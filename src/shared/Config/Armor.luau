--!strict
-- Placas de colete (estilo Warzone, valores do Rob Run). PROVISÓRIO: a P4 ajusta em playtest.
-- Rob Run: armadura leve 25, média 50, assalto 75, pesada 100. Aqui cada placa = 25,
-- então 1 placa = leve ... 4 placas = pesada.

return {
	-- Armadura de cada placa
	PlateHealth = 25,
	-- Quantas placas cabem no colete
	MaxPlates = 4,
	-- Quantas placas extras o jogador consegue carregar
	CarryMax = 5,
	-- Placas já no colete ao nascer
	SpawnPlates = 4,
	-- Placas extras na mochila ao nascer
	SpawnCarried = 2,
	-- Tempo para colocar uma placa (s); não dá para atirar enquanto coloca
	PlateInsertSeconds = 1.2,
	-- O colete protege o corpo todo (Warzone). false = só o tronco
	VestCoversAllRegions = true,
	-- Tempo entre dois usos da caixa de placas pelo mesmo jogador (s)
	CrateCooldownSeconds = 10,
	-- Distância máxima para usar a caixa de placas (studs)
	CrateInteractDistance = 8,
	-- Rate limit do pedido de colocar placa (s)
	PlateRemoteMinInterval = 0.2,
}
