--!strict
-- Polícia x Ladrões na delegacia provisória (workspace.PoliceStation).
-- Opção A: FactionService é o ÚNICO que escreve Player.Faction. Este serviço é espelho:
--   * injeta checagens (Wanted, Robbery, Combat, cooldown) no FactionService
--   * ouve FactionService.onFactionChanged (e o join) para ajustar Team, RespawnLocation,
--     uniforme, Notice e LoadCharacter quando o lado muda
--   * cria os botões físicos da delegacia (RecruitTerminal -> JoinPolice, LeaveLocker -> GoCivil)
--     que encaminham direto para FactionService.requestAction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Net = require(ReplicatedStorage.Shared.Lib.Net)
local Notice = require(ReplicatedStorage.Shared.Lib.Notice)
local TeamsConfig = require(ReplicatedStorage.Shared.Config.Teams)
local CombatService = require(script.Parent.CombatService)
local FactionService = require(script.Parent.FactionService)
local WantedService = require(script.Parent.WantedService)
local RobberyService = require(script.Parent.RobberyService)

type Side = "Police" | "Robbers"

local ATTR = CombatContract.Attributes
local STATION_NAME = "PoliceStation"
local PROMPT_SLACK = 3 -- folga de distância para a rede (studs)
local UNIFORM_FOLDER = "PoliceUniform"

-- Motivos do FactionService -> texto para o jogador
local REASON_TEXT: { [string]: string } = {
	police_full = "A Polícia está cheia agora. Tente de novo em instantes.",
	switch_cooldown = "Você trocou de lado há pouco. Espere um pouco.",
	in_combat = "Você está em combate. Espere um pouco.",
	in_transition = "Termine o que está fazendo antes.",
	wanted = "Você está procurado. Despiste a polícia antes.",
	robbing = "Termine ou abandone o roubo antes.",
	dirty_cash = "Você está com dinheiro sujo. Lave antes.",
	stolen_items = "Você está com itens roubados. Venda antes.",
	not_at_station = "Vá até a delegacia.",
	downed = "Agora não dá.",
	dead = "Só dá para trocar de equipe vivo.",
	already_police = "Você já é policial.",
	already_civil = "Você já está fora da Polícia.",
}

local TeamService = {}

local teams: { [Side]: Team } = {}
local busy: { [Player]: boolean } = {}
local policeSpawn: SpawnLocation? = nil

local function sideConfig(side: Side): { Name: string, Color: BrickColor, Faction: string }
	return if side == "Police" then TeamsConfig.Police else TeamsConfig.Robbers
end

local function ensureTeam(side: Side): Team
	local cfg = sideConfig(side)
	local team = Teams:FindFirstChild(cfg.Name)
	if not (team and team:IsA("Team")) then
		local created = Instance.new("Team")
		created.Name = cfg.Name
		created.TeamColor = cfg.Color
		created.AutoAssignable = false -- a equipe vem da facção, não do Roblox
		created.Parent = Teams
		team = created
	end
	return team :: Team
end

local function factionOf(player: Player): string
	local faction = player:GetAttribute(ATTR.Faction)
	return if typeof(faction) == "string" then faction else CombatContract.DefaultFaction
end

local function isPolice(player: Player): boolean
	return factionOf(player) == TeamsConfig.Police.Faction
end

-- Equipe nativa e lugar de nascer seguem a facção (Civil fica sem equipe)
local function syncTeam(player: Player)
	local faction = factionOf(player)
	if faction == TeamsConfig.Police.Faction then
		player.Team = teams.Police
		player.RespawnLocation = policeSpawn
	elseif faction == TeamsConfig.Robbers.Faction then
		player.Team = teams.Robbers
		player.RespawnLocation = nil
	else
		player.Team = nil
		player.RespawnLocation = nil
	end
end

