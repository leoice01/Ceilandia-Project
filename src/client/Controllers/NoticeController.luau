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
local TOAST_SECONDS = 5
local toastToken = 0
local toast: TextLabel? = nil

-- Painel próprio no topo da tela, para quando a notificação do Roblox não está disponível
-- (a interface do Roblox às vezes não carrega no Studio)
local function showToast(title: string, text: string)
	local label = toast
	if not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "Notices"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 7
		gui.Parent = player:WaitForChild("PlayerGui")
		local created = Instance.new("TextLabel")
		created.AnchorPoint = Vector2.new(0.5, 0)
		created.Position = UDim2.new(0.5, 0, 0, 70)
		created.Size = UDim2.fromOffset(460, 0)
		created.AutomaticSize = Enum.AutomaticSize.Y
		created.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		created.BackgroundTransparency = 0.15
		created.TextColor3 = Color3.new(1, 1, 1)
		created.Font = Enum.Font.GothamMedium
		created.TextSize = 16
		created.TextWrapped = true
		created.RichText = true
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 14)
		padding.PaddingRight = UDim.new(0, 14)
		padding.Parent = created
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = created
		created.Parent = gui
		toast = created
		label = created
	end
	local current = label :: TextLabel
	toastToken += 1
	local token = toastToken
	current.Text = ("<b>%s</b>\n%s"):format(title, text)
	current.Visible = true
	task.delay(TOAST_SECONDS, function()
		if token == toastToken then
			current.Visible = false
		end
	end)
end

local function show(title: unknown, text: unknown)
	if typeof(title) ~= "string" or typeof(text) ~= "string" then
		return
	end
	local ok = pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 5 })
	end)
	if not ok then
		showToast(title, text)
	end
end

-- Para outros controllers (alertas da polícia): mesma notificação com o painel de reserva
function NoticeController.show(title: string, text: string)
	show(title, text)
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
