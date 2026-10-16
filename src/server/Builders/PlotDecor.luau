--!strict
-- Chunky low-poly yard and world decorations, built from plain Parts.
-- The tree / boulder / bench / crate / lamp / planter shapes are ported from the Find The Pet
-- map's KitParts (pieces only, recoloured bright), plus beach, candy, castle and star pieces.
-- Nothing here uses an asset id. Every piece is `(make, parent, base, scale, theme)`.
--   PlotDecor.yard(...)   dresses one yard for its theme (floor tiles, corner trees, side props)
--   PlotDecor.world(...)  fills the empty world around the yards (spots from Util/DecorLayout)
-- Shapes face -Z like the yards do. Nothing scary, nothing gross, no flags.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DecorLayout = require(ReplicatedStorage.Shared.Util.DecorLayout)
local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)

type Theme = PlotThemes.Theme
type PartMaker = (props: { [string]: any }) -> Part
type Piece = (make: PartMaker, parent: Instance, base: CFrame, scale: number, theme: Theme) -> ()

local PlotDecor = {}

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

local function pick<T>(list: { T }, i: number): T
	return list[((i - 1) % #list) + 1]
end

-- One part, placed relative to `base`. Decoration never blocks the player unless `solid`.
local function put(
	make: PartMaker,
	parent: Instance,
	name: string,
	base: CFrame,
	offset: CFrame,
	size: Vector3,
	color: Color3,
	shape: Enum.PartType?,
	solid: boolean?,
	material: Enum.Material?
): Part
	local props: { [string]: any } = {
		Name = name,
		Size = size,
		CFrame = base * offset,
		Color = color,
		CanCollide = solid == true,
		CanQuery = false,
	}
	if shape then
		props.Shape = shape
	end
	if material then
		props.Material = material
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
	base: CFrame,
	y: number,
	diameter: number,
	height: number,
	color: Color3,
	solid: boolean?,
	material: Enum.Material?
): Part
	return put(
		make,
		parent,
		name,
		base,
		CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, diameter, diameter),
		color,
		CYL,
		solid,
		material
	)
end

-- Big corner pieces -----------------------------------------------------------------------------

local TREES: { [string]: Piece } = {}

function TREES.oak(make, parent, base, s, theme)
	put(make, parent, "Trunk", base, CFrame.new(0, 2.2 * s, 0), Vector3.new(1.2, 4.4, 1.2) * s, theme.trunk, nil, true)
	for i = 1, 3 do
		local size = (5.6 - i * 0.9) * s
		put(
			make,
			parent,
			"Leaves",
			base,
			CFrame.new(0, (3.6 + i * 1.5) * s, 0) * CFrame.Angles(0, math.rad(25 * i), math.rad(8)),
			Vector3.one * size,
			pick(theme.foliage, i),
			nil,
			false
		)
	end
end

function TREES.palm(make, parent, base, s, theme)
	-- Leaning trunk of three stacked blocks, a crown of flat leaves, two coconuts.
	for i = 0, 2 do
		put(
			make,
			parent,
			"Trunk",
			base,
			CFrame.new(i * 0.5 * s, (1.4 + i * 2.6) * s, 0) * CFrame.Angles(0, 0, math.rad(-6)),
			Vector3.new(1.1, 2.8, 1.1) * s,
			theme.trunk,
			nil,
			i == 0
		)
	end
	local top = CFrame.new(1.5 * s, 8.3 * s, 0)
	for i = 0, 4 do
		put(
			make,
			parent,
			"Leaf",
			base,
			top * CFrame.Angles(0, math.rad(72 * i), 0) * CFrame.new(0, 0, -2.2 * s) * CFrame.Angles(math.rad(18), 0, 0),
			Vector3.new(1.6, 0.35, 5) * s,
			pick(theme.foliage, i + 1)
		)
	end
	for _, dx in { -0.5, 0.5 } do
		put(
			make,
			parent,
			"Coconut",
			base,
			top * CFrame.new(dx * s, -0.7 * s, 0),
			Vector3.one * 0.8 * s,
			theme.trunk,
			BALL
		)
	end
end

