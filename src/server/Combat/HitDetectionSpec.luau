--!strict
-- Testes unitários puros de HitDetection, LagCompensation, Damage e CombatContract.validateFire.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.Combat)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)
local CombatContract = require(ReplicatedStorage.Shared.Lib.CombatContract)
local Damage = require(script.Parent.Damage)
local HitDetection = require(script.Parent.HitDetection)
local LagCompensation = require(script.Parent.LagCompensation)

local HitDetectionSpec = {}

local function approx(a: number, b: number): boolean
	return math.abs(a - b) < 1e-4
end

local function makeBoxPart(name: string, pos: Vector3, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.Size = size
	part.CFrame = CFrame.new(pos)
	part.Parent = parent
	return part
end

local function makeDummy(name: string, rootPos: Vector3, health: number, parent: Instance): (Model, Humanoid, Part, Part)
	local model = Instance.new("Model")
	model.Name = name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = health
	hum.Parent = model
	local root = makeBoxPart("HumanoidRootPart", rootPos, Vector3.new(2, 2, 1), model)
	local head = makeBoxPart("Head", rootPos + Vector3.new(0, 2, 0), Vector3.new(1.2, 1.2, 1.2), model)
	model.PrimaryPart = root
	model.Parent = parent
	return model, hum, root, head
end

function HitDetectionSpec.run(): (number, number, { string })
	local passed = 0
	local failed = 0
	local failures: { string } = {}

	local function check(name: string, condition: boolean, detail: string?)
		if condition then
			passed += 1
		else
			failed += 1
			table.insert(failures, name .. (if detail then (": " .. detail) else ""))
		end
	end

	local sandbox = Instance.new("Folder")
	sandbox.Name = "_HitDetectionSpecSandbox"
	sandbox.Parent = workspace
	local base = Vector3.new(0, 4000, 0)

	local runOk, runErr = pcall(function()
		-- 1) I1: blocked_origin (root -> head atravessando parede) e tolerância de origem
		local tol = CombatConfig.OriginTolerance
		check("origin_tolerance_positive", tol > 0)

		local shooter, _, _, head = makeDummy("Shooter", base, 100, sandbox)
		local worldParams = HitDetection.buildWorldParams({ shooter })

		local ok, reason = HitDetection.validateOrigin(shooter, head.Position, worldParams)
		check("origin_clear_head_ok", ok == true and reason == nil)

		ok, reason = HitDetection.validateOrigin(shooter, head.Position + Vector3.new(math.max(0.1, tol - 0.25), 0, 0), worldParams)
		check("origin_within_tolerance_ok", ok == true and reason == nil)

		ok, reason = HitDetection.validateOrigin(shooter, head.Position + Vector3.new(tol + 0.25, 0, 0), worldParams)
		check("origin_beyond_tolerance_rejected", ok == false and reason == "origin_far", tostring(reason))

		-- Parede fina entre root (y=4000) e head (y=4002)
		local headWall = makeBoxPart("HeadWall", base + Vector3.new(0, 1, 0), Vector3.new(4, 0.5, 4), sandbox)
		ok, reason = HitDetection.validateOrigin(shooter, head.Position, worldParams)
		check("blocked_origin_root_to_head_wall", ok == false and reason == "blocked_origin", tostring(reason))
		headWall:Destroy()

		-- Parede entre head e origem deslocada dentro da tolerância (head -> origin)
		local sideWall = makeBoxPart("SideWall", head.Position + Vector3.new(0.75, 0, 0), Vector3.new(0.4, 3, 3), sandbox)
		ok, reason = HitDetection.validateOrigin(shooter, head.Position + Vector3.new(1.5, 0, 0), worldParams)
		check("origin_through_wall_rejected", ok == false and reason == "origin_through_wall", tostring(reason))
		sideWall:Destroy()

		-- 2) I2: broadphase (raio 6 studs)
		check("broadphase_radius_is_6", approx(CombatConfig.BroadphaseRadius, 6))
		local origin = Vector3.new(0, 0, 0)
		local dir = Vector3.new(0, 0, -1)
		check("broadphase_inside_hit", HitDetection.isWithinBroadphase(Vector3.new(3, 0, -50), origin, dir, 100, 6) == true)
		check("broadphase_on_edge_hit", HitDetection.isWithinBroadphase(Vector3.new(6, 0, -50), origin, dir, 100, 6) == true)
		check("broadphase_outside_ignored", HitDetection.isWithinBroadphase(Vector3.new(6.5, 0, -50), origin, dir, 100, 6) == false)
		check("broadphase_behind_origin_ignored", HitDetection.isWithinBroadphase(Vector3.new(0, 0, 7), origin, dir, 100, 6) == false)
		check("broadphase_past_max_dist_ignored", HitDetection.isWithinBroadphase(Vector3.new(0, 0, -107), origin, dir, 100, 6) == false)

		-- 3) I2: morto ignorado (cadáver na frente não bloqueia vivo atrás) e Accessory/Handle ignorado
		local rayOrigin = base + Vector3.new(20, 2, 0)
		local deadDummy = makeDummy("DeadFront", base + Vector3.new(20, 0, -10), 0, sandbox)
		local aliveDummy, _, _, aliveHead = makeDummy("AliveBack", base + Vector3.new(20, 0, -20), 100, sandbox)
		local hitRes, hitModel, hitPart = HitDetection.raycastWorldAlive(rayOrigin, Vector3.new(0, 0, -40), { shooter })
		check(
			"dead_npc_ignored_hits_alive_behind",
			hitRes ~= nil and hitModel == aliveDummy and hitPart == aliveHead,
			if hitModel then hitModel.Name else "nil"
		)

		local acc = Instance.new("Accessory")
		acc.Name = "BigHat"
		local handle = makeBoxPart("Handle", aliveHead.Position + Vector3.new(0, 0, 1.5), Vector3.new(3, 3, 0.5), acc)
		handle.CanQuery = true
		acc.Parent = aliveDummy
		local accHit, accModel, accPart = HitDetection.raycastWorldAlive(rayOrigin, Vector3.new(0, 0, -40), { shooter })
		check(
			"npc_accessory_ignored_hits_head",
			accHit ~= nil and accModel == aliveDummy and accPart == aliveHead,
			if accPart then accPart.Name else "nil"
		)
		deadDummy:Destroy()
		aliveDummy:Destroy()

		-- 4) I3: clamp do rewind (ping 50 ms, 300 ms, 1 s e clientTimestamp forjado)
		local maxRw = CombatConfig.MaxRewindSeconds
		local interp = CombatConfig.InterpolationDelay
		check("max_rewind_positive", maxRw > 0)
		local rw50 = LagCompensation.computeRewindSeconds(0.05, nil)
		local rw300 = LagCompensation.computeRewindSeconds(0.30, nil)
		local rw1000 = LagCompensation.computeRewindSeconds(1.0, nil)
		local rwNeg = LagCompensation.computeRewindSeconds(-0.2, nil)
		local rwNaN = LagCompensation.computeRewindSeconds(0 / 0, nil)
		check("rewind_ping_50ms", approx(rw50, math.min(0.05 + interp, maxRw)), ("got=%.4f"):format(rw50))
		check("rewind_ping_300ms_clamped", approx(rw300, math.min(0.30 + interp, maxRw)), ("got=%.4f"):format(rw300))
		check("rewind_ping_1s_clamped", approx(rw1000, maxRw), ("got=%.4f"):format(rw1000))
		check("rewind_ping_negative_sanitized", approx(rwNeg, math.min(interp, maxRw)), ("got=%.4f"):format(rwNeg))
		check("rewind_ping_nan_sanitized", approx(rwNaN, math.min(interp, maxRw)), ("got=%.4f"):format(rwNaN))

		local forged = LagCompensation.computeRewindSeconds(0.02, 0.5)
		local expectedCap = math.min(maxRw, 0.02 + interp + CombatConfig.ClientTimestampSlack)
		check("rewind_forged_timestamp_clamped", approx(forged, expectedCap), ("got=%.4f"):format(forged))

		-- 5) Tiro impossível (ImpossibleShotSlack = 8)
		check("impossible_shot_slack_is_8", approx(CombatConfig.ImpossibleShotSlack, 8))
		check("impossible_shot_over_slack_true", HitDetection.isImpossibleShot(29, 20) == true)
		check("impossible_shot_at_slack_false", HitDetection.isImpossibleShot(28, 20) == false)
		check("impossible_shot_no_wall_false", HitDetection.isImpossibleShot(100, nil) == false)

		-- 6) Menores: validateFire (5 campos com seq, select("#") == 1) e guards de NaN/negativo no Damage
		local validPayload = {
			origin = Vector3.new(0, 5, 0),
			direction = Vector3.new(0, 0, -1),
			timestamp = 10,
			weaponId = "M4A1",
			seq = 1,
		}
		local vOk, vReason = CombatContract.validateFire(validPayload)
		check("validate_fire_single_arg_ok", vOk == true and vReason == nil, tostring(vReason))
		vOk, vReason = CombatContract.validateFire(validPayload, "extra")
		check("validate_fire_extra_arg_rejected", vOk == false and vReason == "unexpected_args", tostring(vReason))
		vOk, vReason = CombatContract.validateFire()
		check("validate_fire_zero_args_rejected", vOk == false and vReason == "unexpected_args", tostring(vReason))
		vOk, vReason = CombatContract.validateFire({
			origin = Vector3.new(0, 5, 0),
			direction = Vector3.new(0, 0, -1),
			timestamp = 10,
			weaponId = "M4A1",
			seq = -1,
		})
		check("validate_fire_negative_seq_rejected", vOk == false and vReason == "bad_seq", tostring(vReason))

		local nan = 0 / 0
		check("damage_falloff_nan_safe", approx(Damage.falloff(nan, 100, 300, 0.6), 0.6))
		local remArmor, remDmg = Damage.absorb(50, -20)
		check("damage_absorb_negative_no_heal", approx(remArmor, 50) and approx(remDmg, 0))
		remArmor, remDmg = Damage.absorb(nan, nan)
		check("damage_absorb_nan_safe", approx(remArmor, 0) and approx(remDmg, 0))
		local m4 = Weapons.M4A1
		local computedNaN = Damage.compute(m4, "Head", nan)
		check("damage_compute_nan_distance_finite", computedNaN == computedNaN and computedNaN >= 0)
	end)

	sandbox:Destroy()
	if not runOk then
		failed += 1
		table.insert(failures, "runtime_error: " .. tostring(runErr))
	end

	return passed, failed, failures
end

return HitDetectionSpec