--!strict
-- PROVISÓRIO (feito pela P2 com OK do usuário; a P4 escolhe os sons finais depois).
-- Sons de feedback para quem atira (sem aviso na tela):
--   placa do inimigo quebrou (CombatHit armor = "Broken") -> som de placa quebrando
--   você derrubou / finalizou alguém (CombatFeed com actor = você) -> som de derrubar

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Lib"):WaitForChild("Net"))
local CombatContract = require(Shared:WaitForChild("Lib"):WaitForChild("CombatContract"))

-- Sons do Warzone subidos por terceiros na Creator Store, escolhidos pelo usuário.
-- Podem ser removidos por direitos autorais; se pararem de tocar, troque o ID aqui.
local PLATE_BREAK_SOUND = "rbxassetid://8618202949" -- "Warzone armor break_crack sound"
local DOWNED_SOUND = "rbxassetid://104889661573356" -- "CoD WZ enemy armor break": o "ding" que o usuário escolheu

local CombatFeedbackController = {}

local player = Players.LocalPlayer
local templates: { [string]: Sound } = {}

-- Sons-modelo pré-carregados; cada toque é uma cópia (dá para tocar vários juntos)
local function preloadSounds()
	local list = {}
	for _, id in { PLATE_BREAK_SOUND, DOWNED_SOUND } do
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Parent = SoundService
		templates[id] = sound
		table.insert(list, sound)
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
end

local function playSound(id: string, volume: number, pitch: number)
	local template = templates[id]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	-- PlayOnRemove toca o som inteiro mesmo depois de destruído, sem precisar esperar
	sound.PlayOnRemove = true
	sound.Parent = SoundService
	sound:Destroy()
end

local function onPlateBroken()
	playSound(PLATE_BREAK_SOUND, 0.9, 1)
end

local function onFeed(kind: unknown, actor: unknown, _victimName: unknown)
	if actor ~= player then
		return
	end
	if kind == "Downed" then
		playSound(DOWNED_SOUND, 0.9, 1)
	elseif kind == "Finished" then
		playSound(DOWNED_SOUND, 0.9, 0.85)
	end
end

function CombatFeedbackController:Start()
	preloadSounds()
	Net.clientEvent(CombatContract.Remotes.Hit).OnClientEvent:Connect(function(_region: unknown, _result: unknown, armor: unknown)
		if armor == "Broken" then
			onPlateBroken()
		end
	end)
	Net.clientEvent(CombatContract.Remotes.Feed).OnClientEvent:Connect(onFeed)
end

return CombatFeedbackController
