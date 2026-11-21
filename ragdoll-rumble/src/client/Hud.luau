--!strict
-- In-match HUD: fighter bar, banners, countdown, kill feed, crosshair, vignettes,
-- KO panel, results podium, controls help and touch controls.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local UI = require(script.Parent:WaitForChild("UIKit"))
local Input = require(script.Parent:WaitForChild("Input"))
local Store = require(script.Parent:WaitForChild("Store"))

local Hud = {}

local gui: ScreenGui
local bar: Frame
local cards: { [number]: any } = {}
local bannerHolder: Frame
local countLabel: TextLabel
local feed: Frame
local cross: Frame
local crossTicks: { Frame } = {}
local crossKick = 0
local vignette: { Frame } = {}
local sdFrame: Frame
local koPanel: Frame
local koText: TextLabel
local koSub: TextLabel
local help: Frame
local results: Frame
local spectate: TextLabel
local weaponCard: Frame
local weaponName: TextLabel
local ammoBar: Frame
local ammoText: TextLabel
local touch: Frame? = nil
local lowHp, hurtFlash = 0, 0
local sdOn = false
local bannerToken = 0

local function colorOf(ci: number?): Color3
	local c = Config.COLORS[ci or 1] or Config.COLORS[1]
	return c.main
end

function Hud.init(parent: Instance)
	gui = UI.new("ScreenGui", { Name = "RumbleHud", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parent)

	-- vignettes
	local dirs = {
		{ UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.75, 0), -90 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0.82, 0, 0, 0), 180 },
	}
	for i, d in dirs do
		local f = UI.new("Frame", { Size = d[1], Position = d[2], BackgroundColor3 = Color3.fromRGB(255, 30, 60), BorderSizePixel = 0, BackgroundTransparency = 1 }, gui)
		UI.new("UIGradient", { Rotation = d[3], Transparency = NumberSequence.new(0, 1) }, f)
		vignette[i] = f
	end
	sdFrame = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 120), BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)

	-- fighter bar
	bar = UI.new("Frame", { Size = UDim2.new(1, -40, 0, 86), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, gui)
	UI.list(bar, true, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)

	-- weapon card (mine)
	weaponCard = UI.panel({ Size = UDim2.fromOffset(250, 66), Position = UDim2.new(0, 16, 1, -112), AnchorPoint = Vector2.new(0, 1) }, gui)
	weaponName = UI.text({ Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(12, 4), FontFace = UI.TITLE, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, Text = "FISTS", ZIndex = 2 }, weaponCard)
	UI.textStroke(weaponName, 2)
	local ammoTrack = UI.new("Frame", { Size = UDim2.new(1, -24, 0, 10), Position = UDim2.fromOffset(12, 40), BackgroundColor3 = UI.C.bg2, ZIndex = 2 }, weaponCard)
	UI.round(ammoTrack)
	ammoBar = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.C.gold, ZIndex = 3 }, ammoTrack)
	UI.round(ammoBar)
	ammoText = UI.text({ Size = UDim2.new(0, 120, 0, 20), Position = UDim2.new(1, -132, 0, 10), FontFace = UI.HEAVY, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.C.gold, Text = "", ZIndex = 2 }, weaponCard)
	UI.textStroke(ammoText, 1.5)

	-- banners + countdown
	bannerHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 160), Position = UDim2.new(0, 0, 0.28, 0), BackgroundTransparency = 1, ZIndex = 8 }, gui)
	countLabel = UI.text({ Size = UDim2.new(1, 0, 0, 220), Position = UDim2.new(0, 0, 0.5, -110), FontFace = UI.TITLE, TextSize = 190, TextColor3 = UI.C.gold, Text = "", TextTransparency = 1, ZIndex = 9 }, gui)
	UI.textStroke(countLabel, 9)

	-- kill feed
	feed = UI.new("Frame", { Size = UDim2.new(0, 380, 0, 260), Position = UDim2.new(1, -16, 0, 150), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1 }, gui)
	UI.list(feed, false, 5, Enum.HorizontalAlignment.Right)

	-- crosshair
	cross = UI.new("Frame", { Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, gui)
	local dot = UI.new("Frame", { Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0.5, -3, 0.5, -3), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 21 }, cross)
	UI.round(dot)
	UI.stroke(dot, 1.5, UI.C.dark)
	for i = 1, 4 do
		local t = UI.new("Frame", { Size = if i % 2 == 0 then UDim2.fromOffset(12, 4) else UDim2.fromOffset(4, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 21 }, cross)
		UI.corner(t, 2)
		UI.stroke(t, 1.5, UI.C.dark)
		crossTicks[i] = t
	end

	-- KO panel
	koPanel = UI.panel({ Size = UDim2.fromOffset(440, 96), Position = UDim2.new(0.5, 0, 0.72, 0), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 10 }, gui)
	koText = UI.text({ Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 10), FontFace = UI.TITLE, TextSize = 38, TextColor3 = UI.C.red, Text = "", ZIndex = 11 }, koPanel)
	UI.textStroke(koText, 3)
	koSub = UI.text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 58), FontFace = UI.BOLD, TextSize = 17, TextColor3 = UI.C.dim, Text = "", ZIndex = 11, RichText = true }, koPanel)

	spectate = UI.text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -140), FontFace = UI.TITLE, TextSize = 24, Text = "", ZIndex = 6 }, gui)
	UI.textStroke(spectate, 2)

	-- help
	help = UI.panel({ Size = UDim2.fromOffset(330, 236), Position = UDim2.new(1, -16, 1, -112), AnchorPoint = Vector2.new(1, 1) }, gui)
	UI.text({
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		TextSize = 16,
		FontFace = UI.BOLD,
		ZIndex = 2,
		Text = "<font color='#ffd36e'><b>CONTROLS</b></font>   (H to hide)\n"
			.. "<font color='#5bc0ff'>A / D</font>   move\n"
			.. "<font color='#5bc0ff'>W / Space</font>   jump · again in air = flip\n"
			.. "<font color='#5bc0ff'>S</font>   crouch · fast fall\n"
			.. "<font color='#5bc0ff'>Left click</font>   punch / shoot / swing\n"
			.. "<font color='#5bc0ff'>Right click / Shift</font>   block (tap = parry)\n"
			.. "<font color='#5bc0ff'>F / Q</font>   throw your weapon\n"
			.. "<font color='#5bc0ff'>E</font>   use stations in the lobby\n"
			.. "Walk over weapons to grab them!",
	}, help)

	-- results
	results = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.C.dark, BackgroundTransparency = 0.25, Visible = false, ZIndex = 30 }, gui)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Hud.buildTouch()
		help.Visible = false
	end
