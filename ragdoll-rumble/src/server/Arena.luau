--!strict
-- Builds the 3D side-view arenas from the 2D layouts in Maps.luau.
-- Moving platforms are real physics bodies (rigid Align constraints) so they carry avatars.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Motion = require(Shared:WaitForChild("Motion"))
local Util = require(Shared:WaitForChild("Util"))

local Arena = {}

local DEPTH = 18

local folder: Folder? = nil
local movers: { { part: BasePart, ap: AlignPosition, ao: AlignOrientation, def: any } } = {}
local hazards: { any } = {}
local inkPart: BasePart? = nil
Arena.map = nil :: any
Arena.inkY = -math.huge

local function c3(hex: number): Color3
	local r, g, b = Util.hexToRGB(hex)
	return Color3.fromRGB(r, g, b)
end
Arena.c3 = c3

local function part(props: { [string]: any }, parent: Instance?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	if parent then
		p.Parent = parent
	end
	return p
end

local function deco(props: { [string]: any }, parent: Instance): BasePart
	local p = part(props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function material(name: string?): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name or "SmoothPlastic"]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

-------------------------------------------------------------------------------
-- backdrop / lighting per theme

local function buildBackdrop(map: any, f: Folder)
	local th = map.theme
	local b = map.bounds
	local cx, cy = (b.left + b.right) * 0.5, (b.bottom + b.top) * 0.5
	local rng = Util.rng(#map.name * 977 + 13)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = f

	local sky = deco({ Name = "Sky", Size = Vector3.new(1600, 800, 2), CFrame = CFrame.new(cx, cy + 40, -330), Color = c3(th.skyBottom) }, decor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 1
	gui.LightInfluence = 0
	gui.Parent = sky
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c3(th.skyTop)),
		ColorSequenceKeypoint.new(0.6, c3(th.skyTop):Lerp(c3(th.skyBottom), 0.65)),
		ColorSequenceKeypoint.new(1, c3(th.skyBottom)),
	})
	grad.Parent = frame

	local sunCol = c3(th.accent):Lerp(Color3.new(1, 1, 1), 0.35)
	local sun = deco({ Name = "Sun", Shape = Enum.PartType.Ball, Size = Vector3.new(80, 80, 80), Color = sunCol, Material = Enum.Material.Neon }, decor)
	sun.CFrame = CFrame.new(cx + rng:range(-70, 70), cy + 45, -300)

	local kind = th.kind
	local far = c3(th.skyBottom):Lerp(c3(th.block), 0.6)
	local near = c3(th.block):Lerp(Color3.new(0, 0, 0), 0.3)
	local ground = b.bottom - 25

	local function block(x: number, w: number, h: number, z: number, d: number, col: Color3, mat: Enum.Material?, angle: number?)
		return deco({
			Size = Vector3.new(w, h, d),
			CFrame = CFrame.new(x, ground + h * 0.5, z) * CFrame.Angles(0, 0, math.rad(angle or 0)),
			Color = col,
			Material = mat or Enum.Material.SmoothPlastic,
		}, decor)
	end

	if kind == "city" then
		for i = 1, 28 do
			block(cx - 220 + i * 16 + rng:range(-4, 4), rng:range(10, 18), rng:range(40, 110), -220, 20, far)
		end
		for i = 1, 18 do
			local x = cx - 160 + i * 18 + rng:range(-5, 5)
			local h, w = rng:range(30, 85), rng:range(10, 15)
			block(x, w, h, -120, 16, near, Enum.Material.Concrete)
			for _ = 1, 7 do
				if rng:next() < 0.65 then
					deco({ Size = Vector3.new(1.4, 1.8, 0.4), CFrame = CFrame.new(x + rng:range(-w * 0.35, w * 0.35), ground + rng:range(5, h - 3), -111.8), Color = c3(th.accent), Material = Enum.Material.Neon }, decor)
				end
			end
		end
	elseif kind == "carnival" then
		for i = 1, 9 do
			local s = rng:range(26, 40)
			local col = if i % 2 == 0 then c3(th.edge):Lerp(far, 0.45) else c3(th.ledge):Lerp(far, 0.45)
			deco({ Size = Vector3.new(s, s, 20), CFrame = CFrame.new(cx - 170 + i * 38, ground + 2, -170) * CFrame.Angles(0, 0, math.rad(45)), Color = col, Material = Enum.Material.Fabric }, decor)
		end
		for i = 0, 50 do
			local x = cx - 110 + i * 4.4
			local y = cy + 36 - math.sin(i / 50 * math.pi * 3) ^ 2 * 7
			deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(x, y, -60), Color = Color3.fromHSV((i * 0.13) % 1, 0.6, 1), Material = Enum.Material.Neon }, decor)
		end
	elseif kind == "factory" then
		for i = 1, 10 do
			local h = rng:range(60, 120)
			local x = cx - 160 + i * 32 + rng:range(-6, 6)
			block(x, rng:range(6, 10), h, -180, 8, far, Enum.Material.Brick)
		end
		for i = 1, 4 do
			local r = rng:range(12, 20)
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, r * 2, r * 2), CFrame = CFrame.new(cx - 100 + i * 48, cy + rng:range(-8, 22), -110) * CFrame.Angles(0, math.pi / 2, 0), Color = near, Material = Enum.Material.Metal }, decor)
		end
	elseif kind == "temple" then
		for i = 0, 7 do
			local w = 150 - i * 18
			deco({ Size = Vector3.new(w, 10, 40), CFrame = CFrame.new(cx, ground + 5 + i * 10, -220), Color = far:Lerp(Color3.new(0, 0, 0), i * 0.03), Material = Enum.Material.Slate }, decor)
		end
		for i = 1, 12 do
			local x = cx - 140 + i * 24
			block(x, 5, rng:range(45, 80), -110, 5, near, Enum.Material.Slate)
			for k = 1, 3 do
				deco({ Size = Vector3.new(0.6, rng:range(8, 18), 0.6), CFrame = CFrame.new(x + rng:range(-3, 3), cy + 44 - k * 4, -100), Color = c3(0x3f7d3a), Material = Enum.Material.Grass }, decor)
			end
		end
	elseif kind == "arctic" then
		for i = 1, 12 do
			local s = rng:range(24, 44)
			deco({ Size = Vector3.new(s, s, s), CFrame = CFrame.new(cx - 170 + i * 30, ground - 4, rng:range(-200, -130)) * CFrame.Angles(0, 0, math.rad(rng:range(20, 70))), Color = c3(0xd9efff):Lerp(far, 0.25), Material = Enum.Material.Glacier }, decor)
		end
		deco({ Name = "Water", Size = Vector3.new(1200, 4, 400), CFrame = CFrame.new(cx, map.killY + 6, -150), Color = c3(0x1d4e89), Material = Enum.Material.Glass, Transparency = 0.2 }, decor)
		local emitter = deco({ Size = Vector3.new(240, 1, 80), CFrame = CFrame.new(cx, b.top + 25, -20), Transparency = 1 }, decor)
		local pe = Instance.new("ParticleEmitter")
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Rate = 70
		pe.Lifetime = NumberRange.new(8, 12)
		pe.Speed = NumberRange.new(6, 10)
		pe.SpreadAngle = Vector2.new(25, 25)
		pe.Size = NumberSequence.new(0.35)
		pe.LightEmission = 0.4
		pe.Parent = emitter
	elseif kind == "lab" then
		for i = 1, 14 do
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(500, 1.6, 1.6), CFrame = CFrame.new(cx, cy - 32 + i * 6.5, -120 - (i % 3) * 12), Color = far, Material = Enum.Material.Metal }, decor)
		end
		for i = 1, 8 do
			deco({ Size = Vector3.new(12, 7, 0.6), CFrame = CFrame.new(cx - 125 + i * 31, cy + rng:range(-10, 30), -95), Color = c3(th.edge), Material = Enum.Material.Neon, Transparency = 0.45 }, decor)
		end
	elseif kind == "desert" then
		for i = 1, 8 do
			local x = cx - 160 + i * 40 + rng:range(-8, 8)
			local w, h = rng:range(26, 44), rng:range(20, 44)
			block(x, w, h, -200, 40, far, Enum.Material.Sandstone)
			block(x, w * 0.7, h + 8, -205, 30, far:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Sandstone)
		end
		for i = 1, 10 do
			local x = cx - 140 + i * 28 + rng:range(-6, 6)
			local h = rng:range(7, 13)
			block(x, 1.8, h, -100, 1.8, c3(0x3e6b3a), Enum.Material.Grass)
			deco({ Size = Vector3.new(4.5, 1.4, 1.4), CFrame = CFrame.new(x, ground + h * 0.6, -100), Color = c3(0x3e6b3a), Material = Enum.Material.Grass }, decor)
		end
	elseif kind == "neon" then
		for i = -16, 16 do
			deco({ Size = Vector3.new(0.4, 0.4, 300), CFrame = CFrame.new(cx + i * 16, b.bottom - 6, -160), Color = c3(th.ledge), Material = Enum.Material.Neon, Transparency = 0.3 }, decor)
		end
		for i = 1, 10 do
			deco({ Size = Vector3.new(700, 0.4, 0.4), CFrame = CFrame.new(cx, b.bottom - 6, -10 - i * i * 3), Color = c3(th.edge), Material = Enum.Material.Neon, Transparency = 0.3 }, decor)
		end
		for i = 1, 6 do
			deco({ Size = Vector3.new(90, 3, 2), CFrame = CFrame.new(sun.Position.X, sun.Position.Y - 6 - i * 6, -255), Color = c3(th.skyBottom) }, decor)
		end
	end

	-- lighting mood
	Lighting.ClockTime = th.clock or 14
	Lighting.Brightness = if kind == "neon" or kind == "lab" then 1.2 else 2.2
	Lighting.Ambient = c3(th.skyTop):Lerp(Color3.new(1, 1, 1), 0.45)
	Lighting.OutdoorAmbient = c3(th.skyBottom):Lerp(Color3.new(1, 1, 1), 0.35)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.FogEnd = 100000
	Lighting.GlobalShadows = true
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo:Destroy()
	end
