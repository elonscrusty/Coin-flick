--!strict
-- Rare pet sparkles follow the viewer's Low Effects setting (client only, cosmetic). PetModel tags every rarity
-- Sparkles, trait sparkles, Legendary beams and rarity PointLights "PetSparkle" (followers built here, gallery pets built on the server); this turns them all off locally
-- while Settings.LowEffects is on and back on when it is off. Nothing is sent anywhere.

local CollectionService = game:GetService("CollectionService")

local State = require(script.Parent.State)

local PetSparkle = {}

local TAG = "PetSparkle"

local function low(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.LowEffects == true
end

-- Tagged pet FX: rarity and Rainbow / Silver Cosmic sparkles, Legendary beams, rarity glow lights, the follower
-- particle traits from PetFx (element embers / snowflakes / ..., Golden / Rainbow shimmer) and the Golden / Rainbow
-- follower trails (PetTrail).
local function apply(inst: Instance, on: boolean)
	if inst:IsA("Sparkles") or inst:IsA("Beam") or inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Trail") then
		(inst :: any).Enabled = on
	end
end

local started = false
function PetSparkle.start()
	if started then
		return
	end
	started = true
	local current = not low()
	for _, inst in CollectionService:GetTagged(TAG) do
		apply(inst, current)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		apply(inst, not low())
	end)
	State.Changed.Event:Connect(function(what)
		if what ~= "Profile" then
			return
		end
		local on = not low()
		if on ~= current then
			current = on
			for _, inst in CollectionService:GetTagged(TAG) do
				apply(inst, on)
			end
		end
	end)
end

return PetSparkle
