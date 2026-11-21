--!strict
-- Server-authoritative combat: health, knockback, ragdolls, weapons, pickups, projectiles.
-- Players detect their own hits (snappy feel) and the server validates them; bots and
-- projectiles are resolved fully on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Rig = require(Shared:WaitForChild("Rig"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Arena = require(script.Parent:WaitForChild("Arena"))

local Combat = {}

export type F = {
	fid: number,
	name: string,
	colorIndex: number,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	isBot: boolean,
	alive: boolean,
	wid: number,
	ammo: number,
	aim: number,
	blocking: boolean,
	crouch: boolean,
	blockStart: number,
	stagger: number,
	lastHitBy: number,
	lastHitTime: number,
	ragdollUntil: number,
	knockUntil: number,
	knockLV: LinearVelocity?,
	deathCause: string,
	hazardCd: number,
	lastAction: { [string]: number },
	lastShot: number,
	meleeHits: { [number]: number },
	discardAt: number,
	hitBudget: number,
	brain: any,
	lastKnock: Vector3,
}

type Pickup = {
	model: Model,
	handle: BasePart,
	wid: number,
	ammo: number,
	born: number,
	thrownBy: number,
	thrownAt: number,
	dangerous: boolean,
}

type Proj = {
	part: BasePart,
	kind: string,
	wid: number,
	owner: number,
	born: number,
	fuse: number,
	last: Vector3,
}

Combat.fighters = {} :: { [number]: F }
local pickups: { Pickup } = {}
local projectiles: { Proj } = {}
local Event = Remotes.Event

Combat.hooks = {
	onDeath = function(_f: F, _killer: number, _cause: string) end,
	active = function(): boolean
		return true
	end,
	roundTime = function(): number
		return 0
	end,
}

local function sendAll(msg: any)
	Event:FireAllClients(msg)
end

local function sendOthers(player: Player?, msg: any)
	for _, p in Players:GetPlayers() do
		if p ~= player then
			Event:FireClient(p, msg)
		end
	end
end
Combat.sendAll = sendAll
Combat.sendOthers = sendOthers

local function clock(): number
	return os.clock()
end

local function folder(name: string): Folder
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f :: Folder
end

-------------------------------------------------------------------------------
-- geometry helpers

function Combat.facing(f: F): number
	return if f.root.CFrame.LookVector.X >= 0 then 1 else -1
end

function Combat.aimDir(f: F): Vector3
	return Vector3.new(math.cos(f.aim), math.sin(f.aim), 0)
end

function Combat.shoulder(f: F): Vector3
	local ut = f.model:FindFirstChild("UpperTorso") or f.model:FindFirstChild("Torso")
	if ut and ut:IsA("BasePart") then
		return ut.Position + Vector3.new(0, ut.Size.Y * 0.3, 0)
	end
	return f.root.Position + Vector3.new(0, 1.5, 0)
end

local BODY = { "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso", "Torso" }

function Combat.distToBody(f: F, p: Vector3): number
	local best = math.huge
	for _, n in BODY do
		local part = f.model:FindFirstChild(n)
		if part and part:IsA("BasePart") then
			local d = (part.Position - p).Magnitude
			if d < best then
				best = d
			end
		end
	end
	return best
end

function Combat.isRagdoll(f: F): boolean
	return f.model:GetAttribute("Ragdoll") == true
end

function Combat.fromModel(inst: Instance?): F?
	local m = inst
	while m and m ~= workspace do
		if m:IsA("Model") and m:GetAttribute("Fid") then
			return Combat.fighters[m:GetAttribute("Fid") :: number]
		end
		m = m.Parent
	end
	return nil
end

function Combat.rayParams(exclude: { Instance }): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(exclude)
	table.insert(list, folder("Pickups"))
	table.insert(list, folder("Projectiles"))
	rp.FilterDescendantsInstances = list
	rp.IgnoreWater = true
	return rp
end

-------------------------------------------------------------------------------
-- weapon models

-- weapon space (+X barrel, +Y up) -> right hand space (arm points along -Y)
local GRIP = CFrame.fromMatrix(Vector3.new(0, -0.25, 0), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))

function Combat.buildWeaponModel(w: Weapons.Weapon, physical: boolean): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "Weapon"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = if physical then Vector3.new(math.max(1, w.length + 0.4), 0.8, 1.2) else Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide = physical
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = not physical
	handle.CFrame = CFrame.new(0, 1000, 0)
	handle.Parent = m
	if physical then
		handle.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.6, 0.35, 1, 1)
	end
	m.PrimaryPart = handle
	for i, d in w.parts do
		local p = Instance.new("Part")
		p.Name = "P" .. i
		local shape = d.shape
		if shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(d.w, d.h, d.h)
		elseif shape == "ball" then
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(d.w, d.w, d.w)
		else
			p.Size = Vector3.new(d.w, d.h, d.d or 0.4)
		end
		local r, g, b = Util.hexToRGB(d.color)
		p.Color = Color3.fromRGB(r, g, b)
		p.Material = if d.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = handle.CFrame * CFrame.new(d.x, d.y, d.z or 0)
		p.Parent = m
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = handle
		wc.Part1 = p
		wc.Parent = p
	end
	-- tip marker so clients can attach slash trails / muzzle flashes
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Position = Vector3.new(w.length, 0, 0)
	tip.Parent = handle
	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(math.min(0.6, w.length * 0.3), 0, 0)
	base.Parent = handle
	m:SetAttribute("Wid", w.id)
	return m, handle
