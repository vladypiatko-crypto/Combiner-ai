--!strict
-- Lobby / meta UI: profile chip, phase pill, dock, ready button, crates, locker, settings.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Maps = require(Shared:WaitForChild("Maps"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Skins = require(script.Parent:WaitForChild("Skins"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local CrateUI = require(script.Parent:WaitForChild("CrateUI"))

local Menu = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local coinLabel: TextLabel
local coinShown = 0
local saveChip: TextLabel
local pill: Frame
local pillTitle: TextLabel
local pillSub: TextLabel
local pillBar: Frame
local dock: Frame
local readyBtn: TextButton
local adminBtn: TextButton
local windows: { [string]: UI.Window } = {}
local lockerPages: { [string]: ScrollingFrame } = {}
local oddsLists: { [string]: Frame } = {}
local rollButtons: { [string]: TextButton } = {}
local fpsLabel: TextLabel

Menu.onPreview = function(_id: string) end
Menu.onAdmin = function() end

local function request(kind: string, args: any): any
	local ok, res = pcall(function()
		return Remotes.Request:InvokeServer(kind, args)
	end)
	if not ok then
		return { ok = false, msg = "request failed" }
	end
	return res
end
Menu.request = request

-------------------------------------------------------------------------------
-- build

local function buildChip()
	local chip = UI.panel({ Size = UDim2.fromOffset(300, 74), Position = UDim2.fromOffset(16, 62) }, gui)
	local face = UI.new("ImageLabel", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = UI.C.bg2, ZIndex = 2 }, chip)
	UI.round(face)
	UI.stroke(face, 2, UI.C.pink)
	UI.thumb(player.UserId, face)
	local nm = UI.text({ Size = UDim2.new(1, -80, 0, 26), Position = UDim2.fromOffset(74, 8), Text = player.DisplayName, FontFace = UI.HEAVY, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 }, chip)
	UI.textStroke(nm, 1.5)
	UI.coin(chip, 24, 2).Position = UDim2.fromOffset(74, 40)
	coinLabel = UI.text({ Size = UDim2.new(0, 140, 0, 26), Position = UDim2.fromOffset(104, 39), Text = "0", FontFace = UI.TITLE, TextSize = 24, TextColor3 = UI.C.gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 }, chip)
	UI.textStroke(coinLabel, 2)
	saveChip = UI.text({ Size = UDim2.fromOffset(300, 18), Position = UDim2.new(0, 0, 1, 6), Text = "", FontFace = UI.BOLD, TextSize = 13, TextColor3 = UI.C.dim, TextXAlignment = Enum.TextXAlignment.Left }, chip)
	fpsLabel = UI.text({ Size = UDim2.fromOffset(120, 18), Position = UDim2.new(0, 0, 1, 24), Text = "", FontFace = UI.BOLD, TextSize = 13, TextColor3 = UI.C.green, TextXAlignment = Enum.TextXAlignment.Left, Visible = false }, chip)
end

local function buildPill()
	pill = UI.panel({ Size = UDim2.fromOffset(380, 70), Position = UDim2.new(0.5, 0, 0, 58), AnchorPoint = Vector2.new(0.5, 0) }, gui)
	pillTitle = UI.text({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 6), FontFace = UI.TITLE, TextSize = 30, Text = "THE ARCADE", ZIndex = 2 }, pill)
	UI.textStroke(pillTitle, 2.5)
	pillSub = UI.text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 40), FontFace = UI.BOLD, TextSize = 15, TextColor3 = UI.C.dim, Text = "", ZIndex = 2 }, pill)
	local track = UI.new("Frame", { Size = UDim2.new(1, -24, 0, 5), Position = UDim2.new(0, 12, 1, -9), BackgroundColor3 = UI.C.bg2, ZIndex = 2 }, pill)
	UI.round(track)
	pillBar = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.C.pink, ZIndex = 3 }, track)
	UI.round(pillBar)
	UI.gradient(pillBar, UI.C.pink, UI.C.cyan, 0)
end

local function openOnly(name: string)
	for n, w in windows do
		if n ~= name and w.frame.Visible then
			w.close()
		end
	end
	local w = windows[name]
	if w then
		if w.frame.Visible then
			w.close()
		else
			UI.open(w)
			Store.emit("panelOpened", name)
		end
	end
