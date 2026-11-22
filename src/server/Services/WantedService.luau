--!strict
-- Sistema de procurado (referência: Rob Run). Só o servidor decide.
--   * Crimes somam pontos (Shared/Config/Wanted); pontos viram estrelas.
--   * Cada crime tem cooldown por chave (mesma vítima, mesmo lugar...) e teto próprio,
--     para nada inflar as estrelas por engano.
--   * Perseguição: policial com visão do suspeito, ou troca de tiro com a polícia.
--   * Fuga: tempo sem contato e sem polícia por perto, saindo da área de busca.
--   * Depois de escapar e sem crime recente, os pontos caem aos poucos até zerar.
--   * A polícia recebe alertas no momento dos eventos (crime, início da perseguição,
--     contato perdido, fuga) com detalhe conforme as estrelas — nunca a posição ao vivo.
-- Outros sistemas avisam crimes por WantedService.reportCrime (roubos, veículos...).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Lib.Net)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local WantedContract = require(ReplicatedStorage.Shared.Lib.WantedContract)
local WantedConfig = require(ReplicatedStorage.Shared.Config.Wanted)
local Factions = require(script.Parent.Parent.Combat.Factions)

type Status = WantedContract.Status
type Alert = WantedContract.Alert
type AlertKind = WantedContract.AlertKind

local ATTR = WantedContract.Attributes
local FACTIONS = CombatContract.Factions
local POLICE_CRIMES: { [string]: boolean } = { AssaultPolice = true, WoundPolice = true, KillPolice = true }
local SIGHT_HEIGHT = Vector3.new(0, 1.5, 0) -- olho acima do centro do corpo (studs)

type Record = {
	player: Player,
	points: number,
	status: Status,
	phase: "Wanted" | "Escaping" | "Escaped", -- fase sem contato (Suspected/Pursued são por cima)
	identified: boolean,
	lastCrimeAt: number,
	lastContactAt: number,
	contactUntil: number, -- contato garantido depois de troca de tiro com a polícia
	searchCenter: Vector3?,
	escapeProgress: number,
	escapedAt: number,
	lastDecayAt: number,
	policeCrimeTimes: { number },
}

export type CrimeOptions = {
	key: string?, -- separa cooldowns (ex.: id da vítima, nome da loja)
	identified: boolean?, -- já se sabe quem é (ex.: a vítima é policial)
}

local WantedService = {}

local alertRemote: RemoteEvent
local records: { [Player]: Record } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local rng = Random.new()

-- ---------- quem é quem ----------
local function isRobber(player: Player): boolean
	return Factions.of(player) == FACTIONS.Robber
end

local function isPolicePlayer(player: Player): boolean
	return Factions.of(player) == FACTIONS.Police
end

-- Policial (jogador ou unidade de teste/IA com a tag) é a vítima?
local function isPoliceVictim(model: Model, victim: Player?): boolean
	if victim then
		return isPolicePlayer(victim)
	end
	return CollectionService:HasTag(model, WantedConfig.PoliceUnitTag)
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aliveAndActive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and model:GetAttribute(CombatContract.Attributes.Downed) ~= true
end

-- Policiais que podem ver/perseguir agora
local function policeModels(): { Model }
	local list: { Model } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and isPolicePlayer(player) and aliveAndActive(character) then
			table.insert(list, character)
		end
	end
	for _, unit in CollectionService:GetTagged(WantedConfig.PoliceUnitTag) do
		if unit:IsA("Model") and unit:IsDescendantOf(workspace) and aliveAndActive(unit) then
			table.insert(list, unit)
		end
	end
	return list
end

local function canSee(observer: Model, target: Model): boolean
	local from, to = rootOf(observer), rootOf(target)
	if not from or not to then
		return false
	end
	local origin = from.Position + SIGHT_HEIGHT
	local offset = to.Position + SIGHT_HEIGHT - origin
	local ignore: { Instance } = { observer, target }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character) -- gente na frente não esconde o suspeito
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(origin, offset, params) == nil
end

