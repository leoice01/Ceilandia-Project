# Fase 0 — Protótipo de combate

**Critério de saída:** o tiroteio está gostoso em playtest com jogadores reais.

| Tarefa | Área | Status | Arquivos |
|---|---|---|---|
| Montar o projeto: Rojo, Git e estrutura de pastas | P2 · Servidor | Feito | default.project.json, rokit.toml, src/, AGENTS.md |
| Armas no cliente: tiro, recoil, spread e mira | P1 · Combate | A fazer | |
| Validação de tiro e dano no servidor (regiões do corpo e colete) | P2 · Servidor | Fazendo (servidor pronto; falta a P1 ligar o cliente em `CombatFire` e teste com 2 jogadores) | src/server/Services/CombatService.luau, src/server/Combat/, src/shared/Lib/CombatContract.luau, src/shared/Config/Weapons.luau, src/shared/Config/Combat.luau |
| Movimento: corrida, slide, mantle, agachar, deitar e lean | P1 · Combate | A fazer | |
| Câmera, hitmarker, impacto e kill feed | P1 · Combate | A fazer | |
| Derrubado, reviver e finalizar | P2 · Servidor | A fazer | |
| Anti-exploit básico e logs de tiro | P2 · Servidor | Fazendo (remotes novos com rate limit e log de abuso; GunServer legado ainda sem) | src/shared/Lib/Net.luau, src/shared/Config/Net.luau |
| Modelos das 3 primeiras armas | P3 · Arte 3D | A fazer | |
| Personagem base e arena de teste | P3 · Arte 3D | A fazer | |
| Animações de arma: atirar, recarregar e mirar | P4 · Design | A fazer | |
| Animações de movimento e de derrubado | P4 · Design | A fazer | |
| Valores de dano, TTK e recoil | P4 · Design | A fazer | |
| Sons de tiro e de impacto | P4 · Design | A fazer | |
| Playtest semanal | Todos | A fazer | |