end

local function hand(f: F): BasePart?
	local h = f.model:FindFirstChild("RightHand") or f.model:FindFirstChild("Right Arm")
	return if h and h:IsA("BasePart") then h else nil
end

function Combat.unequip(f: F, drop: boolean, vel: Vector3?)
	local old = f.model:FindFirstChild("Weapon")
	local wid, ammo = f.wid, f.ammo
	if old then
		old:Destroy()
	end
	f.wid = 0
	f.ammo = 0
	f.discardAt = 0
	f.model:SetAttribute("Wid", 0)
	f.model:SetAttribute("Ammo", 0)
	if drop and wid ~= 0 then
		local h = hand(f)
		local pos = if h then h.Position else f.root.Position
		local w = Weapons.get(wid)
		if w and (ammo > 0 or w.kind == "melee") then
			Combat.spawnPickup(wid, pos, vel or Vector3.new(0, 20, 0), ammo, f.fid)
		end
	end
	sendAll({ t = "Unequip", fid = f.fid })
end

function Combat.equip(f: F, wid: number, ammo: number?)
	local w = Weapons.get(wid)
	if not w then
		return
	end
	local old = f.model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	f.wid = wid
	f.ammo = ammo or w.ammo
	f.discardAt = 0
	f.model:SetAttribute("Wid", wid)
	f.model:SetAttribute("Ammo", f.ammo)
	local h = hand(f)
	if not h then
		return
	end
	local m, handle = Combat.buildWeaponModel(w, false)
	m:PivotTo(h.CFrame * GRIP)
	local weld = Instance.new("Weld")
	weld.Part0 = h
	weld.Part1 = handle
	weld.C0 = GRIP
	weld.Parent = handle
	m.Parent = f.model
	sendAll({ t = "Equip", fid = f.fid, wid = wid })
end

local function setAmmo(f: F, ammo: number)
	f.ammo = ammo
	f.model:SetAttribute("Ammo", ammo)
	local w = Weapons.get(f.wid)
	if ammo <= 0 and w and w.kind ~= "melee" and w.kind ~= "throwable" then
		f.discardAt = clock() + 0.45
	end
end

-------------------------------------------------------------------------------
-- pickups

function Combat.spawnPickup(wid: number, pos: Vector3, vel: Vector3, ammo: number?, thrownBy: number?)
	local w = Weapons.get(wid)
	if not w then
		return
	end
	local m, handle = Combat.buildWeaponModel(w, true)
	m.Name = "Pickup_" .. w.key
	m:PivotTo(CFrame.new(pos.X, pos.Y, 0) * CFrame.Angles(0, 0, math.random() * math.pi * 2))
	if not thrownBy then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 0.85
		hl.FillColor = Color3.new(1, 1, 1)
		hl.OutlineColor = Color3.fromRGB(255, 240, 160)
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 240, 160)
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = handle
	end
	m:SetAttribute("Pickup", true)
	m.Parent = folder("Pickups")
	handle.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y, 0)
	handle.AssemblyAngularVelocity = Vector3.new(0, 0, (math.random() - 0.5) * 16)
	pcall(function()
		handle:SetNetworkOwner(nil)
	end)
	table.insert(pickups, {
		model = m,
		handle = handle,
		wid = wid,
		ammo = if ammo then ammo else w.ammo,
		born = clock(),
		thrownBy = thrownBy or 0,
		thrownAt = if thrownBy then clock() else 0,
		dangerous = thrownBy ~= nil and vel.Magnitude > 30,
	})
end

function Combat.groundWeaponCount(): number
	local n = 0
	for _, p in pickups do
		if p.thrownBy == 0 then
			n += 1
		end
	end
	return n
end

local function lockBody(part: BasePart)
	local p = part.Position
	local cf = part.CFrame
	local tilted = math.abs(cf.LookVector.Z) < 0.97
	if math.abs(p.Z) > 0.05 or tilted then
		local rv = cf.RightVector
		local a = math.atan2(rv.Y, rv.X)
		part.CFrame = CFrame.new(p.X, p.Y, 0) * CFrame.Angles(0, 0, a)
	end
	local v = part.AssemblyLinearVelocity
	local w = part.AssemblyAngularVelocity
	if math.abs(v.Z) > 0.01 or math.abs(w.X) > 0.01 or math.abs(w.Y) > 0.01 then
		part.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
		part.AssemblyAngularVelocity = Vector3.new(0, 0, w.Z)
	end
