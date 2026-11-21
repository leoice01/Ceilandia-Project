# Decisões

| Data | Decisão | Motivo |
|---|---|---|
| 2026-11-21 | Place do jogo: Ceilandia (placeId 117817773230060) | escolha do usuário |
| 2026-11-21 | Código oficial em `src/` com Git; Rojo 7.7.1 via Rokit sincroniza com o Studio; mapa fica no Studio | design: Rojo + Git |
| 2026-11-21 | Nossa equipe de agentes é a P2 · Servidor | divisão do trabalho |
| 2026-11-21 | Nova lib de rede NÃO pode usar a pasta `ReplicatedStorage.Remotes` (já usada pelo GunServer legado); usar pasta própria, ex. `ReplicatedStorage.Net` | evitar colisão com scripts legados |
| 2026-11-21 | Lib de rede em `src/shared/Lib/Net.luau` (pasta `ReplicatedStorage.Net`): servidor cria os remotes, rate limit por jogador e por remote, log de abuso `[Abuse] user= remote= reason= total=` com cooldown por motivo | regra 2 do AGENTS.md |
| 2026-11-21 | Contrato de rede do combate em `src/shared/Lib/CombatContract.luau`: `CombatFire({origin, direction, timestamp, weaponId})`, `CombatReload()`, `CombatHit(region, lethal, armorHit)`, `CombatFX(shooter, weaponId, origin, hitPos)`. Mudanças combinadas com a P1 | contrato cliente/servidor |
| 2026-11-21 | Lag compensation: histórico de 1 s das partes dos jogadores a 30 Hz, rewind = timestamp do cliente − atraso de interpolação, limitado a 0,25 s. NPCs usam raycast normal | tiro justo com ping alto, sem abuso de timestamp antigo |
| 2026-11-21 | Facção vem do atributo `Faction` do Player; sem atributo = "Bandido" (na Fase 0 todos trocam tiro). Civil não toma tiro, policial não acerta policial, bandido acerta bandido | design: civil neutro |
| 2026-11-21 | Colete (`ArmorVest`) protege o tronco e capacete (`ArmorHelmet`) a cabeça; membros sem armadura. Absorvem tudo antes da vida | design: armadura estilo placas |
| 2026-11-21 | `src/shared/Config/Weapons.luau` e `Combat.luau` criados pela P2 com valores PROVISÓRIOS (M4A1 copiada do legado; membros 0,75x; queda de dano de 120 a 400 studs até 0,6x). A P4 ajusta | autorizado pelo usuário para destravar o servidor |
| 2026-11-21 | Derrubado: tiro que zeraria a vida de quem está de pé derruba (atributo `Downed`). Derrubado rasteja, não atira, e `Humanoid.Health` vira o sangue que resta (cai até zero em `BleedOutSeconds`; tiros também tiram). A regeneração padrão (`Health`) fica desligada enquanto está no chão | design: derrubado estilo Warzone |
| 2026-11-21 | Reviver (E / ButtonX) e Finalizar (F / ButtonY) são ProximityPrompts criados pelo servidor, sempre visíveis. O servidor mede o tempo de segurar (HoldBegan/HoldEnded), a distância e quem pode: aliado revive, inimigo finaliza | servidor é autoridade; com a mesma tecla o Roblox esconde um dos botões |
| 2026-11-21 | Aliado = policial com policial, ou mesma gang (atributo `Gang` do Player). Sem gang, bandido não revive bandido | design: aliado da mesma gang |
| 2026-11-21 | `CombatHit` passou a mandar `result` ("Hit" / "Downed" / "Killed") no lugar de `lethal`; novo remote `CombatFeed(kind, actor, victimName)` para o kill feed | contrato com a P1, antes de ela começar o cliente |
| 2026-11-21 | Dummy/NPC só cai derrubado se tiver o atributo `Downable = true`; jogadores sempre caem | testar derrubado sem 2 jogadores |

## Perguntas em aberto

- [ ] Nome do jogo e identidade visual (cidade realista ou estilizada?)
- [ ] Câmera: terceira pessoa com ombro, primeira pessoa, ou as duas com troca?
- [ ] Quem das 4 pessoas fica com cada papel (Pessoa 1 a 4)? Alguém já tem experiência em Luau, modelagem ou animação?
- [ ] Policial pode atirar em quem tem só 1 estrela, ou só prender?
- [ ] Dinheiro e itens perdidos ao morrer: tudo o que se carrega ou uma porcentagem?
- [ ] Tamanho máximo de gang e duração da temporada do ranking.
- [ ] Polícia: qualquer jogador pode entrar, ou existe limite de proporção entre polícia e civis?
