--!strict
-- Flowers and sparkles along the lobby paths (idea 33, owner pick 2026-10-15). Lobby only, built once at boot.
-- Small chunky low-poly flower clusters (stem + flat petal disc + round centre, bright cartoon colours) stand on the
-- grass beside every path segment (parts inside a folder or model named "Paths", the lobby build's path layer).
-- Every spot is checked before a cluster goes there: a ray must land on grass (Grass / LeafyGrass, or a green part)
-- and the cluster's box (plus a 1 stud margin) must touch no other part. The lobby build sets CanQuery = false on its
-- paths and decor, so raycasts and overlap queries cannot see them: every part of the map is read once into a flat
-- grid (shared/PathGrid) and the box is checked against that, plus a GetPartBoundsInBox for queryable parts.
-- Every third cluster twinkles (tagged PetSparkle: Low Effects turns the twinkles off).
-- Lighting and colours of the map are the polish thread's; this only adds the props.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local PathGrid = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").PathGrid)

local LobbyBloom = {}

local SPACING = 12 -- studs between samples along a path side
local GRID = 10 -- no two clusters closer than this
local MAX = 140
-- a clump's real spread: flowers up to 1.8 studs from its centre with 1 stud petal discs (2x size, runner 2026-10-15)
local BOX = Vector3.new(6, 4.8, 6)
local MARGIN = 0.3 -- studs of clear grass between a clump and a walkway
local SOLID_MARGIN = 0.6 -- and between a clump and a prop (bench, lamp, fence)
local CLEAR = BOX.X / 2 + 0.9 -- first try: the clump's edge just outside the edge stones (0.85 past the strip side)
local LIFT = 0.5 -- a part blocks only when its top is more than this above the ground under the cluster
local PETALS = {
	Color3.fromRGB(255, 120, 170), -- pink
	Color3.fromRGB(255, 220, 70), -- yellow
	Color3.fromRGB(255, 255, 255), -- white
	Color3.fromRGB(190, 130, 255), -- purple
	Color3.fromRGB(255, 110, 90), -- coral red
	Color3.fromRGB(120, 200, 255), -- sky blue
}
local STEM = Color3.fromRGB(80, 170, 70)
local CENTRE = Color3.fromRGB(255, 200, 60)

local function prop(parent: Instance, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One flower: stem, a flat petal disc and a round centre, `h` studs tall, standing on `base` (ground point).
local function flower(parent: Instance, base: Vector3, h: number, color: Color3, rng: Random)
	local tilt = CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.12, 0.12))
	local root = CFrame.new(base) * tilt
	prop(parent, Enum.PartType.Block, Vector3.new(0.36, h, 0.36), root * CFrame.new(0, h / 2, 0), STEM)
	local head = root * CFrame.new(0, h, 0)
	-- a cylinder's axis is X: turn it upright so the disc lies flat
	prop(parent, Enum.PartType.Cylinder, Vector3.new(0.36, 2.0, 2.0), head * CFrame.Angles(0, 0, math.pi / 2), color)
	prop(parent, Enum.PartType.Ball, Vector3.new(0.84, 0.84, 0.84), head * CFrame.new(0, 0.24, 0), CENTRE)
end

local function twinkle(part: BasePart)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "BloomTwinkle"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 220), Color3.fromRGB(255, 190, 240))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Rate = 1.6
	pe.Speed = NumberRange.new(0.2, 0.6)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = part
	CollectionService:AddTag(pe, "PetSparkle")
end

-- Grass: a grass material, or a green part (the lobby ground is a flat-shaded green part, not grass material).
function LobbyBloom.isGrass(material: Enum.Material, color: Color3?): boolean
	if material == Enum.Material.Grass or material == Enum.Material.LeafyGrass then
		return true
	end
	if not color then
		return false
	end
	local r, g, b = color.R * 255, color.G * 255, color.B * 255
	return g > r + 12 and g > b + 12
end

local function grass(hit: RaycastResult): boolean
	local inst = hit.Instance
	return LobbyBloom.isGrass(hit.Material, if inst:IsA("BasePart") then inst.Color else nil)
end

-- Every part of the map that a flower must not touch (everything but characters, the bloom itself, Terrain and parts
-- nobody can see or bump into).
-- Returns (solid, trim, tall): trim = small edge / lawn decor (LobbyBloom.isTrim), checked with no margin; tall = gate
-- and arch parts (LobbyBloom.isOverhead), checked at any height (Studio 2026-10-15: a clump stood under a yard gate).
local function obstacles(bloom: Instance): (PathGrid.Grid, PathGrid.Grid, PathGrid.Grid)
	local g = PathGrid.new(16)
	local trim = PathGrid.new(16)
	local tall = PathGrid.new(16)
	local Players = game:GetService("Players")
	for _, d in Workspace:GetDescendants() do
		-- Terrain counts as one world-sized box (Studio 2026-10-15: it blocked every spot), so it and anything
		-- absurdly big are left out; the ground itself drops out by height (only boxes above its top block)
		local huge = d:IsA("BasePart") and (d.Size.X > 2000 or d.Size.Z > 2000)
		if d:IsA("BasePart") and d ~= Workspace.Terrain and d.ClassName ~= "Terrain" and not huge and not d:IsDescendantOf(bloom) and not d:FindFirstAncestor("Paths") then
			local model = d:FindFirstAncestorOfClass("Model")
			if model and Players:GetPlayerFromCharacter(model) then
				continue
			end
			local box = PathGrid.fromPart(d)
			if LobbyBloom.isOverhead(d) then
				PathGrid.add(tall, box)
			elseif d.Transparency < 1 or d.CanCollide then
				PathGrid.add(if LobbyBloom.isTrim(d.Name) then trim else g, box)
			end
		end
	end
	return g, trim, tall
