--!strict
-- Combate autoritativo: valida cada tiro, reconstrói os alvos com lag compensation,
-- aplica dano por região (partes reais do R6) com queda por distância e armadura,
-- controla munição (pente + reserva), tempo de saque e recarga, e replica o efeito.
-- O cliente só manda a intenção: origem, direção, hora do tiro, arma e número do tiro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local WeaponMath = require(ReplicatedStorage.Shared.Lib.WeaponMath)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local DownedConfig = require(ReplicatedStorage.Shared.Config.Downed)

local Combat = script.Parent.Parent.Combat
local Damage = require(Combat.Damage)
local LagCompensation = require(Combat.LagCompensation)
local Factions = require(Combat.Factions)
local DownedService = require(script.Parent.DownedService)
local ArmorService = require(script.Parent.ArmorService)
local WantedService = require(script.Parent.WantedService)

type FirePayload = CombatContract.FirePayload
type HitResult = CombatContract.HitResult
type ArmorHit = CombatContract.ArmorHit
type WeaponConfig = Weapons.WeaponConfig

local REMOTES = CombatContract.Remotes
local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions

-- Partes do R6 que contam como corpo. Acessório, ferramenta e outras peças não contam:
-- o tiro passa por elas (chapéu não "come" o tiro na cabeça).
local BODY_PARTS: { [string]: boolean } = {
	Head = true,
	Torso = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	HumanoidRootPart = true,
}
local MAX_PASS_THROUGH = 6 -- quantas peças não-corpo um tiro atravessa antes de desistir
local ORIGIN_WALL_MARGIN = 0.1 -- origem recuada da parede quando o cano encosta nela (studs)

local CombatService = {}

local hitRemote: RemoteEvent
local fxRemote: RemoteEvent
local damagedRemote: RemoteEvent
local fireBudget: { [Player]: { tokens: number, last: number } } = {}
local lastSeq: { [Player]: number } = {}
-- chave fraca: a Tool destruída (respawn) sai sozinha da tabela
local equippedAt: { [Tool]: number } = setmetatable({}, { __mode = "k" }) :: any
local reloadToken: { [Tool]: number } = setmetatable({}, { __mode = "k" }) :: any

local function getEquipped(player: Player): (Tool?, string?, WeaponConfig?, Model?)
	local character = player.Character
	if not character then
		return nil, nil, nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil, nil, nil, nil
	end
	local weaponId = tool:GetAttribute(ATTR.Weapon)
	if typeof(weaponId) ~= "string" then
		return nil, nil, nil, nil
	end
	local weapon = Weapons[weaponId]
	if not weapon then
		return nil, nil, nil, nil
	end
	return tool, weaponId, weapon, character
end

-- Raycast do mundo ignorando todos os jogadores (eles são testados com rewind).
-- Peças de NPC que não são corpo (acessórios etc.) são atravessadas.
local function worldRaycast(origin: Vector3, ray: Vector3): RaycastResult?
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	for _ = 1, MAX_PASS_THROUGH do
		local result = workspace:Raycast(origin, ray, params)
		if not result then
			return nil
		end
		local instance = result.Instance
		local model = instance:FindFirstAncestorOfClass("Model")
		local isCharacter = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
		if isCharacter and not (instance.Parent == model and BODY_PARTS[instance.Name]) then
			params:AddToFilter(instance)
		else
			return result
		end
	end
	return nil
end

-- Resultado de um tiro aceito (usado pela ponte da arma legada)
export type ShotReport = {
	tool: Tool,
	weaponId: string,
	origin: Vector3,
	hitPos: Vector3, -- impacto do primeiro projétil
	region: Damage.Region?, -- nil = o primeiro projétil não acertou ninguém que toma dano
	result: HitResult?,
}

