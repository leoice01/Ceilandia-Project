--!strict
-- DESATIVADA: nenhum cliente/Tool ativo usa ReplicatedStorage.Remotes.GunFire
-- (GunClient e GunServer estão desativados; o cliente novo usa CombatFire via WeaponController).
-- Mantida como módulo inativo para não quebrar o loader de Services.

local LegacyGunBridge = {}

function LegacyGunBridge:Start()
	return
end

return LegacyGunBridge
