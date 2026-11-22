--!strict
-- Pontos de plantão policial (CollectionService tag "PoliceStation"),
-- contagem/fila de vagas policiais e bônus de equilíbrio quando desfalcada.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)
local Factions = require(script.Parent.Factions)
local FactionRules = require(script.Parent.FactionRules)

local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions
local STATES = CombatContract.FactionStates
local PROMPTS = CombatContract.Prompts
local TAGS = CombatContract.Tags

local PoliceStations = {}

local stationLastUse: { [Player]: number } = {}
local policeQueue: { Player } = {}
local currentBonusMultiplier = 1

function PoliceStations.countFactions(): (number, number)
	local players = Players:GetPlayers()
	local police = 0
	for _, p in players do
		if Factions.of(p) == FACTIONS.Police then
			police += 1
		end
	end
	return police, #players
end

function PoliceStations.refreshPoliceBonus(): number
	local police, total = PoliceStations.countFactions()
	currentBonusMultiplier = FactionRules.policeBonusMultiplier(police, total, FactionsConfig)
	ReplicatedStorage:SetAttribute(ATTR.PoliceBonusMultiplier, currentBonusMultiplier)
	return currentBonusMultiplier
end

function PoliceStations.getBonusMultiplier(): number
	return currentBonusMultiplier
end

function PoliceStations.enqueue(player: Player)
	if not table.find(policeQueue, player) then
		table.insert(policeQueue, player)
	end
end

function PoliceStations.dequeue(player: Player)
	local index = table.find(policeQueue, player)
	if index then
		table.remove(policeQueue, index)
	end
end

function PoliceStations.notifyNextQueued(notify: (Player) -> ())
	local police, total = PoliceStations.countFactions()
	if police >= FactionRules.maxPoliceSlots(total, FactionsConfig) then
		return
	end
	while #policeQueue > 0 do
		local nextPlayer = table.remove(policeQueue, 1) :: Player
		if nextPlayer.Parent and Factions.of(nextPlayer) == FACTIONS.Civil and Factions.stateOf(nextPlayer) == STATES.Idle then
			notify(nextPlayer)
			return
		end
	end
end

function PoliceStations.isNear(root: BasePart?): boolean
	if not root then
		return false
	end
	local maxDistance = FactionsConfig.StationInteractDistance + FactionsConfig.StationDistanceSlack
	for _, inst in CollectionService:GetTagged(TAGS.PoliceStation) do
		if inst:IsA("BasePart") and (root.Position - inst.Position).Magnitude <= maxDistance then
			return true
		end
	end
	-- Também reconhece os pontos físicos da delegacia (workspace.PoliceStation)
	local station = workspace:FindFirstChild("PoliceStation")
	if station then
		for _, partName in { "RecruitTerminal", "LeaveLocker" } do
			local part = station:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") and (root.Position - part.Position).Magnitude <= maxDistance then
				return true
			end
		end
	end
	return false
end

function PoliceStations.forget(player: Player)
	stationLastUse[player] = nil
	PoliceStations.dequeue(player)
end

local function setupStation(instance: Instance, onTrigger: (player: Player) -> ())
	if not instance:IsA("BasePart") or instance:FindFirstChild(PROMPTS.PoliceStation) then
		return
	end
	-- Evita prompt duplicado se uma peça da delegacia física (RecruitTerminal/LeaveLocker) receber a tag
	if
		instance:FindFirstChild("JoinPolice")
		or instance:FindFirstChild("LeavePolice")
		or instance.Name == "RecruitTerminal"
		or instance.Name == "LeaveLocker"
	then
		return
	end
	local part = instance
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPTS.PoliceStation
	prompt.ActionText = "Plantão Policial"
	prompt.ObjectText = "Delegacia"
	prompt.HoldDuration = FactionsConfig.StationPromptHoldSeconds
	prompt.MaxActivationDistance = FactionsConfig.StationInteractDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or character:GetAttribute(ATTR.Downed) == true then
			return
		end
		if not root or not root:IsA("BasePart") then
			return
		end
		local maxDistance = FactionsConfig.StationInteractDistance + FactionsConfig.StationDistanceSlack
		if (root.Position - part.Position).Magnitude > maxDistance then
			Net.reportAbuse(player, "PromptPoliceStation", "too_far")
			return
		end
		local now = os.clock()
		local last = stationLastUse[player]
		if last and now - last < FactionsConfig.StationPromptCooldownSeconds then
			return
		end
		stationLastUse[player] = now
		onTrigger(player)
	end)
end

local function removeStation(instance: Instance)
	local prompt = instance:FindFirstChild(PROMPTS.PoliceStation)
	if prompt then
		prompt:Destroy()
	end
end

function PoliceStations.bindAll(onTrigger: (player: Player) -> ())
	for _, station in CollectionService:GetTagged(TAGS.PoliceStation) do
		setupStation(station, onTrigger)
	end
	CollectionService:GetInstanceAddedSignal(TAGS.PoliceStation):Connect(function(inst: Instance)
		setupStation(inst, onTrigger)
	end)
	CollectionService:GetInstanceRemovedSignal(TAGS.PoliceStation):Connect(removeStation)
end

return PoliceStations