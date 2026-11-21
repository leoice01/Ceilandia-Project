--!strict
-- Combate autoritativo: valida cada tiro, reconstrói os alvos com lag compensation,
-- aplica dano por região com queda por distância e armadura, e replica o efeito.
-- Convive com o GunServer legado: ele usa ReplicatedStorage.Remotes, este usa
-- ReplicatedStorage.Net. Quando o cliente novo (P1) estiver pronto, o legado sai.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)

local Combat = script.Parent.Parent.Combat
local Damage = require(Combat.Damage)
local LagCompensation = require(Combat.LagCompensation)

type FirePayload = CombatContract.FirePayload

local REMOTES = CombatContract.Remotes
local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions

local CombatService = {}

local hitRemote: RemoteEvent
local fxRemote: RemoteEvent
local lastShot: { [Player]: number } = {}

local function getEquipped(player: Player): (Tool?, string?, Weapons.WeaponConfig?, Model?)
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

local function factionOf(player: Player): string
	local faction = player:GetAttribute(ATTR.Faction)
	return if typeof(faction) == "string" then faction else CombatContract.DefaultFaction
end

-- Civil não toma tiro; policial não acerta policial; bandido acerta bandido.
-- victim nil = NPC/dummy.
local function canDamage(attacker: Player, victim: Player?): boolean
	if not victim then
		return true
	end
	if victim == attacker then
		return false
	end
	local victimFaction = factionOf(victim)
	if victimFaction == FACTIONS.Civil then
		return false
	end
	if factionOf(attacker) == FACTIONS.Police and victimFaction == FACTIONS.Police then
		return false
	end
	return true
end

-- Raycast do mundo ignorando o atirador e todos os jogadores (que são testados com rewind)
local function worldRaycastParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return params
end

-- Aplica dano já com armadura. Retorna se morreu (ou caiu) e se acertou armadura.
local function applyDamage(model: Model, humanoid: Humanoid, region: Damage.Region, rawDamage: number): (boolean, boolean)
	local armorAttr = if region == "Head" then ATTR.Helmet elseif region == "Torso" then ATTR.Vest else nil
	local toHealth = rawDamage
	local armorHit = false
	if armorAttr then
		local armor = model:GetAttribute(armorAttr)
		if typeof(armor) == "number" and armor > 0 then
			local remaining, leftover = Damage.absorb(armor, rawDamage)
			model:SetAttribute(armorAttr, remaining)
			toHealth = leftover
			armorHit = true
		end
	end
	if toHealth > 0 then
		-- TODO(derrubado): quando o DownedService existir, vida 0 vira derrubado em vez de morte
		humanoid:TakeDamage(toHealth)
	end
	return humanoid.Health <= 0, armorHit
end

local function replicateFx(shooter: Player, weaponId: string, origin: Vector3, hitPos: Vector3)
	local radius = CombatConfig.FxRadius
	for _, other in Players:GetPlayers() do
		if other ~= shooter then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and ((root.Position - origin).Magnitude <= radius or (root.Position - hitPos).Magnitude <= radius) then
				fxRemote:FireClient(other, shooter, weaponId, origin, hitPos)
			end
		end
	end
end

