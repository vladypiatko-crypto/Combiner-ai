-- Sanity checks for arena layouts (run: tools/check.sh). Pure logic, no Roblox APIs.
local Maps = __req("Maps")
local Motion = __req("Motion")
local Weapons = __req("Weapons")

local fails = 0
local function check(ok, msg)
	if not ok then
		fails += 1
		print("  FAIL " .. msg)
	end
end

local function blockAt(def, t)
	local x, y = Motion.pose(def.motion, def.x, def.y, math.rad(def.angle or 0), t)
	return x, y
end

for mi, map in Maps.list do
	print(map.name)
	for si, sp in map.spawns do
		local sx, sy = sp[1], sp[2]
		-- standing volume (avatar ~ 2 wide, 5.5 tall) must be free
		local buried, ground = false, false
		for _, b in map.blocks do
			if not b.motion or b.motion.type == "sine" then
				local bx, by = blockAt(b, 0)
				local hw, hh = b.w / 2, b.h / 2
				if math.abs(sx - bx) < hw + 1 and (sy + 0.3) < by + hh and (sy + 5.5) > by - hh then
					buried = true
				end
				if math.abs(sx - bx) < hw + 0.5 and math.abs((by + hh) - sy) < 1.6 then
					ground = true
				end
			end
		end
		check(not buried, string.format("%s spawn %d (%g,%g) is inside geometry", map.name, si, sx, sy))
		check(ground, string.format("%s spawn %d (%g,%g) has no floor under it", map.name, si, sx, sy))
	end
	check(map.weaponX[1] > map.bounds.left and map.weaponX[2] < map.bounds.right, map.name .. " weapon drops outside bounds")
	check(#map.spawns >= 8, map.name .. " needs 8 spawns")
	check(map.killY < map.bounds.bottom, map.name .. " killY should be below the camera bottom")
end

-- pellet spreads are deterministic and sane
for _, w in Weapons.list do
	local a = Weapons.angles(w, 0, 12345)
	local b = Weapons.angles(w, 0, 12345)
	check(#a == w.pellets, w.name .. " pellet count")
	for i = 1, #a do
		check(a[i] == b[i], w.name .. " deterministic spread")
		check(math.abs(a[i]) <= w.spread * 1.4 + 1e-9, w.name .. " spread within limits")
	end
end

print(if fails == 0 then "ALL MAP CHECKS PASSED" else ("FAILURES: " .. fails))
