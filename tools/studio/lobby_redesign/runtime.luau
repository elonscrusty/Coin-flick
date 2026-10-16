-- Lobby redesign 2026-10-14 (thread "Lobby redesign"). Studio EDIT mode only. Safe to run again: the new dressing
-- lives in Workspace.LobbyRedesign (rebuilt each run), hooks are moved to absolute spots, old decor is MOVED (not
-- deleted) to ServerStorage.LobbyBackups.Removed_1014. Full backup: ServerStorage.LobbyBackups.Lobby_Before_Redesign_1014.
-- Prints a report: moved hooks, missing paths, kit models not found.

local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Run this in Edit mode (press Stop first)")
local SS = game:GetService("ServerStorage")
assert(SS:FindFirstChild("LobbyBackups") and SS.LobbyBackups:FindFirstChild("Lobby_Before_Redesign_1014"), "backup missing")
local KIT = SS:FindFirstChild("LobbyKitV2")
-- r30: one BasePart of a kit piece (an imported single mesh may arrive as a MeshPart or as a Model holding one)
local function kitPart(name: string): BasePart?
	local k = KIT and KIT:FindFirstChild(name, true)
	if k and k:IsA("BasePart") then
		return k
	end
	return if k then k:FindFirstChildWhichIsA("BasePart", true) else nil
end
local report = { moved = 0, missing = {}, nokit = {}, archived = 0 }

local function find(path: string): Instance?
	local cur: Instance? = workspace
	for seg in string.gmatch(path, "[^%.]+") do
		cur = cur and cur:FindFirstChild(seg)
	end
	return cur
end

-- the new dressing folder
local old = workspace:FindFirstChild("LobbyRedesign")
if old then
	old:Destroy()
end
local ROOT = Instance.new("Model")
ROOT.Name = "LobbyRedesign"
ROOT.Parent = workspace
local function sub(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = ROOT
	return f
end

-- 1. archive the old decor (moved, not deleted)
local bin = SS.LobbyBackups:FindFirstChild("Removed_1014") or Instance.new("Folder")
bin.Name = "Removed_1014"
bin.Parent = SS.LobbyBackups
for _, p in {
	"LobbyMeadow.Park.Hedge", "LobbyMeadow.Park.GateDressing", "LobbyMeadow.Park.Lamps", "LobbyMeadow.Park.TowerApproach",
	"LobbyMeadow.Park.Props", "LobbyMeadow.Park.ParkProps", "LobbyMeadow.Park.ParkTrees", "LobbyMeadow.Park.Topiary",
	"LobbyMeadow.Park.Dressing", "LobbyMeadow.Park.Clusters", "LobbyMeadow.Park.PathEdges", "LobbyMeadow.Park.Ponds",
	"LobbyMeadow.Park.SpawnSurround", "LobbyMeadow.Park.Paths", "LobbyMeadow.Shrine",
	"FTP_Lobby.Scenery.Ground.CleanFloor", "LobbyMeadow.Park.SpawnPlaza.SpawnFountain",
	"LobbyMeadow.Park.Hills", -- the inner hill ring buried the backs of the yards (Studio 10-15); cliffs + pines + outer hills frame the park
} do
	local inst = find(p)
	if inst then
		inst.Name = p
		inst.Parent = bin
		report.archived += 1
	end
end
-- round 18: every RollingHill_*_Decor_v2 under the outer hills goes too (there are several with the same name, so the
-- path lookup missed them): they made the seam, the row of rock blobs and the pale "white rock" in the top-down shots
do
	local hills = find("LobbyMeadow.Park.OuterHills")
	if hills then
		for _, d in hills:GetDescendants() do
			if string.match(d.Name, "^RollingHill_.*_Decor_v2$") and d.Parent then
				d.Parent = bin
				report.archived += 1
			end
		end
	end
end
-- the shop meshes the first run archived come back for the shop square
local shopRow = find("FTP_Lobby.ShopRow")
for _, n in { "ShopBackpack", "ShopTower" } do
	local b = bin:FindFirstChild("FTP_Lobby.ShopRow." .. n)
	if b and shopRow then
		b.Name = n
		b.Parent = shopRow
	end
end
do -- the event shop building is a bit smaller (once)
	local t = find("FTP_Lobby.ShopRow.ShopTower")
	if t and t:IsA("BasePart") and not t:GetAttribute("RedesignScaled") then
		t.Size *= 0.72
		t:SetAttribute("RedesignScaled", true)
	end
end
-- the hanging paw banner by the castle door (no flags)
do
	local tower = find("LobbyMeadow.Tower")
	local banner = tower and tower:FindFirstChild("Lobby_TowerBanner", true)
	if banner then
		banner.Parent = bin
		report.archived += 1
	end
end
-- old ambient emitters that sat on removed things (shrine, old mound, old pad and egg spots)
local fx = find("LobbyMeadow.Park.AmbientFX")
if fx then
	for _, e in fx:GetDescendants() do
		if e:IsA("BasePart") or e:IsA("Attachment") then
			local p = if e:IsA("Attachment") then e.WorldPosition else (e :: BasePart).Position
			local function near(x, z, r)
				return (Vector2.new(p.X, p.Z) - Vector2.new(x, z)).Magnitude < r
			end
			if near(34, 92, 6) or near(0, -104, 6) or near(0, 48, 6) or near(0, -48, 6) or near(0, 70, 6) then
				if e:IsA("Attachment") then
					e:Destroy() -- a copy is in the full backup
				else
					e.Parent = bin
				end
			elseif near(0, 108, 6) then
				if e:IsA("Attachment") then
					e.WorldPosition = Vector3.new(0, p.Y, 154)
				else
					(e :: BasePart).Position = Vector3.new(0, p.Y, 154) -- sparkles follow the fountain
				end
			end
		end
	end
end

-- ground height under (x, z), ignoring the new dressing and anything hovering
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(x: number, z: number): number
	local list = {}
	for _, p in { "LobbyMeadow.Ground", "FTP_Lobby.Collision.YardFloor" } do
		local g = find(p)
		if g then
			table.insert(list, g)
		end
	end
	if #list > 0 then
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = list
	else
		rp.FilterDescendantsInstances = { ROOT }
	end
	local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), rp)
	rp.FilterType = Enum.RaycastFilterType.Exclude
	return if hit then hit.Position.Y else 0
end
local G0 = groundY(0, 60)

-- 2. move the hooks. yaw = degrees clockwise from north (-Z); the "front" says how the object's facing is measured
local function bbox(inst: Instance): (CFrame, Vector3)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	local bp = inst :: BasePart
	return bp.CFrame, bp.Size
end
local function pivotOf(inst: Instance): CFrame
	return (inst :: any):GetPivot()
end
local function yawOfDir(d: Vector3): number
	return math.deg(math.atan2(d.X, -d.Z))
end
local function guiFront(inst: Instance): Vector3?
	for _, g in inst:GetDescendants() do
		if g:IsA("SurfaceGui") and g.Parent and g.Parent:IsA("BasePart") then
			local part = g.Parent :: BasePart
			return part.CFrame:VectorToWorldSpace(Vector3.fromNormalId(g.Face))
		end
	end
	return nil
end
local function place(inst: Instance, x: number, z: number, yaw: number?, front: string, y: number?): CFrame?
	local cf = bbox(inst)
	local center = cf.Position
	local delta = 0
	if yaw and front ~= "none" then
		local dir: Vector3?
		if front == "look" then
			dir = pivotOf(inst).LookVector
		elseif front == "gui" then
			dir = guiFront(inst) or pivotOf(inst).LookVector
		elseif string.sub(front, 1, 4) == "ref:" then
			local r = inst:FindFirstChild(string.sub(front, 5), true)
			if r and r:IsA("BasePart") then
				dir = r.Position - center
			end
		end
		if dir then
			delta = yaw - yawOfDir(dir * Vector3.new(1, 0, 1))
		end
	end
	local rot = CFrame.Angles(0, math.rad(-delta), 0)
	local pivot = pivotOf(inst)
	local off = pivot.Position - center
	local newCenter = Vector3.new(x, if y then G0 + y else center.Y, z)
	local newPivot = CFrame.new(newCenter + rot:VectorToWorldSpace(off)) * rot * pivot.Rotation
	local before = pivot
	;(inst :: any):PivotTo(newPivot)
	return newPivot * before:Inverse()
end

for _, h in DATA.hooks do
	local inst = find(h.path)
	if not inst then
		table.insert(report.missing, h.path)
		continue
	end
	local moveBy = place(inst, h.x, h.z, h.yaw, h.front, h.y)
	report.moved += 1
	-- the plot's gate arch rides along with its plot
	local plotNo = string.match(h.path, "Plots%.Plot(%d+)$")
	if plotNo and moveBy then
		local gate = find("LobbyMeadow.Park.PlotGates.Plot" .. plotNo .. "_Gate")
		if gate then
			(gate :: any):PivotTo(moveBy * pivotOf(gate))
		end
	end
end

-- the EggShop counter (and its prompt) stands at the ShopEgg front, long side along the shop front
do
	local shop = find("FTP_Lobby.Buildings.EggShop")
	local counter = shop and shop:FindFirstChild("Counter", true)
	local e = DATA.eggshop
	if shop and counter and counter:IsA("BasePart") then
		local a = math.rad(e.yaw)
		local fwd = Vector3.new(math.sin(a), 0, -math.cos(a))
		local spot = Vector3.new(e.x, G0 + counter.Size.Y / 2 + 0.6, e.z) + fwd * (e.d / 2 + 2.5)
		counter.CFrame = CFrame.new(spot) * CFrame.Angles(0, math.rad(-e.yaw), 0)
		local anchor = shop:FindFirstChild("ShopAnchor")
		if anchor and anchor:IsA("BasePart") then
			anchor.CFrame = CFrame.new(e.x, anchor.Position.Y, e.z)
			anchor.Transparency = 1
			anchor.CanCollide = false
		end
	else
		table.insert(report.missing, "FTP_Lobby.Buildings.EggShop.Counter")
	end
end

-- the FightBoard spot (FightBoard.luau builds the live board on a part with attribute FightBoard)
do
	local fb = Instance.new("Part")
	fb.Name = "FightBoardSpot"
	fb.Size = Vector3.new(16, 9, 0.4)
	fb.Transparency = 1
	fb.Anchored = true
	fb.CanCollide = false
	fb.CanQuery = false
	fb.CanTouch = false
	fb:SetAttribute("FightBoard", true)
	fb.CFrame = CFrame.new(DATA.fightboard.x, G0 + 9, DATA.fightboard.z) * CFrame.Angles(0, math.rad(-DATA.fightboard.yaw), 0)
	fb.Parent = ROOT
end

-- 3. ground: recolour and soft patches
local ground = find("LobbyMeadow.Ground")
if ground then
	for _, d in ground:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.fromHex("7cbd4e") -- round 26: brighter (carter: "too bland on mobile"); round 8 was 6a9a48
			d.Material = Enum.Material.SmoothPlastic
		end
	end
