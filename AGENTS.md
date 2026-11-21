# Polícia e Ladrão PvP — regras para agentes

Jogo de polícia e ladrão no Roblox em que o tiroteio é o produto. Design completo: `docs/design.md`.
Decisões tomadas: `docs/decisoes.md`. Tarefas da fase atual: `docs/fases/`.

## Fase atual

**Fase 0 — protótipo de combate.** Nada fora de combate entra antes do tiroteio ficar gostoso em playtest.
Se a tarefa não está em `docs/fases/fase-0.md`, pergunte antes de fazer.

## Nossa área: P2 · Servidor
Esta equipe de agentes faz o trabalho da Pessoa 2. Escrevemos em `src/server` e, combinando antes, em `src/shared/Lib`.
Não mexemos em `src/client` (P1), arte/mapa no Studio (P3) nem em valores de `src/shared/Config` (P4) sem pedir.
No place Ceilandia existem scripts legados (GunServer, PoseServer, GunClient...). Não apagar nem desativar sem OK do usuário. Ver `docs/inventario-ceilandia.md`.

## Estrutura

```
default.project.json   mapa Rojo → Studio
src/server/            ServerScriptService/Server   (Services/*.luau)
src/client/            StarterPlayerScripts/Client  (Controllers/*.luau)
src/shared/            ReplicatedStorage/Shared     (Lib/, Config/)
docs/                  design, decisões, quadro de tarefas por fase
.claude/skills/        guias de como fazer cada tipo de trabalho (leia o que se aplica)
```

- `Services` (servidor) e `Controllers` (cliente) são ModuleScripts que retornam uma tabela com `Init()` e `Start()` opcionais. O bootstrap (`init.server.luau` / `init.client.luau`) chama todos os `Init` e depois todos os `Start`.
- `shared/Lib`: código reutilizável sem regra de jogo (rede, rate limit, tipos, utilidades).
- `shared/Config`: números de balanceamento (dano, TTK, recoil, preços). Quem define os valores é o Design (P4). Código não tem número mágico de balanceamento.

## Regras que não se quebram

1. **Servidor é autoridade** sobre dano, vida, dinheiro, inventário, procurado, cofres e ranking. O cliente só manda intenção ("atirei nesta direção") e mostra resultado.
2. **Todo RemoteEvent valida tipo, faixa e frequência** no servidor. Ver `.claude/skills/remotes-seguros/SKILL.md`.
3. **Luau `--!strict`** em todo arquivo novo.
4. **Mobile médio é o alvo de desempenho.** Efeitos, ricochetes e física de roupa só no cliente e só perto (LOD).
5. **Dono da área decide.** Mexer em área de outro (tabela abaixo) só combinando antes.
6. Mudou regra de jogo ou arquitetura? Registre em `docs/decisoes.md`.

## Áreas

| Área | Pasta principal | Dono de |
|---|---|---|
| P1 · Combate (cliente) | `src/client` | armas no cliente, movimento, câmera, HUD, menus, veículos, minigames |
| P2 · Servidor | `src/server` | validação de tiro, dano, derrubado, dados, economia, procurado, roubos, gangs |
| P3 · Arte 3D | Studio (Team Create) | modelos, roupas, máscaras, mapa |
| P4 · Design | `src/shared/Config`, `docs/` | regras, valores, animações, sons, playtests |

## Skills (`.claude/skills/<nome>/SKILL.md`)

| Skill | Quando ler |
|---|---|
| `orquestracao` | ao dividir trabalho entre agentes |
| `luau-padroes` | antes de escrever qualquer Luau |
| `remotes-seguros` | ao criar ou mudar comunicação cliente↔servidor |
| `combate-netcode` | tiro, dano, lag compensation, derrubado |
| `dados-sessao` | DataStore, salvamento, cofres |
| `teste-studio` | ao testar no Roblox Studio |

## Entrega

Termine dizendo o que mudou (arquivos), como foi testado e o que ficou pendente.
