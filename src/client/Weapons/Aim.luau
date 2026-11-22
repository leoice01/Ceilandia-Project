--!strict
-- Mira em duas etapas para a câmera TPS (sobre o ombro):
--   1) ponto pretendido: raio da câmera pela mira, começando na altura do personagem
--      (o que está entre a câmera e o personagem não conta);
--   2) trajetória real: do cano (origem validada perto da cabeça) até o ponto pretendido.
--      Se tiver parede no caminho, o tiro para nela — a câmera deslocada para o lado
--      não deixa acertar ninguém através da parede.
-- O servidor refaz a etapa 2 a partir da origem que ele mesmo valida.

local Aim = {}

local MIN_TRAVEL = 1.5 -- ponto pretendido colado no cano: usa a direção da câmera (studs)
local BLOCK_MARGIN = 0.5 -- folga para dizer que o cano está bloqueado (studs)
local ORIGIN_WALL_MARGIN = 0.1 -- mesmo recuo da origem que o servidor usa (studs)

-- Ponto na tela onde fica a mira: sempre o centro (câmera sobre o ombro; no celular
-- também). Seguir o mouse solto faria o tiro sair longe da mira.
function Aim.screenPoint(camera: Camera): Vector2
	return camera.ViewportSize * 0.5
end

-- Etapa 1: ponto que o jogador está mirando. dir já inclui a dispersão.
function Aim.intendedPoint(rayOrigin: Vector3, dir: Vector3, head: Vector3, range: number, params: RaycastParams): Vector3
	local unit = dir.Unit
	-- começa no ponto do raio mais perto da cabeça: parede atrás do personagem não vira alvo
	local skip = math.max(0, (head - rayOrigin):Dot(unit))
	local start = rayOrigin + unit * skip
	local result = workspace:Raycast(start, unit * range, params)
	return if result then result.Position else start + unit * range
end

-- Origem do tiro: o cano, puxado para perto da cabeça (tolerância do servidor) e para
-- antes de qualquer parede entre a cabeça e o cano.
function Aim.origin(head: Vector3, muzzle: Vector3, maxDistance: number, params: RaycastParams): Vector3
	local offset = muzzle - head
	if offset.Magnitude > maxDistance then
		offset = offset.Unit * maxDistance
	end
	if offset.Magnitude < 0.05 then
		return head
	end
	local blocked = workspace:Raycast(head, offset, params)
	if blocked then
		local back = math.max(0, (blocked.Position - head).Magnitude - ORIGIN_WALL_MARGIN)
		return head + offset.Unit * back
	end
	return head + offset
end

-- Etapa 2: direção do cano até o ponto pretendido
function Aim.direction(origin: Vector3, intended: Vector3, cameraDir: Vector3): Vector3
	local travel = intended - origin
	if travel.Magnitude < MIN_TRAVEL or travel:Dot(cameraDir) <= 0 then
		return cameraDir.Unit
	end
	return travel.Unit
end

-- Onde o tiro bate de verdade saindo do cano. blocked = parou antes do ponto pretendido.
function Aim.trace(origin: Vector3, direction: Vector3, range: number, intended: Vector3?, params: RaycastParams): (Vector3, RaycastResult?, boolean)
	local result = workspace:Raycast(origin, direction * range, params)
	local hitPos = if result then result.Position else origin + direction * range
	local blocked = false
	if intended and result then
		blocked = (hitPos - origin).Magnitude < (intended - origin).Magnitude - BLOCK_MARGIN
	end
	return hitPos, result, blocked
end

return Aim
