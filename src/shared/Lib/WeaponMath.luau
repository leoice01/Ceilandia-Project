--!strict
-- Contas de arma usadas no cliente e no servidor (sem regra de jogo nem números de balanceamento).

local WeaponMath = {}

local TAU = math.pi * 2

export type SpreadState = {
	aiming: boolean,
	moving: boolean,
	airborne: boolean,
	crouching: boolean,
	bloom: number, -- abertura extra por tiros seguidos (graus)
}

-- Direção dentro de um cone de diâmetro coneDeg em volta de dir. u e v em [0, 1):
-- u = distância do centro (sqrt = espalhado por igual no disco), v = ângulo em volta.
function WeaponMath.coneDirection(dir: Vector3, coneDeg: number, u: number, v: number): Vector3
	local unit = dir.Unit
	if coneDeg <= 0 then
		return unit
	end
	local radius = math.sqrt(u) * math.rad(coneDeg) * 0.5
	local frame = CFrame.lookAt(Vector3.zero, unit)
	return (frame * CFrame.Angles(0, 0, v * TAU) * CFrame.Angles(radius, 0, 0)).LookVector
end

-- Chumbos da escopeta em padrão FIXO (o mesmo no cliente e no servidor, sem sorteio):
-- um no centro e o resto em volta, alternando anel de dentro e de fora.
function WeaponMath.pelletDirections(dir: Vector3, count: number, coneDeg: number): { Vector3 }
	local unit = dir.Unit
	local out = { unit }
	if count <= 1 or coneDeg <= 0 then
		for _ = 2, count do
			table.insert(out, unit)
		end
		return out
	end
	local frame = CFrame.lookAt(Vector3.zero, unit)
	local half = math.rad(coneDeg) * 0.5
	local around = count - 1
	for k = 1, around do
		local angle = (k - 1) / around * TAU
		local radius = if k % 2 == 0 then half else half * 0.55
		table.insert(out, (frame * CFrame.Angles(0, 0, angle) * CFrame.Angles(radius, 0, 0)).LookVector)
	end
	return out
end

-- Cone de dispersão atual (graus) a partir da config da arma e do estado do jogador
function WeaponMath.currentSpread(
	spread: { Base: number, MovingMultiplier: number, AirMultiplier: number, CrouchMultiplier: number },
	hipAccuracy: number,
	adsAccuracy: number,
	state: SpreadState
): number
	local accuracy = if state.aiming then adsAccuracy else hipAccuracy
	local cone = (spread.Base + state.bloom) * (1 - accuracy)
	if state.airborne then
		cone *= spread.AirMultiplier
	elseif state.moving then
		cone *= spread.MovingMultiplier
	end
	if state.crouching then
		cone *= spread.CrouchMultiplier
	end
	return cone
end

return WeaponMath
