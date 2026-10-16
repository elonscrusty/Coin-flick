--!strict
-- The dream pet on show: a giant Void Dragon statue in the lobby with "1 in 1000" on its plinth, so every new player
-- sees the rarest pet in the first minute. Built once at boot from the same procedural pet model the game draws
-- everywhere (shared/PetModel), so it matches the real pet. REPLACE: a hand-made statue mesh from the Blender helper.
--
-- Where: a Part named MapNames.VoidStatueSpot anywhere in the lobby map (the statue faces the Part's LookVector);
-- without one it stands a little in front of the lobby spawn, facing the spawn. When the leaderboard tree has a
-- DragonPerch (server/TreeBoardService), the statue is rebuilt there with no plinth: VoidStatue.perch.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MapNames = require(Shared.MapNames)
local PetModel = require(Shared.PetModel)
local Retention = require(Shared.Retention)

local VoidStatue = {}

VoidStatue.Species = "CosmicDragon" -- Config.Minerals: "Void Dragon", the Space zone's 1 in 1000 chase pet
VoidStatue.Height = 16 -- studs, the dragon alone
VoidStatue.Fallback = CFrame.new(-20, 0, -30) -- from the lobby spawn when the map has no spot
VoidStatue.SignGap = 3 -- studs between the top of the dragon (its bounding box, plus the hover) and the sign's bottom
VoidStatue.Hover = 0.8 -- the client's breathing hover lifts the dragon up to this much (client/VoidStatueFx)

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

local function sign(face: BasePart, top: string, bottom: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StatueSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = face
	type Line = { Name: string, Text: string, Y: number, H: number, Color: Color3 }
	local lines: { Line } = {
		{ Name = "Title", Text = top, Y = 0, H = 0.42, Color = Color3.fromRGB(240, 140, 255) },
		{ Name = "Odds", Text = bottom, Y = 0.4, H = 0.34, Color = Color3.fromRGB(255, 214, 64) },
		{ Name = "Source", Text = Retention.DreamSource, Y = 0.74, H = 0.24, Color = Color3.fromRGB(255, 255, 255) },
	}
	for _, line in lines do
		local l = Instance.new("TextLabel")
		l.Name = line.Name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, line.Y)
		l.Size = UDim2.fromScale(0.92, line.H)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = line.Text
		l.TextColor3 = line.Color
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(30, 20, 60)
		stroke.Parent = l
		l.Parent = gui
	end
end

local function findSpot(root: Instance?): BasePart?
	for _, where in { root, Workspace } do
		if where then
			local p = where:FindFirstChild(MapNames.VoidStatueSpot, true)
			if p and p:IsA("BasePart") then
				return p
			end
		end
	end
	return nil
end

-- Big floating "VOID DRAGON / 1 in 1000" sign over the dragon's head, readable from the spawn (the client pulses it).
-- `at` = the statue's facing, `headY` = the world height of the top of the dragon: the sign's bottom edge sits
-- SignGap studs over it (Studio 2026-10-14: a fixed offset clipped into the head of a Height 30 dragon).
local function floatingSign(model: Model, at: CFrame, headY: number, height: number)
	local w, h = math.max(14, height * 0.9), math.max(6, height * 0.4)
	local centre = CFrame.new(at.Position.X, headY + VoidStatue.SignGap + h / 2, at.Position.Z) * at.Rotation
	local anchor = part(model, "SignAnchor", Enum.PartType.Block, Vector3.new(0.2, 0.2, 0.2), centre, Color3.new(1, 1, 1))
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	local bb = Instance.new("BillboardGui")
	bb.Name = "StatueSign"
	bb.Size = UDim2.fromScale(w, h)
	bb.LightInfluence = 0
	bb.MaxDistance = 600
	bb.Parent = anchor
	type Line = { Name: string, Text: string, Y: number, H: number, Color: Color3 }
	local lines: { Line } = {
		{ Name = "Title", Text = "VOID DRAGON", Y = 0, H = 0.42, Color = Color3.fromRGB(240, 140, 255) },
		{ Name = "Odds", Text = "1 in 1000", Y = 0.4, H = 0.34, Color = Color3.fromRGB(255, 214, 64) },
		{ Name = "Source", Text = Retention.DreamSource, Y = 0.74, H = 0.24, Color = Color3.fromRGB(255, 255, 255) },
	}
	for _, line in lines do
		local l = Instance.new("TextLabel")
		l.Name = line.Name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, line.Y)
		l.Size = UDim2.fromScale(1, line.H)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = line.Text
		l.TextColor3 = line.Color
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(30, 20, 60)
		stroke.Parent = l
		l.Parent = bb
	end
end