end

-------------------------------------------------------------------------------
-- geometry

local function buildBlock(def: any, th: any, f: Folder, index: number)
	local depth = def.depth or DEPTH
	local style = def.style
	local col = c3(if style == "ledge" or style == "cabin" or style == "lift" then th.ledge else th.block)
	local p = part({
		Name = "Block" .. index,
		Size = Vector3.new(def.w, def.h, depth),
		CFrame = CFrame.new(def.x, def.y, 0) * CFrame.Angles(0, 0, math.rad(def.angle or 0)),
		Color = col,
		Material = material(th.material),
	}, f)
	-- bright top edge so platforms read clearly from the side
	local edgeH = math.min(0.6, def.h * 0.45)
	local edge = deco({
		Name = "Edge",
		Size = Vector3.new(def.w + 0.1, edgeH, depth + 0.1),
		CFrame = p.CFrame * CFrame.new(0, def.h * 0.5 - edgeH * 0.5 + 0.02, 0),
		Color = c3(th.edge),
		Material = if th.kind == "neon" or th.kind == "lab" then Enum.Material.Neon else material(th.material),
	}, p)
	if style == "ice" then
		p.Material = Enum.Material.Glacier
		edge.Material = Enum.Material.Snow
		edge.Color = Color3.new(1, 1, 1)
	elseif style == "crate" then
		p.Material = Enum.Material.WoodPlanks
		p.Color = c3(0x8a5a2b)
		edge.Color = c3(0xa8743f)
		edge.Material = Enum.Material.WoodPlanks
	elseif style == "spinner" then
		p.Material = Enum.Material.Neon
		p.Color = c3(th.accent)
		edge.Transparency = 1
	elseif style == "belt" then
		p.Color = c3(0x2a2420)
		edge.Material = Enum.Material.DiamondPlate
		edge.Color = c3(0x3a3530)
		p.AssemblyLinearVelocity = Vector3.new(def.conveyor or 0, 0, 0)
		p:SetAttribute("Conveyor", def.conveyor or 0)
		-- hazard stripes along the front face
		for i = 0, math.floor(def.w / 3) do
			deco({ Size = Vector3.new(1.2, def.h * 0.6, 0.2), CFrame = CFrame.new(def.x - def.w * 0.5 + i * 3 + 1, def.y - 0.4, depth * 0.5 + 0.1) * CFrame.Angles(0, 0, math.rad(30)), Color = c3(th.edge), Material = Enum.Material.Neon }, p)
		end
	elseif style == "lift" then
		edge.Material = Enum.Material.Neon
	elseif style == "cabin" then
		edge.Material = Enum.Material.Neon
		edge.Color = Color3.fromHSV((index * 0.17) % 1, 0.65, 1)
	end

	if def.motion then
		-- physical mover: unanchored + rigid alignment, server owned
		local w = Instance.new("WeldConstraint")
		w.Part0 = p
		w.Part1 = edge
		edge.Anchored = false
		edge.Massless = true
		w.Parent = p
		p.Anchored = false
		p.CustomPhysicalProperties = PhysicalProperties.new(5, 0.6, 0, 1, 1)
		local att = Instance.new("Attachment")
		att.Parent = p
		local ap = Instance.new("AlignPosition")
		ap.Mode = Enum.PositionAlignmentMode.OneAttachment
		ap.Attachment0 = att
		ap.RigidityEnabled = true
		ap.Position = p.Position
		ap.Parent = p
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.RigidityEnabled = true
		ao.CFrame = p.CFrame.Rotation
		ao.Parent = p
		table.insert(movers, { part = p, ap = ap, ao = ao, def = def })
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
	end
	return p
