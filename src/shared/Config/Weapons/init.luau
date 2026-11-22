--!strict
-- Índice das armas: junta os padrões da categoria (Categories) com cada arma de List/,
-- confere os campos e devolve { [WeaponId] = WeaponConfig }.
-- Nova arma = um ModuleScript novo em List/ com WeaponId, WeaponType e o que muda.
-- Os números são da P4 (Design); o código só lê daqui.

export type WeaponType = "Pistol" | "SMG" | "AssaultRifle" | "Shotgun" | "Sniper"
export type Slot = "Primary" | "Secondary"
export type FireMode = "Auto" | "Semi"
export type PoseSet = "Rifle" | "Pistol"

export type SpreadConfig = {
	Base: number, -- cone de dispersão sem mirar, parado (graus)
	PerShot: number, -- quanto o cone abre a cada tiro seguido (graus)
	Max: number, -- abertura extra máxima por tiros seguidos (graus)
	Recovery: number, -- quanto a abertura extra fecha por segundo (graus/s)
	MovingMultiplier: number, -- andando
	AirMultiplier: number, -- no ar
	CrouchMultiplier: number, -- agachado
}

export type RecoilProfile = {
	Vertical: number, -- graus para cima por tiro
	Horizontal: number, -- graus para o lado por tiro (multiplica o Pattern)
	Variance: number, -- tremido aleatório pequeno (fração do recuo, 0..1)
}

export type RecoilConfig = {
	Hip: RecoilProfile,
	ADS: RecoilProfile,
	Pattern: { number }, -- lado de cada tiro seguido (-1 esquerda .. 1 direita); repete
	ClimbPerShot: number, -- cada tiro seguido sobe um pouco mais (fração)
	ClimbMaxShots: number, -- até quantos tiros o recuo continua crescendo
	KickSpeed: number, -- quão rápido a câmera chega no recuo (1/s); sem tranco seco
	RecoveryDelay: number, -- s sem atirar até a mira voltar
	RecoverySpeed: number, -- velocidade da volta (1/s)
	GunKick: number, -- coice visual da arma para trás (studs)
}

export type WeaponConfig = {
	WeaponId: string,
	DisplayName: string,
	WeaponType: WeaponType,
	Slot: Slot,
	FireMode: FireMode,
	PoseSet: PoseSet,
	Damage: number, -- por projétil (escopeta: por chumbo), no tronco, a curta distância
	Pellets: number, -- projéteis por tiro (escopeta > 1)
	PelletSpread: number, -- cone fixo dos chumbos (graus)
	RPM: number, -- tiros por minuto
	FireInterval: number, -- calculado: segundos entre tiros
	MagazineSize: number,
	ReserveAmmo: number, -- munição extra ao nascer
	ReloadTime: number, -- s
	EquipTime: number, -- s do saque até poder atirar
	Range: number, -- alcance máximo (studs)
	FalloffStart: number, -- a partir daqui o dano cai (studs)
	FalloffEnd: number, -- a partir daqui o dano fica no mínimo (studs)
	FalloffMinMultiplier: number,
	HeadshotMultiplier: number,
	TorsoMultiplier: number,
	LimbMultiplier: number,
	HipFireAccuracy: number, -- 0..1
	ADSAccuracy: number, -- 0..1
	Spread: SpreadConfig,
	Recoil: RecoilConfig,
	AdsFov: number,
	AdsTime: number, -- s para entrar na mira
}

local WEAPON_TYPES: { [string]: boolean } = { Pistol = true, SMG = true, AssaultRifle = true, Shotgun = true, Sniper = true }
local SLOTS: { [string]: boolean } = { Primary = true, Secondary = true }
local FIRE_MODES: { [string]: boolean } = { Auto = true, Semi = true }
local POSE_SETS: { [string]: boolean } = { Rifle = true, Pistol = true }
local POSITIVE_FIELDS = { "Damage", "RPM", "MagazineSize", "ReloadTime", "Range", "AdsFov", "AdsTime", "Pellets" }
local NON_NEGATIVE_FIELDS = {
	"ReserveAmmo", "EquipTime", "FalloffStart", "FalloffEnd", "FalloffMinMultiplier", "HeadshotMultiplier",
	"TorsoMultiplier", "LimbMultiplier", "PelletSpread",
}
local UNIT_FIELDS = { "HipFireAccuracy", "ADSAccuracy" }

