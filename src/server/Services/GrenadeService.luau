--!strict
-- Granada de teste. O cliente só pede "lancei nesta direção"; o servidor cria a granada
-- (física do servidor, sem dono cliente), espera o pavio e explode:
--   - quebra vidros, portas e objetos destrutíveis pelo sistema de destruição do place
--   - dano em quem está no raio (cai com a distância, parede bloqueia), passando pela
--     armadura e pelo derrubado do CombatService. Quem lança também se machuca.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local GrenadeConfig = require(ReplicatedStorage.Shared.Config.Grenade)
local Factions = require(script.Parent.Parent.Combat.Factions)
local CombatService = require(script.Parent.CombatService)
local WantedService = require(script.Parent.WantedService)

local ATTR = CombatContract.Attributes
local ITEM = CombatContract.GrenadeItem
local REMOTE = CombatContract.Remotes.GrenadeThrow
local FACTIONS = CombatContract.Factions
local HAND_OFFSET = 2.5 -- a granada nasce a essa distância da cabeça, na direção do arremesso (studs)
local GRENADE_SIZE = 0.9 -- (studs)

type DestructionApi = { Explode: (Vector3, number, number) -> () }

local GrenadeService = {}

local lastThrow: { [Player]: number } = {}
local destruction: DestructionApi? = nil

-- Sistema de destruição do place (legado, fora do repositório). Sem ele, a granada só dá dano.
local function findDestruction(): DestructionApi?
	local folder = ServerScriptService:FindFirstChild("Destruction")
	local module = folder and folder:FindFirstChild("DestructionService")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, api = pcall(require, module)
	if ok and type(api) == "table" and type((api :: any).Explode) == "function" then
		return api :: DestructionApi
	end
	warn("[GrenadeService] DestructionService encontrado mas não carregou; granada sem destruição")
	return nil
end

local function countOf(player: Player): number
	local value = player:GetAttribute(ITEM.CountAttribute)
	return if typeof(value) == "number" then value else 0
end

local function findItem(player: Player): Tool?
	for _, holder in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(ITEM.Attribute) == true then
					return child
				end
			end
		end
	end
	return nil
end

-- O nome do item mostra quantas granadas restam na barra de itens
local function refreshItemName(player: Player)
	local tool = findItem(player)
	if tool then
		tool.Name = ("%s x%d"):format(ITEM.Name, countOf(player))
	end
end

local function giveItem(player: Player)
	player:SetAttribute(ITEM.CountAttribute, GrenadeConfig.SpawnCount)
	task.defer(function()
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
		if not backpack then
			return
		end
		if not findItem(player) then
			local tool = Instance.new("Tool")
			tool.RequiresHandle = false
			tool.CanBeDropped = false
			tool.ToolTip = "Clique para lançar"
			tool:SetAttribute(ITEM.Attribute, true)
			tool.Parent = backpack
		end
		refreshItemName(player)
	end)
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

-- Dano em todos os humanoides no raio, com linha de visão da explosão até o corpo
local function damageAround(position: Vector3, thrower: Player, grenade: BasePart)
	local radius = GrenadeConfig.Radius
	local victims: { [Model]: boolean } = {}
	local ignore: { Instance } = { grenade }
	for _, part in workspace:GetPartBoundsInRadius(position, radius) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not victims[model] then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				victims[model] = true
				table.insert(ignore, model) -- um corpo não protege outro
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	for model in victims do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = rootOf(model)
		if humanoid and root then
			local offset = root.Position - position
			local distance = offset.Magnitude
			local victim = Players:GetPlayerFromCharacter(model)
			local isSelf = victim == thrower
			local allowed = isSelf or Factions.canDamage(thrower, victim)
			-- parede entre a explosão e o corpo bloqueia o dano
			local blocked = distance > 0.5 and workspace:Raycast(position, offset, params) ~= nil
			if distance <= radius and allowed and not blocked then
				local falloff = 1 + (GrenadeConfig.EdgeMultiplier - 1) * math.clamp(distance / radius, 0, 1)
				local amount = GrenadeConfig.MaxDamage * falloff
				if isSelf then
					amount *= GrenadeConfig.SelfDamageMultiplier
				end
				CombatService.applyDamage(thrower, model, humanoid, "Torso", amount, root.Position, position)
			end
		end
	end
