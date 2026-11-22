--!strict
-- Registro de ocorrências policiais (só servidor). Cada crime com alerta abre uma ocorrência;
-- o WantedService atualiza o estado conforme a perseguição e manda para os policiais.
--   Reported  crime comunicado, suspeito não identificado
--   Active    suspeito identificado, ainda à solta (sem contato agora)
--   Pursuit   polícia em contato com o suspeito
--   Escaped   suspeito despistou a polícia (ocorrência fechada)
--   Resolved  suspeito morto/preso ou procurado zerado (ocorrência fechada)
-- Roubos de loja, banco, veículo, disparos e ataques à polícia já passam por aqui através
-- do WantedService.reportCrime; não precisa de código novo por tipo de crime.

export type State = "Reported" | "Active" | "Pursuit" | "Resolved" | "Escaped"

export type Incident = {
	id: number,
	crime: string,
	label: string,
	suspect: Player,
	identified: boolean,
	position: Vector3, -- local exato (só servidor)
	approx: Vector3?, -- local que a polícia recebe (impreciso conforme a gravidade)
	radius: number,
	threat: number, -- estrelas na hora do crime (atualiza se subir)
	priority: string,
	state: State,
	time: number, -- os.time() do crime
}

export type OpenParams = {
	crime: string,
	label: string,
	suspect: Player,
	identified: boolean,
	position: Vector3,
	approx: Vector3?,
	radius: number,
	threat: number,
	priority: string,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WantedConfig = require(ReplicatedStorage.Shared.Config.Wanted)

local MAX_HISTORY = 50
local CLOSED: { [State]: boolean } = { Resolved = true, Escaped = true }
local DEBUG = RunService:IsStudio() and WantedConfig.DebugIncidents == true

local IncidentService = {}

local function log(incident: Incident, event: string)
	if DEBUG then
		print(("[Ocorrência #%d] %s | %s | suspeito=%s%s | %d★ | estado=%s | local=%s"):format(
			incident.id, event, incident.label, incident.suspect.Name,
			if incident.identified then " (identificado)" else "", incident.threat, incident.state,
			tostring(incident.position)))
	end
end

local nextId = 0
local open: { Incident } = {}
local history: { Incident } = {}

local function close(incident: Incident)
	local index = table.find(open, incident)
	if index then
		table.remove(open, index)
	end
	table.insert(history, 1, incident)
	if #history > MAX_HISTORY then
		table.remove(history)
	end
end

function IncidentService.open(params: OpenParams): Incident
	nextId += 1
	local incident: Incident = {
		id = nextId,
		crime = params.crime,
		label = params.label,
		suspect = params.suspect,
		identified = params.identified,
		position = params.position,
		approx = params.approx,
		radius = params.radius,
		threat = params.threat,
		priority = params.priority,
		state = if params.identified then "Active" else "Reported",
		time = os.time(),
	}
	table.insert(open, incident)
	log(incident, "aberta")
	return incident
end

-- Atualiza todas as ocorrências abertas do suspeito. Estados finais fecham a ocorrência.
-- Devolve a mais recente (para o alerta).
function IncidentService.setSuspectState(suspect: Player, state: State, threat: number?, identified: boolean?): Incident?
	local latest: Incident? = nil
	for i = #open, 1, -1 do
		local incident = open[i]
		if incident.suspect == suspect then
			incident.state = state
			if threat then
				incident.threat = math.max(incident.threat, threat)
			end
			if identified then
				incident.identified = true
			end
			if not latest then
				latest = incident
			end
			log(incident, "atualizada")
			if CLOSED[state] then
				close(incident)
			end
		end
	end
	return latest
end

function IncidentService.latestOpen(suspect: Player): Incident?
	for i = #open, 1, -1 do
		if open[i].suspect == suspect then
			return open[i]
		end
	end
	return nil
end

function IncidentService.openIncidents(): { Incident }
	return table.clone(open)
end

function IncidentService.recent(): { Incident }
	return table.clone(history)
end

return IncidentService
