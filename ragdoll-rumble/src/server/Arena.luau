--!strict
-- Builds zones (the lobby + the current match arena) from the 2D layouts in Maps.luau.
-- Moving platforms are real physics bodies so they carry avatars. Props are tagged
-- "RumbleSkin" so clients can dress them with the Blender meshes (fallback parts stay
-- visible if mesh APIs are unavailable).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Motion = require(Shared:WaitForChild("Motion"))
local Util = require(Shared:WaitForChild("Util"))

local Arena = {}

local DEPTH = 18

export type Zone = {
	name: string,
	map: any,
	folder: Folder,
	geometry: Folder,
	movers: { { part: BasePart, ap: AlignPosition, ao: AlignOrientation, def: any } },
	hazards: { any },
	inkPart: BasePart?,
	inkY: number,
}

Arena.zones = {} :: { [string]: Zone }

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
Arena.part = part

local function deco(props: { [string]: any }, parent: Instance): BasePart
	local p = part(props, parent)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end
Arena.deco = deco

-- invisible anchor that clients replace with a Blender mesh
function Arena.skinAnchor(name: string, cf: CFrame, scale: number?, parent: Instance): BasePart
	local a = deco({ Name = "Skin_" .. name, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf, Transparency = 1 }, parent)
	a:SetAttribute("Skin", name)
	a:SetAttribute("SkinScale", scale or 1)
	CollectionService:AddTag(a, "RumbleSkin")
	return a
end

local function material(name: string?): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name or "SmoothPlastic"]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

-------------------------------------------------------------------------------
-- backdrop

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

	if kind == "city" or kind == "lobby" then
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
			block(cx - 160 + i * 32 + rng:range(-6, 6), rng:range(6, 10), rng:range(60, 120), -180, 8, far, Enum.Material.Brick)
		end
		for i = 1, 4 do
			local r = rng:range(12, 20)
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, r * 2, r * 2), CFrame = CFrame.new(cx - 100 + i * 48, cy + rng:range(-8, 22), -110) * CFrame.Angles(0, math.pi / 2, 0), Color = near, Material = Enum.Material.Metal }, decor)
		end
	elseif kind == "temple" then
		for i = 0, 7 do
			deco({ Size = Vector3.new(150 - i * 18, 10, 40), CFrame = CFrame.new(cx, ground + 5 + i * 10, -220), Color = far:Lerp(Color3.new(0, 0, 0), i * 0.03), Material = Enum.Material.Slate }, decor)
		end
		for i = 1, 12 do
			local x = cx - 140 + i * 24
			block(x, 5, rng:range(45, 80), -110, 5, near, Enum.Material.Slate)
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
	elseif kind == "neon" then
		for i = -16, 16 do
			deco({ Size = Vector3.new(0.4, 0.4, 300), CFrame = CFrame.new(cx + i * 16, b.bottom - 6, -160), Color = c3(th.ledge), Material = Enum.Material.Neon, Transparency = 0.3 }, decor)
		end
		for i = 1, 10 do
			deco({ Size = Vector3.new(700, 0.4, 0.4), CFrame = CFrame.new(cx, b.bottom - 6, -10 - i * i * 3), Color = c3(th.edge), Material = Enum.Material.Neon, Transparency = 0.3 }, decor)
		end
	end
	if kind == "lobby" then
		-- back wall of the arcade hall with neon strips
		deco({ Size = Vector3.new(164, 44, 2), CFrame = CFrame.new(0, 1019, -10), Color = c3(0x1c1834), Material = Enum.Material.SmoothPlastic }, decor)
		for i = 0, 3 do
			deco({ Size = Vector3.new(164, 0.4, 0.3), CFrame = CFrame.new(0, 1003 + i * 9, -8.9), Color = if i % 2 == 0 then c3(th.edge) else c3(th.accent), Material = Enum.Material.Neon }, decor)
		end
	end
end

-------------------------------------------------------------------------------
-- geometry

