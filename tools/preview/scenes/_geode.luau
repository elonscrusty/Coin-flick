-- _geode: Pass C pictures. Specimens on stands in open ground, cavities facing the camera (-Z).
--   --set view=front|side|close   --set n=N (default 4)  --set lod=1  --set yaw=DEG  --set i=K (which specimen)
local C = lib("ctr")
C.boot({})
local GeodeModel = preview.shared("GeodeModel")
local KitModels = preview.shared("KitModels")
local n = tonumber(preview.args.n) or 4
local view = preview.args.view or "front"
local floor = Instance.new("Part")
floor.Size = Vector3.new(80, 1, 40)
floor.CFrame = CFrame.new(400, -0.5, 400)
floor.Color = Color3.fromRGB(150, 138, 118)
floor.Anchored = true
floor.Parent = workspace
local specs = {
	{ Mineral = "Amethyst", Formation = "Cluster", Modifier = "Natural", Mass = 2, Seed = 11 },
	{ Mineral = "Citrine", Formation = "Spire", Modifier = "Natural", Mass = 2, Seed = 23 },
	{ Mineral = "RoseQuartz", Formation = "TwinCore", Modifier = "Natural", Mass = 2, Seed = 47 },
	{ Mineral = "Celestite", Formation = "HollowBloom", Modifier = "Natural", Mass = 2, Seed = 35 },
	{ Mineral = "Fluorite", Formation = "Cluster", Modifier = "Natural", Mass = 2, Seed = 59 },
	{ Mineral = "EmberQuartz", Formation = "Spire", Modifier = "Natural", Mass = 2, Seed = 71 },
}
local gap = 6.5
local xs = {}
for i = 1, n do
	local x = 400 + (i - (n + 1) / 2) * gap
	xs[i] = x
	local spec = specs[(i - 1) % #specs + 1]
	local o = { Scale = 1, Lod = preview.args.lod == "1" }
	local m
	if (GeodeModel :: any).onStand then
		m = (GeodeModel :: any).onStand(spec, o)
		m:PivotTo(CFrame.new(x, 0, 400))
	else
		m = GeodeModel.build(spec, o)
		local st = KitModels.clone("Geode_Stand", 1)
		if st then
			st.Parent = workspace
			st:PivotTo(CFrame.new(x, 0, 400))
		end
		m:PivotTo(CFrame.new(x, 0.36, 400))
	end
	m.Parent = workspace
end
local mid = Vector3.new(400, 1.7, 400)
if view == "front" then
	C.cameraAt(mid, Vector3.new(0, 0.4, -22 - n * 2), 34)
elseif view == "close" then
	local x = xs[tonumber(preview.args.i) or 1]
	local yaw = math.rad(tonumber(preview.args.yaw) or 20)
	C.cameraAt(Vector3.new(x, 1.8, 400), Vector3.new(math.sin(yaw) * 6, 1.1, -math.cos(yaw) * 6), 40)
else
	local x = xs[tonumber(preview.args.i) or 1]
	local yaw = math.rad(tonumber(preview.args.yaw) or 45)
	C.cameraAt(Vector3.new(x, 1.7, 400), Vector3.new(math.sin(yaw) * 11, 1.8, -math.cos(yaw) * 11), 32)
end
if preview.args.hud ~= "1" then
	local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			g:Destroy()
		end
	end
end