end
local function flat(parent, cf: CFrame, size: Vector3, color: string, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = Color3.fromHex(color)
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end
local DISC = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder lying flat
local fPatch = sub("GrassPatches")
-- round 22: ground layers 0.012 apart (tops): patches G0+0.012 (they no longer overlap each other, gen_build), zone
-- edges +0.024 / +0.036, zone tops +0.048, the TRAIN flagstone +0.06 / +0.072 / +0.084, paths from +0.11. Zones no
-- longer overlap each other either (smaller blend rings), so nothing flat shares a height with something it overlaps.
for _, g in DATA.patches do
	flat(fPatch, CFrame.new(g.x, G0 + 0.012 - 0.05, g.z) * DISC, Vector3.new(0.1, g.r * 2, g.r * 2), g.c, Enum.PartType.Cylinder)
end

-- 3b. zone grounds (round 6): a meadow under FIND, red-brown dirt under FIGHT, grey-blue flagstone under TRAIN, a
-- fresh lawn at the spawn; each is a soft two-tone disc under its plaza (paths and tiles sit on top)
local fZone = sub("ZoneGrounds")
for _, zn in DATA.zones do
	-- a wide two-step blend into the lawn (round 9: the tints read as small discs from above)
	for step, k in { 0.7, 0.4 } do
		local edge = Color3.fromHex(zn.c):Lerp(Color3.fromHex("7cbd4e"), k):ToHex()
		local rr = zn.r + (3 - step) * 3 -- round 23: *5 made FIND/FIGHT edge rings overlap the TRAIN ring (scan: z-fight)
		local base = if zn.name == "TrainFlagstone" then 0.036 else 0
		flat(fZone, CFrame.new(zn.x, G0 + base + 0.012 + step * 0.012 - 0.05, zn.z) * DISC, Vector3.new(0.1, rr * 2, rr * 2), edge, Enum.PartType.Cylinder).Name =
			zn.name .. "Edge" .. step
	end
	local top = flat(fZone, CFrame.new(zn.x, G0 + (if zn.name == "TrainFlagstone" then 0.084 else 0.048) - 0.05, zn.z) * DISC, Vector3.new(0.1, zn.r * 2, zn.r * 2), zn.c, Enum.PartType.Cylinder)
	top.Name = zn.name
	top.Material = (Enum.Material :: any)[zn.m]
	if zn.flowers then -- the FIND meadow is dotted with little flowers
		local rnd = Random.new(7)
		local cols = { "ffe27a", "ffffff" }
		for _ = 1, 60 do
			local a, rr = rnd:NextNumber(0, 2 * math.pi), zn.r * math.sqrt(rnd:NextNumber(0.05, 1))
			local x, z = zn.x + rr * math.cos(a), zn.z + rr * math.sin(a)
			local f = flat(fZone, CFrame.new(x, G0 + 0.3, z), Vector3.new(0.5, 0.5, 0.5), cols[rnd:NextInteger(1, #cols)], Enum.PartType.Ball)
			f.CastShadow = false
		end
	end
end
-- yards: green grass (carter 2026-10-15: "supposed to be green like grass"), a touch richer than the lawn outside
local soil = 0
for k = 1, 6 do
	local plot = find("FTP_Lobby.Plots.Plot" .. k)
	if plot then
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "YardSoil" and d.Size.Y <= 2 and d.Size.X >= 40 and d.Size.Z >= 40 then
				d.Color = Color3.fromHex("88c855")
				d.Material = Enum.Material.Grass
				soil += 1
			end
		end
	end
end
print("[LobbyRedesign] yard floors set to green grass: " .. soil)
-- round 9: crop-row ridges on each yard's soil (pets stand on them fine) and a bigger owner sign. The name sign's
-- text part (PlotSign) was wider than its plaque (SignPlaque), so the name floated; both grow 1.5x and line up.
local rows, signs = 0, 0
for k = 1, 6 do
	local plot = find("FTP_Lobby.Plots.Plot" .. k)
	if not plot then
		continue
	end
	for _, d in plot:GetDescendants() do -- round 9 rows sat under the lawn decals; round 10 rebuilds them on a soil slab
		if (d.Name == "CropRow" or d.Name == "YardSoil" or d.Name == "YardCrop") and d.Parent and not plot:GetAttribute("RedesignRows14") then
			d:Destroy()
		end
	end
	-- round 17: earlier runs laid a new slab (and new beds) on top of the last run's slab every time (Studio: the floor
	-- count grew 6 -> 24). Keep the lowest slab and the lowest copy of each bed piece; the rest go.
	do
		local lowest = math.huge
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "YardSoil" then
				lowest = math.min(lowest, d.Position.Y)
			end
		end
		local rowLow = math.huge
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "YardSoil" then
				if d.Position.Y > lowest + 0.01 then
					d:Destroy()
				else
					d:SetAttribute("RedesignRows14", true)
				end
			elseif d:IsA("BasePart") and d.Name == "CropRow" then
				rowLow = math.min(rowLow, d.Position.Y)
			end
		end
		-- round 18: beds from a later run sit 0.2 higher (and 1 stud over) on the stacked slab; keep the lowest set
		local ridgeTop = -math.huge
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "CropRow" then
				if d.Position.Y > rowLow + 0.15 then
					d:Destroy()
				elseif d:GetAttribute("CropRow") then
					ridgeTop = math.max(ridgeTop, d.Position.Y + d.Size.Y / 2)
				end
			end
		end
		if ridgeTop > -math.huge then
			for _, c in plot:GetDescendants() do
				if c:IsA("Model") and c.Name == "YardCrop" then
					local ccf, csz = c:GetBoundingBox()
					local lift = (ccf.Position.Y - csz.Y / 2) - ridgeTop
					if lift > 0.05 then
						c:PivotTo(c:GetPivot() - Vector3.new(0, lift, 0))
					end
				end
			end
		end
	end
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "YardSoil" and d.Size.Y <= 2 and d.Size.X >= 40 and d.Size.Z >= 40 and not d:GetAttribute("RedesignRows14") then
			d:SetAttribute("RedesignRows14", true)
			local slab = Instance.new("Part")
			slab.Name = "YardSoil"
			slab.Anchored = true
			slab.CanCollide = true -- round 11: flush and solid, so the yard-lift raycast and players stand on it
			slab.CanQuery = true
			slab.CanTouch = false
			slab.Material = Enum.Material.Grass -- a clean grass top so lawn decals and zone tints can't show through
			slab.Color = Color3.fromHex("88c855")
			slab.Size = Vector3.new(d.Size.X - 1, 0.1, d.Size.Z - 1)
			slab.CFrame = d.CFrame * CFrame.new(0, d.Size.Y / 2 + 0.05, 0)
			slab.Parent = d.Parent
			slab:SetAttribute("RedesignRows14", true)
			-- two small garden beds along the fence sides (crops sit on them); the middle stays open grass for pets
			local n = 7
			for _, r in { 1, n } do
				local off = (r - (n + 1) / 2) * (d.Size.Z - 10) / (n - 1)
				local ridge = Instance.new("Part")
				ridge.Name = "CropRow"
				ridge.Anchored = true
				ridge.CanCollide = false
				ridge.CanQuery = false
				ridge.CanTouch = false
				ridge.Material = Enum.Material.Ground
				ridge.Color = Color3.fromHex("7e5634")
				ridge.Size = Vector3.new(d.Size.X - 10, 0.35, 2.4)
				ridge.CFrame = d.CFrame * CFrame.new(0, d.Size.Y / 2 + 0.27, off)
				ridge.Parent = d.Parent
				ridge:SetAttribute("CropRow", true) -- crops go on these beds (below)
				local edge = Instance.new("Part") -- a low wooden edge round the bed
				edge.Name = "CropRow"
				edge.Anchored = true
				edge.CanCollide = false
				edge.CanQuery = false
				edge.CanTouch = false
				edge.Material = Enum.Material.WoodPlanks
				edge.Color = Color3.fromHex("a0703f")
				edge.Size = Vector3.new(d.Size.X - 9, 0.3, 3.2)
				edge.CFrame = ridge.CFrame * CFrame.new(0, -0.08, 0)
				edge.Parent = d.Parent
				rows += 1
			end
		end
	end
	plot:SetAttribute("RedesignRows14", true)
	local plaque = plot:FindFirstChild("SignPlaque", true)
	local text = plot:FindFirstChild("PlotSign", true)
	if plaque and plaque:IsA("BasePart") and text and text:IsA("BasePart") and not plaque:GetAttribute("RedesignBig") then
		plaque:SetAttribute("RedesignBig", true)
		local cf = plaque.CFrame
		plaque.Size = Vector3.new(plaque.Size.X * 1.5, plaque.Size.Y * 1.5, plaque.Size.Z)
		plaque.CFrame = cf + Vector3.new(0, plaque.Size.Y / 6, 0) -- grow upward, keep the bottom edge
		text.Size = Vector3.new(plaque.Size.X - 0.6, plaque.Size.Y - 0.5, text.Size.Z)
		text.CFrame = plaque.CFrame * CFrame.new(0, 0, -(plaque.Size.Z / 2 + text.Size.Z / 2 + 0.02))
		-- keep the text on the side the plaque already faced
		if (text.CFrame.Position - cf.Position):Dot(cf.LookVector) < 0 then
			text.CFrame = plaque.CFrame * CFrame.new(0, 0, plaque.Size.Z / 2 + text.Size.Z / 2 + 0.02) * CFrame.Angles(0, math.pi, 0)
		end
		local gui = text:FindFirstChildWhichIsA("SurfaceGui")
		if gui then
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
		end
		signs += 1
	end
end
print(("[LobbyRedesign] crop rows %d, bigger yard signs %d"):format(rows, signs))

-- 4. paths (round 6: wider, cobblestone top, dark border), each on its own hair-thin layer (no z-fighting)
local fPath = sub("Paths")
local PATH_SAND = "efe0ad" -- r30: carter's old lobby path colour (warm cream sand)
for i, pth in DATA.paths do
	local pts = pth.pts
	-- r30 (carter: "the pathway looks awful"; his old shot): ONE plain smooth cream-sand strip, a little wider, no border
	-- strip, no stripes; low white edge stones are added below
	for layer = 2, 2 do
		local w = pth.w + 2
		-- yard spurs are narrow wooden boardwalks; the main walks are cobblestone
		-- round 13: each road leans toward its zone (sand to FIND, red clay to FIGHT, blue-grey to TRAIN)
		local ROAD = {} -- r29i (runner: "one warm sand path with dark edge stones"): every walk is the same sand; r29h cbb88c/c4a990/9eb0be
		local col = PATH_SAND -- r30: every walk and yard spur the same cream sand (r29i cfc4a2 cobble, dark edges)
		-- round 25 (runner: "brown outlines look like cut-outs"): the border is a pale stone curb
		local mat = Enum.Material.SmoothPlastic
		-- round 24: identical strips can overlap without flicker, so every border shares one height and each road colour
		-- gets its own band 0.02 apart (0.004 per path was too thin at a distance)
		local TOPBAND = {}
		local y = if layer == 1 then G0 + 0.06 else G0 + 0.08 + (TOPBAND[col] or 0) * 0.02
		for k = 1, #pts do
			local a = Vector3.new(pts[k][1], y, pts[k][2])
			flat(fPath, CFrame.new(a) * DISC, Vector3.new(0.1, w, w), col, Enum.PartType.Cylinder).Material = mat
			if k < #pts then
				local b = Vector3.new(pts[k + 1][1], y, pts[k + 1][2])
				local len = (b - a).Magnitude
				flat(fPath, CFrame.lookAt((a + b) / 2, b), Vector3.new(w, 0.1, len), col).Material = mat
			end
		end
	end
	-- round 9: colour lines to follow (one per spoke; the main walk carries all three from the spawn)
	if false and pth.arrows then -- r29i (runner, three rounds: "the coloured lanes read as stripes"): lines off
		local lines = if pth.arrows == "f2c230" then { { -3, "f0a020" }, { 0, "e0443a" }, { 3, "2fa7d6" } } else { { 0, pth.arrows } }
		local LINEBAND = { f0a020 = 0, e0443a = 1, ["2fa7d6"] = 2 }
		for _, ln in lines do
			local y = G0 + 0.18 + (LINEBAND[ln[2]] or 0) * 0.02 -- round 24: one band per line colour, 0.02 apart
			for k = 1, #pts - 1 do
				local a = Vector3.new(pts[k][1], y, pts[k][2])
				local b = Vector3.new(pts[k + 1][1], y, pts[k + 1][2])
				local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.new(ln[1], 0, 0)
				-- r29e (runner: "rainbow stripes loud"): the lines are softer, a third of the way to the sand colour
				flat(fPath, cf, Vector3.new(1.1, 0.1, (b - a).Magnitude + 0.9), Color3.fromHex(ln[2]):Lerp(Color3.fromHex("c6b894"), 0.6):ToHex()) -- r29h: quieter still
			end
		end
	end
	-- round 7: zone-coloured chevrons down the middle of each spoke, pointing out to the zone
	if false and pth.arrows then -- round 10: chevrons off (they read as forks next to the colour lines)
		local y = G0 + 0.2 + i * 0.002
		local walked, nextAt = 0, 8
		for k = 1, #pts - 1 do
			local a = Vector3.new(pts[k][1], y, pts[k][2])
			local b = Vector3.new(pts[k + 1][1], y, pts[k + 1][2])
			local len = (b - a).Magnitude
			while nextAt <= walked + len and len > 0 do
				local at = a:Lerp(b, (nextAt - walked) / len)
				local look = CFrame.lookAt(at, at + (b - a))
				for _, side in { -1, 1 } do
					local arm = flat(fPath, look * CFrame.Angles(0, math.rad(side * 40), 0) * CFrame.new(side * 1.3, 0, 0),
						Vector3.new(3.6, 0.1, 1.1), pth.arrows)
					arm.Material = Enum.Material.SmoothPlastic
				end
				nextAt += 10
			end
			walked += len
		end
	end
end

-- round 7: two ponds by the castle (water, stone rim, lily pads)
local fPond = sub("Ponds")
for _, pd in DATA.ponds do
	local y = G0
	flat(fPond, CFrame.new(pd.x, y + 0.08, pd.z) * DISC, Vector3.new(0.1, pd.r * 2 + 2, pd.r * 2 + 2), "8d877f", Enum.PartType.Cylinder).Material =
		Enum.Material.Slate
	local water = flat(fPond, CFrame.new(pd.x, y + 0.14, pd.z) * DISC, Vector3.new(0.1, pd.r * 2 - 0.6, pd.r * 2 - 0.6), "3d8fd6",
		Enum.PartType.Cylinder)
	water.Material = Enum.Material.SmoothPlastic -- r29j: glass read cyan
	local n = 18
	for k = 0, n - 1 do
		local a = k / n * 2 * math.pi
		local pos = Vector3.new(pd.x + (pd.r - 0.2) * math.sin(a), y + 0.5, pd.z - (pd.r - 0.2) * math.cos(a))
		local rock = flat(fPond, CFrame.lookAt(pos, Vector3.new(pd.x, pos.Y, pd.z)), Vector3.new(2 * math.pi * pd.r / n + 0.4, 1, 1.4), "9a958e")
		rock.Material = Enum.Material.Slate
		rock.CanCollide = true
	end
	for k = 0, 3 do
		local a = k * 1.7 + pd.x
		local pad = flat(fPond, CFrame.new(pd.x + math.cos(a) * pd.r * 0.5, y + 0.2, pd.z + math.sin(a) * pd.r * 0.5) * DISC,
			Vector3.new(0.1, 2.4, 2.4), "58b83a", Enum.PartType.Cylinder)
		pad.Material = Enum.Material.SmoothPlastic
	end
end

-- 4b. r30: low white edge stones along both sides of every walk (carter's old shot), one every 3.6 studs, skipped where
-- the spot is on another walk or a plaza (junctions stay open). No collision, so nobody trips on them.
do
	local segs = {}
	for _, pth in DATA.paths do
		for k = 1, #pth.pts - 1 do
			table.insert(segs, { a = Vector2.new(pth.pts[k][1], pth.pts[k][2]), b = Vector2.new(pth.pts[k + 1][1], pth.pts[k + 1][2]), r = (pth.w + 2) / 2 })
		end
	end
	local function onWalk(p: Vector2): boolean
		for _, sg in segs do
			local ab = sg.b - sg.a
			local t = if ab.Magnitude > 0 then math.clamp((p - sg.a):Dot(ab) / ab.Magnitude ^ 2, 0, 1) else 0
			if (p - (sg.a + ab * t)).Magnitude < sg.r + 0.2 then
				return true
			end
		end
		for _, pz in DATA.plazas do
			if (p - Vector2.new(pz.x, pz.z)).Magnitude < pz.r + 1.5 then
				return true
			end
		end
		return false
	end
	local n = 0
	for _, pth in DATA.paths do
		local off = (pth.w + 2) / 2 + 0.45
		local carry = 0
		for k = 1, #pth.pts - 1 do
			local a = Vector2.new(pth.pts[k][1], pth.pts[k][2])
			local b = Vector2.new(pth.pts[k + 1][1], pth.pts[k + 1][2])
			local len = (b - a).Magnitude
			if len < 1e-3 then
				continue
			end
			local dir = (b - a).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			local d = carry
			while d < len do
				local c = a + dir * d
				for _, sgn in { -1, 1 } do
					local p = c + side * off * sgn
					if not onWalk(p) then
						local y = groundY(p.X, p.Y)
						local at = CFrame.lookAt(Vector3.new(p.X, y + 0.2, p.Y), Vector3.new(p.X + dir.X, y + 0.2, p.Y + dir.Y))
						local kc = kitPart("PathCurb_Stone_v1")
						if kc then -- r30: kit 1015j curb stone (long side along the walk)
							local st = kc:Clone()
							local ls = math.max(st.Size.X, st.Size.Z)
							st.Size = st.Size * (1.5 / ls)
							st.CFrame = at * (if st.Size.X > st.Size.Z then CFrame.Angles(0, math.rad(90), 0) else CFrame.new())
								* CFrame.new(0, st.Size.Y / 2 - 0.25, 0)
							st.Anchored, st.CanCollide, st.CanQuery, st.CanTouch = true, false, false, false
							st.Name = "EdgeStone"
							st.Parent = fPath
						else
							local st = flat(fPath, at, Vector3.new(0.8, 0.5, 1.5), "f4f2ea")
							st.Name = "EdgeStone"
							st.CastShadow = true
						end
						n += 1
					end
				end
				d += 3.6
			end
			carry = d - len
		end
	end
	print("[LobbyRedesign] path edge stones: " .. n)
end

-- 5. plazas: grout disc + rings of peach tiles (two tones), above the paths
local fPlaza = sub("Plazas")
for _, pz in DATA.plazas do
	local y = G0 + 0.3 -- round 23: up 0.1 so the path colour lines have room below
	flat(fPlaza, CFrame.new(pz.x, y, pz.z) * DISC, Vector3.new(0.12, pz.r * 2 + 1.2, pz.r * 2 + 1.2), PATH_SAND, Enum.PartType.Cylinder) -- r29e: warm stone grout (was orange b87a4c)
	local ring = 0
	local r = 5.7
	while r + 2.7 <= pz.r + 0.3 do
		ring += 1
		local n = math.max(6, math.floor(2 * math.pi * r / 6.5))
		for k = 0, n - 1 do
			local a = (k + (ring % 2) * 0.5) / n * 2 * math.pi
			local len = 2 * math.pi * r / n - 0.45
			local tone = PATH_SAND -- r30: plain plazas like the old lobby (no tile pattern); r29i 9e8c6c / ad9a78 -- r29e (runner: "plaza floor orange/red up close"): sandstone; round 28 c07c4a/d1925e
			-- round 29 (scan: ZFIGHT 24): straight tiles on a circle overlap their neighbours near the inner edge, so the
			-- two tones sit 0.02 apart (same-colour overlaps are fine, different colours need 0.02)
			local pos = Vector3.new(pz.x + r * math.sin(a), y + 0.08, pz.z - r * math.cos(a))
			flat(fPlaza, CFrame.lookAt(pos, Vector3.new(pz.x, pos.Y, pz.z)) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(5.4, 0.12, len), tone)
		end
		r += 6
	end
	flat(fPlaza, CFrame.new(pz.x, y + 0.12, pz.z) * DISC, Vector3.new(0.12, 5.4, 5.4), PATH_SAND, Enum.PartType.Cylinder) -- round 29: above both tile tones
	local pd = kitPart("PlazaPaver_Disc_v1")
	if pd then -- r30: kit 1015j round paver disc over the plain cream floor (no collision)
		local d = pd:Clone()
		local k = (pz.r * 2 - 1) / math.max(d.Size.X, d.Size.Z)
		d.Size = Vector3.new(d.Size.X * k, math.min(d.Size.Y * k, 0.3), d.Size.Z * k)
		d.CFrame = CFrame.new(pz.x, y + 0.2 + d.Size.Y / 2, pz.z)
		d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		d.Name = "PlazaPaverDisc"
		d.Parent = fPlaza
	end
	if pz.ring then -- zone colour border
		local n = math.floor(2 * math.pi * pz.r / 4)
		for k = 0, n - 1 do
			local a = k / n * 2 * math.pi
			local pos = Vector3.new(pz.x + (pz.r + 0.2) * math.sin(a), y + 0.14, pz.z - (pz.r + 0.2) * math.cos(a))
			flat(fPlaza, CFrame.lookAt(pos, Vector3.new(pz.x, pos.Y, pz.z)) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(1.0, 0.4, 2 * math.pi * pz.r / n - 1.2), "f4f2ea") -- r30: low white edge stones, gaps between -- r29i: brick-stone border tinted by the zone (red read pink)
		end
	end
end

-- 5b. shop square floor inlay (round 7): a purple ring round the fountain, a gold ring further out and gold diamonds
-- pointing down the four walks. r30: off (carter: plain paths and plazas like the old lobby)
if false then
	local y = G0 + 0.46
	local function band(r: number, wdt: number, col: string)
		local n = math.floor(2 * math.pi * r / 3)
		for k = 0, n - 1 do
			local a = k / n * 2 * math.pi
			local pos = Vector3.new(r * math.sin(a), y, -r * math.cos(a))
			flat(fPlaza, CFrame.lookAt(pos, Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(wdt, 0.1, 2 * math.pi * r / n + 0.05), col)
		end
	end
	band(17.5, 1.6, Color3.fromHex("8a4fd8"):Lerp(Color3.fromHex("8a7a68"), 0.8):ToHex()) -- r29h: a softer lilac (runner: purple stripe loud)
	band(31, 1.2, Color3.fromHex("d6a73a"):Lerp(Color3.fromHex("8a7a68"), 0.6):ToHex()) -- r29j: stone, not a yellow lane
	for k = 0, 3 do
		local a = math.rad(90 * k)
		local pos = Vector3.new(25 * math.sin(a), y, -25 * math.cos(a))
		flat(fPlaza, CFrame.new(pos) * CFrame.Angles(0, math.rad(45 - 90 * k), 0), Vector3.new(3.6, 0.1, 3.6), "d6a73a").Name = "InlayDiamond"
	end
end

-- 6. kit clones (trees, lamps, flowers, cliffs): sit the bottom on the ground, a little sunk
-- round 7: prefer the Blender _v3 re-exports (calm colours baked in) over _v2, and fall back from the zone colour
-- variants to the old species when the hero batch isn't imported yet
local FALLBACK = { Tree_Round_Autumn_v1 = "Tree_AutumnOrange", Tree_Round_BlueGreen_v1 = "Tree_Pine_B_v2",
	Tree_Round_Golden_v1 = "Tree_Olive", WallTower_Stone_v1 = "Cliff_Natural_B" }
local function kitModel(name: string): Instance?
	if not KIT then
		return nil
	end
	local v3 = string.gsub(name, "_v2$", "_v3")
	return (v3 ~= name and KIT:FindFirstChild(v3, true)) or KIT:FindFirstChild(name, true)
		or (FALLBACK[name] and kitModel(FALLBACK[name]))
end
-- round 30: Blender kit 1015j (tools/blender/lobby_kit_1015j.py) replaces the tinted cliffs and the thin pines when it
-- is imported: each old piece name maps to its new pieces (picked by spot, so neighbours vary), scaled to the old
-- piece's height so the plan's spacing still holds. Missing kit = the old piece, as before.
local PREFER = {
	Cliff_Natural_A = { "RockWall_A_v1", "RockWall_C_v1" },
	Cliff_Natural_B = { "RockWall_B_v1", "RockWall_D_v1" },
	Tree_Pine_A_v2 = { "Pine_Tall_v1", "Pine_Mid_v1" },
	Tree_Pine_B_v2 = { "Pine_Mid_v1", "Pine_Tall_v1", "Pine_Small_v1" },
	Tree_DarkGreen = { "Pine_Small_v1", "Pine_Mid_v1" },
	Tree_Round_B_v2 = { "Tree_RoundChunky_v1" },
}
local kitUsed: { [string]: number } = {}
local function preferred(name: string, x: number, z: number): (Instance?, number)
	local list = PREFER[name]
	if not (list and KIT) then
		return nil, 1
	end
	local pick = list[math.floor(math.abs(x * 7.3 + z * 13.1)) % #list + 1]
	local new = KIT:FindFirstChild(pick, true)
	if not new then
		return nil, 1
	end
	kitUsed[pick] = (kitUsed[pick] or 0) + 1
	local old = kitModel(name)
	local function height(i: Instance): number
		return if i:IsA("Model") then i:GetExtentsSize().Y elseif i:IsA("BasePart") then i.Size.Y else 0
	end
	local hOld, hNew = if old then height(old) else 0, height(new)
	return new, if hOld > 0 and hNew > 0 then hOld / hNew else 1
end
local function clone(name: string, x: number, z: number, yaw: number, s: number, lift: number?, parent: Instance)
	local pref, fit = preferred(name, x, z)
	local src = pref or kitModel(name)
	if not src then
		report.nokit[name] = true
		return
	end
	s *= fit
	local c = src:Clone()
	if c:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = name
		c.Parent = m
		m.PrimaryPart = c
		c = m
	end
	local m = c :: Model
	if s ~= 1 then
		m:ScaleTo(m:GetScale() * s)
	end
	m:PivotTo(CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(-yaw), 0))
	local cf, size = m:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	m:PivotTo(m:GetPivot() + Vector3.new(0, groundY(x, z) + (lift or 0) - 0.3 - bottom, 0))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = parent
end
local fDecor = sub("Decor")
for _, d in DATA.decor do
	clone(d.m, d.x, d.z, d.yaw, d.s, nil, fDecor)
end
-- round 25 (runner: "orange trees clip lamp posts"): the plan sees trunks, not crowns, so a tree whose crown
-- touches a lamp steps away from it, 1.5 studs at a time (up to 9)
do
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	for _, lamp in fDecor:GetChildren() do
		if not (lamp:IsA("Model") and string.find(lamp.Name, "^LampPost")) then
			continue
		end
		local lcf, lsz = lamp:GetBoundingBox()
		for _ = 1, 6 do
			local trees = {}
			for _, t in fDecor:GetChildren() do
				if t:IsA("Model") and (string.find(t.Name, "^Tree_") or string.find(t.Name, "^Pine_")) then
					table.insert(trees, t)
				end
			end
			op.FilterDescendantsInstances = trees
			local hit: Model? = nil
			for _, hp in workspace:GetPartBoundsInBox(lcf, lsz, op) do
				local t = hp:FindFirstAncestorWhichIsA("Model")
				while t and t.Parent ~= fDecor do
					t = t:FindFirstAncestorWhichIsA("Model")
				end
				if t then
					hit = t
					break
				end
			end
			if not hit then
				break
			end
			local away = hit:GetPivot().Position - lcf.Position
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
			hit:PivotTo(hit:GetPivot() + away * 1.5)
		end
	end
end
-- 6b. plaza props (round 6): built stand-ins, no asset ids. REPLACE with kit meshes when they exist.
local fProps = sub("PlazaProps")
local function part(parent, cf: CFrame, size: Vector3, col: string, mat: Enum.Material?, shape: Enum.PartType?, collide: boolean?)
	local p = flat(parent, cf, size, col, shape)
	p.CastShadow = true
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CanCollide = collide == true
	return p
end
local function fire(at: BasePart, blue: boolean)
	local f = Instance.new("Fire")
	f.Size = 4
	f.Heat = 6
	if blue then
		f.Color = Color3.fromHex("5fc4ef")
		f.SecondaryColor = Color3.fromHex("2b6fd6")
	end
	f.Parent = at
	local l = Instance.new("PointLight")
	l.Color = if blue then Color3.fromHex("8fd8ff") else Color3.fromHex("ffb347")
	l.Range = if blue then 12 else 8 -- r29e (runner: "plaza tile red-pink from the pillar glow"): a smaller warm glow
	l.Brightness = if blue then 1.5 else 0.7
	l.Parent = at
end
local function brazier(m, cf: CFrame, blue: boolean)
	part(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(1.8, 3, 1.8), "8d877f", Enum.Material.Slate, nil, true)
	part(m, cf * CFrame.new(0, 3.3, 0) * DISC, Vector3.new(0.9, 3.4, 3.4), "5a554f", Enum.Material.Slate, Enum.PartType.Cylinder, true)
	local coal = part(m, cf * CFrame.new(0, 3.8, 0) * DISC, Vector3.new(0.2, 2.6, 2.6), if blue then "2b6fd6" else "ff7a2b",
		Enum.Material.Neon, Enum.PartType.Cylinder)
	fire(coal, blue)
end
local function planter(m, cf: CFrame, col: string, mat: Enum.Material)
	part(m, cf * CFrame.new(0, 0.9, 0), Vector3.new(4.4, 1.8, 4.4), col, mat, nil, true)
	part(m, cf * CFrame.new(0, 1.85, 0), Vector3.new(3.8, 0.2, 3.8), "6b4a2b", Enum.Material.Ground)
	part(m, cf * CFrame.new(0, 3.1, 0), Vector3.new(3.4, 2.8, 3.4), "4f8a35", Enum.Material.Grass, Enum.PartType.Ball)
	local flowers = { "e0443a", "ffe27a", "ffffff", "f08a2b" }
	for k = 0, 5 do
		local a = k / 6 * 2 * math.pi
		part(m, cf * CFrame.new(math.cos(a) * 1.5, 3.4 + (k % 2) * 0.5, math.sin(a) * 1.5), Vector3.new(0.8, 0.8, 0.8),
			flowers[k % 4 + 1], nil, Enum.PartType.Ball)
	end
end
local PROPS: { [string]: (Model, CFrame) -> () } = {
	P_EggCrate = function(m, cf)
		part(m, cf * CFrame.new(0, 1.2, 0), Vector3.new(4, 2.4, 4), "a0703f", Enum.Material.WoodPlanks, nil, true)
		part(m, cf * CFrame.new(0, 2.45, 0), Vector3.new(4.3, 0.3, 4.3), "7a5230", Enum.Material.Wood)
		local cols = { "fff1c9", "a9ddf7", "b9ebb0", "ffe27a" }
		for k = 0, 3 do
			local a = k * math.pi / 2 + 0.6
			local e = part(m, cf * CFrame.new(math.cos(a) * 0.9, 3.5, math.sin(a) * 0.9), Vector3.new(1.5, 1.95, 1.5), cols[k + 1],
				nil, Enum.PartType.Ball)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = e
		end
	end,
	P_HayBale = function(m, cf)
		part(m, cf * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(4.2, 3.2, 3.2), "e3c25a",
			Enum.Material.Fabric, Enum.PartType.Cylinder, true)
		for _, dz in { -1.2, 1.2 } do
			part(m, cf * CFrame.new(0, 1.6, dz) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.3, 3.3, 3.3), "b8923a", nil,
				Enum.PartType.Cylinder)
		end
	end,
	P_Brazier = function(m, cf)
		brazier(m, cf, false)
	end,
	P_Brazier_Blue = function(m, cf)
		brazier(m, cf, true)
	end,
	P_Bench_Stone = function(m, cf)
		for _, dx in { -2.2, 2.2 } do
			part(m, cf * CFrame.new(dx, 0.8, 0), Vector3.new(1, 1.6, 1.6), "8d877f", Enum.Material.Slate, nil, true)
		end
		part(m, cf * CFrame.new(0, 1.9, 0), Vector3.new(6, 0.7, 2), "b9b0a2", Enum.Material.Slate, nil, true)
	end,
	P_Planter = function(m, cf)
		planter(m, cf, "a0703f", Enum.Material.WoodPlanks)
	end,
	P_StonePlanter = function(m, cf)
		planter(m, cf, "9aa3ad", Enum.Material.Slate)
	end,
	P_PetBowl = function(m, cf)
		part(m, cf * CFrame.new(0, 0.35, 0) * DISC, Vector3.new(0.7, 2.2, 2.2), "e0443a", nil, Enum.PartType.Cylinder, true)
		part(m, cf * CFrame.new(0, 0.72, 0) * DISC, Vector3.new(0.1, 1.7, 1.7), "8a5a2b", Enum.Material.Pebble, Enum.PartType.Cylinder)
	end,
	P_Bench_Wood = function(m, cf)
		for _, dx in { -2.3, 2.3 } do
			part(m, cf * CFrame.new(dx, 0.8, 0), Vector3.new(0.8, 1.6, 1.8), "5e4a37", Enum.Material.Wood, nil, true)
		end
		part(m, cf * CFrame.new(0, 1.75, 0), Vector3.new(6, 0.5, 2), "a0703f", Enum.Material.WoodPlanks, nil, true)
		part(m, cf * CFrame.new(0, 3, 0.85), Vector3.new(6, 1.6, 0.4), "a0703f", Enum.Material.WoodPlanks, nil, true)
	end,
	P_SignPost = function(m, cf)
		-- round 15: the spawn's big direction post (runner: "FIND/FIGHT/TRAIN board at the spawn, big outlined signs").
		-- Each arm points at its place, ends in an arrow tip and carries the zone name on both sides.
		-- round 23 (runner: "far too large, blocks the view"): everything at 0.6 size
		local S = 0.6
		part(m, cf * CFrame.new(0, 8 * S, 0), Vector3.new(2.2, 16, 2.2) * S, "7a5230", Enum.Material.Wood, nil, true)
		part(m, cf * CFrame.new(0, 16.5 * S, 0), Vector3.new(3, 1, 3) * S, "d6a73a", nil, nil, true)
		local base = cf.Position
		-- round 22: three arms, all above lamp height (the low SHOPS arm hit a lamp; the shop square is straight ahead)
		local AIM = { { "🥚 FIND", "f0a020", -100, -36 }, { "⚔️ FIGHT", "e0443a", 100, -36 }, { "⭐ TRAIN", "2fa7d6", 0, -112 } }
		for k, t in AIM do
			local dir = Vector3.new(t[3] - base.X, 0, t[4] - base.Z)
			if dir.Magnitude < 20 then
				continue -- the post already stands at this place
			end
			local at = base + Vector3.new(0, (16.2 - k * 2.6) * S, 0) + dir.Unit * 5.4 * S
			local arm = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.rad(90), 0) -- X runs along the arm
			local b = part(m, arm, Vector3.new(10, 3, 0.6) * S, t[2], Enum.Material.SmoothPlastic)
			part(m, arm, Vector3.new(10.4, 3.4, 0.4) * S, "ffffff", Enum.Material.SmoothPlastic) -- white outline
			local tip = part(m, arm * CFrame.new(5.6 * S, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(2.4, 2.4, 0.58) * S, t[2],
				Enum.Material.SmoothPlastic)
			tip.Name = "ArmTip"
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local gui = Instance.new("SurfaceGui")
				gui.Face = face
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 40
				gui.LightInfluence = 0
				gui.Parent = b
				local l = Instance.new("TextLabel")
				l.BackgroundTransparency = 1
				l.Size = UDim2.fromScale(0.9, 0.84)
				l.Position = UDim2.fromScale(0.05, 0.08)
				l.Text = t[1]
				l.TextScaled = true
				l.Font = Enum.Font.FredokaOne
				l.TextColor3 = Color3.new(1, 1, 1)
				local st = Instance.new("UIStroke")
				st.Thickness = 4
				st.Color = Color3.fromHex("2b1a0e")
				st.Parent = l
				l.Parent = gui
			end
		end
	end,
	P_PetBall = function(m, cf)
		part(m, cf * CFrame.new(0, 0.8, 0), Vector3.new(1.6, 1.6, 1.6), "2fa7d6", nil, Enum.PartType.Ball, true)
		part(m, cf * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.4, 1.7, 1.7), "ffe27a", nil,
			Enum.PartType.Cylinder)
	end,
}
-- round 13: the Blender props batch replaces some stand-ins when it is in LobbyKitV2
-- round 16: the Blender hub props (blender_lobby_hub_1015) for the shop square stalls and the spawn's balloon cart
local KIT_PROP = { P_PetBowl = "PetBowl_v1", P_PetStatue = "PetStatue_Plaza_v1", P_FruitStall = "FruitStall_v1",
	P_TreatStall = "MarketStall_Treats_v1", P_BalloonCart = "BalloonCart_v1",
	-- round 18: Blender kit 1015b (blender_lobby_kit_1015b)
	P_HatchNest = "HatchNest_Big_v1", P_HuntBoard = "HuntBoard_v1", P_Dummy = "TrainingDummy_Straw_v1",
	P_HayBale = "HayBale_Round_v1", P_EggCrate = "EggCrate_Stack_v1",
	-- round 20: Blender kit 1015c
	P_Bench_Wood = "Bench_Park_v1", P_Planter = "Planter_Round_v1" }
-- writes big two-sided words on a flat board face (the hunt board's blank plate)
local function faceWords(b: BasePart, words: string)
	local sz = b.Size
	local faces = if sz.X <= sz.Y and sz.X <= sz.Z then { Enum.NormalId.Left, Enum.NormalId.Right }
		elseif sz.Y <= sz.Z then { Enum.NormalId.Top, Enum.NormalId.Bottom }
		else { Enum.NormalId.Front, Enum.NormalId.Back }
	for _, f in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = b
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.92, 0.88)
		l.Position = UDim2.fromScale(0.04, 0.06)
		l.Text = words
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = Color3.fromHex("ffe27a")
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromHex("2b1a0e")
		st.Parent = l
		l.Parent = gui
	end
end
local HUNT_WORDS = "🥚 EGG HUNT\nStand on a pad to play!"
PROPS.P_HatchNest = function(m, cf) -- stand-in (REPLACE: HatchNest_Big_v1)
	part(m, cf * CFrame.new(0, 1, 0) * DISC, Vector3.new(2, 13, 13), "c9a061", Enum.Material.Fabric, Enum.PartType.Cylinder, true)
	for k, col in { "ffd23f", "4fc3f7", "7bd96a", "ff8a3d", "b98cf0", "5ad1c0" } do
		local a = k * math.pi / 3
		part(m, cf * CFrame.new(math.cos(a) * 3.6, 2.6, math.sin(a) * 3.6), Vector3.new(2.6, 3.4, 2.6), col, nil, Enum.PartType.Ball)
	end
end
PROPS.P_HuntBoard = function(m, cf) -- stand-in (REPLACE: HuntBoard_v1)
	for _, dx in { -3.2, 3.2 } do
		part(m, cf * CFrame.new(dx, 3, 0), Vector3.new(0.6, 6, 0.6), "7a5230", Enum.Material.Wood, nil, true)
	end
	local b = part(m, cf * CFrame.new(0, 4, 0), Vector3.new(6.6, 3.4, 0.4), "a0703f", Enum.Material.WoodPlanks, nil, true)
	faceWords(b, HUNT_WORDS)
end
PROPS.P_Dummy = function(m, cf) -- stand-in (REPLACE: TrainingDummy_Straw_v1); round head, no face
	part(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(0.5, 3, 0.5), "7a5230", Enum.Material.Wood, nil, true)
	part(m, cf * CFrame.new(0, 3.6, 0), Vector3.new(2, 2.4, 1.4), "e3c25a", Enum.Material.Fabric, nil, true)
	part(m, cf * CFrame.new(0, 5.4, 0), Vector3.new(1.5, 1.5, 1.5), "e3c25a", Enum.Material.Fabric, Enum.PartType.Ball, true)
end
-- stand-ins until the hub props are imported (REPLACE: FruitStall_v1, MarketStall_Treats_v1, BalloonCart_v1)
local function stall(m, cf: CFrame, w: number, roof: string, goods: { string })
	part(m, cf * CFrame.new(0, 1.6, 0), Vector3.new(w, 3.2, 3.2), "a0703f", Enum.Material.WoodPlanks, nil, true)
	for _, dx in { -w / 2 + 0.4, w / 2 - 0.4 } do
		part(m, cf * CFrame.new(dx, 4, 1.2), Vector3.new(0.5, 8, 0.5), "7a5230", Enum.Material.Wood, nil, true)
	end
	part(m, cf * CFrame.new(0, 8.2, 0.4) * CFrame.Angles(math.rad(-14), 0, 0), Vector3.new(w + 1, 0.4, 4.6), roof, Enum.Material.Fabric)
	for k, col in goods do
		local x = -w / 2 + 1 + (k - 0.5) * (w - 2) / #goods
		part(m, cf * CFrame.new(x, 3.7, -0.6), Vector3.new(1.2, 1.2, 1.2), col, nil, Enum.PartType.Ball)
	end
end
PROPS.P_FruitStall = function(m, cf)
	stall(m, cf, 9, "f0a020", { "e0443a", "ffe27a", "7bd96a", "f08a2b", "e0443a" })
end
PROPS.P_TreatStall = function(m, cf)
	stall(m, cf, 7.4, "2fa7d6", { "dc9a78", "ffe27a", "dc9a78", "ffe27a" })
end
PROPS.P_BalloonCart = function(m, cf)
	part(m, cf * CFrame.new(0, 1.8, 0), Vector3.new(4.5, 2.2, 2.6), "2fa7d6", nil, nil, true)
	for _, dx in { -1.6, 1.6 } do
		part(m, cf * CFrame.new(dx, 0.7, 1.4) * DISC, Vector3.new(0.4, 1.4, 1.4), "5e4a37", nil, Enum.PartType.Cylinder)
	end
	for k, col in { "e0443a", "ffe27a", "4fc3f7", "7bd96a", "b98cf0" } do
		local a = k * 2 * math.pi / 5
		part(m, cf * CFrame.new(math.cos(a) * 1.2, 8.4 + (k % 2) * 0.8, math.sin(a) * 1.2), Vector3.new(1.6, 2, 1.6), col, nil, Enum.PartType.Ball)
	end
	part(m, cf * CFrame.new(0, 5.2, 0), Vector3.new(0.12, 6.4, 0.12), "ffffff")
end
local function placeKit(name: string, x: number, z: number, yaw: number, parent: Instance, y: number?): Model?
	local src = kitModel(name)
	if not src then
		return nil
	end
	local c = src:Clone()
	if c:IsA("BasePart") then
		local w = Instance.new("Model")
		w.Name = name
		c.Parent = w
		w.PrimaryPart = c
		c = w
	end
	local m = c :: Model
	m:PivotTo(CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(-yaw), 0))
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, (y or groundY(x, z)) - (cf.Position.Y - size.Y / 2), 0))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	for _, d in m:GetDescendants() do -- round 18: kit parts named *_Glow light up (GardenLantern_v1_Glow)
		if d:IsA("BasePart") and string.find(d.Name, "_Glow", 1, true) then
			d.Material = Enum.Material.Neon
			d.Color = Color3.fromHex("e8b450") -- r29h: a warm glow that doesn't blow out on a phone
		end
	end
	m.Parent = parent
	return m
