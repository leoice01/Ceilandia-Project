--!strict
-- Desenha os ProximityPrompts com Style = Custom (botões da delegacia e dos roubos).
-- O balão padrão do Roblox é desenhado pela interface do próprio Roblox, que às vezes não
-- carrega no Studio; aí o jogador não vê o botão. Com Style = Custom, este controller
-- mostra o balão numa ScreenGui (interface 2D, que sempre aparece), seguindo a posição do
-- objeto na tela: tecla, ação, objeto e a barra de segurar. Apertar a tecla continua sendo
-- do Roblox; no celular o toque no balão segura/solta o botão.

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CARD_SIZE = Vector2.new(230, 64)
local HEIGHT_OFFSET = 1.5 -- studs acima do objeto
local BG = Color3.fromRGB(18, 20, 26)
local ACCENT = Color3.fromRGB(70, 140, 255)

local PromptController = {}

local player = Players.LocalPlayer
local gui: ScreenGui

type Card = {
	root: TextButton,
	fill: Frame,
	adornee: Instance,
	holdStart: number?,
	connections: { RBXScriptConnection },
}

local cards: { [ProximityPrompt]: Card } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "Toque"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function label(parent: Instance, text: string, size: number, position: UDim2, width: UDim, color: Color3, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = UDim2.new(width, UDim.new(0, size + 4))
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color
	l.Text = text
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

-- posição no mundo do objeto do botão
local function worldPosition(adornee: Instance): Vector3?
	if adornee:IsA("BasePart") then
		return adornee.Position + Vector3.new(0, adornee.Size.Y / 2 + HEIGHT_OFFSET, 0)
	elseif adornee:IsA("Attachment") then
		return adornee.WorldPosition + Vector3.new(0, HEIGHT_OFFSET, 0)
	elseif adornee:IsA("Model") then
		return adornee:GetPivot().Position + Vector3.new(0, HEIGHT_OFFSET, 0)
	end
	return nil
end

local function hide(prompt: ProximityPrompt)
	local card = cards[prompt]
	if not card then
		return
	end
	cards[prompt] = nil
	for _, connection in card.connections do
		connection:Disconnect()
	end
	card.root:Destroy()
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end
	hide(prompt)
	local adornee = prompt.Parent
	if not adornee or not worldPosition(adornee) then
		return
	end

	local card = Instance.new("TextButton")
	card.Name = "Prompt"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	card.BackgroundColor3 = BG
	card.BackgroundTransparency = 0.15
	card.AutoButtonColor = false
	card.Text = ""
	card.Visible = false
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local keyBox = Instance.new("Frame")
	keyBox.Position = UDim2.fromOffset(10, 12)
	keyBox.Size = UDim2.fromOffset(40, 40)
	keyBox.BackgroundColor3 = Color3.new(1, 1, 1)
	keyBox.Parent = card
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 8)
	keyCorner.Parent = keyBox
	local key = label(keyBox, keyText(prompt, inputType), 16, UDim2.fromOffset(0, 9), UDim.new(1, 0), BG, true)
	key.TextXAlignment = Enum.TextXAlignment.Center
	key.TextScaled = #key.Text > 2
	key.Size = UDim2.new(1, 0, 0, 22)

	label(card, prompt.ObjectText, 12, UDim2.fromOffset(60, 10), UDim.new(1, -68), Color3.fromRGB(180, 186, 200), false)
	label(card, prompt.ActionText, 17, UDim2.fromOffset(60, 26), UDim.new(1, -68), Color3.new(1, 1, 1), true)

	-- barra de segurar
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 60, 1, -9)
	bar.Size = UDim2.new(1, -70, 0, 4)
	bar.BackgroundColor3 = Color3.fromRGB(60, 64, 76)
	bar.BorderSizePixel = 0
	bar.Visible = prompt.HoldDuration > 0
	bar.Parent = card
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local entry: Card = { root = card, fill = fill, adornee = adornee, holdStart = nil, connections = {} }
	cards[prompt] = entry

	table.insert(entry.connections, prompt.PromptButtonHoldBegan:Connect(function()
		entry.holdStart = os.clock()
	end))
	table.insert(entry.connections, prompt.PromptButtonHoldEnded:Connect(function()
		entry.holdStart = nil
		fill.Size = UDim2.fromScale(0, 1)
	end))
	table.insert(entry.connections, prompt.Triggered:Connect(function()
		entry.holdStart = nil
		fill.Size = UDim2.fromScale(1, 1)
	end))
	-- toque/clique no balão (celular): segura enquanto o dedo estiver em cima
	table.insert(entry.connections, card.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	table.insert(entry.connections, card.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
	table.insert(entry.connections, prompt.AncestryChanged:Connect(function()
		if not prompt:IsDescendantOf(workspace) then
			hide(prompt)
		end
	end))
end

local function update()
	local camera = workspace.CurrentCamera
	for prompt, card in cards do
		local position = worldPosition(card.adornee)
		if position then
			local point, onScreen = camera:WorldToViewportPoint(position)
			card.root.Visible = onScreen
			card.root.Position = UDim2.fromOffset(point.X, point.Y)
		else
			card.root.Visible = false
		end
		local started = card.holdStart
		if started and prompt.HoldDuration > 0 then
			card.fill.Size = UDim2.fromScale(math.clamp((os.clock() - started) / prompt.HoldDuration, 0, 1), 1)
		end
	end
end

function PromptController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Prompts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- posição igual à da câmera (WorldToViewportPoint)
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
end

function PromptController:Start()
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
	RunService.RenderStepped:Connect(update)
end

return PromptController