end

function Hud.toggleHelp()
	help.Visible = not help.Visible
end

-------------------------------------------------------------------------------
-- touch controls

function Hud.buildTouch()
	local t = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	touch = t
	local function button(text: string, pos: UDim2, size: number, color: Color3, onDown: () -> (), onUp: () -> ())
		local b = UI.new("TextButton", { Size = UDim2.fromOffset(size, size), Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = 0.2, Text = "", AutoButtonColor = false }, t)
		UI.round(b)
		UI.stroke(b, 3, Color3.new(1, 1, 1), 0.4)
		local l = UI.text({ Size = UDim2.fromScale(1, 1), Text = text, FontFace = UI.TITLE, TextSize = math.floor(size * 0.27) }, b)
		UI.textStroke(l, 2)
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				b.BackgroundTransparency = 0
				UI.scale(b).Scale = 0.9
				onDown()
			end
		end)
		b.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				b.BackgroundTransparency = 0.2
				UI.scale(b).Scale = 1
				onUp()
			end
		end)
	end
	local dark = Color3.fromRGB(40, 36, 64)
	button("◀", UDim2.new(0, 80, 1, -150), 92, dark, function()
		Input.touchMove = -1
	end, function()
		if Input.touchMove < 0 then
			Input.touchMove = 0
		end
	end)
	button("▶", UDim2.new(0, 190, 1, -150), 92, dark, function()
		Input.touchMove = 1
	end, function()
		if Input.touchMove > 0 then
			Input.touchMove = 0
		end
	end)
	button("▼", UDim2.new(0, 135, 1, -64), 62, dark, function()
		Input.touchDown = true
	end, function()
		Input.touchDown = false
	end)
	button("JUMP", UDim2.new(1, -90, 1, -150), 104, UI.C.cyan, function()
		Input.touchPress("jump", true)
	end, function()
		Input.touchPress("jump", false)
	end)
	button("HIT", UDim2.new(1, -205, 1, -200), 100, UI.C.red, function()
		Input.touchPress("attack", true)
	end, function()
		Input.touchPress("attack", false)
	end)
	button("BLOCK", UDim2.new(1, -210, 1, -88), 76, UI.C.green, function()
		Input.touchPress("block", true)
	end, function()
		Input.touchPress("block", false)
	end)
	button("THROW", UDim2.new(1, -90, 1, -262), 76, Color3.fromRGB(255, 143, 60), function()
		Input.touchPress("throw", true)
	end, function()
		Input.touchPress("throw", false)
	end)