end

local function updatePickups(_dt: number)
	local now = clock()
	local map = Arena.map
	for i = #pickups, 1, -1 do
		local p = pickups[i]
		local h = p.handle
		if not p.model.Parent or not h.Parent then
			table.remove(pickups, i)
			continue
		end
		lockBody(h)
		local pos = h.Position
		local speed = h.AssemblyLinearVelocity.Magnitude
		local w = Weapons.get(p.wid)
		local expired = now - p.born > Config.WEAPON_DESPAWN or (map and pos.Y < map.killY - 15)
		if p.ammo <= 0 and w and w.kind ~= "melee" and now - p.born > 1.5 then
			expired = true
		end
		if expired then
			p.model:Destroy()
			table.remove(pickups, i)
			continue
		end
		-- thrown weapons hurt
		if p.dangerous then
			if speed < 28 then
				p.dangerous = false
			else
				for _, f in Combat.fighters do
					if f.alive and (f.fid ~= p.thrownBy or now - p.thrownAt > 0.45) and Combat.distToBody(f, pos) < 2.6 then
						local v = h.AssemblyLinearVelocity
						local s = math.clamp(speed / 80, 0.5, 1.3)
						Combat.damage(f, p.thrownBy, {
							damage = Weapons.THROWN.damage * s,
							dir = Vector3.new(v.X, v.Y, 0).Unit,
							knock = Weapons.THROWN.knock * s,
							up = 0.35,
							ragdoll = Weapons.THROWN.ragdoll,
							kind = "thrown",
							pos = pos,
						})
						h.AssemblyLinearVelocity = Vector3.new(-v.X * 0.25, math.abs(v.Y) * 0.2 + 14, 0)
						p.dangerous = false
						break
					end
				end
			end
		end
		-- auto pickup for empty hands
		if not p.dangerous and (p.ammo > 0 or (w and w.kind == "melee")) then
			for _, f in Combat.fighters do
				if f.alive and f.wid == 0 and not Combat.isRagdoll(f) and (f.fid ~= p.thrownBy or now - p.thrownAt > 0.7) then
					if (f.root.Position - pos).Magnitude < Config.PICKUP_RADIUS + 0.8 then
						Combat.equip(f, p.wid, p.ammo)
						sendAll({ t = "Picked", fid = f.fid, wid = p.wid })
						p.model:Destroy()
						table.remove(pickups, i)
						break
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- damage + knockback

function Combat.knock(f: F, vel: Vector3, ragdoll: number)
	f.lastKnock = vel
	if ragdoll > 0 and f.alive then
		Rig.setRagdoll(f.model, true)
		f.ragdollUntil = math.max(f.ragdollUntil, clock() + ragdoll)
	end
	local floppy = ragdoll > 0 or not f.alive or Combat.isRagdoll(f)
	if f.player then
		Event:FireClient(f.player, { t = "Knock", vx = vel.X, vy = vel.Y, ragdoll = ragdoll, floppy = floppy })
	else
		if floppy then
			if f.alive then
				f.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
			Rig.fling(f.model, vel, (math.random() - 0.5) * 14)
		elseif f.knockLV then
			f.knockLV.VectorVelocity = vel
			f.knockLV.Enabled = true
			f.knockUntil = clock() + Config.KNOCK_TIME
		end
	end
end

export type HitInfo = {
	damage: number,
	dir: Vector3,
	knock: number,
	up: number?,
	ragdoll: number?,
	kind: string,
	pos: Vector3?,
	headshot: boolean?,
	wid: number?,
}

