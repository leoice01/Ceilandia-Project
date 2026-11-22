--!strict
-- Transforma os clipes de AnimationClips (poses em graus, no espaço da peça "pai")
-- em KeyframeSequence do Roblox para R6. O mesmo KeyframeSequence abre no Animation
-- Editor e pode ser publicado; no Studio dá para testar com ID temporário.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

export type JointPose = {
	rx: number?, -- graus no eixo X do pai: perna/braço positivo = para frente; Root negativo = tronco para frente
	ry: number?, -- graus no eixo Y do pai (giro)
	rz: number?, -- graus no eixo Z do pai
	out: number?, -- abrir para fora (graus); o lado é resolvido aqui (direito/esquerdo)
	pos: Vector3?, -- deslocamento em studs no espaço do pai (Root: abaixar o corpo)
}
export type JointName = "Root" | "Neck" | "RightShoulder" | "LeftShoulder" | "RightHip" | "LeftHip"
export type ClipKey = { t: number, pose: { [string]: JointPose } }
export type Clip = {
	length: number,
	loop: boolean,
	priority: string, -- nome de Enum.AnimationPriority
	refSpeed: number?, -- velocidade (studs/s) em que o clipe toca na velocidade 1
	keys: { ClipKey },
}

-- C0 padrão das juntas do R6
local C0: { [string]: CFrame } = {
	Root = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	Neck = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	RightShoulder = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftShoulder = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	RightHip = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	LeftHip = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}
-- peça movida por cada junta (nome do Pose no KeyframeSequence)
local PART: { [string]: string } = {
	Root = "Torso",
	Neck = "Head",
	RightShoulder = "Right Arm",
	LeftShoulder = "Left Arm",
	RightHip = "Right Leg",
	LeftHip = "Left Leg",
}
local SIDE: { [string]: number } = { RightShoulder = 1, LeftShoulder = -1, RightHip = 1, LeftHip = -1 }
local LIMBS = { "Neck", "RightShoulder", "LeftShoulder", "RightHip", "LeftHip" }

local ClipBuilder = {}

-- Pose em graus no espaço do pai -> Motor6D.Transform da junta
function ClipBuilder.toTransform(joint: string, pose: JointPose?): CFrame
	if not pose then
		return CFrame.identity
	end
	local c0 = C0[joint]
	local pivot = c0.Position
	local rz = (pose.rz or 0) + (pose.out or 0) * (SIDE[joint] or 1)
	local rotation = CFrame.Angles(math.rad(pose.rx or 0), math.rad(pose.ry or 0), math.rad(rz))
	local inParent = CFrame.new(pose.pos or Vector3.zero) * CFrame.new(pivot) * rotation * CFrame.new(-pivot)
	return c0:Inverse() * inParent * c0
end

local function newPose(name: string, cf: CFrame, parent: Instance): Pose
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	p.Weight = 1
	p.EasingStyle = Enum.PoseEasingStyle.Cubic
	p.EasingDirection = Enum.PoseEasingDirection.InOut
	p.Parent = parent
	return p
end

function ClipBuilder.build(name: string, clip: Clip): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = clip.loop
	sequence.Priority = (Enum.AnimationPriority :: any)[clip.priority]
	for _, key in clip.keys do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = key.t
		local rootPose = newPose("HumanoidRootPart", CFrame.identity, keyframe)
		local torsoPose = newPose(PART.Root, ClipBuilder.toTransform("Root", key.pose.Root), rootPose)
		for _, joint in LIMBS do
			newPose(PART[joint], ClipBuilder.toTransform(joint, key.pose[joint]), torsoPose)
		end
		keyframe.Parent = sequence
	end
	return sequence
end

-- ID para tocar o clipe: o publicado, se existir; senão um temporário (só funciona no Studio)
function ClipBuilder.animationId(name: string, clip: Clip, published: { [string]: string }): string?
	local id = published[name]
	if id and id ~= "" then
		return id
	end
	-- ID temporário só existe no Studio; no jogo publicado o clipe precisa de ID publicado
	if not RunService:IsStudio() then
		return nil
	end
	local ok, temp = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(ClipBuilder.build(name, clip))
	end)
	if ok then
		return temp
	end
	warn(("[ClipBuilder] clipe %s sem ID publicado e sem ID temporário: %s"):format(name, tostring(temp)))
	return nil
end

return ClipBuilder
