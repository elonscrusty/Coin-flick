--!strict
-- Walks the little helper guys around their table with a bouncy hop.
-- Visual only (each client animates locally; nothing is sent over the network).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local ClientNet = require(script.Parent.Parent.ClientNet)

local Helpers = {}

local tracked: { [Model]: boolean } = {}
local jumpAt: { [string]: number } = {} -- "ownerId/helperId" -> when that helper last flipped
local UP = Vector3.new(0, 1, 0)

local function ownerOf(model: Model): number?
	local tableModel = model:FindFirstAncestorOfClass("Model")
	local owner = tableModel and tableModel:GetAttribute("OwnerUserId")
	return if typeof(owner) == "number" then owner else nil
end

local function step()
	local now = os.clock()
	for model in tracked do
		if model.Parent == nil then
			tracked[model] = nil
			continue
		end
		local center = model:GetAttribute("OrbitCenter")
		local radius = model:GetAttribute("OrbitRadius")
		local phase = model:GetAttribute("Phase")
		if typeof(center) ~= "Vector3" or typeof(radius) ~= "number" or typeof(phase) ~= "number" then
			continue
		end
		local angle = now * 0.6 + phase
		local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local hop = math.abs(math.sin(now * 8 + phase)) * 0.5
		local owner = ownerOf(model)
		local helperId = model:GetAttribute("HelperId")
		local jumped = owner and jumpAt[`{owner}/{helperId}`]
		if jumped and now - jumped < 0.45 then
			hop += math.sin(math.pi * (now - jumped) / 0.45) * 2
		end
		local forward = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local at = pos + UP * hop
		model:PivotTo(CFrame.lookAt(at, at + forward))
	end
end

local function track(instance: Instance)
	if instance:IsA("Model") then
		tracked[instance] = true
	end
end

function Helpers.init()
	for _, instance in CollectionService:GetTagged("Helper") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("Helper"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Helper"):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			tracked[instance] = nil
		end
	end)
	ClientNet.event("Flipped").OnClientEvent:Connect(function(ev: Types.FlipEvent)
		if ev.byHelper and ev.helper then
			jumpAt[`{ev.ownerId}/{ev.helper}`] = os.clock()
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return Helpers
