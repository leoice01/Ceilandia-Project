--!strict
-- Armas. PROVISÓRIO: valores da M4A1 copiados do legado ReplicatedStorage.Weapons.Config;
-- multiplicadores por região e queda de dano chutados pela P2. A P4 ajusta.

export type WeaponConfig = {
	Damage: number, -- dano base no tronco a curta distância
	FireRate: number, -- segundos entre tiros
	Range: number, -- alcance máximo (studs)
	MagSize: number,
	ReloadTime: number, -- segundos
	HeadMultiplier: number,
	TorsoMultiplier: number,
	LimbMultiplier: number,
	FalloffStart: number, -- a partir dessa distância o dano começa a cair (studs)
	FalloffEnd: number, -- a partir dessa distância o dano fica no mínimo (studs)
	FalloffMinMultiplier: number, -- dano mínimo = Damage * isto
	-- Usados pelo cliente (P1)
	Spread: number, -- graus
	Recoil: number, -- graus
	AdsSpreadMultiplier: number,
	AdsFov: number,
}

local Weapons: { [string]: WeaponConfig } = {
	M4A1 = {
		Damage = 22,
		FireRate = 0.08,
		Range = 600,
		MagSize = 30,
		ReloadTime = 2.2,
		HeadMultiplier = 2,
		TorsoMultiplier = 1,
		LimbMultiplier = 0.75,
		FalloffStart = 120,
		FalloffEnd = 400,
		FalloffMinMultiplier = 0.6,
		Spread = 0.8,
		Recoil = 0.6,
		AdsSpreadMultiplier = 0.25,
		AdsFov = 50,
	},
}

return Weapons