end
Menu.open = openOnly

local function buildDock()
	dock = UI.new("Frame", { Size = UDim2.fromOffset(170, 330), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, gui)
	UI.list(dock, false, 12, Enum.HorizontalAlignment.Right)
	UI.button(dock, { text = "CRATES", icon = "🎲", size = UDim2.fromOffset(170, 56), color = UI.C.pink, order = 1, onClick = function()
		openOnly("crates")
	end })
	UI.button(dock, { text = "LOCKER", icon = "🎒", size = UDim2.fromOffset(170, 56), color = UI.C.cyan, order = 2, onClick = function()
		openOnly("locker")
	end })
	UI.button(dock, { text = "SETTINGS", icon = "⚙️", size = UDim2.fromOffset(170, 56), color = Color3.fromRGB(120, 112, 170), order = 3, onClick = function()
		openOnly("settings")
	end })
	adminBtn = UI.button(dock, { text = "ADMIN", icon = "🛠️", size = UDim2.fromOffset(170, 56), color = Color3.fromRGB(255, 143, 60), order = 4, onClick = function()
		Menu.onAdmin()
	end })
	adminBtn.Visible = false
	readyBtn = UI.button(gui, {
		text = "READY UP",
		icon = "⚔️",
		size = UDim2.fromOffset(260, 66),
		position = UDim2.new(0.5, 0, 1, -28),
		anchor = Vector2.new(0.5, 1),
		color = UI.C.green,
		textSize = 30,
		onClick = function()
			Store.ready = not Store.ready
			request("ready", { on = Store.ready })
			UI.setButton(readyBtn, if Store.ready then "✓  READY!" else "⚔️  READY UP", if Store.ready then UI.C.gold else UI.C.green)
		end,
	})
end

-- crates window ---------------------------------------------------------------------
local function crateCard(parent: Instance, kind: string, order: number)
	local isFin = kind == "finisher"
	local col = if isFin then UI.C.pink else UI.C.cyan
	local card = UI.new("Frame", { Size = UDim2.new(0.5, -8, 1, 0), BackgroundColor3 = UI.C.bg2, BackgroundTransparency = 0.25, LayoutOrder = order, ZIndex = 22 }, parent)
	UI.corner(card, 14)
	UI.stroke(card, 2, col, 0.2)
	local t = UI.text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 8), Text = if isFin then "FINISHER CRATE" else "ENTRANCE CRATE", FontFace = UI.TITLE, TextSize = 28, TextColor3 = col, ZIndex = 23 }, card)
	UI.textStroke(t, 2)
	UI.text({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 40), Text = if isFin then "plays when YOU knock someone out" else "plays when you spawn into a round", FontFace = UI.BODY, TextSize = 15, TextColor3 = UI.C.dim, ZIndex = 23 }, card)
	local vp = UI.new("ViewportFrame", { Size = UDim2.new(1, 0, 0, 150), Position = UDim2.fromOffset(0, 60), BackgroundTransparency = 1, Ambient = Color3.fromRGB(170, 160, 200), LightDirection = Vector3.new(-1, -1, -1), ZIndex = 23 }, card)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 2, 8.5), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	local function fill()
		vp:ClearAllChildren()
		cam.Parent = vp
		local m = Skins.clone(if isFin then "crate_finisher" else "crate_spawn", CFrame.new(), 1)
		if not m then
			m = Instance.new("Model")
			local b = Instance.new("Part")
			b.Size = Vector3.new(3, 3, 3)
			b.Color = if isFin then Color3.fromRGB(176, 40, 58) else Color3.fromRGB(30, 78, 140)
			b.Material = Enum.Material.WoodPlanks
			b.Parent = m
		end
		(m :: Model).Parent = vp
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if not (m :: Model).Parent then
				conn:Disconnect()
				return
			end
			(m :: Model):PivotTo(CFrame.Angles(0.25, os.clock() * 0.8, 0))
		end)
	end
	fill()
	Store.on("skinsReady", fill)
	rollButtons[kind] = UI.button(card, {
		text = "ROLL  ·  " .. Config.CRATE_COST .. " ★",
		size = UDim2.new(1, -24, 0, 54),
		position = UDim2.new(0, 12, 0, 214),
		color = col,
		textSize = 24,
		z = 24,
		onClick = function()
			if CrateUI.busy() then
				return
			end
			local res = request("roll", { kind = kind })
			if res and res.ok then
				windows.crates.close()
				CrateUI.play(kind, res, function(id)
					local r = request("equip", { id = id })
					if r and r.ok then
						UI.toast("Equipped " .. Cosmetics.byId[id].name, UI.C.green)
					end
				end)
			else
				UI.toast(if res then res.msg or "can't roll" else "can't roll", UI.C.red)
				Audio.play("block")
			end
		end,
	})
	local odds = UI.new("ScrollingFrame", { Size = UDim2.new(1, -16, 1, -284), Position = UDim2.fromOffset(8, 278), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 23 }, card)
	UI.list(odds, false, 4)
	oddsLists[kind] = odds