-- Aplica dano já com armadura. Retorna o resultado (acertou, derrubou, matou), o acerto
-- na armadura e quanto do dano foi para a armadura e para a vida.
local function applyDamage(
	attacker: Player,
	model: Model,
	humanoid: Humanoid,
	region: Damage.Region,
	rawDamage: number
): (HitResult, ArmorHit, number, number)
	-- Proteção de spawn: ForceField bloqueia o dano todo
	if model:FindFirstChildOfClass("ForceField") then
		return "Hit", "None", 0, 0
	end
	local toHealth, armorHit = ArmorService.absorb(model, region, rawDamage)
	local toArmor = rawDamage - toHealth
	local wasDowned = DownedService.isDowned(model)
	-- Policial machuca pouco o bandido derrubado: o certo é algemar
	if wasDowned and Factions.of(attacker) == FACTIONS.Police then
		local victim = Players:GetPlayerFromCharacter(model)
		if victim and Factions.of(victim) == FACTIONS.Robber then
			toHealth *= DownedConfig.PoliceVsDownedRobberMultiplier
		end
	end
	if toHealth > 0 then
		-- Tiro que zeraria a vida de quem está de pé derruba em vez de matar
		if not wasDowned and toHealth >= humanoid.Health and DownedService.isDownable(model) then
			DownedService.down(model, humanoid, attacker)
			return "Downed", armorHit, toArmor, toHealth
		end
		humanoid:TakeDamage(toHealth)
	end
	if humanoid.Health <= 0 then
		if wasDowned then
			DownedService.finishedByShot(model, attacker)
		end
		return "Killed", armorHit, toArmor, toHealth
	end
	return "Hit", armorHit, toArmor, toHealth
end

-- Avisa a vítima (se for jogador) de onde veio o dano, para o indicador de direção
local function notifyDamaged(model: Model, sourcePos: Vector3, amount: number)
	if amount <= 0 then
		return
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		damagedRemote:FireClient(victim, sourcePos, amount)
	end
end

local function replicateFx(shooter: Player, weaponId: string, origin: Vector3, hitPositions: { Vector3 })
	local radius = CombatConfig.FxRadius
	local last = hitPositions[1]
	for _, other in Players:GetPlayers() do
		if other ~= shooter then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and ((root.Position - origin).Magnitude <= radius or (root.Position - last).Magnitude <= radius) then
				fxRemote:FireClient(other, shooter, weaponId, origin, hitPositions)
			end
		end
	end
end

type Impact = {
	distance: number,
	part: BasePart?,
	model: Model?,
	player: Player?,
}

-- Um projétil: mundo + NPCs agora, jogadores como estavam no tempo do tiro.
-- O mais perto vence, então ninguém leva tiro através de parede.
local function castProjectile(shooter: Player, origin: Vector3, ray: Vector3, rewindTo: number): Impact
	local worldHit = worldRaycast(origin, ray)
	local impact: Impact = {
		distance = if worldHit then (worldHit.Position - origin).Magnitude else ray.Magnitude,
		part = nil,
		model = nil,
		player = nil,
	}
	if worldHit then
		local model = worldHit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			impact.part = worldHit.Instance :: BasePart
			impact.model = model
		end
	end
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other ~= shooter and otherCharacter then
			local part, distance = LagCompensation.raycastCharacter(otherCharacter, rewindTo, origin, ray)
			if part and distance and distance < impact.distance then
				impact.distance = distance
				impact.part = part
				impact.model = otherCharacter
				impact.player = other
			end
		end
	end
	return impact
end

-- Origem do tiro: perto da cabeça (tolerância) e do mesmo lado da parede que a cabeça.
-- Cano encostado na parede não é trapaça: a origem é puxada para antes da parede.
-- A pose (agachado, slide) só existe no cliente: a cabeça de referência é a do servidor
-- com a mesma pose aplicada. Andando, a do servidor fica um pouco atrás: folga pela velocidade.
local function validateOrigin(player: Player, character: Model, head: BasePart, origin: Vector3): Vector3?
	local headPos = LagCompensation.posedCFrame(character, head).Position
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
	local tolerance = CombatConfig.OriginTolerance + speed * CombatConfig.OriginSpeedAllowance
	local fromHead = origin - headPos
	if fromHead.Magnitude > tolerance then
		Net.reportAbuse(player, REMOTES.Fire, "origin_far")
		return nil
	end
	if fromHead.Magnitude <= 0.05 then
		return origin
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local blocked = workspace:Raycast(headPos, fromHead, params)
	if blocked then
		local back = math.max(0, (blocked.Position - headPos).Magnitude - ORIGIN_WALL_MARGIN)
		return headPos + fromHead.Unit * back
	end
	return origin
end

