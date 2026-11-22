--!strict
-- Guarda um histórico curto da posição das partes de cada personagem de jogador
-- e testa um raio contra as partes "voltadas no tempo" (lag compensation).
-- NPCs não entram aqui: eles não têm atraso de rede e são testados com raycast normal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local RayHitbox = require(script.Parent.RayHitbox)

type Snapshot = {
	t: number,
	rootCFrame: CFrame?,
	cframes: { [BasePart]: CFrame },
}

type History = {
	parts: { BasePart },
	partsDirty: boolean,
	ring: { Snapshot },
	newest: number, -- índice do snapshot mais novo no anel
	count: number,
}

type PoseTransform = {
	body: CFrame,
	rightLeg: CFrame,
	leftLeg: CFrame,
}

local SLOT_COUNT = math.ceil(CombatConfig.HistorySeconds * CombatConfig.HistoryHz) + 2
local RECORD_INTERVAL = 1 / CombatConfig.HistoryHz
local EPSILON = 1e-9

type BodyPose = { drop: number, lean: number, rightLeg: number, leftLeg: number }
-- agachado = ajoelhado sobre as pernas; mesmos valores de Shared/Config/AnimationClips
local CROUCH_POSE: BodyPose = { drop = 1.5, lean = math.rad(-5), rightLeg = math.rad(-88), leftLeg = math.rad(-92) }
local SLIDE_POSE: BodyPose = { drop = 1.3, lean = math.rad(40), rightLeg = math.rad(45), leftLeg = math.rad(-15) }
-- derrubado: deitado de bruços (os braços esticados à frente não entram na hitbox)
local DOWNED_POSE: BodyPose = { drop = 2.5, lean = math.rad(-90), rightLeg = 0, leftLeg = 0 }
local RIGHT_HIP = CFrame.new(0.5, -1, 0) -- quadril no espaço do Torso (R6)
local LEFT_HIP = CFrame.new(-0.5, -1, 0)

local LagCompensation = {}

local histories: { [Model]: History } = {}
local started = false

local function bodyPoseOf(character: Model): BodyPose?
	if character:GetAttribute("Downed") == true then
		return DOWNED_POSE
	end
	if character:GetAttribute("Pose") == "Slide" then
		return SLIDE_POSE
	end
	if character:GetAttribute("PoseCrouch") == true then
		return CROUCH_POSE
	end
	return nil
end

-- Calcula os CFrames de transformação da pose R6 uma única vez (sem closure no hot-path)
local function poseTransformFor(character: Model): PoseTransform?
	local pose = bodyPoseOf(character)
	if not pose then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local torso = character:FindFirstChild("Torso")
	if not (root and root:IsA("BasePart") and torso and torso:IsA("BasePart")) then
		return nil
	end
	local rootCf = root.CFrame
	local torsoCf = torso.CFrame
	return {
		body = rootCf * CFrame.new(0, -pose.drop, 0) * CFrame.Angles(pose.lean, 0, 0) * rootCf:Inverse(),
		rightLeg = torsoCf * RIGHT_HIP * CFrame.Angles(pose.rightLeg, 0, 0) * RIGHT_HIP:Inverse() * torsoCf:Inverse(),
		leftLeg = torsoCf * LEFT_HIP * CFrame.Angles(pose.leftLeg, 0, 0) * LEFT_HIP:Inverse() * torsoCf:Inverse(),
	}
end

local function applyPose(part: BasePart, pose: PoseTransform?): CFrame
	local cf = part.CFrame
	if not pose then
		return cf
	end
	if part.Name == "Right Leg" then
		cf = pose.rightLeg * cf
	elseif part.Name == "Left Leg" then
		cf = pose.leftLeg * cf
	end
	return pose.body * cf
end

local function newHistory(): History
	local ring: { Snapshot } = table.create(SLOT_COUNT)
	for i = 1, SLOT_COUNT do
		ring[i] = { t = -math.huge, rootCFrame = nil, cframes = {} }
	end
	return { parts = {}, partsDirty = true, ring = ring, newest = 0, count = 0 }
end

-- Partes do corpo consultáveis que contam como alvo (sem HumanoidRootPart nem CanQuery = false)
local function collectParts(character: Model): { BasePart }
	local list = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and child.CanQuery then
			table.insert(list, child)
		end
	end
	return list
end

local function track(character: Model)
	local history = newHistory()
	histories[character] = history
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
		local root = character:FindFirstChild("HumanoidRootPart")
		snapshot.rootCFrame = if root and root:IsA("BasePart") then root.CFrame else nil
		table.clear(snapshot.cframes)
		local pose = poseTransformFor(character)
		for _, part in history.parts do
			if part.Parent == character and part.CanQuery then
				snapshot.cframes[part] = applyPose(part, pose)
			end
		end
		history.count = math.min(history.count + 1, SLOT_COUNT)
	end
end

-- Resolve o par de snapshots uma única vez por personagem.
-- Quando t > newestSnap.t e t < now, interpola newestSnap -> posição ao vivo (useLiveB = true).
local function resolveSample(history: History?, t: number, now: number): (Snapshot?, Snapshot?, number, boolean)
	if not history or history.count == 0 or t >= now then
		return nil, nil, 1, true
	end
	local newestSnap = history.ring[history.newest]
	if t >= newestSnap.t then
		local span = now - newestSnap.t
		local alpha = if span > EPSILON then math.clamp((t - newestSnap.t) / span, 0, 1) else 1
		return newestSnap, nil, alpha, true
	end

	local newerSnap: Snapshot = newestSnap
	local index = if history.newest == 1 then SLOT_COUNT else history.newest - 1
	for _ = 2, history.count do
		local snap = history.ring[index]
		if snap.t <= t then
			local span = newerSnap.t - snap.t
			local alpha = if span > EPSILON then math.clamp((t - snap.t) / span, 0, 1) else 0
			return snap, newerSnap, alpha, false
		end
		newerSnap = snap
		index = if index == 1 then SLOT_COUNT else index - 1
	end

	-- t é mais velho que o histórico todo: usa o snapshot mais antigo
	return newerSnap, nil, 0, false
