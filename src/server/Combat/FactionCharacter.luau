--!strict
-- Helpers de personagem para Escolha de Lado: proteção de ferramentas para Civil,
-- ajuste/restauração de velocidade na transformação, replicação LOD de FX e morte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local FactionsConfig = require(ReplicatedStorage.Shared.Config.Factions)
local Factions = require(script.Parent.Factions)

type FactionTransformKind = CombatContract.FactionTransformKind

local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions

local FactionCharacter = {}

local function isWeaponTool(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(ATTR.Weapon) ~= nil
end

function FactionCharacter.info(player: Player): (Model?, Humanoid?, BasePart?, boolean, boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPart = if root and root:IsA("BasePart") then root else nil
	local alive = humanoid ~= nil and humanoid.Health > 0
	local downed = character ~= nil and character:GetAttribute(ATTR.Downed) == true
	return character, humanoid, rootPart, alive, downed
end

function FactionCharacter.enforceCivilTools(player: Player)
	if Factions.of(player) ~= FACTIONS.Civil then
		return
	end
	local character, humanoid = FactionCharacter.info(player)
	if not character or not humanoid then
		return
	end
	for _, child in character:GetChildren() do
		if isWeaponTool(child) then
			humanoid:UnequipTools()
			return
		end
	end
end

function FactionCharacter.applyTransformSpeed(player: Player): number?
	local _, humanoid = FactionCharacter.info(player)
	local mult = FactionsConfig.TransformWalkSpeedMultiplier
	if humanoid and mult > 0 and mult < 1 then
		local saved = humanoid.WalkSpeed
		humanoid.WalkSpeed = saved * mult
		return saved
	end
	return nil
end

function FactionCharacter.restoreSpeed(player: Player, saved: number?)
	if not saved then
		return
	end
	local character, humanoid, _, alive, downed = FactionCharacter.info(player)
	if character and humanoid and alive and not downed then
		humanoid.WalkSpeed = saved
	end
end

function FactionCharacter.replicateFx(remote: RemoteEvent?, actor: Player, kind: FactionTransformKind, duration: number)
	if not remote then
		return
	end
	local _, _, actorRoot = FactionCharacter.info(actor)
	if not actorRoot then
		return
	end
	local origin = actorRoot.Position
	local radius = FactionsConfig.TransformFxRadius
	for _, other in Players:GetPlayers() do
		local _, _, otherRoot = FactionCharacter.info(other)
		if other == actor or (otherRoot and (otherRoot.Position - origin).Magnitude <= radius) then
			remote:FireClient(other, actor, kind, duration)
		end
	end
end

function FactionCharacter.bind(
	player: Player,
	connections: { RBXScriptConnection },
	character: Model,
	onDied: (killer: Player?) -> ()
)
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)

	FactionCharacter.enforceCivilTools(player)
	table.insert(connections, character.ChildAdded:Connect(function(child: Instance)
		if Factions.of(player) == FACTIONS.Civil and isWeaponTool(child) then
			task.defer(FactionCharacter.enforceCivilTools, player)
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(connections, humanoid.Died:Connect(function()
			local creator = humanoid:FindFirstChild("creator")
			local killer = if creator and creator:IsA("ObjectValue") and creator.Value and creator.Value:IsA("Player")
				then creator.Value
				else nil
			onDied(if killer ~= player then killer else nil)
		end))
	end
end

return FactionCharacter