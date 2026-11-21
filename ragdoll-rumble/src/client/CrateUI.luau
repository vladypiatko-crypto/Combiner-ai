--!strict
-- Crate roll cutscene: spinning crate -> name ticker that slows down -> rarity build-up
-- (flashes / shakes that escalate tier by tier for rare pulls) -> reveal card.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))

local UI = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Skins = require(script.Parent:WaitForChild("Skins"))
local Audio = require(script.Parent:WaitForChild("Audio"))

local CrateUI = {}

local gui: ScreenGui
local overlay: Frame
local flash: Frame
local stage: Frame
local ticker: TextLabel
local tickerSub: TextLabel
local tierText: TextLabel
local busy = false
local particles: { { f: Frame, v: Vector2, life: number, max: number } } = {}

function CrateUI.init(parent: Instance)
	gui = UI.new("ScreenGui", { Name = "RumbleCrates", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 40, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parent)
	overlay = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.C.dark, BackgroundTransparency = 1, ZIndex = 1 }, gui)
	flash = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 30 }, gui)
	stage = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, gui)
	ticker = UI.text({ Size = UDim2.new(1, 0, 0, 90), Position = UDim2.new(0, 0, 0.62, 0), FontFace = UI.TITLE, TextSize = 70, Text = "", ZIndex = 10 }, stage)
	UI.textStroke(ticker, 5)
	tickerSub = UI.text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0.62, 86), FontFace = UI.HEAVY, TextSize = 26, Text = "", ZIndex = 10 }, stage)
	UI.textStroke(tickerSub, 2.5)
	tierText = UI.text({ Size = UDim2.new(1, 0, 0, 140), Position = UDim2.new(0, 0, 0.18, 0), FontFace = UI.TITLE, TextSize = 120, Text = "", TextTransparency = 1, ZIndex = 12 }, stage)
	UI.textStroke(tierText, 7)
	RunService.RenderStepped:Connect(function(dt)
		for i = #particles, 1, -1 do
			local p = particles[i]
			p.life -= dt
			if p.life <= 0 or not p.f.Parent then
				p.f:Destroy()
				table.remove(particles, i)
				continue
			end
			p.v += Vector2.new(0, 600 * dt)
			local pos = p.f.Position
			p.f.Position = UDim2.new(pos.X.Scale, pos.X.Offset + p.v.X * dt, pos.Y.Scale, pos.Y.Offset + p.v.Y * dt)
			p.f.Rotation += p.v.X * dt
			p.f.BackgroundTransparency = 1 - p.life / p.max
		end
	end)
end

local function burst(color: Color3, n: number, z: number?)
	for _ = 1, n do
		local s = math.random(6, 14)
		local f = UI.new("Frame", {
			Size = UDim2.fromOffset(s, s),
			Position = UDim2.fromScale(0.5, 0.45),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if math.random() < 0.3 then Color3.new(1, 1, 1) else color,
			BorderSizePixel = 0,
			Rotation = math.random(0, 90),
			ZIndex = z or 15,
		}, stage)
		local a = math.random() * math.pi * 2
		local sp = math.random(250, 750)
		local life = 0.8 + math.random() * 0.8
		table.insert(particles, { f = f, v = Vector2.new(math.cos(a) * sp, math.sin(a) * sp - 300), life = life, max = life })
	end
end

local function doFlash(color: Color3, strength: number, t: number)
	if not Store.settings.flashing then
		strength *= 0.25
	end
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	UI.tween(flash, t, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

local function shake(amount: number, t: number)
	if not Store.settings.shake then
		return
	end
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < t do
			local k = 1 - (os.clock() - start) / t
			stage.Position = UDim2.fromOffset((math.random() - 0.5) * amount * k, (math.random() - 0.5) * amount * k)
			RunService.RenderStepped:Wait()
		end
		stage.Position = UDim2.fromOffset(0, 0)
	end)
end

