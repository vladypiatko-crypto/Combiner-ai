--!strict
-- Bot fighters: colorful custom mannequin avatars + a scrappy platform-fighter brain.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Rig = require(Shared:WaitForChild("Rig"))
local Util = require(Shared:WaitForChild("Util"))
local Arena = require(script.Parent:WaitForChild("Arena"))
local Combat = require(script.Parent:WaitForChild("Combat"))

local Bots = {}

local templates: { [number]: Model } = {}
local templateFolder: Folder? = nil

local function getFolder(): Folder
	if not templateFolder then
		local f = Instance.new("Folder")
		f.Name = "RumbleBotTemplates"
		f.Parent = ServerStorage
		templateFolder = f
	end
	return templateFolder :: Folder
end

-- build (once per color) an R15 mannequin in that fighter color
function Bots.template(colorIndex: number): Model?
	if templates[colorIndex] then
		return templates[colorIndex]
	end
	local c = Config.COLORS[colorIndex] or Config.COLORS[1]
	local desc = Instance.new("HumanoidDescription")
	local skin = c.main:Lerp(Color3.new(1, 1, 1), 0.55)
	desc.HeadColor = skin
	desc.LeftArmColor = c.main
	desc.RightArmColor = c.main
	desc.TorsoColor = c.main
	desc.LeftLegColor = c.dark
	desc.RightLegColor = c.dark
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Ragdoll Rumble] could not build a bot avatar:", model)
		return nil
	end
	local m = model :: Model
	-- glowing headband so bots are easy to tell apart
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		local band = Instance.new("Part")
		band.Name = "Headband"
		band.Shape = Enum.PartType.Cylinder
		band.Size = Vector3.new(0.35, head.Size.Y * 1.02, head.Size.Y * 1.02)
		band.Color = c.main
		band.Material = Enum.Material.Neon
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.Massless = true
		band.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.18, 0) * CFrame.Angles(0, 0, math.pi / 2)
		band.Parent = m
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = head
		wc.Part1 = band
		wc.Parent = band
	end
	local animate = m:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	Rig.setup(m)
	m.Parent = getFolder()
	templates[colorIndex] = m
	return m
end

export type Brain = {
	rng: Util.Rng,
	skill: number,
	targetFid: number,
	retarget: number,
	attackCd: number,
	jumpCd: number,
	blockUntil: number,
	react: number,
	aimErr: number,
	aimErrT: number,
	hand: string,
	djumpUsed: boolean,
	stuckT: number,
	lastX: number,
	idleDir: number,
	idleT: number,
}

function Bots.newBrain(seed: number, skill: number): Brain
	return {
		rng = Util.rng(seed),
		skill = skill,
		targetFid = 0,
		retarget = 0,
		attackCd = 0.5,
		jumpCd = 0,
		blockUntil = 0,
		react = 0,
		aimErr = 0,
		aimErrT = 0,
		hand = "R",
		djumpUsed = false,
		stuckT = 0,
		lastX = 0,
		idleDir = 1,
		idleT = 0,
	}
end

local function geoParams(): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	local arena = Arena.folder()
	local geo = if arena then arena:FindFirstChild("Geometry") else nil
	rp.FilterDescendantsInstances = if geo then { geo } else {}
	return rp
end

local function groundBelow(rp: RaycastParams, x: number, y: number, depth: number): boolean
	return workspace:Raycast(Vector3.new(x, y, 0), Vector3.new(0, -depth, 0), rp) ~= nil
end