end

-- Gates and arches over the lanes (the lobby build's YardGates and ZoneArches folders): nothing grows under them.
function LobbyBloom.isOverhead(part: Instance): boolean
	return part:FindFirstAncestor("YardGates") ~= nil or part:FindFirstAncestor("ZoneArches") ~= nil
end

-- Small decor that sits at a path's edge or on the lawn (edge stones, curbs, lawn tufts): a flower may stand right
-- beside it (no margin), it just must not overlap it. Everything else in "Paths" is walkway (1 stud margin).
function LobbyBloom.isTrim(name: string): boolean
	local n = string.lower(name)
	return string.find(n, "edge", 1, true) ~= nil or string.find(n, "stone", 1, true) ~= nil
		or string.find(n, "curb", 1, true) ~= nil or string.find(n, "tuft", 1, true) ~= nil
end

-- Tries out from a strip's side, nearest first: an edge stone, a joint or a joining strip at the edge pushes the clump out.
local STEPS = { 0, 0.75, 1.5, 2.5, 3.5, 5, 6.5, 8, 10 }

-- Last build's rejection counts by reason (printed by build, read by tests / Studio checks).
LobbyBloom.Stats = {} :: { [string]: number }

-- Builds the flowers; returns how many clusters were placed (0 when the lobby has no "Paths").
function LobbyBloom.build(): number
	local folders: { Instance } = {}
	for _, d in Workspace:GetDescendants() do
		if d.Name == "Paths" and (d:IsA("Folder") or d:IsA("Model")) then
			table.insert(folders, d)
		end
	end
	if #folders == 0 then
		LobbyBloom.Stats = {}
		print("[LobbyBloom] no Paths folder: no flowers")
		return 0
	end
	local bloom = Instance.new("Folder")
	bloom.Name = "LobbyBloom"
	bloom.Parent = Workspace
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = table.clone(folders)
	table.insert(exclude, bloom)
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	ray.FilterDescendantsInstances = exclude
	local solid, trimGrid, tall = obstacles(bloom) -- trimGrid: edge stones, curbs, tufts (no margin); tall: gates
	local pathGrid = PathGrid.new(16) -- walkway: 1 stud margin, any height
	local walkways: { PathGrid.Box } = {}
	for _, f in folders do
		for _, d in f:GetDescendants() do
			if d:IsA("BasePart") then
				local box = PathGrid.fromPart(d)
				if LobbyBloom.isTrim(d.Name) then
					PathGrid.add(trimGrid, box)
				else
					PathGrid.add(pathGrid, box)
					if not box.Round and math.max(box.HX, box.HZ) >= 2 then
						table.insert(walkways, box)
					end
				end
			end
		end
	end

	local hits: { [string]: RaycastResult } = {}
	local function ground(x: number, z: number, y: number): number?
		local hit = Workspace:Raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -24, 0), ray)
		if not (hit and grass(hit) and hit.Normal.Y > 0.85) then
			return nil
		end
		hits[x .. ":" .. z] = hit
		return hit.Position.Y
	end
	local function extra(x: number, y: number, z: number): string?
		local hx = BOX.X / 2
		if PathGrid.touchesExact(solid, x, z, hx, hx, y + LIFT, y + BOX.Y, SOLID_MARGIN) then
			return "solid"
		end
		if PathGrid.touchesExact(tall, x, z, hx, hx, -math.huge, math.huge, 1) then
			return "gate"
		end
		local over = OverlapParams.new()
		over.FilterType = Enum.RaycastFilterType.Exclude
		local hit = hits[x .. ":" .. z]
		over.FilterDescendantsInstances = if hit then { hit.Instance, bloom } else { bloom }
		for _, other in Workspace:GetPartBoundsInBox(CFrame.new(x, y + BOX.Y / 2 + 0.05, z), BOX, over) do
			local top = other.Position.Y + other.Size.Y / 2
			if (other.Transparency < 1 or other.CanCollide) and top > y + LIFT and not LobbyBloom.isTrim(other.Name) and not other:FindFirstAncestor("Paths") then
				return "query"
			end
		end
		return nil
	end
	local spots, stats = PathGrid.spots(walkways, pathGrid, trimGrid, {
		Half = BOX.X / 2, Height = BOX.Y, Margin = MARGIN, Clear = CLEAR, Spacing = SPACING, Steps = STEPS, Cell = GRID, Max = MAX,
		Ground = ground, Extra = extra,
	})
	LobbyBloom.Stats = stats

	local rng = Random.new(20261015)
	for placed, s in spots do
		local g = Vector3.new(s[1], s[2], s[3])
		local cluster = Instance.new("Model")
		cluster.Name = "Flowers"
		cluster.Parent = bloom
		local color = PETALS[rng:NextInteger(1, #PETALS)]
		for k = 1, 3 do
			local a = (k / 3) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
			local r = if k == 1 then 0 else rng:NextNumber(1.0, 1.8)
			local base = g + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			flower(cluster, base, rng:NextNumber(1.8, 3.2), if k == 3 then PETALS[rng:NextInteger(1, #PETALS)] else color, rng)
		end
		if placed % 3 == 0 then
			local first = cluster:FindFirstChildWhichIsA("BasePart")
			if first then
				twinkle(first)
			end
		end
	end
	-- one line per build: placed and every rejection reason (the last reason tried per sample)
	local parts = {}
	for _, k in { "placed", "samples", "tries", "notGrass", "path", "trim", "solid", "gate", "query", "spaced" } do
		table.insert(parts, k .. "=" .. (stats[k] or 0))
	end
	print("[LobbyBloom] " .. table.concat(parts, " "))
	return #spots
end

return LobbyBloom
