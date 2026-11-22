--!strict
-- Máquina de estados autoritativa de Escolha de Lado (Civil, Bandido, Policia).
-- Controla Mask-Up tático, plantão policial, retorno a Civil anti-exploit e proteção de Civil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)
local Combat = script.Parent.Parent.Combat
local Factions = require(Combat.Factions)
local FactionRules = require(Combat.FactionRules)
local FactionCharacter = require(Combat.FactionCharacter)
local PoliceStations = require(Combat.PoliceStations)

type FactionAction = CombatContract.FactionAction
type FactionRequestPayload = CombatContract.FactionRequestPayload

type PlayerRecord = {
	joinedAt: number,
	usedInitialChoice: boolean,
	switchCooldownUntil: number,
	inCombatUntil: number,
	transitionToken: number,
	transitionThread: thread?,
	savedWalkSpeed: number?,
	characterConnections: { RBXScriptConnection },
}

export type FactionChangedCallback = (player: Player, newFaction: string, oldFaction: string, reason: string?) -> ()
export type CivilKilledCallback = (victim: Player, killer: Player?, reason: string) -> ()
export type ExternalChecks = {
	getWantedStars: ((player: Player) -> number)?,
	isRobbing: ((player: Player) -> boolean)?,
	secondsSinceCombat: ((player: Player) -> number)?,
	combatLockSeconds: number?,
	switchCooldownSeconds: number?,
}

local REMOTES = CombatContract.Remotes
local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions
local STATES = CombatContract.FactionStates

local FactionService = {}

local stateChangedRemote: RemoteEvent? = nil
local transformFxRemote: RemoteEvent? = nil
local records: { [Player]: PlayerRecord } = {}
local factionChangedListeners: { FactionChangedCallback } = {}
local civilKilledListeners: { CivilKilledCallback } = {}
local externalChecks: ExternalChecks = {}

