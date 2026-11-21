--!strict
-- Ragdoll Rumble client: wires input, procedural animation, camera, effects, sound and UI.

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
local Remotes = require(Shared:WaitForChild("Remotes"))

local Audio = require(script:WaitForChild("Audio"))
local Input = require(script:WaitForChild("Input"))
local CameraRig = require(script:WaitForChild("CameraRig"))
local Animator = require(script:WaitForChild("Animator"))
local Effects = require(script:WaitForChild("Effects"))
local Tags = require(script:WaitForChild("Tags"))
local Hud = require(script:WaitForChild("Hud"))
local Controller = require(script:WaitForChild("Controller"))

local player = Players.LocalPlayer
local Event = Remotes.Event
local State = Remotes.State

-------------------------------------------------------------------------------
-- setup

Audio.init()
Effects.init()
Hud.init()
Input.init(Hud.toggleHelp)
Controller.init()

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

-- post processing for that punchy look
local function post(className: string, props: { [string]: any })
	local name = "Rumble" .. className
	local e = Lighting:FindFirstChild(name) or Instance.new(className)
	e.Name = name
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = Lighting
end
post("BloomEffect", { Intensity = 0.8, Size = 28, Threshold = 0.9 })
post("ColorCorrectionEffect", { Saturation = 0.15, Contrast = 0.08, Brightness = 0.02 })
post("SunRaysEffect", { Intensity = 0.04, Spread = 0.6 })

local myFid = 0
local mapIndex = 0
local roundStart = 0
local fightTime = 0
local lastCount = -1
local saws: { { part: BasePart, def: any } } = {}
local scores: { any } = {}

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

local function nameOf(fid: number): string
	if fid == myFid then
		return "YOU"
	end
	for _, s in scores do
		if s.fid == fid then
			return s.name
		end
	end
	local m = modelOf(fid)
	return if m then (m:GetAttribute("FighterName") or m.Name) :: string else "???"
end

local function colorOf(fid: number): Color3
	for _, s in scores do
		if s.fid == fid then
			local c = Config.COLORS[s.color]
			if c then
				return c.main
			end
		end
	end
	local m = modelOf(fid)
	return if m then Tags.color(m) else Color3.new(1, 1, 1)
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function rootOf(fid: number): BasePart?
	local m = modelOf(fid)
	local r = if m then m:FindFirstChild("HumanoidRootPart") else nil
	return if r and r:IsA("BasePart") then r else nil
end

-------------------------------------------------------------------------------
-- fighters coming and going

