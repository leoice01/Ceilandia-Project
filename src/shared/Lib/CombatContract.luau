--!strict
-- Contrato de rede do combate entre o cliente (P1) e o servidor (P2).
-- Mudou nome de remote, campo ou ordem de argumento aqui = combinar com a P1 antes.
--
-- Cliente -> servidor
--   CombatFire(payload: FirePayload)  tiro; o cliente já mostrou o feedback local
--   CombatReload()                    pedido de recarga
--   ArmorInsertPlate()                pedido de colocar UMA placa no colete; para encher
--                                     o colete, o cliente manda de novo quando Plating sumir
--   GrenadeThrow(direction: Vector3)  lançar a granada equipada na direção (vetor unitário)
--   FactionRequest(payload: FactionRequestPayload)
--                                     pedido de troca/cancelamento de lado (MaskUp, JoinPolice, GoCivil, Cancel)
-- Servidor -> cliente
--   CombatHit(region: HitRegion, result: HitResult, armor: ArmorHit,
--             armorDamage: number, healthDamage: number, hitPos: Vector3)
--       só para quem atirou: confirma o acerto (hitmarker real). armor diz se bateu
--       na armadura e se quebrou uma placa; armorDamage/healthDamage = quanto foi para
--       a armadura e para a vida (números de dano); hitPos = onde o tiro bateu
--   CombatFX(shooter: Player, weaponId: string, origin: Vector3, hitPositions: { Vector3 })
--       para os outros jogadores por perto: desenhar rastro e impacto (um por chumbo)
--   CombatFeed(kind: FeedKind, actor: Player?, victimName: string)
--       para todos: kill feed (actor = quem derrubou/finalizou/reviveu; nil = sangrou)
--   CombatDamaged(sourcePos: Vector3, amount: number)
--       só para quem levou dano: de onde veio (indicador de direção do dano)
--   FactionStateChanged(player: Player, faction: string, state: string, duration: number?, reason: string?)
--       para todos (mudança de estado) ou só para o solicitante (motivo de recusa)
--   FactionTransformFX(player: Player, kind: FactionTransformKind, duration: number)
--       para jogadores próximos (LOD por raio): efeito de máscara / desmascarar

local Net = require(script.Parent.Net)
local FactionsConfig = require(script.Parent.Parent.Config.Factions)

export type FirePayload = {
	origin: Vector3, -- de onde o tiro sai (perto da cabeça/ombro)
	direction: Vector3, -- vetor unitário da mira
	timestamp: number, -- workspace:GetServerTimeNow() no cliente na hora do tiro
	weaponId: string, -- atributo Weapon da Tool equipada
	seq: number, -- número do tiro, sempre crescente por jogador (evita contar o mesmo tiro duas vezes)
}

export type HitRegion = "Head" | "Torso" | "Limb"
export type HitResult = "Hit" | "Downed" | "Killed"
export type FeedKind = "Downed" | "Finished" | "BledOut" | "Revived"
-- "None" = sem armadura; "Hit" = armadura absorveu; "Broken" = uma placa (ou o capacete) quebrou
export type ArmorHit = "None" | "Hit" | "Broken"
export type FactionAction = "MaskUp" | "JoinPolice" | "GoCivil" | "Cancel"
export type FactionState = "Idle" | "Transforming" | "Unmasking"
export type FactionTransformKind = "MaskUp" | "Unmask"
export type FactionRequestPayload = {
	action: FactionAction,
}

local MAX_WEAPON_ID_LENGTH = 32
local FIRE_PAYLOAD_FIELDS = 5
local MAX_SEQ = 2 ^ 31
local FACTION_REQUEST_FIELDS = 1
local VALID_FACTION_ACTIONS: { [string]: boolean } = {
	MaskUp = true,
	JoinPolice = true,
	GoCivil = true,
	Cancel = true,
}

local CombatContract = {
	Remotes = {
		Fire = "CombatFire",
		Reload = "CombatReload",
		Hit = "CombatHit",
		FX = "CombatFX",
		Feed = "CombatFeed",
		Damaged = "CombatDamaged",
		InsertPlate = "ArmorInsertPlate",
		GrenadeThrow = "GrenadeThrow",
		FactionRequest = "FactionRequest",
		FactionStateChanged = "FactionStateChanged",
		FactionTransformFX = "FactionTransformFX",
	},
	Prompts = {
		Revive = "Revive",
		Finish = "Finish",
		ArmorCrate = "ArmorCrate",
		PoliceStation = "PoliceStation",
	},
	Tags = {
		ArmorCrate = "ArmorCrate",
		PoliceStation = "PoliceStation",
	},
	PlateItem = {
		Name = "Placas",
		Attribute = "PlateItem",
	},
	GrenadeItem = {
		Name = "Granada",
		Attribute = "GrenadeItem",
		CountAttribute = "GrenadesCarried",
	},
	Factions = {
		Civil = "Civil",
		Police = "Policia",
		Robber = "Bandido",
	},
	FactionStates = {
		Idle = "Idle",
		Transforming = "Transforming",
		Unmasking = "Unmasking",
	},
	-- Facção padrão controlada por Shared.Config.Factions
	DefaultFaction = if FactionsConfig.Phase0AutoBandit then "Bandido" else FactionsConfig.DefaultSpawnFaction,
	Attributes = {
		Faction = "Faction",
		FactionState = "FactionState",
		InCombatUntil = "InCombatUntil",
		WantedLevel = "WantedLevel",
		DirtyCash = "DirtyCash",
		StolenItemsCount = "StolenItemsCount",
		PoliceBonusMultiplier = "PoliceBonusMultiplier",
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
		Reserve = "Reserve",
		Slot = "Slot",
	},
}

-- Confere formato e tipos do payload de tiro (não confere regra de jogo)
function CombatContract.validateFire(...: any): (boolean, string?)
	if select("#", ...) ~= 1 then
		return false, "unexpected_args"
	end
	local payload = ...
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
	local seq = payload.seq
	if not Net.isFiniteNumber(seq) or seq ~= math.floor(seq) or seq < 0 or seq > MAX_SEQ then
		return false, "bad_seq"
	end
	return true, nil
end

-- Confere formato e ação válida do pedido de escolha de lado
function CombatContract.validateFactionRequest(payload: any, ...: any): (boolean, string?)
	if select("#", ...) ~= 0 then
		return false, "unexpected_args"
	end
	if typeof(payload) ~= "table" then
		return false, "payload_not_table"
	end
	local fields = 0
	for _ in payload do
		fields += 1
		if fields > FACTION_REQUEST_FIELDS then
			return false, "payload_extra_fields"
		end
	end
	local action = payload.action
	if typeof(action) ~= "string" or not VALID_FACTION_ACTIONS[action] then
		return false, "bad_action"
	end
	return true, nil
end

return CombatContract