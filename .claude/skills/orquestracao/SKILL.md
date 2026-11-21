---
name: orquestracao
description: Use ao dividir, delegar ou revisar tarefas entre agentes no projeto Polícia e Ladrão (papel do Piloto, posse de arquivos, divisão cliente↔servidor, escolha de tipo de task e uso do MCP Roblox_Studio).
---

# Orquestração de Agentes

## Regra de posse (`owns`)

- Uma tarefa = um agente = um conjunto exclusivo de arquivos (`owns`).
- Nunca coloque dois agentes editando o mesmo arquivo em paralelo.
- Respeite a fase ativa em `docs/fases/`: na Fase 0, nada fora de combate entra sem confirmação.

## Mapa área → pasta

| Área | Pasta principal | Escopo |
|---|---|---|
| P1 · Combate (cliente) | `src/client` | armas no cliente, movimento, câmera, HUD, menus, veículos |
| P2 · Servidor | `src/server` | validação de tiro, dano, derrubado, dados, economia, roubos, gangs |
| P3 · Arte 3D | Studio (Team Create) | modelos, roupas, máscaras, mapa |
| P4 · Design | `src/shared/Config`, `docs/` | regras, balanceamento, playtests |
| Infra compartilhada | `src/shared/Lib` | utilidades sem regra de jogo (combinar contrato antes) |

## Tarefas que cruzam cliente↔servidor

1. Defina primeiro o contrato de tipos e nomes de Remote em `src/shared/` (tarefa curta ou `planner`).
2. Dispare **2 agentes** em paralelo com `owns` disjuntos: um em `src/client` (P1) e outro em `src/server` (P2).
3. Dispare **1 agente `review`** ao final para conferir validação no servidor, aderência ao contrato e ausência de números mágicos.

```luau
--!strict
-- Contrato compartilhado que permite P1 e P2 trabalharem em paralelo
export type FirePayload = {
	origin: Vector3,
	direction: Vector3,
	timestamp: number,
	weaponId: string,
}
```

## Quando usar cada tipo de task

- `planner`: quebrar épico, definir contratos em `shared/` e mapear `owns`.
- `implement`: criar ou alterar arquivos dentro de um `owns` delimitado.
- `review`: auditar diff sem editar (segurança de remotes, `--!strict`, escopo).
- `test_validate`: executar testes no Studio ou validações automatizadas.
- `fix`: corrigir bugs apontados por `review` ou `test_validate`.

## Regra do MCP `Roblox_Studio`

- Passe `mcp: ["Roblox_Studio"]` **somente** para agentes que precisam interagir com o Studio (ex.: `test_validate`, leitura de console ou inspeção de instâncias).
- Agentes que só editam `.luau` ou `docs/` não recebem acesso ao MCP.

## Checklist do Piloto

- [ ] Cada agente recebeu escopo fechado, lista explícita de `owns` e critério de pronto.
- [ ] Tarefa cliente↔servidor foi dividida em 2 implementações + 1 `review`.
- [ ] Todo agente reportou: arquivos mudados, como testou e pendências.
- [ ] `docs/fases/*.md` atualizado com status e arquivos de cada tarefa.
- [ ] Mudança de regra de jogo ou arquitetura registrada em `docs/decisoes.md`.
