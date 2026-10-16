--!strict
-- Pet Battle floating islands (carter 2026-10-14: "make a floating island. nobody will want to spectate the fights so
-- make them teleport to the small island"). Every fight claims its own island copy far up in the sky
-- (IslandRules.spot), the two fighters are moved onto it and back to the lobby after the result (PvpService).
-- The look: ServerStorage[PvpConfig.Island.Model] ("ArenaIsland", the owner's Blender model) is cloned when it
-- exists. Contract for that model: a Model with a part marked attribute ArenaCenter = true whose top face is the fight
-- floor (optional attribute FightRadius, default PvpConfig.Island.Radius), teams face each other along that part's X
-- axis. Without it a procedural stand-in is built (REPLACE: the owner's ArenaIsland): a round grass top, a rocky
-- underside, a few floating rocks, and invisible walls so nobody walks off.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PvpConfig = require(Shared.PvpConfig)
local IslandRules = require(Shared.IslandRules)

local SkyIsland = {}

export type Claim = { Slot: number, Model: Model, Origin: CFrame, Layout: any, Radius: number }

local free: { number } = {}
local used: { [number]: boolean } = {}
local folder: Folder? = nil

local GRASS = Color3.fromRGB(110, 200, 90)
local DIRT = Color3.fromRGB(150, 104, 70)
local ROCK = Color3.fromRGB(128, 118, 132)
local FLOOR = Color3.fromRGB(176, 146, 98) -- a natural sand path, not near-white under the lobby bloom

local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "PetBattleIslands"
	f.Parent = Workspace
	folder = f
	return f
end

local function part(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder part lying flat (its axis pointing up)

-- REPLACE: the owner's ArenaIsland model (ServerStorage). Procedural stand-in, top face at `at`.
local function standIn(at: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "ArenaIsland"
	local r = PvpConfig.Island.Radius
	local top = part(m, "Grass", Enum.PartType.Cylinder, Vector3.new(3, r * 2 + 6, r * 2 + 6), CFrame.new(at - Vector3.new(0, 1.5, 0)) * FLAT, GRASS, Enum.Material.Grass)
	top.CanCollide = true
	-- a sand strip down the middle where the pets fight, grass all round it
	part(m, "Strip", Enum.PartType.Block, Vector3.new(r * 1.5, 0.2, r * 0.9), CFrame.new(at + Vector3.new(0, 0.05, 0)), FLOOR, Enum.Material.Sand).CanCollide = false
	-- rocky underside: shrinking discs and a tip, a little off-centre so it looks hand made
	local y, w = -3, r * 2 + 2
	for i = 1, 5 do
		local h = 5 + i
		local off = Vector3.new(math.sin(i * 1.7) * i * 0.8, 0, math.cos(i * 2.3) * i * 0.8)
		part(m, "Underside" .. i, Enum.PartType.Cylinder, Vector3.new(h, w, w), CFrame.new(at + off + Vector3.new(0, y - h / 2, 0)) * FLAT, if i % 2 == 0 then ROCK else DIRT, Enum.Material.Slate).CanCollide = false
		y -= h - 1
		w *= 0.72
	end
	-- floating rocks around it
	for i = 1, 7 do
		local a = i * (math.pi * 2 / 7) + 0.4
		local d = r + 14 + (i % 3) * 6
		local s = 3 + (i % 3) * 2
		local rock = part(m, "FloatRock" .. i, Enum.PartType.Block, Vector3.new(s, s * 0.8, s * 1.1), CFrame.new(at + Vector3.new(math.cos(a) * d, -4 + (i % 4) * 5, math.sin(a) * d)) * CFrame.Angles(i, i * 0.7, i * 0.3), ROCK, Enum.Material.Slate)
		rock.CanCollide = false
	end
	-- invisible walls round the edge
	local n = 24
	for i = 1, n do
		local a = (i - 0.5) * (math.pi * 2 / n)
		local pos = at + Vector3.new(math.cos(a) * (r + 3), 8, math.sin(a) * (r + 3))
		local wall = part(m, "Wall", Enum.PartType.Block, Vector3.new(1, 18, (r + 3) * 2 * math.pi / n + 1), CFrame.lookAt(pos, at + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(90), 0), ROCK)
		wall.Transparency = 1
		wall.CanQuery = false
	end
	-- the fight floor marker (hidden)
	local centre = part(m, "ArenaCenter", Enum.PartType.Block, Vector3.new(r * 2, 1, r * 2), CFrame.new(at - Vector3.new(0, 0.5, 0)), FLOOR)
	centre.Transparency = 1
	centre.CanCollide = false
	centre.CanQuery = false
	centre:SetAttribute("ArenaCenter", true)
	centre:SetAttribute("FightRadius", r)
	m.PrimaryPart = top
	return m
end

local function centreOf(m: Model): BasePart?
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ArenaCenter") == true then
			return d
		end
	end
	return nil
end

-- An ArenaIsland without a marked fight floor still works: a ray straight down through the middle of the model finds
-- its top surface, and a hidden ArenaCenter part is added there (radius from the model's size, at most Island.Radius).
local function markFloor(m: Model): BasePart?
	local cf, size = m:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { m }
	local hit = Workspace:Raycast(cf.Position + Vector3.new(0, size.Y, 0), Vector3.new(0, -size.Y * 2, 0), params)
	if not hit then
		return nil
	end
	local r = math.clamp(math.min(size.X, size.Z) / 2 - 4, 10, PvpConfig.Island.Radius)
	local c = part(m, "ArenaCenter", Enum.PartType.Block, Vector3.new(r * 2, 1, r * 2), CFrame.new(hit.Position - Vector3.new(0, 0.5, 0)), FLOOR)
	c.Transparency = 1
	c.CanCollide = false
	c.CanQuery = false
	c:SetAttribute("ArenaCenter", true)
	c:SetAttribute("FightRadius", r)
	return c
end

-- Claims an island for a new fight: its own copy at its own spot. Returns where the fight sits and its layout.
function SkyIsland.claim(): Claim
	local slot: number = table.remove(free, 1) or 0
	if slot == 0 then
		slot = 1
		while used[slot] do
			slot += 1
		end
	end
	used[slot] = true
	local at = IslandRules.spot(slot)
	local template = ServerStorage:FindFirstChild(PvpConfig.Island.Model)
	local m: Model? = nil
	if template and template:IsA("Model") then
		local copy = template:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true -- a floating island never falls
			end
		end
		-- move it out of the way first, then find (or mark) its fight floor and put the floor's top centre on the spot
		copy:PivotTo(CFrame.new(at) * copy:GetPivot().Rotation)
		copy.Parent = root()
		local c = centreOf(copy) or markFloor(copy)
		if c then
			local top = c.Position + Vector3.new(0, c.Size.Y / 2, 0)
			copy:PivotTo(copy:GetPivot() + (at - top))
			m = copy
		else
			warn("[SkyIsland] ArenaIsland has no floor to fight on (no ArenaCenter part, nothing under its middle); using the stand-in")
			copy:Destroy()
		end
	end
	local source = if m then "ArenaIsland" else "StandIn"
	if not m then
		m = standIn(at)
	end
	local island = m :: Model
	island:SetAttribute("IslandSource", source) -- Studio check: which island a fight got
	island.Name = "ArenaIsland_" .. slot
	island.Parent = root()
	local c = centreOf(island) :: BasePart
	local r = c:GetAttribute("FightRadius")
	local radius = if type(r) == "number" then r else PvpConfig.Island.Radius
	local origin, layoutName = IslandRules.origin(c.CFrame, c.Size, radius)
	return { Slot = slot, Model = island, Origin = origin, Layout = PvpConfig.Layouts[layoutName], Radius = radius }
end

function SkyIsland.free(slot: number, m: Model?)
	if m then
		m:Destroy()
	end
	if used[slot] then
		used[slot] = nil
		table.insert(free, slot)
		table.sort(free)
	end
end

-- Islands in use (tests).
function SkyIsland.count(): number
	local n = 0
	for _ in used do
		n += 1
	end
	return n
end

return SkyIsland
