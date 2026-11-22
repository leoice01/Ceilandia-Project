--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P1 assume o HUD depois).
-- Feedback de combate na tela:
--   kill feed (canto superior direito), indicador de direção do dano (em volta da mira),
--   ícone de placa quebrada (ao lado da mira) e medalhas (abate duplo/triplo,
--   longa distância, vingança).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

-- Aparência e regras de UX (cliente, não é balanceamento)
local FEED_MAX = 5
local FEED_LIFETIME = 6 -- s
local DAMAGE_ARROW_LIFETIME = 1.2 -- s
local DAMAGE_ARROW_RADIUS = 130 -- px da mira
local MULTIKILL_WINDOW = 4 -- s entre abates para contar como duplo/triplo
local LONGSHOT_DISTANCE = 150 -- studs (~42 m)
local MEDAL_LIFETIME = 1.6 -- s
local RED = Color3.fromRGB(255, 70, 70)
local WHITE = Color3.new(1, 1, 1)
local GRAY = Color3.fromRGB(190, 190, 190)
local GOLD = Color3.fromRGB(255, 205, 70)
local ARMOR_BLUE = Color3.fromRGB(70, 170, 255)

local VERBS: { [string]: string } = {
	Downed = "derrubou",
	Finished = "eliminou",
	Revived = "reviveu",
}

local CombatHudController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local feedFrame: Frame
local medalLabel: TextLabel
local medalScale: UIScale
local medalToken = 0
local armorIcon: TextLabel
local armorScale: UIScale

type Arrow = { frame: Frame, source: Vector3, born: number }
local arrows: { Arrow } = {}

-- abates recentes do jogador local, para medalhas
local recentKills: { number } = {}
local countedVictims: { [string]: number } = {}
local lastAttackerName: string? = nil

