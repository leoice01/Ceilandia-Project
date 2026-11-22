--!strict
-- Validação de origem, raycast de mundo (ignorando NPCs mortos e acessórios/peças não-corpo)
-- e detecção de acerto contra jogadores com broadphase e lag compensation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local LagCompensation = require(script.Parent.LagCompensation)

export type HitResolution = {
	hitPos: Vector3,
	distance: number,
	hitPart: BasePart?,
	hitModel: Model?,
	hitPlayer: Player?,
	worldGeometryDistance: number?, -- preenchido quando o raio parou em geometria (não NPC)
}

local ORIGIN_EPSILON = 1e-4
local ORIGIN_WALL_CHECK_MIN = 0.05
local MAX_WORLD_PIERCE = 8

-- Partes de corpo (R6 + R15). Acessórios, ferramentas e outras peças são atravessados.
local BODY_PARTS: { [string]: boolean } = {
	Head = true,
	Torso = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	HumanoidRootPart = true,
	UpperTorso = true,
	LowerTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

local HitDetection = {}

-- RaycastParams de mundo: exclui personagens de todos os jogadores (testados com rewind)
function HitDetection.buildWorldParams(extraExcluded: { Instance }?): RaycastParams
	local excluded: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	if extraExcluded then
		for _, inst in extraExcluded do
			table.insert(excluded, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	return params
end

-- Bloqueia cabeça enfiada em parede: raycast saindo de dentro de um bloco não detecta a face
function HitDetection.isOriginBlockedByWall(rootPos: Vector3, headPos: Vector3, worldParams: RaycastParams): boolean
	local rootToHead = headPos - rootPos
	if rootToHead.Magnitude <= ORIGIN_EPSILON then
		return false
	end
	return workspace:Raycast(rootPos, rootToHead, worldParams) ~= nil
end

-- Valida origem enviada no CombatFire contra geometria do mundo (root -> head e head -> origin)
function HitDetection.validateOrigin(
	character: Model,
	origin: Vector3,
	worldParams: RaycastParams
): (boolean, string?)
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not (root and root:IsA("BasePart") and head and head:IsA("BasePart")) then
		return false, "missing_parts"
	end
	local headPos = LagCompensation.posedCFrame(character, head).Position
	if HitDetection.isOriginBlockedByWall(root.Position, headPos, worldParams) then
		return false, "blocked_origin"
	end
	local speed = root.AssemblyLinearVelocity.Magnitude
	local tolerance = CombatConfig.OriginTolerance + speed * (CombatConfig.OriginSpeedAllowance or 0)
	local fromHead = origin - headPos
	if fromHead.Magnitude > tolerance then
		return false, "origin_far"
	end
	if fromHead.Magnitude > ORIGIN_WALL_CHECK_MIN and workspace:Raycast(headPos, fromHead, worldParams) ~= nil then
		return false, "origin_through_wall"
	end
	return true, nil
end

-- Broadphase puro: distância do root rebobinado ao segmento [origin, origin + dirUnit * maxDist]
function HitDetection.isWithinBroadphase(
	rootPos: Vector3,
	origin: Vector3,
	dirUnit: Vector3,
	maxDist: number,
	radius: number
): boolean
	if maxDist <= 0 or radius < 0 then
		return false
	end
	local toRoot = rootPos - origin
	local proj = math.clamp(toRoot:Dot(dirUnit), 0, maxDist)
	local perp = toRoot - dirUnit * proj
	return perp:Dot(perp) <= radius * radius
end

-- Verdadeiro quando o cliente mirou muito além da parede em que o raio do servidor parou
function HitDetection.isImpossibleShot(targetDist: number, worldGeometryDistance: number?, slack: number?): boolean
	if worldGeometryDistance == nil then
		return false
	end
	local limit = if slack ~= nil then slack else CombatConfig.ImpossibleShotSlack
	return (targetDist - worldGeometryDistance) > limit
end

-- Raycast de mundo que atravessa NPCs/bonecos mortos (Health <= 0) e peças não-corpo (acessórios/tools)
function HitDetection.raycastWorldAlive(
	origin: Vector3,
	ray: Vector3,
	baseExcluded: { Instance }
): (RaycastResult?, Model?, BasePart?)
	local excluded: { Instance } = table.clone(baseExcluded)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded

	for _ = 1, MAX_WORLD_PIERCE do
		local hit = workspace:Raycast(origin, ray, params)
		if not hit then
			return nil, nil, nil
		end
		local instance = hit.Instance
		local model = instance:FindFirstAncestorOfClass("Model")
		local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		if model and humanoid then
			if humanoid.Health <= 0 then
				-- Cadáver de NPC/boneco não bloqueia tiros contra alvos atrás dele
				table.insert(excluded, model)
				params.FilterDescendantsInstances = excluded
				continue
			end
			if not (instance.Parent == model and BODY_PARTS[instance.Name]) then
				-- Ignora Accessory/Handle ou Tool de NPC para não contar "Limb" errado
				local accessory = instance:FindFirstAncestorOfClass("Accessory")
				table.insert(excluded, accessory or instance)
				params.FilterDescendantsInstances = excluded
				continue
			end
			return hit, model, instance :: BasePart
		end
		return hit, nil, nil
	end

	return nil, nil, nil
end

-- Resolve o primeiro impacto válido entre mundo/NPCs vivos e jogadores rebobinados
function HitDetection.resolveHit(
	shooter: Player,
	origin: Vector3,
	dirUnit: Vector3,
	range: number,
	rewindTo: number,
	worldParams: RaycastParams
): HitResolution
	local worldHit, npcModel, npcPart =
		HitDetection.raycastWorldAlive(origin, dirUnit * range, worldParams.FilterDescendantsInstances)
	local bestDistance = if worldHit then worldHit.Distance else range
	local hitPart: BasePart? = npcPart
	local hitModel: Model? = npcModel
	local hitPlayer: Player? = nil
	local worldGeometryDistance: number? = if worldHit and not npcModel then worldHit.Distance else nil

	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other == shooter or not otherCharacter then
			continue
		end
		local otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
		if not otherHumanoid or otherHumanoid.Health <= 0 then
			continue
		end
		local part, distance = LagCompensation.raycastCharacter(
			otherCharacter,
			rewindTo,
			origin,
			dirUnit,
			bestDistance,
			CombatConfig.BroadphaseRadius
		)
		if part and distance and distance < bestDistance then
			bestDistance = distance
			hitPart = part
			hitModel = otherCharacter
			hitPlayer = other
		end
	end

	return {
		hitPos = origin + dirUnit * bestDistance,
		distance = bestDistance,
		hitPart = hitPart,
		hitModel = hitModel,
		hitPlayer = hitPlayer,
		worldGeometryDistance = worldGeometryDistance,
	}
end

return HitDetection