function Combat.damage(victim: F, attackerFid: number, info: HitInfo)
	if not Combat.hooks.active() then
		return
	end
	local dir = info.dir
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 1, 0)
	end
	local damage, knock, ragdoll = info.damage, info.knock, info.ragdoll or 0
	local kind = info.kind
	local blocked, parried, deflected = false, false, false
	local facing = Combat.facing(victim)
	local fromFront = dir.X * facing < 0.2

	if victim.alive and victim.blocking and fromFront and not Combat.isRagdoll(victim) then
		if kind == "punch" or kind == "melee" or kind == "thrown" then
			blocked = true
			damage *= (1 - Config.BLOCK_REDUCTION)
			knock *= 0.35
			ragdoll = 0
			parried = kind ~= "thrown" and clock() - victim.blockStart < Config.PARRY_WINDOW
		elseif kind == "bullet" then
			local w = Weapons.get(victim.wid)
			if w and w.deflect then
				deflected = true
				damage, knock, ragdoll = 0, knock * 0.2, 0
			end
		end
	end

	local pos = info.pos or victim.root.Position
	if not victim.alive then
		Combat.knock(victim, dir * knock + Vector3.new(0, (info.up or 0.35) * knock, 0), 0)
		return
	end

	local hp = math.max(0, victim.humanoid.Health - damage)
	if damage > 0 and attackerFid ~= victim.fid and attackerFid ~= 0 then
		victim.lastHitBy = attackerFid
		victim.lastHitTime = clock()
	end
	victim.stagger += damage
	if victim.stagger >= Config.STAGGER_LIMIT and ragdoll == 0 and not blocked then
		ragdoll = 0.9
		victim.stagger = 0
	end
	local vel = dir * knock + Vector3.new(0, (info.up or 0.35) * knock, 0)
	if hp <= 0 then
		victim.deathCause = kind
		victim.lastKnock = vel
	end
	Combat.knock(victim, vel, if hp <= 0 then 0 else ragdoll)

	if parried then
		local att = Combat.fighters[attackerFid]
		if att and att.alive then
			Combat.knock(att, Vector3.new(-dir.X * 45, 30, 0), 0.9)
			sendAll({ t = "Parry", fid = victim.fid, attacker = attackerFid })
		end
	end
	if deflected then
		sendAll({ t = "Deflect", fid = victim.fid, x = pos.X, y = pos.Y })
		local att = Combat.fighters[attackerFid]
		if att and att.alive and att ~= victim and info.wid then
			-- the bullet comes right back at the shooter
			task.delay(0.08, function()
				if att.alive then
					Combat.damage(att, victim.fid, { damage = info.damage * 0.5, dir = -dir, knock = info.knock, up = 0.25, kind = "deflected", pos = Combat.shoulder(att) })
				end
			end)
		end
	end

	sendAll({
		t = "Hit",
		fid = victim.fid,
		attacker = attackerFid,
		x = pos.X,
		y = pos.Y,
		damage = math.floor(damage + 0.5),
		hp = math.floor(hp + 0.5),
		blocked = blocked,
		parried = parried,
		deflected = deflected,
		headshot = info.headshot == true,
		kind = kind,
		kx = vel.X,
		ky = vel.Y,
		ragdoll = ragdoll,
	})
	victim.humanoid.Health = hp
end

function Combat.kill(f: F, cause: string)
	if not f.alive then
		return
	end
	f.deathCause = cause
	f.humanoid.Health = 0
end

-- called from Humanoid.Died
function Combat.onDied(f: F)
	if not f.alive then
		return
	end
	f.alive = false
	f.model:SetAttribute("Alive", false)
	Rig.setRagdoll(f.model, true)
	local vel = f.lastKnock or Vector3.new(0, 30, 0)
	if f.wid ~= 0 then
		Combat.unequip(f, true, vel * 0.5 + Vector3.new(0, 15, 0))
	end
	Combat.knock(f, vel, 0)
	local killer = if clock() - f.lastHitTime < 5 then f.lastHitBy else 0
	sendAll({ t = "Died", fid = f.fid, killer = killer, cause = f.deathCause })
	Combat.hooks.onDeath(f, killer, f.deathCause)
end

function Combat.explode(pos: Vector3, w: Weapons.Weapon, ownerFid: number)
	sendAll({ t = "Boom", x = pos.X, y = pos.Y, r = w.radius, wid = w.id })
	for _, f in Combat.fighters do
		local d = Combat.distToBody(f, pos)
		if d < w.radius then
			local fall = 1 - (d / w.radius) * 0.7
			local to = f.root.Position - pos
			local dir = Vector3.new(to.X, to.Y + 1.5, 0)
			dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 1, 0)
			Combat.damage(f, ownerFid, {
				damage = w.damage * fall * (if f.fid == ownerFid then 0.5 else 1),
				dir = dir,
				knock = w.knock * fall,
				up = 0.3,
				ragdoll = w.ragdoll * fall,
				kind = "explosion",
				pos = pos,
			})
		end
	end
	for _, p in pickups do
		local to = p.handle.Position - pos
		if to.Magnitude < w.radius then
			p.handle.AssemblyLinearVelocity += Vector3.new(to.X, to.Y + 3, 0).Unit * 60
		end
	end
end

-------------------------------------------------------------------------------
-- projectiles

