--!strict
-- Small reusable kit helpers for the lobby (LobbyBuilder) and anything else built from Parts:
-- part/model helpers, V4 palette, a blocky pixel font that makes sign titles out of real geometry
-- (the offline preview does not draw SurfaceGuis, and block letters never wrap), a fitted
-- SurfaceGui text label, and a few props (planter, bench, crate stack, lamp, tree, cliff).
-- Convention: kit frames put +Z toward the viewer (the "front" of a sign or building), -Z is the
-- back wall, +Y up. Pixel text and SurfaceGui labels on the +Z face read left to right.
-- REPLACE markers: these are procedural stand-ins for meshes (docs/ASSET_MANIFEST.md, lobby kit).

local Kit = {}

-- V4 section C palette
Kit.Char = Color3.fromRGB(32, 40, 51) -- #202833 deep charcoal
Kit.Slate = Color3.fromRGB(77, 91, 102) -- #4D5B66
Kit.Conc = Color3.fromRGB(193, 182, 162) -- #C1B6A2 warm concrete
Kit.Wood = Color3.fromRGB(168, 117, 72) -- #A87548
Kit.Amber = Color3.fromRGB(244, 190, 67) -- #F4BE43
Kit.Cream = Color3.fromRGB(244, 239, 229) -- #F4EFE5
Kit.Mint = Color3.fromRGB(114, 204, 160) -- #72CCA0
-- supporting tones derived from the palette
Kit.Pad = Color3.fromRGB(122, 115, 101) -- darker workshop pad
Kit.Paver = Color3.fromRGB(214, 204, 184) -- lighter inset stone
Kit.Wall = Color3.fromRGB(226, 218, 200) -- light wall panel
Kit.Shrub = Color3.fromRGB(96, 142, 96)
Kit.Soil = Color3.fromRGB(86, 70, 56)

local M = Enum.Material

function Kit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Decoration: no collision, never hit by raycasts.
function Kit.deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

function Kit.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Kit.model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A cylinder whose axis points up (Roblox cylinders run along X, so turn it).
function Kit.upCylinder(parent: Instance, name: string, diameter: number, height: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return Kit.part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, mat, Enum.PartType.Cylinder)
end

