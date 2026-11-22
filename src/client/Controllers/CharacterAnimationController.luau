--!strict
-- Locomoção do personagem local (R6) com AnimationTracks: idle, andar, correr, sprint,
-- agachar, no ar e sentado. Substitui o "Animate" padrão do Roblox no jogador.
-- As tracks tocadas no próprio personagem são replicadas pelo Roblox para os outros
-- jogadores (com ID publicado; o ID temporário do Studio só aparece para quem tocou).
-- Braços com arma, slide e derrubado ficam com a camada de arma (PoseAnimator legado).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared:WaitForChild("Config"):WaitForChild("AnimationConfig"))
local AnimationClips = require(Shared.Config:WaitForChild("AnimationClips"))
local ClipBuilder = require(Shared:WaitForChild("Lib"):WaitForChild("ClipBuilder"))
local AnimationTypes = require(Shared.Lib:WaitForChild("AnimationTypes"))

type LocomotionState = AnimationTypes.LocomotionState

-- estado -> clipe
local CLIP_FOR: { [string]: string } = {
	Idle = "Idle",
	IdleCombat = "IdleCombat",
	Walking = "Walk",
	Running = "Run",
	Sprinting = "Sprint",
	Crouching = "Crouch",
	CrouchWalking = "CrouchWalk",
	Airborne = "Air",
	Sitting = "Sit",
}
local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local CharacterAnimationController = {}

local player = Players.LocalPlayer
local animationIds: { [string]: string } = {}

type Session = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	state: LocomotionState?,
	current: AnimationTrack?,
	connections: { RBXScriptConnection },
}
local session: Session? = nil

-- IDs gerados uma vez por cliente (o temporário do Studio é caro de registrar)
local function idFor(clipName: string): string?
	local cached = animationIds[clipName]
	if cached then
		return cached
	end
	local clip = AnimationClips[clipName]
	if not clip then
		return nil
	end
	local id = ClipBuilder.animationId(clipName, clip, AnimationConfig.PublishedIds)
	if id then
		animationIds[clipName] = id
	end
	return id
end

local function hasGun(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("Weapon") ~= nil
end

local function chooseState(s: Session): LocomotionState
	local character, humanoid = s.character, s.humanoid
	if humanoid.Health <= 0 then
		return "Dead"
	end
	if character:GetAttribute("Downed") == true then
		return "Downed"
	end
	if character:GetAttribute("Sliding") == true then
		return "Sliding"
	end
	if humanoid.Sit then
		return "Sitting"
	end
	if AIR_STATES[humanoid:GetState()] then
		return "Airborne"
	end
	local v = s.root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = speed > AnimationConfig.MovingSpeed and humanoid.MoveDirection.Magnitude > 0.05
	if character:GetAttribute("Crouching") == true then
		return if moving then "CrouchWalking" else "Crouching"
	end
	if not moving then
		return if hasGun(character) then "IdleCombat" else "Idle"
	end
	if character:GetAttribute("Sprinting") == true or speed >= AnimationConfig.SprintSpeed then
		return "Sprinting"
	end
	return if speed >= AnimationConfig.RunSpeed then "Running" else "Walking"
end

local function stopAll(s: Session, fade: number)
	for _, track in s.tracks do
		if track.IsPlaying then
			track:Stop(fade)
		end
	end
	s.current = nil
end

local function update(s: Session)
	local state = chooseState(s)
	local clipName = CLIP_FOR[state]

	if state ~= s.state then
		s.state = state
		local fade = AnimationConfig.Fades[state] or AnimationConfig.DefaultFade
		if not clipName or AnimationTypes.ProceduralBody[state] then
			-- slide, derrubado e morte: o corpo é de outro sistema
			stopAll(s, fade)
		else
			local track = s.tracks[clipName]
			if track and track ~= s.current then
				if s.current then
					s.current:Stop(fade)
				end
				track:Play(fade)
				s.current = track
			end
		end
	end

	-- casa a passada com a velocidade real (o pé não "patina")
	local current = s.current
	local clip = clipName and AnimationClips[clipName]
	if current and clip and clip.refSpeed then
		local v = s.root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local rate = math.clamp(speed / clip.refSpeed, AnimationConfig.MinPlaybackSpeed, AnimationConfig.MaxPlaybackSpeed)
		if math.abs(current.Speed - rate) > 0.03 then
			current:AdjustSpeed(rate)
		end
	end
end

local function cleanup()
	local s = session
	if not s then
		return
	end
	session = nil
	for _, connection in s.connections do
		connection:Disconnect()
	end
	for _, track in s.tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function setup(character: Model)
	cleanup()
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or not character:FindFirstChild("Torso") then
		return -- só R6
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	-- tira o Animate padrão do Roblox e o que ele já estiver tocando
	local default = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 2)
	if default then
		default:Destroy()
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end

	-- carrega cada clipe uma vez por personagem (tracks reaproveitadas)
	local tracks: { [string]: AnimationTrack } = {}
	for clipName in AnimationClips do
		local id = idFor(clipName)
		if id then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local track = animator:LoadAnimation(animation)
			track.Priority = (Enum.AnimationPriority :: any)[AnimationClips[clipName].priority]
			track.Looped = AnimationClips[clipName].loop
			tracks[clipName] = track
		end
	end

	local s: Session = {
		character = character,
		humanoid = humanoid,
		root = root,
		tracks = tracks,
		state = nil,
		current = nil,
		connections = {},
	}
	session = s
	table.insert(s.connections, RunService.Heartbeat:Connect(function()
		if session == s then
			update(s)
		end
	end))
	table.insert(s.connections, humanoid.Died:Connect(function()
		stopAll(s, 0.1)
	end))
end

function CharacterAnimationController:Start()
	if player.Character then
		task.spawn(setup, player.Character)
	end
	player.CharacterAdded:Connect(setup)
	player.CharacterRemoving:Connect(cleanup)
end

return CharacterAnimationController