-- Cadência com folga: na média no máximo a da arma (com tolerância), mas aceita
-- FireBurstShots tiros chegando juntos. Devolve false se passou do limite.
local function takeShotToken(player: Player, weapon: WeaponConfig, now: number): boolean
	local bucket = fireBudget[player]
	local capacity = CombatConfig.FireBurstShots
	local refill = weapon.FireInterval * CombatConfig.FireRateTolerance
	if not bucket then
		bucket = { tokens = capacity, last = now }
		fireBudget[player] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.last) / refill)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function processShot(player: Player, payload: FirePayload): ShotReport?
	local tool, weaponId, weapon, character = getEquipped(player)
	if not tool or not weaponId or not weapon or not character then
		Net.reportAbuse(player, REMOTES.Fire, "no_weapon")
		return nil
	end
	-- Cada tiro tem um número crescente: repetido ou fora de ordem nunca conta de novo
	local previousSeq = lastSeq[player]
	if previousSeq and payload.seq <= previousSeq then
		Net.reportAbuse(player, REMOTES.Fire, "duplicate_seq")
		return nil
	end
	lastSeq[player] = payload.seq
	if payload.weaponId ~= weaponId then
		-- Troca de arma com tiro ainda a caminho: não é abuso, só ignora
		return nil
	end
	if Factions.of(player) == FACTIONS.Civil then
		Net.reportAbuse(player, REMOTES.Fire, "civil_shot")
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head") :: BasePart?
	-- Pacote atrasado de quem acabou de morrer/cair não é abuso: só ignora
	if not humanoid or humanoid.Health <= 0 or not head then
		return nil
	end
	if
		character:GetAttribute(ATTR.Downed) == true
		or character:GetAttribute(ATTR.Plating) == true
		or tool:GetAttribute(ATTR.Reloading) == true
	then
		return nil
	end

	local now = os.clock()
	-- Ainda sacando a arma (o cliente espera o mesmo tempo; a folga cobre o jitter)
	local drawnAt = equippedAt[tool]
	if drawnAt and now - drawnAt < weapon.EquipTime * CombatConfig.FireRateTolerance then
		return nil
	end
	local ammo = tool:GetAttribute(ATTR.Ammo)
	if typeof(ammo) ~= "number" or ammo <= 0 then
		return nil
	end

	local origin = validateOrigin(player, character, head, payload.origin)
	if not origin then
		return nil
	end
	if not takeShotToken(player, weapon, now) then
		Net.reportAbuse(player, REMOTES.Fire, "fire_rate")
		return nil
	end

	tool:SetAttribute(ATTR.Ammo, ammo - 1)
	-- disparo em via pública (o WantedService decide se conta)
	WantedService.onShotFired(player, origin)

	local rewindTo = LagCompensation.rewindTime(payload.timestamp)
	local directions = WeaponMath.pelletDirections(payload.direction, weapon.Pellets, weapon.PelletSpread)
	local hitPositions: { Vector3 } = {}
	-- Quem já caiu ou morreu com um chumbo não conta de novo com os outros do mesmo tiro
	local settled: { [Model]: boolean } = {}
	local report: ShotReport = { tool = tool, weaponId = weaponId, origin = origin, hitPos = origin }

	for index, direction in directions do
		local impact = castProjectile(player, origin, direction * weapon.Range, rewindTo)
		local hitPos = origin + direction * impact.distance
		table.insert(hitPositions, hitPos)
		if index == 1 then
			report.hitPos = hitPos
		end
		local model, part = impact.model, impact.part
		if model and part and not settled[model] then
			local victimHumanoid = model:FindFirstChildOfClass("Humanoid")
			if victimHumanoid and victimHumanoid.Health > 0 and Factions.canDamage(player, impact.player) then
				local region = Damage.regionOf(part.Name)
				local raw = Damage.compute(weapon, region, impact.distance)
				local result, armorHit, toArmor, toHealth = applyDamage(player, model, victimHumanoid, region, raw)
				notifyDamaged(model, origin, toArmor + toHealth)
				hitRemote:FireClient(player, region, result, armorHit, toArmor, toHealth, hitPos)
				WantedService.onHit(player, model, impact.player, toHealth, result, hitPos)
				if result ~= "Hit" then
					settled[model] = true
				end
				if index == 1 then
					report.region = region
					report.result = result
				end
				if CombatConfig.DebugShotLog then
					print(("[Shot] %s #%d -> %s %s(%s) %.1f dmg (armor %.1f, health %.1f) @ %.0f studs %s"):format(
						player.Name, payload.seq, model.Name, region, part.Name, raw, toArmor, toHealth, impact.distance, result))
				end
			end
		end
	end

	replicateFx(player, weaponId, origin, hitPositions)
	return report
end

local function onFire(player: Player, payload: FirePayload)
	debug.profilebegin("Combat_ShotValidation")
	processShot(player, payload)
	debug.profileend()
end

-- Tiro vindo de outra entrada do servidor (ponte da arma legada). Passa pelas mesmas
-- validações do remote CombatFire, menos o rate limit bruto do Net.
function CombatService.fire(player: Player, payload: FirePayload): ShotReport?
	local ok, reason = CombatContract.validateFire(payload)
	if not ok then
		Net.reportAbuse(player, REMOTES.Fire, reason or "invalid_args")
		return nil
	end
	debug.profilebegin("Combat_ShotValidation")
	local report = processShot(player, payload)
	debug.profileend()
	return report
