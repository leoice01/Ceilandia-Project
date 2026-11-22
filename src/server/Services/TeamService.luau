--!strict
-- Polícia x Ladrões na delegacia provisória (workspace.PoliceStation).
-- Quem decide a facção (atributo Faction: Civil / Bandido / Policia) é o FactionService;
-- este serviço só acrescenta o que ele não tem e nunca escreve a facção por conta própria
-- (exceto no fallback sem FactionService e na volta a Bandido da Fase 0, ver leave()):
--   * Teams nativos do Roblox sincronizados com a facção (nome/cor de equipe)
--   * botões físicos da delegacia: terminal "Entrar para a Polícia" e armário
--     "Devolver distintivo", que pedem a troca ao FactionService
--   * regras extras da delegacia: sem procurado, sem combate recente, sem roubo em
--     andamento, intervalo entre trocas
--   * policial nasce na delegacia, com uniforme provisório e proteção de spawn
-- A troca recria o personagem: armas e uniforme da equipe nova, nada da anterior.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Net = require(ReplicatedStorage.Shared.Lib.Net)
local Notice = require(ReplicatedStorage.Shared.Lib.Notice)
local TeamsConfig = require(ReplicatedStorage.Shared.Config.Teams)
local CombatService = require(script.Parent.CombatService)
local WantedService = require(script.Parent.WantedService)
local RobberyService = require(script.Parent.RobberyService)

type Side = "Police" | "Robbers"

local ATTR = CombatContract.Attributes
local FACTIONS = CombatContract.Factions
local STATION_NAME = "PoliceStation"
local PROMPT_SLACK = 3 -- folga de distância para a rede (studs)
local UNIFORM_FOLDER = "PoliceUniform"
local IN_COMBAT_UNTIL = "InCombatUntil" -- atributo do FactionService (hora do servidor)

-- Motivos do FactionService -> texto para o jogador
local REASON_TEXT: { [string]: string } = {
	police_full = "A Polícia está cheia agora. Tente de novo em instantes.",
	switch_cooldown = "Você trocou de lado há pouco. Espere um pouco.",
	in_combat = "Você está em combate. Espere um pouco.",
	in_transition = "Termine o que está fazendo antes.",
	wanted = "Você está procurado. Despiste a polícia antes.",
	dirty_cash = "Você está com dinheiro sujo. Lave antes.",
	stolen_items = "Você está com itens roubados. Venda antes.",
	not_at_station = "Vá até a delegacia.",
	downed = "Agora não dá.",
	dead = "Só dá para trocar de equipe vivo.",
}

-- FactionService e regras de facção (de outra pessoa da equipe; pode não existir numa
-- cópia antiga do projeto: aí este serviço usa o próprio fallback)
local function optional(parent: Instance, name: string): any
	local module = parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then (require :: any)(module) else nil
end
local Combat = script.Parent.Parent.Combat
local FactionService = optional(script.Parent, "FactionService")
local PoliceStations = optional(Combat, "PoliceStations")
local FactionRules = optional(Combat, "FactionRules")
local FactionsConfig = optional(ReplicatedStorage.Shared.Config, "Factions")

local TeamService = {}

local teams: { [Side]: Team } = {}
local lastSwitch: { [Player]: number } = {}
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

