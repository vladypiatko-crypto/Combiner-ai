--!strict
-- Character rig helpers: ragdoll joints, facing / knockback movers, plane lock.
-- Works on any Humanoid rig (players' own R15 avatars and the bot mannequins).

local Rig = {}

-- ragdoll cone limits per joint (degrees)
local LIMITS: { [string]: { number } } = {
	Neck = { 40, 35 },
	Waist = { 30, 30 },
	LeftShoulder = { 110, 70 },
	RightShoulder = { 110, 70 },
	LeftElbow = { 100, 10 },
	RightElbow = { 100, 10 },
	LeftWrist = { 35, 20 },
	RightWrist = { 35, 20 },
	LeftHip = { 85, 30 },
	RightHip = { 85, 30 },
	LeftKnee = { 100, 10 },
	RightKnee = { 100, 10 },
	LeftAnkle = { 35, 15 },
	RightAnkle = { 35, 15 },
	-- R6 names
	["Left Shoulder"] = { 110, 70 },
	["Right Shoulder"] = { 110, 70 },
	["Left Hip"] = { 85, 30 },
	["Right Hip"] = { 85, 30 },
}

function Rig.motors(model: Model): { [string]: Motor6D }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			out[d.Name] = d
		end
	end
	return out
end

local function isRootJoint(m: Motor6D): boolean
	return m.Name == "Root" or m.Name == "RootJoint"
end

-- server: add (disabled) ragdoll sockets + movers to a freshly spawned character
function Rig.setup(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseCollide", d.CanCollide)
		end
		if d:IsA("Motor6D") and not isRootJoint(d) and d.Part0 and d.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "Rag0_" .. d.Name
			a0.CFrame = d.C0
			a0.Parent = d.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "Rag1_" .. d.Name
			a1.CFrame = d.C1
			a1.Parent = d.Part1
			local lim = LIMITS[d.Name] or { 45, 30 }
			local s = Instance.new("BallSocketConstraint")
			s.Name = "Rag_" .. d.Name
			s.Attachment0 = a0
			s.Attachment1 = a1
			s.LimitsEnabled = true
			s.UpperAngle = lim[1]
			s.TwistLimitsEnabled = true
			s.TwistLowerAngle = -lim[2]
			s.TwistUpperAngle = lim[2]
			s.Restitution = 0.1
			s.Enabled = false
			s.Parent = d.Parent
			local nc = Instance.new("NoCollisionConstraint")
			nc.Name = "RagNC_" .. d.Name
			nc.Part0 = d.Part0
			nc.Part1 = d.Part1
			nc.Parent = d.Parent
		end
	end

	local att = Instance.new("Attachment")
	att.Name = "RumbleAttachment"
	att.Parent = root

	local facing = Instance.new("AlignOrientation")
	facing.Name = "Facing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = att
	facing.MaxTorque = 1e7
	facing.Responsiveness = 60
	facing.CFrame = CFrame.Angles(0, -math.pi / 2, 0)
	facing.Parent = root

	local knock = Instance.new("LinearVelocity")
	knock.Name = "Knock"
	knock.Attachment0 = att
	knock.MaxForce = 1e7
	knock.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	knock.RelativeTo = Enum.ActuatorRelativeTo.World
	knock.VectorVelocity = Vector3.zero
	knock.Enabled = false
	knock.Parent = root
end

-- server: switch ragdoll on / off (replicates to everyone)
function Rig.setRagdoll(model: Model, on: boolean)
	if model:GetAttribute("Ragdoll") == on then
		return
	end
	model:SetAttribute("Ragdoll", on)
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and not isRootJoint(d) then
			d.Enabled = not on
		elseif d:IsA("BallSocketConstraint") and string.sub(d.Name, 1, 4) == "Rag_" then
			d.Enabled = on
		end
	end
	-- only the body parts themselves collide while floppy (not hats / weapons)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			if on and d.Name == "HumanoidRootPart" then
				d.CanCollide = false
			elseif on then
				d.CanCollide = true
			else
				d.CanCollide = d:GetAttribute("BaseCollide") == true
			end
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		local facing = root:FindFirstChild("Facing") :: AlignOrientation?
		if facing then
			facing.Enabled = not on
		end
	end
end

-- facing: +1 = looking toward +X (screen right), -1 = toward -X
function Rig.facingCFrame(facing: number): CFrame
	return CFrame.Angles(0, if facing > 0 then -math.pi / 2 else math.pi / 2, 0)
end

-- owner side: keep the whole body on the Z = 0 plane
function Rig.lockPlane(model: Model, root: BasePart, parts: { BasePart }?)
	local p = root.Position
	if math.abs(p.Z) > 0.04 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, 0, -p.Z))
	end
	if parts then
		for _, part in parts do
			local v = part.AssemblyLinearVelocity
			if math.abs(v.Z) > 0.05 then
				part.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z * 0.3)
			end
		end
	else
		local v = root.AssemblyLinearVelocity
		if math.abs(v.Z) > 0.05 then
			root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
		end
	end
end

function Rig.bodyParts(model: Model): { BasePart }
	local out = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- owner side: throw every body part (used when a ragdoll starts)
function Rig.fling(model: Model, vel: Vector3, spin: number)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = vel + Vector3.new((math.random() - 0.5) * 6, (math.random() - 0.5) * 6, 0)
			d.AssemblyAngularVelocity = Vector3.new(0, 0, spin + (math.random() - 0.5) * 4)
		end
	end
end

return Rig
