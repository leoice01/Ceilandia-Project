--!strict
-- Contrato do sistema de procurado entre servidor (WantedService) e cliente.
-- O servidor é o único que escreve os atributos; o cliente só mostra.
--
-- Atributos no Player (escritos pelo servidor):
--   WantedLevel (number 0–5)   estrelas; o HUD existente (HudController) desenha
--   WantedState (string)       aparência das estrelas no HUD:
--       "white" procurado | "hollow" polícia na área | "red" perseguido |
--       "flash" fugindo | "gray" escapou, estrelas caindo
--   WantedStatus (string)      estado lógico (WantedStatus abaixo)
--   WantedPoints (number)      pontos acumulados
--   WantedBounty (number)      valor pela cabeça (informativo até existir economia)
--   CameraSeen (boolean)       badge do HUD: suspeito identificado pela polícia
--
-- Servidor -> cliente (só policiais):
--   WantedAlert(alert: Alert)

export type Status = "NotWanted" | "Wanted" | "Suspected" | "Pursued" | "Escaping" | "Escaped"

export type AlertKind = "Crime" | "Pursuit" | "ContactLost" | "Escaped" | "Cleared"

export type Alert = {
	kind: AlertKind,
	crime: string?, -- id do crime (Crime)
	label: string, -- texto pronto para mostrar
	stars: number, -- gravidade
	priority: string,
	position: Vector3?, -- centro aproximado (já com imprecisão); nil = sem localização
	radius: number, -- tamanho da área (studs)
	suspect: string?, -- nome do suspeito quando identificado e o nível permite
	suspectActive: boolean, -- false = suspeito escapou/saiu
}

local WantedContract = {
	Remotes = {
		Alert = "WantedAlert",
	},
	Attributes = {
		Level = "WantedLevel",
		State = "WantedState",
		Status = "WantedStatus",
		Points = "WantedPoints",
		Bounty = "WantedBounty",
		Identified = "CameraSeen",
	},
	-- estado lógico -> aparência das estrelas no HUD existente
	Visual = {
		NotWanted = "white",
		Wanted = "white",
		Suspected = "hollow",
		Pursued = "red",
		Escaping = "flash",
		Escaped = "gray",
	} :: { [Status]: string },
}

-- Pontos -> estrelas (thresholds[n] = pontos mínimos da estrela n)
function WantedContract.starsFor(points: number, thresholds: { number }): number
	local stars = 0
	for i, minimum in thresholds do
		if points >= minimum then
			stars = i
		end
	end
	return stars
end

return WantedContract
