-- placement: numeric placement audit of the built lobby and one hunt arena (Master Prompt 8 sections 5, 23).
-- Boots the real server and client, starts a solo hunt (so an arena exists), then measures every BasePart of
-- Workspace.CT_Rocks_Lobby and Workspace.CT_Rocks_Arena_<n> and reports, with numbers:
--   CAMIGNORE  visible decorative parts (non-colliding) without the CameraIgnore attribute
--   QUERY      visible decorative parts that still answer raycasts (CanQuery) inside the walkable area, so they
--              could catch the interaction ray or the line-of-sight check
--   FLOAT      top-level props whose lowest point is more than 0.2 studs above the ground under them and that
--              rest on nothing
--   BURY       props sunk more than 0.5 studs below the ground (cliffs, walls, rock masses and floors exempt:
--              they reach under the floor on purpose)
--   ZFIGHT     two visible flat faces at the same height (within 0.004) that overlap
--   ROUTE      collidable geometry standing in a walking route (lobby clear zones, arena pile -> table lanes,
--              table -> hopper lanes) or decor answering raycasts there
--   NOCOLLIDE  solid-looking kit furniture in the walkable area (over 1.5 tall) with no collision under it
--   BIGBLOCK   invisible blockers much larger than the visible thing they stand in for
--   CLIP       two separate props interpenetrating by more than a quarter of the smaller one
-- Every finding is one "[FAIL] <CHECK> <path> <numbers>" line; the scene ends with "PLACEMENT PASS" or
-- "PLACEMENT FAIL: n". --set area=lobby|arena limits the audit, --set verbose=on lists the measured props.
-- Offline only (preview mock: no physics, mesh collision is what the code set). Nothing here is a Studio test.
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local area = preview.args.area or "both"
local verbose = preview.args.verbose == "on"

-- the player owns a display with 4 made-up specimens, so one claimed cabinet (built later by the gallery) is audited
local s = C.boot({
	profile = function(data)
		local specs = C.fakeSpecimens(4)
		data.InventoryGeodes = specs
		data.DisplayCapacity = 4
		data.DisplayAssignments = {}
		for _, g in ipairs(specs) do
			table.insert(data.DisplayAssignments, g.Id)
		end
	end,
})
C.settle(1)
local gallery = C.server("GalleryService")
if gallery then
	gallery.render(s.me)
end
local w = C.watchMatch()
local init = nil
if area ~= "lobby" then
	init = C.startSolo(w)
	C.waitPhase(w, "Searching", 8)
end
C.settle(1)

local fails = 0
local counts: { [string]: number } = {}
local function fail(check: string, inst: Instance, detail: string)
	fails += 1
	counts[check] = (counts[check] or 0) + 1
	if counts[check] <= 40 or preview.args.all == "on" then
		print(string.format("[FAIL] %-9s %s  %s", check, inst:GetFullName(), detail))
	end
end

-- world AABB of a part
local function box(p: BasePart): (Vector3, Vector3)
	local cf, sz = p.CFrame, p.Size
	local r = cf - cf.Position
	local hx = math.abs(r.RightVector.X) * sz.X + math.abs(r.UpVector.X) * sz.Y + math.abs(-r.LookVector.X) * sz.Z
	local hy = math.abs(r.RightVector.Y) * sz.X + math.abs(r.UpVector.Y) * sz.Y + math.abs(-r.LookVector.Y) * sz.Z
	local hz = math.abs(r.RightVector.Z) * sz.X + math.abs(r.UpVector.Z) * sz.Y + math.abs(-r.LookVector.Z) * sz.Z
	local h = Vector3.new(hx, hy, hz) / 2
	return cf.Position - h, cf.Position + h
end

local function overlap1(a0: number, a1: number, b0: number, b1: number): number
	return math.max(0, math.min(a1, b1) - math.max(a0, b0))
end

local function inCharacter(d: Instance): boolean
	for _, pl in Players:GetPlayers() do
		if pl.Character and d:IsDescendantOf(pl.Character) then
			return true
		end
	end
	return false
end

