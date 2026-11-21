--!strict
-- Screen UI: scoreboard, banners, countdown, kill feed, weapon / hp panel, crosshair,
-- vignettes, champion screen and touch controls.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Weapons = require(Shared:WaitForChild("Weapons"))

local Input = require(script.Parent:WaitForChild("Input"))

local Hud = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local scoreRow: Frame
local banner: TextLabel
local bannerSub: TextLabel
local bannerScale: UIScale
local countLabel: TextLabel
local countScale: UIScale
local feed: Frame
local weaponName: TextLabel
local ammoLabel: TextLabel
local hpFill: Frame
local hpText: TextLabel
local crosshair: Frame
local help: Frame
local spectate: TextLabel
local vignette: { Frame } = {}
local sdFrame: Frame
local champion: Frame
local bannerToken = 0
local thumbs: { [number]: string } = {}
local lowHp = 0
local hurtFlash = 0
local sdPulse = false

local function mk(className: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(className)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	return mk("UIStroke", { Thickness = thickness or 3, Color = color or Color3.fromRGB(18, 16, 28), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, parent)
end

local function corner(parent: Instance, r: number?)
	return mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, parent)
end

function Hud.init()
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("RumbleHud")
	if old then
		old:Destroy()
	end
	gui = mk("ScreenGui", { Name = "RumbleHud", IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, pg)

	-- vignettes (low hp / hurt)
	local dirs = {
		{ UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0.78, 0), -90 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.new(0.84, 0, 0, 0), 180 },
	}
	for i, d in dirs do
		local f = mk("Frame", { Size = d[1], Position = d[2], BackgroundColor3 = Color3.fromRGB(255, 30, 50), BorderSizePixel = 0, BackgroundTransparency = 1 }, gui)
		mk("UIGradient", { Rotation = d[3], Transparency = NumberSequence.new(0, 1) }, f)
		vignette[i] = f
	end
	sdFrame = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 40, 90), BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)

	-- scoreboard
	scoreRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 74), Position = UDim2.fromOffset(0, 46), BackgroundTransparency = 1 }, gui)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scoreRow)

	-- banner
	banner = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 110),
		Position = UDim2.new(0, 0, 0.3, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.LuckiestGuy,
		TextSize = 84,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		TextTransparency = 1,
	}, gui)
	stroke(banner, 6)
	bannerScale = mk("UIScale", { Scale = 1 }, banner)
	bannerSub = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.3, 104),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(240, 236, 255),
		Text = "",
		TextTransparency = 1,
	}, gui)
	stroke(bannerSub, 3)

	countLabel = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 200),
		Position = UDim2.new(0, 0, 0.5, -100),
		BackgroundTransparency = 1,
		Font = Enum.Font.LuckiestGuy,
		TextSize = 160,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Text = "",
		TextTransparency = 1,
	}, gui)
	stroke(countLabel, 8)
	countScale = mk("UIScale", { Scale = 1 }, countLabel)

	-- kill feed
	feed = mk("Frame", { Size = UDim2.new(0, 320, 0, 220), Position = UDim2.new(1, -330, 0, 130), BackgroundTransparency = 1 }, gui)
	mk("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, feed)

	-- me panel (hp + weapon)
	local panel = mk("Frame", { Size = UDim2.new(0, 280, 0, 92), Position = UDim2.new(0, 18, 1, -112), BackgroundColor3 = Color3.fromRGB(20, 18, 32), BackgroundTransparency = 0.25 }, gui)
	corner(panel, 14)
	stroke(panel, 2, Color3.fromRGB(70, 64, 100))
	local hpBack = mk("Frame", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(45, 40, 62) }, panel)
	corner(hpBack, 8)
	hpFill = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 230, 120) }, hpBack)
	corner(hpFill, 8)
	hpText = mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Text = "100" }, hpBack)
	stroke(hpText, 2)
	weaponName = mk("TextLabel", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 34), BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = "FISTS" }, panel)
	stroke(weaponName, 2)
	ammoLabel = mk("TextLabel", { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 62), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 220, 120), Text = "grab a weapon!" }, panel)
	stroke(ammoLabel, 2)

	-- crosshair
	crosshair = mk("Frame", { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 10 }, gui)
	corner(crosshair, 13)
	mk("UIStroke", { Thickness = 3, Color = Color3.new(1, 1, 1) }, crosshair)
	local dot = mk("Frame", { Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0.5, -3, 0.5, -3), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, crosshair)
	corner(dot, 3)

	-- help
	help = mk("Frame", { Size = UDim2.new(0, 300, 0, 196), Position = UDim2.new(1, -318, 1, -214), BackgroundColor3 = Color3.fromRGB(20, 18, 32), BackgroundTransparency = 0.2 }, gui)
	corner(help, 14)
	stroke(help, 2, Color3.fromRGB(70, 64, 100))
	mk("TextLabel", {
		Size = UDim2.new(1, -20, 1, -16),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(235, 232, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		RichText = true,
		Text = "<b>CONTROLS</b>  (H to hide)\n"
			.. "<font color='#ffd36e'>A / D</font>  move\n"
			.. "<font color='#ffd36e'>W / Space</font>  jump (again in air = flip)\n"
			.. "<font color='#ffd36e'>S</font>  crouch / fast fall\n"
			.. "<font color='#ffd36e'>Left click</font>  punch / shoot / swing\n"
			.. "<font color='#ffd36e'>Right click / Shift</font>  block (tap = parry)\n"
			.. "<font color='#ffd36e'>F / E</font>  throw your weapon\n"
			.. "Walk over weapons to grab them!",
	}, help)

	spectate = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -170), BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextSize = 30, TextColor3 = Color3.new(1, 1, 1), Text = "", TextTransparency = 0 }, gui)
	stroke(spectate, 3)

	champion = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 20), BackgroundTransparency = 1, Visible = false, ZIndex = 20 }, gui)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Hud.buildTouch()
		help.Visible = false
	end
	task.delay(25, function()
		if help then
			help.Visible = false
		end
	end)
