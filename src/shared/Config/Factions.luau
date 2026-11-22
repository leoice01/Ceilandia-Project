--!strict
-- Escolha de lado (Civil, Bandido, Policia). PROVISÓRIO (P4): a P4 ajusta em playtest.

return {
	-- Tempo de canalização para puxar máscara (Civil -> Bandido) (s)
	TransformSeconds = 2.5,
	-- Tempo de canalização para esfriar identidade (Bandido -> Civil) (s)
	UnmaskSeconds = 3.0,
	-- Tempo de canalização para sair de plantão fora da delegacia (Policia -> Civil) (s)
	EndShiftSeconds = 2.0,
	-- Tempo mínimo entre trocas concluídas de facção (s)
	SwitchCooldownSeconds = 10,
	-- Tempo fora de combate exigido para voltar a Civil (s)
	CombatCooldownSeconds = 25,
	-- Janela no primeiro spawn para entrar direto na Polícia sem ir à delegacia (s)
	InitialChoiceSeconds = 30,
	-- Proporção máxima de policiais sobre jogadores ativos (0..1)
	MaxPoliceRatio = 0.4,
	-- Mínimo garantido de vagas policiais mesmo em servidores pequenos
	MinPoliceSlots = 2,
	-- Abaixo dessa proporção de policiais, ativa bônus de incentivo
	UnderstaffedPoliceRatio = 0.25,
	-- Multiplicador de recompensa quando a polícia está desfalcada
	PoliceBonusMultiplier = 1.25,
	-- Distância máxima do ProximityPrompt em pontos com tag PoliceStation (studs)
	StationInteractDistance = 10,
	-- Folga de rede na validação de distância da delegacia (studs)
	StationDistanceSlack = 2,
	-- Tempo de segurar no ProximityPrompt da delegacia (s)
	StationPromptHoldSeconds = 0.5,
	-- Cooldown anti-spam no ProximityPrompt da delegacia (s)
	StationPromptCooldownSeconds = 1.0,
	-- Raio de replicação LOD dos efeitos de transformação (studs)
	TransformFxRadius = 250,
	-- Multiplicador de velocidade durante Transforming (1 = sem redução)
	TransformWalkSpeedMultiplier = 0.6,
	-- Rate limit bruto do remote FactionRequest (s)
	RequestMinInterval = 0.25,
	-- Ao morrer, volta para Civil automaticamente.
	-- false a pedido do usuário (delegacia, nov/2026): policial que morre renasce policial
	-- na delegacia; o procurado do ladrão já zera na morte pelo WantedService.
	ResetToCivilOnDeath = false,
	-- Flag da Fase 0: se true, não reseta facção ao morrer para agilizar playtest de tiro
	Phase0CombatTest = false,
	-- Permite escolher Polícia direto no primeiro spawn dentro de InitialChoiceSeconds
	AllowInstantStartChoice = true,
	-- Facção inicial ao entrar no servidor
	DefaultSpawnFaction = "Civil",
	-- Flag da Fase 0: se true, jogadores sem facção entram como Bandido
	Phase0AutoBandit = true, -- botão de máscara (FactionController_P1 em ServerStorage.HudBackups) fora por enquanto
	-- Flag da Fase 0: Bandidos sem gang contam como aliados para reviver/não finalizar
	Phase0BanditsAreAllies = true, -- PROVISÓRIO (P4): enquanto não existe sistema de gangs; desligar quando as gangs existirem
}