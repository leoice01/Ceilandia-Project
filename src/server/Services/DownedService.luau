--!strict
-- Estado derrubado: quando um tiro zeraria a vida, o personagem cai em vez de morrer.
-- Derrubado rasteja, não atira e sangra (Humanoid.Health cai até zero). Um aliado
-- revive segurando um botão; um inimigo finaliza segurando outro botão ou atirando.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local DownedConfig = require(ReplicatedStorage.Shared.Config.Downed)
local Factions = require(script.Parent.Parent.Combat.Factions)
local ArmorService = require(script.Parent.ArmorService)
local WantedService = require(script.Parent.WantedService)

type FeedKind = CombatContract.FeedKind

type DownedState = {
	model: Model,
	humanoid: Humanoid,
	player: Player?,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	maxHealth: number,
	regenScript: Script?,
	prompts: { ProximityPrompt },
	holds: { [ProximityPrompt]: { [Player]: number } },
	connections: { RBXScriptConnection },
}

local ATTR = CombatContract.Attributes
local PROMPTS = CombatContract.Prompts
local BLEED_TICK = 0.1 -- de quanto em quanto tempo a vida do derrubado é atualizada (s)
local DISTANCE_SLACK = 2 -- folga na distância de interação para variação de rede (studs)

local DownedService = {}

local downed: { [Model]: DownedState } = {}
local feedRemote: RemoteEvent

local function feed(kind: FeedKind, actor: Player?, victimName: string)
	feedRemote:FireAllClients(kind, actor, victimName)
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Sai do estado derrubado. restore = levantou (volta velocidade, pulo e regeneração).
local function clear(state: DownedState, restore: boolean)
	if downed[state.model] ~= state then
		return
	end
	downed[state.model] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
	for _, prompt in state.prompts do
		prompt:Destroy()
	end
	if state.model.Parent then
		state.model:SetAttribute(ATTR.Downed, nil)
	end
	if restore then
		state.humanoid.MaxHealth = state.maxHealth
		state.humanoid.WalkSpeed = state.walkSpeed
		state.humanoid.JumpPower = state.jumpPower
		state.humanoid.JumpHeight = state.jumpHeight
		if state.regenScript then
			state.regenScript.Enabled = true
		end
	end
end

-- Quem interage precisa estar vivo, de pé e perto de quem está no chão
local function canInteract(interactor: Player, state: DownedState): boolean
	local character = interactor.Character
	if not character or character == state.model or downed[character] then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local from, to = rootOf(character), rootOf(state.model)
	if not from or not to then
		return false
	end
	return (from.Position - to.Position).Magnitude <= DownedConfig.InteractDistance + DISTANCE_SLACK
end

local function revive(state: DownedState, by: Player)
	clear(state, true)
	state.humanoid.Health = math.min(DownedConfig.ReviveHealth, state.humanoid.MaxHealth)
	feed("Revived", by, state.model.Name)
end

local function kill(state: DownedState, kind: FeedKind, by: Player?)
	clear(state, false)
	state.humanoid.Health = 0
	feed(kind, by, state.model.Name)
end

-- Cria um botão de segurar. O cliente controla o tempo de segurar, então o servidor
-- mede de novo pelo HoldBegan/HoldEnded e recusa quem disparou cedo demais.
local function addPrompt(
	state: DownedState,
	root: BasePart,
	name: string,
	actionText: string,
	holdSeconds: number,
	keyboardKey: Enum.KeyCode,
	gamepadKey: Enum.KeyCode,
	allowed: (Player) -> boolean,
	onDone: (Player) -> ()
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = state.model.Name
	prompt.HoldDuration = holdSeconds
	-- Reviver e Finalizar ficam na mesma parte: teclas diferentes e os dois visíveis,
	-- senão o Roblox mostra só um botão por tecla e o outro some
	prompt.KeyboardKeyCode = keyboardKey
	prompt.GamepadKeyCode = gamepadKey
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.MaxActivationDistance = DownedConfig.InteractDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local holds: { [Player]: number } = {}
	state.holds[prompt] = holds
	table.insert(state.prompts, prompt)
	local minimumHold = holdSeconds * (1 - DownedConfig.HoldTolerance)

	table.insert(state.connections, prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		holds[player] = os.clock()
	end))
	table.insert(state.connections, prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		-- Soltou antes do tempo: invalida o começo
		local began = holds[player]
		if began and os.clock() - began < minimumHold then
			holds[player] = nil
		end
	end))
	table.insert(state.connections, prompt.Triggered:Connect(function(player: Player)
		local began = holds[player]
		holds[player] = nil
		if downed[state.model] ~= state then
			return
		end
		if not began or os.clock() - began < minimumHold then
			Net.reportAbuse(player, "Prompt" .. name, "hold_too_short")
			return
		end
		if not canInteract(player, state) then
			Net.reportAbuse(player, "Prompt" .. name, "too_far_or_invalid")
			return
		end
		if not allowed(player) then
			return
		end
		onDone(player)
	end))
