--!strict
-- Still ViewportFrame thumbnails of the game's own Blender kit models (Rock_* names show a procedural egg) (ReplicatedStorage.Assets.Kit, see
-- shared/KitModels) for catalog rows and previews: the carry basket, a rock, the station tray, the rubble bin,
-- the gallery cabinet. One static render each (no spin, no physics, nothing per frame); the frame owns the
-- clone, so destroying the screen frees it. When the kit model is not loaded the drawn icon is used instead.
-- Never an invented asset id.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local KitModels = require(Shared.KitModels)
local GeodeModel = require(Shared.GeodeModel)
local UI = require(script.Parent.UI)

local ModelThumb = {}

-- kit name -> (yaw degrees, pitch degrees)
local POSE = {
	Basket_Filled = { -24, 22 },
	Basket_Empty = { -24, 22 },
	Rock_03_SquatBoulder = { -30, 18 },
	Station_InputTray = { -28, 28 },
	Station_RubbleBin = { -28, 20 },
	Prop_StoneBin = { -28, 20 },
	Gallery_Cabinet = { -18, 10 },
	Gallery_Shelf = { -18, 12 },
	Gallery_Showcase = { -18, 12 },
}

-- Returns the container (a ViewportFrame, or a frame holding the fallback icon). `size` sizes the fallback icon.
function ModelThumb.make(parent: Instance, kitName: string, fallbackIcon: string, size: number, props: { [string]: any }?): GuiObject
	-- rocks are eggs now (Find The Pet): a procedural spotted egg instead of the quarry rock mesh
	local m: Model? = if string.sub(kitName, 1, 5) == "Rock_" then GeodeModel.rockShell(1, 2, kitName, { Tint = 3 }) else KitModels.clone(kitName)
	if not m then
		local holder = UI.frame(parent, { Name = "Thumb", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		UI.apply(holder, props)
		UI.icon(holder, fallbackIcon, size, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		return holder
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Thumb"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(150, 148, 144)
	vp.LightColor = Color3.fromRGB(255, 244, 228)
	vp.LightDirection = Vector3.new(-0.45, -0.7, 0.55)
	UI.apply(vp, props)
	vp.Parent = parent
	local pose = POSE[kitName] or { -26, 18 }
	m:PivotTo(CFrame.Angles(0, math.rad(pose[1]), 0))
	m.Parent = vp
	local cf, ext = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local radius = ext.Magnitude / 2 * 0.92
	local dist = radius / math.tan(math.rad(15))
	local pitch = math.rad(pose[2])
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, math.sin(pitch) * dist, -math.cos(pitch) * dist), cf.Position)
	return vp
end

return ModelThumb
