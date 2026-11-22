--!strict
-- Armas de fogo no cliente: entrada, modos de disparo (automático/semiautomático),
-- cadência, quadril/mira (ADS), dispersão, munição prevista, saque/guardar, recuo e HUD.
-- Substitui o GunClient legado. Fala com o CombatService pelo CombatFire; o servidor
-- decide se acertou, onde e quanto. Aqui só há previsão e feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared.Lib:WaitForChild("CombatContract"))
local WeaponMath = require(Shared.Lib:WaitForChild("WeaponMath"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))
local CombatConfig = require(Shared.Config:WaitForChild("Combat"))

local WeaponModules = script.Parent.Parent:WaitForChild("Weapons")
local Aim = require(WeaponModules:WaitForChild("Aim"))
local Recoil = require(WeaponModules:WaitForChild("Recoil"))
local WeaponHud = require(WeaponModules:WaitForChild("WeaponHud"))
local WeaponEffects = require(WeaponModules:WaitForChild("WeaponEffects"))

type WeaponConfig = Weapons.WeaponConfig

local ATTR = CombatContract.Attributes
-- atributos locais (só o dono escreve; a pose local lê)
local LOCAL_ATTR = {
	Aiming = "Aiming",
	Firing = "Firing",
	Equipping = "Equipping",
	Holstering = "Holstering",
	RecoilKick = "RecoilKick",
}
local RELOAD_REQUEST_COOLDOWN = 0.5 -- s entre pedidos automáticos de recarga
local AMMO_RESYNC_AFTER = 0.6 -- s sem atirar: munição prevista volta a ser a do servidor
local KICK_ATTR_EPSILON = 0.005

local WeaponController = {}

local player = Players.LocalPlayer
local rng = Random.new()
local fireRemote: RemoteEvent
local reloadRemote: RemoteEvent

local character: Model? = nil
local humanoid: Humanoid? = nil
local tool: Tool? = nil
local weapon: WeaponConfig? = nil
local toolConnections: { RBXScriptConnection } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local triggerHeld = false
local semiQueuedAt: number? = nil
local aiming = false
local holstering = false
local lastFire = -math.huge
local seq = 0
local shotIndex = 0
local bloom = 0
local predictedAmmo = 0
local lastAmmoAttr = 0
local readyAt = 0
local lastReloadRequest = -math.huge
local firingToken = 0
local equipToken = 0
local fovTween: Tween? = nil
local lastKickAttr = 0

