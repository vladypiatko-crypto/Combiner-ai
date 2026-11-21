--!strict
-- Player profiles: coins, crate inventory, equipped cosmetics, stats.
-- Saved with DataStoreService; if that's unavailable (e.g. Studio without API access)
-- profiles still work for the session and the client is told saving is off.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Data = {}

export type Profile = {
	coins: number,
	inventory: { [string]: number },
	equipped: { finisher: string, spawn: string },
	stats: { kills: number, wins: number, rounds: number, matches: number, rolls: number, best: number },
	luck: number, -- admin testing only (not saved)
	forceRarity: number?, -- admin testing only (not saved)
	freeRolls: boolean, -- admin testing only (not saved)
	loaded: boolean,
	dirty: boolean,
}

local store: DataStore? = nil
Data.saving = false
local profiles: { [Player]: Profile } = {}

do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE)
	end)
	if ok then
		store = s
		Data.saving = true
	end
end

local function fresh(): Profile
	return {
		coins = Config.START_COINS,
		inventory = { [Cosmetics.DEFAULT.finisher] = 1, [Cosmetics.DEFAULT.spawn] = 1 },
		equipped = { finisher = Cosmetics.DEFAULT.finisher, spawn = Cosmetics.DEFAULT.spawn },
		stats = { kills = 0, wins = 0, rounds = 0, matches = 0, rolls = 0, best = 0 },
		luck = 1,
		forceRarity = nil,
		freeRolls = false,
		loaded = false,
		dirty = false,
	}
end

local function serialize(p: Profile): any
	return { v = 1, coins = p.coins, inventory = p.inventory, equipped = p.equipped, stats = p.stats }
end

local function merge(p: Profile, saved: any)
	if type(saved) ~= "table" then
		return
	end
	if type(saved.coins) == "number" then
		p.coins = math.max(0, math.floor(saved.coins))
	end
	if type(saved.inventory) == "table" then
		for id, n in saved.inventory do
			if Cosmetics.byId[id] and type(n) == "number" then
				p.inventory[id] = math.max(p.inventory[id] or 0, math.floor(n))
			end
		end
	end
	if type(saved.equipped) == "table" then
		for _, kind in Cosmetics.KINDS do
			local id = saved.equipped[kind]
			if type(id) == "string" and p.inventory[id] and Cosmetics.byId[id].kind == kind then
				(p.equipped :: any)[kind] = id
			end
		end
	end
	if type(saved.stats) == "table" then
		for k, v in saved.stats do
			if type(v) == "number" and (p.stats :: any)[k] ~= nil then
				(p.stats :: any)[k] = v
			end
		end
	end
end

function Data.get(player: Player): Profile?
	return profiles[player]
end

function Data.public(player: Player): any
	local p = profiles[player]
	if not p then
		return nil
	end
	return {
		coins = p.coins,
		inventory = p.inventory,
		equipped = p.equipped,
		stats = p.stats,
		saving = Data.saving,
		luck = p.luck,
		forceRarity = p.forceRarity,
		freeRolls = p.freeRolls,
	}
end

function Data.push(player: Player)
	if player.Parent then
		Remotes.Event:FireClient(player, { t = "Profile", profile = Data.public(player) })
	end
	local p = profiles[player]
	local ls = player:FindFirstChild("leaderstats")
	if p and ls then
		local coins = ls:FindFirstChild("Coins") :: IntValue?
		local wins = ls:FindFirstChild("Wins") :: IntValue?
		if coins then
			coins.Value = p.coins
		end
		if wins then
			wins.Value = p.stats.wins
		end
	end
end

function Data.load(player: Player): Profile
	local p = fresh()
	profiles[player] = p
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = ls
	ls.Parent = player
	local s = store
	if s and Data.saving then
		for attempt = 1, 3 do
			local ok, res = pcall(function()
				return s:GetAsync("u_" .. player.UserId)
			end)
			if ok then
				merge(p, res)
				break
			else
				warn("[Ragdoll Rumble] data load failed (attempt " .. attempt .. "):", res)
				if string.find(tostring(res), "Studio") or string.find(tostring(res), "API") then
					Data.saving = false
					break
				end
				task.wait(1.5 * attempt)
			end
		end
	end
	p.loaded = true
	Data.push(player)
	return p
end

function Data.save(player: Player)
	local p = profiles[player]
	local s = store
	if not p or not p.loaded or not s or not Data.saving then
		return
	end
	local payload = serialize(p)
	local ok, err = pcall(function()
		s:SetAsync("u_" .. player.UserId, payload)
	end)
	if ok then
		p.dirty = false
	else
		warn("[Ragdoll Rumble] data save failed:", err)
	end
end

function Data.release(player: Player)
	Data.save(player)
	profiles[player] = nil
end

function Data.addCoins(player: Player, n: number, reason: string?)
	local p = profiles[player]
	if not p or n == 0 then
		return
	end
	p.coins = math.max(0, p.coins + math.floor(n))
	p.dirty = true
	Data.push(player)
	if reason and n > 0 then
		Remotes.Event:FireClient(player, { t = "Coins", amount = math.floor(n), reason = reason })
	end
end

function Data.stat(player: Player, key: string, delta: number)
	local p = profiles[player]
	if p and (p.stats :: any)[key] ~= nil then
		(p.stats :: any)[key] += delta
		p.dirty = true
	end
end

function Data.equip(player: Player, id: string): (boolean, string?)
	local p = profiles[player]
	local item = Cosmetics.byId[id]
	if not p or not item then
		return false, "unknown item"
	end
	if (p.inventory[id] or 0) <= 0 then
		return false, "you don't own that yet"
	end
	(p.equipped :: any)[item.kind] = id
	p.dirty = true
	Data.push(player)
	return true, nil
end

function Data.equipped(player: Player?, kind: string): string
	local p = if player then profiles[player] else nil
	if p then
		return (p.equipped :: any)[kind]
	end
	return (Cosmetics.DEFAULT :: any)[kind]
end

function Data.reset(player: Player)
	local old = profiles[player]
	local p = fresh()
	p.loaded = true
	p.dirty = true
	if old then
		p.luck = old.luck
	end
	profiles[player] = p
	Data.push(player)
end

-- autosave + shutdown save
task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE)
		for player, p in profiles do
			if p.dirty then
				Data.save(player)
			end
		end
	end
end)

game:BindToClose(function()
	local threads = {}
	for _, player in Players:GetPlayers() do
		table.insert(threads, task.spawn(Data.save, player))
	end
	task.wait(2)
end)

return Data
