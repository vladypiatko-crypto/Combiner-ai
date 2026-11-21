--!strict
-- Small math helpers + a deterministic PRNG (no Roblox APIs so tests can run anywhere).

local Util = {}

local sqrt, atan2, cos, sin, floor = math.sqrt, math.atan2, math.cos, math.sin, math.floor

function Util.clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.len(x: number, y: number): number
	return sqrt(x * x + y * y)
end

function Util.norm(x: number, y: number): (number, number, number)
	local l = sqrt(x * x + y * y)
	if l < 1e-9 then
		return 0, 0, 0
	end
	return x / l, y / l, l
end

function Util.angle(x: number, y: number): number
	return atan2(y, x)
end

function Util.dir(a: number): (number, number)
	return cos(a), sin(a)
end

function Util.sign(x: number): number
	if x > 0 then
		return 1
	elseif x < 0 then
		return -1
	end
	return 0
end

-- wrap angle to (-pi, pi]
function Util.wrap(a: number): number
	a = (a + math.pi) % (2 * math.pi)
	if a < 0 then
		a += 2 * math.pi
	end
	return a - math.pi
end

-- distance from point P to segment AB, plus closest point and parameter t
function Util.pointSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number): (number, number, number, number)
	local abx, aby = bx - ax, by - ay
	local l2 = abx * abx + aby * aby
	local t = 0
	if l2 > 1e-9 then
		t = Util.clamp(((px - ax) * abx + (py - ay) * aby) / l2, 0, 1)
	end
	local cx, cy = ax + abx * t, ay + aby * t
	local dx, dy = px - cx, py - cy
	return sqrt(dx * dx + dy * dy), cx, cy, t
end

-- ray (origin + dir * s, s in [0, maxS]) vs circle. returns s or nil
function Util.rayCircle(ox: number, oy: number, dx: number, dy: number, maxS: number, cx: number, cy: number, r: number): number?
	local fx, fy = ox - cx, oy - cy
	local b = fx * dx + fy * dy
	local c = fx * fx + fy * fy - r * r
	if c <= 0 then
		return 0
	end
	if b > 0 then
		return nil
	end
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local s = -b - sqrt(disc)
	if s < 0 or s > maxS then
		return nil
	end
	return s
end

-- ray vs capsule (segment AB with radius r): approximated by sampling the closest approach
function Util.rayCapsule(ox: number, oy: number, dx: number, dy: number, maxS: number, ax: number, ay: number, bx: number, by: number, r: number): number?
	-- solve closest points between the ray segment and AB
	local ex, ey = ox + dx * maxS, oy + dy * maxS
	-- segment-segment closest distance using parametric clamp
	local ux, uy = ex - ox, ey - oy
	local vx, vy = bx - ax, by - ay
	local wx, wy = ox - ax, oy - ay
	local a = ux * ux + uy * uy
	local b = ux * vx + uy * vy
	local c = vx * vx + vy * vy
	local d = ux * wx + uy * wy
	local e = vx * wx + vy * wy
	local D = a * c - b * b
	local sc, tc
	if D < 1e-9 then
		sc = 0
		tc = if c > 1e-9 then Util.clamp(e / c, 0, 1) else 0
	else
		sc = Util.clamp((b * e - c * d) / D, 0, 1)
		tc = if c > 1e-9 then Util.clamp((b * sc + e) / c, 0, 1) else 0
		-- recompute sc for the clamped tc
		sc = if a > 1e-9 then Util.clamp((tc * b - d) / a, 0, 1) else 0
	end
	local px, py = ox + ux * sc, oy + uy * sc
	local qx, qy = ax + vx * tc, ay + vy * tc
	local ddx, ddy = px - qx, py - qy
	if ddx * ddx + ddy * ddy > r * r then
		return nil
	end
	-- step back to the surface roughly: hit distance along ray
	return math.max(0, sc * maxS - r * 0.5)
end

-- xorshift32 PRNG -------------------------------------------------------------
export type Rng = { state: number, next: (Rng) -> number, range: (Rng, number, number) -> number, int: (Rng, number, number) -> number }

local function rngNext(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end

local function rngRange(self: Rng, a: number, b: number): number
	return a + (b - a) * rngNext(self)
end

local function rngInt(self: Rng, a: number, b: number): number
	return a + floor(rngNext(self) * (b - a + 1))
end

function Util.rng(seed: number): Rng
	local s = floor(seed) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	return { state = s, next = rngNext, range = rngRange, int = rngInt }
end

function Util.hexToRGB(hex: number): (number, number, number)
	return bit32.rshift(hex, 16) % 256, bit32.rshift(hex, 8) % 256, hex % 256
end

function Util.shuffle<T>(list: { T }, rng: Rng): { T }
	for i = #list, 2, -1 do
		local j = rng:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- silence unused warnings for helpers only used in some builds
local _ = cos
local _ = sin

return Util
