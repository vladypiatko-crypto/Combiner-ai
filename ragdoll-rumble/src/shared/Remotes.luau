--!strict
-- Remote events (created by the server, awaited by clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local function get(name: string, className: string): any
	local folder = ReplicatedStorage:FindFirstChild("RumbleRemotes")
	if RunService:IsServer() then
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "RumbleRemotes"
			folder.Parent = ReplicatedStorage
		end
		local r = (folder :: Instance):FindFirstChild(name)
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	folder = ReplicatedStorage:WaitForChild("RumbleRemotes")
	return (folder :: Instance):WaitForChild(name)
end

-- reliable game events (both directions), tables with a `t` field
Remotes.Event = get("Event", "RemoteEvent") :: RemoteEvent
-- unreliable aim / flag stream (both directions)
Remotes.State = get("State", "UnreliableRemoteEvent") :: UnreliableRemoteEvent

return Remotes
