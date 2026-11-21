--!strict
-- Local fighter control: your own avatar, locked to the side-view plane.
-- Movement / jumps / attacks happen instantly here; hits are reported to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Rig = require(Shared:WaitForChild("Rig"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Input = require(script.Parent:WaitForChild("Input"))
local Animator = require(script.Parent:WaitForChild("Animator"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))
local Tags = require(script.Parent:WaitForChild("Tags"))

local Controller = {}

local player = Players.LocalPlayer
local Event = Remotes.Event

local char: Model? = nil
local hum: Humanoid? = nil
local root: BasePart? = nil
local facingObj: AlignOrientation? = nil
local knockLV: LinearVelocity? = nil
local bodyParts: { BasePart } = {}

Controller.aim = 0
Controller.facing = 1
Controller.blocking = false
Controller.crouch = false

local input = {
	moveX = 0,
	jump = false,
	crouch = false,
	attack = false,
	block = false,
	aimX = 0,
	aimY = 0,
	jumpPressed = false,
	attackPressed = false,
	throwPressed = false,
}

local attackCd = 0
local attackBuffer = 0
local hand = "R"
local djumpUsed = false
local knockUntil = 0
local wasGrounded = true
local airTime = 0
local physicsSince = 0

local function now(): number
	return os.clock()
end

local function fighterFolder(): Instance?
	return workspace:FindFirstChild("Fighters")
end

local function fid(): number
	local c = char
	local v = if c then c:GetAttribute("Fid") else nil
	return if type(v) == "number" then v else 0
end
Controller.fid = fid

local function myColor(): Color3
	return if char then Tags.color(char) else Color3.new(1, 1, 1)
end

function Controller.character(): Model?
	return char
end

function Controller.alive(): boolean
	return char ~= nil and hum ~= nil and (hum :: Humanoid).Health > 0 and char.Parent ~= nil
end

function Controller.isRagdoll(): boolean
	return char ~= nil and (char :: Model):GetAttribute("Ragdoll") == true
end

function Controller.shoulder(): Vector3
	local c = char
	if not c then
		return Vector3.zero
	end
	local ut = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
	if ut and ut:IsA("BasePart") then
		return ut.Position + Vector3.new(0, ut.Size.Y * 0.3, 0)
	end
	return if root then root.Position + Vector3.new(0, 1.5, 0) else Vector3.zero
end

local function aimDir(): Vector3
	return Vector3.new(math.cos(Controller.aim), math.sin(Controller.aim), 0)
end

local function onCharacter(c: Model)
	char = c
	hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
	root = c:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root then
		return
	end
	local h = hum :: Humanoid
	h.AutoRotate = false
	pcall(function()
		h:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		h:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	end)
	bodyParts = Rig.bodyParts(c)
	djumpUsed = false
	task.spawn(function()
		local r = root :: BasePart
		facingObj = r:WaitForChild("Facing", 15) :: AlignOrientation?
		knockLV = r:WaitForChild("Knock", 15) :: LinearVelocity?
	end)
end

function Controller.init()
	task.spawn(function()
		local ok, err = pcall(function()
			local ps = player:WaitForChild("PlayerScripts")
			local pm = require(ps:WaitForChild("PlayerModule") :: ModuleScript) :: any
			pm:GetControls():Disable()
		end)
		if not ok then
			warn("[Ragdoll Rumble] could not disable default controls:", err)
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-------------------------------------------------------------------------------
-- hit detection against other fighters

local BODY = { "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "Torso" }

local function bodyDist(m: Model, p: Vector3): (number, Vector3)
	local best, bp = math.huge, p
	for _, n in BODY do
		local part = m:FindFirstChild(n)
		if part and part:IsA("BasePart") then
			local d = (part.Position - p).Magnitude
			if d < best then
				best, bp = d, part.Position
			end
		end
	end
	return best, bp
end

local function victimsNear(center: Vector3, radius: number): { { model: Model, fid: number, at: Vector3 } }
	local out = {}
	local folder = fighterFolder()
	if not folder then
		return out
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m ~= char then
			local vf = m:GetAttribute("Fid")
			if type(vf) == "number" then
				local d, at = bodyDist(m, center)
				if d < radius then
					table.insert(out, { model = m, fid = vf, at = at })
				end
			end
		end
	end
	return out
end

local function fighterOf(inst: Instance): Model?
	local m: Instance? = inst
	while m and m ~= workspace do
		if m:IsA("Model") and m:GetAttribute("Fid") then
			return m :: Model
		end
		m = m.Parent
	end
	return nil
end

local function rayParams(): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	if char then
		table.insert(list, char)
	end
	for _, n in { "RumbleFX", "Pickups", "Projectiles", "RumbleView" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	local arena = workspace:FindFirstChild("Arena")
	if arena then
		local ink = arena:FindFirstChild("Ink")
		if ink then
			table.insert(list, ink)
		end
		local decor = arena:FindFirstChild("Decor")
		if decor then
			table.insert(list, decor)
		end
	end
	rp.FilterDescendantsInstances = list
	return rp
end

-------------------------------------------------------------------------------
-- attacks

local function impactFx(pos: Vector3, big: boolean)
	Effects.spark(pos, Color3.new(1, 1, 1), if big then 14 else 8, if big then 50 else 32)
	Effects.ring(pos, myColor(), if big then 4 else 2.4)
	CameraRig.shake(if big then 0.3 else 0.14)
	CameraRig.punchZoom(if big then 0.07 else 0.025)
	if big then
		Effects.stars(pos, Color3.fromRGB(255, 236, 150), 5)
	end
end

local function punch()
	hand = if hand == "R" then "L" else "R"
	attackCd = Config.PUNCH_COOLDOWN
	local f = fid()
	Animator.trigger(f, "punch", hand)
	Event:FireServer({ t = "Act", kind = "punch", hand = hand })
	Audio.play("whoosh")
	task.delay(0.075, function()
		if not Controller.alive() or Controller.isRagdoll() then
			return
		end
		local dir = aimDir()
		local center = Controller.shoulder() + dir * Config.PUNCH_REACH
		for _, v in victimsNear(center, Config.PUNCH_RADIUS) do
			Event:FireServer({ t = "Hit", victim = v.fid, kind = "punch", dx = dir.X, dy = dir.Y, x = v.at.X, y = v.at.Y })
			impactFx(center:Lerp(v.at, 0.5), false)
			Audio.play("punch")
		end
	end)
end

local function swing(w: Weapons.Weapon)
	attackCd = w.rate
	Animator.trigger(fid(), "swing")
	Event:FireServer({ t = "Act", kind = "swing" })
	Audio.play("slash")
	task.delay(0.06, function()
		local d = aimDir()
		Effects.slash(Controller.shoulder() + d * 2.4, Controller.aim, myColor(), Controller.facing, if w.key == "bonker" then 1.5 else 1.3)
	end)
	local hitSet: { [number]: boolean } = {}
	for _, delay in { 0.05, 0.1, 0.16 } do
		task.delay(delay, function()
			if not Controller.alive() or Controller.isRagdoll() then
				return
			end
			local dir = aimDir()
			local center = Controller.shoulder() + dir * (w.length * 0.6 + 1.2)
			for _, v in victimsNear(center, w.length * 0.55 + 1.6) do
				if not hitSet[v.fid] then
					hitSet[v.fid] = true
					Event:FireServer({ t = "Hit", victim = v.fid, kind = "melee", dx = dir.X, dy = dir.Y, x = v.at.X, y = v.at.Y })
					impactFx(v.at, true)
					Audio.play(if w.key == "bonker" then "bonk" else "heavy")
				end
			end
		end)
	end
end

function Controller.selfKnock(v: Vector3, duration: number)
	local lv = knockLV
	if lv then
		lv.VectorVelocity = v
		lv.Enabled = true
		knockUntil = now() + duration
	end
end

local function muzzleFrom(w: Weapons.Weapon): Vector3
	local sh = Controller.shoulder()
	local dir = aimDir()
	local reach = 1.9 + w.length * 0.8
	local hit = workspace:Raycast(sh, dir * reach, rayParams())
	if hit and not fighterOf(hit.Instance) then
		return hit.Position - dir * 0.3
	end
	return sh + dir * reach
end

local function fire(w: Weapons.Weapon)
	attackCd = w.rate
	local seed = math.random(1, 1000000)
	local origin = muzzleFrom(w)
	local rp = rayParams()
	local hits = {}
	local ends = {}
	local r, g, b = Util.hexToRGB(w.tracer)
	local tracerColor = Color3.fromRGB(r, g, b)
	for i, a in Weapons.angles(w, Controller.aim, seed) do
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local res = workspace:Raycast(origin, dir * w.range, rp)
		local endPos = if res then res.Position else origin + dir * w.range
		table.insert(ends, { endPos.X, endPos.Y })
		Effects.tracer(origin, endPos, tracerColor, if w.key == "longshot" then 0.35 else 0.18)
		if res then
			local m = fighterOf(res.Instance)
			if m then
				local vf = m:GetAttribute("Fid")
				table.insert(hits, { fid = vf, head = res.Instance.Name == "Head", x = res.Position.X, y = res.Position.Y, i = i })
				Effects.spark(res.Position, Color3.new(1, 1, 1), 6, 30)
			else
				Effects.spark(res.Position, tracerColor, 5, 22, 0.25)
			end
		end
	end
	Effects.muzzle(origin, Controller.aim, tracerColor)
	Effects.shell(Controller.shoulder(), Controller.facing)
	Audio.play(w.sound)
	Animator.trigger(fid(), "fire")
	CameraRig.shake(math.clamp(w.recoil / 60, 0.05, 0.4))
	local d = aimDir()
	CameraRig.kick(-d.X * 0.4, -d.Y * 0.4)
	if w.recoil >= 15 then
		local v = root and root.AssemblyLinearVelocity or Vector3.zero
		Controller.selfKnock(Vector3.new(v.X, math.max(v.Y, 0), 0) * 0.3 - d * w.recoil, 0.12)
	end
	Event:FireServer({ t = "Shoot", wid = w.id, x = origin.X, y = origin.Y, aim = Controller.aim, seed = seed, hits = hits, ends = ends })
end

local function launch(w: Weapons.Weapon)
	attackCd = w.rate
	Event:FireServer({ t = "Launch", wid = w.id, aim = Controller.aim })
	if w.kind == "throwable" then
		Animator.trigger(fid(), "lob")
		Audio.play("lob")
	else
		Animator.trigger(fid(), "fire")
		Audio.play("rocket")
		Effects.muzzle(muzzleFrom(w), Controller.aim, Color3.fromRGB(255, 160, 80))
		CameraRig.shake(0.25)
		if w.recoil > 0 then
			Controller.selfKnock(-aimDir() * w.recoil, 0.12)
		end
	end
end

-------------------------------------------------------------------------------
-- per frame

-- mouseWorld: point under the cursor; autoTarget: nearest enemy (pad / touch aim assist)
function Controller.update(dt: number, mouseWorld: Vector2?, autoTarget: Vector2?, frozen: boolean)
	local c, h, r = char, hum, root
	if not c or not h or not r or not c.Parent then
		return
	end
	local sh = Controller.shoulder()
	Input.apply(input, sh.X, sh.Y, Controller.facing, mouseWorld, autoTarget)
	local dx, dy = input.aimX - sh.X, input.aimY - sh.Y
	if dx * dx + dy * dy > 0.3 then
		Controller.aim = math.atan2(dy, dx)
	end
	local cx = math.cos(Controller.aim)
	if math.abs(cx) > 0.1 then
		Controller.facing = if cx > 0 then 1 else -1
	end

	local f = fid()
	local alive = Controller.alive()
	local floppy = Controller.isRagdoll()
	attackCd -= dt
	Controller.blocking = alive and not floppy and not frozen and input.block
	Controller.crouch = input.crouch
	local flags = (if Controller.blocking then 1 else 0) + (if Controller.crouch then 2 else 0)
	Animator.setState(f, Controller.aim, flags, true)

	-- failsafe: never stay stuck in Physics state once the server stood us up
	local st = h:GetState()
	if alive and not floppy and st == Enum.HumanoidStateType.Physics then
		physicsSince += dt
		if physicsSince > 0.4 then
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
			physicsSince = 0
		end
	else
		physicsSince = 0
	end

	if not alive or floppy or frozen then
		h:Move(Vector3.zero, false)
		input.jumpPressed, input.attackPressed, input.throwPressed = false, false, false
		attackBuffer = 0
		return
	end

	local fo = facingObj
	if fo then
		fo.CFrame = Rig.facingCFrame(Controller.facing)
	end

	-- movement
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	local speedMul = if Controller.blocking then Config.BLOCK_SPEED elseif input.crouch and grounded then 0.45 else 1
	if now() > knockUntil then
		h:Move(Vector3.new(input.moveX * speedMul, 0, 0), false)
	end
	if grounded then
		if not wasGrounded and airTime > 0.3 then
			Audio.play("land", math.clamp(airTime, 0.4, 1.2))
			Effects.dust(r.Position - Vector3.new(0, 2.6, 0), 4)
		end
		djumpUsed = false
		airTime = 0
	else
		airTime += dt
	end
	wasGrounded = grounded

	if input.jumpPressed then
		input.jumpPressed = false
		if grounded then
			h.Jump = true
			Audio.play("jump")
			Effects.dust(r.Position - Vector3.new(0, 2.6, 0), 3)
		elseif not djumpUsed then
			djumpUsed = true
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(v.X, Config.DOUBLE_JUMP_VELOCITY, 0)
			Animator.trigger(f, "djump")
			Event:FireServer({ t = "Act", kind = "djump" })
			Effects.ring(r.Position - Vector3.new(0, 2.4, 0), myColor(), 4)
			Audio.play("djump")
		end
	end
	if not grounded and input.crouch then
		local v = r.AssemblyLinearVelocity
		if v.Y > -90 then
			r.AssemblyLinearVelocity = v - Vector3.new(0, Config.FAST_FALL * dt, 0)
		end
	end

	-- attacks
	local w = Weapons.get(c:GetAttribute("Wid") :: number?)
	local ammo = (c:GetAttribute("Ammo") :: number?) or 0
	if input.throwPressed then
		input.throwPressed = false
		if w then
			Event:FireServer({ t = "Throw", aim = Controller.aim })
			Animator.trigger(f, "throw")
			Audio.play("throw")
		end
	end
	if input.attackPressed then
		attackBuffer = 0.2
		input.attackPressed = false
	else
		attackBuffer = math.max(0, attackBuffer - dt)
	end
	local want = attackBuffer > 0 or (input.attack and w ~= nil and w.auto)
	if want and attackCd <= 0 and not Controller.blocking then
		attackBuffer = 0
		if not w then
			punch()
		elseif w.kind == "melee" then
			swing(w)
		elseif w.kind == "gun" then
			if ammo > 0 then
				fire(w)
			end
		elseif ammo > 0 then
			launch(w)
		end
	end
end

-- before each physics step
function Controller.physicsStep(_dt: number)
	local c, r = char, root
	if not c or not r or not c.Parent then
		return
	end
	local lv = knockLV
	if lv and lv.Enabled and now() > knockUntil then
		lv.Enabled = false
	end
	local floppy = Controller.isRagdoll() or not Controller.alive()
	Rig.lockPlane(c, r, if floppy then bodyParts else nil)
end

-------------------------------------------------------------------------------
-- server -> me

function Controller.onKnock(msg: any)
	local c, h = char, hum
	if not c or not h then
		return
	end
	local v = Vector3.new(tonumber(msg.vx) or 0, tonumber(msg.vy) or 0, 0)
	if msg.floppy then
		if h.Health > 0 then
			h:ChangeState(Enum.HumanoidStateType.Physics)
		end
		Rig.fling(c, v, (math.random() - 0.5) * 14)
	else
		Controller.selfKnock(v, Config.KNOCK_TIME)
		if v.Y > 10 then
			h:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
end

function Controller.onGetUp()
	local h = hum
	if h and h.Health > 0 then
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- nearest enemy for aim assist
function Controller.nearestEnemy(): Vector2?
	local c, r = char, root
	local folder = fighterFolder()
	if not c or not r or not folder then
		return nil
	end
	local best, bestD = nil, 60
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m ~= c then
			local hm = m:FindFirstChildOfClass("Humanoid")
			local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
			if hm and hm.Health > 0 and t and t:IsA("BasePart") then
				local d = (t.Position - r.Position).Magnitude
				if d < bestD then
					best, bestD = Vector2.new(t.Position.X, t.Position.Y), d
				end
			end
		end
	end
	return best
end

return Controller
