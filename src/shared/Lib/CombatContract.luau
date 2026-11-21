--!strict
-- Contrato de rede do combate entre o cliente (P1) e o servidor (P2).
-- Mudou nome de remote, campo ou ordem de argumento aqui = combinar com a P1 antes.
--
-- Cliente -> servidor
--   CombatFire(payload: FirePayload)  tiro; o cliente já mostrou o feedback local
--   CombatReload()                    pedido de recarga
-- Servidor -> cliente
--   CombatHit(region: HitRegion, lethal: boolean, armorHit: boolean)
--       só para quem atirou: confirma o acerto (hitmarker real)
--   CombatFX(shooter: Player, weaponId: string, origin: Vector3, hitPos: Vector3)
--       para os outros jogadores por perto: desenhar rastro e impacto
--
-- Atributos que só o servidor escreve:
--   Player.Faction (string)        "Civil" | "Policia" | "Bandido"; sem atributo = DefaultFaction
--   Character.ArmorVest (number)   colete: absorve dano no tronco
--   Character.ArmorHelmet (number) capacete: absorve dano na cabeça
--   Character.Downed (boolean)     derrubado (sistema de derrubado, tarefa separada)
--   Tool.Weapon (string), Tool.Ammo (number), Tool.Reloading (boolean)

local Net = require(script.Parent.Net)

export type FirePayload = {
	origin: Vector3, -- de onde o tiro sai (perto da cabeça/ombro)
	direction: Vector3, -- vetor unitário da mira
	timestamp: number, -- workspace:GetServerTimeNow() no cliente na hora do tiro
	weaponId: string, -- atributo Weapon da Tool equipada
}

export type HitRegion = "Head" | "Torso" | "Limb"

local MAX_WEAPON_ID_LENGTH = 32
local FIRE_PAYLOAD_FIELDS = 4

local CombatContract = {
	Remotes = {
		Fire = "CombatFire",
		Reload = "CombatReload",
		Hit = "CombatHit",
		FX = "CombatFX",
	},
	Factions = {
		Civil = "Civil",
		Police = "Policia",
		Robber = "Bandido",
	},
	-- Na Fase 0 todo mundo sem facção pode trocar tiro
	DefaultFaction = "Bandido",
	Attributes = {
		Faction = "Faction",
		Vest = "ArmorVest",
		Helmet = "ArmorHelmet",
		Downed = "Downed",
		Weapon = "Weapon",
		Ammo = "Ammo",
		Reloading = "Reloading",
	},
}

-- Confere formato e tipos do payload de tiro (não confere regra de jogo)
function CombatContract.validateFire(payload: any): (boolean, string?)
	if typeof(payload) ~= "table" then
		return false, "payload_not_table"
	end
	local fields = 0
	for _ in payload do
		fields += 1
		if fields > FIRE_PAYLOAD_FIELDS then
			return false, "payload_extra_fields"
		end
	end
	if not Net.isFiniteVector3(payload.origin) then
		return false, "bad_origin"
	end
	if not Net.isFiniteVector3(payload.direction) then
		return false, "bad_direction"
	end
	local length = (payload.direction :: Vector3).Magnitude
	if length < 0.5 or length > 1.5 then
		return false, "direction_not_unit"
	end
	if not Net.isFiniteNumber(payload.timestamp) then
		return false, "bad_timestamp"
	end
	if not Net.isShortString(payload.weaponId, MAX_WEAPON_ID_LENGTH) then
		return false, "bad_weapon_id"
	end
	return true, nil
end

return CombatContract
