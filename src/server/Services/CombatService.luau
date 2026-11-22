--!strict
-- Combate autoritativo: valida cada tiro, reconstrói os alvos com lag compensation,
-- aplica dano por região com queda por distância e armadura, controla munição,
-- cadência, saque e recarga, e replica o efeito.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local RateLimit = require(ReplicatedStorage.Shared.Lib.RateLimit)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local WeaponMath = require(ReplicatedStorage.Shared.Lib.WeaponMath)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local DownedConfig = require(ReplicatedStorage.Shared.Config.Downed)

local Combat = script.Parent.Parent.Combat
local Damage = require(Combat.Damage)
local LagCompensation = require(Combat.LagCompensation)
local HitDetection = require(Combat.HitDetection)
local LegacyGuard = require(Combat.LegacyGuard)
local Factions = require(Combat.Factions)
local Reload = require(Combat.Reload)
local WeaponState = require(Combat.WeaponState)
local DownedService = require(script.Parent.DownedService)
local ArmorService = require(script.Parent.ArmorService)
local KillFeedService = require(script.Parent.KillFeedService)
local FactionService = require(script.Parent.FactionService)
local WantedService = require(script.Parent.WantedService)

type FirePayload = CombatContract.FirePayload
type HitResult = CombatContract.HitResult
type ArmorHit = CombatContract.ArmorHit

local REMOTES = CombatContract.Remotes
local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions

export type ShotReport = {
	tool: Tool,
	weaponId: string,
	origin: Vector3,
	hitPos: Vector3,
	region: Damage.Region?,
	result: HitResult?,
	worldGeometryDistance: number?,
}

local CombatService = {}

local hitRemote: RemoteEvent
local fxRemote: RemoteEvent
local damagedRemote: RemoteEvent
local fireRateLimiters: { [string]: RateLimit.RateLimiter } = {}
local lastCombat: { [Player]: number } = {}
local lastSeq: { [Player]: number } = {}

local function getFireRateLimiter(weaponId: string, fireInterval: number): RateLimit.RateLimiter
	local limiter = fireRateLimiters[weaponId]
	if not limiter then
		limiter = RateLimit.new(1 / fireInterval, CombatConfig.FireBurstShots)
		fireRateLimiters[weaponId] = limiter
	end
	return limiter
end

local function applyDamage(
	attacker: Player, model: Model, humanoid: Humanoid, region: Damage.Region,
	rawDamage: number, weaponName: string?, distance: number?, sourcePos: Vector3?
): (HitResult, ArmorHit, number, number)
	local now = os.clock()
	lastCombat[attacker] = now
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer then lastCombat[victimPlayer] = now end
	if model:FindFirstChildOfClass("ForceField") then return "Hit", "None", 0, 0 end

	local toHealth, armorHit = ArmorService.absorb(model, region, rawDamage)
	local toArmor = rawDamage - toHealth
	if victimPlayer and (toArmor + toHealth) > 0 then
		pcall(FactionService.markCombat, victimPlayer)
		pcall(FactionService.cancelTransition, victimPlayer, "damaged")
		if sourcePos then damagedRemote:FireClient(victimPlayer, sourcePos, toArmor + toHealth) end
	end

	local wasDowned = DownedService.isDowned(model)
	if wasDowned and Factions.of(attacker) == FACTIONS.Police and victimPlayer and Factions.of(victimPlayer) == FACTIONS.Robber then
		toHealth *= DownedConfig.PoliceVsDownedRobberMultiplier
	end
	if toHealth > 0 then
		if not wasDowned and toHealth >= humanoid.Health and DownedService.isDownable(model) then
			pcall(KillFeedService.noteLethalHit, KillFeedService, model, attacker, weaponName, distance, region == "Head", true)
			DownedService.down(model, humanoid, attacker)
			return "Downed", armorHit, toArmor, toHealth
		end
		if toHealth >= humanoid.Health then
			pcall(KillFeedService.noteLethalHit, KillFeedService, model, attacker, weaponName, distance, region == "Head", false)
			if wasDowned then
				-- Antes de zerar a vida: humanoid.Died limpa downed[model] sincronamente
				DownedService.finishedByShot(model, attacker)
			end
		end
		humanoid:TakeDamage(toHealth)
	end
	if humanoid.Health <= 0 then
		if wasDowned then DownedService.finishedByShot(model, attacker) end
		return "Killed", armorHit, toArmor, toHealth
	end
	return "Hit", armorHit, toArmor, toHealth
