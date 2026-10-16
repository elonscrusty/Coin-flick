--!strict
-- Latest numbers from the server, for the HUD. Display only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local ClientNet = require(script.Parent.Parent.ClientNet)

type Snapshot = Types.Snapshot

local State = {}

local current: Snapshot? = nil
local listeners: { (Snapshot) -> () } = {}

function State.get(): Snapshot?
	return current
end

function State.onChange(fn: (Snapshot) -> ())
	table.insert(listeners, fn)
	if current then
		task.spawn(fn, current)
	end
end

function State.init()
	ClientNet.event("State").OnClientEvent:Connect(function(snapshot: Snapshot)
		current = snapshot
		for _, fn in listeners do
			task.spawn(fn, snapshot)
		end
	end)
end

return State
