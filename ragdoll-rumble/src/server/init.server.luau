--!strict
-- Ragdoll Rumble server: lobby -> match (rounds) -> results -> lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Arena = require(script:WaitForChild("Arena"))
local Combat = require(script:WaitForChild("Combat"))
local Bots = require(script:WaitForChild("Bots"))
local Data = require(script:WaitForChild("Data"))
local Crates = require(script:WaitForChild("Crates"))
local Admin = require(script:WaitForChild("Admin"))
local Lobby = require(script:WaitForChild("Lobby"))
local Spawner = require(script:WaitForChild("Spawner"))

Players.CharacterAutoLoads = false
workspace.Gravity = Config.GRAVITY

local Event = Remotes.Event
local State = Remotes.State
local Request = Remotes.Request

local rng = Util.rng(os.time())

local function now(): number
	return workspace:GetServerTimeNow()
end

local function sendAll(msg: any)
	Event:FireAllClients(msg)
end

-------------------------------------------------------------------------------
-- participants

type Entry = {
	fid: number,
	player: Player?,
	name: string,
	colorIndex: number,
	isBot: boolean,
	isDummy: boolean,
	sparring: boolean,
	loaded: boolean,
	inMatch: boolean,
	wins: number,
	kills: number,
	finisher: string,
	spawnFx: string,
	home: Vector3?,
}

local entries: { [number]: Entry } = {}
local byPlayer: { [Player]: Entry } = {}
local nextFid = 1

local function allocFid(): number
	for _ = 1, 255 do
		local id = nextFid
		nextFid = nextFid % 250 + 1
		if not entries[id] then
			return id
		end
	end
	error("out of fighter ids")
end

