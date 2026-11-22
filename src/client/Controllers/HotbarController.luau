--!strict
-- Barra de atalhos própria (substitui a mochila padrão do Roblox, que às vezes não carrega
-- no Studio e deixa o jogador sem trocar de arma). Teclas 1–9, toque no slot (celular),
-- D-pad esquerda/direita (controle). Mesma tecla da arma na mão = guardar (com animação).
-- Ordem: arma principal, secundária, depois os outros itens na ordem em que chegaram.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))

local ATTR = CombatContract.Attributes
local MAX_SLOTS = 9
local SLOT_SIZE = 64
local SLOT_GAP = 6
local CORE_GUI_RETRIES = 20
local KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}
local SLOT_RANK: { [string]: number } = { Primary = 1, Secondary = 2 }
local IDLE_COLOR = Color3.fromRGB(20, 20, 24)
local ACTIVE_COLOR = Color3.fromRGB(70, 140, 255)

local HotbarController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local bar: Frame
local order: { Tool } = {} -- ordem de chegada dos itens
local slots: { Tool } = {} -- ordem mostrada
local slotFrames: { Frame } = {}
local watched: { [Tool]: RBXScriptConnection } = {}
local character: Model? = nil

local function equippedTool(): Tool?
	return if character then character:FindFirstChildOfClass("Tool") else nil
end

local function owned(tool: Tool): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	return tool.Parent ~= nil and (tool.Parent == backpack or tool.Parent == character)
end

-- 1 = principal, 2 = secundária, 3 = outras armas (extras do Studio), 4 = itens.
-- Só a primeira arma de cada slot fica no lugar fixo.
local function ranker(list: { Tool }): (Tool) -> number
	local first: { [string]: Tool } = {}
	for _, tool in list do
		local slot = tool:GetAttribute(ATTR.Slot)
		if typeof(slot) == "string" and SLOT_RANK[slot] and not first[slot] then
			first[slot] = tool
		end
	end
	return function(tool: Tool): number
		local slot = tool:GetAttribute(ATTR.Slot)
		if typeof(slot) ~= "string" then
			return 4
		end
		return if first[slot] == tool then SLOT_RANK[slot] or 3 else 3
	end
end

local function slotText(tool: Tool): string
	local ammo = tool:GetAttribute(ATTR.Ammo)
	local reserve = tool:GetAttribute(ATTR.Reserve)
	if typeof(ammo) == "number" then
		return if typeof(reserve) == "number" then ("%d | %d"):format(ammo, reserve) else tostring(ammo)
	end
	return ""
end

local function newSlot(index: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Slot" .. index
	frame.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	frame.BackgroundColor3 = IDLE_COLOR
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Thickness = 2
	stroke.Color = ACTIVE_COLOR
	stroke.Enabled = false
	stroke.Parent = frame

	local function text(name: string, size: number, y: number, align: Enum.TextXAlignment): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 4, 0, y)
		label.Size = UDim2.new(1, -8, 0, size + 2)
		label.Font = Enum.Font.GothamBold
		label.TextSize = size
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.6
		label.TextXAlignment = align
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = frame
		return label
	end
	text("Key", 11, 2, Enum.TextXAlignment.Left).Text = tostring(index)
	text("ItemName", 12, 22, Enum.TextXAlignment.Center)
	text("Info", 10, 44, Enum.TextXAlignment.Center).TextColor3 = Color3.fromRGB(200, 200, 200)

	-- toque/clique no slot
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.Parent = frame
	button.Activated:Connect(function()
		HotbarController.select(index)
	end)
	frame.Parent = bar
	return frame
end