end

local function buildHazard(def: any, th: any, f: Folder, index: number)
	if def.kind == "saw" then
		local r = def.r
		local saw = deco({
			Name = "Saw" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, r * 2, r * 2),
			CFrame = CFrame.new(def.x, def.y, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = c3(0xaab2bf),
			Material = Enum.Material.Metal,
		}, f)
		saw:SetAttribute("SawIndex", index)
		saw:SetAttribute("Radius", r)
		local n = math.max(8, math.floor(r * 3))
		for i = 1, n do
			local a = i / n * math.pi * 2
			local tooth = deco({
				Size = Vector3.new(0.6, r * 0.34, r * 0.34),
				CFrame = saw.CFrame * CFrame.new(0, math.cos(a) * r, math.sin(a) * r) * CFrame.Angles(a + math.pi / 4, 0, 0),
				Color = c3(0xe6ebf2),
				Material = Enum.Material.Metal,
			}, saw)
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = saw
			wc.Part1 = tooth
			wc.Parent = tooth
			tooth.Anchored = false
			tooth.Massless = true
		end
		local hub = deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, r * 0.6, r * 0.6), CFrame = saw.CFrame, Color = c3(0xd62828), Material = Enum.Material.Neon }, saw)
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = saw
		wc.Part1 = hub
		wc.Parent = hub
		hub.Anchored = false
		hub.Massless = true
		table.insert(hazards, { kind = "saw", def = def, part = saw })
	elseif def.kind == "spikes" then
		local base = deco({ Size = Vector3.new(def.w, def.h * 1.2, DEPTH - 2), CFrame = CFrame.new(def.x, def.y - def.h * 0.4, 0), Color = c3(0x3a1f24) }, f)
		local n = math.max(1, math.floor(def.w / 1.3))
		local step = def.w / n
		for i = 1, n do
			for k = -2, 2 do
				deco({
					Size = Vector3.new(step * 0.7, step * 0.7, step * 0.7),
					CFrame = CFrame.new(def.x - def.w * 0.5 + step * (i - 0.5), def.y, k * 3.2) * CFrame.Angles(0, math.rad(45), math.rad(45)),
					Color = c3(0xd8dde6),
					Material = Enum.Material.Metal,
				}, base)
			end
		end
		table.insert(hazards, { kind = "spikes", def = def })
	end