end
PROPS.P_PetStatue = function(m, cf) -- stand-in: a stone plinth with a round stone pet (REPLACE: PetStatue_Plaza_v1)
	part(m, cf * CFrame.new(0, 1.5, 0), Vector3.new(5, 3, 5), "9a958e", Enum.Material.Slate, nil, true)
	part(m, cf * CFrame.new(0, 5, 0), Vector3.new(3.6, 4, 3.6), "b9b0a2", Enum.Material.Slate, Enum.PartType.Ball, true)
end
for _, pr in DATA.props do
	local km = KIT_PROP[pr.m] and placeKit(KIT_PROP[pr.m], pr.x, pr.z, pr.yaw, fProps)
	if km then
		if pr.m == "P_HuntBoard" then
			local face = km:FindFirstChild("HuntBoard_v1_Face", true)
			if face and face:IsA("BasePart") then
				faceWords(face, HUNT_WORDS)
			end
		end
		continue
	end
	local build = PROPS[pr.m]
	if not build then
		report.nokit[pr.m] = true
		continue
	end
	local m = Instance.new("Model")
	m.Name = pr.m
	build(m, CFrame.new(pr.x, groundY(pr.x, pr.z), pr.z) * CFrame.Angles(0, math.rad(-pr.yaw), 0))
	m.Parent = fProps
