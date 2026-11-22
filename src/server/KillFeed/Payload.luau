--!strict

export type PlayerSnapshot = {
	displayName: string,
	username: string,
	userId: number,
	team: string,
}

export type KillPosition = {
	x: number,
	y: number,
	z: number,
}

export type KillEntry = {
	victim: PlayerSnapshot,
	killer: PlayerSnapshot?,
	killerLabel: string,
	weapon: string?,
	distance: number?,
	headshot: boolean?,
	time: number,
	zone: string,
	position: KillPosition,
	jobId: string,
	placeId: number,
}

export type PlayerLike = {
	DisplayName: string,
	Name: string,
	UserId: number,
	Team: Team?,
	GetAttribute: (self: any, name: string) -> any,
}

export type BuildParams = {
	victim: PlayerLike,
	killer: PlayerLike?,
	weaponName: string?,
	cause: string,
	distance: number?,
	headshot: boolean?,
	zone: string?,
	position: Vector3?,
	time: number?,
	jobId: string?,
	placeId: number?,
}

local MAX_NAME_LEN = 64
local MAX_LABEL_LEN = 64
local MAX_WEAPON_LEN = 48
local MAX_ZONE_LEN = 48

local Payload = {}

local function clampString(value: string, maxLen: number): string
	if #value <= maxLen then
		return value
	end
	return string.sub(value, 1, maxLen)
end

local function resolveTeam(player: PlayerLike): string
	local faction = player:GetAttribute("Faction")
	if typeof(faction) == "string" and faction ~= "" then
		if faction == "Bandido" then
			return "Ladrão"
		elseif faction == "Policia" then
			return "Polícia"
		end
		return clampString(faction, MAX_NAME_LEN)
	end
	if player.Team then
		return clampString(player.Team.Name, MAX_NAME_LEN)
	end
	return "Sem time"
end

local function snapshotPlayer(player: PlayerLike): PlayerSnapshot
	return {
		displayName = clampString(player.DisplayName, MAX_NAME_LEN),
		username = clampString(player.Name, MAX_NAME_LEN),
		userId = player.UserId,
		team = resolveTeam(player),
	}
end

local function resolveKillerLabel(victim: PlayerLike, killer: PlayerLike?, cause: string): string
	if killer == nil then
		if cause == "fall" then
			return "Queda"
		end
		return "Ambiente"
	end
	if killer.UserId == victim.UserId then
		return "Suicídio"
	end
	return clampString(killer.DisplayName, MAX_LABEL_LEN)
end

local function round1(value: number): number
	return math.round(value * 10) / 10
end

local function roundPosition(pos: Vector3?): KillPosition
	if not pos then
		return { x = 0, y = 0, z = 0 }
	end
	return {
		x = math.round(pos.X),
		y = math.round(pos.Y),
		z = math.round(pos.Z),
	}
end

local function formatJobId(rawJobId: string?): string
	local id = rawJobId or game.JobId
	if id == "" then
		return "studio"
	end
	return string.sub(id, 1, 8)
end

function Payload.build(params: BuildParams): KillEntry
	local victimSnap = snapshotPlayer(params.victim)
	local killerSnap = if params.killer then snapshotPlayer(params.killer) else nil
	local weapon: string? = if params.weaponName and params.weaponName ~= ""
		then clampString(params.weaponName, MAX_WEAPON_LEN)
		else nil
	local distance: number? = if params.distance ~= nil then round1(params.distance) else nil

	return {
		victim = victimSnap,
		killer = killerSnap,
		killerLabel = resolveKillerLabel(params.victim, params.killer, params.cause),
		weapon = weapon,
		distance = distance,
		headshot = params.headshot,
		time = params.time or os.time(),
		zone = clampString(params.zone or "Rua", MAX_ZONE_LEN),
		position = roundPosition(params.position),
		jobId = formatJobId(params.jobId),
		placeId = params.placeId or game.PlaceId,
	}
end

return Payload