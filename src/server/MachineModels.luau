--!strict
-- Procedural machine models for the arena bays: cute pastel egg-cracking gadgets (peach / lavender / mint paint; the
-- shapes and motion roles are the old crusher machines). Original note: (orange / slate industrial style, see
-- docs/refs/02_tools_machines.png). Everything is anchored parts; the moving bits are animated on
-- each client by src/client/MachineView.luau, found through attributes:
--   Role = Belt | Spin | Jaw | Plate | Piston | Light | Beacon | Dust   (Dir = +1 / -1, Order = n)
-- Moving parts never collide and never answer queries (collision-safe animation): only the frame,
-- housing and base can be bumped, and they never move. Bay-local axes: -Z faces the pile (intake),
-- +Z is the outlet, the pad top is y = 0.
-- REPLACE: swap these builders for uploaded meshes (CT_Rocks_Machine_<Id>) once art exists.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KitModels = require(Shared.KitModels)
local KitPlace = require(script.Parent.KitPlace)
local GearKit = require(Shared.GearKit)

local P = Config.Palette
local ORANGE = Color3.fromRGB(255, 160, 150) -- peach pink
local SLATE = Color3.fromRGB(176, 158, 214) -- lavender
local SLATEL = Color3.fromRGB(206, 232, 214) -- mint
local YELLOW = Color3.fromRGB(255, 218, 110)
local CREAM = P.Cream
local DARK = Color3.fromRGB(150, 118, 150)
local STEEL = Color3.fromRGB(252, 244, 232)
local BELT = Color3.fromRGB(190, 170, 226)
local NEON_OFF = Color3.fromRGB(92, 98, 106)

local MachineModels = {}

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
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, name: string, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return mk(parent, name, Vector3.new(length, dia, dia), cf, color, mat, false, Enum.PartType.Cylinder)
end

-- A sub-model whose pivot is its core part, so clients can rotate it around that centre.
local function rotor(parent: Instance, name: string, role: string, dir: number, cf: CFrame, length: number, dia: number, ridges: number): Model
	local m = Instance.new("Model")
	m.Name = name
	local core = cyl(m, "Core", length, dia, cf, STEEL)
	for i = 1, ridges do
		local a = (i / ridges) * math.pi * 2
		mk(m, "Ridge", Vector3.new(length * 0.96, dia * 0.22, dia * 0.22), cf * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0, dia * 0.5), if i % 2 == 0 then ORANGE else DARK)
	end
	m.PrimaryPart = core
	m:SetAttribute("Role", role)
	m:SetAttribute("Dir", dir)
	m.Parent = parent
	return m
end

-- Hinged plate: pivot part sits on the hinge, the plate hangs off it.
local function jaw(parent: Instance, name: string, dir: number, hinge: CFrame, plate: Vector3, off: Vector3): Model
	local m = Instance.new("Model")
	m.Name = name
	local pivot = mk(m, "Hinge", Vector3.new(0.4, 0.4, 0.4), hinge, DARK)
	mk(m, "Plate", plate, hinge * CFrame.new(off), STEEL)
	for i = -1, 1 do
		mk(m, "Teeth", Vector3.new(0.4, plate.Y * 0.14, plate.Z * 0.96), hinge * CFrame.new(off + Vector3.new(dir * 0.4, i * plate.Y * 0.3, 0)), ORANGE)
	end
	m.PrimaryPart = pivot
	m:SetAttribute("Role", "Jaw")
	m:SetAttribute("Dir", dir)
	m.Parent = parent
	return m
end

local function stateLight(parent: Instance, base: CFrame, x: number, z: number, height: number)
	mk(parent, "LightPost", Vector3.new(0.3, height, 0.3), base * CFrame.new(x, height / 2, z), DARK, Enum.Material.SmoothPlastic, true)
	local bulb = mk(parent, "StateLight", Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(x, height + 0.4, z), NEON_OFF, Enum.Material.Neon, false, Enum.PartType.Ball)
	bulb:SetAttribute("Role", "Light")
	local pl = Instance.new("PointLight")
	pl.Range = 8
	pl.Brightness = 0.5
	pl.Color = NEON_OFF
	pl.Enabled = false
	pl.Parent = bulb