-- parts whose job is to be hit by rays / be walked on / carry a prompt (not decor)
local FUNCTIONAL = {
	Body = true, Counter = true, Cabinet = true, Floor = true, Surface = true, Plate = true, InputTray = true,
	OutputTray = true, DockPad = true, Stand = true, Feed = true, Pad = true, Apron = true, TableBody = true,
	PreviewAnchor = true, Nameplate = true, Sign = true, Light = true,
}
local function functional(p: BasePart): boolean
	if FUNCTIONAL[p.Name] or p:FindFirstChildWhichIsA("ProximityPrompt") or p:FindFirstChildWhichIsA("SurfaceGui") then
		return true
	end
	local m = p:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:GetAttribute("StationIndex") ~= nil or m:GetAttribute("Hopper") ~= nil or m:GetAttribute("MachineId") ~= nil then
			return true -- tables, sellers and machines own their own ray policy (StationModels / MachineModels)
		end
		m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model") or nil
	end
	return false
end

local CANOPY = { Leaf = true, LeafDark = true, Leaves = true, Sage = true, SageDark = true }
local function decor(p: BasePart): boolean
	return not p.CanCollide and p.Transparency < 1 and not functional(p)
end

-- exempt from BURY: they reach under the floor on purpose
local DEEP = { "Cliff", "Strata", "Ground", "Plaza", "Floor", "Bench", "Wall", "Rock", "Bounds", "Mass", "Step", "Face", "Boulder", "Road", "Waterfall", "Ledge", "Edge.", "Boundary.", "Lodge_Building" }
local function deep(name: string): boolean
	-- the CT_Rocks_ prefix of every game name is not a rock
	local n = string.gsub(name, "CT_Rocks_", "")
	for _, k in DEEP do
		if string.find(n, k, 1, true) then
			return true
		end
	end
	return false
end