local function buildBlock(zone: Zone, def: any, index: number)
	local th = zone.map.theme
	local depth = def.depth or DEPTH
	local style = def.style
	local col = c3(if style == "ledge" or style == "cabin" or style == "lift" then th.ledge else th.block)
	local p = part({
		Name = "Block" .. index,
		Size = Vector3.new(def.w, def.h, depth),
		CFrame = CFrame.new(def.x, def.y, 0) * CFrame.Angles(0, 0, math.rad(def.angle or 0)),
		Color = col,
		Material = material(th.material),
	}, zone.geometry)
	local edgeH = math.min(0.6, def.h * 0.45)
	local edge = deco({
		Name = "Edge",
		Size = Vector3.new(def.w + 0.1, edgeH, depth + 0.1),
		CFrame = p.CFrame * CFrame.new(0, def.h * 0.5 - edgeH * 0.5 + 0.02, 0),
		Color = c3(th.edge),
		Material = if th.kind == "neon" or th.kind == "lab" or th.kind == "lobby" then Enum.Material.Neon else material(th.material),
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
		for i = 0, math.floor(def.w / 3) do
			deco({ Size = Vector3.new(1.2, def.h * 0.6, 0.2), CFrame = CFrame.new(def.x - def.w * 0.5 + i * 3 + 1, def.y - 0.4, depth * 0.5 + 0.1) * CFrame.Angles(0, 0, math.rad(30)), Color = c3(th.edge), Material = Enum.Material.Neon }, p)
		end
	elseif style == "lift" or style == "cabin" then
		edge.Material = Enum.Material.Neon
		if style == "cabin" then
			edge.Color = Color3.fromHSV((index * 0.17) % 1, 0.65, 1)
		end
	end
	if def.motion then
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
		table.insert(zone.movers, { part = p, ap = ap, ao = ao, def = def })
		pcall(function()
			p:SetNetworkOwner(nil)
		end)
	end
end

local function buildHazard(zone: Zone, def: any, index: number)
	local f = zone.folder
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
		saw:SetAttribute("Fallback", true)
		local n = math.max(8, math.floor(r * 3))
		for i = 1, n do
			local a = i / n * math.pi * 2
			local tooth = deco({
				Size = Vector3.new(0.6, r * 0.34, r * 0.34),
				CFrame = saw.CFrame * CFrame.new(0, math.cos(a) * r, math.sin(a) * r) * CFrame.Angles(a + math.pi / 4, 0, 0),
				Color = c3(0xe6ebf2),
				Material = Enum.Material.Metal,
			}, saw)
			tooth:SetAttribute("Fallback", true)
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = saw
			wc.Part1 = tooth
			wc.Parent = tooth
			tooth.Anchored = false
			tooth.Massless = true
		end
		-- the Blender saw mesh is modeled facing the camera (radius 1)
		local anchor = Arena.skinAnchor("saw", CFrame.new(def.x, def.y, 0), r, saw)
		anchor.Anchored = false
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = saw
		wc.Part1 = anchor
		wc.Parent = anchor
		table.insert(zone.hazards, { kind = "saw", def = def, part = saw })
	elseif def.kind == "spikes" then
		local holder = Instance.new("Model")
		holder.Name = "Spikes" .. index
		holder.Parent = f
		deco({ Size = Vector3.new(def.w, def.h * 1.2, DEPTH - 2), CFrame = CFrame.new(def.x, def.y - def.h * 0.4, 0), Color = c3(0x3a1f24) }, holder)
		local n = math.max(1, math.floor(def.w / 1.3))
		local step = def.w / n
		for i = 1, n do
			for k = -2, 2 do
				local x, z = def.x - def.w * 0.5 + step * (i - 0.5), k * 3.2
				local d = deco({
					Size = Vector3.new(step * 0.7, step * 0.7, step * 0.7),
					CFrame = CFrame.new(x, def.y, z) * CFrame.Angles(0, math.rad(45), math.rad(45)),
					Color = c3(0xd8dde6),
					Material = Enum.Material.Metal,
				}, holder)
				d:SetAttribute("Fallback", true)
				Arena.skinAnchor("spike", CFrame.new(x, def.y - def.h * 0.5, z), step * 0.9, holder)
			end
		end
		table.insert(zone.hazards, { kind = "spikes", def = def })
	end
end

-------------------------------------------------------------------------------

function Arena.clear(name: string)
	local z = Arena.zones[name]
	if z then
		z.folder:Destroy()
		Arena.zones[name] = nil
	end
end

function Arena.build(name: string, map: any): Zone
	Arena.clear(name)
	local f = Instance.new("Folder")
	f.Name = if name == "lobby" then "Lobby" else "Arena"
	f:SetAttribute("Zone", name)
	f.Parent = workspace
	local geo = Instance.new("Folder")
	geo.Name = "Geometry"
	geo.Parent = f
	local zone: Zone = { name = name, map = map, folder = f, geometry = geo, movers = {}, hazards = {}, inkPart = nil, inkY = -math.huge }
	Arena.zones[name] = zone
	buildBackdrop(map, f)
	for i, def in map.blocks do
		buildBlock(zone, def, i)
	end
	for i, def in map.hazards do
		buildHazard(zone, def, i)
	end
	local th = map.theme
	if map.wheel then
		local w = map.wheel
		deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 5, 5), CFrame = CFrame.new(w.x, w.y, -6) * CFrame.Angles(0, math.pi / 2, 0), Color = c3(th.accent), Material = Enum.Material.Neon }, f)
		for _, s in { -1, 1 } do
			local hgt = w.y - map.bounds.bottom + 12
			deco({ Size = Vector3.new(2, hgt, 2), CFrame = CFrame.new(w.x + s * 5, w.y - hgt * 0.5, -7) * CFrame.Angles(0, 0, math.rad(s * 12)), Color = c3(th.block), Material = Enum.Material.Metal }, f)
		end
	end
	for _, def in map.blocks do
		local m = def.motion
		if m and m.type == "pendulum" then
			deco({ Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(m.px, m.py, -2), Color = c3(th.accent), Material = Enum.Material.Metal }, f)
		end
	end
	if name ~= "lobby" then
		local ink = deco({ Name = "Ink", Size = Vector3.new(1400, 200, 200), Color = c3(th.ink), Material = Enum.Material.Neon, Transparency = 0.25 }, f)
		zone.inkPart = ink
		Arena.setInk(name, map.killY)
	end
	Arena.update(0)
	return zone