end

-- round 20 (kit 1015c): stone rosettes where the four walks enter the shop square (they replace the gold diamonds),
-- and a big one in the middle of the spawn plaza
do
	local placed = 0
	for k = 0, 3 do
		local a = math.rad(90 * k)
		local t = placeKit("ShopSquare_Tile_v1", 27.5 * math.sin(a), -27.5 * math.cos(a), 90 * k, fPlaza, G0 + 0.54)
		if t then
			t:ScaleTo(t:GetScale() * 0.42) -- round 22: smaller and further out, clear of the stalls and statues
			local cf, size = t:GetBoundingBox()
			t:PivotTo(t:GetPivot() + Vector3.new(0, G0 + 0.54 - (cf.Position.Y - size.Y / 2), 0))
			placed += 1
		end
	end
	if placed == 4 then
		for _, d in fPlaza:GetChildren() do
			if d.Name == "InlayDiamond" then
				d:Destroy()
			end
		end
	end
	local sp = placeKit("ShopSquare_Tile_v1", 0, 140, 0, fPlaza, G0 + 0.54)
	if sp then -- round 22: 12 across, inside the clear spot the plan keeps for it (bushes stood on the full-size one)
		sp:ScaleTo(sp:GetScale() * 0.6)
		local cf, size = sp:GetBoundingBox()
		sp:PivotTo(sp:GetPivot() + Vector3.new(0, G0 + 0.54 - (cf.Position.Y - size.Y / 2), 0))
	end
end

-- round 13: Blender crops along the two outer rows of each yard (small, no collision; skipped if not imported)
for k = 1, 6 do
	local plot = find("FTP_Lobby.Plots.Plot" .. k)
	if not plot or plot:GetAttribute("RedesignCrops14") then
		continue
	end
	plot:SetAttribute("RedesignCrops14", true)
	for _, ridge in plot:GetDescendants() do
		if ridge:IsA("BasePart") and ridge:GetAttribute("CropRow") then
			local half = (ridge.Size.X - 2) / 2
			local step = 0
			for xx = -half, half, 4 do
				step += 1
				local cropName = if step % 2 == 0 then "CropPlant_Carrot_v1" else "CropPlant_Sprout_v1"
				local w = (ridge.CFrame * CFrame.new(xx, ridge.Size.Y / 2, 0)).Position
				local crop = placeKit(cropName, w.X, w.Z, step * 37, ridge.Parent :: Instance, w.Y)
				if crop then
					crop.Name = "YardCrop"
					for _, q in crop:GetDescendants() do
						if q:IsA("BasePart") then
							q.CanCollide = false
							q.CanQuery = false
						end
					end
				end
			end
		end
	end
end

local fEdge = sub("EdgeCliffs")
for _, d in DATA.cliffs do
	clone(d.m, d.x, d.z, d.yaw, d.s, d.lift, fEdge)
end
-- round 30: kit 1015j far hill ring (green hills with pines baked in) between the cliff belt and the far mountains,
-- so the horizon behind the spawn is never empty. 12 segments at radius 250, turned to face the park.
do
	local names = { "FarHillRing_A_v1", "FarHillRing_B_v1", "FarHillRing_C_v1" }
	if KIT and KIT:FindFirstChild(names[1], true) then
		local fH = sub("FarHills")
		for k = 0, 11 do
			local src = KIT:FindFirstChild(names[k % 3 + 1], true)
			if src then
				local a = math.rad(k * 30 + 15)
				local m = src:Clone()
				if m:IsA("BasePart") then
					local w2 = Instance.new("Model")
					m.Parent = w2
					w2.PrimaryPart = m
					m = w2
				end
				local mm = m :: Model
				local ext = mm:GetExtentsSize()
				mm:ScaleTo(mm:GetScale() * 140 / math.max(ext.X, 1)) -- each segment ~140 wide: 12 close the ring at r 250
				local x, z = math.sin(a) * 250, -math.cos(a) * 250
				mm:PivotTo(CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 0)))
				local cf, size = mm:GetBoundingBox()
				mm:PivotTo(mm:GetPivot() + Vector3.new(0, (G0 - 4) - (cf.Position.Y - size.Y / 2), 0))
				for _, d in mm:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored, d.CanCollide, d.CanQuery, d.CastShadow = true, false, false, false
					end
				end
				mm.Parent = fH
				kitUsed.FarHill = (kitUsed.FarHill or 0) + 1
			end
		end
	end
