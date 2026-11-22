--!strict
-- Alertas da central para policiais. Não cria interface nova: cada alerta vira um pino no
-- minimapa do HUD existente (peça local com a tag MapPin, que o HudController já desenha)
-- e uma notificação padrão do Roblox. A posição vem do servidor já com imprecisão
-- (área de busca), e só nos eventos — nunca a posição ao vivo do suspeito.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local NoticeController = require(script.Parent:WaitForChild("NoticeController"))

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

-- notificação do Roblox, com o painel de reserva do NoticeController se ela não carregar
local function notify(title: string, text: string)
	NoticeController.show(title, text)
end

-- ocorrências conhecidas por este policial (id -> último estado) e seus pinos
local incidents: { [number]: WantedContract.IncidentInfo } = {}
local incidentPins: { [number]: Part } = {}
local CLOSED: { [string]: boolean } = { Resolved = true, Escaped = true }

local function makePin(position: Vector3, icon: string, stars: number, radius: number): Part
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
	pin:SetAttribute("Color", SEVERITY_COLOR[math.clamp(stars, 1, #SEVERITY_COLOR)])
	pin:SetAttribute("Radius", radius)
	pin.Parent = folder
	CollectionService:AddTag(pin, PIN_TAG)
	Debris:AddItem(pin, WantedConfig.AlertPinSeconds)
	return pin
end

-- Pino no minimapa. Com ocorrência: um pino por ocorrência (atualiza no lugar);
-- ocorrência fechada (escapou/resolvida) tira o pino.
local function updatePin(alert: WantedContract.Alert)
	local incident = alert.incident
	local id = if incident and typeof(incident.id) == "number" then incident.id else nil
	if id and incident then
		incidents[id] = incident
		if CLOSED[incident.state] then
			local old = incidentPins[id]
			if old then
				old:Destroy()
			end
			incidentPins[id] = nil
			return
		end
	end
	local position = alert.position
	local icon = PIN_ICON[if alert.kind == "Sync" then "Crime" else alert.kind]
	if typeof(position) ~= "Vector3" or not icon then
		return
	end
	local pin = makePin(position, icon, alert.stars, alert.radius)
	if id then
		local old = incidentPins[id]
		if old then
			old:Destroy()
		end
		incidentPins[id] = pin
	end
end

local function onAlert(raw: unknown)
	if type(raw) ~= "table" then
		return
	end
	local alert = raw :: WantedContract.Alert
	if typeof(alert.label) ~= "string" or typeof(alert.stars) ~= "number" then
		return
	end
	updatePin(alert)
	if alert.kind == "Sync" then
		return -- ocorrência antiga: só o pino, sem notificação
	end
	local stars = string.rep("★", math.clamp(math.floor(alert.stars), 1, 5))
	local who = if typeof(alert.suspect) == "string" then "Suspeito: " .. alert.suspect else "Suspeito não identificado"
	local where = if typeof(alert.position) == "Vector3" then "área marcada no mapa" else "local desconhecido"
	notify(("%s  %s"):format(stars, alert.label), ("%s · %s · prioridade %s"):format(who, where, tostring(alert.priority)))
end

-- Ocorrências que este policial conhece (para uma futura tela da central)
function PoliceAlertController.incidents(): { [number]: WantedContract.IncidentInfo }
	return incidents
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
