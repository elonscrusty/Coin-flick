--!strict
-- Little 3D icons for shop cards, drawn in ViewportFrames from the SAME chunky
-- parts the game uses (real hat models, the real helper blob, gold coins), so
-- icons match the world on every device (no OS emoji).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HatBuilder = require(ReplicatedStorage.Shared.Builders.HatBuilder)

local Icons = {}

local COIN_GOLD = Color3.fromRGB(255, 200, 50)
local COIN_RIM = Color3.fromRGB(225, 150, 30)
local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder upright (flat coin)

type Make = (props: { [string]: any }) -> Part

local function make(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(part :: any)[k] = v
	end
	return part
end

local function add(model: Model, props: { [string]: any })
	make(props).Parent = model
end

-- A flat gold coin lying down at `at`, with a darker rim and a raised face.
local function coin(model: Model, at: CFrame, diameter: number, face: Color3?, rim: Color3?)
	add(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, diameter, diameter),
		CFrame = at * UP,
		Color = rim or COIN_RIM,
	})
	add(model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, diameter * 0.78, diameter * 0.78),
		CFrame = at * UP,
		Color = face or COIN_GOLD,
	})
end

local function helperModel(model: Model, def: { id: string, body: Color3, cap: Color3 })
	local skin = Color3.fromRGB(255, 220, 180)
	local dark = Color3.fromRGB(20, 20, 30)
	local wide = def.id == "chompy"
	add(model, {
		Shape = Enum.PartType.Ball,
		Size = if wide then Vector3.new(2.5, 1.8, 2.2) else Vector3.one * 2,
		CFrame = CFrame.new(),
		Color = def.body,
	})
	add(model, { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(0, 1.5, 0), Color = skin })
	for _, x in { -0.35, 0.35 } do
		add(
			model,
			{ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.35, CFrame = CFrame.new(x, 1.6, -0.7), Color = dark }
		)
	end
	if def.id == "twinkle" then
		-- star over the head instead of a cap
		for k = 0, 1 do
			add(model, {
				Size = Vector3.new(1.8, 0.3, 0.3),
				CFrame = CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, k * math.pi / 2),
				Color = def.cap,
			})
			add(model, {
				Size = Vector3.new(1.3, 0.25, 0.25),
				CFrame = CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.pi / 4 + k * math.pi / 2),
				Color = Color3.fromRGB(255, 255, 255),
			})
		end
	elseif def.id == "king" then
		for k = 0, 4 do
			local a = k * math.pi * 2 / 5
			add(model, {
				Size = Vector3.new(0.3, 0.7, 0.3),
				CFrame = CFrame.new(math.cos(a) * 0.55, 2.6, math.sin(a) * 0.55),
				Color = def.cap,
			})
		end
		add(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.45, 1.5, 1.5),
			CFrame = CFrame.new(0, 2.25, 0) * UP,
			Color = def.cap,
		})
	else
		add(model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 1.5, 1.5),
			CFrame = CFrame.new(0, 2.25, 0) * UP,
			Color = def.cap,
		})
	end
	if def.id == "zippy" then -- lightning badge on the belly
		local yellow = Color3.fromRGB(255, 215, 40)
		add(model, {
			Size = Vector3.new(0.35, 0.8, 0.2),
			CFrame = CFrame.new(0.15, 0.35, -1.0) * CFrame.Angles(0, 0, -0.4),
			Color = yellow,
		})
		add(model, {
			Size = Vector3.new(0.35, 0.8, 0.2),
			CFrame = CFrame.new(-0.15, -0.3, -1.0) * CFrame.Angles(0, 0, -0.4),
			Color = yellow,
		})
	elseif def.id == "chompy" then -- big grin with teeth
		add(model, { Size = Vector3.new(0.9, 0.35, 0.2), CFrame = CFrame.new(0, 1.2, -0.78), Color = dark })
		for _, x in { -0.25, 0.25 } do
			add(model, {
				Size = Vector3.new(0.22, 0.2, 0.2),
				CFrame = CFrame.new(x, 1.32, -0.86),
				Color = Color3.fromRGB(255, 255, 255),
			})
		end
	elseif def.id == "twinkle" then -- little sparkles on the body
		for _, p in { Vector3.new(-0.7, 0.3, -0.8), Vector3.new(0.6, -0.4, -0.85) } do
			add(model, { Size = Vector3.one * 0.3, CFrame = CFrame.new(p), Color = def.cap })
		end
	end
end

