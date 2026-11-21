---
name: remotes-seguros
description: Use ao criar, modificar ou revisar qualquer comunicação cliente↔servidor (`RemoteEvent` ou `RemoteFunction`) para garantir criação no servidor, validação completa de argumentos, checagem de estado e rate limit.
---

# Remotes Seguros

## Princípios inegociáveis

- **Servidor cria todos os Remotes** (em pasta dedicada no `ReplicatedStorage`). Cliente só espera com `WaitForChild`.
- **Cliente envia intenção, nunca resultado:** nunca aceite dano, vida, dinheiro, inventário, arma equipada ou estrelas de procurado vindos do cliente.
- **Valide tudo no servidor:** tipo (`typeof`), faixa (sem `NaN`/`inf`, magnitude limitada), estado do jogador (vivo, não derrubado, facção permitida) e frequência (rate limit por jogador e por remote).
- **Registre abusos:** payload inválido ou spam acima do limite é descartado e logado com `UserId`, nome do remote e motivo.

## Exemplo (`Remotes.onServer` em `src/shared/Lib/Remotes.luau`)

```luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Validator = (...any) -> (boolean, string?)
export type Handler = (Player, ...any) -> ()

local Remotes = {}
local lastCall: { [string]: { [number]: number } } = {}

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	return created
end

-- Helper seguro: NaN falha (n ~= n) e infinito falha (abs == huge)
function Remotes.isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

function Remotes.onServer(name: string, validator: Validator, handler: Handler, minInterval: number?)
	local interval = minInterval or 0.1 -- Valor padrão; cadências de jogo vêm de shared/Config
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = getOrCreateFolder()
	lastCall[name] = {}

	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		local prev = lastCall[name][player.UserId]
		if prev and (now - prev) < interval then
			warn(("[Abuse] user=%d remote=%s reason=rate_limit"):format(player.UserId, name))
			return
		end
		lastCall[name][player.UserId] = now

		local ok, reason = validator(...)
		if not ok then
			warn(("[Abuse] user=%d remote=%s reason=%s"):format(player.UserId, name, reason or "invalid_args"))
			return
		end
		handler(player, ...)
	end)
end

return Remotes
```

## Checklist de segurança

- [ ] Remote criado exclusivamente no servidor; limpe `lastCall` no `Players.PlayerRemoving`.
- [ ] Cada argumento validado com `typeof` e checagem de `NaN`/`inf`/tamanho de vetor ou string.
- [ ] Estado do jogador conferido no servidor (vivo, não derrubado, facção, distância de interação).
- [ ] Rate limit por jogador e por remote configurado (valores de cadência em `shared/Config`).
- [ ] Nenhum valor de dano, dinheiro ou inventário aceito do cliente.
- [ ] Tentativas inválidas descartadas e logadas com `UserId`, remote e motivo.
