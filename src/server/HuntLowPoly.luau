--!strict
-- Low-poly hunt arena (owner's Blender set, lobby_blender/roblox/hunt_lowpoly): when the meshes are in the place,
-- the Meadow hunt shows them instead of the procedural ground, hills, trees, fence and pads. Other zones keep the
-- procedural look (their re-skins tint those parts). Nothing that collides or that the round uses is removed: the
-- procedural parts it covers only turn invisible (their old Transparency is kept in the attribute LPHidden and put
-- back for other zones). Meshes: ServerStorage.HuntLowPoly (Hunt_Ground, Hunt_Nest, Hunt_Pads, Hunt_Stalls,
-- Hunt_Fence, Hunt_Ledge, Hunt_Water) and the shared props in ServerStorage.LowPolyLib (<Prop>_LowPoly models).
-- Placement data (arena-local studs, origin = pile centre on the floor) from hunt_placement.json.
local ServerStorage = game:GetService("ServerStorage")

local HuntLowPoly = {}

local FOLDER = "CT_Rocks_LowPoly"
local FLIP = CFrame.Angles(0, math.pi, 0)
-- procedural folders/models the low-poly set replaces (visual only; collision stays)
local COVERED = { "CT_Rocks_Boundary", "CT_Rocks_Ground", "CT_Rocks_StationPads", "CT_Rocks_ZoneScenery" }
local KEEP_VISIBLE = { CT_Rocks_Road = true }
-- hidden parts that keep their collision (walking surface, table pads, the east drop wall and rails)
local KEEP_SOLID = { CT_Rocks_Floor = true, CT_Rocks_Bench = true, Pad = true }
local KEEP_SOLID_IN = { CT_Rocks_Railing = true, CT_Rocks_RetainingWall = true }

local PIECES: { [string]: Vector3 } = {
	Hunt_Fence = Vector3.new(0.0, 4.785, -0.179),
	Hunt_Ground = Vector3.new(0.016, 2.437, -0.006),
	Hunt_Ledge = Vector3.new(65.088, -4.648, 0.016),
	Hunt_Nest = Vector3.new(-0.01, 0.541, -0.006),
	Hunt_Pads = Vector3.new(0.0, 0.154, 0.0),
	Hunt_Stalls = Vector3.new(0.0, 3.476, 0.0),
	Hunt_Water = Vector3.new(70.4, -8.824, 3.969),
}
-- merged scenery meshes (arena studs, merged_placement.json): prop -> centre of its HuntMerged_<prop> mesh
local MERGED: { [string]: Vector3 } = {
	Rock = Vector3.new(-0.004, 1.998, -0.007),
	Kit_Rock_A = Vector3.new(-0.711, 1.085, 3.215),
	Mushroom = Vector3.new(16.219, 1.991, 31.085),
	FlowerBush = Vector3.new(28.512, -2.367, 1.857),
	Kit_Bush_A = Vector3.new(-37.952, 1.431, 1.17),
}

-- Merged meshes not used: the HuntMerged_Rock centre sits on the pile centre, which the six Rock spots below cannot
-- explain (their middle is 18 studs south of it), so it carries rocks we cannot place or move (owner video: grey rocks
-- under and between the eggs). Mushroom: placed one by one so the nest keep-out below applies (a mushroom clipped a nest).
local NO_MERGE: { [string]: boolean } = { Rock = true, Mushroom = true }
-- Pieces not placed: Hunt_Nest is a flat straw bed under the egg pile that read as gold slabs (owner video).
local SKIP_PIECE: { [string]: boolean } = { Hunt_Nest = true }

-- Keep-out (arena-local xz): no scenery prop within these of the pile, the four nests and their machine bays.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local RoundRocks = require(Shared.RoundRocks)
local WorldKit = require(Shared.WorldKit)
local ZoneThemes = require(Shared.ZoneThemes)
local HuntPlacement = require(Shared.HuntPlacement)
local HuntZoneKit = require(Shared.HuntZoneKit)
local SCENERY = HuntPlacement.SCENERY
local nearHopper = HuntPlacement.nearHopper
type KeepOut = { At: Vector3, R: number }
local KEEP_OUT: { KeepOut } = { { At = Vector3.zero, R = 14 } }
for i = 1, Config.Station.Count do
	local dir = RoundRocks.stationPosition(i).Unit
	table.insert(KEEP_OUT, { At = dir * Config.Station.Radius, R = 8 })
	table.insert(KEEP_OUT, { At = dir * 32.75, R = 7 }) -- ArenaBuilder BAY_RADIUS
end
local function keptOut(x: number, z: number, radius: number): boolean
	for _, k in KEEP_OUT do
		local at = k.At
		if Vector2.new(x - at.X, z - at.Z).Magnitude < k.R + radius then
			return true
		end
	end
	return false
end

-- zone of each hunt tier (Config.TierOrder ids) and its piece set: ServerStorage.HuntLowPoly (Meadow) or
-- ServerStorage.HuntLowPoly_<Zone>; a zone without its own pieces uses the Meadow ones
local ZONE_OF_TIER = HuntZoneKit.ZoneOfTier
-- zone textures for the shared scenery props (prop_textures/<Prop>_LowPoly_<Zone>_tex.png); Meadow keeps the mesh's own
local PROP_TEX: { [string]: { [string]: string } } = {
	Forest = {
		Barrel = "rbxassetid://89725050548401",
		CliffPine = "rbxassetid://137769791848746",
		CliffStep = "rbxassetid://98623443356270",
		CliffTall = "rbxassetid://133627867440591",
		Crate = "rbxassetid://138492924980534",
		FlowerBush = "rbxassetid://134566110332735",
		Kit_Bush_A = "rbxassetid://139221721045406",
		Kit_Pine_A = "rbxassetid://90156129212851",
		Kit_Rock_A = "rbxassetid://140028050702795",
		Kit_Tree_A = "rbxassetid://133296195798037",
		Kit_Tree_B = "rbxassetid://133296195798037",
		Mushroom = "rbxassetid://78842743650461",
		PineTree = "rbxassetid://95774379961243",
		Rock = "rbxassetid://121235479982147",
		RoundTree = "rbxassetid://81209100832087",
	},
	Snow = {
		Barrel = "rbxassetid://87055105774180",
		CliffPine = "rbxassetid://126381169994876",
		CliffStep = "rbxassetid://140193253118536",
		CliffTall = "rbxassetid://83213241715810",
		Crate = "rbxassetid://138492924980534",
		FlowerBush = "rbxassetid://137827687647265",
		Kit_Bush_A = "rbxassetid://74887658151228",
		Kit_Pine_A = "rbxassetid://104818861381656",
		Kit_Rock_A = "rbxassetid://140028050702795",
		Kit_Tree_A = "rbxassetid://109578682907200",
		Kit_Tree_B = "rbxassetid://109578682907200",
		Mushroom = "rbxassetid://87164838386234",
		PineTree = "rbxassetid://123544408092828",
		Rock = "rbxassetid://119012433215485",
		RoundTree = "rbxassetid://78764098185774",
	},
	Space = {
		Barrel = "rbxassetid://91794126910640",
		CliffPine = "rbxassetid://131077040710394",
		CliffStep = "rbxassetid://86807361922469",
		CliffTall = "rbxassetid://76395645122323",
		Crate = "rbxassetid://138492924980534",
		FlowerBush = "rbxassetid://106504275926136",
		Kit_Bush_A = "rbxassetid://107131682610477",
		Kit_Pine_A = "rbxassetid://120484873893516",
		Kit_Rock_A = "rbxassetid://140028050702795",
		Kit_Tree_A = "rbxassetid://115540876428923",
		Kit_Tree_B = "rbxassetid://115540876428923",
		Mushroom = "rbxassetid://87164838386234",
		PineTree = "rbxassetid://103934000274426",
		Rock = "rbxassetid://116922990283062",
		RoundTree = "rbxassetid://90945658224449",
	},
	Volcano = {
		Barrel = "rbxassetid://135637895091175",
		CliffPine = "rbxassetid://101208525968066",
		CliffStep = "rbxassetid://135588974535977",
		CliffTall = "rbxassetid://135691926011952",
		Crate = "rbxassetid://138492924980534",
		FlowerBush = "rbxassetid://99132004962560",
		Kit_Bush_A = "rbxassetid://130776082044736",
		Kit_Pine_A = "rbxassetid://120513091427435",
		Kit_Rock_A = "rbxassetid://140028050702795",
		Kit_Tree_A = "rbxassetid://86519725745959",
		Kit_Tree_B = "rbxassetid://86519725745959",
		Mushroom = "rbxassetid://87164838386234",
		PineTree = "rbxassetid://118183059207119",
		Rock = "rbxassetid://84492359657719",
		RoundTree = "rbxassetid://78724788182643",
	},
}

local function sources(zone: string?): ({ [string]: MeshPart }, { [string]: MeshPart })
	local pieces: { [string]: MeshPart } = {}
	local props: { [string]: MeshPart } = {}
	local function collect(folder: Instance?)
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("MeshPart") then
					-- "Hunt_Ground_Snow.001" and "Hunt_Ground" both count as Hunt_Ground
					local name = string.gsub(string.gsub(d.Name, "%.%d+$", ""), "_(%a+)$", function(z)
						return if z == zone then "" else "_" .. z
					end)
					pieces[name] = pieces[name] or d
				end
			end
		end
	end
	if zone and zone ~= "Meadow" then
		collect(ServerStorage:FindFirstChild("HuntLowPoly_" .. zone))
	end
	collect(ServerStorage:FindFirstChild("HuntLowPoly"))
	local lib = ServerStorage:FindFirstChild("LowPolyLib")
	if lib then
		for _, m in lib:GetChildren() do
			local stem = string.match(m.Name, "^(.-)_LowPoly$")
			local mp = stem and m:FindFirstChildWhichIsA("MeshPart", true)
			if stem and mp then
				props[stem] = mp
			end
		end
	end
	return pieces, props
end

function HuntLowPoly.available(): boolean
	local pieces = sources()
	local ground: MeshPart? = pieces["Hunt_Ground"]
	return ground ~= nil
end

-- A textured mesh ignores Color: drop its texture so the flat zone colour shows (flat low-poly style). Clones only:
-- each zone builds fresh copies, so the Meadow keeps the textures as built.
local function flatColor(p: BasePart, col: Color3)
	if p:IsA("MeshPart") then
		p.TextureID = ""
	end
	for _, c in p:GetChildren() do
		if c:IsA("SurfaceAppearance") then
			c:Destroy()
		end
	end
	p.Color = col
end

local function finish(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("CameraIgnore", true)
end

-- worksite props the set replaces (no lamps in the meadow, owner rule; hay and crates come back as low-poly props)
local function worksiteCovered(name: string): boolean
	return name == "CT_Rocks_LampMast" or string.match(name, "Wall_Lamp") ~= nil or name == "CT_Rocks_HayBale" or name == "CT_Rocks_Pallet"
		or string.match(name, "^CT_Rocks_Crate") ~= nil or string.match(name, "Shelter") ~= nil
end

local function hideIn(container: Instance, hide: boolean)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and not KEEP_VISIBLE[d.Name] then
			local saved = d:GetAttribute("LPHidden")
			if hide and saved == nil then
				d:SetAttribute("LPHidden", d.Transparency)
				d.Transparency = 1
				-- hidden props must not block (invisible roofs, trunks, crates); floors, pads, walls and rails stay solid
				if d.CanCollide and not KEEP_SOLID[d.Name] and not (d.Parent and KEEP_SOLID_IN[d.Parent.Name]) then
					d:SetAttribute("LPCollide", true)
					d.CanCollide = false
				end
			elseif hide then
				-- already hidden, but a zone re-skin (ZoneScenery) may have shown it again: keep it hidden
				d.Transparency = 1
			elseif not hide and type(saved) == "number" then
				d.Transparency = saved
				d:SetAttribute("LPHidden", nil)
				if d:GetAttribute("LPCollide") then
					d.CanCollide = true
					d:SetAttribute("LPCollide", nil)
				end
			end
		elseif d:IsA("Light") then
			-- remember lights that were on, so restoring never switches on one that was off
			if hide and d.Enabled then
				d:SetAttribute("LPLight", true)
				d.Enabled = false
			elseif not hide and d:GetAttribute("LPLight") then
				d.Enabled = true
				d:SetAttribute("LPLight", nil)
			end
		elseif d:IsA("LayerCollector") and not (d.Parent and KEEP_VISIBLE[d.Parent.Name]) then
			-- a sign's words go with its part: the hidden gate sign left "PET MEADOW" floating in the sky (sweep 191)
			if hide and d.Enabled then
				d:SetAttribute("LPGui", true)
				d.Enabled = false
			elseif not hide and d:GetAttribute("LPGui") then
				d.Enabled = true
				d:SetAttribute("LPGui", nil)
			end
		end
	end
end

local function setCovered(root: Instance, hide: boolean)
	for _, name in COVERED do
		local f = root:FindFirstChild(name)
		if f then
			hideIn(f, hide)
		end
	end
	local site = root:FindFirstChild("CT_Rocks_Worksite")
	if site then
		for _, m in site:GetChildren() do
			if worksiteCovered(m.Name) then
				hideIn(m, hide)
			end
		end
	end
end

-- the worksite's hay bales and crates as low-poly props at the same spots and heights
local function swapWorksite(root: Instance, f: Instance, props: { [string]: MeshPart }, tex: { [string]: string }?, fenceHalf: number, c: Vector3)
	local site = root:FindFirstChild("CT_Rocks_Worksite")
	if not site then
		return
	end
	-- a few props only (the full set crowded the path by the shell stall): the rest stay hidden with the procedural site
	local KEEP = { HayBale = 2, Crate = 1 }
	local count: { [string]: number } = {}
	for _, m in site:GetChildren() do
		local stem = if m.Name == "CT_Rocks_HayBale" then "HayBale" elseif string.match(m.Name, "^CT_Rocks_Crate") then "Crate" else nil
		if stem then
			count[stem] = (count[stem] or 0) + 1
			if count[stem] > KEEP[stem] then
				stem = nil
			end
		end
		local src = stem and props[stem]
		if src and m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			local p = src:Clone()
			p.Name = stem :: string
			p.Size = src.Size * (size.Y / src.Size.Y) * 0.65 -- the kit props read oversized next to the tables
			local _, yaw = m:GetPivot():ToEulerAnglesYXZ()
			-- the arena-local spot steps off the fence like any prop (cf is world space, c the arena centre)
			local ox, oz = c.X, c.Z
			local nx, nz = HuntPlacement.spot(stem :: string, cf.X - ox, cf.Z - oz, 0.5 * math.max(p.Size.X, p.Size.Z), fenceHalf)
			p.CFrame = CFrame.new(ox + nx, cf.Y - size.Y / 2 + p.Size.Y / 2, oz + nz) * CFrame.Angles(0, yaw, 0) * FLIP
			if tex and tex[stem :: string] then
				p.TextureID = tex[stem :: string]
			end
			finish(p)
			p.Parent = f
		end
	end
end

-- water: a slow bob (the only moving piece)
local function bobWater(p: BasePart)
	local TweenService = game:GetService("TweenService")
	local tw = TweenService:Create(p, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { CFrame = p.CFrame * CFrame.new(0, 0.18, 0) })
	tw:Play()
	p.Destroying:Once(function()
		tw:Cancel()
	end)
	-- a few soft glints drifting on the surface (polish #38); tagged so Low Effects can switch them off
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "WaterSparkle"
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 240, 255))
	glint.LightEmission = 0.8
	glint.Rate = 6
	glint.Lifetime = NumberRange.new(0.6, 1.2)
	glint.Speed = NumberRange.new(0, 0.3)
	glint.SpreadAngle = Vector2.new(180, 0)
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.45), NumberSequenceKeypoint.new(1, 0) })
	glint.Transparency = NumberSequence.new(0.2)
	glint.Parent = p
	game:GetService("CollectionService"):AddTag(glint, "PetSparkle")
