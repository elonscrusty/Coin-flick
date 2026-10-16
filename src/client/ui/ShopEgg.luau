--!strict
-- Shop egg art: each of the three shop eggs gets its own look so the Eggs tab reads like a pet-game shop and not a pile
-- of the same egg in three tints. Basic = cream egg with soft spots and a gloss, Rare = sapphire egg with a gold band
-- and gems, Mythic = violet egg with glowing cracks and sparks orbiting it. The body is the game's own egg
-- (GeodeModel.rockShell: the owner's / Blender meshes when loaded, Parts otherwise), the trims are small Parts on its
-- surface, so no asset ids are needed. An owner picture (RobuxConfig egg Image id, 0 = none) replaces the 3D egg.
-- The egg idles with a slow spin and bob; a soft halo disc sits behind it.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GeodeModel = require(Shared:WaitForChild("GeodeModel"))
local UI = require(script.Parent:WaitForChild("UI"))

local ShopEgg = {}

export type Look = {
	Tint: number, -- EGG_TINTS index for the body
	Body: Color3?, -- the body colour (the smooth kit egg or Parts; the textured pile eggs are skipped then)
	Spots: boolean, -- keep GeodeModel's own spot pattern
	Band: Color3?, -- a metal band round the middle
	Gems: Color3?, -- gems on the band
	Cracks: Color3?, -- glowing crack lines
	Sparks: Color3?, -- orbiting sparks
	Halo: Color3, -- the disc behind the egg
}

local LOOKS: { [string]: Look } = {
	BasicEgg = { Tint = 1, Spots = true, Halo = Color3.fromRGB(255, 236, 200) },
	RareEgg = {
		Tint = 2, Spots = false, Body = Color3.fromRGB(70, 140, 255), Band = Color3.fromRGB(255, 206, 60),
		Gems = Color3.fromRGB(120, 250, 255), Halo = Color3.fromRGB(150, 220, 255),
	},
	MythicEgg = {
		Tint = 5, Spots = false, Body = Color3.fromRGB(118, 60, 220), Cracks = Color3.fromRGB(110, 255, 255),
		Sparks = Color3.fromRGB(255, 230, 90), Halo = Color3.fromRGB(210, 170, 255),
	},
}

function ShopEgg.look(eggId: string): Look
	return LOOKS[eggId] or LOOKS.BasicEgg
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, ball: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = "Trim"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if ball then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end

-- point and outward normal on the egg ellipsoid (half width a, half height b): th from the top, ph round
local function eggPoint(a: number, b: number, th: number, ph: number): (Vector3, Vector3)
	local d = Vector3.new(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))
	return Vector3.new(d.X * a, d.Y * b, d.Z * a), Vector3.new(d.X / a, d.Y / b, d.Z / a).Unit
end

