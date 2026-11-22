--!strict
-- Testes unitários puros de DownedRules (distância, linha de visão, validade e
-- cancelamento de hold) e Factions.areAllies com Civil.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)
local DownedRules = require(script.Parent.DownedRules)
local Factions = require(script.Parent.Factions)

local F = CombatContract.Factions
local S = CombatContract.FactionStates

local DownedRulesSpec = {}

local function fakePlayer(faction: string?, state: string?, gang: string?): Player
	local attrs: { [string]: any } = {
		[CombatContract.Attributes.Faction] = faction,
		[CombatContract.Attributes.FactionState] = state,
		[CombatContract.Attributes.Gang] = gang,
	}
	return ({
		GetAttribute = function(_self: any, key: string): any
			return attrs[key]
		end,
	} :: any) :: Player
end

function DownedRulesSpec.run(): (number, number, { string })
	local passed = 0
	local failed = 0
	local failures: { string } = {}

	local function check(name: string, condition: boolean, detail: string?)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(failures, name .. (if detail then (": " .. detail) else ""))
		end
	end

	-- 1) canInteract puro (distância, LoS, vivo, derrubado, próprio corpo, NaN)
	local baseCtx: DownedRules.InteractContext = {
		interactorAlive = true,
		interactorDowned = false,
		isSameModel = false,
		distance = 5,
		maxDistance = 10,
		hasLineOfSight = true,
	}
	local ok, reason = DownedRules.canInteract(baseCtx)
	check("can_interact_valid_ok", ok == true and reason == nil, tostring(reason))

	local edgeCtx = table.clone(baseCtx)
	edgeCtx.distance = 10
	ok, reason = DownedRules.canInteract(edgeCtx)
	check("can_interact_exact_max_dist_ok", ok == true and reason == nil, tostring(reason))

	local farCtx = table.clone(baseCtx)
	farCtx.distance = 10.1
	ok, reason = DownedRules.canInteract(farCtx)
	check("can_interact_too_far_rejected", ok == false and reason == "too_far", tostring(reason))

	local noLosCtx = table.clone(baseCtx)
	noLosCtx.hasLineOfSight = false
	ok, reason = DownedRules.canInteract(noLosCtx)
	check("can_interact_no_los_rejected", ok == false and reason == "no_los", tostring(reason))

	local deadCtx = table.clone(baseCtx)
	deadCtx.interactorAlive = false
	ok, reason = DownedRules.canInteract(deadCtx)
	check("can_interact_dead_rejected", ok == false and reason == "dead", tostring(reason))

	local downedCtx = table.clone(baseCtx)
	downedCtx.interactorDowned = true
	ok, reason = DownedRules.canInteract(downedCtx)
	check("can_interact_downed_rejected", ok == false and reason == "downed", tostring(reason))

	local selfCtx = table.clone(baseCtx)
	selfCtx.isSameModel = true
	ok, reason = DownedRules.canInteract(selfCtx)
	check("can_interact_self_rejected", ok == false and reason == "self", tostring(reason))

	local nanCtx = table.clone(baseCtx)
	nanCtx.distance = 0 / 0
	ok, reason = DownedRules.canInteract(nanCtx)
	check("can_interact_nan_dist_rejected", ok == false and reason == "bad_distance", tostring(reason))

	-- 2) hasLineOfSight no workspace (livre vs parede vs peça ignorada)
	local sandbox = Instance.new("Folder")
	sandbox.Name = "_DownedRulesSpecSandbox"
	sandbox.Parent = workspace
	local runOk, runErr = pcall(function()
		local pA = Vector3.new(0, 4200, 0)
		local pB = Vector3.new(0, 4200, -8)
		check("los_clear_true", DownedRules.hasLineOfSight(pA, pB, {}) == true)

		local wall = Instance.new("Part")
		wall.Anchored = true
		wall.CanQuery = true
		wall.Size = Vector3.new(6, 6, 1)
		wall.CFrame = CFrame.new(0, 4200, -4)
		wall.Parent = sandbox
		check("los_blocked_by_wall_false", DownedRules.hasLineOfSight(pA, pB, {}) == false)
		check("los_ignored_part_true", DownedRules.hasLineOfSight(pA, pB, { wall }) == true)
	end)
	sandbox:Destroy()
	if not runOk then
		check("los_sandbox_no_error", false, tostring(runErr))
	end

	-- 3) isHoldValid e shouldCancelHold
	ok, reason = DownedRules.isHoldValid(nil, 100, 4, 0.15)
	check("hold_nil_rejected", ok == false and reason == "no_hold", tostring(reason))

	ok, reason = DownedRules.isHoldValid(97, 100, 4, 0.15) -- 3.0s < 3.4s
	check("hold_too_short_rejected", ok == false and reason == "hold_too_short", tostring(reason))

	ok, reason = DownedRules.isHoldValid(96.6, 100, 4, 0.15) -- 3.4s == minHold
	check("hold_at_tolerance_ok", ok == true and reason == nil, tostring(reason))

	ok, reason = DownedRules.isHoldValid(95, 100, 4, 0.15)
	check("hold_over_duration_ok", ok == true and reason == nil, tostring(reason))

	local cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = true, canInteract = true, allowed = true, now = 100,
	})
	check("should_cancel_active_false", cancel == false and cancelReason == nil)

	cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = false, canInteract = true, allowed = true, now = 100,
	})
	check("should_cancel_disconnected_true", cancel == true and cancelReason == "disconnected")

	cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = true, canInteract = true, allowed = true, shotFired = true, now = 100,
	})
	check("should_cancel_shot_fired_true", cancel == true and cancelReason == "shot_fired")

	cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = true, canInteract = false, allowed = true, now = 100,
	})
	check("should_cancel_cannot_interact_true", cancel == true and cancelReason == "cannot_interact")

	cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = true, canInteract = true, allowed = true, endedAt = 99.8, now = 100, triggerGraceSeconds = 0.5,
	})
	check("should_cancel_ended_within_grace_false", cancel == false)

	cancel, cancelReason = DownedRules.shouldCancelHold({
		connected = true, canInteract = true, allowed = true, endedAt = 99.0, now = 100, triggerGraceSeconds = 0.5,
	})
	check("should_cancel_ended_past_grace_true", cancel == true and cancelReason == "hold_expired")

	-- 4) Factions.areAllies com Civil (mantendo Phase0BanditsAreAllies)
	local civilNoGang = fakePlayer(F.Civil, S.Idle)
	local civilGangA1 = fakePlayer(F.Civil, S.Idle, "GangA")
	local civilGangA2 = fakePlayer(F.Civil, S.Idle, "GangA")
	local robberGangA = fakePlayer(F.Robber, S.Idle, "GangA")
	local robber1 = fakePlayer(F.Robber, S.Idle)
	local robber2 = fakePlayer(F.Robber, S.Idle)
	local police = fakePlayer(F.Police, S.Idle)

	local prevFlag = FactionsConfig.Phase0BanditsAreAllies
	local allyOk, allyErr = pcall(function()
		FactionsConfig.Phase0BanditsAreAllies = true
		check("allies_civil_vs_civil_same_gang_false", Factions.areAllies(civilGangA1, civilGangA2) == false)
		check("allies_civil_vs_robber_same_gang_false", Factions.areAllies(civilGangA1, robberGangA) == false)
		check("allies_robber_vs_civil_same_gang_false", Factions.areAllies(robberGangA, civilGangA1) == false)
		check("allies_civil_vs_police_false", Factions.areAllies(civilNoGang, police) == false)
		check("allies_bandits_phase0_preserved_true", Factions.areAllies(robber1, robber2) == true)
	end)
	FactionsConfig.Phase0BanditsAreAllies = prevFlag
	if not allyOk then
		check("allies_civil_no_error", false, tostring(allyErr))
	end

	return passed, failed, failures
end

return DownedRulesSpec