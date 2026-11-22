--!strict
-- Regras puras de interação com derrubados (distância, linha de visão, validade e
-- cancelamento de hold), reutilizáveis por DownedService, ArmorService e testes.

export type InteractContext = {
	interactorAlive: boolean,
	interactorDowned: boolean,
	isSameModel: boolean,
	distance: number,
	maxDistance: number,
	hasLineOfSight: boolean,
}

export type HoldCheckContext = {
	connected: boolean,
	canInteract: boolean,
	allowed: boolean,
	shotFired: boolean?,
	endedAt: number?,
	now: number,
	triggerGraceSeconds: number?,
}

local MIN_LOS_DISTANCE = 0.05
local DEFAULT_TRIGGER_GRACE = 0.5

local DownedRules = {}

local function isFinite(n: number?): boolean
	return n ~= nil and n == n and math.abs(n) < math.huge
end

-- Raycast autoritativo de linha de visão no servidor entre dois pontos.
function DownedRules.hasLineOfSight(fromPos: Vector3, toPos: Vector3, ignoreInstances: { Instance }): boolean
	local delta = toPos - fromPos
	if delta.Magnitude <= MIN_LOS_DISTANCE then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreInstances
	return workspace:Raycast(fromPos, delta, params) == nil
end

-- Regra pura de interação (vivo, de pé, não é o próprio corpo, distância e linha de visão).
function DownedRules.canInteract(ctx: InteractContext): (boolean, string?)
	if ctx.isSameModel then
		return false, "self"
	end
	if not ctx.interactorAlive then
		return false, "dead"
	end
	if ctx.interactorDowned then
		return false, "downed"
	end
	if not isFinite(ctx.distance) or not isFinite(ctx.maxDistance) or ctx.distance < 0 or ctx.maxDistance < 0 then
		return false, "bad_distance"
	end
	if ctx.distance > ctx.maxDistance then
		return false, "too_far"
	end
	if not ctx.hasLineOfSight then
		return false, "no_los"
	end
	return true, nil
end

-- Confere se o hold existiu e cumpriu o tempo mínimo com folga de rede.
function DownedRules.isHoldValid(
	beganAt: number?,
	now: number,
	holdSeconds: number,
	tolerance: number
): (boolean, string?)
	if not isFinite(beganAt) or not isFinite(now) or not isFinite(holdSeconds) or not isFinite(tolerance) then
		return false, "no_hold"
	end
	local clampedTol = math.clamp(tolerance, 0, 1)
	local minHold = math.max(0, holdSeconds * (1 - clampedTol))
	if (now - (beganAt :: number)) < minHold then
		return false, "hold_too_short"
	end
	return true, nil
end

-- Decide se um hold ativo deve ser cancelado na checagem periódica (~0,1 s).
function DownedRules.shouldCancelHold(ctx: HoldCheckContext): (boolean, string?)
	if not ctx.connected then
		return true, "disconnected"
	end
	if ctx.shotFired == true then
		return true, "shot_fired"
	end
	if not ctx.canInteract then
		return true, "cannot_interact"
	end
	if not ctx.allowed then
		return true, "not_allowed"
	end
	if ctx.endedAt ~= nil then
		local grace = ctx.triggerGraceSeconds or DEFAULT_TRIGGER_GRACE
		if not isFinite(ctx.endedAt) or not isFinite(ctx.now) or (ctx.now - ctx.endedAt) > grace then
			return true, "hold_expired"
		end
	end
	return false, nil
end

return DownedRules