end
-- round 18 (runner: "blue void past the ring, distant landforms"): a ring of far low-poly mountains (kit 1015b),
-- 330-420 studs out, turned and scaled so the five shapes don't repeat side by side
do
	local fM = sub("FarMountains")
	local names = { "DistantMountains_Ring_v1_B", "DistantMountains_Ring_v1_A", "DistantMountains_Ring_v1_C",
		"DistantMountains_Ring_v1_D", "DistantMountains_Ring_v1_E" }
	local n = 0
	for k = 0, 13 do
		local a = math.rad(k * 360 / 14 + 7)
		local r = 330 + (k % 3) * 45
		local x, z = math.sin(a) * r, -math.cos(a) * r
		local m = placeKit(names[k % #names + 1], x, z, k * 360 / 14 + 180 + (k % 2) * 25, fM, G0 - 6)
		if m then
			m:ScaleTo(m:GetScale() * (1.15 + (k % 4) * 0.12))
			local cf, size = m:GetBoundingBox()
			m:PivotTo(m:GetPivot() + Vector3.new(0, (G0 - 6) - (cf.Position.Y - size.Y / 2), 0))
			-- round 20: the further ring, the paler (runner: "no near-to-far haze gradient")
			-- round 29 (runner: "haze washes the mountains"): deeper blue-grey, only a light step paler per ring
			local tint = Color3.fromHex(({ "6f86b8", "7a86bf", "6a84b0" })[k % 3 + 1]):Lerp(Color3.fromHex("c4d4ee"), 0.05 + (k % 3) * 0.1):ToHex()
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CastShadow = false
					-- round 19 (runner: "tint blue-purple so they don't merge with the lawn greens"): far blue
					d.Color = Color3.fromHex(tint)
					if d:IsA("MeshPart") then
						d.TextureID = ""
					end
					d.Material = Enum.Material.SmoothPlastic
				end
			end
			n += 1
		end
	end
	print("[LobbyRedesign] far mountains " .. n)
end
-- round 16 (runner: "towers taller, bright cone roof, lanterns, silhouette against the sky"): a stepped orange roof
-- and four warm lanterns on top of each corner watchtower
for _, t in fEdge:GetChildren() do
	if t:IsA("Model") and string.find(t.Name, "WallTower", 1, true) then
		local cf, size = t:GetBoundingBox()
		local top = cf.Position + Vector3.new(0, size.Y / 2, 0)
		local r = math.min(size.X, size.Z) * 0.5
		for k = 0, 4 do
			local rr = r * (1.08 - k * 0.21)
			local ring = flat(fEdge, CFrame.new(top + Vector3.new(0, 0.9 + k * 1.8, 0)) * DISC, Vector3.new(1.8, rr * 2, rr * 2),
				if k % 2 == 0 then "f08a2b" else "e0743a", Enum.PartType.Cylinder)
			ring.Name = "TowerRoof"
			ring.CastShadow = true
		end
		local tip = flat(fEdge, CFrame.new(top + Vector3.new(0, 10.4, 0)), Vector3.new(1.6, 1.6, 1.6), "d99a2e", Enum.PartType.Ball) -- r29h: deeper gold (neon blew out)
		tip.Material = Enum.Material.SmoothPlastic -- r29i: matte (runner)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local at = top + Vector3.new(math.cos(a) * (r + 0.4), -1.6, math.sin(a) * (r + 0.4))
			local lamp = flat(fEdge, CFrame.new(at), Vector3.new(1.2, 1.6, 1.2), "e8b450")
			lamp.Material = Enum.Material.SmoothPlastic
			lamp.Name = "TowerLantern"
		end
		-- round 19: the WallIvy_Patch_v1 slabs are off (runner: "flat square slabs, not vines"; half were buried)
		-- round 20 (kit 1015c): two stone buttresses and a leafy vine on each tower face that looks into the park, each
		-- set on the real stone face found by a ray (round 18's box guess buried half the ivy)
		local tcf = t:GetPivot()
		local towerRay = RaycastParams.new()
		towerRay.FilterType = Enum.RaycastFilterType.Include
		towerRay.FilterDescendantsInstances = { t }
		local inward = -Vector3.new(cf.Position.X, 0, cf.Position.Z).Unit
		for _, side in { tcf.LookVector, -tcf.LookVector, tcf.RightVector, -tcf.RightVector } do
			side = Vector3.new(side.X, 0, side.Z).Unit
			if side:Dot(inward) > 0.3 then
				local across = side:Cross(Vector3.yAxis)
				local wallDist: number? = nil -- round 21: the buttress rays find the wall; an ivy ray that lands far off it is skipped
				for j, off in { -5.5, 5.5, 0 } do
					local from = cf.Position + side * 40 + across * off + Vector3.new(0, if j == 3 then 6 else -size.Y / 2 + 4, 0)
					local hit = workspace:Raycast(from, -side * 60, towerRay)
					if j < 3 and hit then
						wallDist = math.min(wallDist or math.huge, hit.Distance)
					end
					if hit and j == 3 and wallDist and math.abs(hit.Distance - wallDist) > 1.5 then
						hit = nil
					end
					if hit then
						local p = hit.Position
						local name = if j == 3 then "LeafIvy_Hang_v1" else "Buttress_Stone_v1"
						local y = if j == 3 then p.Y - 4 else cf.Position.Y - size.Y / 2
						local m = placeKit(name, p.X, p.Z, 0, fEdge, y)
						if m then
							-- the ivy's pivot is its flat back; the buttress pivots at its base centre, so it steps out half its depth
							-- round 21 (Studio): buttresses sat 1.39 into the stone and ivy 0.55, so both step out by that much more
							local pv = m:GetPivot().Position + (if j == 3 then side * 0.6 else side * 4.0)
							m:PivotTo(CFrame.lookAt(pv, pv + side)) -- front (-Z) out of the wall, flat back on the stone
							if j < 3 then -- round 23 (scan: clip): a small tree planted against the tower makes way for the buttress
								local bcf, bsz = m:GetBoundingBox()
								local op = OverlapParams.new()
								op.FilterType = Enum.RaycastFilterType.Include
								op.FilterDescendantsInstances = { fDecor }
								for _, hitPart in workspace:GetPartBoundsInBox(bcf, bsz, op) do
									local tree = hitPart:FindFirstAncestorWhichIsA("Model")
									if tree and tree.Parent == fDecor and (string.find(tree.Name, "^Tree_") or string.find(tree.Name, "^Pine_")) then
										tree:Destroy()
									end
								end
							end
						end
					end
				end
			end
		end
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromHex("ffcf7a")
		glow.Range = 24
		glow.Brightness = 1.5
		glow.Parent = tip
	end
end
-- round 12: green tops on the wall. A bush sits on every other cliff, coloured by the side of the island (west gold,
-- east autumn, north blue-green, south plain), so the ring reads as part of the zones and not one grey band
do
	local k, placed = 0, 0
	for _, m in fEdge:GetChildren() do
		if not (m:IsA("Model") and string.match(m.Name, "^Cliff")) then
			continue
		end
		k += 1
		local cf, size = m:GetBoundingBox()
		local p = cf.Position
		local name = if p.X < -140 and p.Z > -130 and p.Z < 70 then "Bush_Round_Golden_v1"
			elseif p.X > 140 and p.Z > -130 and p.Z < 70 then "Bush_Round_Autumn_v1"
			elseif p.Z < -190 then "Bush_Round_BlueGreen_v1"
			else "Bush_Round_A_v2"
		for j = 0, 1 do -- round 27: two on every cliff (runner: "bare grey wall")
			local src = kitModel(name)
			if not src then
				report.nokit[name] = true
				break
			end
			local b = src:Clone()
			if b:IsA("BasePart") then
				local w = Instance.new("Model")
				w.Name = name
				b.Parent = w
				w.PrimaryPart = b
				b = w
			end
			local bm = b :: Model
			bm:ScaleTo(bm:GetScale() * (1.4 + (k % 3) * 0.25))
			local along = cf.RightVector * ((j - 0.5) * size.X * 0.4)
			bm:PivotTo(CFrame.new(p + along) * CFrame.Angles(0, k * 1.3, 0))
			local bcf, bsize = bm:GetBoundingBox()
			bm:PivotTo(bm:GetPivot() + Vector3.new(0, (p.Y + size.Y / 2 - 0.8) - (bcf.Position.Y - bsize.Y / 2), 0))
			for _, d in bm:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
				end
			end
			bm.Parent = fEdge
			placed += 1
		end
	end
	print("[LobbyRedesign] wall-top bushes: " .. placed)
end
-- round 8: vary the grey cliffs (untextured meshes only) between warm and cool stone
do
	-- round 29 (runner vs carter's old shot: "cliffs grey-green, want blue-grey"): the old lobby's blue-grey stone
	-- r29h (runner: "cliff wall reads flat royal blue, painted"): calmer blue-grey with a rock grain, not lifted
	local STONE = { "a7b0c2", "9ca6ba", "b0b8c8", "98a2b6", "a2acbf" } -- r29i: lighter (Slate darkens it; read navy)
	local k = 0
	for _, m in fEdge:GetChildren() do
		if string.match(m.Name, "^Cliff") then
			k += 1
			for _, d in m:GetDescendants() do
				-- r29e (runner: "cliffs still grey-green"): textured cliff meshes lose the grey-green texture too and take the
				-- flat blue-grey stone (the old flat-shaded look; the texture id is kept in VibeTex to undo)
				if d:IsA("MeshPart") and d.TextureID ~= "" then
					d:SetAttribute("VibeTex", d.TextureID)
					d.TextureID = ""
				end
				if d:IsA("MeshPart") and d.TextureID == "" then
					d.Material = Enum.Material.Slate
					d.Color = Color3.fromHex(STONE[k % #STONE + 1])
				end
			end
		end
	end
end
-- round 8: slow gold sparkles over the shop square and warm embers over the battle ring (default particle, no ids)
local fFx = sub("Sparkles")
local function sparkle(pos: Vector3, col: string, up: number, rate: number)
	local p = flat(fFx, CFrame.new(pos), Vector3.new(1, 1, 1), col)
	p.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromHex(col))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.2)
	pe.Speed = NumberRange.new(0.4, 1)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, up, 0)
	pe.Lifetime = NumberRange.new(2.5, 4)
	pe.Rate = rate
	pe.Parent = p
end
for k = 0, 5 do
	local a = k / 6 * 2 * math.pi + 0.3
	sparkle(Vector3.new(30 * math.sin(a), G0 + 6, -30 * math.cos(a)), "ffe27a", 0.3, 3)
end
sparkle(Vector3.new(DATA.battle.x, G0 + 2, DATA.battle.z), "ff9a3c", 2, 6)

-- 7. the egg pile (hunt entrance): straw nest + a dome of eggs
local fPile = sub("EggPile")
do
	local P = DATA.pile
	flat(fPile, CFrame.new(P.x, G0 + 0.5, P.z) * DISC, Vector3.new(1, P.r * 2, P.r * 2), "c9a061", Enum.PartType.Cylinder).CanCollide = true
	flat(fPile, CFrame.new(P.x, G0 + 0.7, P.z) * DISC, Vector3.new(1.6, P.r * 2 + 2.5, P.r * 2 + 2.5), "a97f45", Enum.PartType.Cylinder)
	for _, e in DATA.eggs do
		local ecf = CFrame.new(e.x, G0 + e.y, e.z) * CFrame.Angles(math.rad(e.tilt), math.rad(e.tilt * 3), 0)
		-- r29j (runner: "egg pile very bright"): white eggs are a soft cream, pale ones a touch deeper
		local ec = if e.c == "ffffff" then "efe4cc" else Color3.fromHex(e.c):Lerp(Color3.fromHex("b89a6a"), 0.12):ToHex()
		local p = flat(fPile, ecf, Vector3.new(e.s, e.s * 1.3, e.s), ec, Enum.PartType.Ball)
		-- round 22 (runner: "reads as party balloons"): a white or gold zigzag-free band round every other egg, so they
		-- read as painted eggs
		if math.floor(e.x * 10) % 2 == 0 then
			local band = flat(fPile, ecf * CFrame.new(0, -e.s * 0.05, 0) * DISC, Vector3.new(e.s * 0.22, e.s * 1.02, e.s * 1.02),
				if e.c == "ffffff" or e.c == "fff3b0" then "d9902a" else "efe4cc", Enum.PartType.Cylinder)
			band.CastShadow = false
		end
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.CastShadow = true
	end
end

-- round 19 (runner: "particles on the egg pile"): gold sparkles drifting up off the dome
sparkle(Vector3.new(DATA.pile.x, G0 + 8, DATA.pile.z), "ffe27a", 10, 6)

-- 7b. round 15: the free-egg stand at the spawn (runner: "the spawn reads as an empty octagon, give it a focal point").
-- A gold ring and a pale disc round StarterEggSpot (the spot itself stays clear for the egg), six little lanterns and a
-- warm light, so the first thing a new player sees is where the free egg is.
do
	local S = DATA.starter
	local c = CFrame.new(S.x, groundY(S.x, S.z), S.z)
	-- r29e (runner: "yellow glow trim blown out"): a plain gold ring, not neon
	flat(fPile, c * CFrame.new(0, 0.14, 0) * DISC, Vector3.new(0.1, S.r * 2 + 2, S.r * 2 + 2), "b8945a", Enum.PartType.Cylinder).Material = -- r29j: no yellow glow ring
		Enum.Material.SmoothPlastic
	flat(fPile, c * CFrame.new(0, 0.16, 0) * DISC, Vector3.new(0.1, S.r * 2, S.r * 2), "e8cf86", Enum.PartType.Cylinder)
	for k = 0, 5 do
		local a = k * math.pi / 3
		local at = c * CFrame.new(math.cos(a) * (S.r + 2.2), 0, math.sin(a) * (S.r + 2.2))
		local post = flat(fPile, at * CFrame.new(0, 1, 0), Vector3.new(0.5, 2, 0.5), "7a5230")
		post.Material = Enum.Material.Wood
		local lamp = flat(fPile, at * CFrame.new(0, 2.3, 0), Vector3.new(0.9, 0.9, 0.9), "e8b450", Enum.PartType.Ball)
		lamp.Material = Enum.Material.SmoothPlastic
	end
	local glow = flat(fPile, c * CFrame.new(0, 4, 0), Vector3.new(0.2, 0.2, 0.2), "ffffff")
	glow.Transparency = 1
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex("ffd23f")
	l.Range = 16
	l.Brightness = 1.6
	l.Parent = glow
	sparkle(c.Position + Vector3.new(0, 1, 0), "ffe27a", 4, 4)
end

-- 8. the battle ring: stone floor, low wall of blocks, four pillars with gold caps (BattlePad sits in the middle)
local fBat = sub("BattleRing")
do
	local B = DATA.battle
	local y = G0
	-- round 21 (runner: "blank cream pit"): warm sand floor, a red fighting ring, a dark centre circle and a gold rim
	local floor = flat(fBat, CFrame.new(B.x, y + 0.3, B.z) * DISC, Vector3.new(0.6, B.r * 2, B.r * 2), "cdb48c", Enum.PartType.Cylinder) -- r29h: sand, not salmon
	floor.Material = Enum.Material.Sand
	flat(fBat, CFrame.new(B.x, y + 0.62, B.z) * DISC, Vector3.new(0.04, B.r * 1.5, B.r * 1.5), "a8473c", Enum.PartType.Cylinder)
	flat(fBat, CFrame.new(B.x, y + 0.64, B.z) * DISC, Vector3.new(0.04, B.r * 1.3, B.r * 1.3), "cdb48c", Enum.PartType.Cylinder).Material =
		Enum.Material.Sand
	flat(fBat, CFrame.new(B.x, y + 0.66, B.z) * DISC, Vector3.new(0.04, B.r * 0.55, B.r * 0.55), "7a2a24", Enum.PartType.Cylinder)
	flat(fBat, CFrame.new(B.x, y + 0.68, B.z) * DISC, Vector3.new(0.04, B.r * 0.45, B.r * 0.45), "d6a73a", Enum.PartType.Cylinder)
	flat(fBat, CFrame.new(B.x, y + 0.7, B.z) * DISC, Vector3.new(0.04, B.r * 0.38, B.r * 0.38), "7a2a24", Enum.PartType.Cylinder)
	local n = 22
	for k = 0, n - 1 do
		local a = k / n * 2 * math.pi
		if k % 11 ~= 5 then -- two gaps to walk in (west, toward the lobby; east)
			local pos = Vector3.new(B.x + (B.r - 0.8) * math.sin(a), y + 1.5, B.z - (B.r - 0.8) * math.cos(a))
			local p = flat(fBat, CFrame.lookAt(pos, Vector3.new(B.x, pos.Y, B.z)), Vector3.new(2 * math.pi * B.r / n - 0.3, 3, 2), "a3876d")
			p.Material = Enum.Material.Slate
			p.CanCollide = true
			flat(fBat, CFrame.lookAt(pos, Vector3.new(B.x, pos.Y, B.z)) * CFrame.new(0, 1.62, 0), Vector3.new(2 * math.pi * B.r / n - 0.2, 0.25, 2.2),
				"8a5a4a") -- r29j: brick (red read pink)
		end
	end
	for k = 0, 3 do
		local a = math.rad(45 + 90 * k)
		local pos = Vector3.new(B.x + (B.r + 1.5) * math.sin(a), y + 6, B.z - (B.r + 1.5) * math.cos(a))
		local p = flat(fBat, CFrame.new(pos), Vector3.new(3.4, 12, 3.4), "8d877f")
		p.Material = Enum.Material.Slate
		p.CanCollide = true
		local cap = flat(fBat, CFrame.new(pos + Vector3.new(0, 6.6, 0)), Vector3.new(4.2, 1.2, 4.2), "d6a73a")
		cap.Material = Enum.Material.SmoothPlastic
		local coal = flat(fBat, CFrame.new(pos + Vector3.new(0, 7.3, 0)) * DISC, Vector3.new(0.2, 2.6, 2.6), "ff7a2b", Enum.PartType.Cylinder)
		coal.Material = Enum.Material.Neon
		local f = Instance.new("Fire")
		f.Size = 4
		f.Heat = 6
		f.Parent = coal
	end
end

-- 8b. the surrounding hills: a deeper, natural green (untextured meshes only; textured ones are reported)
local hillsTextured = 0
for _, p in { "LobbyMeadow.Park.Hills", "LobbyMeadow.Park.OuterHills" } do
	local f = find(p)
	if f then
		for _, d in f:GetDescendants() do
			if d:IsA("MeshPart") then
				if d.TextureID == "" and not d:FindFirstChildWhichIsA("SurfaceAppearance") then
					local HUES = { "4f8a35", "5e9a3e", "6b8f3a", "7d9c45", "4a7d3a", "8a9a4a" } -- varied natural greens + olive
					d.Color = Color3.fromHex(HUES[math.floor(math.abs(d.Position.X * 7 + d.Position.Z * 13)) % #HUES + 1])
				else
					hillsTextured += 1
				end
			end
		end
	end
end
print("[LobbyRedesign] hill meshes with a texture (not tinted): " .. hillsTextured)


-- 8c. hero: the Void Dragon fountain in the middle of the shop square (carter 2026-10-15). A round pool with a stone
-- rim and an island; VoidStatue builds the 20-stud dragon on the VoidStatueSpot (no plinth) with its floating
-- "VOID DRAGON 1 in 1000" sign. The leaderboard tree and its spot go to the backup bin (TreeBoardService skips).
for _, t in { find("LobbyMeadow.LeaderboardTreeSpot"), SS:FindFirstChild("LeaderboardTree") } do
	if t then
		t.Parent = bin
		report.archived += 1
	end
end
-- round 7: meshes already in the lobby that came from the _v2 exports carried the old green texture; give each the
-- texture of its _v3 twin from the kit (same mesh, calm colours)
local v3tex: { [string]: string } = {}
if KIT then
	for _, d in KIT:GetDescendants() do
		if d:IsA("MeshPart") and string.match(d.Name, "_v3$") and d.TextureID ~= "" then
			v3tex[d.Name] = d.TextureID
		end
	end
end
local retextured = 0
for _, top in { find("LobbyMeadow"), find("FTP_Lobby"), ROOT } do
	if top then
		for _, d in top:GetDescendants() do
			if d:IsA("MeshPart") and string.match(d.Name, "_v2$") then
				local t = v3tex[string.gsub(d.Name, "_v2$", "_v3")]
				if t and d.TextureID ~= t then
					d.TextureID = t
					retextured += 1
				end
			end
		end
	end
end
print("[LobbyRedesign] _v2 meshes given their _v3 calm texture: " .. retextured)

local fHero = sub("DragonFountain")
local heroFountain = KIT and KIT:FindFirstChild("FountainBase_v1", true)
local islandTop = G0 + 2.3
if heroFountain then -- the Blender pool (26 across, island top 3.4 up) replaces the scripted pool, rim and island
	local f = heroFountain:Clone() :: Model
	f.Parent = fHero
	f:PivotTo(CFrame.new(0, G0, 0))
	local cf, size = f:GetBoundingBox()
	f:PivotTo(f:GetPivot() + Vector3.new(0, G0 - (cf.Position.Y - size.Y / 2), 0))
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	islandTop = G0 + 3.3 -- island top is 4.0 up and the statue stands 0.7 above its spot (Studio rounds 7-8)
end
do
	local R, ISLE = DATA.knoll.r, 6
	if not heroFountain then -- scripted pool, rim, island and glow ring
		flat(fHero, CFrame.new(0, G0 + 0.15, 0) * DISC, Vector3.new(0.3, R * 2, R * 2), "6c7a8a", Enum.PartType.Cylinder) -- r29j: stone basin, not a cyan ring
		local water = flat(fHero, CFrame.new(0, G0 + 0.9, 0) * DISC, Vector3.new(0.2, R * 2 - 1, R * 2 - 1), "3d8fd6", Enum.PartType.Cylinder)
		water.Material = Enum.Material.Glass
		water.Transparency = 0.2
		local n = 36
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * 2 * math.pi
			local pos = Vector3.new((R - 0.9) * math.sin(a), G0 + 1.1, -(R - 0.9) * math.cos(a))
			local p = flat(fHero, CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)), Vector3.new(2 * math.pi * R / n + 0.2, 2.2, 1.8), "cfc6b8")
			p.Material = Enum.Material.Slate
			p.CanCollide = true
			p.CanQuery = true
		end
		local isle = flat(fHero, CFrame.new(0, G0 + 1.2, 0) * DISC, Vector3.new(2.4, ISLE * 2, ISLE * 2), "8d877f", Enum.PartType.Cylinder)
		isle.Material = Enum.Material.Slate
		isle.CanCollide = true
		for k = 0, 23 do -- glowing purple ring round the island
			local a = k / 24 * 2 * math.pi
			local pos = Vector3.new((ISLE + 0.4) * math.sin(a), G0 + 1.0, -(ISLE + 0.4) * math.cos(a))
			flat(fHero, CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)) * CFrame.Angles(0, math.rad(90), 0),
				Vector3.new(0.8, 0.3, 2 * math.pi * ISLE / 24 + 0.2), "8a4fd8").Material = Enum.Material.Neon
		end
	end
	for k = 0, 3 do -- spray jets (default particle texture, no asset ids)
		local a = math.rad(45 + 90 * k)
		local pos = Vector3.new((R + ISLE) / 2 * math.sin(a), G0 + 1, -(R + ISLE) / 2 * math.cos(a))
		local jet = flat(fHero, CFrame.new(pos), Vector3.new(1, 0.4, 1), "9fe4ff")
		jet.Transparency = 1
		local att = Instance.new("Attachment")
		att.Parent = jet
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromHex("dff6ff"))
		pe.LightEmission = 0.4
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.2) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.Speed = NumberRange.new(13, 16)
		pe.SpreadAngle = Vector2.new(5, 5)
		pe.Acceleration = Vector3.new(0, -30, 0)
		pe.Lifetime = NumberRange.new(0.9, 1.1)
		pe.Rate = 35
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Parent = att
	end
	local spot = find("LobbyMeadow.VoidStatueSpot") or Instance.new("Part")
	spot.Name = "VoidStatueSpot"
	local sp = spot :: BasePart
	sp.Size = Vector3.new(4, 0.2, 4)
	sp.Anchored = true
	sp.CanCollide = false
	sp.Transparency = 1
	sp.CFrame = CFrame.lookAt(Vector3.new(0, islandTop, 0), Vector3.new(0, islandTop, 10)) -- faces the spawn
	sp:SetAttribute("Height", 20)
	sp:SetAttribute("Plinth", false)
	sp.Parent = find("LobbyMeadow") or workspace