end

-- On/off panel with a prompt; only the owner's press counts (checked on the server).
local function panel(parent: Instance, base: CFrame, x: number, z: number, y: number)
	local post = mk(parent, "PanelPost", Vector3.new(0.4, y, 0.4), base * CFrame.new(x, y / 2, z), DARK, Enum.Material.SmoothPlastic, true)
	local box = mk(parent, "Panel", Vector3.new(1.5, 1.6, 0.5), base * CFrame.new(x, y + 0.1, z - 0.1), SLATE, Enum.Material.SmoothPlastic, true)
	mk(parent, "PanelOn", Vector3.new(0.5, 0.5, 0.12), base * CFrame.new(x - 0.38, y + 0.35, z - 0.4), Color3.fromRGB(110, 220, 140), Enum.Material.Neon)
	mk(parent, "PanelOff", Vector3.new(0.5, 0.5, 0.12), base * CFrame.new(x + 0.38, y + 0.35, z - 0.4), P.Red, Enum.Material.Neon)
	mk(parent, "PanelStrip", Vector3.new(1.2, 0.3, 0.1), base * CFrame.new(x, y - 0.35, z - 0.4), YELLOW, Enum.Material.SmoothPlastic)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "MachineToggle"
	pp.ActionText = "Start / Stop"
	pp.ObjectText = "Machine"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R
	pp:SetAttribute("MachineToggle", true)
	pp.Parent = box
	post.Name = "PanelPost"
end

local function belt(parent: Instance, base: CFrame, width: number, z0: number, z1: number, y: number, tiles: number)
	local len = z1 - z0
	mk(parent, "BeltBed", Vector3.new(width + 0.2, 0.5, len), base * CFrame.new(0, y - 0.3, (z0 + z1) / 2), DARK, Enum.Material.SmoothPlastic, true)
	for _, sx in { -1, 1 } do
		mk(parent, "BeltRail", Vector3.new(0.3, 0.8, len), base * CFrame.new(sx * (width / 2 + 0.2), y + 0.1, (z0 + z1) / 2), ORANGE)
	end
	local pitch = len / tiles
	for i = 1, tiles do
		local t = mk(parent, "BeltTile", Vector3.new(width, 0.14, pitch * 0.82), base * CFrame.new(0, y, z0 + (i - 0.5) * pitch), if i % 2 == 0 then BELT else Color3.fromRGB(214, 198, 240), Enum.Material.SmoothPlastic)
		t:SetAttribute("Role", "Belt")
		t:SetAttribute("Order", i)
		t:SetAttribute("Count", tiles)
		t:SetAttribute("Z0", z0)
		t:SetAttribute("Length", len)
		if i % 4 == 0 then
			mk(t, "Chevron", Vector3.new(width * 0.5, 0.04, pitch * 0.3), t.CFrame * CFrame.new(0, 0.08, 0), YELLOW, Enum.Material.SmoothPlastic)
		end
	end
end

local function dust(parent: BasePart, offset: Vector3)
	local a = Instance.new("Attachment")
	a.Name = "DustPoint"
	a.Position = offset
	a:SetAttribute("Role", "Dust")
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Enabled = false
	e.Rate = 8
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = a
end

-- Soft padded tray the geode lands in (width 2.2, depth d).
local function geodeTray(parent: Instance, base: CFrame, x: number, y: number, z: number, d: number)
	mk(parent, "TrayBody", Vector3.new(2.2, 0.5, d), base * CFrame.new(x, y, z), SLATEL, Enum.Material.SmoothPlastic, true)
	mk(parent, "TrayPad", Vector3.new(1.8, 0.2, d - 0.4), base * CFrame.new(x, y + 0.35, z), CREAM, Enum.Material.Fabric)
	for _, sx in { -1, 1 } do
		mk(parent, "TrayRim", Vector3.new(0.2, 0.5, d), base * CFrame.new(x + sx * 1.1, y + 0.4, z), YELLOW)
	end
	mk(parent, "TrayRim", Vector3.new(2.2, 0.5, 0.2), base * CFrame.new(x, y + 0.4, z + d / 2), YELLOW)
