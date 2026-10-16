--!strict
-- Racers never bump (owner pick): characters in a hunt use the collision group "Racers", which does not collide
-- with itself, so hunters pass through each other but still stand on the floor, the pile and the nests.
-- MatchService turns it on when it places a character at a hunt spawn and off when it sends them to the lobby.
-- Every PhysicsService call is wrapped in pcall: a failure only means players bump as before.

local GROUP = "Racers"
local DEFAULT = "Default"

local RacerCollision = {}

local ready = false
local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function setup()
	if ready then
		return true
	end
	local ok = pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		if not PhysicsService:IsCollisionGroupRegistered(GROUP) then
			PhysicsService:RegisterCollisionGroup(GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	end)
	ready = ok
	return ok
end

local function groupFor(char: Model): string
	return if char:GetAttribute("Racer") == true then GROUP else DEFAULT
end

local function setPart(part: Instance, group: string)
	if part:IsA("BasePart") then
		pcall(function()
			part.CollisionGroup = group
		end)
	end
end

-- Puts every part of `char` (and parts added later: accessories, held tools) in the racer group or back.
function RacerCollision.apply(char: Model?, on: boolean)
	if not char or not setup() then
		return
	end
	char:SetAttribute("Racer", on)
	local group = groupFor(char)
	for _, d in char:GetDescendants() do
		setPart(d, group)
	end
	if not watched[char] then
		watched[char] = true
		char.DescendantAdded:Connect(function(d)
			setPart(d, groupFor(char))
		end)
	end
end

function RacerCollision.start()
	setup()
end

return RacerCollision
