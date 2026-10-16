-- spawn: the lobby spawn regression (docs/m11/CAMERA_SPAWN_FIX.md, owner report "I spawn in the roof").
-- Boots the real server + client, then checks on the built lobby:
--   * exactly one SpawnLocation (CT_Rocks_LobbySpawn), solid, lying flush on the lodge floor (top within 0.1 above
--     Config.Lodge.FloorY), inside the lodge room with a margin from every wall
--   * a 4 x 6 x 4 character box standing on it (and on every point of the lobby-return band MatchService uses:
--     lobby.Spawn offset by x +-6, z +-3) touches no colliding part and stays under the ceiling (Config.Lodge.CeilingY)
--   * the server fix: a character that appears on top of the ceiling (where the roof spawn left the owner) is put
--     back on the spawn pad by the server, inside the room
-- Prints "SPAWN PASS" when everything holds. Offline only (the preview mock): Roblox's real spawn placement is
-- not simulated, which is why the server places lobby characters itself.
local C = lib("ctr")
if preview.args.kit == "off" then
	game:GetService("Workspace"):SetAttribute("LodgeFallbackTest", true) -- every lodge asset as its Part stand-in
end
local s = C.boot({})
local Workspace = game:GetService("Workspace")
local Config = s.Config
local L = Config.Lodge
local me = s.me
local failed = false
local function fail(msg: string)
	failed = true
	print("[FAIL] spawn: " .. msg)
end

local spawns = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") then
		table.insert(spawns, d)
	end
end
if #spawns ~= 1 then
	fail(#spawns .. " SpawnLocations in the lobby, expected exactly 1")
end
local pad = spawns[1] :: SpawnLocation
if not pad then
	print("[FAIL] spawn: no SpawnLocation")
	return
end
local lobbyRoot = Workspace:FindFirstChild("CT_Rocks_Lobby")
if pad.Name ~= "CT_Rocks_LobbySpawn" or not lobbyRoot or not pad:IsDescendantOf(lobbyRoot) then
	fail("the spawn is " .. pad:GetFullName() .. ", expected CT_Rocks_Lobby/CT_Rocks_LobbySpawn")
end
if not pad.CanCollide then
	fail("the spawn pad is not solid (CanCollide false)")
end
local top = pad.Position.Y + pad.Size.Y / 2
print(("[spawn] pad at %s size %s top %.3f (floor %.3f, ceiling %.3f)"):format(tostring(pad.Position), tostring(pad.Size), top, L.FloorY, L.CeilingY))
if top < L.FloorY - 1e-3 or top > L.FloorY + 0.1 then
	fail(("pad top %.3f is not flush on the floor (%.3f)"):format(top, L.FloorY))
end

local function inRoom(p: Vector3, half: Vector3): boolean
	return p.X - half.X > L.MinX and p.X + half.X < L.MaxX and p.Z - half.Z > L.MinZ and p.Z + half.Z < L.MaxZ
		and p.Y - half.Y >= L.FloorY - 1e-3 and p.Y + half.Y < L.CeilingY
end

-- world AABB of a part (conservative for rotated parts)
local function aabb(p: BasePart): (Vector3, Vector3)
	local cf, sz = p.CFrame, p.Size / 2
	local r, u, b = cf.RightVector, cf.UpVector, cf.LookVector
	local ext = Vector3.new(
		math.abs(r.X) * sz.X + math.abs(u.X) * sz.Y + math.abs(b.X) * sz.Z,
		math.abs(r.Y) * sz.X + math.abs(u.Y) * sz.Y + math.abs(b.Y) * sz.Z,
		math.abs(r.Z) * sz.X + math.abs(u.Z) * sz.Y + math.abs(b.Z) * sz.Z
	)
	return cf.Position - ext, cf.Position + ext
end

local solids = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("BasePart") and d.CanCollide and d ~= pad and not d:IsA("Terrain") then -- the game places no terrain
		local isChar = false
		for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
			if pl.Character and d:IsDescendantOf(pl.Character) then
				isChar = true
			end
		end
		if not isChar then
			table.insert(solids, d)
		end
	end
end
print("[spawn] colliding parts checked: " .. #solids)

local BOX = Vector3.new(4, 6, 4)
local function checkBox(label: string, feet: Vector3)
	local centre = feet + Vector3.new(0, BOX.Y / 2 + 0.05, 0)
	local half = BOX / 2
	if not inRoom(centre, half) then
		fail(label .. ": the character box at " .. tostring(centre) .. " is not inside the lodge room under the ceiling")
	end
	local lo, hi = centre - half, centre + half
	for _, p in ipairs(solids) do
		local a, b = aabb(p)
		if a.X < hi.X and b.X > lo.X and a.Y < hi.Y and b.Y > lo.Y and a.Z < hi.Z and b.Z > lo.Z then
			fail(label .. ": the character box overlaps " .. p:GetFullName())
		end
	end
end

local feet = Vector3.new(pad.Position.X, top, pad.Position.Z)
checkBox("spawn", feet)
-- lobby return band (MatchService: lobby.Spawn * (random -6..6, 0, random -3..3))
local cf = pad.CFrame
for _, o in ipairs({ { -6, -3 }, { 6, -3 }, { -6, 3 }, { 6, 3 } }) do
	local p = (cf * CFrame.new(o[1], 0, o[2])).Position
	checkBox(("return %+d,%+d"):format(o[1], o[2]), Vector3.new(p.X, top, p.Z))
end
-- the spawn faces into the hall (the hunt bays at -Z)
if pad.CFrame.LookVector.Z > -0.9 then
	fail("the spawn does not face the hunt bays (-Z): " .. tostring(pad.CFrame.LookVector))
end

-- Server fix: a character appearing on the ceiling collider (the owner's roof spawn) is moved onto the pad.
C.makeCharacter(me, CFrame.new(0, L.CeilingY + 1, 0))
preview.advance(0.5)
local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
if not root then
	fail("no character after respawn")
else
	local p = root.Position
	print("[spawn] respawned root at " .. tostring(p))
	if not inRoom(p, Vector3.new(0.5, 0.5, 0.5)) or p.Y > L.FloorY + 6 or (Vector3.new(p.X, 0, p.Z) - Vector3.new(feet.X, 0, feet.Z)).Magnitude > 1 then
		fail("a character that appeared on the roof was not put back on the spawn pad (root " .. tostring(p) .. ")")
	end
end

if not failed then
	print("SPAWN PASS")
end
