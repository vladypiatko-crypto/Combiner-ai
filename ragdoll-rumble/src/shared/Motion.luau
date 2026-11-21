--!strict
-- Time-driven motion for moving platforms / saws. Pure math so the server (physics) and
-- every client (visuals, hazards) agree exactly when given the same round time.

local Motion = {}

local sin, cos, pi = math.sin, math.cos, math.pi

-- returns x, y, angle (radians, about Z)
function Motion.pose(m: any?, bx: number, by: number, ba: number, t: number): (number, number, number)
	if not m then
		return bx, by, ba
	end
	local period = m.period or 4
	local w = 2 * pi / period
	local ph = m.phase or 0
	if m.type == "sine" then
		local k = sin(t * w + ph)
		return bx + (m.ax or 0) * k, by + (m.ay or 0) * k, ba
	elseif m.type == "orbit" then
		local a = t * w + ph
		local r = m.radius or 10
		return (m.cx or bx) + cos(a) * r, (m.cy or by) + sin(a) * r, ba
	elseif m.type == "pendulum" then
		local th = (m.amp or 0.5) * sin(t * w + ph)
		local len = m.len or 10
		return (m.px or bx) + sin(th) * len, (m.py or by) - cos(th) * len, ba
	elseif m.type == "spin" then
		return bx, by, ba + (m.speed or 1) * t
	end
	return bx, by, ba
end

return Motion
