--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P1 assume depois).
-- Números de dano que sobem do ponto do acerto, só para quem atirou:
--   azul = dano na armadura, branco = dano na vida, vermelho = dano na vida na cabeça.
-- Acerto na armadura também solta faíscas azuis (mais forte quando a placa quebra).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

-- Aparência (UX do cliente, não é balanceamento)
local ARMOR_COLOR = Color3.fromRGB(70, 170, 255)
local HEALTH_COLOR = Color3.fromRGB(255, 255, 255)
local CRITICAL_COLOR = Color3.fromRGB(255, 60, 60)
local NUMBER_LIFETIME = 0.8 -- s
local NUMBER_RISE = 2.5 -- studs
local NUMBER_JITTER = 0.8 -- espalha números de tiros seguidos (studs)
local NUMBER_SIZE = 34 -- px
local SPARKS_HIT = 10
local SPARKS_BROKEN = 28
local FLASH_TIME = 0.08 -- s

local DamageNumbersController = {}

local random = Random.new()

-- Âncora invisível no ponto do acerto (Attachment no Terrain não cria peça física)
local function anchorAt(position: Vector3, lifetime: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	Debris:AddItem(attachment, lifetime)
	return attachment
end

local function showNumber(position: Vector3, amount: number, color: Color3, sideOffset: number)
	local rounded = math.floor(amount + 0.5)
	if rounded <= 0 then
		return
	end
	local anchor = anchorAt(position, NUMBER_LIFETIME + 0.1)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, NUMBER_SIZE + 10)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	local start = Vector3.new(sideOffset + random:NextNumber(-NUMBER_JITTER, NUMBER_JITTER) * 0.5, 0.5, 0)
	billboard.StudsOffsetWorldSpace = start
	-- Precisa do Adornee explícito: ser filho de um Attachment não basta para posicionar
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = NUMBER_SIZE
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = tostring(rounded)
	label.Parent = billboard

	-- "Pop" rápido e depois sobe e some
	local scale = Instance.new("UIScale")
	scale.Scale = 1.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local info = TweenInfo.new(NUMBER_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffsetWorldSpace = start + Vector3.new(0, NUMBER_RISE, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(NUMBER_LIFETIME * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, NUMBER_LIFETIME * 0.5), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function armorSparks(position: Vector3, broken: boolean)
	local anchor = anchorAt(position, 0.6)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(ARMOR_COLOR)
	sparks.LightEmission = 1
	sparks.Brightness = 3
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if broken then 0.35 else 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Speed = NumberRange.new(12, if broken then 28 else 18)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 6
	sparks.Enabled = false
	sparks.Parent = anchor
	sparks:Emit(if broken then SPARKS_BROKEN else SPARKS_HIT)

	local flash = Instance.new("PointLight")
	flash.Color = ARMOR_COLOR
	flash.Brightness = if broken then 6 else 3
	flash.Range = if broken then 10 else 6
	flash.Parent = anchor
	Debris:AddItem(flash, FLASH_TIME)
end

local function onHit(
	region: unknown,
	_result: unknown,
	armor: unknown,
	armorDamage: unknown,
	healthDamage: unknown,
	hitPos: unknown
)
	if typeof(hitPos) ~= "Vector3" then
		return
	end
	local position = hitPos :: Vector3
	local toArmor = if typeof(armorDamage) == "number" then armorDamage else 0
	local toHealth = if typeof(healthDamage) == "number" then healthDamage else 0

	if armor == "Hit" or armor == "Broken" then
		armorSparks(position, armor == "Broken")
	end
	-- Os dois números saem lado a lado quando o tiro passa da armadura para a vida
	local both = toArmor > 0 and toHealth > 0
	showNumber(position, toArmor, ARMOR_COLOR, if both then -0.6 else 0)
	showNumber(position, toHealth, if region == "Head" then CRITICAL_COLOR else HEALTH_COLOR, if both then 0.6 else 0)
end

function DamageNumbersController:Start()
	local hitRemote = Net.clientEvent(CombatContract.Remotes.Hit)
	hitRemote.OnClientEvent:Connect(onHit)
end

return DamageNumbersController
