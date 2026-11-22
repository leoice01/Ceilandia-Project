--!strict
-- Tipos de roubo. PROVISÓRIO: a P4 ajusta.
-- Qualquer BasePart com a tag "Robbable" e o atributo RobberyType = <chave abaixo> vira
-- um alvo de roubo (lojas, bancos e joalherias futuras entram aqui sem código novo).

export type RobberyType = {
	Label: string, -- nome mostrado no botão e no alerta
	Duration: number, -- s segurando o local até concluir
	Cooldown: number, -- s até o mesmo alvo poder ser roubado de novo
	MaxDistance: number, -- studs: sair disso interrompe
	Crime: string, -- crime do WantedService (Shared/Config/Wanted)
	Reward: number, -- dinheiro ao concluir (0 até existir economia)
}

return {
	Tag = "Robbable",
	TypeAttribute = "RobberyType",
	CheckInterval = 0.2, -- s entre conferências do roubo em andamento
	PromptSpamCooldown = 1, -- s entre tentativas do mesmo jogador
	Types = {
		-- cofre de evidências da delegacia provisória (ferramenta de teste)
		PoliceSafe = {
			Label = "Cofre de evidências",
			Duration = 10,
			Cooldown = 90,
			MaxDistance = 10,
			Crime = "EvidenceRobbery",
			Reward = 0,
		},
	} :: { [string]: RobberyType },
}
