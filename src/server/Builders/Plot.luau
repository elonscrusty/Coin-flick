--!strict
-- Builds a player's 3D yard: a colored pad, a low-poly fence with an open
-- entrance facing the middle of the map, a name arch, and trees. More trees
-- and flowers appear with every reset, so your plot grows as you play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)

local Plot = {}

-- Gate pillars this tall keep the name sign above the spawn camera's picture AND above the walk
-- view just outside the gate (tests/specs/Map.spec.luau projects both).
local ARCH_TOP = 20
-- Half the entrance width. Wide, so the pillars sit at the very edges of the walk view and the
-- table stays big; thin pillars so they never fill the picture.
local GATE_HALF = 11
local PILLAR_W = 0.5
local BAND_W = 0.7
local CAP_SIZE = 1.3
-- Arch pillars stay bright white in EVERY theme, so a brown or dark avatar never blends into them.
local PILLAR = Color3.fromRGB(255, 252, 245)
local PILLAR_CAP = Color3.fromRGB(255, 205, 50)
local TRUNK = Color3.fromRGB(120, 80, 45)
local LEAVES = {
	Color3.fromRGB(80, 200, 80),
	Color3.fromRGB(60, 180, 100),
	Color3.fromRGB(120, 220, 70),
}
local FLOWERS = {
	Color3.fromRGB(255, 90, 120),
	Color3.fromRGB(255, 220, 60),
	Color3.fromRGB(150, 120, 255),
	Color3.fromRGB(255, 150, 60),
}

type PartMaker = (props: { [string]: any }) -> Part

local function tree(make: PartMaker, parent: Instance, base: CFrame, size: number, leafColor: Color3)
	local trunk = make({
		Name = "Trunk",
		Size = Vector3.new(1.2, 4 * size, 1.2),
		CFrame = base * CFrame.new(0, 2 * size, 0),
		Color = TRUNK,
	})
	trunk.Parent = parent
	-- Chunky low-poly crown: two stacked, twisted blocks.
	for i, s in { 4.5, 3.2 } do
		local crown = make({
			Name = "Leaves",
			Size = Vector3.new(s, s, s) * size,
			CFrame = base * CFrame.new(0, (4 + i * 1.6) * size, 0) * CFrame.Angles(0, math.rad(25 * i), math.rad(8)),
			Color = leafColor,
			CanCollide = false,
		})
		crown.Parent = parent
	end
end

Plot.tree = tree
Plot.PILLAR = PILLAR
Plot.ARCH_TOP = ARCH_TOP
Plot.GATE_HALF = GATE_HALF
Plot.PILLAR_W = PILLAR_W
Plot.CAP_SIZE = CAP_SIZE
Plot.LEAVES = LEAVES
Plot.FLOWERS = FLOWERS

local function flower(make: PartMaker, parent: Instance, base: CFrame, color: Color3)
	local stem = make({
		Name = "Stem",
		Size = Vector3.new(0.25, 1, 0.25),
		CFrame = base * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(70, 170, 60),
		CanCollide = false,
	})
	stem.Parent = parent
	local head = make({
		Name = "Flower",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.8, 0.8),
		CFrame = base * CFrame.new(0, 1.2, 0),
		Color = color,
		CanCollide = false,
	})
	head.Parent = parent
end