end

-- props that are trees or bushes (zone LeafTint; the extra Forest trees use the tree ones)
local LEAFY: { [string]: boolean } = { PineTree = true, Kit_Pine_A = true, RoundTree = true, Kit_Tree_A = true, Kit_Tree_B = true, FlowerBush = true, Kit_Bush_A = true }
local BOULDERS: { [string]: boolean } = { Rock = true, Kit_Rock_A = true }
-- pieces that are the pale wood (deck, stalls, fence) and take the zone Wood tint
local WOODEN: { [string]: boolean } = { Hunt_Ledge = true, Hunt_Stalls = true, Hunt_Fence = true }
local WHITE = Color3.new(1, 1, 1)

local FOREST_EXTRAS = HuntPlacement.forestExtras()

-- ground height under arena-local (x, z): ray onto the low-poly ground and ledge (CanQuery is off on them, so it is
-- switched on for the cast only); falls back to the flat floor / bench
local function groundY(f: Instance, base: CFrame, x: number, z: number): number
	local hits: { BasePart } = {}
	for _, n in { "Hunt_Ground", "Hunt_Ledge" } do
		local g = f:FindFirstChild(n)
		if g and g:IsA("BasePart") then
			table.insert(hits, g)
		end
	end
	local fallback = if x > ZoneThemes.Layout.DropX then ZoneThemes.Layout.BenchY else 0
	if #hits == 0 then
		return fallback
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = table.clone(hits) :: { any }
	for _, g in hits do
		g.CanQuery = true
	end
	local from = base * CFrame.new(x, 40, z)
	local hit = workspace:Raycast(from.Position, Vector3.new(0, -80, 0), params)
	for _, g in hits do
		g.CanQuery = false
	end
	return if hit then hit.Position.Y - base.Y else fallback
