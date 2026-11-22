--!strict
-- Granada de teste. PROVISÓRIO: valores iniciais da P2; a P4 ajusta em playtest.

return {
	-- Granadas na mochila ao nascer
	SpawnCount = 3,
	-- Tempo do arremesso até explodir (s)
	FuseSeconds = 2.5,
	-- Velocidade do arremesso (studs/s) e quanto ela sobe a mais (fração da velocidade)
	ThrowSpeed = 70,
	ThrowLift = 0.2,
	-- Tempo mínimo entre dois arremessos do mesmo jogador (s)
	ThrowCooldown = 1,
	-- Raio da explosão (studs)
	Radius = 16,
	-- Dano em quem está no centro; na borda cai até MaxDamage * EdgeMultiplier
	MaxDamage = 140,
	EdgeMultiplier = 0.15,
	-- Dano nos objetos destrutíveis (vidros, prateleiras, portas) no centro
	DestructionDamage = 150,
	-- Quem lança também toma dano se estiver perto (fração do dano normal)
	SelfDamageMultiplier = 1,
}
