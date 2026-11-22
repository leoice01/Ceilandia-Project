--!strict
-- Estado da arma equipada no servidor: leitura da Tool/WeaponConfig, tempo de saque
-- (EquipTime), cancelamento de recarga ao guardar e validação inicial de Shared.Config.Weapons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Reload = require(script.Parent.Reload)

type WeaponConfig = Weapons.WeaponConfig

local ATTR = CombatContract.Attributes

-- chave fraca: a Tool destruída (respawn) sai sozinha da tabela
local equippedAt: { [Tool]: number } = setmetatable({}, { __mode = "k" }) :: any

local WeaponState = {}

function WeaponState.getEquipped(player: Player): (Tool?, string?, WeaponConfig?, Model?)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not character or not tool then
		return nil, nil, nil, nil
	end
	local weaponId = tool:GetAttribute(ATTR.Weapon)
	local weapon = if typeof(weaponId) == "string" then Weapons[weaponId] else nil
	if not weapon then
		return nil, nil, nil, nil
	end
	return tool, weaponId :: string, weapon, character
end

function WeaponState.isDrawing(tool: Tool, weapon: WeaponConfig): boolean
	local drawnAt = equippedAt[tool]
	return drawnAt ~= nil and (os.clock() - drawnAt) < weapon.EquipTime * CombatConfig.FireRateTolerance
end

local function watchCharacter(player: Player, character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and typeof(child:GetAttribute(ATTR.Weapon)) == "string" then
			equippedAt[child] = os.clock()
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and equippedAt[child] then
			equippedAt[child] = nil
			Reload.cancel(player)
		end
	end)
end

function WeaponState.startWatching()
	local function onPlayer(player: Player)
		if player.Character then
			watchCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character: Model)
			watchCharacter(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

function WeaponState.validateConfig()
	for weaponId, weapon in Weapons do
		local ok = Net.isFiniteNumber(weapon.Damage)
			and weapon.Damage > 0
			and Net.isFiniteNumber(weapon.FireInterval)
			and weapon.FireInterval > 0
			and Net.isFiniteNumber(weapon.Range)
			and weapon.Range > 0
			and Net.isFiniteNumber(weapon.MagazineSize)
			and weapon.MagazineSize > 0
			and Net.isFiniteNumber(weapon.ReloadTime)
			and weapon.ReloadTime >= 0
			and Net.isFiniteNumber(weapon.HeadshotMultiplier)
			and weapon.HeadshotMultiplier > 0
		if not ok then
			warn(("[CombatService] Arma '%s' em Shared.Config.Weapons tem valores inválidos"):format(weaponId))
		end
	end
end

return WeaponState