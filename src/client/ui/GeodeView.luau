--!strict
-- ViewportFrame showing one pet (GeodeModel.build -> PetModel), framed from the model's bounding box (no
-- cropping). The pet faces the camera (-Z), turned about 22 degrees so its round 3D shape reads; manual drag turns
-- it (no forced spin). A WorldModel holds the parts. Bright, soft light for the pastel look.
-- The hatch reveal (RevealView), results, collection and inspect panels all use this same view.

local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GeodeModel = require(Shared.GeodeModel)

local GeodeView = {}

local FOV = 32
local BASE_YAW = math.rad(-22) -- a slight 3/4 turn so the round body reads (a flat front view looks like a sticker)
GeodeView.Yaw = BASE_YAW
GeodeView.Ambient = Color3.fromRGB(150, 146, 160)
GeodeView.LightColor = Color3.fromRGB(255, 244, 228)
GeodeView.LightDirection = Vector3.new(-0.45, -0.6, 0.66)

-- The pet's own box: see-through effect parts (the wide rarity aura ring on the ground, glow discs) are left out,
-- or a small pet is framed for the size of its ring and shows up tiny in its card.
local function bodyBox(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 and d.Name ~= "Aura" and d.Name ~= "TypeGlow" then
			local half = d.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						lo = lo:Min(p)
						hi = hi:Max(p)
					end
				end
			end
		end
	end
	if lo.X > hi.X then
		local cf, size = model:GetBoundingBox()
		return cf.Position, size
	end
	return (lo + hi) / 2, hi - lo
end

-- Camera on the -Z side (the pet faces -Z), slightly above, far enough that the whole
-- bounding sphere fits with a margin.
function GeodeView.frame(cam: Camera, model: Model, margin: number?)
	local centre, size = bodyBox(model)
	local radius = size.Magnitude / 2 * (margin or 0.9) -- the box diagonal over-states the round pet, 0.9 still fits
	local dist = radius / math.tan(math.rad(FOV / 2))
	local target = centre
	local pitch = math.rad(16)
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(target + Vector3.new(0, math.sin(pitch) * dist, -math.cos(pitch) * dist), target)
end

function GeodeView.make(parent: Instance, spec, props: { [string]: any }?, draggable: boolean?): (ViewportFrame, Model, Camera)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = GeodeView.Ambient
	vp.LightColor = GeodeView.LightColor
	vp.LightDirection = GeodeView.LightDirection
	local backing = false
	if props then
		for k, v in props do
			if k == "Backing" then
				backing = v == true
			else
				(vp :: any)[k] = v
			end
		end
	end
	if backing then
		-- a soft cream plate behind the pet, so blue and green pets don't melt into the blue menu
		vp.BackgroundColor3 = Color3.fromRGB(255, 248, 232)
		vp.BackgroundTransparency = 0.1
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = vp
	end
	vp.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = GeodeModel.build(spec, { Scale = 1 })
	-- the evolve force-field shell reads as a solid ball in a viewport; picture cards keep the sparkles only
	local aura = model:FindFirstChild("EvolveAura")
	if aura and aura:IsA("BasePart") then
		aura.Transparency = 1
	end
	model.Parent = world
	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam
	GeodeView.frame(cam, model)
	model:PivotTo(CFrame.Angles(0, BASE_YAW, 0))
	if draggable then
		local yaw = BASE_YAW
		local dragging: InputObject? = nil
		local last = Vector2.zero
		vp.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = input
				last = Vector2.new(input.Position.X, input.Position.Y)
			end
		end)
		local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseMovement) and vp.Parent then
				local pos = Vector2.new(input.Position.X, input.Position.Y)
				yaw = math.clamp(yaw + (pos.X - last.X) * 0.01, -1.3, 1.3)
				last = pos
				model:PivotTo(CFrame.Angles(0, yaw, 0))
			end
		end)
		local c2 = UserInputService.InputEnded:Connect(function(input)
			if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = nil
			end
		end)
		vp.Destroying:Connect(function()
			c1:Disconnect()
			c2:Disconnect()
		end)
	end
	return vp, model, cam
end

return GeodeView