function FactionService.setExternalChecks(checks: ExternalChecks) externalChecks = checks end
local function numAttr(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end
local function addListener<T>(list: { T }, callback: T): () -> ()
	table.insert(list, callback)
	return function()
		local index = table.find(list, callback)
		if index then table.remove(list, index) end
	end
end
local function broadcast(player: Player, faction: string, state: string, duration: number?, reason: string?)
	if stateChangedRemote then stateChangedRemote:FireAllClients(player, faction, state, duration, reason) end
end
local function notifyClient(player: Player, reason: string)
	if stateChangedRemote then stateChangedRemote:FireClient(player, player, Factions.of(player), Factions.stateOf(player), nil, reason) end
end

local function switchCtx(player: Player, record: PlayerRecord, atStation: boolean): FactionRules.GoCivilContext
	local char, _, _, alive, downed = FactionCharacter.info(player)
	local extStars = if externalChecks.getWantedStars then externalChecks.getWantedStars(player) else 0
	return {
		faction = Factions.of(player), state = Factions.stateOf(player),
		alive = alive, downed = downed, plating = char ~= nil and char:GetAttribute(ATTR.Plating) == true,
		now = os.clock(), switchCooldownUntil = record.switchCooldownUntil, inCombatUntil = record.inCombatUntil,
		secondsSinceCombat = if externalChecks.secondsSinceCombat then externalChecks.secondsSinceCombat(player) else math.huge,
		combatLockSeconds = externalChecks.combatLockSeconds,
		wantedLevel = math.max(numAttr(player, ATTR.WantedLevel), extStars),
		isRobbing = externalChecks.isRobbing ~= nil and externalChecks.isRobbing(player) == true,
		dirtyCash = numAttr(player, ATTR.DirtyCash), stolenItemsCount = numAttr(player, ATTR.StolenItemsCount),
		atStation = atStation,
	}
end

local function clearTransition(player: Player, record: PlayerRecord)
	record.transitionToken += 1
	local thread = record.transitionThread
	record.transitionThread = nil
	if thread and coroutine.running() ~= thread then pcall(task.cancel, thread) end
	local saved = record.savedWalkSpeed
	record.savedWalkSpeed = nil
	FactionCharacter.restoreSpeed(player, saved)
end

local function applyFaction(player: Player, record: PlayerRecord, newFaction: string, reason: string?, setCooldown: boolean)
	local oldFaction = Factions.of(player)
	player:SetAttribute(ATTR.Faction, newFaction)
	player:SetAttribute(ATTR.FactionState, STATES.Idle)
	if setCooldown then
		local cd = externalChecks.switchCooldownSeconds or FactionsConfig.SwitchCooldownSeconds
		record.switchCooldownUntil = os.clock() + cd
	end
	if newFaction == FACTIONS.Civil then
		FactionCharacter.enforceCivilTools(player)
	elseif newFaction == FACTIONS.Police then
		PoliceStations.dequeue(player)
	end
	PoliceStations.refreshPoliceBonus()
	if oldFaction == FACTIONS.Police and newFaction ~= FACTIONS.Police then
		PoliceStations.notifyNextQueued(function(queued: Player)
			notifyClient(queued, "police_slot_available")
		end)
	end
	broadcast(player, newFaction, STATES.Idle, nil, reason)
	if oldFaction ~= newFaction then
		for _, callback in factionChangedListeners do
			task.spawn(callback, player, newFaction, oldFaction, reason)
		end
	end
end

local function handleMaskUp(player: Player, record: PlayerRecord): (boolean, string?)
	local _, _, _, alive, downed = FactionCharacter.info(player)
	local ok, reason = FactionRules.canMaskUp({
		faction = Factions.of(player), state = Factions.stateOf(player),
		alive = alive, downed = downed, now = os.clock(),
		switchCooldownUntil = record.switchCooldownUntil,
	}, FactionsConfig)
	if not ok then
		notifyClient(player, reason or "denied")
		return false, reason
	end

	local duration = FactionsConfig.TransformSeconds
	clearTransition(player, record)
	local token = record.transitionToken
	player:SetAttribute(ATTR.FactionState, STATES.Transforming)
	record.savedWalkSpeed = FactionCharacter.applyTransformSpeed(player)
	broadcast(player, FACTIONS.Civil, STATES.Transforming, duration, "mask_up")
	FactionCharacter.replicateFx(transformFxRemote, player, "MaskUp", duration)

	record.transitionThread = task.delay(duration, function()
		if records[player] ~= record or record.transitionToken ~= token then return end
		record.transitionThread = nil
		local saved = record.savedWalkSpeed
		record.savedWalkSpeed = nil
		FactionCharacter.restoreSpeed(player, saved)
		local _, _, _, stillAlive, stillDowned = FactionCharacter.info(player)
		if not player.Parent or not stillAlive or stillDowned or Factions.of(player) ~= FACTIONS.Civil then
			player:SetAttribute(ATTR.FactionState, STATES.Idle)
			broadcast(player, Factions.of(player), STATES.Idle, nil, "interrupted")
			return
		end
		applyFaction(player, record, FACTIONS.Robber, "mask_up", true)
	end)
	return true, nil
end

local function handleJoinPolice(player: Player, record: PlayerRecord, atStation: boolean): (boolean, string?)
	local policeCount, activePlayers = PoliceStations.countFactions()
	local ctx = switchCtx(player, record, atStation) :: any
	ctx.joinedAt = record.joinedAt
	ctx.usedInitialChoice = record.usedInitialChoice
	ctx.policeCount = policeCount
	ctx.activePlayers = activePlayers
	local ok, reason = FactionRules.canJoinPolice(ctx, FactionsConfig)
	if not ok then
		if reason == "police_full" then PoliceStations.enqueue(player) end
		notifyClient(player, reason or "denied")
		return false, reason
	end
	if not atStation then record.usedInitialChoice = true end
	clearTransition(player, record)
	applyFaction(player, record, FACTIONS.Police, "join_police", true)
	return true, nil
end

local function handleGoCivil(player: Player, record: PlayerRecord, atStation: boolean): (boolean, string?)
	local ctx = switchCtx(player, record, atStation)
	local ok, reason = FactionRules.canGoCivil(ctx, FactionsConfig)
	if not ok then
		notifyClient(player, reason or "denied")
		return false, reason
	end
	local targetFaction = FactionRules.goCivilTargetFaction(ctx.faction, FactionsConfig)
	local duration = FactionRules.goCivilDuration(ctx.faction, atStation, FactionsConfig)
	clearTransition(player, record)
	if duration <= 0 then
		applyFaction(player, record, targetFaction, "end_shift", true)
		return true, nil
	end
	local token = record.transitionToken
	local fxReason = if ctx.faction == FACTIONS.Police then "end_shift" else "unmask"
	player:SetAttribute(ATTR.FactionState, STATES.Unmasking)
	broadcast(player, ctx.faction, STATES.Unmasking, duration, fxReason)
	FactionCharacter.replicateFx(transformFxRemote, player, "Unmask", duration)

	record.transitionThread = task.delay(duration, function()
		if records[player] ~= record or record.transitionToken ~= token then return end
		record.transitionThread = nil
		local recheck = switchCtx(player, record, atStation)
		recheck.state = STATES.Idle -- o timer encerra a própria canalização
		local stillOk, failReason = FactionRules.canGoCivil(recheck, FactionsConfig)
		if not player.Parent or not stillOk then
			player:SetAttribute(ATTR.FactionState, STATES.Idle)
			broadcast(player, Factions.of(player), STATES.Idle, nil, failReason or "interrupted")
			return
		end
		applyFaction(player, record, FactionRules.goCivilTargetFaction(recheck.faction, FactionsConfig), fxReason, true)
	end)
	return true, nil
end

function FactionService.requestAction(player: Player, action: FactionAction, atStationOverride: boolean?): (boolean, string?)
	local record = records[player]
	if not record then return false, "no_record" end
	local _, _, root = FactionCharacter.info(player)
	local atStation = if atStationOverride ~= nil then atStationOverride else PoliceStations.isNear(root)
	if action == "MaskUp" then return handleMaskUp(player, record)
	elseif action == "JoinPolice" then return handleJoinPolice(player, record, atStation)
	elseif action == "GoCivil" then return handleGoCivil(player, record, atStation)
	elseif action == "Cancel" then
		if Factions.stateOf(player) == STATES.Idle then return false, "not_in_transition" end
		FactionService.cancelTransition(player, "cancelled")
		return true, nil
	end
	return false, "bad_action"
end

function FactionService.markCombat(player: Player)
	local record = records[player]
	if not record then return end
	local cooldown = FactionsConfig.CombatCooldownSeconds
	record.inCombatUntil = os.clock() + cooldown
	player:SetAttribute(ATTR.InCombatUntil, workspace:GetServerTimeNow() + cooldown)
end

function FactionService.cancelTransition(player: Player, reason: string)
	local record = records[player]
	if not record or not FactionRules.shouldCancelTransitionOnDamage(Factions.stateOf(player)) then return end
	clearTransition(player, record)
	player:SetAttribute(ATTR.FactionState, STATES.Idle)
	broadcast(player, Factions.of(player), STATES.Idle, nil, reason)
end

local function forceFaction(player: Player, target: string, reason: string)
	local record = records[player]
	if not record then return end
	clearTransition(player, record)
	if Factions.of(player) == target and Factions.stateOf(player) == STATES.Idle then
		if target == FACTIONS.Civil then FactionCharacter.enforceCivilTools(player) end
		return
	end
	applyFaction(player, record, target, reason, false)
end

function FactionService.forceCivil(player: Player, reason: string) forceFaction(player, FACTIONS.Civil, reason) end
function FactionService.getPoliceBonusMultiplier(): number return PoliceStations.getBonusMultiplier() end
-- Ganchos públicos para Loadout/TeamService e Procurado (morte não-combate de Civil)
function FactionService.onFactionChanged(callback: FactionChangedCallback): () -> () return addListener(factionChangedListeners, callback) end
function FactionService.onCivilKilledByPlayer(callback: CivilKilledCallback): () -> () return addListener(civilKilledListeners, callback) end
function FactionService.notifyCivilKilledByPlayer(victim: Player, killer: Player?, reason: string?)
	for _, callback in civilKilledListeners do task.spawn(callback, victim, killer, reason or "non_combat_death") end
end

local function onCharacter(player: Player, record: PlayerRecord, character: Model)
	FactionCharacter.bind(player, record.characterConnections, character, function(killer: Player?)
		FactionService.cancelTransition(player, "died")
		if Factions.of(player) == FACTIONS.Civil and killer then
			FactionService.notifyCivilKilledByPlayer(player, killer, "non_combat_death")
		end
		if FactionRules.shouldResetOnDeath(FactionsConfig) then
			-- Defer garante que KillFeedService leia a facção real da vítima no Died antes do reset
			task.defer(forceFaction, player, FactionRules.deathResetFaction(FactionsConfig), "died")
		end
	end)
end

local function setupPlayer(player: Player)
	local record: PlayerRecord = {
		joinedAt = os.clock(), usedInitialChoice = false, switchCooldownUntil = 0,
		inCombatUntil = 0, transitionToken = 0, transitionThread = nil,
		savedWalkSpeed = nil, characterConnections = {},
	}
	records[player] = record
	player:SetAttribute(ATTR.Faction, Factions.defaultFaction())
	player:SetAttribute(ATTR.FactionState, STATES.Idle)
	player:SetAttribute(ATTR.InCombatUntil, 0)
	if player:GetAttribute(ATTR.WantedLevel) == nil then
		player:SetAttribute(ATTR.WantedLevel, 0)
	end
	PoliceStations.refreshPoliceBonus()
	if player.Character then task.spawn(onCharacter, player, record, player.Character) end
	player.CharacterAdded:Connect(function(character: Model)
		if records[player] == record then onCharacter(player, record, character) end
	end)
end

function FactionService:Init()
	Net.serverEvent(REMOTES.FactionRequest)
	stateChangedRemote = Net.serverEvent(REMOTES.FactionStateChanged)
	transformFxRemote = Net.serverEvent(REMOTES.FactionTransformFX)
	PoliceStations.refreshPoliceBonus()
end

function FactionService:Start()
	Net.listen(REMOTES.FactionRequest, CombatContract.validateFactionRequest, function(player: Player, payload: FactionRequestPayload)
		FactionService.requestAction(player, payload.action)
	end, FactionsConfig.RequestMinInterval)

	for _, player in Players:GetPlayers() do setupPlayer(player) end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		local wasPolice = Factions.of(player) == FACTIONS.Police
		local record = records[player]
		if record then
			clearTransition(player, record)
			for _, conn in record.characterConnections do conn:Disconnect() end
			records[player] = nil
		end
		PoliceStations.forget(player)
		PoliceStations.refreshPoliceBonus()
		if wasPolice then
			PoliceStations.notifyNextQueued(function(queued: Player) notifyClient(queued, "police_slot_available") end)
		end
	end)

	PoliceStations.bindAll(function(player: Player)
		local action: FactionAction = if Factions.of(player) == FACTIONS.Police then "GoCivil" else "JoinPolice"
		FactionService.requestAction(player, action, true)
	end)
end

return FactionService