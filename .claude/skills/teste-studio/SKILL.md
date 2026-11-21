---
name: teste-studio
description: Use ao testar, depurar rede, simular lag, perfilar desempenho mobile ou validar alterações no Roblox Studio (inclusive via MCP `Roblox_Studio`).
---

# Testes e Diagnóstico no Roblox Studio

## Fluxo de execução

1. Suba o sync com `rojo serve` na raiz do repositório e conecte o plugin Rojo no Studio.
2. **Play Solo:** valide boot (`Init`/`Start`), erros de tipo/runtime, lógica de arma isolada e UI.
3. **Local Server (2+ jogadores):** obrigatório para qualquer mudança em tiro, lag compensation, dano, derrubado, algema, roubo ou cofre.

## Rede, mobile e desempenho

- **Simular lag:** configure *Incoming Replication Lag* em Studio Settings → Network (confirmar caminho exato na versão atual do Studio) com 0.10–0.25 s para testar previsão no cliente e rewind no servidor.
- **Emulador mobile:** ative o Device Emulator com um celular médio (alvo do projeto). Confirme que `StreamingEnabled` está ligado e que efeitos/física de roupa aplicam LOD apenas de perto.
- **Console e erros:** monitore janela **Output** no Studio e **Developer Console** (`F9` — confirmar atalho na doc) nas abas Client e Server; zero warnings de Remote ou erros não tratados.
- **MicroProfiler:** use para caçar engasgos de frame no cliente e picos de script no servidor (confirmar atalho de abertura na doc para o seu SO).

## Instrumentação Luau para o MicroProfiler

```luau
--!strict

-- Marca trechos críticos para inspeção no MicroProfiler sem poluir produção
local function runShotValidation(validateFn: () -> ())
	debug.profilebegin("Combat_ShotValidation")
	validateFn()
	debug.profileend()
end

return {
	runShotValidation = runShotValidation,
}
```

## Uso do MCP `Roblox_Studio`

- Use o MCP **somente** quando o agente tiver acesso explícito (`mcp: ["Roblox_Studio"]`).
- Priorize inspecionar árvore de instâncias, ler saída do console (`get_console_output`), iniciar/parar playtest (`start_stop_play`) e capturar tela (`screen_capture`) para comprovar a validação.
- Não salve mudanças manuais feitas só no Studio que deveriam estar versionadas via Rojo em `src/`.

## O que reportar ao terminar o teste

- [ ] **Cenário:** Play Solo ou Local Server (quantos clientes) + lag simulado (em ms).
- [ ] **Dispositivo:** PC e/ou emulador mobile testado.
- [ ] **Console:** zero erros no Output (Client e Server) ou erro exato copiado.
- [ ] **Desempenho:** observação de FPS/frame time ou trecho medido no MicroProfiler.
- [ ] **Pendências:** tudo que não pôde ser testado (ex.: Studio fechado ou sem 2º cliente).
