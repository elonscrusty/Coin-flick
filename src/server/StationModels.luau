--!strict
-- HATCH NESTS (was the crushing tables, V3 loop): four identical pastel nest stations: a round straw nest with a soft
-- cushion plate on a wooden stump table. (Original note: four identical steel work stations on a circle around the shared pile,
-- one per player slot. Procedural stand-ins in the chunky industrial style (REPLACE markers: swap
-- these builders for uploaded meshes named CT_Rocks_Station_<n> once art exists).
--
-- Table frame (local, y = 0 is the floor, the centre of the table is the origin):
--   -Z faces the pile: the player works on that side, +Z is the back (shield, sign, machine feed).
--   +X is the player's LEFT (input tray, basket dock), -X the player's RIGHT (output tray).
--   Size about 7 (X) x 4 (Z) x 3 (Y) studs, work surface top at y = 3.
--
-- Named parts and attachments the client uses (all anchored, none collide except frame + surface):
--   Plate            part    anvil / crushing plate; Attachment "Plate" on its top centre (y = 3.35; kit table 2.86)
--   InputTray        part    shallow tray; Attachments "Slot1".."Slot16" (queued rocks, slot 1 is the
--                            next to be crushed; 11..16 sit on top for the bigger nests) and "InputTray" (centre)
--   NestBase, NestStraw parts the nest ring round the plate: colour and material follow the owner's nest level
--                            (ProgressConfig.Nests: Straw, Wood, Stone, Gold; the names stay the same)
--   OutputTray       part    rubble tray; Attachment "OutputTray" (centre)
--   DockPad          part    basket dock shelf; Attachment "Dock" on top
--   Stand            part    invisible marker WORK_SPOT (4.2) studs in front; Attachment "Stand" (where the player
--                            works, camera framing target)
--   Feed             part    invisible marker at the back; Attachment "MachineFeed" (toward the machine bay)
--   Nameplate        part    SurfaceGui TextLabel "Name" (player name)
--   Sign             part    SurfaceGui TextLabel "Title" (station number / state)
--   Light            part    (kit tables only) status light; the Part nests have none (setOwner skips it)
-- Model attributes: StationIndex, Active (bool), OwnerId (number, 0 = nobody), SlotCount (tray slots built),
-- NestLevel (the look shown).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local RoundRocks = require(Shared.RoundRocks)
local KitModels = require(Shared.KitModels)
local KitPlace = require(script.Parent.KitPlace)
local LowPolyStation = require(script.Parent.LowPolyStation)
local ProgressConfig = require(Shared.ProgressConfig)
local WorldKit = require(Shared.WorldKit)
-- smooth Blender nest ring (Shared.EggKit + ReplicatedStorage.EggKitMeshes); nil = the old straw balls
local EggKit: any = nil
do
	local mod = Shared:FindFirstChild("EggKit")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			EggKit = m
		end
	end
end

local P = Config.Palette
local StationModels = {}

-- Where the player works, studs in front of the table centre (the plate is about the same distance). First person
-- (docs/m8/fp): at 3.2 the plate and rock filled a third of the view; from 4.2 the whole plate, both trays and the
-- hammer stroke fit calmly. The kit's own marker (4.95) is not used. Nothing enforces it: the server range is CrushRange.
local WORK_SPOT = 4.2
local STEEL = Color3.fromRGB(250, 240, 222)
local DARK = Color3.fromRGB(236, 196, 200)
local IRON = Color3.fromRGB(196, 146, 98) -- warm wood (the pale lilac read as plastic)
local RUBBER = Color3.fromRGB(150, 110, 84)
local WOOD = Color3.fromRGB(226, 170, 110)
local PLATE = Color3.fromRGB(255, 190, 208)
-- Restrained owner accents (small inset, tray stripe, sign border and name): warm orange, steel blue, sage
-- green, plum. No neon cyan / green / violet. ArenaBuilder uses the same list for the pad number inset.
local COLORS = {
	Color3.fromRGB(255, 160, 96),
	Color3.fromRGB(116, 180, 240),
	Color3.fromRGB(120, 210, 140),
	Color3.fromRGB(200, 150, 230),
}
StationModels.Accents = COLORS

-- Enough tray slots for the biggest nest upgrade (ProgressConfig.MaxQueue).
StationModels.SlotCount = math.max(Config.Station.QueueCapacity, ProgressConfig.MaxQueue)

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, solid: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A bar from point a to point b (frame-local points are transformed by `base`).
local function beam(parent: Instance, name: string, base: CFrame, a: Vector3, b: Vector3, thick: number, color: Color3): Part
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(base:PointToWorldSpace(a), base:PointToWorldSpace(b)) * CFrame.new(0, 0, -len / 2)
	local p = mk(parent, name, Vector3.new(thick, thick, len), cf, color, Enum.Material.SmoothPlastic, false)
	return p
end

local function attach(p: BasePart, name: string, offset: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = offset
	a.Parent = p
	return a
end

-- Lodge kit language (docs/lodge, ArenaKit.L): warm timber, dark iron, sign wood with cream letters, gold trim.
local LODGE_TIMBER = Color3.fromRGB(206, 138, 84)
local LODGE_TIMBER_LIGHT = Color3.fromRGB(234, 172, 112)
local LODGE_TIMBER_DARK = Color3.fromRGB(150, 96, 64)
local LODGE_IRON = Color3.fromRGB(124, 98, 90)
local LODGE_SIGN = Color3.fromRGB(172, 112, 72)
local LODGE_CHARCOAL = Color3.fromRGB(110, 82, 104)
local CREAM = Color3.fromRGB(246, 238, 220)
local IDLE_INK = Color3.fromRGB(236, 228, 214) -- idle plaque text: still 9:1 on the charcoal plate

-- Fitted text on the Front face of `p` (SignLayout via KitPlace.applyFit: explicit TextSize, never TextScaled) with the
-- sign attributes the numeric audit reads. `name` is the TextLabel's name (the client looks up "Name").
local function labelOn(p: BasePart, face: Enum.NormalId, name: string, text: string, color: Color3, bg: Color3?, preset: string?): TextLabel
	local w, h = p.Size.X, p.Size.Y
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = face
	g.LightInfluence = 0
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundColor3 = bg or DARK
	t.BackgroundTransparency = if bg then 0 else 1
	t.TextColor3 = color
	t.Font = Enum.Font.FredokaOne
	t.Parent = g
	local f = KitPlace.applyFit(g, t, text, w, h, preset or "Plaque")
	p:SetAttribute("SignText", f.Text)
	p:SetAttribute("SignPreset", preset or "Plaque")
	p:SetAttribute("SignW", w)
	p:SetAttribute("SignH", h)
	return t
end

-- Re-fits a sign label after its text changed (setOwner): the size is recomputed for the new text.
local function refit(label: TextLabel, text: string)
	local g = label.Parent
	local p = g and g.Parent
	if not (g and g:IsA("SurfaceGui") and p and p:IsA("BasePart")) then
		label.Text = text
		return
	end
	local w, h = p:GetAttribute("SignW"), p:GetAttribute("SignH")
	local preset = p:GetAttribute("SignPreset")
	if type(w) == "number" and type(h) == "number" and type(preset) == "string" then
		local f = KitPlace.applyFit(g, label, text, w, h, preset)
		p:SetAttribute("SignText", f.Text)
	else
		label.Text = text
	end
end

-- The station sign: a framed lodge timber board on two timber posts at the BACK of the table, above the shield,
-- its face toward the work side (-Z) so it reads from the pile and from the work spot. Built as one object
-- (KitPlace.signBoard: face, frame and text together) in a Model named "Sign"; its label is named "Title".
-- Face 3.2 x 0.95 studs, centre 6.0 studs up: clear of the shield (top about 4.6) and of the machine bay behind.
local SIGN_W, SIGN_H, SIGN_Y, SIGN_Z = 3.2, 0.95, 6.0, 2.05
local function stationSign(m: Model, cf: CFrame, index: number, tint: Color3): BasePart
	for _, sx in { -1.55, 1.55 } do
		mk(m, "SignPost", Vector3.new(0.34, SIGN_Y + 0.1, 0.34), cf * CFrame.new(sx, (SIGN_Y + 0.1) / 2, SIGN_Z + 0.3), LODGE_TIMBER, Enum.Material.Wood, false)
	end
	local face, label = KitPlace.signBoard(m, "Sign", cf * CFrame.new(0, SIGN_Y, SIGN_Z) * CFrame.Angles(0, math.pi, 0), SIGN_W, SIGN_H, "NEST " .. index, "Plaque", {
		Face = LODGE_SIGN,
		Frame = LODGE_TIMBER_DARK,
		Ink = CREAM,
		Trim = tint,
		Depth = 0.3,
	})
	label.Name = "Title" -- the board model is "Sign" (setOwner finds the label under it); its face keeps the kit name "Face"
	-- the side rails are exactly as tall as the face, so on a table turned 45 degrees their top faces share a plane
	-- with the face's top (placement audit: z-fighting); 0.04 taller, they tuck into the top and bottom rails instead
	local board = face.Parent
	for _, n in { "RailL", "RailR" } do
		local r = board and board:FindFirstChild(n) :: BasePart?
		if r then
			r.Size += Vector3.new(0, 0.04, 0)
		end
	end
	return face
end

-- The owner's NestTable mesh (Shared.WorldKit, ReplicatedStorage.WorldKit_LowPoly) in place of the code-built table
-- body: legs, pads, rails, braces, work surface, edges, corner marks and the low bolts. Only those go: every named hook
-- part (Plate, InputTray + Slots, OutputTray, DockPad, Nameplate, Sign, Stand, Feed, NestBase/NestStraw, ColorStrip)
-- stays. The solid ones (Leg, Surface: the colliders, Surface is also the PrimaryPart the client frames on) turn
-- invisible and keep their collision; the rest are removed. The mesh is stretched to the old body box, 7 x 3 x 4
-- studs (its top = the work surface at y = 3, where the plate and trays sit), front (-Z) toward the pile like the table.
local TABLE_BODY = {
	Leg = true, RubberPad = true, RailX = true, RailLow = true, RailZ = true, Brace = true, Surface = true,
	SurfaceEdgeFront = true, SurfaceEdgeBack = true, CornerMark = true,
}
local TABLE_BOX = Vector3.new(7, 3, 4)
local function nestTable(m: Model, cf: CFrame)
	local mesh = if WorldKit.has("NestTable") then WorldKit.clone("NestTable", "NestTable") else nil
	if not mesh then
		return
	end
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") then
			local y = cf:PointToObjectSpace(d.Position).Y
			if TABLE_BODY[d.Name] or (d.Name == "Bolt" and y < 3.1) then
				if d.CanCollide or d == m.PrimaryPart then
					d.Transparency = 1
					d.CastShadow = false
				else
					d:Destroy()
				end
			end
		end
	end
	mesh.Size = TABLE_BOX
	WorldKit.onFloor(mesh, cf)
	mesh.CastShadow = true
	mesh.Parent = m
	m:SetAttribute("NestTableMesh", true)
end

-- Builds one table from the Part stand-ins. `cf` = floor-level frame at the table centre, -Z toward the pile.
local function buildParts(index: number, cf: CFrame, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Station_" .. index
	m:SetAttribute("StationIndex", index)
	m:SetAttribute("Active", false)
	m:SetAttribute("OwnerId", 0)
	m.Parent = parent
	local function L(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local tint = COLORS[index] or P.Orange

	-- legs, rubber pads, rails, diagonal braces
	for _, sx in { -3.1, 3.1 } do
		for _, sz in { -1.6, 1.6 } do
			mk(m, "Leg", Vector3.new(0.7, 2.5, 0.7), L(sx, 1.4, sz), LODGE_TIMBER, Enum.Material.Wood, true)
			mk(m, "RubberPad", Vector3.new(0.9, 0.15, 0.9), L(sx, 0.075, sz), RUBBER, Enum.Material.Rubber, false)
			mk(m, "Bolt", Vector3.new(0.18, 0.1, 0.18), L(sx, 0.2, sz), P.Yellow, Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
		end
	end
	for _, sz in { -1.6, 1.6 } do
		mk(m, "RailX", Vector3.new(6.2, 0.35, 0.35), L(0, 2.3, sz), LODGE_TIMBER_LIGHT, Enum.Material.Wood, false)
		mk(m, "RailLow", Vector3.new(6.2, 0.3, 0.3), L(0, 0.7, sz), IRON, Enum.Material.SmoothPlastic, false)
	end
	for _, sx in { -3.1, 3.1 } do
		-- 0.03 lower than RailX: the rails cross at the corners and equal tops z-fought (placement audit)
		mk(m, "RailZ", Vector3.new(0.35, 0.35, 3.2), L(sx, 2.27, 0), IRON, Enum.Material.SmoothPlastic, false)
		-- diagonal braces on both end frames
		beam(m, "Brace", cf, Vector3.new(sx, 0.7, -1.6), Vector3.new(sx, 2.3, 1.6), 0.22, DARK)
		beam(m, "Brace", cf, Vector3.new(sx, 0.7, 1.6), Vector3.new(sx, 2.3, -1.6), 0.22, DARK)
	end
	for _, sz in { -1.6, 1.6 } do
		beam(m, "Brace", cf, Vector3.new(-3.1, 0.7, sz), Vector3.new(3.1, 2.3, sz), 0.2, DARK)
	end

	-- thick worn work surface
	local top = mk(m, "Surface", Vector3.new(7, 0.5, 4), L(0, 2.75, 0), WOOD, Enum.Material.WoodPlanks, true)
	mk(m, "SurfaceEdgeFront", Vector3.new(7.1, 0.12, 0.2), L(0, 3.02, -1.95), DARK, Enum.Material.SmoothPlastic, false)
	mk(m, "SurfaceEdgeBack", Vector3.new(7.1, 0.12, 0.2), L(0, 3.02, 1.95), DARK, Enum.Material.SmoothPlastic, false)
	-- yellow corner marks (two bars per corner)
	for _, sx in { -3.3, 3.3 } do
		for _, sz in { -1.75, 1.75 } do
			mk(m, "CornerMark", Vector3.new(0.9, 0.05, 0.18), L(sx, 3.02, sz), P.Yellow, Enum.Material.SmoothPlastic, false)
			mk(m, "CornerMark", Vector3.new(0.18, 0.05, 0.9), L(sx, 3.02, sz), P.Yellow, Enum.Material.SmoothPlastic, false)
			mk(m, "Bolt", Vector3.new(0.2, 0.08, 0.2), L(sx - math.sign(sx) * 0.3, 3.03, sz - math.sign(sz) * 0.3), STEEL, Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
		end
	end

	-- anvil / crushing plate at the centre
	local plate = mk(m, "Plate", Vector3.new(1.9, 0.35, 1.9), L(0, 3.175, 0), PLATE, Enum.Material.Fabric, true)
	attach(plate, "Plate", Vector3.new(0, 0.175, 0))
	-- straw nest ring round the cushion plate (visual only). The owner's low-poly nest (LowPolyStation) when imported:
	-- same names, so setNestLevel still dresses it
	local lpBase, lpStraw = LowPolyStation.nestPieces()
	if lpBase and lpStraw then
		lpBase.Name = "NestBase"
		lpBase.CFrame = L(0, 3.03 + lpBase.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
		lpBase.Parent = m
		lpStraw.Name = "NestStraw"
		lpStraw.CFrame = L(0, 3.03 + lpStraw.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
		lpStraw.CastShadow = true
		lpStraw.Parent = m
	else
		mk(m, "NestBase", Vector3.new(0.12, 2.9, 2.9), L(0, 3.03, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 208, 124), Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
	end
	local ring = (lpStraw == nil) and EggKit and EggKit.has("Nest_Ring") and EggKit.size("Nest_Ring")
	if ring then
		-- one woven straw ring mesh round the cushion plate (same name, so setNestLevel still dresses it)
		local k = 3.2 / ring.X
		local piece = EggKit.place(m, "Nest_Ring", "NestStraw", L(0, 3.0, 0), Vector3.new(k, k * 0.9, k), Color3.fromRGB(240, 204, 120), Enum.Material.SmoothPlastic)
		if piece then
			piece.CastShadow = true
		end
	end
	for k = 1, (if ring or lpStraw then 0 else 16) do
		local a = k / 16 * math.pi * 2
		local r = 1.28 + (k % 2) * 0.1
		local piece = mk(m, "NestStraw", Vector3.new(0.75, 0.5, 0.5), L(math.cos(a) * r, 3.22 + (k % 3) * 0.04, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2 + (k % 3) * 0.25, 0), Color3.fromRGB(246, 214, 128):Lerp(Color3.fromRGB(214, 170, 90), (k % 4) / 4), Enum.Material.SmoothPlastic, false, Enum.PartType.Ball)
		piece.Size = Vector3.new(0.9, 0.5, 0.55)
	end
	for _, sx in { -1, 1 } do
		mk(m, "PlateRim", Vector3.new(0.14, 0.18, 2.1), L(sx * 1.0, 3.44, 0), Color3.fromRGB(255, 222, 232), Enum.Material.SmoothPlastic, false)
		mk(m, "PlateRim", Vector3.new(2.1, 0.18, 0.14), L(0, 3.44, sx * 1.0), Color3.fromRGB(255, 222, 232), Enum.Material.SmoothPlastic, false)
		for _, sz in { -1, 1 } do
			mk(m, "Bolt", Vector3.new(0.2, 0.1, 0.2), L(sx * 0.78, 3.37, sz * 0.78), STEEL, Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
		end
	end

	-- input tray (player's left, +X): ten slots in two rows, slot 1 nearest the plate
	local input = mk(m, "InputTray", Vector3.new(1.9, 0.18, 3.2), L(2.4, 3.09, 0), DARK, Enum.Material.SmoothPlastic, false)
	for _, sx in { -1, 1 } do
		mk(m, "TrayWall", Vector3.new(0.12, 0.34, 3.3), L(2.4 + sx * 0.97, 3.26, 0), IRON, Enum.Material.SmoothPlastic, false)
	end
	for _, sz in { -1, 1 } do
		mk(m, "TrayWall", Vector3.new(2.0, 0.34, 0.12), L(2.4, 3.26, sz * 1.62), IRON, Enum.Material.SmoothPlastic, false)
	end
	attach(input, "InputTray", Vector3.new(0, 0.09, 0))
	for i = 1, StationModels.SlotCount do
		if i <= 10 then
			local row = (i - 1) % 2 -- 0 = row near the plate, 1 = outer row
			local col = (i - 1) // 2 -- 0..4 along Z, front to back
			local z = -1.2 + col * 0.6
			local x = if row == 0 then -0.42 else 0.42
			attach(input, "Slot" .. i, Vector3.new(x, 0.09 + 0.3, z))
		else
			-- bigger nests: a second layer resting between the two rows
			local z = -1.5 + (i - 11) * 0.6
			attach(input, "Slot" .. i, Vector3.new(0, 0.09 + 0.3 + 0.3, z))
		end
	end
	m:SetAttribute("SlotCount", StationModels.SlotCount)
	-- output tray (player's right, -X)
	local output = mk(m, "OutputTray", Vector3.new(1.9, 0.18, 3.2), L(-2.4, 3.09, 0), DARK, Enum.Material.SmoothPlastic, false)
	for _, sx in { -1, 1 } do
		mk(m, "TrayWall", Vector3.new(0.12, 0.3, 3.3), L(-2.4 + sx * 0.97, 3.24, 0), IRON, Enum.Material.SmoothPlastic, false)
	end
	for _, sz in { -1, 1 } do
		mk(m, "TrayWall", Vector3.new(2.0, 0.3, 0.12), L(-2.4, 3.24, sz * 1.62), IRON, Enum.Material.SmoothPlastic, false)
	end
	attach(output, "OutputTray", Vector3.new(0, 0.2, 0))

	-- basket dock: a bracketed shelf on the left end (the player's basket hangs here while they work)
	local dock = mk(m, "DockPad", Vector3.new(1.7, 0.25, 1.5), L(4.35, 1.5, -0.6), IRON, Enum.Material.SmoothPlastic, false)
	attach(dock, "Dock", Vector3.new(0, 0.125, 0))
	mk(m, "DockRim", Vector3.new(1.8, 0.06, 0.12), L(4.35, 1.65, -1.38), P.Yellow, Enum.Material.SmoothPlastic, false)
	beam(m, "DockBrace", cf, Vector3.new(3.4, 2.1, -0.6), Vector3.new(4.2, 1.4, -0.6), 0.2, DARK)
	mk(m, "DockPost", Vector3.new(0.2, 1.4, 0.2), L(5.1, 0.8, -1.2), DARK, Enum.Material.SmoothPlastic, false)

	-- tool rail at the back of the plate + tool hooks. (No glass pane any more: its Glass glare sat right behind the egg
	-- in the work view and in front of the NEST sign from the pile, owner video.)
	mk(m, "ShieldFrame", Vector3.new(3.6, 0.15, 0.2), L(0, 4.6, 1.7), DARK, Enum.Material.SmoothPlastic, false)
	for _, sx in { -1.8, 1.8 } do
		mk(m, "ShieldPost", Vector3.new(0.18, 1.7, 0.18), L(sx, 3.8, 1.7), DARK, Enum.Material.SmoothPlastic, false)
	end
	for _, sx in { -1.2, 1.2 } do
		mk(m, "ToolHook", Vector3.new(0.12, 0.12, 0.5), L(sx, 4.2, 1.45), STEEL, Enum.Material.SmoothPlastic, false)
		mk(m, "ToolHookTip", Vector3.new(0.12, 0.3, 0.12), L(sx, 4.05, 1.22), STEEL, Enum.Material.SmoothPlastic, false)
	end

	-- player colour strip + nameplate on the front edge
	mk(m, "ColorStrip", Vector3.new(7, 0.22, 0.12), L(0, 2.55, -2.04), tint, Enum.Material.SmoothPlastic, false)
	local name = mk(m, "Nameplate", Vector3.new(4.2, 0.7, 0.1), L(0, 2.3, -2.08), LODGE_CHARCOAL, Enum.Material.SmoothPlastic, false)
	labelOn(name, Enum.NormalId.Front, "Name", "NEST " .. index, IDLE_INK, LODGE_CHARCOAL, "Nameplate")

	-- readable sign on two posts at the back. No status lamp: the old one was a ball hanging in the air over the board
	-- (owner video: a green ball floating above the nest); the nameplate already shows who uses the nest.
	stationSign(m, cf, index, tint)

	-- invisible markers for the client (where to stand, where a machine feeds)
	local stand = mk(m, "Stand", Vector3.new(1, 0.2, 1), L(0, 0.1, -WORK_SPOT), P.Yellow, Enum.Material.SmoothPlastic, false)
	stand.Transparency = 1
	attach(stand, "Stand", Vector3.new(0, 0.1, 0))
	local feed = mk(m, "Feed", Vector3.new(1, 1, 1), L(0, 2.6, 2.4), P.Yellow, Enum.Material.SmoothPlastic, false)
	feed.Transparency = 1
	attach(feed, "MachineFeed", Vector3.zero)

	-- floor mark where the player works (yellow outline)
	for _, o in { Vector3.new(-1.6, 0, -3.2), Vector3.new(1.6, 0, -3.2) } do
		mk(m, "StandMark", Vector3.new(0.15, 0.04, 2.2), L(o.X, 0.03, o.Z), P.Yellow, Enum.Material.SmoothPlastic, false)
	end

	m.PrimaryPart = top
	nestTable(m, cf)
	return m
end

-- Kit version -------------------------------------------------------------------------------------
-- The same table assembled from the Blender kit meshes (docs/MODELING.md, Station_Assembled preview):
-- Station_Table with the anvil plate, input tray, rubble bin, shield and beacon at its attach points
-- and the sign beside it. The floor pad is a plain concrete slab built by ArenaBuilder (the kit's
-- hazard-striped Station_FloorPad is no longer used: owner colour and stripes competed with the work). The meshes are visual only; every part and
-- attachment the client and server use is rebuilt here as an invisible helper with the same name and
-- the same frame as in the Part version (Surface = PrimaryPart at y 2.75, Plate, InputTray with
-- Slot1..10, OutputTray, DockPad, Stand, Feed) plus the text carriers Nameplate and Sign and the
-- status Light (the beacon lens). Pieces of the Accent slot take the station colour.
-- (the kit Station_Sign is no longer placed: its 1.3 x 1.0 face was too small for readable text and its rock icon
-- stood in front of the text plate; the lodge timber board from stationSign replaces it)
local KIT_NEEDED = { "Station_Table", "Station_AnvilPlate", "Station_InputTray", "Station_RubbleBin", "Station_Shield", "Station_Beacon" }

function StationModels.kitAvailable(): boolean
	if true then
		return false -- the quarry-style kit table is not used for the hatch nests (REPLACE: real nest mesh)
	end
	for _, n in KIT_NEEDED do
		if not KitModels.template(n) then
			return false
		end
	end
	return true
end

-- Copies the MeshParts of a kit template into `m` at frame `at` (a kit model origin, scaled by `scale`).
-- Names get `prefix`; Accent pieces take `tint` and are tagged for the client; returns name -> part.
-- Palette pass (docs/BRIEF_V9_MASTER7_CORRECTIONS.md section 3): the kit meshes carry navy-black Slate / FrameDark
-- and cold blue-grey Frame colours that read black in the work view. Table, tray and bin frames become warm
-- wood, the rest warm charcoal; the Amber and Accent pieces are not touched.
local WOODEN_KITS = { Station_Table = true, Station_InputTray = true, Station_RubbleBin = true }
-- Lodge kit language (docs/lodge): the table, tray and bin bodies are lodge timber with darker timber grooves; every
-- frame, post, strap and rim is dark iron (so the table has a clean dark outline against the pale pad and the warm
-- floor, like the owner's quarry target); bolts a lighter iron. Plate steel, glass, lamp and accent are not touched.
local function warm(p: MeshPart, kitName: string)
	local n = string.match(p.Name, "_(.+)$") or p.Name
	local slot = string.match(n, "^([%a]+)") or n
	if slot == "Wood" then
		p.Color = if WOODEN_KITS[kitName] then LODGE_TIMBER else LODGE_TIMBER_LIGHT
		p.Material = Enum.Material.Wood
	elseif slot == "WoodDark" then
		p.Color = LODGE_TIMBER_DARK
		p.Material = Enum.Material.Wood
	elseif slot == "Frame" then
		p.Color = LODGE_IRON
		p.Material = Enum.Material.Metal
	elseif slot == "FrameDark" then
		p.Color = Color3.fromRGB(42, 44, 47)
	elseif slot == "Slate" then
		p.Color = Color3.fromRGB(70, 72, 76)
	elseif slot == "SteelLight" then
		p.Color = Color3.fromRGB(150, 148, 142)
	end
end

local function addKit(m: Model, kitName: string, prefix: string, at: CFrame, scale: number, tint: Color3, solidPiece: string?): { [string]: BasePart }
	local out: { [string]: BasePart } = {}
	local t = KitModels.template(kitName)
	if not t then
		return out
	end
	for _, src in t:GetChildren() do
		if src:IsA("MeshPart") then
			local p = src:Clone()
			for _, ch in p:GetChildren() do
				ch:Destroy()
			end
			p.Name = prefix .. "_" .. src.Name
			p.Size = src.Size * scale
			p.CFrame = at * CFrame.new(src.Position * scale) * src.CFrame.Rotation
			p.Anchored = true
			p.CanCollide = solidPiece == src.Name
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = src.Transparency < 0.5
			warm(p, kitName)
			if string.sub(src.Name, 1, 6) == "Accent" then
				p.Color = tint
				p:SetAttribute("AccentSlot", true)
			end
			p.Parent = m
			out[src.Name] = p
		end
	end
	return out
end

local function helper(parent: Instance, name: string, size: Vector3, cf: CFrame, solid: boolean): Part
	local p = mk(parent, name, size, cf, DARK, Enum.Material.SmoothPlastic, solid)
	p.Transparency = 1
	return p
end

local function buildKit(index: number, cf: CFrame, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Station_" .. index
	m:SetAttribute("StationIndex", index)
	m:SetAttribute("Active", false)
	m:SetAttribute("OwnerId", 0)
	m:SetAttribute("Kit", true)
	m.Parent = parent
	local function L(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local tint = COLORS[index] or P.Orange
	local tableT = KitModels.template("Station_Table") :: Model
	local function pt(name: string): Vector3
		return KitModels.attach(tableT, name) or Vector3.zero
	end

	-- the floor pad, the table and the kit pieces on it
	addKit(m, "Station_Table", "Table", cf, 1, tint)
	local plateAt, trayAt, binAt = pt("Plate"), pt("InputTray"), pt("RubbleBin")
	-- First person (Master 7) was checked at the work spot: the eye is about 5 studs up and 3.2 back, so the rock on
	-- the plate (top about 4.4) is 10-20 degrees below a level gaze, inside the view and above the bottom HUD; a
	-- raised plate put the rock top at eye height and hid the hammer contact, so the height stays as it was.
	local plateKit = addKit(m, "Station_AnvilPlate", "Plate", cf * CFrame.new(plateAt), 1, tint)
	if plateKit.Amber then
		-- the hazard border is the table's one amber accent: kept, but muted so it does not shout over the rock
		plateKit.Amber.Color = Color3.fromRGB(176, 142, 86)
	end
	addKit(m, "Station_InputTray", "Tray", cf * CFrame.new(trayAt), 1, tint)
	local bin = addKit(m, "Station_RubbleBin", "Bin", cf * CFrame.new(binAt), 1, tint)
	if bin.Fill then
		bin.Fill:Destroy() -- the bin starts empty; the client drops rubble into it as rocks are crushed
	end
	addKit(m, "Station_Shield", "Shield", cf * CFrame.new(pt("Shield")), 1, tint)
	local beacon = addKit(m, "Station_Beacon", "Beacon", cf * CFrame.new(pt("Beacon")), 1, tint)

	-- invisible: the work surface (PrimaryPart, frame origin = 2.75 below its centre, the clients rely on it) and
	-- one solid body block under the kit table (top 2.5; replaces the four corner legs of the old table)
	local top = helper(m, "Surface", Vector3.new(7, 0.5, 4), L(0, 2.75, 0), false)
	helper(m, "TableBody", Vector3.new(7.2, 2.5, 3.5), L(0, 1.25, 0), true)

	-- anvil plate: the rock rests on the top (the AnvilPlate mesh is 0.36 high)
	local plate = helper(m, "Plate", Vector3.new(2.7, 0.36, 2.1), cf * CFrame.new(plateAt + Vector3.new(0, 0.18, 0)), true)
	attach(plate, "Plate", Vector3.new(0, 0.18, 0))

	-- input tray: ten slots in two rows of five, slot 1 nearest the plate (the tray is at +X)
	local trayFloor = 0.16 -- the kit tray's Slots attach height
	local input = helper(m, "InputTray", Vector3.new(2.2, 0.16, 1.75), cf * CFrame.new(trayAt + Vector3.new(0, 0.08, 0)), false)
	attach(input, "InputTray", Vector3.new(0, trayFloor - 0.08, 0))
	for i = 1, StationModels.SlotCount do
		if i <= 10 then
			local row = (i - 1) % 2
			local col = (i - 1) // 2
			local x = -0.84 + col * 0.42
			local z = if row == 0 then 0.3 else -0.3
			attach(input, "Slot" .. i, Vector3.new(x, trayFloor + 0.37 - 0.08, z)) -- a mini rock centre sits 0.12 above this
		else
			attach(input, "Slot" .. i, Vector3.new(-0.84 + (i - 11) * 0.336, trayFloor + 0.37 - 0.08 + 0.25, 0))
		end
	end
	m:SetAttribute("SlotCount", StationModels.SlotCount)

	-- rubble bin (the player's right, -X); the client spreads rubble over SpreadX x SpreadZ around it
	local output = helper(m, "OutputTray", Vector3.new(1.9, 0.1, 1.5), cf * CFrame.new(binAt), false)
	output:SetAttribute("SpreadX", 0.62)
	output:SetAttribute("SpreadZ", 0.45)
	attach(output, "OutputTray", Vector3.new(0, 0.3, 0))

	local dock = helper(m, "DockPad", Vector3.new(1.4, 0.2, 1.4), cf * CFrame.new(pt("Dock")), false)
	attach(dock, "Dock", Vector3.zero)
	local stand = helper(m, "Stand", Vector3.new(1, 0.2, 1), cf * CFrame.new(Vector3.new(0, 0.1, -WORK_SPOT)), false)
	attach(stand, "Stand", Vector3.new(0, 0.1, 0))
	local feed = helper(m, "Feed", Vector3.new(1, 1, 1), cf * CFrame.new(pt("MachineFeed")), false)
	attach(feed, "MachineFeed", Vector3.zero)

	-- nameplate over the table's front plaque, 3.4 x 0.74: the kit plaque (1.7 x 0.58) is too small for a name at a
	-- readable size (SignLayout's Nameplate minimum is 0.36 studs per em, which needs a 0.62+ stud tall plate and
	-- about 3 studs of width for a 12-letter name). It spans the front between the iron corner posts (inner edges at
	-- x = +-3.0), between the two straps (y 0.82 and 1.63), 0.05 in front of the posts' faces: nothing covers it.
	local np = pt("Nameplate")
	local name = mk(m, "Nameplate", Vector3.new(3.4, 0.74, 0.04), cf * CFrame.new(np.X, np.Y, np.Z - 0.03), LODGE_CHARCOAL, Enum.Material.SmoothPlastic, false)
	labelOn(name, Enum.NormalId.Front, "Name", "NEST " .. index, IDLE_INK, LODGE_CHARCOAL, "Nameplate")

	-- station sign: lodge timber board on posts behind the table (text faces the work side)
	stationSign(m, cf, index, tint)

	-- status light: the beacon lens (neon, blinks in the preview of the kit; here it just changes colour)
	local lens = beacon.Lens
	if lens then
		lens.Name = "Light"
		lens.Material = Enum.Material.Neon
		lens.Color = Color3.fromRGB(92, 98, 106)
		local pl = Instance.new("PointLight")
		pl.Range = 8
		pl.Brightness = 0.5
		pl.Color = lens.Color
		pl.Enabled = false
		pl.Parent = lens
	end

	m.PrimaryPart = top
	return m
end

-- Builds one table: from the kit meshes when they are loaded, else from Parts (identical contract).
function StationModels.build(index: number, cf: CFrame, parent: Instance): Model
	if StationModels.kitAvailable() then
		local ok, m = pcall(buildKit, index, cf, parent)
		if ok then
			return m
		end
		warn("[StationModels] kit table failed, using Parts: " .. tostring(m))
		local half = parent:FindFirstChild("CT_Rocks_Station_" .. index)
		if half then
			half:Destroy()
		end
	end
	return buildParts(index, cf, parent)
end

-- Dresses the nest ring (NestBase + NestStraw parts) in the look of nest level `level` (ProgressConfig.Nests).
-- Looks only; the tray size is enforced by the round core. REPLACE: real nest meshes per level.
function StationModels.setNestLevel(model: Model, level: number?)
	local nest = ProgressConfig.nest(level or 1)
	model:SetAttribute("NestLevel", ProgressConfig.clampLevel(level or 1, #ProgressConfig.Nests))
	local mat = (Enum.Material :: any)[nest.Material] or Enum.Material.SmoothPlastic
	local k = 0
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "NestBase" then
				d.Color = nest.Color
				d.Material = mat
			elseif d.Name == "NestStraw" then
				k += 1
				d.Color = nest.Color:Lerp(nest.Dark, (k % 4) / 4)
				d.Material = mat
				d.Reflectance = if nest.Id == "Gold" then 0.15 else 0
			end
		end
	end
end

-- Marks a table as used by `ownerName`. An unused table stays calm: no cover, no warning text, the same
-- table with a dim lamp, "TABLE n" on its plaque and a quiet grey sign (it can be used next hunt).
function StationModels.setOwner(model: Model, ownerId: number?, ownerName: string?)
	local active = ownerId ~= nil
	model:SetAttribute("Active", active)
	model:SetAttribute("OwnerId", ownerId or 0)
	-- the owner's nest level (EconomyService keeps the NestLevel player attribute); an unused nest is straw
	local owner = if ownerId then game:GetService("Players"):GetPlayerByUserId(ownerId) else nil
	local lvl = if owner then owner:GetAttribute("NestLevel") else nil
	StationModels.setNestLevel(model, if type(lvl) == "number" then lvl else 1)
	local index = (model:GetAttribute("StationIndex") or 1) :: number -- set as a number when the nest is built
	local tint = COLORS[index] or P.Orange
	local plate = model:FindFirstChild("Nameplate")
	local nameLabel = plate and plate:FindFirstChild("Name", true) :: TextLabel?
	if nameLabel then
		refit(nameLabel, if active then (ownerName or "Player") else "NEST " .. index)
		-- owner accent on the charcoal plate (all four accents are at least 5:1 there); idle text a calm light grey
		nameLabel.TextColor3 = if active then tint else IDLE_INK
	end
	local sign = model:FindFirstChild("Sign", true)
	local title = sign and sign:FindFirstChild("Title", true) :: TextLabel?
	if title then
		-- the sign always names the table; cream on sign wood reads in both states (the lamp shows "in use")
		refit(title, "NEST " .. index)
		title.TextColor3 = CREAM
	end
	local light = model:FindFirstChild("Light") :: Part?
	if light then
		-- a small, calm "in use" lamp (Master 7: fewer bright lamps): muted green, a faint short-range glow
		local c = if active then Color3.fromRGB(118, 168, 108) else Color3.fromRGB(92, 98, 106)
		light.Color = c
		light.Material = if active then Enum.Material.SmoothPlastic else light.Material
		local pl = light:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Color = c
			pl.Brightness = 0.25
			pl.Range = 5
			pl.Enabled = active
		end
	end
end

-- Table frames for one arena: centre `c`, one per station index, facing the pile.
-- `floorY` lifts the tables onto the top of their concrete pads (ArenaBuilder passes the pad height), so the
-- feet stand on the slab instead of 0.3 studs inside it (placement audit).
function StationModels.buildAll(c: Vector3, parent: Instance, floorY: number?): { Model }
	local out = {}
	local lift = floorY or 0
	for i = 1, Config.Station.Count do
		local rel = RoundRocks.stationPosition(i)
		local pos = Vector3.new(c.X + rel.X, c.Y + lift, c.Z + rel.Z)
		local cf = CFrame.lookAt(pos, Vector3.new(c.X, c.Y + lift, c.Z))
		local m = StationModels.build(i, cf, parent)
		StationModels.setOwner(m, nil, nil)
		table.insert(out, m)
	end
	return out
end

return StationModels
