--!strict
-- Quem pode atacar quem e quem é aliado de quem. Usado pelo combate e pelo derrubado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)

local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions

local Factions = {}

function Factions.of(player: Player): string
	local faction = player:GetAttribute(ATTR.Faction)
	return if typeof(faction) == "string" then faction else CombatContract.DefaultFaction
end

local function gangOf(player: Player): string?
	local gang = player:GetAttribute(ATTR.Gang)
	return if typeof(gang) == "string" and gang ~= "" then gang else nil
end

-- Civil não ataca nem toma tiro; policial não acerta policial; bandido acerta bandido.
-- victim nil = NPC/dummy.
function Factions.canDamage(attacker: Player, victim: Player?): boolean
	if Factions.of(attacker) == FACTIONS.Civil then
		return false
	end
	if not victim then
		return true
	end
	if victim == attacker then
		return false
	end
	local victimFaction = Factions.of(victim)
	if victimFaction == FACTIONS.Civil then
		return false
	end
	if Factions.of(attacker) == FACTIONS.Police and victimFaction == FACTIONS.Police then
		return false
	end
	return true
end

-- Pode reviver: policial revive policial; bandido revive quem é da mesma gang.
function Factions.areAllies(a: Player, b: Player): boolean
	if a == b then
		return false
	end
	local factionA, factionB = Factions.of(a), Factions.of(b)
	if factionA == FACTIONS.Police and factionB == FACTIONS.Police then
		return true
	end
	local gangA, gangB = gangOf(a), gangOf(b)
	return gangA ~= nil and gangA == gangB
end

return Factions
