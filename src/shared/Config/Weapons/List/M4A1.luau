--!strict
-- Fuzil de assalto. PROVISÓRIO: a P4 ajusta.
-- Base = "RC 5.56" do Rob Run (Mk1, build 0.7, wikis de fãs robrungg.wiki e wikily.gg, nov/2026):
-- 16 corpo / 24 cabeça, 660 RPM, pente 30, recarga 2,3 s, dano cheio até 55 m, alcance 150 m
-- (1 m = 3,57 studs). Membros 0,85x vem do documento de combate do usuário.
return {
	WeaponId = "M4A1",
	DisplayName = "M4A1",
	WeaponType = "AssaultRifle",
	Damage = 16,
	RPM = 660,
	MagazineSize = 30,
	ReserveAmmo = 120,
	ReloadTime = 2.3,
	Range = 535,
	FalloffStart = 196,
	FalloffEnd = 535,
}
