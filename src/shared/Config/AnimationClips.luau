--!strict
-- Clipes de locomoção R6 (Prioridade 1). PROVISÓRIO: a P4 ajusta.
-- Ângulos em graus no espaço da peça "pai" (Root = HumanoidRootPart, membros = Torso):
--   Root.rx negativo = tronco para frente; Root.pos.Y negativo = corpo mais baixo
--   perna/braço rx positivo = para frente; out = abrir para o lado
-- Com arma na mão, os braços são controlados pela arma (camada de cima); as poses de
-- braço daqui aparecem desarmado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClipBuilder = require(ReplicatedStorage.Shared.Lib.ClipBuilder)

type Clip = ClipBuilder.Clip
type ClipKey = ClipBuilder.ClipKey

-- Mesma pose agachada usada na hitbox do servidor (LagCompensation): mudar junto.
-- Agachado = ajoelhado sentado sobre as pernas (referência: Criminality): quadril quase
-- no chão, tronco quase reto e as duas pernas deitadas para trás.
local CROUCH_DROP = 1.5
local CROUCH_LEAN = -5
local CROUCH_RIGHT_LEG = -88
local CROUCH_LEFT_LEG = -92

type CycleParams = {
	length: number, -- duração de um ciclo (dois passos), s
	refSpeed: number, -- velocidade em que o ciclo encaixa no chão, studs/s
	legSwing: number, -- amplitude das pernas, graus
	armSwing: number, -- amplitude dos braços (oposta às pernas), graus
	armOut: number, -- braços um pouco abertos, graus
	armOutSwing: number?, -- quanto o braço abre a mais quando vai à frente (corrida solta)
	backKick: number?, -- multiplica o balanço da perna que vai para trás (chute de corrida)
	lean: number, -- inclinação do tronco (negativo = frente), graus
	bob: number, -- quanto desce no apoio do pé, studs
	rise: number, -- quanto sobe na passagem, studs
	roll: number, -- balanço lateral do tronco, graus
	twist: number, -- torção do quadril acompanhando a perna, graus
	drop: number?, -- corpo mais baixo (agachado), studs
	rightLegBase: number?, -- ângulo base das pernas (agachado)
	leftLegBase: number?,
	headCounter: number?, -- quanto a cabeça compensa a torção (0..1)
}

-- Ciclo de passada: contato perna direita à frente (0), passagem (1/4), contato esquerda
-- (1/2), passagem (3/4), volta ao começo (1)
local function cycle(p: CycleParams): Clip
	local keys: { ClipKey } = {}
	local drop = p.drop or 0
	local baseR = p.rightLegBase or 0
	local baseL = p.leftLegBase or 0
	local counter = p.headCounter or 0.7
	local phases = {
		{ f = 0.00, s = 1, contact = true, side = 0 },
		{ f = 0.25, s = 0, contact = false, side = 1 },
		{ f = 0.50, s = -1, contact = true, side = 0 },
		{ f = 0.75, s = 0, contact = false, side = -1 },
		{ f = 1.00, s = 1, contact = true, side = 0 },
	}
	local outSwing = p.armOutSwing or 0
	local kick = p.backKick or 1
	for _, ph in phases do
		local y = -drop + (if ph.contact then -p.bob else p.rise)
		local twist = p.twist * ph.s
		-- perna que vai para trás chuta mais (a da frente fica no valor normal)
		local rightLeg = p.legSwing * ph.s * (if ph.s < 0 then kick else 1)
		local leftLeg = -p.legSwing * ph.s * (if ph.s > 0 then kick else 1)
		table.insert(keys, {
			t = ph.f * p.length,
			pose = {
				Root = { rx = p.lean, ry = twist, rz = p.roll * ph.side, pos = Vector3.new(0, y, 0) },
				Neck = { ry = -twist * counter, rx = -p.lean * 0.5 },
				RightHip = { rx = baseR + rightLeg },
				LeftHip = { rx = baseL + leftLeg },
				-- braço que vai à frente também abre para o lado (corrida solta)
				RightShoulder = { rx = -p.armSwing * ph.s, out = p.armOut + outSwing * math.max(0, -ph.s) },
				LeftShoulder = { rx = p.armSwing * ph.s, out = p.armOut + outSwing * math.max(0, ph.s) },
			},
		})
	end
	return { length = p.length, loop = true, priority = "Movement", refSpeed = p.refSpeed, keys = keys }
end

-- Respiração: duas poses que se alternam devagar
local function breathe(length: number, priority: string, a: { [string]: any }, b: { [string]: any }): Clip
	return {
		length = length,
		loop = true,
		priority = priority,
		keys = {
			{ t = 0, pose = a },
			{ t = length / 2, pose = b },
			{ t = length, pose = a },
		},
	}
end