function TREES.lolly(make, parent, base, s, theme)
	-- A giant lollipop: white stick, two-colour round candy.
	put(make, parent, "Stick", base, CFrame.new(0, 3 * s, 0), Vector3.new(0.8, 6, 0.8) * s, theme.trunk, nil, true)
	put(make, parent, "Candy", base, CFrame.new(0, 7.6 * s, 0), Vector3.one * 5.6 * s, pick(theme.foliage, 1), BALL)
	put(
		make,
		parent,
		"Swirl",
		base,
		CFrame.new(0, 7.6 * s, 0) * CFrame.Angles(0, 0, math.rad(35)),
		Vector3.new(5.8, 1.1, 5.8) * s,
		pick(theme.foliage, 2),
		BALL
	)
	put(
		make,
		parent,
		"Swirl",
		base,
		CFrame.new(0, 7.6 * s, 0) * CFrame.Angles(0, math.rad(90), math.rad(-35)),
		Vector3.new(5.8, 1.1, 5.8) * s,
		pick(theme.foliage, 3),
		BALL
	)
end

function TREES.tower(make, parent, base, s, theme)
	-- A toy tower: stacked blocks, a cone roof, two window slits.
	put(make, parent, "Wall", base, CFrame.new(0, 3 * s, 0), Vector3.new(4, 6, 4) * s, theme.trunk, nil, true)
	put(
		make,
		parent,
		"Ring",
		base,
		CFrame.new(0, 6.2 * s, 0),
		Vector3.new(4.8, 0.7, 4.8) * s,
		pick(theme.foliage, 1),
		nil,
		true
	)
	put(
		make,
		parent,
		"Roof",
		base,
		CFrame.new(0, 8.2 * s, 0) * CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(3.4, 3.4, 3.4) * s,
		pick(theme.foliage, 2)
	)
	put(
		make,
		parent,
		"Tip",
		base,
		CFrame.new(0, 10.4 * s, 0) * CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(1.4, 1.6, 1.4) * s,
		theme.accent[1]
	)
	for _, dx in { -1, 1 } do
		put(
			make,
			parent,
			"Window",
			base,
			CFrame.new(dx * 0.9 * s, 3.8 * s, -2.02 * s),
			Vector3.new(0.7, 1.5, 0.12) * s,
			theme.accent[3]
		)
	end
end

function TREES.crystal(make, parent, base, s, theme)
	-- A glowing crystal cluster on a small rock.
	put(
		make,
		parent,
		"Rock",
		base,
		CFrame.new(0, 0.7 * s, 0),
		Vector3.new(4, 1.4, 4) * s,
		pick(theme.stone, 1),
		nil,
		true
	)
	for i = 1, 4 do
		local h = (3 + (i % 3) * 1.8) * s
		local a = i * 1.7
		put(
			make,
			parent,
			"Crystal",
			base,
			CFrame.new(math.cos(a) * 0.9 * s, 1.4 * s + h / 2, math.sin(a) * 0.9 * s)
				* CFrame.Angles(math.rad(8 * (i - 2)), a, math.rad(6 * (2 - i))),
			Vector3.new(1.1, h, 1.1) * s,
			pick(theme.foliage, i),
			nil,
			false,
			NEON
		)
	end
end

-- Small props -------------------------------------------------------------------------------------

local PROPS: { [string]: Piece } = {}

function PROPS.bench(make, parent, base, s, theme)
	put(make, parent, "Seat", base, CFrame.new(0, 1.5 * s, 0), Vector3.new(5, 0.4, 1.5) * s, theme.post)
	put(
		make,
		parent,
		"Back",
		base,
		CFrame.new(0, 2.4 * s, 0.7 * s) * CFrame.Angles(math.rad(8), 0, 0),
		Vector3.new(5, 1.2, 0.3) * s,
		theme.post
	)
	for _, x in { -2.1, 2.1 } do
		put(make, parent, "Leg", base, CFrame.new(x * s, 0.75 * s, 0), Vector3.new(0.4, 1.5, 1.3) * s, theme.border)
	end
end

function PROPS.boulder(make, parent, base, s, theme)
	for i = 1, 3 do
		local size = s * (3 - i * 0.55)
		put(
			make,
			parent,
			"Chunk",
			base,
			CFrame.new(((i * 5) % 3 - 1) * 0.35 * s, size * 0.3, ((i * 7) % 3 - 1) * 0.35 * s)
				* CFrame.Angles(0.3 * i, i * 2.1, -0.25 * i),
			Vector3.new(size, size * 0.75, size * 0.9),
			pick(theme.stone, i),
			nil,
			i == 1
		)
	end
end