end

function Arena.setInk(name: string, y: number)
	local z = Arena.zones[name]
	if not z then
		return
	end
	z.inkY = y
	if z.inkPart then
		z.inkPart.CFrame = CFrame.new(0, y - 100, -60)
	end
end

function Arena.update(t: number)
	for _, z in Arena.zones do
		for _, m in z.movers do
			local d = m.def
			local x, y, a = Motion.pose(d.motion, d.x, d.y, math.rad(d.angle or 0), t)
			m.ap.Position = Vector3.new(x, y, 0)
			m.ao.CFrame = CFrame.Angles(0, 0, a)
		end
	end
end

function Arena.hazardAt(name: string, pos: Vector3, radius: number, t: number): (string?, Vector3)
	local z = Arena.zones[name]
	if not z then
		return nil, Vector3.zero
	end
	for _, h in z.hazards do
		local d = h.def
		if h.kind == "saw" then
			local x, y = Motion.pose(d.motion, d.x, d.y, 0, t)
			local dx, dy = pos.X - x, pos.Y - y
			if math.sqrt(dx * dx + dy * dy) < d.r + radius then
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

function Arena.zone(name: string): Zone?
	return Arena.zones[name]
end

function Arena.spawnCFrame(name: string, x: number, y: number): CFrame
	local z = Arena.zones[name]
	local cx = if z then (z.map.bounds.left + z.map.bounds.right) * 0.5 else 0
	local facing = if x > cx then -1 else 1
	return CFrame.new(x, y + 3.4, 0) * CFrame.Angles(0, if facing > 0 then -math.pi / 2 else math.pi / 2, 0)
end

-- which zone is this point in (lobby sits far above the arenas)
function Arena.zoneAt(pos: Vector3): string
	return if pos.Y > 600 then "lobby" else "arena"
end

return Arena
