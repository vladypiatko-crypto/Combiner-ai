-- Sanity checks for arena layouts + crate odds (run: tools/check.sh). Runs outside Roblox.
Color3 = Color3 or { fromRGB = function(r, g, b) return { r, g, b } end }
local Maps = __req("Maps")
local Motion = __req("Motion")
local Weapons = __req("Weapons")
local Cosmetics = __req("Cosmetics")

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

local all = table.clone(Maps.list)
table.insert(all, Maps.lobby)
for mi, map in all do
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
	check(map == Maps.lobby or #map.spawns >= 8, map.name .. " needs 8 spawns")
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

-- crate odds: rarest-first "1 in N" rolls
local seed = 12345
local function rand()
	seed = (seed * 1664525 + 1013904223) % 4294967296
	return seed / 4294967296
end
for _, kind in Cosmetics.KINDS do
	local counts, n = {}, 200000
	for _ = 1, n do
		local it = Cosmetics.roll(kind, rand, 1)
		counts[it.id] = (counts[it.id] or 0) + 1
	end
	print("odds for " .. kind .. " crates (" .. n .. " rolls):")
	for _, it in Cosmetics.ofKind(kind) do
		if it.chance > 0 then
			local got = (counts[it.id] or 0) / n
			print(string.format("  %-18s %-10s expected~%-9s got 1 in %s", it.name, Cosmetics.rarity(it).name, Cosmetics.formatChance(it.chance), if got > 0 then string.format("%.0f", 1 / got) else "-"))
		end
	end
	check((counts[Cosmetics.ofKind(kind)[2].id] or 0) > n * 0.3, kind .. ": the most common item should dominate")
	for r = 1, 8 do
		local it = Cosmetics.roll(kind, rand, 1, r)
		check(it.rarity == r, kind .. " forced rarity " .. r)
	end
end
check(Cosmetics.formatChance(30000) == "1 in 30,000", "chance formatting")
print(if fails == 0 then "ALL CHECKS PASSED" else ("FAILURES: " .. fails))