function PROPS.crate(make, parent, base, s, theme)
	put(
		make,
		parent,
		"Box",
		base,
		CFrame.new(0, 1.1 * s, 0),
		Vector3.one * 2.2 * s,
		theme.trunk,
		nil,
		true,
		Enum.Material.WoodPlanks
	)
	put(make, parent, "Band", base, CFrame.new(0, 1.1 * s, 0), Vector3.new(2.3, 0.4, 2.3) * s, theme.post)
end

function PROPS.bush(make, parent, base, s, theme)
	for i = 1, 3 do
		put(
			make,
			parent,
			"Bush",
			base,
			CFrame.new((i - 2) * 0.9 * s, 0.9 * s, (i % 2) * 0.5 * s),
			Vector3.one * (1.9 + (i % 2) * 0.5) * s,
			pick(theme.foliage, i),
			BALL
		)
	end
	put(
		make,
		parent,
		"Berry",
		base,
		CFrame.new(0.3 * s, 1.9 * s, -0.7 * s),
		Vector3.one * 0.5 * s,
		theme.accent[1],
		BALL
	)
end

function PROPS.umbrella(make, parent, base, s, theme)
	upCyl(make, parent, "Pole", base, 2.3 * s, 0.3 * s, 4.6 * s, theme.fence)
	for i = 0, 5 do
		put(
			make,
			parent,
			"Slice",
			base,
			CFrame.new(0, 4.4 * s, 0)
				* CFrame.Angles(0, math.rad(60 * i), 0)
				* CFrame.new(0, 0, -1.1 * s)
				* CFrame.Angles(math.rad(12), 0, 0),
			Vector3.new(1.3, 0.25, 2.3) * s,
			if i % 2 == 0 then theme.accent[1] else theme.fence
		)
	end
end

function PROPS.shell(make, parent, base, s, theme)
	put(make, parent, "Shell", base, CFrame.new(0, 0.7 * s, 0), Vector3.new(2.2, 1.4, 1.6) * s, theme.accent[1], BALL)
	put(make, parent, "Ridge", base, CFrame.new(0, 1.0 * s, -0.4 * s), Vector3.new(0.35, 1.3, 1.5) * s, theme.accent[4])
end

function PROPS.bucket(make, parent, base, s, theme)
	upCyl(make, parent, "Bucket", base, 0.9 * s, 1.8 * s, 1.8 * s, theme.accent[3])
	upCyl(make, parent, "Sand", base, 1.85 * s, 1.5 * s, 0.3 * s, theme.pad)
	put(
		make,
		parent,
		"Spade",
		base,
		CFrame.new(1.6 * s, 0.4 * s, 0) * CFrame.Angles(0, 0, math.rad(-20)),
		Vector3.new(0.3, 2.2, 0.8) * s,
		theme.accent[2]
	)
end

function PROPS.cupcake(make, parent, base, s, theme)
	upCyl(make, parent, "Wrapper", base, 0.9 * s, 2.2 * s, 1.8 * s, theme.accent[2])
	put(
		make,
		parent,
		"Frosting",
		base,
		CFrame.new(0, 2.2 * s, 0),
		Vector3.new(2.6, 1.8, 2.6) * s,
		theme.accent[1],
		BALL
	)
	put(
		make,
		parent,
		"Cherry",
		base,
		CFrame.new(0, 3.3 * s, 0),
		Vector3.one * 0.8 * s,
		Color3.fromRGB(255, 70, 90),
		BALL
	)
end

function PROPS.gumdrop(make, parent, base, s, theme)
	put(
		make,
		parent,
		"Gumdrop",
		base,
		CFrame.new(0, 1.2 * s, 0),
		Vector3.new(2.6, 2.4, 2.6) * s,
		pick(theme.accent, 2),
		BALL
	)
	put(make, parent, "Sugar", base, CFrame.new(0, 0.3 * s, 0), Vector3.new(2.8, 0.5, 2.8) * s, theme.fence)
end

function PROPS.candycane(make, parent, base, s, theme)
	for i = 0, 4 do
		put(
			make,
			parent,
			"Stripe",
			base,
			CFrame.new(0, (0.7 + i * 1.1) * s, 0),
			Vector3.new(0.8, 1.1, 0.8) * s,
			if i % 2 == 0 then theme.accent[1] else theme.fence
		)
	end
	for i = 0, 1 do
		put(
			make,
			parent,
			"Hook",
			base,
			CFrame.new((0.55 + i * 0.5) * s, (5.6 - i * 0.1) * s, 0),
			Vector3.new(0.8, 0.8, 0.8) * s,
			if i % 2 == 0 then theme.fence else theme.accent[1]
		)
	end
