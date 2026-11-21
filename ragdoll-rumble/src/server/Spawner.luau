--!strict
-- Puts fighters into the world: player avatars (LoadCharacterAsync), bots and lobby dummies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rig = require(Shared:WaitForChild("Rig"))

local Arena = require(script.Parent:WaitForChild("Arena"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Bots = require(script.Parent:WaitForChild("Bots"))

local Spawner = {}

export type Who = { fid: number, name: string, colorIndex: number, player: Player?, isBot: boolean }

local function fightersFolder(): Folder
	local f = workspace:FindFirstChild("Fighters")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Fighters"
		f.Parent = workspace
	end
	return f :: Folder
end

Spawner.onSpawned = function(_f: Combat.F) end

-- configure a freshly spawned rig and register it
function Spawner.setup(who: Who, model: Model, zone: string, x: number, y: number, frozen: boolean, isDummy: boolean?): Combat.F?
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return nil
	end
	-- replace any previous registration for this fighter id
	local old = Combat.fighters[who.fid]
	if old and old.model ~= model then
		Combat.unregister(who.fid)
		if old.isBot and old.model.Parent then
			old.model:Destroy()
		end
	end
	if not root:FindFirstChild("Facing") then
		Rig.setup(model)
	end
	model:PivotTo(Arena.spawnCFrame(zone, x, y))
	hum.MaxHealth = Config.MAX_HP
	hum.Health = Config.MAX_HP
	hum.UseJumpPower = true
	hum.WalkSpeed = if frozen then 0 else Config.WALK_SPEED
	hum.JumpPower = if frozen then 0 else Config.JUMP_POWER
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.AutoRotate = false
	model:SetAttribute("Fid", who.fid)
	model:SetAttribute("ColorIndex", who.colorIndex)
	model:SetAttribute("FighterName", who.name)
	model:SetAttribute("IsBot", who.isBot)
	model:SetAttribute("IsDummy", isDummy == true)
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Wid", 0)
	model:SetAttribute("Ammo", 0)
	model:SetAttribute("Alive", true)
	model:SetAttribute("Ragdoll", false)
	model:SetAttribute("Victory", false)
	local z = Arena.zones[zone]
	local cx = if z then (z.map.bounds.left + z.map.bounds.right) * 0.5 else 0
	local facing = if x > cx then -1 else 1
	local fo = root:FindFirstChild("Facing") :: AlignOrientation?
	if fo then
		fo.CFrame = Rig.facingCFrame(facing)
	end
	model.Parent = fightersFolder()
	local f = Combat.newFighter(who.fid, who.name, who.colorIndex, model, who.player, zone, isDummy)
	f.aim = if facing > 0 then 0 else math.pi
	if who.isBot then
		f.brain = Bots.newBrain(math.random(1, 1e6), if isDummy then 0 else 0.45 + math.random() * 0.4)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	Combat.register(f)
	Spawner.onSpawned(f)
	return f
end

local tokens: { [number]: number } = {}

-- async; a newer spawn request for the same fighter cancels older ones
function Spawner.spawn(who: Who, zone: string, x: number, y: number, frozen: boolean, isDummy: boolean?)
	local token = (tokens[who.fid] or 0) + 1
	tokens[who.fid] = token
	task.spawn(function()
		if who.player then
			local player = who.player :: Player
			local ok, err = pcall(function()
				(player :: any):LoadCharacterAsync()
			end)
			if not ok then
				ok, err = pcall(function()
					player:LoadCharacter()
				end)
			end
			if not ok then
				warn("[Ragdoll Rumble] could not load character:", err)
				return
			end
			local char = player.Character
			if not char or tokens[who.fid] ~= token then
				return
			end
			char:WaitForChild("HumanoidRootPart", 6)
			char:WaitForChild("Humanoid", 6)
			if tokens[who.fid] ~= token or not char.Parent or not player.Parent then
				return
			end
			Spawner.setup(who, char, zone, x, y, frozen, false)
		else
			local tpl = Bots.template(who.colorIndex)
			if not tpl or tokens[who.fid] ~= token then
				return
			end
			local m = tpl:Clone()
			m.Name = who.name
			Spawner.setup(who, m, zone, x, y, frozen, isDummy)
		end
	end)
end

function Spawner.cancel(fid: number)
	tokens[fid] = (tokens[fid] or 0) + 1
end

return Spawner
