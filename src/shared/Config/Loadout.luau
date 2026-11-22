--!strict
-- Armas que cada jogador recebe ao nascer, por facção. PROVISÓRIO: a P4 decide
-- (loja e inventário vêm depois).

export type Kit = { Primary: string, Secondary: string }

return {
	-- chave = atributo Faction (CombatContract.Factions)
	ByFaction = {
		Bandido = { Primary = "M4A1", Secondary = "G17" },
		Policia = { Primary = "MP5", Secondary = "G17" },
	} :: { [string]: Kit },
	-- facção sem kit (civil) não recebe arma
	-- Só no Studio: armas extras na mochila para testar todas as categorias no playtest
	-- (as que já estão no kit da facção não se repetem)
	StudioExtras = { "R870", "M24" },
}
