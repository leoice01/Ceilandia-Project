--!strict
-- Validação de tiro e lag compensation. PROVISÓRIO: valores iniciais da P2;
-- ajustar em playtest com lag simulado (P4 decide o que afeta a sensação de jogo).

return {
	-- Rewind máximo aceito para reconstruir a posição dos alvos (s)
	MaxRewindSeconds = 0.25,
	-- Atraso de interpolação que o cliente vê nos outros jogadores (s)
	InterpolationDelay = 0.1,
	-- Folga extra sobre ping + InterpolationDelay ao aceitar clientTimestamp (s)
	ClientTimestampSlack = 0.05, -- PROVISÓRIO (P4)
	-- Quanto histórico de posição o servidor guarda por jogador (s)
	HistorySeconds = 1,
	-- Quantas fotos de posição por segundo entram no histórico
	HistoryHz = 30,
	-- Raio de broadphase do root rebobinado ao segmento do tiro (studs)
	BroadphaseRadius = 6, -- PROVISÓRIO (P4)
	-- Distância máxima entre a origem enviada e a cabeça do atirador, já com a pose do
	-- servidor (agachado/slide) (studs). Cobre o cano da arma mais comprida mirando.
	OriginTolerance = 5,
	-- O cliente puxa a origem para até OriginTolerance - isto da própria cabeça: a folga
	-- cobre a diferença entre a pose animada no cliente e a do servidor (studs)
	OriginClientMargin = 1.5,
	-- Andando, a cabeça no servidor fica atrás da do cliente: folga = velocidade × isto (s)
	OriginSpeedAllowance = 0.3,
	-- Excesso de distância além da parede para registrar tiro impossível (studs)
	ImpossibleShotSlack = 8, -- PROVISÓRIO (P4)
	-- Cadência: folga usada no EquipTime (o token bucket de disparo usa 1 / weapon.FireInterval)
	FireRateTolerance = 0.9,
	-- Capacidade de rajada do token bucket de cadência (folga para jitter de rede)
	FireBurstShots = 2,
	-- Rate limit bruto dos remotes de combate (s)
	FireRemoteMinInterval = 0.02,
	ReloadRemoteMinInterval = 0.2,
	-- Só recebe o efeito do tiro quem está a essa distância da origem ou do impacto (studs)
	FxRadius = 350,
	-- Imprime cada tiro validado no Output (só para depurar)
	DebugShotLog = false,
	-- Flags de diagnóstico desligáveis em playtest
	Debug = { -- PROVISÓRIO (P4)
		LogLagComp = false,
	},

	-- Sensação no cliente (P4 ajusta)
	-- FOV da câmera sobre o ombro sem mirar (documento de combate: 80)
	DefaultFov = 80,
	-- Clique de arma semiautomática um pouco antes da hora vale quando a arma ficar pronta (s)
	SemiFireBuffer = 0.15,
	-- Segura a pose de tiro um pouco depois de soltar o gatilho (s)
	FiringPoseHold = 0.5,
	-- Duração da animação de guardar a arma (s)
	HolsterTime = 0.25,
}