--!strict
-- Recuo por arma, em camada por cima da câmera (não substitui o controlador da câmera):
-- depois que a câmera do Roblox e o MovementClient atualizam, gira a câmera só o pedaço
-- de recuo daquele quadro. A câmera parte da própria direção a cada quadro, então o
-- giro fica — igual mexer o mouse.
--   * mecânico: a mira sobe de verdade (o jogador compensa puxando o mouse para baixo);
--   * padrão horizontal fixo por arma (aprendível) + tremido pequeno (Variance);
--   * chega suave (KickSpeed), sem tranco que treme a tela;
--   * recuperação: depois de RecoveryDelay sem atirar, devolve só o que o jogador
--     NÃO compensou (se já puxou para baixo, não desce mais).

local RunService = game:GetService("RunService")

local Weapons = require(game:GetService("ReplicatedStorage").Shared.Config.Weapons)

type RecoilConfig = Weapons.RecoilConfig

local BIND_NAME = "WeaponRecoil"
local MAX_PITCH = math.rad(80) -- não deixa o recuo virar a câmera de cabeça para baixo
local DONE_EPSILON = 1e-3 -- graus

local Recoil = {}

local camera = workspace.CurrentCamera
local rng = Random.new()

local config: RecoilConfig? = nil
local pendingPitch = 0 -- graus que ainda vão ser aplicados (subindo)
local pendingYaw = 0
local debt = 0 -- graus de recuo vertical ainda não devolvidos
local burstStartPitch = 0 -- rad: pitch quando a rajada começou
local lastKick = -math.huge
local gunKick = 0 -- 0..1, coice visual da arma
local bound = false

local function pitchOf(cf: CFrame): number
	return math.asin(math.clamp(cf.LookVector.Y, -1, 1))
end

-- Gira a câmera: pitch em volta do próprio eixo X, yaw em volta do Y do mundo
local function rotateCamera(pitchDeg: number, yawDeg: number)
	if pitchDeg == 0 and yawDeg == 0 then
		return
	end
	camera = workspace.CurrentCamera
	local cf = camera.CFrame
	local current = pitchOf(cf)
	local pitch = math.clamp(current + math.rad(pitchDeg), -MAX_PITCH, MAX_PITCH) - current
	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, -math.rad(yawDeg)) * cf.Rotation * CFrame.Angles(pitch, 0, 0)
	camera.CFrame = CFrame.new(cf.Position) * rotation
end

local function step(dt: number)
	local c = config
	if not c then
		return
	end
	-- chega no recuo suavemente
	local alpha = 1 - math.exp(-c.KickSpeed * dt)
	local dp, dy = pendingPitch * alpha, pendingYaw * alpha
	pendingPitch -= dp
	pendingYaw -= dy
	rotateCamera(dp, dy)

	-- recuperação: só o que sobrou acima do ponto onde a rajada começou
	if debt > 0 and os.clock() - lastKick >= c.RecoveryDelay and math.abs(pendingPitch) < 0.05 then
		local above = math.deg(pitchOf(workspace.CurrentCamera.CFrame) - burstStartPitch)
		debt = math.clamp(debt, 0, math.max(0, above))
		local back = debt * (1 - math.exp(-c.RecoverySpeed * dt))
		debt -= back
		rotateCamera(-back, 0)
		if debt < DONE_EPSILON then
			debt = 0
		end
	end

	gunKick *= math.exp(-14 * dt)
end

function Recoil.setWeapon(weaponConfig: RecoilConfig?)
	config = weaponConfig
	pendingPitch, pendingYaw, debt, gunKick = 0, 0, 0, 0
	if weaponConfig and not bound then
		bound = true
		-- depois da câmera (Camera) e do MovementClient (Camera + 1)
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, step)
	elseif not weaponConfig and bound then
		bound = false
		RunService:UnbindFromRenderStep(BIND_NAME)
	end
end

-- Um tiro. shotIndex começa em 1 em cada rajada.
function Recoil.kick(shotIndex: number, aiming: boolean)
	local c = config
	if not c then
		return
	end
	local profile = if aiming then c.ADS else c.Hip
	local climb = 1 + math.min(shotIndex - 1, c.ClimbMaxShots) * c.ClimbPerShot
	local side = c.Pattern[(shotIndex - 1) % #c.Pattern + 1]
	local vertical = profile.Vertical * climb * (1 + profile.Variance * rng:NextNumber(-1, 1))
	local horizontal = profile.Horizontal * side + profile.Horizontal * profile.Variance * rng:NextNumber(-1, 1)
	if debt <= 0 then
		burstStartPitch = pitchOf(workspace.CurrentCamera.CFrame)
	end
	pendingPitch += vertical
	pendingYaw += horizontal
	debt += vertical
	lastKick = os.clock()
	gunKick = 1
end

-- Coice visual da arma (0..1), para a pose recuar a arma
function Recoil.gunKick(): number
	return gunKick
end

return Recoil
