--!strict
-- Regras puras da Escolha de Lado (sem tocar em instâncias, 100% testável).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)

export type RulesConfig = {
	TransformSeconds: number,
	UnmaskSeconds: number,
	EndShiftSeconds: number,
	SwitchCooldownSeconds: number,
	CombatCooldownSeconds: number,
	InitialChoiceSeconds: number,
	MaxPoliceRatio: number,
	MinPoliceSlots: number,
	UnderstaffedPoliceRatio: number,
	PoliceBonusMultiplier: number,
	ResetToCivilOnDeath: boolean,
	Phase0CombatTest: boolean,
	AllowInstantStartChoice: boolean,
	DefaultSpawnFaction: string,
	Phase0AutoBandit: boolean,
}

export type MaskUpContext = {
	faction: string,
	state: string,
	alive: boolean,
	downed: boolean,
	now: number,
	switchCooldownUntil: number,
}

export type JoinPoliceContext = {
	faction: string,
	state: string,
	alive: boolean,
	downed: boolean,
	plating: boolean?,
	now: number,
	switchCooldownUntil: number,
	inCombatUntil: number?,
	secondsSinceCombat: number?,
	combatLockSeconds: number?,
	wantedLevel: number?,
	isRobbing: boolean?,
	dirtyCash: number?,
	stolenItemsCount: number?,
	atStation: boolean,
	joinedAt: number,
	usedInitialChoice: boolean,
	policeCount: number,
	activePlayers: number,
}

export type GoCivilContext = {
	faction: string,
	state: string,
	alive: boolean,
	downed: boolean,
	plating: boolean?,
	now: number,
	switchCooldownUntil: number,
	inCombatUntil: number,
	secondsSinceCombat: number?,
	combatLockSeconds: number?,
	wantedLevel: number,
	isRobbing: boolean?,
	dirtyCash: number,
	stolenItemsCount: number,
	atStation: boolean,
}

local FACTIONS = CombatContract.Factions
local STATES = CombatContract.FactionStates

local FactionRules = {}

local function cfgOf(config: RulesConfig?): RulesConfig
	return (config or FactionsConfig) :: RulesConfig
end

-- Teto dinâmico de vagas policiais respeitando mínimo garantido
function FactionRules.maxPoliceSlots(activePlayers: number, config: RulesConfig?): number
	local cfg = cfgOf(config)
	local scaled = math.floor(math.max(0, activePlayers) * cfg.MaxPoliceRatio)
	return math.max(cfg.MinPoliceSlots, scaled)
end

-- Indica se a polícia está abaixo da proporção mínima saudável
function FactionRules.isPoliceUnderstaffed(policeCount: number, activePlayers: number, config: RulesConfig?): boolean
	if activePlayers <= 0 then
		return false
	end
	local cfg = cfgOf(config)
	return (policeCount / activePlayers) < cfg.UnderstaffedPoliceRatio
end

function FactionRules.policeBonusMultiplier(policeCount: number, activePlayers: number, config: RulesConfig?): number
	local cfg = cfgOf(config)
	return if FactionRules.isPoliceUnderstaffed(policeCount, activePlayers, cfg) then cfg.PoliceBonusMultiplier else 1
end

function FactionRules.canMaskUp(ctx: MaskUpContext, _config: RulesConfig?): (boolean, string?)
	if not ctx.alive then
		return false, "dead"
	end
	if ctx.downed then
		return false, "downed"
	end
	if ctx.state ~= STATES.Idle then
		return false, "in_transition"
	end
	if ctx.faction ~= FACTIONS.Civil then
		return false, "not_civil"
	end
	if ctx.now < ctx.switchCooldownUntil then
		return false, "switch_cooldown"
	end
	return true, nil
end