-- ---------- troca de equipe ----------
-- Regras da delegacia que vêm antes das do FactionService
local function canSwitch(player: Player, to: Side): (boolean, string?)
	if (to == "Police") == isPolice(player) then
		return false, if to == "Police" then "Você já é policial." else "Você já está fora da Polícia."
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, REASON_TEXT.dead
	end
	if character:GetAttribute(ATTR.Downed) == true or character:GetAttribute(ATTR.Plating) == true then
		return false, REASON_TEXT.downed
	end
	if WantedService.getStars(player) > 0 then
		return false, "Você está procurado. Despiste a polícia antes de se alistar."
	end
	local sinceCombat = CombatService.secondsSinceCombat(player)
	if sinceCombat < TeamsConfig.CombatLock then
		return false, ("Você está em combate. Espere %d s."):format(math.ceil(TeamsConfig.CombatLock - sinceCombat))
	end
	local combatUntil = player:GetAttribute(IN_COMBAT_UNTIL)
	if typeof(combatUntil) == "number" and combatUntil > workspace:GetServerTimeNow() then
		return false, ("Você está em combate. Espere %d s."):format(math.ceil(combatUntil - workspace:GetServerTimeNow()))
	end
	if RobberyService.isRobbing(player) then
		return false, "Termine ou abandone o roubo antes."
	end
	local last = lastSwitch[player]
	if last and os.clock() - last < TeamsConfig.SwitchCooldown then
		return false, ("Espere %d s para trocar de novo."):format(math.ceil(TeamsConfig.SwitchCooldown - (os.clock() - last)))
	end
	if to == "Police" and PoliceStations and FactionRules then
		local police, total = PoliceStations.countFactions()
		if police >= FactionRules.maxPoliceSlots(total) then
			return false, REASON_TEXT.police_full
		end
	end
	return true, nil
end

-- Ladrão (ou civil) -> Polícia pelo FactionService. Na Fase 0 todo mundo é Bandido e o
-- FactionService só aceita Civil -> Polícia: a delegacia faz o "entregar a máscara" na hora
-- (forceCivil) e pede o alistamento; se ele recusar, volta para a facção de antes.
local function join(player: Player): (boolean, string?)
	if not FactionService then
		player:SetAttribute(ATTR.Faction, TeamsConfig.Police.Faction) -- fallback sem FactionService
		return true, nil
	end
	local before = factionOf(player)
	if before ~= FACTIONS.Civil then
		FactionService.forceCivil(player, "police_recruit")
	end
	local ok, reason = FactionService.requestAction(player, "JoinPolice", true)
	if not ok and factionOf(player) ~= before then
		player:SetAttribute(ATTR.Faction, before)
	end
	return ok, reason
end

-- Polícia -> Ladrão. FactionService: fim de plantão na delegacia (vira Civil na hora).
-- Fase 0 (Phase0AutoBandit): não existe civil jogável, então volta a Bandido — o mesmo que
-- o FactionService faz quando reseta a facção na morte.
local function leave(player: Player): (boolean, string?)
	if not FactionService then
		player:SetAttribute(ATTR.Faction, TeamsConfig.Robbers.Faction) -- fallback sem FactionService
		return true, nil
	end
	local ok, reason = FactionService.requestAction(player, "GoCivil", true)
	if not ok then
		return false, reason
	end
	if FactionsConfig and FactionsConfig.Phase0AutoBandit and factionOf(player) == FACTIONS.Civil then
		player:SetAttribute(ATTR.Faction, TeamsConfig.Robbers.Faction)
	end
	return true, nil
end

function TeamService.requestSwitch(player: Player, to: Side): boolean
	if busy[player] then
		return false
	end
	local ok, reason = canSwitch(player, to)
	if not ok then
		Notice.send(player, "Delegacia", reason or "Não foi possível trocar de equipe.")
		return false
	end
	busy[player] = true
	local switched, why = if to == "Police" then join(player) else leave(player)
	busy[player] = nil
	if not switched then
		Notice.send(player, "Delegacia", (why and REASON_TEXT[why]) or "Não foi possível trocar de equipe.")
		return false
	end
	lastSwitch[player] = os.clock()
	syncTeam(player)
	Notice.send(player, "Delegacia", if to == "Police"
		then "Você entrou para a Polícia. Bem-vindo à corporação!"
		else "Você devolveu o distintivo e saiu da Polícia.")
	-- personagem novo: armas, uniforme e spawn da equipe nova (nada da anterior sobra)
	player:LoadCharacter()
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

	local function onPlayer(player: Player)
		if not FactionService and player:GetAttribute(ATTR.Faction) == nil then
			player:SetAttribute(ATTR.Faction, CombatContract.DefaultFaction) -- fallback
		end
		syncTeam(player)
		-- qualquer mudança de facção (delegacia, máscara, morte...) acerta equipe e spawn
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
		lastSwitch[player] = nil
		busy[player] = nil
	end)
end

return TeamService
