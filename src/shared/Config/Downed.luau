--!strict
-- Estado derrubado. PROVISÓRIO: valores iniciais da P2; a P4 ajusta em playtest.

return {
	-- Vida (sangue) ao cair; tiros continuam tirando dela e zerar = morte
	DownedHealth = 100,
	-- Tempo até sangrar tudo se ninguém reviver nem finalizar (s)
	BleedOutSeconds = 30,
	-- Velocidade rastejando (studs/s)
	CrawlSpeed = 3,
	-- Tempo segurando o botão para reviver um aliado (s)
	ReviveHoldSeconds = 4,
	-- Vida com que o aliado levanta
	ReviveHealth = 30,
	-- Tempo segurando o botão para finalizar um inimigo (s)
	FinishHoldSeconds = 1.5,
	-- Distância máxima para reviver ou finalizar (studs)
	InteractDistance = 8,
	-- Folga no tempo de segurar, para variação de rede (fração do tempo pedido)
	HoldTolerance = 0.15,
}