local Categories = require(script.Categories) :: { [string]: { [string]: any } }

-- Cópia profunda de base com override por cima (tabelas de chave string se fundem;
-- listas, como Pattern, são trocadas inteiras)
local function merge(base: { [any]: any }, override: { [any]: any }): { [any]: any }
	local out: { [any]: any } = {}
	for k, v in base do
		out[k] = if type(v) == "table" then merge(v, {}) else v
	end
	for k, v in override do
		local current = out[k]
		if type(v) == "table" and type(current) == "table" and #v == 0 then
			out[k] = merge(current, v)
		elseif type(v) == "table" then
			out[k] = merge(v, {})
		else
			out[k] = v
		end
	end
	return out
end

local function check(ok: boolean, weaponId: string, message: string)
	if not ok then
		error(("[Weapons] %s: %s"):format(weaponId, message), 0)
	end
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end

local function validate(w: { [string]: any })
	local id = tostring(w.WeaponId)
	check(type(w.WeaponId) == "string" and #w.WeaponId > 0 and #w.WeaponId <= 32, id, "WeaponId inválido")
	check(type(w.DisplayName) == "string", id, "DisplayName faltando")
	check(WEAPON_TYPES[w.WeaponType] == true, id, "WeaponType inválido")
	check(SLOTS[w.Slot] == true, id, "Slot inválido")
	check(FIRE_MODES[w.FireMode] == true, id, "FireMode inválido")
	check(POSE_SETS[w.PoseSet] == true, id, "PoseSet inválido")
	for _, field in POSITIVE_FIELDS do
		check(isNumber(w[field]) and w[field] > 0, id, field .. " precisa ser número > 0")
	end
	for _, field in NON_NEGATIVE_FIELDS do
		check(isNumber(w[field]) and w[field] >= 0, id, field .. " precisa ser número >= 0")
	end
	for _, field in UNIT_FIELDS do
		check(isNumber(w[field]) and w[field] >= 0 and w[field] <= 1, id, field .. " precisa estar entre 0 e 1")
	end
	check(w.FalloffEnd >= w.FalloffStart, id, "FalloffEnd menor que FalloffStart")
	check(w.Pellets == math.floor(w.Pellets), id, "Pellets precisa ser inteiro")
	check(type(w.Spread) == "table", id, "Spread faltando")
	for _, field in { "Base", "PerShot", "Max", "Recovery", "MovingMultiplier", "AirMultiplier", "CrouchMultiplier" } do
		check(isNumber(w.Spread[field]) and w.Spread[field] >= 0, id, "Spread." .. field .. " inválido")
	end
	local recoil = w.Recoil
	check(type(recoil) == "table", id, "Recoil faltando")
	for _, mode in { "Hip", "ADS" } do
		check(type(recoil[mode]) == "table", id, "Recoil." .. mode .. " faltando")
		for _, field in { "Vertical", "Horizontal", "Variance" } do
			check(isNumber(recoil[mode][field]) and recoil[mode][field] >= 0, id, ("Recoil.%s.%s inválido"):format(mode, field))
		end
	end
	check(type(recoil.Pattern) == "table" and #recoil.Pattern > 0, id, "Recoil.Pattern vazio")
	for _, field in { "ClimbPerShot", "ClimbMaxShots", "KickSpeed", "RecoveryDelay", "RecoverySpeed", "GunKick" } do
		check(isNumber(recoil[field]) and recoil[field] >= 0, id, "Recoil." .. field .. " inválido")
	end
end

local Weapons: { [string]: WeaponConfig } = {}

for _, module in script.List:GetChildren() do
	if module:IsA("ModuleScript") then
		local raw = (require :: any)(module) :: { [string]: any }
		local category = Categories[raw.WeaponType]
		check(category ~= nil, module.Name, "categoria desconhecida " .. tostring(raw.WeaponType))
		local weapon = merge(category, raw)
		weapon.FireInterval = if isNumber(weapon.RPM) and weapon.RPM > 0 then 60 / weapon.RPM else 0
		validate(weapon)
		check(Weapons[weapon.WeaponId] == nil, weapon.WeaponId, "WeaponId repetido")
		Weapons[weapon.WeaponId] = table.freeze(weapon) :: any
	end
end

return Weapons
