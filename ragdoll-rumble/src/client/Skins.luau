--!strict
-- Turns the Blender mesh data (Shared/MeshData) into MeshParts at runtime with EditableMesh,
-- then "skins" any instance the server tagged with RumbleSkin. If mesh APIs are unavailable
-- the part-built fallback models simply stay visible.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MeshData = require(Shared:WaitForChild("MeshData")) :: any

local Skins = {}
Skins.ok = nil :: boolean?
Skins.err = nil :: string?
Skins.built = 0

type Template = { part: MeshPart, center: Vector3, size: Vector3 }
local templates: { [string]: { solid: Template?, glow: Template? } } = {}
local pending: { Instance } = {}
local ready = false

local function hexColor(h: number): Color3
	return Color3.fromRGB(bit32.rshift(h, 16) % 256, bit32.rshift(h, 8) % 256, h % 256)
end

local function buildSub(sub: any, glow: boolean): Template
	local v = sub.v
	local n = #v // 3
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	local pos = table.create(n)
	for i = 1, n do
		local p = Vector3.new(v[i * 3 - 2], v[i * 3 - 1], v[i * 3])
		pos[i] = p
		mn = mn:Min(p)
		mx = mx:Max(p)
	end
	local center = (mn + mx) * 0.5
	local size = (mx - mn):Max(Vector3.new(0.05, 0.05, 0.05))

	local em = (AssetService :: any):CreateEditableMesh()
	local colors = {}
	for i, hex in sub.pal do
		colors[i] = em:AddColor(hexColor(hex), 1)
	end
	local ids = table.create(n)
	for i = 1, n do
		ids[i] = em:AddVertex(pos[i] - center)
	end
	local t, c = sub.t, sub.c
	for k = 1, #c do
		local a, b, cc = t[k * 3 - 2], t[k * 3 - 1], t[k * 3]
		local pa, pb, pc = pos[a], pos[b], pos[cc]
		local nrm = (pb - pa):Cross(pc - pa)
		if nrm.Magnitude < 1e-9 then
			continue
		end
		local nid = em:AddNormal(nrm.Unit)
		local col = colors[c[k]]
		-- both windings, both using the outward normal: visible + correctly lit either way
		local f1 = em:AddTriangle(ids[a], ids[b], ids[cc])
		em:SetFaceNormals(f1, { nid, nid, nid })
		em:SetFaceColors(f1, { col, col, col })
		local f2 = em:AddTriangle(ids[a], ids[cc], ids[b])
		em:SetFaceNormals(f2, { nid, nid, nid })
		em:SetFaceColors(f2, { col, col, col })
	end
	local mp = (AssetService :: any):CreateMeshPartAsync((Content :: any).fromObject(em)) :: MeshPart
	mp.Size = size
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = not glow
	mp.Massless = true
	mp.Color = Color3.new(1, 1, 1)
	mp.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	return { part = mp, center = center, size = size }
end

-- clone a mesh (solid + optional glow) into a Model placed at `cf` (the asset's origin)
function Skins.clone(name: string, cf: CFrame, scale: number?): Model?
	local tpl = templates[name]
	if not tpl then
		return nil
	end
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Skin_" .. name
	for _, key in { "solid", "glow" } do
		local sub = (tpl :: any)[key] :: Template?
		if sub then
			local p = sub.part:Clone()
			p.Size = sub.size * s
			p.CFrame = cf * CFrame.new(sub.center * s)
			p.Parent = m
			if key == "solid" then
				m.PrimaryPart = p
			end
		end
	end
	return m
end

function Skins.has(name: string): boolean
	return templates[name] ~= nil
end

-- dress one tagged anchor: weld the mesh onto it and hide the fallback siblings
local function apply(anchor: Instance)
	if not anchor:IsA("BasePart") or anchor:GetAttribute("Skinned") then
		return
	end
	local name = anchor:GetAttribute("Skin")
	if type(name) ~= "string" or not templates[name] then
		return
	end
	local scale = anchor:GetAttribute("SkinScale")
	local m = Skins.clone(name, anchor.CFrame, if type(scale) == "number" then scale else 1)
	if not m then
		return
	end
	anchor:SetAttribute("Skinned", true)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = anchor
			w.Part1 = p
			w.Parent = p
		end
	end
	m.Parent = anchor
	local holder = anchor.Parent
	if holder then
		if holder:IsA("BasePart") and holder:GetAttribute("Fallback") then
			holder.Transparency = 1
		end
		for _, d in holder:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Fallback") then
				d.Transparency = 1
			end
		end
	end
end

local function onTagged(inst: Instance)
	if ready then
		task.defer(apply, inst)
	else
		table.insert(pending, inst)
	end
end

function Skins.init(onDone: ((boolean, string?) -> ())?)
	CollectionService:GetInstanceAddedSignal("RumbleSkin"):Connect(onTagged)
	for _, inst in CollectionService:GetTagged("RumbleSkin") do
		onTagged(inst)
	end
	task.spawn(function()
		local names = {}
		for name in MeshData do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local data = MeshData[name]
			local ok, err = pcall(function()
				local entry = {}
				if data.solid then
					entry.solid = buildSub(data.solid, false)
				end
				if data.glow then
					entry.glow = buildSub(data.glow, true)
				end
				templates[name] = entry
			end)
			if not ok then
				Skins.ok = false
				Skins.err = tostring(err)
				warn("[Ragdoll Rumble] mesh models unavailable, using part models instead:", err)
				break
			end
			Skins.built += 1
			task.wait()
		end
		if Skins.ok ~= false then
			Skins.ok = true
		end
		ready = true
		for _, inst in pending do
			if inst.Parent then
				apply(inst)
			end
		end
		pending = {}
		if onDone then
			onDone(Skins.ok == true, Skins.err)
		end
	end)
end

return Skins
