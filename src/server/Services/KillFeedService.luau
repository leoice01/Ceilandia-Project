--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KillFeedConfig = require(ReplicatedStorage.Shared.Config.KillFeed)
local KillFeedFolder = script.Parent.Parent.KillFeed
local Payload = require(KillFeedFolder.Payload)
local Queue = require(KillFeedFolder.Queue)
local Zones = require(KillFeedFolder.Zones)

export type ReportInfo = {
	distance: number?,
	headshot: boolean?,
}

type LethalNote = {
	attacker: Player?,
	weaponName: string?,
	distance: number?,
	headshot: boolean?,
	timestamp: number,
	persistsWhileDowned: boolean,
}

local KillFeedService = {}

local queue = Queue.new(
	KillFeedConfig.QueueCap,
	KillFeedConfig.BackoffBase,
	KillFeedConfig.BackoffMax
) :: Queue.Queue<Payload.KillEntry>

local lethalNotes: { [Model]: LethalNote } = {}
local lastFallTime: { [Model]: number } = {}
local isClosing = false

local function getCharacterPosition(character: Model?): Vector3?
	if not character then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function shouldPrintOnly(): boolean
	return RunService:IsStudio() and workspace:GetAttribute("KillFeedInStudio") ~= true
end

local function sendBatch(batch: { Payload.KillEntry }): boolean
	if #batch == 0 then
		return true
	end

	local bodyOk, body = pcall(function()
		return HttpService:JSONEncode({ kills = batch })
	end)
	if not bodyOk then
		warn("[KillFeed] JSONEncode failed:", body)
		return false
	end

	if shouldPrintOnly() then
		print("[KillFeed][Studio]", body)
		return true
	end

	local ok, errOrRes = pcall(function()
		local url: any = if KillFeedConfig.EndpointUrl ~= ""
			then KillFeedConfig.EndpointUrl
			else HttpService:GetSecret("KILLFEED_URL")
		local tokenSecret = HttpService:GetSecret("KILLFEED_TOKEN")
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["Authorization"] = tokenSecret:AddPrefix("Bearer "),
			},
			Body = body,
		})
	end)

	if not ok then
		warn("[KillFeed] RequestAsync error:", errOrRes)
		return false
	end

	local res = errOrRes :: { Success: boolean, StatusCode: number, StatusMessage: string }
	if not res.Success then
		warn(("[KillFeed] HTTP %d: %s"):format(res.StatusCode, res.StatusMessage))
		return false
	end

	return true
end

local function flushOnce(): boolean
	if queue:isEmpty() then
		return true
	end
	if not queue:canSend(os.clock()) then
		return false
	end

	local batch = queue:take(KillFeedConfig.BatchSize)
	local ok = sendBatch(batch)
	if ok then
		queue:recordSuccess()
		return true
	end

	-- Devolve o lote para o início da fila em caso de falha e aplica backoff
	queue:pushFront(batch)
	queue:recordFailure(os.clock())
	return false
end

function KillFeedService:noteLethalHit(
	victimCharacter: Model,
	attacker: Player?,
	weaponName: string?,
	distance: number?,
	headshot: boolean?,
	persistsWhileDowned: boolean?
)
	lethalNotes[victimCharacter] = {
		attacker = attacker,
		weaponName = weaponName,
		distance = distance,
		headshot = headshot,
		timestamp = os.clock(),
		persistsWhileDowned = persistsWhileDowned == true,
	}
end

function KillFeedService:clearNote(victimCharacter: Model)
	lethalNotes[victimCharacter] = nil
end

function KillFeedService:report(
	victim: Player,
	killer: Player?,
	weaponName: string?,
	cause: string,
	info: ReportInfo?
)
	local pos = getCharacterPosition(victim.Character)
	local zone = if pos then Zones.findZone(pos) else "Rua"
	local entry = Payload.build({
		victim = victim,
		killer = killer,
		weaponName = weaponName,
		cause = cause,
		distance = if info then info.distance else nil,
		headshot = if info then info.headshot else nil,
		zone = zone,
		position = pos,
	})
	queue:push(entry)
end

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.StateChanged:Connect(function(_oldState, newState)
		if newState == Enum.HumanoidStateType.Freefall or newState == Enum.HumanoidStateType.Landed then
			lastFallTime[character] = os.clock()
		end
	end)

	humanoid.Died:Connect(function()
		local now = os.clock()
		local note = lethalNotes[character]
		lethalNotes[character] = nil

		if note and (note.persistsWhileDowned or (now - note.timestamp) <= KillFeedConfig.AttributionWindow) then
			KillFeedService:report(player, note.attacker, note.weaponName, "combat", {
				distance = note.distance,
				headshot = note.headshot,
			})
		else
			local fallAt = lastFallTime[character]
			local cause = if fallAt and (now - fallAt) <= 2 then "fall" else "environment"
			KillFeedService:report(player, nil, nil, cause, nil)
		end

		lastFallTime[character] = nil
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			lethalNotes[character] = nil
			lastFallTime[character] = nil
		end
	end)
end

function KillFeedService:Init()
	table.clear(lethalNotes)
	table.clear(lastFallTime)
	isClosing = false
end

function KillFeedService:Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end

	task.spawn(function()
		while not isClosing do
			task.wait(KillFeedConfig.FlushInterval)
			if not isClosing then
				pcall(flushOnce)
			end
		end
	end)

	game:BindToClose(function()
		isClosing = true
		local deadline = os.clock() + KillFeedConfig.CloseTimeout
		while not queue:isEmpty() and os.clock() < deadline do
			local ok = flushOnce()
			if not ok then
				break
			end
		end
	end)
end

return KillFeedService