end

local function sampleRootPosition(character: Model, snapA: Snapshot?, snapB: Snapshot?, alpha: number, useLiveB: boolean): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart")
	local livePos = if root and root:IsA("BasePart") then root.Position else nil
	local cfA = if snapA then snapA.rootCFrame else nil
	if not cfA then
		return livePos
	end
	if useLiveB then
		return if livePos then cfA.Position:Lerp(livePos, alpha) else cfA.Position
	end
	if snapB and snapB.rootCFrame then
		return cfA.Position:Lerp(snapB.rootCFrame.Position, alpha)
	end
	return cfA.Position
end

local function samplePartCFrame(part: BasePart, pose: PoseTransform?, snapA: Snapshot?, snapB: Snapshot?, alpha: number, useLiveB: boolean): CFrame
	local cfA = if snapA then snapA.cframes[part] else nil
	if not cfA then
		return applyPose(part, pose)
	end
	if useLiveB then
		return cfA:Lerp(applyPose(part, pose), alpha)
	end
	local cfB = if snapB then snapB.cframes[part] else nil
	return if cfB then cfA:Lerp(cfB, alpha) else cfA
end

-- Testa o raio contra o personagem no tempo t com broadphase pelo root rebobinado.
-- dirUnit deve ser unitário; maxDist limita o segmento testado.
function LagCompensation.raycastCharacter(character: Model, t: number, origin: Vector3, dirUnit: Vector3, maxDist: number, broadphaseRadius: number?): (BasePart?, number?)
	if maxDist <= 0 then
		return nil, nil
	end
	local history = histories[character]
	local now = workspace:GetServerTimeNow()
	local snapA, snapB, alpha, useLiveB = resolveSample(history, t, now)

	local radius = if broadphaseRadius ~= nil then broadphaseRadius else CombatConfig.BroadphaseRadius
	if radius > 0 then
		local rootPos = sampleRootPosition(character, snapA, snapB, alpha, useLiveB)
		if rootPos then
			local toRoot = rootPos - origin
			local proj = math.clamp(toRoot:Dot(dirUnit), 0, maxDist)
			local perp = toRoot - dirUnit * proj
			if perp:Dot(perp) > radius * radius then
				return nil, nil
			end
		end
	end

	local parts = if history then history.parts else collectParts(character)
	local pose = poseTransformFor(character)
	local ray = dirUnit * maxDist
	local bestPart: BasePart? = nil
	local bestFraction = math.huge

	for _, part in parts do
		if part.Parent == character and part.CanQuery then
			local cf = samplePartCFrame(part, pose, snapA, snapB, alpha, useLiveB)
			local fraction = RayHitbox.rayBoxFraction(cf, part.Size, origin, ray)
			if fraction and fraction < bestFraction then
				bestFraction = fraction
				bestPart = part
			end
		end
	end

	if bestPart then
		return bestPart, bestFraction * maxDist
	end
	return nil, nil
end

-- CFrame atual de uma parte com a pose do corpo que o cliente desenha (agachado, slide,
-- derrubado). Usado para conferir a origem do tiro contra a cabeça "de verdade".
function LagCompensation.posedCFrame(character: Model, part: BasePart): CFrame
	local pose = poseTransformFor(character)
	return applyPose(part, pose)
end

-- Cálculo puro do rewind em segundos (testável isoladamente).
-- Sem clientAgeSeconds: clamp(ping + InterpolationDelay, 0, MaxRewindSeconds).
-- Com clientAgeSeconds (CombatFire): nunca passa de ping + InterpolationDelay + ClientTimestampSlack nem MaxRewindSeconds.
function LagCompensation.computeRewindSeconds(pingSeconds: number, clientAgeSeconds: number?): number
	local ping = if pingSeconds == pingSeconds and pingSeconds > 0 and pingSeconds < math.huge then pingSeconds else 0
	local pingRewind = math.clamp(ping + CombatConfig.InterpolationDelay, 0, CombatConfig.MaxRewindSeconds)
	if clientAgeSeconds == nil then
		return pingRewind
	end
	local maxAllowed = math.min(
		CombatConfig.MaxRewindSeconds,
		ping + CombatConfig.InterpolationDelay + CombatConfig.ClientTimestampSlack
	)
	local desired = clientAgeSeconds + CombatConfig.InterpolationDelay
	if desired ~= desired or math.abs(desired) == math.huge then
		return pingRewind
	end
	return math.clamp(desired, 0, maxAllowed)
end

-- Tempo no servidor para reconstruir os alvos usando ping real (e timestamp do cliente quando enviado)
function LagCompensation.rewindTime(player: Player, clientTimestamp: number?): number
	local now = workspace:GetServerTimeNow()
	local ping = player:GetNetworkPing()
	local clientAge: number? = if clientTimestamp ~= nil then (now - clientTimestamp) else nil
	local rewind = LagCompensation.computeRewindSeconds(ping, clientAge)
	if CombatConfig.Debug and CombatConfig.Debug.LogLagComp then
		local mode = if clientTimestamp ~= nil then "client_clamped" else "ping"
		print(("[LagComp] %s ping=%.0fms rewind=%.0fms mode=%s"):format(player.Name, ping * 1000, rewind * 1000, mode))
	end
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