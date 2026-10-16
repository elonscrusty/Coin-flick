--!strict
-- Dino-jungle pet park (the public lobby, owner picks 2026-10-10, latest layout picture in the project thread): a
-- central grass clearing with the four queue nests (2 x 2, each glowing its own colour, each with a small count sign)
-- and a tall crowned leaderboard; 12 square fenced plots all around it with stone paths between them; the spawn plaza
-- with the stalls at the south end of the main stone path and the EGG SHOP hut at its north end. The park sits on
-- normal ground in a jungle valley closed by tall mossy cliffs and a spaced-out jungle edge (simple low-poly palms and
-- trees, a couple of giant dino skulls). Warm lanterns on fence posts and along the paths. No floating island, no
-- fountain, no waterfalls. Owner feedback built in: open space, bold shapes, few small props, few parts per tree.
--
-- Layout numbers: src/shared/ParkConfig.luau. LobbyBuilder calls ParkBuilder.build and puts the stalls (LodgeBuilder)
-- and the spawn on it. Everything is procedural Parts (REPLACE: real jungle / dino / nest meshes) except the kit cliffs
-- (Blender kit via MeshService, Part fallbacks when absent).
--
-- Contracts built here (for the queue and tower helpers; what they do is not implemented here):
--   * Part `TowerPortal` (attribute TowerPortal = true, CanTouch, no collision) in the PET TOWER doorway at the west
--     end of the cross path
--   * four queue nests: Parts `QueuePad1..4` (the glowing disc in each nest; attribute HuntPortal = true, QueuePad = n,
--     QueueColour = "Yellow" / "Blue" / "Pink" / "Green"; CanTouch, solid, stand-on height 0.4)
--   * one small sign per nest: Part `QueueSign` (attribute QueuePad = n) with a SurfaceGui holding the TextLabel
--     `QueueText` (default "STEP ON"), for that nest's count / countdown
--   * per plot a model CT_Rocks_Alcove_<i> (GalleryService; Main.client's "YOUR GALLERY" marker uses its `Floor`)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ParkConfig = require(Shared.ParkConfig)
local WhatsNew = require(Shared.WhatsNew)
local MapNames = require(Shared.MapNames)
local Kit = require(script.Parent.KitParts)
local KitPlace = require(script.Parent.KitPlace)

local part, deco, folder, model = Kit.part, Kit.deco, Kit.folder, Kit.model
local M = Enum.Material

local ParkBuilder = {}

-- Palette: lush deep greens, warm stone and timber, golden lantern light, teal and orange accents (not pastel).
local C = {
	Grass = Color3.fromRGB(72, 176, 52),
	GrassLight = Color3.fromRGB(110, 200, 60),
	Leaf = Color3.fromRGB(46, 170, 56),
	LeafDark = Color3.fromRGB(26, 128, 52),
	LeafLime = Color3.fromRGB(140, 214, 50),
	FernOrange = Color3.fromRGB(255, 122, 28),
	Trunk = Color3.fromRGB(160, 100, 52),
	TrunkDark = Color3.fromRGB(122, 74, 40),
	Stone = Color3.fromRGB(186, 176, 160),
	StoneWarm = Color3.fromRGB(214, 188, 146),
	StoneDark = Color3.fromRGB(124, 116, 104),
	Moss = Color3.fromRGB(78, 128, 48),
	Wood = Color3.fromRGB(176, 104, 48),
	WoodDark = Color3.fromRGB(122, 70, 36),
	Twig = Color3.fromRGB(168, 108, 50),
	TwigDark = Color3.fromRGB(124, 78, 38),
	Bone = Color3.fromRGB(236, 224, 196),
	BoneShade = Color3.fromRGB(196, 182, 152),
	Socket = Color3.fromRGB(54, 44, 40),
	Teal = Color3.fromRGB(0, 224, 204),
	TealDeep = Color3.fromRGB(22, 130, 126),
	Orange = Color3.fromRGB(255, 132, 24),
	Lantern = Color3.fromRGB(255, 190, 90),
	Iron = Color3.fromRGB(62, 52, 46),
	Glass = Color3.fromRGB(196, 242, 236),
	Cream = Color3.fromRGB(246, 232, 200),
	Gold = Color3.fromRGB(250, 196, 60),
}
ParkBuilder.Palette = C

-- Nest glow colours (ParkConfig.QueuePads.Colours)
local NEST = {
	Yellow = Color3.fromRGB(255, 212, 64),
	Blue = Color3.fromRGB(70, 186, 255),
	Pink = Color3.fromRGB(255, 104, 206),
	Green = Color3.fromRGB(104, 232, 104),
}
ParkBuilder.NestColours = NEST

local Y0 = 0 -- ground top (Config.Lodge.FloorY)
local PAVE_TOP = 0.05 -- paving / plot floor tops

-- Primitives -----------------------------------------------------------------------------------------------------

-- An ellipsoid (block + sphere mesh, any proportions).
local function blob(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = part(parent, name, size, cf, color, mat or M.SmoothPlastic)
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.Sphere
	sm.Parent = p
	return p
end

local function upCyl(parent: Instance, name: string, d: number, h: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return Kit.upCylinder(parent, name, d, h, cf, color, mat)
end

-- A flat walking surface (top at PAVE_TOP + lift).
local function pave(parent: Instance, name: string, w: number, d: number, cf: CFrame, color: Color3, mat: Enum.Material?, lift: number?): Part
	local h = 0.1 + (lift or 0) * 2
	local p = part(parent, name, Vector3.new(w, h, d), cf * CFrame.new(0, PAVE_TOP - h / 2 + (lift or 0), 0), color, mat or M.Cobblestone)
	p.CastShadow = false
	return p
end

local function quiet(m: Instance)
	KitPlace.cameraIgnore(m)
end

-- A warm lantern (dark cap + glowing body) sitting on `top` (world point). `light` adds a small PointLight.
-- Owner's Meshy prop (ServerStorage.MeshyAssets) fitted into `size`, bottom on `base`, turned by `yaw`, parented and
-- quieted; nil when that asset is missing so the caller builds its Part stand-in.
local function meshAt(parent: Instance, name: string, modelName: string, base: Vector3, size: Vector3, yaw: number?): Model?
	local mesh = KitPlace.meshy(name, CFrame.new(base + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, yaw or 0, 0), size)
	if not mesh then
		return nil
	end
	mesh.Name = modelName
	local box, ext = mesh:GetBoundingBox()
	mesh:PivotTo(mesh:GetPivot() + Vector3.new(0, base.Y + ext.Y / 2 - box.Position.Y, 0)) -- bottom on the ground
	mesh.Parent = parent
	quiet(mesh)
	return mesh
end

local function lantern(parent: Instance, top: Vector3, s: number, light: boolean?)
	local glow = deco(part(parent, "Lantern", Vector3.new(0.6, 0.75, 0.6) * s, CFrame.new(top + Vector3.new(0, 0.4 * s, 0)), C.Lantern, M.Neon))
	glow.CastShadow = false
	deco(part(parent, "LanternCap", Vector3.new(0.85, 0.2, 0.85) * s, CFrame.new(top + Vector3.new(0, 0.86 * s, 0)), C.Iron, M.Metal)).CastShadow = false
	if light then
		Kit.light(glow, "PointLight", Color3.fromRGB(255, 186, 110), 1.1, 14)
	end
end

-- Lantern post along a path: one timber post with a lantern on top.
local function lanternPost(parent: Instance, pos: Vector3, light: boolean)
	local mm = meshAt(parent, "MeshyLantern", "CT_Park_LanternPost", pos, Vector3.new(1.8, 5.4, 1.8))
	if mm then
		if light then
			local glow = Instance.new("Part")
			glow.Name = "LanternGlow"
			glow.Size = Vector3.new(0.2, 0.2, 0.2)
			glow.Transparency = 1
			glow.Position = pos + Vector3.new(0, 4.6, 0)
			Kit.deco(glow)
			glow.Parent = mm
			Kit.light(glow, "PointLight", Color3.fromRGB(255, 186, 110), 1.1, 14)
		end
		return
	end
	local m = model(parent, "CT_Park_LanternPost")
	part(m, "Post", Vector3.new(0.7, 4.2, 0.7), CFrame.new(pos + Vector3.new(0, 2.1, 0)), C.WoodDark, M.Wood)
	lantern(m, pos + Vector3.new(0, 4.2, 0), 1.3, light)
	quiet(m)
end

-- Simple low-poly palm (5 parts): one leaning trunk, four broad drooping fronds (Leaf / LeafDark sway on the client).
local function palm(parent: Instance, base: Vector3, h: number, rng: Random): Model
	local mm = meshAt(parent, "MeshyPalm", "CT_Park_Palm", base, Vector3.new(h * 0.9, h * 1.2, h * 0.9), rng:NextNumber(0, math.pi * 2))
	if mm then
		KitPlace.blocker(mm, CFrame.new(base + Vector3.new(0, h / 2, 0)), Vector3.new(1.3, h, 1.3), "TrunkBlock")
		return mm
	end
	local m = model(parent, "CT_Park_Palm")
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * (h * 0.12)
	local top = base + Vector3.new(0, h, 0) + lean
	local mid = (base + top) / 2
	local trunk = part(m, "Trunk", Vector3.new(h + 0.4, 1.3, 1.3), CFrame.lookAt(mid, top) * CFrame.Angles(0, math.rad(90), 0), C.Trunk, M.Wood, Enum.PartType.Cylinder)
	trunk.CanCollide = true
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, 4 do
		local a = a0 + i / 4 * math.pi * 2
		local L = h * 0.55
		deco(part(m, if i % 2 == 0 then "Leaf" else "LeafDark", Vector3.new(h * 0.2, 0.3, L), CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(-math.rad(24), 0, 0) * CFrame.new(0, 0, -L / 2), if i % 2 == 0 then C.Leaf else C.LeafDark, M.Grass))
	end
	KitPlace.sway(m, base + Vector3.new(0, h * 0.5, 0))
	quiet(m)
	return m
end

-- Simple low-poly broad tree (3 parts): trunk and two round canopies.
local function tree(parent: Instance, base: Vector3, s: number, rng: Random): Model
	local h = 9 * s
	-- the owner's MeshyTree (ServerStorage.MeshyAssets) at the same spot and about the same height; the code tree below
	-- is the fallback when it is missing
	local tall = h + 10 * s
	local mesh = KitPlace.meshy("MeshyTree", CFrame.new(base + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), Vector3.new(tall, tall, tall))
	if mesh then
		mesh.Name = "CT_Park_Tree"
		local box, ext = mesh:GetBoundingBox()
		mesh:PivotTo(mesh:GetPivot() + Vector3.new(0, base.Y + ext.Y / 2 - box.Position.Y, 0)) -- bottom on the ground
		mesh.Parent = parent
		quiet(mesh)
		return mesh
	end
	local m = model(parent, "CT_Park_Tree")
	part(m, "Trunk", Vector3.new(h, 1.8 * s, 1.8 * s), CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), C.TrunkDark, M.Wood, Enum.PartType.Cylinder)
	local d = rng:NextNumber(10, 12) * s
	deco(blob(m, "Leaves", Vector3.new(d, d * 0.75, d), CFrame.new(base + Vector3.new(0, h + 1 * s, 0)), if rng:NextNumber() < 0.5 then C.Leaf else C.LeafDark, M.Grass))
	deco(blob(m, "Leaves", Vector3.new(d * 0.6, d * 0.5, d * 0.6), CFrame.new(base + Vector3.new(d * 0.3, h + 3.4 * s, -d * 0.15)), C.LeafLime, M.Grass))
	KitPlace.sway(m, base + Vector3.new(0, h * 0.6, 0))
	quiet(m)
	return m
end

-- One round bush (1 part), green or orange.
local function bush(parent: Instance, base: Vector3, s: number, color: Color3)
	local b = deco(blob(parent, "Bush", Vector3.new(4, 2.6, 4) * s, CFrame.new(base + Vector3.new(0, 0.9 * s, 0)), color, M.Grass))
	b.CastShadow = false
	b:SetAttribute("CameraIgnore", true)
end

-- Giant dino skull lying on the ground (9 parts), snout toward cf's look direction.
local function skull(parent: Instance, cf: CFrame, s: number): Model
	local sk = KitPlace.meshy("MeshySkull", cf * CFrame.new(0, 3.2 * s, 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(8, 6.4, 13) * s)
	if sk then
		sk.Name = "CT_Park_Skull"
		sk.Parent = parent
		quiet(sk)
		return sk
	end
	local m = model(parent, "CT_Park_Skull")
	blob(m, "Cranium", Vector3.new(6.4, 4.8, 7) * s, cf * CFrame.new(0, 2.4 * s, 1.8 * s), C.Bone, M.SmoothPlastic)
	blob(m, "Snout", Vector3.new(4.2, 3.0, 7.4) * s, cf * CFrame.new(0, 1.9 * s, -3.6 * s) * CFrame.Angles(math.rad(-6), 0, 0), C.Bone, M.SmoothPlastic)
	for _, sx in { -1, 1 } do
		deco(blob(m, "Socket", Vector3.new(1.0, 1.9, 2.0) * s, cf * CFrame.new(sx * 2.9 * s, 2.9 * s, 0.4 * s), C.Socket, M.SmoothPlastic))
		deco(part(m, "Horn", Vector3.new(0.9, 2.6, 0.9) * s, cf * CFrame.new(sx * 2.4 * s, 5.0 * s, 2.4 * s) * CFrame.Angles(math.rad(-25), 0, sx * math.rad(-20)), C.BoneShade, M.SmoothPlastic))
		deco(part(m, "Tooth", Vector3.new(0.5, 1.3, 0.5) * s, cf * CFrame.new(sx * 1.6 * s, 0.9 * s, -5.6 * s), C.Cream, M.SmoothPlastic))
	end
	deco(part(m, "Jaw", Vector3.new(3.8, 0.8, 7.6) * s, cf * CFrame.new(0, 0.45 * s, -2.8 * s) * CFrame.Angles(math.rad(4), 0, 0), C.BoneShade, M.SmoothPlastic))
	quiet(m)
	return m
end

-- Fence run in a plot frame F from local a to b (ground plane): posts every ~5.4 studs, two rails, an invisible wall.
-- `lanterns` puts a warm lantern on the first and last post.
local function fenceRun(m: Instance, F: CFrame, a: Vector3, b: Vector3, lanterns: boolean)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 5.4 + 0.5))
	for k = 0, n do
		local p = a:Lerp(b, k / n)
		part(m, "FencePost", Vector3.new(0.8, 3.5, 0.8), F * CFrame.new(p + Vector3.new(0, 1.75, 0)), C.WoodDark, M.Wood)
		if lanterns and (k == 0 or k == n) then
			lantern(m, (F * CFrame.new(p + Vector3.new(0, 3.5, 0))).Position, 1)
		end
	end
	local mid = (a + b) / 2
	local dir = CFrame.lookAt(mid, b)
	for _, y in { 1.25, 2.5 } do
		part(m, "FenceRail", Vector3.new(0.3, 0.42, len), F * dir * CFrame.new(0, y, 0), C.Wood, M.Wood)
	end
	KitPlace.blocker(m, F * dir * CFrame.new(0, 2, 0), Vector3.new(0.6, 4, len), "FenceBlock")
end

-- A gold crown (7 parts), gem on the front (-Z of cf), base at cf. Used on the RAREST PET board and, scaled up,
-- floating over the most-liked plot (GalleryService moves that one).
function ParkBuilder.crown(parent: Instance, name: string, cf: CFrame, s: number): Model
	local cm = model(parent, name)
	deco(upCyl(cm, "CrownBand", 3.6 * s, 1.0 * s, cf * CFrame.new(0, 0.5 * s, 0), C.Gold, M.SmoothPlastic))
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		deco(part(cm, "CrownPoint", Vector3.new(0.8, 1.6, 0.8) * s, cf * CFrame.new(math.cos(a) * 1.5 * s, 1.6 * s, math.sin(a) * 1.5 * s) * CFrame.Angles(0, -a, 0), C.Gold, M.SmoothPlastic))
	end
	deco(part(cm, "CrownGem", Vector3.new(0.7, 0.7, 0.7) * s, cf * CFrame.new(0, 0.6 * s, -1.8 * s), Color3.fromRGB(230, 40, 60), M.Neon, Enum.PartType.Ball))
	quiet(cm)
	return cm
end

-- Plots ----------------------------------------------------------------------------------------------------------

export type Plot = {
	Index: number,
	Root: Model,
	Frame: CFrame, -- plot frame on the ground, LookVector toward the gate
	Plate: TextLabel,
	SetLabel: (string) -> (),
	-- the 3 glass domes (display slot k = dome k): pet frame (feet on the stand, facing the gate), plaque frame
	-- (+Z toward the viewer) and the pet scale
	Domes: { { Slot: CFrame, Label: CFrame, Scale: number } },
	SetLikes: (number) -> (), -- the LIKE sign's count
	CrownAt: CFrame, -- where the most-liked crown floats over this plot
	Wander: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }, -- plot-local box for wandering pets
	-- kept for the old alcove interface (GalleryService, older tools)
	Shutters: { BasePart },
	SetCapacity: (number) -> (),
	LabelDepth: number,
}