end

function PROPS.barrel(make, parent, base, s, theme)
	upCyl(make, parent, "Barrel", base, 1.2 * s, 2.2 * s, 2.4 * s, theme.trunk, true, Enum.Material.WoodPlanks)
	for _, y in { 0.5, 1.9 } do
		upCyl(make, parent, "Hoop", base, y * s, 2.3 * s, 0.25 * s, theme.post)
	end
end

function PROPS.torch(make, parent, base, s, theme)
	upCyl(make, parent, "Pole", base, 1.8 * s, 0.4 * s, 3.6 * s, theme.post)
	put(
		make,
		parent,
		"Flame",
		base,
		CFrame.new(0, 4.1 * s, 0),
		Vector3.new(1, 1.4, 1) * s,
		theme.accent[1],
		BALL,
		false,
		NEON
	)
end

function PROPS.orb(make, parent, base, s, theme)
	upCyl(make, parent, "Plinth", base, 0.4 * s, 1.8 * s, 0.8 * s, pick(theme.stone, 1))
	put(make, parent, "Orb", base, CFrame.new(0, 2.2 * s, 0), Vector3.one * 2.4 * s, theme.accent[1], BALL, false, NEON)
end

function PROPS.antenna(make, parent, base, s, theme)
	upCyl(make, parent, "Mast", base, 2.4 * s, 0.35 * s, 4.8 * s, theme.fence)
	put(
		make,
		parent,
		"Dish",
		base,
		CFrame.new(0, 4.8 * s, 0) * CFrame.Angles(math.rad(-35), 0, 0),
		Vector3.new(2.4, 0.4, 2.4) * s,
		theme.accent[3],
		CYL
	)
	put(
		make,
		parent,
		"Blink",
		base,
		CFrame.new(0, 5.4 * s, 0),
		Vector3.one * 0.5 * s,
		theme.accent[2],
		BALL,
		false,
		NEON
	)
end

