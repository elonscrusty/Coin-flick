--!strict
-- Builds the shared lobby and the private quarry arenas from Parts (procedural stand-ins for the
-- modular kit in docs/refs). Names use the CT_Rocks_ prefix so imported meshes can replace them
-- later. Front is -Z, up is +Y, pivots on the floor.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local KitModels = require(Shared.KitModels)
local MeshService = require(script.Parent.MeshService)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

local P = Config.Palette
local World = {}

local DARK = Color3.fromRGB(52, 58, 64)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3?, bg: Color3?, font: Enum.Font?): TextLabel
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg or P.Slate
	t.BackgroundTransparency = if bg then 0 else 1
	t.TextColor3 = color or P.Yellow
	t.Font = font or Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = t
	return t
end

local function prompt(p: BasePart, action: string, object: string, panel: string, dist: number?)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = dist or 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	pp:SetAttribute("Panel", panel)
	pp.Parent = p
	return pp
end

-- Kit pieces -------------------------------------------------------------------------------

-- Rubble selling hopper. The prompt is handled on the server (EconomyService).
local function hopper(parent: Instance, cf: CFrame): Model
	local m = model(parent, "CT_Rocks_SellHopper")
	local body = part(m, "Body", Vector3.new(8, 3.5, 5), cf * CFrame.new(0, 1.75, 0), DARK, Enum.Material.Metal)
	part(m, "LipL", Vector3.new(0.6, 1.2, 5.6), cf * CFrame.new(-4, 4, 0) * CFrame.Angles(0, 0, math.rad(-20)), P.Orange, Enum.Material.Metal)
	part(m, "LipR", Vector3.new(0.6, 1.2, 5.6), cf * CFrame.new(4, 4, 0) * CFrame.Angles(0, 0, math.rad(20)), P.Orange, Enum.Material.Metal)
	for i = 1, 5 do
		deco(part(m, "Gravel", Vector3.new(1.2, 1, 1.2), cf * CFrame.new(-2.8 + i * 1.0, 3.7, (i % 2) * 0.8 - 0.4) * CFrame.Angles(i, i * 2, 0), P.Rock, Enum.Material.Slate))
	end
	-- grate bars across the mouth and a hazard band on the front
	for i = -3, 3 do
		deco(part(m, "Grate", Vector3.new(0.18, 0.18, 4.6), cf * CFrame.new(i * 1.05, 3.55, 0), Color3.fromRGB(30, 32, 36), Enum.Material.Metal))
	end
	for i = 0, 5 do
		local band = deco(part(m, "Hazard", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(-3.3 + i * 1.32, 0.45, -2.56) * CFrame.Angles(0, 0, math.rad(30)), if i % 2 == 0 then P.Yellow else Color3.fromRGB(28, 28, 30), Enum.Material.SmoothPlastic))
		band.Name = "Hazard"
	end
	local sign = deco(part(m, "Sign", Vector3.new(6, 1.6, 0.2), cf * CFrame.new(0, 1.9, -2.6), P.Slate, Enum.Material.SmoothPlastic))
	label(sign, Enum.NormalId.Front, "SELL CANDY", P.Yellow)
	local pp = prompt(body, "Sell Candy", "Candy Stand", "", 12)
	pp.UIOffset = Vector2.new(0, 30)
	pp.Name = "SellPrompt"
	pp:SetAttribute("Sell", true)
	m:SetAttribute("Hopper", true)
	return m
end
World.hopper = hopper

-- Tool models (also used welded to characters). `scale` sizes the whole tool (EconomyService
-- fits it to the avatar). The grip part sits at the origin. Hammers extend along +Y (head at
-- HeadY); the jackhammer's handlebar lies along X at the origin with the two rubber grips at
-- x = +-GripX, and the body, chuck and silver bit hang along -Y down to the contact point at
-- TipY. These numbers are stored as attributes (already scaled) for ToolAnim, and they match
-- the CT_Rocks_* meshes from tools/gen_meshes.py, which are used instead when uploaded.
World.ToolDims = {
	Hammer = { Length = 3.93, HeadY = 3.35 },
	SteelHammer = { Length = 4.0, HeadY = 3.35 },
	Jackhammer = { Length = 3.05, TipY = -2.92, GripX = 0.7 },
}

-- Kit hand tools (Tool_*.fbx via MeshService): the origin is the grip, handle up +Y, striking faces
-- along X (jackhammer: handlebar along X, body and bit hang down -Y). `Length` is the fit length used by
-- EconomyService.attachTool: it is chosen so the head (or bit tip) ends up as far from the fist as it
-- was with the Part tools, which keeps ToolAnim's reach and the contact with the plate unchanged.
local KIT_TOOL = { Hammer = "Tool_StarterHammer", SteelHammer = "Tool_SteelHammer", Jackhammer = "Tool_Jackhammer" }
local KIT_DIMS = {
	Hammer = { Length = 3.93 * 2.85 / 3.35, HeadY = 2.85 },
	SteelHammer = { Length = 4.0 * 2.85 / 3.35, HeadY = 2.85 },
	Jackhammer = { Length = 3.05 * 3.95 / 2.92, TipY = -3.95, GripX = 1.4 },
}

