--!strict
-- P1
-- Uma barrinha por placa do colete, logo acima da barra de itens, e as placas extras da mochila.
-- Sem barra de vida (decisão de design): a borda do cartão pisca vermelha quando derrubado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))
local ArmorConfig = require(Shared:WaitForChild("Config"):WaitForChild("Armor"))

local ATTR = CombatContract.Attributes

-- Aparência (UX do cliente, não é balanceamento)
local REF_H = 1080
local WIDTH = 300 -- px
local HOTBAR_CLEARANCE = 150 -- px acima da borda de baixo (ref 1080p), acima da hotbar do HotbarController
local PLATE_HEIGHT = 12
local ROW_HEIGHT = 32 -- altura da linha (badge de placas extras)
local GAP = 6
local CARD_PAD_X = 12
local CARD_PAD_Y = 10
local BADGE_GAP = 10
local BADGE_WIDTH = 52

local GLASS = Color3.fromRGB(10, 11, 15)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DOWNED_COLOR = Color3.fromRGB(255, 90, 74)
local PLATE_COLOR = Color3.fromRGB(70, 170, 255)
local PLATING_COLOR = Color3.fromRGB(170, 220, 255)
local EMPTY_COLOR = Color3.fromRGB(8, 9, 12)
local SMOOTH = 14 -- velocidade com que as barras acompanham o valor real

local IMG_SHIELD = "rbxassetid://109480723605696"
local FONT_NUM = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)

local PlayerHudController = {}

local player = Players.LocalPlayer

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function bar(parent: Instance, position: UDim2, size: UDim2, radius: number): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = EMPTY_COLOR
	back.BackgroundTransparency = 0.28
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 1
	stroke.Transparency = 0.92
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, radius)
	fillCorner.Parent = fill
	return back, fill
end

