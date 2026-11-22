--!strict
-- Roubos. Qualquer BasePart com a tag Robbable e o atributo RobberyType (Shared/Config/Robbery)
-- ganha um botão "Roubar". O servidor controla tudo: começo, tempo, interrupção, conclusão e
-- intervalo. O cliente só aperta o ProximityPrompt do Roblox.
--   * um ladrão por vez em cada alvo (o botão some enquanto alguém rouba ou no intervalo)
--   * interrompe se o ladrão morrer, cair, sair de perto, sair do jogo ou virar policial
--   * ao concluir: crime no WantedService (estrelas, alerta e ocorrência da polícia)
-- Estado no próprio alvo (atributos, replicados): RobberyState "Idle" | "InProgress" |
-- "Cooldown", RobberyProgress (0..1), RobberyCooldownEnd (hora do servidor).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Notice = require(ReplicatedStorage.Shared.Lib.Notice)
local RobberyConfig = require(ReplicatedStorage.Shared.Config.Robbery)
local Factions = require(script.Parent.Parent.Combat.Factions)
local WantedService = require(script.Parent.WantedService)

type RobberyType = RobberyConfig.RobberyType

local ATTR = CombatContract.Attributes
local DISTANCE_SLACK = 2 -- folga de rede (studs)
local BEEP_SOUND = "rbxasset://sounds/electronicpingshort.wav" -- som embutido do Roblox
local ALARM_ON = Color3.fromRGB(255, 40, 40)
local ALARM_OFF = Color3.fromRGB(120, 20, 20)

type Target = {
	part: BasePart,
	config: RobberyType,
	prompt: ProximityPrompt,
	billboard: BillboardGui,
	title: TextLabel,
	fill: Frame,
	alarm: BasePart?,
	alarmLight: PointLight?,
	beep: Sound,
	robber: Player?,
	token: number,
}

local RobberyService = {}

local targets: { [BasePart]: Target } = {}
local lastTry: { [Player]: number } = {}

local function setState(target: Target, state: string, progress: number)
	target.part:SetAttribute("RobberyState", state)
	target.part:SetAttribute("RobberyProgress", progress)
	target.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	local alarmOn = state == "InProgress"
	if target.alarm then
		target.alarm.Color = if alarmOn then ALARM_ON else ALARM_OFF
		target.alarm.Material = if alarmOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if target.alarmLight then
		target.alarmLight.Enabled = alarmOn
	end
end

local function canRob(player: Player, target: Target): (boolean, string?)
	if Factions.of(player) ~= CombatContract.Factions.Robber then
		return false, "Só ladrões podem roubar."
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return false, "Você precisa estar vivo."
	end
	if character:GetAttribute(ATTR.Downed) == true then
		return false, "Você está derrubado."
	end
	if (root.Position - target.part.Position).Magnitude > target.config.MaxDistance + DISTANCE_SLACK then
		return false, "Você se afastou demais."
	end
	return true, nil
end

local function reset(target: Target)
	target.robber = nil
	target.billboard.Enabled = false
	target.prompt.Enabled = true
	setState(target, "Idle", 0)
end

local function startCooldown(target: Target)
	local cooldown = target.config.Cooldown
	local ends = workspace:GetServerTimeNow() + cooldown
	target.part:SetAttribute("RobberyCooldownEnd", ends)
	setState(target, "Cooldown", 1)
	target.billboard.Enabled = true
	local token = target.token
	task.spawn(function()
		while target.token == token and workspace:GetServerTimeNow() < ends do
			target.title.Text = ("%s — vazio (%d s)"):format(target.config.Label, math.ceil(ends - workspace:GetServerTimeNow()))
			task.wait(1)
		end
		if target.token == token then
			reset(target)
		end
	end)
end

local function finish(target: Target, player: Player)
	local config = target.config
	target.robber = nil
	startCooldown(target)
	if config.Reward > 0 then
		local cash = player:GetAttribute("Cash")
		player:SetAttribute("Cash", (if typeof(cash) == "number" then cash else 0) + config.Reward)
	end
	-- crime: estrelas, alerta da polícia e ocorrência (WantedService + IncidentService)
	WantedService.reportCrime(player, config.Crime, target.part.Position, { key = target.part:GetFullName() })
	Notice.send(player, "Roubo concluído", ("%s roubado! A polícia foi alertada."):format(config.Label))
end

local function cancel(target: Target, player: Player?, reason: string)
	target.token += 1
	reset(target)
	if player and player.Parent then
		Notice.send(player, "Roubo interrompido", reason)
	end
end

