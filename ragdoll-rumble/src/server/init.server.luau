--!strict
-- Ragdoll Rumble server: rounds, spawning avatars + bots, weapon drops, state relay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Util = require(Shared:WaitForChild("Util"))
local Rig = require(Shared:WaitForChild("Rig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Arena = require(script:WaitForChild("Arena"))
local Combat = require(script:WaitForChild("Combat"))
local Bots = require(script:WaitForChild("Bots"))

Players.CharacterAutoLoads = false
workspace.Gravity = Config.GRAVITY

local Event = Remotes.Event
local State = Remotes.State

local fightersFolder = workspace:FindFirstChild("Fighters") or Instance.new("Folder")
fightersFolder.Name = "Fighters"
fightersFolder.Parent = workspace

-------------------------------------------------------------------------------
-- participants

type Entry = {
	fid: number,
	player: Player?,
	name: string,
	colorIndex: number,
	wins: number,
	kills: number,
	isBot: boolean,
	ready: boolean,
}

local entries: { [number]: Entry } = {}
local byPlayer: { [Player]: Entry } = {}
local nextFid = 1
local rng = Util.rng(os.time())

local function now(): number
	return workspace:GetServerTimeNow()
end

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
		used[e.colorIndex] = true
	end
	for i = 1, #Config.COLORS do
		if not used[i] then
			return i
		end
	end
	return rng:int(1, #Config.COLORS)
end

local function newEntry(player: Player?, name: string, isBot: boolean): Entry
	local e: Entry = {
		fid = allocFid(),
		player = player,
		name = name,
		colorIndex = 0,
		wins = 0,
		kills = 0,
		isBot = isBot,
		ready = isBot,
	}
	e.colorIndex = freeColor()
	entries[e.fid] = e
	if player then
		byPlayer[player] = e
	end
	return e
end

local function humanCount(): number
	local n = 0
	for _, e in entries do
		if not e.isBot and e.ready then
			n += 1
		end
	end
	return n
end

local function scoreTable(): { any }
	local out = {}
	for _, e in entries do
		table.insert(out, {
			fid = e.fid,
			name = e.name,
			color = e.colorIndex,
			wins = e.wins,
			kills = e.kills,
			bot = e.isBot,
			userId = if e.player then e.player.UserId else 0,
		})
	end
	table.sort(out, function(a, b)
		return a.fid < b.fid
	end)
	return out
end

local function sendAll(msg: any)
	Event:FireAllClients(msg)
end

-------------------------------------------------------------------------------
-- round state

local state = "idle" -- idle | countdown | fight | roundEnd | matchEnd
local mapIndex = 0
local roundNumber = 0
local roundStart = 0
local fightTime = 0
local stateTimer = 0
local nextWeaponAt = 0
local suddenDeath = false
local roundToken = 0
local lastMaps: { number } = {}

Combat.hooks.active = function(): boolean
	return state == "fight" or state == "roundEnd" or state == "matchEnd"
end

Combat.hooks.onDeath = function(_f: Combat.F, killer: number, _cause: string)
	local ke = entries[killer]
	if ke then
		ke.kills += 1
	end
end

local function roundInfo(): any
	return {
		map = mapIndex,
		round = roundNumber,
		start = roundStart,
		fight = fightTime,
		state = state,
		suddenDeath = suddenDeath,
	}
end

local function syncBots()
	local humans = humanCount()
	local want = 0
	if Config.BOTS_ENABLED and humans > 0 then
		want = math.clamp(Config.TARGET_FIGHTERS - humans, 0, Config.MAX_FIGHTERS - humans)
	end
	local bots = {}
	for _, e in entries do
		if e.isBot then
			table.insert(bots, e)
		end
	end
	while #bots > want do
		local e = table.remove(bots) :: Entry
		entries[e.fid] = nil
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

local function pickMap(): number
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

local function setupFighter(e: Entry, model: Model, x: number, y: number)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	if not root:FindFirstChild("Facing") then
		Rig.setup(model)
	end
	model:PivotTo(Arena.spawnCFrame(x, y))
	hum.MaxHealth = Config.MAX_HP
	hum.Health = Config.MAX_HP
	hum.UseJumpPower = true
	local frozen = now() < fightTime
	hum.WalkSpeed = if frozen then 0 else Config.WALK_SPEED
	hum.JumpPower = if frozen then 0 else Config.JUMP_POWER
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.AutoRotate = false
	model:SetAttribute("Fid", e.fid)
	model:SetAttribute("ColorIndex", e.colorIndex)
	model:SetAttribute("FighterName", e.name)
	model:SetAttribute("IsBot", e.isBot)
	model:SetAttribute("Wid", 0)
	model:SetAttribute("Ammo", 0)
	model:SetAttribute("Alive", true)
	model:SetAttribute("Ragdoll", false)
	model:SetAttribute("Victory", false)
	local facing = if x > (Arena.map.bounds.left + Arena.map.bounds.right) * 0.5 then -1 else 1
	local fo = root:FindFirstChild("Facing") :: AlignOrientation?
	if fo then
		fo.CFrame = Rig.facingCFrame(facing)
	end
	model.Parent = fightersFolder
	local f = Combat.newFighter(e.fid, e.name, e.colorIndex, model, e.player)
	f.aim = if facing > 0 then 0 else math.pi
	if e.isBot then
		f.brain = Bots.newBrain(rng:int(1, 1e6), rng:range(0.45, 0.85))
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	Combat.register(f)
end

local function spawnEntry(e: Entry, x: number, y: number, token: number)
	if e.isBot then
		task.spawn(function()
			local tpl = Bots.template(e.colorIndex)
			if not tpl or token ~= roundToken or not entries[e.fid] then
				return
			end
			local m = tpl:Clone()
			m.Name = e.name
			setupFighter(e, m, x, y)
		end)
	else
		local player = e.player :: Player
		task.spawn(function()
			local ok, err = pcall(function()
				player:LoadCharacter()
			end)
			if not ok then
				warn("[Ragdoll Rumble] LoadCharacter failed:", err)
				return
			end
			local char = player.Character
			if not char or token ~= roundToken then
				return
			end
			char:WaitForChild("HumanoidRootPart", 5)
			char:WaitForChild("Humanoid", 5)
			if token ~= roundToken or not char.Parent then
				return
			end
			setupFighter(e, char, x, y)
		end)
	end
end

local function startRound()
	syncBots()
	if humanCount() == 0 then
		state = "idle"
		Combat.reset()
		Arena.clear()
		workspace:SetAttribute("RoundState", "idle")
		return
	end
	roundToken += 1
	roundNumber += 1
	Combat.reset()
	for _, child in fightersFolder:GetChildren() do
		child:Destroy()
	end
	mapIndex = pickMap()
	local map = Maps.get(mapIndex)
	Arena.build(map)
	roundStart = now() + 0.2
	fightTime = roundStart + Config.LOAD_TIME + Config.COUNTDOWN
	suddenDeath = false
	nextWeaponAt = fightTime + rng:range(1, 2.5)
	state = "countdown"
	workspace:SetAttribute("RoundStart", roundStart)
	workspace:SetAttribute("FightTime", fightTime)
	workspace:SetAttribute("MapIndex", mapIndex)
	workspace:SetAttribute("Round", roundNumber)
	workspace:SetAttribute("RoundState", state)
	workspace:SetAttribute("InkStart", 0)

	local spawns = Util.shuffle(table.clone(map.spawns), rng)
	local order = {}
	for _, e in entries do
		if e.ready then
			table.insert(order, e)
		end
	end
	table.sort(order, function(a, b)
		return a.fid < b.fid
	end)
	for i, e in order do
		if i > Config.MAX_FIGHTERS then
			break
		end
		local sp = spawns[((i - 1) % #spawns) + 1]
		spawnEntry(e, sp[1] + (if i > #spawns then rng:range(-2, 2) else 0), sp[2], roundToken)
	end
	sendAll({ t = "RoundStart", info = roundInfo(), scores = scoreTable() })
end

local function endRound(winner: Combat.F?)
	state = "roundEnd"
	stateTimer = Config.ROUND_END_DELAY
	local wfid = 0
	if winner then
		wfid = winner.fid
		local e = entries[wfid]
		if e then
			e.wins += 1
		end
		winner.model:SetAttribute("Victory", true)
	end
	workspace:SetAttribute("RoundState", state)
	sendAll({ t = "RoundEnd", winner = wfid, scores = scoreTable() })
	local e = entries[wfid]
	if e and e.wins >= Config.WINS_TO_MATCH then
		state = "matchEnd"
		stateTimer = Config.MATCH_END_DELAY
		workspace:SetAttribute("RoundState", state)
		sendAll({ t = "MatchEnd", winner = wfid, name = e.name, color = e.colorIndex, userId = if e.player then e.player.UserId else 0, scores = scoreTable() })
	end
end

-------------------------------------------------------------------------------
-- remotes

Event.OnServerEvent:Connect(function(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.t) ~= "string" then
		return
	end
	local e = byPlayer[player]
	if not e then
		return
	end
	if msg.t == "Ready" then
		if e.ready then
			return
		end
		e.ready = true
		Event:FireClient(player, { t = "Welcome", fid = e.fid, info = roundInfo(), scores = scoreTable() })
		sendAll({ t = "Scores", scores = scoreTable() })
		local humansInRound = false
		for _, f in Combat.fighters do
			if f.player then
				humansInRound = true
			end
		end
		if state == "idle" or not humansInRound then
			startRound()
		end
		return
	end
	local f = Combat.fighters[e.fid]
	if not f or f.player ~= player or f.model ~= player.Character then
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
	local e = byPlayer[player]
	if not e or type(aimByte) ~= "number" or type(flags) ~= "number" then
		return
	end
	local f = Combat.fighters[e.fid]
	if f and f.player == player then
		Combat.onState(f, (math.clamp(aimByte, 0, 255) / 255) * 2 * math.pi - math.pi, math.floor(flags) % 256)
	end
end)

Players.PlayerAdded:Connect(function(player)
	newEntry(player, player.DisplayName, false)
	sendAll({ t = "Scores", scores = scoreTable() })
end)

Players.PlayerRemoving:Connect(function(player)
	local e = byPlayer[player]
	byPlayer[player] = nil
	if not e then
		return
	end
	entries[e.fid] = nil
	local f = Combat.fighters[e.fid]
	if f then
		Combat.unregister(e.fid)
		sendAll({ t = "Left", fid = e.fid })
	end
	sendAll({ t = "Scores", scores = scoreTable() })
	if humanCount() == 0 then
		state = "idle"
		Combat.reset()
		Arena.clear()
	end
end)

for _, p in Players:GetPlayers() do
	if not byPlayer[p] then
		newEntry(p, p.DisplayName, false)
	end
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
		local flags = 0
		if f.blocking then
			flags += 1
		end
		if f.crouch then
			flags += 2
		end
		buffer.writeu8(b, o + 2, flags)
	end
	State:FireAllClients(b)
end

RunService.Heartbeat:Connect(function(dt)
	if state == "idle" then
		return
	end
	local t = now()
	local motionT = t - roundStart
	Arena.update(motionT)

	if state == "countdown" and t >= fightTime then
		state = "fight"
		workspace:SetAttribute("RoundState", state)
		for _, f in Combat.fighters do
			f.humanoid.WalkSpeed = Config.WALK_SPEED
			f.humanoid.JumpPower = Config.JUMP_POWER
		end
		sendAll({ t = "Fight" })
	end

	Combat.update(dt, motionT)
	local frozen = state == "countdown"
	for _, f in Combat.fighters do
		if f.brain then
			Bots.think(f, dt, frozen or state == "matchEnd")
		end
	end

	if state == "fight" then
		local map = Arena.map
		-- weapon drops
		if t >= nextWeaponAt then
			nextWeaponAt = t + rng:range(Config.WEAPON_SPAWN_MIN, Config.WEAPON_SPAWN_MAX)
			if Combat.groundWeaponCount() < Config.MAX_GROUND_WEAPONS then
				local w = Weapons.pick(rng:next())
				local x = rng:range(map.weaponX[1], map.weaponX[2])
				Combat.spawnPickup(w.id, Vector3.new(x, map.weaponY, 0), Vector3.new(rng:range(-4, 4), -10, 0))
				sendAll({ t = "Drop", wid = w.id, x = x, y = map.weaponY })
			end
		end
		-- sudden death: the ink rises
		local sdStart = fightTime + Config.SUDDEN_DEATH_AT
		if t > sdStart then
			if not suddenDeath then
				suddenDeath = true
				workspace:SetAttribute("InkStart", sdStart)
				sendAll({ t = "SuddenDeath" })
			end
			Arena.setInk(map.killY + (t - sdStart) * Config.SUDDEN_DEATH_SPEED)
		end
		-- round over?
		local total, alive, last = 0, 0, nil
		for _, f in Combat.fighters do
			total += 1
			if f.alive then
				alive += 1
				last = f
			end
		end
		if total >= 2 and alive <= 1 then
			endRound(last)
		elseif total == 1 and humanCount() >= 2 and t > fightTime + 5 then
			endRound(last)
		end
	elseif state == "roundEnd" or state == "matchEnd" then
		stateTimer -= dt
		if stateTimer <= 0 then
			if state == "matchEnd" then
				for _, e in entries do
					e.wins = 0
					e.kills = 0
				end
			end
			startRound()
		end
	end

	stateAcc += dt
	if stateAcc >= 1 / Config.STATE_RATE then
		stateAcc = 0
		broadcastStates()
	end
end)

print("[Ragdoll Rumble] server ready")