local function refreshRayParams()
	local ignore: { Instance } = { WeaponEffects.folder() }
	if character then
		table.insert(ignore, character)
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function attrNumber(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end


local function setLocal(name: string, value: any)
	local c = character
	if c and c:GetAttribute(name) ~= value then
		c:SetAttribute(name, value)
	end
end

-- ---------- estado ----------
local function cannotFire(): boolean
	local t, c, h = tool, character, humanoid
	if not t or not weapon or not c or not h then
		return true
	end
	return h.Health <= 0
		or holstering
		or os.clock() < readyAt
		or c:GetAttribute(ATTR.Downed) == true
		or c:GetAttribute(ATTR.Plating) == true
		or t:GetAttribute(ATTR.Reloading) == true
end

local function currentCone(w: WeaponConfig): number
	local h, c = humanoid, character
	return WeaponMath.currentSpread(w.Spread, w.HipFireAccuracy, w.ADSAccuracy, {
		aiming = aiming,
		moving = h ~= nil and h.MoveDirection.Magnitude > 0.1,
		airborne = h ~= nil and h.FloorMaterial == Enum.Material.Air,
		crouching = c ~= nil and c:GetAttribute("Crouching") == true,
		bloom = bloom,
	})
end

local function updateAmmoHud()
	local t, w = tool, weapon
	if not t or not w then
		return
	end
	WeaponHud.setAmmo(w.DisplayName, math.max(predictedAmmo, 0), attrNumber(t, ATTR.Reserve), t:GetAttribute(ATTR.Reloading) == true)
end

local function requestReload()
	local t, w = tool, weapon
	if not t or not w or holstering or t:GetAttribute(ATTR.Reloading) == true then
		return
	end
	local reserve = attrNumber(t, ATTR.Reserve)
	if predictedAmmo >= w.MagazineSize or (reserve and reserve <= 0) then
		return
	end
	local now = os.clock()
	if now - lastReloadRequest < RELOAD_REQUEST_COOLDOWN then
		return
	end
	lastReloadRequest = now
	reloadRemote:FireServer()
end

local function holdFiringPose()
	firingToken += 1
	setLocal(LOCAL_ATTR.Firing, true)
end

local function releaseFiringPose()
	firingToken += 1
	local token = firingToken
	task.delay(CombatConfig.FiringPoseHold, function()
		if token == firingToken then
			setLocal(LOCAL_ATTR.Firing, false)
		end
	end)
end

-- ---------- disparo ----------
local function fire()
	local t, w, c = tool, weapon, character
	if not t or not w or not c then
		return
	end
	if predictedAmmo <= 0 then
		requestReload()
		return
	end
	local head = c:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local now = os.clock()
	-- rajada nova: o padrão de recuo recomeça
	if now - lastFire > w.FireInterval + w.Recoil.RecoveryDelay then
		shotIndex = 0
	end
	shotIndex += 1
	-- rajada contínua: guarda o que sobrou do intervalo, senão o tiro fica preso ao quadro
	-- (a 60 FPS, 660 RPM viraria 600)
	-- (nunca dois tiros a menos de meio intervalo: depois de um travamento não sai rajada)
	lastFire = if now - lastFire < w.FireInterval * 2 then math.max(lastFire + w.FireInterval, now - w.FireInterval * 0.5) else now
	seq += 1

	-- 1) ponto pretendido (mira + dispersão)
	local camera = workspace.CurrentCamera
	local screen = Aim.screenPoint(camera)
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local aimDir = WeaponMath.coneDirection(ray.Direction, currentCone(w), rng:NextNumber(), rng:NextNumber())
	local intended = Aim.intendedPoint(ray.Origin, aimDir, head.Position, w.Range, rayParams)
	-- 2) do cano até o ponto pretendido, sem atravessar parede
	local muzzle = WeaponEffects.muzzle(t)
	local muzzlePos = if muzzle then muzzle.WorldPosition else head.Position
	local origin = Aim.origin(head.Position, muzzlePos, CombatConfig.OriginTolerance - CombatConfig.OriginClientMargin, rayParams)
	local direction = Aim.direction(origin, intended, aimDir)

	fireRemote:FireServer({
		origin = origin,
		direction = direction,
		timestamp = workspace:GetServerTimeNow(),
		weaponId = w.WeaponId,
		seq = seq,
	})

	-- previsão local: munição, dispersão, efeitos e recuo na hora
	predictedAmmo -= 1
	bloom = math.min(bloom + w.Spread.PerShot, w.Spread.Max)
	for _, pellet in WeaponMath.pelletDirections(direction, w.Pellets, w.PelletSpread) do
		local hitPos = Aim.trace(origin, pellet, w.Range, nil, rayParams)
		WeaponEffects.tracer(muzzlePos, hitPos)
	end
	WeaponEffects.shot(t, w.WeaponType)
	Recoil.kick(shotIndex, aiming)
	updateAmmoHud()
	if predictedAmmo <= 0 then
		requestReload()
	end
end

-- ---------- mira (ADS) ----------
local function setFov(fov: number, duration: number)
	if fovTween then
		fovTween:Cancel()
	end
	local tween = TweenService:Create(workspace.CurrentCamera, TweenInfo.new(duration, Enum.EasingStyle.Quad), { FieldOfView = fov })
	fovTween = tween
	tween:Play()
end

local function setAiming(on: boolean)
	local w = weapon
	if on and not w then
		return
	end
	if aiming == on then
		return
	end
	aiming = on
	setLocal(LOCAL_ATTR.Aiming, on)
	local duration = if w then w.AdsTime else 0.15
	setFov(if on and w then w.AdsFov else CombatConfig.DefaultFov, duration)
end