-- ---------- uniforme provisório (só no personagem; o avatar volta ao sair) ----------
local function weldedPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, anchor: BasePart, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false -- não vira alvo nem bloqueia tiro
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function applyUniform(character: Model)
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not head or not torso or character:FindFirstChild(UNIFORM_FOLDER) then
		return
	end
	local uniform = TeamsConfig.Uniform
	-- roupa e cor do avatar: tira/troca agora e também o que chegar depois
	-- (a aparência do avatar carrega aos poucos e chegaria por cima do uniforme)
	local function enforce(child: Instance)
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			task.defer(child.Destroy, child)
		elseif child:IsA("Accessory") and child.AccessoryType == Enum.AccessoryType.Hat then
			task.defer(child.Destroy, child) -- o quepe entra no lugar do chapéu
		elseif child:IsA("BodyColors") then
			local colors = child
			local function paint()
				if colors.TorsoColor3 ~= uniform.Shirt then
					colors.TorsoColor3 = uniform.Shirt
				end
				if colors.LeftArmColor3 ~= uniform.Shirt then
					colors.LeftArmColor3 = uniform.Shirt
				end
				if colors.RightArmColor3 ~= uniform.Shirt then
					colors.RightArmColor3 = uniform.Shirt
				end
				if colors.LeftLegColor3 ~= uniform.Pants then
					colors.LeftLegColor3 = uniform.Pants
				end
				if colors.RightLegColor3 ~= uniform.Pants then
					colors.RightLegColor3 = uniform.Pants
				end
			end
			paint()
			-- a aparência do avatar repinta depois: volta para o uniforme
			colors.Changed:Connect(function()
				task.defer(paint)
			end)
		end
	end
	for _, child in character:GetChildren() do
		enforce(child)
	end
	if not character:FindFirstChildOfClass("BodyColors") then
		local colors = Instance.new("BodyColors")
		enforce(colors)
		colors.Parent = character
	end
	character.ChildAdded:Connect(enforce)

	-- peças numa pasta (não são filhas diretas do personagem: não entram na hitbox)
	local folder = Instance.new("Folder")
	folder.Name = UNIFORM_FOLDER
	local cap = weldedPart(folder, "Cap", Vector3.new(0.42, 1.3, 1.3), head.CFrame * CFrame.new(0, 0.66, 0) * CFrame.Angles(0, 0, math.rad(90)), uniform.Cap, head, Enum.Material.Fabric)
	cap.Shape = Enum.PartType.Cylinder
	weldedPart(folder, "CapBrim", Vector3.new(1.15, 0.08, 0.55), head.CFrame * CFrame.new(0, 0.5, -0.72), uniform.Cap, head, Enum.Material.Fabric)
	weldedPart(folder, "CapBadge", Vector3.new(0.3, 0.26, 0.06), head.CFrame * CFrame.new(0, 0.7, -0.64), uniform.Badge, head, Enum.Material.Metal)
	weldedPart(folder, "ChestBadge", Vector3.new(0.32, 0.36, 0.06), torso.CFrame * CFrame.new(-0.5, 0.45, -0.52), uniform.Badge, torso, Enum.Material.Metal)
	local back = weldedPart(folder, "BackText", Vector3.new(1.8, 0.5, 0.02), torso.CFrame * CFrame.new(0, 0.45, 0.51), uniform.Shirt, torso)
	back.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.5
	gui.Parent = back
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = uniform.BackText
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = uniform.Badge
	text.Parent = gui
	folder.Parent = character
end

local function protectSpawn(character: Model)
	local shield = Instance.new("ForceField")
	shield.Name = "SpawnProtection"
	shield.Parent = character
	task.delay(TeamsConfig.SpawnProtection, function()
		if shield.Parent then
			shield:Destroy()
		end
	end)
end

local function onCharacter(player: Player, character: Model)
	if not isPolice(player) then
		return
	end
	protectSpawn(character)
	-- cabeça e tronco chegam junto com o personagem; a roupa do avatar que chegar depois
	-- é trocada pelo uniforme na hora (applyUniform fica de olho)
	character:WaitForChild("Torso", 5)
	character:WaitForChild("Head", 5)
	if character.Parent and isPolice(player) then
		applyUniform(character)
	end