end

-------------------------------------------------------------------------------
-- fighter bar

local function makeCard(s: any): any
	local col = colorOf(s.color)
	local me = s.fid == Store.myFid
	local w = if me then 200 else 168
	local card = UI.panel({ Size = UDim2.fromOffset(w, if me then 80 else 70), LayoutOrder = if me then -1 else s.fid }, bar)
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if me then UI.C.gold else col
		st.Thickness = if me then 3 else 2
		st.Transparency = 0
	end
	local face = UI.new("ImageLabel", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = col, ZIndex = 2 }, card)
	UI.round(face)
	UI.stroke(face, 2.5, col)
	if s.userId and s.userId > 0 then
		UI.thumb(s.userId, face)
	else
		UI.text({ Size = UDim2.fromScale(1, 1), Text = string.upper(string.sub(s.name, 1, 1)), FontFace = UI.TITLE, TextSize = 26, ZIndex = 3 }, face)
	end
	local nm = UI.text({ Size = UDim2.new(1, -66, 0, 20), Position = UDim2.fromOffset(60, 6), Text = if me then "YOU" else s.name, FontFace = UI.HEAVY, TextSize = 16, TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.3), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 }, card)
	UI.textStroke(nm, 1.5)
	local track = UI.new("Frame", { Size = UDim2.new(1, -68, 0, 12), Position = UDim2.fromOffset(60, 30), BackgroundColor3 = UI.C.dark, ZIndex = 2 }, card)
	UI.round(track)
	local trail = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 }, track)
	UI.round(trail)
	local hp = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = col, ZIndex = 4 }, track)
	UI.round(hp)
	UI.gradient(hp, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210), 90)
	local pips = UI.new("Frame", { Size = UDim2.new(1, -68, 0, 12), Position = UDim2.fromOffset(60, 48), BackgroundTransparency = 1, ZIndex = 2 }, card)
	UI.list(pips, true, 3)
	local pipList = {}
	for k = 1, Config.WINS_TO_MATCH do
		local p = UI.new("Frame", { Size = UDim2.fromOffset(16, 9), BackgroundColor3 = UI.C.bg2, ZIndex = 3, LayoutOrder = k }, pips)
		UI.corner(p, 3)
		pipList[k] = p
	end
	local ko = UI.text({ Size = UDim2.fromScale(1, 1), Text = "KO", FontFace = UI.TITLE, TextSize = 44, TextColor3 = UI.C.red, Rotation = -12, Visible = false, ZIndex = 8 }, card)
	UI.textStroke(ko, 3)
	return { card = card, hp = hp, trail = trail, pips = pipList, ko = ko, color = col, shownHp = 1, trailHp = 1, wins = -1, dead = false }
end

function Hud.setRoster(scores: { any })
	for fid, c in cards do
		c.card:Destroy()
		cards[fid] = nil
	end
	for _, s in scores do
		if s.inMatch then
			cards[s.fid] = makeCard(s)
		end
	end
	Hud.setScores(scores)
end

function Hud.setScores(scores: { any })
	for _, s in scores do
		local c = cards[s.fid]
		if c and c.wins ~= s.wins then
			for k, p in c.pips do
				local on = k <= s.wins
				p.BackgroundColor3 = if on then UI.C.gold else UI.C.bg2
				if on and k > math.max(c.wins, 0) and c.wins >= 0 then
					UI.pop(p, 2.2, 0.4)
				end
			end
			c.wins = s.wins
		end
	end