end

function Hud.toggleHelp()
	help.Visible = not help.Visible
end

-------------------------------------------------------------------------------
-- touch controls

function Hud.buildTouch()
	local function button(text: string, pos: UDim2, size: number, color: Color3, onDown: () -> (), onUp: () -> ())
		local b = mk("TextButton", {
			Size = UDim2.fromOffset(size, size),
			Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.25,
			Font = Enum.Font.LuckiestGuy,
			TextSize = math.floor(size * 0.28),
			TextColor3 = Color3.new(1, 1, 1),
			Text = text,
			AutoButtonColor = false,
		}, gui)
		corner(b, math.floor(size / 2))
		stroke(b, 3)
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = 0
				onDown()
			end
		end)
		b.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				b.BackgroundTransparency = 0.25
				onUp()
			end
		end)
		return b
	end
	local dark = Color3.fromRGB(40, 36, 60)
	button("◀", UDim2.new(0, 80, 1, -110), 90, dark, function()
		Input.touchMove = -1
	end, function()
		if Input.touchMove < 0 then
			Input.touchMove = 0
		end
	end)
	button("▶", UDim2.new(0, 190, 1, -110), 90, dark, function()
		Input.touchMove = 1
	end, function()
		if Input.touchMove > 0 then
			Input.touchMove = 0
		end
	end)
	button("▼", UDim2.new(0, 135, 1, -30), 60, dark, function()
		Input.touchDown = true
	end, function()
		Input.touchDown = false
	end)
	button("JUMP", UDim2.new(1, -90, 1, -100), 100, Color3.fromRGB(63, 169, 255), function()
		Input.touchPress("jump", true)
	end, function()
		Input.touchPress("jump", false)
	end)
	button("HIT", UDim2.new(1, -200, 1, -150), 96, Color3.fromRGB(255, 77, 94), function()
		Input.touchPress("attack", true)
	end, function()
		Input.touchPress("attack", false)
	end)
	button("BLOCK", UDim2.new(1, -205, 1, -45), 72, Color3.fromRGB(142, 200, 74), function()
		Input.touchPress("block", true)
	end, function()
		Input.touchPress("block", false)
	end)
	button("THROW", UDim2.new(1, -90, 1, -215), 72, Color3.fromRGB(255, 160, 60), function()
		Input.touchPress("throw", true)
	end, function()
		Input.touchPress("throw", false)
	end)
