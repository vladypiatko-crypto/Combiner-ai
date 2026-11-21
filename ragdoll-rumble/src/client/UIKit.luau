--!strict
-- Tiny UI kit: one consistent look (dark glass + neon accents) and animated components.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local UI = {}

UI.C = {
	bg = Color3.fromRGB(17, 15, 31),
	bg2 = Color3.fromRGB(30, 25, 54),
	line = Color3.fromRGB(92, 80, 150),
	text = Color3.fromRGB(241, 238, 255),
	dim = Color3.fromRGB(160, 152, 200),
	pink = Color3.fromRGB(255, 93, 207),
	cyan = Color3.fromRGB(91, 192, 255),
	gold = Color3.fromRGB(255, 211, 110),
	green = Color3.fromRGB(110, 230, 130),
	red = Color3.fromRGB(255, 77, 94),
	dark = Color3.fromRGB(10, 9, 18),
}

UI.TITLE = Font.fromEnum(Enum.Font.LuckiestGuy)
UI.ROUND = Font.fromEnum(Enum.Font.FredokaOne)
UI.BOLD = Font.fromName("BuilderSans", Enum.FontWeight.Bold)
UI.HEAVY = Font.fromName("BuilderSans", Enum.FontWeight.Heavy)
UI.BODY = Font.fromName("BuilderSans", Enum.FontWeight.Medium)

UI.click = function() end -- set by the main script (plays a sound)
UI.hover = function() end

function UI.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local i = Instance.new(className)
	if props then
		for k, v in props do
			(i :: any)[k] = v
		end
	end
	if parent then
		i.Parent = parent
	end
	return i
end

function UI.corner(parent: Instance, r: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, parent)
end

function UI.round(parent: Instance): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or UI.C.line,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.textStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or UI.C.dark,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

function UI.pad(parent: Instance, all: number, x: number?)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, x or all),
		PaddingRight = UDim.new(0, x or all),
	}, parent)
end

function UI.list(parent: Instance, horizontal: boolean, padding: number, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

function UI.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?): UIGradient
	return UI.new("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 90 }, parent)
end

function UI.tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

function UI.scale(obj: Instance): UIScale
	local s = obj:FindFirstChildOfClass("UIScale")
	if not s then
		s = UI.new("UIScale", { Scale = 1 }, obj)
	end
	return s :: UIScale
end

function UI.pop(obj: Instance, from: number?, t: number?)
	local s = UI.scale(obj)
	s.Scale = from or 0.6
	UI.tween(s, t or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- glassy panel
function UI.panel(props: { [string]: any }, parent: Instance?): Frame
	local f = UI.new("Frame", { BackgroundColor3 = UI.C.bg, BackgroundTransparency = 0.06, BorderSizePixel = 0 }, nil)
	for k, v in props do
		(f :: any)[k] = v
	end
	UI.corner(f, 16)
	UI.stroke(f, 2, UI.C.line, 0.25)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 210)),
		Rotation = 90,
	}, f)
	if parent then
		f.Parent = parent
	end
	return f
end

function UI.text(props: { [string]: any }, parent: Instance?): TextLabel
	local t = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = UI.BOLD,
		TextColor3 = UI.C.text,
		TextSize = 18,
		Text = "",
	}, nil)
	for k, v in props do
		(t :: any)[k] = v
	end
	if parent then
		t.Parent = parent
	end
	return t
end

