--!strict
-- 3D picture of a shop item (hand tool or machine) in a ViewportFrame.
-- Source order: ReplicatedStorage.Assets.Kit.<name> (Blender kit model, when marked Ready), then
-- ReplicatedStorage.Assets.Previews.<id> (the Part / uploaded-mesh model the server builds from the
-- same factories as the world, see server/PreviewKit), then a drawn icon. Never an invented asset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.UI)

local ItemView = {}

local GearKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearKit")) -- Gear_<Id> first, old names after
local FALLBACK_ICON = {
	Hammer = "boostLuck", SteelHammer = "boostCoins", Jackhammer = "boostSpeed",
	AutoCracker = "queue", HydraulicPress = "egg", IndustrialCrusher = "sparkle",
}

local TOOLS = { Hammer = true, SteelHammer = true, Jackhammer = true }

-- Shop-picture finish for the upgrade tools (Studio: the Golden Mallet read as recoloured wood, the Rainbow Tapper
-- as a plain grey drill). Only untextured parts are tinted, so a real textured mesh keeps its own look; the handle,
-- grip rubber and drill bit stay as they are. Picture only: the held tool is untouched.
local GOLD = Color3.fromRGB(255, 196, 46)
local function finish(model: Instance, id: string)
	if id ~= "SteelHammer" and id ~= "Jackhammer" then
		return
	end
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d:FindFirstChildOfClass("SurfaceAppearance") == nil
			and not (d:IsA("MeshPart") and d.TextureID ~= "") then
			local n = string.lower(d.Name)
			if not (string.find(n, "wood") or string.find(n, "rubber") or string.find(n, "grip") or string.find(n, "handle") or n == "bit") then
				table.insert(parts, d)
			end
		end
	end
	table.sort(parts, function(a, b)
		return a.Position.Y > b.Position.Y
	end)
	for i, p in parts do
		if id == "SteelHammer" then
			p.Color = GOLD:Lerp(Color3.fromRGB(255, 236, 140), if string.find(string.lower(p.Name), "light") then 0.45 else 0)
			p.Material = Enum.Material.Metal
			p.Reflectance = 0.15
		else
			p.Color = Color3.fromHSV(((i - 1) / math.max(#parts, 1)) * 0.85, 0.75, 1)
			p.Material = Enum.Material.SmoothPlastic
		end
	end
end

local function template(id: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local kit = assets:FindFirstChild("Kit")
	if kit then
		for _, n in GearKit.kitNames(id) do
			local m = kit:FindFirstChild(n)
			if m and m:IsA("Model") and m:GetAttribute("Ready") then
				return m
			end
		end
	end
	local pv = assets:FindFirstChild("Previews")
	local m = pv and pv:FindFirstChild(id)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

-- Returns the viewport, or a drawn icon frame when no model exists. `props` go to the container.
-- `iconSize` sizes the drawn fallback icon to the slot (a fixed 56 spilled out of the smaller shop-row thumbs).
function ItemView.make(parent: Instance, id: string, props: { [string]: any }?, iconSize: number?): GuiObject
	local src = template(id)
	if not src then
		local holder = UI.frame(parent, { BackgroundTransparency = 1 })
		if props then
			for k, v in props do
				(holder :: any)[k] = v
			end
		end
		UI.icon(holder, FALLBACK_ICON[id] or "star", iconSize or 56, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		return holder
	end
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 166, 160)
	vp.LightColor = Color3.fromRGB(255, 244, 228)
	vp.LightDirection = Vector3.new(-0.4, -0.6, 0.7)
	if props then
		for k, v in props do
			(vp :: any)[k] = v
		end
	end
	vp.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local model = src:Clone()
	finish(model, id)
	-- "Jackhammer" (Rainbow Tapper) has a lower-case h: it missed the tool pose and showed flat and small
	local isTool = TOOLS[id] == true
	-- tools stand diagonally like the sheet; machines face the camera (front is -Z)
	local turn = if isTool then CFrame.Angles(0, math.rad(-30), math.rad(32)) else CFrame.Angles(0, math.rad(-24), 0)
	model.Parent = world
	model:PivotTo(turn)
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.Parent = vp
	vp.CurrentCamera = cam
	local radius = size.Magnitude / 2 * 0.95
	local dist = radius / math.tan(math.rad(35 / 2))
	cam.FieldOfView = 35
	local target = cf.Position
	cam.CFrame = CFrame.lookAt(target + Vector3.new(0, math.sin(math.rad(14)) * dist, -math.cos(math.rad(14)) * dist), target)
	return vp
end

return ItemView