local function processShot(player: Player, payload: FirePayload)
	local tool, weaponId, weapon, character = getEquipped(player)
	if not tool or not weaponId or not weapon or not character then
		Net.reportAbuse(player, REMOTES.Fire, "no_weapon")
		return
	end
	if payload.weaponId ~= weaponId then
		Net.reportAbuse(player, REMOTES.Fire, "weapon_mismatch")
		return
	end
	if factionOf(player) == FACTIONS.Civil then
		Net.reportAbuse(player, REMOTES.Fire, "civil_shot")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head") :: BasePart?
	-- Pacote atrasado de quem acabou de morrer/cair não é abuso: só ignora
	if not humanoid or humanoid.Health <= 0 or not head then
		return
	end
	if character:GetAttribute(ATTR.Downed) == true or tool:GetAttribute(ATTR.Reloading) == true then
		return
	end

	local now = os.clock()
	if now - (lastShot[player] or 0) < weapon.FireRate * CombatConfig.FireRateTolerance then
		Net.reportAbuse(player, REMOTES.Fire, "fire_rate")
		return
	end
	local ammo = tool:GetAttribute(ATTR.Ammo)
	if typeof(ammo) ~= "number" or ammo <= 0 then
		return
	end

	-- A origem precisa estar perto da cabeça e sem parede entre as duas
	local origin = payload.origin
	local fromHead = origin - head.Position
	if fromHead.Magnitude > CombatConfig.OriginTolerance then
		Net.reportAbuse(player, REMOTES.Fire, "origin_far")
		return
	end
	local selfParams = RaycastParams.new()
	selfParams.FilterType = Enum.RaycastFilterType.Exclude
	selfParams.FilterDescendantsInstances = { character }
	if fromHead.Magnitude > 0.05 and workspace:Raycast(head.Position, fromHead, selfParams) then
		Net.reportAbuse(player, REMOTES.Fire, "origin_through_wall")
		return
	end

	lastShot[player] = now
	tool:SetAttribute(ATTR.Ammo, ammo - 1)

	local ray = payload.direction.Unit * weapon.Range
	local rewindTo = LagCompensation.rewindTime(payload.timestamp)

	-- 1) mundo + NPCs (sem atraso de rede)
	local worldHit = workspace:Raycast(origin, ray, worldRaycastParams())
	local bestDistance = if worldHit then (worldHit.Position - origin).Magnitude else weapon.Range
	local hitPart: BasePart? = nil
	local hitModel: Model? = nil
	local hitPlayer: Player? = nil
	if worldHit then
		local model = worldHit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			hitPart = worldHit.Instance :: BasePart
			hitModel = model
		end
	end

	-- 2) jogadores como estavam no tempo do tiro; só valem se vierem antes da parede
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other ~= player and otherCharacter then
			local part, distance = LagCompensation.raycastCharacter(otherCharacter, rewindTo, origin, ray)
			if part and distance and distance < bestDistance then
				bestDistance = distance
				hitPart = part
				hitModel = otherCharacter
				hitPlayer = other
			end
		end
	end

	local hitPos = origin + payload.direction.Unit * bestDistance

	if hitPart and hitModel then
		local victimHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
		if victimHumanoid and victimHumanoid.Health > 0 and canDamage(player, hitPlayer) then
			local region = Damage.regionOf(hitPart.Name)
			local raw = Damage.compute(weapon, region, bestDistance)
			local lethal, armorHit = applyDamage(hitModel, victimHumanoid, region, raw)
			hitRemote:FireClient(player, region, lethal, armorHit)
			if CombatConfig.DebugShotLog then
				print(("[Shot] %s -> %s %s %.1f dmg @ %.0f studs lethal=%s"):format(
					player.Name, hitModel.Name, region, raw, bestDistance, tostring(lethal)))
			end
		end
	end

	replicateFx(player, weaponId, origin, hitPos)
end

local function onFire(player: Player, payload: FirePayload)
	debug.profilebegin("Combat_ShotValidation")
	processShot(player, payload)
	debug.profileend()
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
	if typeof(ammo) ~= "number" or ammo >= weapon.MagSize then
		return
	end
	tool:SetAttribute(ATTR.Reloading, true)
	task.delay(weapon.ReloadTime, function()
		if not tool.Parent then
			return
		end
		tool:SetAttribute(ATTR.Reloading, false)
		-- Trocar de arma no meio cancela a recarga
		if tool.Parent == player.Character then
			tool:SetAttribute(ATTR.Ammo, weapon.MagSize)
		end
	end)
end

function CombatService:Init()
	hitRemote = Net.serverEvent(REMOTES.Hit)
	fxRemote = Net.serverEvent(REMOTES.FX)
end

function CombatService:Start()
	LagCompensation.start()
	Net.listen(REMOTES.Fire, CombatContract.validateFire, onFire, CombatConfig.FireRemoteMinInterval)
	Net.listen(REMOTES.Reload, Net.noArgs, onReload, CombatConfig.ReloadRemoteMinInterval)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastShot[player] = nil
	end)
end

return CombatService