local function onFighter(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local model = m :: Model
	task.spawn(function()
		for _ = 1, 50 do
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

local function watchFighters(folder: Instance)
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
end
task.spawn(function()
	watchFighters(workspace:WaitForChild("Fighters"))
end)

-- arena visuals: spinning saws, paint surfaces
local function refreshArena()
	saws = {}
	local arena = workspace:FindFirstChild("Arena")
	local map = if mapIndex > 0 then Maps.get(mapIndex) else nil
	if not arena or not map then
		return
	end
	Effects.setGeometry(arena:FindFirstChild("Geometry"))
	for _, c in arena:GetChildren() do
		local idx = c:GetAttribute("SawIndex")
		if c:IsA("BasePart") and type(idx) == "number" and map.hazards[idx] then
			table.insert(saws, { part = c, def = map.hazards[idx] })
		end
	end
end
workspace.ChildAdded:Connect(function(c)
	if c.Name == "Arena" then
		task.wait(0.5)
		refreshArena()
	end
end)

-------------------------------------------------------------------------------
-- server events

local handlers: { [string]: (any) -> () } = {}

local function startRoundVisuals(info: any)
	if not info or not info.map or info.map == 0 then
		return
	end
	mapIndex = info.map
	roundStart = info.start
	fightTime = info.fight
	lastCount = -1
	local map = Maps.get(mapIndex)
	CameraRig.reset(map.bounds)
	Effects.clearSplats()
	Hud.hideChampion()
	Hud.suddenDeath(info.suddenDeath == true)
	if info.state == "countdown" then
		Hud.banner(string.upper(map.name), "Round " .. tostring(info.round) .. "  ·  " .. map.subtitle, nil, 2.2)
	end
	task.delay(1, refreshArena)
	task.delay(3, refreshArena)
end

handlers.Welcome = function(msg)
	myFid = msg.fid
	scores = msg.scores or {}
	Hud.setScores(scores, myFid)
	startRoundVisuals(msg.info)
end

handlers.Scores = function(msg)
	scores = msg.scores or scores
	Hud.setScores(scores, myFid)
end

handlers.RoundStart = function(msg)
	scores = msg.scores or scores
	Hud.setScores(scores, myFid)
	Hud.spectate("")
	startRoundVisuals(msg.info)
end

handlers.Fight = function(_msg)
	if lastCount ~= 0 then
		lastCount = 0
		Hud.count("FIGHT!", Color3.fromRGB(255, 90, 110))
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
	for _, e in msg.ends or {} do
		if type(e) == "table" and type(e[1]) == "number" and type(e[2]) == "number" then
			local endPos = Vector3.new(e[1], e[2], 0)
			Effects.tracer(origin, endPos, col, if w.key == "longshot" then 0.35 else 0.18)
			Effects.spark(endPos, col, 3, 18, 0.22)
		end
	end
	local m = modelOf(msg.fid)
	local aim = 0
	if #(msg.ends or {}) > 0 and type(msg.ends[1]) == "table" then
		aim = math.atan2(msg.ends[1][2] - msg.y, msg.ends[1][1] - msg.x)
	end
	Effects.muzzle(origin, aim, col)
	if m then
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			Effects.shell(r.Position + Vector3.new(0, 1.5, 0), if r.CFrame.LookVector.X >= 0 then 1 else -1)
		end
	end
	Animator.trigger(msg.fid, "fire")
	Audio.play(w.sound, 0.75)
end

handlers.Launch = function(msg)
	if msg.fid == myFid then
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
		local fromFront = (push.X * facing) < 0
		Animator.trigger(msg.fid, "flinch", nil, if fromFront then 1 else -1)
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
	if msg.damage > 0 then
		Effects.paint(pos, push * 0.35, victimColor, math.clamp(math.floor(msg.damage / 4), 3, 16))
		if msg.attacker ~= myFid or (msg.kind ~= "punch" and msg.kind ~= "melee") then
			Effects.spark(pos, Color3.new(1, 1, 1), if big then 14 else 7, if big then 55 else 30)
			Effects.ring(pos, victimColor, if big then 4 else 2.4)
		end
		local col = if msg.headshot then Color3.fromRGB(255, 80, 80) else Color3.fromRGB(255, 240, 200)
		Effects.text(pos + Vector3.new(0, 1.5, 0), (if msg.headshot then "HEADSHOT " else "") .. tostring(msg.damage), col, if big then 30 else 22, 0.7)
	end
	if msg.kind == "punch" then
		if msg.attacker ~= myFid then
			Audio.play(if big then "heavy" else "punch", 0.8)
		elseif big then
			Audio.play("heavy")
		end
	elseif msg.kind == "melee" then
		if msg.attacker ~= myFid then
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
	if (msg.ragdoll or 0) > 0 then
		Audio.play("heavy", 0.7)
	end
	local me = msg.fid == myFid or msg.attacker == myFid
	CameraRig.shake(math.clamp(msg.damage / 70, 0.05, 0.6) * (if me then 1.4 else 0.6))
	if msg.fid == myFid then
		Hud.hurt(msg.damage)
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
		Effects.paint(pos, Vector3.new(0, 20, 0), col, 26)
		Effects.spark(pos, col, 24, 70, 0.5)
		Effects.ring(pos, col, 7, 0.4)
		Effects.flash(pos, Color3.new(1, 1, 1), 4)
		Effects.text(pos + Vector3.new(0, 3, 0), "KO!", col, 52, 1.1)
	end
	Audio.play("ko")
	CameraRig.shake(0.55)
	local victim = nameOf(msg.fid)
	local text
	local cause = msg.cause
	if msg.killer and msg.killer ~= 0 and msg.killer ~= msg.fid then
		local verb = if cause == "fell" then "launched" elseif cause == "explosion" then "blew up" elseif cause == "punch" then "punched out" elseif cause == "melee" then "smacked" elseif cause == "bullet" then "blasted" elseif cause == "saw" or cause == "spikes" then "shoved" else "KO'd"
		text = string.format("<font color='%s'>%s</font> %s <font color='%s'>%s</font>", hex(colorOf(msg.killer)), nameOf(msg.killer), verb, hex(col), victim)
	else
		local how = if cause == "fell" then "fell off the map" elseif cause == "saw" then "met the saw" elseif cause == "spikes" then "found the spikes" elseif cause == "explosion" then "blew themselves up" else "got KO'd"
		text = string.format("<font color='%s'>%s</font> %s", hex(col), victim, how)
	end
	Hud.feed(text)
	if msg.fid == myFid then
		Hud.spectate("YOU GOT KO'D — watching the rest")
	end
end

handlers.Boom = function(msg)
	local pos = Vector3.new(msg.x, msg.y, 0)
	Effects.explosion(pos, msg.r or 9)
	Audio.play("boom")
	CameraRig.shake(0.75)
end

handlers.Equip = function(msg)
	if msg.fid == myFid then
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
	scores = msg.scores or scores
	Hud.setScores(scores, myFid)
	Hud.suddenDeath(false)
	if msg.winner and msg.winner ~= 0 then
		local col = colorOf(msg.winner)
		local name = nameOf(msg.winner)
		Hud.banner(if msg.winner == myFid then "YOU WIN!" else string.upper(name) .. " WINS!", "round point!", col, 3)
		local r = rootOf(msg.winner)
		if r then
			Effects.confetti(r.Position + Vector3.new(0, 18, 0), 40)
		end
	else
		Hud.banner("DRAW!", "nobody survived", Color3.fromRGB(220, 220, 220), 3)
	end
	Audio.play("win")
end

handlers.MatchEnd = function(msg)
	local c = Config.COLORS[msg.color] or Config.COLORS[1]
	task.delay(1.2, function()
		Hud.champion(if msg.winner == myFid then "YOU" else msg.name, c.main, msg.userId or 0)
		Audio.play("win", 1, 0.8)
	end)
end

handlers.SuddenDeath = function(_msg)
	Hud.banner("SUDDEN DEATH", "the ink is rising!", Color3.fromRGB(255, 70, 120), 2.5)
	Hud.suddenDeath(true)
	Audio.play("fight", 1, 0.7)
end

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
		if fid ~= myFid then
			local aim = (buffer.readu8(b, o + 1) / 255) * 2 * math.pi - math.pi
			Animator.setState(fid, aim, buffer.readu8(b, o + 2))
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

RunService:BindToRenderStep("RagdollRumble", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local t = now()
	local frozen = t < fightTime or workspace:GetAttribute("RoundState") == "matchEnd"

	-- countdown
	if fightTime > 0 then
		local remain = fightTime - t
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

	-- my fighter
	local mouseWorld = CameraRig.toWorld(UserInputService:GetMouseLocation())
	local auto = if Input.mode ~= "mouse" then Controller.nearestEnemy() else nil
	Controller.update(dt, mouseWorld, auto, frozen)
	stateAcc += dt
	if stateAcc >= 1 / Config.STATE_RATE then
		stateAcc = 0
		local aimByte = math.floor(((Controller.aim + math.pi) / (2 * math.pi)) * 255 + 0.5) % 256
		local flags = (if Controller.blocking then 1 else 0) + (if Controller.crouch then 2 else 0)
		State:FireServer(aimByte, flags)
	end

	-- camera frames everyone still standing
	local targets = {}
	local folder = fighters()
	if folder then
		for _, m in folder:GetChildren() do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local r = m:FindFirstChild("HumanoidRootPart")
			if hum and r and r:IsA("BasePart") and (hum.Health > 0 or m == player.Character) then
				local map = if mapIndex > 0 then Maps.get(mapIndex) else nil
				if not map or r.Position.Y > map.killY - 5 then
					table.insert(targets, Vector2.new(r.Position.X, r.Position.Y))
				end
			end
		end
	end
	CameraRig.update(dt, targets)

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

	local c = player.Character
	local hum = if c then c:FindFirstChildOfClass("Humanoid") else nil
	local inRound = c ~= nil and c.Parent == folder
	local hp = if hum then hum.Health else 0
	local wid = if c then (c:GetAttribute("Wid") :: number?) or 0 else 0
	local ammo = if c then (c:GetAttribute("Ammo") :: number?) or 0 else 0
	local alive = inRound and hp > 0
	Hud.update(dt, if inRound then hp else 0, alive, wid, ammo, if c then Tags.color(c) else Color3.new(1, 1, 1), Input.mode == "mouse" and alive)
	if not inRound and mapIndex > 0 then
		Hud.spectate("SPECTATING — you'll join next round")
	end
end)

Event:FireServer({ t = "Ready" })
print("[Ragdoll Rumble] client ready")
