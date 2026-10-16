--!strict
-- The big cartoon scenery of the shared world: sky clouds, balloons and floating islands (they bob
-- on every client, see client SkyFx), colourful hills, a fountain plaza, striped paths with flower
-- rows, and the pretty FREE PLOT marker. Plain Parts only, no asset ids. Where things go comes from
-- Shared/Util/SkyLayout (tested); this file only turns numbers into chunky low-poly parts.
-- Nothing is scary, nothing is a flag.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SkyLayout = require(ReplicatedStorage.Shared.Util.SkyLayout)
local Meshes = require(script.Parent.Parent.Systems.Meshes)

type PartMaker = (props: { [string]: any }) -> Part

local WorldArt = {}

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder

WorldArt.BobTag = "SkyBob"

-- One decoration part: no collision, never hit by a raycast, no shadow cost.
local function deco(
	make: PartMaker,
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	collide: boolean?
): Part
	local props: { [string]: any } = {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		CanCollide = collide == true,
		CanQuery = false,
		CastShadow = false,
	}
	if shape then
		props.Shape = shape
	end
	local part = make(props)
	part.Parent = parent
	return part
end

-- A cylinder standing up (Roblox cylinders lie along X).
local function upCyl(
	make: PartMaker,
	parent: Instance,
	name: string,
	at: Vector3,
	diameter: number,
	height: number,
	color: Color3,
	collide: boolean?
): Part
	return deco(
		make,
		parent,
		name,
		CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		CYL,
		collide
	)
end

-- Marks a model so every client gently bobs and turns it (SkyFx). Nothing moves on the server.
local function bobbing(model: Model, amp: number, speed: number, spin: number, phase: number)
	model:SetAttribute("BobAmp", amp)
	model:SetAttribute("BobSpeed", speed)
	model:SetAttribute("BobSpin", spin)
	model:SetAttribute("BobPhase", phase)
	CollectionService:AddTag(model, WorldArt.BobTag)
end

-- Sky ---------------------------------------------------------------------------------------------

function WorldArt.cloud(make: PartMaker, parent: Instance, item: SkyLayout.Item)
	local real = Meshes.clone("CF_Cloud", CFrame.new(item.x, item.y, item.z), nil, 6.54, true, item.scale)
	if real then
		real.Parent = parent
		bobbing(real, 1.5 * item.scale, 0.25 + item.spin * 0.2, 0, item.phase)
		return
	end
	local model = Instance.new("Model")
	model.Name = "Cloud"
	local s = item.scale
	local white = Color3.fromRGB(255, 255, 255)
	local shade = Color3.fromRGB(226, 240, 255)
	local at = Vector3.new(item.x, item.y, item.z)
	local puffs = {
		{ 0, 0, 0, 16 },
		{ 11, -1, 2, 12 },
		{ -11, -1.5, -1, 12 },
		{ 5, 4, -3, 11 },
		{ -5, 3, 3, 10 },
	}
	for i, p in puffs do
		deco(
			make,
			model,
			"Puff",
			CFrame.new(at + Vector3.new(p[1] * s, p[2] * s, p[3] * s)),
			Vector3.one * p[4] * s,
			if i % 2 == 0 then shade else white,
			BALL
		)
	end
	model.Parent = parent
	bobbing(model, 1.5 * s, 0.25 + item.spin * 0.2, 0, item.phase)
end

