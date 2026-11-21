--!strict
-- All visual effects. A small pooled particle system moves parts in bulk every frame.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Skins = require(script.Parent:WaitForChild("Skins"))

local Effects = {}

local folder: Folder
local anchor: BasePart
local splatFolder: Folder

type Particle = {
	part: BasePart,
	shape: string,
	pos: Vector3,
	vel: Vector3,
	life: number,
	max: number,
	grav: number,
	drag: number,
	fade: number, -- start transparency
	grow: number,
	size: Vector3,
	rot: CFrame,
	spin: number,
	paint: boolean,
	color: Color3,
	axisZ: boolean,
}

local live: { Particle } = {}
local pools: { [string]: { BasePart } } = {}
local splats: { BasePart } = {}
local MAX_SPLATS = 260
local geoParams = RaycastParams.new()
geoParams.FilterType = Enum.RaycastFilterType.Include

local bulkParts: { BasePart } = {}
local bulkCFs: { CFrame } = {}

local function newPart(shape: string): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "disc" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = folder
	return p
end

local function take(shape: string): BasePart
	local pool = pools[shape]
	if pool and #pool > 0 then
		local p = table.remove(pool) :: BasePart
		return p
	end
	return newPart(shape)
end

local function give(shape: string, p: BasePart)
	p.Transparency = 1
	p.CFrame = CFrame.new(0, -5000, 0)
	pools[shape] = pools[shape] or {}
	table.insert(pools[shape], p)
end

function Effects.init()
	local f = workspace:FindFirstChild("RumbleFX")
	if f then
		f:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "RumbleFX"
	folder.Parent = workspace
	splatFolder = Instance.new("Folder")
	splatFolder.Name = "Splats"
	splatFolder.Parent = folder
	anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(0, 0, 0)
	anchor.Parent = folder
end

function Effects.folder(): Folder
	return folder
end

function Effects.setGeometry(geo: Instance?)
	geoParams.FilterDescendantsInstances = if geo then { geo } else {}
end

function Effects.clearSplats()
	for _, s in splats do
		s:Destroy()
	end
	splats = {}
end

local function spawn(shape: string, pos: Vector3, vel: Vector3, life: number, size: Vector3, color: Color3, opts: any?): Particle
	local o = opts or {}
	local p = take(shape)
	p.Size = size
	p.Color = color
	p.Material = o.material or Enum.Material.Neon
	p.Transparency = o.fade or 0
	local pt: Particle = {
		part = p,
		shape = shape,
		pos = pos,
		vel = vel,
		life = life,
		max = life,
		grav = o.grav or 0,
		drag = o.drag or 0,
		fade = o.fade or 0,
		grow = o.grow or 0,
		size = size,
		rot = o.rot or CFrame.identity,
		spin = o.spin or 0,
		paint = o.paint or false,
		color = color,
		axisZ = shape == "disc",
	}
	table.insert(live, pt)
	return pt
end

local function rand(a: number, b: number): number
	return a + (b - a) * math.random()
end

local function dir2(angle: number): Vector3
	return Vector3.new(math.cos(angle), math.sin(angle), 0)
end

-------------------------------------------------------------------------------
-- effect library

function Effects.spark(pos: Vector3, color: Color3, count: number, speed: number, size: number?)
	local s = size or 0.35
	for _ = 1, count do
		local a = rand(0, math.pi * 2)
		local v = dir2(a) * rand(speed * 0.4, speed) + Vector3.new(0, 0, rand(-4, 4))
		spawn("block", pos, v, rand(0.18, 0.35), Vector3.new(s * 2.2, s * 0.5, s * 0.5), color, { grav = 60, drag = 3, rot = CFrame.Angles(0, 0, a), spin = rand(-10, 10) })
	end
end

function Effects.ring(pos: Vector3, color: Color3, size: number, life: number?)
	spawn("disc", pos + Vector3.new(0, 0, 1.5), Vector3.zero, life or 0.25, Vector3.new(0.1, size * 0.3, size * 0.3), color, { grow = 3.2, fade = 0.15 })
end

function Effects.flash(pos: Vector3, color: Color3, size: number, life: number?)
	spawn("ball", pos + Vector3.new(0, 0, 1), Vector3.zero, life or 0.12, Vector3.new(size, size, size), color, { grow = 0.8 })
end

function Effects.dust(pos: Vector3, count: number, color: Color3?)
	local c = color or Color3.fromRGB(230, 225, 215)
	for i = 1, count do
		local side = if i % 2 == 0 then 1 else -1
		spawn("ball", pos + Vector3.new(rand(-0.6, 0.6), 0.2, rand(-1.5, 1.5)), Vector3.new(side * rand(4, 10), rand(1, 4), 0), rand(0.3, 0.5), Vector3.new(0.9, 0.9, 0.9), c, { drag = 5, grow = 1.6, fade = 0.3, material = Enum.Material.SmoothPlastic })
	end
end

