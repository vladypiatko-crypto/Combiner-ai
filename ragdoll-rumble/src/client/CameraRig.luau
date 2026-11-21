--!strict
-- Side-on "couch fighter" camera: frames every living fighter, eases zoom, adds shake.

local CameraRig = {}

local FOV = 34
local MIN_H, MAX_H = 34, 80

local cam: Camera = workspace.CurrentCamera
local cx, cy, h = 0, 8, 50
local trauma = 0
local punch = Vector2.zero
local bounds = { left = -60, right = 60, bottom = -30, top = 50 }
local t = 0
local zoomPunch = 0
CameraRig.shakeEnabled = true

function CameraRig.reset(b: { left: number, right: number, bottom: number, top: number })
	bounds = b
	cx = (b.left + b.right) * 0.5
	cy = (b.bottom + b.top) * 0.5 - 6
	h = MAX_H
	trauma = 0
end

function CameraRig.shake(amount: number)
	if CameraRig.shakeEnabled then
		trauma = math.min(1, trauma + amount)
	end
end

-- quick zoom-in on heavy impacts
function CameraRig.punchZoom(amount: number)
	if CameraRig.shakeEnabled then
		zoomPunch = math.min(0.25, zoomPunch + amount)
	end
end

function CameraRig.setBounds(b: { left: number, right: number, bottom: number, top: number })
	bounds = b
end

-- directional kick (e.g. recoil / big hit)
function CameraRig.kick(dx: number, dy: number)
	punch += Vector2.new(dx, dy)
end

function CameraRig.update(dt: number, targets: { Vector2 }, zoomBias: number?, snap: boolean?)
	cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	t += dt
	local vp = cam.ViewportSize
	local aspect = if vp.Y > 0 then vp.X / vp.Y else 16 / 9

	local tx, ty, th
	if #targets == 0 then
		tx = (bounds.left + bounds.right) * 0.5
		ty = (bounds.bottom + bounds.top) * 0.5 - 6
		th = MAX_H
	else
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, p in targets do
			minX = math.min(minX, p.X)
			maxX = math.max(maxX, p.X)
			minY = math.min(minY, p.Y)
			maxY = math.max(maxY, p.Y)
		end
		minX -= 9
		maxX += 9
		minY -= 6
		maxY += 9
		tx = (minX + maxX) * 0.5
		ty = (minY + maxY) * 0.5
		th = math.max(maxY - minY, (maxX - minX) / aspect)
		th = math.clamp(th * (zoomBias or 1), MIN_H, MAX_H)
	end

	-- keep the view mostly inside the arena
	local halfW = th * aspect * 0.5
	local left, right = bounds.left - 10, bounds.right + 10
	if right - left > halfW * 2 then
		tx = math.clamp(tx, left + halfW, right - halfW)
	else
		tx = (left + right) * 0.5
	end
	ty = math.clamp(ty, bounds.bottom + th * 0.5 - 6, bounds.top - th * 0.5 + 10)

	local k = if snap then 1 else 1 - math.exp(-dt * 3.2)
	local kz = if snap then 1 else 1 - math.exp(-dt * 2.2)
	cx += (tx - cx) * k
	cy += (ty - cy) * k
	h += (th - h) * kz

	trauma = math.max(0, trauma - dt * 1.6)
	punch *= math.exp(-dt * 12)
	local s = trauma * trauma
	local sx = (math.noise(t * 25, 0.3) * 2) * s * 1.4 + punch.X
	local sy = (math.noise(0.7, t * 25) * 2) * s * 1.4 + punch.Y
	local roll = math.noise(t * 20, 4.2) * s * 0.035

	zoomPunch = math.max(0, zoomPunch - dt * 1.2)
	local hh = h * (1 - zoomPunch)
	local dist = (hh * 0.5) / math.tan(math.rad(FOV * 0.5))
	-- a slight look-down angle shows off the 3D depth of the arena
	local eye = Vector3.new(cx + sx, cy + sy + hh * 0.2, dist)
	cam.CFrame = CFrame.lookAt(eye, Vector3.new(cx + sx, cy + sy, 0)) * CFrame.Angles(0, 0, roll)
	cam.Focus = CFrame.new(cx, cy, 0)
end

-- world point on the z = 0 plane under a viewport position
function CameraRig.toWorld(screen: Vector2): Vector2?
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	local dz = ray.Direction.Z
	if math.abs(dz) < 1e-5 then
		return nil
	end
	local s = -ray.Origin.Z / dz
	local p = ray.Origin + ray.Direction * s
	return Vector2.new(p.X, p.Y)
end

function CameraRig.viewHeight(): number
	return h
end

return CameraRig