end

local function refreshOdds()
	local prof = Store.profile
	for kind, list in oddsLists do
		list:ClearAllChildren()
		UI.list(list, false, 4)
		for i, it in Cosmetics.ofKind(kind) do
			if it.chance <= 0 then
				continue
			end
			local r = Cosmetics.rarity(it)
			local owned = if prof and prof.inventory then prof.inventory[it.id] or 0 else 0
			local row = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 26), BackgroundColor3 = r.color, BackgroundTransparency = 0.82, LayoutOrder = i, ZIndex = 24 }, list)
			UI.corner(row, 8)
			UI.text({ Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(8, 0), Text = it.icon .. "  " .. (if owned > 0 or it.rarity <= 3 then it.name else "???"), FontFace = UI.BOLD, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = r.color:Lerp(Color3.new(1, 1, 1), 0.3), ZIndex = 25 }, row)
			UI.text({ Size = UDim2.new(0.4, -10, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), Text = Cosmetics.formatChance(it.chance) .. (if owned > 0 then "  ×" .. owned else ""), FontFace = UI.BOLD, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.C.dim, ZIndex = 25 }, row)
		end
	end
	for kind, b in rollButtons do
		local free = prof and prof.freeRolls
		UI.setButton(b, if free then "ROLL  ·  FREE" else "ROLL  ·  " .. Config.CRATE_COST .. " ★", nil)
		local _ = kind
	end
end

local function buildCrates()
	local w = UI.window(gui, "CRATES", UDim2.fromOffset(760, 560), UI.C.pink)
	windows.crates = w
	local row = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, w.body)
	UI.list(row, true, 16)
	crateCard(row, "finisher", 1)
	crateCard(row, "spawn", 2)
end

-- locker window ---------------------------------------------------------------------
local function refreshLocker()
	local prof = Store.profile
	for kind, page in lockerPages do
		for _, c in page:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local grid = page:FindFirstChildOfClass("UIListLayout")
		if grid then
			grid:Destroy()
		end
		if not page:FindFirstChildOfClass("UIGridLayout") then
			UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 176), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		end
		for i, it in Cosmetics.ofKind(kind) do
			local r = Cosmetics.rarity(it)
			local owned = if prof and prof.inventory then prof.inventory[it.id] or 0 else (if it.chance == 0 then 1 else 0)
			local equipped = prof and prof.equipped and prof.equipped[kind] == it.id
			local card = UI.new("TextButton", { BackgroundColor3 = if owned > 0 then UI.C.bg2 else UI.C.dark, Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 23 }, page)
			UI.corner(card, 12)
			UI.stroke(card, if equipped then 4 else 2, if equipped then UI.C.green else r.color, if owned > 0 then 0 else 0.6)
			UI.text({ Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 8), Text = if owned > 0 then it.icon else "❔", TextSize = 46, FontFace = UI.BODY, ZIndex = 24 }, card)
			local nm = UI.text({ Size = UDim2.new(1, -10, 0, 40), Position = UDim2.fromOffset(5, 74), Text = if owned > 0 then it.name else "???", TextWrapped = true, FontFace = UI.HEAVY, TextSize = 16, TextColor3 = r.color:Lerp(Color3.new(1, 1, 1), 0.3), ZIndex = 24 }, card)
			UI.textStroke(nm, 1.5)
			UI.text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 114), Text = r.name .. " · " .. Cosmetics.formatChance(it.chance), FontFace = UI.BOLD, TextSize = 12, TextColor3 = r.color, ZIndex = 24 }, card)
			local status = if equipped then "EQUIPPED" elseif owned > 0 then "×" .. owned else "LOCKED"
			UI.text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 140), Text = status, FontFace = UI.TITLE, TextSize = 18, TextColor3 = if equipped then UI.C.green else UI.C.dim, ZIndex = 24 }, card)
			if it.rarity >= 5 and owned > 0 then
				UI.shimmer(nm, { r.color, Color3.new(1, 1, 1), r.color }, 0.7)
			end
			card.Activated:Connect(function()
				if owned <= 0 then
					UI.toast("Roll crates to unlock " .. Cosmetics.formatChance(it.chance) .. " items!", r.color)
					return
				end
				UI.click()
				Menu.onPreview(it.id)
				if not equipped then
					local res = request("equip", { id = it.id })
					if res and res.ok then
						UI.toast("Equipped " .. it.name, UI.C.green)
					else
						UI.toast(if res then res.msg or "can't equip" else "can't equip", UI.C.red)
					end
				end
			end)
		end
	end
