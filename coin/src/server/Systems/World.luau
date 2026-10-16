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
local freeMarkers: { [number]: Model } = {}
local parkFolder: Folder? = nil

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
	spawn.Transparency = 1 -- the round welcome mat below is what you see
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Parent = workspace
	World.welcomeMat(Vector3.new(0, 0, 26))

	tablesFolder = Instance.new("Folder")
	tablesFolder.Name = "Tables"
	tablesFolder.Parent = workspace

	Players.PlayerRemoving:Connect(World.releasePlot)
end

-- An empty yard's marker, so every path ends somewhere: a pale pad, four corner posts and a
-- "FREE PLOT" sign beside the gate. It disappears while a player owns the yard (see claimPlot).
local function buildFreeMarker(slot: number, parent: Instance): Model
	local center, outward = World.plotCenter(slot)
	local base = CFrame.lookAt(center, center - outward)
	local half = Config.PLOT_SIZE / 2
	local model = Instance.new("Model")
	model.Name = `FreePlot{slot}`
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, collide: boolean?): Part
		local p = makePart({
			Name = name,
			Size = size,
			CFrame = base * offset,
			Color = color,
			CanCollide = collide == true,
			CanQuery = collide == true,
		})
		p.Parent = model
		return p
	end
	part(
		"Pad",
		Vector3.new(Config.PLOT_SIZE, 0.2, Config.PLOT_SIZE),
		CFrame.new(0, 0.1, 0),
		Color3.fromRGB(205, 240, 190)
	)
	part(
		"Trim",
		Vector3.new(Config.PLOT_SIZE + 1.6, 0.14, Config.PLOT_SIZE + 1.6),
		CFrame.new(0, 0.07, 0),
		Color3.fromRGB(255, 220, 90)
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				"Post",
				Vector3.new(1, 2.4, 1),
				CFrame.new(sx * (half - 1), 1.2, sz * (half - 1)),
				Color3.fromRGB(255, 250, 240)
			)
			part(
				"PostCap",
				Vector3.new(1.2, 0.5, 1.2),
				CFrame.new(sx * (half - 1), 2.6, sz * (half - 1)),
				Color3.fromRGB(255, 200, 40)
			)
		end
	end
	-- a gold coin trophy on a pedestal in the middle, so a free yard shines from far away
	local Meshes = require(script.Parent.Meshes) -- here: it reads Enum values the offline tests lack
	local trophy = Meshes.clone("CF_FreeStatue", base, nil, nil, true)
	if trophy then
		trophy.Parent = model
	else
		part("Pedestal", Vector3.new(4, 1.4, 4), CFrame.new(0, 0.9, 0), Color3.fromRGB(255, 250, 240), true)
		local statue = makePart({
			Name = "CoinStatue",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 4.2, 4.2),
			CFrame = base * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = Color3.fromRGB(255, 205, 40),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
		})
		statue.Parent = model
	end
	local balloonColors = {
		Color3.fromRGB(255, 90, 120),
		Color3.fromRGB(70, 170, 255),
		Color3.fromRGB(255, 210, 50),
		Color3.fromRGB(110, 220, 90),
	}
	local index = 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			index += 1
			local ball = makePart({
				Name = "Balloon",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 3.2,
				CFrame = base * CFrame.new(sx * (half - 1), 6, sz * (half - 1)),
				Color = balloonColors[index],
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			})
			ball.Parent = model
		end
	end
	part("SignPole", Vector3.new(0.6, 4.2, 0.6), CFrame.new(-11.5, 2.1, -half - 3), Color3.fromRGB(150, 100, 60), true)
	local board = part("Sign", Vector3.new(9, 3, 0.5), CFrame.new(-11.5, 4.9, -half - 3), Color3.fromRGB(255, 200, 40))
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.PixelsPerStud = 40
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.85)
		label.Position = UDim2.fromScale(0.05, 0.08)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(120, 70, 20)
		label.Text = "FREE PLOT"
		label.Parent = gui
	end
	model.Parent = parent
	return model
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
		freeMarkers[slot] = buildFreeMarker(slot, folder)
		-- Two trees in the gap between this yard and the next.
		local gapAngle = math.atan2(z, x) + math.pi / Config.MAX_PLOTS
		for _, radius in { Config.PLOT_RING_RADIUS - 6, Config.PLOT_RING_RADIUS + 10 } do
			local at = Vector3.new(math.cos(gapAngle) * radius, 0, math.sin(gapAngle) * radius)
			local leaves = Plot.LEAVES[rng:NextInteger(1, #Plot.LEAVES)]
			Plot.tree(makePart, folder, CFrame.new(at), rng:NextNumber(1.2, 1.6), leaves)
		end
	end
	-- Trees, rocks, bushes, logs, mushrooms and flower beds around the yards.
	local PlotDecor = require(script.Parent.Parent.Builders.PlotDecor) -- here, not at the top: it reads Enum values the offline tests lack
	PlotDecor.world(makePart, folder)
	-- Big cartoon scenery: coloured hills, fountain plaza, striped paths, flowers, sky clouds,
	-- balloons and floating islands (WorldArt, lazy for the same reason as PlotDecor).
	local WorldArt = require(script.Parent.Parent.Builders.WorldArt)
	WorldArt.hills(makePart, folder)
	WorldArt.plaza(makePart, folder)
	for slot = 1, Config.MAX_PLOTS do
		WorldArt.path(makePart, folder, slot, inner, outer - 14) -- stops short of the yard: ZOOM sees the front
	end
	WorldArt.sky(makePart, folder)
	folder.Parent = workspace
	parkFolder = folder
end

-- The spawn spot: a round mat (blue ring, white ring, gold middle) instead of a plain yellow slab.
function World.welcomeMat(at: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "WelcomeMat"
	local rings = {
		{ diameter = 14, color = Color3.fromRGB(70, 170, 255) },
		{ diameter = 11.5, color = Color3.fromRGB(255, 255, 255) },
		{ diameter = 9, color = Color3.fromRGB(255, 200, 40) },
		{ diameter = 5.5, color = Color3.fromRGB(255, 120, 190) },
	}
	for i, ring in rings do
		local disc = makePart({
			Name = `Mat{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25 + i * 0.08, ring.diameter, ring.diameter),
			CFrame = CFrame.new(at + Vector3.new(0, 0.1 + i * 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = ring.color,
			CanCollide = false,
		})
		disc.Parent = folder
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
			local marker = freeMarkers[slot]
			if marker then
				marker.Parent = nil -- the yard is taken, no "free" sign
			end
			return slot
		end
	end
	return nil
end

function World.releasePlot(player: Player)
	for slot = 1, Config.MAX_PLOTS do
		if plotOwners[slot] == player then
			plotOwners[slot] = nil
			local marker = freeMarkers[slot]
			if marker and parkFolder then
				marker.Parent = parkFolder
			end
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
