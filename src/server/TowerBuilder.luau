--!strict
-- Pet Tower arenas: one fighting floor per run, far from the lobby and the egg arenas. Players stand on the
-- south side (-Z), pets line up in front of them, mobs come from the north side (+Z). Invisible walls keep
-- everyone on the floor; a plain invisible floor part does the colliding.
-- Look: when the owner's Blender kit is imported (ServerStorage "TowerRoomKit" + the TowerRoomKit module), each floor
-- is a square stone tower room built from it (walls, pillars, the glowing door arch on the mob side, banners,
-- braziers) and recoloured per theme. Without the kit, a tidy procedural stand-in (stone columns, low theme
-- dressing) is built instead.

local Workspace = game:GetService("Workspace")

local TowerRoomKit = require(script.Parent.TowerRoomKit)
local TowerPropSlots = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").TowerPropSlots)

local TowerBuilder = {}

local BASE = Vector3.new(4000, 300, 0) -- far from the lodge (origin) and the hunt arenas
local SPACING = 300
local RADIUS = 34
local ROOM = 48 -- half width of the kit room: 3 x 3 floor tiles of 32 studs
local TILE = 32
local free: { number } = {}
local used: { [number]: boolean } = {}
local folder: Folder? = nil

local COL = {
	Floor = Color3.fromRGB(196, 214, 150),
	Ring = Color3.fromRGB(246, 214, 120),
	Stone = Color3.fromRGB(176, 168, 190),
	Pillar = Color3.fromRGB(160, 132, 210),
	Cap = Color3.fromRGB(255, 196, 120),
	MobSide = Color3.fromRGB(255, 160, 150),
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "PetTower"
	f.Parent = Workspace
	folder = f
	return f
end

-- The kit room (owner's Blender TowerRoomKit). Pieces sit on y = 0 with their front on +Z, so each wall-side piece
-- is turned to face the room centre. Visual only (nothing collides); the fighting area in the middle stays clear.
local function kitRoom(m: Model, origin: CFrame): boolean
	for _, need in { "TR_Floor", "TR_Wall", "TR_Pillar", "TR_Arch" } do
		if not TowerRoomKit.has(need) then
			return false
		end
	end
	local room = Instance.new("Model")
	room.Name = "Room"
	local function put(name: string, label: string, cf: CFrame, scale: number?)
		if TowerRoomKit.has(name) then
			TowerRoomKit.place(room, name, label, cf, scale or 1)
		end
	end
	-- a spot (x, y, z) in arena space, turned so its front (+Z) looks at the room centre
	local function facing(x: number, y: number, z: number): CFrame
		local pos = origin * Vector3.new(x, y, z)
		local centre = origin * Vector3.new(0, y, 0)
		return CFrame.lookAt(pos, pos - (centre - pos))
	end
	for ix = -1, 1 do
		for iz = -1, 1 do
			put("TR_Floor", "Tile", origin * CFrame.new(ix * TILE, -TowerRoomKit.size("TR_Floor").Y, iz * TILE))
		end
	end
	-- a stone skirt under the walls: the gap between the floor tiles and the wall bases showed the sky
	do
		local skirt = Instance.new("Part")
		skirt.Name = "Stone"
		-- from 2 studs under the tiles up to just under their top face, so nothing shows between it and the wall bases
		local floorY = TowerRoomKit.size("TR_Floor").Y
		skirt.Size = Vector3.new(2 * ROOM + 40, floorY + 2, 2 * ROOM + 40)
		skirt.CFrame = origin * CFrame.new(0, -0.05 - (floorY + 2) / 2, 0)
		skirt.Color = Color3.fromRGB(120, 116, 110)
		skirt.Material = Enum.Material.SmoothPlastic
		skirt.Anchored = true
		skirt.CanCollide = false
		skirt.CanQuery = false
		skirt.CanTouch = false
		skirt.Parent = room
	end
	local depth = TowerRoomKit.size("TR_Wall").Z
	local edge = ROOM + depth / 2
	for k = -1, 1 do
		local along = k * TILE
		put("TR_Wall", "WallN", facing(along, 0, edge))
		put("TR_Wall", "WallS", facing(along, 0, -edge))
		put("TR_Wall", "WallE", facing(edge, 0, along))
		put("TR_Wall", "WallW", facing(-edge, 0, along))
	end
	-- corner posts: the wall ring left a sky gap where two walls meet behind the corner pillar
	do
		local corner = Instance.new("Model")
		corner.Name = "Corner"
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local post = Instance.new("Part")
				post.Name = "Stone"
				post.Size = Vector3.new(depth + 1, 30, depth + 1)
				post.CFrame = origin * CFrame.new(sx * edge, 9, sz * edge) -- down past the skirt
				post.Color = Color3.fromRGB(236, 230, 243)
				post.Material = Enum.Material.SmoothPlastic
				post.Anchored = true
				post.CanCollide = false
				post.CanQuery = false
				post.CanTouch = false
				post.Parent = corner
			end
		end
		corner.Parent = room
	end
	for _, a in { -ROOM, -TILE / 2, TILE / 2, ROOM } do
		put("TR_Pillar", "Pillar", facing(a, 0, edge))
		put("TR_Pillar", "Pillar", facing(a, 0, -edge))
		if math.abs(a) < ROOM then
			put("TR_Pillar", "Pillar", facing(edge, 0, a))
			put("TR_Pillar", "Pillar", facing(-edge, 0, a))
		end
	end
	-- the mobs' door: the glowing arch in the middle of the north wall
	put("TR_Arch", "Door", facing(0, 0, ROOM - TowerRoomKit.size("TR_Arch").Z / 2))
	-- the owner's low-poly door frame and door (IMPORT_NOW5, ServerStorage.LowPolyLib) in that arch, sized to its opening,
	-- flush with its front; static (the mobs walk out of the room's middle, not through the door)
	do
		local lib = game:GetService("ServerStorage"):FindFirstChild("LowPolyLib")
		local arch = TowerRoomKit.size("TR_Arch")
		local at = facing(0, 0, ROOM - arch.Z - 0.4)
		for _, name in { "TowerDoorFrame_LowPoly", "TowerDoor_LowPoly" } do
			local src = lib and lib:FindFirstChild(name)
			local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
			if mp then
				local p = mp:Clone()
				p.Name = name
				p.Size = mp.Size * (arch.X * 0.75 / 8.4) -- the frame (8.4 wide) fills three quarters of the arch width
				p.CFrame = at * CFrame.new(0, p.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Parent = room
			end
		end
	end
	-- flat floor marks only in the middle (nothing to trip the fight): the emblem, and a rug under the players
	put("TR_Emblem", "Emblem", origin * CFrame.new(0, -0.2, 0)) -- a raised pad: accent and rim both above the tiles
	put("TR_Rug", "Rug", origin * CFrame.new(0, 0, -32))
	-- the owner's 3D low-poly pieces (ServerStorage.LowPolyLib): base on `cf`, front toward the room, `k` x natural size
	local lowLib = game:GetService("ServerStorage"):FindFirstChild("LowPolyLib")
	local function lowPoly(name: string, label: string, cf: CFrame, k: number): BasePart?
		local src = lowLib and lowLib:FindFirstChild(name)
		local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
		if not mp then
			return nil
		end
		local p = mp:Clone()
		p.Name = label
		p.Size = mp.Size * k
		p.CFrame = cf * CFrame.new(0, p.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = room
		return p
	end
	-- dressing along the walls and in the corners: the 3D banner when imported (as tall as the kit banner), else the kit one
	local function banner(cf: CFrame)
		local src = lowLib and lowLib:FindFirstChild("TowerBanner_LowPoly")
		local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
		if not (mp and lowPoly("TowerBanner_LowPoly", "Banner", cf, TowerRoomKit.size("TR_Banner").Y / math.max(mp.Size.Y, 0.01))) then
			put("TR_Banner", "Banner", cf)
		end
	end
	for _, along in { -TILE, 0, TILE } do
		banner(facing(ROOM - 1, 7, along))
		banner(facing(-(ROOM - 1), 7, along))
	end
	for _, x in { -TILE, TILE } do
		banner(facing(x, 7, -(ROOM - 1)))
	end
	-- every wall's flat door panel is hidden (it read as a flat brown slab); the side walls get the 3D door instead
	for _, w in room:GetChildren() do
		if w:IsA("Model") and string.sub(w.Name, 1, 4) == "Wall" then
			local acc = w:FindFirstChild("Accent")
			if acc and acc:IsA("BasePart") then
				acc.Transparency = 1
			end
		end
	end
	-- side walls: the 3D door (same size as the one in the mobs' arch) where the panel was
	do
		local doorK = TowerRoomKit.size("TR_Arch").X * 0.75 / 8.4
		for _, along in { -TILE, 0, TILE } do
			for _, sx in { -1, 1 } do
				if lowPoly("TowerDoor_LowPoly", "SideDoor", facing(sx * (ROOM - 0.2), 0, along), doorK) then
					for _, w in room:GetChildren() do
						if (w.Name == "WallE" or w.Name == "WallW") and w:IsA("Model") then
							local pv = w:GetPivot().Position
							local here = origin * Vector3.new(sx * edge, 0, along)
							if (Vector3.new(pv.X, 0, pv.Z) - Vector3.new(here.X, 0, here.Z)).Magnitude < 2 then
								local acc = w:FindFirstChild("Accent")
								if acc and acc:IsA("BasePart") then
									acc.Transparency = 1 -- the door replaces the flat panel
								end
							end
						end
					end
				end
			end
		end
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			put("TR_Brazier", "Brazier", facing(sx * (ROOM - 7), 0, sz * (ROOM - 7)), 1.6) -- in scale with the 19-stud arches
			put("TR_Crystals", "Crystals", facing(sx * (ROOM - 8), 0, sz * (ROOM - 14))) -- clear of the wall faces
		end
		put("TR_Chest", "Chest", facing(sx * (ROOM - 27), 0, ROOM - 5), 1.8) -- beside the back-wall doors, not in front
	end
	room.Parent = m
	return true
end

local function build(origin: CFrame, slot: number): Model
	local m = Instance.new("Model")
	m.Name = "TowerFloor" .. slot
	-- Floor: a fat disc with a gold ring, plus a red disc on the mobs' side so the sides read at a glance. (The pale-blue
	-- pets' disc read as a puddle in Studio; the pets, the players and the kit's rug mark that side instead.)
	part(m, "Floor", Vector3.new(4, RADIUS * 2, RADIUS * 2), origin * CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.rad(90)), COL.Floor, Enum.PartType.Cylinder)
	part(m, "Ring", Vector3.new(4.2, RADIUS * 2 + 3, RADIUS * 2 + 3), origin * CFrame.new(0, -2.3, 0) * CFrame.Angles(0, 0, math.rad(90)), COL.Ring, Enum.PartType.Cylinder)
	-- a low slab with a darker rim under it, so it reads as a raised pad, not a decal
	local mobs = part(m, "MobSide", Vector3.new(0.5, 22, 22), origin * CFrame.new(0, 0.3, 12) * CFrame.Angles(0, 0, math.rad(90)), COL.MobSide, Enum.PartType.Cylinder)
	mobs.CanCollide = false
	local rim = part(m, "MobSideRim", Vector3.new(0.36, 23.4, 23.4), origin * CFrame.new(0, 0.2, 12) * CFrame.Angles(0, 0, math.rad(90)), COL.MobSide:Lerp(Color3.new(0, 0, 0), 0.3), Enum.PartType.Cylinder)
	rim.CanCollide = false
	-- Invisible walls keep everyone on the fighting floor (both looks).
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local wall = part(m, "Wall", Vector3.new(22, 30, 1), origin * CFrame.Angles(0, a, 0) * CFrame.new(0, 13, RADIUS - 0.5), COL.Stone)
		wall.Transparency = 1
	end
	if kitRoom(m, origin) then
		m:SetAttribute("Kit", true)
		for _, name in { "Floor", "Ring" } do
			local p = m:FindFirstChild(name) :: BasePart?
			if p then
				p.Transparency = 1 -- still the collider; the kit tiles are the floor you see
			end
		end
	else
		-- Stand-in: stone columns (base, shaft, capital) around the edge so the floor reads as a room in a tower.
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			local base = origin * CFrame.new(math.sin(a) * (RADIUS + 1), 0, math.cos(a) * (RADIUS + 1)) * CFrame.Angles(0, a, 0)
			part(m, "Plinth", Vector3.new(5, 1.4, 5), base * CFrame.new(0, 0.7, 0), COL.Stone)
			part(m, "Pillar", Vector3.new(3.4, 14, 3.4), base * CFrame.new(0, 8.4, 0), COL.Pillar)
			part(m, "Cap", Vector3.new(5, 1.4, 5), base * CFrame.new(0, 16.1, 0), COL.Cap)
		end
		-- Mob gate on the north side.
		part(m, "GateL", Vector3.new(3, 12, 3), origin * CFrame.new(-6, 6, RADIUS - 3), COL.Stone)
		part(m, "GateR", Vector3.new(3, 12, 3), origin * CFrame.new(6, 6, RADIUS - 3), COL.Stone)
		part(m, "GateTop", Vector3.new(15, 3, 3), origin * CFrame.new(0, 13.5, RADIUS - 3), COL.Cap)
	end
	local ceiling = part(m, "Ceiling", Vector3.new(RADIUS * 2.4, 1, RADIUS * 2.4), origin * CFrame.new(0, 34, 0), COL.Stone)
	ceiling.Transparency = 1
	m.PrimaryPart = m:FindFirstChild("Floor") :: Part
	m.Parent = root()
	return m
end

-- Owner's low-poly tower props (IMPORT_NOW4 tower_props, imported into ServerStorage.TowerProps_LowPoly): one mesh per
-- prop, a texture per floor theme. A ring of them stands along the east and west walls of the kit room, between the
-- pillars (never in the fight area or in front of the players' rug). No kit, no props.
local THEME_PROPS: { [string]: { { any } } } = { -- { prop, height }
	Jungle = { { "CliffPine", 13 }, { "Kit_Bush_A", 3.5 }, { "Kit_Tree_A", 11 }, { "FlowerBush", 3 }, { "Mushroom", 3 } },
	Lava = { { "Rock", 4 }, { "Crystals", 6 }, { "Kit_Rock_A", 3 }, { "Rock", 3 }, { "Crystals", 5 } },
	Ice = { { "CliffPine", 11 }, { "Crystals", 6 }, { "Rock", 3.5 }, { "CliffPine", 10 }, { "Kit_Rock_A", 3 } },
	Space = { { "Crystals", 7 }, { "Kit_Rock_A", 3 }, { "Rock", 4 }, { "Crystals", 5 }, { "Kit_Rock_A", 2.5 } },
}
local PROP_TEX: { [string]: { [string]: string } } = {
	CliffPine = { Ice = "rbxassetid://126381169994876", Jungle = "rbxassetid://137769791848746", Lava = "rbxassetid://101208525968066", Space = "rbxassetid://131077040710394" },
	Crystals = { Ice = "rbxassetid://91283769250531", Jungle = "rbxassetid://79062133730502", Lava = "rbxassetid://120350004870548", Space = "rbxassetid://113669184909190" },
	FlowerBush = { Ice = "rbxassetid://137827687647265", Jungle = "rbxassetid://134566110332735", Lava = "rbxassetid://99132004962560", Space = "rbxassetid://106504275926136" },
	Kit_Bush_A = { Ice = "rbxassetid://74887658151228", Jungle = "rbxassetid://139221721045406", Lava = "rbxassetid://130776082044736", Space = "rbxassetid://107131682610477" },
	Kit_Rock_A = { Ice = "rbxassetid://140028050702795", Jungle = "rbxassetid://140028050702795", Lava = "rbxassetid://140028050702795", Space = "rbxassetid://140028050702795" },
	Kit_Tree_A = { Ice = "rbxassetid://109578682907200", Jungle = "rbxassetid://133296195798037", Lava = "rbxassetid://86519725745959", Space = "rbxassetid://115540876428923" },
	Mushroom = { Ice = "rbxassetid://87164838386234", Jungle = "rbxassetid://87164838386234", Lava = "rbxassetid://87164838386234", Space = "rbxassetid://87164838386234" },
	PineTree = { Ice = "rbxassetid://123544408092828", Jungle = "rbxassetid://95774379961243", Lava = "rbxassetid://118183059207119", Space = "rbxassetid://103934000274426" },
	Rock = { Ice = "rbxassetid://119012433215485", Jungle = "rbxassetid://121235479982147", Lava = "rbxassetid://84492359657719", Space = "rbxassetid://116922990283062" },
}
local function themeProps(arena: Model, themeId: string, origin: CFrame, glow: Color3)
	local old = arena:FindFirstChild("ThemeProps")
	if old then
		old:Destroy()
	end
	local lib = game:GetService("ServerStorage"):FindFirstChild("TowerProps_LowPoly")
	local set = THEME_PROPS[themeId]
	if not (lib and set) then
		return
	end
	local m = Instance.new("Model")
	m.Name = "ThemeProps"
	local k = 0
	for _, sx in { -1, 1 } do
		-- one prop in each wall span between the side doors (doors at 0 and +-TILE, about 6 studs either side)
		for _, along in TowerPropSlots.Alongs do
			k += 1
			local pick = set[(k - 1) % #set + 1]
			local src = lib:FindFirstChild(pick[1] .. "_LowPoly")
			local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
			if mp then
				local p = mp:Clone()
				p.Name = pick[1]
				-- the mesh only: helper bits imported with it (particles, attachments, decals) showed as stray red dots
				for _, c in p:GetChildren() do
					if not c:IsA("SurfaceAppearance") then
						c:Destroy()
					end
				end
				-- trees keep their height (capping their width squashed the cliff pine into a low blob); the inset below keeps
				-- them off the wall
				local tree = string.find(pick[1], "Pine") ~= nil or string.find(pick[1], "Tree") ~= nil
				p.Size = mp.Size * TowerPropSlots.scale(mp.Size.X, mp.Size.Y, mp.Size.Z, pick[2], tree)
				local tex = PROP_TEX[pick[1]]
				if pick[1] == "Crystals" then
					-- crystals take the theme colour (their texture showed cyan ice in every room)
					for _, c in p:GetChildren() do
						if c:IsA("SurfaceAppearance") then
							c:Destroy()
						end
					end
					p.TextureID = ""
					p.Color = glow
					p.Material = Enum.Material.Glass
				elseif themeId == "Space" and (pick[1] == "Rock" or pick[1] == "Kit_Rock_A") then
					-- navy rocks vanished into the dark space floor: flat light lilac
					for _, c in p:GetChildren() do
						if c:IsA("SurfaceAppearance") then
							c:Destroy()
						end
					end
					p.TextureID = ""
					p.Color = Color3.fromRGB(178, 158, 228)
					p.Material = Enum.Material.SmoothPlastic
				elseif tex and tex[themeId] then
					p.TextureID = tex[themeId]
				end
				-- inset by the prop's own footprint so it never pokes through the wall
				local half = TowerPropSlots.half(p.Size.X, p.Size.Z)
				local px, pz = TowerPropSlots.position(sx, along, half)
				p.CFrame = origin * CFrame.new(px, p.Size.Y / 2, pz) * CFrame.Angles(0, k * 1.3, 0) * CFrame.Angles(0, math.pi, 0)
				p.Anchored = true
				p.CanCollide = true -- solid, so the camera stops at the trees instead of filling the screen with leaves
				p.CanQuery = false
				p.CanTouch = false
				p.Parent = m
			end
		end
	end
	-- jungle floors: the owner's mossy floor tiles and vine walls (ServerStorage.WorldKit_LowPoly) over the kit room
	local kit = game:GetService("ServerStorage"):FindFirstChild("WorldKit_LowPoly")
	local floorSrc = kit and kit:FindFirstChild("Tower_JungleFloor")
	local wallSrc = kit and kit:FindFirstChild("Tower_JungleWall")
	if themeId == "Jungle" and floorSrc and wallSrc and floorSrc:IsA("BasePart") and wallSrc:IsA("BasePart") then
		local function lay(src: BasePart, size: Vector3, cf: CFrame, solid: boolean?)
			local p = src:Clone()
			p.Size = size
			p.CFrame = cf
			p.Anchored = true
			p.CanCollide = solid == true -- walls solid so the camera stops at them
			p.CanQuery = false
			p.CanTouch = false
			p.Parent = m
		end
		local fk = TILE / floorSrc.Size.X
		local fs = floorSrc.Size * fk
		for ix = -1, 1 do
			for iz = -1, 1 do
				lay(floorSrc, fs, origin * CFrame.new(ix * TILE, 0.15 - fs.Y / 2, iz * TILE))
			end
		end
		local wk = TILE / wallSrc.Size.X
		local ws = wallSrc.Size * wk
		local centre = origin.Position
		for k2 = -1, 1 do
			for _, at in { Vector3.new(k2 * TILE, 0, ROOM), Vector3.new(k2 * TILE, 0, -ROOM), Vector3.new(ROOM, 0, k2 * TILE), Vector3.new(-ROOM, 0, k2 * TILE) } do
				local inward = -Vector3.new(math.sign(at.X) * (if math.abs(at.X) == ROOM then 1 else 0), 0, math.sign(at.Z) * (if math.abs(at.Z) == ROOM then 1 else 0))
				local pos = origin * (at - inward * (ws.Z / 2)) + Vector3.new(0, ws.Y / 2, 0)
				-- the mesh's front (-Z before the import flip) faces the room centre
				lay(wallSrc, ws, CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z)), true)
				-- the jungle wall mesh has a flat door painted on it: a 3D door stands in front of each one (the north
				-- middle slot is behind the mobs' arch door already)
				local doorLib = game:GetService("ServerStorage"):FindFirstChild("LowPolyLib")
				local dsrc = doorLib and doorLib:FindFirstChild("TowerDoor_LowPoly")
				local dmp = dsrc and dsrc:FindFirstChildWhichIsA("MeshPart", true)
				-- front and back walls only (the side walls have their SideDoor already)
				if dmp and math.abs(at.Z) == ROOM and not (k2 == 0 and at.Z == ROOM) then
					local door = dmp:Clone()
					door.Name = "JungleWallDoor"
					door.Size = dmp.Size * (TowerRoomKit.size("TR_Arch").X * 0.75 / 8.4)
					-- on the room side of the wall (its inner face is at the room edge), not behind it
					local base = origin * (at + inward * (door.Size.Z / 2 + 0.1))
					door.CFrame = CFrame.lookAt(base, base - Vector3.new(inward.X, 0, inward.Z))
						* CFrame.new(0, door.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
					door.Anchored = true
					door.CanCollide = false
					door.CanQuery = false
					door.CanTouch = false
					door.Parent = m
				end
			end
		end
	end
	m.Parent = arena
end

-- Lava floors: a warm glow accent so the room does not read dark. A few static lava pools in the corners and thin
-- cracks along the walls, all flat bright colour (SmoothPlastic, no Neon bloom, no lights) and away from the middle
-- where the pets and mobs fight. Any other theme just removes them.
local function lavaGlow(arena: Model, themeId: string, origin: CFrame, glow: Color3)
	local old = arena:FindFirstChild("LavaGlow")
	if old then
		old:Destroy()
	end
	if themeId ~= "Lava" then
		return
	end
	local m = Instance.new("Model")
	m.Name = "LavaGlow"
	local bright = glow:Lerp(Color3.fromRGB(255, 200, 90), 0.45)
	local edge = ROOM - 9
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local at = origin * CFrame.new(sx * edge, 0, sz * edge)
			local rim = part(m, "LavaRim", Vector3.new(0.3, 9, 9), at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 40, 30), Enum.PartType.Cylinder)
			rim.Material = Enum.Material.Basalt
			local pool = part(m, "LavaPool", Vector3.new(0.34, 7, 7), at * CFrame.new(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(90)), bright, Enum.PartType.Cylinder)
			pool.Material = Enum.Material.SmoothPlastic
		end
	end
	for i = 0, 7 do
		local side = i % 4
		local along = (if i < 4 then -0.45 else 0.45) * TILE
		local x, z, yaw = 0, 0, 0
		if side == 0 then
			x, z, yaw = along, edge + 2, 0
		elseif side == 1 then
			x, z, yaw = along, -edge - 2, 0
		elseif side == 2 then
			x, z, yaw = edge + 2, along, math.pi / 2
		else
			x, z, yaw = -edge - 2, along, math.pi / 2
		end
		local crack = part(m, "LavaCrack", Vector3.new(7, 0.12, 0.8), origin * CFrame.new(x, 0.18, z) * CFrame.Angles(0, yaw + (i - 3.5) * 0.12, 0), bright)
		crack.Material = Enum.Material.SmoothPlastic
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	m.Parent = arena
end

-- Recolours the floor and swaps its decorations for a theme (TowerConfig.Themes entry).
function TowerBuilder.theme(arena: Model, theme: any, origin: CFrame)
	if arena:GetAttribute("Theme") == theme.Id then
		return
	end
	arena:SetAttribute("Theme", theme.Id)
	for _, d in arena:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Floor" then
				d.Color = theme.Floor
			elseif d.Name == "Ring" or d.Name == "GateTop" then
				d.Color = theme.Ring
			elseif d.Name == "Pillar" or d.Name == "Plinth" or d.Name == "GateL" or d.Name == "GateR" then
				d.Color = theme.Pillar
			elseif d.Name == "Cap" then
				d.Color = theme.Cap
			end
		end
	end
	-- the mobs' half: salmon, pale blue on the ice floors and lilac in space (salmon read wrong there)
	local mobCol = if theme.Id == "Ice" then Color3.fromRGB(150, 200, 240) elseif theme.Id == "Space" then Color3.fromRGB(176, 150, 230) else COL.MobSide
	for _, n in { "MobSide", "MobSideRim" } do
		local d = arena:FindFirstChild(n)
		if d and d:IsA("BasePart") then
			d.Color = if n == "MobSideRim" then mobCol:Lerp(Color3.new(0, 0, 0), 0.3) else mobCol
		end
	end
	local room = arena:FindFirstChild("Room")
	if room then
		-- kit room: the accents, glow and a hint of the stone take the theme's colours; no extra props
		local accent = if theme.Id == "Ice" then theme.Ring else theme.Cap
		for _, d in room:GetDescendants() do
			if d:IsA("BasePart") then
				local base = d:GetAttribute("BaseColor")
				if typeof(base) ~= "Color3" then
					base = d.Color
					d:SetAttribute("BaseColor", base)
				end
				local pad = d.Parent ~= nil and (d.Parent.Name == "Rug" or d.Parent.Name == "Emblem")
				if pad and d.Name == "Trim" then
					-- the pads' gold border, half way to the floor (a thick bright yellow line in the dark space room)
					d.Color = (base :: Color3):Lerp(theme.Floor, 0.5)
				elseif pad and (d.Name == "Accent" or d.Name == "AccentDark") then
					-- the players' rug and the middle emblem: the theme floor, a shade darker, inside the gold trim (the
					-- bright accent slab was the brightest thing in the room)
					d.Color = theme.Floor:Lerp(Color3.new(0, 0, 0), if d.Name == "AccentDark" then 0.3 else 0.15)
				elseif d.Name == "Banner" and d:IsA("MeshPart") then
					-- the 3D banner's texture was green in every theme: flat theme accent instead
					for _, c in d:GetChildren() do
						if c:IsA("SurfaceAppearance") then
							c:Destroy()
						end
					end
					d.TextureID = ""
					d.Color = accent
				elseif d.Name == "Accent" then
					d.Color = accent
				elseif d.Name == "AccentDark" then
					d.Color = accent:Lerp(Color3.new(0, 0, 0), 0.3)
				elseif d.Name == "Glow" then
					-- flat colour, not Neon: the big doorway glow bloomed over the whole screen
					d.Color = theme.Glow
					d.Material = Enum.Material.SmoothPlastic
				elseif d.Name == "Stone" or d.Name == "StoneDark" then
					-- the room takes the theme's own colours (the pale lilac kit stone read the same in every theme):
					-- floor tiles the theme floor, walls / pillars / arches the theme pillar colour, the dark half darker
					local holder = d.Parent
					local tile = holder ~= nil and (holder.Name == "Tile" or holder.Name == "Emblem" or holder.Name == "Rug")
					local want: Color3 = if tile then theme.Floor else theme.Pillar
					local c = (base :: Color3):Lerp(want, 0.8)
					d.Color = if d.Name == "StoneDark" then c:Lerp(Color3.new(0, 0, 0), 0.18) else c
				end
			end
		end
		themeProps(arena, theme.Id, origin, theme.Glow)
		lavaGlow(arena, theme.Id, origin, theme.Glow)
		return
	end
	local old = arena:FindFirstChild("Decor")
	if old then
		old:Destroy()
	end
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	for i = 0, 9 do
		local a = (i + 0.5) / 10 * math.pi * 2
		local pos = origin * CFrame.new(math.sin(a) * (RADIUS - 3), 0, math.cos(a) * (RADIUS - 3))
		if theme.Id == "Jungle" then
			-- low leafy patches at the foot of the wall (tall green balls read as blobs)
			local moss = part(decor, "Moss", Vector3.new(0.4, 5, 5), pos * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), theme.Cap, Enum.PartType.Cylinder)
			moss.CanCollide = false
			local leaf = part(decor, "Leaf", Vector3.new(2.6, 0.5, 1.2), pos * CFrame.new(0.6, 0.45, 0.4) * CFrame.Angles(0, a, math.rad(18)), theme.Glow)
			leaf.CanCollide = false
		elseif theme.Id == "Lava" then
			local crack = part(decor, "LavaCrack", Vector3.new(6, 0.12, 1.2), pos * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, a, 0), theme.Glow)
			crack.Material = Enum.Material.Neon
			crack.CanCollide = false
		elseif theme.Id == "Ice" then
			local spike = part(decor, "IceSpike", Vector3.new(1.6, 5, 1.6), pos * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, a, math.rad(8)), theme.Glow)
			spike.Material = Enum.Material.Ice
			spike.Transparency = 0.25
			spike.CanCollide = false
		else
			local star = part(decor, "Star", Vector3.new(1.2, 1.2, 1.2), pos * CFrame.new(0, 9 + (i % 3) * 3, 0), theme.Glow, Enum.PartType.Ball)
			star.Material = Enum.Material.Neon
			star.CanCollide = false
		end
	end
	decor.Parent = arena
end

-- A free arena slot: (slot, arena model, origin CFrame at floor height, facing the mobs).
function TowerBuilder.claim(): (number, Model, CFrame)
	local slot: number = table.remove(free) or 0
	if slot == 0 then
		slot = 1
		while used[slot] do
			slot += 1
		end
	end
	used[slot] = true
	local origin = CFrame.new(BASE + Vector3.new((slot - 1) * SPACING, 0, 0))
	return slot, build(origin, slot), origin
end

function TowerBuilder.free(slot: number, arena: Model)
	arena:Destroy()
	used[slot] = nil
	table.insert(free, slot)
end

-- Where member `i` (1-4) stands: on the team's side, well behind the pet line (pets at z -14, mobs at +12),
-- on the players' rug and inside the invisible walls, facing the mobs.
local STAND_Z = -29
function TowerBuilder.standCFrame(origin: CFrame, i: number): CFrame
	local x = (i - 2.5) * 5
	local pos = origin * Vector3.new(x, 3.5, STAND_Z)
	return CFrame.lookAt(pos, pos + origin.LookVector * -1)
end

return TowerBuilder
