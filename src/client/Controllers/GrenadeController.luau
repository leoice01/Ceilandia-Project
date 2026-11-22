--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P1 assume depois).
-- Item "Granada": clicar lança na direção da mira. O servidor cria, voa e explode a granada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

local AIM_RANGE = 300 -- até onde procura o ponto mirado (studs)

local GrenadeController = {}

local player = Players.LocalPlayer
local throwRemote: RemoteEvent
local hooked: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Direção da cabeça até o ponto que a mira (mouse/centro da tela) está apontando
local function aimDirection(character: Model): Vector3?
	local head = character:FindFirstChild("Head") :: BasePart?
	local camera = workspace.CurrentCamera
	if not head or not camera then
		return nil
	end
	local screen = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
	local target = if hit then hit.Position else ray.Origin + ray.Direction * AIM_RANGE
	local offset = target - head.Position
	if offset.Magnitude < 0.1 then
		return ray.Direction
	end
	return offset.Unit
end

local function hook(tool: Tool)
	if hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		local character = player.Character
		local direction = character and aimDirection(character)
		if direction then
			throwRemote:FireServer(direction)
		end
	end)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute(CombatContract.GrenadeItem.Attribute) == true then
			hook(child)
		end
	end)
end

function GrenadeController:Start()
	throwRemote = Net.clientEvent(CombatContract.Remotes.GrenadeThrow)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return GrenadeController
