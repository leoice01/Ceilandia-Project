--!strict
-- Alertas da central para policiais. Não cria interface nova: cada alerta vira um pino no
-- minimapa do HUD existente (peça local com a tag MapPin, que o HudController já desenha)
-- e uma notificação padrão do Roblox. A posição vem do servidor já com imprecisão
-- (área de busca), e só nos eventos — nunca a posição ao vivo do suspeito.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local WantedContract = require(Shared.Lib:WaitForChild("WantedContract"))
local WantedConfig = require(Shared:WaitForChild("Config"):WaitForChild("Wanted"))

local PIN_TAG = "MapPin"
local PIN_ICON: { [string]: string } = { Crime = "mask", Pursuit = "shield", ContactLost = "flag" }
-- cor pela gravidade (estrelas)
local SEVERITY_COLOR: { Color3 } = {
	Color3.fromRGB(255, 214, 90),
	Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 110, 50),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(220, 40, 255),
}

local PoliceAlertController = {}

local folder: Folder

local function notify(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 6 })
	end)
end

local function addPin(alert: WantedContract.Alert)
	local position = alert.position
	local icon = PIN_ICON[alert.kind]
	if not position or not icon then
		return
	end
	local pin = Instance.new("Part")
	pin.Name = "PoliceAlert"
	pin.Anchored = true
	pin.CanCollide = false
	pin.CanQuery = false
	pin.CanTouch = false
	pin.Transparency = 1
	pin.Size = Vector3.one
	pin.Position = position
	pin:SetAttribute("Icon", icon)
	pin:SetAttribute("Color", SEVERITY_COLOR[math.clamp(alert.stars, 1, #SEVERITY_COLOR)])
	pin:SetAttribute("Radius", alert.radius)
	pin.Parent = folder
	CollectionService:AddTag(pin, PIN_TAG)
	Debris:AddItem(pin, WantedConfig.AlertPinSeconds)
end

local function onAlert(raw: unknown)
	if type(raw) ~= "table" then
		return
	end
	local alert = raw :: WantedContract.Alert
	if typeof(alert.label) ~= "string" or typeof(alert.stars) ~= "number" then
		return
	end
	local stars = string.rep("★", math.clamp(math.floor(alert.stars), 1, 5))
	local who = if typeof(alert.suspect) == "string" then "Suspeito: " .. alert.suspect else "Suspeito não identificado"
	local where = if typeof(alert.position) == "Vector3" then "área marcada no mapa" else "local desconhecido"
	notify(("%s  %s"):format(stars, alert.label), ("%s · %s · prioridade %s"):format(who, where, tostring(alert.priority)))
	addPin(alert)
end

function PoliceAlertController:Init()
	folder = Instance.new("Folder")
	folder.Name = "PoliceAlerts_Local"
	folder.Parent = workspace
end

function PoliceAlertController:Start()
	Net.clientEvent(WantedContract.Remotes.Alert).OnClientEvent:Connect(onAlert)
end

return PoliceAlertController
