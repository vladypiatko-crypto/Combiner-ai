--!strict
-- Crate cosmetics: finishers (play when you KO someone) and entrances (play when you spawn).
-- Every item has a "1 in N" chance. Rolls check the rarest items first, so luck boosts
-- the odds of everything at once.

local Cosmetics = {}

export type Rarity = { id: number, name: string, color: Color3, glow: Color3, min: number }
export type Item = { id: string, kind: string, name: string, chance: number, rarity: number, desc: string, icon: string }

Cosmetics.RARITIES = {
	{ id = 1, name = "Common", color = Color3.fromRGB(201, 206, 216), glow = Color3.fromRGB(255, 255, 255), min = 1 },
	{ id = 2, name = "Uncommon", color = Color3.fromRGB(107, 214, 107), glow = Color3.fromRGB(170, 255, 150), min = 4 },
	{ id = 3, name = "Rare", color = Color3.fromRGB(63, 169, 255), glow = Color3.fromRGB(140, 210, 255), min = 16 },
	{ id = 4, name = "Epic", color = Color3.fromRGB(165, 107, 255), glow = Color3.fromRGB(210, 170, 255), min = 64 },
	{ id = 5, name = "Legendary", color = Color3.fromRGB(255, 201, 60), glow = Color3.fromRGB(255, 236, 150), min = 256 },
	{ id = 6, name = "Mythic", color = Color3.fromRGB(255, 77, 141), glow = Color3.fromRGB(255, 160, 200), min = 1000 },
	{ id = 7, name = "Celestial", color = Color3.fromRGB(120, 240, 255), glow = Color3.fromRGB(255, 255, 255), min = 5000 },
	{ id = 8, name = "Glitched", color = Color3.fromRGB(0, 255, 156), glow = Color3.fromRGB(255, 255, 255), min = 20000 },
} :: { Rarity }

local function rarityFor(chance: number): number
	local r = 1
	for _, t in Cosmetics.RARITIES do
		if chance >= t.min then
			r = t.id
		end
	end
	return r
end

local ITEMS = {
	-- finishers
	{ "pop", "finisher", "Pop", 0, "A classic burst of paint.", "💥" },
	{ "confetti", "finisher", "Confetti Cannon", 2, "Party time on their grave.", "🎉" },
	{ "splash", "finisher", "Paint Splash", 3, "A huge splash in their color.", "🎨" },
	{ "shockwave", "finisher", "Shockwave", 6, "A ring that rattles the screen.", "🌀" },
	{ "skull", "finisher", "Skull Pop", 9, "A giant skull pops out. Spooky.", "💀" },
	{ "thunder", "finisher", "Thunderclap", 24, "Lightning strikes where they fell.", "⚡" },
	{ "shatter", "finisher", "Pixel Shatter", 48, "They break into glowing cubes.", "🧊" },
	{ "fireworks", "finisher", "Firework Show", 120, "A full fireworks display.", "🎆" },
	{ "supernova", "finisher", "Supernova", 450, "A star collapses and explodes.", "🌟" },
	{ "blackhole", "finisher", "Black Hole", 1600, "Everything gets sucked in.", "🕳️" },
	{ "rift", "finisher", "Rainbow Rift", 7777, "Reality splits into color.", "🌈" },
	{ "glitch", "finisher", "GLITCH.EXE", 30000, "ERR: opponent.exe has stopped.", "👾" },
	-- entrances
	{ "drop", "spawn", "Drop In", 0, "A clean landing.", "⬇️" },
	{ "smoke", "spawn", "Smoke Puff", 2, "Appear from a puff of smoke.", "💨" },
	{ "paintbomb", "spawn", "Paint Bomb", 3, "Arrive with a splash.", "🖌️" },
	{ "sparks", "spawn", "Spark Fountain", 6, "Sparks shoot from your feet.", "✨" },
	{ "rings", "spawn", "Ring Pulse", 9, "Pulsing rings announce you.", "⭕" },
	{ "lightning", "spawn", "Lightning Strike", 25, "Struck down from the sky.", "🌩️" },
	{ "meteor", "spawn", "Meteor Landing", 50, "Crash in on a flaming rock.", "☄️" },
	{ "portal", "spawn", "Portal Jump", 130, "Step out of a portal.", "🌌" },
	{ "angel", "spawn", "Angel Descent", 480, "Float down in a beam of light.", "😇" },
	{ "void", "spawn", "Void Rift", 1800, "Crawl out of the void.", "🟣" },
	{ "starfall", "spawn", "Starfall", 8000, "Stars rain down around you.", "🌠" },
	{ "error404", "spawn", "ERROR 404", 33333, "Spawn not found. Spawning anyway.", "🚫" },
}

Cosmetics.items = {} :: { Item }
Cosmetics.byId = {} :: { [string]: Item }
for _, d in ITEMS do
	local it: Item = {
		id = d[1] :: string,
		kind = d[2] :: string,
		name = d[3] :: string,
		chance = d[4] :: number,
		rarity = if (d[4] :: number) == 0 then 1 else rarityFor(d[4] :: number),
		desc = d[5] :: string,
		icon = d[6] :: string,
	}
	table.insert(Cosmetics.items, it)
	Cosmetics.byId[it.id] = it
end

Cosmetics.DEFAULT = { finisher = "pop", spawn = "drop" }
Cosmetics.KINDS = { "finisher", "spawn" }
Cosmetics.KIND_NAMES = { finisher = "Finisher", spawn = "Entrance" }

function Cosmetics.ofKind(kind: string): { Item }
	local out = {}
	for _, it in Cosmetics.items do
		if it.kind == kind then
			table.insert(out, it)
		end
	end
	table.sort(out, function(a, b)
		return a.chance < b.chance
	end)
	return out
end

function Cosmetics.rarity(item: Item): Rarity
	return Cosmetics.RARITIES[item.rarity]
end

-- rarest-first roll. `rand` returns [0,1). `forceRarity` (admin testing) picks from a tier.
function Cosmetics.roll(kind: string, rand: () -> number, luck: number?, forceRarity: number?): Item
	local pool = Cosmetics.ofKind(kind)
	if forceRarity then
		local tier = {}
		for _, it in pool do
			if it.chance > 0 and it.rarity == forceRarity then
				table.insert(tier, it)
			end
		end
		if #tier > 0 then
			return tier[math.floor(rand() * #tier) + 1]
		end
	end
	local l = math.max(1, luck or 1)
	for i = #pool, 1, -1 do
		local it = pool[i]
		if it.chance > 0 and rand() < l / it.chance then
			return it
		end
	end
	-- nothing hit: the most common rollable item
	for _, it in pool do
		if it.chance > 0 then
			return it
		end
	end
	return pool[1]
end

function Cosmetics.formatChance(n: number): string
	if n <= 0 then
		return "default"
	end
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "1 in " .. out
end

return Cosmetics
