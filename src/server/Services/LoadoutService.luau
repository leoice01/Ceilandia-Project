--!strict
-- Dá as armas de cada jogador ao nascer: principal e secundária (Shared/Config/Loadout),
-- com pente cheio e munição reserva. Quem controla munição e recarga é o CombatService;
-- equipar/guardar é a Tool do Roblox (o cliente equipa e o servidor vê pela Tool no personagem).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local LoadoutConfig = require(ReplicatedStorage.Shared.Config.Loadout)
local WeaponModels = require(script.Parent.Parent.Combat.WeaponModels)

local ATTR = CombatContract.Attributes

local LoadoutService = {}

local function makeWeapon(weaponId: string): Tool?
	local weapon = Weapons[weaponId]
	if not weapon then
		warn(("[LoadoutService] arma %s não existe em Shared/Config/Weapons"):format(weaponId))
		return nil
	end
	local tool = WeaponModels.build(weaponId, weapon.WeaponType)
	tool.Name = weapon.DisplayName
	tool:SetAttribute(ATTR.Weapon, weaponId)
	tool:SetAttribute(ATTR.Slot, weapon.Slot)
	tool:SetAttribute(ATTR.Ammo, weapon.MagazineSize)
	tool:SetAttribute(ATTR.Reserve, weapon.ReserveAmmo)
	tool:SetAttribute(ATTR.Reloading, false)
	return tool
end

local function loadoutIds(): { string }
	local ids = { LoadoutConfig.Primary, LoadoutConfig.Secondary }
	if RunService:IsStudio() then
		for _, id in LoadoutConfig.StudioExtras do
			table.insert(ids, id)
		end
	end
	return ids
end

-- Síncrono no CharacterAdded: as armas entram na mochila antes dos outros itens
-- (que usam task.defer) e ficam nos atalhos 1 e 2
local function giveLoadout(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		return
	end
	-- arma que não veio daqui (StarterPack antigo) sai, para não ter duas
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(ATTR.Weapon) ~= nil and child:GetAttribute(ATTR.Slot) == nil then
			child:Destroy()
		end
	end
	for _, weaponId in loadoutIds() do
		local tool = makeWeapon(weaponId)
		if tool then
			tool.Parent = backpack
		end
	end
end

function LoadoutService:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			giveLoadout(player)
		end)
		if player.Character then
			giveLoadout(player)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return LoadoutService