local function label(parent: Instance, text: string, color: Color3, size: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.35
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Text = text
	l.Parent = parent
	return l
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colorTag(text: string, color: Color3, bold: boolean): string
	local hex = color:ToHex()
	local body = ('<font color="#%s">%s</font>'):format(hex, escape(text))
	return if bold then "<b>" .. body .. "</b>" else body
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	feedFrame = Instance.new("Frame")
	feedFrame.AnchorPoint = Vector2.new(1, 0)
	feedFrame.Position = UDim2.new(1, -16, 0, 70)
	feedFrame.Size = UDim2.fromOffset(420, 200)
	feedFrame.BackgroundTransparency = 1
	feedFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = feedFrame

	medalLabel = label(gui, "", GOLD, 30, Enum.Font.GothamBlack)
	medalLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	medalLabel.Position = UDim2.fromScale(0.5, 0.3)
	medalLabel.Size = UDim2.fromOffset(500, 40)
	medalLabel.TextTransparency = 1
	medalLabel.TextStrokeTransparency = 1
	medalScale = Instance.new("UIScale")
	medalScale.Parent = medalLabel

	armorIcon = label(gui, "◆ PLACA", ARMOR_BLUE, 16, Enum.Font.GothamBlack)
	armorIcon.AnchorPoint = Vector2.new(0, 0.5)
	armorIcon.Size = UDim2.fromOffset(90, 20)
	armorIcon.TextXAlignment = Enum.TextXAlignment.Left
	armorIcon.TextTransparency = 1
	armorIcon.TextStrokeTransparency = 1
	armorScale = Instance.new("UIScale")
	armorScale.Parent = armorIcon
end

-- ---------- kill feed ----------
local feedOrder = 0
local function pushFeed(kind: string, actor: Player?, victimName: string)
	local victimColor = if victimName == player.Name then GOLD else RED
	local text: string
	if kind == "BledOut" then
		text = colorTag(victimName, victimColor, true) .. colorTag(" sangrou até morrer", GRAY, false)
	else
		local verb = VERBS[kind]
		if not verb or not actor then
			return
		end
		local actorColor = if actor == player then GOLD else WHITE
		local targetColor = if kind == "Revived" then WHITE else victimColor
		text = colorTag(actor.Name, actorColor, true) .. colorTag(" " .. verb .. " ", GRAY, false) .. colorTag(victimName, targetColor, true)
	end

	feedOrder += 1
	local entry = label(feedFrame, text, WHITE, 17, Enum.Font.GothamMedium)
	entry.RichText = true
	entry.Size = UDim2.new(1, 0, 0, 22)
	entry.TextXAlignment = Enum.TextXAlignment.Right
	entry.LayoutOrder = feedOrder
	entry.BackgroundColor3 = Color3.new(0, 0, 0)
	entry.BackgroundTransparency = 0.6

	-- mantém só as últimas FEED_MAX linhas
	local entries = {}
	for _, child in feedFrame:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #entries - FEED_MAX do
		entries[i]:Destroy()
	end

	task.delay(FEED_LIFETIME, function()
		if entry.Parent then
			local fade = TweenService:Create(entry, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			entry:Destroy()
		end
	end)
end

-- ---------- medalhas ----------
local function showMedal(text: string)
	medalToken += 1
	local token = medalToken
	medalLabel.Text = text
	medalLabel.TextTransparency, medalLabel.TextStrokeTransparency = 0, 0.35
	medalScale.Scale = 1.5
	TweenService:Create(medalScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(MEDAL_LIFETIME, function()
		if token == medalToken then
			TweenService:Create(medalLabel, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function distanceTo(victimName: string): number?
	local victim = Players:FindFirstChild(victimName)
	local model = if victim and victim:IsA("Player") then victim.Character else workspace:FindFirstChild(victimName, true)
	local character = player.Character
	local from = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not from or not model or not model:IsA("Model") then
		return nil
	end
	return (model:GetPivot().Position - from.Position).Magnitude
end

-- conta um abate do jogador local (derrubar já conta; finalizar o mesmo alvo logo depois não conta de novo)
local function onMyTakedown(victimName: string)
	local now = os.clock()
	local last = countedVictims[victimName]
	if last and now - last < MULTIKILL_WINDOW * 2 then
		return
	end
	countedVictims[victimName] = now

	local kept = {}
	for _, t in recentKills do
		if now - t <= MULTIKILL_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	recentKills = kept

	local medal: string? = nil
	if lastAttackerName and victimName == lastAttackerName then
		medal = "VINGANÇA"
		lastAttackerName = nil
	end
	if #recentKills >= 3 then
		medal = "ABATE TRIPLO"
	elseif #recentKills == 2 then
		medal = "ABATE DUPLO"
	end
	local distance = distanceTo(victimName)
	if not medal and distance and distance >= LONGSHOT_DISTANCE then
		medal = ("LONGA DISTÂNCIA  %dm"):format(math.floor(distance * 0.28 + 0.5))
	end
	if medal then
		showMedal(medal)
	end
end

local function onFeed(kind: unknown, actor: unknown, victimName: unknown)
	if typeof(kind) ~= "string" or typeof(victimName) ~= "string" then
		return
	end
	local actorPlayer = if typeof(actor) == "Instance" and actor:IsA("Player") then actor else nil
	pushFeed(kind, actorPlayer, victimName)
	if actorPlayer == player and (kind == "Downed" or kind == "Finished") then
		onMyTakedown(victimName)
	end
	-- quem me derrubou/matou vira alvo de vingança
	if victimName == player.Name and actorPlayer and actorPlayer ~= player and (kind == "Downed" or kind == "Finished") then
		lastAttackerName = actorPlayer.Name
	end
end

-- ---------- ícone de placa quebrada ----------
local function onHit(_region: unknown, _result: unknown, armor: unknown)
	if armor ~= "Broken" then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	armorIcon.Position = UDim2.fromOffset(mouse.X + 22, mouse.Y)
	armorIcon.TextTransparency, armorIcon.TextStrokeTransparency = 0, 0.35
	armorScale.Scale = 1.4
	TweenService:Create(armorScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(armorIcon, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.35), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

-- ---------- direção do dano ----------
local function onDamaged(sourcePos: unknown, _amount: unknown)
	if typeof(sourcePos) ~= "Vector3" then
		return
	end
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(70, 9)
	frame.BackgroundColor3 = RED
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	table.insert(arrows, { frame = frame, source = sourcePos :: Vector3, born = os.clock() })
end

local function updateArrows()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local center = viewport / 2
	local now = os.clock()
	for i = #arrows, 1, -1 do
		local arrow = arrows[i]
		local age = now - arrow.born
		if age >= DAMAGE_ARROW_LIFETIME then
			arrow.frame:Destroy()
			table.remove(arrows, i)
		else
			-- ângulo da origem do dano em relação para onde a câmera olha (0 = na frente)
			local offset = camera.CFrame:VectorToObjectSpace(arrow.source - camera.CFrame.Position)
			local angle = math.atan2(offset.X, -offset.Z)
			arrow.frame.Position = UDim2.fromOffset(
				center.X + math.sin(angle) * DAMAGE_ARROW_RADIUS,
				center.Y - math.cos(angle) * DAMAGE_ARROW_RADIUS
			)
			arrow.frame.Rotation = math.deg(angle)
			arrow.frame.BackgroundTransparency = 0.1 + 0.9 * (age / DAMAGE_ARROW_LIFETIME)
		end
	end
end

function CombatHudController:Start()
	build()
	Net.clientEvent(CombatContract.Remotes.Feed).OnClientEvent:Connect(onFeed)
	Net.clientEvent(CombatContract.Remotes.Hit).OnClientEvent:Connect(onHit)
	Net.clientEvent(CombatContract.Remotes.Damaged).OnClientEvent:Connect(onDamaged)
	RunService.RenderStepped:Connect(updateArrows)
end

return CombatHudController
