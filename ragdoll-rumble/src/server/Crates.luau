--!strict
-- Server-side crate rolls (the client only plays the reveal animation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Data = require(script.Parent:WaitForChild("Data"))

local Crates = {}

local rng = Random.new()
local lastRoll: { [Player]: number } = {}

Crates.onRare = function(_player: Player, _item: Cosmetics.Item) end

function Crates.roll(player: Player, kind: string): any
	local p = Data.get(player)
	if not p or not p.loaded then
		return { ok = false, msg = "still loading your data" }
	end
	if kind ~= "finisher" and kind ~= "spawn" then
		return { ok = false, msg = "unknown crate" }
	end
	local t = os.clock()
	if t - (lastRoll[player] or 0) < 0.8 then
		return { ok = false, msg = "slow down!" }
	end
	if not p.freeRolls and p.coins < Config.CRATE_COST then
		return { ok = false, msg = "not enough coins" }
	end
	lastRoll[player] = t
	if not p.freeRolls then
		p.coins -= Config.CRATE_COST
	end
	local item = Cosmetics.roll(kind, function()
		return rng:NextNumber()
	end, p.luck, p.forceRarity)
	p.forceRarity = nil
	local owned = p.inventory[item.id] or 0
	p.inventory[item.id] = owned + 1
	p.stats.rolls += 1
	p.stats.best = math.max(p.stats.best, item.chance)
	p.dirty = true
	local refund = 0
	if owned > 0 and item.rarity <= 2 then
		refund = Config.DUPE_REFUND
		p.coins += refund
	end
	Data.push(player)
	if item.rarity >= Config.ANNOUNCE_RARITY then
		Remotes.Event:FireAllClients({ t = "Announce", name = player.DisplayName, userId = player.UserId, item = item.id })
		Crates.onRare(player, item)
	end
	return { ok = true, item = item.id, new = owned == 0, refund = refund, count = owned + 1 }
end

Players.PlayerRemoving:Connect(function(player)
	lastRoll[player] = nil
end)

return Crates