function FactionRules.canJoinPolice(ctx: JoinPoliceContext, config: RulesConfig?): (boolean, string?)
	local cfg = cfgOf(config)
	if not ctx.alive then
		return false, "dead"
	end
	if ctx.downed or ctx.plating then
		return false, "downed"
	end
	if ctx.state ~= STATES.Idle then
		return false, "in_transition"
	end
	if ctx.faction == FACTIONS.Police then
		return false, "already_police"
	end
	-- Na Fase 0 (Phase0AutoBandit), jogador entra Bandido e pode se alistar direto na delegacia
	local phase0StationRecruit = cfg.Phase0AutoBandit and ctx.faction == FACTIONS.Robber and ctx.atStation
	if ctx.faction ~= FACTIONS.Civil and not phase0StationRecruit then
		return false, "not_civil"
	end
	if ctx.now < ctx.switchCooldownUntil then
		return false, "switch_cooldown"
	end
	if ctx.inCombatUntil ~= nil and ctx.now < ctx.inCombatUntil then
		return false, "in_combat"
	end
	if ctx.secondsSinceCombat ~= nil and ctx.combatLockSeconds ~= nil and ctx.secondsSinceCombat < ctx.combatLockSeconds then
		return false, "in_combat"
	end
	if (ctx.wantedLevel or 0) > 0 then
		return false, "wanted"
	end
	if ctx.isRobbing == true then
		return false, "robbing"
	end
	if ctx.faction == FACTIONS.Robber then
		if (ctx.dirtyCash or 0) > 0 then
			return false, "dirty_cash"
		end
		if (ctx.stolenItemsCount or 0) > 0 then
			return false, "stolen_items"
		end
	end
	local withinInitialWindow = cfg.AllowInstantStartChoice
		and not ctx.usedInitialChoice
		and (ctx.now - ctx.joinedAt) <= cfg.InitialChoiceSeconds
	if not ctx.atStation and not withinInitialWindow then
		return false, "not_at_station"
	end
	local maxSlots = FactionRules.maxPoliceSlots(ctx.activePlayers, cfg)
	if ctx.policeCount >= maxSlots then
		return false, "police_full"
	end
	return true, nil
end

function FactionRules.canGoCivil(ctx: GoCivilContext, _config: RulesConfig?): (boolean, string?)
	if not ctx.alive then
		return false, "dead"
	end
	if ctx.downed or ctx.plating then
		return false, "downed"
	end
	if ctx.state ~= STATES.Idle then
		return false, "in_transition"
	end
	if ctx.faction == FACTIONS.Civil then
		return false, "already_civil"
	end
	if ctx.now < ctx.switchCooldownUntil then
		return false, "switch_cooldown"
	end
	if ctx.now < ctx.inCombatUntil then
		return false, "in_combat"
	end
	if ctx.secondsSinceCombat ~= nil and ctx.combatLockSeconds ~= nil and ctx.secondsSinceCombat < ctx.combatLockSeconds then
		return false, "in_combat"
	end
	if ctx.isRobbing == true then
		return false, "robbing"
	end
	if ctx.wantedLevel > 0 then
		return false, "wanted"
	end
	if ctx.faction == FACTIONS.Robber then
		if ctx.dirtyCash > 0 then
			return false, "dirty_cash"
		end
		if ctx.stolenItemsCount > 0 then
			return false, "stolen_items"
		end
	end
	return true, nil
end

-- Duração de canalização para retornar a Civil (0 = instantâneo na delegacia para Polícia)
function FactionRules.goCivilDuration(faction: string, atStation: boolean, config: RulesConfig?): number
	local cfg = cfgOf(config)
	if faction == FACTIONS.Police then
		return if atStation then 0 else cfg.EndShiftSeconds
	end
	return cfg.UnmaskSeconds
end

function FactionRules.shouldCancelTransitionOnDamage(state: string): boolean
	return state == STATES.Transforming or state == STATES.Unmasking
end

function FactionRules.shouldResetOnDeath(config: RulesConfig?): boolean
	local cfg = cfgOf(config)
	return cfg.ResetToCivilOnDeath and not cfg.Phase0CombatTest
end

-- Facção inicial padrão (Bandido enquanto Phase0AutoBandit=true; senão DefaultSpawnFaction)
function FactionRules.defaultSpawnFaction(config: RulesConfig?): string
	local cfg = cfgOf(config)
	return if cfg.Phase0AutoBandit then FACTIONS.Robber else cfg.DefaultSpawnFaction
end

-- Facção alvo ao resetar na morte (mantém jogador armado com Phase0AutoBandit=true)
function FactionRules.deathResetFaction(config: RulesConfig?): string
	return FactionRules.defaultSpawnFaction(config)
end

-- Facção destino ao encerrar plantão/desmascarar (Fase 0 sem civil jogável: Polícia volta a Bandido)
function FactionRules.goCivilTargetFaction(currentFaction: string, config: RulesConfig?): string
	local cfg = cfgOf(config)
	if cfg.Phase0AutoBandit and currentFaction == FACTIONS.Police then
		return FACTIONS.Robber
	end
	return FACTIONS.Civil
end

return FactionRules