local function buildPlot(parent: Instance, i: number): Plot
	local P = ParkConfig.Plot
	local S = ParkConfig.Showcase
	local F = ParkConfig.plotFrame(i, Y0)
	local half = P.Size / 2
	local m = model(parent, MapNames.plot(i))
	m:SetAttribute("Plot", i)
	-- yard floor (the "YOUR GALLERY" marker targets `Floor`) and a dirt patch where the commons wander
	pave(m, "Floor", P.Size - 0.4, P.Size - 0.4, F, C.GrassLight, M.Grass)
	local W = S.Wander
	pave(m, "RouteYard", W.MaxX - W.MinX + 3, W.MaxZ - W.MinZ + 3, F * CFrame.new((W.MinX + W.MaxX) / 2, 0, (W.MinZ + W.MaxZ) / 2), Color3.fromRGB(176, 136, 88), M.Ground, 0.02)
	-- fence with the gate gap toward the path; lanterns on the corner posts
	local g = 3.4
	fenceRun(m, F, Vector3.new(-half, 0, half), Vector3.new(half, 0, half), true)
	fenceRun(m, F, Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half), false)
	fenceRun(m, F, Vector3.new(half, 0, -half), Vector3.new(half, 0, half), false)
	fenceRun(m, F, Vector3.new(-half, 0, -half), Vector3.new(-g - 0.6, 0, -half), true)
	fenceRun(m, F, Vector3.new(g + 0.6, 0, -half), Vector3.new(half, 0, -half), true)
	-- gate: two thick posts with lanterns, a beam, the owner's name sign facing the path
	for _, sx in { -1, 1 } do
		part(m, "GatePost", Vector3.new(1.3, 7.4, 1.3), F * CFrame.new(sx * (g + 0.2), 3.7, -half), C.WoodDark, M.Wood)
		lantern(m, (F * CFrame.new(sx * (g + 0.2), 7.4, -half)).Position, 1.4, sx > 0)
	end
	deco(part(m, "GateBeam", Vector3.new(2 * g + 2.4, 0.8, 1.0), F * CFrame.new(0, 6.6, -half), C.Wood, M.Wood))
	local plateFace, plateText = KitPlace.signBoard(m, "Nameplate", F * CFrame.new(0, 8.1, -half - 0.35) * CFrame.Angles(0, math.pi, 0), 8.4, 1.7, ParkConfig.EmptyPlot, "Nameplate", { Face = C.WoodDark, Frame = C.Wood, Trim = C.Orange, Ink = C.Cream })
	local NW, NH = 8.4, 1.7
	local function setLabel(text: string)
		local fit = KitPlace.applyFit(plateText.Parent :: SurfaceGui, plateText, text, NW, NH, "Nameplate")
		plateFace:SetAttribute("SignText", fit.Text)
		plateFace:SetAttribute("SignFill", fit.Fill)
		-- a free plot's sign glows soft green (text colour only, no light); an owned plot's name stays cream
		plateText.TextColor3 = if text == ParkConfig.EmptyPlot then Color3.fromRGB(150, 235, 160) else C.Cream
	end
	setLabel(ParkConfig.EmptyPlot)
	-- the 3 glass domes on stone stands at the back (owner pick: the player chooses the pets inside); the middle one
	-- is bigger and carries the plot's glow light
	local domes = {}
	for k, D in S.Domes do
		local bc = F * CFrame.new(D.X, 0, D.Z)
		upCyl(m, "DomePlinth", D.Plinth, 0.9, bc * CFrame.new(0, 0.45, 0), C.Stone, M.Slate)
		upCyl(m, "DomeTier", D.Plinth - 0.8, D.Height - 0.9 + 0.01, bc * CFrame.new(0, 0.9 + (D.Height - 0.9) / 2, 0), C.StoneDark, M.Slate)
		deco(upCyl(m, "ShelfLight", D.Plinth + 0.35, 0.22, bc * CFrame.new(0, 0.78, 0), C.Teal, M.Neon)).CastShadow = false
		local dome = part(m, "Dome", Vector3.new(D.Dome, D.Dome, D.Dome), bc * CFrame.new(0, D.Height, 0), C.Glass, M.Glass, Enum.PartType.Ball)
		dome.Transparency = 0.64
		dome.CastShadow = false
		dome.CanQuery = false
		if k == 1 then
			local glow = deco(part(m, "Light", Vector3.new(0.2, 0.2, 0.2), bc * CFrame.new(0, D.Height + 3, 0), C.Teal, M.SmoothPlastic))
			glow.Transparency = 1
			Kit.light(glow, "PointLight", Color3.fromRGB(120, 255, 236), 1.0, 14)
		end
		local pw = math.min(3.6, D.Plinth * 0.48)
		part(m, "PlaqueStand", Vector3.new(pw + 0.4, 0.9, 0.7), bc * CFrame.new(0, 0.45, -D.Plinth / 2 - 0.5), C.StoneDark, M.Slate)
		table.insert(domes, {
			Slot = bc * CFrame.new(0, D.Height, 0),
			Label = bc * CFrame.new(0, 0.48, -D.Plinth / 2 - 0.88) * CFrame.Angles(0, math.pi, 0),
			Scale = D.PetScale,
		})
	end
	-- LIKE post just inside the gate: a wooden post with a pink like sign; its prompt (attribute LikePlot = i) is
	-- handled by GalleryService (one like per visitor per plot owner per server session, server-checked)
	local lp = F * CFrame.new(g + 6, 0, -half + 2.4)
	local post = part(m, "LikePost", Vector3.new(0.8, 4.2, 0.8), lp * CFrame.new(0, 2.1, 0), C.WoodDark, M.Wood)
	local likeFace, likeText = KitPlace.signText(m, "LikeSign", lp * CFrame.new(0, 4.4, -0.45) * CFrame.Angles(0, math.pi, 0), 3.0, 1.3, "0 LIKES", "Plaque", C.Cream, Color3.fromRGB(226, 70, 150))
	local likePrompt = Kit.prompt(post, "Like", ParkConfig.EmptyPlot, "", 9)
	likePrompt.Name = "LikePrompt"
	likePrompt:SetAttribute("Off", true) -- GalleryService turns it on when someone owns the plot
	likePrompt:SetAttribute("LikePlot", i)
	local function setLikes(n: number)
		local text = if n == 1 then "1 LIKE" else tostring(n) .. " LIKES"
		local fit = KitPlace.applyFit(likeText.Parent :: SurfaceGui, likeText, text, 3.0, 1.3, "Plaque")
		likeFace:SetAttribute("SignText", fit.Text)
	end
	-- one bush in a back corner (alternating sides and colours)
	local side = if i % 2 == 0 then 1 else -1
	bush(m, (F * CFrame.new(side * (half - 3), 0, half - 3)).Position, 0.9, if i % 3 == 0 then C.FernOrange else C.Leaf)
	return {
		SetLikes = setLikes,
		CrownAt = F * CFrame.new(0, ParkConfig.Likes.CrownHeight, 4),
		Index = i,
		Root = m,
		Frame = F,
		Plate = plateText,
		SetLabel = setLabel,
		Domes = domes,
		Wander = { MinX = W.MinX, MaxX = W.MaxX, MinZ = W.MinZ, MaxZ = W.MaxZ },
		Shutters = {},
		SetCapacity = function(_n: number) end,
		LabelDepth = 1,
	}