end

local function replicateFx(shooter: Player, weaponId: string, origin: Vector3, hitPositions: { Vector3 })
	local radius = CombatConfig.FxRadius
	local last = hitPositions[1]
	if not last then return end
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

local function processShot(player: Player, payload: FirePayload, usePingOnly: boolean?): ShotReport?
	if LegacyGuard.isLegacyGunServerActive() then return nil end
	if not Factions.canAttack(player) then
		local reason = if Factions.of(player) == FACTIONS.Civil then "civil_shot" else "faction_transition_shot"
		Net.reportAbuse(player, REMOTES.Fire, reason)
		return nil
	end
	if DownedService.isInteracting(player) then
		DownedService.cancelInteractor(player)
		return nil
	end
	local tool, weaponId, weapon, character = WeaponState.getEquipped(player)
	if not tool or not weaponId or not weapon or not character then
		Net.reportAbuse(player, REMOTES.Fire, "no_weapon")
		return nil
	end
	local previousSeq = lastSeq[player]
	if previousSeq and payload.seq <= previousSeq then
		Net.reportAbuse(player, REMOTES.Fire, "duplicate_seq")
		return nil
	end
	lastSeq[player] = payload.seq
	if payload.weaponId ~= weaponId then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not head then return nil end
	if
		character:GetAttribute(ATTR.Downed) == true
		or DownedService.isDowned(character)
		or character:GetAttribute(ATTR.Plating) == true
		or tool:GetAttribute(ATTR.Reloading) == true
		or WeaponState.isDrawing(tool, weapon)
	then
		return nil
	end

	local ammo = tool:GetAttribute(ATTR.Ammo)
	if not Net.isFiniteNumber(ammo) or (ammo :: number) <= 0 then return nil end

	local origin = payload.origin
	local worldParams = HitDetection.buildWorldParams()
	local originOk, originReason = HitDetection.validateOrigin(character, origin, worldParams)
	if not originOk then
		if originReason and originReason ~= "missing_parts" then
			Net.reportAbuse(player, REMOTES.Fire, originReason)
		end
		return nil
	end
	if not getFireRateLimiter(weaponId, weapon.FireInterval):allow(player) then
		Net.reportAbuse(player, REMOTES.Fire, "fire_rate")
		return nil
	end

	tool:SetAttribute(ATTR.Ammo, (ammo :: number) - 1)
	local shield = character:FindFirstChildOfClass("ForceField")
	if shield then shield:Destroy() end
	lastCombat[player] = os.clock()
	pcall(FactionService.markCombat, player)
	WantedService.onShotFired(player, origin)

	local clientTimestamp: number? = if usePingOnly then nil else payload.timestamp
	local rewindTo = LagCompensation.rewindTime(player, clientTimestamp)
	local directions = WeaponMath.pelletDirections(payload.direction, weapon.Pellets, weapon.PelletSpread)
	local hitPositions: { Vector3 } = {}
	local settled: { [Model]: boolean } = {}
	local report: ShotReport = { tool = tool, weaponId = weaponId, origin = origin, hitPos = origin }

	for index, direction in directions do
		local hit = HitDetection.resolveHit(player, origin, direction, weapon.Range, rewindTo, worldParams)
		local hitPos = hit.hitPos
		table.insert(hitPositions, hitPos)
		if index == 1 then
			report.hitPos = hitPos
			report.worldGeometryDistance = hit.worldGeometryDistance
		end
		local model, part = hit.hitModel, hit.hitPart
		if model and part and not settled[model] then
			local victimHumanoid = model:FindFirstChildOfClass("Humanoid")
			local canHit = if DownedService.isDowned(model)
				then Factions.canFinish(player, hit.hitPlayer)
				else Factions.canDamage(player, hit.hitPlayer)
			if victimHumanoid and victimHumanoid.Health > 0 and canHit then
				local region = Damage.regionOf(part.Name)
				local raw = Damage.compute(weapon, region, hit.distance)
				local result, armorHit, toArmor, toHealth =
					applyDamage(player, model, victimHumanoid, region, raw, weaponId, hit.distance, origin)
				hitRemote:FireClient(player, region, result, armorHit, toArmor, toHealth, hitPos)
				WantedService.onHit(player, model, hit.hitPlayer, toHealth, result, hitPos)
				if result ~= "Hit" then settled[model] = true end
				if index == 1 then
					report.region = region
					report.result = result
				end
				if CombatConfig.DebugShotLog then
					print(("[Shot] %s #%d -> %s %s(%s) %.1f dmg (armor %.1f, health %.1f) @ %.0f studs %s"):format(
						player.Name, payload.seq, model.Name, region, part.Name, raw, toArmor, toHealth, hit.distance, result))
				end
			end
		end
	end

	replicateFx(player, weaponId, origin, hitPositions)
	return report