function Combat.launch(f: F, w: Weapons.Weapon, aim: number)
	local dir = Vector3.new(math.cos(aim), math.sin(aim), 0)
	local origin = Combat.shoulder(f) + dir * 2.2
	local hit = workspace:Raycast(Combat.shoulder(f), dir * 2.4, Combat.rayParams({ f.model }))
	if hit then
		origin = hit.Position - dir * 0.4
	end
	local p = Instance.new("Part")
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local kind = if w.kind == "launcher" then "rocket" else "grenade"
	if kind == "rocket" then
		p.Name = "Rocket"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(1.8, 0.7, 0.7)
		p.Color = Color3.fromRGB(76, 107, 58)
		p.CanCollide = false
		p.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, aim)
		local att = Instance.new("Attachment")
		att.Parent = p
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = att
		lv.MaxForce = 1e7
		lv.VectorVelocity = dir * w.speed
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.Parent = p
		local nose = Instance.new("Part")
		nose.Shape = Enum.PartType.Ball
		nose.Size = Vector3.new(0.75, 0.75, 0.75)
		nose.Color = Color3.fromRGB(255, 77, 94)
		nose.Material = Enum.Material.Neon
		nose.CanCollide = false
		nose.CanQuery = false
		nose.Massless = true
		nose.CFrame = p.CFrame * CFrame.new(0.9, 0, 0)
		nose.Parent = p
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = p
		wc.Part1 = nose
		wc.Parent = nose
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 80)
		light.Range = 12
		light.Brightness = 3
		light.Parent = p
		p.AssemblyLinearVelocity = dir * w.speed
	else
		p.Name = "Grenade"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(1.1, 1.1, 1.1)
		p.Color = Color3.fromRGB(47, 158, 68)
		p.Material = Enum.Material.SmoothPlastic
		p.CustomPhysicalProperties = PhysicalProperties.new(2, 0.5, 0.55, 1, 1)
		p.CFrame = CFrame.new(origin)
		local spark = Instance.new("ParticleEmitter")
		spark.Rate = 40
		spark.Lifetime = NumberRange.new(0.2, 0.4)
		spark.Speed = NumberRange.new(3, 6)
		spark.SpreadAngle = Vector2.new(60, 60)
		spark.Size = NumberSequence.new(0.25, 0)
		spark.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
		spark.LightEmission = 1
		spark.Parent = p
		local v = f.root.AssemblyLinearVelocity
		p.AssemblyLinearVelocity = dir * w.speed + Vector3.new(v.X * 0.4, 12, 0)
		p.AssemblyAngularVelocity = Vector3.new(0, 0, -f.aim * 10)
	end
	p.Parent = folder("Projectiles")
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	table.insert(projectiles, { part = p, kind = kind, wid = w.id, owner = f.fid, born = clock(), fuse = w.fuse, last = origin })
	sendAll({ t = "Launch", fid = f.fid, wid = w.id, kind = kind, x = origin.X, y = origin.Y })
end

local function updateProjectiles(dt: number)
	local now = clock()
	for i = #projectiles, 1, -1 do
		local pr = projectiles[i]
		local p = pr.part
		if not p.Parent then
			table.remove(projectiles, i)
			continue
		end
		local w = Weapons.get(pr.wid) :: Weapons.Weapon
		local pos = p.Position
		local boom: Vector3? = nil
		if pr.kind == "rocket" then
			local owner = Combat.fighters[pr.owner]
			local ex = { p }
			if owner and now - pr.born < 0.3 then
				table.insert(ex, owner.model)
			end
			local delta = pos - pr.last
			if delta.Magnitude > 0.01 then
				local hit = workspace:Raycast(pr.last, delta, Combat.rayParams(ex))
				if hit then
					local victim = Combat.fromModel(hit.Instance)
					if not victim or victim.fid ~= pr.owner or now - pr.born > 0.3 then
						boom = hit.Position
					end
				end
			end
			if not boom then
				for _, f in Combat.fighters do
					if f.alive and (f.fid ~= pr.owner or now - pr.born > 0.3) and Combat.distToBody(f, pos) < 2.2 then
						boom = pos
						break
					end
				end
			end
			if now - pr.born > 5 then
				boom = pos
			end
			-- keep it in the plane
			if math.abs(pos.Z) > 0.05 then
				p.CFrame = CFrame.new(pos.X, pos.Y, 0) * p.CFrame.Rotation
			end
		else
			lockBody(p)
			pr.fuse -= dt
			if pr.fuse <= 0 then
				boom = pos
			end
		end
		pr.last = p.Position
		local map = Arena.map
		if map and pos.Y < map.killY - 20 then
			p:Destroy()
			table.remove(projectiles, i)
			continue
		end
		if boom then
			p:Destroy()
			table.remove(projectiles, i)
			Combat.explode(boom, w, pr.owner)
		end
	end
end

-------------------------------------------------------------------------------
-- attacks (shared by bots and validated player requests)

local function act(f: F, kind: string, extra: any?)
	f.lastAction[kind] = clock()
	local msg = { t = "Act", fid = f.fid, kind = kind }
	if extra then
		for k, v in extra do
			msg[k] = v
		end
	end
	sendOthers(f.player, msg)
end
Combat.act = act

local function meleeKnockDir(att: F, victim: F, aimDir: Vector3): Vector3
	local dx = victim.root.Position.X - att.root.Position.X
	local sx = if dx >= 0 then 1 else -1
	return Vector3.new(sx * math.max(0.6, math.abs(aimDir.X)), math.clamp(aimDir.Y, -0.3, 0.8), 0).Unit
end

