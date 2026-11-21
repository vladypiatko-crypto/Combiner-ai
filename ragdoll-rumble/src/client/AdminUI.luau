--!strict
-- Admin panel (the server re-checks permissions for every action).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Maps = require(Shared:WaitForChild("Maps"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Skins = require(script.Parent:WaitForChild("Skins"))

local AdminUI = {}

local win: UI.Window? = nil
local pages: { [string]: ScrollingFrame } = {}
local playerList: Frame? = nil
local logBox: TextLabel? = nil
local status: TextLabel? = nil

local function act(action: string, args: any?): any
	local ok, res = pcall(function()
		return Remotes.Request:InvokeServer("admin", { action = action, args = args })
	end)
	if not ok or type(res) ~= "table" then
		UI.toast("admin request failed", UI.C.red)
		return nil
	end
	if res.msg then
		UI.toast(res.msg, if res.ok then UI.C.green else UI.C.red)
	end
	return res
end

local function btn(parent: Instance, text: string, color: Color3?, fn: () -> (), width: number?)
	return UI.button(parent, { text = text, size = UDim2.fromOffset(width or 150, 38), color = color or UI.C.bg2, textSize = 16, font = UI.HEAVY, z = 23, onClick = fn })
end

local function refreshPlayers()
	local pl = playerList
	if not pl then
		return
	end
	for _, c in pl:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local res = act("state")
	if not res or not res.data then
		return
	end
	if status then
		local d = res.data
		status.Text = string.format("phase: %s  ·  bots: %s (fill to %d, x%.1f%s)  ·  saving: %s  ·  3D models: %s",
			tostring(d.phase), if d.botsEnabled then "on" else "off", d.target, d.difficulty, if d.passive then ", passive" else "",
			if d.saving then "on" else "off", if Skins.ok then "mesh" elseif Skins.ok == false then "fallback (" .. tostring(Skins.err) .. ")" else "loading")
	end
	for i, p in res.data.players do
		local row = UI.new("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = UI.C.bg2, BackgroundTransparency = 0.3, LayoutOrder = 10 + i, ZIndex = 22 }, pl)
		UI.corner(row, 10)
		UI.pad(row, 3, 8)
		UI.list(row, true, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
		UI.text({ Size = UDim2.fromOffset(170, 38), Text = p.name .. "  (" .. p.zone .. ")", TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 23 }, row)
		local uid = p.userId
		btn(row, "Heal", UI.C.green, function()
			act("player.heal", { userId = uid })
		end, 70)
		btn(row, "KO", UI.C.red, function()
			act("player.kill", { userId = uid })
		end, 60)
		btn(row, if p.god then "God: ON" else "God: off", if p.god then UI.C.gold else UI.C.bg2, function()
			act("player.god", { userId = uid, on = not p.god })
			refreshPlayers()
		end, 100)
		btn(row, "Flop", UI.C.cyan, function()
			act("player.ragdoll", { userId = uid })
		end, 70)
		btn(row, "+1000 ★", UI.C.gold, function()
			act("player.coins", { userId = uid, amount = 1000 })
		end, 100)
	end
end

local function refreshLogs()
	local res = act("logs")
	local lb = logBox
	if not res or not lb then
		return
	end
	local lines = {}
	for i = #res.data, math.max(1, #res.data - 25), -1 do
		local l = res.data[i]
		table.insert(lines, string.format("<font color='%s'>[%s]</font> %s", if l.kind == "error" then "#ff5a6e" else "#ffd36e", l.kind, (l.msg:gsub("<", "&lt;"))))
	end
	lb.Text = if #lines > 0 then table.concat(lines, "\n") else "no server errors or warnings 🎉"
end

function AdminUI.init(parent: Instance)
	local w = UI.window(parent, "ADMIN PANEL", UDim2.fromOffset(760, 560), Color3.fromRGB(255, 143, 60))
	win = w
	pages = UI.tabs(w.body, { "Match", "Bots", "Players", "Weapons", "Crates", "Debug" }, Color3.fromRGB(255, 143, 60))

	-- match
	local m = pages.Match
	local s1 = UI.section(m, "Flow", 1)
	local r1 = UI.row(s1, 1)
	btn(r1, "Start match now", UI.C.green, function()
		act("match.start")
	end, 170)
	btn(r1, "Skip round", UI.C.cyan, function()
		act("round.skip")
	end)
	btn(r1, "End match", UI.C.red, function()
		act("match.end")
	end)
	btn(r1, "Sudden death", Color3.fromRGB(255, 70, 120), function()
		act("suddendeath")
	end)
	local r2 = UI.row(s1, 2)
	btn(r2, "Lobby timer 5s", UI.C.bg2, function()
		act("intermission", { seconds = 5 })
	end, 160)
	btn(r2, "Lobby timer 60s", UI.C.bg2, function()
		act("intermission", { seconds = 60 })
	end, 160)
	local s2 = UI.section(m, "Next map", 2)
	local grid = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, s2)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 40), CellPadding = UDim2.fromOffset(6, 6) }, grid)
	for i, map in Maps.list do
		btn(grid, map.name, UI.C.bg2, function()
			act("round.map", { map = i })
		end)
	end

	-- bots
	local b = pages.Bots
	local sb = UI.section(b, "Bots in matches", 1)
	UI.toggle(sb, "Bots enabled", true, function(v)
		act("bots.enabled", { on = v })
	end, 1)
	UI.toggle(sb, "Passive bots (they won't attack)", false, function(v)
		act("bots.passive", { on = v })
	end, 2)
	UI.slider(sb, "Fill matches up to", 1, 8, 4, function(v)
		act("bots.target", { count = math.floor(v + 0.5) })
	end, function(v)
		return tostring(math.floor(v + 0.5)) .. " fighters"
	end, 3)
	UI.slider(sb, "Difficulty", 0.2, 1.6, 1, function(v)
		act("bots.difficulty", { value = v })
	end, function(v)
		return string.format("x%.1f", v)
	end, 4)
	local sb2 = UI.section(b, "Testing", 2)
	local rb = UI.row(sb2, 1)
	btn(rb, "Spawn sparring bot near me", UI.C.pink, function()
		act("bots.spawn")
	end, 260)

	-- players
	local p = pages.Players
	local sp = UI.section(p, "Players", 1)
	status = UI.text({ Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextSize = 14, TextColor3 = UI.C.dim, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 23 }, sp)
	btn(sp, "Refresh", UI.C.cyan, refreshPlayers, 120).LayoutOrder = 2
	playerList = sp

	-- weapons
	local wp = pages.Weapons
	local sw = UI.section(wp, "Give yourself a weapon", 1)
	local wg = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 100), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, sw)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(165, 40), CellPadding = UDim2.fromOffset(6, 6) }, wg)
	for _, wpn in Weapons.list do
		btn(wg, wpn.name, UI.C.bg2, function()
			act("player.weapon", { wid = wpn.id, userId = Players.LocalPlayer.UserId })
		end)
	end
	local sw2 = UI.section(wp, "Drop one from the sky", 2)
	local wg2 = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 100), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, sw2)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(165, 40), CellPadding = UDim2.fromOffset(6, 6) }, wg2)
	for _, wpn in Weapons.list do
		btn(wg2, wpn.name, UI.C.bg2, function()
			act("weapon.drop", { wid = wpn.id })
		end)
	end

	-- crates
	local c = pages.Crates
	local sc = UI.section(c, "Force your next roll (watch the animations)", 1)
	local cg = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 22 }, sc)
	UI.new("UIGridLayout", { CellSize = UDim2.fromOffset(165, 40), CellPadding = UDim2.fromOffset(6, 6) }, cg)
	for _, r in Cosmetics.RARITIES do
		btn(cg, r.name, r.color, function()
			act("crate.force", { rarity = r.id })
		end)
	end
	local sc2 = UI.section(c, "Economy", 2)
	UI.toggle(sc2, "Free rolls", false, function(v)
		act("crate.free", { on = v })
	end, 1)
	UI.slider(sc2, "Luck", 1, 1000, 1, function(v)
		act("crate.luck", { value = math.floor(v) })
	end, function(v)
		return string.format("x%d", math.floor(v))
	end, 2)
	local rc = UI.row(sc2, 3)
	btn(rc, "+10,000 coins", UI.C.gold, function()
		act("player.coins", { amount = 10000 })
	end, 170)
	btn(rc, "Reset my data", UI.C.red, function()
		act("data.reset")
	end, 170)

	-- debug
	local d = pages.Debug
	local sd = UI.section(d, "Server errors + warnings", 1)
	btn(sd, "Refresh", UI.C.cyan, refreshLogs, 120).LayoutOrder = 1
	logBox = UI.text({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Font.fromEnum(Enum.Font.Code), TextSize = 13, Text = "", LayoutOrder = 2, ZIndex = 23 }, sd)

	UserInputService.InputBegan:Connect(function(io, gpe)
		if not gpe and (io.KeyCode == Enum.KeyCode.F2 or io.KeyCode == Enum.KeyCode.Backquote) and Store.isAdmin then
			AdminUI.toggle()
		end
	end)
end

function AdminUI.toggle()
	local w = win
	if not w then
		return
	end
	if w.frame.Visible then
		w.close()
	else
		UI.open(w)
		refreshPlayers()
		refreshLogs()
	end
end

return AdminUI
