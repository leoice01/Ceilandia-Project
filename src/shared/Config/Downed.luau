--!strict
-- Estado derrubado. PROVISÓRIO: a P4 ajusta em playtest.
-- Do Rob Run: finalizar um derrubado leva mais 150 de dano, e policial causa só 20%
-- do dano em bandido derrubado (incentiva prender em vez de matar).

return {
	-- Vida (sangue) ao cair; tiros continuam tirando dela e zerar = morte
	DownedHealth = 150,
	-- Fração do dano que um policial causa em bandido derrubado
	PoliceVsDownedRobberMultiplier = 0.2,
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
	-- Velocidade base ao levantar (ignora o snapshot da queda, ex.: agachado/slide) (studs/s)
	BaseWalkSpeed = 16, -- PROVISÓRIO (P4)
	-- Intervalo de revalidação contínua do hold de reviver/finalizar (s)
	HoldCheckInterval = 0.1, -- PROVISÓRIO (P4)
	-- Janela entre HoldEnded e Triggered após cumprir o tempo mínimo (s)
	HoldTriggerGraceSeconds = 0.5, -- PROVISÓRIO (P4)
}
