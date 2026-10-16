--!strict
-- The sunny world: lighting, grass, spawn, and the ring of table plots.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)
local Plot = require(script.Parent.Parent.Builders.Plot)

local World = {}

local plotOwners: { [number]: Player } = {}
local tablesFolder: Folder

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end
World.makePart = makePart

function World.init()
	-- Always sunny.
	Lighting.ClockTime = 13.5
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(130, 120, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 140)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.5

	-- Cartoon sky: a thick bright-blue haze paints over the realistic default
	-- skybox and its clouds (no sky pictures needed). Tuned in Config.Sky.
	local sky = Config.Sky
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = sky.density
	atmosphere.Offset = sky.offset
	atmosphere.Haze = sky.haze
	atmosphere.Glare = 0
	atmosphere.Color = sky.color
	atmosphere.Decay = sky.decay
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = 0.25
	color.Contrast = 0.08
	color.Parent = Lighting

	-- No realistic 3D clouds (they looked off-style next to the chunky cartoon world).

	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(512, 2, 512),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(110, 210, 90),
	})
	ground.Parent = workspace
	World.decorate()

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, 26) -- the mega coin stands in the very middle
	spawn.Color = Color3.fromRGB(255, 220, 80)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = workspace

	tablesFolder = Instance.new("Folder")
	tablesFolder.Name = "Tables"
	tablesFolder.Parent = workspace

	Players.PlayerRemoving:Connect(World.releasePlot)
end

-- The park around the yards: a sandy plaza with paths to every yard, trees
-- between the yards, and a forest + flowers further out. Same every server.
function World.decorate()
	local folder = Instance.new("Folder")
	folder.Name = "Park"
	local rng = Random.new(7)
	local SAND = Color3.fromRGB(245, 222, 160)
	local plaza = makePart({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 46, 46),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = SAND,
	})
	plaza.Parent = folder
	local inner = 22
	local outer = Config.PLOT_RING_RADIUS - Config.PLOT_SIZE / 2
	for slot = 1, Config.MAX_PLOTS do
		local x, z = TableLayout.plotPosition(slot, Config.MAX_PLOTS, Config.PLOT_RING_RADIUS)
		local dir = Vector3.new(x, 0, z).Unit
		local mid = dir * ((inner + outer) / 2) + Vector3.new(0, 0.1, 0)
		local path = makePart({
			Name = "Path",
			Size = Vector3.new(6, 0.2, outer - inner + 2),
			CFrame = CFrame.lookAt(mid, mid + dir),
			Color = SAND,
		})
		path.Parent = folder
		-- Two trees in the gap between this yard and the next.
		local gapAngle = math.atan2(z, x) + math.pi / Config.MAX_PLOTS
		for _, radius in { Config.PLOT_RING_RADIUS - 6, Config.PLOT_RING_RADIUS + 10 } do
			local at = Vector3.new(math.cos(gapAngle) * radius, 0, math.sin(gapAngle) * radius)
			local leaves = Plot.LEAVES[rng:NextInteger(1, #Plot.LEAVES)]
			Plot.tree(makePart, folder, CFrame.new(at), rng:NextNumber(1.2, 1.6), leaves)
		end
	end
	-- Forest ring outside the yards.
	for _ = 1, 48 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(Config.PLOT_RING_RADIUS + 30, 200)
		local at = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local leaves = Plot.LEAVES[rng:NextInteger(1, #Plot.LEAVES)]
		Plot.tree(makePart, folder, CFrame.new(at) * CFrame.Angles(0, angle, 0), rng:NextNumber(1.3, 2.2), leaves)
	end
	-- Flower patches.
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(Config.PLOT_RING_RADIUS + 22, 190)
		local center = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local color = Plot.FLOWERS[rng:NextInteger(1, #Plot.FLOWERS)]
		for _ = 1, 5 do
			local offset = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			Plot.flower(makePart, folder, CFrame.new(center + offset), color)
		end
	end
	-- Bushes and chunky rocks just outside the yards, so the field is never empty.
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(Config.PLOT_RING_RADIUS + Config.PLOT_SIZE / 2 + 4, 150)
		local at = CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		if rng:NextNumber() < 0.6 then
			World.bush(folder, at, rng:NextNumber(1, 1.8), Plot.LEAVES[rng:NextInteger(1, #Plot.LEAVES)])
		else
			World.rock(folder, at, rng:NextNumber(1.2, 3), rng)
		end
	end
	-- Rolling green hills all round the edge close off the horizon.
	for i = 1, 26 do
		local angle = (i / 26) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local radius = rng:NextNumber(205, 235)
		local size = rng:NextNumber(60, 95)
		local hill = makePart({
			Name = "Hill",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			CFrame = CFrame.new(math.cos(angle) * radius, -size * 0.3, math.sin(angle) * radius),
			Color = if i % 2 == 0 then Color3.fromRGB(95, 200, 85) else Color3.fromRGB(125, 215, 80),
			CastShadow = false,
		})
		hill.Parent = folder
	end
	folder.Parent = workspace
end

-- A round, chunky bush: three squashed balls.
function World.bush(parent: Instance, base: CFrame, size: number, color: Color3)
	for _, piece in { { 0, 0, 2.2 }, { 1.1, 0.2, 1.6 }, { -1, 0.1, 1.7 } } do
		local ball = makePart({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * piece[3] * size,
			CFrame = base * CFrame.new(piece[1] * size, piece[3] * size * 0.35 + piece[2], 0),
			Color = color,
			CanCollide = false,
		})
		ball.Parent = parent
	end
end

-- A low-poly rock: a few tilted grey blocks, flat-shaded.
function World.rock(parent: Instance, base: CFrame, size: number, rng: Random)
	local greys = { Color3.fromRGB(170, 175, 185), Color3.fromRGB(150, 155, 168), Color3.fromRGB(195, 198, 205) }
	for i = 1, 3 do
		local s = size * (1.3 - i * 0.25)
		local block = makePart({
			Name = "Rock",
			Size = Vector3.new(s * 1.4, s, s * 1.1),
			CFrame = base
				* CFrame.new((i - 2) * size * 0.6, s * 0.35, rng:NextNumber(-0.3, 0.3) * size)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
			Color = greys[i],
		})
		block.Parent = parent
	end
end

function World.tablesFolder(): Folder
	return tablesFolder
end

function World.claimPlot(player: Player): number?
	for slot = 1, Config.MAX_PLOTS do
		if plotOwners[slot] == player then
			return slot
		end
	end
	for slot = 1, Config.MAX_PLOTS do
		if not plotOwners[slot] then
			plotOwners[slot] = player
			return slot
		end
	end
	return nil
end

function World.releasePlot(player: Player)
	for slot = 1, Config.MAX_PLOTS do
		if plotOwners[slot] == player then
			plotOwners[slot] = nil
		end
	end
end

-- Centre of a plot on the ground, and which way is "outwards" (away from the middle).
function World.plotCenter(slot: number): (Vector3, Vector3)
	local x, z = TableLayout.plotPosition(slot, Config.MAX_PLOTS, Config.PLOT_RING_RADIUS)
	local center = Vector3.new(x, 0, z)
	local outward = Vector3.new(x, 0, z).Unit
	return center, outward
end

return World