end

local function buildLocker()
	local w = UI.window(gui, "LOCKER", UDim2.fromOffset(720, 540), UI.C.cyan)
	windows.locker = w
	local pages = UI.tabs(w.body, { "Finishers", "Entrances" }, UI.C.cyan)
	lockerPages.finisher = pages.Finishers
	lockerPages.spawn = pages.Entrances
	UI.text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -18), Text = "click an item to equip it + preview it on your fighter", FontFace = UI.BODY, TextSize = 14, TextColor3 = UI.C.dim, ZIndex = 22 }, w.body)
end

-- settings ---------------------------------------------------------------------------
local function buildSettings()
	local w = UI.window(gui, "SETTINGS", UDim2.fromOffset(480, 470), Color3.fromRGB(120, 112, 170))
	windows.settings = w
	local list = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, w.body)
	UI.list(list, false, 6)
	local s = Store.settings
	UI.slider(list, "Sound volume", 0, 1.5, s.sfx, function(v)
		s.sfx = v
		Audio.volume = v
	end, function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end, 1)
	UI.toggle(list, "Screen shake", s.shake, function(v)
		s.shake = v
	end, 2)
	UI.toggle(list, "Damage numbers", s.numbers, function(v)
		s.numbers = v
	end, 3)
	UI.toggle(list, "Flashing effects (crate reveals)", s.flashing, function(v)
		s.flashing = v
	end, 4)
	UI.toggle(list, "Quick rolls for Common / Uncommon", s.quickRolls, function(v)
		s.quickRolls = v
	end, 5)
	UI.toggle(list, "Show FPS", s.fps, function(v)
		s.fps = v
		fpsLabel.Visible = v
	end, 6)
	UI.text({ Size = UDim2.new(1, 0, 0, 40), Text = "Tip: press H in a match for the controls", FontFace = UI.BODY, TextSize = 14, TextColor3 = UI.C.dim, LayoutOrder = 7, ZIndex = 22 }, list)
end

-------------------------------------------------------------------------------