end

-- Próximo número de tiro válido para quem atira por outra entrada do servidor (ponte legada)
function CombatService.nextSeq(player: Player): number
	return (lastSeq[player] or 0) + 1
end

local function cancelReload(tool: Tool)
	reloadToken[tool] = (reloadToken[tool] or 0) + 1
	if tool:GetAttribute(ATTR.Reloading) == true then
		tool:SetAttribute(ATTR.Reloading, false)
	end
end

local function onReload(player: Player)
	local tool, _, weapon = getEquipped(player)
	if not tool or not weapon then
		return
	end
	if tool:GetAttribute(ATTR.Reloading) == true then
		return
	end
	local ammo = tool:GetAttribute(ATTR.Ammo)
	if typeof(ammo) ~= "number" or ammo >= weapon.MagazineSize then
		return
	end
	local reserve = tool:GetAttribute(ATTR.Reserve)
	if typeof(reserve) == "number" and reserve <= 0 then
		return
	end
	local token = (reloadToken[tool] or 0) + 1
	reloadToken[tool] = token
	tool:SetAttribute(ATTR.Reloading, true)
	task.delay(weapon.ReloadTime, function()
		-- Guardou/trocou a arma no meio: a recarga já foi cancelada
		if reloadToken[tool] ~= token or tool.Parent ~= player.Character then
			return
		end
		tool:SetAttribute(ATTR.Reloading, false)
		local current = tool:GetAttribute(ATTR.Ammo)
		local inMag = if typeof(current) == "number" then current else 0
		local need = weapon.MagazineSize - inMag
		local left = tool:GetAttribute(ATTR.Reserve)
		if typeof(left) == "number" then
			local take = math.clamp(need, 0, left)
			tool:SetAttribute(ATTR.Ammo, inMag + take)
			tool:SetAttribute(ATTR.Reserve, left - take)
		else
			-- Arma sem reserva (legado): recarga infinita
			tool:SetAttribute(ATTR.Ammo, weapon.MagazineSize)
		end
	end)
end

-- Recarga vinda de outra entrada do servidor (ponte da arma legada)
function CombatService.reload(player: Player)
	onReload(player)
end

-- Dano de outras fontes (explosão etc.) com as mesmas regras do tiro: armadura,
-- derrubado e kill feed. Quem causou recebe o CombatHit (números de dano e sons),
-- menos quando acertou a si mesmo. Quem pode atacar quem fica com quem chama.
function CombatService.applyDamage(
	attacker: Player,
	model: Model,
	humanoid: Humanoid,
	region: Damage.Region,
	amount: number,
	hitPos: Vector3,
	sourcePos: Vector3 -- de onde veio o dano (indicador de direção da vítima)
): HitResult?
	if amount <= 0 or humanoid.Health <= 0 then
		return nil
	end
	local result, armorHit, toArmor, toHealth = applyDamage(attacker, model, humanoid, region, amount)
	notifyDamaged(model, sourcePos, toArmor + toHealth)
	if attacker.Character ~= model then
		hitRemote:FireClient(attacker, region, result, armorHit, toArmor, toHealth, hitPos)
		WantedService.onHit(attacker, model, Players:GetPlayerFromCharacter(model), toHealth, result, hitPos)
	end
	return result
end

-- Saque: a arma só atira depois do EquipTime. Guardar cancela a recarga.
local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and typeof(child:GetAttribute(ATTR.Weapon)) == "string" then
			equippedAt[child] = os.clock()
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and equippedAt[child] then
			equippedAt[child] = nil
			cancelReload(child)
		end
	end)
end

function CombatService:Init()
	hitRemote = Net.serverEvent(REMOTES.Hit)
	fxRemote = Net.serverEvent(REMOTES.FX)
	damagedRemote = Net.serverEvent(REMOTES.Damaged)
end

function CombatService:Start()
	LagCompensation.start()
	Net.listen(REMOTES.Fire, CombatContract.validateFire, onFire, CombatConfig.FireRemoteMinInterval)
	Net.listen(REMOTES.Reload, Net.noArgs, onReload, CombatConfig.ReloadRemoteMinInterval)
	local function onPlayer(player: Player)
		if player.Character then
			watchCharacter(player.Character)
		end
		player.CharacterAdded:Connect(watchCharacter)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		fireBudget[player] = nil
		lastSeq[player] = nil
	end)
end

return CombatService
