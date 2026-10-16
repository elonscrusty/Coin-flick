--!strict
-- The sunny world: lighting, grass, spawn, and the ring of table plots.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)

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

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Haze = 0
	atmosphere.Glare = 0.2
	atmosphere.Color = Color3.fromRGB(200, 230, 255)
	atmosphere.Decay = Color3.fromRGB(120, 180, 255)
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

	local terrain = workspace.Terrain
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = terrain

	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(512, 2, 512),
		Position = Vector3.new(0, -1, 0),
		Color = Color3.fromRGB(110, 210, 90),
	})
	ground.Parent = workspace

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(0, 0.5, 0)
	spawn.Color = Color3.fromRGB(255, 220, 80)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Parent = workspace

	tablesFolder = Instance.new("Folder")
	tablesFolder.Name = "Tables"
	tablesFolder.Parent = workspace

	Players.PlayerRemoving:Connect(World.releasePlot)
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
