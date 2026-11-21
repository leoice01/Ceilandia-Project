--!strict
-- Placas de colete (estilo Warzone). O colete guarda até MaxPlates placas; cada placa
-- tem PlateHealth de armadura, que absorve o dano antes da vida. O jogador carrega
-- placas extras e coloca uma por vez (não atira enquanto coloca). Caixas de placas
-- (tag ArmorCrate) enchem a mochila.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local ArmorConfig = require(ReplicatedStorage.Shared.Config.Armor)
local Damage = require(script.Parent.Parent.Combat.Damage)

type ArmorHit = CombatContract.ArmorHit

local ATTR = CombatContract.Attributes
local EPSILON = 1e-6
local DISTANCE_SLACK = 2 -- folga na distância da caixa para variação de rede (studs)

local ArmorService = {}

-- Ficha da placa sendo colocada; trocar ou apagar cancela a colocação em andamento
local platingToken: { [Model]: number } = {}
local nextToken = 0
local crateLastUse: { [Player]: number } = {}

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Quantas placas (inteiras ou partidas) uma quantidade de armadura representa
local function platesIn(armor: number): number
	return math.ceil(armor / ArmorConfig.PlateHealth - EPSILON)
end

-- Tira o dano da armadura antes da vida. Capacete protege a cabeça primeiro;
-- o colete protege o corpo todo (ou só o tronco, conforme a config).
-- Retorna o dano que passa para a vida e o tipo de acerto na armadura.
function ArmorService.absorb(model: Model, region: Damage.Region, damage: number): (number, ArmorHit)
	local kind: ArmorHit = "None"
	local remaining = damage

	if region == "Head" then
		local helmet = numberAttribute(model, ATTR.Helmet)
		if helmet > 0 then
			local left, through = Damage.absorb(helmet, remaining)
			model:SetAttribute(ATTR.Helmet, left)
			remaining = through
			kind = if left <= 0 then "Broken" else "Hit"
		end
	end

	if remaining > 0 and (ArmorConfig.VestCoversAllRegions or region == "Torso") then
		local vest = numberAttribute(model, ATTR.Vest)
		if vest > 0 then
			local left, through = Damage.absorb(vest, remaining)
			model:SetAttribute(ATTR.Vest, left)
			remaining = through
			if platesIn(left) < platesIn(vest) then
				kind = "Broken"
			elseif kind == "None" then
				kind = "Hit"
			end
		end
	end

	return remaining, kind
end

-- Derrubado perde o colete e para de colocar placa
function ArmorService.strip(model: Model)
	platingToken[model] = nil
	model:SetAttribute(ATTR.Vest, 0)
	model:SetAttribute(ATTR.Plating, nil)
end

local function equipOnSpawn(player: Player, character: Model)
	local plateHealth = ArmorConfig.PlateHealth
	character:SetAttribute(ATTR.VestMax, ArmorConfig.MaxPlates * plateHealth)
	character:SetAttribute(ATTR.Vest, math.min(ArmorConfig.SpawnPlates, ArmorConfig.MaxPlates) * plateHealth)
	player:SetAttribute(ATTR.PlatesCarried, math.min(ArmorConfig.SpawnCarried, ArmorConfig.CarryMax))
end

-- Item "Placas" na mochila. A mochila é refeita a cada spawn, então dá de novo;
-- o defer espera o Roblox copiar o StarterPack antes, para não ser apagado.
local function givePlateItem(player: Player)
	task.defer(function()
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
		if not backpack then
			return
		end
		local item = CombatContract.PlateItem
		for _, holder in { backpack, player.Character } do
			if holder then
				for _, child in holder:GetChildren() do
					if child:IsA("Tool") and child:GetAttribute(item.Attribute) == true then
						return
					end
				end
			end
		end
		local tool = Instance.new("Tool")
		tool.Name = item.Name
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		tool.ToolTip = "Clique ou segure para colocar placas"
		tool:SetAttribute(item.Attribute, true)
		tool.Parent = backpack
	end)