-- big friendly animated button
function UI.button(parent: Instance, o: { [string]: any }): TextButton
	local color: Color3 = o.color or UI.C.pink
	local b = UI.new("TextButton", {
		Name = o.name or "Button",
		Size = o.size or UDim2.fromOffset(160, 48),
		Position = o.position or UDim2.new(),
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = o.order or 0,
		ZIndex = o.z or 1,
	}, parent)
	UI.corner(b, o.radius or 14)
	local st = UI.stroke(b, 2, color:Lerp(Color3.new(1, 1, 1), 0.45), 0.1)
	UI.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205)),
		Rotation = 90,
	}, b)
	-- bottom "lip" for a chunky 3D feel
	local lip = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -3),
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45),
		BorderSizePixel = 0,
		ZIndex = (o.z or 1) - 1,
	}, b)
	UI.corner(lip, o.radius or 14)
	local label = UI.text({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = (if o.icon then o.icon .. "  " else "") .. (o.text or ""),
		FontFace = o.font or UI.TITLE,
		TextSize = o.textSize or 22,
		TextColor3 = o.textColor or Color3.new(1, 1, 1),
		ZIndex = (o.z or 1) + 1,
	}, b)
	UI.textStroke(label, 2, color:Lerp(Color3.new(0, 0, 0), 0.6))
	local sc = UI.scale(b)
	b.MouseEnter:Connect(function()
		UI.tween(sc, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
		UI.tween(st, 0.15, { Transparency = 0 })
		UI.hover()
	end)
	b.MouseLeave:Connect(function()
		UI.tween(sc, 0.15, { Scale = 1 })
		UI.tween(st, 0.15, { Transparency = 0.1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(sc, 0.08, { Scale = 0.93 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(sc, 0.2, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	if o.onClick then
		b.Activated:Connect(function()
			UI.click()
			o.onClick()
		end)
	end
	return b
end

function UI.setButton(b: TextButton, text: string?, color: Color3?)
	local label = b:FindFirstChild("Label") :: TextLabel?
	if label and text then
		label.Text = text
	end
	if color then
		b.BackgroundColor3 = color
		local lip = b:FindFirstChildOfClass("Frame")
		if lip then
			lip.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.45)
		end
		local st = b:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
		end
	end
end

-- endless shimmer across a gui object (rarity labels, legendary cards)
function UI.shimmer(obj: GuiObject, colors: { Color3 }, speed: number?): UIGradient
	local kp = {}
	for i, c in colors do
		table.insert(kp, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	local g = UI.new("UIGradient", { Color = ColorSequence.new(kp), Rotation = 20 }, obj)
	local s = speed or 0.6
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not g.Parent then
			conn:Disconnect()
			return
		end
		local t = (os.clock() * s) % 2
		g.Offset = Vector2.new(t - 1, 0)
	end)
	return g
end

-- spinning sunburst rays behind something special
function UI.rays(parent: GuiObject, color: Color3, count: number?, z: number?): Frame
	local holder = UI.new("Frame", {
		Size = UDim2.fromScale(2.2, 2.2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z or 0,
	}, parent)
	-- GUI rotation pivots around an object's center, so each ray is a full bar through
	-- the middle (one bar = two opposite rays)
	local n = math.max(1, math.floor((count or 12) / 2))
	for i = 1, n do
		local ray = UI.new("Frame", {
			Size = UDim2.new(0, 56, 1, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = (i - 1) * (180 / n),
			ZIndex = z or 0,
		}, holder)
		UI.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Rotation = 90,
		}, ray)
	end
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		holder.Rotation = (holder.Rotation + dt * 25) % 360
	end)
	return holder
end

-------------------------------------------------------------------------------
-- toasts

local toastHolder: Frame? = nil

function UI.toasts(parent: Instance)
	local h = UI.new("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 520, 0, 300),
		Position = UDim2.new(0.5, 0, 0, 132),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}, parent)
	UI.list(h, false, 6, Enum.HorizontalAlignment.Center)
	toastHolder = h
end

function UI.toast(text: string, color: Color3?, life: number?, rich: boolean?): Frame?
	local h = toastHolder
	if not h then
		return nil
	end
	local col = color or UI.C.cyan
	local f = UI.new("Frame", {
		Size = UDim2.new(0, 0, 0, 42),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = UI.C.bg,
		BackgroundTransparency = 0.05,
		LayoutOrder = math.floor(os.clock() * 100),
		ZIndex = 50,
	}, h)
	UI.corner(f, 21)
	UI.stroke(f, 2, col, 0)
	UI.pad(f, 0, 18)
	local t = UI.text({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		RichText = rich == true,
		TextSize = 19,
		FontFace = UI.HEAVY,
		TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.35),
		ZIndex = 51,
	}, f)
	UI.textStroke(t, 1.5)
	UI.pop(f, 0.5)
	task.delay(life or 3, function()
		if f.Parent then
			UI.tween(f, 0.3, { BackgroundTransparency = 1 })
			UI.tween(t, 0.3, { TextTransparency = 1 })
			local st = f:FindFirstChildOfClass("UIStroke")
			if st then
				UI.tween(st, 0.3, { Transparency = 1 })
			end
			task.wait(0.32)
			f:Destroy()
		end
	end)
	return f
end

-------------------------------------------------------------------------------
-- windows

export type Window = { frame: Frame, body: Frame, close: () -> (), title: TextLabel }

function UI.window(parent: Instance, title: string, size: UDim2, accent: Color3?, onClose: (() -> ())?): Window
	local acc = accent or UI.C.pink
	local f = UI.panel({
		Name = title,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 20,
	}, parent)
	local bar = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = acc, BorderSizePixel = 0, ZIndex = 21 }, f)
	UI.corner(bar, 16)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), BackgroundColor3 = acc, BorderSizePixel = 0, ZIndex = 21 }, bar)
	UI.gradient(bar, Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170), 90)
	local tl = UI.text({ Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(20, 0), Text = title, FontFace = UI.TITLE, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 }, bar)
	UI.textStroke(tl, 3, acc:Lerp(Color3.new(0, 0, 0), 0.6))
	local body = UI.new("Frame", { Name = "Body", Size = UDim2.new(1, -28, 1, -72), Position = UDim2.fromOffset(14, 64), BackgroundTransparency = 1, ZIndex = 21 }, f)
	local function close()
		UI.tween(UI.scale(f), 0.15, { Scale = 0.85 })
		task.delay(0.15, function()
			f.Visible = false
			UI.scale(f).Scale = 1
		end)
		if onClose then
			onClose()
		end
	end
	UI.button(bar, {
		text = "✕",
		size = UDim2.fromOffset(40, 40),
		position = UDim2.new(1, -48, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = UI.C.red,
		textSize = 22,
		z = 23,
		onClick = close,
	})
	-- drag by the title bar
	local dragging, start, origin = false, Vector2.zero, UDim2.new()
	bar.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			start = Vector2.new(io.Position.X, io.Position.Y)
			origin = f.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(io.Position.X, io.Position.Y) - start
			f.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	f.Visible = false
	return { frame = f, body = body, close = close, title = tl }
end

function UI.open(w: Window)
	w.frame.Visible = true
	UI.pop(w.frame, 0.85, 0.3)
end

-- tab strip: returns pages[name]
function UI.tabs(parent: Frame, names: { string }, accent: Color3?): { [string]: ScrollingFrame }
	local acc = accent or UI.C.cyan
	local strip = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 22 }, parent)
	UI.list(strip, true, 6)
	local pages: { [string]: ScrollingFrame } = {}
	local buttons: { [string]: TextButton } = {}
	local function select(name: string)
		for n, p in pages do
			p.Visible = n == name
			UI.setButton(buttons[n], nil, if n == name then acc else UI.C.bg2)
		end
	end
	for i, n in names do
		buttons[n] = UI.button(strip, {
			text = n,
			size = UDim2.fromOffset(math.max(96, #n * 13 + 30), 36),
			color = UI.C.bg2,
			textSize = 17,
			order = i,
			z = 23,
			onClick = function()
				select(n)
			end,
		})
		local page = UI.new("ScrollingFrame", {
			Name = n,
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.fromOffset(0, 50),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = acc,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
			ZIndex = 22,
		}, parent)
		UI.list(page, false, 8)
		UI.pad(page, 4)
		pages[n] = page
	end
	select(names[1])
	return pages
end

function UI.section(parent: Instance, title: string, order: number): Frame
	local f = UI.new("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = UI.C.bg2, BackgroundTransparency = 0.3, LayoutOrder = order, ZIndex = 22 }, parent)
	UI.corner(f, 12)
	UI.pad(f, 10)
	UI.list(f, false, 8)
	local t = UI.text({ Size = UDim2.new(1, 0, 0, 22), Text = title, FontFace = UI.HEAVY, TextSize = 18, TextColor3 = UI.C.gold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = -1, ZIndex = 23 }, f)
	UI.textStroke(t, 1.5)
	return f
end

function UI.row(parent: Instance, order: number?): Frame
	local r = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = order or 0, ZIndex = 22 }, parent)
	UI.list(r, true, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	return r
end

function UI.toggle(parent: Instance, label: string, value: boolean, onChange: (boolean) -> (), order: number?): Frame
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = order or 0, ZIndex = 22 }, parent)
	UI.text({ Size = UDim2.new(1, -80, 1, 0), Text = label, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 }, row)
	local track = UI.new("TextButton", { Size = UDim2.fromOffset(62, 32), Position = UDim2.new(1, -62, 0.5, -16), BackgroundColor3 = if value then UI.C.green else UI.C.bg2, Text = "", AutoButtonColor = false, ZIndex = 23 }, row)
	UI.round(track)
	UI.stroke(track, 2, UI.C.line, 0.3)
	local knob = UI.new("Frame", { Size = UDim2.fromOffset(26, 26), Position = if value then UDim2.new(1, -29, 0.5, -13) else UDim2.new(0, 3, 0.5, -13), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 24 }, track)
	UI.round(knob)
	local v = value
	track.Activated:Connect(function()
		v = not v
		UI.click()
		UI.tween(knob, 0.2, { Position = if v then UDim2.new(1, -29, 0.5, -13) else UDim2.new(0, 3, 0.5, -13) }, Enum.EasingStyle.Back)
		UI.tween(track, 0.2, { BackgroundColor3 = if v then UI.C.green else UI.C.bg2 })
		onChange(v)
	end)
	return row
