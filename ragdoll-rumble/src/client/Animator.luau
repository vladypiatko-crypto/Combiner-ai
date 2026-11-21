--!strict
-- Procedural R15 animation for every fighter (your avatar, other players, bots).
-- Each client animates everyone from replicated state (velocity, aim, actions), so no
-- animation assets are needed. Everything is a pitch rotation in the side-view plane.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Weapons"))

local Animator = {}

local JOINTS = {
	"Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist",
	"LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle",
	"LeftHip", "LeftKnee", "LeftAnkle",
}

type Action = { kind: string, t: number, dur: number, hand: string, dir: number }

type Anim = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	motors: { [string]: Motor6D },
	cur: { [string]: Vector3 },
	rootY: number,
	rootPitch: number,
	phase: number,
	aim: number,
	aimTarget: number,
	blocking: boolean,
	crouch: boolean,
	actions: { Action },
	recoil: number,
	flinch: number,
	flinchDir: number,
	airT: number,
	landT: number,
	wasRagdoll: boolean,
	seed: number,
}

local anims: { [Model]: Anim } = {}
local byFid: { [number]: Anim } = {}
local clock = 0

local PI = math.pi
local sin, cos, abs, clamp, exp = math.sin, math.cos, math.abs, math.clamp, math.exp

local function wrap(a: number): number
	return (a + PI) % (2 * PI) - PI
end

function Animator.track(model: Model)
	if anims[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local motors = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	if not motors.Waist or not motors.RightShoulder then
		return -- not an R15 rig
	end
	local cur = {}
	for _, n in JOINTS do
		cur[n] = Vector3.zero
	end
	local a: Anim = {
		model = model,
		humanoid = humanoid,
		root = root,
		motors = motors,
		cur = cur,
		rootY = 0,
		rootPitch = 0,
		phase = 0,
		aim = if root.CFrame.LookVector.X >= 0 then 0 else PI,
		aimTarget = if root.CFrame.LookVector.X >= 0 then 0 else PI,
		blocking = false,
		crouch = false,
		actions = {},
		recoil = 0,
		flinch = 0,
		flinchDir = 1,
		airT = 0,
		landT = 0,
		wasRagdoll = false,
		seed = math.random() * 10,
	}
	anims[model] = a
	local fid = model:GetAttribute("Fid")
	if type(fid) == "number" then
		byFid[fid] = a
	end
end

function Animator.untrack(model: Model)
	local a = anims[model]
	if a then
		anims[model] = nil
		for fid, b in byFid do
			if b == a then
				byFid[fid] = nil
			end
		end
	end
end

local function get(fid: number): Anim?
	local a = byFid[fid]
	if a and a.model.Parent then
		return a
	end
	for m, b in anims do
		if m:GetAttribute("Fid") == fid then
			byFid[fid] = b
			return b
		end
	end
	return nil
end

function Animator.setState(fid: number, aim: number, flags: number, snap: boolean?)
	local a = get(fid)
	if not a then
		return
	end
	a.aimTarget = aim
	if snap then
		a.aim = aim
	end
	a.blocking = bit32.band(flags, 1) ~= 0
	a.crouch = bit32.band(flags, 2) ~= 0
end

-- kind: punch | swing | fire | lob | throw | djump | flinch
function Animator.trigger(fid: number, kind: string, hand: string?, dir: number?)
	local a = get(fid)
	if not a then
		return
	end
	if kind == "fire" then
		a.recoil = 1
		return
	elseif kind == "flinch" then
		a.flinch = 1
		a.flinchDir = dir or 1
		return
	end
	local w = Weapons.get(a.model:GetAttribute("Wid") :: number?)
	local dur = 0.3
	if kind == "swing" then
		dur = (if w then w.swingTime else 0.25) + 0.18
	elseif kind == "lob" or kind == "throw" then
		dur = 0.42
	elseif kind == "djump" then
		dur = 0.4
	end
	-- a new punch replaces the previous one so combos stay snappy
	for i = #a.actions, 1, -1 do
		if a.actions[i].kind == kind then
			table.remove(a.actions, i)
		end
	end
	table.insert(a.actions, { kind = kind, t = 0, dur = dur, hand = hand or "R", dir = dir or 1 })
end

local function easeOut(x: number): number
	x = clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x) * (1 - x)