end

local function explode(grenade: BasePart, thrower: Player)
	if not grenade.Parent then
		return
	end
	local position = grenade.Position
	grenade:Destroy()

	-- efeito visual e som padrão do Roblox, sem empurrar nem desmontar nada
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = GrenadeConfig.Radius
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = workspace

	if destruction then
		destruction.Explode(position, GrenadeConfig.Radius, GrenadeConfig.DestructionDamage)
	end
	damageAround(position, thrower, grenade)
	WantedService.onExplosion(thrower, position)
end

local function onThrow(player: Player, direction: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not head then
		return
	end
	if character:GetAttribute(ATTR.Downed) == true or Factions.of(player) == FACTIONS.Civil then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute(ITEM.Attribute) ~= true then
		Net.reportAbuse(player, REMOTE, "no_grenade_equipped")
		return
	end
	local now = os.clock()
	local last = lastThrow[player]
	if last and now - last < GrenadeConfig.ThrowCooldown then
		return
	end
	local count = countOf(player)
	if count <= 0 then
		return
	end
	lastThrow[player] = now
	player:SetAttribute(ITEM.CountAttribute, count - 1)
	refreshItemName(player)

	local aim = direction.Unit
	-- nasce na frente da mão; se tiver parede logo ali, nasce na cabeça
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local spawnAt = head.Position + aim * HAND_OFFSET
	if workspace:Raycast(head.Position, aim * HAND_OFFSET, params) then
		spawnAt = head.Position
	end

	local grenade = Instance.new("Part")
	grenade.Name = "Grenade"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.one * GRENADE_SIZE
	grenade.Color = Color3.fromRGB(60, 75, 45)
	grenade.Material = Enum.Material.Metal
	grenade.CustomPhysicalProperties = PhysicalProperties.new(2, 0.6, 0.25)
	grenade.CFrame = CFrame.new(spawnAt)
	-- não bate em quem lançou (senão, mirando pra baixo, ela quica no próprio corpo e volta)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local ignore = Instance.new("NoCollisionConstraint")
			ignore.Part0 = grenade
			ignore.Part1 = part
			ignore.Parent = grenade
		end
	end
	grenade.Parent = workspace
	grenade:SetNetworkOwner(nil) -- física no servidor: o cliente não move a granada
	local speed = GrenadeConfig.ThrowSpeed
	grenade.AssemblyLinearVelocity = aim * speed + Vector3.yAxis * speed * GrenadeConfig.ThrowLift

	task.delay(GrenadeConfig.FuseSeconds, explode, grenade, player)
end

local function validateThrow(direction: any): (boolean, string?)
	if not Net.isFiniteVector3(direction) then
		return false, "bad_direction"
	end
	local length = (direction :: Vector3).Magnitude
	if length < 0.5 or length > 1.5 then
		return false, "direction_not_unit"
	end
	return true, nil
end

function GrenadeService:Init()
	Net.serverEvent(REMOTE)
end

function GrenadeService:Start()
	destruction = findDestruction()
	-- rate limit bruto abaixo do cooldown: clique rápido é ignorado pelo cooldown, só spam vira log
	Net.listen(REMOTE, validateThrow, onThrow, GrenadeConfig.ThrowCooldown * 0.25)

	local function onPlayer(player: Player)
		if player.Character then
			giveItem(player)
		end
		player.CharacterAdded:Connect(function()
			giveItem(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastThrow[player] = nil
	end)
end

return GrenadeService
