--!strict
-- Ragdoll Rumble: global tunables (movement, combat, rounds, bots).

local Config = {}

-- World / movement (side-view: everyone lives on the Z = 0 plane)
Config.GRAVITY = 165
Config.WALK_SPEED = 21
Config.JUMP_POWER = 54
Config.DOUBLE_JUMP_VELOCITY = 50
Config.FAST_FALL = 140 -- extra downward accel while holding crouch in the air
Config.PLANE_Z = 0

-- Health / combat
Config.MAX_HP = 100
Config.PUNCH_DAMAGE = 7
Config.PUNCH_KNOCK = 42
Config.PUNCH_COOLDOWN = 0.3
Config.PUNCH_REACH = 2.7 -- shoulder -> fist distance at full extension
Config.PUNCH_RADIUS = 2.3
Config.BLOCK_REDUCTION = 0.8
Config.BLOCK_SPEED = 0.45
Config.PARRY_WINDOW = 0.2
Config.STAGGER_LIMIT = 28 -- accumulated damage within a short window that knocks you into ragdoll
Config.STAGGER_DECAY = 14 -- per second
Config.THROW_SPEED = 95
Config.PICKUP_RADIUS = 3.6
Config.KNOCK_TIME = 0.16 -- how long a non-ragdoll knockback overrides movement

-- Rounds / match
Config.WINS_TO_MATCH = 5
Config.COUNTDOWN = 3
Config.LOAD_TIME = 1.5 -- time given to load avatars before the countdown starts
Config.ROUND_END_DELAY = 4
Config.MATCH_END_DELAY = 7
Config.SUDDEN_DEATH_AT = 60 -- seconds of fighting before the ink starts rising
Config.SUDDEN_DEATH_SPEED = 2.4
Config.WEAPON_SPAWN_MIN = 3.5
Config.WEAPON_SPAWN_MAX = 7
Config.MAX_GROUND_WEAPONS = 6
Config.WEAPON_DESPAWN = 30

-- Lobby / match flow
Config.INTERMISSION = 25 -- lobby countdown before a match
Config.SOLO_INTERMISSION = 12 -- shorter when you're alone
Config.READY_SHORTCUT = 4 -- everyone ready -> start in this many seconds
Config.MAX_ROUNDS = 9 -- a match also ends after this many rounds
Config.RESULTS_TIME = 9
Config.LOBBY_RESPAWN = 2
Config.DUMMY_RESPAWN = 3
Config.LOBBY_WEAPONS = 3 -- weapons lying around the lobby training area

-- Economy / crates
Config.START_COINS = 500
Config.COINS_KO = 15
Config.COINS_ROUND_WIN = 30
Config.COINS_MATCH_WIN = 150
Config.COINS_PLAYED = 20
Config.CRATE_COST = 100
Config.DUPE_REFUND = 25 -- coins back for a duplicate Common / Uncommon
Config.ANNOUNCE_RARITY = 5 -- Legendary+ rolls get announced to the whole server
Config.DATASTORE = "RagdollRumble_v1"
Config.AUTOSAVE = 90

-- Admins: anyone in Studio, the game owner (or group rank 250+), plus these user ids
Config.ADMINS = {} :: { number }

-- Bots
Config.BOTS_ENABLED = true
Config.TARGET_FIGHTERS = 4 -- bots fill empty slots up to this many fighters
Config.MAX_FIGHTERS = 8

-- Networking
Config.STATE_RATE = 20 -- aim/flag updates per second

-- Fighter palette: name tags, outlines, crosshair, paint splats, bot bodies
Config.COLORS = {
	{ name = "RED", main = Color3.fromRGB(255, 77, 94), dark = Color3.fromRGB(138, 31, 44) },
	{ name = "BLUE", main = Color3.fromRGB(63, 169, 255), dark = Color3.fromRGB(27, 79, 128) },
	{ name = "LIME", main = Color3.fromRGB(142, 240, 74), dark = Color3.fromRGB(61, 122, 23) },
	{ name = "GOLD", main = Color3.fromRGB(255, 201, 60), dark = Color3.fromRGB(138, 99, 18) },
	{ name = "PINK", main = Color3.fromRGB(255, 106, 213), dark = Color3.fromRGB(134, 38, 111) },
	{ name = "CYAN", main = Color3.fromRGB(60, 242, 224), dark = Color3.fromRGB(20, 122, 113) },
	{ name = "ORANGE", main = Color3.fromRGB(255, 143, 60), dark = Color3.fromRGB(138, 63, 14) },
	{ name = "VIOLET", main = Color3.fromRGB(167, 123, 255), dark = Color3.fromRGB(75, 44, 143) },
}

Config.BOT_NAMES = {
	"Noodles", "Wobbles", "Sir Flop", "Twiggy", "Bonk", "Spaghetti", "Jelly", "Limbo", "Floppa", "Kevin",
}

return Config
