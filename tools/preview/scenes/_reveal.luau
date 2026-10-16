-- _reveal: the opened reveal halves beside the specimen, as RevealView ends (no UI, no hunt).
--   --set seed=N  --set mineral=Amethyst  --set d=12 (camera distance)
local C = lib("ctr")
C.boot({})
local GeodeModel = preview.shared("GeodeModel")
local KitModels = preview.shared("KitModels")
local floor = Instance.new("Part")
floor.Size = Vector3.new(80, 1, 40)
floor.CFrame = CFrame.new(400, -0.5, 400)
floor.Color = Color3.fromRGB(150, 138, 118)
floor.Anchored = true
floor.Parent = workspace
local spec = { Mineral = preview.args.mineral or "Amethyst", Formation = "Cluster", Modifier = "Natural", Mass = 2, Seed = tonumber(preview.args.seed) or 11, Rarity = "Rare" }
local m = GeodeModel.build(spec, { Scale = 1 })
m:PivotTo(CFrame.new(400, 0.2, 400))
m.Parent = workspace
local t = KitModels.template("Geode_Cluster_A")
if t then
	local lo, hi = KitModels.extents(t)
	print("cluster A extents", lo, hi, "kit loaded")
else
	print("no kit templates")
end
for _, h in GeodeModel.frontHalves(spec, 1) do
	local side = h:GetAttribute("Side")
	-- the same final pose as RevealView.pose at k = 1 (closed pose = model pivot * the half's own pivot)
	local R = 1.25
	local closed = CFrame.new(400, 0.2, 400) * h:GetPivot()
	h:PivotTo(closed * CFrame.new(side * 0.35 * R, -0.08 * R, 0.3 * R) * CFrame.Angles(0, -side * math.rad(140), 0))
	h.Parent = workspace
end
C.cameraAt(Vector3.new(400, 2.2, 400), Vector3.new(0, 0.3, -(tonumber(preview.args.d) or 12)), 38)
local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
if pg then
	for _, g in pg:GetChildren() do
		g:Destroy()
	end
end