end

-------------------------------------------------------------------------------
-- scoreboard

local function thumbFor(userId: number, image: ImageLabel)
	if thumbs[userId] then
		image.Image = thumbs[userId]
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and content then
			thumbs[userId] = content
			if image.Parent then
				image.Image = content
			end
		end
	end)
end

function Hud.setScores(scores: { any }, myFid: number)
	for _, c in scoreRow:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, s in scores do
		local cdef = Config.COLORS[s.color] or Config.COLORS[1]
		local card = mk("Frame", { Size = UDim2.fromOffset(132, 70), BackgroundColor3 = Color3.fromRGB(20, 18, 32), BackgroundTransparency = 0.2, LayoutOrder = i }, scoreRow)
		corner(card, 14)
		mk("UIStroke", { Thickness = if s.fid == myFid then 3 else 2, Color = cdef.main }, card)
		local face = mk("ImageLabel", { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 11), BackgroundColor3 = cdef.main, Image = "" }, card)
		corner(face, 24)
		if s.userId and s.userId > 0 then
			thumbFor(s.userId, face)
		else
			mk("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextSize = 26, TextColor3 = Color3.new(1, 1, 1), Text = string.upper(string.sub(s.name, 1, 1)) }, face)
		end
		local nm = mk("TextLabel", {
			Size = UDim2.new(1, -64, 0, 22),
			Position = UDim2.fromOffset(60, 8),
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = cdef.main:Lerp(Color3.new(1, 1, 1), 0.3),
			Text = if s.fid == myFid then "YOU" else s.name,
		}, card)
		stroke(nm, 2)
		local pips = mk("Frame", { Size = UDim2.new(1, -64, 0, 14), Position = UDim2.fromOffset(60, 36), BackgroundTransparency = 1 }, card)
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, pips)
		for k = 1, Config.WINS_TO_MATCH do
			local pip = mk("Frame", { Size = UDim2.fromOffset(10, 12), BackgroundColor3 = if k <= s.wins then cdef.main else Color3.fromRGB(60, 56, 80), BorderSizePixel = 0 }, pips)
			corner(pip, 3)
		end
	end
end

-------------------------------------------------------------------------------
-- banners