end

function Arena.clear()
	if folder then
		folder:Destroy()
	end
	folder = nil
	movers = {}
	hazards = {}
	inkPart = nil
	Arena.inkY = -math.huge
end

function Arena.build(map: any)
	Arena.clear()
	Arena.map = map
	local f = Instance.new("Folder")
	f.Name = "Arena"
	f.Parent = workspace
	folder = f
	local th = map.theme
	buildBackdrop(map, f)
	local geo = Instance.new("Folder")
	geo.Name = "Geometry"
	geo.Parent = f
	for i, def in map.blocks do
		buildBlock(def, th, geo, i)
	end
	for i, def in map.hazards do
		buildHazard(def, th, f, i)
	end
	-- ferris wheel hub + struts
	if map.wheel then
		local w = map.wheel
		deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 5, 5), CFrame = CFrame.new(w.x, w.y, -6) * CFrame.Angles(0, math.pi / 2, 0), Color = c3(th.accent), Material = Enum.Material.Neon }, f)
		for _, s in { -1, 1 } do
			local hgt = w.y - map.bounds.bottom + 12
			deco({ Size = Vector3.new(2, hgt, 2), CFrame = CFrame.new(w.x + s * 5, w.y - hgt * 0.5, -7) * CFrame.Angles(0, 0, math.rad(s * 12)), Color = c3(th.block), Material = Enum.Material.Metal }, f)
		end
	end
	-- pendulum pivots
	for _, def in map.blocks do
		local m = def.motion
		if m and m.type == "pendulum" then
			deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(m.px, m.py, -2), Color = c3(th.accent), Material = Enum.Material.Metal }, f)
		end
	end
	-- the ink pool (rises during sudden death)
	local ink = deco({ Name = "Ink", Size = Vector3.new(1400, 200, 200), Color = c3(th.ink), Material = Enum.Material.Neon, Transparency = 0.25 }, f)
	inkPart = ink
	Arena.setInk(map.killY)
	Arena.update(0)