end

local function deco(f: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	finish(p)
	p.Parent = f
	return p
end

-- Space: shallow craters on the floor between the nests and crystal clusters just outside the fence (procedural,
-- no asset ids; REPLACE with real meshes when uploaded). Built after the set is parented (ground rays need it).
local function spaceDressing(f: Instance, base: CFrame, t: ZoneThemes.Theme, fenceHalf: number)
	local rng = Random.new(5151)
	local rim, pit = Color3.fromRGB(150, 128, 196), Color3.fromRGB(112, 92, 160)
	for k = 0, 11 do
		local a = math.rad(k * 30 + 15)
		local r = if k % 2 == 0 then 24 else 38
		local x, z = math.cos(a) * r, math.sin(a) * r
		local dia = rng:NextNumber(5, 8)
		if not keptOut(x, z, dia / 2) and not (z < 0 and math.abs(x) < ZoneThemes.Layout.RoadHalfWidth + 3) then
			local y = groundY(f, base, x, z)
			local at = base * CFrame.new(x, y, z)
			-- cylinders run along X: stand them on end
			deco(f, "CraterRim", Vector3.new(0.5, dia, dia), at * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), rim, Enum.Material.Slate, Enum.PartType.Cylinder)
			deco(f, "CraterPit", Vector3.new(0.5, dia * 0.7, dia * 0.7), at * CFrame.new(0, 0.14, 0) * CFrame.Angles(0, 0, math.rad(90)), pit, Enum.Material.Slate, Enum.PartType.Cylinder)
		end
	end
	for _, ring in ZoneThemes.ringSpots() do
		-- pushed out to 6 studs past the fence square (3 clear + the cluster's own 3 of spread); the clusters stood on the fence
		local cx, cz = HuntPlacement.pushOut(ring.X, ring.Z, fenceHalf, 6)
		local spot = Vector3.new(cx, 0, cz)
		local y = groundY(f, base, spot.X, spot.Z)
		for k = 1, 3 do
			local h = rng:NextNumber(3, 7)
			local w = rng:NextNumber(0.9, 1.5)
			local cf = base * CFrame.new(spot.X + rng:NextNumber(-1.5, 1.5), y, spot.Z + rng:NextNumber(-1.5, 1.5))
				* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35))
			local neon = k == 1
			deco(f, "Crystal", Vector3.new(w, h, w), cf * CFrame.new(0, h * 0.4, 0) * CFrame.Angles(0, math.rad(45), 0),
				if neon then t.Accent else t.Rock, if neon then Enum.Material.Neon else Enum.Material.Glass)
		end
	end