end

local function isStanding(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or character:GetAttribute(ATTR.Downed) == true then
		return nil
	end
	return humanoid
end

local function finishPlate(player: Player, character: Model, token: number)
	if platingToken[character] ~= token then
		return -- cancelada (caiu, morreu ou foi trocada)
	end
	platingToken[character] = nil
	if not character.Parent then
		return
	end
	character:SetAttribute(ATTR.Plating, nil)
	if player.Character ~= character or not isStanding(character) then
		return
	end
	local carried = numberAttribute(player, ATTR.PlatesCarried)
	local current = numberAttribute(character, ATTR.Vest)
	local maximum = numberAttribute(character, ATTR.VestMax)
	if carried <= 0 or current >= maximum then
		return
	end
	-- A placa nova completa a próxima placa: 30 vira 50, 50 vira 100 (como no Warzone)
	local plateHealth = ArmorConfig.PlateHealth
	local filled = math.floor(current / plateHealth + EPSILON) + 1
	character:SetAttribute(ATTR.Vest, math.min(maximum, filled * plateHealth))
	player:SetAttribute(ATTR.PlatesCarried, carried - 1)
end

-- Pedido de colocar uma placa. Pedido fora de hora (já colocando, colete cheio, sem
-- placa) é ignorado sem log: o cliente pode mandar de novo enquanto o botão está apertado.
local function onInsertPlate(player: Player)
	local character = player.Character
	if not character or not isStanding(character) then
		return
	end
	if character:GetAttribute(ATTR.Plating) == true then
		return
	end
	if numberAttribute(player, ATTR.PlatesCarried) <= 0 then
		return
	end
	if numberAttribute(character, ATTR.Vest) >= numberAttribute(character, ATTR.VestMax) then
		return
	end
	nextToken += 1
	local token = nextToken
	platingToken[character] = token
	character:SetAttribute(ATTR.Plating, true)
	task.delay(ArmorConfig.PlateInsertSeconds, finishPlate, player, character, token)
end

local function setupCrate(instance: Instance)
	if not instance:IsA("BasePart") or instance:FindFirstChild(CombatContract.Prompts.ArmorCrate) then
		return
	end
	local part = instance
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = CombatContract.Prompts.ArmorCrate
	prompt.ActionText = "Pegar placas"
	prompt.ObjectText = "Caixa de placas"
	prompt.MaxActivationDistance = ArmorConfig.CrateInteractDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root or not isStanding(character) then
			return
		end
		if (root.Position - part.Position).Magnitude > ArmorConfig.CrateInteractDistance + DISTANCE_SLACK then
			Net.reportAbuse(player, "PromptArmorCrate", "too_far")
			return
		end
		local now = os.clock()
		local last = crateLastUse[player]
		if last and now - last < ArmorConfig.CrateCooldownSeconds then
			return
		end
		crateLastUse[player] = now
		player:SetAttribute(ATTR.PlatesCarried, ArmorConfig.CarryMax)
	end)
end

local function removeCrate(instance: Instance)
	local prompt = instance:FindFirstChild(CombatContract.Prompts.ArmorCrate)
	if prompt then
		prompt:Destroy()
	end
end

function ArmorService:Init()
	Net.serverEvent(CombatContract.Remotes.InsertPlate)
end

function ArmorService:Start()
	Net.listen(CombatContract.Remotes.InsertPlate, Net.noArgs, onInsertPlate, ArmorConfig.PlateRemoteMinInterval)

	local function onPlayer(player: Player)
		if player.Character then
			equipOnSpawn(player, player.Character)
			givePlateItem(player)
		end
		player.CharacterAdded:Connect(function(character: Model)
			equipOnSpawn(player, character)
			givePlateItem(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		crateLastUse[player] = nil
	end)

	local tag = CombatContract.Tags.ArmorCrate
	for _, crate in CollectionService:GetTagged(tag) do
		setupCrate(crate)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(setupCrate)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeCrate)
end

return ArmorService
