--!strict
-- Controle de recarga no servidor: valida estado/facção, guarda recarga ativa
-- por jogador e cancela ao trocar de arma, cair derrubado, colocar placa, morrer ou sair.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local Factions = require(script.Parent.Factions)

type ReloadState = {
	tool: Tool,
	thread: thread,
	connections: { RBXScriptConnection },
}

local ATTR = CombatContract.Attributes

local Reload = {}

local activeReloads: { [Player]: ReloadState } = {}

local function disconnectAll(connections: { RBXScriptConnection })
	for _, conn in connections do
		conn:Disconnect()
	end
end

function Reload.cancel(player: Player)
	local state = activeReloads[player]
	if not state then
		return
	end
	activeReloads[player] = nil
	disconnectAll(state.connections)
	if coroutine.running() ~= state.thread then
		pcall(task.cancel, state.thread)
	end
	if state.tool.Parent then
		state.tool:SetAttribute(ATTR.Reloading, false)
	end
end

function Reload.start(player: Player, tool: Tool, weapon: Weapons.WeaponConfig, character: Model)
	if not Factions.canAttack(player) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if character:GetAttribute(ATTR.Downed) == true or character:GetAttribute(ATTR.Plating) == true then
		return
	end
	if activeReloads[player] ~= nil or tool:GetAttribute(ATTR.Reloading) == true then
		return
	end
	local ammo = tool:GetAttribute(ATTR.Ammo)
	if not Net.isFiniteNumber(ammo) or (ammo :: number) >= weapon.MagazineSize then
		return
	end
	local reserve = tool:GetAttribute(ATTR.Reserve)
	if reserve ~= nil and (not Net.isFiniteNumber(reserve) or (reserve :: number) <= 0) then
		return
	end

	tool:SetAttribute(ATTR.Reloading, true)

	local state: ReloadState
	local connections: { RBXScriptConnection } = {}

	table.insert(connections, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= character and activeReloads[player] == state then
			Reload.cancel(player)
		end
	end))
	table.insert(connections, character:GetAttributeChangedSignal(ATTR.Downed):Connect(function()
		if character:GetAttribute(ATTR.Downed) == true and activeReloads[player] == state then
			Reload.cancel(player)
		end
	end))
	table.insert(connections, character:GetAttributeChangedSignal(ATTR.Plating):Connect(function()
		if character:GetAttribute(ATTR.Plating) == true and activeReloads[player] == state then
			Reload.cancel(player)
		end
	end))
	table.insert(connections, humanoid.Died:Connect(function()
		if activeReloads[player] == state then
			Reload.cancel(player)
		end
	end))

	local thread = task.delay(weapon.ReloadTime, function()
		if activeReloads[player] ~= state then
			return
		end
		activeReloads[player] = nil
		disconnectAll(state.connections)
		if tool.Parent then
			tool:SetAttribute(ATTR.Reloading, false)
		end
		if
			player.Parent ~= nil
			and player.Character == character
			and tool.Parent == character
			and humanoid.Health > 0
			and character:GetAttribute(ATTR.Downed) ~= true
			and character:GetAttribute(ATTR.Plating) ~= true
			and Factions.canAttack(player)
		then
			local current = tool:GetAttribute(ATTR.Ammo)
			local inMag = if Net.isFiniteNumber(current) then current :: number else 0
			local need = math.max(0, weapon.MagazineSize - inMag)
			local left = tool:GetAttribute(ATTR.Reserve)
			if Net.isFiniteNumber(left) then
				local take = math.clamp(need, 0, left :: number)
				tool:SetAttribute(ATTR.Ammo, inMag + take)
				tool:SetAttribute(ATTR.Reserve, (left :: number) - take)
			else
				-- Arma sem reserva (legado): recarga infinita
				tool:SetAttribute(ATTR.Ammo, weapon.MagazineSize)
			end
		end
	end)

	state = {
		tool = tool,
		thread = thread,
		connections = connections,
	}
	activeReloads[player] = state
end

return Reload