end

-- The zone's own piece set (ServerStorage.HuntZoneKit_<Zone>, contract in Shared.HuntZoneKit): key -> source piece
-- (MeshPart or Model) and the roles present. Empty when the zone has no kit yet (the tinted meadow set is used).
local function kitPieces(zone: string): ({ [string]: Instance }, HuntZoneKit.Plan)
	local found: { [string]: Instance } = {}
	local names: { string } = {}
	local function walk(folder: Instance)
		for _, ch in folder:GetChildren() do
			if ch:IsA("Folder") then
				walk(ch)
			elseif ch:IsA("BasePart") or ch:IsA("Model") then
				local _, key = HuntZoneKit.roleOf(ch.Name, zone)
				if key and not found[key] then
					found[key] = ch
					table.insert(names, ch.Name)
				end
			end
		end
	end
	local folder = ServerStorage:FindFirstChild(HuntZoneKit.folderName(zone))
	if folder then
		walk(folder)
	end
	return found, HuntZoneKit.plan(names, zone)
end

-- Places one kit piece on arena spot `slot`: its box bottom on the floor (y 0, the bench past the east drop), its
-- box centre on the spot, front toward the arena; the piece's Offset / Yaw / Scale attributes tune it in Studio.
-- Visual only (no collision, no queries) except the Ground, which is walked on. `fit` scales on top of Scale and
-- `y` overrides the floor height (scatter rows carry their own).
local function placeKit(f: Instance, src: Instance, role: string, slot: HuntZoneKit.Slot, base: CFrame, fit: number?, y: number?): Instance
	local copy = src:Clone()
	local scale = src:GetAttribute("Scale")
	local offset = src:GetAttribute("Offset")
	local yaw = src:GetAttribute("Yaw")
	-- (a scatter piece ignores Scale: it is fitted to the footprint the fence checks were made for)
	local k = (if typeof(scale) == "number" and scale > 0 and role ~= "Scatter" then scale else 1) * (fit or 1)
	local floorY = y or (if slot.X > ZoneThemes.Layout.DropX and role ~= "Ground" then ZoneThemes.Layout.BenchY else 0)
	local cf = base * CFrame.new(slot.X, floorY, slot.Z)
		* CFrame.Angles(0, slot.Yaw + (if typeof(yaw) == "number" then math.rad(yaw) else 0), 0)
		* CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.zero)
	local walk = role == "Ground"
	local function setup(p: BasePart)
		finish(p)
		p.CanCollide = walk
		p.CastShadow = not walk and role ~= "PathEdge"
	end
	if copy:IsA("Model") then
		if k ~= 1 then
			copy:ScaleTo(copy:GetScale() * k)
		end
		copy:PivotTo(cf)
		local bcf, bsize = copy:GetBoundingBox()
		local bottom = bcf.Position - Vector3.new(0, bsize.Y / 2, 0)
		copy:PivotTo(copy:GetPivot() + (cf.Position - bottom))
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				setup(d)
			end
		end
	elseif copy:IsA("BasePart") then
		copy.Size *= k
		copy.CFrame = cf * CFrame.new(0, copy.Size.Y / 2, 0)
		setup(copy)
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				setup(d)
			end
		end
	end
	copy:SetAttribute("ZoneKit", role) -- the client can find the hero and the gate (animation, VFX)
	copy.Parent = f
	return copy