-- paint droplets in the victim's color that splat onto the arena
function Effects.paint(pos: Vector3, push: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local v = push * rand(0.3, 0.9) + Vector3.new(rand(-12, 12), rand(-4, 16), 0)
		spawn("ball", pos, v, 1.4, Vector3.new(0.35, 0.35, 0.35), color, { grav = 120, paint = true, material = Enum.Material.SmoothPlastic })
	end
end

local function makeSplat(pos: Vector3, normal: Vector3, color: Color3)
	local up = if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.fromMatrix(pos + normal * 0.04, normal, normal:Cross(up).Unit)
	local d = rand(0.7, 1.6)
	local s = Instance.new("Part")
	s.Shape = Enum.PartType.Cylinder
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.SmoothPlastic
	s.Color = color
	s.Size = Vector3.new(0.05, d, d * rand(0.8, 1.3))
	s.CFrame = cf
	s.Parent = splatFolder
	table.insert(splats, s)
	if #splats > MAX_SPLATS then
		local old = table.remove(splats, 1)
		if old then
			old:Destroy()
		end
	end
end

function Effects.tracer(from: Vector3, to: Vector3, color: Color3, width: number?)
	local d = to - from
	local len = d.Magnitude
	if len < 0.1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	local wd = width or 0.18
	p.Size = Vector3.new(len, wd, wd)
	p.CFrame = CFrame.new(from + d * 0.5) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(len, 0.02, 0.02) }):Play()
	Debris:AddItem(p, 0.15)
end

function Effects.muzzle(pos: Vector3, angle: number, color: Color3?)
	local c = color or Color3.fromRGB(255, 220, 120)
	local d = dir2(angle)
	spawn("ball", pos + d * 0.3, Vector3.zero, 0.07, Vector3.new(1.3, 1.3, 1.3), c, { grow = 0.5 })
	spawn("block", pos + d * 0.8, d * 6, 0.06, Vector3.new(1.8, 0.35, 0.35), Color3.new(1, 1, 0.85), { rot = CFrame.Angles(0, 0, angle) })
	for _ = 1, 4 do
		local a = angle + rand(-0.5, 0.5)
		spawn("block", pos, dir2(a) * rand(20, 40), rand(0.08, 0.14), Vector3.new(0.5, 0.12, 0.12), c, { rot = CFrame.Angles(0, 0, a), drag = 8 })
	end
	local lp = Instance.new("Part")
	lp.Anchored = true
	lp.CanCollide = false
	lp.CanQuery = false
	lp.Transparency = 1
	lp.Size = Vector3.new(0.2, 0.2, 0.2)
	lp.CFrame = CFrame.new(pos + Vector3.new(0, 0, 2))
	local light = Instance.new("PointLight")
	light.Color = c
	light.Range = 14
	light.Brightness = 4
	light.Parent = lp
	lp.Parent = folder
	Debris:AddItem(lp, 0.06)
end

function Effects.shell(pos: Vector3, facing: number)
	spawn("block", pos, Vector3.new(-facing * rand(6, 12), rand(10, 18), rand(-2, 2)), 0.9, Vector3.new(0.18, 0.32, 0.18), Color3.fromRGB(230, 180, 60), { grav = 140, spin = rand(-20, 20), material = Enum.Material.Metal })
end

function Effects.explosion(pos: Vector3, radius: number)
	spawn("ball", pos + Vector3.new(0, 0, 1), Vector3.zero, 0.3, Vector3.new(radius * 0.6, radius * 0.6, radius * 0.6), Color3.fromRGB(255, 245, 210), { grow = 1.3 })
	spawn("ball", pos, Vector3.zero, 0.5, Vector3.new(radius * 0.9, radius * 0.9, radius * 0.9), Color3.fromRGB(255, 140, 50), { grow = 0.7, fade = 0.2 })
	spawn("disc", pos + Vector3.new(0, 0, 1.5), Vector3.zero, 0.35, Vector3.new(0.15, radius * 0.6, radius * 0.6), Color3.fromRGB(255, 230, 160), { grow = 3.5, fade = 0.1 })
	for _ = 1, 14 do
		local a = rand(0, math.pi * 2)
		spawn("ball", pos + dir2(a) * rand(0.5, radius * 0.4), dir2(a) * rand(4, 12) + Vector3.new(0, 6, 0), rand(0.8, 1.4), Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(70, 65, 70), { drag = 2.5, grow = 1.6, fade = 0.25, material = Enum.Material.SmoothPlastic })
	end
	Effects.spark(pos, Color3.fromRGB(255, 190, 80), 22, 70, 0.5)
	local lp = Instance.new("Part")
	lp.Anchored = true
	lp.CanCollide = false
	lp.CanQuery = false
	lp.Transparency = 1
	lp.Size = Vector3.new(0.2, 0.2, 0.2)
	lp.CFrame = CFrame.new(pos + Vector3.new(0, 0, 4))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = radius * 4
	light.Brightness = 8
	light.Parent = lp
	lp.Parent = folder
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
	Debris:AddItem(lp, 0.55)
end

function Effects.beam(x: number, top: number, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.5
	p.Size = Vector3.new(1.4, 120, 1.4)
	p.CFrame = CFrame.new(x, top - 50, -1)
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(0.1, 120, 0.1) }):Play()
	Debris:AddItem(p, 1.2)
end

