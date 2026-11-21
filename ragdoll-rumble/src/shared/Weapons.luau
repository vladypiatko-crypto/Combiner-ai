--!strict
-- Weapon definitions. Models are built from boxes in weapon space:
-- +X = barrel / blade direction, +Y = up, origin = the grip (held in the right hand).

export type Part = { x: number, y: number, z: number?, w: number, h: number, d: number?, color: number, neon: boolean?, shape: string? }

export type Weapon = {
	id: number,
	key: string,
	name: string,
	kind: string, -- "gun" | "melee" | "throwable" | "launcher"
	weight: number,
	ammo: number,
	rate: number,
	auto: boolean,
	pellets: number,
	spread: number,
	range: number,
	speed: number,
	damage: number,
	knock: number,
	ragdoll: number,
	recoil: number,
	twoHanded: boolean,
	length: number,
	swingTime: number,
	deflect: boolean,
	fuse: number,
	radius: number,
	headMult: number,
	sound: string,
	tracer: number,
	parts: { Part },
}

local Weapons = {}
Weapons.list = {} :: { Weapon }
Weapons.byKey = {} :: { [string]: Weapon }

local function def(w: any)
	w.ammo = w.ammo or 1
	w.rate = w.rate or 0.3
	w.auto = w.auto or false
	w.pellets = w.pellets or 1
	w.spread = w.spread or 0
	w.range = w.range or 140
	w.speed = w.speed or 0
	w.damage = w.damage or 10
	w.knock = w.knock or 15
	w.ragdoll = w.ragdoll or 0
	w.recoil = w.recoil or 0
	w.twoHanded = w.twoHanded or false
	w.length = w.length or 1.2
	w.swingTime = w.swingTime or 0.25
	w.deflect = w.deflect or false
	w.fuse = w.fuse or 0
	w.radius = w.radius or 0
	w.headMult = w.headMult or 1.5
	w.sound = w.sound or "pistol"
	w.tracer = w.tracer or 0xfff4aa
	w.weight = w.weight or 1
	table.insert(Weapons.list, w)
	w.id = #Weapons.list
	Weapons.byKey[w.key] = w
end

local METAL = 0x2b2f3a
local DARK = 0x16181f
local WOOD = 0x9a6233

def({
	key = "popper",
	name = "Popper",
	kind = "gun",
	weight = 1.3,
	ammo = 10,
	rate = 0.2,
	damage = 20,
	knock = 26,
	spread = 0.015,
	recoil = 6,
	length = 1.5,
	sound = "pistol",
	parts = {
		{ x = 0.55, y = 0.15, w = 1.4, h = 0.42, d = 0.32, color = METAL },
		{ x = 0.05, y = -0.25, w = 0.36, h = 0.7, d = 0.3, color = DARK },
		{ x = 1.15, y = 0.15, w = 0.2, h = 0.26, d = 0.34, color = 0xffd34d, neon = true },
	},
})

def({
	key = "scatter",
	name = "Scattergun",
	kind = "gun",
	weight = 1,
	ammo = 4,
	rate = 0.7,
	pellets = 7,
	spread = 0.2,
	range = 42,
	damage = 11,
	knock = 32,
	recoil = 48,
	twoHanded = true,
	length = 2.6,
	sound = "shotgun",
	tracer = 0xffc86b,
	parts = {
		{ x = 1.1, y = 0.12, w = 2.8, h = 0.4, d = 0.36, color = METAL },
		{ x = 1.3, y = -0.18, w = 1.3, h = 0.3, d = 0.4, color = WOOD },
		{ x = -0.6, y = -0.05, w = 1.1, h = 0.5, d = 0.34, color = WOOD },
	},
})

def({
	key = "buzzer",
	name = "Buzzer",
	kind = "gun",
	weight = 1,
	ammo = 34,
	rate = 0.075,
	auto = true,
	damage = 6,
	knock = 11,
	spread = 0.08,
	recoil = 3,
	twoHanded = true,
	length = 2,
	sound = "smg",
	tracer = 0x7df9ff,
	parts = {
		{ x = 0.7, y = 0.12, w = 2, h = 0.46, d = 0.36, color = DARK },
		{ x = 0.4, y = -0.42, w = 0.3, h = 0.75, d = 0.3, color = METAL },
		{ x = -0.45, y = 0.05, w = 0.6, h = 0.36, d = 0.3, color = METAL },
		{ x = 1.6, y = 0.12, w = 0.22, h = 0.24, d = 0.38, color = 0x3cf2e0, neon = true },
	},
})