local Clips: { [string]: Clip } = {
	-- parado, desarmado: peso relaxado, respiração no tronco e braços soltos
	Idle = breathe(2.6, "Idle", {
		Root = { rx = -1, pos = Vector3.new(0, 0, 0) },
		Neck = { rx = 1 },
		RightShoulder = { out = 3 },
		LeftShoulder = { out = 3 },
		RightHip = { out = 2 },
		LeftHip = { out = 2 },
	}, {
		Root = { rx = -2, pos = Vector3.new(0, -0.03, 0) },
		Neck = { rx = -1 },
		RightShoulder = { out = 5, rx = 2 },
		LeftShoulder = { out = 5, rx = 2 },
		RightHip = { out = 2 },
		LeftHip = { out = 2 },
	}),

	-- parado com arma: base mais aberta, tronco à frente, pronto para reagir
	IdleCombat = breathe(2.0, "Idle", {
		Root = { rx = -5, ry = 4, pos = Vector3.new(0, -0.08, 0) },
		Neck = { ry = -4, rx = 2 },
		RightHip = { out = 6, rx = -4 },
		LeftHip = { out = 6, rx = 6 },
	}, {
		Root = { rx = -6, ry = 4, pos = Vector3.new(0, -0.11, 0) },
		Neck = { ry = -4, rx = 1 },
		RightHip = { out = 6, rx = -4 },
		LeftHip = { out = 6, rx = 6 },
	}),

	-- andar (mirando ou devagar)
	Walk = cycle({
		length = 1.0, refSpeed = 10, legSwing = 28, armSwing = 16, armOut = 4,
		lean = -2, bob = 0.06, rise = 0.02, roll = 2, twist = 4,
	}),

	-- correr: corpo todo mexendo (referência Criminality) — tronco à frente, braços soltos
	-- e abrindo, quadril e ombros torcendo, corpo quicando
	Run = cycle({
		length = 0.7, refSpeed = 16, legSwing = 50, armSwing = 62, armOut = 8, armOutSwing = 22,
		backKick = 1.25, lean = -14, bob = 0.18, rise = 0.08, roll = 5, twist = 12, headCounter = 0.8,
	}),

	-- sprint: ainda mais inclinado, braços batendo alto, passadas longas
	Sprint = cycle({
		length = 0.56, refSpeed = 24, legSwing = 62, armSwing = 80, armOut = 10, armOutSwing = 30,
		backKick = 1.3, lean = -22, bob = 0.24, rise = 0.1, roll = 6, twist = 16, headCounter = 0.85,
	}),

	-- agachado parado: ajoelhado sentado sobre as pernas (mesma pose da hitbox do servidor)
	Crouch = breathe(2.4, "Idle", {
		Root = { rx = CROUCH_LEAN, pos = Vector3.new(0, -CROUCH_DROP, 0) },
		Neck = { rx = 2 },
		RightHip = { rx = CROUCH_RIGHT_LEG, out = 3 },
		LeftHip = { rx = CROUCH_LEFT_LEG, out = 3 },
		RightShoulder = { rx = 10, out = 5 },
		LeftShoulder = { rx = 6, out = 5 },
	}, {
		Root = { rx = CROUCH_LEAN - 1, pos = Vector3.new(0, -CROUCH_DROP - 0.03, 0) },
		Neck = { rx = 1 },
		RightHip = { rx = CROUCH_RIGHT_LEG, out = 3 },
		LeftHip = { rx = CROUCH_LEFT_LEG, out = 3 },
		RightShoulder = { rx = 12, out = 6 },
		LeftShoulder = { rx = 8, out = 6 },
	}),

	-- agachado andando: continua ajoelhado, as pernas se arrastam alternando pouco
	CrouchWalk = cycle({
		length = 0.9, refSpeed = 8, legSwing = 8, armSwing = 10, armOut = 5,
		lean = CROUCH_LEAN - 2, bob = 0.03, rise = 0.02, roll = 2.5, twist = 4,
		drop = CROUCH_DROP, rightLegBase = CROUCH_RIGHT_LEG, leftLegBase = CROUCH_LEFT_LEG,
		headCounter = 0.9,
	}),

	-- no ar (pulo/queda): pernas preparadas, braços um pouco abertos para equilíbrio
	Air = breathe(0.8, "Movement", {
		Root = { rx = -3 },
		RightHip = { rx = 18 },
		LeftHip = { rx = -12 },
		RightShoulder = { out = 22, rx = 10 },
		LeftShoulder = { out = 22, rx = 10 },
	}, {
		Root = { rx = -4 },
		RightHip = { rx = 22 },
		LeftHip = { rx = -16 },
		RightShoulder = { out = 26, rx = 12 },
		LeftShoulder = { out = 26, rx = 12 },
	}),

	-- sentado (bancos/veículos)
	Sit = breathe(3, "Movement", {
		RightHip = { rx = 90 },
		LeftHip = { rx = 90 },
		RightShoulder = { rx = 25 },
		LeftShoulder = { rx = 25 },
	}, {
		RightHip = { rx = 90 },
		LeftHip = { rx = 90 },
		RightShoulder = { rx = 27 },
		LeftShoulder = { rx = 27 },
	}),
}

return Clips
