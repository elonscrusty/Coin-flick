--!strict
-- Builds each silly hat from chunky parts. y = 0 is the top of the head,
-- -Z is the front of the face. Sized for a normal Roblox head (~1.2 wide).

type Make = (props: { [string]: any }) -> Part

local HatBuilder = {}

local function cyl(model: Model, make: Make, height: number, diameter: number, y: number, color: Color3)
	local part = make({
		Name = "Piece",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(0, y + height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), -- upright cylinder
		Color = color,
	})
	part.Parent = model
	return part
end

local function ball(model: Model, make: Make, diameter: number, at: Vector3, color: Color3)
	local part = make({
		Name = "Piece",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		Position = at,
		Color = color,
	})
	part.Parent = model
	return part
end

local function block(model: Model, make: Make, size: Vector3, cframe: CFrame, color: Color3)
	local part = make({ Name = "Piece", Size = size, CFrame = cframe, Color = color })
	part.Parent = model
	return part
end

local PINK = Color3.fromRGB(255, 110, 190)
local YELLOW = Color3.fromRGB(255, 220, 60)
local ORANGE = Color3.fromRGB(255, 130, 30)
local WHITE = Color3.fromRGB(255, 255, 255)
local BROWN = Color3.fromRGB(150, 95, 50)
local DARK = Color3.fromRGB(35, 35, 45)
local RED = Color3.fromRGB(240, 70, 70)
local BLUE = Color3.fromRGB(70, 160, 255)
local GOLD = Color3.fromRGB(255, 200, 40)

export type Disc = { y: number, height: number, diameter: number, color: Color3 }

-- A cone built from thin discs that shrink smoothly (a stack of 3 big steps
-- reads as a cake). Colors alternate in stripes of `stripe` discs.
function HatBuilder.cone(
	steps: number,
	baseDiameter: number,
	tipDiameter: number,
	height: number,
	colors: { Color3 },
	stripe: number
): { Disc }
	local discs: { Disc } = {}
	local each = height / steps
	for i = 0, steps - 1 do
		local t = i / (steps - 1)
		table.insert(discs, {
			y = i * each,
			height = each * 1.02,
			diameter = baseDiameter + (tipDiameter - baseDiameter) * t,
			color = colors[(i // stripe) % #colors + 1],
		})
	end
	return discs
end

local function discs(m: Model, make: Make, list: { Disc }, y0: number)
	for _, d in list do
		cyl(m, make, d.height, d.diameter, y0 + d.y, d.color)
	end
end

local PARTY = HatBuilder.cone(8, 1.0, 0.1, 1.3, { PINK, YELLOW }, 2)
local TRAFFIC_CONE = HatBuilder.cone(7, 0.95, 0.22, 0.95, { ORANGE, ORANGE, WHITE, WHITE, ORANGE, ORANGE, ORANGE }, 1)

local BUILDERS: { [string]: (Model, Make) -> () } = {
	party = function(m, make)
		discs(m, make, PARTY, 0)
		ball(m, make, 0.3, Vector3.new(0, 1.38, 0), YELLOW)
	end,
	cone = function(m, make)
		block(m, make, Vector3.new(1.3, 0.12, 1.3), CFrame.new(0, 0.06, 0), ORANGE)
		discs(m, make, TRAFFIC_CONE, 0.12)
	end,
	cowboy = function(m, make)
		cyl(m, make, 0.12, 2.1, 0, BROWN)
		cyl(m, make, 0.6, 1.1, 0.12, BROWN)
		cyl(m, make, 0.14, 1.13, 0.14, RED)
	end,
	chef = function(m, make)
		cyl(m, make, 0.8, 1.05, 0, WHITE)
		cyl(m, make, 0.45, 1.4, 0.75, WHITE)
	end,
	propeller = function(m, make)
		cyl(m, make, 0.35, 1.2, 0, BLUE)
		cyl(m, make, 0.12, 1.25, 0.05, YELLOW)
		cyl(m, make, 0.4, 0.12, 0.35, DARK)
		block(m, make, Vector3.new(1.6, 0.06, 0.3), CFrame.new(0, 0.78, 0), RED)
		block(m, make, Vector3.new(0.3, 0.06, 1.6), CFrame.new(0, 0.8, 0), YELLOW)
	end,
	duck = function(m, make)
		ball(m, make, 1.1, Vector3.new(0, 0.45, 0.1), YELLOW)
		ball(m, make, 0.7, Vector3.new(0, 1.05, -0.25), YELLOW)
		block(m, make, Vector3.new(0.4, 0.14, 0.3), CFrame.new(0, 1.0, -0.65), ORANGE)
		ball(m, make, 0.14, Vector3.new(-0.18, 1.15, -0.55), DARK)
		ball(m, make, 0.14, Vector3.new(0.18, 1.15, -0.55), DARK)
	end,
	tophat = function(m, make)
		cyl(m, make, 0.1, 1.6, 0, DARK)
		cyl(m, make, 1.0, 1.0, 0.1, DARK)
		cyl(m, make, 0.16, 1.03, 0.14, RED)
	end,
	crown = function(m, make)
		cyl(m, make, 0.32, 1.15, 0, GOLD)
		for i = 0, 4 do
			local angle = i * math.pi * 2 / 5
			local at = Vector3.new(math.cos(angle) * 0.5, 0.45, math.sin(angle) * 0.5)
			block(m, make, Vector3.new(0.2, 0.28, 0.2), CFrame.new(at) * CFrame.Angles(0, -angle, 0), GOLD)
			ball(m, make, 0.16, at + Vector3.new(0, 0.2, 0), if i % 2 == 0 then RED else BLUE)
		end
	end,
}

function HatBuilder.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

-- A hat model around the origin. The caller moves it onto a head and welds it.
function HatBuilder.build(id: string, make: Make): Model?
	local builder = BUILDERS[id]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "CoinFlickHat"
	builder(model, make)
	-- Pivot at the head-top point (not the middle of the hat), so moving and
	-- scaling keeps the brim sitting on the head.
	model.WorldPivot = CFrame.new()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	return model
end

return HatBuilder
