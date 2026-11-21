--!strict
-- Guarda um histórico curto da posição das partes de cada personagem de jogador
-- e testa um raio contra as partes "voltadas no tempo" (lag compensation).
-- NPCs não entram aqui: eles não têm atraso de rede e são testados com raycast normal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)

type Snapshot = {
	t: number,
	cframes: { [BasePart]: CFrame },
}

type History = {
	parts: { BasePart },
	partsDirty: boolean,
	ring: { Snapshot },
	newest: number, -- índice do snapshot mais novo no anel
	count: number,
}

local SLOT_COUNT = math.ceil(CombatConfig.HistorySeconds * CombatConfig.HistoryHz) + 2
local RECORD_INTERVAL = 1 / CombatConfig.HistoryHz
local EPSILON = 1e-9

local LagCompensation = {}

local histories: { [Model]: History } = {}
local started = false

local function newHistory(): History
	local ring: { Snapshot } = table.create(SLOT_COUNT)
	for i = 1, SLOT_COUNT do
		ring[i] = { t = -math.huge, cframes = {} }
	end
	return { parts = {}, partsDirty = true, ring = ring, newest = 0, count = 0 }
end

-- Partes do corpo que contam como alvo (sem a HumanoidRootPart, que é invisível)
local function collectParts(character: Model): { BasePart }
	local list = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			table.insert(list, child)
		end
	end
	return list
end

local function track(character: Model)
	local history = newHistory()
	histories[character] = history
	-- R15 monta as partes aos poucos; refaz a lista quando mudar
	character.ChildAdded:Connect(function()
		history.partsDirty = true
	end)
	character.ChildRemoved:Connect(function()
		history.partsDirty = true
	end)
end

local function untrack(character: Model)
	histories[character] = nil
end

local function record(now: number)
	for character, history in histories do
		if history.partsDirty then
			history.parts = collectParts(character)
			history.partsDirty = false
		end
		history.newest = history.newest % SLOT_COUNT + 1
		local snapshot = history.ring[history.newest]
		snapshot.t = now
		table.clear(snapshot.cframes)
		for _, part in history.parts do
			snapshot.cframes[part] = part.CFrame
		end
		history.count = math.min(history.count + 1, SLOT_COUNT)
	end
end

-- CFrame de uma parte no tempo t, interpolando entre dois snapshots
local function cframeAt(history: History, part: BasePart, t: number): CFrame
	if history.count == 0 then
		return part.CFrame
	end
	local newerSnap: Snapshot? = nil
	local index = history.newest
	for _ = 1, history.count do
		local snap = history.ring[index]
		local cf = snap.cframes[part]
		if snap.t <= t then
			if not cf then
				return part.CFrame
			end
			if not newerSnap then
				-- t é mais novo que o último snapshot: usa a posição atual
				return part.CFrame
			end
			local newerCf = newerSnap.cframes[part]
			if not newerCf then
				return cf
			end
			local span = newerSnap.t - snap.t
			local alpha = if span > EPSILON then (t - snap.t) / span else 0
			return cf:Lerp(newerCf, alpha)
		end
		newerSnap = snap
		index = if index == 1 then SLOT_COUNT else index - 1
	end
	-- t é mais velho que o histórico todo: usa o snapshot mais antigo
	if newerSnap then
		local oldest = newerSnap.cframes[part]
		if oldest then
			return oldest
		end
	end
	return part.CFrame
end

-- Teste raio x caixa orientada (slab). dir é o raio inteiro (direção * alcance).
-- Retorna a fração [0, 1] do raio onde entra na caixa, ou nil.
local function rayBoxFraction(cf: CFrame, size: Vector3, origin: Vector3, dir: Vector3): number?
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local half = size * 0.5
	local tMin, tMax = 0, 1

	local function slab(oAxis: number, dAxis: number, halfAxis: number): boolean
		if math.abs(dAxis) < EPSILON then
			return math.abs(oAxis) <= halfAxis
		end
		local t1 = (-halfAxis - oAxis) / dAxis
		local t2 = (halfAxis - oAxis) / dAxis
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not slab(o.X, d.X, half.X) then
		return nil
	end
	if not slab(o.Y, d.Y, half.Y) then
		return nil
	end
	if not slab(o.Z, d.Z, half.Z) then
		return nil
	end
	return tMin
end

-- Testa o raio contra o personagem como ele estava no tempo t.
-- Retorna a parte atingida mais próxima e a distância até ela (studs).
function LagCompensation.raycastCharacter(character: Model, t: number, origin: Vector3, dir: Vector3): (BasePart?, number?)
	local history = histories[character]
	local parts = if history then history.parts else collectParts(character)
	local length = dir.Magnitude
	local bestPart: BasePart? = nil
	local bestFraction = math.huge

	for _, part in parts do
		if part.Parent == character then
			local cf = if history then cframeAt(history, part, t) else part.CFrame
			local fraction = rayBoxFraction(cf, part.Size, origin, dir)
			if fraction and fraction < bestFraction then
				bestFraction = fraction
				bestPart = part
			end
		end
	end

	if bestPart then
		return bestPart, bestFraction * length
	end
	return nil, nil
end

-- Tempo no servidor para reconstruir os alvos, a partir do timestamp do cliente
function LagCompensation.rewindTime(clientTimestamp: number): number
	local now = workspace:GetServerTimeNow()
	local target = clientTimestamp - CombatConfig.InterpolationDelay
	local rewind = math.clamp(now - target, 0, CombatConfig.MaxRewindSeconds)
	return now - rewind
end

function LagCompensation.start()
	if started then
		return
	end
	started = true

	local function onPlayer(player: Player)
		if player.Character then
			track(player.Character)
		end
		player.CharacterAdded:Connect(track)
		player.CharacterRemoving:Connect(untrack)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < RECORD_INTERVAL then
			return
		end
		accumulator = math.min(accumulator - RECORD_INTERVAL, RECORD_INTERVAL)
		debug.profilebegin("Combat_LagCompRecord")
		record(workspace:GetServerTimeNow())
		debug.profileend()
	end)
end

return LagCompensation