local function render()
	slots = {}
	for _, tool in order do
		if owned(tool) then
			table.insert(slots, tool)
		end
	end
	-- estável: armas principal/secundária na frente, o resto na ordem de chegada
	local position: { [Tool]: number } = {}
	for i, tool in slots do
		position[tool] = i
	end
	local rank = ranker(slots)
	table.sort(slots, function(a: Tool, b: Tool): boolean
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return position[a] < position[b]
	end)

	local current = equippedTool()
	local count = math.min(#slots, MAX_SLOTS)
	for i = 1, MAX_SLOTS do
		local tool = slots[i]
		local frame = slotFrames[i]
		if i <= count and tool then
			if not frame then
				frame = newSlot(i)
				slotFrames[i] = frame
			end
			frame.Visible = true
			frame.LayoutOrder = i
			;(frame:FindFirstChild("ItemName") :: TextLabel).Text = tool.Name
			;(frame:FindFirstChild("Info") :: TextLabel).Text = slotText(tool)
			local active = tool == current
			;(frame:FindFirstChild("Stroke") :: UIStroke).Enabled = active
			frame.BackgroundTransparency = if active then 0.15 else 0.35
		elseif frame then
			frame.Visible = false
		end
	end
	bar.Visible = count > 0
end

local function watch(tool: Instance)
	if not tool:IsA("Tool") or watched[tool] then
		return
	end
	if not table.find(order, tool) then
		table.insert(order, tool)
	end
	-- munição no slot
	watched[tool] = tool.AttributeChanged:Connect(render)
	tool.Destroying:Once(function()
		local connection = watched[tool]
		if connection then
			connection:Disconnect()
		end
		watched[tool] = nil
		local index = table.find(order, tool)
		if index then
			table.remove(order, index)
		end
		render()
	end)
end

-- Escolhe o slot: equipa; se já estava na mão, guarda (arma de fogo com animação)
function HotbarController.select(index: number)
	local tool = slots[index]
	local c = character
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	if not tool or not c or not humanoid or humanoid.Health <= 0 then
		return
	end
	if c:GetAttribute(ATTR.Downed) == true then
		return
	end
	if tool.Parent == c then
		if not WeaponController.holster() then
			humanoid:UnequipTools()
		end
		return
	end
	humanoid:EquipTool(tool)
end

local function cycle(step: number)
	if #slots == 0 then
		return
	end
	local current = equippedTool()
	local index = if current then table.find(slots, current) or 0 else 0
	local nextIndex = (index - 1 + step) % math.min(#slots, MAX_SLOTS) + 1
	HotbarController.select(nextIndex)
end

local function onInput(input: InputObject, processed: boolean)
	if processed then
		return -- digitando no chat etc.
	end
	local index = table.find(KEYS, input.KeyCode)
	if index then
		HotbarController.select(index)
	elseif input.KeyCode == Enum.KeyCode.DPadRight then
		cycle(1)
	elseif input.KeyCode == Enum.KeyCode.DPadLeft then
		cycle(-1)
	end
end

-- A mochila padrão do Roblox sai (as duas juntas brigariam pelas mesmas teclas).
-- SetCoreGuiEnabled falha se a interface do Roblox ainda não carregou: tenta de novo.
local function disableDefaultBackpack()
	for _ = 1, CORE_GUI_RETRIES do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

local function onCharacter(newCharacter: Model)
	character = newCharacter
	newCharacter.ChildAdded:Connect(function(child: Instance)
		watch(child)
		render()
	end)
	newCharacter.ChildRemoved:Connect(render)
	for _, child in newCharacter:GetChildren() do
		watch(child)
	end
	render()
end

local function onBackpack(backpack: Instance)
	backpack.ChildAdded:Connect(function(child: Instance)
		watch(child)
		render()
	end)
	backpack.ChildRemoved:Connect(render)
	for _, child in backpack:GetChildren() do
		watch(child)
	end
	render()
end

function HotbarController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Hotbar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")

	bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset(0, SLOT_SIZE)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
end

function HotbarController:Start()
	task.spawn(disableDefaultBackpack)
	UserInputService.InputBegan:Connect(onInput)
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			onBackpack(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		onBackpack(backpack)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return HotbarController
