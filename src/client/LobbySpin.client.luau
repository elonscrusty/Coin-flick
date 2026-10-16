--!strict
-- Slow spin for lobby showpieces (the egg on the EGG SHOP roof, the tower portal swirl). Any anchored BasePart tagged "LobbySpin" turns
-- about its own up axis on this client (attribute SpinSpeed = radians per second, default 0.6). Visual only.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "LobbySpin"
local home: { [BasePart]: CFrame } = {}

local function add(inst: Instance)
	if inst:IsA("BasePart") and not home[inst] then
		home[inst] = inst.CFrame
	end
end
local function remove(inst: Instance)
	if inst:IsA("BasePart") then
		home[inst] = nil
	end
end
for _, inst in CollectionService:GetTagged(TAG) do
	add(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

local t0 = os.clock()
RunService.Heartbeat:Connect(function()
	local t = os.clock() - t0
	for part, cf in home do
		if part.Parent then
			local speed = part:GetAttribute("SpinSpeed")
			local s = if type(speed) == "number" then speed else 0.6
			local axis = part:GetAttribute("SpinAxis") -- "X" / "Y" (default) / "Z": the local axis to turn about
			local a = t * s
			part.CFrame = cf * (if axis == "X" then CFrame.Angles(a, 0, 0) elseif axis == "Z" then CFrame.Angles(0, 0, a) else CFrame.Angles(0, a, 0))
		end
	end
end)
