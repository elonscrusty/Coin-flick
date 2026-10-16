--!strict
-- Creates every remote (server only) from the one list in Shared/Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

local events: { [string]: RemoteEvent } = {}

function Net.init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	local function add(name: string)
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		events[name] = remote
	end
	for _, name in Remotes.Events do
		add(name)
	end
	if RunService:IsStudio() then
		for _, name in Remotes.StudioOnly do
			add(name)
		end
	end
	folder.Parent = ReplicatedStorage
end

function Net.event(name: string): RemoteEvent
	local remote = events[name]
	assert(remote, `unknown remote {name}`)
	return remote
end

return Net
