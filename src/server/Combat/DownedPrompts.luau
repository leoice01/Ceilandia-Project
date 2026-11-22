--!strict
-- Prompts de reviver/finalizar e registro de holds ativos com validação contínua (~0,1 s).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local DownedConfig = require(ReplicatedStorage.Shared.Config.Downed)
local DownedRules = require(script.Parent.DownedRules)

export type ActiveHold = {
	player: Player,
	prompt: ProximityPrompt,
	beganAt: number,
	endedAt: number?,
	allowed: (Player) -> boolean,
}

export type PromptOwner = {
	model: Model,
	prompts: { ProximityPrompt },
	holds: { [ProximityPrompt]: { [Player]: ActiveHold } },
	connections: { RBXScriptConnection },
}

export type PromptSpec = {
	name: string,
	actionText: string,
	holdSeconds: number,
	keyboardKey: Enum.KeyCode,
	gamepadKey: Enum.KeyCode,
	allowed: (Player) -> boolean,
	onDone: (Player) -> (),
}

local DownedPrompts = {}

local activeInteractors: { [Player]: { [ProximityPrompt]: ActiveHold } } = {}

function DownedPrompts.removeHold(owner: PromptOwner, prompt: ProximityPrompt, player: Player)
	local promptHolds = owner.holds[prompt]
	if promptHolds then
		promptHolds[player] = nil
	end
	local playerHolds = activeInteractors[player]
	if playerHolds then
		playerHolds[prompt] = nil
		if next(playerHolds) == nil then
			activeInteractors[player] = nil
		end
	end
end

function DownedPrompts.clearOwner(owner: PromptOwner)
	for prompt, promptHolds in owner.holds do
		for player in promptHolds do
			DownedPrompts.removeHold(owner, prompt, player)
		end
	end
	for _, prompt in owner.prompts do
		prompt:Destroy()
	end
end

function DownedPrompts.isInteracting(player: Player): boolean
	local holds = activeInteractors[player]
	if not holds then
		return false
	end
	for _, entry in holds do
		if entry.endedAt == nil then
			return true
		end
	end
	return false
end

function DownedPrompts.cancelInteractor(player: Player, owners: { [Model]: PromptOwner })
	if not activeInteractors[player] then
		return
	end
	activeInteractors[player] = nil
	for _, owner in owners do
		for _, promptHolds in owner.holds do
			promptHolds[player] = nil
		end
	end
end

function DownedPrompts.attach(
	owner: PromptOwner,
	root: BasePart,
	spec: PromptSpec,
	isActive: () -> boolean,
	evaluateInteract: (Player) -> (boolean, string?)
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = spec.name
	prompt.ActionText = spec.actionText
	prompt.ObjectText = owner.model.Name
	prompt.HoldDuration = spec.holdSeconds
	prompt.KeyboardKeyCode = spec.keyboardKey
	prompt.GamepadKeyCode = spec.gamepadKey
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.MaxActivationDistance = DownedConfig.InteractDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local holds: { [Player]: ActiveHold } = {}
	owner.holds[prompt] = holds
	table.insert(owner.prompts, prompt)

	table.insert(owner.connections, prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		if not isActive() or not spec.allowed(player) then
			return
		end
		local ok, reason = evaluateInteract(player)
		if not ok then
			if reason == "too_far" or reason == "no_los" then
				Net.reportAbuse(player, "Prompt" .. spec.name, reason)
			end
			return
		end
		local entry: ActiveHold = {
			player = player,
			prompt = prompt,
			beganAt = os.clock(),
			endedAt = nil,
			allowed = spec.allowed,
		}
		holds[player] = entry
		local perPlayer = activeInteractors[player]
		if not perPlayer then
			perPlayer = {}
			activeInteractors[player] = perPlayer
		end
		perPlayer[prompt] = entry
	end))

	table.insert(owner.connections, prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		local entry = holds[player]
		if not entry then
			return
		end
		local now = os.clock()
		local valid = DownedRules.isHoldValid(entry.beganAt, now, spec.holdSeconds, DownedConfig.HoldTolerance)
		if not valid then
			DownedPrompts.removeHold(owner, prompt, player)
		else
			entry.endedAt = now
		end
	end))

	table.insert(owner.connections, prompt.Triggered:Connect(function(player: Player)
		local entry = holds[player]
		DownedPrompts.removeHold(owner, prompt, player)
		if not isActive() then
			return
		end
		local now = os.clock()
		local holdOk, holdReason = DownedRules.isHoldValid(
			if entry then entry.beganAt else nil, now, spec.holdSeconds, DownedConfig.HoldTolerance
		)
		if not holdOk then
			Net.reportAbuse(player, "Prompt" .. spec.name, holdReason or "hold_too_short")
			return
		end
		local canOk, canReason = evaluateInteract(player)
		if not canOk then
			Net.reportAbuse(player, "Prompt" .. spec.name, canReason or "too_far_or_invalid")
			return
		end
		if not spec.allowed(player) then
			return
		end
		spec.onDone(player)
	end))
end

-- Revalida holds ativos (~0,1 s): saída, distância, vida, derrubado, LoS, permissão e janela
function DownedPrompts.tickOwner(owner: PromptOwner, now: number, evaluateInteract: (Player) -> (boolean, string?))
	for prompt, promptHolds in owner.holds do
		for player, entry in promptHolds do
			local connected = player.Parent ~= nil
			local canOk = connected and (evaluateInteract(player) == true)
			local allowOk = connected and entry.allowed(player)
			local cancel = DownedRules.shouldCancelHold({
				connected = connected,
				canInteract = canOk,
				allowed = allowOk,
				endedAt = entry.endedAt,
				now = now,
				triggerGraceSeconds = DownedConfig.HoldTriggerGraceSeconds,
			})
			if cancel then
				DownedPrompts.removeHold(owner, prompt, player)
			end
		end
	end
end

return DownedPrompts