-- ---------- ações ----------
local function onAimAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.Touch then
		-- no celular o botão alterna
		if state == Enum.UserInputState.Begin then
			setAiming(not aiming)
		end
		return Enum.ContextActionResult.Sink
	end
	if state == Enum.UserInputState.Begin then
		setAiming(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setAiming(false)
	end
	return Enum.ContextActionResult.Pass
end

local function onReloadAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		lastReloadRequest = -math.huge -- pedido do jogador não espera o cooldown automático
		requestReload()
	end
	return Enum.ContextActionResult.Sink
end

-- Guarda a arma com a animação (a pose "Holster" toca e depois a Tool sai da mão).
-- Devolve false se não tem arma de fogo na mão.
local function holster(): boolean
	if not tool then
		return false
	end
	if holstering then
		return true
	end
	holstering = true
	setAiming(false)
	setLocal(LOCAL_ATTR.Holstering, true)
	local token = equipToken
	task.delay(CombatConfig.HolsterTime, function()
		local h = humanoid
		if token == equipToken and h then
			h:UnequipTools()
		end
	end)
	return true
end

local function onHolsterAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not tool then
		return Enum.ContextActionResult.Pass
	end
	holster()
	return Enum.ContextActionResult.Sink
end

-- Para a barra de atalhos: guardar a arma de fogo na mão com animação
function WeaponController.holster(): boolean
	return holster()
end

-- ---------- equipar / guardar ----------
local function unequip()
	equipToken += 1
	setAiming(false)
	tool, weapon = nil, nil
	triggerHeld, semiQueuedAt, holstering = false, nil, false
	for _, connection in toolConnections do
		connection:Disconnect()
	end
	table.clear(toolConnections)
	Recoil.setWeapon(nil)
	firingToken += 1
	setLocal(LOCAL_ATTR.Firing, false)
	setLocal(LOCAL_ATTR.Equipping, false)
	setLocal(LOCAL_ATTR.Holstering, false)
	setLocal(LOCAL_ATTR.RecoilKick, 0)
	lastKickAttr = 0
	ContextActionService:UnbindAction("WeaponReload")
	ContextActionService:UnbindAction("WeaponAim")
	ContextActionService:UnbindAction("WeaponHolster")
	WeaponHud.setVisible(false)
	WeaponHud.setBlocked(nil)
	UserInputService.MouseIconEnabled = true
end

local function onAmmoChanged()
	local t = tool
	if not t then
		return
	end
	local ammo = attrNumber(t, ATTR.Ammo) or 0
	if ammo > lastAmmoAttr then
		predictedAmmo = ammo -- recarregou
	else
		predictedAmmo = math.min(predictedAmmo, ammo)
	end
	lastAmmoAttr = ammo
	updateAmmoHud()
end

local function equip(newTool: Tool)
	local weaponId = newTool:GetAttribute(ATTR.Weapon)
	local w = if typeof(weaponId) == "string" then Weapons[weaponId] else nil
	if not w then
		return
	end
	unequip()
	tool, weapon = newTool, w
	local token = equipToken
	readyAt = os.clock() + w.EquipTime
	shotIndex, bloom = 0, 0
	lastAmmoAttr = attrNumber(newTool, ATTR.Ammo) or 0
	predictedAmmo = lastAmmoAttr

	-- animação de sacar: a pose local lê "Equipping"
	setLocal(LOCAL_ATTR.Equipping, true)
	task.delay(w.EquipTime, function()
		if token == equipToken then
			setLocal(LOCAL_ATTR.Equipping, false)
		end
	end)

	table.insert(toolConnections, newTool.Activated:Connect(function()
		triggerHeld = true
		if w.FireMode == "Semi" then
			semiQueuedAt = os.clock()
		end
		holdFiringPose()
	end))
	table.insert(toolConnections, newTool.Deactivated:Connect(function()
		triggerHeld = false
		releaseFiringPose()
	end))
	table.insert(toolConnections, newTool:GetAttributeChangedSignal(ATTR.Ammo):Connect(onAmmoChanged))
	table.insert(toolConnections, newTool:GetAttributeChangedSignal(ATTR.Reserve):Connect(updateAmmoHud))
	table.insert(toolConnections, newTool:GetAttributeChangedSignal(ATTR.Reloading):Connect(updateAmmoHud))

	Recoil.setWeapon(w.Recoil)
	ContextActionService:BindAction("WeaponReload", onReloadAction, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("WeaponReload", "R")
	ContextActionService:BindAction("WeaponAim", onAimAction, true, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:SetTitle("WeaponAim", "Mirar")
	ContextActionService:BindAction("WeaponHolster", onHolsterAction, false, Enum.KeyCode.H, Enum.KeyCode.DPadDown)
	WeaponHud.setVisible(true)
	UserInputService.MouseIconEnabled = false
	updateAmmoHud()
end

-- ---------- quadro a quadro ----------
local function onRender(dt: number)
	local t, w, c = tool, weapon, character
	if not t or not w or not c then
		return
	end
	local now = os.clock()
	bloom = math.max(0, bloom - w.Spread.Recovery * dt)

	-- munição prevista volta a ser a do servidor quando não há tiro a caminho
	if now - lastFire > AMMO_RESYNC_AFTER then
		local real = attrNumber(t, ATTR.Ammo) or 0
		if real ~= predictedAmmo then
			predictedAmmo = real
			lastAmmoAttr = real
			updateAmmoHud()
		end
	end

	local ready = not cannotFire() and now - lastFire >= w.FireInterval
	if w.FireMode == "Auto" then
		if triggerHeld and ready then
			fire()
		end
	elseif semiQueuedAt then
		if now - semiQueuedAt > CombatConfig.SemiFireBuffer then
			semiQueuedAt = nil
		elseif ready then
			semiQueuedAt = nil
			fire()
		end
	end

	-- mira: abre com a dispersão real; X vermelho se o cano não vê o ponto da mira
	local camera = workspace.CurrentCamera
	local screen = Aim.screenPoint(camera)
	local halfFov = math.rad(camera.FieldOfView) * 0.5
	local gap = math.tan(math.rad(currentCone(w)) * 0.5) / math.tan(halfFov) * camera.ViewportSize.Y * 0.5
	WeaponHud.updateCrosshair(screen, gap)

	local head = c:FindFirstChild("Head") :: BasePart?
	if head then
		local ray = camera:ViewportPointToRay(screen.X, screen.Y)
		local intended = Aim.intendedPoint(ray.Origin, ray.Direction, head.Position, w.Range, rayParams)
		local muzzle = WeaponEffects.muzzle(t)
		local muzzlePos = if muzzle then muzzle.WorldPosition else head.Position
		local origin = Aim.origin(head.Position, muzzlePos, CombatConfig.OriginTolerance - CombatConfig.OriginClientMargin, rayParams)
		local direction = Aim.direction(origin, intended, ray.Direction)
		local hitPos, _, blocked = Aim.trace(origin, direction, w.Range, intended, rayParams)
		if blocked then
			local point, onScreen = camera:WorldToViewportPoint(hitPos)
			WeaponHud.setBlocked(if onScreen then Vector2.new(point.X, point.Y) else nil)
		else
			WeaponHud.setBlocked(nil)
		end
	end

	-- coice visual da arma para a pose local
	local kick = Recoil.gunKick() * w.Recoil.GunKick
	if math.abs(kick - lastKickAttr) > KICK_ATTR_EPSILON or (kick == 0 and lastKickAttr ~= 0) then
		lastKickAttr = if kick < KICK_ATTR_EPSILON then 0 else kick
		setLocal(LOCAL_ATTR.RecoilKick, lastKickAttr)
	end
end

-- ---------- rede ----------
local function onHit(region: unknown, result: unknown)
	if weapon then
		WeaponHud.showHit(region == "Head", result == "Downed" or result == "Killed")
	end
end

-- Tiro de outro jogador por perto: som, clarão e rastro (um por chumbo)
local function onOtherShot(shooter: unknown, weaponId: unknown, origin: unknown, hitPositions: unknown)
	if typeof(shooter) ~= "Instance" or not (shooter :: Instance):IsA("Player") or shooter == player then
		return
	end
	if typeof(origin) ~= "Vector3" or type(hitPositions) ~= "table" then
		return
	end
	local w = if typeof(weaponId) == "string" then Weapons[weaponId] else nil
	local shooterCharacter = (shooter :: Player).Character
	local shooterTool = shooterCharacter and shooterCharacter:FindFirstChildOfClass("Tool")
	local from = origin :: Vector3
	if shooterTool then
		local muzzle = WeaponEffects.muzzle(shooterTool)
		if muzzle then
			from = muzzle.WorldPosition
		end
		WeaponEffects.shot(shooterTool, if w then w.WeaponType else "AssaultRifle")
	end
	for _, hitPos in hitPositions :: { any } do
		if typeof(hitPos) == "Vector3" then
			WeaponEffects.tracer(from, hitPos)
		end
	end
end

local function onCharacter(newCharacter: Model)
	unequip()
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	refreshRayParams()
	newCharacter.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and character == newCharacter then
			equip(child)
		end
	end)
	newCharacter.ChildRemoved:Connect(function(child: Instance)
		if child == tool then
			unequip()
		end
	end)
	local h = humanoid
	if h then
		h.Died:Connect(unequip)
	end
	local current = newCharacter:FindFirstChildOfClass("Tool")
	if current then
		equip(current)
	end
end

function WeaponController:Init()
	fireRemote = Net.clientEvent(CombatContract.Remotes.Fire)
	reloadRemote = Net.clientEvent(CombatContract.Remotes.Reload)
	WeaponHud.create()
end

function WeaponController:Start()
	workspace.CurrentCamera.FieldOfView = CombatConfig.DefaultFov
	Net.clientEvent(CombatContract.Remotes.Hit).OnClientEvent:Connect(onHit)
	Net.clientEvent(CombatContract.Remotes.FX).OnClientEvent:Connect(onOtherShot)
	RunService.RenderStepped:Connect(onRender)
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		unequip()
		character, humanoid = nil, nil
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return WeaponController
