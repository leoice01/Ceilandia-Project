--!strict
-- Animações de locomoção (R6). PROVISÓRIO: a P4 ajusta.
-- Os clipes em si (poses) ficam em AnimationClips.luau.

return {
	-- Velocidades (studs/s) que separam os estados de locomoção
	MovingSpeed = 0.6, -- abaixo disso está parado
	RunSpeed = 12, -- a partir daqui troca andar por correr
	SprintSpeed = 20, -- a partir daqui é sprint (ou atributo Sprinting do movimento)

	-- Tempo de transição entre clipes (s)
	DefaultFade = 0.2,
	Fades = {
		Crouching = 0.25,
		CrouchWalking = 0.25,
		Sprinting = 0.15,
		Airborne = 0.12,
	} :: { [string]: number },

	-- Limites para acelerar/desacelerar o clipe conforme a velocidade real
	MinPlaybackSpeed = 0.5,
	MaxPlaybackSpeed = 1.6,

	-- IDs publicados no Roblox (rbxassetid). Vazio = no Studio usa ID temporário gerado
	-- a partir de AnimationClips; o jogo publicado precisa destes IDs.
	PublishedIds = {} :: { [string]: string },
}