-- Builds the statue (once). `root` = the lobby root, `spawn` = the lobby spawn CFrame. Returns the statue model.
-- The spot Part may carry attributes: Height (number, the dragon's height in studs, default VoidStatue.Height) and
-- Plinth (boolean, default true; false = no code plinth, the dragon stands on the spot's top). The client animates
-- it (client/VoidStatueFx: breathing hover, orbiting sparkles, pulsing "1 in 1000").
function VoidStatue.build(root: Instance, spawn: CFrame?, perch: CFrame?, perchHeight: number?): Model?
	local old = root:FindFirstChild("VoidDragonStatue")
	if old then
		return old :: Model
	end
	local spot = if perch then nil else findSpot(root)
	local at: CFrame
	local height = VoidStatue.Height
	local withPlinth = true
	if perch then
		-- on the leaderboard tree's top: no plinth, facing the perch's front
		local p = perch.Position
		local look = Vector3.new(perch.LookVector.X, 0, perch.LookVector.Z)
		at = CFrame.lookAt(p, p + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1)))
		if perchHeight and perchHeight > 2 and perchHeight < 200 then
			height = perchHeight
		end
		withPlinth = false
	elseif spot then
		local p = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0) -- on top of the spot
		local look = Vector3.new(spot.CFrame.LookVector.X, 0, spot.CFrame.LookVector.Z)
		at = CFrame.lookAt(p, p + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, 1)))
		local h = spot:GetAttribute("Height")
		if type(h) == "number" and h > 2 and h < 200 then
			height = h
		end
		withPlinth = spot:GetAttribute("Plinth") ~= false
		spot.Transparency = 1
		spot.CanCollide = false
	else
		local s = spawn or CFrame.new()
		local p = (s * VoidStatue.Fallback).Position - Vector3.new(0, 3.5, 0) -- the lobby Spawn sits 3.5 above the pad
		local face = Vector3.new(s.Position.X, p.Y, s.Position.Z)
		at = CFrame.lookAt(p, if (face - p).Magnitude > 0.1 then face else p + Vector3.new(0, 0, 1))
	end
	local k = height / VoidStatue.Height -- the plinth grows with the dragon
	local model = Instance.new("Model")
	model.Name = "VoidDragonStatue"
	local top = 0
	local glowAt: BasePart
	if withPlinth then
		-- plinth: chunky low-poly stone in two steps, a gold rim and the sign on the front
		local stone, stoneDark = Color3.fromRGB(88, 78, 140), Color3.fromRGB(60, 52, 104)
		part(model, "Base", Enum.PartType.Block, Vector3.new(16, 1.6, 16) * k, at * CFrame.new(0, 0.8 * k, 0), stoneDark, Enum.Material.Slate)
		local plinth = part(model, "Plinth", Enum.PartType.Block, Vector3.new(12, 4, 12) * k, at * CFrame.new(0, 3.6 * k, 0), stone, Enum.Material.Slate)
		part(model, "Rim", Enum.PartType.Block, Vector3.new(12.6, 0.6, 12.6) * k, at * CFrame.new(0, 5.9 * k, 0), Color3.fromRGB(255, 204, 64), Enum.Material.Foil)
		local face = part(model, "SignFace", Enum.PartType.Block, Vector3.new(10, 3, 0.2) * k, at * CFrame.new(0, 3.6 * k, -6.1 * k), Color3.fromRGB(40, 30, 80))
		face.CanCollide = false
		sign(face, "VOID DRAGON", "1 in 1000")
		plinth:SetAttribute("Hint", Retention.DreamHint)
		model.PrimaryPart = plinth
		glowAt = plinth
		top = 6.2 * k
	else
		local base = part(model, "Base", Enum.PartType.Block, Vector3.new(1, 0.2, 1), at, Color3.new(1, 1, 1))
		base.Transparency = 1
		base.CanCollide = false
		base.CanQuery = false
		model.PrimaryPart = base
		glowAt = base
	end
	local headY = at.Position.Y + top + height -- the dragon's top; measured from its parts below when it builds
	local ok, dragon = pcall(PetModel.build, { Mineral = VoidStatue.Species, Rarity = "Legendary", Modifier = "Natural", Formation = "Spire", Seed = 1000, Mass = 2 }, { NoLight = false })
	if ok and dragon then
		local d = dragon :: Model
		PetModel.fitHeight(d, height, height * 1.4)
		d.Name = "Dragon"
		d:PivotTo(at * CFrame.new(0, top, 0))
		d:SetAttribute("Home", d:GetPivot()) -- the client's breathing hover moves it around this
		d.Parent = model
		local bcf, bsize = d:GetBoundingBox()
		headY = bcf.Position.Y + bsize.Y / 2 + VoidStatue.Hover
	else
		warn("[VoidStatue] dragon model failed: " .. tostring(dragon))
	end
	floatingSign(model, at, headY, height)
	-- a purple light beam straight up from over the dragon, seen from anywhere in the lobby (neon, soft, always day)
	local beamH = 160
	for i, b in { { W = 2.2, T = 0.45 }, { W = 5, T = 0.8 } } do
		local beam = part(model, "Beam" .. i, Enum.PartType.Cylinder, Vector3.new(beamH, b.W, b.W), CFrame.new(at.Position.X, headY + beamH / 2, at.Position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(118, 72, 255), Enum.Material.Neon) -- deep void violet (190,110,255 read as pink in the lobby shots)
		beam.Transparency = b.T
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
	end
	-- a soft purple glow so it reads from across the lobby (always day: a soft light, not a night effect)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 100, 255)
	light.Range = math.min(60, 22 * k)
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = glowAt
	model:SetAttribute("Height", height)
	model:SetAttribute("Top", top)
	model.Parent = root
	return model
end

-- Moves the statue onto the leaderboard tree: the old one (anywhere under `root` or the Workspace) is replaced by a
-- plinth-less dragon standing at `cf` (client/VoidStatueFx picks the new one up). Returns the new statue.
function VoidStatue.perch(root: Instance, cf: CFrame, height: number?): Model?
	for _, where in { root, Workspace } do
		local old = where:FindFirstChild("VoidDragonStatue", true)
		if old then
			old:Destroy()
		end
	end
	local spot = findSpot(root)
	if spot then
		spot.Transparency = 1
		spot.CanCollide = false
	end
	return VoidStatue.build(root, nil, cf, height)
end

return VoidStatue
