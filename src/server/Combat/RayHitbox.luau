--!strict
-- Teste puro de interseção raio x caixa orientada (slab), sem closures no caminho quente.

local EPSILON = 1e-9

local RayHitbox = {}

local function slabAxis(
	oAxis: number,
	dAxis: number,
	halfAxis: number,
	tMin: number,
	tMax: number
): (boolean, number, number)
	if math.abs(dAxis) < EPSILON then
		return math.abs(oAxis) <= halfAxis, tMin, tMax
	end
	local inv = 1 / dAxis
	local t1 = (-halfAxis - oAxis) * inv
	local t2 = (halfAxis - oAxis) * inv
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	local nextMin = if t1 > tMin then t1 else tMin
	local nextMax = if t2 < tMax then t2 else tMax
	return nextMin <= nextMax, nextMin, nextMax
end

-- ray é o vetor inteiro do segmento (direção unitária * alcance).
-- Retorna a fração [0, 1] onde o raio entra na caixa, ou nil.
function RayHitbox.rayBoxFraction(cf: CFrame, size: Vector3, origin: Vector3, ray: Vector3): number?
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(ray)
	local half = size * 0.5

	local ok, tMin, tMax = slabAxis(o.X, d.X, half.X, 0, 1)
	if not ok then
		return nil
	end
	ok, tMin, tMax = slabAxis(o.Y, d.Y, half.Y, tMin, tMax)
	if not ok then
		return nil
	end
	ok, tMin, tMax = slabAxis(o.Z, d.Z, half.Z, tMin, tMax)
	return if ok then tMin else nil
end

return RayHitbox