function Effects.confetti(center: Vector3, width: number)
	for _ = 1, 90 do
		local c = Color3.fromHSV(math.random(), 0.75, 1)
		spawn("block", center + Vector3.new(rand(-width, width) * 0.5, rand(0, 10), rand(-3, 3)), Vector3.new(rand(-6, 6), rand(-12, 4), 0), rand(2.5, 4), Vector3.new(0.6, 0.35, 0.05), c, { grav = 12, drag = 1.5, spin = rand(-8, 8), rot = CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6)), material = Enum.Material.SmoothPlastic })
	end
end

-- floating text (damage numbers, KO!, BLOCK, PARRY)
function Effects.text(pos: Vector3, text: string, color: Color3, size: number?, life: number?)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(200, 60)
	gui.StudsOffsetWorldSpace = pos + Vector3.new(0, 0, 2)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size or 26
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 18, 30)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	gui.Parent = folder
	local l = life or 0.8
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(l, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = pos + Vector3.new(rand(-1, 1), 3, 2) }):Play()
	task.delay(l * 0.6, function()
		TweenService:Create(label, TweenInfo.new(l * 0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(l * 0.4), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(gui, l + 0.05)
end

-- crescent slash arc (Blender mesh) for melee swings
function Effects.slash(pos: Vector3, angle: number, color: Color3, facing: number, scale: number?)
	local sc = scale or 1.3
	local cf = CFrame.new(pos + Vector3.new(0, 0, 1.2)) * CFrame.Angles(0, 0, angle) * (if facing < 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.identity)
	local m = Skins.clone("fx_slash", cf, sc)
	if m then
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
				p.Transparency = 0.1
				TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Transparency = 1, Size = p.Size * 1.35 }):Play()
			end
		end
		m.Parent = folder
		Debris:AddItem(m, 0.25)
	else
		for i = -1, 1 do
			local a = angle + i * 0.5
			Effects.tracer(pos + dir2(a) * 1.2, pos + dir2(a + 0.4 * facing) * 3, color, 0.3)
		end
	end
end

-- little spinning stars (Blender mesh) for big hits
function Effects.stars(pos: Vector3, color: Color3, n: number)
	for _ = 1, n do
		local a = rand(0, math.pi * 2)
		local m = Skins.clone("fx_star", CFrame.new(pos) * CFrame.Angles(0, 0, a), rand(0.25, 0.45))
		if not m then
			Effects.spark(pos, color, 2, 30)
			continue
		end
		local v = dir2(a) * rand(14, 26)
		m.Parent = folder
		local parts = {}
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.Color = color
				table.insert(parts, p)
			end
		end
		task.spawn(function()
			local t0 = os.clock()
			local pos0 = pos
			while os.clock() - t0 < 0.55 and m.Parent do
				local t = os.clock() - t0
				local cf = CFrame.new(pos0 + v * t - Vector3.new(0, 30 * t * t, 0)) * CFrame.Angles(0, 0, a + t * 9)
				m:PivotTo(cf)
				for _, p in parts do
					p.Transparency = math.clamp((t - 0.25) / 0.3, 0, 1)
				end
				task.wait()
			end
			m:Destroy()
		end)
	end
end

-- slash trail on melee weapons (attachments created by the server)
function Effects.decorateWeapon(weapon: Model, color: Color3)
	local handle = weapon:FindFirstChild("Handle")
	if not handle then
		return
	end
	local tip = handle:FindFirstChild("Tip") :: Attachment?
	local base = handle:FindFirstChild("Base") :: Attachment?
	if not tip or not base or handle:FindFirstChild("SlashTrail") then
		return
	end
	local trail = Instance.new("Trail")
	trail.Name = "SlashTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = handle
end

-------------------------------------------------------------------------------

function Effects.update(dt: number)
	table.clear(bulkParts)
	table.clear(bulkCFs)
	for i = #live, 1, -1 do
		local p = live[i]
		p.life -= dt
		if p.life <= 0 then
			give(p.shape, p.part)
			table.remove(live, i)
			continue
		end
		local old = p.pos
		p.vel -= Vector3.new(0, p.grav * dt, 0)
		if p.drag > 0 then
			p.vel *= math.max(0, 1 - p.drag * dt)
		end
		p.pos += p.vel * dt
		if p.paint then
			local hit = workspace:Raycast(old, p.pos - old, geoParams)
			if hit then
				makeSplat(hit.Position, hit.Normal, p.color)
				give(p.shape, p.part)
				table.remove(live, i)
				continue
			end
		end
		local k = 1 - p.life / p.max
		if p.grow > 0 then
			p.part.Size = p.size * (1 + p.grow * k)
		end
		p.part.Transparency = p.fade + (1 - p.fade) * (k * k)
		if p.spin ~= 0 then
			p.rot *= CFrame.Angles(0, 0, p.spin * dt)
		end
		local cf = CFrame.new(p.pos) * p.rot
		if p.axisZ then
			cf = CFrame.new(p.pos) * CFrame.Angles(0, math.pi / 2, 0)
		end
		table.insert(bulkParts, p.part)
		table.insert(bulkCFs, cf)
	end
	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

return Effects
