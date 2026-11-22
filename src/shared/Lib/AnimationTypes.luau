--!strict
-- Estados de animação do personagem e regras de quais combinações são válidas.
-- A locomoção (pernas/tronco) tem um estado só por vez; ações da arma vêm em camadas
-- por cima e consultam estas regras antes de entrar.

export type LocomotionState =
	"Idle"
	| "IdleCombat"
	| "Walking"
	| "Running"
	| "Sprinting"
	| "Crouching"
	| "CrouchWalking"
	| "Airborne"
	| "Sitting"
	| "Sliding" -- ainda no PoseAnimator legado (Prioridade 4)
	| "Downed" -- ainda no PoseAnimator legado
	| "Dead"

export type ActionState = "None" | "HipFire" | "ADS" | "Shooting" | "Reloading" | "WeaponSwitching" | "TakingDamage"

local AnimationTypes = {}

-- Estados de locomoção em que o corpo é controlado por outro sistema (sem tracks de locomoção)
AnimationTypes.ProceduralBody = {
	Sliding = true,
	Downed = true,
	Dead = true,
} :: { [string]: boolean }

-- Ações proibidas em cada estado de locomoção
local BLOCKED: { [string]: { [string]: boolean } } = {
	Sprinting = { ADS = true, Shooting = true, Reloading = true },
	Downed = { HipFire = true, ADS = true, Shooting = true, Reloading = true, WeaponSwitching = true },
	Dead = { HipFire = true, ADS = true, Shooting = true, Reloading = true, WeaponSwitching = true, TakingDamage = true },
	Airborne = { ADS = true },
}

-- Ações que não podem acontecer juntas
local EXCLUSIVE: { [string]: { [string]: boolean } } = {
	WeaponSwitching = { ADS = true, Shooting = true, Reloading = true },
	Reloading = { Shooting = true },
}

function AnimationTypes.canDoAction(locomotion: LocomotionState, current: ActionState, wanted: ActionState): boolean
	local blocked = BLOCKED[locomotion]
	if blocked and blocked[wanted] then
		return false
	end
	local exclusive = EXCLUSIVE[current]
	if exclusive and exclusive[wanted] then
		return false
	end
	return true
end

return AnimationTypes