function Menu.init(parent: Instance)
	gui = UI.new("ScreenGui", { Name = "RumbleMenu", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parent)
	UI.toasts(gui)
	buildChip()
	buildPill()
	buildDock()
	buildCrates()
	buildLocker()
	buildSettings()
	Store.on("profile", function()
		refreshOdds()
		refreshLocker()
	end)
	Store.on("admin", function(isAdmin: boolean)
		adminBtn.Visible = isAdmin
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		local panel = prompt:GetAttribute("Panel")
		if type(panel) == "string" and windows[panel] then
			openOnly(panel)
		end
	end)
	UserInputService.InputBegan:Connect(function(io, gpe)
		if gpe then
			return
		end
		if io.KeyCode == Enum.KeyCode.Escape then
			for _, w in windows do
				if w.frame.Visible then
					w.close()
				end
			end
		end
	end)
	refreshOdds()
	refreshLocker()
end

function Menu.setProfile(p: any)
	if not p then
		return
	end
	local old = Store.profile
	Store.profile = p
	if old and old.coins ~= p.coins then
		UI.countTo(coinLabel, old.coins, p.coins, 0.6)
		UI.pop(coinLabel, 1.3, 0.3)
	else
		coinLabel.Text = UI.fmt(p.coins)
	end
	coinShown = p.coins
	saveChip.Text = if p.saving then "" else "⚠ progress isn't saving (Studio: enable API services)"
	Store.emit("profile", p)
end

function Menu.coinPopup(amount: number, reason: string)
	local t = UI.text({
		Size = UDim2.fromOffset(240, 28),
		Position = UDim2.fromOffset(104, 132),
		Text = string.format("+%d  %s", amount, reason),
		FontFace = UI.TITLE,
		TextSize = 22,
		TextColor3 = UI.C.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, gui)
	UI.textStroke(t, 2)
	UI.pop(t, 0.5)
	UI.tween(t, 1.4, { Position = UDim2.fromOffset(104, 104), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.6)
	task.delay(2.1, function()
		t:Destroy()
	end)
	Audio.play("pickup", 0.6, 1.4)
end

local fpsAcc, fpsFrames = 0, 0

function Menu.update(dt: number, inLobby: boolean)
	local phase = workspace:GetAttribute("Phase") or "lobby"
	local t = workspace:GetServerTimeNow()
	dock.Visible = inLobby
	readyBtn.Visible = inLobby and phase == "lobby"
	if phase ~= "lobby" and Store.ready then
		Store.ready = false
		UI.setButton(readyBtn, "⚔️  READY UP", UI.C.green)
	end
	if phase == "lobby" then
		local pe = workspace:GetAttribute("PhaseEnd") or 0
		local hc = workspace:GetAttribute("HumanCount") or 0
		local rc = workspace:GetAttribute("ReadyCount") or 0
		if pe > 0 then
			local left = math.max(0, pe - t)
			pillTitle.Text = string.format("MATCH IN %d:%02d", math.floor(left / 60), math.floor(left % 60))
			pillBar.Size = UDim2.fromScale(math.clamp(1 - left / Config.INTERMISSION, 0, 1), 1)
		else
			pillTitle.Text = "THE ARCADE"
			pillBar.Size = UDim2.fromScale(0, 1)
		end
		pillSub.Text = string.format("%d/%d ready  ·  stand in the portal or hit READY", rc, hc)
	elseif phase == "match" then
		local mi = workspace:GetAttribute("MapIndex") or 0
		local map = if mi > 0 then Maps.get(mi) else nil
		pillTitle.Text = if map then "ROUND " .. tostring(workspace:GetAttribute("Round") or 1) else "MATCH"
		pillSub.Text = if map then map.name .. "  ·  first to " .. Config.WINS_TO_MATCH else ""
		local ink = workspace:GetAttribute("InkStart") or 0
		local ft = workspace:GetAttribute("FightTime") or 0
		if ink > 0 then
			pillBar.Size = UDim2.fromScale(1, 1)
			pillSub.Text = "SUDDEN DEATH · the ink is rising!"
		elseif ft > 0 and t > ft then
			pillBar.Size = UDim2.fromScale(math.clamp((t - ft) / Config.SUDDEN_DEATH_AT, 0, 1), 1)
		else
			pillBar.Size = UDim2.fromScale(0, 1)
		end
	elseif phase == "results" then
		pillTitle.Text = "RESULTS"
		local pe = workspace:GetAttribute("PhaseEnd") or 0
		pillSub.Text = string.format("back to the lobby in %d", math.max(0, math.ceil(pe - t)))
	end
	if Store.settings.fps then
		fpsAcc += dt
		fpsFrames += 1
		if fpsAcc >= 0.5 then
			fpsLabel.Text = string.format("%d FPS", math.floor(fpsFrames / fpsAcc + 0.5))
			fpsAcc, fpsFrames = 0, 0
		end
	end
	local _ = coinShown
end

function Menu.gui(): ScreenGui
	return gui
end

return Menu