-- The egg model with its trims; the model is centred on the origin.
function ShopEgg.model(eggId: string, variant: number): Model
	local look = ShopEgg.look(eggId)
	local D = 2
	-- the smooth kit egg or Parts (never the owner's textured pile eggs: their texture would hide the colour)
	local m = GeodeModel.rockShell(variant, D, "ShopEgg", { Tint = look.Tint, Low = not look.Spots, Color = look.Body, NoTexture = look.Body ~= nil })
	local _, ext = m:GetBoundingBox()
	local A, B = ext.X / 2 / 1.1, ext.Y / 2 / 1.25 -- the Bounds part pads the egg by 1.1 x 1.25
	local trims = Instance.new("Model")
	trims.Name = "Trims"
	trims.Parent = m
	-- gloss: a soft white highlight high on the shoulder (every egg)
	local gp, gn = eggPoint(A, B, 0.55, 2.3)
	part(trims, Vector3.new(0.22 * D, 0.12 * D, 0.06 * D), CFrame.lookAt(gp, gp + gn) * CFrame.new(0, 0, -0.01 * D), Color3.new(1, 1, 1), Enum.Material.Neon, true)
	if look.Band then
		-- a metal band round the middle, slightly wider than the egg
		local r = A * 1.04
		part(trims, Vector3.new(2 * r, 0.12 * D, 2 * r), CFrame.new(0, -0.02 * B, 0), look.Band, Enum.Material.Metal, true)
		local n = 6
		for i = 1, n do
			local ph = (i - 1) / n * math.pi * 2
			local p, nrm = eggPoint(A * 1.06, B, math.pi / 2 + 0.02, ph)
			local gem = part(trims, Vector3.new(0.1 * D, 0.1 * D, 0.1 * D), CFrame.lookAt(p, p + nrm), look.Gems or look.Band :: Color3, Enum.Material.Neon, true)
			gem.Name = "Gem"
		end
		-- a crown of small gems near the top
		for i = 1, 5 do
			local ph = (i - 1) / 5 * math.pi * 2 + 0.3
			local p, nrm = eggPoint(A, B, 0.75, ph)
			part(trims, Vector3.new(0.07 * D, 0.07 * D, 0.07 * D), CFrame.lookAt(p, p + nrm), look.Band :: Color3, Enum.Material.Metal, true)
		end
	end
	if look.Cracks then
		-- glowing zigzag cracks: short thin slabs laid along the surface
		local rng = Random.new(77)
		for c = 1, 6 do
			local th = rng:NextNumber(0.5, 1.7)
			local ph = (c - 1) / 6 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local dir = if c % 2 == 0 then 1 else -1
			for _ = 1, 3 do
				local th2 = th + rng:NextNumber(0.12, 0.28)
				local ph2 = ph + dir * rng:NextNumber(0.2, 0.45)
				dir = -dir
				local p1 = eggPoint(A, B, th, ph)
				local p2 = eggPoint(A, B, th2, ph2)
				local mid, nrm = eggPoint(A, B, (th + th2) / 2, (ph + ph2) / 2)
				local len = (p2 - p1).Magnitude
				local cf = CFrame.lookAt(mid, mid + nrm, (p2 - p1).Unit) * CFrame.new(0, 0, -0.015 * D)
				part(trims, Vector3.new(0.025 * D, len * 1.08, 0.04 * D), cf, look.Cracks :: Color3, Enum.Material.Neon)
				th, ph = th2, ph2
				if th > 2.4 then
					break
				end
			end
		end
	end
	if look.Sparks then
		-- sparks on a tilted ring round the egg; ShopEgg.view spins the ring
		local ring = Instance.new("Model")
		ring.Name = "Sparks"
		local n = 7
		for i = 1, n do
			local a = (i - 1) / n * math.pi * 2
			local r = A * 1.22
			local s = (0.06 + 0.03 * (i % 2)) * D
			local p = Vector3.new(math.cos(a) * r, math.sin(a * 3) * 0.08 * D, math.sin(a) * r)
			part(ring, Vector3.new(s, s, s), CFrame.new(p), if i % 3 == 0 then (look.Cracks or look.Sparks) :: Color3 else look.Sparks :: Color3, Enum.Material.Neon, true)
		end
		local pivot = part(ring, Vector3.new(0.1, 0.1, 0.1), CFrame.new(), Color3.new(), Enum.Material.SmoothPlastic)
		pivot.Transparency = 1
		pivot.Name = "Pivot"
		ring.PrimaryPart = pivot
		ring:PivotTo(CFrame.Angles(math.rad(-18), 0, math.rad(10)))
		ring.Parent = m
	end
	return m
end

export type ViewOpts = {
	Yaw: number?, -- degrees
	Pitch: number?, -- degrees
	Spin: boolean?, -- idle spin + bob (default true)
	Halo: boolean?, -- the disc behind the egg (default true)
	Variant: number?, -- GeodeModel pattern variant
	Image: number?, -- an owner picture instead of the 3D egg (0 / nil = none)
}

-- The egg in a still ViewportFrame (or an ImageLabel when the owner gave a picture) with a halo disc behind it.
function ShopEgg.view(parent: Instance, eggId: string, props: { [string]: any }?, opts: ViewOpts?): GuiObject
	local o: ViewOpts = opts or {}
	local look = ShopEgg.look(eggId)
	local host = Instance.new("Frame")
	host.Name = "Egg"
	host.BackgroundTransparency = 1
	host.ZIndex = 5
	UI.apply(host, props)
	host.Parent = parent
	if o.Halo ~= false then
		local halo = Instance.new("Frame")
		halo.Name = "Halo"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.54)
		halo.Size = UDim2.fromScale(0.84, 0.84)
		halo.BackgroundColor3 = look.Halo
		halo.BackgroundTransparency = 0.45
		halo.BorderSizePixel = 0
		halo.ZIndex = host.ZIndex
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = halo
		local glow = Instance.new("UIStroke")
		glow.Color = look.Halo
		glow.Thickness = 6
		glow.Transparency = 0.6
		glow.Parent = halo
		halo.Parent = host
	end
	if o.Image and o.Image > 0 then
		local img = Instance.new("ImageLabel")
		img.Name = "Picture"
		img.BackgroundTransparency = 1
		img.Image = "rbxassetid://" .. tostring(o.Image)
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromScale(1, 1)
		img.ZIndex = host.ZIndex + 1
		img.Parent = host
		return host
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 168, 165)
	vp.LightColor = Color3.fromRGB(255, 246, 230)
	vp.LightDirection = Vector3.new(-0.4, -0.75, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.ZIndex = host.ZIndex + 1
	vp.Parent = host
	local m = ShopEgg.model(eggId, o.Variant or 1)
	local yaw0 = math.rad(o.Yaw or -20)
	local pitch0 = math.rad(o.Pitch or 0)
	m:PivotTo(CFrame.Angles(0, yaw0, pitch0))
	m.Parent = vp
	local cf, ext = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 28
	cam.Parent = vp
	vp.CurrentCamera = cam
	local radius = ext.Magnitude / 2 * 0.8
	local dist = radius / math.tan(math.rad(14))
	local p = math.rad(14)
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, math.sin(p) * dist, -math.cos(p) * dist), cf.Position)
	if o.Spin ~= false then
		local t = 0
		local sparks = m:FindFirstChild("Sparks")
		local conn = RunService.RenderStepped:Connect(function(dt: number)
			t += dt
			m:PivotTo(CFrame.new(0, math.sin(t * 2.2) * 0.04, 0) * CFrame.Angles(0, yaw0 + math.sin(t * 0.9) * 0.35, pitch0))
			if sparks and sparks:IsA("Model") then
				sparks:PivotTo(CFrame.Angles(math.rad(-18), t * 1.6, math.rad(10)))
			end
		end)
		host.Destroying:Connect(function()
			conn:Disconnect()
		end)
	end
	return host
end

return ShopEgg
