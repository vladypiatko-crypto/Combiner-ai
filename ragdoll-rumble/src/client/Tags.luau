--!strict
-- Per-fighter overlays: colored outline, name + health tag, launch trail.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Tags = {}

type Tag = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	gui: BillboardGui,
	name: TextLabel,
	hpBack: Frame,
	hpFill: Frame,
	trail: Trail?,
	lastHp: number,
	show: number,
	color: Color3,
	dead: boolean,
}

local tags: { [Model]: Tag } = {}

function Tags.color(model: Model): Color3
	local ci = model:GetAttribute("ColorIndex")
	local c = Config.COLORS[if type(ci) == "number" then ci else 1] or Config.COLORS[1]
	return c.main
end

function Tags.add(model: Model, isMe: boolean)
	if tags[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	if not humanoid or not root or not head then
		return
	end
	local color = Tags.color(model)

	local hl = Instance.new("Highlight")
	hl.Name = "RumbleOutline"
	hl.Adornee = model
	hl.FillTransparency = 1
	hl.OutlineColor = color
	hl.OutlineTransparency = if isMe then 0 else 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "RumbleTag"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 22)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = if isMe then 20 else 16
	name.Text = if isMe then "▼ YOU ▼" else (model:GetAttribute("FighterName") or model.Name) :: string
	name.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(15, 14, 24)
	stroke.Parent = name
	local back = Instance.new("Frame")
	back.Size = UDim2.new(0, 70, 0, 8)
	back.Position = UDim2.new(0.5, -35, 0, 26)
	back.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
	back.BorderSizePixel = 0
	back.BackgroundTransparency = 1
	back.Parent = gui
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.BackgroundTransparency = 1
	fill.Parent = back
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	gui.Parent = model

	-- launch trail (shows when sent flying)
	local trail: Trail? = nil
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailTop"
		a0.Position = Vector3.new(0, torso.Size.Y * 0.5, 0)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailBottom"
		a1.Position = Vector3.new(0, -torso.Size.Y * 0.5, 0)
		a1.Parent = torso
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Lifetime = 0.3
		t.LightEmission = 0.8
		t.FaceCamera = true
		t.Color = ColorSequence.new(color)
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		t.Enabled = false
		t.Parent = torso
		trail = t
	end

	tags[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		gui = gui,
		name = name,
		hpBack = back,
		hpFill = fill,
		trail = trail,
		lastHp = humanoid.Health,
		show = 0,
		color = color,
		dead = false,
	}
end

function Tags.remove(model: Model)
	tags[model] = nil
end

function Tags.update(dt: number)
	for model, tag in tags do
		if not model.Parent then
			tags[model] = nil
			continue
		end
		local hp = tag.humanoid.Health
		if hp ~= tag.lastHp then
			tag.lastHp = hp
			tag.show = 3
			local frac = math.clamp(hp / Config.MAX_HP, 0, 1)
			tag.hpFill.Size = UDim2.fromScale(frac, 1)
			tag.hpFill.BackgroundColor3 = if frac > 0.5 then tag.color elseif frac > 0.25 then Color3.fromRGB(255, 190, 60) else Color3.fromRGB(255, 70, 70)
		end
		local dead = hp <= 0
		if dead ~= tag.dead then
			tag.dead = dead
			tag.name.TextTransparency = if dead then 0.65 else 0
		end
		if tag.show > 0 and not dead then
			tag.show -= dt
			local tr = if tag.show < 0.5 then 1 - tag.show * 2 else 0
			tag.hpBack.BackgroundTransparency = 0.25 + tr * 0.75
			tag.hpFill.BackgroundTransparency = tr
		else
			tag.hpBack.BackgroundTransparency = 1
			tag.hpFill.BackgroundTransparency = 1
		end
		if tag.trail then
			local speed = tag.root.AssemblyLinearVelocity.Magnitude
			tag.trail.Enabled = speed > 55
		end
	end
end

return Tags