-- 3D crate in a ViewportFrame (Blender mesh if available, else a chunky block)
local function crateView(kind: string): (ViewportFrame, () -> ())
	local vp = UI.new("ViewportFrame", {
		Size = UDim2.fromOffset(320, 320),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 160, 200),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
		ZIndex = 6,
	}, stage)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local model = Skins.clone(if kind == "finisher" then "crate_finisher" else "crate_spawn", CFrame.new(), 1)
	if not model then
		model = Instance.new("Model")
		local box = Instance.new("Part")
		box.Size = Vector3.new(3, 3, 3)
		box.Color = if kind == "finisher" then Color3.fromRGB(176, 40, 58) else Color3.fromRGB(30, 78, 140)
		box.Material = Enum.Material.WoodPlanks
		box.Parent = model
		local band = Instance.new("Part")
		band.Size = Vector3.new(3.1, 0.5, 3.1)
		band.Color = Color3.fromRGB(255, 201, 60)
		band.Material = Enum.Material.Neon
		band.Parent = model
		model.PrimaryPart = box
	end
	local m = model :: Model
	m.Parent = vp
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 2.2, 8.5), Vector3.zero)
	local spin = 0
	local shakeAmt = 0
	local alive = true
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not alive or not m.Parent then
			return
		end
		spin += dt * (1.2 + shakeAmt * 6)
		local j = shakeAmt * 0.25
		m:PivotTo(CFrame.Angles(0, spin, 0) * CFrame.Angles((math.random() - 0.5) * j, 0, (math.random() - 0.5) * j))
	end)
	local function setShake(v: number)
		shakeAmt = v
	end
	vp:SetAttribute("Shake", 0)
	vp.AttributeChanged:Connect(function(a)
		if a == "Shake" then
			setShake(vp:GetAttribute("Shake") :: number)
		end
	end)
	return vp, function()
		alive = false
		conn:Disconnect()
	end
end

local function blur(on: boolean)
	local b = Lighting:FindFirstChild("RumbleBlur") :: BlurEffect?
	if not b then
		local nb = Instance.new("BlurEffect")
		nb.Name = "RumbleBlur"
		nb.Size = 0
		nb.Parent = Lighting
		b = nb
	end
	UI.tween(b :: BlurEffect, 0.4, { Size = if on then 18 else 0 })
end

function CrateUI.busy(): boolean
	return busy
end