end

-- Paths, clearing, nests ----------------------------------------------------------------------------------------

local function buildPaths(root: Instance)
	local f = folder(root, "CT_Park_Paths")
	local Pa, Cl = ParkConfig.Path, ParkConfig.Clearing
	local ring, w = Pa.Ring, Pa.Width
	local outer = 88 -- the plots' outer edge (cells at 66 +- 16, plus a margin)
	-- the stone ring around the clearing, out to the plots' outer edge on all four sides
	for _, s in { -1, 1 } do
		pave(f, "RouteRing", outer * 2, w, CFrame.new(0, Y0, s * ring), C.Stone, M.Cobblestone)
		pave(f, "RouteRing", w, ring * 2 - w - 0.2, CFrame.new(s * ring, Y0, 0), C.Stone, M.Cobblestone)
		pave(f, "RouteRing", w, outer - ring - w / 2 - 0.1, CFrame.new(s * ring, Y0, (ring + w / 2 + outer) / 2), C.Stone, M.Cobblestone)
		pave(f, "RouteRing", w, outer - ring - w / 2 - 0.1, CFrame.new(s * ring, Y0, -(ring + w / 2 + outer) / 2), C.Stone, M.Cobblestone)
	end
	-- the main path (x = 0) from the spawn plaza to the ring and on from the ring to the EGG SHOP, and the cross paths
	-- between the west / east plots (z = 0)
	local Pz, Sh = ParkConfig.Plaza, ParkConfig.Shop
	local southFrom, southTo = Pz.MinZ, ring + w / 2
	pave(f, "RouteMain", w, southFrom - southTo, CFrame.new(0, Y0, (southFrom + southTo) / 2), C.StoneWarm, M.Cobblestone)
	local northFrom, northTo = -(ring + w / 2), Sh.Z + 6
	pave(f, "RouteMain", w, northFrom - northTo, CFrame.new(0, Y0, (northFrom + northTo) / 2), C.StoneWarm, M.Cobblestone)
	for _, s in { -1, 1 } do
		local from, to = ring + w / 2, outer
		pave(f, "RouteCross", to - from, w, CFrame.new(s * (from + to) / 2, Y0, 0), C.Stone, M.Cobblestone)
	end
	-- a short stone apron from the ring into the clearing on the main path (where people walk in)
	local apron = ring - w / 2 - (Cl.Half - 8)
	for _, s in { -1, 1 } do
		pave(f, "RouteApron", w, apron, CFrame.new(0, Y0, s * (ring - w / 2 - apron / 2)), C.StoneWarm, M.Cobblestone)
	end
	-- lantern posts along the paths (every third one lit)
	local k = 0
	local function post(x: number, z: number)
		k += 1
		lanternPost(f, Vector3.new(x, 0, z), k % 3 == 0)
	end
	for _, z in { 62, 80, -62, -80, -98 } do
		post(-(w / 2 + 1), z)
		post(w / 2 + 1, z)
	end
	for _, s in { -1, 1 } do
		for _, t in { -30, 30 } do
			post(t, s * (ring - w / 2 - 1)) -- inner side of the north / south ring
			post(s * (ring - w / 2 - 1), t) -- inner side of the west / east ring
		end
	end
