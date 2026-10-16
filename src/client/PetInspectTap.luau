--!strict
-- Tap-to-inspect (carter 2026-10-14: players should look at someone else's pet and want a stronger one): a tap or
-- click on another player's following pet asks the server for its card (PvpAction op "Inspect"); the server answers
-- through the "Inspect" event and InspectPanel shows the pet with its battle power, level and the owner's trophies.
-- Follower parts are not queryable (no raycast hits), so the tap is matched on screen: the nearest pet whose
-- on-screen size covers the tap wins. Lobby only; nothing happens during a hunt, the tower or a battle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PetFollow = require(script.Parent.PetFollow)

local PetInspectTap = {}

local player = Players.LocalPlayer
local MIN_RADIUS = 36 -- px: a far pet still takes a finger-sized tap
local MAX_RANGE = 120 -- studs from the camera

local function busy(): boolean
	return player:GetAttribute("MatchKey") ~= nil or player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true
end

-- The other player's pet under screen point `at`, or nil.
function PetInspectTap.pick(at: Vector2): (Player?, string?)
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil, nil
	end
	local best: { Player: Player, Id: string, Model: Model }? = nil
	local bestD = math.huge
	for _, s in PetFollow.shown() do
		if s.Player ~= player then
			local cf, size = s.Model:GetBoundingBox()
			if (cf.Position - cam.CFrame.Position).Magnitude <= MAX_RANGE then
				local c, onScreen = cam:WorldToViewportPoint(cf.Position)
				if onScreen and c.Z > 0 then
					local top = cam:WorldToViewportPoint(cf.Position + Vector3.new(0, math.max(size.Y, size.X) / 2, 0))
					local r = math.max(MIN_RADIUS, (Vector2.new(top.X, top.Y) - Vector2.new(c.X, c.Y)).Magnitude * 1.3)
					local d = (Vector2.new(c.X, c.Y) - at).Magnitude
					if d <= r and d < bestD then
						best, bestD = s, d
					end
				end
			end
		end
	end
	if best then
		return best.Player, best.Id
	end
	return nil, nil
end

function PetInspectTap.start()
	local net = ReplicatedStorage:WaitForChild("PvpNet")
	local action = net:WaitForChild("PvpAction") :: RemoteEvent
	local last = 0
	local function tapAt(pos: Vector2)
		if busy() or os.clock() - last < 0.6 then
			return
		end
		local owner, id = PetInspectTap.pick(pos)
		if owner and id then
			last = os.clock()
			action:FireServer({ Op = "Inspect", UserId = owner.UserId, Pet = id })
		end
	end
	UserInputService.TouchTap:Connect(function(touches, processed)
		if not processed and touches[1] then
			tapAt(touches[1])
		end
	end)
	-- a mouse click that did not drag the camera (TouchTap covers phones)
	local downAt: Vector2? = nil
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local from = downAt
		downAt = nil
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if not processed and from and (at - from).Magnitude < 8 then
			tapAt(at)
		end
	end)
end

return PetInspectTap