end

-- 8c2. shop square signs and prompts: a big name board over each shop front; PET INDEX and MY PETS open their
-- Collection tab (client Main: panels PetIndex / MyPets); the EVENT SHOP has no shop yet, so its board says so and
-- it has no prompt.
local fShop = sub("ShopSquare")
local SIGN = { PetIndexShop = { "PET INDEX", "2fa7d6", "PetIndex", "📖" }, MyPetsShop = { "MY PETS", "58b83a", "MyPets", "🐾" },
	EventShop = { "EVENT SHOP", "e0443a", nil, "🎉" } }
local function board(parent, cf: CFrame, w: number, h: number, col: string, line1: string, line2: string?)
	local b = flat(parent, cf, Vector3.new(w, h, 0.8), col)
	local gui: SurfaceGui
	local function t(text, y, hh)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.92, hh)
		l.Position = UDim2.fromScale(0.04, y)
		l.Text = text
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = Color3.new(1, 1, 1)
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = Color3.fromHex("2b1a0e")
		st.Parent = l
		l.Parent = gui
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do -- round 8: readable from both sides
		gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = b
		if line2 then
			t(line1, 0.06, 0.56)
			t(line2, 0.64, 0.3)
		else
			t(line1, 0.12, 0.76)
		end
	end
	return b
end
-- round 9: a monument sign beside each shop door, turned to face the middle of the square (the runner read the
-- hanging boards edge-on); big two-sided text with the shop's icon
local function monument(front: Vector3, fwd: Vector3, title: string, col: string, line2: string, sc: number?)
	local k = sc or 1 -- round 20: the EVENT SHOP "coming soon" board is smaller (runner: it crowded the square)
	local right = fwd:Cross(Vector3.yAxis)
	-- round 15: stand on the side of the door away from the spawn-to-dragon walk (MY PETS hid the dragon)
	local a1, a2 = front + fwd * 3 + right * 11, front + fwd * 3 - right * 11
	local at = if math.abs(a2.X) > math.abs(a1.X) then a2 else a1
	local face = CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
	for _, dx in { -6.2 * k, 6.2 * k } do
		local post = flat(fShop, face * CFrame.new(dx, 3 * k, 0), Vector3.new(1.2, 6 * k, 1.2), "7a5230")
		post.Material = Enum.Material.Wood
		post.CanCollide = true
	end
	local b = board(fShop, face * CFrame.new(0, 6.2 * k, 0), 15 * k, 5.2 * k, col, title, line2)
	b.CanCollide = true
	local cap = flat(fShop, face * CFrame.new(0, 9 * k, 0), Vector3.new(15.8 * k, 0.6, 1.4), "5e4a37")
	cap.Material = Enum.Material.Wood
end
local function shopFront(s)
	local a = math.rad(s.yaw)
	local fwd = Vector3.new(math.sin(a), 0, -math.cos(a))
	return fwd, Vector3.new(s.x, G0, s.z) + fwd * (s.d / 2 + 1.5)
end
for _, s in DATA.shops do
	local info = SIGN[s.name]
	local fwd, front = shopFront(s)
	local look = CFrame.lookAt(front, front + fwd)
	monument(front, fwd, info[4] .. " " .. info[1], info[2], if info[3] then "TAP TO OPEN" else "COMING SOON", if info[3] then 1 else 0.65)
	if info[3] then
		local pad = flat(fShop, look * CFrame.new(0, 2, 0), Vector3.new(6, 4, 1), "ffffff")
		pad.Transparency = 1
		pad.CanQuery = true
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Open"
		pp.ObjectText = info[1]
		pp.MaxActivationDistance = 12
		pp.RequiresLineOfSight = false
		pp:SetAttribute("Panel", info[3])
		pp.Parent = pad
	end
end
do -- the egg shop gets the same big board (its counter prompt is the existing EggShop hook)
	local e = DATA.eggshop
	local a = math.rad(e.yaw)
	local fwd = Vector3.new(math.sin(a), 0, -math.cos(a))
	local front = Vector3.new(e.x, G0, e.z) + fwd * (e.d / 2 + 1.5)
	monument(front, fwd, "🥚 EGG SHOP", "d6a73a", "PETS FOR ROBUX")
end

-- 8d. zone gates (round 7): the Blender hero gate for each zone when it is in LobbyKitV2 (FIND_Gate_v1, FIGHT_Gate_v1,
-- TRAIN_Gate_v1, each with a blank _Sign board), else the scripted stone arch. Each gets its zone glow, a round icon
-- badge on top and a dark ground shadow under the posts.
local fArch = sub("ZoneArches")
local function signText(sign: BasePart, faces: { Enum.NormalId }, words: string)
	local title, sub = string.match(words, "^(%S+)%s+(.+)$")
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = sign
		-- round 9: two lines (zone name big, what it is small) so the text stays inside the plate
		for k, line in { { title or words, 0.04, 0.6 }, { sub or "", 0.66, 0.3 } } do
			if line[1] == "" then
				continue
			end
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(0.9, line[3])
			l.Position = UDim2.fromScale(0.05, line[2])
			l.Text = line[1]
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextColor3 = Color3.new(1, 1, 1)
			local st = Instance.new("UIStroke")
			st.Thickness = if k == 1 then 4 else 3
			st.Color = Color3.fromHex("2b1a0e")
			st.Parent = l
			l.Parent = gui
		end
	end
end
for _, a in DATA.arches do
	local L = Vector3.new(a.lx, G0, a.lz)
	local R = Vector3.new(a.rx, G0, a.rz)
	local mid = (L + R) / 2
	local span = (R - L).Magnitude
	local right = (R - L).Unit
	local topY = G0 + 11
	local glowAt: BasePart
	local src = KIT and KIT:FindFirstChild(a.text .. "_Gate_v1", true)
	if src then
		local g = src:Clone() :: Model
		g.Parent = fArch
		-- the gate's width runs along its X; stand it across the walk with the base on the ground
		g:PivotTo(CFrame.fromMatrix(mid, right, Vector3.yAxis))
		local cf, size = g:GetBoundingBox()
		g:PivotTo(g:GetPivot() + Vector3.new(0, groundY(mid.X, mid.Z) - (cf.Position.Y - size.Y / 2), 0))
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		cf, size = g:GetBoundingBox()
		topY = cf.Position.Y + size.Y / 2
		-- the plate is named like FIND_Gate_v1_Sign.001; write on its two big faces (the thin axis decides which)
		local sign: Instance? = nil
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") and string.find(d.Name, "_Sign", 1, true) then
				sign = d
				break
			end
		end
		if sign and sign:IsA("BasePart") then
			local sz = sign.Size
			local faces = if sz.X <= sz.Y and sz.X <= sz.Z then { Enum.NormalId.Left, Enum.NormalId.Right }
				elseif sz.Y <= sz.Z then { Enum.NormalId.Top, Enum.NormalId.Bottom }
				else { Enum.NormalId.Front, Enum.NormalId.Back }
			signText(sign, faces, a.text .. "  " .. a.sub)
			glowAt = sign
		else
			glowAt = g.PrimaryPart or g:FindFirstChildWhichIsA("BasePart", true) :: BasePart
		end
	else
		-- scripted stand-in, a different look per zone: FIND warm wood + straw roof, FIGHT red-brown rock + fire,
		-- TRAIN blue-grey stone + blue crystal tips
		local style = ({
			FIND = { post = "8a5a2b", postMat = Enum.Material.WoodPlanks, cap = "e3c25a" },
			FIGHT = { post = "7a4a3a", postMat = Enum.Material.Slate, cap = "5a554f" },
			TRAIN = { post = "7f8fa0", postMat = Enum.Material.Slate, cap = "5fc4ef" },
		})[a.text]
		for _, p in { L, R } do
			local post = flat(fArch, CFrame.new(p + Vector3.new(0, 6, 0)), Vector3.new(3.4, 12, 3.4), style.post)
			post.Material = style.postMat
			post.CanCollide = true
			local cap = flat(fArch, CFrame.new(p + Vector3.new(0, 12.8, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3, 1.6, 3),
				style.cap)
			if a.text == "TRAIN" then
				cap.Material = Enum.Material.Neon
				cap.Size = Vector3.new(1.8, 3.2, 1.8)
				cap.CFrame = CFrame.new(p + Vector3.new(0, 13.6, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
			elseif a.text == "FIGHT" then
				local coal = flat(fArch, CFrame.new(p + Vector3.new(0, 13.7, 0)) * DISC, Vector3.new(0.2, 2.4, 2.4), "ff7a2b", Enum.PartType.Cylinder)
				coal.Material = Enum.Material.Neon
				local f = Instance.new("Fire")
				f.Size = 4
				f.Parent = coal
			end
		end
		local along = CFrame.lookAt(mid + Vector3.new(0, 11.4, 0), R + Vector3.new(0, 11.4, 0)) -- Z runs post to post
		local beam = flat(fArch, along, Vector3.new(1.8, 1.5, span + 2), style.post)
		beam.Material = style.postMat
		if a.text == "FIND" then -- a peaked straw roof over the beam
			for _, side in { -1, 1 } do
				local roof = flat(fArch, along * CFrame.new(side * 1.6, 1.4, 0) * CFrame.Angles(0, 0, math.rad(-side * 35)),
					Vector3.new(3.6, 0.6, span + 4), "e3c25a")
				roof.Material = Enum.Material.Fabric
			end
		end
		local sign = flat(fArch, along * CFrame.new(0, -2.6, 0), Vector3.new(0.8, 3, math.min(span - 8, 16)), a.col)
		signText(sign, { Enum.NormalId.Left, Enum.NormalId.Right }, a.text .. "  " .. a.sub)
		glowAt = sign
		topY = G0 + 14
	end
	-- a zone-coloured threshold band on the ground between the posts (reads from above)
	local band = flat(fArch, CFrame.lookAt(mid + Vector3.new(0, 0.3, 0), R + Vector3.new(0, 0.3, 0)), Vector3.new(2.4, 0.1, span - 4), a.col)
	band.Material = Enum.Material.SmoothPlastic
	-- dark ground shadow under each post (fake ambient occlusion)
	for _, p in { L, R } do
		local ao = flat(fArch, CFrame.new(p.X, G0 + 0.21, p.Z) * DISC, Vector3.new(0.05, 8, 8), "000000", Enum.PartType.Cylinder)
		ao.Transparency = 0.65
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromHex(a.col)
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = glowAt
	-- round 13: the 3D zone icon floats over the gate, and a big floating name reads from the shop square
	local iconName = ({ FIND = "Icon_Egg_v1", FIGHT = "Icon_Claws_v1", TRAIN = "Icon_Star_v1" })[a.text]
	local icon3d = iconName and placeKit(iconName, mid.X, mid.Z, 0, fArch, topY + 1.5)
	if icon3d then
		icon3d:ScaleTo(icon3d:GetScale() * 1.2) -- round 21: smaller (walkthrough: it filled the view)
		local icf = icon3d:GetPivot()
		icon3d:PivotTo(CFrame.fromMatrix(icf.Position, right, Vector3.yAxis))
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(18, 4.5)
	bb.StudsOffsetWorldSpace = Vector3.new(0, topY - G0 + (if icon3d then 9 else 4), 0)
	bb.MaxDistance = 260
	bb.LightInfluence = 0
	bb.Adornee = glowAt
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 1)
	name.Text = ({ FIND = "🥚 EGG HUNT", FIGHT = "⚔️ BATTLE", TRAIN = "⭐ TRAIN" })[a.text]
	name.TextScaled = true
	name.Font = Enum.Font.FredokaOne
	name.TextColor3 = Color3.fromHex(a.col)
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = Color3.new(1, 1, 1)
	st.Parent = name
	name.Parent = bb
	bb.Parent = glowAt
	-- the round zone icon on top was cut in round 10 (it read as a flat placeholder)
	if false then
	local badge = flat(fArch, CFrame.fromMatrix(Vector3.new(mid.X, topY + 4, mid.Z), right, Vector3.yAxis), Vector3.new(7, 7, 0.6), a.col)
	badge.Transparency = 1
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(300, 300)
		gui.LightInfluence = 0
		gui.Parent = badge
		local disc = Instance.new("Frame")
		disc.Size = UDim2.fromScale(1, 1)
		disc.BackgroundColor3 = Color3.fromHex(a.col)
		disc.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local ring = Instance.new("UIStroke")
		ring.Thickness = 14
		ring.Color = Color3.new(1, 1, 1)
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = disc
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromScale(0.9, 0.9)
		icon.Position = UDim2.fromScale(0.05, 0.05)
		icon.Text = a.icon
		icon.TextScaled = true
		icon.Font = Enum.Font.FredokaOne
		icon.TextColor3 = Color3.new(1, 1, 1)
		icon.Parent = disc
	end
	end
end

-- 8e. yards: a gold claim disc just inside each gate
local fYard = sub("YardGates")
-- round 15 (runner: "yards as real plots"): a round number badge over each owner sign (the sign itself shows the
-- owner or the free-plot text from GalleryService) and a watering can at the end of each garden bed
for k = 1, 6 do
	local plot = find("FTP_Lobby.Plots.Plot" .. k)
	if not plot then
		continue
	end
	local plaque = plot:FindFirstChild("SignPlaque", true)
	if plaque and plaque:IsA("BasePart") then
		local cf = plaque.CFrame * CFrame.new(0, plaque.Size.Y / 2 + 2.2, 0)
		local disc = flat(fYard, cf * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.6, 4, 4), "d6a73a", Enum.PartType.Cylinder)
		disc.Name = "YardNumber"
		local rim = flat(fYard, cf * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.5, 4.5, 4.5), "ffffff", Enum.PartType.Cylinder)
		rim.Name = "YardNumberRim"
		local face = flat(fYard, cf, Vector3.new(3.2, 3.2, 0.7), "ffffff")
		face.Transparency = 1
		face.Name = "YardNumberText"
		for _, nf in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = nf
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50
			gui.LightInfluence = 0
			gui.Parent = face
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Text = tostring(k)
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextColor3 = Color3.new(1, 1, 1)
			local st = Instance.new("UIStroke")
			st.Thickness = 4
			st.Color = Color3.fromHex("7a4a12")
			st.Parent = l
			l.Parent = gui
		end
	end
	-- round 16 (runner: "big plot number readable far, gate arch, mailbox, lawn variation"): a floating YARD k name
	-- over the badge, a wooden arch over the gate with the number, a mailbox inside the gate and a few softer grass patches
	local Y = DATA.yards[k]
	-- round 17: the floating name moves onto the gate arch (on the plaque it read as a bug in the corner shots)
	local YCOL = { "f0a020", "2fa7d6", "58b83a", "e0443a", "8a4fd8", "3fbfae" }
	if Y then
		local soilPart = plot:FindFirstChild("YardSoil", true)
		local soilTop = if soilPart and soilPart:IsA("BasePart") then soilPart.Position.Y + soilPart.Size.Y / 2 else groundY(Y.gx, Y.gz)
		local g = groundY(Y.fx, Y.gz)
		local base = CFrame.new(Y.fx, g, Y.gz) * CFrame.Angles(0, math.rad(if Y.sg > 0 then -90 else 90), 0) -- -Z looks out to the lane
		for _, dz in { -5, 5 } do
			part(fYard, base * CFrame.new(dz, 4.5, 0), Vector3.new(0.9, 9, 0.9), "7a5230", Enum.Material.Wood, nil, true)
			part(fYard, base * CFrame.new(dz, 9.2, 0), Vector3.new(1.3, 0.5, 1.3), "d6a73a", nil, nil, true)
		end
		part(fYard, base * CFrame.new(0, 8.6, 0), Vector3.new(11.6, 0.7, 0.9), "a0703f", Enum.Material.WoodPlanks, nil, true)
		local sb = part(fYard, base * CFrame.new(0, 7.2, 0), Vector3.new(6.4, 2.2, 0.4), YCOL[k], nil, nil, true)
		-- round 25: no floating YARD k title (it stacked over the owner sign, runner); the crest and the board stay
		-- a little pet house in the gate corner (REPLACE stand-in: PetHouse_Wood_v1 from the props batch)
		local hx, hz = Y.gx - Y.sg * 10, Y.gz - 11 -- round 28: 3 further from the gate posts (Yard 4, 5) -- round 23: 10 in (its roof still clipped the flower border at 7)
		local house = placeKit("PetHouse_Wood_v1", hx, hz, if Y.sg > 0 then 90 else -90, fYard, soilTop)
		if house then -- round 26 (runner: "shrink the doghouses"): 0.8 size, bottom back on the soil
			house:ScaleTo(house:GetScale() * 0.8)
			local hcf, hsz = house:GetBoundingBox()
			house:PivotTo(house:GetPivot() + Vector3.new(0, soilTop - (hcf.Position.Y - hsz.Y / 2), 0))
		end
		if not house then
			local hc = CFrame.new(hx, soilTop, hz)
			part(fYard, hc * CFrame.new(0, 1.5, 0), Vector3.new(4, 3, 4), "a0703f", Enum.Material.WoodPlanks, nil, true)
			part(fYard, hc * CFrame.new(0, 3.6, 0), Vector3.new(4.6, 1.2, 4.6), YCOL[k], nil, nil, true)
		end
		for _, nf in { Enum.NormalId.Back } do -- round 25: the street side carries the owner sign
			local gui = Instance.new("SurfaceGui")
			gui.Face = nf
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 0
			gui.Parent = sb
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(0.92, 0.84)
			l.Position = UDim2.fromScale(0.04, 0.08)
			l.Text = "YARD " .. k
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextColor3 = Color3.new(1, 1, 1)
			local st = Instance.new("UIStroke")
			st.Thickness = 3
			st.Color = Color3.fromHex("2b1a0e")
			st.Parent = l
			l.Parent = gui
		end
		-- mailbox just inside the gate (outside the yard-pet spots, which keep 5 studs off the fence)
		-- round 18 (runner: "one prop doesn't make a yard"): stepping stones in from the gate, a pet bed by the house,
		-- flower borders along the inside of the front fence and two lanterns at the arch (kit 1015b; skipped if missing)
		local face = if Y.sg > 0 then 90 else -90
		placeKit("SteppingStones_v1", Y.gx - Y.sg * 6.5, Y.gz, 0, fYard, soilTop)
		placeKit("PetBed_Round_v1", Y.gx - Y.sg * 10, Y.gz - 20, face, fYard, soilTop) -- round 23: in front of the house
		for _, dz in { -16, 16 } do
			-- round 20: whatever the mesh's own pivot turn, make the long side run along z (inside the fence): yaw 0 and 90
			-- both came out along x in Studio, so measure and turn it if needed
			local fb = placeKit("FlowerBorder_Strip_v1", Y.gx + Y.sg * 0.2, Y.gz + dz, 0, fYard, soilTop)
			if fb then
				fb:ScaleTo(fb:GetScale() * 0.75) -- round 22: 9 long, clear of the pet house (scan: clip)
				local _, fsz = fb:GetBoundingBox()
				if fsz.X > fsz.Z then
					fb:PivotTo(fb:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
				end
				local fcf, fsz2 = fb:GetBoundingBox() -- re-centre on the spot after the turn (the pivot may be off-centre)
				-- round 29 (scan: FENCE 0.71 on all 12): the strip's street edge stays 1.3 inside the front fence line (~gx)
				fb:PivotTo(fb:GetPivot() + Vector3.new(Y.gx - Y.sg * (fsz2.X / 2 + 1.3) - fcf.Position.X, 0, Y.gz + dz - fcf.Position.Z))
			end
		end
		for _, dz in { -6.5, 6.5 } do
			placeKit("GardenLantern_v1", Y.fx, Y.gz + dz, face, fYard)
		end
		-- round 25 (runner: "yards are big flat empty rectangles"): flower beds along both side fences, hay and an egg
		-- crate in the back corners, round planters in the front corners. All within 4.5 of a fence, so the yard-pet
		-- spots (5 in from the fence) and the domes keep the middle.
		-- round 27: the side-fence flower beds are off (scan: FENCE 78, too close to the fence)
		for _, side in { -1, 1 } do
			-- round 26: the front-corner planters went (half buried by the gate, runner: fewer gate props); the back-corner
			-- props sit on whatever ground is under them, not the soil slab height
			local prop = placeKit(if side < 0 then "HayBale_Round_v1" else "EggCrate_Stack_v1", Y.px - Y.sg * (Y.hw - 5),
				Y.gz + side * (Y.hd - 5), 30 * k, fYard)
			if prop then
				-- round 29 (scan: FENCE 0.4-1.6, the turned box reached the fence): measure the turned box and slide it in so
				-- its edges stay 1.3 off the back fence (3.4 in from the plot edge) and the side fence
				local pcf, psz = prop:GetBoundingBox()
				local backX = Y.px - Y.sg * (Y.hw - 3.4)
				local sideZ = Y.gz + side * (Y.hd - 3.4)
				local wantX = backX + Y.sg * (psz.X / 2 + 1.3)
				local wantZ = sideZ - side * (psz.Z / 2 + 1.3)
				local nx = if Y.sg > 0 then math.max(pcf.Position.X, wantX) else math.min(pcf.Position.X, wantX)
				local nz = if side > 0 then math.min(pcf.Position.Z, wantZ) else math.max(pcf.Position.Z, wantZ)
				prop:PivotTo(prop:GetPivot() + Vector3.new(nx - pcf.Position.X, 0, nz - pcf.Position.Z))
			end
		end
		-- round 26 (runner: "two titles stack on the gate"): the plot's own sign set (post, backing, plaque, mesh) is hidden
		-- (Transparency 1, no collide, LobbyHidden = true to undo), and only its text carrier PlotSign, which MapHooks writes
		-- the owner's name on, moves onto the street face of the arch board at board size
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "PlotSign" and (string.find(d.Name, "^PlotSign") or d.Name == "SignPlaque") then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				d:SetAttribute("LobbyHidden", true)
				for _, gui in d:GetDescendants() do
					if gui:IsA("SurfaceGui") or gui:IsA("BillboardGui") then
						gui.Enabled = false
					end
				end
			end
		end
		local carrier = plot:FindFirstChild("PlotSign", true)
		if carrier and carrier:IsA("BasePart") then
			local gui = carrier:FindFirstChildWhichIsA("SurfaceGui")
			local turn = if gui and gui.Face == Enum.NormalId.Back then CFrame.Angles(0, math.pi, 0) else CFrame.identity
			if gui and gui.Face ~= Enum.NormalId.Front and gui.Face ~= Enum.NormalId.Back then
				warn("[lobby] " .. plot.Name .. ".PlotSign text is on its " .. gui.Face.Name .. " face; left where it is")
			else
				carrier.Size = Vector3.new(8.6, 2.4, 0.3)
				carrier.CFrame = base * CFrame.new(0, 7.2, -0.4) * turn
				carrier.Color = Color3.fromHex("5a3a22") -- dark wood: the green FREE PLOT and cream names read on it
				carrier.Material = Enum.Material.SmoothPlastic
				carrier.Transparency = 0
			end
		end
		local mb = CFrame.new(Y.gx - Y.sg * 1.5, soilTop, Y.gz + 9.5) -- round 28: clear of the plot gate (scan: clip) * CFrame.Angles(0, math.rad(if Y.sg > 0 then -90 else 90), 0)
		part(fYard, mb * CFrame.new(0, 1.6, 0), Vector3.new(0.4, 3.2, 0.4), "7a5230", Enum.Material.Wood, nil, true)
		part(fYard, mb * CFrame.new(0, 3.5, 0), Vector3.new(1.2, 1.1, 1.8), YCOL[k], nil, nil, true)
		part(fYard, mb * CFrame.new(0.65, 3.9, 0.3), Vector3.new(0.1, 0.8, 0.25), "ffe27a")
	end
	local slab = plot:FindFirstChild("YardSoil", true)
	if slab and slab:IsA("BasePart") then
		-- round 22: the colour trim is gone (it ran under the fences, scan: 24 FENCE hits)
		local rnd = Random.new(40 + k)
		-- round 26 (runner: "break up the bare grass"): 8 patches in three tones, each 0.012 above the last (0.004 flickers)
		local TONES = { "7fbf4d", "79b848", "84c552" } -- r29h: no lighter tone (runner: pale circles) -- r29e (runner: "pale lime circles in yards"): close to the yard green
		for j = 1, 8 do
			local px = rnd:NextNumber(-0.34, 0.34) * slab.Size.X
			local pz = rnd:NextNumber(-0.34, 0.34) * slab.Size.Z
			local rr = rnd:NextNumber(4, 8)
			local pt = flat(fYard, slab.CFrame * CFrame.new(px, 0.06 + j * 0.012, pz) * DISC, Vector3.new(0.02, rr * 2, rr * 2),
				TONES[j % 3 + 1], Enum.PartType.Cylinder)
			pt.Material = Enum.Material.Grass
			pt.CanQuery = false
			pt.Name = "YardLawnPatch"
		end
	end
	local cans = 0
	for _, ridge in plot:GetDescendants() do
		if cans < 1 and ridge:IsA("BasePart") and ridge:GetAttribute("CropRow") then
			local w = (ridge.CFrame * CFrame.new(ridge.Size.X / 2 + 1.6, ridge.Size.Y / 2, 0)).Position
			local can = placeKit("WateringCan_v1", w.X, w.Z, 30 * k, fYard, w.Y - ridge.Size.Y)
			if can then
				cans += 1
				for _, q in can:GetDescendants() do
					if q:IsA("BasePart") then
						q.CanCollide = false
						q.CanQuery = false
					end
				end
			end
		end
	end
end

-- 8c. round 27 (runner stuck at 6.9: "fuller yards, less bare grass, better walls"; carter: "do what you gotta do").
-- Everything here is placed only where it is clear: a piece that would touch a path, a plaza or anything standing is
-- removed again, so the fill never makes new clips.
local fillOp = OverlapParams.new()
fillOp.FilterType = Enum.RaycastFilterType.Exclude
local function blocked(cf: CFrame, size: Vector3, bottom: number, skip: Instance): boolean
	fillOp.FilterDescendantsInstances = { skip }
	local shrink = Vector3.new(math.max(size.X - 0.4, 0.2), math.max(size.Y - 0.2, 0.2), math.max(size.Z - 0.4, 0.2))
	for _, h in workspace:GetPartBoundsInBox(cf, shrink, fillOp) do
		if h:IsA("Terrain") then
			continue
		end
		if h:IsDescendantOf(fPath) or h:IsDescendantOf(fPlaza) then
			return true
		end
		if h.Transparency >= 1 and not h.CanCollide then
			continue
		end
		local e = h.ExtentsSize
		if e.Y <= 3 and e.X >= 12 and e.Z >= 12 then
			continue -- a floor or soil slab under the piece (round 27: the yard floors rejected every yard piece)
		end
		if h.Position.Y + e.Y / 2 > bottom + 0.45 then
			return true
		end
	end
	return false
end
local function hypot(a: number, b: number): number
	return math.sqrt(a * a + b * b)
end
-- paving is CanQuery off (flat parts), so paths and plazas are tested by their plan shapes instead
local function onPaving(x: number, z: number, r: number): boolean
	for _, pz in DATA.plazas do
		if hypot(x - pz.x, z - pz.z) < pz.r + r + 0.6 then
			return true
		end
	end
	for _, c in DATA.ponds do
		if hypot(x - c.x, z - c.z) < c.r + r + 1 then
			return true
		end
	end
	for _, c in { DATA.pile, DATA.battle } do
		if hypot(x - c.x, z - c.z) < c.r + r + 3 then
			return true
		end
	end
	if hypot(x, z) < DATA.knoll.r + r + 1 then
		return true
	end
	for _, pth in DATA.paths do
		local half = pth.w / 2 + 1.5 + r -- the stone curb is 1.5 wider each side
		local pts = pth.pts
		for k = 1, #pts - 1 do
			local ax, az, bx, bz = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
			local dx, dz = bx - ax, bz - az
			local L2 = dx * dx + dz * dz
			local t = if L2 > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / L2, 0, 1) else 0
			if hypot(x - (ax + dx * t), z - (az + dz * t)) < half then
				return true
			end
		end
	end
	return false