end

-- One woven nest around a glowing pad, a small count sign beside it.
local function nest(parent: Instance, n: number, x: number, z: number, colourName: string)
	local Q = ParkConfig.QueuePads
	local col = NEST[colourName] or C.Teal
	local m = model(parent, "CT_Park_Nest" .. n)
	local c = CFrame.new(x, Y0, z)
	local R = Q.Size / 2
	-- the woven rim: twig rolls around the pad (two rows, alternating tones). REPLACE: real woven nest mesh.
	local ring = meshAt(m, "MeshyNestRing", "NestRim", c.Position, Vector3.new(Q.Size + 4.6, 2.2, Q.Size + 4.6), n)
	local segs = if ring then 0 else 10
	for k = 0, segs - 1 do
		local a = k / segs * math.pi * 2
		local p = c * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.7 + (k % 2) * 0.08, -(R + 0.9))
		deco(blob(m, "Twig", Vector3.new(3.4, 1.4, 1.7), p * CFrame.Angles(0, 0, math.rad(if k % 2 == 0 then 12 else -12)), if k % 2 == 0 then C.Twig else C.TwigDark, M.Wood))
	end
	for k = 0, segs - 1 do
		local a = (k + 0.5) / segs * math.pi * 2
		local p = c * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.45 + (k % 2) * 0.08, -(R + 0.7)) -- alternate heights: no coplanar tops
		deco(blob(m, "Twig", Vector3.new(3.2, 0.9, 1.3), p, if k % 2 == 0 then C.TwigDark else C.Twig, M.Wood))
	end
	local pad = Instance.new("Part")
	pad.Name = MapNames.QueuePad .. n
	pad:SetAttribute("HuntPortal", true)
	pad:SetAttribute("PadIndex", n) -- PartyService lights the pads in this order, one per queued player
	pad:SetAttribute("QueuePad", n)
	pad:SetAttribute("QueueColour", colourName)
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.4, Q.Size, Q.Size)
	pad.CFrame = c * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = col
	pad.Material = M.Neon
	pad.Transparency = 0.05
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = true
	pad.CanQuery = false
	pad.CastShadow = false
	pad.Parent = m
	Kit.light(pad, "PointLight", col, 1.4, 14)
	quiet(m)
