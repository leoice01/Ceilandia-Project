--!strict
-- Contrato de rede do combate entre o cliente (P1) e o servidor (P2).
-- Mudou nome de remote, campo ou ordem de argumento aqui = combinar com a P1 antes.
--
-- Cliente -> servidor
--   CombatFire(payload: FirePayload)  tiro; o cliente já mostrou o feedback local
--   CombatReload()                    pedido de recarga
--   ArmorInsertPlate()                pedido de colocar UMA placa no colete; para encher
--                                     o colete, o cliente manda de novo quando Plating sumir
-- Servidor -> cliente
--   CombatHit(region: HitRegion, result: HitResult, armor: ArmorHit,
--             armorDamage: number, healthDamage: number, hitPos: Vector3)
--       só para quem atirou: confirma o acerto (hitmarker real). armor diz se bateu
--       na armadura e se quebrou uma placa; armorDamage/healthDamage = quanto foi para
--       a armadura e para a vida (números de dano); hitPos = onde o tiro bateu
--   CombatFX(shooter: Player, weaponId: string, origin: Vector3, hitPos: Vector3)
--       para os outros jogadores por perto: desenhar rastro e impacto
--   CombatFeed(kind: FeedKind, actor: Player?, victimName: string)
--       para todos: kill feed (actor = quem derrubou/finalizou/reviveu; nil = sangrou)
--
-- Atributos que só o servidor escreve:
--   Player.Faction (string)        "Civil" | "Policia" | "Bandido"; sem atributo = DefaultFaction
--   Player.Gang (string)           nome da gang; mesma gang = pode reviver
--   Player.PlatesCarried (number)  placas extras na mochila
--   Character.ArmorVest (number)   armadura do colete (placas × PlateHealth); absorve antes da vida
--   Character.ArmorVestMax (number) armadura máxima do colete (para a barra no HUD)
--   Character.Plating (boolean)    colocando placa agora (não atira)
--   Character.ArmorHelmet (number) capacete: absorve dano na cabeça, antes do colete
--   Character.Downed (boolean)     derrubado: rasteja, não atira; Humanoid.Health = sangue que resta
--   Model.Downable (boolean)       NPC/dummy que cai derrubado em vez de morrer (jogadores sempre caem)
--   Tool.Weapon (string), Tool.Ammo (number), Tool.Reloading (boolean)
--
-- Interação (ProximityPrompt criado pelo servidor na HumanoidRootPart de quem está derrubado):
--   "Revive" (aliado segura E / ButtonX) e "Finish" (inimigo segura F / ButtonY). O cliente pode esconder o prompt
--   que não se aplica ao jogador, mas quem decide é o servidor.
-- Caixa de placas: qualquer BasePart com a tag "ArmorCrate" (CollectionService) ganha um
--   ProximityPrompt "ArmorCrate" (E) que enche as placas da mochila.

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
-- "None" = sem armadura; "Hit" = armadura absorveu; "Broken" = uma placa (ou o capacete) quebrou
export type ArmorHit = "None" | "Hit" | "Broken"

local MAX_WEAPON_ID_LENGTH = 32
local FIRE_PAYLOAD_FIELDS = 4

local CombatContract = {
	Remotes = {
		Fire = "CombatFire",
		Reload = "CombatReload",
		Hit = "CombatHit",
		FX = "CombatFX",
		Feed = "CombatFeed",
		InsertPlate = "ArmorInsertPlate",
	},
	Prompts = {
		Revive = "Revive",
		Finish = "Finish",
		ArmorCrate = "ArmorCrate",
	},
	Tags = {
		ArmorCrate = "ArmorCrate",
	},
	-- Item de colocar placa: Tool criada pelo servidor na mochila a cada spawn.
	-- O cliente manda ArmorInsertPlate ao clicar (segurando = enche o colete).
	PlateItem = {
		Name = "Placas",
		Attribute = "PlateItem",
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
		VestMax = "ArmorVestMax",
		Plating = "Plating",
		PlatesCarried = "PlatesCarried",
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