function Bots.think(f: Combat.F, dt: number, frozen: boolean)
	local b = f.brain :: Brain
	local hum = f.humanoid
	if not f.alive or Combat.isRagdoll(f) or frozen then
		hum:Move(Vector3.zero, false)
		f.blocking = false
		return
	end
	local rng = b.rng
	local now = os.clock()
	local root = f.root
	local pos = root.Position
	local rp = geoParams()
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if grounded then
		b.djumpUsed = false
	end
	b.retarget -= dt
	b.attackCd -= dt
	b.jumpCd -= dt
	b.react -= dt
	b.aimErrT -= dt
	if b.aimErrT <= 0 then
		b.aimErrT = rng:range(0.3, 0.8)
		b.aimErr = rng:range(-1, 1) * (1 - b.skill) * 0.3
	end

	-- target
	local target = Combat.fighters[b.targetFid]
	if b.retarget <= 0 or not target or not target.alive then
		b.retarget = rng:range(0.7, 1.5)
		local best, bestD = nil, math.huge
		for _, o in Combat.fighters do
			if o ~= f and o.alive and o.model.Parent then
				local d = (o.root.Position - pos).Magnitude * rng:range(0.8, 1.25)
				if d < bestD then
					best, bestD = o, d
				end
			end
		end
		target = best
		b.targetFid = if best then best.fid else 0
	end

	-- weapon hunting
	local w = Weapons.get(f.wid)
	local goal = pos
	local wantWeapon = false
	local dist = math.huge
	if target then
		dist = (target.root.Position - pos).Magnitude
	end
	if not w then
		local pickups = workspace:FindFirstChild("Pickups")
		local best, bestD = nil, 30
		if pickups then
			for _, m in pickups:GetChildren() do
				if m:IsA("Model") and m.PrimaryPart then
					local pp = m.PrimaryPart.Position
					local d = (pp - pos).Magnitude
					if d < bestD and pp.Y > (if Arena.map then Arena.map.killY + 5 else -1e9) then
						best, bestD = pp, d
					end
				end
			end
		end
		if best and (bestD < dist * 1.3 or bestD < 9) then
			goal = best
			wantWeapon = true
		end
	end
	if not wantWeapon and target then
		goal = target.root.Position
	end

	local prefer = 2.6
	if w and (w.kind == "gun" or w.kind == "launcher") then
		prefer = if w.key == "scatter" then 9 else 18
	elseif w and w.kind == "throwable" then
		prefer = 14
	elseif w and w.kind == "melee" then
		prefer = 3.2
	end
	if wantWeapon then
		prefer = 0
	end

	local dx = goal.X - pos.X
	local move = 0
	if math.abs(dx) > prefer + 0.8 then
		move = Util.sign(dx)
	elseif not wantWeapon and math.abs(dx) < prefer - 4 then
		move = -Util.sign(dx)
	end

	-- don't walk off ledges unless it's a jumpable gap toward the goal
	if grounded and move ~= 0 then
		if not groundBelow(rp, pos.X + move * 3, pos.Y, 16) then
			local gapOk = false
			for k = 5, 16, 2 do
				if groundBelow(rp, pos.X + move * k, pos.Y + 4, 14) then
					gapOk = true
					break
				end
			end
			if gapOk and (goal.Y > pos.Y - 8 or wantWeapon) then
				if b.jumpCd <= 0 then
					hum.Jump = true
					b.jumpCd = 0.6
				end
			elseif goal.Y < pos.Y - 4 and groundBelow(rp, pos.X + move * 3, pos.Y, 40) then
				-- safe drop
			else
				move = 0
			end
		end
	end

	-- recovery: off stage -> head back to the middle, double jump
	local bnd = if Arena.map then Arena.map.bounds else { left = -50, right = 50 }
	if not grounded and not groundBelow(rp, pos.X, pos.Y, 60) then
		move = Util.sign((bnd.left + bnd.right) * 0.5 - pos.X)
		if not b.djumpUsed and root.AssemblyLinearVelocity.Y < 4 then
			b.djumpUsed = true
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, Config.DOUBLE_JUMP_VELOCITY, 0)
			Combat.act(f, "djump")
		end
	end

	-- jump at walls / higher goals
	if grounded and b.jumpCd <= 0 then
		local dir = if move ~= 0 then move else Combat.facing(f)
		local wall = workspace:Raycast(pos, Vector3.new(dir * 3, 0, 0), rp)
		local higher = goal.Y > pos.Y + 4 and math.abs(dx) < 16
		if (wall and move ~= 0) or higher then
			hum.Jump = true
			b.jumpCd = rng:range(0.5, 0.9)
		end
	end
	-- stuck
	if math.abs(pos.X - b.lastX) < 0.02 and move ~= 0 then
		b.stuckT += dt
		if b.stuckT > 0.7 then
			hum.Jump = true
			b.stuckT = 0
		end
	else
		b.stuckT = 0
	end
	b.lastX = pos.X

	if not target and not wantWeapon then
		b.idleT -= dt
		if b.idleT <= 0 then
			b.idleT = rng:range(1, 2.5)
			b.idleDir = if rng:next() < 0.5 then -1 else 1
		end
		move = b.idleDir
		if grounded and not groundBelow(rp, pos.X + move * 3, pos.Y, 16) then
			b.idleDir = -b.idleDir
			move = 0
		end
	end

	-- block incoming swings
	f.blocking = now < b.blockUntil
	if target and dist < 7 and b.react <= 0 then
		local la = math.max(target.lastAction.punch or 0, target.lastAction.swing or 0)
		if now - la < 0.12 then
			b.react = rng:range(0.25, 0.5)
			if rng:next() < b.skill * 0.55 then
				b.blockUntil = now + rng:range(0.25, 0.45)
				f.blockStart = now
				f.blocking = true
			end
		end
	end
	local speed = if f.blocking then Config.BLOCK_SPEED else 1
	hum:Move(Vector3.new(move * speed, 0, 0), false)

	-- aim + facing
	local aimAt = if target then (target.model:FindFirstChild("UpperTorso") or target.root) :: BasePart else nil
	if aimAt then
		local sh = Combat.shoulder(f)
		local to = aimAt.Position - sh
		local extra = 0
		if w and w.kind == "throwable" then
			extra = math.clamp(to.Magnitude * 0.025, 0, 0.6)
		end
		f.aim = math.atan2(to.Y, to.X) + b.aimErr + extra * Util.sign(to.X)
		if extra > 0 and to.X < 0 then
			f.aim = math.atan2(to.Y, to.X) + b.aimErr - extra
		end
	elseif move ~= 0 then
		f.aim = if move > 0 then 0 else math.pi
	end
	local facingObj = root:FindFirstChild("Facing") :: AlignOrientation?
	if facingObj then
		facingObj.CFrame = Rig.facingCFrame(if math.cos(f.aim) >= 0 then 1 else -1)
	end

	if not target or f.blocking then
		return
	end

	-- attack
	if b.attackCd <= 0 then
		if not w then
			if dist < 4.6 then
				b.hand = if b.hand == "R" then "L" else "R"
				Combat.botPunch(f, b.hand)
				b.attackCd = Config.PUNCH_COOLDOWN + rng:range(0.05, 0.35) * (1.4 - b.skill)
			end
		elseif w.kind == "melee" then
			if dist < w.length + 3 then
				Combat.botSwing(f)
				b.attackCd = w.rate + rng:range(0.05, 0.3)
			end
		else
			local sh = Combat.shoulder(f)
			local dir = Vector3.new(math.cos(f.aim), math.sin(f.aim), 0)
			local blocked = workspace:Raycast(sh, dir * math.min(dist, 80), rp)
			if not blocked and dist < (if w.kind == "gun" then math.min(w.range, 70) else 45) then
				if w.kind == "gun" then
					Combat.botShoot(f)
					b.attackCd = w.rate + (if w.auto then 0 else rng:range(0.1, 0.45) * (1.3 - b.skill))
				elseif dist > 7 then
					Combat.botLaunch(f)
					b.attackCd = w.rate + rng:range(0.2, 0.6)
				end
			end
		end
	end
end

return Bots
