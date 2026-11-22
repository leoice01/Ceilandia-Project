--!strict
-- Quem pode atacar quem e quem é aliado de quem. Usado pelo combate e pelo derrubado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)

local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions
local STATES = CombatContract.FactionStates

local Factions = {}

function Factions.defaultFaction(): string
	if FactionsConfig.Phase0AutoBandit then
		return FACTIONS.Robber
	end
	return FactionsConfig.DefaultSpawnFaction
end

function Factions.of(player: Player): string
	local faction = player:GetAttribute(ATTR.Faction)
	return if typeof(faction) == "string" then faction else Factions.defaultFaction()
end

function Factions.stateOf(player: Player): string
	local state = player:GetAttribute(ATTR.FactionState)
	return if typeof(state) == "string" then state else STATES.Idle
end

-- Só pode disparar/recarregar quem não é Civil e não está em transição de identidade
function Factions.canAttack(player: Player): boolean
	return Factions.of(player) ~= FACTIONS.Civil and Factions.stateOf(player) == STATES.Idle
end

local function gangOf(player: Player): string?
	local gang = player:GetAttribute(ATTR.Gang)
	return if typeof(gang) == "string" and gang ~= "" then gang else nil
end

-- Regra pura de dano por facção/estado: Civil Idle não ataca nem toma tiro;
-- Civil em Transforming fica vulnerável mas travado de atirar; Policia x Policia bloqueado.
function Factions.canFactionsDamage(
	attackerFaction: string,
	attackerState: string?,
	victimFaction: string?,
	victimState: string?
): boolean
	if attackerFaction == FACTIONS.Civil or (attackerState ~= nil and attackerState ~= STATES.Idle) then
		return false
	end
	if not victimFaction then
		return true
	end
	if victimFaction == FACTIONS.Civil and victimState ~= STATES.Transforming then
		return false
	end
	if attackerFaction == FACTIONS.Police and victimFaction == FACTIONS.Police then
		return false
	end
	return true
end

-- Civil não ataca nem toma tiro (exceto vulnerável durante Transforming);
-- policial não acerta policial; bandido acerta bandido. victim nil = NPC/dummy.
function Factions.canDamage(attacker: Player, victim: Player?): boolean
	if not Factions.canAttack(attacker) then
		return false
	end
	if not victim then
		return true
	end
	if victim == attacker then
		return false
	end
	return Factions.canFactionsDamage(
		Factions.of(attacker),
		Factions.stateOf(attacker),
		Factions.of(victim),
		Factions.stateOf(victim)
	)
end

-- Pode reviver: policial revive policial; mesma gang; ou Bandido sem gang na Fase 0.
-- Civil nunca é aliado de ninguém (não participa de combate/revive).
function Factions.areAllies(a: Player, b: Player): boolean
	if a == b then
		return false
	end
	local factionA, factionB = Factions.of(a), Factions.of(b)
	if factionA == FACTIONS.Civil or factionB == FACTIONS.Civil then
		return false
	end
	if factionA == FACTIONS.Police and factionB == FACTIONS.Police then
		return true
	end
	local gangA, gangB = gangOf(a), gangOf(b)
	if gangA ~= nil and gangA == gangB then
		return true
	end
	return FactionsConfig.Phase0BanditsAreAllies == true
		and factionA == FACTIONS.Robber
		and factionB == FACTIONS.Robber
		and gangA == nil
		and gangB == nil
end

-- Só inimigo finaliza (prompt ou tiro em derrubado); victim nil = NPC/dummy.
function Factions.canFinish(attacker: Player, victim: Player?): boolean
	if not Factions.canDamage(attacker, victim) then
		return false
	end
	if victim and Factions.areAllies(attacker, victim) then
		return false
	end
	return true
end

return Factions