local function begin(target: Target, player: Player)
	target.token += 1
	local token = target.token
	target.robber = player
	target.prompt.Enabled = false -- ninguém mais começa este alvo agora
	target.billboard.Enabled = true
	target.title.Text = ("Roubando: %s"):format(target.config.Label)
	setState(target, "InProgress", 0)
	Notice.send(player, "Roubo", ("Fique perto do %s por %d s."):format(target.config.Label:lower(), target.config.Duration))

	task.spawn(function()
		local started = os.clock()
		local lastBeep = -1
		while target.token == token do
			task.wait(RobberyConfig.CheckInterval)
			if target.token ~= token then
				return
			end
			if not player.Parent then
				cancel(target, nil, "")
				return
			end
			local ok, reason = canRob(player, target)
			if not ok then
				cancel(target, player, reason or "Condições perdidas.")
				return
			end
			local elapsed = os.clock() - started
			setState(target, "InProgress", elapsed / target.config.Duration)
			local second = math.floor(elapsed)
			if second ~= lastBeep then
				lastBeep = second
				target.beep:Play()
			end
			if elapsed >= target.config.Duration then
				finish(target, player)
				return
			end
		end
	end)
end

local function tryStart(player: Player, target: Target)
	local now = os.clock()
	local last = lastTry[player]
	if last and now - last < RobberyConfig.PromptSpamCooldown then
		return -- spam do botão
	end
	lastTry[player] = now
	local state = target.part:GetAttribute("RobberyState")
	if state == "InProgress" then
		Notice.send(player, "Roubo", "Alguém já está roubando aqui.")
		return
	elseif state == "Cooldown" then
		Notice.send(player, "Roubo", "Já foi roubado. Volte mais tarde.")
		return
	end
	if RobberyService.isRobbing(player) then
		return
	end
	local ok, reason = canRob(player, target)
	if not ok then
		Notice.send(player, "Roubo", reason or "Agora não dá.")
		return
	end
	begin(target, player)
end

local function setup(instance: Instance)
	if not instance:IsA("BasePart") or targets[instance] then
		return
	end
	local typeName = instance:GetAttribute(RobberyConfig.TypeAttribute)
	local config = if typeof(typeName) == "string" then RobberyConfig.Types[typeName] else nil
	if not config then
		warn(("[RobberyService] %s sem RobberyType válido"):format(instance:GetFullName()))
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Rob"
	prompt.ActionText = "Roubar"
	prompt.ObjectText = config.Label
	prompt.HoldDuration = 0 -- o tempo do roubo é contado no servidor
	prompt.MaxActivationDistance = math.max(config.MaxDistance - 2, 4)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom -- desenhado pelo PromptController
	prompt.Parent = instance

	-- placa com o progresso em cima do alvo (no mundo, não é interface nova)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RobberyStatus"
	billboard.Size = UDim2.fromOffset(240, 58)
	billboard.StudsOffset = Vector3.new(0, instance.Size.Y / 2 + 2.2, 0)
	billboard.MaxDistance = 80
	billboard.Enabled = false
	billboard.Parent = instance
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.4
	title.Parent = billboard
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 0, 0, 32)
	bar.Size = UDim2.new(1, 0, 0, 16)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local alarm: BasePart? = nil
	local alarmLight: PointLight? = nil
	if instance.Parent then
		for _, sibling in instance.Parent:GetChildren() do
			if sibling:IsA("BasePart") and sibling:GetAttribute("Role") == "RobberyAlarm" then
				alarm = sibling
				local light = Instance.new("PointLight")
				light.Color = ALARM_ON
				light.Range = 20
				light.Brightness = 3
				light.Enabled = false
				light.Parent = sibling
				alarmLight = light
				break
			end
		end
	end

	local beep = Instance.new("Sound")
	beep.Name = "RobberyBeep"
	beep.SoundId = BEEP_SOUND
	beep.Volume = 0.8
	beep.RollOffMaxDistance = 90
	beep.Parent = instance

	local target: Target = {
		part = instance,
		config = config,
		prompt = prompt,
		billboard = billboard,
		title = title,
		fill = fill,
		alarm = alarm,
		alarmLight = alarmLight,
		beep = beep,
		robber = nil,
		token = 0,
	}
	targets[instance] = target
	reset(target)
	prompt.Triggered:Connect(function(player: Player)
		tryStart(player, target)
	end)
end

function RobberyService.isRobbing(player: Player): boolean
	for _, target in targets do
		if target.robber == player then
			return true
		end
	end
	return false
end

function RobberyService:Start()
	for _, instance in CollectionService:GetTagged(RobberyConfig.Tag) do
		setup(instance)
	end
	CollectionService:GetInstanceAddedSignal(RobberyConfig.Tag):Connect(setup)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTry[player] = nil
		for _, target in targets do
			if target.robber == player then
				cancel(target, nil, "")
			end
		end
	end)
end

return RobberyService
