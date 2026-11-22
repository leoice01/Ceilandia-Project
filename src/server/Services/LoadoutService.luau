--!strict
-- Dá as armas de cada jogador ao nascer: principal e secundária da facção (Shared/Config/Loadout),
-- com pente cheio e munição reserva. Quem controla munição e recarga é o CombatService;
-- equipar/guardar é a Tool do Roblox (o cliente equipa e o servidor vê pela Tool no personagem).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local LoadoutConfig = require(ReplicatedStorage.Shared.Config.Loadout)
local WeaponModels = require(script.Parent.Parent.Combat.WeaponModels)
local Factions = require(script.Parent.Parent.Combat.Factions)

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

-- Kit da facção atual (policial e ladrão têm armas diferentes; civil não tem)
local function loadoutIds(player: Player): { string }
	local kit = LoadoutConfig.ByFaction[Factions.of(player)]
	if not kit then
		return {}
	end
	local ids = { kit.Primary, kit.Secondary }
	if RunService:IsStudio() then
		for _, id in LoadoutConfig.StudioExtras do
			-- arma extra que já está no kit não entra de novo
			if not table.find(ids, id) then
				table.insert(ids, id)
			end
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
	-- nunca duas cópias: qualquer arma que já esteja na mochila ou na mão sai antes
	-- (StarterPack antigo, chamada repetida, kit da equipe anterior)
	for _, holder in { backpack, player.Character } do
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(ATTR.Weapon) ~= nil then
					child:Destroy()
				end
			end
		end
	end
	for _, weaponId in loadoutIds(player) do
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