local BUILD: { [string]: (Model) -> () } = {
	moreCoins = function(m)
		for i = 0, 2 do
			coin(m, CFrame.new((i - 1) * 0.25, i * 0.42, 0) * CFrame.Angles(0, i * 0.5, 0), 2)
		end
	end,
	bigCoins = function(m)
		coin(m, CFrame.new(-0.6, 0, 0) * CFrame.Angles(0, 0, 0.25), 3)
		coin(m, CFrame.new(1.6, -0.3, 0.6), 1.3)
	end,
	luck = function(m) -- four-leaf clover, standing up so it faces the camera
		local green = Color3.fromRGB(70, 200, 90)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			add(m, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.4, 1.4, 0.45),
				CFrame = CFrame.new(math.cos(a) * 0.7, math.sin(a) * 0.7 + 0.4, 0),
				Color = green,
			})
		end
		add(m, {
			Size = Vector3.new(0.25, 1.5, 0.25),
			CFrame = CFrame.new(0.25, -0.9, 0) * CFrame.Angles(0, 0, 0.3),
			Color = Color3.fromRGB(50, 150, 60),
		})
	end,
	speed = function(m) -- stopwatch
		local at = CFrame.Angles(math.pi / 2.4, 0, 0)
		coin(m, at, 2.6, Color3.fromRGB(255, 255, 255), Color3.fromRGB(235, 70, 70))
		add(m, {
			Size = Vector3.new(0.18, 0.12, 1.0),
			CFrame = at * CFrame.new(0.25, 0.3, -0.3) * CFrame.Angles(0, -0.5, 0),
			Color = Color3.fromRGB(45, 30, 20),
		})
		add(m, {
			Size = Vector3.new(0.5, 0.4, 0.5),
			CFrame = at * CFrame.new(0, 0.1, -1.55),
			Color = Color3.fromRGB(235, 70, 70),
		})
	end,
	doubleCash = function(m)
		coin(m, CFrame.new(-0.7, 0, 0) * CFrame.Angles(math.pi / 2.4, 0, 0), 2.2)
		coin(m, CFrame.new(0.7, 0, 0.3) * CFrame.Angles(math.pi / 2.4, 0, 0), 2.2)
	end,
	autoFlip = function(m)
		coin(m, CFrame.new(0, 0.6, 0) * CFrame.Angles(math.pi / 2.6, 0, 0), 2.2)
		for i = 0, 5 do -- gear
			local a = i * math.pi / 3
			add(m, {
				Size = Vector3.new(0.5, 0.4, 0.5),
				CFrame = CFrame.new(math.cos(a) * 1.3, -1, math.sin(a) * 1.3) * CFrame.Angles(0, -a, 0),
				Color = Color3.fromRGB(140, 150, 170),
			})
		end
		add(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2.3, 2.3),
			CFrame = CFrame.new(0, -1, 0) * UP,
			Color = Color3.fromRGB(160, 170, 190),
		})
	end,
	helperSlot = function(m)
		helperModel(m, { id = "buddy", body = Color3.fromRGB(90, 200, 255), cap = Color3.fromRGB(255, 90, 90) })
		local green = Color3.fromRGB(70, 210, 110)
		add(m, { Size = Vector3.new(1.4, 0.45, 0.45), CFrame = CFrame.new(1.8, 2.2, -0.3), Color = green })
		add(m, { Size = Vector3.new(0.45, 1.4, 0.45), CFrame = CFrame.new(1.8, 2.2, -0.3), Color = green })
	end,
}

-- Frames the model so it fills the icon, looking down at it a little.
local function frame(viewport: ViewportFrame, model: Model, yaw: number)
	local box, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local camera = viewport.CurrentCamera or Instance.new("Camera")
	if camera.Parent ~= viewport then
		camera.FieldOfView = 30
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 1.02
	local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-22), 0, 0)
	local center = box.Position
	camera.CFrame = CFrame.new(center - dir.LookVector * distance, center)
	viewport:SetAttribute("Distance", distance)
	viewport:SetAttribute("Center", center)
end

local function viewport(name: string, build: (Model) -> (), yaw: number?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = name
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.fromRGB(255, 250, 235)
	vp.LightDirection = Vector3.new(-0.6, -1, -0.5)
	local model = Instance.new("Model")
	model.Name = "Icon"
	build(model)
	model.Parent = vp
	vp:SetAttribute("Yaw", yaw or math.rad(200))
	frame(vp, model, yaw or math.rad(200))
	return vp
end

function Icons.hat(id: string): ViewportFrame?
	if not HatBuilder.has(id) then
		return nil
	end
	return viewport(`Hat_{id}`, function(m)
		local hat = HatBuilder.build(id, make :: Make)
		if hat then
			for _, part in hat:GetChildren() do
				part.Parent = m
			end
			hat:Destroy()
		end
	end)
end

function Icons.helper(def: Config.HelperDef): ViewportFrame
	return viewport(`Helper_{def.id}`, function(m)
		helperModel(m, def)
	end, math.rad(160))
end

function Icons.thing(key: string): ViewportFrame?
	local build = BUILD[key]
	if build then
		return viewport(`Icon_{key}`, build)
	end
	local skin = nil
	for _, s in Config.Skins do
		if s.id == key then
			skin = s
		end
	end
	if skin then
		local face = skin.coin
		return viewport(`Skin_{key}`, function(m)
			coin(m, CFrame.Angles(math.pi / 2.4, 0, 0), 2.6, face, face:Lerp(Color3.new(0, 0, 0), 0.25))
		end)
	end
	return nil
end

-- Slowly turns an icon (call every frame for the icons on screen).
function Icons.turn(vp: ViewportFrame, yaw: number)
	local camera = vp.CurrentCamera
	local distance = vp:GetAttribute("Distance")
	local center = vp:GetAttribute("Center")
	if not camera or typeof(distance) ~= "number" or typeof(center) ~= "Vector3" then
		return
	end
	local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-22), 0, 0)
	camera.CFrame = CFrame.new(center - dir.LookVector * distance, center)
end

return Icons
