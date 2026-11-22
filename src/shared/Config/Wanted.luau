--!strict
-- Sistema de procurado (referência: Rob Run). PROVISÓRIO: a P4 ajusta todos os números.
-- Pontos de crime viram estrelas; a polícia recebe alertas com mais ou menos informação
-- conforme as estrelas; perseguição, fuga e redução gradual são controladas no servidor.

export type Crime = {
	Points: number, -- pontos de procurado que o crime soma
	Cooldown: number, -- s: o mesmo crime (mesma chave) não soma de novo antes disso
	MaxPoints: number?, -- o crime sozinho não leva o procurado acima disso (evita exagero)
	Label: string, -- texto do alerta da polícia
	Alert: boolean, -- avisa a polícia
}

return {
	-- Pontos -> estrelas. Estrela N a partir de StarThresholds[N] pontos.
	-- 0: 0 estrelas | 1–24: 1 | 25–59: 2 | 60–109: 3 | 110–179: 4 | 180+: 5
	StarThresholds = { 1, 25, 60, 110, 180 },
	MaxPoints = 250,

	-- Valor da cabeça (bounty) por estrela, só informativo até existir economia
	BountyPerStar = { 0, 500, 1500, 3500, 7000, 12000 }, -- índice 1 = 0 estrelas

	Crimes = {
		-- leves
		PublicGunfire = { Points = 5, Cooldown = 8, MaxPoints = 24, Label = "Disparos em via pública", Alert = true },
		CaughtInAct = { Points = 5, Cooldown = 20, MaxPoints = nil, Label = "Suspeito visto cometendo crime", Alert = false },
		AssaultPolice = { Points = 15, Cooldown = 10, MaxPoints = nil, Label = "Policial atacado", Alert = true },
		Explosion = { Points = 10, Cooldown = 8, MaxPoints = 59, Label = "Explosão", Alert = true },
		-- moderados
		Trespass = { Points = 15, Cooldown = 60, MaxPoints = 59, Label = "Invasão de área restrita", Alert = true },
		VehicleTheft = { Points = 20, Cooldown = 30, MaxPoints = nil, Label = "Roubo de veículo", Alert = true },
		WoundPolice = { Points = 25, Cooldown = 15, MaxPoints = nil, Label = "Policial ferido", Alert = true },
		StoreRobbery = { Points = 30, Cooldown = 60, MaxPoints = nil, Label = "Roubo a estabelecimento", Alert = true },
		-- graves
		KillPolice = { Points = 40, Cooldown = 60, MaxPoints = nil, Label = "Policial abatido", Alert = true },
		JewelryRobbery = { Points = 60, Cooldown = 120, MaxPoints = nil, Label = "Roubo a joalheria", Alert = true },
		BankRobbery = { Points = 70, Cooldown = 120, MaxPoints = nil, Label = "Assalto a banco", Alert = true },
		MajorShootout = { Points = 35, Cooldown = 45, MaxPoints = nil, Label = "Confronto armado com a polícia", Alert = true },
	} :: { [string]: Crime },

	-- Confronto grande: tantos crimes contra a polícia dentro da janela vira MajorShootout
	ShootoutPoliceCrimes = 4,
	ShootoutWindow = 30, -- s

	-- Áreas: BasePart com a tag RestrictedTag = invadir conta Trespass; com SafeZoneTag,
	-- tiro ali dentro não conta como disparo em via pública (estande de tiro, por exemplo)
	RestrictedTag = "RestrictedArea",
	SafeZoneTag = "NoCrimeZone",
	-- Policial de teste/IA: modelo com esta tag conta como polícia (contato e vítima)
	PoliceUnitTag = "PoliceUnit",

	-- Identificação e perseguição (studs / s)
	WitnessRange = 140, -- policial a essa distância com visão do crime = suspeito identificado
	PursuitRange = 120, -- policial com visão do suspeito até aqui = perseguição (contato)
	SuspectRange = 220, -- policial perto, sem visão = "suspeito" (polícia na área; a fuga não anda)
	ContactLostTime = 4, -- s sem contato até a perseguição virar fuga
	ConfrontationContact = 6, -- s de contato garantido depois de troca de tiro com a polícia

	-- Fuga: tempo acumulado sem contato e sem polícia por perto, mais sair da área de busca
	EscapeTimeBase = 15, -- s com 1 estrela
	EscapeTimePerStar = 8, -- s a mais por estrela acima de 1
	SearchRadiusBase = 150, -- raio da área de busca com 1 estrela (studs)
	SearchRadiusPerStar = 50,
	-- Escondido dentro da área de busca também escapa, mas leva este múltiplo do tempo
	InsideAreaEscapeMultiplier = 2,

	-- Redução gradual (só depois de escapar e sem crime recente)
	DecayDelay = 10, -- s depois de escapar (e do último crime) até começar a cair
	DecayInterval = 3, -- s entre cada redução
	DecayPoints = 6, -- pontos que caem por vez

	-- Ao morrer ou ser preso o procurado zera
	ClearOnDeath = true,

	-- Alertas da polícia por estrela (índice = estrelas). Raio = imprecisão da posição.
	-- Nível baixo: só o tipo de crime e área grande; alto: área pequena e nome do suspeito.
	AlertDetail = {
		{ Location = false, Radius = 0, ShowSuspect = false, Priority = "Baixa" },
		{ Location = true, Radius = 120, ShowSuspect = false, Priority = "Média" },
		{ Location = true, Radius = 70, ShowSuspect = true, Priority = "Alta" },
		{ Location = true, Radius = 45, ShowSuspect = true, Priority = "Muito alta" },
		{ Location = true, Radius = 30, ShowSuspect = true, Priority = "Máxima" },
	},
	AlertPinSeconds = 25, -- quanto tempo o alerta fica no minimapa da polícia
	TickInterval = 0.25, -- s entre atualizações de perseguição no servidor
}