-- Dimensions (Length for the avatar fit, HeadY / TipY / GripX for ToolAnim) of the tool that
-- World.toolModel builds right now: the kit version when its template is loaded, else the Part one.
function World.toolDims(toolId: string): { [string]: number }
	local kit = KIT_TOOL[toolId]
	if kit and KitModels.template(kit) then
		return KIT_DIMS[toolId]
	end
	return World.ToolDims[toolId] or World.ToolDims.Hammer
end

function World.toolModel(toolId: string, scale: number?): Model
	local sc = scale or 1
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Tool_" .. toolId
	local function tp(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
		local p = part(m, name, size * sc, cf.Rotation + cf.Position * sc, color, mat, shape)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.CastShadow = false
		return p
	end
	-- a cylinder along Y (Roblox cylinders run along X)
	local function rod(name, len: number, dia: number, at: Vector3, color, mat)
		return tp(name, Vector3.new(len, dia, dia), CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), color, mat, Enum.PartType.Cylinder)
	end
	-- a cylinder segment from a to b
	local function hose(name, a: Vector3, b: Vector3, dia: number, color)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		return tp(name, Vector3.new(len + dia * 0.6, dia, dia), CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0), color, Enum.Material.Rubber, Enum.PartType.Cylinder)
	end
	local grip
	local kitTool = if KIT_TOOL[toolId] then KitModels.template(KIT_TOOL[toolId]) else nil
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local meshT = assets and assets:FindFirstChild("CT_Rocks_" .. toolId)
	local STEEL = Color3.fromRGB(196, 200, 206)
	local RUBBER = Color3.fromRGB(28, 30, 34)
	if kitTool then
		-- Blender kit model: a tiny invisible Grip part at the origin, every coloured piece welded to it
		-- below (same Weld loop as the Part version, so attachment and animation work unchanged).
		grip = tp("Grip", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 0, 0), DARK, Enum.Material.SmoothPlastic)
		grip.Transparency = 1
		for _, src in kitTool:GetChildren() do
			if src:IsA("MeshPart") then
				local mp = src:Clone()
				for _, ch in mp:GetChildren() do
					ch:Destroy()
				end
				mp.Size = src.Size * sc
				mp.CFrame = CFrame.new(src.Position * sc) * src.CFrame.Rotation
				mp.Anchored = false
				mp.CanCollide = false
				mp.CanQuery = false
				mp.CanTouch = false
				mp.Massless = true
				mp.CastShadow = false
				mp.Parent = m
			end
		end
	elseif meshT and meshT:IsA("MeshPart") then
		-- Uploaded mesh (pivot = file origin = grip). A tiny invisible Grip part sits at the origin
		-- so Motor6D / Weld attachment works exactly as for the Part version.
		grip = tp("Grip", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 0, 0), DARK, Enum.Material.SmoothPlastic)
		grip.Transparency = 1
		local mp = meshT:Clone()
		mp.Name = "Mesh"
		mp.Color = Color3.new(1, 1, 1) -- vertex colours carry the materials
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.Massless = true
		mp.CastShadow = false
		local po = mp.PivotOffset
		mp.Size = mp.Size * sc
		mp.PivotOffset = po.Rotation + po.Position * sc
		mp.CFrame = CFrame.identity * mp.PivotOffset:Inverse() -- origin of the file at the grip
		mp.Parent = m
	elseif toolId == "Jackhammer" then
		-- handlebar with two rubber grips, a short neck into the orange body, air inlet and a
		-- hanging hose at the back, dark chuck, long silver bit with a chisel point
		grip = tp("Grip", Vector3.new(1.7, 0.16, 0.16), CFrame.new(0, 0, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		for sx = -1, 1, 2 do
			tp("GripRubber", Vector3.new(0.34, 0.26, 0.26), CFrame.new(sx * 0.7, 0, 0), RUBBER, Enum.Material.Rubber, Enum.PartType.Cylinder)
			tp("GripCap", Vector3.new(0.06, 0.3, 0.3), CFrame.new(sx * 0.88, 0, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		tp("Neck", Vector3.new(0.34, 0.36, 0.3), CFrame.new(0, -0.2, 0), DARK, Enum.Material.Metal)
		tp("Body", Vector3.new(0.72, 1.05, 0.72), CFrame.new(0, -0.88, 0), P.Orange, Enum.Material.SmoothPlastic)
		tp("BodyCap", Vector3.new(0.78, 0.12, 0.78), CFrame.new(0, -0.38, 0), DARK, Enum.Material.Metal)
		tp("Stripe", Vector3.new(0.76, 0.1, 0.76), CFrame.new(0, -0.75, 0), DARK, Enum.Material.SmoothPlastic)
		tp("Exhaust", Vector3.new(0.14, 0.32, 0.26), CFrame.new(-0.41, -1.0, 0), DARK, Enum.Material.Metal)
		tp("Inlet", Vector3.new(0.18, 0.18, 0.2), CFrame.new(0, -0.62, 0.43), DARK, Enum.Material.Metal)
		local pts = { Vector3.new(0, -0.62, 0.52), Vector3.new(0, -0.78, 0.76), Vector3.new(0.04, -1.12, 0.92), Vector3.new(0.1, -1.55, 0.95), Vector3.new(0.16, -1.95, 0.8), Vector3.new(0.2, -2.25, 0.55) }
		for i = 1, #pts - 1 do
			hose("Hose", pts[i], pts[i + 1], 0.13, RUBBER)
		end
		rod("Collar", 0.24, 0.38, Vector3.new(0, -1.5, 0), Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
		rod("Shaft", 1.05, 0.13, Vector3.new(0, -2.12, 0), STEEL, Enum.Material.Metal)
		-- flat chisel blade at the contact point (bottom at TipY)
		tp("Bit", Vector3.new(0.17, 0.3, 0.06), CFrame.new(0, -2.77, 0), STEEL, Enum.Material.Metal)
	else
		local steel = toolId == "SteelHammer"
		grip = tp("Grip", Vector3.new(0.45, 1.1, 0.45), CFrame.new(0, 0, 0), RUBBER, Enum.Material.Rubber)
		tp("Handle", Vector3.new(0.36, 2.6, 0.36), CFrame.new(0, 1.8, 0), P.Orange, Enum.Material.SmoothPlastic)
		local headColor = if steel then Color3.fromRGB(64, 68, 74) else Color3.fromRGB(150, 154, 160)
		local hs = if steel then Vector3.new(2.5, 1.3, 1.3) else Vector3.new(2.2, 1.15, 1.15)
		tp("Head", hs, CFrame.new(0, 3.35, 0), headColor, Enum.Material.Metal)
		-- striking faces and a collar make the hammer shape obvious from any side
		tp("FaceL", Vector3.new(0.25, hs.Y * 1.08, hs.Z * 1.08), CFrame.new(-hs.X / 2, 3.35, 0), Color3.fromRGB(205, 208, 214), Enum.Material.Metal)
		tp("FaceR", Vector3.new(0.25, hs.Y * 1.08, hs.Z * 1.08), CFrame.new(hs.X / 2, 3.35, 0), Color3.fromRGB(205, 208, 214), Enum.Material.Metal)
		tp("Collar", Vector3.new(0.55, 0.3, 0.55), CFrame.new(0, 2.65, 0), DARK, Enum.Material.Metal)
	end
	local dims = if kitTool then KIT_DIMS[toolId] else (World.ToolDims[toolId] or World.ToolDims.Hammer)
	m:SetAttribute("Scale", sc)
	for k, v in dims do
		m:SetAttribute(k, v * sc)
	end
	-- classic Welds with explicit offsets (deterministic; also what the offline preview solves)
	for _, p in m:GetChildren() do
		if p ~= grip and p:IsA("BasePart") then
			local w = Instance.new("Weld")
			w.C0 = grip.CFrame:ToObjectSpace(p.CFrame)
			w.C1 = CFrame.identity
			w.Part0 = grip
			w.Part1 = p
			w.Parent = p
		end
	end
	m.PrimaryPart = grip
	return m
end

-- Lobby -------------------------------------------------------------------------------------

export type Alcove = { Index: number, Root: Model, Plate: TextLabel, Slots: { CFrame } }

-- The public lobby lives in LobbyBuilder (V4 section D); same return fields as before:
-- Root, Spawn, Alcoves (Index, Root, Plate, Slots) and Stands.
function World.buildLobby(): { [string]: any }
	return require(script.Parent.LobbyBuilder).build(World.toolModel)
end

-- Arena ------------------------------------------------------------------------------------

-- Match place (Teleport mode): the one arena sits at the place origin instead of far from a lobby.
local arenaAtOrigin = false
function World.useOriginArena()
	arenaAtOrigin = true
end

function World.arenaCenter(slot: number): Vector3
	if arenaAtOrigin and slot == 1 then
		return Vector3.zero
	end
	return Vector3.new(1200 + (slot - 1) * 260, 0, 0)
end

-- The V4 quarry worksite lives in ArenaBuilder (kit pieces in ArenaKit). Returns Root, Center,
-- Spawns, Bays, Tables, PileFolder, MachineFolder (and Hopper).
function World.buildArena(slot: number): { [string]: any }
	-- the kit meshes load in parallel at boot; give stragglers a moment so the first arena uses them
	MeshService.waitReady(6)
	return ArenaBuilder.build(slot, World.arenaCenter(slot))
end

return World
