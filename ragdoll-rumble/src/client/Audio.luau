--!strict
-- Custom sound design: every effect is a recipe of layered sources (sounds that ship with
-- the Roblox client, so they always load) run through effect chains (distortion, EQ,
-- reverb, echo). Swap any `id` for your own "rbxassetid://123" to re-skin a sound.

local SoundService = game:GetService("SoundService")

local Audio = {}

type Fx = { dist: number?, low: number?, mid: number?, high: number?, reverb: number?, echo: number? }
type Layer = { id: string, vol: number, pitch: number, var: number?, fx: Fx? }

local S = {
	collide = "rbxasset://sounds/collide.wav",
	lunge = "rbxasset://sounds/swordlunge.wav",
	slash = "rbxasset://sounds/swordslash.wav",
	unsheath = "rbxasset://sounds/unsheath.wav",
	paint = "rbxasset://sounds/paintball.wav",
	rocket = "rbxasset://sounds/Rocket shot.wav",
	whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/clickfast.wav",
	jump = "rbxasset://sounds/action_jump.mp3",
	land = "rbxasset://sounds/action_jump_land.mp3",
	glass = "rbxasset://sounds/glassbreak.wav",
}

local RECIPES: { [string]: { Layer } } = {
	whoosh = { { id = S.lunge, vol = 0.32, pitch = 1.8, var = 0.15, fx = { high = -6 } } },
	punch = {
		{ id = S.collide, vol = 1.0, pitch = 1.1, var = 0.18, fx = { dist = 0.35, low = 6 } },
		{ id = S.land, vol = 0.55, pitch = 1.6, var = 0.1 },
	},
	heavy = {
		{ id = S.collide, vol = 1.2, pitch = 0.55, var = 0.08, fx = { dist = 0.5, low = 8 } },
		{ id = S.rocket, vol = 0.25, pitch = 2.6, var = 0.1, fx = { high = 2 } },
	},
	block = {
		{ id = S.unsheath, vol = 0.5, pitch = 2.0, var = 0.08, fx = { echo = 0.15 } },
		{ id = S.collide, vol = 0.35, pitch = 1.8, var = 0.1 },
	},
	parry = {
		{ id = S.ping, vol = 0.6, pitch = 1.6, var = 0, fx = { reverb = 0.4 } },
		{ id = S.unsheath, vol = 0.6, pitch = 1.3, var = 0.05, fx = { reverb = 0.3 } },
	},
	slash = { { id = S.slash, vol = 0.65, pitch = 1.1, var = 0.12 }, { id = S.lunge, vol = 0.25, pitch = 1.4, var = 0.1 } },
	bonk = {
		{ id = S.collide, vol = 1.3, pitch = 0.75, var = 0.05, fx = { dist = 0.2, low = 5 } },
		{ id = S.land, vol = 0.6, pitch = 0.7, var = 0.05 },
	},
	pistol = {
		{ id = S.paint, vol = 0.8, pitch = 1.1, var = 0.08, fx = { dist = 0.3, low = 4 } },
		{ id = S.rocket, vol = 0.18, pitch = 3, var = 0.1 },
	},
	smg = { { id = S.paint, vol = 0.5, pitch = 1.5, var = 0.1, fx = { dist = 0.25 } } },
	shotgun = {
		{ id = S.rocket, vol = 0.8, pitch = 1.5, var = 0.06, fx = { dist = 0.45, low = 6 } },
		{ id = S.collide, vol = 0.4, pitch = 0.8, var = 0.05 },
	},
	sniper = {
		{ id = S.rocket, vol = 0.9, pitch = 2.2, var = 0.03, fx = { dist = 0.3, reverb = 0.35 } },
		{ id = S.ping, vol = 0.2, pitch = 0.5, var = 0, fx = { reverb = 0.5 } },
	},
	rocket = { { id = S.rocket, vol = 0.8, pitch = 0.9, var = 0.05, fx = { low = 4 } }, { id = S.whoosh, vol = 0.5, pitch = 1, var = 0.05 } },
	boom = {
		{ id = S.rocket, vol = 1.4, pitch = 0.45, var = 0.05, fx = { dist = 0.6, low = 10, reverb = 0.3 } },
		{ id = S.collide, vol = 1.0, pitch = 0.35, var = 0.05, fx = { dist = 0.4 } },
		{ id = S.glass, vol = 0.3, pitch = 0.5, var = 0.1 },
	},
	throw = { { id = S.lunge, vol = 0.45, pitch = 1.1, var = 0.1 } },
	lob = { { id = S.lunge, vol = 0.4, pitch = 0.9, var = 0.1 }, { id = S.click, vol = 0.3, pitch = 0.8, var = 0 } },
	pickup = { { id = S.ping, vol = 0.45, pitch = 1.5, var = 0.04 }, { id = S.click, vol = 0.3, pitch = 1.4, var = 0 } },
	deflect = { { id = S.unsheath, vol = 0.7, pitch = 1.6, var = 0.1, fx = { echo = 0.2 } } },
	jump = { { id = S.jump, vol = 0.3, pitch = 1.2, var = 0.1 } },
	djump = { { id = S.lunge, vol = 0.35, pitch = 2.4, var = 0.1 }, { id = S.ping, vol = 0.15, pitch = 2, var = 0.05 } },
	land = { { id = S.land, vol = 0.35, pitch = 1, var = 0.1 } },
	ko = {
		{ id = S.collide, vol = 1.4, pitch = 0.4, var = 0.05, fx = { dist = 0.5, low = 6 } },
		{ id = S.glass, vol = 0.35, pitch = 0.7, var = 0.1 },
		{ id = S.ping, vol = 0.4, pitch = 0.6, var = 0, fx = { reverb = 0.5 } },
	},
	tick = { { id = S.click, vol = 0.6, pitch = 1, var = 0 } },
	fight = { { id = S.ping, vol = 0.7, pitch = 0.8, var = 0, fx = { echo = 0.3 } }, { id = S.rocket, vol = 0.3, pitch = 0.7, var = 0 } },
	win = { { id = S.ping, vol = 0.7, pitch = 1.2, var = 0, fx = { echo = 0.3, reverb = 0.3 } } },
	saw = { { id = S.slash, vol = 0.6, pitch = 0.6, var = 0.1, fx = { dist = 0.3 } } },
	spikes = { { id = S.unsheath, vol = 0.6, pitch = 0.7, var = 0.1 } },
	drop = { { id = S.ping, vol = 0.3, pitch = 1, var = 0.05 } },
	click = { { id = S.click, vol = 0.4, pitch = 1.2, var = 0 } },
}

