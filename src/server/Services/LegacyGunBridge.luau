--!strict
-- PONTE TEMPORÁRIA: liga a arma legada (GunClient, remotes em ReplicatedStorage.Remotes)
-- ao CombatService novo, para dar para jogar com armadura, derrubado e números de dano
-- antes do cliente novo da P1. O GunServer legado precisa estar desativado, senão o
-- tiro contaria duas vezes. Apagar este arquivo quando o WeaponController da P1 usar CombatFire.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local CombatService = require(script.Parent.CombatService)

local ATTR = CombatContract.Attributes
local LEGACY_SHOULDER_PEEK = 1.3 -- mesmo valor do GunServer legado (studs)
local LEGACY_FIRE = "LegacyGunFire"
local LEGACY_RELOAD = "LegacyGunReload"

local LegacyGunBridge = {}

local lastReload: { [Player]: number } = {}

local function remoteIn(folder: Instance, name: string): RemoteEvent?
	local remote = folder:FindFirstChild(name)
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

-- Mesma origem do GunServer legado: cabeça, deslocada para o ombro se não tiver parede
local function legacyOrigin(character: Model, head: BasePart): Vector3
	local origin = head.Position
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local side = character:GetAttribute("ShoulderSide")
	if root and (side == 1 or side == -1) then
		local peek = root.CFrame.RightVector * (side :: number) * LEGACY_SHOULDER_PEEK
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		if not workspace:Raycast(origin, peek, params) then
			origin += peek
		end
	end
	return origin
end

function LegacyGunBridge:Start()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		return
	end
	local gunFire = remoteIn(folder, "GunFire")
	local gunReload = remoteIn(folder, "GunReload")
	local gunHit = remoteIn(folder, "GunHit")
	local gunFx = remoteIn(folder, "GunFX")
	if not gunFire or not gunReload or not gunHit or not gunFx then
		return
	end

	local legacyServer = ServerScriptService:FindFirstChild("GunServer")
	if legacyServer and legacyServer:IsA("Script") and legacyServer.Enabled then
		warn("[LegacyGunBridge] GunServer legado está ativo; ponte desligada para não contar tiro duas vezes")
		return
	end

	gunFire.OnServerEvent:Connect(function(player: Player, target: unknown)
		if not Net.isFiniteVector3(target) then
			Net.reportAbuse(player, LEGACY_FIRE, "bad_target")
			return
		end
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local tool = character and character:FindFirstChildOfClass("Tool")
		if not character or not head or not tool then
			return
		end
		local weaponId = tool:GetAttribute(ATTR.Weapon)
		if typeof(weaponId) ~= "string" then
			return
		end
		local origin = legacyOrigin(character, head)
		local offset = (target :: Vector3) - origin
		if offset.Magnitude < 0.05 then
			return
		end

		-- O cliente legado não manda timestamp: usa o tempo do servidor (rewind só da interpolação)
		local report = CombatService.fire(player, {
			origin = origin,
			direction = offset.Unit,
			timestamp = workspace:GetServerTimeNow(),
			weaponId = weaponId,
			seq = CombatService.nextSeq(player),
		})
		if not report then
			return
		end

		-- Hitmarker do GunClient legado: (headshot, killed)
		if report.region then
			gunHit:FireClient(player, report.region == "Head", report.result ~= "Hit")
		end
		-- Rastro do tiro no GunClient legado dos outros jogadores por perto
		for _, other in Players:GetPlayers() do
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if other ~= player and otherRoot then
				local near = (otherRoot.Position - report.origin).Magnitude <= CombatConfig.FxRadius
					or (otherRoot.Position - report.hitPos).Magnitude <= CombatConfig.FxRadius
				if near then
					gunFx:FireClient(other, report.tool, report.origin, report.hitPos)
				end
			end
		end
	end)

	gunReload.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		local last = lastReload[player]
		if last and now - last < CombatConfig.ReloadRemoteMinInterval then
			Net.reportAbuse(player, LEGACY_RELOAD, "rate_limit")
			return
		end
		lastReload[player] = now
		CombatService.reload(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastReload[player] = nil
	end)
end

return LegacyGunBridge
