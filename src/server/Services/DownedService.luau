--!strict
-- Estado derrubado: quando um tiro zeraria a vida, o personagem cai em vez de morrer.
-- Derrubado rasteja, não atira/reequipa arma e sangra. Aliado revive segurando E;
-- inimigo finaliza segurando F ou atirando. Validação contínua de distância, LoS e hold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local DownedConfig = require(ReplicatedStorage.Shared.Config.Downed)
local Combat = script.Parent.Parent.Combat
local Factions = require(Combat.Factions)
local DownedRules = require(Combat.DownedRules)
local DownedPrompts = require(Combat.DownedPrompts)
local ArmorService = require(script.Parent.ArmorService)
local KillFeedService = require(script.Parent.KillFeedService)
local FactionService = require(script.Parent.FactionService)
local WantedService = require(script.Parent.WantedService)

type FeedKind = CombatContract.FeedKind
type ActiveHold = DownedPrompts.ActiveHold

type DownedState = {
	model: Model,
	humanoid: Humanoid,
	player: Player?,
	jumpPower: number,
	jumpHeight: number,
	maxHealth: number,
	regenScript: Script?,
	prompts: { ProximityPrompt },
	holds: { [ProximityPrompt]: { [Player]: ActiveHold } },
	connections: { RBXScriptConnection },
}

local ATTR = CombatContract.Attributes
local PROMPTS = CombatContract.Prompts
local TICK_INTERVAL = DownedConfig.HoldCheckInterval or 0.1
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

-- Sai do estado derrubado. restore = levantou (volta WalkSpeed base, pulo e regeneração).
local function clear(state: DownedState, restore: boolean)
	if downed[state.model] ~= state then
		return
	end
	downed[state.model] = nil
	DownedPrompts.clearOwner(state)
	for _, connection in state.connections do
		connection:Disconnect()
	end
	if state.model.Parent then
		state.model:SetAttribute(ATTR.Downed, nil)
	end
	if restore then
		state.humanoid.MaxHealth = state.maxHealth
		state.humanoid.WalkSpeed = DownedConfig.BaseWalkSpeed
		state.humanoid.JumpPower = state.jumpPower
		state.humanoid.JumpHeight = state.jumpHeight
		if state.regenScript then
			state.regenScript.Enabled = true
		end
	end
end

-- Quem interage precisa estar vivo, de pé, perto e com linha de visão desobstruída
local function evaluateInteract(interactor: Player, state: DownedState): (boolean, string?)
	local character = interactor.Character
	if not character then
		return false, "no_character"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local isDowned = downed[character] ~= nil or character:GetAttribute(ATTR.Downed) == true
	local from, to = rootOf(character), rootOf(state.model)
	if not from or not to then
		return false, "missing_root"
	end
	local distance = (from.Position - to.Position).Magnitude
	local maxDist = DownedConfig.InteractDistance + DISTANCE_SLACK
	local hasLos = distance <= maxDist and DownedRules.hasLineOfSight(from.Position, to.Position, { character, state.model })
	return DownedRules.canInteract({
		interactorAlive = alive,
		interactorDowned = isDowned,
		isSameModel = character == state.model,
		distance = distance,
		maxDistance = maxDist,
		hasLineOfSight = hasLos,
	})
end

local function revive(state: DownedState, by: Player)
	pcall(KillFeedService.clearNote, KillFeedService, state.model)
	clear(state, true)
	state.humanoid.Health = math.min(DownedConfig.ReviveHealth, state.humanoid.MaxHealth)
	feed("Revived", by, state.model.Name)
end

local function kill(state: DownedState, kind: FeedKind, by: Player?)
	if kind == "Finished" and by then
		local killerRoot = by.Character and rootOf(by.Character)
		local victimRoot = rootOf(state.model)
		local distance: number? = if killerRoot and victimRoot
			then (killerRoot.Position - victimRoot.Position).Magnitude
			else nil
		pcall(KillFeedService.noteLethalHit, KillFeedService, state.model, by, "Finalização", distance, false, false)
		pcall(WantedService.onFinished, by, state.model, state.player)
	end
	clear(state, false)
	state.humanoid.Health = 0
	feed(kind, by, state.model.Name)
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

function DownedService.canInteract(interactor: Player, model: Model): (boolean, string?)
	local state = downed[model]
	if not state then
		return false, "not_downed"
	end
	return evaluateInteract(interactor, state)
end

function DownedService.isInteracting(player: Player): boolean
	return DownedPrompts.isInteracting(player)
end

function DownedService.cancelInteractor(player: Player)
	DownedPrompts.cancelInteractor(player, downed :: any)
end

-- Derruba o modelo. attacker = quem deu o tiro (para o kill feed).
function DownedService.down(model: Model, humanoid: Humanoid, attacker: Player?)
	if downed[model] or humanoid.Health <= 0 then
		return
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	if victimPlayer then
		DownedService.cancelInteractor(victimPlayer)
		pcall(FactionService.cancelTransition, victimPlayer, "downed")
	end
	local root = rootOf(model)
	local regen = model:FindFirstChild("Health")
	local state: DownedState = {
		model = model,
		humanoid = humanoid,
		player = victimPlayer,
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
	if state.regenScript then
		state.regenScript.Enabled = false
	end
	humanoid.MaxHealth = DownedConfig.DownedHealth
	humanoid.Health = DownedConfig.DownedHealth
	ArmorService.strip(model)
	model:SetAttribute(ATTR.Downed, true)

	-- Impede reequipar qualquer Tool enquanto está no chão
	table.insert(state.connections, model.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and downed[model] == state then
			task.defer(function()
				if downed[model] == state and child.Parent == model then
					humanoid:UnequipTools()
				end
			end)
		end
	end))

	local victim = state.player
	if root then
		local isActive = function(): boolean return downed[model] == state end
		local evalFor = function(player: Player): (boolean, string?) return evaluateInteract(player, state) end
		DownedPrompts.attach(state, root, {
			name = PROMPTS.Revive, actionText = "Reviver", holdSeconds = DownedConfig.ReviveHoldSeconds,
			keyboardKey = Enum.KeyCode.E, gamepadKey = Enum.KeyCode.ButtonX,
			allowed = function(player: Player): boolean
				return if not victim then Factions.canDamage(player, nil) else Factions.areAllies(player, victim)
			end,
			onDone = function(player: Player) revive(state, player) end,
		}, isActive, evalFor)
		DownedPrompts.attach(state, root, {
			name = PROMPTS.Finish, actionText = "Finalizar", holdSeconds = DownedConfig.FinishHoldSeconds,
			keyboardKey = Enum.KeyCode.F, gamepadKey = Enum.KeyCode.ButtonY,
			allowed = function(player: Player): boolean return Factions.canFinish(player, victim) end,
			onDone = function(player: Player) kill(state, "Finished", player) end,
		}, isActive, evalFor)
	end

	table.insert(state.connections, humanoid.Died:Connect(function() clear(state, false) end))
	table.insert(state.connections, model.Destroying:Connect(function() clear(state, false) end))

	feed("Downed", attacker, model.Name)
end

-- Chamado pelo combate ANTES de zerar a vida de quem já estava derrubado
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
	Players.PlayerRemoving:Connect(function(player: Player)
		DownedService.cancelInteractor(player)
	end)

	local bleedPerSecond = DownedConfig.DownedHealth / DownedConfig.BleedOutSeconds
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		for _, state in downed do
			DownedPrompts.tickOwner(state, now, function(player: Player): (boolean, string?)
				return evaluateInteract(player, state)
			end)
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