-- A cylinder whose axis points along the frame's Z (a round disc facing the viewer).
function Kit.discZ(parent: Instance, name: string, diameter: number, thick: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return Kit.part(parent, name, Vector3.new(thick, diameter, diameter), cf * CFrame.Angles(0, math.rad(90), 0), color, mat, Enum.PartType.Cylinder)
end

function Kit.light(parent: Instance, kind: string, color: Color3, brightness: number, range: number, angle: number?): Light
	local l = Instance.new(kind) :: any
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	if angle and kind == "SpotLight" then
		l.Angle = angle
		l.Face = Enum.NormalId.Bottom
	end
	l.Parent = parent
	return l
end

-- One fitted single-line (or explicit multi-line) label on a part face. Text can never wrap
-- mid-line: TextWrapped is off, TextScaled shrinks it to the box, and a size cap keeps short
-- text from growing huge. `lines` splits the box height evenly when text holds "\n".
function Kit.label(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?, font: Enum.Font?, pxPerStud: number?): TextLabel
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pxPerStud or 50
	g.LightInfluence = 0
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or Kit.Char
	t.BackgroundTransparency = if bg then 0 else 1
	t.TextColor3 = color or Kit.Cream
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextWrapped = false
	t.Text = text
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = t
	return t
end

function Kit.prompt(p: BasePart, action: string, object: string, panel: string, dist: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = dist or 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	if panel ~= "" then
		pp:SetAttribute("Panel", panel)
	end
	pp.Parent = p
	return pp
end

-- Pixel font ----------------------------------------------------------------------------------

local FONT: { [string]: { string } } = {
	A = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
	B = { "11110", "10001", "10001", "11110", "10001", "10001", "11110" },
	C = { "01111", "10000", "10000", "10000", "10000", "10000", "01111" },
	D = { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
	E = { "11111", "10000", "10000", "11110", "10000", "10000", "11111" },
	F = { "11111", "10000", "10000", "11110", "10000", "10000", "10000" },
	G = { "01111", "10000", "10000", "10011", "10001", "10001", "01111" },
	H = { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
	I = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
	J = { "00111", "00010", "00010", "00010", "00010", "10010", "01100" },
	K = { "10001", "10010", "10100", "11000", "10100", "10010", "10001" },
	L = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
	M = { "10001", "11011", "10101", "10101", "10001", "10001", "10001" },
	N = { "10001", "11001", "10101", "10011", "10001", "10001", "10001" },
	O = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
	P = { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
	Q = { "01110", "10001", "10001", "10001", "10101", "10010", "01101" },
	R = { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
	S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
	T = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
	U = { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
	V = { "10001", "10001", "10001", "10001", "10001", "01010", "00100" },
	W = { "10001", "10001", "10001", "10101", "10101", "11011", "10001" },
	X = { "10001", "10001", "01010", "00100", "01010", "10001", "10001" },
	Y = { "10001", "10001", "01010", "00100", "00100", "00100", "00100" },
	Z = { "11111", "00001", "00010", "00100", "01000", "10000", "11111" },
}

-- Width in studs of `text` set in the pixel font with the given cell size.
function Kit.pixelWidth(text: string, cell: number): number
	local cols = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		cols += if ch == " " then 4 else 6
	end
	return math.max(0, cols - 1) * cell
end

-- Blocky letters centred on `cf` (text faces +Z of cf, reads along +X, cf.Position is the
-- centre of the text block). One Part per horizontal run, so "START" is about 25 parts.
function Kit.pixelText(parent: Instance, text: string, cf: CFrame, cell: number, color: Color3, depth: number?, mat: Enum.Material?): Model
	local m = Kit.model(parent, "PixelText_" .. string.gsub(text, " ", "_"))
	local w = Kit.pixelWidth(text, cell)
	local d = depth or cell
	local x0 = -w / 2
	local col = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local rows = FONT[ch]
		if rows then
			for r, bits in rows do
				local c = 1
				while c <= 5 do
					if string.sub(bits, c, c) == "1" then
						local e = c
						while e < 5 and string.sub(bits, e + 1, e + 1) == "1" do
							e += 1
						end
						local runW = (e - c + 1) * cell
						local cx = x0 + (col + c - 1) * cell + runW / 2
						local cy = (3.5 - (r - 1) - 0.5) * cell
						local p = Kit.part(m, "L", Vector3.new(runW, cell, d), cf * CFrame.new(cx, cy, d / 2), color, mat)
						p.CanQuery = false
						p.CanTouch = false
						p.CanCollide = false
						c = e + 1
					else
						c += 1
					end
				end
			end
			col += 6
		else
			col += 4
		end
	end
	return m
end

-- Props ---------------------------------------------------------------------------------------

function Kit.crate(parent: Instance, cf: CFrame, s: number, variant: number?): Model
	local m = Kit.model(parent, "CT_Rocks_Crate")
	Kit.part(m, "Box", Vector3.one * s, cf * CFrame.new(0, s / 2, 0), Kit.Wood, M.WoodPlanks)
	if (variant or 1) == 1 then
		Kit.deco(Kit.part(m, "Band", Vector3.new(s * 1.03, s * 0.14, s * 1.03), cf * CFrame.new(0, s * 0.5, 0), Kit.Char, M.Metal))
	else
		Kit.deco(Kit.part(m, "BandA", Vector3.new(s * 0.14, s * 1.03, s * 1.03), cf * CFrame.new(-s * 0.3, s * 0.5, 0), Kit.Slate, M.Metal))
		Kit.deco(Kit.part(m, "BandB", Vector3.new(s * 0.14, s * 1.03, s * 1.03), cf * CFrame.new(s * 0.3, s * 0.5, 0), Kit.Slate, M.Metal))
	end
	return m
end

function Kit.planter(parent: Instance, cf: CFrame, length: number): Model
	local m = Kit.model(parent, "CT_Rocks_Planter")
	Kit.part(m, "Box", Vector3.new(length, 1.5, 1.8), cf * CFrame.new(0, 0.75, 0), Kit.Stone, M.Concrete)
	Kit.deco(Kit.part(m, "Base", Vector3.new(length + 0.2, 0.4, 2.0), cf * CFrame.new(0, 0.2, 0), Kit.Slate, M.Slate))
	Kit.deco(Kit.part(m, "Rim", Vector3.new(length + 0.2, 0.25, 2.0), cf * CFrame.new(0, 1.5, 0), Kit.Conc, M.Concrete))
	Kit.deco(Kit.part(m, "Soil", Vector3.new(length - 0.4, 0.2, 1.4), cf * CFrame.new(0, 1.55, 0), Kit.Soil, M.Ground))
	local n = math.max(2, math.floor(length / 1.6))
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * length / n
		local s = 1.2 + ((i * 7) % 3) * 0.25
		Kit.deco(Kit.part(m, "Shrub", Vector3.one * s, cf * CFrame.new(x, 1.65 + s * 0.4, 0) * CFrame.Angles(0.2 * i, i, 0), Kit.Shrub:Lerp(Kit.Mint, (i % 3) * 0.12), M.Grass, Enum.PartType.Ball))
	end
	return m
end

function Kit.bench(parent: Instance, cf: CFrame): Model
	local m = Kit.model(parent, "CT_Rocks_Bench")
	Kit.part(m, "Seat", Vector3.new(5, 0.4, 1.5), cf * CFrame.new(0, 1.5, 0), Kit.Wood, M.WoodPlanks)
	Kit.deco(Kit.part(m, "Back", Vector3.new(5, 1.2, 0.3), cf * CFrame.new(0, 2.4, -0.7) * CFrame.Angles(math.rad(-8), 0, 0), Kit.Wood, M.WoodPlanks))
	for _, x in { -2.1, 2.1 } do
		Kit.deco(Kit.part(m, "Leg", Vector3.new(0.4, 1.5, 1.3), cf * CFrame.new(x, 0.75, 0), Kit.Char, M.Metal))
	end
	return m
end

function Kit.lampPost(parent: Instance, pos: Vector3, withLight: boolean): Model
	local m = Kit.model(parent, "CT_Rocks_LampPost")
	Kit.part(m, "Foot", Vector3.new(1.4, 0.8, 1.4), CFrame.new(pos + Vector3.new(0, 0.4, 0)), Kit.Slate, M.Concrete)
	Kit.part(m, "Pole", Vector3.new(0.4, 8.4, 0.4), CFrame.new(pos + Vector3.new(0, 4.6, 0)), Kit.Char, M.Metal)
	Kit.part(m, "Arm", Vector3.new(1.6, 0.3, 0.3), CFrame.new(pos + Vector3.new(0.6, 8.7, 0)), Kit.Char, M.Metal)
	local head = Kit.deco(Kit.part(m, "Head", Vector3.new(1.3, 0.7, 1.3), CFrame.new(pos + Vector3.new(1.2, 8.4, 0)), Kit.Amber, M.SmoothPlastic))
	if withLight then
		Kit.light(head, "PointLight", Color3.fromRGB(255, 226, 170), 0.8, 22)
	end
	return m
end

function Kit.tree(parent: Instance, pos: Vector3, rng: Random, scale: number?): Model
	local k = scale or 1
	local m = Kit.model(parent, "CT_Rocks_Tree")
	local h = rng:NextNumber(6, 9) * k
	Kit.part(m, "Trunk", Vector3.new(1.3 * k, h, 1.3 * k), CFrame.new(pos + Vector3.new(0, h / 2, 0)), Kit.Wood:Lerp(Kit.Char, 0.25), M.Wood)
	for i = 1, 3 do
		local s = (rng:NextNumber(5, 7.5) - i * 0.7) * k
		Kit.deco(Kit.part(m, "Leaves", Vector3.one * s, CFrame.new(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), h + i * 1.5 - 1.2, rng:NextNumber(-0.6, 0.6))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0), Color3.fromRGB(86, 140, 84):Lerp(Color3.fromRGB(66, 112, 76), rng:NextNumber(0, 0.7)), M.Grass))
	end
	return m
end

function Kit.boulder(parent: Instance, cf: CFrame, size: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Boulder")
	for i = 1, 3 do
		local s = size * (1 - i * 0.18)
		Kit.part(m, "Chunk", Vector3.new(s, s * 0.75, s * 0.9), cf * CFrame.new(rng:NextNumber(-0.25, 0.25) * size, s * 0.3, rng:NextNumber(-0.25, 0.25) * size) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)), Kit.Slate:Lerp(Kit.Conc, rng:NextNumber(0.1, 0.45)), M.Slate)
	end
	return m
end

-- A cliff band: broad slate faces with warm sandstone layers. `cf` faces +Z toward the play area.
function Kit.cliff(parent: Instance, cf: CFrame, length: number, height: number, rng: Random): Model
	local m = Kit.model(parent, "CT_Rocks_Cliff")
	local x = -length / 2
	while x < length / 2 do
		local w = rng:NextNumber(8, 13)
		local h = height * rng:NextNumber(0.75, 1.1)
		Kit.part(m, "Face", Vector3.new(w, h, rng:NextNumber(8, 12)), cf * CFrame.new(x + w / 2, h / 2 - 1, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.22, 0.22), rng:NextNumber(-0.04, 0.04)), Kit.Slate:Lerp(Kit.Conc, rng:NextNumber(0.15, 0.5)), M.Slate)
		Kit.deco(Kit.part(m, "Layer", Vector3.new(w * 0.98, 1.2, 0.6), cf * CFrame.new(x + w / 2, h * 0.45, 5.6), Color3.fromRGB(196, 170, 130), M.Sandstone))
		x += w * 0.8
	end
	return m
end

-- Stone-and-steel kit (owner reference sheets 01-04) -------------------------------------------

Kit.Stone = Color3.fromRGB(206, 196, 174) -- warm cut stone for pillars, planters, steps

-- Stone pillar with dark steel bands; cf is the centre of the base on the ground.
function Kit.pillar(parent: Instance, cf: CFrame, h: number, w: number): Model
	local m = Kit.model(parent, "CT_Rocks_Pillar")
	Kit.part(m, "Base", Vector3.new(w * 1.25, 0.9, w * 1.25), cf * CFrame.new(0, 0.45, 0), Kit.Slate, M.Slate)
	Kit.part(m, "Shaft", Vector3.new(w, h - 1.8, w), cf * CFrame.new(0, 0.9 + (h - 1.8) / 2, 0), Kit.Stone, M.Concrete)
	Kit.deco(Kit.part(m, "BandLow", Vector3.new(w * 1.12, 0.5, w * 1.12), cf * CFrame.new(0, 1.7, 0), Kit.Char, M.Metal))
	Kit.deco(Kit.part(m, "BandHigh", Vector3.new(w * 1.12, 0.5, w * 1.12), cf * CFrame.new(0, h - 1.5, 0), Kit.Char, M.Metal))
	Kit.part(m, "Cap", Vector3.new(w * 1.3, 0.9, w * 1.3), cf * CFrame.new(0, h - 0.45, 0), Kit.Char, M.Metal)
	for _, sx in { -1, 1 } do
		Kit.deco(Kit.part(m, "Bolt", Vector3.new(0.22, 0.22, 0.12), cf * CFrame.new(sx * w * 0.35, h - 1.5, w * 0.57), Kit.Slate, M.Metal))
	end
	return m
end

-- Glowing lantern box (amber core in a dark frame). cf is the centre.
function Kit.lantern(parent: Instance, cf: CFrame, scale: number?, withLight: boolean?): Model
	local k = scale or 1
	local m = Kit.model(parent, "CT_Rocks_Lantern")
	Kit.deco(Kit.part(m, "Core", Vector3.new(0.7, 1.1, 0.7) * k, cf, Kit.Amber, M.Neon))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.deco(Kit.part(m, "Post", Vector3.new(0.14, 1.3, 0.14) * k, cf * CFrame.new(sx * 0.4 * k, 0, sz * 0.4 * k), Kit.Char, M.Metal))
		end
	end
	Kit.deco(Kit.part(m, "Cap", Vector3.new(1.1, 0.2, 1.1) * k, cf * CFrame.new(0, 0.7 * k, 0), Kit.Char, M.Metal))
	Kit.deco(Kit.part(m, "Foot", Vector3.new(1.0, 0.16, 1.0) * k, cf * CFrame.new(0, -0.68 * k, 0), Kit.Char, M.Metal))
	if withLight then
		local core = m:FindFirstChild("Core") :: BasePart
		Kit.light(core, "PointLight", Color3.fromRGB(255, 214, 150), 0.8, 18)
	end
	return m
end

-- Bracketed wall lantern; cf origin is on the wall surface, +Z is out of the wall.
function Kit.wallLamp(parent: Instance, cf: CFrame, withLight: boolean?): Model
	local m = Kit.model(parent, "CT_Rocks_WallLamp")
	Kit.deco(Kit.part(m, "Plate", Vector3.new(0.9, 1.6, 0.25), cf * CFrame.new(0, 0, 0.12), Kit.Char, M.Metal))
	Kit.deco(Kit.part(m, "Arm", Vector3.new(0.25, 0.25, 1.0), cf * CFrame.new(0, 0.5, 0.7), Kit.Char, M.Metal))
	Kit.lantern(m, cf * CFrame.new(0, -0.1, 1.1), 0.8, withLight)
	return m
end

-- Standing lamp: stone foot, dark frame, glowing core (reference 12). cf is the ground centre.
function Kit.standingLamp(parent: Instance, pos: Vector3, withLight: boolean?): Model
	local m = Kit.model(parent, "CT_Rocks_StandingLamp")
	Kit.part(m, "Foot", Vector3.new(1.7, 1.3, 1.7), CFrame.new(pos + Vector3.new(0, 0.65, 0)), Kit.Stone, M.Concrete)
	Kit.part(m, "FootBand", Vector3.new(1.85, 0.3, 1.85), CFrame.new(pos + Vector3.new(0, 1.45, 0)), Kit.Char, M.Metal)
	local core = Kit.deco(Kit.part(m, "Core", Vector3.new(0.9, 2.8, 0.9), CFrame.new(pos + Vector3.new(0, 3.2, 0)), Kit.Amber, M.Neon))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Kit.part(m, "Post", Vector3.new(0.3, 3.0, 0.3), CFrame.new(pos + Vector3.new(sx * 0.6, 3.2, sz * 0.6)), Kit.Char, M.Metal)
		end
	end
	Kit.part(m, "Cap", Vector3.new(1.9, 0.5, 1.9), CFrame.new(pos + Vector3.new(0, 4.85, 0)), Kit.Char, M.Metal)
	if withLight then
		Kit.light(core, "PointLight", Color3.fromRGB(255, 214, 150), 0.8, 24)
	end
	return m
end

-- Short kiosk bollard with a glowing slot (reference 15).
function Kit.bollard(parent: Instance, pos: Vector3): Model
	local m = Kit.model(parent, "CT_Rocks_Bollard")
	Kit.part(m, "Body", Vector3.new(1.5, 2.6, 1.5), CFrame.new(pos + Vector3.new(0, 1.3, 0)), Kit.Slate, M.Slate)
	Kit.deco(Kit.part(m, "Slot", Vector3.new(0.5, 1.5, 0.12), CFrame.new(pos + Vector3.new(0, 1.4, 0.78)), Kit.Amber, M.Neon))
	Kit.part(m, "Top", Vector3.new(1.8, 0.4, 1.8), CFrame.new(pos + Vector3.new(0, 2.8, 0)), Kit.Char, M.Metal)
	return m
end

-- Dark rail fence with glowing post slots (reference 8). cf: centre on the ground, runs along X.
function Kit.fence(parent: Instance, cf: CFrame, length: number): Model
	local m = Kit.model(parent, "CT_Rocks_Fence")
	local n = math.max(1, math.floor(length / 6))
	for i = 0, n do
		local x = -length / 2 + i * length / n
		Kit.part(m, "Post", Vector3.new(1.0, 3.6, 1.0), cf * CFrame.new(x, 1.8, 0), Kit.Char, M.Metal)
		Kit.deco(Kit.part(m, "Slot", Vector3.new(0.3, 1.5, 0.1), cf * CFrame.new(x, 2.0, 0.54), Kit.Amber, M.Neon))
		Kit.deco(Kit.part(m, "PostCap", Vector3.new(1.2, 0.3, 1.2), cf * CFrame.new(x, 3.7, 0), Kit.Slate, M.Metal))
	end
	for _, y in { 1.2, 2.0, 2.8 } do
		Kit.deco(Kit.part(m, "Rail", Vector3.new(length, 0.3, 0.4), cf * CFrame.new(0, y, 0), Kit.Slate, M.Metal))
	end
	Kit.deco(Kit.part(m, "Curb", Vector3.new(length, 0.5, 1.4), cf * CFrame.new(0, 0.25, 0), Kit.Stone, M.Concrete))
	return m
end

-- Octagon-style stone emblem with an amber crystal cluster. Decoration only, never a collectible.
-- cf: centre of the emblem, +Z toward the viewer.
function Kit.emblem(parent: Instance, cf: CFrame, d: number): Model
	local m = Kit.model(parent, "CT_Rocks_Emblem")
	Kit.deco(Kit.discZ(m, "Rock", d, d * 0.12, cf, Kit.Slate, M.Slate))
	Kit.deco(Kit.discZ(m, "Rim", d * 0.86, d * 0.14, cf * CFrame.new(0, 0, d * 0.01), Kit.Stone, M.Slate))
	Kit.deco(Kit.discZ(m, "Inner", d * 0.66, d * 0.16, cf * CFrame.new(0, 0, d * 0.02), Kit.Char, M.SmoothPlastic))
	for i, a in { -30, 0, 30 } do
		local len = (if i == 2 then 0.5 else 0.38) * d
		Kit.deco(Kit.part(m, "Crystal", Vector3.new(0.17 * d, len, 0.1 * d), cf * CFrame.new(0, -0.2 * d, d * 0.1) * CFrame.Angles(0, 0, math.rad(-a)) * CFrame.new(0, len / 2, 0), Kit.Amber, M.SmoothPlastic))
		Kit.deco(Kit.part(m, "CrystalTip", Vector3.new(0.17 * d, 0.14 * d, 0.1 * d), cf * CFrame.new(0, -0.2 * d, d * 0.1) * CFrame.Angles(0, 0, math.rad(-a)) * CFrame.new(0, len + 0.04 * d, 0) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 220, 120), M.SmoothPlastic))
	end
	return m
end

-- Crossed hammers emblem (workshop identity), +Z toward the viewer.
function Kit.hammerEmblem(parent: Instance, cf: CFrame, d: number): Model
	local m = Kit.model(parent, "CT_Rocks_HammerEmblem")
	Kit.deco(Kit.part(m, "Plate", Vector3.new(d, d * 0.8, d * 0.1), cf, Kit.Char, M.SmoothPlastic))
	for _, a in { 38, -38 } do
		local r = cf * CFrame.new(0, 0, d * 0.08) * CFrame.Angles(0, 0, math.rad(a))
		Kit.deco(Kit.part(m, "Handle", Vector3.new(0.08 * d, 0.7 * d, 0.07 * d), r, Kit.Wood, M.Wood))
		Kit.deco(Kit.part(m, "Head", Vector3.new(0.36 * d, 0.16 * d, 0.1 * d), r * CFrame.new(0, 0.3 * d, 0), Kit.Amber, M.Metal))
	end
	return m
end

-- Glowing chevron path inset pointing toward -Z (reference 14). cf: centre on the paving surface.
function Kit.chevron(parent: Instance, cf: CFrame, size: number): Model
	local m = Kit.model(parent, "CT_Rocks_PathArrow")
	Kit.deco(Kit.part(m, "Border", Vector3.new(size, 0.07, size), cf * CFrame.new(0, 0.035, 0), Kit.Stone, M.Concrete))
	Kit.deco(Kit.part(m, "Inset", Vector3.new(size * 0.8, 0.09, size * 0.8), cf * CFrame.new(0, 0.045, 0), Kit.Char, M.Concrete))
	for _, s in { -1, 1 } do
		Kit.deco(Kit.part(m, "Bar", Vector3.new(size * 0.12, 0.05, size * 0.46), cf * CFrame.new(s * size * 0.15, 0.1, size * 0.02) * CFrame.Angles(0, math.rad(s * 45), 0), Kit.Amber, M.Neon))
	end
	return m
end

-- Entrance arch: two stone pillars with lanterns and a stepped dark header carrying an emblem.
-- cf: centre on the ground, +Z toward the viewer; `span` is the clear width between the pillars.
function Kit.arch(parent: Instance, cf: CFrame, span: number, h: number): Model
	local m = Kit.model(parent, "CT_Rocks_EntranceArch")
	for _, s in { -1, 1 } do
		local pc = cf * CFrame.new(s * (span / 2 + 1), 0, 0)
		Kit.pillar(m, pc, h, 2.0)
		Kit.deco(Kit.part(m, "Slot", Vector3.new(0.5, 4.2, 0.14), pc * CFrame.new(0, h * 0.5, 1.12), Kit.Amber, M.Neon))
	end
	local w = span + 4
	Kit.deco(Kit.part(m, "HeaderLow", Vector3.new(w, 1.4, 2.0), cf * CFrame.new(0, h + 0.5, 0), Kit.Char, M.Metal))
	Kit.deco(Kit.part(m, "HeaderMid", Vector3.new(w * 0.7, 1.2, 1.9), cf * CFrame.new(0, h + 1.7, 0), Kit.Slate, M.Metal))
	Kit.deco(Kit.part(m, "HeaderTop", Vector3.new(w * 0.4, 1.0, 1.8), cf * CFrame.new(0, h + 2.8, 0), Kit.Char, M.Metal))
	Kit.emblem(m, cf * CFrame.new(0, h + 1.9, 1.05), 3.2)
	return m
end

return Kit