local function freeColor(): number
	local used = {}
	for _, e in entries do
		if not e.isDummy then
			used[e.colorIndex] = true
		end
	end
	for i = 1, #Config.COLORS do
		if not used[i] then
			return i
		end
	end
	return rng:int(1, #Config.COLORS)
end

local function randomCosmetic(kind: string): string
	local pool = {}
	for _, it in Cosmetics.ofKind(kind) do
		if it.rarity <= 3 then
			table.insert(pool, it.id)
		end
	end
	return pool[rng:int(1, #pool)]
end

local function newEntry(player: Player?, name: string, isBot: boolean, isDummy: boolean?): Entry
	local e: Entry = {
		fid = allocFid(),
		player = player,
		name = name,
		colorIndex = 0,
		isBot = isBot,
		isDummy = isDummy == true,
		sparring = false,
		loaded = isBot,
		inMatch = false,
		wins = 0,
		kills = 0,
		finisher = if isBot then randomCosmetic("finisher") else Cosmetics.DEFAULT.finisher,
		spawnFx = if isBot then randomCosmetic("spawn") else Cosmetics.DEFAULT.spawn,
		home = nil,
	}
	e.colorIndex = if isDummy then 8 else freeColor()
	entries[e.fid] = e
	if player then
		byPlayer[player] = e
	end
	return e
end

local function who(e: Entry): Spawner.Who
	return { fid = e.fid, name = e.name, colorIndex = e.colorIndex, player = e.player, isBot = e.isBot }
end

local function humans(): { Entry }
	local out = {}
	for _, e in entries do
		if not e.isBot and e.loaded and e.player and e.player.Parent then
			table.insert(out, e)
		end
	end
	return out
end

local function scoreTable(matchOnly: boolean?): { any }
	local out = {}
	for _, e in entries do
		if not e.isDummy and not e.sparring and (not matchOnly or e.inMatch) then
			table.insert(out, {
				fid = e.fid,
				name = e.name,
				color = e.colorIndex,
				wins = e.wins,
				kills = e.kills,
				bot = e.isBot,
				inMatch = e.inMatch,
				userId = if e.player then e.player.UserId else 0,
			})
		end
	end
	table.sort(out, function(a: any, b: any)
		return a.fid < b.fid
	end)
	return out
end

-------------------------------------------------------------------------------
-- state

local phase = "lobby" -- lobby | match | results
local phaseEnd = 0
local intermission = false
local roundState = "none" -- none | countdown | fight | roundEnd
local roundTimer = 0
local mapIndex = 0
local nextMap: number? = nil
local roundNumber = 0
local roundStart = now()
local fightTime = 0
local sdStart = math.huge
local suddenDeath = false
local nextWeaponAt = 0
local lastMaps: { number } = {}

local function setAttr(k: string, v: any)
	workspace:SetAttribute(k, v)
end

local function roundInfo(): any
	return {
		map = mapIndex,
		round = roundNumber,
		start = roundStart,
		fight = fightTime,
		state = roundState,
		phase = phase,
		suddenDeath = suddenDeath,
	}
end

local function spawnInLobby(e: Entry)
	local x, y = Lobby.spawnPoint()
	Spawner.spawn(who(e), "lobby", x, y, false)
end

-------------------------------------------------------------------------------
-- combat hooks

Combat.hooks.active = function(): boolean
	return phase ~= "lobby" and (roundState == "fight" or roundState == "roundEnd")
end

Combat.hooks.finisherOf = function(fid: number): string?
	local e = entries[fid]
	if not e then
		return nil
	end
	if e.player then
		return Data.equipped(e.player, "finisher")
	end
	return e.finisher
end

Combat.hooks.onDeath = function(f: Combat.F, killer: number, _cause: string)
	local ke = entries[killer]
	if f.zone == "arena" and phase == "match" then
		if ke and killer ~= f.fid then
			ke.kills += 1
			if ke.player then
				Data.addCoins(ke.player, Config.COINS_KO, "KO")
				Data.stat(ke.player, "kills", 1)
			end
		end
		return
	end
	-- lobby deaths respawn
	local e = entries[f.fid]
	if not e then
		return
	end
	if e.isDummy or e.sparring then
		task.delay(Config.DUMMY_RESPAWN, function()
			if entries[e.fid] == e and e.home then
				Spawner.spawn(who(e), "lobby", e.home.X, e.home.Y, false, true)
			end
		end)
	elseif e.player then
		task.delay(Config.LOBBY_RESPAWN, function()
			if entries[e.fid] == e and e.player and e.player.Parent then
				local cur = Combat.fighters[e.fid]
				if not cur or not cur.alive then
					spawnInLobby(e)
				end
			end
		end)
	end
end

Spawner.onSpawned = function(f: Combat.F)
	local e = entries[f.fid]
	if not e then
		return
	end
	if e.sparring then
		(f :: any).sparring = true
	end
	if f.zone == "arena" then
		local id = if e.player then Data.equipped(e.player, "spawn") else e.spawnFx
		task.delay(0.35, function()
			if f.model.Parent then
				local p = f.root.Position
				sendAll({ t = "SpawnFx", fid = f.fid, id = id, x = p.X, y = p.Y })
			end
		end)
	end
end

Crates.onRare = function(_player: Player, item: Cosmetics.Item)
	Lobby.celebrate(Cosmetics.rarity(item).color)
end

-------------------------------------------------------------------------------
-- bots

local function syncBots()
	local inMatch = 0
	for _, e in humans() do
		if e.inMatch or phase == "lobby" then
			inMatch += 1
		end
	end
	local want = if Config.BOTS_ENABLED then math.clamp(Config.TARGET_FIGHTERS - inMatch, 0, Config.MAX_FIGHTERS - inMatch) else 0
	local bots = {}
	for _, e in entries do
		if e.isBot and not e.isDummy and not e.sparring then
			table.insert(bots, e)
		end
	end
	while #bots > want do
		local e = table.remove(bots) :: Entry
		entries[e.fid] = nil
		Spawner.cancel(e.fid)
	end
	local used = {}
	for _, e in entries do
		used[e.name] = true
	end
	while #bots < want do
		local name = Config.BOT_NAMES[rng:int(1, #Config.BOT_NAMES)]
		for _ = 1, 12 do
			if not used[name] then
				break
			end
			name = Config.BOT_NAMES[rng:int(1, #Config.BOT_NAMES)]
		end
		used[name] = true
		table.insert(bots, newEntry(nil, name, true))
	end
end

-------------------------------------------------------------------------------
-- match flow

local function pickMap(): number
	if nextMap then
		local m = nextMap
		nextMap = nil
		return m
	end
	local n = #Maps.list
	for _ = 1, 30 do
		local i = rng:int(1, n)
		if not table.find(lastMaps, i) then
			table.insert(lastMaps, i)
			while #lastMaps > math.min(3, n - 1) do
				table.remove(lastMaps, 1)
			end
			return i
		end
	end
	return rng:int(1, n)
end

local endMatch: () -> ()

local function startRound()
	roundNumber += 1
	mapIndex = pickMap()
	local map = Maps.get(mapIndex)
	Combat.reset("arena")
	for _, f in Combat.fighters do
		if f.zone == "arena" then
			Combat.unregister(f.fid)
		end
	end
	Arena.build("arena", map)
	roundStart = now() + 0.2
	fightTime = roundStart + Config.LOAD_TIME + Config.COUNTDOWN
	sdStart = fightTime + Config.SUDDEN_DEATH_AT
	suddenDeath = false
	nextWeaponAt = fightTime + rng:range(1, 2.5)
	roundState = "countdown"
	setAttr("RoundStart", roundStart)
	setAttr("FightTime", fightTime)
	setAttr("MapIndex", mapIndex)
	setAttr("Round", roundNumber)
	setAttr("RoundState", roundState)
	setAttr("InkStart", 0)
	local spawns = Util.shuffle(table.clone(map.spawns), rng)
	local order = {}
	for _, e in entries do
		if e.inMatch and (e.isBot or (e.player and e.player.Parent)) then
			table.insert(order, e)
		end
	end
	table.sort(order, function(a: Entry, b: Entry)
		return a.fid < b.fid
	end)
	for i, e in order do
		if i > Config.MAX_FIGHTERS then
			break
		end
		local sp = spawns[((i - 1) % #spawns) + 1]
		Spawner.spawn(who(e), "arena", sp[1] + (if i > #spawns then rng:range(-2, 2) else 0), sp[2], true)
	end
	sendAll({ t = "RoundStart", info = roundInfo(), scores = scoreTable(true) })
end

local function startMatch(): (boolean, string?)
	if phase ~= "lobby" then
		return false, "a match is already running"
	end
	local hs = humans()
	if #hs == 0 then
		return false, "nobody to play"
	end
	phase = "match"
	intermission = false
	setAttr("Phase", phase)
	roundNumber = 0
	for _, e in entries do
		e.inMatch = false
		e.wins = 0
		e.kills = 0
	end
	for _, e in hs do
		e.inMatch = true
	end
	syncBots()
	for _, e in entries do
		if e.isBot and not e.isDummy and not e.sparring then
			e.inMatch = true
		end
	end
	sendAll({ t = "MatchStart" })
	startRound()
	return true, "match started"
end

local function endRound(winner: Combat.F?)
	if roundState == "roundEnd" then
		return
	end
	roundState = "roundEnd"
	roundTimer = Config.ROUND_END_DELAY
	setAttr("RoundState", roundState)
	local wfid = 0
	if winner then
		wfid = winner.fid
		local e = entries[wfid]
		if e then
			e.wins += 1
			if e.player then
				Data.addCoins(e.player, Config.COINS_ROUND_WIN, "Round win")
				Data.stat(e.player, "rounds", 1)
			end
		end
		winner.model:SetAttribute("Victory", true)
	end
	sendAll({ t = "RoundEnd", winner = wfid, scores = scoreTable(true) })
end

endMatch = function()
	if phase ~= "match" then
		return
	end
	phase = "results"
	phaseEnd = now() + Config.RESULTS_TIME
	roundState = "none"
	setAttr("Phase", phase)
	setAttr("PhaseEnd", phaseEnd)
	setAttr("RoundState", roundState)
	local list = {}
	for _, e in entries do
		if e.inMatch then
			table.insert(list, e)
		end
	end
	table.sort(list, function(a: Entry, b: Entry)
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		return a.kills > b.kills
	end)
	local placements = {}
	for i, e in list do
		table.insert(placements, { fid = e.fid, name = e.name, color = e.colorIndex, wins = e.wins, kills = e.kills, userId = if e.player then e.player.UserId else 0, bot = e.isBot })
		if e.player and e.player.Parent then
			Data.addCoins(e.player, Config.COINS_PLAYED, "Match played")
			Data.stat(e.player, "matches", 1)
			if i == 1 and e.wins > 0 then
				Data.addCoins(e.player, Config.COINS_MATCH_WIN, "Match win!")
				Data.stat(e.player, "wins", 1)
			end
		end
	end
	sendAll({ t = "Results", placements = placements, ends = phaseEnd })
end

local function backToLobby()
	phase = "lobby"
	setAttr("Phase", phase)
	Combat.reset("arena")
	Arena.clear("arena")
	mapIndex = 0
	setAttr("MapIndex", 0)
	for _, e in entries do
		e.inMatch = false
		e.wins = 0
		e.kills = 0
	end
	for _, e in humans() do
		spawnInLobby(e)
	end
	intermission = false
	sendAll({ t = "Lobby", scores = scoreTable() })
end

-------------------------------------------------------------------------------
-- admin api

Admin.init({
	startMatch = startMatch,
	endMatch = function(): (boolean, string?)
		if phase ~= "match" then
			return false, "no match running"
		end
		endMatch()
		return true, "match ended"
	end,
	skipRound = function(): (boolean, string?)
		if phase ~= "match" or roundState == "roundEnd" then
			return false, "no round to skip"
		end
		endRound(nil)
		return true, "round skipped"
	end,
	setNextMap = function(i: number)
		nextMap = i
	end,
	suddenDeath = function(): (boolean, string?)
		if phase ~= "match" or roundState ~= "fight" then
			return false, "only during a fight"
		end
		sdStart = now()
		return true, "here comes the ink"
	end,
	setIntermission = function(sec: number): (boolean, string?)
		if phase ~= "lobby" then
			return false, "only in the lobby"
		end
		intermission = true
		phaseEnd = now() + sec
		setAttr("PhaseEnd", phaseEnd)
		return true, string.format("match starts in %ds", sec)
	end,
	syncBots = syncBots,
	spawnTestBot = function(player: Player): (boolean, string?)
		local f = Combat.forPlayer(player)
		if not f then
			return false, "spawn in first"
		end
		local name = Config.BOT_NAMES[rng:int(1, #Config.BOT_NAMES)] .. " (sparring)"
		local e = newEntry(nil, name, true, true)
		e.sparring = true
		e.colorIndex = freeColor()
		local p = f.root.Position
		e.home = Vector3.new(p.X + 8, p.Y - 3, 0)
		Spawner.spawn(who(e), f.zone, p.X + 8, p.Y - 3, false, true)
		return true, "spawned a sparring bot"
	end,
})

-------------------------------------------------------------------------------
-- remotes

local function fighterOf(player: Player): Combat.F?
	local e = byPlayer[player]
	if not e then
		return nil
	end
	local f = Combat.fighters[e.fid]
	if f and f.player == player and f.model == player.Character then
		return f
	end
	return nil
end

Event.OnServerEvent:Connect(function(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.t) ~= "string" then
		return
	end
	local e = byPlayer[player]
	if not e then
		return
	end
	if msg.t == "Ready" then
		Event:FireClient(player, {
			t = "Welcome",
			fid = e.fid,
			info = roundInfo(),
			scores = scoreTable(phase ~= "lobby"),
			isAdmin = Admin.isAdmin(player),
			profile = Data.public(player),
		})
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	if msg.t == "Act" then
		Combat.onAct(f, msg)
	elseif msg.t == "Hit" then
		Combat.onHit(f, msg)
	elseif msg.t == "Shoot" then
		Combat.onShoot(f, msg)
	elseif msg.t == "Launch" then
		Combat.onLaunch(f, msg)
	elseif msg.t == "Throw" then
		Combat.onThrow(f, msg)
	end
end)

State.OnServerEvent:Connect(function(player: Player, aimByte: any, flags: any)
	if type(aimByte) ~= "number" or type(flags) ~= "number" then
		return
	end
	local f = fighterOf(player)
	if f then
		Combat.onState(f, (math.clamp(aimByte, 0, 255) / 255) * 2 * math.pi - math.pi, math.floor(flags) % 256)
	end
end)

Request.OnServerInvoke = function(player: Player, kind: any, args: any): any
	if kind == "roll" then
		return Crates.roll(player, if type(args) == "table" then args.kind else "")
	elseif kind == "equip" then
		local ok, msg = Data.equip(player, if type(args) == "table" and type(args.id) == "string" then args.id else "")
		return { ok = ok, msg = msg }
	elseif kind == "ready" then
		Lobby.uiReady[player] = type(args) == "table" and args.on == true
		return { ok = true }
	elseif kind == "profile" then
		return { ok = true, profile = Data.public(player) }
	elseif kind == "admin" then
		if type(args) ~= "table" then
			return { ok = false, msg = "bad request" }
		end
		return Admin.handle(player, args.action, args.args)
	end
	return { ok = false, msg = "unknown request" }
end

-------------------------------------------------------------------------------
-- players

Players.PlayerAdded:Connect(function(player)
	local e = newEntry(player, player.DisplayName, false)
	player:SetAttribute("Admin", Admin.isAdmin(player))
	task.spawn(function()
		Data.load(player)
		if not player.Parent then
			return
		end
		e.loaded = true
		spawnInLobby(e)
		sendAll({ t = "Scores", scores = scoreTable(phase ~= "lobby") })
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local e = byPlayer[player]
	byPlayer[player] = nil
	Data.release(player)
	if not e then
		return
	end
	entries[e.fid] = nil
	Spawner.cancel(e.fid)
	local f = Combat.fighters[e.fid]
	if f then
		Combat.unregister(e.fid)
		sendAll({ t = "Left", fid = e.fid })
	end
	sendAll({ t = "Scores", scores = scoreTable(phase ~= "lobby") })
end)

-------------------------------------------------------------------------------
-- boot

Lobby.build()
for i, d in Maps.lobby.stations.dummies do
	local e = newEntry(nil, "Dummy " .. i, true, true)
	e.home = Vector3.new(d[1], d[2], 0)
	Spawner.spawn(who(e), "lobby", d[1], d[2], false, true)
end
setAttr("Phase", phase)
setAttr("PhaseEnd", 0)
setAttr("RoundState", roundState)
setAttr("MapIndex", 0)

for _, p in Players:GetPlayers() do
	task.spawn(function()
		if not byPlayer[p] then
			local e = newEntry(p, p.DisplayName, false)
			p:SetAttribute("Admin", Admin.isAdmin(p))
			Data.load(p)
			e.loaded = true
			spawnInLobby(e)
		end
	end)
end

-------------------------------------------------------------------------------
-- main loop

local stateAcc = 0

local function broadcastStates()
	local list = {}
	for _, f in Combat.fighters do
		table.insert(list, f)
	end
	local b = buffer.create(1 + #list * 3)
	buffer.writeu8(b, 0, #list)
	for i, f in list do
		local o = 1 + (i - 1) * 3
		buffer.writeu8(b, o, f.fid)
		buffer.writeu8(b, o + 1, math.floor(((f.aim + math.pi) / (2 * math.pi)) * 255 + 0.5) % 256)
		buffer.writeu8(b, o + 2, (if f.blocking then 1 else 0) + (if f.crouch then 2 else 0))
	end
	State:FireAllClients(b)
end

RunService.Heartbeat:Connect(function(dt)
	local t = now()
	local motionT = t - roundStart
	Arena.update(motionT)
	Combat.update(dt, motionT)
	local frozenArena = roundState == "countdown" or phase == "results"
	for _, f in Combat.fighters do
		if f.brain then
			Bots.think(f, dt, f.zone == "arena" and frozenArena and not (f :: any).sparring)
		end
	end
	Lobby.update(dt)

	if phase == "lobby" then
		local hs = humans()
		local readyCount = 0
		for _, e in hs do
			if e.player and Lobby.ready[e.player] then
				readyCount += 1
			end
		end
		setAttr("ReadyCount", readyCount)
		setAttr("HumanCount", #hs)
		if #hs == 0 then
			intermission = false
			setAttr("PhaseEnd", 0)
		else
			if not intermission then
				intermission = true
				phaseEnd = t + (if #hs == 1 then Config.SOLO_INTERMISSION else Config.INTERMISSION)
				setAttr("PhaseEnd", phaseEnd)
			end
			if readyCount == #hs and phaseEnd - t > Config.READY_SHORTCUT then
				phaseEnd = t + Config.READY_SHORTCUT
				setAttr("PhaseEnd", phaseEnd)
			end
			if t >= phaseEnd then
				startMatch()
			end
		end
	elseif phase == "match" then
		if roundState == "countdown" and t >= fightTime then
			roundState = "fight"
			setAttr("RoundState", roundState)
			for _, f in Combat.fighters do
				if f.zone == "arena" then
					f.humanoid.WalkSpeed = Config.WALK_SPEED
					f.humanoid.JumpPower = Config.JUMP_POWER
				end
			end
			sendAll({ t = "Fight" })
		elseif roundState == "fight" then
			local zone = Arena.zones.arena
			if zone and t >= nextWeaponAt then
				nextWeaponAt = t + rng:range(Config.WEAPON_SPAWN_MIN, Config.WEAPON_SPAWN_MAX)
				if Combat.groundWeaponCount("arena") < Config.MAX_GROUND_WEAPONS then
					local w = Weapons.pick(rng:next())
					local map = zone.map
					local x = rng:range(map.weaponX[1], map.weaponX[2])
					Combat.spawnPickup(w.id, Vector3.new(x, map.weaponY, 0), Vector3.new(rng:range(-4, 4), -10, 0))
					sendAll({ t = "Drop", wid = w.id, x = x, y = map.weaponY })
				end
			end
			if zone and t > sdStart then
				if not suddenDeath then
					suddenDeath = true
					setAttr("InkStart", sdStart)
					sendAll({ t = "SuddenDeath" })
				end
				Arena.setInk("arena", zone.map.killY + (t - sdStart) * Config.SUDDEN_DEATH_SPEED)
			end
			local total, alive, last = 0, 0, nil
			for _, f in Combat.fighters do
				if f.zone == "arena" then
					total += 1
					if f.alive then
						alive += 1
						last = f
					end
				end
			end
			local humansIn = 0
			for _, e in humans() do
				if e.inMatch then
					humansIn += 1
				end
			end
			if humansIn == 0 then
				endMatch()
			elseif total >= 2 and alive <= 1 then
				endRound(last)
			elseif total <= 1 and t > fightTime + 5 then
				endRound(last)
			end
		elseif roundState == "roundEnd" then
			roundTimer -= dt
			if roundTimer <= 0 then
				local top = 0
				for _, e in entries do
					if e.inMatch then
						top = math.max(top, e.wins)
					end
				end
				if top >= Config.WINS_TO_MATCH or roundNumber >= Config.MAX_ROUNDS then
					endMatch()
				else
					startRound()
				end
			end
		end
	elseif phase == "results" then
		if t >= phaseEnd then
			backToLobby()
		end
	end

	stateAcc += dt
	if stateAcc >= 1 / Config.STATE_RATE then
		stateAcc = 0
		broadcastStates()
	end
end)

print("[Ragdoll Rumble] server ready")
