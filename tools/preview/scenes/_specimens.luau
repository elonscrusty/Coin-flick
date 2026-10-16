-- _specimens: a sheet of GeodeModel.build specimens in open ground, one column per specimen
-- (C.fakeSpecimens) and one row per detail level: full (reveal/results/collection), Lod
-- (gallery shelf) and Tiny (back shelves). --set n=N specimens (default 5).
local C = lib("ctr")
C.boot({})
local GeodeModel = preview.shared("GeodeModel")
local n = tonumber(preview.args.n) or 5
local floor = Instance.new("Part")
floor.Size = Vector3.new(80, 1, 40)
floor.CFrame = CFrame.new(400, -0.5, 400)
floor.Color = Color3.fromRGB(176, 160, 130)
floor.Anchored = true
floor.Parent = workspace
for i, sp in C.fakeSpecimens(n) do
	for row, opts in { {}, { Lod = true }, { Tiny = true } } do
		local o = table.clone(opts)
		o.Scale = 1
		local m = GeodeModel.build(sp, o)
		m:PivotTo(CFrame.new(400 + (i - (n + 1) / 2) * 4, 0, 400 + (row - 2) * 5) * CFrame.Angles(0, math.rad(-20), 0))
		m.Parent = workspace
	end
end
if preview.args.display == "1" then
	-- Collection corner: decorative example geodes (GeodeModel.example) leaning 12 degrees on small plinths,
	-- cavities facing the viewer (-Z)
	for i, mineral in { "Amethyst", "Citrine", "Fluorite", "RoseQuartz", "Calcite" } do
		local x = 400 + (i - 3) * 3
		local plinth = Instance.new("Part")
		plinth.Size = Vector3.new(2.2, 0.5, 1.6)
		plinth.CFrame = CFrame.new(x, 0.25, 408)
		plinth.Color = Color3.fromRGB(70, 64, 60)
		plinth.Anchored = true
		plinth.Parent = workspace
		local m = GeodeModel.example(mineral, 40 + i, { Scale = 1.1, Tilt = 12 })
		m:PivotTo(CFrame.new(x, 0.5, 408))
		m.Parent = workspace
	end
	C.cameraAt(Vector3.new(400, 1.6, 408), Vector3.new(0, 1.5, -9), 40)
elseif preview.args.cam == "front" then
	-- level, straight-on view of the cavities (the specimens face -Z)
	C.cameraAt(Vector3.new(400, 1.6, 400), Vector3.new(0, 1, -24), 40)
else
	C.cameraAt(Vector3.new(400, 1.5, 400), Vector3.new(0, 9, -20), 50)
end
