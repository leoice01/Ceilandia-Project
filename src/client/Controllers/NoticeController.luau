--!strict
-- Mostra os avisos do servidor (Lib/Notice) com a notificação padrão do Roblox.
-- Também esconde, só para este jogador, o botão de recrutamento que não se aplica a ele
-- (policial não vê "Entrar para a Polícia"; ladrão não vê "Devolver distintivo").
-- Quem decide a troca é sempre o servidor.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local Notice = require(Shared.Lib:WaitForChild("Notice"))

-- nome do prompt -> facção que NÃO deve ver
local HIDE_FOR: { [string]: string } = { JoinPolice = "Policia", LeavePolice = "Bandido" }

local NoticeController = {}

local player = Players.LocalPlayer

local function show(title: unknown, text: unknown)
	if typeof(title) ~= "string" or typeof(text) ~= "string" then
		return
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 5 })
	end)
end

function NoticeController:Start()
	Net.clientEvent(Notice.Remote).OnClientEvent:Connect(show)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local hideFor = HIDE_FOR[prompt.Name]
		if hideFor and player:GetAttribute("Faction") == hideFor then
			prompt.Enabled = false -- só local; volta quando a facção mudar
		end
	end)
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		local station = workspace:FindFirstChild("PoliceStation")
		if not station then
			return
		end
		for _, prompt in station:GetDescendants() do
			if prompt:IsA("ProximityPrompt") and HIDE_FOR[prompt.Name] then
				prompt.Enabled = player:GetAttribute("Faction") ~= HIDE_FOR[prompt.Name]
			end
		end
	end)
end

return NoticeController
