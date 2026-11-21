---
name: combate-netcode
description: Use ao implementar ou revisar disparo, raycast, lag compensation, cálculo de dano por região, armadura (colete/capacete), estado derrubado (downed) ou anti-exploit de combate.
---

# Combate e Netcode Autoritativo

## Fluxo do tiro

1. **Cliente prevê:** toca som, traçador, recoil e hitmarker provisório na hora; envia `{ origin, direction, timestamp, weaponId }`.
2. **Servidor valida:**
   - Jogador vivo, não derrubado, não civil, com a arma equipada e munição > 0.
   - Cadência respeitada (lida de `shared/Config/Weapons`).
   - Origem próxima da cabeça do personagem (tolerância em `Config`) e vetor de direção válido.
   - Lag compensation: reconstrói posição histórica do alvo usando `timestamp` limitado ao teto de rewind (ex.: buffer ~1 s, teto ~250 ms — valores finais em `Config`).
   - Linha de visão (`workspace:Raycast`) sem atravessar parede até o ponto de impacto.
3. **Tiro impossível:** descarte sem aplicar dano e registre no log de abuso.

## Dano, armadura e estado derrubado

- **Regiões:** multiplicador separado para cabeça, tronco e membros + queda de dano por distância (falloff).
- **Armadura:** colete e capacete absorvem dano antes da vida e quebram ao zerar (estilo placas).
- **Derrubado (`downed`):** vida chega a 0 → cai no chão (rasteja devagar, não atira, sangra com timer).
  - Aliado da mesma gang revive segurando botão (fica vulnerável).
  - Inimigo pode finalizar ou deixar sangrar.
  - Policial algema derrubado (forma principal de prisão).
  - Kit de autorreanimação (raro) permite levantar sozinho uma vez.

## Exemplo de validação server-side (`src/server/Services/CombatService.luau`)

```luau
--!strict

export type ShotData = {
	origin: Vector3,
	direction: Vector3,
	timestamp: number,
	weaponId: string,
}

-- Limita o rewind para impedir abuso de timestamp antigo
local function clampRewindTime(clientTime: number, maxRewindSeconds: number): number
	local serverNow = workspace:GetServerTimeNow()
	local delta = math.clamp(serverNow - clientTime, 0, maxRewindSeconds)
	return serverNow - delta
end

-- Aplica dano na armadura antes da vida; retorna dano residual aplicado à vida
local function applyArmorDamage(armor: number, health: number, rawDamage: number): (number, number)
	local absorbed = math.min(armor, rawDamage)
	local remainingArmor = armor - absorbed
	local leftover = rawDamage - absorbed
	return remainingArmor, math.max(0, health - leftover)
end

-- Raycast autoritativo de linha de visão (exclui o atirador)
local function castLineOfSight(shooterChar: Model, origin: Vector3, dir: Vector3, range: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { shooterChar }
	return workspace:Raycast(origin, dir.Unit * range, params)
end
```

## Checklist de combate

- [ ] Cliente apenas prevê feedback; dano, munição e estado `downed` são 100% no servidor.
- [ ] Rewind tem teto rígido e histórico circular (~1 s), ambos vindos de `shared/Config`.
- [ ] Origem comparada com `Head.Position` e linha de visão checada com `workspace:Raycast`.
- [ ] Civil não atira nem toma dano de tiro; tiro impossível descartado e logado.
- [ ] Colete/capacete absorvem dano antes da vida; vida 0 entra em `downed`, não morte direta.
