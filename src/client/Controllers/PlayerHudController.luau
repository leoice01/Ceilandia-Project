--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P1 assume o HUD depois).
-- Barra de vida (verde; vermelha quando derrubado) e uma barrinha por placa do colete,
-- logo acima da barra de itens do Roblox. Mostra também as placas extras da mochila.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))
local ArmorConfig = require(Shared:WaitForChild("Config"):WaitForChild("Armor"))

local ATTR = CombatContract.Attributes

-- Aparência (UX do cliente, não é balanceamento)
local WIDTH = 300 -- px
local HOTBAR_CLEARANCE = 80 -- px acima da borda de baixo, para ficar em cima da barra de itens
local PLATE_HEIGHT = 10
local HEALTH_HEIGHT = 12
local GAP = 4
local HEALTH_COLOR = Color3.fromRGB(80, 220, 100)
local DOWNED_COLOR = Color3.fromRGB(230, 60, 60)
local PLATE_COLOR = Color3.fromRGB(70, 170, 255)
local PLATING_COLOR = Color3.fromRGB(170, 220, 255)
local EMPTY_COLOR = Color3.fromRGB(20, 20, 24)
local SMOOTH = 14 -- velocidade com que as barras acompanham o valor real

local PlayerHudController = {}

local player = Players.LocalPlayer

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function bar(parent: Instance, position: UDim2, size: UDim2): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = EMPTY_COLOR
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill
	return back, fill
end

function PlayerHudController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -HOTBAR_CLEARANCE)
	container.Size = UDim2.fromOffset(WIDTH, PLATE_HEIGHT + GAP + HEALTH_HEIGHT)
	container.BackgroundTransparency = 1
	container.Parent = gui

	-- uma barrinha por placa
	local plateCount = ArmorConfig.MaxPlates
	local plateWidth = (WIDTH - GAP * (plateCount - 1)) / plateCount
	local plateFills: { Frame } = {}
	for i = 1, plateCount do
		local _, fill = bar(container, UDim2.fromOffset((i - 1) * (plateWidth + GAP), 0), UDim2.fromOffset(plateWidth, PLATE_HEIGHT))
		fill.BackgroundColor3 = PLATE_COLOR
		table.insert(plateFills, fill)
	end

	local _, healthFill = bar(container, UDim2.fromOffset(0, PLATE_HEIGHT + GAP), UDim2.fromOffset(WIDTH, HEALTH_HEIGHT))
	healthFill.BackgroundColor3 = HEALTH_COLOR

	-- placas extras na mochila, à direita das barrinhas
	local carriedLabel = Instance.new("TextLabel")
	carriedLabel.AnchorPoint = Vector2.new(0, 0.5)
	carriedLabel.Position = UDim2.new(1, 8, 0, PLATE_HEIGHT / 2)
	carriedLabel.Size = UDim2.fromOffset(60, 18)
	carriedLabel.BackgroundTransparency = 1
	carriedLabel.Font = Enum.Font.GothamBold
	carriedLabel.TextSize = 14
	carriedLabel.TextColor3 = PLATE_COLOR
	carriedLabel.TextStrokeTransparency = 0.4
	carriedLabel.TextXAlignment = Enum.TextXAlignment.Left
	carriedLabel.Parent = container

	local shownHealth = 1
	local shownArmor = 0

	RunService.RenderStepped:Connect(function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		container.Visible = humanoid ~= nil
		if not character or not humanoid then
			return
		end
		local alpha = 1 - math.exp(-SMOOTH * dt)

		local healthTarget = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
		shownHealth += (healthTarget - shownHealth) * alpha
		healthFill.Size = UDim2.fromScale(shownHealth, 1)
		healthFill.BackgroundColor3 = if character:GetAttribute(ATTR.Downed) == true then DOWNED_COLOR else HEALTH_COLOR

		local armorTarget = numberAttribute(character, ATTR.Vest)
		shownArmor += (armorTarget - shownArmor) * alpha
		local plateHealth = ArmorConfig.PlateHealth
		local plating = character:GetAttribute(ATTR.Plating) == true
		for i, fill in plateFills do
			local amount = math.clamp((shownArmor - (i - 1) * plateHealth) / plateHealth, 0, 1)
			fill.Size = UDim2.fromScale(amount, 1)
			fill.BackgroundColor3 = if plating then PLATING_COLOR else PLATE_COLOR
		end

		carriedLabel.Text = ("x%d"):format(numberAttribute(player, ATTR.PlatesCarried))
	end)
end

return PlayerHudController