local function audit(root: Instance, ground: (Vector3) -> number, walk: (Vector3) -> boolean, routes: { { any } }, label: string)
	local parts: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not inCharacter(d) then
			table.insert(parts, d)
		end
	end
	print(string.format("[audit] %s: %d parts", label, #parts))

	-- CAMIGNORE / QUERY
	for _, p in parts do
		if decor(p) then
			if p:GetAttribute("CameraIgnore") ~= true then
				fail("CAMIGNORE", p, "")
			end
			if p.CanQuery then
				local lo, hi = box(p)
				local c = (lo + hi) / 2
				if walk(c) and lo.Y < ground(c) + 12 then
					fail("QUERY", p, string.format("at (%.1f, %.1f, %.1f)", c.X, c.Y, c.Z))
				end
			end
		end
	end

	-- ROUTE: collidable geometry (or ray-catching decor) inside a walking route, above the floor. Tested in the
	-- part's own frame (rotated tables and walls are not inflated to their axis-aligned box).
	for _, p in parts do
		local blocks = (p.CanCollide and p.Name ~= "CT_Rocks_LobbySpawn") or (p.CanQuery and decor(p))
		if blocks then
			local lo, hi = box(p)
			local c = (lo + hi) / 2
			-- a walkable slab up to 0.45 (a step the avatar climbs without jumping) is floor, not an obstacle
			if hi.Y > ground(c) + 0.45 and lo.Y < ground(c) + 7 then
				for _, r in routes do
					local name, x0, x1, z0, z1 = r[1], r[2], r[3], r[4], r[5]
					local ox, oz = overlap1(lo.X, hi.X, x0, x1), overlap1(lo.Z, hi.Z, z0, z1)
					if ox > 0.05 and oz > 0.05 then
						local rc = Vector3.new((x0 + x1) / 2, p.Position.Y, (z0 + z1) / 2)
						local l = p.CFrame:PointToObjectSpace(rc)
						local hw, hd = (x1 - x0) / 2, (z1 - z0) / 2
						local ex = p.Size.X / 2 + math.max(hw, hd) * 0.75
						local ez = p.Size.Z / 2 + math.max(hw, hd) * 0.75
						if math.abs(l.X) < ex - 0.05 and math.abs(l.Z) < ez - 0.05 then
							fail("ROUTE", p, string.format("%s, route centre %.2f / %.2f inside (half %.2f / %.2f), top %.2f", name, math.abs(l.X), math.abs(l.Z), ex, ez, hi.Y - ground(c)))
						end
					end
				end
			end
		end
	end

	-- ZFIGHT: flat visible faces at the same height that overlap (bucketed by height)
	local tops: { [number]: { { lo: Vector3, hi: Vector3, p: BasePart } } } = {}
	for _, p in parts do
		if p:IsA("Part") and p.Transparency < 0.95 and math.abs(p.CFrame.UpVector.Y) > 0.999 and (p :: Part).Shape == Enum.PartType.Block then
			local lo, hi = box(p)
			local key = math.floor(hi.Y * 200 + 0.5)
			tops[key] = tops[key] or {}
			table.insert(tops[key], { lo = lo, hi = hi, p = p })
		end
	end
	for key, list in tops do
		local near = {}
		for _, k in { key - 1, key, key + 1 } do
			for _, e in tops[k] or {} do
				table.insert(near, e)
			end
		end
		for _, a in list do
			for _, b in near do
				if a.p ~= b.p and (b.p:GetDebugId() > a.p:GetDebugId() or tops[key] ~= list) and math.abs(a.hi.Y - b.hi.Y) < 0.004 then
					local ox, oz = overlap1(a.lo.X, a.hi.X, b.lo.X, b.hi.X), overlap1(a.lo.Z, a.hi.Z, b.lo.Z, b.hi.Z)
					if ox > 0.1 and oz > 0.1 and a.p.Color ~= b.p.Color then
						if a.p:GetDebugId() < b.p:GetDebugId() then
							fail("ZFIGHT", a.p, string.format("with %s, top %.3f, overlap %.2f x %.2f", b.p:GetFullName(), a.hi.Y, ox, oz))
						end
					end
				end
			end
		end
	end

	-- props = top-level models under the scenery folders (and their direct models)
	local props: { Model } = {}
	local function addProps(container: Instance)
		for _, c in container:GetChildren() do
			if c:IsA("Model") then
				table.insert(props, c)
			elseif c:IsA("Folder") and c.Name ~= "Pile" then
				addProps(c)
			end
		end
	end
	addProps(root)
	local pbox: { [Model]: { Vector3 } } = {}
	for _, m in props do
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		local any = false
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "Dome" then -- glass domes sink their lower half into the plinth
				local a, b = box(p)
				lo, hi = lo:Min(a), hi:Max(b)
				any = true
			end
		end
		if any then
			pbox[m] = { lo, hi }
		end
	end

	-- FLOAT / BURY
	local solids: { BasePart } = {}
	for _, p in parts do
		if p.Transparency < 1 then
			table.insert(solids, p)
		end
	end
	for m, b in pbox do
		local lo, hi = b[1], b[2]
		local c = (lo + hi) / 2
		local g = ground(Vector3.new(c.X, 0, c.Z))
		if verbose then
			print(string.format("[prop] %-40s bottom %+.2f size %.1f x %.1f x %.1f", m:GetFullName(), lo.Y - g, hi.X - lo.X, hi.Y - lo.Y, hi.Z - lo.Z))
		end
		if lo.Y > g + 0.2 then
			-- resting on something that is not part of itself?
			local rests = false
			for _, p in solids do
				if not p:IsDescendantOf(m) then
					local a, bb = box(p)
					-- resting on a top face, or mounted on a side (a wall lamp on its wall): touching within 0.15
					local onTop = math.abs(bb.Y - lo.Y) < 0.25 and overlap1(a.X, bb.X, lo.X, hi.X) > 0.05 and overlap1(a.Z, bb.Z, lo.Z, hi.Z) > 0.05
					local onSide = overlap1(a.Y, bb.Y, lo.Y, hi.Y) > 0.05 and overlap1(a.X - 0.15, bb.X + 0.15, lo.X, hi.X) > 0 and overlap1(a.Z - 0.15, bb.Z + 0.15, lo.Z, hi.Z) > 0
					if onTop or onSide then
						rests = true
						break
					end
				end
			end
			if not rests and lo.Y < g + 40 then
				fail("FLOAT", m, string.format("bottom %.2f above ground %.2f", lo.Y - g, g))
			end
		elseif lo.Y < g - 0.5 and not deep(m.Name) and not deep(m:GetFullName()) then
			fail("BURY", m, string.format("bottom %.2f below ground %.2f", g - lo.Y, g))
		end
	end

	-- NOCOLLIDE / BIGBLOCK
	local colliders: { BasePart } = {}
	for _, p in parts do
		if p.CanCollide then
			table.insert(colliders, p)
		end
	end
	for m, b in pbox do
		local lo, hi = b[1], b[2]
		local c = (lo + hi) / 2
		local g = ground(c)
		local tall = hi.Y - g
		if m:FindFirstChild("Root") and walk(c) and tall > 1.5 and not deep(m.Name) then
			-- the body you would bump into: visible parts that start below 2.5 studs (a tree's planter, not its crown)
			local blo, bhi = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") and p.Transparency < 1 and not CANOPY[p.Name] then
					local a, bb = box(p)
					if a.Y < g + 2.5 then
						blo, bhi = blo:Min(a), bhi:Max(bb)
					end
				end
			end
			if blo.X < bhi.X then
				local fx, fz = bhi.X - blo.X, bhi.Z - blo.Z
				local covered = 0
				for _, p in colliders do
					local a, bb = box(p)
					if bb.Y > g + 0.45 and a.Y < g + 2.5 then
						covered = math.max(covered, overlap1(a.X, bb.X, blo.X, bhi.X) * overlap1(a.Z, bb.Z, blo.Z, bhi.Z))
					end
				end
				-- walk-in structures (open-front shelters, nooks) only need a collider somewhere (their back wall)
				local walkIn = string.find(m.Name, "Shelter", 1, true) or string.find(m.Name, "Nook", 1, true) or m:GetAttribute("WalkIn") == true
				local need = if walkIn then 0.05 else 0.3
				if covered < need * fx * fz then
					fail("NOCOLLIDE", m, string.format("body %.1f x %.1f, tall %.1f, best collider covers %.0f%%", fx, fz, tall, covered / (fx * fz) * 100))
				end
			end
		end
	end
	for _, p in colliders do
		if p.Transparency >= 1 and not deep(p.Name) then
			local a, bb = box(p)
			local area = (bb.X - a.X) * (bb.Z - a.Z)
			local vis = 0
			for _, q in solids do
				if q ~= p then
					local qa, qb = box(q)
					if overlap1(qa.Y, qb.Y, a.Y, bb.Y) > 0.05 then
						vis = math.max(vis, overlap1(qa.X, qb.X, a.X, bb.X) * overlap1(qa.Z, qb.Z, a.Z, bb.Z))
					end
				end
			end
			-- union approximation: the largest visible part overlapping it; a blocker over many small pieces is fine
			local inside = 0
			for _, q in solids do
				local qa, qb = box(q)
				if q ~= p and qa.X >= a.X - 0.3 and qb.X <= bb.X + 0.3 and qa.Z >= a.Z - 0.3 and qb.Z <= bb.Z + 0.3 and overlap1(qa.Y, qb.Y, a.Y, bb.Y) > 0 then
					inside += (qb.X - qa.X) * (qb.Z - qa.Z)
				end
			end
			if area > 4 and math.max(vis, math.min(inside, area)) < area * 0.25 then
				fail("BIGBLOCK", p, string.format("blocker %.1f x %.1f, visible under it %.1f studs2", bb.X - a.X, bb.Z - a.Z, math.max(vis, inside)))
			end
		end
	end

	-- --set manifest=on: one measured row per placed world asset (docs/ASSET_MANIFEST.md "World placement")
	if preview.args.manifest == "on" then
		local seen: { [string]: { n: number, line: string } } = {}
		for m in pbox do
			local key = string.gsub(m.Name, "^CT_Rocks_", "")
			key = string.gsub(key, "_%d+$", "")
			local cf, size = m:GetBoundingBox()
			local blocker, solid = false, false
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					if d.Transparency >= 1 then
						blocker = true
					else
						solid = true
					end
				end
			end
			local coll = if blocker and solid then "solid parts + blocker" elseif blocker then "invisible blocker" elseif solid then "solid parts" else "none"
			local kind = if m:FindFirstChild("Root") then "kit" else "parts"
			local folder = m.Parent and m.Parent.Name or "?"
			local g = ground(cf.Position)
			local bottom = cf.Position.Y - size.Y / 2 - g
			local line = string.format("%s|%s|%.1f x %.1f x %.1f|%s|%s|%+.2f", label, kind, size.X, size.Y, size.Z, coll, folder, bottom)
			if seen[key] then
				seen[key].n += 1
			else
				seen[key] = { n = 1, line = line }
			end
		end
		for k, v in seen do
			print(string.format("[asset] %s|%s|%d", k, v.line, v.n))
		end
	end
	local rootModels = 0
	for m in pbox do
		if m:FindFirstChild("Root") then
			rootModels += 1
		end
	end
	print(string.format("[audit] %s: %d props measured (%d kit models), %d colliders", label, (function()
		local n = 0
		for _ in pbox do
			n += 1
		end
		return n
	end)(), rootModels, #colliders))
	-- CLIP: distinct props interpenetrating
	local list = {}
	for m, b in pbox do
		local c = (b[1] + b[2]) / 2
		if walk(c) and not deep(m.Name) then
			table.insert(list, { m = m, lo = b[1], hi = b[2] })
		end
	end
	print(string.format("[audit] %s: %d props in the walkable area checked for clipping", label, #list))
	-- part-level: the summed overlap of the two props' visible parts (each part's axis-aligned box scaled by its
	-- fill, so a long diagonal rail does not count as the whole box it sweeps), against the smaller prop's volume
	local function solidsOf(m: Model): { { lo: Vector3, hi: Vector3, fill: number, vol: number } }
		local out = {}
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local a, bb = box(p)
				local bv = (bb.X - a.X) * (bb.Y - a.Y) * (bb.Z - a.Z)
				local v = p.Size.X * p.Size.Y * p.Size.Z
				if bv > 1e-4 then
					table.insert(out, { lo = a, hi = bb, fill = math.min(1, v / bv), vol = v })
				end
			end
		end
		return out
	end
	local cache = {}
	for i = 1, #list do
		for j = i + 1, #list do
			local A, B = list[i], list[j]
			local coarse = overlap1(A.lo.X, A.hi.X, B.lo.X, B.hi.X) * overlap1(A.lo.Y, A.hi.Y, B.lo.Y, B.hi.Y) * overlap1(A.lo.Z, A.hi.Z, B.lo.Z, B.hi.Z)
			-- items set on an assembly (a lantern on a counter, a geode on its pedestal) share the assembly's MountGroup
			local function group(m: Instance): any
				local x: Instance? = m
				while x and x ~= root do
					local g = x:GetAttribute("MountGroup")
					if g ~= nil then
						return g
					end
					x = x.Parent
				end
				return nil
			end
			local ga, gb = group(A.m), group(B.m)
			local mounted = ga ~= nil and ga == gb
			if coarse > 0 and not mounted and not A.m:IsAncestorOf(B.m) and not B.m:IsAncestorOf(A.m) then
				cache[A.m] = cache[A.m] or solidsOf(A.m)
				cache[B.m] = cache[B.m] or solidsOf(B.m)
				local va, vb, v = 0, 0, 0
				for _, x in cache[A.m] do
					va += x.vol
				end
				for _, y in cache[B.m] do
					vb += y.vol
				end
				for _, x in cache[A.m] do
					for _, y in cache[B.m] do
						local o = overlap1(x.lo.X, x.hi.X, y.lo.X, y.hi.X) * overlap1(x.lo.Y, x.hi.Y, y.lo.Y, y.hi.Y) * overlap1(x.lo.Z, x.hi.Z, y.lo.Z, y.hi.Z)
						-- two floor slabs meeting (a table pad joining its machine bay pad) is paving, not clipping
						local flatX, flatY = (x.hi.Y - x.lo.Y) <= 0.35, (y.hi.Y - y.lo.Y) <= 0.35
						if o > 0 and not (flatX and flatY) then
							v += o * math.min(x.fill, y.fill)
						end
					end
				end
				local small = math.min(va, vb)
				-- contents of a walk-in structure (crates stored in a nook) are meant to be inside it
				local function walkIn(m: Model): boolean
					return string.find(m.Name, "Shelter", 1, true) ~= nil or string.find(m.Name, "Nook", 1, true) ~= nil
				end
				local function inside(x, y): boolean
					return x.lo.X >= y.lo.X - 0.2 and x.hi.X <= y.hi.X + 0.2 and x.lo.Z >= y.lo.Z - 0.2 and x.hi.Z <= y.hi.Z + 0.2
				end
				if (walkIn(A.m) and inside(B, A)) or (walkIn(B.m) and inside(A, B)) then
					v = 0
				end
				if small > 0.5 and v > 0.25 * small and v > 0.3 then
					fail("CLIP", A.m, string.format("with %s, %.2f studs3 = %.0f%% of the smaller", B.m:GetFullName(), v, v / small * 100))
				end
			end
		end
	end
end

-- Lobby: the Prospector Lodge floor (y 3) inside, the porch deck, the yard (0) outside; walkable = inside the hall
if area ~= "arena" then
	local lobby = Workspace:FindFirstChild("CT_Rocks_Lobby")
	local LB = C.server("LobbyBuilder")
	if lobby and LB then
		local routes = {}
		for _, z in LB.ClearZones or {} do
			table.insert(routes, { "lobby:" .. z.Name, z.MinX, z.MaxX, z.MinZ, z.MaxZ })
		end
		audit(lobby, LB.groundAt, LB.insideLodge, routes, "lobby")
	else
		print("[FAIL] no lobby built")
		fails += 1
	end
end

-- Arena: main level 0, lower bench (y -9) east of the drop at x + 44; walkable = inside the octagon (apothem 43)
if area ~= "lobby" and init then
	local c: Vector3 = init.Center
	local arena
	for _, d in Workspace:GetChildren() do
		if string.sub(d.Name, 1, 15) == "CT_Rocks_Arena_" then
			arena = d
		end
	end
	if arena then
		local Config = C.shared("Config")
		local RoundRocks = C.shared("RoundRocks")
		local routes = {}
		-- lanes: mound edge -> stance of each table (3 wide), table -> hopper (2.4 wide), as boxes along the lane
		local function lane(name: string, a: Vector3, b: Vector3, width: number)
			local n = math.max(1, math.floor((b - a).Magnitude / 2))
			for k = 0, n - 1 do
				local p = a:Lerp(b, (k + 0.5) / n)
				table.insert(routes, { name, p.X - width / 2, p.X + width / 2, p.Z - width / 2, p.Z + width / 2 })
			end
		end
		for i = 1, Config.Station.Count do
			local dir = RoundRocks.stationPosition(i).Unit
			lane("arena:pile->table" .. i, c + dir * 10, c + dir * (Config.Station.Radius - 6.5), 3)
			local hop = c + Vector3.new(0, 0, if dir.Z > 0 then 26 else -26)
			lane("arena:table" .. i .. "->hopper", c + dir * (Config.Station.Radius - 5.5), hop, 2.4)
		end
		audit(arena, function(p)
			return c.Y + (if p.X - c.X > 44 then -9 else 0)
		end, function(p)
			local d = Vector3.new(p.X - c.X, 0, p.Z - c.Z)
			for k = 0, 7 do
				local a = math.rad(k * 45)
				if d:Dot(Vector3.new(math.cos(a), 0, math.sin(a))) > 43 then
					return false
				end
			end
			return true
		end, routes, "arena")
	else
		print("[FAIL] no arena built")
		fails += 1
	end
end

for k, n in counts do
	print(string.format("[count] %-9s %d", k, n))
end
if fails == 0 then
	print("PLACEMENT PASS")
else
	print("PLACEMENT FAIL: " .. fails)
end
