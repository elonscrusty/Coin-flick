-- bloom: lobby flowers (server LobbyBloom) and the rainbow path test (shared/PathGrid) on the real lobby paths near
-- spawn (Studio's geometry dump) plus stand-in props. The scene's raycast only sees the ground (LobbyBloom leaves the
-- Paths folders out of its ray anyway).
-- Prints BLOOM PASS / FAIL lines: flowers placed, none touching a path or prop, the trail test on / off the path.
local C = lib("ctr")
local s = C.boot({ profile = function(data)
	data.TutorialStep = 1
end })
local PathGrid = C.shared("PathGrid")
local LobbyBloom = C.server("LobbyBloom")

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, query: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanQuery = query
	p.Parent = parent
	return p
end

-- the real lobby paths near spawn, from Studio's dump (tests/fixtures/bloom/paths_dump.json, 2026-10-15): short wide
-- strips (26 wide along X, ~3 long) joined by 26 wide Cylinder discs whose axis points up, edge stones just outside
local dump = preview.fixtures["paths_dump.json"] or error("tests/fixtures/bloom/paths_dump.json missing")
local O = Vector3.new(0, 0.6, 100) -- spawn, ground top
local map = Instance.new("Model")
map.Name = "BloomTestMap"
map.Parent = workspace
local g0 = dump.groundUnder[1]
local ground = part("Ground", Vector3.new(g0.size[1], g0.size[2], g0.size[3]), CFrame.new(g0.cframe[1], g0.cframe[2], g0.cframe[3]), Color3.fromRGB(110, 190, 80), map, true)
local paths = Instance.new("Model")
paths.Name = "Paths"
paths.Parent = map
local function fromDump(e, color: Color3): Part
	local c = e.cframe
	local p = part(e.name, Vector3.new(e.size[1], e.size[2], e.size[3]), CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]), color, paths, false)
	if e.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	return p
end
local segs = {}
for _, e in dump.strips do
	table.insert(segs, fromDump(e, Color3.fromRGB(200, 180, 130)))
end
for _, e in dump.edgeStones do
	table.insert(segs, fromDump(e, Color3.fromRGB(170, 170, 160)))
end
-- a world-sized box like Workspace.Terrain's bounds (Studio: Terrain blocked every spot before it was left out)
local world = part("WorldBox", Vector3.new(4096, 2048, 4096), CFrame.new(O), Color3.new(1, 1, 1), map, false)
world.Transparency = 1
local props = {
	part("Lamp", Vector3.new(1, 8, 1), CFrame.new(22, 4.6, 100), Color3.fromRGB(60, 60, 70), map, false),
	part("Bench", Vector3.new(6, 2, 2), CFrame.new(-12, 1.6, 96), Color3.fromRGB(150, 100, 60), map, false),
}
for k = 1, 12 do
	table.insert(props, part("LawnTuft", Vector3.new(1.5, 1.2, 1.5), CFrame.new(-40 + k * 7, 1.2, 80 + (k % 3) * 3), Color3.fromRGB(80, 170, 70), map, false))