function Combat.applyMelee(att: F, victim: F, kind: string, aimDir: Vector3, pos: Vector3?)
	local t = clock()
	if (att.meleeHits[victim.fid] or 0) > t - 0.15 then
		return
	end
	att.meleeHits[victim.fid] = t
	local dir = meleeKnockDir(att, victim, aimDir)
	if kind == "punch" then
		Combat.damage(victim, att.fid, { damage = Config.PUNCH_DAMAGE, dir = dir, knock = Config.PUNCH_KNOCK, up = 0.45, ragdoll = 0, kind = "punch", pos = pos })
	else
		local w = Weapons.get(att.wid)
		if not w or w.kind ~= "melee" then
			return
		end
		Combat.damage(victim, att.fid, { damage = w.damage, dir = dir, knock = w.knock, up = 0.4, ragdoll = w.ragdoll, kind = "melee", pos = pos, wid = w.id })
	end
end

-- server-side melee query (bots)
local function meleeVictims(att: F, center: Vector3, radius: number): { F }
	local out = {}
	for _, o in Combat.fighters do
		if o ~= att and o.alive and Combat.distToBody(o, center) < radius then
			table.insert(out, o)
		end
	end
	return out
end

function Combat.botPunch(f: F, hand: string)
	act(f, "punch", { hand = hand })
	task.delay(0.08, function()
		if not f.alive or Combat.isRagdoll(f) then
			return
		end
		local dir = Combat.aimDir(f)
		local center = Combat.shoulder(f) + dir * Config.PUNCH_REACH
		for _, v in meleeVictims(f, center, Config.PUNCH_RADIUS) do
			Combat.applyMelee(f, v, "punch", dir, center)
		end
	end)
end

function Combat.botSwing(f: F)
	local w = Weapons.get(f.wid)
	if not w then
		return
	end
	act(f, "swing")
	for _, delay in { 0.06, 0.13 } do
		task.delay(delay, function()
			if not f.alive or Combat.isRagdoll(f) then
				return
			end
			local dir = Combat.aimDir(f)
			local center = Combat.shoulder(f) + dir * (w.length * 0.6 + 1.2)
			for _, v in meleeVictims(f, center, w.length * 0.55 + 1.6) do
				Combat.applyMelee(f, v, "melee", dir, center)
			end
		end)
	end
end

function Combat.muzzle(f: F, w: Weapons.Weapon, aim: number): Vector3
	local dir = Vector3.new(math.cos(aim), math.sin(aim), 0)
	local sh = Combat.shoulder(f)
	local reach = 1.9 + w.length * 0.8
	local hit = workspace:Raycast(sh, dir * reach, Combat.rayParams({ f.model }))
	if hit then
		return hit.Position - dir * 0.3
	end
	return sh + dir * reach
end

-- server-simulated gun shot (bots)
function Combat.botShoot(f: F)
	local w = Weapons.get(f.wid)
	if not w or f.ammo <= 0 then
		return
	end
	setAmmo(f, f.ammo - 1)
	local seed = math.random(1, 1e6)
	local origin = Combat.muzzle(f, w, f.aim)
	local ends = {}
	local rp = Combat.rayParams({ f.model })
	for _, a in Weapons.angles(w, f.aim, seed) do
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local hit = workspace:Raycast(origin, dir * w.range, rp)
		local endPos = if hit then hit.Position else origin + dir * w.range
		table.insert(ends, { endPos.X, endPos.Y })
		if hit then
			local victim = Combat.fromModel(hit.Instance)
			if victim and victim ~= f then
				local head = hit.Instance.Name == "Head"
				Combat.damage(victim, f.fid, {
					damage = w.damage * (if head then w.headMult else 1),
					dir = dir,
					knock = w.knock,
					up = 0.25,
					ragdoll = w.ragdoll,
					kind = "bullet",
					pos = hit.Position,
					headshot = head,
					wid = w.id,
				})
			end
		end
	end
	if w.recoil > 0 then
		Combat.knock(f, -Vector3.new(math.cos(f.aim), math.sin(f.aim), 0) * w.recoil * 0.6, 0)
	end
	sendAll({ t = "Shot", fid = f.fid, wid = w.id, x = origin.X, y = origin.Y, ends = ends })
end

function Combat.throwWeapon(f: F, aim: number)
	local w = Weapons.get(f.wid)
	if not w then
		return
	end
	local ammo = f.ammo
	local dir = Vector3.new(math.cos(aim), math.sin(aim), 0)
	local v = f.root.AssemblyLinearVelocity
	local vel = dir * Config.THROW_SPEED + Vector3.new(v.X * 0.5, 8, 0)
	local h = hand(f)
	local pos = if h then h.Position else Combat.shoulder(f)
	local old = f.model:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	f.wid = 0
	f.ammo = 0
	f.discardAt = 0
	f.model:SetAttribute("Wid", 0)
	f.model:SetAttribute("Ammo", 0)
	sendAll({ t = "Unequip", fid = f.fid })
	act(f, "throw")
	if ammo > 0 or w.kind == "melee" then
		Combat.spawnPickup(w.id, Vector3.new(pos.X, pos.Y, 0), vel, ammo, f.fid)
	else
		-- empty guns still make decent projectiles
		Combat.spawnPickup(w.id, Vector3.new(pos.X, pos.Y, 0), vel, 0, f.fid)
	end