end

function Arena.setInk(y: number)
	Arena.inkY = y
	if inkPart then
		inkPart.CFrame = CFrame.new(0, y - 100, -60)
	end
end

function Arena.update(t: number)
	for _, m in movers do
		local d = m.def
		local x, y, a = Motion.pose(d.motion, d.x, d.y, math.rad(d.angle or 0), t)
		m.ap.Position = Vector3.new(x, y, 0)
		m.ao.CFrame = CFrame.Angles(0, 0, a)
	end
end

-- hazard touching a sphere at pos? returns kind and push direction
function Arena.hazardAt(pos: Vector3, radius: number, t: number): (string?, Vector3)
	for _, h in hazards do
		local d = h.def
		if h.kind == "saw" then
			local x, y = Motion.pose(d.motion, d.x, d.y, 0, t)
			local dx, dy = pos.X - x, pos.Y - y
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist < d.r + radius then
				local nx, ny = Util.norm(dx, dy)
				if nx == 0 and ny == 0 then
					ny = 1
				end
				return "saw", Vector3.new(nx, ny, 0)
			end
		elseif h.kind == "spikes" then
			if math.abs(pos.X - d.x) < d.w * 0.5 + radius and math.abs(pos.Y - d.y) < d.h * 0.5 + radius then
				return "spikes", Vector3.new(0, 1, 0)
			end
		end
	end
	return nil, Vector3.zero
end

function Arena.folder(): Folder?
	return folder
end

function Arena.spawnCFrame(x: number, y: number): CFrame
	local map = Arena.map
	local cx = if map then (map.bounds.left + map.bounds.right) * 0.5 else 0
	local facing = if x > cx then -1 else 1
	return CFrame.new(x, y + 3.4, 0) * CFrame.Angles(0, if facing > 0 then -math.pi / 2 else math.pi / 2, 0)
end

return Arena
