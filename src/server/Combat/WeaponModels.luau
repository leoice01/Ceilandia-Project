--!strict
-- Monta a Tool de cada arma. Usa o modelo da P3 em ServerStorage.WeaponModels.<WeaponId>
-- (uma Tool com Handle e um Attachment "Muzzle" na ponta do cano); sem modelo, monta um
-- provisório com blocos, no mesmo padrão:
--   Handle = empunhadura (onde a mão direita segura), invisível, cano apontando para -Z,
--   Y para cima. Muzzle = ponta do cano, no espaço do Handle. Peças soldadas no Handle.

local ServerStorage = game:GetService("ServerStorage")

local TEMPLATE_FOLDER = "WeaponModels"
local GUN_COLOR = Color3.fromRGB(38, 38, 42)
local FURNITURE_COLOR = Color3.fromRGB(58, 52, 46)
local HANDLE_SIZE = Vector3.new(0.25, 0.6, 0.25)

type Block = { size: Vector3, at: Vector3, color: Color3? }
type Shape = { blocks: { Block }, muzzle: Vector3 }

-- Formas provisórias por categoria (studs, espaço do Handle). Só aparência: não muda dano.
local SHAPES: { [string]: Shape } = {
	Pistol = {
		blocks = {
			{ size = Vector3.new(0.22, 0.55, 0.3), at = Vector3.new(0, -0.02, 0.04) },
			{ size = Vector3.new(0.24, 0.26, 1.0), at = Vector3.new(0, 0.36, -0.3) },
			{ size = Vector3.new(0.18, 0.1, 0.32), at = Vector3.new(0, 0.18, -0.18) },
		},
		muzzle = Vector3.new(0, 0.36, -0.82),
	},
	SMG = {
		blocks = {
			{ size = Vector3.new(0.26, 0.4, 1.5), at = Vector3.new(0, 0.32, -0.55) },
			{ size = Vector3.new(0.12, 0.12, 0.45), at = Vector3.new(0, 0.38, -1.5) },
			{ size = Vector3.new(0.16, 0.7, 0.24), at = Vector3.new(0, -0.12, -0.8) },
			{ size = Vector3.new(0.14, 0.3, 0.9), at = Vector3.new(0, 0.28, 0.7), color = FURNITURE_COLOR },
		},
		muzzle = Vector3.new(0, 0.38, -1.75),
	},
	AssaultRifle = {
		blocks = {
			{ size = Vector3.new(0.26, 0.42, 1.7), at = Vector3.new(0, 0.3, -0.6) },
			{ size = Vector3.new(0.12, 0.12, 0.7), at = Vector3.new(0, 0.38, -1.8) },
			{ size = Vector3.new(0.18, 0.7, 0.3), at = Vector3.new(0, -0.15, -0.75) },
			{ size = Vector3.new(0.2, 0.42, 1.1), at = Vector3.new(0, 0.2, 0.85), color = FURNITURE_COLOR },
		},
		muzzle = Vector3.new(0, 0.38, -2.15),
	},
	Shotgun = {
		blocks = {
			{ size = Vector3.new(0.26, 0.36, 1.3), at = Vector3.new(0, 0.3, -0.45) },
			{ size = Vector3.new(0.14, 0.14, 1.8), at = Vector3.new(0, 0.42, -1.95) },
			{ size = Vector3.new(0.2, 0.2, 0.7), at = Vector3.new(0, 0.24, -1.55), color = FURNITURE_COLOR },
			{ size = Vector3.new(0.18, 0.45, 1.3), at = Vector3.new(0, 0.15, 0.95), color = FURNITURE_COLOR },
		},
		muzzle = Vector3.new(0, 0.42, -2.85),
	},
	Sniper = {
		blocks = {
			{ size = Vector3.new(0.24, 0.4, 2.6), at = Vector3.new(0, 0.22, -0.2), color = FURNITURE_COLOR },
			{ size = Vector3.new(0.12, 0.12, 1.8), at = Vector3.new(0, 0.38, -2.3) },
			{ size = Vector3.new(0.18, 0.18, 1.0), at = Vector3.new(0, 0.68, -0.5) },
			{ size = Vector3.new(0.08, 0.2, 0.08), at = Vector3.new(0, 0.5, -0.5) },
		},
		muzzle = Vector3.new(0, 0.38, -3.2),
	},
}

local WeaponModels = {}

local function newPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addMuzzle(handle: BasePart, position: Vector3)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = position
	muzzle.Parent = handle
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Brightness = 4
	flash.Range = 8
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Enabled = false
	flash.Parent = muzzle
end

local function placeholder(weaponType: string): Tool
	local shape = SHAPES[weaponType] or SHAPES.AssaultRifle
	local tool = Instance.new("Tool")
	local handle = newPart("Handle", HANDLE_SIZE)
	handle.Transparency = 1
	handle.Parent = tool
	for i, block in shape.blocks do
		local part = newPart("Body" .. i, block.size)
		part.Color = block.color or GUN_COLOR
		part.CFrame = CFrame.new(block.at)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
		part.Parent = tool
	end
	addMuzzle(handle, shape.muzzle)
	return tool
end

-- Tool nova (sem atributos de jogo) para a arma
function WeaponModels.build(weaponId: string, weaponType: string): Tool
	local folder = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
	local template = folder and folder:FindFirstChild(weaponId)
	local tool: Tool
	if template and template:IsA("Tool") and template:FindFirstChild("Handle") then
		tool = template:Clone()
	else
		tool = placeholder(weaponType)
	end
	-- a pose da arma (PoseAnimator) controla a solda da mão; o Grip padrão só vale no primeiro quadro
	tool.Grip = CFrame.identity
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	return tool
end

return WeaponModels