end

local function easeInOut(x: number): number
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function set(t: { [string]: Vector3 }, name: string, p: number, y: number?, r: number?)
	t[name] = Vector3.new(p, y or 0, r or 0)
end

local function animate(a: Anim, dt: number)
	local root = a.root
	local hum = a.humanoid
	local vel = root.AssemblyLinearVelocity
	local facing = if root.CFrame.LookVector.X >= 0 then 1 else -1
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local vx, vy = vel.X, vel.Y
	local speed = abs(vx)
	local t = clock + a.seed
	local w = Weapons.get(a.model:GetAttribute("Wid") :: number?)

	-- aim smoothing
	a.aim = a.aim + wrap(a.aimTarget - a.aim) * (1 - exp(-dt * 22))
	local th = a.aim
	-- arm pitch that points the arm along the aim (0 = down, pi/2 = forward, pi = up)
	local aimPitch = math.atan2(cos(th) * facing, -sin(th))

	if grounded then
		if a.airT > 0.25 then
			a.landT = 0.2
		end
		a.airT = 0
	else
		a.airT += dt
	end
	a.landT = math.max(0, a.landT - dt)
	a.recoil = math.max(0, a.recoil - dt * 7)
	a.flinch = math.max(0, a.flinch - dt * 4)

	local T: { [string]: Vector3 } = {}
	local rootY, rootPitch = 0, 0
	local waistP, waistY = 0, 0

	-- legs / base -----------------------------------------------------------------
	if not grounded then
		local rising = vy > 4
		set(T, "RightHip", if rising then 1.0 else 0.4)
		set(T, "LeftHip", if rising then 0.25 else -0.25)
		set(T, "RightKnee", if rising then -1.6 else -0.6)
		set(T, "LeftKnee", if rising then -0.9 else -0.35)
		set(T, "RightAnkle", 0.3)
		set(T, "LeftAnkle", 0.2)
		waistP = if rising then -0.12 else 0.06
	elseif a.crouch then
		set(T, "RightHip", 1.15)
		set(T, "LeftHip", 0.75)
		set(T, "RightKnee", -1.8)
		set(T, "LeftKnee", -1.6)
		set(T, "RightAnkle", 0.6)
		set(T, "LeftAnkle", 0.8)
		rootY = -1.05
		waistP = -0.35
	elseif speed > 1.5 then
		local forward = if vx * facing >= 0 then 1 else -1
		a.phase += dt * speed * 0.48 * forward
		local s, c = sin(a.phase), cos(a.phase)
		local amp = clamp(speed / 21, 0.35, 1)
		set(T, "RightHip", s * 0.9 * amp)
		set(T, "LeftHip", -s * 0.9 * amp)
		set(T, "RightKnee", -0.2 - math.max(0, c) * 1.35 * amp)
		set(T, "LeftKnee", -0.2 - math.max(0, -c) * 1.35 * amp)
		set(T, "RightAnkle", 0.25 * s * amp)
		set(T, "LeftAnkle", -0.25 * s * amp)
		rootY = abs(s) * 0.2 * amp - 0.06
		waistP = -0.16 * amp * forward
	else
		local b = sin(t * 2.3)
		set(T, "RightHip", 0.16)
		set(T, "LeftHip", -0.12)
		set(T, "RightKnee", -0.22)
		set(T, "LeftKnee", -0.3)
		set(T, "RightAnkle", 0.06)
		set(T, "LeftAnkle", 0.18)
		rootY = -0.1 + b * 0.035
		waistP = -0.06 + b * 0.02
	end
	if a.landT > 0 then
		local k = a.landT / 0.2
		for _, n in { "RightHip", "LeftHip" } do
			T[n] += Vector3.new(0.6 * k, 0, 0)
		end
		for _, n in { "RightKnee", "LeftKnee" } do
			T[n] += Vector3.new(-1.0 * k, 0, 0)
		end
		rootY -= 0.55 * k
	end

	-- upper body ----------------------------------------------------------------------
	local bob = sin(t * 4.2) * 0.04
	local guardR = Vector3.new(0.95 + bob, 0, -0.15)
	local guardL = Vector3.new(0.75 + bob, 0, 0.15)
	local elbowGuardR, elbowGuardL = 1.75, 1.9
	local armR, armL = guardR, guardL
	local elbR, elbL = elbowGuardR, elbowGuardL
	local wristR = 0
	local ap = aimPitch - waistP -- compensate for the torso lean

	if a.blocking then
		armR = Vector3.new(1.55, 0, -0.35)
		armL = Vector3.new(1.5, 0, 0.35)
		elbR, elbL = 2.1, 2.1
		waistP -= 0.08
	elseif w and (w.kind == "gun" or w.kind == "launcher") then
		armR = Vector3.new(ap, 0, 0)
		elbR = 0.05
		if w.twoHanded then
			armL = Vector3.new(ap - 0.08, 0, 0.55)
			elbL = 0.75
		else
			armL = Vector3.new(0.45, 0, 0.1)
			elbL = 1.0
		end
	elseif w and w.kind == "melee" then
		armR = Vector3.new(ap + 0.9, 0, -0.1)
		elbR = 1.0
		wristR = 0.3
	elseif w and w.kind == "throwable" then
		armR = Vector3.new(2.5, 0, -0.1)
		elbR = 1.5
	end

	if not grounded and a.airT > 0.35 and vy < -35 and not w and not a.blocking then
		-- flail when falling fast
		local fl = sin(t * 15) * 0.45
		armR = Vector3.new(2.2 + fl, 0, 0.6)
		armL = Vector3.new(2.2 - fl, 0, -0.6)
		elbR, elbL = 0.6, 0.6
	end

	-- actions ------------------------------------------------------------------------
	for i = #a.actions, 1, -1 do
		local act = a.actions[i]
		act.t += dt
		local p = act.t / act.dur
		if p >= 1 then
			table.remove(a.actions, i)
			continue
		end
		if act.kind == "punch" then
			local ext
			if p < 0.25 then
				ext = easeOut(p / 0.25)
			elseif p < 0.4 then
				ext = 1
			else
				ext = 1 - easeInOut((p - 0.4) / 0.6)
			end
			local target = Vector3.new(ap, 0, 0)
			if act.hand == "R" then
				armR = armR:Lerp(target, ext)
				elbR = elbR + (0.05 - elbR) * ext
				waistY += 0.5 * ext
				armL = armL + Vector3.new(-0.2 * ext, 0, 0)
			else
				armL = armL:Lerp(target, ext)
				elbL = elbL + (0.05 - elbL) * ext
				waistY -= 0.5 * ext
				armR = armR + Vector3.new(-0.2 * ext, 0, 0)
			end
			waistP -= 0.14 * ext
		elseif act.kind == "swing" then
			local st = if w then w.swingTime else 0.25
			local q = act.t / st
			if q <= 1 then
				local e = easeOut(q)
				local a0, a1 = ap + 2.3, ap - 0.9
				armR = Vector3.new(a0 + (a1 - a0) * e, 0, -0.1)
				elbR = 0.15
				wristR = 0.1
				waistY += -0.45 + 0.95 * e
				waistP -= 0.15 * e
			else
				local r = easeInOut((act.t - st) / (act.dur - st))
				armR = Vector3.new(ap - 0.9, 0, -0.1):Lerp(armR, r)
				elbR = 0.15 + (elbR - 0.15) * r
				waistY += 0.5 * (1 - r)
			end
		elseif act.kind == "lob" or act.kind == "throw" then
			if p < 0.3 then
				local e = easeOut(p / 0.3)
				armR = armR:Lerp(Vector3.new(2.9, 0, -0.1), e)
				elbR = elbR + (1.4 - elbR) * e
				waistY -= 0.4 * e
			elseif p < 0.6 then
				local e = easeOut((p - 0.3) / 0.3)
				armR = Vector3.new(2.9 + (ap - 0.25 - 2.9) * e, 0, -0.1)
				elbR = 1.4 + (0.1 - 1.4) * e
				waistY += -0.4 + 0.9 * e
			else
				local r = easeInOut((p - 0.6) / 0.4)
				armR = Vector3.new(ap - 0.25, 0, -0.1):Lerp(armR, r)
				elbR = 0.1 + (elbR - 0.1) * r
				waistY += 0.5 * (1 - r)
			end
		elseif act.kind == "djump" then
			rootPitch = -2 * PI * easeInOut(p)
			for _, n in { "RightHip", "LeftHip" } do
				T[n] = Vector3.new(1.7, 0, 0)
			end
			for _, n in { "RightKnee", "LeftKnee" } do
				T[n] = Vector3.new(-2.2, 0, 0)
			end
			armR = Vector3.new(1.2, 0, -0.3)
			armL = Vector3.new(1.2, 0, 0.3)
			elbR, elbL = 1.6, 1.6
		end
	end

	-- recoil + flinch
	if a.recoil > 0 then
		local k = a.recoil * a.recoil
		armR += Vector3.new(0.4 * k, 0, 0)
		elbR += 0.35 * k
		waistP += 0.14 * k
		if w and w.twoHanded then
			armL += Vector3.new(0.4 * k, 0, 0)
		end
	end
	local neckP = clamp((aimPitch - PI / 2) * 0.55, -0.55, 0.6)
	if a.flinch > 0 then
		local k = a.flinch * a.flinch
		waistP += 0.5 * k * a.flinchDir
		neckP += 0.45 * k * a.flinchDir
		armR += Vector3.new(0.3 * k, 0, 0.5 * k)
		armL += Vector3.new(0.3 * k, 0, -0.5 * k)
	end

	-- victory dance
	if a.model:GetAttribute("Victory") == true then
		local wave = sin(t * 9)
		armR = Vector3.new(2.95 + wave * 0.15, 0, 0.35)
		armL = Vector3.new(2.95 - wave * 0.15, 0, -0.35)
		elbR, elbL = 0.3 + wave * 0.3, 0.3 - wave * 0.3
		waistP = 0.12
		waistY = sin(t * 4.5) * 0.35
		neckP = 0.3
		if grounded then
			rootY += abs(sin(t * 6)) * 0.4
		end
	end

	set(T, "RightShoulder", armR.X, armR.Y, armR.Z)
	set(T, "LeftShoulder", armL.X, armL.Y, armL.Z)
	set(T, "RightElbow", elbR)
	set(T, "LeftElbow", elbL)
	set(T, "RightWrist", wristR)
	set(T, "LeftWrist", 0)
	set(T, "Waist", waistP, waistY, 0)
	set(T, "Neck", neckP - waistP * 0.5, -waistY * 0.4, 0)

	-- smooth + write ---------------------------------------------------------------------
	local fast = #a.actions > 0 or a.recoil > 0.2
	local kFast = 1 - exp(-dt * 40)
	local kSlow = 1 - exp(-dt * 16)
	for _, n in JOINTS do
		local target = T[n]
		if n == "Root" or not target then
			continue
		end
		local k = if fast and (string.find(n, "Shoulder") or string.find(n, "Elbow") or n == "Waist") then kFast else kSlow
		local c = a.cur[n]
		c = c + (target - c) * k
		a.cur[n] = c
		local m = a.motors[n]
		if m then
			m.Transform = CFrame.Angles(c.X, c.Y, c.Z)
		end
	end
	a.rootY += (rootY - a.rootY) * kSlow
	if rootPitch ~= 0 then
		a.rootPitch = rootPitch
	else
		a.rootPitch += (0 - a.rootPitch) * kFast
	end
	local rm = a.motors.Root
	if rm then
		rm.Transform = CFrame.new(0, a.rootY, 0) * CFrame.Angles(a.rootPitch, 0, 0)
	end
end

function Animator.step(dt: number)
	clock += dt
	for model, a in anims do
		if not model.Parent then
			anims[model] = nil
			continue
		end
		local floppy = model:GetAttribute("Ragdoll") == true or a.humanoid.Health <= 0
		if floppy then
			if not a.wasRagdoll then
				a.wasRagdoll = true
				local rm = a.motors.Root
				if rm then
					rm.Transform = CFrame.identity
				end
				table.clear(a.actions)
			end
			continue
		end
		a.wasRagdoll = false
		animate(a, dt)
	end
end

return Animator