-- Algum policial vê o alvo até range? E algum está a menos de nearRange (com ou sem visão)?
local function policeAround(target: Model, range: number, nearRange: number): (boolean, boolean)
	local root = rootOf(target)
	if not root then
		return false, false
	end
	local seen, near = false, false
	for _, police in policeModels() do
		local policeRoot = rootOf(police)
		if policeRoot then
			local distance = (policeRoot.Position - root.Position).Magnitude
			if distance <= nearRange then
				near = true
			end
			if distance <= range and canSee(police, target) then
				seen = true
				break
			end
		end
	end
	return seen, near
end

local function insideTagged(tag: string, position: Vector3): BasePart?
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") then
			local p = part.CFrame:PointToObjectSpace(position)
			local half = part.Size * 0.5
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return part
			end
		end
	end
	return nil
end

-- ---------- estado ----------
local function starsOf(record: Record): number
	return WantedContract.starsFor(record.points, WantedConfig.StarThresholds)
end

local function publish(record: Record)
	local player = record.player
	local stars = starsOf(record)
	local status: Status = if record.points <= 0 then "NotWanted" else record.status
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set(ATTR.Level, stars)
	set(ATTR.State, WantedContract.Visual[status])
	set(ATTR.Status, status)
	set(ATTR.Points, math.floor(record.points + 0.5))
	set(ATTR.Bounty, WantedConfig.BountyPerStar[stars + 1] or 0)
	set(ATTR.Identified, record.identified and stars > 0)
end

local function newRecord(player: Player): Record
	return {
		player = player,
		points = 0,
		status = "NotWanted",
		phase = "Wanted",
		identified = false,
		lastCrimeAt = -math.huge,
		lastContactAt = -math.huge,
		contactUntil = -math.huge,
		searchCenter = nil,
		escapeProgress = 0,
		escapedAt = -math.huge,
		lastDecayAt = -math.huge,
		policeCrimeTimes = {},
	}
end

local function recordOf(player: Player): Record
	local record = records[player]
	if not record then
		record = newRecord(player)
		records[player] = record
	end
	return record
end

-- ---------- alertas da polícia ----------
local ALERT_LABEL: { [AlertKind]: string } = {
	Crime = "",
	Pursuit = "Perseguição em andamento",
	ContactLost = "Contato visual perdido com o suspeito",
	Escaped = "Suspeito escapou",
	Cleared = "Ocorrência encerrada",
}

