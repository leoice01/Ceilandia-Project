--!strict
-- Parâmetros técnicos da rede (não são balanceamento de jogo).

return {
	-- Intervalo médio mínimo padrão entre chamadas do mesmo remote pelo mesmo jogador (s)
	DefaultMinInterval = 0.05,
	-- Quantas chamadas podem chegar juntas acima da média (pacotes agrupados pela rede)
	BurstCapacity = 5,
	-- Mesmo motivo de abuso do mesmo jogador só é logado de novo depois disso (s)
	AbuseLogCooldown = 5,
	-- Maior magnitude aceita num Vector3 vindo do cliente (studs)
	MaxVectorMagnitude = 100000,
}