end

-------------------------------------------------------------------------------
-- banners / countdown / feed

function Hud.banner(text: string, sub: string?, color: Color3?, duration: number?)
	bannerToken += 1
	local token = bannerToken
	for _, c in bannerHolder:GetChildren() do
		c:Destroy()
	end
	local col = color or UI.C.pink
	local stripe = UI.new("Frame", { Size = UDim2.new(1.4, 0, 0, 110), Position = UDim2.new(-1.4, 0, 0, 10), BackgroundColor3 = col, BackgroundTransparency = 0.15, Rotation = -3, ZIndex = 8 }, bannerHolder)
	UI.gradient(stripe, col, col:Lerp(Color3.new(0, 0, 0), 0.5), 0)
	local t = UI.text({ Size = UDim2.new(1, 0, 0, 100), Position = UDim2.fromOffset(0, 12), Text = text, FontFace = UI.TITLE, TextSize = 88, ZIndex = 9 }, bannerHolder)
	UI.textStroke(t, 6, col:Lerp(Color3.new(0, 0, 0), 0.65))
	local s = UI.text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 120), Text = sub or "", FontFace = UI.HEAVY, TextSize = 26, ZIndex = 9 }, bannerHolder)
	UI.textStroke(s, 2.5)
	UI.tween(stripe, 0.35, { Position = UDim2.new(-0.2, 0, 0, 10) }, Enum.EasingStyle.Quint)
	UI.pop(t, 0.4, 0.4)
	task.delay(duration or 2, function()
		if token ~= bannerToken then
			return
		end
		UI.tween(stripe, 0.3, { Position = UDim2.new(1.2, 0, 0, 10) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		UI.tween(t, 0.3, { TextTransparency = 1 })
		UI.tween(s, 0.3, { TextTransparency = 1 })
	end)
end

function Hud.count(text: string, color: Color3?)
	countLabel.Text = text
	countLabel.TextColor3 = color or UI.C.gold
	countLabel.TextTransparency = 0
	countLabel.Rotation = math.random(-6, 6)
	UI.pop(countLabel, 2.2, 0.3)
	UI.tween(countLabel, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.6)
end

local CAUSE_ICON = {
	punch = "👊", melee = "🗡️", bullet = "🔫", explosion = "💥", fell = "🕳️", saw = "🪚", spikes = "📌", thrown = "🎯", deflected = "↩️", admin = "🛠️",
}

function Hud.feed(killer: string?, killerColor: Color3?, victim: string, victimColor: Color3, cause: string)
	local row = UI.panel({ Size = UDim2.new(0, 0, 0, 36), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = -math.floor(os.clock() * 100) }, feed)
	UI.pad(row, 0, 12)
	UI.list(row, true, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	local function name(text: string, col: Color3, order: number)
		local l = UI.text({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = text, FontFace = UI.HEAVY, TextSize = 17, TextColor3 = col, LayoutOrder = order, ZIndex = 2 }, row)
		UI.textStroke(l, 1.5)
	end
	if killer then
		name(killer, killerColor or Color3.new(1, 1, 1), 1)
	end
	UI.text({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = CAUSE_ICON[cause] or "💀", TextSize = 18, LayoutOrder = 2, ZIndex = 2 }, row)
	name(victim, victimColor, 3)
	UI.pop(row, 0.6)
	local n = 0
	for _, c in feed:GetChildren() do
		if c:IsA("Frame") then
			n += 1
		end
	end
	task.delay(5, function()
		if row.Parent then
			UI.tween(row, 0.35, { BackgroundTransparency = 1 })
			for _, d in row:GetDescendants() do
				if d:IsA("TextLabel") then
					UI.tween(d, 0.35, { TextTransparency = 1 })
				elseif d:IsA("UIStroke") then
					UI.tween(d, 0.35, { Transparency = 1 })
				end
			end
			task.wait(0.4)
			row:Destroy()
		end
	end)
	local _ = n
end

function Hud.ko(killer: string?, killerColor: Color3?, finisher: string?)
	koPanel.Visible = true
	koText.Text = if killer then "KO'D BY " .. string.upper(killer) else "KNOCKED OUT"
	koText.TextColor3 = killerColor or UI.C.red
	koSub.Text = if finisher then "finished with <b>" .. finisher .. "</b> · spectating..." else "spectating until the next round..."
	UI.pop(koPanel, 0.6)
	task.delay(3.5, function()
		koPanel.Visible = false
	end)
end

function Hud.hurt(amount: number)
	hurtFlash = math.min(0.6, hurtFlash + amount / 60)
end

function Hud.kick(amount: number)
	crossKick = math.min(1, crossKick + amount)
end

function Hud.suddenDeath(on: boolean)
	sdOn = on
	if not on then
		sdFrame.BackgroundTransparency = 1
	end
end

function Hud.spectate(text: string)
	spectate.Text = text
end

-------------------------------------------------------------------------------
-- results podium

function Hud.results(placements: { any }, myCoins: number)
	results:ClearAllChildren()
	results.Visible = true
	results.BackgroundTransparency = 1
	UI.tween(results, 0.4, { BackgroundTransparency = 0.2 })
	local title = UI.text({ Size = UDim2.new(1, 0, 0, 90), Position = UDim2.new(0, 0, 0.08, 0), Text = "MATCH RESULTS", FontFace = UI.TITLE, TextSize = 76, TextColor3 = UI.C.gold, ZIndex = 31 }, results)
	UI.textStroke(title, 5)
	UI.pop(title, 0.5)
	local heights = { 220, 160, 120 }
	local xs = { 0.5, 0.32, 0.68 }
	for i = 1, math.min(3, #placements) do
		local p = placements[i]
		local col = colorOf(p.color)
		local holder = UI.new("Frame", { Size = UDim2.fromOffset(200, heights[i] + 190), Position = UDim2.new(xs[i], 0, 0.86, 0), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, ZIndex = 31 }, results)
		local ped = UI.panel({ Size = UDim2.new(1, 0, 0, heights[i]), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), ZIndex = 31 }, holder)
		local st = ped:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = col
			st.Thickness = 3
		end
		local rank = UI.text({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 10), Text = tostring(i), FontFace = UI.TITLE, TextSize = 64, TextColor3 = if i == 1 then UI.C.gold else UI.C.text, ZIndex = 32 }, ped)
		UI.textStroke(rank, 4)
		UI.text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 80), Text = string.format("🏆 %d   💥 %d", p.wins, p.kills), FontFace = UI.HEAVY, TextSize = 18, ZIndex = 32 }, ped)
		local face = UI.new("ImageLabel", { Size = UDim2.fromOffset(120, 120), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = col, ZIndex = 32 }, holder)
		UI.round(face)
		UI.stroke(face, 5, if i == 1 then UI.C.gold else col)
		if p.userId > 0 then
			UI.thumb(p.userId, face)
		else
			UI.text({ Size = UDim2.fromScale(1, 1), Text = string.upper(string.sub(p.name, 1, 1)), FontFace = UI.TITLE, TextSize = 60, ZIndex = 33 }, face)
		end
		local nm = UI.text({ Size = UDim2.new(1, 40, 0, 34), Position = UDim2.new(0.5, 0, 0, 134), AnchorPoint = Vector2.new(0.5, 0), Text = if p.fid == Store.myFid then "YOU" else p.name, FontFace = UI.TITLE, TextSize = 30, TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.2), ZIndex = 32 }, holder)
		UI.textStroke(nm, 3)
		if i == 1 then
			UI.rays(face, UI.C.gold, 12, 31)
			local crown = UI.text({ Size = UDim2.fromOffset(80, 60), Position = UDim2.new(0.5, 0, 0, -48), AnchorPoint = Vector2.new(0.5, 0), Text = "👑", TextSize = 52, ZIndex = 34 }, holder)
			UI.pop(crown, 0.2, 0.6)
		end
		holder.Position = UDim2.new(xs[i], 0, 1.6, 0)
		UI.tween(holder, 0.6, { Position = UDim2.new(xs[i], 0, 0.86, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.25 * (4 - i))
	end
	if myCoins > 0 then
		local cl = UI.text({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0.92, 0), Text = "", FontFace = UI.TITLE, TextSize = 32, TextColor3 = UI.C.gold, ZIndex = 31 }, results)
		UI.textStroke(cl, 3)
		UI.countTo(cl, 0, myCoins, 1.4, "+ ")
		task.delay(1.45, function()
			cl.Text = "+ " .. UI.fmt(myCoins) .. " ★ this match"
		end)
	end
end

function Hud.hideResults()
	if results.Visible then
		UI.tween(results, 0.3, { BackgroundTransparency = 1 })
		task.delay(0.3, function()
			results.Visible = false
			results:ClearAllChildren()
		end)
	end
end

-------------------------------------------------------------------------------
-- per frame

-- hpOf(fid) -> hp, alive (nil if unknown)
function Hud.update(dt: number, inMatchView: boolean, hpOf: (number) -> (number?, boolean?), me: any)
	bar.Visible = inMatchView
	weaponCard.Visible = me.inArena
	for fid, c in cards do
		local hp, alive = hpOf(fid)
		local frac = math.clamp((hp or 0) / Config.MAX_HP, 0, 1)
		c.shownHp += (frac - c.shownHp) * math.min(1, dt * 14)
		if frac < c.trailHp then
			c.trailHp = math.max(frac, c.trailHp - dt * 0.35)
		else
			c.trailHp = frac
		end
		c.hp.Size = UDim2.fromScale(c.shownHp, 1)
		c.trail.Size = UDim2.fromScale(c.trailHp, 1)
		c.hp.BackgroundColor3 = if frac > 0.5 then c.color elseif frac > 0.25 then Color3.fromRGB(255, 190, 60) else Color3.fromRGB(255, 70, 70)
		local dead = alive == false
		if dead ~= c.dead then
			c.dead = dead
			c.ko.Visible = dead
			if dead then
				UI.pop(c.ko, 2.5, 0.3)
			end
			c.card.BackgroundTransparency = if dead then 0.5 else 0.06
		end
	end
	-- weapon card
	local w = Weapons.get(me.wid)
	if w then
		weaponName.Text = string.upper(w.name)
		if w.kind == "melee" then
			ammoBar.Size = UDim2.fromScale(1, 1)
			ammoText.Text = "∞"
		else
			ammoBar.Size = UDim2.fromScale(math.clamp(me.ammo / math.max(1, w.ammo), 0, 1), 1)
			ammoText.Text = if me.ammo > 0 then tostring(me.ammo) .. " / " .. tostring(w.ammo) else "EMPTY"
		end
	else
		weaponName.Text = "FISTS"
		ammoBar.Size = UDim2.fromScale(0, 1)
		ammoText.Text = "grab a weapon!"
	end
	-- crosshair
	cross.Visible = me.crosshair
	UserInputService.MouseIconEnabled = not me.crosshair
	if me.crosshair then
		local m = UserInputService:GetMouseLocation()
		cross.Position = UDim2.fromOffset(m.X, m.Y)
		crossKick = math.max(0, crossKick - dt * 5)
		local gap = 9 + crossKick * 14
		local offs = { Vector2.new(0, -gap), Vector2.new(gap, 0), Vector2.new(0, gap), Vector2.new(-gap, 0) }
		for i, t in crossTicks do
			t.Position = UDim2.new(0.5, offs[i].X, 0.5, offs[i].Y)
			t.BackgroundColor3 = me.color
		end
	end
	-- vignettes
	local frac = math.clamp(me.hp / Config.MAX_HP, 0, 1)
	local target = if me.alive and me.inArena and frac < 0.35 then (0.35 - frac) * 1.6 else 0
	lowHp += (target - lowHp) * math.min(1, dt * 4)
	hurtFlash = math.max(0, hurtFlash - dt * 1.5)
	local pulse = lowHp * (0.75 + 0.25 * math.sin(os.clock() * 6)) + hurtFlash
	for _, f in vignette do
		f.BackgroundTransparency = 1 - math.clamp(pulse, 0, 0.75)
	end
	if sdOn then
		sdFrame.BackgroundTransparency = 0.93 + math.sin(os.clock() * 5) * 0.04
	end
	if touch then
		touch.Visible = me.alive
	end
end

function Hud.gui(): ScreenGui
	return gui
end

return Hud