end

function Combat.botLaunch(f: F)
	local w = Weapons.get(f.wid)
	if not w or f.ammo <= 0 then
		return
	end
	setAmmo(f, f.ammo - 1)
	act(f, if w.kind == "throwable" then "lob" else "fire")
	Combat.launch(f, w, f.aim)
	if w.recoil > 0 then
		Combat.knock(f, -Combat.aimDir(f) * w.recoil * 0.6, 0)
	end
	if w.kind == "throwable" and f.ammo <= 0 then
		Combat.unequip(f, false)
	end
end

-------------------------------------------------------------------------------
-- validated player requests

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and math.abs(v) < 1e6 then
		return v
	end
	return default
end
Combat.num = num

function Combat.onAct(f: F, msg: any)
	local kind = msg.kind
	if kind ~= "punch" and kind ~= "swing" and kind ~= "djump" and kind ~= "lob" and kind ~= "fire" then
		return
	end
	if not f.alive then
		return
	end
	act(f, kind, { hand = if msg.hand == "L" then "L" else "R" })
end

function Combat.onHit(f: F, msg: any)
	if not f.alive or Combat.isRagdoll(f) then
		return
	end
	local victim = Combat.fighters[num(msg.victim, -1)]
	if not victim or victim == f then
		return
	end
	local kind = msg.kind
	local t = clock()
	local dir = Vector3.new(num(msg.dx, 1), num(msg.dy, 0), 0)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(Combat.facing(f), 0, 0)
	local dist = (victim.root.Position - f.root.Position).Magnitude
	if kind == "punch" then
		if t - (f.lastAction.punch or 0) > 0.6 or dist > Config.PUNCH_REACH + Config.PUNCH_RADIUS + 5 then
			return
		end
	elseif kind == "melee" then
		local w = Weapons.get(f.wid)
		if not w or w.kind ~= "melee" or t - (f.lastAction.swing or 0) > 0.7 or dist > w.length + 7 then
			return
		end
	else
		return
	end
	Combat.applyMelee(f, victim, kind, dir, Vector3.new(num(msg.x, victim.root.Position.X), num(msg.y, victim.root.Position.Y), 0))
end