end

function DownedService.isDownable(model: Model): boolean
	if Players:GetPlayerFromCharacter(model) then
		return true
	end
	return model:GetAttribute(ATTR.Downable) == true
end

function DownedService.isDowned(model: Model): boolean
	return downed[model] ~= nil
end

-- Derruba o modelo. attacker = quem deu o tiro (para o kill feed).
function DownedService.down(model: Model, humanoid: Humanoid, attacker: Player?)
	if downed[model] or humanoid.Health <= 0 then
		return
	end
	local root = rootOf(model)
	local regen = model:FindFirstChild("Health")
	local state: DownedState = {
		model = model,
		humanoid = humanoid,
		player = Players:GetPlayerFromCharacter(model),
		walkSpeed = humanoid.WalkSpeed,
		maxHealth = humanoid.MaxHealth,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		regenScript = if regen and regen:IsA("Script") then regen else nil,
		prompts = {},
		holds = {},
		connections = {},
	}
	downed[model] = state

	humanoid:UnequipTools()
	humanoid.WalkSpeed = DownedConfig.CrawlSpeed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	-- A regeneração padrão do Roblox curaria o sangramento
	if state.regenScript then
		state.regenScript.Enabled = false
	end
	-- o sangue do derrubado pode passar da vida normal (Rob Run: 150), então a vida
	-- máxima sobe enquanto está no chão e volta ao levantar
	humanoid.MaxHealth = DownedConfig.DownedHealth
	humanoid.Health = DownedConfig.DownedHealth
	-- Caiu = placas quebradas; tiros no chão vão direto no sangue
	ArmorService.strip(model)
	model:SetAttribute(ATTR.Downed, true)

	local victim = state.player
	if root then
		addPrompt(state, root, PROMPTS.Revive, "Reviver", DownedConfig.ReviveHoldSeconds, Enum.KeyCode.E, Enum.KeyCode.ButtonX, function(player: Player): boolean
			-- NPC de teste pode ser revivido por qualquer um que não seja civil
			if not victim then
				return Factions.canDamage(player, nil)
			end
			return Factions.areAllies(player, victim)
		end, function(player: Player)
			revive(state, player)
		end)
		addPrompt(state, root, PROMPTS.Finish, "Finalizar", DownedConfig.FinishHoldSeconds, Enum.KeyCode.F, Enum.KeyCode.ButtonY, function(player: Player): boolean
			return Factions.canDamage(player, victim)
		end, function(player: Player)
			kill(state, "Finished", player)
			WantedService.onFinished(player, state.model, state.player)
		end)
	end

	table.insert(state.connections, humanoid.Died:Connect(function()
		clear(state, false)
	end))
	table.insert(state.connections, model.Destroying:Connect(function()
		clear(state, false)
	end))

	feed("Downed", attacker, model.Name)
end

-- Chamado pelo combate quando um tiro mata quem já estava derrubado
function DownedService.finishedByShot(model: Model, attacker: Player)
	local state = downed[model]
	if not state then
		return
	end
	clear(state, false)
	feed("Finished", attacker, model.Name)
end

function DownedService:Init()
	feedRemote = Net.serverEvent(CombatContract.Remotes.Feed)
end

function DownedService:Start()
	local bleedPerSecond = DownedConfig.DownedHealth / DownedConfig.BleedOutSeconds
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < BLEED_TICK then
			return
		end
		local step = accumulator
		accumulator = 0
		for _, state in downed do
			local health = state.humanoid.Health - bleedPerSecond * step
			if health <= 0 then
				kill(state, "BledOut", nil)
			else
				state.humanoid.Health = health
			end
		end
	end)
end

return DownedService
