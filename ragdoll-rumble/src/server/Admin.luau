--!strict
-- Admin actions. Every request is permission-checked here on the server.
-- Admins: everyone while testing in Studio, the game owner (or group rank 250+), Config.ADMINS.

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Maps = require(Shared:WaitForChild("Maps"))

local Combat = require(script.Parent:WaitForChild("Combat"))
local Bots = require(script.Parent:WaitForChild("Bots"))
local Data = require(script.Parent:WaitForChild("Data"))

local Admin = {}

local flow: any = nil -- set by the main script (match control functions)
local logs: { { t: number, kind: string, msg: string } } = {}

LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
		table.insert(logs, { t = os.time(), kind = if kind == Enum.MessageType.MessageError then "error" else "warn", msg = msg })
		if #logs > 60 then
			table.remove(logs, 1)
		end
	end
end)

function Admin.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.ADMINS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return (player :: any):GetRankInGroupAsync(game.CreatorId)
	end)
	if not ok then
		ok, rank = pcall(function()
			return (player :: any):GetRankInGroup(game.CreatorId)
		end)
	end
	return ok and type(rank) == "number" and rank >= 250
end

function Admin.init(api: any)
	flow = api
end

local function target(player: Player, args: any): Player
	if type(args) == "table" and type(args.userId) == "number" then
		local p = Players:GetPlayerByUserId(args.userId)
		if p then
			return p
		end
	end
	return player
end

local function num(v: any, d: number, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v then
		return d
	end
	return math.clamp(v, lo, hi)
end

local actions: { [string]: any } = {}

-- match ---------------------------------------------------------------------------
actions["match.start"] = function()
	return flow.startMatch()
end
actions["match.end"] = function()
	return flow.endMatch()
end
actions["round.skip"] = function()
	return flow.skipRound()
end
actions["round.map"] = function(_p, a)
	local i = math.floor(num(a and a.map, 1, 1, #Maps.list))
	flow.setNextMap(i)
	return true, "next map: " .. Maps.get(i).name
end
actions["suddendeath"] = function()
	return flow.suddenDeath()
end
actions["intermission"] = function(_p, a)
	return flow.setIntermission(num(a and a.seconds, 10, 0, 300))
end

-- bots -----------------------------------------------------------------------------
actions["bots.target"] = function(_p, a)
	Config.TARGET_FIGHTERS = math.floor(num(a and a.count, 4, 1, Config.MAX_FIGHTERS))
	flow.syncBots()
	return true, "matches fill up to " .. Config.TARGET_FIGHTERS .. " fighters"
end
actions["bots.enabled"] = function(_p, a)
	Config.BOTS_ENABLED = a and a.on == true
	flow.syncBots()
	return true, if Config.BOTS_ENABLED then "bots on" else "bots off"
end
actions["bots.difficulty"] = function(_p, a)
	Bots.difficulty = num(a and a.value, 1, 0.2, 1.6)
	return true, string.format("bot difficulty x%.1f", Bots.difficulty)
end
actions["bots.passive"] = function(_p, a)
	Bots.passive = a and a.on == true
	return true, if Bots.passive then "bots won't attack" else "bots fight back"
end
actions["bots.spawn"] = function(player)
	return flow.spawnTestBot(player)
end

-- players --------------------------------------------------------------------------
actions["player.kill"] = function(player, a)
	local f = Combat.forPlayer(target(player, a))
	if not f then
		return false, "no fighter"
	end
	Combat.kill(f, "admin")
	return true, "KO'd " .. f.name
end
actions["player.heal"] = function(player, a)
	local f = Combat.forPlayer(target(player, a))
	if not f or not f.alive then
		return false, "no living fighter"
	end
	f.humanoid.Health = f.humanoid.MaxHealth
	return true, "healed " .. f.name
end
actions["player.god"] = function(player, a)
	local f = Combat.forPlayer(target(player, a))
	if not f then
		return false, "no fighter"
	end
	f.god = a and a.on == true
	return true, f.name .. (if f.god then " is invincible" else " can be hurt again")
end
actions["player.ragdoll"] = function(player, a)
	local f = Combat.forPlayer(target(player, a))
	if not f or not f.alive then
		return false, "no living fighter"
	end
	Combat.knock(f, Vector3.new(0, 40, 0), 2)
	return true, "flop!"
end
actions["player.weapon"] = function(player, a)
	local f = Combat.forPlayer(target(player, a))
	local w = Weapons.get(math.floor(num(a and a.wid, 1, 1, #Weapons.list)))
	if not f or not f.alive or not w then
		return false, "no living fighter"
	end
	Combat.equip(f, w.id)
	return true, "gave " .. w.name
end
actions["player.coins"] = function(player, a)
	local p = target(player, a)
	local n = math.floor(num(a and a.amount, 1000, -1e7, 1e7))
	Data.addCoins(p, n, "admin")
	return true, string.format("%+d coins to %s", n, p.DisplayName)
end
actions["weapon.drop"] = function(player, a)
	local f = Combat.forPlayer(player)
	local w = Weapons.get(math.floor(num(a and a.wid, 1, 1, #Weapons.list)))
	if not f or not w then
		return false, "spawn in first"
	end
	Combat.spawnPickup(w.id, f.root.Position + Vector3.new(0, 10, 0), Vector3.new(0, -5, 0))
	return true, "dropped a " .. w.name
end

-- crates / data --------------------------------------------------------------------
actions["crate.force"] = function(player, a)
	local p = Data.get(player)
	if not p then
		return false, "no profile"
	end
	p.forceRarity = math.floor(num(a and a.rarity, 1, 1, 8))
	Data.push(player)
	return true, "your next roll is forced"
end
actions["crate.luck"] = function(player, a)
	local p = Data.get(player)
	if not p then
		return false, "no profile"
	end
	p.luck = num(a and a.value, 1, 1, 100000)
	Data.push(player)
	return true, string.format("luck x%g", p.luck)
end
actions["crate.free"] = function(player, a)
	local p = Data.get(player)
	if not p then
		return false, "no profile"
	end
	p.freeRolls = a and a.on == true
	Data.push(player)
	return true, if p.freeRolls then "rolls are free" else "rolls cost coins again"
end
actions["data.reset"] = function(player)
	Data.reset(player)
	return true, "profile reset"
end

-- info -------------------------------------------------------------------------------
actions["state"] = function()
	local list = {}
	for _, pl in Players:GetPlayers() do
		local f = Combat.forPlayer(pl)
		table.insert(list, { userId = pl.UserId, name = pl.DisplayName, zone = if f then f.zone else "-", god = f ~= nil and f.god })
	end
	return true, nil, {
		players = list,
		botsEnabled = Config.BOTS_ENABLED,
		target = Config.TARGET_FIGHTERS,
		difficulty = Bots.difficulty,
		passive = Bots.passive,
		saving = Data.saving,
		phase = workspace:GetAttribute("Phase"),
	}
end
actions["logs"] = function()
	return true, nil, logs
end

function Admin.handle(player: Player, action: any, args: any): any
	if not Admin.isAdmin(player) then
		return { ok = false, msg = "admins only" }
	end
	local fn = if type(action) == "string" then actions[action] else nil
	if not fn then
		return { ok = false, msg = "unknown action" }
	end
	local ok, res, msg, data = pcall(fn, player, args)
	if not ok then
		warn("[Ragdoll Rumble] admin action failed:", action, res)
		return { ok = false, msg = tostring(res) }
	end
	return { ok = res, msg = msg, data = data }
end

return Admin
