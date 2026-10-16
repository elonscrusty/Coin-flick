--!strict
-- Builds a player's 3D yard: a colored pad, a low-poly fence with an open
-- entrance facing the middle of the map, a name arch, and trees. More trees
-- and flowers appear with every reset, so your plot grows as you play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Plot = {}

local WOOD = Color3.fromRGB(150, 100, 60)
local FENCE = Color3.fromRGB(255, 250, 240)
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
	look: Config.TableLook,
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
		Color = look.top:Lerp(Color3.new(1, 1, 1), 0.55),
	})
	pad.Parent = folder
	local border = make({
		Name = "Border",
		Size = Vector3.new(Config.PLOT_SIZE + 1.6, 0.3, Config.PLOT_SIZE + 1.6),
		CFrame = plotCFrame * CFrame.new(0, 0.15, 0),
		Color = look.rim,
	})
	border.Parent = folder

	-- Fence: posts + two rails on each side, with a gap for the entrance.
	local gap = 6
	local function fenceRun(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local mid = (from + to) / 2
		local along = CFrame.lookAt(mid, to)
		for _, y in { 1.2, 2.4 } do
			local rail = make({
				Name = "Rail",
				Size = Vector3.new(0.4, 0.4, length),
				CFrame = plotCFrame * (along + Vector3.new(0, y, 0)),
				Color = FENCE,
			})
			rail.Parent = folder
		end
		local posts = math.max(1, math.floor(length / 4))
		for i = 0, posts do
			local p = from:Lerp(to, i / posts)
			local post = make({
				Name = "Post",
				Size = Vector3.new(0.8, 3.2, 0.8),
				CFrame = plotCFrame * CFrame.new(p + Vector3.new(0, 1.6, 0)),
				Color = FENCE,
			})
			post.Parent = folder
		end
	end
	fenceRun(Vector3.new(-half, 0, half), Vector3.new(half, 0, half)) -- back
	fenceRun(Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half)) -- left
	fenceRun(Vector3.new(half, 0, -half), Vector3.new(half, 0, half)) -- right
	fenceRun(Vector3.new(-half, 0, -half), Vector3.new(-gap, 0, -half)) -- front left
	fenceRun(Vector3.new(gap, 0, -half), Vector3.new(half, 0, -half)) -- front right

	-- Name arch over the entrance.
	for _, x in { -gap, gap } do
		local pillar = make({
			Name = "Pillar",
			Size = Vector3.new(1.6, 9, 1.6),
			CFrame = plotCFrame * CFrame.new(x, 4.5, -half),
			Color = WOOD,
		})
		pillar.Parent = folder
	end
	local beam = make({
		Name = "NameSign",
		Size = Vector3.new(gap * 2 + 3, 2.6, 1),
		CFrame = plotCFrame * CFrame.new(0, 9.6, -half),
		Color = look.rim,
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
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(50, 35, 20)
		label.Text = `{ownerName}'s Coins`
		label.Parent = gui
	end

	-- Two trees always; one more per reset (up to 4 extra), plus flowers.
	local treeSpots = {
		Vector3.new(-half + 3.5, 0, half - 3.5),
		Vector3.new(half - 3.5, 0, half - 3.5),
		Vector3.new(-half + 3.5, 0, -half + 5),
		Vector3.new(half - 3.5, 0, -half + 5),
		Vector3.new(-half + 3.5, 0, 0),
		Vector3.new(half - 3.5, 0, 0),
	}
	local treeCount = math.min(#treeSpots, 2 + resets)
	for i = 1, treeCount do
		local spot = treeSpots[i]
		tree(make, folder, plotCFrame * CFrame.new(spot), 1 + (i % 3) * 0.12, LEAVES[(i % #LEAVES) + 1])
	end
	local flowerCount = math.min(16, 4 + resets * 3)
	for i = 1, flowerCount do
		local side = if i % 2 == 0 then 1 else -1
		local z = -half + 2 + ((i - 1) // 2) * 4
		local spot = Vector3.new(side * (half - 1.4), 0.4, z)
		flower(make, folder, plotCFrame * CFrame.new(spot), FLOWERS[(i % #FLOWERS) + 1])
	end

	folder.Parent = parent
end

Plot.flower = flower

return Plot
