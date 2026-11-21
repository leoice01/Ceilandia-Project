--!strict
-- Contrato de rede do combate entre o cliente (P1) e o servidor (P2).
-- Mudou nome de remote, campo ou ordem de argumento aqui = combinar com a P1 antes.
--
-- Cliente -> servidor
--   CombatFire(payload: FirePayload)  tiro; o cliente já mostrou o feedback local
--   CombatReload()                    pedido de recarga
-- Servidor -> cliente
--   CombatHit(region: HitRegion, result: HitResult, armorHit: boolean)
--       só para quem atirou: confirma o acerto (hitmarker real)
--   CombatFX(shooter: Player, weaponId: string, origin: Vector3, hitPos: Vector3)
--       para os outros jogadores por perto: desenhar rastro e impacto
--   CombatFeed(kind: FeedKind, actor: Player?, victimName: string)
--       para todos: kill feed (actor = quem derrubou/finalizou/reviveu; nil = sangrou)
--
-- Atributos que só o servidor escreve:
--   Player.Faction (string)        "Civil" | "Policia" | "Bandido"; sem atributo = DefaultFaction
--   Player.Gang (string)           nome da gang; mesma gang = pode reviver
--   Character.ArmorVest (number)   colete: absorve dano no tronco
--   Character.ArmorHelmet (number) capacete: absorve dano na cabeça
--   Character.Downed (boolean)     derrubado: rasteja, não atira; Humanoid.Health = sangue que resta
--   Model.Downable (boolean)       NPC/dummy que cai derrubado em vez de morrer (jogadores sempre caem)
--   Tool.Weapon (string), Tool.Ammo (number), Tool.Reloading (boolean)
--
-- Interação (ProximityPrompt criado pelo servidor na HumanoidRootPart de quem está derrubado):
--   "Revive" (aliado segura E / ButtonX) e "Finish" (inimigo segura F / ButtonY). O cliente pode esconder o prompt
--   que não se aplica ao jogador, mas quem decide é o servidor.

local Net = require(script.Parent.Net)

export type FirePayload = {
	origin: Vector3, -- de onde o tiro sai (perto da cabeça/ombro)
	direction: Vector3, -- vetor unitário da mira
	timestamp: number, -- workspace:GetServerTimeNow() no cliente na hora do tiro
	weaponId: string, -- atributo Weapon da Tool equipada
}

export type HitRegion = "Head" | "Torso" | "Limb"
export type HitResult = "Hit" | "Downed" | "Killed"
export type FeedKind = "Downed" | "Finished" | "BledOut" | "Revived"

local MAX_WEAPON_ID_LENGTH = 32
local FIRE_PAYLOAD_FIELDS = 4

local CombatContract = {
	Remotes = {
		Fire = "CombatFire",
		Reload = "CombatReload",
		Hit = "CombatHit",
		FX = "CombatFX",
		Feed = "CombatFeed",
	},
	Prompts = {
		Revive = "Revive",
		Finish = "Finish",
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
		Gang = "Gang",
		Downable = "Downable",
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
