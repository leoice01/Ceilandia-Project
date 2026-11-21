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
	if distance <= startDistance then
		return 1
	end
	if distance >= endDistance or endDistance <= startDistance then
		return minMultiplier
	end
	local alpha = (distance - startDistance) / (endDistance - startDistance)
	return 1 + (minMultiplier - 1) * alpha
end

-- Dano antes da armadura
function Damage.compute(weapon: Weapons.WeaponConfig, region: Region, distance: number): number
	local multiplier = if region == "Head"
		then weapon.HeadMultiplier
		elseif region == "Torso" then weapon.TorsoMultiplier
		else weapon.LimbMultiplier
	local falloff = Damage.falloff(distance, weapon.FalloffStart, weapon.FalloffEnd, weapon.FalloffMinMultiplier)
	return weapon.Damage * multiplier * falloff
end

-- A armadura absorve tudo que puder antes da vida (estilo placas).
-- Retorna a armadura que sobrou e o dano que passa para a vida.
function Damage.absorb(armor: number, damage: number): (number, number)
	local absorbed = math.min(math.max(armor, 0), damage)
	return armor - absorbed, damage - absorbed
end

return Damage