end
-- a yard gate beside the lane (posts + a high arch beam, like build_lobby's YardGates): nothing may grow under it
local gates = Instance.new("Folder")
gates.Name = "YardGates"
gates.Parent = map
local gateParts = {
	part("Part", Vector3.new(0.9, 9, 0.9), CFrame.new(-20, 5.1, 108), Color3.fromRGB(122, 82, 48), gates, false),
	part("Part", Vector3.new(0.9, 9, 0.9), CFrame.new(-20, 5.1, 118), Color3.fromRGB(122, 82, 48), gates, false),
	part("Part", Vector3.new(0.9, 0.7, 11.6), CFrame.new(-20, 9.2, 113), Color3.fromRGB(160, 112, 63), gates, false),
}

preview.setRaycast(function(origin: Vector3, dir: Vector3, _params)
	-- only the queryable ground answers (paths and props have CanQuery = false)
	local top = ground.Position.Y + ground.Size.Y / 2
	if dir.Y >= 0 or origin.Y < top or origin.Y + dir.Y > top then
		return nil
	end
	local p = Vector3.new(origin.X, top, origin.Z)
	if math.abs(p.X - ground.Position.X) > ground.Size.X / 2 or math.abs(p.Z - ground.Position.Z) > ground.Size.Z / 2 then
		return nil
	end
	return { Instance = ground, Position = p, Normal = Vector3.new(0, 1, 0), Distance = origin.Y - top, Material = Enum.Material.SmoothPlastic }
end)

local n = LobbyBloom.build()
local function check(ok: boolean, what: string)
	print((if ok then "BLOOM PASS " else "BLOOM FAIL ") .. what)
end
check(n >= 15, "flowers placed beside the real lobby paths (dump: strips, joint discs, edge stones; lamp, bench, tufts): " .. n)
local st = LobbyBloom.Stats
print("BLOOM stats placed=" .. tostring(st.placed) .. " path=" .. tostring(st.path) .. " trim=" .. tostring(st.trim) .. " solid=" .. tostring(st.solid) .. " notGrass=" .. tostring(st.notGrass) .. " spaced=" .. tostring(st.spaced))

-- no flower part touches a path or prop (exact boxes, margin 0)
local blockers = PathGrid.new(8)
for _, p in segs do
	PathGrid.add(blockers, PathGrid.fromPart(p))
end
for _, p in props do
	PathGrid.add(blockers, PathGrid.fromPart(p))
end
local bloom = workspace:FindFirstChild("LobbyBloom")
local touching, parts = 0, 0
for _, d in (if bloom then bloom:GetDescendants() else {}) do
	if d:IsA("BasePart") then
		parts += 1
		local b = PathGrid.fromPart(d)
		-- the flower part's flat bounds against each blocker's exact turned footprint (no margin)
		if PathGrid.touchesExact(blockers, b.X, b.Z, (b.MaxX - b.MinX) / 2, (b.MaxZ - b.MinZ) / 2, b.Y - b.HY, b.Y + b.HY, 0) then
			touching += 1
		end
	end
end
local gateGrid = PathGrid.new(8)
for _, p in gateParts do
	PathGrid.add(gateGrid, PathGrid.fromPart(p))
end
local underGate = 0
for _, d in (if bloom then bloom:GetDescendants() else {}) do
	if d:IsA("BasePart") then
		local b = PathGrid.fromPart(d)
		if PathGrid.touchesExact(gateGrid, b.X, b.Z, (b.MaxX - b.MinX) / 2, (b.MaxZ - b.MinZ) / 2, -math.huge, math.huge, 0) then
			underGate += 1
		end
	end
end
check(underGate == 0, "flower parts under the yard gate (any height): " .. underGate)
check(parts > 0 and touching == 0, ("flower parts touching a path or prop: %d of %d"):format(touching, parts))

-- the rainbow trail test: feet over a path (root 3 studs above it) counts, the grass beside it does not
local g = PathGrid.lobbyPaths(map)
local onWalk = PathGrid.under(g, 6.3, 3.7, 100.5, 0.5, 0.5, 7) ~= nil -- middle of the first strip
local edge = (segs[2].CFrame * CFrame.new(11, 0, 0)).Position -- 2 studs inside a strip's side
local onTurned = PathGrid.under(g, edge.X, 3.7, edge.Z, 0.5, 0.5, 7) ~= nil
local offGrass = PathGrid.under(g, 30, 3.6, 100, 0.5, 0.5, 7) == nil -- beside the edge stones
check(g.Count == #segs and onWalk and onTurned and offGrass, "rainbow trail: on path / turned path / grass = " .. tostring(onWalk) .. " / " .. tostring(onTurned) .. " / " .. tostring(not offGrass))

C.cameraAt(O, Vector3.new(0, 55, 65), 50)
C.settle(0.3)