-- `plotCFrame`: ground-level centre of the plot, with -Z facing the middle
-- of the map (that's where the entrance is).
function Plot.build(
	make: PartMaker,
	parent: Instance,
	plotCFrame: CFrame,
	theme: PlotThemes.Theme,
	ownerName: string,
	resets: number
)
	local half = Config.PLOT_SIZE / 2
	local folder = Instance.new("Folder")
	folder.Name = "Plot"

	local pad = make({
		Name = "Pad",
		Size = Vector3.new(Config.PLOT_SIZE, 0.4, Config.PLOT_SIZE),
		CFrame = plotCFrame * CFrame.new(0, 0.2, 0),
		Color = theme.pad,
	})
	pad.Parent = folder
	local border = make({
		Name = "Border",
		Size = Vector3.new(Config.PLOT_SIZE + 1.6, 0.3, Config.PLOT_SIZE + 1.6),
		CFrame = plotCFrame * CFrame.new(0, 0.15, 0),
		Color = theme.border,
	})
	border.Parent = folder

	-- Fence: posts + two rails on each side, with a gap for the entrance.
	local gap = GATE_HALF
	-- Real models when uploaded (Meshes.has), the Part fence below otherwise. Required here, not at the top:
	-- Meshes reads Enum values the offline tests lack.
	local Meshes = require(script.Parent.Parent.Systems.Meshes)
	local useModels = Meshes.has("CF_FenceSection") and Meshes.has("CF_FencePost")
	local function fenceRun(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local mid = (from + to) / 2
		local along = CFrame.lookAt(mid, to)
		local posts = math.max(1, math.floor(length / 4))
		if useModels then
			-- one invisible wall keeps players in; the models are looks only
			local wall = make({
				Name = "FenceWall",
				Size = Vector3.new(0.4, 3.2, length),
				CFrame = plotCFrame * (along + Vector3.new(0, 1.6, 0)),
				Transparency = 1,
				CanQuery = false,
			})
			wall.Parent = folder
			local dir = (to - from).Unit
			local tints = { Wood = theme.fence }
			local spacing = length / posts
			local pieces = math.ceil(spacing / 4)
			for i = 0, posts do
				local p = from:Lerp(to, i / posts)
				local post = Meshes.clone("CF_FencePost", plotCFrame * CFrame.new(p), tints)
				if post then
					post.Parent = folder
				end
				if i < posts then
					for k = 0, pieces - 1 do
						local at = p + dir * (spacing * (k + 0.5) / pieces)
						local section = Meshes.clone(
							"CF_FenceSection",
							plotCFrame * CFrame.fromMatrix(at, dir, Vector3.yAxis),
							tints,
							spacing / pieces / 4
						)
						if section then
							section.Parent = folder
						end
					end
				end
			end
			return
		end
		for _, y in { 1.2, 2.4 } do
			local rail = make({
				Name = "Rail",
				Size = Vector3.new(0.4, 0.4, length),
				CFrame = plotCFrame * (along + Vector3.new(0, y, 0)),
				Color = theme.fence,
			})
			rail.Parent = folder
		end
		for i = 0, posts do
			local p = from:Lerp(to, i / posts)
			local post = make({
				Name = "Post",
				Size = Vector3.new(0.8, 3.2, 0.8),
				CFrame = plotCFrame * CFrame.new(p + Vector3.new(0, 1.6, 0)),
				Color = theme.fence,
			})
			post.Parent = folder
		end
	end
	fenceRun(Vector3.new(-half, 0, half), Vector3.new(half, 0, half)) -- back
	fenceRun(Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half)) -- left
	fenceRun(Vector3.new(half, 0, -half), Vector3.new(half, 0, half)) -- right
	fenceRun(Vector3.new(-half, 0, -half), Vector3.new(-gap, 0, -half)) -- front left
	fenceRun(Vector3.new(gap, 0, -half), Vector3.new(half, 0, -half)) -- front right

	-- Name arch over the entrance. Tall, so from the spawn camera (outside the gate, behind your
	-- avatar) the sign is above the picture and the pillars stay beside the table, not in front of it.
	local pillarModels = Meshes.has("CF_ArchPillar")
	for _, x in { -gap, gap } do
		local pillar = make({
			Name = "Pillar",
			Size = Vector3.new(PILLAR_W, ARCH_TOP, PILLAR_W),
			CFrame = plotCFrame * CFrame.new(x, ARCH_TOP / 2, -half),
			Color = PILLAR,
			Transparency = if pillarModels then 1 else 0, -- the model is the look, this part stays as the solid
		})
		pillar.Parent = folder
		if pillarModels then
			local model = Meshes.clone("CF_ArchPillar", plotCFrame * CFrame.new(x, 0, -half), { Band = theme.border })
			if model then
				model.Parent = folder
				continue
			end
			pillar.Transparency = 0
		end
		-- Trim bands stay below the name sign (it hangs from ARCH_TOP - 2.9 up), never across its letters.
		for i = 1, 4 do
			local band = make({
				Name = "Band",
				Size = Vector3.new(BAND_W, 0.5, BAND_W),
				CFrame = plotCFrame * CFrame.new(x, i * 2.9, -half),
				Color = theme.border,
				CanCollide = false,
			})
			band.Parent = folder
		end
		local cap = make({
			Name = "Cap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * CAP_SIZE,
			CFrame = plotCFrame * CFrame.new(x, ARCH_TOP + 0.4, -half),
			Color = PILLAR_CAP,
			CanCollide = false,
		})
		cap.Parent = folder
	end
	local beam = make({
		Name = "NameSign",
		Size = Vector3.new(gap * 2 + 3, 2.6, 1),
		CFrame = plotCFrame * CFrame.new(0, ARCH_TOP - 1.6, -half),
		Color = theme.sign,
	})
	beam.Parent = folder
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.PixelsPerStud = 40
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.Parent = beam
		local label = Instance.new("TextLabel")
		-- Letters stay between the pillars, clear of the posts and anything at the sign ends.
		label.Size = UDim2.fromScale(0.84, 0.9)
		label.Position = UDim2.fromScale(0.08, 0.05)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = theme.signText
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(50, 35, 20)
		label.Text = `{ownerName}'s Coins`
		label.Parent = gui
	end

	-- Theme dressing: floor tiles, corner trees, side props. Grows with every reset.
	-- Required here, not at the top: PlotDecor reads Enum values, which the offline tests do not have.
	local PlotDecor = require(script.Parent.PlotDecor)
	PlotDecor.yard(make, folder, plotCFrame, theme, resets)

	folder.Parent = parent
end

Plot.flower = flower

return Plot