end

local function buildClearing(root: Instance, rng: Random)
	local f = folder(root, "CT_Park_Clearing")
	local Q = ParkConfig.QueuePads
	for n, s in Q.Spots do
		nest(f, n, s[1], s[2], Q.Colours[n])
	end
	-- the one queue board (PartyService writes the count / countdown into QueueBoard/QueueText) on a timber arch just
	-- north of the nests, facing the spawn; the arch posts stand outside the middle walk
	local bz = -21
	for _, sx in { -1, 1 } do
		part(f, "QueueArchPost", Vector3.new(1, 9.6, 1), CFrame.new(sx * 6, 4.8, bz), C.WoodDark, M.Wood)
	end
	deco(part(f, "QueueArchFrame", Vector3.new(11.4, 3.4, 0.5), CFrame.new(0, 8.2, bz - 0.1), C.Wood, M.Wood))
	local qb = Instance.new("Part")
	qb.Name = MapNames.QueueBoard
	qb.Size = Vector3.new(10.6, 2.8, 0.1)
	qb.CFrame = CFrame.new(0, 8.2, bz + 0.2) * CFrame.Angles(0, math.pi, 0) -- Front face toward +Z (the spawn side)
	qb.Color = Color3.fromRGB(36, 30, 28)
	qb.Material = M.SmoothPlastic
	qb.Anchored = true
	qb.CanCollide = false
	qb.CanQuery = false
	qb.CanTouch = false
	qb.CastShadow = false
	qb:SetAttribute("CameraIgnore", true)
	qb.Parent = f
	local gui = Instance.new("SurfaceGui")
	gui.Name = "QueueGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = qb
	local text = Instance.new("TextLabel")
	text.Name = MapNames.QueueText
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = C.Gold
	text.TextScaled = true
	text.Text = "STEP ON TO PLAY"
	text.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.14, 0)
	padding.PaddingBottom = UDim.new(0.14, 0)
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.Parent = text
	-- (the RAREST PET board wears the kit's own trophy emblem on top: LodgeBuilder.buildBoards; no extra crown there)
	-- a few bushes in the clearing corners (not in the walk lines)
	for _, p in { Vector3.new(-32, 0, -32), Vector3.new(32, 0, 30), Vector3.new(-33, 0, 28), Vector3.new(30, 0, -32) } do
		bush(f, p, rng:NextNumber(1.0, 1.3), if p.X > 0 then C.Leaf else C.FernOrange)
	end
end

-- Jungle edge, cliffs and the valley floor -------------------------------------------------------------------------

local CLIFFS = { "Cliff_A", "Cliff_B", "Cliff_C", "Cliff_D", "Cliff_E", "Cliff_F", "Cliff_Corner" }
local CLIFF_TONE: { [string]: Color3 } = {
	Cliff = Color3.fromRGB(128, 120, 104),
	CliffDark = Color3.fromRGB(98, 92, 82),
	RockLight = Color3.fromRGB(150, 140, 120),
	Moss = Color3.fromRGB(70, 124, 46),
}

local function buildValley(root: Instance, rng: Random)
	local B = ParkConfig.Bounds
	local f = folder(root, "CT_Park_Jungle")
	part(root, "CT_Rocks_Ground", Vector3.new(800, 2, 800), CFrame.new(0, Y0 - 1, 0), C.Grass, M.Grass)
	-- tall mossy cliffs all round (kit cliffs, toned; procedural bands when the kit is missing)
	local edge = folder(f, "CT_Park_Cliffs")
	local function row(from: Vector3, to: Vector3, faceDir: Vector3, lo: number, hi: number, pitch: number)
		local len = (to - from).Magnitude
		local dir = (to - from).Unit
		local n = math.max(1, math.floor(len / pitch))
		for k = 0, n - 1 do
			local pos = from + dir * (len * (k + 0.5) / n) + faceDir * rng:NextNumber(-3, 3)
			local cf = KitPlace.facing(Vector3.new(pos.X, -0.5, pos.Z), faceDir) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0)
			local c = KitPlace.place(edge, CLIFFS[rng:NextInteger(1, #CLIFFS)], cf, rng:NextNumber(lo, hi))
			if c then
				KitPlace.tone(c, CLIFF_TONE)
				quiet(c)
			end
		end
	end
	if KitPlace.has("Cliff_A", "Cliff_B", "Cliff_C") then
		row(Vector3.new(B.MinX - 26, 0, B.MinZ - 30), Vector3.new(B.MinX - 26, 0, B.MaxZ + 30), Vector3.xAxis, 2.2, 2.8, 32)
		row(Vector3.new(B.MaxX + 26, 0, B.MinZ - 30), Vector3.new(B.MaxX + 26, 0, B.MaxZ + 30), -Vector3.xAxis, 2.2, 2.8, 32)
		row(Vector3.new(B.MinX - 26, 0, B.MinZ - 28), Vector3.new(B.MaxX + 26, 0, B.MinZ - 28), Vector3.zAxis, 2.6, 3.2, 32)
		row(Vector3.new(B.MinX - 26, 0, B.MaxZ + 26), Vector3.new(B.MaxX + 26, 0, B.MaxZ + 26), -Vector3.zAxis, 2.0, 2.5, 32)
	else
		Kit.cliff(edge, CFrame.new(0, 0, B.MinZ - 28), 280, 44, rng)
		Kit.cliff(edge, CFrame.new(0, 0, B.MaxZ + 26) * CFrame.Angles(0, math.pi, 0), 280, 32, rng)
		Kit.cliff(edge, CFrame.new(B.MinX - 26, 0, 0) * CFrame.Angles(0, math.rad(90), 0), 320, 38, rng)
		Kit.cliff(edge, CFrame.new(B.MaxX + 26, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), 320, 38, rng)
	end
	-- the jungle edge: simple palms and broad trees, spaced out, just outside the boundary
	local function edgeRow(from: Vector3, to: Vector3, pitch: number)
		local len = (to - from).Magnitude
		local n = math.max(1, math.floor(len / pitch))
		for k = 0, n - 1 do
			local p = from:Lerp(to, (k + rng:NextNumber(0.3, 0.7)) / n)
			if k % 2 == 0 then
				palm(f, p, rng:NextNumber(16, 22), rng)
			else
				tree(f, p, rng:NextNumber(1.3, 1.7), rng)
			end
		end
	end
	edgeRow(Vector3.new(B.MinX - 4, 0, B.MinZ), Vector3.new(B.MinX - 4, 0, B.MaxZ), 20)
	edgeRow(Vector3.new(B.MaxX + 4, 0, B.MinZ), Vector3.new(B.MaxX + 4, 0, B.MaxZ), 20)
	edgeRow(Vector3.new(B.MinX + 8, 0, B.MinZ - 4), Vector3.new(B.MaxX - 8, 0, B.MinZ - 4), 20)
	edgeRow(Vector3.new(B.MinX + 8, 0, B.MaxZ + 4), Vector3.new(B.MaxX - 8, 0, B.MaxZ + 4), 20)
	-- the margins between the plots' outer fences (|x| = 82) and the boundary: a few palms, trees, bushes
	for _, s in { -1, 1 } do
		for k, z in { -110, -70, -34, 24, 50, 90, 124 } do
			local x = s * rng:NextNumber(91, 97)
			if k % 2 == 0 then
				palm(f, Vector3.new(x, 0, z), rng:NextNumber(14, 19), rng)
			else
				tree(f, Vector3.new(x, 0, z), rng:NextNumber(1.0, 1.2), rng)
			end
			bush(f, Vector3.new(x - s * 5, 0, z + 6), 1.1, if k % 3 == 0 then C.FernOrange else C.Leaf)
		end
		-- north margin beside the EGG SHOP
		for _, x in { 30, 70 } do
			palm(f, Vector3.new(s * x, 0, -112 + rng:NextNumber(-4, 4)), rng:NextNumber(14, 18), rng)
		end
	end
	-- two giant dino skulls in the margins (bold shapes, not clutter)
	skull(f, KitPlace.facing(Vector3.new(-95, 0, -34), Vector3.new(0.35, 0, 1).Unit), 1.3)
	skull(f, CFrame.lookAt(Vector3.new(93, 0, 70), Vector3.new(70, 0, 60)), 1.1)
	-- secret egg: a small mossy speckled egg tucked behind a bush in the far north-east corner of the jungle edge,
	-- reachable on foot. Only the hook lives here (part SecretEgg, attribute SecretEgg = true, prompt "Take");
	-- the award side is handled elsewhere through that attribute. REPLACE: real mesh
	local SE = ParkConfig.SecretEgg
	bush(f, Vector3.new(SE.X - 3.2, 0, SE.Z + 2.6), 1.15, C.LeafDark)
	bush(f, Vector3.new(SE.X + 1.4, 0, SE.Z + 3.6), 0.8, C.Leaf)
	local egg = blob(f, MapNames.SecretEgg, Vector3.new(1.2, 1.6, 1.2), CFrame.new(SE.X, Y0 + 0.75, SE.Z) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(96, 132, 70), M.SmoothPlastic)
	egg.CanCollide = true
	egg.CanQuery = true
	egg:SetAttribute("SecretEgg", true)
	for k = 1, 3 do
		local a = k * 2.1
		deco(blob(f, "SecretEggSpot", Vector3.new(0.34, 0.34, 0.12), CFrame.new(SE.X + math.cos(a) * 0.58, Y0 + 0.5 + k * 0.22, SE.Z + math.sin(a) * 0.58) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(196, 170, 70), M.SmoothPlastic))
	end
	local take = Kit.prompt(egg, "Take", "???", "", 6)
	take.Name = "Take"
	take.RequiresLineOfSight = false
	-- invisible boundary around the park
	local bounds = folder(f, "CT_Park_Bounds")
	for _, bd in {
		{ Vector3.new(0, 40, B.MaxZ), Vector3.new(B.MaxX - B.MinX, 80, 1) },
		{ Vector3.new(0, 40, B.MinZ), Vector3.new(B.MaxX - B.MinX, 80, 1) },
		{ Vector3.new(B.MinX, 40, (B.MinZ + B.MaxZ) / 2), Vector3.new(1, 80, B.MaxZ - B.MinZ) },
		{ Vector3.new(B.MaxX, 40, (B.MinZ + B.MaxZ) / 2), Vector3.new(1, 80, B.MaxZ - B.MinZ) },
	} do
		local w = part(bounds, "Bounds", bd[2], CFrame.new(bd[1]), Color3.new(), M.SmoothPlastic)
		w.Transparency = 1
		w.CanQuery = false
		w.CastShadow = false
	end
end

local function buildPlaza(root: Instance, rng: Random)
	local Pz = ParkConfig.Plaza
	local f = folder(root, "CT_Park_Plaza")
	pave(f, "RoutePlaza", Pz.MaxX - Pz.MinX, Pz.MaxZ - Pz.MinZ, CFrame.new((Pz.MinX + Pz.MaxX) / 2, Y0, (Pz.MinZ + Pz.MaxZ) / 2), C.StoneWarm, M.Cobblestone)
	-- the park sign on a timber arch where the main path leaves the plaza toward the clearing
	local az = Pz.MinZ + 1
	for _, sx in { -1, 1 } do
		part(f, "ArchPost", Vector3.new(1.8, 11, 1.8), CFrame.new(sx * 7.5, 5.5, az), C.WoodDark, M.Wood)
		lantern(f, Vector3.new(sx * 7.5, 11, az), 1.6, true)
	end
	deco(part(f, "ArchBeam", Vector3.new(17.4, 1.2, 1.4), CFrame.new(0, 10.5, az), C.Wood, M.Wood))
	KitPlace.signBoard(f, "ParkSign", CFrame.new(0, 12.6, az + 0.8), 12, 2.6, "PET PARK", "Landmark", { Face = C.WoodDark, Frame = C.Wood, Trim = C.Orange, Outline = true })
	-- a few lantern posts and two palms around the plaza
	for _, p in { Vector3.new(-14, 0, 94), Vector3.new(14, 0, 94), Vector3.new(-6, 0, 131), Vector3.new(6, 0, 131) } do
		lanternPost(f, p, true)
	end
	for _, p in { Vector3.new(-14, 0, 136), Vector3.new(14, 0, 136) } do
		palm(f, p, rng:NextNumber(15, 18), rng)
	end
	-- WHAT'S NEW board beside the arch, facing the spawn: a heading sign over a pale notes panel (shared/WhatsNew)
	local N = ParkConfig.NewsBoard
	local nb = model(f, "CT_Park_WhatsNew")
	local bottom = 1.6
	for _, sx in { -1, 1 } do
		part(nb, "NewsPost", Vector3.new(1.2, bottom + N.H + 3.6, 1.2), CFrame.new(N.X + sx * (N.W / 2 + 0.7), (bottom + N.H + 3.6) / 2, N.Z - 0.3), C.WoodDark, M.Wood)
	end
	part(nb, "NewsBack", Vector3.new(N.W + 0.6, N.H + 0.6, 0.4), CFrame.new(N.X, bottom + N.H / 2, N.Z - 0.35), C.Wood, M.WoodPlanks)
	KitPlace.signText(nb, "WhatsNewText", CFrame.new(N.X, bottom + N.H / 2, N.Z - 0.1), N.W, N.H, table.concat(WhatsNew.Lines, "\n"), "Placard", Color3.fromRGB(44, 40, 36), Color3.fromRGB(246, 236, 210))
	KitPlace.signBoard(nb, "WhatsNewSign", CFrame.new(N.X, bottom + N.H + 1.9, N.Z - 0.1), N.W * 0.7, 2.4, WhatsNew.Title, "Landmark", { Face = C.Orange, Frame = C.WoodDark, Trim = C.Gold, Outline = true })
end


-- PET TOWER entrance at the west end of the cross path (the tower thread hooks `TowerPortal`; nothing here does it):
-- two mossy stone pillars, a beam with the PET TOWER sign facing the park, a glowing purple doorway Part
-- `TowerPortal` (attribute TowerPortal = true, CanTouch, no collision) and a solid back.
local function buildTower(root: Instance)
	local T = ParkConfig.Tower
	local f = model(root, MapNames.TowerEntrance)
	local x, z = T.X, T.Z
	pave(f, "RouteTower", -88 - x, ParkConfig.Path.Width, CFrame.new((x - 88) / 2, Y0, z), C.Stone, M.Cobblestone)
	pave(f, "RouteTowerApron", 8, 18, CFrame.new(x + 1, Y0, z), C.StoneWarm, M.Cobblestone, 0.01)
	local H, W = 15, 12
	-- the owner's Meshy temple (front -Z turned to face +X, toward the path from the plaza); it stands behind the portal
	-- and is solid (precise mesh collision, so its steps are walkable); the plain Part door is hidden and moved onto the
	-- foot of the steps
	local gate = meshAt(f, "MeshyTowerGate", "TowerGate", Vector3.new(x - 9, Y0, z), Vector3.new(24, 34, 24), math.rad(-90))
	if gate then
		-- glowing aura: flame curtains that hug the temple and flow upward (TowerAuraFx; Beams with a scrolling texture,
		-- so it animates on every client with no script). It raycasts the temple, so it is built once the temple is in
		-- the workspace.
		task.spawn(function()
			for _ = 1, 50 do
				if gate:IsDescendantOf(workspace) then
					break
				end
				task.wait(0.1)
			end
			if gate.Parent then
				require(script.Parent.TowerAuraFx).build(gate, Y0).Parent = gate
			end
		end)
	end
	for _, sz in (if gate then {} else { -1, 1 }) :: { number } do
		part(f, "TowerPillar", Vector3.new(3.4, H, 3.4), CFrame.new(x, H / 2, z + sz * (W / 2 + 1.7)), C.Stone, M.Slate)
		deco(part(f, "Moss", Vector3.new(3.7, 1.6, 3.7), CFrame.new(x, H - 0.6, z + sz * (W / 2 + 1.7)), C.Moss, M.Grass))
		lantern(f, Vector3.new(x, H, z + sz * (W / 2 + 1.7)), 1.8, sz > 0)
	end
	if not gate then deco(part(f, "TowerBeam", Vector3.new(3.8, 2, W + 7.4), CFrame.new(x, H - 1.6, z), C.StoneDark, M.Slate)) end
	local signX, signY, signZ, signW, signH = x + 2.1, H - 1.6, z, 11, 2.4
	if gate then
		signX, signY, signZ, signW, signH = x - 6.6, 18.9, z + 0.9, 5.6, 1.5 -- on the temple's blank wooden plaque above its door
	end
	KitPlace.signBoard(f, "TowerSign", CFrame.lookAt(Vector3.new(signX, signY, signZ), Vector3.new(signX - 1, signY, signZ)), signW, signH, "TRAINING TOWER", "Landmark", { Face = Color3.fromRGB(70, 40, 110), Frame = C.WoodDark, Trim = C.Gold, Outline = true })
	local door = Instance.new("Part")
	door.Name = MapNames.TowerPortal
	door:SetAttribute("TowerPortal", true)
	door:SetAttribute("CameraIgnore", true)
	door.Size = Vector3.new(0.6, H - 3.6, W)
	door.CFrame = CFrame.new(x, (H - 3.6) / 2, z)
	door.Color = Color3.fromRGB(178, 110, 255)
	door.Material = M.Neon
	door.Transparency = 0.35
	door.Anchored = true
	door.CanCollide = false
	door.CanTouch = true
	door.CanQuery = false
	door.CastShadow = false
	door.Parent = f
	Kit.light(door, "PointLight", Color3.fromRGB(190, 130, 255), 1.4, 18)
	if gate then
		door.Transparency = 1
		door.CFrame = CFrame.new(x + 3.5, (H - 3.6) / 2, z)
		local glow = door:FindFirstChildWhichIsA("PointLight")
		if glow then -- a soft glow only: the full light tinted the temple's stone purple
			glow.Brightness = 0.5
			glow.Range = 9
		end
	end
	if not gate then
		KitPlace.blocker(f, CFrame.new(x - 1.4, H / 2, z), Vector3.new(1, H, W + 2), "TowerBack")
	end
end

-- Public HATCH STAND beside the EGG SHOP: a round two-tier stone stage with a glowing ring, a square gold top Part
-- `HatchStand` (attribute HatchStand = true) carrying the Attachment `HatchPoint` on its top face, and a sign on two
-- posts behind it. Only the hook lives here: the hatch show is played at HatchPoint by the shop side.
local function buildHatchStand(root: Instance)
	local HS = ParkConfig.HatchStand
	local f = model(root, "CT_Park_HatchStand")
	local base = CFrame.new(HS.X, Y0, HS.Z)
	local podium = meshAt(f, "MeshyHatchStand", "StageMesh", base.Position, Vector3.new(HS.D, 2.0, HS.D))
	if podium then
		KitPlace.blocker(f, base * CFrame.new(0, 1.0, 0), Vector3.new(HS.D * 0.7, 2.0, HS.D * 0.7), "StageBlock")
	else
	upCyl(f, "StageBase", HS.D, 0.8, base * CFrame.new(0, 0.4, 0), C.Stone, M.Slate)
	upCyl(f, "StageTier", HS.D - 2.6, 1.2, base * CFrame.new(0, 0.8 + 0.6, 0), C.StoneDark, M.Slate)
	end
	deco(upCyl(f, "StageRing", HS.D - 2.2, 0.2, base * CFrame.new(0, 1.7, 0), C.Orange, M.Neon)).CastShadow = false
	local top = Instance.new("Part")
	top.Name = MapNames.HatchStand
	top:SetAttribute("HatchStand", true)
	top.Size = Vector3.new(5, 0.6, 5)
	top.CFrame = base * CFrame.new(0, 2.0 + 0.3, 0)
	top.Color = C.Gold
	top.Material = M.SmoothPlastic
	top.Anchored = true
	top.CanCollide = true
	top.Parent = f
	local at = Instance.new("Attachment")
	at.Name = MapNames.HatchPoint
	at.Position = Vector3.new(0, 0.3, 0) -- the top face
	at.Parent = top
	local sz = HS.Z - HS.D / 2 - 0.8
	for _, sx in { -1, 1 } do
		part(f, "SignPost", Vector3.new(1, 9, 1), CFrame.new(HS.X + sx * 5.2, 4.5, sz), C.WoodDark, M.Wood)
		lantern(f, Vector3.new(HS.X + sx * 5.2, 9, sz), 1.4, sx > 0)
	end
	KitPlace.signBoard(f, "HatchSign", CFrame.new(HS.X, 7.6, sz + 0.2), 9, 2.0, "HATCH STAND", "Landmark", { Face = C.TealDeep, Frame = C.WoodDark, Trim = C.Gold, Outline = true })
	quiet(f)
end

-- Build ----------------------------------------------------------------------------------------------------------

-- Stall frames (kit front -Z toward where people stand) and the board frames.
function ParkBuilder.stallFrames(): { [string]: any }
	local Pz, Sh, L, TB = ParkConfig.Plaza, ParkConfig.Shop, ParkConfig.Leaderboard, ParkConfig.TowerBoard
	return {
		Upgrades = KitPlace.facing(Vector3.new(Pz.MinX + 8, 0, 112), Vector3.xAxis),
		PetBook = KitPlace.facing(Vector3.new(Pz.MaxX - 8, 0, 112), -Vector3.xAxis),
		Seller = KitPlace.facing(Vector3.new(-26, 0, Pz.MaxZ - 3), -Vector3.zAxis),
		EggShop = KitPlace.facing(Vector3.new(Sh.X, 0, Sh.Z), Vector3.zAxis),
		-- owner: only two lobby boards, side by side facing the nests
		Boards = {
			{ "Biggest", "RAREST PET", KitPlace.facing(Vector3.new(L.X, 0, L.Z), -Vector3.xAxis) } :: { any },
			{ "Tower", "HIGHEST FLOOR", KitPlace.facing(Vector3.new(TB.X, 0, TB.Z), -Vector3.xAxis) } :: { any },
		},
	}
end

function ParkBuilder.build(root: Instance): { Plots: { Plot } }
	local rng = Random.new(2027)
	buildValley(root, rng)
	buildPaths(root)
	buildClearing(root, rng)
	buildPlaza(root, rng)
	buildTower(root)
	buildHatchStand(root)
	local gallery = folder(root, "CT_Rocks_Gallery")
	local plots: { Plot } = {}
	for i = 1, ParkConfig.Plot.Count do
		table.insert(plots, buildPlot(gallery, i))
	end
	return { Plots = plots }
end

return ParkBuilder