end

-- Shows the low-poly set of hunt tier `tierId` (its zone: Meadow, Forest, Snow, Volcano, Space) on arena `root`
-- (centre `c`), rebuilding it when the zone changes; without the meshes it removes the set and restores the
-- procedural parts. Safe to call every round.
-- ground colour of the skirt under each zone's arena
local SKIRT: { [string]: Color3 } = {
	Meadow = Color3.fromRGB(116, 196, 74),
	Forest = Color3.fromRGB(62, 122, 52),
	Snow = Color3.fromRGB(226, 234, 245),
	Volcano = Color3.fromRGB(96, 70, 60),
	Space = Color3.fromRGB(150, 130, 190), -- lilac rock (the sky stays bright day)
}

function HuntLowPoly.apply(root: Instance, c: Vector3, tierId: string?)
	local zone = ZONE_OF_TIER[tierId or "Gravel"] or "Meadow"
	local theme = ZoneThemes.get(tierId)
	local old = root:FindFirstChild(FOLDER)
	if old and old:GetAttribute("Zone") ~= zone then
		old:Destroy()
		old = nil
	end
	if not HuntLowPoly.available() then
		if old then
			old:Destroy()
		end
		if root:GetAttribute("LPCovered") then
			-- (also after a zone change destroyed the old set above) put the procedural parts back
			setCovered(root, false)
			root:SetAttribute("LPCovered", nil)
		end
		return
	end
	if old then
		setCovered(root, true) -- zone re-skins re-create ZoneScenery: keep it hidden
		return
	end
	local pieces, props = sources(zone)
	local tex = PROP_TEX[zone]
	-- the zone's own pieces swap in role by role; every role it lacks keeps the tinted meadow piece
	local kit, kitPlan = kitPieces(zone)
	local scatterKeys: { string } = kitPlan.Scatter or {}
	local ownSkyline = kitPlan.Skyline ~= nil
	local hasKit = next(kit) ~= nil
	local style = HuntZoneKit.Style[zone] or HuntZoneKit.Style.Meadow
	local function replaced(prop: string): boolean
		return (#scatterKeys > 0 and HuntZoneKit.Scatterable[prop] == true)
			or (ownSkyline and string.sub(prop, 1, 5) == "Cliff" and prop ~= "CliffPine")
	end
	-- the fence line, measured from the fence mesh (a square about 85 x 85: half of its box is where the line runs)
	local fenceSrc = pieces.Hunt_Fence
	local fenceHalf = if fenceSrc then math.min(fenceSrc.Size.X, fenceSrc.Size.Z) / 2 else HuntPlacement.FenceHalf
	local f = Instance.new("Folder")
	f.Name = FOLDER
	f:SetAttribute("Zone", zone)
	local base = CFrame.new(c)
	-- the owner's StonePad mesh (Shared.WorldKit) on each station pad instead of the merged Hunt_Pads piece: stretched
	-- to the hidden procedural Pad slab's box (11.6 x PAD_TOP x 8.8, ArenaBuilder), so its top is where the nest
	-- table stands; visual only, the hidden Pad keeps the collision
	local stonePads = WorldKit.has("StonePad")
	if stonePads then
		local padsFolder = root:FindFirstChild("CT_Rocks_StationPads")
		local padModels: { Instance } = if padsFolder then padsFolder:GetChildren() else {}
		for _, pad in padModels do
			local slab = pad:FindFirstChild("Pad")
			local p = if slab and slab:IsA("BasePart") then WorldKit.clone("StonePad", "StonePad") else nil
			if p and slab and slab:IsA("BasePart") then
				WorldKit.fitBox(p, slab.CFrame, slab.Size)
				if zone ~= "Meadow" then
					flatColor(p, theme.Stone) -- the zone's stepping-stone colour (the Meadow keeps the mesh as built)
				end
				finish(p)
				p.CastShadow = false
				p.Parent = f
			end
		end
	end
	for name, at in PIECES do
		local skip = SKIP_PIECE[name] or (stonePads and name == "Hunt_Pads") or (theme.HideWater and name == "Hunt_Water")
			or (name == "Hunt_Ground" and kitPlan.Ground ~= nil)
		local src = if skip then nil else pieces[name]
		if src then
			local p = src:Clone()
			p.Name = name
			p.CFrame = base * CFrame.new(at) * FLIP
			finish(p)
			p.CastShadow = name ~= "Hunt_Ground" and name ~= "Hunt_Nest" and name ~= "Hunt_Pads" and name ~= "Hunt_Water"
			if name == "Hunt_Pads" then
				-- hex stepping stones: the zone's stone (Meadow: warm sandy, the plain blue-grey read as unfinished)
				p.Color = theme.Stone
			elseif WOODEN[name] and theme.Wood ~= WHITE then
				p.Color = theme.Wood
			elseif name == "Hunt_Ground" and theme.GroundTint then
				p.Color = theme.GroundTint -- a tint only: the ground keeps its own texture (dirt path, facets)
			end
			if name == "Hunt_Ground" or name == "Hunt_Ledge" then
				-- walk on the low-poly ground itself (it rises gently toward the fence; the flat floor stays under it).
				-- (Default collision fidelity: a convex decomposition of the mesh)
				p.CanCollide = true
			end
			p.Parent = f
		end
	end
	-- merged meshes (IMPORT_NOW4 merged/, pieces HuntMerged_<Prop>): one mesh stands in for every scenery copy of
	-- that prop, so the arena has far fewer parts
	-- a prop with any spot inside the keep-out is placed one by one (its merged mesh would bring that copy along)
	local function propRadius(s: { any }): number
		local src = props[s[1]]
		return if src then 0.5 * math.max(src.Size.X, src.Size.Z) * s[6] else 0
	end
	-- where a prop stands: props that would clip the square fence (within 3 studs of it, trees by their trunk) step 3
	-- studs clear of it, perpendicular to the line (the cliffs are the backdrop and stay put)
	local function spot(s: { any }): (number, number)
		return HuntPlacement.spot(s[1], s[2], s[4], propRadius(s), fenceHalf)
	end
	-- a prop that had to move (its merged mesh would bring the old copy), or that would crowd a shell stand
	local function blocked(s: { any }): boolean
		local x, z = spot(s)
		return x ~= s[2] or z ~= s[4] or nearHopper(x, z, propRadius(s))
	end
	local mergeOk: { [string]: boolean } = {}
	for prop in MERGED do
		mergeOk[prop] = not NO_MERGE[prop] and not replaced(prop)
	end
	for _, s in SCENERY do
		if mergeOk[s[1]] and (keptOut(s[2], s[4], propRadius(s)) or blocked(s)) then
			mergeOk[s[1]] = false
		end
	end
	local merged: { [string]: boolean } = {}
	for prop, at in MERGED do
		local src = if mergeOk[prop] then pieces["HuntMerged_" .. prop] else nil
		if src then
			merged[prop] = true
			local p = src:Clone()
			p.Name = "HuntMerged_" .. prop
			p.CFrame = base * CFrame.new(at) * FLIP
			if tex and tex[prop] then
				p.TextureID = tex[prop]
			end
			if BOULDERS[prop] and theme.Boulder then
				flatColor(p, theme.Boulder)
			elseif prop == "Kit_Rock_A" then
				p.Color = Color3.fromRGB(255, 226, 178) -- the flat stone slabs by the nests: warm, not pale blue-grey
			elseif LEAFY[prop] and theme.LeafTint then
				p.Color = theme.LeafTint
			end
			finish(p)
			p.Parent = f
		end
	end
	-- the owner's small mushroom cluster (ServerStorage.WorldKit_LowPoly) stands in for the giant mushroom
	local wk = game:GetService("ServerStorage"):FindFirstChild("WorldKit_LowPoly")
	local smallShroom = wk and wk:FindFirstChild("Mushrooms_Small")
	local scenery = SCENERY
	if theme.ExtraTrees then
		scenery = table.clone(SCENERY)
		table.move(FOREST_EXTRAS, 1, #FOREST_EXTRAS, #scenery + 1, scenery)
	end
	for i, s in scenery do
		local swapKey = HuntZoneKit.scatterFor(s[1], i, scatterKeys)
		local swap = if swapKey then kit[swapKey] else nil
		local sx, sz = spot(s)
		if swap then
			-- the zone's scatter prop, fitted to the footprint of the meadow prop it stands in for (the placement
			-- checks were made for that footprint), BigScatter times that outside the fence (re-spotted for the bigger
			-- footprint, so it still clears the fence); a meadow prop without its mesh keeps the scatter's own size
			local r0 = propRadius(s)
			local big = HuntZoneKit.outside(s[2], s[4], r0 * HuntZoneKit.BigScatter, fenceHalf)
			local rr = if big then r0 * HuntZoneKit.BigScatter else r0
			local bx, bz = sx, sz
			if big then
				bx, bz = HuntPlacement.spot(s[1], s[2], s[4], rr, fenceHalf)
			end
			if not keptOut(bx, bz, rr) and not nearHopper(bx, bz, rr) and not HuntZoneKit.inLane(bx, bz, rr, fenceHalf) then
				local ext = if swap:IsA("Model") then swap:GetExtentsSize() elseif swap:IsA("BasePart") then swap.Size else Vector3.one
				local fit = if rr > 0 then HuntZoneKit.fitScale(math.max(ext.X, ext.Z), 2 * rr) else (if big then HuntZoneKit.BigScatter else 1)
				placeKit(f, swap, "Scatter", { X = bx, Z = bz, Yaw = s[5] }, base, fit, s[3])
			end
			continue
		end
		if hasKit and HuntZoneKit.inLane(sx, sz, propRadius(s), fenceHalf) then
			continue -- the clear central path
		end
		if replaced(s[1]) then
			continue
		end
		local small = s[1] == "Mushroom" and smallShroom and smallShroom:IsA("MeshPart")
		local src = if small then smallShroom :: MeshPart else props[s[1]]
		if src and not merged[s[1]] and not keptOut(sx, sz, propRadius(s)) and not nearHopper(sx, sz, propRadius(s)) then
			local p = src:Clone()
			p.Name = s[1]
			p.Size = if small then src.Size * 1.6 else src.Size * s[6]
			p.CFrame = base * CFrame.new(sx, s[3] + p.Size.Y / 2, sz) * CFrame.Angles(0, s[5], 0) * FLIP
			if tex and tex[s[1]] and not small then
				p.TextureID = tex[s[1]]
			end
			if string.sub(s[1], 1, 5) == "Cliff" then
				p.Color = Color3.new(1, 1, 1) -- full texture brightness: the default grey tint made the cliffs gloomy
			elseif BOULDERS[s[1]] and theme.Boulder then
				flatColor(p, theme.Boulder)
			elseif LEAFY[s[1]] and theme.LeafTint and not small then
				p.Color = theme.LeafTint
			end
			finish(p)
			p.Parent = f
		end
	end
	swapWorksite(root, f, props, tex, fenceHalf, c)
	-- a wide meadow skirt under the arena so the island edge and the sea never show past the cliffs
	do
		local skirt = Instance.new("Part")
		skirt.Name = "HuntSkirt"
		skirt.Size = Vector3.new(256, 1, 256) -- arenas sit 260 apart: never reach the next one
		skirt.CFrame = base * CFrame.new(0, -0.6, 0)
		skirt.Color = SKIRT[zone] or SKIRT.Meadow -- the zone ground colour (the ground mesh itself is white and textured)
		skirt.Material = Enum.Material.SmoothPlastic
		skirt.Anchored = true
		skirt.CanCollide = false
		skirt.CanQuery = false
		skirt.CanTouch = false
		skirt.CastShadow = false
		skirt.Parent = f
	end
	-- the zone's skyline, hero, best-pet statue, gate arch, road trim and ground tile on their spots
	for role, keys in kitPlan do
		if role ~= "Scatter" and role ~= "LaneMarker" then
			-- ring roles: the narrowest piece sets the spacing, so the ring closes whatever the art's width
			local width: number? = nil
			if role == "Skyline" or role == "SkylineFill" then
				for _, key in keys do
					local src = kit[key]
					local sc = src:GetAttribute("Scale")
					local ext = if src:IsA("Model") then src:GetExtentsSize() elseif src:IsA("BasePart") then src.Size else nil
					if ext then
						local w = ext.X * (if typeof(sc) == "number" and sc > 0 then sc else 1)
						width = if width then math.min(width, w) else w
					end
				end
			end
			for _, slot in HuntZoneKit.slots(role, fenceHalf, keys, width) do
				local src = kit[slot.Variant or keys[1]]
				if src then
					local p = placeKit(f, src, role, slot, base)
					if role == "Ground" then
						p.Name = if p:IsA("BasePart") then "Hunt_Ground" else "ZoneGround" -- ground rays find a mesh ground
					end
				end
			end
		end
	end
	if hasKit then
		-- dense scatter clusters behind every nest, just outside the fence
		if #scatterKeys > 0 then
			local angles = {}
			for i = 1, Config.Station.Count do
				table.insert(angles, RoundRocks.stationAngle(i))
			end
			for k, cs in HuntZoneKit.clusterSpots(fenceHalf, angles) do
				local src = kit[scatterKeys[(k - 1) % #scatterKeys + 1]]
				local ext = if src:IsA("Model") then src:GetExtentsSize() elseif src:IsA("BasePart") then src.Size else Vector3.one
				local want = cs.Size * HuntZoneKit.BigScatter
				placeKit(f, src, "Scatter", { X = cs.X, Z = cs.Z, Yaw = cs.Yaw }, base, HuntZoneKit.fitScale(math.max(ext.X, ext.Z), want))
			end
		end
		-- lane markers along the north road (the kit's LaneMarker, else a glowing crystal pillar)
		local marker = kit.LaneMarker
		for _, m in HuntZoneKit.laneMarkers(fenceHalf) do
			if marker then
				placeKit(f, marker, "LaneMarker", m, base)
			else
				local cf = base * CFrame.new(m.X, 3.4, m.Z) * CFrame.Angles(0, m.Yaw, 0.12)
				local p = deco(f, "LaneMarker", Vector3.new(1.6, 7, 1.6), cf, style.Accent, Enum.Material.Neon)
				p:SetAttribute("ZoneKit", "LaneMarker")
				deco(f, "LaneMarkerBase", Vector3.new(3, 1, 3), base * CFrame.new(m.X, 0.5, m.Z) * CFrame.Angles(0, m.Yaw + 0.4, 0), style.Path, Enum.Material.SmoothPlastic)
			end
		end
	end
	f:SetAttribute("ZoneKit", hasKit)
	f.Parent = root
	if hasKit then
		-- the clear central path: flat strips on the ground from the hero's pad, down the road, through the gate, to
		-- the mound's edge (each strip on the ground under it)
		local half, zFar, zNear = HuntZoneKit.lane(fenceHalf)
		local z = zFar
		while z < zNear do
			local len = math.min(8, zNear - z)
			local y = groundY(f, base, 0, z + len / 2)
			local strip = deco(f, "ZonePath", Vector3.new(half * 2, 0.3, len + 0.4), base * CFrame.new(0, y + 0.12, z + len / 2), style.Path, Enum.Material.SmoothPlastic)
			strip.CastShadow = false
			z += len
		end
		-- contrasting pad + beacon light shaft at the two focal points: the hero and the gate
		for _, fp in { { 0, HuntZoneKit.HeroZ, 30, 160 }, { 0, -(fenceHalf + 4), 16, 0 } } do
			local px, pz, d, tall = fp[1], fp[2], fp[3], fp[4]
			local y = groundY(f, base, px, pz)
			local disc = CFrame.Angles(0, 0, math.pi / 2)
			deco(f, "FocalRing", Vector3.new(0.4, d + 2, d + 2), base * CFrame.new(px, y + 0.18, pz) * disc, style.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
			local pad = deco(f, "FocalPad", Vector3.new(0.5, d, d), base * CFrame.new(px, y + 0.3, pz) * disc, style.Pad, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			local light = Instance.new("PointLight")
			light.Color = style.Accent
			light.Range = 24
			light.Brightness = 2
			light.Parent = pad
			if tall > 0 then
				local shaft = deco(f, "Beacon", Vector3.new(tall, 7, 7), base * CFrame.new(px, y + tall / 2, pz) * disc, style.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
				shaft.Transparency = 0.55
				shaft:SetAttribute("ZoneKit", "Beacon")
			end
		end
	end
	if theme.Craters then
		spaceDressing(f, base, theme, fenceHalf)
	end
	if hasKit or theme.Craters or zone == "Volcano" or zone == "Meadow" then
		-- a ring of hills past the fence hides the sea and the blue horizon (the sky itself stays bright day):
		-- lilac in Space, dark rock in the Volcano, grass green in the Meadow
		local volcano = zone == "Volcano"
		local meadowHills = zone == "Meadow"
		local hr = Random.new(7373)
		for k = 0, 17 do
			local a = math.rad(k * 20 + hr:NextNumber(-6, 6))
			local r = hr:NextNumber(150, 175)
			local d = hr:NextNumber(70, 110)
			-- (with a zone kit: always, in the zone's hill colours, as the backstop behind its skyline)
			local hill = deco(f, "SpaceHill", Vector3.new(d, d, d), base * CFrame.new(math.cos(a) * r, -d * 0.18, math.sin(a) * r),
				if hasKit then style.Hill[k % #style.Hill + 1]
				elseif volcano then (if k % 2 == 0 then Color3.fromRGB(88, 70, 66) else Color3.fromRGB(110, 84, 74))
					elseif meadowHills then (if k % 2 == 0 then Color3.fromRGB(112, 172, 88) else Color3.fromRGB(96, 154, 76))
					else (if k % 2 == 0 then Color3.fromRGB(176, 150, 226) else Color3.fromRGB(150, 124, 204)),
				Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			hill.CastShadow = false
		end
	end
	-- the arena's own built pieces under the low-poly set (nest bases, machine-bay decks, the hopper apron) take the
	-- zone's stone / wood colours too; the Meadow puts back the colours they were built with
	local meadow = theme.Boulder == nil
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local parent = d.Parent
			local pname = if parent then parent.Name else ""
			local col: Color3? = nil
			local kind = false
			if d.Name == "Clearance" and string.sub(pname, 1, 19) == "CT_Rocks_MachineBay" then
				d.Transparency = 1 -- the machine deck's corner brackets read as white litter on the deck
			elseif d.Name == "NestBase" then
				col, kind = theme.Stone, true
			elseif (d.Name == "Plate" or d.Name == "InputTray" or d.Name == "OutputTray") and string.sub(pname, 1, 16) == "CT_Rocks_Station" then
				-- the nest table's plate and trays: half way to the zone stone, so they still read as their own pieces
				local was = d:GetAttribute("ZoneBase")
				local orig: Color3 = if typeof(was) == "Color3" then was else d.Color
				col, kind = orig:Lerp(theme.Stone, 0.5), true
			elseif (d.Name == "ShieldFrame" or d.Name == "ShieldPost" or d.Name == "DockPost" or d.Name == "DockBrace") and string.sub(pname, 1, 16) == "CT_Rocks_Station" then
				-- the nest table's pale pink shield and dock posts read as white litter in every zone: plain wood brown, a
				-- touch of the zone stone outside the meadow
				local brown = Color3.fromRGB(150, 108, 72)
				d.Color = if meadow then brown else brown:Lerp(theme.Stone, 0.35)
			elseif (d.Name == "Pad" and string.sub(pname, 1, 19) == "CT_Rocks_MachineBay") or d.Name == "HopperApron" then
				col, kind = if theme.Wood ~= WHITE then theme.Wood else nil, true
			end
			if kind then
				local was = d:GetAttribute("ZoneBase")
				if typeof(was) ~= "Color3" then
					was = d.Color
					d:SetAttribute("ZoneBase", was)
				end
				d.Color = if meadow or not col then was :: Color3 else col
			end
		end
	end
	setCovered(root, true)
	root:SetAttribute("LPCovered", true)
	local water = f:FindFirstChild("Hunt_Water")
	if water and water:IsA("BasePart") then
		bobWater(water)
	end
end

return HuntLowPoly