def({
	key = "longshot",
	name = "Longshot",
	kind = "gun",
	weight = 0.7,
	ammo = 3,
	rate = 1.0,
	damage = 95,
	knock = 85,
	ragdoll = 1.6,
	range = 400,
	recoil = 30,
	twoHanded = true,
	length = 3.6,
	sound = "sniper",
	tracer = 0xff4d5e,
	parts = {
		{ x = 1.5, y = 0.1, w = 4, h = 0.3, d = 0.3, color = DARK },
		{ x = 0.7, y = 0.5, w = 1.1, h = 0.3, d = 0.3, color = METAL, shape = "cyl" },
		{ x = -0.6, y = -0.02, w = 1.1, h = 0.52, d = 0.34, color = 0x3d4a5e },
		{ x = 3.45, y = 0.1, w = 0.2, h = 0.2, d = 0.32, color = 0xff4d5e, neon = true },
	},
})

def({
	key = "edge",
	name = "Edge",
	kind = "melee",
	weight = 1,
	rate = 0.4,
	swingTime = 0.22,
	damage = 38,
	knock = 48,
	ragdoll = 0.8,
	length = 3.6,
	deflect = true,
	sound = "slash",
	parts = {
		{ x = 2.05, y = 0, w = 3.2, h = 0.28, d = 0.12, color = 0xdfe8ff, neon = true },
		{ x = 0.3, y = 0, w = 0.2, h = 0.95, d = 0.35, color = 0xffc93c },
		{ x = -0.1, y = 0, w = 0.75, h = 0.24, d = 0.24, color = DARK },
	},
})

def({
	key = "bonker",
	name = "Bonker",
	kind = "melee",
	weight = 1,
	rate = 0.6,
	swingTime = 0.3,
	damage = 18,
	knock = 125,
	ragdoll = 1.8,
	length = 3.4,
	sound = "bonk",
	parts = {
		{ x = 0.7, y = 0, w = 1.9, h = 0.32, d = 0.32, color = WOOD, shape = "cyl" },
		{ x = 2.4, y = 0, w = 1.7, h = 0.62, d = 0.62, color = 0xc07a3f, shape = "cyl" },
	},
})

def({
	key = "fizz",
	name = "Fizzbomb",
	kind = "throwable",
	weight = 0.9,
	ammo = 3,
	rate = 0.65,
	speed = 75,
	fuse = 1.8,
	radius = 11,
	damage = 60,
	knock = 120,
	ragdoll = 1.8,
	length = 0.8,
	sound = "throw",
	parts = {
		{ x = 0.15, y = 0, w = 0.9, h = 0.9, d = 0.9, color = 0x2f9e44, shape = "ball" },
		{ x = 0.15, y = 0.55, w = 0.3, h = 0.25, d = 0.3, color = 0xffd34d, neon = true },
	},
})

def({
	key = "boomtube",
	name = "Boomtube",
	kind = "launcher",
	weight = 0.6,
	ammo = 2,
	rate = 0.9,
	speed = 95,
	radius = 10,
	damage = 70,
	knock = 130,
	ragdoll = 2,
	recoil = 34,
	twoHanded = true,
	length = 3.2,
	sound = "rocket",
	parts = {
		{ x = 0.9, y = 0.2, w = 3.4, h = 0.75, d = 0.75, color = 0x4c6b3a, shape = "cyl" },
		{ x = 2.65, y = 0.2, w = 0.3, h = 0.9, d = 0.9, color = DARK, shape = "cyl" },
		{ x = 0.3, y = -0.4, w = 0.3, h = 0.6, d = 0.3, color = DARK },
		{ x = -0.85, y = 0.2, w = 0.2, h = 0.6, d = 0.6, color = 0xff8f3c, neon = true },
	},
})

-- thrown weapon hitting someone
Weapons.THROWN = { damage = 16, knock = 60, ragdoll = 1.0 }

function Weapons.get(id: number?): Weapon?
	if id == nil or id == 0 then
		return nil
	end
	return Weapons.list[id]
end

function Weapons.pick(r: number): Weapon
	local total = 0
	for _, w in Weapons.list do
		total += w.weight
	end
	local x = r * total
	for _, w in Weapons.list do
		x -= w.weight
		if x <= 0 then
			return w
		end
	end
	return Weapons.list[1]
end

-- deterministic pellet directions so every client draws the same spread
function Weapons.angles(w: Weapon, aim: number, seed: number): { number }
	local out = {}
	local s = seed
	for i = 1, w.pellets do
		-- small LCG constants keep every product exact in doubles (identical on all machines)
		s = (s * 1664525 + 1013904223) % 4294967296
		local r = s / 4294967296 - 0.5
		if w.pellets > 1 then
			out[i] = aim + ((i - 0.5) / w.pellets - 0.5) * 2 * w.spread + r * w.spread * 0.3
		else
			out[i] = aim + r * 2 * w.spread
		end
	end
	return out
end

return Weapons