function PlayerHudController:Start()
	-- sem barra de vida no jogo: esconde também a padrão do Roblox
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- referência 1920x1080 escalada pela altura do viewport (mesmo padrão do HudController)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Parent = gui
	local rootScale = Instance.new("UIScale")
	rootScale.Parent = root

	local vpConn: RBXScriptConnection? = nil
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local s = math.max(vp.Y, 1) / REF_H
		rootScale.Scale = s
		root.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	end
	local function bindCamera()
		if vpConn then
			vpConn:Disconnect()
			vpConn = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			fit()
			vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		end
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

	local barsHeight = ROW_HEIGHT
	local cardWidth = CARD_PAD_X * 2 + WIDTH + BADGE_GAP + BADGE_WIDTH
	local cardHeight = CARD_PAD_Y * 2 + barsHeight

	local container = Instance.new("Frame")
	container.Name = "VitalsCard"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -HOTBAR_CLEARANCE)
	container.Size = UDim2.fromOffset(cardWidth, cardHeight)
	container.BackgroundColor3 = GLASS
	container.BackgroundTransparency = 0.22
	container.BorderSizePixel = 0
	container.Parent = root
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = container
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = WHITE
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.84
	cardStroke.Parent = container

	local barsArea = Instance.new("Frame")
	barsArea.Name = "Bars"
	barsArea.Position = UDim2.fromOffset(CARD_PAD_X, CARD_PAD_Y)
	barsArea.Size = UDim2.fromOffset(WIDTH, barsHeight)
	barsArea.BackgroundTransparency = 1
	barsArea.Parent = container

	-- uma barrinha por placa
	local plateCount = ArmorConfig.MaxPlates
	local plateWidth = (WIDTH - GAP * (plateCount - 1)) / plateCount
	local plateFills: { Frame } = {}
	for i = 1, plateCount do
		local _, fill = bar(barsArea, UDim2.fromOffset((i - 1) * (plateWidth + GAP), (ROW_HEIGHT - PLATE_HEIGHT) / 2), UDim2.fromOffset(plateWidth, PLATE_HEIGHT), 3)
		fill.BackgroundColor3 = PLATE_COLOR
		table.insert(plateFills, fill)
	end

	-- placas extras na mochila, à direita das barrinhas
	local badge = Instance.new("Frame")
	badge.Name = "PlatesBadge"
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -CARD_PAD_X, 0.5, 0)
	badge.Size = UDim2.fromOffset(BADGE_WIDTH, barsHeight)
	badge.BackgroundColor3 = EMPTY_COLOR
	badge.BackgroundTransparency = 0.35
	badge.BorderSizePixel = 0
	badge.Parent = container
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 9)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = PLATE_COLOR
	badgeStroke.Thickness = 1.5
	badgeStroke.Transparency = 0.55
	badgeStroke.Parent = badge

	local badgeList = Instance.new("UIListLayout")
	badgeList.FillDirection = Enum.FillDirection.Horizontal
	badgeList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	badgeList.VerticalAlignment = Enum.VerticalAlignment.Center
	badgeList.SortOrder = Enum.SortOrder.LayoutOrder
	badgeList.Padding = UDim.new(0, 4)
	badgeList.Parent = badge

	local shieldIcon = Instance.new("ImageLabel")
	shieldIcon.Name = "Icon"
	shieldIcon.Size = UDim2.fromOffset(15, 15)
	shieldIcon.BackgroundTransparency = 1
	shieldIcon.Image = IMG_SHIELD
	shieldIcon.ImageColor3 = PLATE_COLOR
	shieldIcon.ScaleType = Enum.ScaleType.Fit
	shieldIcon.LayoutOrder = 1
	shieldIcon.Parent = badge

	local carriedLabel = Instance.new("TextLabel")
	carriedLabel.Name = "Count"
	carriedLabel.Size = UDim2.fromOffset(0, 22)
	carriedLabel.AutomaticSize = Enum.AutomaticSize.X
	carriedLabel.BackgroundTransparency = 1
	carriedLabel.FontFace = FONT_NUM
	carriedLabel.TextSize = 18
	carriedLabel.TextColor3 = PLATE_COLOR
	carriedLabel.Text = "x0"
	carriedLabel.LayoutOrder = 2
	carriedLabel.Parent = badge
	local carriedTextStroke = Instance.new("UIStroke")
	carriedTextStroke.Color = BLACK
	carriedTextStroke.Thickness = 1
	carriedTextStroke.Transparency = 0.6
	carriedTextStroke.Parent = carriedLabel

	local carriedScale = Instance.new("UIScale")
	carriedScale.Parent = carriedLabel

	local shownArmor = 0
	local lastCarried = -1

	RunService.RenderStepped:Connect(function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		container.Visible = humanoid ~= nil
		if not character or not humanoid then
			return
		end
		local alpha = 1 - math.exp(-SMOOTH * dt)
		local now = os.clock()

		if character:GetAttribute(ATTR.Downed) == true then
			local lowWave = 0.5 - 0.5 * math.cos(now * math.pi / 0.65)
			cardStroke.Color = DOWNED_COLOR
			cardStroke.Transparency = 0.45 + 0.35 * lowWave
		else
			cardStroke.Color = WHITE
			cardStroke.Transparency = 0.84
		end

		local armorTarget = numberAttribute(character, ATTR.Vest)
		shownArmor += (armorTarget - shownArmor) * alpha
		local plateHealth = ArmorConfig.PlateHealth
		local plating = character:GetAttribute(ATTR.Plating) == true
		local plateWave = if plating then (0.5 - 0.5 * math.cos(now * math.pi / 0.4)) else 0
		for i, fill in plateFills do
			local amount = math.clamp((shownArmor - (i - 1) * plateHealth) / plateHealth, 0, 1)
			fill.Size = UDim2.fromScale(amount, 1)
			fill.BackgroundColor3 = if plating then PLATING_COLOR else PLATE_COLOR
			fill.BackgroundTransparency = if plating then (0.35 * plateWave) else 0
		end

		local carried = numberAttribute(player, ATTR.PlatesCarried)
		if carried ~= lastCarried then
			carriedLabel.Text = ("x%d"):format(carried)
			if lastCarried >= 0 then
				carriedScale.Scale = 1.28
				TweenService:Create(carriedScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			lastCarried = carried
		end
	end)
end

return PlayerHudController
