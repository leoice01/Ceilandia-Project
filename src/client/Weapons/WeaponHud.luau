--!strict
-- HUD da arma: mira que abre com a dispersão real, marcador de acerto (confirmado pelo
-- servidor), aviso de cano bloqueado e munição (pente | reserva).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local HIT_SOUND_ID = "rbxassetid://138148057831879"
local LINE_LENGTH = 7
local LINE_THICKNESS = 2
local MIN_GAP = 3 -- px
local MAX_GAP = 120 -- px
local HEAD_COLOR = Color3.fromRGB(255, 210, 60)
local KILL_COLOR = Color3.fromRGB(255, 60, 60)
local BLOCKED_COLOR = Color3.fromRGB(255, 70, 70)

local WeaponHud = {}

local gui: ScreenGui
local crosshair: Frame
local lines: { Frame } = {}
local dot: Frame
local hitmarker: Frame
local hitScale: UIScale
local hitBars: { Frame } = {}
local hitTweens: { Tween } = {}
local blockedMark: Frame
local ammoLabel: TextLabel
local reserveLabel: TextLabel
local nameLabel: TextLabel

local function bar(parent: Instance, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = f
	f.Parent = parent
	return f
end

local function label(parent: Instance, size: number, anchorY: number, y: number): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(1, anchorY)
	l.Position = UDim2.new(1, -28, 1, y)
	l.Size = UDim2.fromOffset(260, size + 6)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Parent = parent
	return l
end

function WeaponHud.create()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "WeaponHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(0, 0)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = gui

	dot = bar(crosshair, UDim2.fromOffset(2, 2))
	dot.Position = UDim2.fromScale(0.5, 0.5)
	for i = 1, 4 do
		local vertical = i <= 2
		local line = bar(crosshair, if vertical
			then UDim2.fromOffset(LINE_THICKNESS, LINE_LENGTH)
			else UDim2.fromOffset(LINE_LENGTH, LINE_THICKNESS))
		lines[i] = line
	end

	hitmarker = Instance.new("Frame")
	hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	hitmarker.Size = UDim2.fromOffset(44, 44)
	hitmarker.BackgroundTransparency = 1
	hitmarker.Parent = crosshair
	hitScale = Instance.new("UIScale")
	hitScale.Parent = hitmarker
	for i = 0, 3 do
		local angle = 45 + i * 90
		local rad = math.rad(angle)
		local b = bar(hitmarker, UDim2.fromOffset(3, 12))
		b.Position = UDim2.new(0.5, math.sin(rad) * 13, 0.5, -math.cos(rad) * 13)
		b.Rotation = angle
		b.BackgroundTransparency = 1
		local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Transparency = 1
		table.insert(hitBars, b)
	end

	-- cano bloqueado: X vermelho onde o tiro vai bater de verdade
	blockedMark = Instance.new("Frame")
	blockedMark.AnchorPoint = Vector2.new(0.5, 0.5)
	blockedMark.Size = UDim2.fromOffset(14, 14)
	blockedMark.BackgroundTransparency = 1
	blockedMark.Visible = false
	blockedMark.Parent = gui
	for _, angle in { 45, -45 } do
		local b = bar(blockedMark, UDim2.fromOffset(2, 14))
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Rotation = angle
		b.BackgroundColor3 = BLOCKED_COLOR
	end

	ammoLabel = label(gui, 34, 1, -56)
	reserveLabel = label(gui, 18, 1, -34)
	nameLabel = label(gui, 14, 1, -96)
	reserveLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	-- o HUD principal (HudController da P1) já mostra munição lendo Ammo/Reserve da Tool;
	-- estes textos só aparecem se ele não existir
	local hasMainHud = player:FindFirstChildOfClass("PlayerScripts") ~= nil
		and player.PlayerScripts:FindFirstChild("HudController", true) ~= nil
	for _, l in { ammoLabel, reserveLabel, nameLabel } do
		l.Visible = not hasMainHud
	end
end

function WeaponHud.setVisible(visible: boolean)
	gui.Enabled = visible
end

-- Mira na posição da tela, aberta para mostrar o cone de dispersão (px de raio)
function WeaponHud.updateCrosshair(position: Vector2, gapPx: number)
	crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	local gap = math.clamp(gapPx, MIN_GAP, MAX_GAP) + LINE_LENGTH * 0.5
	lines[1].Position = UDim2.new(0.5, 0, 0.5, -gap)
	lines[2].Position = UDim2.new(0.5, 0, 0.5, gap)
	lines[3].Position = UDim2.new(0.5, -gap, 0.5, 0)
	lines[4].Position = UDim2.new(0.5, gap, 0.5, 0)
end

function WeaponHud.setBlocked(screenPos: Vector2?)
	if screenPos then
		blockedMark.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
		blockedMark.Visible = true
	else
		blockedMark.Visible = false
	end
end

function WeaponHud.setAmmo(name: string, ammo: number, reserve: number?, reloading: boolean)
	nameLabel.Text = name
	ammoLabel.Text = if reloading then "RECARREGANDO" else tostring(ammo)
	ammoLabel.TextColor3 = if not reloading and ammo == 0 then KILL_COLOR else Color3.new(1, 1, 1)
	reserveLabel.Text = if reserve then ("| %d"):format(reserve) else ""
end

function WeaponHud.showHit(headshot: boolean, finished: boolean)
	for _, t in hitTweens do
		t:Cancel()
	end
	table.clear(hitTweens)
	local color = if finished then KILL_COLOR elseif headshot then HEAD_COLOR else Color3.new(1, 1, 1)
	local hold = if finished then 0.45 else 0.2
	hitScale.Scale = if finished then 1.7 else 1.35
	local popIn = TweenService:Create(hitScale, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if finished then 1.25 else 1 })
	popIn:Play()
	table.insert(hitTweens, popIn)
	for _, b in hitBars do
		b.BackgroundColor3 = color
		b.BackgroundTransparency = 0
		local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Transparency = 0.4
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, hold)
		local fade = TweenService:Create(b, info, { BackgroundTransparency = 1 })
		local fadeStroke = TweenService:Create(stroke, info, { Transparency = 1 })
		fade:Play()
		fadeStroke:Play()
		table.insert(hitTweens, fade)
		table.insert(hitTweens, fadeStroke)
	end
	local sound = Instance.new("Sound")
	sound.SoundId = HIT_SOUND_ID
	sound.Volume = if finished then 0.9 else 0.6
	sound.PlaybackSpeed = if headshot then 1.15 else 1
	sound.Parent = gui
	sound:Play()
	Debris:AddItem(sound, 2)
end

return WeaponHud
