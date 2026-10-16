--!strict
-- Client side of the remotes. The server creates them; we only find them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNet = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")

function ClientNet.event(name: string): RemoteEvent
	local remote = folder:WaitForChild(name)
	if not remote:IsA("RemoteEvent") then
		error(`{name} is not a RemoteEvent`)
	end
	return remote
end

-- For remotes that may not exist (the Studio-only Cheat remote).
function ClientNet.find(name: string): RemoteEvent?
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

return ClientNet