end

-- ---------- troca de equipe (encaminha ao FactionService; nunca escreve Faction) ----------
function TeamService.requestSwitch(player: Player, to: Side): boolean
	if busy[player] then
		return false
	end
	if (to == "Police") == isPolice(player) then
		Notice.send(player, "Delegacia", if to == "Police" then REASON_TEXT.already_police else REASON_TEXT.already_civil)
		return false
	end
	busy[player] = true
	local action: CombatContract.FactionAction = if to == "Police" then "JoinPolice" else "GoCivil"
	local ok, why = FactionService.requestAction(player, action, true)
	busy[player] = nil
	if not ok then
		Notice.send(player, "Delegacia", (why and REASON_TEXT[why]) or "Não foi possível trocar de equipe.")
		return false
	end
	return true
end

local function addPrompt(part: BasePart, name: string, action: string, to: Side)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = "Delegacia"
	prompt.HoldDuration = TeamsConfig.RecruitHoldSeconds
	prompt.MaxActivationDistance = TeamsConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom -- desenhado pelo PromptController
	prompt.Parent = part
	prompt.Triggered:Connect(function(player: Player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - part.Position).Magnitude > TeamsConfig.PromptDistance + PROMPT_SLACK then
			return
		end
		TeamService.requestSwitch(player, to)
	end)
end

function TeamService:Init()
	Net.serverEvent(Notice.Remote) -- existe desde o começo (o cliente espera por ele)
	teams.Police = ensureTeam("Police")
	teams.Robbers = ensureTeam("Robbers")
	FactionService.setExternalChecks({
		getWantedStars = WantedService.getStars,
		isRobbing = RobberyService.isRobbing,
		secondsSinceCombat = CombatService.secondsSinceCombat,
		combatLockSeconds = TeamsConfig.CombatLock,
		switchCooldownSeconds = TeamsConfig.SwitchCooldown,
	})
end

function TeamService:Start()
	local station = workspace:FindFirstChild(STATION_NAME)
	if station then
		local spawnPad = station:FindFirstChild("PoliceSpawnPad", true)
		if spawnPad and spawnPad:IsA("SpawnLocation") then
			policeSpawn = spawnPad
			spawnPad.TeamColor = TeamsConfig.Police.Color
			spawnPad.Neutral = false
			spawnPad.AllowTeamChangeOnTouch = false
			spawnPad.Duration = 0 -- a proteção é a deste serviço (some ao atirar)
		end
		local terminal = station:FindFirstChild("RecruitTerminal", true)
		if terminal and terminal:IsA("BasePart") then
			addPrompt(terminal, "JoinPolice", "Entrar para a Polícia", "Police")
		end
		local locker = station:FindFirstChild("LeaveLocker", true)
		if locker and locker:IsA("BasePart") then
			addPrompt(locker, "LeavePolice", "Devolver distintivo", "Robbers")
		end
	else
		warn("[TeamService] workspace.PoliceStation não encontrado: sem recrutamento")
	end

	FactionService.onFactionChanged(function(player: Player, newFaction: string, oldFaction: string, reason: string?)
		if not player.Parent then
			return
		end
		syncTeam(player)
		if newFaction ~= oldFaction and (reason == "join_police" or reason == "end_shift") then
			Notice.send(player, "Delegacia", if newFaction == TeamsConfig.Police.Faction
				then "Você entrou para a Polícia. Bem-vindo à corporação!"
				else "Você devolveu o distintivo e saiu da Polícia.")
			-- personagem novo: armas, uniforme e spawn da equipe nova (nada da anterior sobra)
			player:LoadCharacter()
		end
	end)

	local function onPlayer(player: Player)
		syncTeam(player)
		-- acompanha o Faction definido pelo FactionService no join ou em qualquer transição
		player:GetAttributeChangedSignal(ATTR.Faction):Connect(function()
			syncTeam(player)
		end)
		player.CharacterAdded:Connect(function(character: Model)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
	end)
end

return TeamService