function Hud.banner(text: string, sub: string?, color: Color3?, duration: number?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color or Color3.new(1, 1, 1)
	banner.TextTransparency = 0
	bannerSub.Text = sub or ""
	bannerSub.TextTransparency = 0
	bannerScale.Scale = 0.3
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(duration or 2, function()
		if token ~= bannerToken then
			return
		end
		TweenService:Create(banner, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(bannerSub, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	end)
end

function Hud.count(text: string, color: Color3?)
	countLabel.Text = text
	countLabel.TextColor3 = color or Color3.fromRGB(255, 230, 120)
	countLabel.TextTransparency = 0
	countScale.Scale = 1.8
	TweenService:Create(countScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(countLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.55), { TextTransparency = 1 }):Play()
end

function Hud.feed(text: string, color: Color3?)
	local row = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Color3.fromRGB(20, 18, 32),
		BackgroundTransparency = 0.25,
		Font = Enum.Font.FredokaOne,
		TextSize = 17,
		RichText = true,
		TextColor3 = color or Color3.new(1, 1, 1),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = -math.floor(os.clock() * 100),
	}, feed)
	corner(row, 8)
	mk("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10) }, row)
	local rows = {}
	for _, c in feed:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(rows, c)
		end
	end
	if #rows > 6 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder > b.LayoutOrder
		end)
		rows[1]:Destroy()
	end
	task.delay(5, function()
		if row.Parent then
			TweenService:Create(row, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			row:Destroy()
		end
	end)
end

function Hud.spectate(text: string)
	spectate.Text = text
end

function Hud.hurt(amount: number)
	hurtFlash = math.min(0.6, hurtFlash + amount / 60)
end

function Hud.suddenDeath(on: boolean)
	sdPulse = on
	if not on then
		sdFrame.BackgroundTransparency = 1
	end
end

function Hud.champion(name: string, color: Color3, userId: number)
	champion.Visible = true
	champion.BackgroundTransparency = 1
	for _, c in champion:GetChildren() do
		c:Destroy()
	end
	TweenService:Create(champion, TweenInfo.new(0.5), { BackgroundTransparency = 0.35 }):Play()
	local face = mk("ImageLabel", { Size = UDim2.fromOffset(170, 170), Position = UDim2.new(0.5, -85, 0.28, -85), BackgroundColor3 = color, ZIndex = 21 }, champion)
	corner(face, 85)
	mk("UIStroke", { Thickness = 6, Color = Color3.new(1, 1, 1) }, face)
	if userId > 0 then
		thumbFor(userId, face)
	end
	local title = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 100), Position = UDim2.new(0, 0, 0.28, 100), BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextSize = 90, TextColor3 = color, Text = string.upper(name), ZIndex = 21 }, champion)
	stroke(title, 7)
	local sub = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.new(0, 0, 0.28, 196), BackgroundTransparency = 1, Font = Enum.Font.LuckiestGuy, TextSize = 44, TextColor3 = Color3.fromRGB(255, 230, 120), Text = "IS THE CHAMPION!", ZIndex = 21 }, champion)
	stroke(sub, 4)
	local s = mk("UIScale", { Scale = 0.2 }, title)
	TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Hud.hideChampion()
	champion.Visible = false
end

-------------------------------------------------------------------------------
-- per frame

function Hud.update(dt: number, hp: number, alive: boolean, wid: number, ammo: number, color: Color3, showCrosshair: boolean)
	-- hp
	local frac = math.clamp(hp / Config.MAX_HP, 0, 1)
	hpFill.Size = UDim2.fromScale(frac, 1)
	hpFill.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(120, 230, 120) elseif frac > 0.25 then Color3.fromRGB(255, 190, 60) else Color3.fromRGB(255, 70, 70)
	hpText.Text = if alive then tostring(math.ceil(hp)) else "KO"
	-- weapon
	local w = Weapons.get(wid)
	if w then
		weaponName.Text = string.upper(w.name)
		if w.kind == "melee" then
			ammoLabel.Text = "swing it! (F to throw)"
		else
			ammoLabel.Text = string.rep("● ", math.min(ammo, 12)) .. (if ammo > 12 then "x" .. ammo else "")
			if ammo <= 0 then
				ammoLabel.Text = "EMPTY - tossing it!"
			end
		end
	else
		weaponName.Text = "FISTS"
		ammoLabel.Text = "grab a weapon!"
	end
	-- crosshair
	crosshair.Visible = showCrosshair
	if showCrosshair then
		local m = UserInputService:GetMouseLocation()
		crosshair.Position = UDim2.fromOffset(m.X, m.Y)
		local st = crosshair:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = color
		end
	end
	UserInputService.MouseIconEnabled = not showCrosshair
	-- vignettes
	local target = if alive and frac < 0.35 then (0.35 - frac) * 1.6 else 0
	lowHp += (target - lowHp) * math.min(1, dt * 4)
	hurtFlash = math.max(0, hurtFlash - dt * 1.5)
	local pulse = lowHp * (0.75 + 0.25 * math.sin(os.clock() * 6)) + hurtFlash
	for _, f in vignette do
		f.BackgroundTransparency = 1 - math.clamp(pulse, 0, 0.75)
	end
	if sdPulse then
		sdFrame.BackgroundTransparency = 0.93 + math.sin(os.clock() * 5) * 0.04
	end
end

return Hud