local POOL = 4
type Voice = { sounds: { Sound }, cursor: number, layer: Layer }
local voices: { [string]: { Voice } } = {}
Audio.muted = false
Audio.volume = 1

local function addFx(s: Sound, fx: Fx?)
	if not fx then
		return
	end
	if fx.low or fx.mid or fx.high then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = fx.low or 0
		eq.MidGain = fx.mid or 0
		eq.HighGain = fx.high or 0
		eq.Priority = 3
		eq.Parent = s
	end
	if fx.dist then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = fx.dist
		d.Priority = 2
		d.Parent = s
	end
	if fx.echo then
		local e = Instance.new("EchoSoundEffect")
		e.Delay = 0.09
		e.Feedback = 0.25
		e.WetLevel = -12 + fx.echo * 10
		e.Priority = 1
		e.Parent = s
	end
	if fx.reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = 1.2
		r.WetLevel = -14 + fx.reverb * 12
		r.Priority = 0
		r.Parent = s
	end
end

function Audio.init()
	local folder = Instance.new("Folder")
	folder.Name = "RumbleSounds"
	folder.Parent = SoundService
	for name, layers in RECIPES do
		local list = {}
		for li, layer in layers do
			local v: Voice = { sounds = {}, cursor = 1, layer = layer }
			for i = 1, POOL do
				local s = Instance.new("Sound")
				s.Name = name .. "_" .. li .. "_" .. i
				s.SoundId = layer.id
				s.Volume = layer.vol
				addFx(s, layer.fx)
				s.Parent = folder
				v.sounds[i] = s
			end
			list[li] = v
		end
		voices[name] = list
	end
end

function Audio.play(name: string, volumeScale: number?, pitchScale: number?)
	if Audio.muted then
		return
	end
	local list = voices[name]
	if not list then
		return
	end
	for _, v in list do
		local s = v.sounds[v.cursor]
		v.cursor = v.cursor % POOL + 1
		local l = v.layer
		local var = l.var or 0
		s.PlaybackSpeed = l.pitch * (pitchScale or 1) * (1 + (math.random() * 2 - 1) * var)
		s.Volume = l.vol * (volumeScale or 1) * Audio.volume
		s.TimePosition = 0
		s:Play()
	end
end

return Audio
