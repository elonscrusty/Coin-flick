-- Lobby glitch scan (2026-10-15, carter: "play throughs and walk throughs to fix all the visual and asset placement
-- glitches"). Studio command bar, EDIT mode, after build_lobby.luau. Read-only: it changes nothing, it prints a report.
-- Checks every object in Workspace.LobbyRedesign (kit clones, props, yard dressing) and the hooks it moved:
--   FLOAT   bottom more than 0.25 above whatever is under it (ray down from 4 points of its box)
--   BURIED  bottom more than 0.6 below the ground under it
--   CLIP    a solid part of one object overlaps a solid part of another object by more than 0.15 studs
--   FENCE   anything of ours touching a yard fence / gate part
--   ZFIGHT  two flat parts (from different objects) at the same height (within 0.01) that overlap from above
-- Prints GLITCHES <n> and one line per glitch: kind, object path, other object, amount, position.
local ROOT = workspace:FindFirstChild("LobbyRedesign")
assert(ROOT, "run build_lobby.luau first")
local out = {}
local function add(kind, a: Instance, b: Instance?, amt: number, pos: Vector3)
	table.insert(out, ("%s  %s  %s  %.2f  (%.1f, %.1f, %.1f)"):format(kind, a:GetFullName(), if b then b:GetFullName() else "-", amt,
		pos.X, pos.Y, pos.Z))
end
-- the "objects": each direct child model / part of the sub folders (a folder of loose parts counts part by part)
local objects: { Instance } = {}
for _, folder in ROOT:GetChildren() do
	for _, o in folder:GetChildren() do
		table.insert(objects, o)
	end
end
local function ownerOf(p: Instance): Instance?
	local x: Instance? = p
	while x and x.Parent and x.Parent.Parent ~= ROOT do
		x = x.Parent
	end
	return if x and x.Parent and x.Parent.Parent == ROOT then x else nil
end
local function box(o: Instance): (CFrame, Vector3)
	if o:IsA("Model") then
		return o:GetBoundingBox()
	end
	local p = o :: BasePart
	return p.CFrame, p.Size
end
-- round 21: things that sit low, stack or float on purpose (paths and grounds are sunk flat layers, cliffs and wall
-- bushes are sunk into the ground, eggs stack on the pile, badges, names, icons and sparkles hover)
local SKIP_FOLDERS = { Paths = true, EggPile = true, ZoneGrounds = true, Ponds = true, Plazas = true, GrassPatches = true,
	Sparkles = true, FarMountains = true, FarHills = true, SkyClouds = true, BattleRing = true, ShopSquare = true, LawnTufts = true }
local function skipLevel(o: Instance): boolean
	local folder = o.Parent and o.Parent.Name or ""
	if SKIP_FOLDERS[folder] then
		return true
	end
	local n = o.Name
	return string.find(n, "^Cliff_") ~= nil or string.find(n, "^Bush_") ~= nil or string.find(n, "^YardNumber") ~= nil
		or string.find(n, "^Icon_") ~= nil or (string.find(n, "^Tree_") ~= nil or string.find(n, "^Pine_") ~= nil) and folder == "EdgeCliffs"
		or string.find(n, "^RockWall_") ~= nil
		or string.find(n, "^LeafIvy") ~= nil or n == "YardLawnPatch" or ((folder == "ZoneArches" or folder == "YardGates") and o:IsA("BasePart")) -- round 23: hand-built gate arches stand on posts by design
end
local function isFlat(o: Instance): boolean
	local _, s = box(o)
	return s.Y < 0.5
end
-- 1. float / buried: rays down from the four lower corners, ignoring the object itself and anything hovering (no collide
-- and no query parts like signs still count as ground only if they are BaseParts with CanQuery)
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
for _, o in objects do
	if not (o:IsA("Model") or o:IsA("BasePart")) or isFlat(o) or skipLevel(o) then
		continue
	end
	local cf, s = box(o)
	if s.Y > 60 or (cf.Position.Y - s.Y / 2) > 30 then
		continue -- far mountains, roofs, floating names: not ground objects
	end
	ray.FilterDescendantsInstances = { ROOT } -- round 22: the ground is the world under our dressing (our own loose parts made false BURIED)
	local bottom = cf.Position.Y - s.Y / 2
	local lowestGap, highestGap = math.huge, -math.huge
	for _, c in { Vector3.new(-0.3, 0, -0.3), Vector3.new(0.3, 0, -0.3), Vector3.new(-0.3, 0, 0.3), Vector3.new(0.3, 0, 0.3), Vector3.zero } do
		local at = cf.Position + Vector3.new(c.X * s.X, 0, c.Z * s.Z)
		local hit = workspace:Raycast(Vector3.new(at.X, bottom + 6, at.Z), Vector3.new(0, -40, 0), ray)
		if hit then
			local gap = bottom - hit.Position.Y
			lowestGap = math.min(lowestGap, gap)
			highestGap = math.max(highestGap, gap)
		end
	end
	if lowestGap ~= math.huge then
		if lowestGap > 0.45 then -- paving and lawn layers have CanQuery off, so a prop on them reads up to ~0.4 high
			add("FLOAT", o, nil, lowestGap, cf.Position)
		elseif highestGap < -0.6 then
			add("BURIED", o, nil, -highestGap, cf.Position)
		end
	end
end
-- round 29: overlaps that are the design, not glitches: the boundary wall (EdgeCliffs: cliffs, towers, buttresses,
-- ivy and the pines planted on the outer hills) interlocks with itself and the OuterHills outside the play space so it
-- has no gaps; and loose parts of one hand-built thing (pond rim stones, battle ring blocks, shop square, gate arches)
-- touch their neighbours in the same folder on purpose.
local WALL = { EdgeCliffs = true, OuterHills = true }
local BUILT = { Ponds = true, BattleRing = true, ShopSquare = true, YardGates = true }
local function folderOf(x: Instance): string
	local f = x.Parent
	return if f then f.Name else ""
end
local function byDesign(a: Instance, b: Instance): boolean
	local fa, fb = folderOf(a), folderOf(b)
	if WALL[fa] and (WALL[fb] or string.find(b:GetFullName(), "OuterHills", 1, true) ~= nil) then
		return true
	end
	return fa == fb and BUILT[fa] == true and a:IsA("BasePart") and b:IsA("BasePart")
end
-- 2. clip + fence: solid parts of ours against every solid part in the world that is not in the same object
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local seen: { [string]: boolean } = {}
for _, o in objects do
	local parts = if o:IsA("BasePart") then { o } else o:GetDescendants()
	overlap.FilterDescendantsInstances = { o }
	for _, p in parts do
		if not p:IsA("BasePart") or not p.CanCollide or p.Transparency >= 1 or p.Size.Magnitude < 0.5 then
			continue
		end
		-- the part's own box, shrunk 0.15 on every side so plain touching doesn't count
		local shrunk = Vector3.new(math.max(p.Size.X - 0.3, 0.05), math.max(p.Size.Y - 0.3, 0.05), math.max(p.Size.Z - 0.3, 0.05))
		for _, q in workspace:GetPartBoundsInBox(p.CFrame, shrunk, overlap) do
			if not q.CanCollide or q.Transparency >= 1 or q:IsDescendantOf(workspace.Terrain) then
				continue
			end
			local other = ownerOf(q) or q.Parent or q
			local isFence = string.find(q:GetFullName(), "Plots", 1, true) ~= nil
			if isFence then
				continue -- a yard fence is one big mesh, so its box covers the whole yard; fences are tested by rays below
			end
			if byDesign(o, other) then
				continue
			end
			local key = o:GetFullName() .. "|" .. other:GetFullName()
			if seen[key] or seen[other:GetFullName() .. "|" .. o:GetFullName()] then
				continue
			end
			seen[key] = true
			add("CLIP", o, other, 0, p.Position)
		end
	end
end
-- 2b. fence: rays across each yard object at knee height, 8 ways from its middle out to its own edge; a fence hit
-- inside the object's footprint (more than 0.15 in) is a FENCE glitch
do
	local fences: { Instance } = {}
	local lobby = workspace:FindFirstChild("FTP_Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	if plots then
		for _, d in plots:GetDescendants() do
			if d:IsA("BasePart") and (string.find(d.Name, "Fence", 1, true) or string.find(d.Name, "Rail", 1, true)
				or string.find(d.Name, "Post", 1, true) or string.find(d.Name, "Gate", 1, true)) then
				table.insert(fences, d)
			end
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = fences
	local yards = ROOT:FindFirstChild("YardGates")
	for _, o in if yards then yards:GetChildren() else {} do
		if not (o:IsA("Model") or o:IsA("BasePart")) then
			continue
		end
		local cf, s = box(o)
		for k = 0, 7 do
			local a = k * math.pi / 4
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local reach = math.abs(dir.X) * s.X / 2 + math.abs(dir.Z) * s.Z / 2
			local from = cf.Position + Vector3.new(0, -s.Y / 2 + math.min(1, s.Y / 2), 0)
			local hit = workspace:Raycast(from, dir * reach, rp)
			if hit and reach - hit.Distance > 0.15 then
				add("FENCE", o, hit.Instance, reach - hit.Distance, hit.Position)
				break
			end
		end
	end
end
-- 3. z-fight: flat parts of different objects at the same height, overlapping from above
local flats: { BasePart } = {}
for _, d in ROOT:GetDescendants() do
	-- round 27: grass tuft blades are thin but upright and cross each other on purpose (not ground layers)
	if d:IsA("BasePart") and d.Transparency < 1 and math.min(d.Size.X, d.Size.Y, d.Size.Z) < 0.3 and not (d.Parent and d.Parent.Name == "LawnTufts") then
		table.insert(flats, d)
	end
end
local function topY(p: BasePart): number
	return p.Position.Y + math.abs(p.CFrame.UpVector.Y) * p.Size.Y / 2 + math.abs(p.CFrame.RightVector.Y) * p.Size.X / 2
		+ math.abs(p.CFrame.LookVector.Y) * p.Size.Z / 2
end
-- the flat part's top face as a rectangle in XZ: centre, two half-axes
local function rect(p: BasePart): (Vector2, { Vector2 })
	local cf, sz = p.CFrame, p.Size
	local axes = {}
	for _, v in { { cf.RightVector, sz.X }, { cf.UpVector, sz.Y }, { cf.LookVector, sz.Z } } do
		local dir, len = v[1], v[2]
		if math.abs(dir.Y) < 0.7 then -- a horizontal axis of the part
			local flat = Vector2.new(dir.X, dir.Z)
			if flat.Magnitude > 1e-6 then
				table.insert(axes, flat.Unit * len / 2)
			end
		end
	end
	return Vector2.new(cf.Position.X, cf.Position.Z), axes
end
-- a lying disc (Cylinder whose axis is vertical): its radius, else nil
local function discRadius(p: BasePart): number?
	if p:IsA("Part") and p.Shape == Enum.PartType.Cylinder and math.abs(p.CFrame.RightVector.Y) > 0.7 then
		return math.min(p.Size.Y, p.Size.Z) / 2
	end
	return nil
end
local function footprintsOverlap(a: BasePart, b: BasePart): boolean
	local ca, ha = rect(a)
	local cb, hb = rect(b)
	local ra, rb = discRadius(a), discRadius(b)
	if ra and rb then -- two discs: circles (the square guess flagged zone grounds 1.3 apart)
		return (cb - ca).Magnitude < ra + rb - 0.01
	end
	if ra or rb then -- disc against a rectangle: nearest point of the rectangle to the circle centre
		local cc, rr, rc, rh = if ra then ca else cb, (ra or rb) :: number, if ra then cb else ca, if ra then hb else ha
		if #rh < 2 then
			return true
		end
		local d = cc - rc
		local u1, u2 = rh[1].Unit, rh[2].Unit
		local x = math.clamp(d:Dot(u1), -rh[1].Magnitude, rh[1].Magnitude)
		local y = math.clamp(d:Dot(u2), -rh[2].Magnitude, rh[2].Magnitude)
		return (d - (u1 * x + u2 * y)).Magnitude < rr - 0.01
	end
	if #ha < 2 or #hb < 2 then
		return true -- not a lying flat piece: keep the old cautious answer
	end
	local d = cb - ca
	for _, axis in { ha[1].Unit, ha[2].Unit, hb[1].Unit, hb[2].Unit } do
		local ra = math.abs(ha[1]:Dot(axis)) + math.abs(ha[2]:Dot(axis))
		local rb = math.abs(hb[1]:Dot(axis)) + math.abs(hb[2]:Dot(axis))
		if math.abs(d:Dot(axis)) >= ra + rb - 0.01 then
			return false
		end
	end
	return true
end
local zf = 0
for i = 1, #flats do
	local a = flats[i]
	for j = i + 1, #flats do
		local b = flats[j]
		if math.abs(topY(a) - topY(b)) < 0.01 and ownerOf(a) ~= ownerOf(b) and a.Color ~= b.Color then
			-- round 29: the real top-face footprints must overlap (separating-axis test on the two rectangles); the old
			-- centre-distance guess flagged plaza tiles of neighbouring rings that have a 0.6 gap
			if footprintsOverlap(a, b) then
				zf += 1
				if zf <= 60 then
					add("ZFIGHT", a, b, 0, a.Position)
				end
			end
		end
	end
end
print(("GLITCHES %d  (objects %d, flat parts %d, z-fight pairs %d)"):format(#out, #objects, #flats, zf))
for _, l in out do
	print(l)
end