function WorldArt.balloon(make: PartMaker, parent: Instance, item: SkyLayout.Item)
	local real = Meshes.clone(
		"CF_Balloon",
		CFrame.new(item.x, item.y, item.z),
		{ Envelope = SkyLayout.BALLOONS[item.color] },
		6.4,
		true,
		item.scale
	)
	if real then
		real.Parent = parent
		bobbing(real, 3 * item.scale, 0.5, item.spin * 0.4, item.phase)
		return
	end
	local model = Instance.new("Model")
	model.Name = "Balloon"
	local s = item.scale
	local color = SkyLayout.BALLOONS[item.color]
	local at = Vector3.new(item.x, item.y, item.z)
	deco(make, model, "Envelope", CFrame.new(at + Vector3.new(0, 6 * s, 0)), Vector3.new(9, 11, 9) * s, color, BALL)
	deco(
		make,
		model,
		"Stripe",
		CFrame.new(at + Vector3.new(0, 6 * s, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(9.2, 3.5, 9.2) * s,
		Color3.fromRGB(255, 255, 255),
		BALL
	)
	deco(
		make,
		model,
		"Knot",
		CFrame.new(at + Vector3.new(0, 0.2 * s, 0)),
		Vector3.new(2, 1.6, 2) * s,
		color:Lerp(Color3.new(0, 0, 0), 0.25)
	)
	upCyl(make, model, "String", at + Vector3.new(0, -2.6 * s, 0), 0.2 * s, 5 * s, SkyLayout.ISLAND.trunk)
	deco(
		make,
		model,
		"Basket",
		CFrame.new(at + Vector3.new(0, -5.6 * s, 0)),
		Vector3.new(2.4, 1.6, 2.4) * s,
		Color3.fromRGB(245, 245, 250)
	)
	model.Parent = parent
	bobbing(model, 3 * s, 0.5, item.spin * 0.4, item.phase)
end

function WorldArt.island(make: PartMaker, parent: Instance, item: SkyLayout.Item)
	local real =
		Meshes.clone("CF_Island", CFrame.new(item.x, item.y + 0.6 * item.scale, item.z), nil, 12.8, true, item.scale)
	if real then
		real.Parent = parent
		bobbing(real, 2.5 * item.scale, 0.3, item.spin * 0.25, item.phase)
		return
	end
	local model = Instance.new("Model")
	model.Name = "FloatingIsland"
	local s = item.scale
	local at = Vector3.new(item.x, item.y, item.z)
	local p = SkyLayout.ISLAND
	-- a round grassy top over a smooth grey-and-white rock bowl (no stacked layers), cute and clean
	deco(make, model, "RockBowl", CFrame.new(at + Vector3.new(0, -2 * s, 0)), Vector3.new(24, 20, 24) * s, p.rock, BALL)
	deco(
		make,
		model,
		"RockLight",
		CFrame.new(at + Vector3.new(3 * s, -4.5 * s, 3 * s)),
		Vector3.new(11, 11, 11) * s,
		p.rockLight,
		BALL
	)
	upCyl(make, model, "Grass", at + Vector3.new(0, 0.6 * s, 0), 27 * s, 2.2 * s, p.grass)
	-- a round bushy tree (grey trunk), flower dots and a big gold coin on top
	upCyl(make, model, "Trunk", at + Vector3.new(-6 * s, 3.6 * s, 2 * s), 1.4 * s, 4.4 * s, p.trunk)
	deco(make, model, "Leaves", CFrame.new(at + Vector3.new(-6 * s, 8 * s, 2 * s)), Vector3.one * 7 * s, p.leaf, BALL)
	for i = 1, 4 do
		local a = i * 1.6
		deco(
			make,
			model,
			"Flower",
			CFrame.new(at + Vector3.new(math.cos(a) * 6 * s + 3 * s, 2 * s, math.sin(a) * 4 * s - 3 * s)),
			Vector3.one * 1.4 * s,
			SkyLayout.BALLOONS[(i + item.color) % #SkyLayout.BALLOONS + 1],
			BALL
		)
	end
	local coin = deco(
		make,
		model,
		"Coin",
		CFrame.new(at + Vector3.new(6 * s, 5.6 * s, -2 * s)) * CFrame.Angles(0, math.rad(40), 0),
		Vector3.new(0.9, 6, 6) * s,
		Color3.fromRGB(255, 205, 40),
		CYL
	)
	coin.Material = Enum.Material.Foil
	model.Parent = parent
	bobbing(model, 2.5 * s, 0.3, item.spin * 0.25, item.phase)
end

-- Hills ---------------------------------------------------------------------------------------------

function WorldArt.hills(make: PartMaker, parent: Instance)
	for i, hill in SkyLayout.hills() do
		local size = hill.size
		deco(make, parent, "Hill", CFrame.new(hill.x, -size * 0.3, hill.z), Vector3.one * size, hill.color, BALL)
		-- a lighter, smaller top patch so each hill has two tones (flat-shaded look)
		deco(
			make,
			parent,
			"HillTop",
			CFrame.new(hill.x * 0.985, size * 0.2, hill.z * 0.985),
			Vector3.one * size * 0.6,
			hill.cap,
			BALL
		)
		if i % 3 == 0 then
			-- a few round "bushes" on the near side
			for k = 1, 3 do
				local back = Vector3.new(-hill.x, 0, -hill.z).Unit
				local at = Vector3.new(hill.x, 0, hill.z) + back * (size * 0.38) + Vector3.new(0, 2, 0)
				deco(
					make,
					parent,
					"HillBush",
					CFrame.new(at + Vector3.new(k * 5 - 10, 0, (k % 2) * 4)),
					Vector3.new(6, 5, 6),
					hill.cap:Lerp(Color3.fromRGB(60, 180, 80), 0.35),
					BALL
				)
			end
		end
	end
end

-- Plaza ---------------------------------------------------------------------------------------------

local function fountain(make: PartMaker, parent: Instance, at: Vector3)
	local real = Meshes.clone("CF_Fountain", CFrame.new(at), nil, nil, true)
	if real then
		real.Parent = parent
		return
	end
	local model = Instance.new("Model")
	model.Name = "Fountain"
	local stone = Color3.fromRGB(235, 232, 245)
	local water = Color3.fromRGB(70, 185, 255)
	upCyl(make, model, "Basin", at + Vector3.new(0, 0.7, 0), 9.2, 1.4, Color3.fromRGB(255, 190, 70), true)
	upCyl(make, model, "BasinRim", at + Vector3.new(0, 1.5, 0), 9.2, 0.4, stone, true)
	local pool = upCyl(make, model, "Water", at + Vector3.new(0, 1.45, 0), 8.0, 0.4, water)
	pool.Transparency = 0.15
	upCyl(make, model, "Column", at + Vector3.new(0, 3.0, 0), 1.7, 3.2, stone)
	upCyl(make, model, "Bowl", at + Vector3.new(0, 4.8, 0), 4.4, 0.8, stone)
	local top = upCyl(make, model, "BowlWater", at + Vector3.new(0, 5.25, 0), 3.8, 0.3, water)
	top.Transparency = 0.15
	-- a chunky spray: a ball on top and drops falling round it
	deco(
		make,
		model,
		"Spray",
		CFrame.new(at + Vector3.new(0, 7.0, 0)),
		Vector3.one * 2.4,
		Color3.fromRGB(200, 235, 255),
		BALL
	)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		deco(
			make,
			model,
			"Drop",
			CFrame.new(at + Vector3.new(math.cos(a) * 2.6, 5.6, math.sin(a) * 2.6)),
			Vector3.one * 0.9,
			Color3.fromRGB(150, 215, 255),
			BALL
		)
	end
	model.Parent = parent
end

-- Coloured rings on the sandy plaza, and four fountains.
function WorldArt.plaza(make: PartMaker, parent: Instance)
	local tile = Meshes.clone("CF_PlazaTile", CFrame.new(0, 0.2, 0), nil, nil, true)
	for i, ring in SkyLayout.PLAZA_RINGS do
		if tile then
			break
		end
		upCyl(make, parent, `PlazaRing{i}`, Vector3.new(0, 0.2 + i * 0.012, 0), ring.diameter, 0.04, ring.color)
	end
	if tile then
		tile.Parent = parent
	end
	for _, spot in SkyLayout.fountains(Config.MAX_PLOTS) do
		fountain(make, parent, Vector3.new(spot.x, 0, spot.z))
	end
end

-- Paths ---------------------------------------------------------------------------------------------

-- Dresses the path to yard `slot` (from `inner` to `outer` studs from the middle): a curb in the slot's
-- colour on both sides, white dashes down the middle and rows of flowers beyond the curbs.
function WorldArt.path(make: PartMaker, parent: Instance, slot: number, inner: number, outer: number)
	local a = (slot - 1) / Config.MAX_PLOTS * math.pi * 2
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local mid = dir * ((inner + outer) / 2)
	local look = CFrame.lookAt(mid, mid + dir)
	local length = outer - inner
	local edge = SkyLayout.PATH_EDGES[(slot - 1) % #SkyLayout.PATH_EDGES + 1]
	for _, sign in { -1, 1 } do
		deco(make, parent, "Curb", look * CFrame.new(sign * 3.4, 0.22, 0), Vector3.new(0.7, 0.25, length), edge)
	end
	local dashes = math.floor(length / 5)
	for i = 0, dashes - 1 do
		local z = -length / 2 + 2.5 + i * 5
		deco(make, parent, "Dash", look * CFrame.new(0, 0.24, z), Vector3.new(0.8, 0.06, 2.4), SkyLayout.PATH_DASH)
	end
	local flowers = SkyLayout.pathFlowers(inner, outer)
	for i, d in flowers do
		for _, sign in { -1, 1 } do
			local at = dir * d + side * (sign * SkyLayout.PATH_FLOWER_SIDE)
			local color = SkyLayout.BALLOONS[(i + slot + (if sign > 0 then 1 else 0)) % #SkyLayout.BALLOONS + 1]
			deco(
				make,
				parent,
				"Stem",
				CFrame.new(at + Vector3.new(0, 0.6, 0)),
				Vector3.new(0.25, 1.2, 0.25),
				Color3.fromRGB(70, 170, 60)
			)
			deco(make, parent, "Flower", CFrame.new(at + Vector3.new(0, 1.5, 0)), Vector3.one * 1.3, color, BALL)
			deco(
				make,
				parent,
				"Heart",
				CFrame.new(at + Vector3.new(0, 1.7, 0)),
				Vector3.one * 0.6,
				Color3.fromRGB(255, 240, 130),
				BALL
			)
		end
	end
end

-- Everything -----------------------------------------------------------------------------------------

function WorldArt.sky(make: PartMaker, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "SkyDecor"
	for _, item in SkyLayout.clouds() do
		WorldArt.cloud(make, folder, item)
	end
	for _, item in SkyLayout.balloons() do
		WorldArt.balloon(make, folder, item)
	end
	for _, item in SkyLayout.islands() do
		WorldArt.island(make, folder, item)
	end
	folder.Parent = parent
end

return WorldArt
