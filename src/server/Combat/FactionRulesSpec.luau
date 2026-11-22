--!strict
-- Testes unitários puros de FactionRules, CombatContract.validateFactionRequest e Factions.canDamage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)
local Factions = require(script.Parent.Factions)
local FactionRules = require(script.Parent.FactionRules)

local F = CombatContract.Factions
local S = CombatContract.FactionStates

local FactionRulesSpec = {}

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

function FactionRulesSpec.run(): (number, number, { string })
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

	-- 1) Civil -> MaskUp
	local ok, reason = FactionRules.canMaskUp({
		faction = F.Civil,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 100,
		switchCooldownUntil = 0,
	})
	check("maskup_civil_ok", ok == true and reason == nil)

	ok, reason = FactionRules.canMaskUp({
		faction = F.Robber,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 100,
		switchCooldownUntil = 0,
	})
	check("maskup_blocked_if_robber", ok == false and reason == "not_civil")

	ok, reason = FactionRules.canMaskUp({
		faction = F.Police,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 100,
		switchCooldownUntil = 0,
	})
	check("maskup_blocked_if_police", ok == false and reason == "not_civil")

	ok, reason = FactionRules.canMaskUp({
		faction = F.Civil,
		state = S.Transforming,
		alive = true,
		downed = false,
		now = 100,
		switchCooldownUntil = 0,
	})
	check("maskup_blocked_if_transitioning", ok == false and reason == "in_transition")

	-- 2) Civil -> Policia (proporcao, minimo, lotado, bonus understaffed)
	check("police_min_slots_small_server", FactionRules.maxPoliceSlots(2) == FactionsConfig.MinPoliceSlots)
	check("police_ratio_slots_large_server", FactionRules.maxPoliceSlots(10) == 4)

	ok, reason = FactionRules.canJoinPolice({
		faction = F.Civil,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 50,
		switchCooldownUntil = 0,
		atStation = true,
		joinedAt = 0,
		usedInitialChoice = true,
		policeCount = 1,
		activePlayers = 4,
	})
	check("join_police_station_ok", ok == true and reason == nil)

	ok, reason = FactionRules.canJoinPolice({
		faction = F.Civil,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 10,
		switchCooldownUntil = 0,
		atStation = false,
		joinedAt = 0,
		usedInitialChoice = false,
		policeCount = 0,
		activePlayers = 4,
	})
	check("join_police_initial_window_ok", ok == true and reason == nil)

	ok, reason = FactionRules.canJoinPolice({
		faction = F.Civil,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 50,
		switchCooldownUntil = 0,
		atStation = false,
		joinedAt = 0,
		usedInitialChoice = false,
		policeCount = 0,
		activePlayers = 4,
	})
	check("join_police_blocked_outside_window_and_station", ok == false and reason == "not_at_station")

	ok, reason = FactionRules.canJoinPolice({
		faction = F.Civil,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 50,
		switchCooldownUntil = 0,
		atStation = true,
		joinedAt = 0,
		usedInitialChoice = true,
		policeCount = 2,
		activePlayers = 5,
	})
	check("join_police_blocked_when_full", ok == false and reason == "police_full")

	check("police_understaffed_true", FactionRules.isPoliceUnderstaffed(1, 10) == true)
	check("police_understaffed_bonus", FactionRules.policeBonusMultiplier(1, 10) == FactionsConfig.PoliceBonusMultiplier)
	check("police_staffed_normal_bonus", FactionRules.policeBonusMultiplier(3, 10) == 1)

	-- 3) Bandido -> Civil (estrelas, DirtyCash, StolenItems, CombatCooldown, Downed, limpo)
	local cleanRobber: FactionRules.GoCivilContext = {
		faction = F.Robber,
		state = S.Idle,
		alive = true,
		downed = false,
		now = 200,
		switchCooldownUntil = 0,
		inCombatUntil = 150,
		wantedLevel = 0,
		dirtyCash = 0,
		stolenItemsCount = 0,
		atStation = false,
	}
	ok, reason = FactionRules.canGoCivil(cleanRobber)
	check("robber_to_civil_clean_ok", ok == true and reason == nil)

	local wantedCtx = table.clone(cleanRobber)
	wantedCtx.wantedLevel = 2
	ok, reason = FactionRules.canGoCivil(wantedCtx)
	check("robber_to_civil_blocked_wanted", ok == false and reason == "wanted")

	local dirtyCtx = table.clone(cleanRobber)
	dirtyCtx.dirtyCash = 500
	ok, reason = FactionRules.canGoCivil(dirtyCtx)
	check("robber_to_civil_blocked_dirty_cash", ok == false and reason == "dirty_cash")

	local stolenCtx = table.clone(cleanRobber)
	stolenCtx.stolenItemsCount = 1
	ok, reason = FactionRules.canGoCivil(stolenCtx)
	check("robber_to_civil_blocked_stolen_items", ok == false and reason == "stolen_items")

	local combatCtx = table.clone(cleanRobber)
	combatCtx.inCombatUntil = 220
	ok, reason = FactionRules.canGoCivil(combatCtx)
	check("robber_to_civil_blocked_in_combat", ok == false and reason == "in_combat")

	local downedCtx = table.clone(cleanRobber)
	downedCtx.downed = true
	ok, reason = FactionRules.canGoCivil(downedCtx)
	check("robber_to_civil_blocked_downed", ok == false and reason == "downed")

	-- 4) Cancelamento de transicao ao tomar dano
	check("cancel_on_damage_transforming", FactionRules.shouldCancelTransitionOnDamage(S.Transforming) == true)
	check("cancel_on_damage_unmasking", FactionRules.shouldCancelTransitionOnDamage(S.Unmasking) == true)
	check("no_cancel_on_damage_idle", FactionRules.shouldCancelTransitionOnDamage(S.Idle) == false)

	-- 5) Regras de Factions.canDamage
	local civilIdle = fakePlayer(F.Civil, S.Idle)
	local civilTrans = fakePlayer(F.Civil, S.Transforming)
	local policeA = fakePlayer(F.Police, S.Idle)
	local policeB = fakePlayer(F.Police, S.Idle)
	local robberA = fakePlayer(F.Robber, S.Idle)
	local robberB = fakePlayer(F.Robber, S.Idle)
	local robberUnmask = fakePlayer(F.Robber, S.Unmasking)

	check("damage_civil_cannot_shoot_robber", Factions.canDamage(civilIdle, robberA) == false)
	check("damage_robber_cannot_shoot_civil", Factions.canDamage(robberA, civilIdle) == false)
	check("damage_police_cannot_shoot_civil", Factions.canDamage(policeA, civilIdle) == false)
	check("damage_civil_transforming_vulnerable", Factions.canDamage(robberA, civilTrans) == true)
	check("damage_civil_transforming_cannot_shoot", Factions.canDamage(civilTrans, robberA) == false)
	check("damage_robber_unmasking_cannot_shoot", Factions.canDamage(robberUnmask, policeA) == false)
	check("damage_police_vs_police_blocked", Factions.canDamage(policeA, policeB) == false)
	check("damage_robber_vs_robber_allowed", Factions.canDamage(robberA, robberB) == true)
	check("damage_police_vs_robber_allowed", Factions.canDamage(policeA, robberA) == true)

	-- 6) Validador do contrato de rede
	ok, reason = CombatContract.validateFactionRequest({ action = "MaskUp" })
	check("validate_request_ok", ok == true and reason == nil)
	ok, reason = CombatContract.validateFactionRequest({ action = "Hack" })
	check("validate_request_bad_action", ok == false and reason == "bad_action")
	ok, reason = CombatContract.validateFactionRequest({ action = "MaskUp", extra = 1 })
	check("validate_request_extra_fields", ok == false and reason == "payload_extra_fields")
	ok, reason = CombatContract.validateFactionRequest("MaskUp")
	check("validate_request_not_table", ok == false and reason == "payload_not_table")

	-- 7) Faccao inicial e reset na morte conforme Phase0AutoBandit
	local cfgBandit = table.clone(FactionsConfig) :: any
	cfgBandit.Phase0AutoBandit = true
	cfgBandit.ResetToCivilOnDeath = true
	cfgBandit.Phase0CombatTest = false
	check("phase0_auto_bandit_true_spawn", FactionRules.defaultSpawnFaction(cfgBandit) == F.Robber)
	check("phase0_auto_bandit_true_death_reset", FactionRules.deathResetFaction(cfgBandit) == F.Robber)
	check("phase0_auto_bandit_true_should_reset", FactionRules.shouldResetOnDeath(cfgBandit) == true)

	local cfgCivil = table.clone(FactionsConfig) :: any
	cfgCivil.Phase0AutoBandit = false
	cfgCivil.DefaultSpawnFaction = F.Civil
	cfgCivil.ResetToCivilOnDeath = true
	cfgCivil.Phase0CombatTest = false
	check("phase0_auto_bandit_false_spawn", FactionRules.defaultSpawnFaction(cfgCivil) == F.Civil)
	check("phase0_auto_bandit_false_death_reset", FactionRules.deathResetFaction(cfgCivil) == F.Civil)
	check("phase0_auto_bandit_false_should_reset", FactionRules.shouldResetOnDeath(cfgCivil) == true)
	check("live_config_auto_bandit_active", FactionsConfig.Phase0AutoBandit == true and Factions.defaultFaction() == F.Robber)

	-- 8) Aliados e finalizacao (Phase0BanditsAreAllies e Factions.canFinish)
	local robberGangA1 = fakePlayer(F.Robber, S.Idle, "GangA")
	local robberGangA2 = fakePlayer(F.Robber, S.Idle, "GangA")
	local robberGangB = fakePlayer(F.Robber, S.Idle, "GangB")
	local prevAlliesFlag = FactionsConfig.Phase0BanditsAreAllies
	check("live_config_bandits_are_allies_active", prevAlliesFlag == true)

	local allyOk, allyErr = pcall(function()
		FactionsConfig.Phase0BanditsAreAllies = true
		check("allies_bandits_no_gang_flag_on", Factions.areAllies(robberA, robberB) == true)
		check("finish_bandits_no_gang_flag_on_blocked", Factions.canFinish(robberA, robberB) == false)
		check("damage_bandits_no_gang_flag_on_allowed", Factions.canDamage(robberA, robberB) == true)
		check("allies_same_gang_true", Factions.areAllies(robberGangA1, robberGangA2) == true)
		check("finish_same_gang_blocked", Factions.canFinish(robberGangA1, robberGangA2) == false)
		check("allies_different_gangs_false", Factions.areAllies(robberGangA1, robberGangB) == false)
		check("finish_different_gangs_allowed", Factions.canFinish(robberGangA1, robberGangB) == true)
		check("allies_gang_vs_no_gang_false", Factions.areAllies(robberGangA1, robberA) == false)
		check("allies_police_vs_police_true", Factions.areAllies(policeA, policeB) == true)
		check("finish_police_vs_police_blocked", Factions.canFinish(policeA, policeB) == false)
		check("allies_police_vs_bandit_false", Factions.areAllies(policeA, robberA) == false)
		check("finish_police_vs_bandit_allowed", Factions.canFinish(policeA, robberA) == true)
		check("finish_bandit_vs_police_allowed", Factions.canFinish(robberA, policeA) == true)
		check("finish_npc_by_bandit_allowed", Factions.canFinish(robberA, nil) == true)
		check("finish_npc_by_civil_blocked", Factions.canFinish(civilIdle, nil) == false)

		FactionsConfig.Phase0BanditsAreAllies = false
		check("allies_bandits_no_gang_flag_off", Factions.areAllies(robberA, robberB) == false)
		check("finish_bandits_no_gang_flag_off_allowed", Factions.canFinish(robberA, robberB) == true)
		check("damage_bandits_no_gang_flag_off_allowed", Factions.canDamage(robberA, robberB) == true)
		check("allies_same_gang_flag_off_true", Factions.areAllies(robberGangA1, robberGangA2) == true)
		check("allies_police_flag_off_true", Factions.areAllies(policeA, policeB) == true)
	end)
	FactionsConfig.Phase0BanditsAreAllies = prevAlliesFlag
	if not allyOk then
		check("allies_section_no_error", false, tostring(allyErr))
	end

	-- 9) Opção A: alistamento na delegacia em Fase 0 (Bandido -> Policia, checagens injetadas e destino ao sair)
	local baseStationJoin: FactionRules.JoinPoliceContext = {
		faction = F.Robber,
		state = S.Idle,
		alive = true,
		downed = false,
		plating = false,
		now = 100,
		switchCooldownUntil = 0,
		inCombatUntil = 0,
		secondsSinceCombat = 60,
		combatLockSeconds = 15,
		wantedLevel = 0,
		isRobbing = false,
		dirtyCash = 0,
		stolenItemsCount = 0,
		atStation = true,
		joinedAt = 0,
		usedInitialChoice = true,
		policeCount = 0,
		activePlayers = 4,
	}
	ok, reason = FactionRules.canJoinPolice(baseStationJoin, cfgBandit)
	check("phase0_robber_join_police_at_station_ok", ok == true and reason == nil, tostring(reason))

	ok, reason = FactionRules.canJoinPolice(baseStationJoin, cfgCivil)
	check("non_phase0_robber_join_police_blocked", ok == false and reason == "not_civil", tostring(reason))

	local wantedJoin = table.clone(baseStationJoin)
	wantedJoin.wantedLevel = 1
	ok, reason = FactionRules.canJoinPolice(wantedJoin, cfgBandit)
	check("join_police_blocked_wanted", ok == false and reason == "wanted", tostring(reason))

	local robbingJoin = table.clone(baseStationJoin)
	robbingJoin.isRobbing = true
	ok, reason = FactionRules.canJoinPolice(robbingJoin, cfgBandit)
	check("join_police_blocked_robbing", ok == false and reason == "robbing", tostring(reason))

	local combatJoin = table.clone(baseStationJoin)
	combatJoin.secondsSinceCombat = 3
	ok, reason = FactionRules.canJoinPolice(combatJoin, cfgBandit)
	check("join_police_blocked_recent_combat", ok == false and reason == "in_combat", tostring(reason))

	check("go_civil_target_phase0_police_is_robber", FactionRules.goCivilTargetFaction(F.Police, cfgBandit) == F.Robber)
	check("go_civil_target_non_phase0_police_is_civil", FactionRules.goCivilTargetFaction(F.Police, cfgCivil) == F.Civil)

	return passed, failed, failures
end

return FactionRulesSpec