end

local function chute(parent: Instance, base: CFrame, x: number, y: number, z: number, width: number, length: number)
	local tilt = CFrame.Angles(math.rad(22), 0, 0) -- outlet end lower
	mk(parent, "OutletChute", Vector3.new(width, 0.25, length), base * CFrame.new(x, y, z) * tilt, SLATEL, Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		mk(parent, "ChuteLip", Vector3.new(0.25, 0.7, length), base * CFrame.new(x + sx * (width / 2), y + 0.25, z) * tilt, ORANGE)
	end
end

-- AUTO CRACKER: intake conveyor, rollers, motor, guarded housing, outlet, soft geode tray -------

local function autoCracker(m: Model, base: CFrame)
	mk(m, "Base", Vector3.new(9.4, 0.5, 9), base * CFrame.new(0, 0.25, 0), SLATEL, Enum.Material.SmoothPlastic, true)
	belt(m, base, 2.6, -4.5, -0.7, 1.15, 9)
	-- housing: walls, roof, floor around a front opening; yellow guard bars across the opening
	local hy, hz = 2.7, 1.5
	mk(m, "HousingWallL", Vector3.new(0.4, 4.2, 4.4), base * CFrame.new(-3.4, hy, hz), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "HousingWallR", Vector3.new(0.4, 4.2, 4.4), base * CFrame.new(3.4, hy, hz), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "HousingBack", Vector3.new(6.4, 4.2, 0.4), base * CFrame.new(0, hy, hz + 2.1), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "HousingRoof", Vector3.new(7.2, 0.4, 4.6), base * CFrame.new(0, hy + 2.3, hz), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "HousingFloor", Vector3.new(6.4, 0.3, 4.4), base * CFrame.new(0, 0.65, hz), DARK, Enum.Material.SmoothPlastic, true)
	mk(m, "FrontPostL", Vector3.new(1.6, 4.2, 0.4), base * CFrame.new(-2.4, hy, hz - 2.2), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "FrontPostR", Vector3.new(1.6, 4.2, 0.4), base * CFrame.new(2.4, hy, hz - 2.2), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "FrontLintel", Vector3.new(3.2, 1.4, 0.4), base * CFrame.new(0, hy + 1.5, hz - 2.2), ORANGE, Enum.Material.SmoothPlastic, true)
	for i = -1, 1 do
		mk(m, "GuardBar", Vector3.new(0.14, 2.2, 0.14), base * CFrame.new(i * 0.9, hy - 0.2, hz - 2.4), YELLOW)
	end
	mk(m, "Stripe", Vector3.new(7.3, 0.4, 0.1), base * CFrame.new(0, hy + 1.7, hz - 2.36), YELLOW, Enum.Material.SmoothPlastic)
	-- three rollers inside the opening
	for i = 0, 2 do
		rotor(m, "Roller" .. (i + 1), "Spin", if i % 2 == 0 then 1 else -1, base * CFrame.new(0, 1.95, hz - 1.5 + i * 1.5), 2.6, 0.95, 4)
	end
	-- motor on the roof with cooling fins
	cyl(m, "Motor", 2.8, 1.6, base * CFrame.new(0, hy + 3.2, hz), SLATE)
	for i = -1, 1 do
		cyl(m, "MotorFin", 0.2, 1.9, base * CFrame.new(i * 0.9, hy + 3.2, hz), DARK)
	end
	mk(m, "MotorMount", Vector3.new(2.2, 0.6, 2.2), base * CFrame.new(0, hy + 2.7, hz), DARK, Enum.Material.SmoothPlastic)
	-- outlet and soft geode tray
	chute(m, base, 0, 1.3, hz + 2.9, 2.4, 1.6)
	geodeTray(m, base, 4.9, 0.7, 2.6, 1.8)
	local out = m:FindFirstChild("OutletChute") :: BasePart
	dust(out, Vector3.new(0, 0.3, 0.8))
	stateLight(m, base, -5.2, -2.6, 3.4)
	panel(m, base, -5.2, -2.6, 1.8)
end

-- HYDRAULIC PRESS: frame, piston, plate, tray, warning beacon, guard rail, recovery chute -------

local function press(m: Model, base: CFrame)
	mk(m, "Base", Vector3.new(9.4, 0.5, 8.2), base * CFrame.new(0, 0.25, 0.4), SLATEL, Enum.Material.SmoothPlastic, true)
	local pz = 0.6
	for _, sx in { -3.3, 3.3 } do
		for _, dz in { -2.5, 2.5 } do
			mk(m, "FramePost", Vector3.new(0.9, 7.2, 0.9), base * CFrame.new(sx, 0.5 + 3.6, pz + dz), ORANGE, Enum.Material.SmoothPlastic, true)
		end
	end
	mk(m, "FrameBeam", Vector3.new(7.8, 1.0, 5.9), base * CFrame.new(0, 8.2, pz), ORANGE, Enum.Material.SmoothPlastic, true)
	mk(m, "BeamStripe", Vector3.new(7.9, 0.3, 0.1), base * CFrame.new(0, 8.2, pz - 2.96), YELLOW, Enum.Material.SmoothPlastic)
	cyl(m, "PistonHousing", 1.8, 1.9, base * CFrame.new(0, 7.0, pz) * CFrame.Angles(0, 0, math.pi / 2), SLATE)
	-- tray (the bed the plate presses onto) with side lips
	mk(m, "TrayBed", Vector3.new(5.4, 0.7, 4.2), base * CFrame.new(0, 0.85, pz), SLATE, Enum.Material.SmoothPlastic, true)
	for _, sx in { -1, 1 } do
		mk(m, "TrayLip", Vector3.new(0.25, 0.7, 4.2), base * CFrame.new(sx * 2.75, 1.25, pz), YELLOW)
	end
	-- moving parts, drawn in the raised pose: plate top 5.95, rod from the beam (7.7) down to it
	local plate = mk(m, "PressPlate", Vector3.new(4.6, 0.7, 3.6), base * CFrame.new(0, 5.6, pz), STEEL, Enum.Material.SmoothPlastic)
	plate:SetAttribute("Role", "Plate")
	for i = 0, 3 do
		mk(plate, "PlateHazard", Vector3.new(0.7, 0.05, 0.18), plate.CFrame * CFrame.new(-1.6 + i * 1.07, 0.38, -1.6), if i % 2 == 0 then YELLOW else DARK, Enum.Material.SmoothPlastic)
	end
	local rod = cyl(m, "PistonRod", 1.75, 1.0, base * CFrame.new(0, (7.7 + 5.95) / 2, pz) * CFrame.Angles(0, 0, math.pi / 2), STEEL)
	rod:SetAttribute("Role", "Piston")
	rod:SetAttribute("Top", 7.7)
	-- warning beacon
	cyl(m, "BeaconBase", 0.4, 1.2, base * CFrame.new(2.6, 8.9, pz + 1.6) * CFrame.Angles(0, 0, math.pi / 2), DARK)
	local beacon = mk(m, "Beacon", Vector3.new(1.0, 1.0, 1.0), base * CFrame.new(2.6, 9.5, pz + 1.6), NEON_OFF, Enum.Material.Neon, false, Enum.PartType.Ball)
	beacon:SetAttribute("Role", "Beacon")
	-- guard rail along both sides and the front corners
	for _, sx in { -4.5, 4.5 } do
		for _, dz in { -3.3, 0, 3.3 } do
			mk(m, "RailPost", Vector3.new(0.25, 2.4, 0.25), base * CFrame.new(sx, 1.7, pz + dz), YELLOW)
		end
		for _, ry in { 1.2, 2.2 } do
			mk(m, "RailBar", Vector3.new(0.2, 0.2, 6.9), base * CFrame.new(sx, ry + 0.5, pz), YELLOW)
		end
	end
	-- intake ramp (front) and recovery chute (back) with the geode pad
	mk(m, "IntakeRamp", Vector3.new(2.8, 0.25, 2.4), base * CFrame.new(0, 1.0, pz - 3.5) * CFrame.Angles(math.rad(14), 0, 0), SLATEL, Enum.Material.SmoothPlastic)
	chute(m, base, 0, 1.15, pz + 2.8, 2.6, 1.6)
	geodeTray(m, base, 0, 0.7, pz + 3.75, 1.2)
	dust(m:FindFirstChild("OutletChute") :: BasePart, Vector3.new(0, 0.3, 0.8))
	stateLight(m, base, -5.4, -2.8, 3.2)
	panel(m, base, -5.4, -2.8, 1.8)
end

-- INDUSTRIAL CRUSHER: conveyor, jaws and rollers, motor, guards, outlet, dust, recovery tray ----

local function crusher(m: Model, base: CFrame)
	mk(m, "Base", Vector3.new(10.6, 0.6, 9.4), base * CFrame.new(0, 0.3, 0), SLATEL, Enum.Material.SmoothPlastic, true)
	belt(m, base, 3.2, -4.6, -2.2, 1.3, 8)
	-- crushing chamber: dark body open at the top
	local cy, cz = 2.6, 0.6
	mk(m, "BodyFloor", Vector3.new(8.6, 0.5, 5.2), base * CFrame.new(0, 0.85, cz), DARK, Enum.Material.SmoothPlastic, true)
	mk(m, "BodyFront", Vector3.new(8.6, 3.4, 0.5), base * CFrame.new(0, cy + 0.2, cz - 2.6), SLATE, Enum.Material.SmoothPlastic, true)
	mk(m, "BodyBack", Vector3.new(8.6, 3.4, 0.5), base * CFrame.new(0, cy + 0.2, cz + 2.6), SLATE, Enum.Material.SmoothPlastic, true)
	for _, sx in { -4.3, 4.3 } do
		mk(m, "BodyWall", Vector3.new(0.5, 3.4, 5.2), base * CFrame.new(sx, cy + 0.2, cz), SLATE, Enum.Material.SmoothPlastic, true)
	end
	mk(m, "BodyBand", Vector3.new(8.7, 0.45, 5.3), base * CFrame.new(0, cy + 1.7, cz), ORANGE, Enum.Material.SmoothPlastic)
	-- feed slot in the front wall is the belt's mouth
	mk(m, "FeedHood", Vector3.new(3.8, 0.4, 1.4), base * CFrame.new(0, 3.0, cz - 3.1), ORANGE, Enum.Material.SmoothPlastic)
	-- two counter-rotating rollers and two swinging jaw plates inside
	rotor(m, "RollerA", "Spin", 1, base * CFrame.new(0, 3.1, cz - 0.9), 6.0, 1.7, 5)
	rotor(m, "RollerB", "Spin", -1, base * CFrame.new(0, 3.1, cz + 0.9), 6.0, 1.7, 5)
	jaw(m, "JawL", 1, base * CFrame.new(-3.7, 4.2, cz), Vector3.new(0.5, 2.6, 4.2), Vector3.new(0.35, -1.3, 0))
	jaw(m, "JawR", -1, base * CFrame.new(3.7, 4.2, cz), Vector3.new(0.5, 2.6, 4.2), Vector3.new(-0.35, -1.3, 0))
	-- guard cage over the open top
	for i = -3, 3 do
		mk(m, "GuardBar", Vector3.new(0.16, 0.16, 5.3), base * CFrame.new(i * 1.15, cy + 2.15, cz), YELLOW)
	end
	for _, dz in { -2.6, 2.6 } do
		mk(m, "GuardBeam", Vector3.new(8.7, 0.22, 0.22), base * CFrame.new(0, cy + 2.15, cz + dz), YELLOW)
	end
	-- motor with a turning flywheel on the right
	cyl(m, "Motor", 1.6, 1.9, base * CFrame.new(5.2, 2.0, cz - 1.4), SLATE)
	cyl(m, "MotorFin", 0.2, 2.2, base * CFrame.new(4.7, 2.0, cz - 1.4), DARK)
	rotor(m, "Flywheel", "Spin", 1, base * CFrame.new(5.3, 2.2, cz + 1.2), 0.5, 2.4, 6)
	-- outlet chute with dust and the recovery tray
	chute(m, base, 0, 1.2, cz + 3.6, 3.0, 1.5)
	geodeTray(m, base, -3.4, 0.9, cz + 3.7, 1.2)
	dust(m:FindFirstChild("OutletChute") :: BasePart, Vector3.new(0, 0.3, 0.8))
	local top = m:FindFirstChild("BodyBand") :: BasePart
	dust(top, Vector3.new(0, 1.0, 0))
	stateLight(m, base, -5.4, -3.3, 3.6)
	panel(m, base, -5.4, -3.3, 1.8)
end

-- Kit machines (Auto_Cracker, Hydraulic_Press, Industrial_Crusher; motion notes in docs/ASSET_MANIFEST.md).
-- The mesh is turned 90 degrees so its feed side (+X) faces the pile side of the bay (-Z), and shifted so
-- its footprint is centred on the pad. The meshes are visual; the server marks the moving pieces with
-- attributes for MachineView (world-space values, the arena never moves):
--   Role KitJaw    Delta (open -> closed slide)        Role KitPress  Travel (platen drop in studs)
--   Role KitRoller Pivot, Axis, Dir (spin about Axis)  Role KitFill   hidden until the machine runs
--   Role Light     the lamp (state colour + PointLight)
-- and the model gets PathStart / PathBeltEnd / PathRoller / PathMid / PathOut (pad-top frame) for the cosmetic
-- feed stones, taken from the kit attachment points.
local KIT_MACHINES = { AutoCracker = "Auto_Cracker", HydraulicPress = "Hydraulic_Press", IndustrialCrusher = "Industrial_Crusher" }

local function kitMachine(m: Model, base: CFrame, id: string): boolean
	if true then
		return false -- the quarry kit machines are not used for the pastel gadgets (REPLACE: real gadget mesh)
	end
	local t = KitModels.template(KIT_MACHINES[id])
	if not t then
		return false
	end
	local lo, hi = KitModels.extents(t)
	local origin = base * CFrame.new(-(lo.Z + hi.Z) / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	local function at(point: string): Vector3
		return KitModels.attach(t, point) or Vector3.zero
	end
	local function world(v: Vector3): Vector3
		return origin:PointToWorldSpace(v)
	end
	local function toBase(v: Vector3): Vector3
		return base:PointToObjectSpace(world(v))
	end
	local pad = mk(m, "Base", Vector3.new(hi.Z - lo.Z, 0.5, hi.X - lo.X), base * CFrame.new(0, 0.25, 0), SLATEL, Enum.Material.SmoothPlastic, false)
	pad.Transparency = 1
	local parts: { [string]: BasePart } = {}
	for _, src in t:GetChildren() do
		if src:IsA("MeshPart") then
			local p = src:Clone()
			for _, ch in p:GetChildren() do
				ch:Destroy()
			end
			p.Anchored = true
			p.CFrame = origin * src.CFrame
			p.CanCollide = src.Name == "Concrete"
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = src.Transparency < 0.5
			p.Parent = m
			parts[src.Name] = p
		end
	end
	-- moving pieces
	local function slide(name: string, openPt: string, closedPt: string)
		local p = parts[name]
		if p then
			p:SetAttribute("Role", "KitJaw")
			p:SetAttribute("Delta", origin:VectorToWorldSpace(at(closedPt) - at(openPt)))
		end
	end
	if id == "AutoCracker" then
		slide("JawL", "JawL_Open", "JawL_Closed")
		slide("JawR", "JawR_Open", "JawR_Closed")
	elseif id == "HydraulicPress" then
		for _, n in { "Piston", "Platen" } do
			if parts[n] then
				parts[n]:SetAttribute("Role", "KitPress")
				parts[n]:SetAttribute("Travel", (at("Platen_Open") - at("Platen_Down")).Magnitude)
			end
		end
	else
		for n, dir in ({ RollerL = 1, RollerR = -1 } :: { [string]: number }) do
			local p = parts[n]
			if p then
				p:SetAttribute("Role", "KitRoller")
				p:SetAttribute("Pivot", world(at(n)))
				p:SetAttribute("Axis", origin:VectorToWorldSpace(Vector3.xAxis))
				p:SetAttribute("Dir", dir)
			end
		end
	end
	for _, n in { "Fill", "HopperFill" } do
		local p = parts[n]
		if p then
			p:SetAttribute("Role", "KitFill")
			p.Transparency = 1
		end
	end
	local lamp = parts.Lamp
	if lamp then
		lamp:SetAttribute("Role", "Light")
		lamp.Material = Enum.Material.Neon
		lamp.Color = NEON_OFF
		local pl = Instance.new("PointLight")
		pl.Range = 8
		pl.Brightness = 0.5
		pl.Color = NEON_OFF
		pl.Enabled = false
		pl.Parent = lamp
	end
	-- start / stop prompt on the panel (only the owner's press counts, checked on the server)
	local box = mk(m, "Panel", Vector3.new(1.4, 1.2, 0.6), origin * CFrame.new(at("Panel")), SLATE, Enum.Material.SmoothPlastic, false)
	box.Transparency = 1
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "MachineToggle"
	pp.ActionText = "Start / Stop"
	pp.ObjectText = "Machine"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R
	pp:SetAttribute("MachineToggle", true)
	pp.Parent = box
	-- dust where the pieces come out
	local out = mk(m, "OutletChute", Vector3.new(1, 1, 1), origin * CFrame.new(at("Output")), DARK, Enum.Material.SmoothPlastic, false)
	out.Transparency = 1
	dust(out, Vector3.new(0, 0.3, 0))
	if id == "IndustrialCrusher" then
		local top = mk(m, "DustTop", Vector3.new(1, 1, 1), origin * CFrame.new(at("Hopper")), DARK, Enum.Material.SmoothPlastic, false)
		top.Transparency = 1
		dust(top, Vector3.new(0, 0.5, 0))
	end
	-- cosmetic feed stone path, from the attachment points
	local outP = at("Output")
	local startP, beltEnd, roller
	if id == "AutoCracker" then
		startP, beltEnd, roller = at("FeedStart"), at("FeedEnd"), at("Chamber")
	elseif id == "HydraulicPress" then
		startP, roller = at("FeedStart"), at("RockSpot")
		beltEnd = roller
	else
		startP, beltEnd, roller = at("Hopper") + Vector3.new(3.4, 0, 0), at("Hopper"), at("RollerL"):Lerp(at("RollerR"), 0.5)
	end
	local mid = if id == "IndustrialCrusher" then at("BeltStart") else roller:Lerp(outP, 0.5)
	m:SetAttribute("PathStart", toBase(startP))
	m:SetAttribute("PathBeltEnd", toBase(beltEnd))
	m:SetAttribute("PathRoller", toBase(roller))
	m:SetAttribute("PathMid", toBase(mid))
	m:SetAttribute("PathOut", toBase(outP))
	m:SetAttribute("Kit", true)
	return true
end

local BUILDERS: { [string]: (Model, CFrame) -> () } = {
	AutoCracker = autoCracker,
	HydraulicPress = press,
	IndustrialCrusher = crusher,
}

-- Owner's Gear_<Id> model (Assets.Kit, Ready=true) as the machine's look, fitted to the Parts footprint and
-- pad-top pivot. The Parts build stays underneath for everything the game uses (Base, hopper / outlet / panel
-- points, the start prompt, state lights, dust, Role pieces MachineView animates); its body parts are only
-- made invisible. No Ready gear model: nothing changes (Parts fallback).
function MachineModels.dressWithGear(m: Model, machineId: string, padTop: CFrame)
	local tpl = KitModels.template("Gear_" .. machineId)
	if GearKit.source(tpl ~= nil, tpl ~= nil and tpl:GetAttribute("Ready") == true) ~= "Gear" or not tpl then
		return
	end
	local ok, err = pcall(function()
		local _, box = m:GetBoundingBox()
		local gear = tpl:Clone()
		local _, gsize = gear:GetBoundingBox()
		local s = GearKit.fitScale(gsize, Vector3.new(box.X, 0, box.Z))
		gear.Name = "GearModel"
		gear:ScaleTo(gear:GetScale() * s)
		local bcf = (m:GetBoundingBox())
		local gcf, gs = gear:GetBoundingBox()
		-- bottom centre of the gear on the bottom centre of the old footprint (pad top)
		local want = CFrame.new(bcf.Position.X, padTop.Position.Y, bcf.Position.Z) * padTop.Rotation
		local have = gcf * CFrame.new(0, -gs.Y / 2, 0)
		gear:PivotTo(want * have:ToObjectSpace(gear:GetPivot()))
		for _, d in gear:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "Base" then
				if GearKit.hideUnderGear(d.Name, d:GetAttribute("Role")) then
					d.Transparency = 1
					for _, l in d:GetChildren() do
						if l:IsA("Light") then
							l.Enabled = false -- the state bulb / beacon glow would float beside the gear model
						end
					end
					d.CastShadow = false
					for _, g in d:GetChildren() do
						if g:IsA("SurfaceGui") then
							g.Enabled = false
						end
					end
				end
			end
		end
		gear.Parent = m
	end)
	if not ok then
		warn("[MachineModels] gear model failed, keeping Parts: " .. tostring(err))
	end
end

-- Builds the machine for a bay (bayCF = the bay pad's CFrame, -Z toward the pile).
function MachineModels.build(machineId: string, bayCF: CFrame, parent: Instance, ownerId: number, ownerName: string): Model?
	local builder = BUILDERS[machineId]
	if not builder then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Machine_" .. machineId
	m:SetAttribute("MachineId", machineId)
	m:SetAttribute("OwnerId", ownerId)
	m:SetAttribute("Frame", bayCF * CFrame.new(0, 0.3, 0)) -- pad-top frame, read by the client animation
	local padTop = bayCF * CFrame.new(0, 0.3, 0)
	local okKit = false
	if KIT_MACHINES[machineId] then
		local ok, res = pcall(kitMachine, m, padTop, machineId)
		okKit = ok and res == true
		if not okKit then
			if not ok then
				warn("[MachineModels] kit machine failed, using Parts: " .. tostring(res))
			end
			m:ClearAllChildren() -- drop a half-built kit model
		end
	end
	if not okKit then
		builder(m, padTop) -- Part stand-in
	end
	local base = m:FindFirstChild("Base") :: BasePart?
	if base then
		m.PrimaryPart = base
	end
	if not okKit then
		MachineModels.dressWithGear(m, machineId, padTop)
	end
	-- owner plate
	local info = Config.Machines[machineId]
	-- (on the slab's outer side, facing the quiet lane between stations: the pad edge towards the table
	-- is hidden behind the table, so a plate there could never be read)
	local plate = mk(m, "OwnerPlate", Vector3.new(4.4, 1.3, 0.16), bayCF * CFrame.new(5.8, 0.8, 0) * CFrame.Angles(0, -math.pi / 2, 0), SLATE, Enum.Material.SmoothPlastic)
	-- fitted text (SignLayout via KitPlace.applyFit, explicit TextSize) with the sign audit attributes
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = plate
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = CREAM
	t.Parent = gui
	-- two lines (owner, machine): on one line the pair overran the plate and the machine name was cut off
	local f = KitPlace.applyFit(gui, t, ownerName .. "\n" .. info.Name, plate.Size.X, plate.Size.Y, "Placard")
	plate:SetAttribute("SignText", f.Text)
	plate:SetAttribute("SignPreset", "Placard")
	plate:SetAttribute("SignW", plate.Size.X)
	plate:SetAttribute("SignH", plate.Size.Y)
	m.Parent = parent
	return m
end

return MachineModels
