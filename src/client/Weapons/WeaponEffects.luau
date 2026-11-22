--!strict
-- Efeitos de tiro só no cliente: som, clarão do cano, rastro e faísca no impacto.
-- O próprio tiro aparece na hora (previsão); o dos outros chega pelo CombatFX.
-- Longe da câmera não desenha (mobile médio).

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SHOT_SOUND_ID = "rbxassetid://122876890028097" -- mesmo som do GunClient legado
-- tom do tiro por categoria até a P4 escolher sons próprios
local PITCH: { [string]: number } = { Pistol = 1.2, SMG = 1.1, AssaultRifle = 1, Shotgun = 0.75, Sniper = 0.7 }
local VOLUME: { [string]: number } = { Pistol = 0.5, SMG = 0.5, AssaultRifle = 0.6, Shotgun = 0.8, Sniper = 0.85 }
local TRACER_COLOR = Color3.fromRGB(255, 214, 120)
local SPARK_COLOR = Color3.fromRGB(255, 190, 90)
local MAX_FX_DISTANCE = 250 -- rastro/faísca longe da câmera não aparece (studs)

local WeaponEffects = {}

local folder = Instance.new("Folder")
folder.Name = "WeaponFX_Local"
folder.Parent = workspace

function WeaponEffects.folder(): Folder
	return folder
end

function WeaponEffects.muzzle(tool: Instance): Attachment?
	local muzzle = tool:FindFirstChild("Muzzle", true)
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

function WeaponEffects.shot(tool: Instance, weaponType: string)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local sound = Instance.new("Sound")
		sound.SoundId = SHOT_SOUND_ID
		sound.Volume = VOLUME[weaponType] or 0.6
		sound.PlaybackSpeed = (PITCH[weaponType] or 1) + (math.random() - 0.5) * 0.06
		sound.RollOffMaxDistance = 400
		sound.Parent = handle
		sound:Play()
		Debris:AddItem(sound, 3)
	end
	local muzzle = WeaponEffects.muzzle(tool)
	local flash = muzzle and muzzle:FindFirstChild("Flash")
	if flash and flash:IsA("PointLight") then
		flash.Enabled = true
		task.delay(0.04, function()
			flash.Enabled = false
		end)
	end
end

local function near(position: Vector3): boolean
	return (workspace.CurrentCamera.CFrame.Position - position).Magnitude <= MAX_FX_DISTANCE
end

function WeaponEffects.tracer(origin: Vector3, hitPos: Vector3)
	local distance = (hitPos - origin).Magnitude
	if distance < 0.1 or not (near(origin) or near(hitPos)) then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = TRACER_COLOR
	tracer.Size = Vector3.new(0.05, 0.05, distance)
	tracer.CFrame = CFrame.lookAt(origin, hitPos) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = folder
	TweenService:Create(tracer, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	Debris:AddItem(tracer, 0.1)

	if near(hitPos) then
		local spark = Instance.new("Part")
		spark.Anchored = true
		spark.CanCollide = false
		spark.CanQuery = false
		spark.CanTouch = false
		spark.CastShadow = false
		spark.Shape = Enum.PartType.Ball
		spark.Material = Enum.Material.Neon
		spark.Color = SPARK_COLOR
		spark.Size = Vector3.new(0.3, 0.3, 0.3)
		spark.Position = hitPos
		spark.Parent = folder
		TweenService:Create(spark, TweenInfo.new(0.15), { Size = Vector3.zero, Transparency = 1 }):Play()
		Debris:AddItem(spark, 0.2)
	end
end

return WeaponEffects
