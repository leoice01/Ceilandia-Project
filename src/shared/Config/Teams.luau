--!strict
-- Equipes (Teams nativos do Roblox ligados ao atributo Faction do combate) e regras de
-- troca na delegacia. PROVISÓRIO: a P4 ajusta.

return {
	Police = {
		Name = "Polícia",
		Color = BrickColor.new("Bright blue"), -- mesma cor do SpawnLocation da delegacia
		Faction = "Policia", -- CombatContract.Factions.Police
	},
	Robbers = {
		Name = "Ladrões",
		Color = BrickColor.new("Bright red"),
		Faction = "Bandido", -- CombatContract.Factions.Robber
	},

	-- Troca de equipe
	SwitchCooldown = 30, -- s entre duas trocas do mesmo jogador
	CombatLock = 15, -- s sem dar nem levar dano antes de poder trocar
	RecruitHoldSeconds = 1.5, -- segurar o botão = confirmação
	PromptDistance = 8, -- studs

	-- Proteção ao nascer na delegacia (some antes se o policial atirar)
	SpawnProtection = 5, -- s

	-- Uniforme provisório (aplicado no personagem novo; o avatar volta ao sair da equipe)
	Uniform = {
		Shirt = Color3.fromRGB(28, 42, 78),
		Pants = Color3.fromRGB(22, 24, 32),
		Cap = Color3.fromRGB(22, 30, 58),
		Badge = Color3.fromRGB(230, 190, 60),
		BackText = "POLÍCIA",
	},
}
