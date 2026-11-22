--!strict
-- Aviso curto do servidor para um jogador ("Você entrou para a Polícia", "Roubo
-- interrompido"...). Só servidor -> cliente; o cliente mostra com a notificação padrão
-- do Roblox (NoticeController). Nenhum dado do cliente é aceito por aqui.

local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)

local REMOTE = "Notice"

local Notice = {}

Notice.Remote = REMOTE

-- Servidor: manda o aviso
function Notice.send(player: Player, title: string, text: string)
	assert(RunService:IsServer(), "Notice.send só no servidor")
	Net.serverEvent(REMOTE):FireClient(player, title, text)
end

return Notice
