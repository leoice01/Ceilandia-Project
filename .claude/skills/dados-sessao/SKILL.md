---
name: dados-sessao
description: Use ao implementar ou revisar persistência de dados de jogador, inventário, dinheiro, cofre de gang, ranking global ou qualquer uso de DataStore/MemoryStore.
---

# Dados, Sessão e Anti-Duplicação

## Persistência de jogador

- Use **ProfileStore** (confirmar assinatura exata da versão adotada na doc) ou session lock próprio com `DataStore:UpdateAsync`.
- **Nunca use `SetAsync`** para dados de jogador: ele sobrescreve sessões concorrentes e gera duplicação/perda.
- Implemente **retry com backoff exponencial**, **autosave periódico** e salvamento ordenado em `game:BindToClose`.
- Se o carregamento falhar após retries, chute o jogador (`player:Kick`) em vez de criar perfil vazio e sobrescrever dados reais.

## Cofre de gang e ranking global

- **Cofre de gang:** fica em um DataStore separado do perfil individual. Toda retirada/depósito usa `UpdateAsync` atômico (resolve dois membros mexendo juntos) e respeita a parcela protegida contra raid.
- **Ranking global (Top 10 gangs):** use `OrderedDataStore` ou `MemoryStoreService` atualizado em lote, não a cada evento (confirmar limites e cotas atuais na doc do Roblox).

## Exemplo de escrita atômica e retry (`src/server/Services/DataService.luau`)

```luau
--!strict

local DataStoreService = game:GetService("DataStoreService")
local vaultStore = DataStoreService:GetDataStore("GangVault_v1")

export type VaultData = {
	cash: number,
	version: number,
}

-- Retira valor do cofre de forma atômica, evitando duplicação em concorrência
local function tryWithdrawAtomic(gangId: string, amount: number, protectedFloor: number): boolean
	if amount <= 0 then
		return false
	end

	local succeeded = false
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			vaultStore:UpdateAsync("gang_" .. gangId, function(current: VaultData?): VaultData?
				succeeded = false -- Reinicia a flag caso o UpdateAsync reexecute por contenção
				local data: VaultData = current or { cash = 0, version = 0 }
				if (data.cash - amount) < protectedFloor then
					return nil -- Cancela escrita sem alterar o dado salvo
				end
				data.cash -= amount
				data.version += 1
				succeeded = true
				return data
			end)
		end)
		if ok then
			return succeeded
		end
		warn(("[Data] retry=%d gang=%s err=%s"):format(attempt, gangId, tostring(err)))
		task.wait(2 ^ attempt)
	end
	return false
end

game:BindToClose(function()
	-- Aguarde liberação de todas as sessões ativas antes de encerrar (confirmar timeout na doc)
	task.wait(1)
end)
```

## Checklist anti-duplicação

- [ ] Nenhum `SetAsync` usado em perfis de jogador ou cofres.
- [ ] Session lock impede o mesmo `UserId` carregar em dois servidores ao mesmo tempo.
- [ ] Falha ao carregar expulsa o jogador; nunca cria dado zerado por cima.
- [ ] Transferência (jogador ↔ cofre / mercado) debita e confirma no servidor antes de creditar.
- [ ] Dados salvos e sessão liberada antes de teleporte entre cidade e sede da gang.
- [ ] `BindToClose` aguarda gravação das sessões abertas.