end
local function placeIfClear(name: string, x: number, z: number, yaw: number, parent: Instance, scale: number?, y: number?): Model?
	local m = placeKit(name, x, z, yaw, parent, y)
	if not m then
		report.nokit[name] = true
		return nil
	end
	local base = y or groundY(x, z)
	if scale and scale ~= 1 then
		m:ScaleTo(m:GetScale() * scale)
		local c0, s0 = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(0, base - (c0.Position.Y - s0.Y / 2), 0))
	end
	local cf, size = m:GetBoundingBox()
	if onPaving(cf.Position.X, cf.Position.Z, math.max(size.X, size.Z) / 2) or blocked(cf, size, base, m) then
		m:Destroy()
		return nil
	end
	return m
end

-- 1) a garden scene in every yard: a stepping-stone walk in from the gate, small trees and bushes along the back,
-- flower beds, a rock and a bench. Distances are measured in from the gate fence (d) and across from the gate line (z).
local fYardScene = sub("YardScenes")
do
	local SCENE = {
		{ "SteppingStones_v1", 21.5, 0, 1 }, { "SteppingStones_v1", 29, 0, 1 }, -- round 28: the gate already has one at 9.5
		{ "Tree_Round_S_v2", 50, -18, 0.8 }, { "Tree_Round_S_v2", 50, 18, 0.8 }, { "Tree_Round_S_v2", 30, -21, 0.75 },
		{ "Tree_Round_S_v2", 30, 21, 0.75 },
		{ "Bush_Round_A_v2", 52, -9, 0.8 }, { "Bush_Blossom_v2", 52, 0, 0.8 }, { "Bush_Round_A_v2", 52, 9, 0.8 },
		{ "Bush_Blossom_v2", 20, 20, 0.8 }, { "Bush_Round_A_v2", 20, -21, 0.8 },
		{ "FlowerBed_Big_Mixed", 36, -12, 0.5 }, { "FlowerBed_Big_Mixed", 36, 12, 0.5 }, { "FlowerBed_Big_Mixed", 26, 9, 0.45 },
		{ "Rock_Natural_A", 44, -23, 0.4 }, { "Rock_Natural_A", 15, 21, 0.35 },
		{ "Bench_Park_v1", 40, 21, 0.9 },
	}
	local n = 0
	for k, Y in DATA.yards do
		local gateX = Y.px + Y.sg * Y.hw
		local plot = find("FTP_Lobby.Plots.Plot" .. k)
		local soilPart = plot and plot:FindFirstChild("YardSoil", true)
		local top: number? = if soilPart and soilPart:IsA("BasePart") then soilPart.Position.Y + soilPart.Size.Y / 2 else nil
		for j, t in SCENE do
			local x, z = gateX - Y.sg * t[2], Y.gz + t[3]
			local yaw = if t[1] == "Bench_Park_v1" then (if Y.sg > 0 then 180 else 0) else (k * 47 + j * 83) % 360
			if placeIfClear(t[1], x, z, yaw, fYardScene, t[4], top) then
				n += 1
			end
		end
	end
	print("[LobbyRedesign] yard scene pieces: " .. n)
end

