--!strict
-- P1
-- Feedback de combate na tela: indicador de direção do dano (em volta da mira).
-- Sem kill feed, sem medalhas e sem aviso de placa quebrada (decisão de design).
-- Visual no padrão do HUD v2 (vermelho #FF5A4A).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

-- Aparência e regras de UX (cliente, não é balanceamento)
local DAMAGE_ARROW_LIFETIME = 1.2 -- s
local DAMAGE_ARROW_RADIUS = 130 -- px da mira
local RED = Color3.fromRGB(255, 90, 74)
local RED_DARK = Color3.fromRGB(194, 29, 29)

local CombatHudController = {}

local player = Players.LocalPlayer
local gui: ScreenGui

type Arrow = { frame: Frame, stroke: UIStroke, source: Vector3, born: number }
local arrows: { Arrow } = {}

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- ---------- direção do dano ----------
local function onDamaged(sourcePos: unknown, _amount: unknown)
	if typeof(sourcePos) ~= "Vector3" then
		return
	end
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(76, 8)
	frame.BackgroundColor3 = RED
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = RED_DARK
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	grad.Parent = frame

	local pop = Instance.new("UIScale")
	pop.Scale = 1.25
	pop.Parent = frame
	TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	table.insert(arrows, { frame = frame, stroke = stroke, source = sourcePos :: Vector3, born = os.clock() })
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
			local progress = age / DAMAGE_ARROW_LIFETIME
			arrow.frame.BackgroundTransparency = 0.08 + 0.92 * progress
			arrow.stroke.Transparency = 0.3 + 0.7 * progress
		end
	end
end

function CombatHudController:Start()
	build()
	Net.clientEvent(CombatContract.Remotes.Damaged).OnClientEvent:Connect(onDamaged)
	RunService.RenderStepped:Connect(updateArrows)
end

return CombatHudController
