--!strict
-- Contas de dano puras (sem tocar em instâncias), para dar pra testar isoladas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

export type Region = "Head" | "Torso" | "Limb"

local TORSO_PARTS: { [string]: boolean } = {
	Torso = true, -- R6
	UpperTorso = true, -- R15
	LowerTorso = true,
	HumanoidRootPart = true,
}

local Damage = {}

function Damage.regionOf(partName: string): Region
	if partName == "Head" then
		return "Head"
	end
	if TORSO_PARTS[partName] then
		return "Torso"
	end
	return "Limb"
end

-- 1 até FalloffStart, cai linear até FalloffMinMultiplier em FalloffEnd
function Damage.falloff(distance: number, startDistance: number, endDistance: number, minMultiplier: number): number
	local cleanMin = if minMultiplier == minMultiplier and math.abs(minMultiplier) < math.huge
		then math.clamp(minMultiplier, 0, 1)
		else 1
	if distance ~= distance then
		return cleanMin
	end
	if startDistance ~= startDistance or endDistance ~= endDistance then
		return cleanMin
	end
	if distance <= startDistance then
		return 1
	end
	if distance >= endDistance or endDistance <= startDistance then
		return cleanMin
	end
	local alpha = math.clamp((distance - startDistance) / (endDistance - startDistance), 0, 1)
	return 1 + (cleanMin - 1) * alpha
end

-- Dano antes da armadura
function Damage.compute(weapon: Weapons.WeaponConfig, region: Region, distance: number): number
	local multiplier = if region == "Head"
		then weapon.HeadshotMultiplier
		elseif region == "Torso" then weapon.TorsoMultiplier
		else weapon.LimbMultiplier
	local falloff = Damage.falloff(distance, weapon.FalloffStart, weapon.FalloffEnd, weapon.FalloffMinMultiplier)
	local raw = weapon.Damage * multiplier * falloff
	if raw ~= raw or raw < 0 or math.abs(raw) == math.huge then
		return 0
	end
	return raw
end

-- A armadura absorve tudo que puder antes da vida (estilo placas).
-- Retorna a armadura que sobrou e o dano que passa para a vida.
function Damage.absorb(armor: number, damage: number): (number, number)
	local cleanArmor = if armor == armor and math.abs(armor) < math.huge then math.max(armor, 0) else 0
	local cleanDamage = if damage == damage and math.abs(damage) < math.huge then math.max(damage, 0) else 0
	local absorbed = math.min(cleanArmor, cleanDamage)
	return cleanArmor - absorbed, cleanDamage - absorbed
end

return Damage