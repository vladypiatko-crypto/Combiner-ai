--!strict
-- The Arcade: lobby stations (crate machine, locker, ready portal, leaderboard, training
-- dummies + weapons to test on them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Maps = require(Shared:WaitForChild("Maps"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local Arena = require(script.Parent:WaitForChild("Arena"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Data = require(script.Parent:WaitForChild("Data"))

local Lobby = {}

local map = Maps.lobby
local st = map.stations
local portalGlow: BasePart? = nil
local board: SurfaceGui? = nil
local machineBeam: BasePart? = nil
Lobby.ready = {} :: { [Player]: boolean }
Lobby.uiReady = {} :: { [Player]: boolean }

local c3 = Arena.c3
local deco = Arena.deco

local function prompt(parent: BasePart, action: string, object: string, panel: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.HoldDuration = 0
	p.Style = Enum.ProximityPromptStyle.Default
	p:SetAttribute("Panel", panel)
	p.Parent = parent
end

local function station(name: string, x: number, y: number, z: number, scale: number, fallback: (Model) -> ()): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = (Arena.zones.lobby :: Arena.Zone).folder
	fallback(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("Fallback", true)
		end
	end
	Arena.skinAnchor(name, CFrame.new(x, y, z), scale, m)
	return m
end

function Lobby.build()
	local zone = Arena.build("lobby", map)
	local th = map.theme

	-- crate machine
	local mx = st.machine.x
	station("machine", mx, 1000, -4, 1, function(m)
		deco({ Size = Vector3.new(5.4, 9, 3.6), CFrame = CFrame.new(mx, 1004.5, -4), Color = c3(0x8b5cf6) }, m)
		deco({ Size = Vector3.new(3.6, 2.2, 0.2), CFrame = CFrame.new(mx, 1005.3, -2.1), Color = c3(0xff5dcf), Material = Enum.Material.Neon }, m)
	end)
	local mp = deco({ Name = "MachinePrompt", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(mx, 1003, 0), Transparency = 1 }, zone.folder)
	prompt(mp, "Open Crates", "Crate Machine", "crates")
	machineBeam = deco({ Name = "MachineBeam", Size = Vector3.new(3, 400, 3), CFrame = CFrame.new(mx, 1210, -4), Color = c3(0xffd36e), Material = Enum.Material.Neon, Transparency = 1 }, zone.folder)
	for i, key in { "crate_finisher", "crate_spawn" } do
		local x = mx - 6 - i * 0.4
		station(key, x, 1001.5 + (i - 1) * 3.05, -5, 1, function(m)
			deco({ Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(x, 1001.5 + (i - 1) * 3.05, -5), Color = if i == 1 then c3(0xb0283a) else c3(0x1e4e8c), Material = Enum.Material.WoodPlanks }, m)
		end)
	end

	-- locker
	local lx = st.locker.x
	station("locker", lx, 1000, -4, 1, function(m)
		deco({ Size = Vector3.new(3.2, 6, 2), CFrame = CFrame.new(lx, 1003, -4), Color = c3(0x1e4e8c) }, m)
	end)
	local lp = deco({ Name = "LockerPrompt", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(lx, 1003, 0), Transparency = 1 }, zone.folder)
	prompt(lp, "Open Locker", "Locker", "locker")

	-- ready portal
	local px = st.portal.x
	station("portal", px, 1003.8, -3, 1, function(m)
		deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 7, 7), CFrame = CFrame.new(px, 1003.8, -3) * CFrame.Angles(0, math.pi / 2, 0), Color = c3(0x16181f) }, m)
	end)
	portalGlow = deco({ Name = "PortalGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 5.6, 5.6), CFrame = CFrame.new(px, 1003.8, -3.2) * CFrame.Angles(0, math.pi / 2, 0), Color = c3(th.accent), Material = Enum.Material.Neon, Transparency = 0.6 }, zone.folder)
	local sign = deco({ Name = "PortalSign", Size = Vector3.new(8, 1.6, 0.3), CFrame = CFrame.new(px, 1008.8, -3), Transparency = 1 }, zone.folder)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.LightInfluence = 0
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.Parent = sign
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.TextScaled = true
	lbl.Text = "STAND HERE TO READY UP"
	lbl.TextColor3 = c3(th.accent)
	lbl.Parent = sg

	-- leaderboard
	local bx, by = st.board.x, st.board.y
	local bp = deco({ Name = "Board", Size = Vector3.new(26, 11, 0.6), CFrame = CFrame.new(bx, by, -8.6), Color = c3(0x16132b) }, zone.folder)
	deco({ Size = Vector3.new(26.8, 11.8, 0.4), CFrame = CFrame.new(bx, by, -8.8), Color = c3(th.edge), Material = Enum.Material.Neon }, zone.folder)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Back
	g.LightInfluence = 0
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.Parent = bp
	board = g

	-- logo, trophy, lamps, benches, targets
	station("logo", 0, 1031.5, -8.4, 1.15, function(m)
		local p = deco({ Size = Vector3.new(17, 7.5, 0.6), CFrame = CFrame.new(0, 1031.5, -8.4), Color = c3(0x16181f) }, m)
		local lg = Instance.new("SurfaceGui")
		lg.Face = Enum.NormalId.Back
		lg.LightInfluence = 0
		lg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		lg.PixelsPerStud = 30
		lg.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.LuckiestGuy
		t.TextScaled = true
		t.Text = "RAGDOLL\nRUMBLE"
		t.TextColor3 = c3(0xff5dcf)
		t.Parent = lg
	end)
	station("trophy", st.trophy.x, st.trophy.y, -2.5, 0.9, function(m)
		deco({ Size = Vector3.new(2, 3, 2), CFrame = CFrame.new(st.trophy.x, st.trophy.y + 1.5, -2.5), Color = c3(0xffc93c), Material = Enum.Material.Metal }, m)
	end)
	for i, x in st.lamps do
		station("lamp", x, 1000, -6, 1, function(m)
			deco({ Size = Vector3.new(0.3, 7, 0.3), CFrame = CFrame.new(x, 1003.5, -6), Color = c3(0x2b2f3a) }, m)
		end)
		local light = deco({ Name = "LampLight" .. i, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(x + 1.4, 1006.5, -6), Transparency = 1 }, zone.folder)
		local pl = Instance.new("PointLight")
		pl.Color = c3(0xffd36e)
		pl.Range = 18
		pl.Brightness = 1.6
		pl.Parent = light
	end
	for _, x in st.benches do
		station("bench", x, 1000, -5, 1, function(m)
			deco({ Size = Vector3.new(4, 0.3, 1.2), CFrame = CFrame.new(x, 1001.1, -5), Color = c3(0x9a6233) }, m)
		end)
	end
	for _, d in st.dummies do
		station("target", d[1], 1007, -5, 0.8, function(m)
			deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.6, 2.6), CFrame = CFrame.new(d[1], 1007, -5) * CFrame.Angles(0, math.pi / 2, 0), Color = c3(0xff4d5e) }, m)
		end)
	end
	-- training sign
	local ts = deco({ Size = Vector3.new(14, 2, 0.3), CFrame = CFrame.new(46, 1013.5, -6), Transparency = 1 }, zone.folder)
	local tg = Instance.new("SurfaceGui")
	tg.Face = Enum.NormalId.Back
	tg.LightInfluence = 0
	tg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tg.PixelsPerStud = 40
	tg.Parent = ts
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.LuckiestGuy
	tl.TextScaled = true
	tl.Text = "TRAINING ZONE"
	tl.TextColor3 = c3(0xffd36e)
	tl.Parent = tg
	return zone
end

-- light pillar when someone rolls something rare
function Lobby.celebrate(color: Color3)
	local b = machineBeam
	if not b then
		return
	end
	b.Color = color
	b.Transparency = 0.15
	task.delay(4, function()
		if b.Parent then
			b.Transparency = 1
		end
	end)
end

function Lobby.spawnPoint(): (number, number)
	local sp = map.spawns[math.random(1, #map.spawns)]
	return sp[1] + (math.random() - 0.5) * 2, sp[2]
end

local weaponTimer = 0
local boardTimer = 0

local function refreshBoard()
	local g = board
	if not g then
		return
	end
	g:ClearAllChildren()
	local rows = {}
	for _, player in Players:GetPlayers() do
		local p = Data.get(player)
		if p then
			table.insert(rows, { name = player.DisplayName, wins = p.stats.wins, kills = p.stats.kills, coins = p.coins })
		end
	end
	table.sort(rows, function(a, b)
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		return a.kills > b.kills
	end)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 80)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.LuckiestGuy
	title.TextSize = 64
	title.Text = "TOP BRAWLERS"
	title.TextColor3 = Color3.fromRGB(255, 211, 110)
	title.Parent = g
	for i = 1, math.min(6, #rows) do
		local r = rows[i]
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -60, 0, 52)
		l.Position = UDim2.fromOffset(30, 80 + (i - 1) * 56)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextSize = 40
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = if i == 1 then Color3.fromRGB(255, 211, 110) else Color3.fromRGB(230, 226, 255)
		l.Text = string.format("%d. %s   🏆 %d   💥 %d", i, r.name, r.wins, r.kills)
		l.Parent = g
	end
end

function Lobby.update(dt: number)
	-- ready by standing in the portal
	local count, ready = 0, 0
	for _, player in Players:GetPlayers() do
		local f = Combat.forPlayer(player)
		local inPortal = false
		if f and f.zone == "lobby" and f.alive then
			local pos = f.root.Position
			inPortal = math.abs(pos.X - st.portal.x) < 3.4 and pos.Y < st.portal.y + 7
		end
		Lobby.ready[player] = inPortal or Lobby.uiReady[player] == true
		if f and f.zone == "lobby" then
			count += 1
			if Lobby.ready[player] then
				ready += 1
			end
		end
	end
	local pg = portalGlow
	if pg then
		pg.Transparency = if count > 0 then 0.6 - 0.5 * (ready / count) else 0.6
	end
	-- test weapons in the training zone
	weaponTimer -= dt
	if weaponTimer <= 0 then
		weaponTimer = 6
		if Combat.groundWeaponCount("lobby") < Config.LOBBY_WEAPONS then
			local w = Weapons.pick(math.random())
			Combat.spawnPickup(w.id, Vector3.new(map.weaponX[1] + math.random() * (map.weaponX[2] - map.weaponX[1]), map.weaponY, 0), Vector3.new(0, -5, 0))
		end
	end
	boardTimer -= dt
	if boardTimer <= 0 then
		boardTimer = 5
		refreshBoard()
	end
end

Players.PlayerRemoving:Connect(function(player)
	Lobby.ready[player] = nil
	Lobby.uiReady[player] = nil
end)

return Lobby