local function sendAlert(kind: AlertKind, record: Record, position: Vector3?, crimeId: string?)
	local stars = math.max(starsOf(record), 1)
	local detail = WantedConfig.AlertDetail[math.min(stars, #WantedConfig.AlertDetail)]
	local approximate: Vector3? = nil
	if detail.Location and position then
		-- centro deslocado dentro do raio: área de busca, não posição exata
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, detail.Radius * 0.6)
		approximate = position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	end
	local crime = if crimeId then WantedConfig.Crimes[crimeId] else nil
	local alert: Alert = {
		kind = kind,
		crime = crimeId,
		label = if crime then crime.Label else ALERT_LABEL[kind],
		stars = stars,
		priority = detail.Priority,
		position = approximate,
		radius = detail.Radius,
		suspect = if detail.ShowSuspect and record.identified then record.player.DisplayName else nil,
		suspectActive = kind ~= "Escaped" and kind ~= "Cleared",
	}
	for _, player in Players:GetPlayers() do
		if player ~= record.player and isPolicePlayer(player) then
			alertRemote:FireClient(player, alert)
		end
	end
end

local function clear(record: Record)
	local player = record.player
	local wasWanted = record.points > 0
	records[player] = newRecord(player)
	publish(records[player])
	if wasWanted then
		sendAlert("Cleared", record, nil, nil)
	end
end

-- ---------- crimes ----------
local reportCrime: (Player, string, Vector3, CrimeOptions?) -> boolean

local function startPursuit(record: Record, position: Vector3)
	local was = record.status
	record.status = "Pursued"
	record.lastContactAt = os.clock()
	record.searchCenter = position
	record.escapeProgress = 0
	record.phase = "Wanted"
	record.identified = true
	if was ~= "Pursued" then
		sendAlert("Pursuit", record, position, nil)
	end
end

-- Soma o crime ao procurado. Devolve true se contou (fora de cooldown, jogador ladrão).
reportCrime = function(player: Player, crimeId: string, position: Vector3, options: CrimeOptions?): boolean
	local crime = WantedConfig.Crimes[crimeId]
	if not crime then
		warn(("[WantedService] crime desconhecido %s"):format(crimeId))
		return false
	end
	if not isRobber(player) then
		return false
	end
	local character = player.Character
	if not character or not aliveAndActive(character) then
		return false
	end
	local now = os.clock()
	local key = crimeId .. ":" .. ((options and options.key) or "")
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldowns[player] = playerCooldowns
	end
	local last = playerCooldowns[key]
	if last and now - last < crime.Cooldown then
		return false -- mesma ação repetida: não soma de novo
	end
	playerCooldowns[key] = now

	local record = recordOf(player)
	local add = crime.Points
	local cap = crime.MaxPoints
	if cap then
		add = math.clamp(cap - record.points, 0, crime.Points)
	end
	record.points = math.min(record.points + add, WantedConfig.MaxPoints)
	record.lastCrimeAt = now
	record.searchCenter = position
	record.escapeProgress = 0
	if record.phase == "Escaped" then
		record.phase = "Wanted"
	end
	if record.status == "NotWanted" or record.status == "Escaped" then
		record.status = "Wanted"
	end

	-- testemunha policial: identificado e perseguição começa na hora
	local witnessed = false
	if options and options.identified then
		record.identified = true
		witnessed = true
	else
		witnessed = policeAround(character, WantedConfig.WitnessRange, 0)
		if witnessed then
			record.identified = true
		end
	end

	if crime.Alert then
		sendAlert("Crime", record, position, crimeId)
	end
	if witnessed then
		startPursuit(record, position)
		if crimeId ~= "CaughtInAct" then
			reportCrime(player, "CaughtInAct", position, nil)
		end
	end

	-- vários crimes contra a polícia em pouco tempo = confronto grande
	if POLICE_CRIMES[crimeId] then
		local times = record.policeCrimeTimes
		table.insert(times, now)
		while times[1] and now - times[1] > WantedConfig.ShootoutWindow do
			table.remove(times, 1)
		end
		if #times >= WantedConfig.ShootoutPoliceCrimes then
			table.clear(times)
			reportCrime(player, "MajorShootout", position, nil)
		end
	end

	publish(record)
	return true
end

-- ---------- perseguição, fuga e redução ----------
local function escapeTime(stars: number): number
	return WantedConfig.EscapeTimeBase + math.max(stars - 1, 0) * WantedConfig.EscapeTimePerStar
end

local function searchRadius(stars: number): number
	return WantedConfig.SearchRadiusBase + math.max(stars - 1, 0) * WantedConfig.SearchRadiusPerStar
end

local function step(record: Record, dt: number, now: number)
	local player = record.player
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return
	end
	local stars = starsOf(record)
	local seen, near = policeAround(character, WantedConfig.PursuitRange, WantedConfig.SuspectRange)

	if seen or now < record.contactUntil then
		startPursuit(record, root.Position)
	elseif record.status == "Pursued" and now - record.lastContactAt < WantedConfig.ContactLostTime then
		-- acabou de sair da vista: ainda é perseguição
	else
		if record.status == "Pursued" then
			record.phase = "Escaping"
			sendAlert("ContactLost", record, record.searchCenter, nil)
		end
		if record.phase ~= "Escaped" then
			-- fuga só anda sem polícia por perto; dentro da área de busca anda mais devagar
			if not near then
				local center = record.searchCenter
				local inside = center ~= nil and (root.Position - center).Magnitude < searchRadius(stars)
				local rate = if inside then 1 / WantedConfig.InsideAreaEscapeMultiplier else 1
				record.escapeProgress += dt * rate
			end
			if record.escapeProgress >= escapeTime(stars) then
				record.phase = "Escaped"
				record.escapedAt = now
				record.lastDecayAt = now
				record.identified = false
				record.searchCenter = nil
				sendAlert("Escaped", record, nil, nil)
			end
		end
		record.status = if near and record.phase ~= "Escaped" then "Suspected" else record.phase
	end

	-- redução gradual: só escapado e sem crime recente
	if record.phase == "Escaped" and record.status == "Escaped" then
		local quietSince = math.max(record.escapedAt, record.lastCrimeAt)
		if now - quietSince >= WantedConfig.DecayDelay and now - record.lastDecayAt >= WantedConfig.DecayInterval then
			record.lastDecayAt = now
			record.points = math.max(0, record.points - WantedConfig.DecayPoints)
			if record.points <= 0 then
				clear(record)
				return
			end
		end
	end
	publish(record)
end

-- Invasão de área restrita: confere ladrões dentro de partes com a tag
local function checkTrespass()
	if #CollectionService:GetTagged(WantedConfig.RestrictedTag) == 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player.Character)
		if root and isRobber(player) then
			local area = insideTagged(WantedConfig.RestrictedTag, root.Position)
			if area then
				reportCrime(player, "Trespass", root.Position, { key = area:GetFullName() })
			end
		end
	end
end

-- ---------- API para outros sistemas ----------
WantedService.reportCrime = reportCrime

function WantedService.getStars(player: Player): number
	local record = records[player]
	return if record then starsOf(record) else 0
end

function WantedService.getStatus(player: Player): Status
	local record = records[player]
	return if record and record.points > 0 then record.status else "NotWanted"
end

-- Preso ou morto: zera
function WantedService.clear(player: Player)
	local record = records[player]
	if record then
		clear(record)
	end
end

-- CombatService: tiro aceito
function WantedService.onShotFired(player: Player, origin: Vector3)
	if insideTagged(WantedConfig.SafeZoneTag, origin) then
		return
	end
	reportCrime(player, "PublicGunfire", origin, nil)
end

-- CombatService: acerto aplicado (tiro ou explosão)
function WantedService.onHit(attacker: Player, model: Model, victim: Player?, healthDamage: number, result: string, position: Vector3)
	if isPoliceVictim(model, victim) then
		local key = if victim then tostring(victim.UserId) else model:GetFullName()
		local options: CrimeOptions = { key = key, identified = true }
		reportCrime(attacker, "AssaultPolice", position, options)
		if healthDamage > 0 then
			reportCrime(attacker, "WoundPolice", position, options)
		end
		if result == "Downed" or result == "Killed" then
			reportCrime(attacker, "KillPolice", position, options)
		end
		return
	end
	-- policial atirando num procurado: troca de tiro = perseguição
	if victim and isPolicePlayer(attacker) then
		local record = records[victim]
		if record and record.points > 0 then
			record.contactUntil = os.clock() + WantedConfig.ConfrontationContact
		end
	end
end

-- DownedService: finalizou alguém derrubado segurando o botão
function WantedService.onFinished(attacker: Player, model: Model, victim: Player?)
	if isPoliceVictim(model, victim) then
		local root = rootOf(model)
		local key = if victim then tostring(victim.UserId) else model:GetFullName()
		reportCrime(attacker, "KillPolice", if root then root.Position else Vector3.zero, { key = key, identified = true })
	end
end

-- GrenadeService: explosão
function WantedService.onExplosion(player: Player, position: Vector3)
	reportCrime(player, "Explosion", position, nil)
end

function WantedService:Init()
	alertRemote = Net.serverEvent(WantedContract.Remotes.Alert)
end

function WantedService:Start()
	local function onPlayer(player: Player)
		publish(recordOf(player))
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid and WantedConfig.ClearOnDeath then
				humanoid.Died:Connect(function()
					WantedService.clear(player)
				end)
			end
		end)
		-- trocou de lado (virou policial/civil): o procurado de ladrão não vale mais
		player:GetAttributeChangedSignal(CombatContract.Attributes.Faction):Connect(function()
			if not isRobber(player) then
				WantedService.clear(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		records[player] = nil
		cooldowns[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < WantedConfig.TickInterval then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		debug.profilebegin("Wanted_Tick")
		local now = os.clock()
		checkTrespass()
		for _, record in records do
			if record.points > 0 then
				step(record, elapsed, now)
			end
		end
		debug.profileend()
	end)
end

return WantedService