-- 2) no bare lawn: low grass tufts and little flower clusters on open ground (not on paths, plazas, yards, the TRAIN
-- flagstone or under anything standing). Built parts, no asset ids; no collide, no query, no shadow.
local fTuft = sub("LawnTufts")
do
	local g = find("LobbyMeadow.Ground")
	local tr = RaycastParams.new()
	tr.FilterType = Enum.RaycastFilterType.Include
	tr.FilterDescendantsInstances = if g then { g } else {}
	local rnd = Random.new(27)
	local GREENS = { "5f9e3a", "76b84a", "8cc95a", "6aa843" }
	local FLOWERS = { "ffffff", "ffe27a", "e0443a", "8a4fd8", "f08a2b", "4fb3e8" }
	local function inYard(x: number, z: number): boolean
		for _, Y in DATA.yards do
			if math.abs(x - Y.px) < Y.hw + 1.5 and math.abs(z - Y.gz) < Y.hd + 1.5 then
				return true
			end
		end
		return false
	end
	local function bit(cf: CFrame, size: Vector3, col: string, shape: Enum.PartType?)
		local b = flat(fTuft, cf, size, col, shape)
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.SmoothPlastic
		return b
	end
	local n = 0
	for gx = -140, 140, 7 do
		for gz = -188, 175, 7 do
			local x, z = gx + rnd:NextNumber(-3, 3), gz + rnd:NextNumber(-3, 3)
			if inYard(x, z) then
				continue
			end
			local hit = workspace:Raycast(Vector3.new(x, G0 + 40, z), Vector3.new(0, -80, 0), tr)
			if not hit or onPaving(x, z, 1.2) then
				continue
			end
			local flag = false
			for _, zn in DATA.zones do
				if zn.name == "TrainFlagstone" and hypot(x - zn.x, z - zn.z) < zn.r + 6 then
					flag = true
				end
			end
			if flag then
				continue
			end
			local y = hit.Position.Y
			if blocked(CFrame.new(x, y + 1.2, z), Vector3.new(3.4, 2.4, 3.4), y, fTuft) then
				continue
			end
			local base = CFrame.new(x, y, z) * CFrame.Angles(0, rnd:NextNumber(0, 6.28), 0)
			for b = 1, 3 do
				local h = rnd:NextNumber(0.7, 1.4)
				bit(base * CFrame.Angles(0, b * 2.1, rnd:NextNumber(-0.35, 0.35)) * CFrame.new(rnd:NextNumber(-0.4, 0.4), h / 2, 0),
					Vector3.new(0.22, h, 0.7), GREENS[rnd:NextInteger(1, #GREENS)])
			end
			if rnd:NextNumber() < 0.3 then
				local col = FLOWERS[rnd:NextInteger(1, #FLOWERS)]
				for b = 1, 3 do
					local a = b * 2.1 + 0.5
					bit(base * CFrame.new(math.cos(a) * 0.7, 0.9 + b * 0.12, math.sin(a) * 0.7), Vector3.new(0.5, 0.5, 0.5), col,
						Enum.PartType.Ball)
				end
			end
			n += 1
		end
	end
	print("[LobbyRedesign] lawn tufts: " .. n)
end

-- 3) the wall: leafy ivy down the inner face of every other cliff (found by a ray, like the towers) and a bush at the
-- foot of each cliff on the park side, so the ring has depth and green at both ends
do
	local ivy, foot = 0, 0
	local cr = RaycastParams.new()
	cr.FilterType = Enum.RaycastFilterType.Include
	local k = 0
	for _, m in fEdge:GetChildren() do
		if not (m:IsA("Model") and string.match(m.Name, "^Cliff_")) then
			continue
		end
		k += 1
		local cf, size = m:GetBoundingBox()
		local p = cf.Position
		local inward = Vector3.new(-p.X, 0, -p.Z)
		-- the wall runs along x on the north and south sides and along z on the east and west sides
		inward = if math.abs(p.X) > 140 then Vector3.new(-math.sign(p.X), 0, 0) else Vector3.new(0, 0, -math.sign(p.Z))
		cr.FilterDescendantsInstances = { m }
		local hit = workspace:Raycast(p + inward * 30 + Vector3.new(0, size.Y * 0.15, 0), -inward * 60, cr)
		if hit and k % 2 == 0 then
			local iv = placeKit("LeafIvy_Hang_v1", hit.Position.X, hit.Position.Z, 0, fEdge, hit.Position.Y - 3)
			if iv then
				local pv = iv:GetPivot().Position + inward * 0.6
				iv:PivotTo(CFrame.lookAt(pv, pv + inward))
				ivy += 1
			end
		end
		if hit then
			local at = hit.Position + inward * 3.6
			local names = { "Bush_Round_A_v2", "Bush_Blossom_v2", "Bush_Round_B_v2" }
			if placeIfClear(names[k % 3 + 1], at.X, at.Z, k * 37 % 360, fEdge, 1.1 + (k % 2) * 0.3) then
				foot += 1
			end
		end
	end
	print("[LobbyRedesign] wall ivy " .. ivy .. ", wall-foot bushes " .. foot)
end

-- 9. light. Round 29 (carter 10-15, screenshot: "I like this old brightness setup we had"): the exact pre-redesign
-- Lighting from shared/VibeGrade.Lighting (deep blue sky, crisp shadows, no grey haze). Place-wide, so hunts, arenas
-- and islands match. The values rounds 26-28 had are kept once as RedesignOld_* attributes on Lighting.
local Lighting = game:GetService("Lighting")
local VL = VibeGrade.Lighting
local function rgb(t: { number }): Color3
	return Color3.new(t[1], t[2], t[3])
end
local function child(className: string, name: string): Instance
	local found = Lighting:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	for _, c in Lighting:GetChildren() do -- an unnamed one of the class (not a named grade we set ourselves)
		if c.ClassName == className and c.Name ~= "ColorCorrection" and c.Name ~= "Grade" and className ~= "ColorCorrectionEffect" then
			c.Name = name
			return c
		end
	end
	local n = Instance.new(className)
	n.Name = name
	n.Parent = Lighting
	return n
end
if Lighting:GetAttribute("RedesignOld_Ambient") == nil then
	Lighting:SetAttribute("RedesignOld_Ambient", Lighting.Ambient)
	Lighting:SetAttribute("RedesignOld_OutdoorAmbient", Lighting.OutdoorAmbient)
	Lighting:SetAttribute("RedesignOld_ExposureCompensation", Lighting.ExposureCompensation)
	Lighting:SetAttribute("RedesignOld_ColorShift_Top", Lighting.ColorShift_Top)
	Lighting:SetAttribute("RedesignOld_Brightness", Lighting.Brightness)
end
Lighting.Brightness = VL.Brightness
Lighting.ExposureCompensation = VL.ExposureCompensation
Lighting.ClockTime = VL.ClockTime
Lighting.GeographicLatitude = VL.GeographicLatitude
Lighting.Ambient = rgb(VL.Ambient)
Lighting.OutdoorAmbient = rgb(VL.OutdoorAmbient)
Lighting.ColorShift_Top = rgb(VL.ColorShiftTop)
Lighting.ShadowSoftness = VL.ShadowSoftness
Lighting.EnvironmentDiffuseScale = VL.EnvironmentDiffuseScale
Lighting.EnvironmentSpecularScale = VL.EnvironmentSpecularScale
Lighting.GlobalShadows = true
-- r29g: crisp sun shadows come from Lighting Style "Realistic" (this Studio has no Technology). Only a write is tried
-- (a read can throw "lacking capability" from the command bar); if it is refused, it is set by hand.
local styleOk = pcall(function()
	(Lighting :: any).LightingStyle = (Enum :: any).LightingStyle[VL.LightingStyle]
end)
print("[LobbyRedesign] lighting style: " .. (if styleOk then "set to " .. VL.LightingStyle
	else "NOT set by script: Lighting > Lighting Style = " .. VL.LightingStyle .. " by hand"))
-- exactly the two old grades: any other ColorCorrectionEffect (round 26 "GameGrade") is parked in the backup
local backups = SS:FindFirstChild("LobbyBackups")
for _, c in Lighting:GetChildren() do
	if c:IsA("ColorCorrectionEffect") and c.Name ~= "ColorCorrection" and c.Name ~= "Grade" then
		c.Parent = backups
	end
end
for name, g in { ColorCorrection = VL.ColorCorrection, Grade = VL.Grade } do
	local cc = child("ColorCorrectionEffect", name) :: ColorCorrectionEffect
	cc.Saturation, cc.Contrast, cc.Brightness, cc.TintColor = g.Saturation, g.Contrast, g.Brightness, rgb(g.Tint)
	cc.Enabled = true
end
local at = child("Atmosphere", "Atmosphere") :: Atmosphere
local A = VL.Atmosphere
at.Density, at.Offset, at.Glare, at.Haze = A.Density, A.Offset, A.Glare, A.Haze
at.Color, at.Decay = rgb(A.Color), rgb(A.Decay)
local bloom = child("BloomEffect", "Bloom") :: BloomEffect
bloom.Intensity, bloom.Size, bloom.Threshold = VL.Bloom.Intensity, VL.Bloom.Size, VL.Bloom.Threshold
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
if clouds then
	clouds.Enabled = VL.TerrainClouds
end
print(string.format("[LobbyRedesign] light: old look, brightness %.2f, exposure %.2f, haze %.2f, grades %.2f + %.2f saturation, terrain clouds %s",
	Lighting.Brightness, Lighting.ExposureCompensation, at.Haze, VL.ColorCorrection.Saturation, VL.Grade.Saturation, tostring(VL.TerrainClouds)))

-- 9b. chunky low-poly clouds (round 29, carter's old shot: blocky white clouds in a deep blue sky). Each cloud is 4-6
-- white blocks, no collision, no shadow, high outside the walls, so they never touch play space.
do
	local fCloud = sub("SkyClouds")
	local rnd = Random.new(29)
	for k = 0, 25 do -- r29h: 26 clouds (runner: sparse in some views)
		local a = math.rad(k * 360 / 26 + rnd:NextNumber(-5, 5))
		-- r29e: half high (G0+150-210), half lower and nearer (G0+80-120, 190-280) so a phone at the spawn sees several
		local low = k % 2 == 1
		local r = if low then rnd:NextNumber(190, 280) else rnd:NextNumber(230, 380)
		local c = CFrame.new(math.sin(a) * r, G0 + (if low then rnd:NextNumber(80, 120) else rnd:NextNumber(150, 210)), -math.cos(a) * r)
			* CFrame.Angles(0, rnd:NextNumber(0, 2 * math.pi), 0)
		local w = rnd:NextNumber(60, 100) -- r29e: bigger, chunkier (was 26-44)
		local kc = KIT and KIT:FindFirstChild(({ "Cloud_A_v1", "Cloud_B_v1", "Cloud_C_v1", "Cloud_D_v1" })[k % 4 + 1], true)
		if kc then -- round 30: kit 1015j cloud meshes, fitted to this cloud's width
			local m = kc:Clone()
			if m:IsA("BasePart") then
				local w2 = Instance.new("Model")
				m.Parent = w2
				w2.PrimaryPart = m
				m = w2
			end
			local mm = m :: Model
			mm.Name = "Cloud_" .. k
			local ext = mm:GetExtentsSize()
			mm:ScaleTo(mm:GetScale() * w / math.max(ext.X, ext.Z, 1))
			mm:PivotTo(c)
			for _, d in mm:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
				end
			end
			mm.Parent = fCloud
			kitUsed.Cloud = (kitUsed.Cloud or 0) + 1
			continue
		end
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud_" .. k
		cloud.Parent = fCloud
		for j = 0, rnd:NextInteger(4, 6) do
			local sx = w * rnd:NextNumber(0.4, 0.65)
			local b = Instance.new("Part")
			b.Name = "Puff"
			b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch, b.CastShadow = true, false, false, false, false
			b.Material = Enum.Material.SmoothPlastic
			b.Color = Color3.fromHex(if j == 0 then "ffffff" else "f4f8ff")
			b.Size = Vector3.new(sx, sx * rnd:NextNumber(0.45, 0.7), sx * rnd:NextNumber(0.6, 0.9))
			b.CFrame = c * CFrame.new((j / 5 - 0.5) * w * 0.8, rnd:NextNumber(-1, 3), rnd:NextNumber(-4, 4))
				* CFrame.Angles(rnd:NextNumber(-0.25, 0.25), rnd:NextNumber(0, 1.2), rnd:NextNumber(-0.2, 0.2))
			b.Parent = cloud
		end
	end
	print("[LobbyRedesign] chunky clouds: 26")
	local used = {}
	for n, c in kitUsed do
		table.insert(used, n .. " x" .. c)
	end
	table.sort(used)
	print("[LobbyRedesign] kit 1015j used: " .. (if #used > 0 then table.concat(used, ", ") else "none (not imported yet, old pieces kept)"))
end

-- 10. anything bright left floating outside the walls (round 6 runner: a white rock/cloud east of the wall) goes to
-- the bin; the report names each one so it can be put back if it was wanted
local floaters = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and not d:IsA("Terrain") and not d:IsDescendantOf(ROOT) and d:IsDescendantOf(workspace) then
		local p = d.Position
		local outside = math.abs(p.X) > 147 or p.Z < -193 or p.Z > 179
		local c = d.Color
		if outside and math.min(c.R, c.G, c.B) > 0.8 and p.Y - d.Size.Y / 2 > G0 + 6 and d.Size.Magnitude < 80 and d.Transparency < 1 then
			local what: Instance = d
			local m = d.Parent
			if m and m:IsA("Model") and #m:GetDescendants() <= 8 then
				what = m
			end
			table.insert(floaters, what:GetFullName())
			what.Parent = bin
		end
	end
end
print("[LobbyRedesign] bright floating things outside the walls, moved to the bin: "
	.. (if #floaters > 0 then table.concat(floaters, ", ") else "none"))

local nok = {}
for k in report.nokit do
	table.insert(nok, k)
end
print(("[LobbyRedesign] moved %d hooks, archived %d old groups, %d parts in LobbyRedesign"):format(
	report.moved, report.archived, #ROOT:GetDescendants()))
print("[LobbyRedesign] missing hooks: " .. (if #report.missing > 0 then table.concat(report.missing, ", ") else "none"))
print("[LobbyRedesign] kit models not found: " .. (if #nok > 0 then table.concat(nok, ", ") else "none"))

-- 11. vibe pass (round 29, carter 10-15: "the map doesn't look vibrant enough to appeal to kids"): every coloured,
-- untextured part of the lobby gets shared/VibeGrade.lift from its ORIGINAL colour (kept in VibeBase, so a re-run never
-- stacks); grass and soil tops lose the dull texture (SmoothPlastic, the flat-shaded pet look). Greys, whites and
-- stone stay. Pets, characters, UI-carrying signs and textured meshes are left alone. Prints the before/after mean.
do
	local function inLobby(p: Vector3): boolean
		return math.abs(p.X) <= 150 and p.Z >= -196 and p.Z <= 182 and p.Y < G0 + 80
	end
	local calm = { ROOT:FindFirstChild("Plazas"), ROOT:FindFirstChild("Paths"), ROOT:FindFirstChild("BattleRing") }
	local function skip(d: Instance): boolean
		for _, f in calm do -- r29e (runner: plaza floor orange/red, paths orange-gold): paving keeps its calm sand colour
			if f and d:IsDescendantOf(f) then
				return true
			end
		end
		if string.find(d:GetFullName(), "OuterHills", 1, true) then
			return true -- r29j: far hills keep a calm green (lifted they read yellow-green)
		end
		local cm = d:FindFirstAncestorWhichIsA("Model")
		if cm and string.find(cm.Name, "^Cliff") then
			return true -- r29h: the cliff stone keeps its calm blue-grey
		end
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			return true -- neon is bright enough already (r29e: "glow trim blown out")
		end
		local m = d:FindFirstAncestorWhichIsA("Model")
		while m do
			if m:FindFirstChildOfClass("Humanoid") or string.find(m.Name, "Pet_", 1, true) then
				return true
			end
			m = m:FindFirstAncestorWhichIsA("Model")
		end
		return d:IsA("MeshPart") and d.TextureID ~= "" or d:FindFirstChildOfClass("SurfaceAppearance") ~= nil
	end
	local n, flat, s0, s1 = 0, 0, 0, 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("Terrain") and d.Transparency < 1 and inLobby(d.Position) and not skip(d) then
			-- the stored original, unless the build set a new colour since the last lift (then that is the original)
			local base = d:GetAttribute("VibeBase")
			if typeof(base) == "Color3" then
				local lr, lg, lb = VibeGrade.lift(base.R, base.G, base.B)
				if Color3.new(lr, lg, lb):ToHex() ~= d.Color:ToHex() then
					base = d.Color
				end
			else
				base = d.Color
			end
			d:SetAttribute("VibeBase", base)
			local c = base :: Color3
			local r, g, b = VibeGrade.lift(c.R, c.G, c.B)
			d.Color = Color3.new(r, g, b)
			local _, sa = VibeGrade.toHsv(c.R, c.G, c.B)
			local _, sb = VibeGrade.toHsv(r, g, b)
			n += 1
			s0 += sa
			s1 += sb
			if VibeGrade.FlatMaterials[d.Material.Name] and math.min(d.Size.X, d.Size.Y, d.Size.Z) < 4
				and math.max(d.Size.X, d.Size.Y, d.Size.Z) >= 4 then
				if d:GetAttribute("VibeBaseMaterial") == nil then
					d:SetAttribute("VibeBaseMaterial", d.Material.Name)
				end
				d.Material = Enum.Material.SmoothPlastic
				flat += 1
			end
		end
	end
	-- r29j (runner: castle and big stone surfaces near-white in the sun): big untextured near-white neutral parts become
	-- a light stone; signs (SurfaceGui), pets and characters are left alone. Original kept in VibeBase.
	local stoned = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("Terrain") and d.Transparency < 0.5 and inLobby(d.Position) and d.Size.Magnitude > 12
			and not d:FindFirstChildWhichIsA("SurfaceGui") and not skip(d) and d.Material ~= Enum.Material.Neon then
			local _, sat, val = VibeGrade.toHsv(d.Color.R, d.Color.G, d.Color.B)
			if sat < 0.12 and val > 0.86 then
				if d:GetAttribute("VibeBase") == nil then
					d:SetAttribute("VibeBase", d.Color)
				end
				d.Color = Color3.fromHex("cfc8ba")
				stoned += 1
			end
		end
	end
	print("[LobbyRedesign] near-white big parts toned to light stone: " .. stoned)
	-- r29e (runner: "lamps and trees barely cast shadows"): every tree and lamp of ours casts one
	local casters = 0
	for _, m in ROOT:GetDescendants() do
		if m:IsA("Model") and (string.find(m.Name, "^Tree") or string.find(m.Name, "^Pine_") or string.find(m.Name, "Lamp")) then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.5 and not d.CastShadow then
					d.CastShadow = true
					casters += 1
				end
			end
		end
	end
	print("[LobbyRedesign] tree and lamp parts set to cast shadows: " .. casters)
	-- r29h (launch-picks thread: the rainbow trail rides the paths by raycast): path strips can be hit by queries
	local paths = ROOT:FindFirstChild("Paths")
	local q = 0
	for _, d in if paths then paths:GetDescendants() else {} do
		if d:IsA("BasePart") then
			d.CanQuery = true
			q += 1
		end
	end
	print("[LobbyRedesign] path strips queryable: " .. q)
	print(string.format("[LobbyRedesign] vibe pass: %d parts lifted (mean saturation %.2f -> %.2f), %d grass/soil tops flat-shaded",
		n, if n > 0 then s0 / n else 0, if n > 0 then s1 / n else 0, flat))
end
