--!strict
-- Ragdoll Rumble client: input, procedural animation, camera, effects, sound, UI glue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Motion = require(Shared:WaitForChild("Motion"))
local Util = require(Shared:WaitForChild("Util"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Audio = require(script:WaitForChild("Audio"))
local Input = require(script:WaitForChild("Input"))
local CameraRig = require(script:WaitForChild("CameraRig"))
local Animator = require(script:WaitForChild("Animator"))
local Effects = require(script:WaitForChild("Effects"))
local Skins = require(script:WaitForChild("Skins"))
local Tags = require(script:WaitForChild("Tags"))
local UI = require(script:WaitForChild("UIKit"))
local Store = require(script:WaitForChild("Store"))
local Hud = require(script:WaitForChild("Hud"))
local Menu = require(script:WaitForChild("Menu"))
local CrateUI = require(script:WaitForChild("CrateUI"))
local AdminUI = require(script:WaitForChild("AdminUI"))
local CosmeticFx = require(script:WaitForChild("CosmeticFx"))
local Controller = require(script:WaitForChild("Controller"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Event = Remotes.Event
local State = Remotes.State

-------------------------------------------------------------------------------
-- setup

Audio.init()
Effects.init()
UI.click = function()
	Audio.play("click")
end
UI.hover = function()
	Audio.play("tick", 0.25, 1.6)
end
Hud.init(playerGui)
Menu.init(playerGui)
CrateUI.init(playerGui)
AdminUI.init(Menu.gui())
Input.init(Hud.toggleHelp)
Controller.init()
Skins.init(function(ok: boolean, err: string?)
	Store.emit("skinsReady", ok)
	if not ok then
		warn("[Ragdoll Rumble] using part models:", err)
	end
end)

Menu.onAdmin = AdminUI.toggle
Menu.onPreview = function(id: string)
	local c = player.Character
	local r = if c then c:FindFirstChild("HumanoidRootPart") else nil
	if r and r:IsA("BasePart") then
		CosmeticFx.preview(id, r.Position, Tags.color(c :: Model))
	end
end

task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local function post(className: string, props: { [string]: any })
	local name = "Rumble" .. className
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = Lighting
end
post("BloomEffect", { Intensity = 0.7, Size = 26, Threshold = 0.92 })
post("ColorCorrectionEffect", { Saturation = 0.15, Contrast = 0.08, Brightness = 0.02 })
post("SunRaysEffect", { Intensity = 0.04, Spread = 0.6 })

-------------------------------------------------------------------------------
-- helpers

local fightTime = 0
local roundStart = 0
local lastCount = -1
local saws: { { part: BasePart, def: any } } = {}
local viewZone = "lobby"
local lightingFor = ""
local matchCoins = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fighters(): Folder?
	return workspace:FindFirstChild("Fighters") :: Folder?
end

local function modelOf(fid: number): Model?
	local f = fighters()
	if not f then
		return nil
	end
	for _, m in f:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Fid") == fid then
			return m
		end
	end
	return nil
end

local function rootOf(fid: number): BasePart?
	local m = modelOf(fid)
	local r = if m then m:FindFirstChild("HumanoidRootPart") else nil
	return if r and r:IsA("BasePart") then r else nil
end

local function nameOf(fid: number): string
	if fid == Store.myFid then
		return "You"
	end
	for _, s in Store.scores do
		if s.fid == fid then
			return s.name
		end
	end
	local m = modelOf(fid)
	return if m then (m:GetAttribute("FighterName") or m.Name) :: string else "???"
end

local function colorOf(fid: number): Color3
	local m = modelOf(fid)
	if m then
		return Tags.color(m)
	end
	for _, s in Store.scores do
		if s.fid == fid then
			local c = Config.COLORS[s.color]
			if c then
				return c.main
			end
		end
	end
	return Color3.new(1, 1, 1)
end

local function c3(hex: number): Color3
	local r, g, b = Util.hexToRGB(hex)
	return Color3.fromRGB(r, g, b)
end

local function mapForZone(zone: string): any?
	if zone == "lobby" then
		return Maps.lobby
	end
	local mi = workspace:GetAttribute("MapIndex")
	if type(mi) == "number" and mi > 0 then
		return Maps.get(mi)
	end
	return nil
end

local function applyLighting(map: any)
	local th = map.theme
	Lighting.ClockTime = th.clock or 14
	Lighting.Brightness = if th.kind == "neon" or th.kind == "lab" or th.kind == "lobby" then 1.3 else 2.2
	Lighting.Ambient = c3(th.skyTop):Lerp(Color3.new(1, 1, 1), 0.45)
	Lighting.OutdoorAmbient = c3(th.skyBottom):Lerp(Color3.new(1, 1, 1), 0.35)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	CameraRig.setBounds(map.bounds)
end

local function refreshArena()
	saws = {}
	local arena = workspace:FindFirstChild("Arena")
	local map = mapForZone("arena")
	if arena and map then
		for _, c in arena:GetChildren() do
			local idx = c:GetAttribute("SawIndex")
			if c:IsA("BasePart") and type(idx) == "number" and map.hazards[idx] then
				table.insert(saws, { part = c, def = map.hazards[idx] })
			end
		end
	end
end

local function paintGeometry()
	local zone = if viewZone == "lobby" then workspace:FindFirstChild("Lobby") else workspace:FindFirstChild("Arena")
	Effects.setGeometry(if zone then zone:FindFirstChild("Geometry") else nil)
end

workspace.ChildAdded:Connect(function(c)
	if c.Name == "Arena" or c.Name == "Lobby" then
		task.wait(0.5)
		refreshArena()
		paintGeometry()
		lightingFor = ""
	end
end)

-------------------------------------------------------------------------------
-- fighters coming and going

local function onFighter(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local model = m :: Model
	task.spawn(function()
		for _ = 1, 60 do
			if model:GetAttribute("Fid") and model:FindFirstChild("HumanoidRootPart") and model:FindFirstChild("Head") then
				break
			end
			task.wait(0.1)
		end
		if not model.Parent then
			return
		end
		Animator.track(model)
		Tags.add(model, model == player.Character)
		local function decorate(child: Instance)
			if child.Name == "Weapon" and child:IsA("Model") then
				task.wait()
				Effects.decorateWeapon(child, Tags.color(model))
			end
		end
		for _, c in model:GetChildren() do
			decorate(c)
		end
		model.ChildAdded:Connect(decorate)
	end)
end

task.spawn(function()
	local folder = workspace:WaitForChild("Fighters")
	for _, m in folder:GetChildren() do
		onFighter(m)
	end
	folder.ChildAdded:Connect(onFighter)
	folder.ChildRemoved:Connect(function(m)
		if m:IsA("Model") then
			Animator.untrack(m)
			Tags.remove(m)
		end
	end)
end)

-------------------------------------------------------------------------------
-- server events

local handlers: { [string]: (any) -> () } = {}

local function setScores(scores: { any }?)
	if scores then
		Store.scores = scores
		Hud.setScores(scores)
	end
end

handlers.Welcome = function(msg)
	Store.myFid = msg.fid
	Store.isAdmin = msg.isAdmin == true
	Store.emit("admin", Store.isAdmin)
	setScores(msg.scores)
	Menu.setProfile(msg.profile)
	if msg.info and msg.info.phase == "match" then
		fightTime = msg.info.fight
		roundStart = msg.info.start
		Hud.setRoster(Store.scores)
	end
	if Store.isAdmin then
		UI.toast("You're an admin · press F2 or use the ADMIN button", Color3.fromRGB(255, 143, 60), 5)
	end
end

handlers.Profile = function(msg)
	Menu.setProfile(msg.profile)
end

handlers.Coins = function(msg)
	Menu.coinPopup(msg.amount, msg.reason)
	if workspace:GetAttribute("Phase") ~= "lobby" then
		matchCoins += msg.amount
	end
end

handlers.Scores = function(msg)
	setScores(msg.scores)
end

handlers.MatchStart = function(_msg)
	matchCoins = 0
	Audio.play("fight", 1, 0.8)
end

handlers.RoundStart = function(msg)
	setScores(msg.scores)
	Hud.setRoster(Store.scores)
	Hud.spectate("")
	Hud.suddenDeath(false)
	local info = msg.info
	fightTime = info.fight
	roundStart = info.start
	lastCount = -1
	local map = Maps.get(info.map)
	Effects.clearSplats()
	if viewZone == "arena" or info.round == 1 then
		Hud.banner(string.upper(map.name), "Round " .. tostring(info.round) .. "  ·  " .. map.subtitle, c3(map.theme.edge), 2.4)
	end
	task.delay(1, refreshArena)
	task.delay(3, refreshArena)
end

handlers.Fight = function(_msg)
	if lastCount ~= 0 and viewZone == "arena" then
		lastCount = 0
		Hud.count("FIGHT!", UI.C.red)
		Audio.play("fight")
	end
end

handlers.Act = function(msg)
	Animator.trigger(msg.fid, msg.kind, msg.hand)
	local r = rootOf(msg.fid)
	if msg.kind == "punch" then
		Audio.play("whoosh", 0.6)
	elseif msg.kind == "swing" then
		Audio.play("slash", 0.7)
		local m = modelOf(msg.fid)
		if r and m then
			local facing = if r.CFrame.LookVector.X >= 0 then 1 else -1
			Effects.slash(r.Position + Vector3.new(facing * 2.4, 1.4, 0), if facing > 0 then 0 else math.pi, Tags.color(m), facing)
		end
	elseif msg.kind == "lob" or msg.kind == "throw" then
		Audio.play("throw", 0.7)
	elseif msg.kind == "djump" and r then
		Effects.ring(r.Position - Vector3.new(0, 2.4, 0), colorOf(msg.fid), 4)
		Audio.play("djump", 0.6)
	end
end

handlers.Shot = function(msg)
	local w = Weapons.get(msg.wid)
	if not w then
		return
	end
	local origin = Vector3.new(msg.x, msg.y, 0)
	local rr, gg, bb = Util.hexToRGB(w.tracer)
	local col = Color3.fromRGB(rr, gg, bb)
	local aim = 0
	for i, e in msg.ends or {} do
		if type(e) == "table" and type(e[1]) == "number" and type(e[2]) == "number" then
			local endPos = Vector3.new(e[1], e[2], 0)
			Effects.tracer(origin, endPos, col, if w.key == "longshot" then 0.35 else 0.18)
			Effects.spark(endPos, col, 3, 18, 0.22)
			if i == 1 then
				aim = math.atan2(e[2] - msg.y, e[1] - msg.x)
			end
		end
	end
	Effects.muzzle(origin, aim, col)
	local r = rootOf(msg.fid)
	if r then
		Effects.shell(r.Position + Vector3.new(0, 1.5, 0), if r.CFrame.LookVector.X >= 0 then 1 else -1)
	end
	Animator.trigger(msg.fid, "fire")
	Audio.play(w.sound, 0.75)
end

handlers.Launch = function(msg)
	if msg.fid == Store.myFid then
		return
	end
	if msg.kind == "rocket" then
		Audio.play("rocket", 0.8)
		Effects.muzzle(Vector3.new(msg.x, msg.y, 0), 0, Color3.fromRGB(255, 160, 80))
	else
		Audio.play("lob", 0.7)
	end
end

handlers.Hit = function(msg)
	local pos = Vector3.new(msg.x, msg.y, 0)
	local victimColor = colorOf(msg.fid)
	local push = Vector3.new(msg.kx or 0, msg.ky or 0, 0)
	local big = (msg.ragdoll or 0) > 0 or msg.damage >= 25
	local r = rootOf(msg.fid)
	if r then
		local facing = if r.CFrame.LookVector.X >= 0 then 1 else -1
		Animator.trigger(msg.fid, "flinch", nil, if (push.X * facing) < 0 then 1 else -1)
	end
	if msg.blocked then
		Effects.spark(pos, Color3.fromRGB(180, 220, 255), 10, 30)
		Effects.ring(pos, Color3.fromRGB(180, 220, 255), 3)
		Effects.text(pos + Vector3.new(0, 2, 0), if msg.parried then "PARRY!" else "BLOCK", Color3.fromRGB(180, 220, 255), if msg.parried then 34 else 24)
		Audio.play(if msg.parried then "parry" else "block")
		CameraRig.shake(if msg.parried then 0.35 else 0.1)
		return
	end
	if msg.deflected then
		Effects.spark(pos, Color3.new(1, 1, 1), 12, 40)
		Effects.text(pos + Vector3.new(0, 2, 0), "DEFLECT!", Color3.new(1, 1, 1), 28)
		Audio.play("deflect")
		return
	end
	if msg.damage > 0 or (msg.kx or 0) ~= 0 then
		Effects.paint(pos, push * 0.35, victimColor, math.clamp(math.floor(math.max(msg.damage, 8) / 4), 3, 16))
		if msg.attacker ~= Store.myFid or (msg.kind ~= "punch" and msg.kind ~= "melee") then
			Effects.spark(pos, Color3.new(1, 1, 1), if big then 14 else 7, if big then 55 else 30)
			Effects.ring(pos, victimColor, if big then 4 else 2.4)
		end
		if big then
			Effects.stars(pos, Color3.fromRGB(255, 236, 150), 4)
		end
		if Store.settings.numbers and msg.damage > 0 then
			local col = if msg.headshot then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(255, 240, 200)
			Effects.text(pos + Vector3.new(0, 1.5, 0), (if msg.headshot then "HEADSHOT " else "") .. tostring(msg.damage), col, if big then 30 else 22, 0.7)
		end
	end
	if msg.kind == "punch" then
		Audio.play(if big then "heavy" else "punch", if msg.attacker == Store.myFid then 0.5 else 0.8)
	elseif msg.kind == "melee" then
		if msg.attacker ~= Store.myFid then
			Audio.play("heavy", 0.8)
		end
	elseif msg.kind == "bullet" or msg.kind == "deflected" or msg.kind == "thrown" then
		Audio.play("punch", 0.6, 1.3)
	elseif msg.kind == "saw" then
		Audio.play("saw")
		Effects.spark(pos, Color3.fromRGB(255, 200, 80), 20, 60)
	elseif msg.kind == "spikes" then
		Audio.play("spikes")
	end
	local me = msg.fid == Store.myFid or msg.attacker == Store.myFid
	CameraRig.shake(math.clamp(msg.damage / 70, 0.05, 0.6) * (if me then 1.4 else 0.6))
	if msg.fid == Store.myFid then
		Hud.hurt(msg.damage)
		if big then
			CameraRig.punchZoom(0.05)
		end
	end
end

handlers.Knock = function(msg)
	Controller.onKnock(msg)
end

handlers.GetUp = function(_msg)
	Controller.onGetUp()
end

handlers.Died = function(msg)
	local r = rootOf(msg.fid)
	local col = colorOf(msg.fid)
	if r then
		local pos = r.Position
		Effects.paint(pos, Vector3.new(0, 20, 0), col, 22)
		Effects.spark(pos, col, 20, 60, 0.5)
		Effects.ring(pos, col, 6, 0.4)
		Effects.flash(pos, Color3.new(1, 1, 1), 4)
		Effects.text(pos + Vector3.new(0, 3, 0), "KO!", col, 52, 1.1)
		CosmeticFx.finisher(msg.finisher, pos, col)
	end
	Audio.play("ko", if msg.zone == "lobby" then 0.6 else 1)
	CameraRig.shake(if msg.zone == "lobby" then 0.25 else 0.55)
	if msg.zone ~= "arena" then
		return
	end
	local killer = if msg.killer and msg.killer ~= 0 and msg.killer ~= msg.fid then msg.killer else nil
	Hud.feed(if killer then nameOf(killer) else nil, if killer then colorOf(killer) else nil, nameOf(msg.fid), col, msg.cause or "ko")
	if msg.fid == Store.myFid then
		local fin = if msg.finisher then Cosmetics.byId[msg.finisher] else nil
		Hud.ko(if killer then nameOf(killer) else nil, if killer then colorOf(killer) else nil, if fin and fin.id ~= "pop" then fin.name else nil)
		Hud.spectate("SPECTATING")
	elseif killer == Store.myFid then
		Hud.banner("KO!", "you took out " .. nameOf(msg.fid), UI.C.gold, 1.2)
	end
end

handlers.SpawnFx = function(msg)
	CosmeticFx.entrance(msg.id, Vector3.new(msg.x, msg.y, 0), colorOf(msg.fid))
end

handlers.Boom = function(msg)
	local pos = Vector3.new(msg.x, msg.y, 0)
	Effects.explosion(pos, msg.r or 9)
	Effects.stars(pos, Color3.fromRGB(255, 190, 80), 6)
	Audio.play("boom")
	CameraRig.shake(0.75)
	CameraRig.punchZoom(0.05)
end

handlers.Equip = function(msg)
	if msg.fid == Store.myFid then
		Audio.play("pickup")
	end
end

handlers.Picked = function(msg)
	local r = rootOf(msg.fid)
	local w = Weapons.get(msg.wid)
	if r and w then
		Effects.text(r.Position + Vector3.new(0, 4.5, 0), string.upper(w.name), colorOf(msg.fid), 22, 0.9)
		Effects.ring(r.Position, colorOf(msg.fid), 3)
	end
end

handlers.Drop = function(msg)
	Effects.beam(msg.x, msg.y, Color3.fromRGB(255, 240, 160))
	Audio.play("drop")
end

handlers.Deflect = function(msg)
	Effects.spark(Vector3.new(msg.x, msg.y, 0), Color3.new(1, 1, 1), 10, 40)
	Audio.play("deflect")
end

handlers.Parry = function(_msg) end

handlers.Hazard = function(msg)
	Effects.spark(Vector3.new(msg.x, msg.y, 0), Color3.fromRGB(255, 210, 90), 14, 50)
end

handlers.RoundEnd = function(msg)
	setScores(msg.scores)
	Hud.suddenDeath(false)
	if viewZone ~= "arena" then
		return
	end
	if msg.winner and msg.winner ~= 0 then
		local col = colorOf(msg.winner)
		Hud.banner(if msg.winner == Store.myFid then "YOU WIN!" else string.upper(nameOf(msg.winner)) .. " WINS!", "round point!", col, 3)
		local r = rootOf(msg.winner)
		if r then
			Effects.confetti(r.Position + Vector3.new(0, 18, 0), 40)
		end
	else
		Hud.banner("DRAW!", "nobody survived", Color3.fromRGB(200, 200, 210), 3)
	end
	Audio.play("win")
end

handlers.Results = function(msg)
	Hud.results(msg.placements or {}, matchCoins)
	local first = (msg.placements or {})[1]
	if first and first.fid == Store.myFid then
		Audio.play("win", 1, 0.8)
		task.delay(0.3, function()
			Audio.play("win", 1, 1.2)
		end)
	end
end

handlers.Lobby = function(msg)
	setScores(msg.scores)
	Hud.hideResults()
	Hud.spectate("")
	Hud.setRoster({})
	UI.toast("Back in the Arcade · roll some crates!", UI.C.pink, 4)
end

handlers.SuddenDeath = function(_msg)
	if viewZone == "arena" then
		Hud.banner("SUDDEN DEATH", "the ink is rising!", Color3.fromRGB(255, 70, 120), 2.5)
		Hud.suddenDeath(true)
		Audio.play("fight", 1, 0.7)
	end
end

handlers.Announce = function(msg)
	local item = Cosmetics.byId[msg.item]
	if not item then
		return
	end
	local r = Cosmetics.rarity(item)
	local hex = string.format("#%02x%02x%02x", math.floor(r.color.R * 255), math.floor(r.color.G * 255), math.floor(r.color.B * 255))
	local t = UI.toast(string.format("%s rolled <font color='%s'>%s %s</font> (%s)!", msg.name, hex, item.icon, item.name, Cosmetics.formatChance(item.chance)), r.color, 6, true)
	if t and item.rarity >= 6 then
		UI.shimmer(t, { r.color, Color3.new(1, 1, 1), r.color }, 1)
	end
	Audio.play("win", 0.7, 1.4)
end

handlers.Left = function(_msg) end

Event.OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local h = handlers[msg.t]
	if h then
		local ok, err = pcall(h, msg)
		if not ok then
			warn("[Ragdoll Rumble] handler", msg.t, err)
		end
	end
end)

State.OnClientEvent:Connect(function(b: any)
	if typeof(b) ~= "buffer" then
		return
	end
	local n = buffer.readu8(b, 0)
	for i = 1, n do
		local o = 1 + (i - 1) * 3
		local fid = buffer.readu8(b, o)
		if fid ~= Store.myFid then
			Animator.setState(fid, (buffer.readu8(b, o + 1) / 255) * 2 * math.pi - math.pi, buffer.readu8(b, o + 2))
		end
	end
end)

-------------------------------------------------------------------------------
-- loops

local stateAcc = 0

RunService.PreSimulation:Connect(function(dt)
	Animator.step(dt)
	Controller.physicsStep(dt)
end)

local function hpOf(fid: number): (number?, boolean?)
	local m = modelOf(fid)
	if not m then
		return 0, false
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not h then
		return 0, false
	end
	return h.Health, h.Health > 0
end

RunService:BindToRenderStep("RagdollRumble", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local t = now()
	local phase = workspace:GetAttribute("Phase") or "lobby"
	local c = player.Character
	local myZone = if c then c:GetAttribute("Zone") else nil
	local hum = if c then c:FindFirstChildOfClass("Humanoid") else nil
	local alive = hum ~= nil and hum.Health > 0
	local inMatch = false
	for _, s in Store.scores do
		if s.fid == Store.myFid and s.inMatch then
			inMatch = true
		end
	end
	-- which zone are we looking at?
	local zone = if type(myZone) == "string" then myZone else "lobby"
	if phase ~= "lobby" and inMatch then
		zone = "arena"
	end
	if zone ~= viewZone then
		viewZone = zone
		lightingFor = ""
		paintGeometry()
		local map = mapForZone(zone)
		if map then
			CameraRig.reset(map.bounds)
		end
	end
	local map = mapForZone(viewZone)
	local key = viewZone .. tostring(workspace:GetAttribute("MapIndex"))
	if map and key ~= lightingFor then
		lightingFor = key
		applyLighting(map)
	end
	CameraRig.shakeEnabled = Store.settings.shake
	Audio.volume = Store.settings.sfx

	-- countdown (arena only)
	local frozen = false
	if viewZone == "arena" and phase == "match" and fightTime > 0 then
		local remain = fightTime - t
		frozen = remain > 0
		if remain > 0 and remain <= Config.COUNTDOWN then
			local n = math.ceil(remain)
			if n ~= lastCount then
				lastCount = n
				Hud.count(tostring(n))
				Audio.play("tick", 1, 1 + (3 - n) * 0.1)
			end
		elseif remain <= 0 and lastCount > 0 then
			handlers.Fight({})
		end
	end
	if myZone == "arena" and phase == "results" then
		frozen = true
	end

	-- my fighter
	local mouseWorld = CameraRig.toWorld(UserInputService:GetMouseLocation())
	local auto = if Input.mode ~= "mouse" then Controller.nearestEnemy() else nil
	Controller.update(dt, mouseWorld, auto, frozen)
	stateAcc += dt
	if stateAcc >= 1 / Config.STATE_RATE then
		stateAcc = 0
		local aimByte = math.floor(((Controller.aim + math.pi) / (2 * math.pi)) * 255 + 0.5) % 256
		State:FireServer(aimByte, (if Controller.blocking then 1 else 0) + (if Controller.crouch then 2 else 0))
	end

	-- camera
	local targets = {}
	local folder = fighters()
	local myRoot = if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if folder then
		for _, m in folder:GetChildren() do
			if m:GetAttribute("Zone") ~= viewZone then
				continue
			end
			local h = m:FindFirstChildOfClass("Humanoid")
			local r = m:FindFirstChild("HumanoidRootPart")
			if not h or not r or not r:IsA("BasePart") then
				continue
			end
			if viewZone == "lobby" then
				-- lobby: follow yourself + whoever is right next to you
				if m == c or (myRoot and (r.Position - myRoot.Position).Magnitude < 22) then
					table.insert(targets, Vector2.new(r.Position.X, r.Position.Y))
				end
			elseif h.Health > 0 or m == c then
				if not map or r.Position.Y > map.killY - 5 then
					table.insert(targets, Vector2.new(r.Position.X, r.Position.Y))
				end
			end
		end
	end
	CameraRig.update(dt, targets, if viewZone == "lobby" then 0.75 else 1)

	-- spinning saws follow the shared motion clock
	local mt = t - roundStart
	for _, s in saws do
		if s.part.Parent then
			local x, y = Motion.pose(s.def.motion, s.def.x, s.def.y, 0, mt)
			s.part.CFrame = CFrame.new(x, y, 0) * CFrame.Angles(0, 0, -mt * 9) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end

	Effects.update(dt)
	Tags.update(dt)
	Menu.update(dt, viewZone == "lobby")
	local wid = if c then (c:GetAttribute("Wid") :: number?) or 0 else 0
	local ammo = if c then (c:GetAttribute("Ammo") :: number?) or 0 else 0
	Hud.update(dt, viewZone == "arena" and phase ~= "lobby", hpOf, {
		inArena = myZone == "arena" and alive,
		alive = alive,
		hp = if hum then hum.Health else 0,
		wid = wid,
		ammo = ammo,
		color = if c then Tags.color(c) else Color3.new(1, 1, 1),
		crosshair = Input.mode == "mouse" and alive and not CrateUI.busy(),
	})
	if viewZone == "lobby" and phase == "match" and not inMatch then
		Hud.spectate("a match is running · you'll join the next one")
	elseif viewZone == "lobby" then
		Hud.spectate("")
	end
end)

Event:FireServer({ t = "Ready" })
print("[Ragdoll Rumble] client ready")