function Combat.onShoot(f: F, msg: any)
	if not f.alive then
		return
	end
	local w = Weapons.get(f.wid)
	if not w or w.kind ~= "gun" or w.id ~= num(msg.wid, -1) or f.ammo <= 0 then
		return
	end
	local t = clock()
	if t - f.lastShot < w.rate * 0.6 then
		return
	end
	f.lastShot = t
	setAmmo(f, f.ammo - 1)
	local aim = num(msg.aim, f.aim)
	local seed = math.floor(num(msg.seed, 0))
	local ox, oy = num(msg.x, f.root.Position.X), num(msg.y, f.root.Position.Y)
	local origin = Vector3.new(ox, oy, 0)
	if (origin - f.root.Position).Magnitude > 12 then
		origin = Combat.muzzle(f, w, aim)
	end
	-- hits reported by the shooter, sanity checked
	local hits = if type(msg.hits) == "table" then msg.hits else {}
	local angles = Weapons.angles(w, aim, seed)
	local used = 0
	for _, h in hits do
		used += 1
		if used > w.pellets then
			break
		end
		if type(h) ~= "table" then
			continue
		end
		local victim = Combat.fighters[num(h.fid, -1)]
		if not victim or victim == f or not victim.alive then
			continue
		end
		local hp = Vector3.new(num(h.x, 0), num(h.y, 0), 0)
		local toVictim = (victim.root.Position - origin)
		if toVictim.Magnitude > w.range + 10 or (hp - victim.root.Position).Magnitude > 8 then
			continue
		end
		local a = angles[math.clamp(math.floor(num(h.i, 1)), 1, #angles)] or aim
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local head = h.head == true
		Combat.damage(victim, f.fid, {
			damage = w.damage * (if head then w.headMult else 1),
			dir = dir,
			knock = w.knock,
			up = 0.25,
			ragdoll = w.ragdoll,
			kind = "bullet",
			pos = hp,
			headshot = head,
			wid = w.id,
		})
	end
	local ends = if type(msg.ends) == "table" then msg.ends else {}
	if #ends > w.pellets then
		ends = {}
	end
	sendOthers(f.player, { t = "Shot", fid = f.fid, wid = w.id, x = origin.X, y = origin.Y, ends = ends })
end

function Combat.onLaunch(f: F, msg: any)
	if not f.alive or Combat.isRagdoll(f) then
		return
	end
	local w = Weapons.get(f.wid)
	if not w or (w.kind ~= "launcher" and w.kind ~= "throwable") or f.ammo <= 0 then
		return
	end
	local t = clock()
	if t - f.lastShot < w.rate * 0.6 then
		return
	end
	f.lastShot = t
	f.aim = num(msg.aim, f.aim)
	setAmmo(f, f.ammo - 1)
	act(f, if w.kind == "throwable" then "lob" else "fire")
	Combat.launch(f, w, f.aim)
	if w.kind == "throwable" and f.ammo <= 0 then
		Combat.unequip(f, false)
	end
end

function Combat.onThrow(f: F, msg: any)
	if not f.alive or f.wid == 0 then
		return
	end
	Combat.throwWeapon(f, num(msg.aim, f.aim))
end

function Combat.onState(f: F, aim: number, flags: number)
	f.aim = aim
	local blocking = bit32.band(flags, 1) ~= 0
	if blocking and not f.blocking then
		f.blockStart = clock()
	end
	f.blocking = blocking
	f.crouch = bit32.band(flags, 2) ~= 0
end

-------------------------------------------------------------------------------
-- per frame

function Combat.update(dt: number, roundT: number)
	local now = clock()
	local map = Arena.map
	for _, f in Combat.fighters do
		if not f.model.Parent then
			continue
		end
		f.stagger = math.max(0, f.stagger - Config.STAGGER_DECAY * dt)
		f.hazardCd = math.max(0, f.hazardCd - dt)
		-- bots are server owned: keep them on the plane + end knockbacks
		if not f.player then
			Rig.lockPlane(f.model, f.root, if Combat.isRagdoll(f) or not f.alive then Rig.bodyParts(f.model) else nil)
			if f.knockLV and f.knockLV.Enabled and now > f.knockUntil then
				f.knockLV.Enabled = false
			end
		end
		if f.alive then
			-- get back up
			if f.ragdollUntil > 0 and now > f.ragdollUntil then
				f.ragdollUntil = 0
				Rig.setRagdoll(f.model, false)
				if f.player then
					Event:FireClient(f.player, { t = "GetUp" })
				else
					f.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end
			-- empty guns get tossed
			if f.discardAt > 0 and now > f.discardAt then
				f.discardAt = 0
				if f.wid ~= 0 and f.ammo <= 0 then
					Combat.throwWeapon(f, f.aim)
				end
			end
			local pos = f.root.Position
			if map then
				local floor = math.max(map.killY, Arena.inkY)
				if pos.Y < floor or pos.X < map.bounds.left - 45 or pos.X > map.bounds.right + 45 then
					Combat.kill(f, "fell")
					continue
				end
			end
			if f.hazardCd <= 0 and Combat.hooks.active() then
				local kind, n = Arena.hazardAt(pos, 1.6, roundT)
				if not kind then
					local head = f.model:FindFirstChild("Head") :: BasePart?
					if head then
						kind, n = Arena.hazardAt(head.Position, 0.8, roundT)
					end
				end
				if kind then
					f.hazardCd = 0.5
					Combat.damage(f, if now - f.lastHitTime < 4 then f.lastHitBy else 0, {
						damage = if kind == "saw" then 22 else 30,
						dir = n,
						knock = if kind == "saw" then 75 else 55,
						up = if kind == "saw" then 0.3 else 0.6,
						ragdoll = 0.8,
						kind = kind,
						pos = pos,
					})
					sendAll({ t = "Hazard", fid = f.fid, kind = kind, x = pos.X, y = pos.Y })
				end
			end
		end
	end
	updatePickups(dt)
	updateProjectiles(dt)
end

function Combat.reset()
	for _, p in pickups do
		p.model:Destroy()
	end
	pickups = {}
	for _, p in projectiles do
		p.part:Destroy()
	end
	projectiles = {}
	folder("Pickups"):ClearAllChildren()
	folder("Projectiles"):ClearAllChildren()
	for fid, f in Combat.fighters do
		if f.isBot and f.model.Parent then
			f.model:Destroy()
		end
		Combat.fighters[fid] = nil
	end
end

function Combat.register(f: F)
	Combat.fighters[f.fid] = f
	f.humanoid.Died:Connect(function()
		Combat.onDied(f)
	end)
end

function Combat.unregister(fid: number)
	Combat.fighters[fid] = nil
end

function Combat.newFighter(fid: number, name: string, colorIndex: number, model: Model, player: Player?): F
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local knock = root:FindFirstChild("Knock") :: LinearVelocity?
	return {
		fid = fid,
		name = name,
		colorIndex = colorIndex,
		model = model,
		humanoid = humanoid,
		root = root,
		player = player,
		isBot = player == nil,
		alive = true,
		wid = 0,
		ammo = 0,
		aim = if root.CFrame.LookVector.X >= 0 then 0 else math.pi,
		blocking = false,
		crouch = false,
		blockStart = 0,
		stagger = 0,
		lastHitBy = 0,
		lastHitTime = -100,
		ragdollUntil = 0,
		knockUntil = 0,
		knockLV = knock,
		deathCause = "ko",
		hazardCd = 0,
		lastAction = {},
		lastShot = 0,
		meleeHits = {},
		discardAt = 0,
		hitBudget = 0,
		brain = nil,
		lastKnock = Vector3.new(0, 30, 0),
	}
end

return Combat
