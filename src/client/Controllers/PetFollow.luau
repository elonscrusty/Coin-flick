--!strict
-- Walks every coin pet behind its owner and hops it (Shared/Util/PetFollowMath has the numbers).
-- Visual only: each client animates all pets locally, nothing is sent over the network. The server
-- places the pet (Systems/Pets) and stamps a "FlipAt" time on it when the pet flips its coin.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Math = require(ReplicatedStorage.Shared.Util.PetFollowMath)

local PetFollow = {}

local TAG = "CoinPet" -- same as PetBuilder.TAG

type Walker = { x: number, y: number, z: number, yaw: number, ready: boolean }
local tracked: { [Model]: Walker } = {}

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function step(dt: number)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, walker in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			continue
		end
		local owner = model:GetAttribute("OwnerUserId")
		local root = if typeof(owner) == "number" then rootOf(owner) else nil
		if not root then
			continue
		end
		local look = root.CFrame.LookVector
		local sx, sy, sz = Math.spot(root.Position.X, root.Position.Y, root.Position.Z, look.X, look.Z)
		if not walker.ready then
			walker.x, walker.y, walker.z, walker.ready = sx, sy, sz, true
		end
		local nx, ny, nz = Math.step(walker.x, walker.y, walker.z, sx, sy, sz, dt)
		local moving = Math.isMoving(nx, ny, nz, sx, sy, sz)
		if moving then
			local dx, dz = nx - walker.x, nz - walker.z
			if dx * dx + dz * dz > 1e-6 then
				walker.yaw = math.atan2(-dx, -dz) -- face where it is walking (the model looks down -Z)
			end
		else
			walker.yaw = math.atan2(-look.X, -look.Z)
		end
		walker.x, walker.y, walker.z = nx, ny, nz
		local flipAt = model:GetAttribute("FlipAt")
		local since = if typeof(flipAt) == "number" then serverNow - flipAt else nil
		local hop = Math.hop(now, (owner :: number) % 7, moving, since)
		model:PivotTo(CFrame.new(nx, ny + hop, nz) * CFrame.Angles(0, walker.yaw, 0))
	end
end

local function track(instance: Instance)
	if instance:IsA("Model") then
		tracked[instance] = { x = 0, y = 0, z = 0, yaw = 0, ready = false }
	end
end

function PetFollow.init()
	for _, instance in CollectionService:GetTagged(TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			tracked[instance] = nil
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return PetFollow