-- res = server roll result { item, new, refund, count }; onEquip(id) called by the EQUIP button
function CrateUI.play(kind: string, res: any, onEquip: (string) -> ())
	if busy then
		return
	end
	local item = Cosmetics.byId[res.item]
	if not item then
		return
	end
	busy = true
	local rarity = Cosmetics.rarity(item)
	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	UI.tween(overlay, 0.35, { BackgroundTransparency = 0.25 })
	blur(true)
	ticker.Text = ""
	tickerSub.Text = ""
	tierText.TextTransparency = 1
	stage.Position = UDim2.fromOffset(0, 0)

	local vp, stopView = crateView(kind)
	local glow = UI.new("Frame", { Size = UDim2.fromOffset(260, 260), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.C.gold, BackgroundTransparency = 0.8, ZIndex = 5 }, stage)
	UI.round(glow)
	UI.pop(vp, 0.4, 0.4)
	Audio.play("lob", 1, 0.8)

	-- 1) shake the crate
	vp:SetAttribute("Shake", 0.4)
	for i = 1, 6 do
		Audio.play("tick", 0.6, 0.7 + i * 0.08)
		UI.tween(glow, 0.12, { Size = UDim2.fromOffset(260 + i * 14, 260 + i * 14), BackgroundTransparency = 0.8 - i * 0.06 })
		task.wait(0.11)
	end

	-- 2) ticker
	local quick = Store.settings.quickRolls and item.rarity <= 2
	local pool = Cosmetics.ofKind(kind)
	local rollable = {}
	for _, it in pool do
		if it.chance > 0 then
			-- show common stuff more often, like real odds
			local w = math.max(1, math.floor(12 / math.sqrt(it.chance)))
			for _ = 1, w do
				table.insert(rollable, it)
			end
		end
	end
	local total = if quick then 0.5 else 2.0 + item.rarity * 0.25
	local start = os.clock()
	local interval = 0.045
	local shown = rollable[1]
	while os.clock() - start < total do
		shown = rollable[math.random(1, #rollable)]
		local r = Cosmetics.rarity(shown)
		ticker.Text = string.upper(shown.name)
		ticker.TextColor3 = r.color
		tickerSub.Text = r.name .. "  ·  " .. Cosmetics.formatChance(shown.chance)
		tickerSub.TextColor3 = r.color:Lerp(Color3.new(1, 1, 1), 0.4)
		UI.pop(ticker, 1.18, 0.12)
		overlay.BackgroundColor3 = r.color:Lerp(UI.C.dark, 0.85)
		Audio.play("tick", 0.5, 0.9 + (os.clock() - start) / total * 0.6)
		local k = (os.clock() - start) / total
		interval = 0.045 + k * k * 0.32
		vp:SetAttribute("Shake", 0.4 + k * 0.8)
		task.wait(interval)
	end
	ticker.Text = ""
	tickerSub.Text = ""

	-- 3) build-up for rare pulls: climb the tiers one by one
	if item.rarity >= 3 and not quick then
		for tier = 3, item.rarity do
			local r = Cosmetics.RARITIES[tier]
			tierText.Text = string.upper(r.name) .. string.rep("!", tier - 2)
			tierText.TextColor3 = r.color
			tierText.TextTransparency = 0
			UI.pop(tierText, 1.6, 0.3)
			doFlash(r.color, 0.55 + tier * 0.04, 0.45)
			shake(8 + tier * 5, 0.4)
			overlay.BackgroundColor3 = r.color:Lerp(UI.C.dark, 0.7)
			Audio.play("win", 0.8, 0.7 + tier * 0.12)
			vp:SetAttribute("Shake", 1.2 + tier * 0.3)
			burst(r.color, 10 + tier * 4, 14)
			task.wait(if tier == item.rarity then 0.7 else 0.42)
		end
		if item.rarity >= 6 then
			-- strobe
			for i = 1, (if Store.settings.flashing then 10 else 3) do
				doFlash(if i % 2 == 0 then Color3.new(1, 1, 1) else rarity.color, 0.7, 0.08)
				Audio.play("tick", 0.8, 1.6)
				task.wait(0.08)
			end
		end
		if item.rarity == 7 then
			local t0 = os.clock()
			while os.clock() - t0 < 1.2 do
				overlay.BackgroundColor3 = Color3.fromHSV((os.clock() * 1.5) % 1, 0.6, 0.35)
				tierText.TextColor3 = Color3.fromHSV((os.clock() * 1.5 + 0.5) % 1, 0.5, 1)
				burst(Color3.fromHSV(math.random(), 0.6, 1), 3, 14)
				task.wait(0.05)
			end
		elseif item.rarity == 8 then
			local glyphs = { "█", "▓", "▒", "░", "#", "@", "%", "0", "1" }
			local t0 = os.clock()
			Audio.play("deflect", 1, 0.5)
			while os.clock() - t0 < 1.4 do
				local s = ""
				for _ = 1, 10 do
					s ..= glyphs[math.random(1, #glyphs)]
				end
				tierText.Text = s
				tierText.TextColor3 = if math.random() < 0.5 then UI.C.green else Color3.new(1, 1, 1)
				overlay.BackgroundColor3 = if math.random() < 0.5 then Color3.new(0, 0, 0) else Color3.fromRGB(0, 40, 20)
				tierText.Position = UDim2.new(0, math.random(-30, 30), 0.18, math.random(-20, 20))
				if math.random() < 0.3 then
					Audio.play("tick", 0.7, math.random() * 2 + 0.5)
				end
				task.wait(0.05)
			end
			tierText.Position = UDim2.new(0, 0, 0.18, 0)
		end
		UI.tween(tierText, 0.25, { TextTransparency = 1 })
	end

	-- 4) the crate pops
	stopView()
	UI.tween(vp, 0.15, { Size = UDim2.fromOffset(420, 420) })
	doFlash(Color3.new(1, 1, 1), 0.9, 0.6)
	shake(14 + item.rarity * 3, 0.35)
	Audio.play(if item.rarity >= 5 then "boom" else "pickup", if item.rarity >= 5 then 0.6 else 1)
	burst(rarity.color, 30 + item.rarity * 8)
	task.wait(0.12)
	vp:Destroy()
	glow:Destroy()

	-- 5) reveal card
	overlay.BackgroundColor3 = rarity.color:Lerp(UI.C.dark, 0.82)
	local holder = UI.new("Frame", { Size = UDim2.fromOffset(460, 360), Position = UDim2.fromScale(0.5, 0.46), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 16 }, stage)
	UI.rays(holder, rarity.color, 14 + item.rarity * 2, 16)
	local card = UI.panel({ Size = UDim2.fromScale(1, 1), ZIndex = 17 }, holder)
	local st = card:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = rarity.color
		st.Thickness = 4
		st.Transparency = 0
	end
	local band = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = rarity.color, ZIndex = 18 }, card)
	UI.corner(band, 16)
	local rl = UI.text({ Size = UDim2.fromScale(1, 1), Text = string.upper(rarity.name) .. "  ·  " .. Cosmetics.formatChance(item.chance), FontFace = UI.TITLE, TextSize = 26, ZIndex = 19 }, band)
	UI.textStroke(rl, 2.5, rarity.color:Lerp(Color3.new(0, 0, 0), 0.6))
	if item.rarity >= 5 then
		UI.shimmer(band, { rarity.color, Color3.new(1, 1, 1), rarity.color }, 0.8)
	end
	UI.text({ Size = UDim2.new(1, 0, 0, 100), Position = UDim2.fromOffset(0, 54), Text = item.icon, TextSize = 84, FontFace = UI.BODY, ZIndex = 18 }, card)
	local nm = UI.text({ Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 156), Text = string.upper(item.name), FontFace = UI.TITLE, TextSize = 46, TextColor3 = rarity.color:Lerp(Color3.new(1, 1, 1), 0.25), ZIndex = 18 }, card)
	UI.textStroke(nm, 3)
	if item.rarity >= 6 then
		UI.shimmer(nm, { rarity.color, Color3.new(1, 1, 1), rarity.glow, rarity.color }, 1.2)
	end
	local sub = Cosmetics.KIND_NAMES[kind] .. "  ·  " .. item.desc
	UI.text({ Size = UDim2.new(1, -30, 0, 40), Position = UDim2.fromOffset(15, 206), Text = sub, TextWrapped = true, TextSize = 17, TextColor3 = UI.C.dim, FontFace = UI.BODY, ZIndex = 18 }, card)
	local note = if res.new then "✨ NEW!" elseif (res.refund or 0) > 0 then string.format("Duplicate · +%d coins back", res.refund) else string.format("You own %d", res.count or 1)
	local nt = UI.text({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 250), Text = note, TextSize = 20, FontFace = UI.HEAVY, TextColor3 = if res.new then UI.C.gold else UI.C.text, ZIndex = 18 }, card)
	UI.textStroke(nt, 1.5)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		UI.tween(overlay, 0.3, { BackgroundTransparency = 1 })
		UI.tween(UI.scale(holder), 0.2, { Scale = 0.6 })
		blur(false)
		task.wait(0.3)
		holder:Destroy()
		gui.Enabled = false
		busy = false
	end
	local row = UI.new("Frame", { Size = UDim2.new(1, -30, 0, 54), Position = UDim2.new(0, 15, 1, -66), BackgroundTransparency = 1, ZIndex = 18 }, card)
	UI.list(row, true, 12, Enum.HorizontalAlignment.Center)
	UI.button(row, {
		text = "EQUIP",
		size = UDim2.fromOffset(180, 50),
		color = UI.C.green,
		z = 19,
		onClick = function()
			onEquip(item.id)
			close()
		end,
	})
	UI.button(row, { text = "NICE", size = UDim2.fromOffset(180, 50), color = rarity.color, z = 19, onClick = close })
	UI.pop(holder, 0.3, 0.5)
	burst(rarity.color, 20 + item.rarity * 6)
	if item.rarity >= 5 then
		Audio.play("win", 1, 1.3)
	end
	-- safety: auto close after a while
	task.delay(25, close)
end

return CrateUI
