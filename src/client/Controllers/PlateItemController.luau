--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P1 assume depois).
-- Item "Placas": clicar coloca uma placa; segurar continua colocando até encher o
-- colete ou acabar a mochila. Quem decide e aplica é o servidor (ArmorInsertPlate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

local ATTR = CombatContract.Attributes
local RETRY_INTERVAL = 0.25 -- s entre checagens enquanto segura (acima do rate limit do servidor)

local PlateItemController = {}

local player = Players.LocalPlayer
local insertRemote: RemoteEvent
local holding = false
local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Só pede quando faz sentido; o servidor confere tudo de novo
local function canPlate(character: Model): boolean
	if character:GetAttribute(ATTR.Plating) == true or character:GetAttribute(ATTR.Downed) == true then
		return false
	end
	if numberAttribute(player, ATTR.PlatesCarried) <= 0 then
		return false
	end
	return numberAttribute(character, ATTR.Vest) < numberAttribute(character, ATTR.VestMax)
end

local function hook(tool: Tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		if holding then
			return
		end
		holding = true
		task.spawn(function()
			while holding and tool.Parent == player.Character do
				local character = player.Character
				if character and canPlate(character) then
					insertRemote:FireServer()
				end
				task.wait(RETRY_INTERVAL)
			end
		end)
	end)
	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
	end)
end

local function watchCharacter(character: Model)
	holding = false
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute(CombatContract.PlateItem.Attribute) == true then
			hook(child)
		end
	end)
end

function PlateItemController:Start()
	insertRemote = Net.clientEvent(CombatContract.Remotes.InsertPlate)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return PlateItemController
