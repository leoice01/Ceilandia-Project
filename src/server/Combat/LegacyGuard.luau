--!strict
-- Verifica recursivamente se o GunServer legado está ativo para evitar execução dupla.

local ServerScriptService = game:GetService("ServerScriptService")

local LegacyGuard = {}

function LegacyGuard.isLegacyGunServerActive(): boolean
	local legacy = ServerScriptService:FindFirstChild("GunServer", true)
	return legacy ~= nil and legacy:IsA("BaseScript") and legacy.Enabled
end

return LegacyGuard