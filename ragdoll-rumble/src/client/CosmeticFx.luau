--!strict
-- Finisher (KO) and entrance (spawn) effects. Built from the Blender VFX meshes
-- (stars, rings, skulls, bolts, rocks, halos) when available, else neon parts.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = require(script.Parent:WaitForChild("Effects"))
local Skins = require(script.Parent:WaitForChild("Skins"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local CameraRig = require(script.Parent:WaitForChild("CameraRig"))

local Fx = {}

type Obj = {
	inst: Instance,
	parts: { BasePart },
	base: { [BasePart]: number },
	pos: Vector3,
	vel: Vector3,
	grav: number,
	rot: CFrame,
	spinAxis: Vector3,
	spin: number,
	scale0: number,
	scale1: number,
	size0: { [BasePart]: Vector3 },
	life: number,
	max: number,
	fadeAt: number,
	pull: Vector3?,
	hue: boolean,
}

local live: { Obj } = {}

local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end

-- spawn a mesh (or a fallback neon part) that moves / spins / grows / fades
local function obj(mesh: string?, pos: Vector3, scale: number, life: number, o: any?): Obj
	local opts = o or {}
	local inst: Instance
	local parts: { BasePart } = {}
	local m = if mesh then Skins.clone(mesh, CFrame.new(), 1) else nil
	if m then
		inst = m
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				p.Anchored = true
				table.insert(parts, p)
				if opts.color and p.Material == Enum.Material.Neon then
					p.Color = opts.color
				end
			end
		end
	else
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = opts.material or Enum.Material.Neon
		p.Color = opts.color or Color3.new(1, 1, 1)
		local shape = opts.shape or "ball"
		if shape == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "disc" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = opts.size or Vector3.new(1, 1, 1)
		inst = p
		table.insert(parts, p)
	end
	inst.Parent = Effects.folder()
	local base, size0 = {}, {}
	for _, p in parts do
		base[p] = opts.transparency or p.Transparency
		size0[p] = p.Size
	end
	local ob: Obj = {
		inst = inst,
		parts = parts,
		base = base,
		pos = pos,
		vel = opts.vel or Vector3.zero,
		grav = opts.grav or 0,
		rot = opts.rot or CFrame.identity,
		spinAxis = opts.axis or Vector3.zAxis,
		spin = opts.spin or 0,
		scale0 = scale,
		scale1 = opts.scaleTo or scale,
		size0 = size0,
		life = life,
		max = life,
		fadeAt = opts.fadeAt or 0.6,
		pull = opts.pull,
		hue = opts.hue == true,
	}
	table.insert(live, ob)
	return ob
end

RunService.RenderStepped:Connect(function(dt)
	for i = #live, 1, -1 do
		local o = live[i]
		o.life -= dt
		if o.life <= 0 or not o.inst.Parent then
			o.inst:Destroy()
			table.remove(live, i)
			continue
		end
		local k = 1 - o.life / o.max
		if o.pull then
			local to = (o.pull :: Vector3) - o.pos
			o.vel += to * dt * 12
		end
		o.vel -= Vector3.new(0, o.grav * dt, 0)
		o.pos += o.vel * dt
		o.rot *= CFrame.fromAxisAngle(o.spinAxis, o.spin * dt)
		local s = o.scale0 + (o.scale1 - o.scale0) * (1 - (1 - k) ^ 3)
		local fade = if k > o.fadeAt then (k - o.fadeAt) / (1 - o.fadeAt) else 0
		local cf = CFrame.new(o.pos) * o.rot
		for _, p in o.parts do
			p.Size = o.size0[p] * s
			p.Transparency = o.base[p] + (1 - o.base[p]) * fade
			if o.hue then
				p.Color = Color3.fromHSV((os.clock() * 0.8 + k) % 1, 0.7, 1)
			end
		end
		if o.inst:IsA("Model") then
			(o.inst :: Model):PivotTo(cf)
		else
			(o.inst :: BasePart).CFrame = cf
		end
	end
end)

-- jagged lightning between two points
local function bolt(from: Vector3, to: Vector3, color: Color3, width: number?)
	local segs = 9
	local prev = from
	local w = width or 0.45
	for i = 1, segs do
		local p = from:Lerp(to, i / segs)
		if i < segs then
			p += Vector3.new(rand(-2.2, 2.2), 0, rand(-0.5, 0.5))
		end
		local d = p - prev
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Size = Vector3.new(w, w, d.Magnitude + 0.2)
		part.CFrame = CFrame.lookAt(prev + d * 0.5, p)
		part.Parent = Effects.folder()
		TweenService:Create(part, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		Debris:AddItem(part, 0.4)
		prev = p
	end
end

local function beam(pos: Vector3, height: number, width: number, color: Color3, life: number)
	obj(nil, pos + Vector3.new(0, height * 0.5, -0.5), 1, life, { shape = "block", size = Vector3.new(width, height, width), color = color, transparency = 0.25, scaleTo = 0.15, fadeAt = 0.3 })
end

local function rings(pos: Vector3, color: Color3, n: number, size: number, life: number?)
	for i = 1, n do
		task.delay((i - 1) * 0.12, function()
			obj("fx_ring", pos + Vector3.new(0, 0, 1), size * 0.3, life or 0.6, { color = color, scaleTo = size * (1 + i * 0.4), fadeAt = 0.2, shape = "disc", size = Vector3.new(0.2, 2, 2), rot = CFrame.Angles(0, math.pi / 2, 0) })
		end)
	end
end

local function stars(pos: Vector3, color: Color3?, n: number, speed: number, life: number?)
	for _ = 1, n do
		local a = rand(0, math.pi * 2)
		local c = color or Color3.fromHSV(math.random(), 0.6, 1)
		obj("fx_star", pos, rand(0.35, 0.7), life or rand(0.7, 1.1), {
			vel = Vector3.new(math.cos(a), math.sin(a), 0) * rand(speed * 0.5, speed),
			grav = 30,
			spin = rand(-8, 8),
			color = c,
			scaleTo = 0.1,
			fadeAt = 0.5,
			size = Vector3.new(0.8, 0.8, 0.8),
		})
	end
end

local function cubes(pos: Vector3, color: Color3, n: number, speed: number, glitch: boolean?)
	for _ = 1, n do
		local a = rand(0, math.pi * 2)
		local c = if glitch then (if math.random() < 0.5 then Color3.fromRGB(0, 255, 156) else Color3.new(0, 0, 0)) else color
		obj(nil, pos + Vector3.new(rand(-1, 1), rand(-1.5, 1.5), 0), 1, rand(0.7, 1.3), {
			shape = "block",
			size = Vector3.new(0.55, 0.55, 0.55),
			color = c,
			material = if math.random() < 0.4 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			vel = Vector3.new(math.cos(a), math.sin(a) + 0.6, 0) * rand(speed * 0.4, speed),
			grav = 70,
			spin = rand(-10, 10),
			axis = Vector3.new(rand(-1, 1), rand(-1, 1), rand(-1, 1)).Unit,
			fadeAt = 0.6,
		})
	end
end

-------------------------------------------------------------------------------
-- finishers (play where the victim fell)

local FINISHERS: { [string]: (Vector3, Color3) -> () } = {}

FINISHERS.pop = function(_pos, _color) end

FINISHERS.confetti = function(pos, _color)
	Effects.confetti(pos + Vector3.new(0, 4, 0), 10)
	Audio.play("pickup", 1, 0.8)
	Audio.play("win", 0.6, 1.5)
end

FINISHERS.splash = function(pos, color)
	Effects.paint(pos, Vector3.new(0, 60, 0), color, 40)
	rings(pos, color, 2, 5)
	Audio.play("heavy", 0.8, 1.2)
end

FINISHERS.shockwave = function(pos, color)
	rings(pos, color, 3, 9)
	Effects.dust(pos - Vector3.new(0, 2, 0), 10)
	CameraRig.shake(0.5)
	Audio.play("boom", 0.6, 1.4)
end

FINISHERS.skull = function(pos, color)
	obj("fx_skull", pos + Vector3.new(0, 3, 1.5), 0.1, 1.6, { scaleTo = 2.4, vel = Vector3.new(0, 3, 0), spin = 1.2, axis = Vector3.yAxis, fadeAt = 0.7, color = color, size = Vector3.new(2, 2, 2) })
	Effects.spark(pos, Color3.fromRGB(170, 110, 255), 18, 40)
	Audio.play("ko", 0.8, 1.4)
end

FINISHERS.thunder = function(pos, _color)
	bolt(pos + Vector3.new(rand(-4, 4), 70, 0), pos, Color3.fromRGB(255, 240, 140), 0.6)
	bolt(pos + Vector3.new(rand(-6, 6), 70, 0), pos, Color3.fromRGB(160, 220, 255), 0.3)
	Effects.flash(pos, Color3.new(1, 1, 1), 8, 0.2)
	Effects.spark(pos, Color3.fromRGB(255, 240, 140), 26, 70)
	Effects.dust(pos - Vector3.new(0, 2, 0), 8, Color3.fromRGB(120, 120, 130))
	CameraRig.shake(0.7)
	Audio.play("boom", 0.9, 1.6)
end

FINISHERS.shatter = function(pos, color)
	cubes(pos, color, 34, 45)
	Effects.flash(pos, color, 4, 0.15)
	Audio.play("ko", 0.6, 1.8)
end

FINISHERS.fireworks = function(pos, _color)
	for i = 1, 5 do
		task.delay(i * 0.18, function()
			local c = Color3.fromHSV(math.random(), 0.7, 1)
			local start = pos + Vector3.new(rand(-8, 8), 0, 0)
			local rocket = obj(nil, start, 1, 0.7, { shape = "ball", size = Vector3.new(0.6, 0.6, 0.6), color = c, vel = Vector3.new(rand(-6, 6), 55, 0), grav = 30, fadeAt = 0.95 })
			Audio.play("whoosh", 0.6, 0.8)
			task.delay(0.65, function()
				stars(rocket.pos, c, 14, 26, 1.2)
				Effects.flash(rocket.pos, c, 3, 0.15)
				Audio.play("boom", 0.4, 1.8)
			end)
		end)
	end
end

FINISHERS.supernova = function(pos, _color)
	local gold = Color3.fromRGB(255, 211, 110)
	obj(nil, pos, 1, 0.5, { shape = "ball", size = Vector3.new(6, 6, 6), color = gold, scaleTo = 0.05, fadeAt = 0.95 })
	Audio.play("djump", 1, 0.5)
	task.delay(0.5, function()
		obj(nil, pos, 0.2, 0.7, { shape = "ball", size = Vector3.new(10, 10, 10), color = Color3.new(1, 1, 1), scaleTo = 2.2, fadeAt = 0.2 })
		rings(pos, gold, 3, 14)
		stars(pos, gold, 16, 50, 1.3)
		Effects.spark(pos, gold, 30, 90, 0.6)
		CameraRig.shake(1)
		Audio.play("boom", 1.2, 0.9)
	end)
end

FINISHERS.blackhole = function(pos, _color)
	local purple = Color3.fromRGB(165, 107, 255)
	local core = obj(nil, pos, 0.1, 2.2, { shape = "ball", size = Vector3.new(6, 6, 6), color = Color3.new(0, 0, 0), material = Enum.Material.SmoothPlastic, scaleTo = 1, fadeAt = 0.85 })
	obj("fx_ring", pos + Vector3.new(0, 0, 0.5), 3, 2.2, { color = purple, spin = 4, axis = Vector3.zAxis, scaleTo = 4, fadeAt = 0.85, rot = CFrame.Angles(0.5, 0, 0), shape = "disc", size = Vector3.new(0.2, 2, 2) })
	for i = 1, 40 do
		task.delay(i * 0.04, function()
			local a = rand(0, math.pi * 2)
			local r = rand(10, 16)
			obj(nil, pos + Vector3.new(math.cos(a) * r, math.sin(a) * r, 0), 1, 0.9, { shape = "ball", size = Vector3.new(0.4, 0.4, 0.4), color = if i % 2 == 0 then purple else Color3.new(1, 1, 1), pull = pos, fadeAt = 0.8 })
		end)
	end
	Audio.play("whoosh", 1, 0.4)
	task.delay(2, function()
		core.life = 0.01
		Effects.flash(pos, purple, 9, 0.3)
		rings(pos, purple, 2, 12)
		CameraRig.shake(0.8)
		Audio.play("boom", 1, 0.6)
	end)
end

FINISHERS.rift = function(pos, _color)
	obj(nil, pos + Vector3.new(0, 4, -0.5), 1, 2, { shape = "block", size = Vector3.new(0.8, 16, 0.8), color = Color3.new(1, 1, 1), hue = true, scaleTo = 1.6, fadeAt = 0.6 })
	for i = 1, 4 do
		task.delay(i * 0.2, function()
			obj("fx_ring", pos + Vector3.new(0, 0, 1), 1, 1, { hue = true, scaleTo = 8 + i * 2, fadeAt = 0.3, shape = "disc", size = Vector3.new(0.2, 2, 2), rot = CFrame.Angles(0, math.pi / 2, 0) })
		end)
	end
	stars(pos, nil, 22, 40, 1.4)
	Effects.confetti(pos + Vector3.new(0, 6, 0), 14)
	CameraRig.shake(0.6)
	Audio.play("win", 1, 1.1)
	Audio.play("djump", 1, 0.7)
end

FINISHERS.glitch = function(pos, _color)
	for i = 1, 12 do
		task.delay(i * 0.08, function()
			cubes(pos + Vector3.new(rand(-3, 3), rand(-2, 4), 0), Color3.new(), 4, 20, true)
			if i % 3 == 0 then
				Audio.play("tick", 0.8, rand(0.5, 2.5))
			end
		end)
	end
	Effects.text(pos + Vector3.new(0, 5, 0), "GLITCH.EXE", Color3.fromRGB(0, 255, 156), 40, 1.6)
	task.delay(0.4, function()
		Effects.text(pos + Vector3.new(rand(-3, 3), 3, 0), "ERR", Color3.fromRGB(255, 80, 80), 30, 0.8)
	end)
	Audio.play("deflect", 1, 0.4)
end

-------------------------------------------------------------------------------
-- entrances (play at the spawn point)

local SPAWNS: { [string]: (Vector3, Color3) -> () } = {}

SPAWNS.drop = function(pos, _color)
	Effects.dust(pos - Vector3.new(0, 3, 0), 6)
end

SPAWNS.smoke = function(pos, _color)
	for _ = 1, 3 do
		Effects.dust(pos + Vector3.new(0, rand(-2, 2), 0), 6, Color3.fromRGB(160, 160, 170))
	end
	Audio.play("whoosh", 0.6, 0.6)
end

SPAWNS.paintbomb = function(pos, color)
	Effects.paint(pos, Vector3.new(0, 40, 0), color, 24)
	rings(pos, color, 1, 6)
	Audio.play("heavy", 0.6, 1.3)
end

SPAWNS.sparks = function(pos, color)
	for i = 1, 8 do
		task.delay(i * 0.08, function()
			Effects.spark(pos - Vector3.new(0, 2.5, 0), if i % 2 == 0 then color else Color3.fromRGB(255, 220, 120), 6, 40)
		end)
	end
	Audio.play("pickup", 0.6, 1.2)
end

SPAWNS.rings = function(pos, color)
	for i = 1, 3 do
		task.delay(i * 0.15, function()
			obj("fx_ring", pos + Vector3.new(0, -2.5 + i * 1.6, 0), 1.2, 0.6, { color = color, scaleTo = 2.2, fadeAt = 0.3, rot = CFrame.Angles(math.pi / 2, 0, 0), shape = "disc", size = Vector3.new(0.2, 2.4, 2.4) })
		end)
	end
	Audio.play("djump", 0.6, 1.2)
end

SPAWNS.lightning = function(pos, _color)
	bolt(pos + Vector3.new(rand(-3, 3), 70, 0), pos - Vector3.new(0, 2.5, 0), Color3.fromRGB(160, 220, 255), 0.55)
	Effects.flash(pos, Color3.new(1, 1, 1), 6, 0.2)
	Effects.dust(pos - Vector3.new(0, 2.5, 0), 8)
	CameraRig.shake(0.4)
	Audio.play("boom", 0.6, 1.7)
end

SPAWNS.meteor = function(pos, _color)
	local start = pos + Vector3.new(-30, 60, 0)
	local rock = obj("fx_rock", start, 1.4, 0.6, { vel = (pos - start) / 0.55, spin = 6, axis = Vector3.new(1, 1, 0).Unit, fadeAt = 0.98, color = Color3.fromRGB(255, 120, 40), shape = "ball", size = Vector3.new(2.5, 2.5, 2.5), material = Enum.Material.Slate })
	local trail = true
	task.spawn(function()
		while trail do
			Effects.spark(rock.pos, Color3.fromRGB(255, 140, 40), 3, 10, 0.5)
			task.wait(0.03)
		end
	end)
	Audio.play("whoosh", 1, 0.6)
	task.delay(0.55, function()
		trail = false
		Effects.explosion(pos - Vector3.new(0, 2, 0), 6)
		Effects.dust(pos - Vector3.new(0, 2.5, 0), 12, Color3.fromRGB(120, 100, 90))
		CameraRig.shake(0.6)
		Audio.play("boom", 0.8, 1.2)
	end)
end

SPAWNS.portal = function(pos, color)
	obj("fx_ring", pos + Vector3.new(0, 0, -1), 0.2, 1.4, { color = color, spin = 5, axis = Vector3.zAxis, scaleTo = 3.6, fadeAt = 0.7, rot = CFrame.Angles(0, 0, 0), shape = "disc", size = Vector3.new(0.2, 2, 2) })
	obj(nil, pos + Vector3.new(0, 0, -1.4), 0.2, 1.4, { shape = "disc", size = Vector3.new(0.1, 6.5, 6.5), color = Color3.fromRGB(40, 10, 80), material = Enum.Material.SmoothPlastic, rot = CFrame.Angles(0, math.pi / 2, 0), scaleTo = 1, fadeAt = 0.7 })
	Effects.spark(pos, color, 14, 30)
	Audio.play("djump", 1, 0.6)
end

SPAWNS.angel = function(pos, _color)
	beam(pos - Vector3.new(0, 3, 0), 120, 5, Color3.fromRGB(255, 245, 210), 1.6)
	obj("fx_halo", pos + Vector3.new(0, 3.6, 0), 0.6, 2, { color = Color3.fromRGB(255, 220, 120), spin = 2, axis = Vector3.yAxis, scaleTo = 0.7, fadeAt = 0.8, shape = "disc", size = Vector3.new(0.2, 2, 2) })
	for _ = 1, 16 do
		obj(nil, pos + Vector3.new(rand(-4, 4), rand(4, 10), rand(-1, 1)), 1, rand(1.2, 2), { shape = "block", size = Vector3.new(0.15, 0.7, 0.3), color = Color3.new(1, 1, 1), vel = Vector3.new(rand(-1, 1), -4, 0), spin = rand(-3, 3), fadeAt = 0.6 })
	end
	Audio.play("win", 0.8, 1.6)
end

SPAWNS.void = function(pos, _color)
	local purple = Color3.fromRGB(120, 40, 200)
	obj(nil, pos + Vector3.new(0, 0, -0.8), 1, 1.8, { shape = "block", size = Vector3.new(1.2, 9, 0.6), color = Color3.new(0, 0, 0), material = Enum.Material.SmoothPlastic, scaleTo = 0.1, fadeAt = 0.7 })
	obj(nil, pos + Vector3.new(0, 0, -1), 1, 1.8, { shape = "block", size = Vector3.new(2, 10, 0.4), color = purple, scaleTo = 0.1, fadeAt = 0.6 })
	for _ = 1, 20 do
		local a = rand(0, math.pi * 2)
		obj(nil, pos, 1, rand(0.6, 1.1), { shape = "block", size = Vector3.new(0.3, 0.3, 0.3), color = if math.random() < 0.5 then purple else Color3.new(0, 0, 0), vel = Vector3.new(math.cos(a), math.sin(a), 0) * rand(10, 25), fadeAt = 0.5, spin = 8 })
	end
	CameraRig.shake(0.3)
	Audio.play("whoosh", 1, 0.35)
end

SPAWNS.starfall = function(pos, _color)
	for i = 1, 20 do
		task.delay(i * 0.06, function()
			local start = pos + Vector3.new(rand(-10, 10), rand(20, 30), rand(-1, 1))
			obj("fx_star", start, 0.5, 1.2, { vel = Vector3.new(rand(-4, 4), -40, 0), spin = 6, color = Color3.fromHSV(rand(0.1, 0.2), 0.6, 1), fadeAt = 0.7, size = Vector3.new(0.8, 0.8, 0.8) })
		end)
	end
	stars(pos, nil, 12, 30)
	Audio.play("win", 0.7, 1.3)
end

SPAWNS.error404 = function(pos, _color)
	for i = 1, 10 do
		task.delay(i * 0.06, function()
			cubes(pos + Vector3.new(rand(-2, 2), rand(-2, 3), 0), Color3.new(), 3, 15, true)
		end)
	end
	Effects.text(pos + Vector3.new(0, 5, 0), "404", Color3.fromRGB(0, 255, 156), 48, 1.4)
	Audio.play("deflect", 1, 0.5)
end

function Fx.finisher(id: string?, pos: Vector3, color: Color3)
	local fn = FINISHERS[id or "pop"]
	if fn then
		fn(pos, color)
	end
end

function Fx.entrance(id: string?, pos: Vector3, color: Color3)
	local fn = SPAWNS[id or "drop"]
	if fn then
		fn(pos, color)
	end
end

function Fx.preview(id: string, pos: Vector3, color: Color3)
	if FINISHERS[id] then
		Fx.finisher(id, pos, color)
	else
		Fx.entrance(id, pos, color)
	end
end

return Fx