function PROPS.log(make, parent, base, s, theme)
	put(
		make,
		parent,
		"Log",
		base,
		CFrame.new(0, 0.8 * s, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(1.6, 1.6, 4.6) * s,
		theme.trunk,
		CYL,
		true
	)
	put(
		make,
		parent,
		"Cap",
		base,
		CFrame.new(0, 1.7 * s, 0),
		Vector3.new(2.2, 0.5, 1.2) * s,
		pick(theme.foliage, 1),
		BALL
	)
end

function PROPS.mushroom(make, parent, base, s, theme)
	upCyl(make, parent, "Stem", base, 0.9 * s, 0.9 * s, 1.8 * s, theme.fence)
	put(make, parent, "Cap", base, CFrame.new(0, 2.1 * s, 0), Vector3.new(2.8, 1.8, 2.8) * s, theme.accent[1], BALL)
	for i = 1, 3 do
		put(
			make,
			parent,
			"Dot",
			base,
			CFrame.new(math.cos(i * 2.1) * 0.9 * s, 2.7 * s, math.sin(i * 2.1) * 0.9 * s),
			Vector3.one * 0.5 * s,
			theme.fence,
			BALL
		)
	end
end

function PROPS.flowerbed(make, parent, base, s, theme)
	put(make, parent, "Bed", base, CFrame.new(0, 0.3 * s, 0), Vector3.new(4.4, 0.6, 3) * s, theme.trunk)
	for i = 1, 6 do
		local x, z = ((i - 1) % 3 - 1) * 1.3 * s, ((i - 1) // 3 - 0.5) * 1.2 * s
		put(
			make,
			parent,
			"Stem",
			base,
			CFrame.new(x, 1.0 * s, z),
			Vector3.new(0.2, 0.8, 0.2) * s,
			Color3.fromRGB(70, 170, 60)
		)
		put(make, parent, "Flower", base, CFrame.new(x, 1.6 * s, z), Vector3.one * 0.8 * s, pick(theme.accent, i), BALL)
	end
end

function PROPS.lamp(make, parent, base, s, theme)
	upCyl(make, parent, "Pole", base, 3.2 * s, 0.4 * s, 6.4 * s, theme.post)
	put(
		make,
		parent,
		"Lamp",
		base,
		CFrame.new(0, 6.8 * s, 0),
		Vector3.one * 1.4 * s,
		theme.accent[2],
		BALL,
		false,
		NEON
	)
end

PlotDecor.trees = TREES
PlotDecor.props = PROPS

-- Pieces the Find The Pet map and the world scatter use for every theme.
local WORLD_KINDS: { [string]: Piece } = {
	tree = TREES.oak,
	boulder = PROPS.boulder,
	bush = PROPS.bush,
	log = PROPS.log,
	mushroom = PROPS.mushroom,
	flowerbed = PROPS.flowerbed,
	lamp = PROPS.lamp,
	bench = PROPS.bench,
}

-- Yard dressing -----------------------------------------------------------------------------------

-- Corner spots for big pieces, side spots for small ones (yard-local, -Z faces the entrance).
function PlotDecor.cornerSpots(half: number): { Vector3 }
	return {
		Vector3.new(-half + 3.5, 0, half - 3.5),
		Vector3.new(half - 3.5, 0, half - 3.5),
		Vector3.new(-half + 3.5, 0, -half + 5),
		Vector3.new(half - 3.5, 0, -half + 5),
		Vector3.new(-half + 3.5, 0, 0),
		Vector3.new(half - 3.5, 0, 0),
	}
end

function PlotDecor.sideSpots(half: number): { Vector3 }
	local x = half - 4.5
	return {
		Vector3.new(-x, 0, 8),
		Vector3.new(x, 0, 8),
		Vector3.new(-x, 0, -8),
		Vector3.new(x, 0, -8),
		Vector3.new(-x + 1, 0, half - 3),
		Vector3.new(x - 1, 0, half - 3),
	}
end

-- Checkered floor tiles in the theme's colours, kept off the table in the middle.
local function floor(make: PartMaker, parent: Instance, plotCFrame: CFrame, theme: Theme)
	local half = Config.PLOT_SIZE / 2
	local tile = 6
	local n = math.floor(Config.PLOT_SIZE / tile)
	local start = -half + tile / 2 + (Config.PLOT_SIZE - n * tile) / 2
	local keepOut = Config.TABLE_RADIUS + 2.5
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			if (ix + iz) % 2 == 0 then
				local x, z = start + ix * tile, start + iz * tile
				if math.sqrt(x * x + z * z) > keepOut + tile * 0.7 then
					put(
						make,
						parent,
						"Tile",
						plotCFrame,
						CFrame.new(x, 0.43, z),
						Vector3.new(tile - 0.5, 0.06, tile - 0.5),
						theme.accent[1]:Lerp(theme.pad, 0.72)
					)
				end
			end
		end
	end
end

-- `resets` grows the yard like Plot.build does: two big pieces, one more per reset.
function PlotDecor.yard(make: PartMaker, parent: Instance, plotCFrame: CFrame, theme: Theme, resets: number)
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. theme.id
	local half = Config.PLOT_SIZE / 2
	floor(make, folder, plotCFrame, theme)

	local treePiece = TREES[theme.tree] or TREES.oak
	local corners = PlotDecor.cornerSpots(half)
	for i = 1, math.min(#corners, 2 + resets) do
		-- face the yard centre
		local at = plotCFrame * CFrame.new(corners[i])
		local base = CFrame.lookAt(at.Position, plotCFrame.Position)
		treePiece(make, folder, base, 1 + (i % 3) * 0.12, theme)
	end

	local sides = PlotDecor.sideSpots(half)
	for i = 1, math.min(#sides, 1 + resets) do
		local kind = pick(theme.props, i)
		local piece = PROPS[kind] or PROPS.boulder
		local at = plotCFrame * CFrame.new(sides[i])
		piece(make, folder, CFrame.lookAt(at.Position, plotCFrame.Position), 1, theme)
	end
	folder.Parent = parent
	return folder
end

-- World dressing ----------------------------------------------------------------------------------

function PlotDecor.world(make: PartMaker, parent: Instance, params: DecorLayout.Params?): Folder
	local folder = Instance.new("Folder")
	folder.Name = "WorldDecor"
	local theme = PlotThemes.list[1]
	for _, spot in DecorLayout.spots(params) do
		local piece = WORLD_KINDS[spot.kind]
		if piece then
			piece(make, folder, CFrame.new(spot.x, 0, spot.z) * CFrame.Angles(0, spot.yaw, 0), spot.scale, theme)
		end
	end
	folder.Parent = parent
	return folder
end

return PlotDecor