end

function UI.slider(parent: Instance, label: string, min: number, max: number, value: number, onChange: (number) -> (), fmt: ((number) -> string)?, order: number?): Frame
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = order or 0, ZIndex = 22 }, parent)
	local lbl = UI.text({ Size = UDim2.new(1, 0, 0, 20), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 }, row)
	local track = UI.new("Frame", { Size = UDim2.new(1, -10, 0, 10), Position = UDim2.new(0, 5, 0, 32), BackgroundColor3 = UI.C.bg2, ZIndex = 23 }, row)
	UI.round(track)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.C.cyan, ZIndex = 24 }, track)
	UI.round(fill)
	local knob = UI.new("Frame", { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 25 }, track)
	UI.round(knob)
	UI.stroke(knob, 2, UI.C.cyan)
	local function set(v: number, fire: boolean)
		v = math.clamp(v, min, max)
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		lbl.Text = label .. ":  " .. (if fmt then fmt(v) else string.format("%.2f", v))
		if fire then
			onChange(v)
		end
	end
	set(value, false)
	local dragging = false
	local function fromX(x: number)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		set(min + (max - min) * a, true)
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(io.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			fromX(io.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return row
end

-------------------------------------------------------------------------------
-- misc

function UI.fmt(n: number): string
	local s = tostring(math.floor(n))
	local neg = string.sub(s, 1, 1) == "-"
	if neg then
		s = string.sub(s, 2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if neg then "-" else "") .. out
end

function UI.coin(parent: Instance, size: number, z: number?): Frame
	local c = UI.new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = UI.C.gold, ZIndex = z or 1 }, parent)
	UI.round(c)
	UI.stroke(c, math.max(1, size / 12), Color3.fromRGB(200, 140, 30))
	local inner = UI.new("Frame", { Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.19, 0.19), BackgroundColor3 = Color3.fromRGB(255, 230, 150), ZIndex = (z or 1) + 1 }, c)
	UI.round(inner)
	UI.text({ Size = UDim2.fromScale(1, 1), Text = "★", TextSize = size * 0.5, TextColor3 = Color3.fromRGB(210, 150, 30), FontFace = UI.HEAVY, ZIndex = (z or 1) + 2 }, inner)
	return c
end

function UI.thumb(userId: number, image: ImageLabel)
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and content and image.Parent then
			image.Image = content
		end
	end)
end

-- count a label up/down to a number
function UI.countTo(label: TextLabel, from: number, to: number, t: number, prefix: string?)
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - start) / t, 0, 1)
		a = 1 - (1 - a) ^ 3
		label.Text = (prefix or "") .. UI.fmt(from + (to - from) * a)
		if a >= 1 then
			conn:Disconnect()
		end
	end)
end

return UI
