--!strict
-- Validação de tiro e lag compensation. PROVISÓRIO: valores iniciais da P2;
-- ajustar em playtest com lag simulado (P4 decide o que afeta a sensação de jogo).

return {
	-- Rewind máximo aceito para reconstruir a posição dos alvos (s)
	MaxRewindSeconds = 0.25,
	-- Atraso de interpolação que o cliente vê nos outros jogadores (s)
	InterpolationDelay = 0.1,
	-- Quanto histórico de posição o servidor guarda por jogador (s)
	HistorySeconds = 1,
	-- Quantas fotos de posição por segundo entram no histórico
	HistoryHz = 30,
	-- Distância máxima entre a origem enviada e a cabeça do atirador (studs)
	OriginTolerance = 4,
	-- Fração da cadência da arma aceita entre dois tiros (folga para jitter de rede)
	FireRateTolerance = 0.75,
	-- Rate limit bruto dos remotes de combate (s)
	FireRemoteMinInterval = 0.02,
	ReloadRemoteMinInterval = 0.2,
	-- Só recebe o efeito do tiro quem está a essa distância da origem ou do impacto (studs)
	FxRadius = 350,
	-- Imprime cada tiro validado no Output (só para depurar)
	DebugShotLog = false,
}