end

local function onFire(player: Player, payload: FirePayload)
	debug.profilebegin("Combat_ShotValidation")
	processShot(player, payload, false)
	debug.profileend()
end

function CombatService.fire(player: Player, payload: FirePayload, usePingOnly: boolean?): ShotReport?
	if LegacyGuard.isLegacyGunServerActive() then return nil end
	local ok, reason = CombatContract.validateFire(payload)
	if not ok then
		Net.reportAbuse(player, REMOTES.Fire, reason or "invalid_args")
		return nil
	end
	debug.profilebegin("Combat_ShotValidation")
	local report = processShot(player, payload, usePingOnly == true)
	debug.profileend()
	return report
end

function CombatService.nextSeq(player: Player): number
	return (lastSeq[player] or 0) + 1
end

local function onReload(player: Player)
	local tool, _, weapon, character = WeaponState.getEquipped(player)
	if not tool or not weapon or not character or DownedService.isDowned(character) then
		return
	end
	Reload.start(player, tool, weapon, character)
end

function CombatService.secondsSinceCombat(player: Player): number
	local last = lastCombat[player]
	return if last then os.clock() - last else math.huge
end

function CombatService.reload(player: Player)
	onReload(player)
end

function CombatService.applyDamage(
	attacker: Player, model: Model, humanoid: Humanoid, region: Damage.Region,
	amount: number, hitPos: Vector3, sourcePos: Vector3, weaponName: string?
): HitResult?
	if amount <= 0 or humanoid.Health <= 0 then return nil end
	local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local distance = if attackerRoot and attackerRoot:IsA("BasePart")
		then (attackerRoot.Position - hitPos).Magnitude
		else nil
	local result, armorHit, toArmor, toHealth =
		applyDamage(attacker, model, humanoid, region, amount, weaponName, distance, sourcePos)
	if attacker.Character ~= model then
		if (toArmor + toHealth) > 0 then pcall(FactionService.markCombat, attacker) end
		hitRemote:FireClient(attacker, region, result, armorHit, toArmor, toHealth, hitPos)
		WantedService.onHit(attacker, model, Players:GetPlayerFromCharacter(model), toHealth, result, hitPos)
	end
	return result
end

function CombatService:Init()
	hitRemote = Net.serverEvent(REMOTES.Hit)
	fxRemote = Net.serverEvent(REMOTES.FX)
	damagedRemote = Net.serverEvent(REMOTES.Damaged)
end

function CombatService:Start()
	WeaponState.validateConfig()
	if LegacyGuard.isLegacyGunServerActive() then
		warn("[CombatService] GunServer legado ativo; tiros serão ignorados para evitar dano em dobro")
	end
	WeaponState.startWatching()
	LagCompensation.start()
	Net.listen(REMOTES.Fire, CombatContract.validateFire, onFire, CombatConfig.FireRemoteMinInterval)
	Net.listen(REMOTES.Reload, Net.noArgs, onReload, CombatConfig.ReloadRemoteMinInterval)
	Players.PlayerRemoving:Connect(function(player: Player)
		Reload.cancel(player)
		for _, limiter in fireRateLimiters do limiter:forget(player) end
		lastCombat[player] = nil
		lastSeq[player] = nil
	end)
end

return CombatService
