---
name: luau-padroes
description: Use antes de criar ou editar qualquer script `.luau` em `src/server`, `src/client` ou `src/shared` para seguir `--!strict`, contrato `Init`/`Start`, nomenclatura e separação de configuração.
---

# Padrões de Luau do Projeto

## Regras obrigatórias

- Todo arquivo `.luau` começa com `--!strict` na primeira linha.
- **Um módulo = uma responsabilidade.** Se crescer demais, extraia submódulo coeso.
- **Services (`src/server/Services`) e Controllers (`src/client/Controllers`)** retornam uma tabela com `Init()` e `Start()` opcionais. `Init` prepara estado e dependências; `Start` conecta eventos e inicia loops.
- **Nomenclatura:** `PascalCase` para módulos e tipos, `camelCase` para variáveis/funções locais, `UPPER_SNAKE_CASE` para constantes técnicas internas.
- **Zero número de balanceamento no código:** dano, TTK, recoil, preços e tempos ficam em `src/shared/Config/`.
- **Concorrência moderna:** use `task.wait`, `task.spawn`, `task.defer`, `task.delay` e `task.cancel`. Nunca use `wait`, `spawn` ou `delay` legados.
- **Sem loop travado:** nunca escreva `while true do` sem yield garantido (prefira eventos ou `RunService`).
- **Tipos compartilhados:** exporte com `export type` em `src/shared/` para cliente e servidor usarem a mesma definição.

## Exemplo (`src/server/Services/WeaponService.luau`)

```luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponsConfig = require(ReplicatedStorage.Shared.Config.Weapons)

export type WeaponId = string

local WeaponService = {}
local activeAmmo: { [Player]: number } = {}

-- Prepara dependências sem iniciar efeitos colaterais de runtime
function WeaponService:Init()
	table.clear(activeAmmo)
end

-- Inicia conexões e rotinas assíncronas após todos os Init()
function WeaponService:Start()
	task.spawn(function()
		while true do
			-- Yield obrigatório para nunca congelar o servidor
			task.wait(1)
		end
	end)
end

function WeaponService:GetBaseDamage(weaponId: WeaponId): number?
	local stats = WeaponsConfig[weaponId]
	return if stats then stats.baseDamage else nil
end

return WeaponService
```

## Checklist antes de concluir

- [ ] `--!strict` está na linha 1 e sem `any` desnecessário.
- [ ] Nenhum número de balanceamento hardcoded (tudo lido de `src/shared/Config/`).
- [ ] `Init()` não depende de efeitos de `Start()` de outros módulos.
- [ ] Uso exclusivo de `task.*` (nenhum `wait`/`spawn`/`delay` legado).
- [ ] Nenhum loop infinito sem yield ou condição de saída.
- [ ] Identificadores em inglês e comentários curtos em português explicando o porquê.
