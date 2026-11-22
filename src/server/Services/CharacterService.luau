--!strict
-- Ajustes de cada personagem de jogador ao nascer.
-- A barra de vida em cima da cabeça fica escondida para jogadores (só o próprio HUD
-- mostra a vida); NPCs e dummies não passam por aqui e continuam com a deles.

local Players = game:GetService("Players")

local CharacterService = {}

local function setup(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

function CharacterService:Start()
	local function onPlayer(player: Player)
		if player.Character then
			setup(player.Character)
		end
		player.CharacterAdded:Connect(setup)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return CharacterService
