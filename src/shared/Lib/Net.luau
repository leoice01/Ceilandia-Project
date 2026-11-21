--!strict
-- Remotes seguros. O servidor cria os RemoteEvents em ReplicatedStorage.Net
-- (a pasta Remotes é do GunServer legado), aplica rate limit, valida os
-- argumentos e registra abuso. O cliente só pega o remote com WaitForChild.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NetConfig = require(script.Parent.Parent.Config.Net)

export type Validator = (...any) -> (boolean, string?)
export type Handler = (player: Player, ...any) -> ()

local FOLDER_NAME = "Net"
local IS_SERVER = RunService:IsServer()

local Net = {}

local lastCall: { [string]: { [Player]: number } } = {}
local lastAbuseLog: { [Player]: { [string]: number } } = {}
local abuseCount: { [Player]: number } = {}

local function getFolder(): Folder
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- NaN falha (n ~= n) e infinito falha (abs == huge)
function Net.isFiniteNumber(value: unknown): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and math.abs(n) < math.huge
end

-- Vector3 sem NaN/inf e com tamanho limitado
function Net.isFiniteVector3(value: unknown, maxMagnitude: number?): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		return false
	end
	return v.Magnitude <= (maxMagnitude or NetConfig.MaxVectorMagnitude)
end

function Net.isShortString(value: unknown, maxLength: number): boolean
	return typeof(value) == "string" and #(value :: string) <= maxLength
end

-- Registra abuso com UserId, remote e motivo. Conta todos, mas só imprime o mesmo
-- motivo de novo depois do cooldown, para spam não inundar o Output.
function Net.reportAbuse(player: Player, remoteName: string, reason: string)
	local total = (abuseCount[player] or 0) + 1
	abuseCount[player] = total

	local perPlayer = lastAbuseLog[player]
	if not perPlayer then
		perPlayer = {}
		lastAbuseLog[player] = perPlayer
	end
	local key = remoteName .. ":" .. reason
	local now = os.clock()
	local prev = perPlayer[key]
	if prev and now - prev < NetConfig.AbuseLogCooldown then
		return
	end
	perPlayer[key] = now
	warn(("[Abuse] user=%d remote=%s reason=%s total=%d"):format(player.UserId, remoteName, reason, total))
end

function Net.getAbuseCount(player: Player): number
	return abuseCount[player] or 0
end

-- Cria (ou reaproveita) um RemoteEvent. Só no servidor.
function Net.serverEvent(name: string): RemoteEvent
	assert(IS_SERVER, "Net.serverEvent só pode ser chamado no servidor")
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Cria o remote e conecta o handler atrás do rate limit e do validador.
function Net.listen(name: string, validator: Validator, handler: Handler, minInterval: number?): RemoteEvent
	local remote = Net.serverEvent(name)
	local interval = minInterval or NetConfig.DefaultMinInterval
	local calls: { [Player]: number } = {}
	lastCall[name] = calls

	remote.OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		local prev = calls[player]
		if prev and now - prev < interval then
			Net.reportAbuse(player, name, "rate_limit")
			return
		end
		calls[player] = now

		local ok, reason = validator(...)
		if not ok then
			Net.reportAbuse(player, name, reason or "invalid_args")
			return
		end
		handler(player, ...)
	end)
	return remote
end

-- Lado do cliente: espera o remote que o servidor criou.
function Net.clientEvent(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

-- Validador para remotes que não recebem argumento nenhum
function Net.noArgs(...: any): (boolean, string?)
	if select("#", ...) ~= 0 then
		return false, "unexpected_args"
	end
	return true, nil
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, calls in lastCall do
			calls[player] = nil
		end
		lastAbuseLog[player] = nil
		abuseCount[player] = nil
	end)
end

return Net
