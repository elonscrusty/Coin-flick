-- The big hatch show (client only, cosmetic; the server already picked and saved the pet before this plays).
-- Port of the Studio demo egg v2 (DemoEggClient_DEV, runner-proven; reference copy in the project files at
-- reference/demo_egg/). Three tiers: RARE (quick), EPIC (god rays), LEGENDARY (slow-mo burst, rainbow, lobby beam).
-- Changes from the demo: any egg part and pet record (HatchShow.play), the game's own pet model when the place has
-- no hand-made one, plain wedge shell chunks when EggKitMeshes is missing, the egg does not regrow (the starter egg
-- is removed after its show), and the camera is held through CameraMode. No pet mouth animation (owner rule).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeodeGen = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GeodeGen"))
local PetModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetModel"))
local CameraMode = require(script.Parent.CameraMode)
local PetStyle = require(script.Parent.ui.PetStyle)

local HatchShow = {}

local player = Players.LocalPlayer
-- set per show by HatchShow.play (the demo had one fixed egg)
local egg: BasePart = nil :: any
local ring: BasePart = nil :: any
local spec: { [string]: any } = {}
local okIds, SoundIds = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundIds")) end)
if not okIds or type(SoundIds) ~= "table" then SoundIds = {} end
-- Find The Pet made sounds (HatchSparkle, HatchDrum; 0 until uploaded = silent)
local okPet, PetSoundIds = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetSoundIds")) end)
if not okPet or type(PetSoundIds) ~= "table" then PetSoundIds = {} end

local TIERS = {
	RARE = { colors = { Color3.fromRGB(70, 160, 255), Color3.fromRGB(80, 240, 255) }, cracks = 2, slow = false, beam = 60, chunks = 14, coins = 10, silhouette = 0.6, rainbow = false },
	EPIC = { colors = { Color3.fromRGB(190, 90, 255), Color3.fromRGB(255, 90, 220) }, cracks = 3, slow = false, beam = 90, chunks = 20, coins = 18, silhouette = 0.9, rainbow = false },
	LEGENDARY = { colors = { Color3.fromRGB(255, 196, 40), Color3.fromRGB(255, 120, 30) }, cracks = 3, slow = true, beam = 400, chunks = 28, coins = 32, silhouette = 1.4, rainbow = true },
}
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 160, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 90, 255)),
})
local CONFETTI = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 220, 120), Color3.fromRGB(80, 170, 255), Color3.fromRGB(200, 110, 255), Color3.fromRGB(255, 255, 255) }

local eggHome = CFrame.new()
local eggSize = Vector3.one
local base = CFrame.new() -- pedestal top, under the egg
local playing = false

local speed = 1 -- 1 = normal, < 1 = slow motion (drives our own animations, waits and particle TimeScale)
local emitters = {}

local function wait_(t: number)
	local left = t
	while left > 0 do
		left -= RunService.RenderStepped:Wait() * speed
	end
end

local function tw(obj, t, props, style, dir)
	local tween = TweenService:Create(obj, TweenInfo.new(t / math.max(speed, 0.05), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

local function sound(name: string, vol: number?, pitch: number?, parent: Instance?)
	local id = SoundIds[name]
	if not id or id == 0 then id = PetSoundIds[name] end
	if not id or id == 0 or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = if type(id) == "number" then "rbxassetid://" .. id else tostring(id)
	s.Volume = vol or 0.8
	s.PlaybackSpeed = (pitch or 1) * math.max(speed, 0.5)
	s.RollOffMaxDistance = 260
	s.Parent = parent or egg
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(8, function() if s.Parent then s:Destroy() end end)
end

local function fx(parent: Instance, props: { [string]: any }): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Texture = SPARK
	p.LightEmission = 1
	p.Enabled = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	table.insert(emitters, p)
	return p
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = workspace
	return p
end

local function shockwave(color: Color3, size: number, t: number, y: number?)
	local w = part({ Shape = Enum.PartType.Cylinder, Color = color, Size = Vector3.new(0.3, 2, 2), Transparency = 0.05 })
	w.CFrame = CFrame.new(base.Position + Vector3.new(0, (y or 0.3), 0)) * CFrame.Angles(0, 0, math.rad(90))
	tw(w, t, { Size = Vector3.new(0.12, size, size), Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(t / math.max(speed, 0.05) + 0.2, function() w:Destroy() end)
end

-- the big banner that slides in (presser only): a white pet-style sheet with the tier's colour round its edge,
-- the rarity on a glossy ribbon over its top and the name in the outlined title words (ui/PetStyle)
local function bigBanner(name: string, rarity: string, tier)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DemoEggBanner"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(-0.6, 0.06)
	holder.Size = UDim2.fromScale(0.62, 0.24)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local K = PetStyle.K
	local tint = if tier.rainbow then RAINBOW else ColorSequence.new(tier.colors[1], tier.colors[2])
	-- drop copy under the sheet (a sibling: children draw above their parent)
	local drop = Instance.new("Frame")
	drop.Name = "Drop"
	drop.Size = UDim2.fromScale(1, 0.62)
	drop.Position = UDim2.new(0, 0, 0.38, 5)
	drop.BackgroundColor3 = K.TitleShadow
	drop.BackgroundTransparency = 0.5
	drop.BorderSizePixel = 0
	drop.ZIndex = 1
	drop.Parent = holder
	PetStyle.round(drop, 18)
	local strip = Instance.new("Frame")
	strip.Name = "Sheet"
	strip.Size = UDim2.fromScale(1, 0.62)
	strip.Position = UDim2.fromScale(0, 0.38)
	strip.BackgroundColor3 = K.Panel
	strip.BorderSizePixel = 0
	strip.ZIndex = 2
	strip.Parent = holder
	PetStyle.round(strip, 18)
	PetStyle.pattern(strip, K.PanelPattern, 0.3, 40, 700, 120, 80)
	local stroke = PetStyle.edge(strip, tier.colors[1], 4)
	local sg = Instance.new("UIGradient", stroke)
	sg.Color = tint
	-- the rarity ribbon: a glossy pill in the tier's colours (rainbow for LEGENDARY), tilted a touch
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.fromScale(0.5, 0.02)
	ribbon.Size = UDim2.fromScale(0.62, 0.42)
	ribbon.BackgroundColor3 = tier.colors[1]
	ribbon.BorderSizePixel = 0
	ribbon.Rotation = -2
	ribbon.ZIndex = 3
	ribbon.Parent = holder
	PetStyle.round(ribbon, 999)
	PetStyle.edge(ribbon, K.Ink, 2.5)
	local g = Instance.new("UIGradient", ribbon)
	g.Color = tint
	local r = PetStyle.words(ribbon, "\u{2605} " .. rarity .. " \u{2605}", 40, {
		Name = "Rarity", Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 2), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4, OutlineThick = 3,
	})
	r.TextWrapped = false
	PetStyle.title(strip, "You hatched " .. name .. "!", 54, {
		Name = "Hatched", Position = UDim2.fromScale(0.04, 0.08), Size = UDim2.fromScale(0.92, 0.84), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(holder, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.06) }):Play()
	task.spawn(function()
		local t0 = os.clock()
		while gui.Parent do
			local a = (os.clock() - t0) * 140 % 360
			g.Rotation = a
			sg.Rotation = -a
			task.wait()
		end
	end)
	return gui, holder
end

local function play(petName: string, rarity: string, presserId: number?)
	if playing then return end
	playing = true
	speed = 1
	table.clear(emitters)
	local tier = TIERS[rarity] or TIERS.EPIC
	local c1, c2 = tier.colors[1], tier.colors[2]
	local mine = presserId == nil or presserId == player.UserId
	local cam = workspace.CurrentCamera
	local trash = {}
	local function keep(x)
		table.insert(trash, x)
		return x
	end

	------------------------------------------------------------ camera + HUD (presser only)
	local oldFov = cam.FieldOfView
	local from = cam.CFrame
	local flat = Vector3.new(from.Position.X - base.Position.X, 0, from.Position.Z - base.Position.Z)
	if flat.Magnitude < 1 then flat = Vector3.new(0, 0, 1) end
	local focus = base.Position + Vector3.new(0, 5, 0)
	local camPos = focus + flat.Unit * 14 + Vector3.new(0, 2, 0)
	local camGoal = CFrame.lookAt(camPos, focus)
	local shake = 0
	local orbit = 0 -- slow camera orbit around the egg (radians/s)
	local orbitAng = 0
	local camConn
	local hidden = {}
	if mine then
		cam:SetAttribute("CT_Cinematic", true)
		cam.CameraType = Enum.CameraType.Scriptable
		for _, gg in player.PlayerGui:GetDescendants() do
			if (gg:IsA("ScreenGui") or gg:IsA("BillboardGui")) and gg.Enabled and gg.Name ~= "DemoEggBanner" then
				gg.Enabled = false
				table.insert(hidden, gg)
			end
		end
		for _, gg in workspace:GetDescendants() do -- world tags like YOUR GALLERY would float over the show
			if gg:IsA("BillboardGui") and gg.Enabled then
				gg.Enabled = false
				table.insert(hidden, gg)
			end
		end
		-- keep the world tags off (the game re-enables its marker) and hide our own avatar + pets from our camera
		local ghosts = {}
		local function ghost(m: Instance?)
			if not m then return end
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then table.insert(ghosts, d) end
			end
		end
		ghost(player.Character)
		local petsFolder = workspace:FindFirstChild("CTR_Pets")
		if petsFolder then
			for _, m in petsFolder:GetChildren() do
				if tostring(m.Name):find(tostring(player.UserId), 1, true) then ghost(m) end
			end
		end
		local scanAt = 0
		local holdConn = RunService.RenderStepped:Connect(function()
			if os.clock() > scanAt then -- tags that appear mid-show (e.g. the gallery marker) get hidden too
				scanAt = os.clock() + 0.25
				for _, root in { workspace, player.PlayerGui } do
					for _, gg in root:GetDescendants() do
						if gg:IsA("BillboardGui") and gg.Enabled and not table.find(hidden, gg) then
							gg.Enabled = false
							table.insert(hidden, gg)
						end
					end
				end
			end
			for _, gg in hidden do
				if gg.Parent and gg.Enabled then gg.Enabled = false end
			end
			for _, d in ghosts do
				if d.Parent then (d :: any).LocalTransparencyModifier = 1 end
			end
		end)
		table.insert(trash, holdConn)
		table.insert(trash, function()
			for _, d in ghosts do
				if d.Parent then (d :: any).LocalTransparencyModifier = 0 end
			end
		end)
		tw(cam, 1.0, { CFrame = camGoal, FieldOfView = 58 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		task.delay(1.05, function()
			camConn = RunService.RenderStepped:Connect(function(dt)
				orbitAng += orbit * dt * speed
				local off = CFrame.Angles(0, orbitAng, 0) * (camPos - focus)
				local goal = CFrame.lookAt(focus + off, focus)
				if shake > 0 then
					goal *= CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, (math.random() - 0.5) * shake * 0.5)
				end
				cam.CFrame = goal
			end)
		end)
	end

	------------------------------------------------------------ anticipation: lights down, spotlight, heartbeat
	local cc, bloom, dof
	if mine then
		cc = keep(Instance.new("ColorCorrectionEffect"))
		cc.Parent = Lighting
		tw(cc, 1.2, { Brightness = -0.28, Contrast = 0.25, Saturation = 0.1, TintColor = Color3.fromRGB(190, 195, 235) })
		bloom = keep(Instance.new("BloomEffect"))
		bloom.Intensity = 0
		bloom.Size = 26
		bloom.Threshold = 1.4
		bloom.Parent = Lighting
		tw(bloom, 2, { Intensity = 0.6 })
		dof = keep(Instance.new("DepthOfFieldEffect"))
		dof.FocusDistance = 15
		dof.InFocusRadius = 14
		dof.FarIntensity = 0
		dof.NearIntensity = 0
		dof.Parent = Lighting
		tw(dof, 1.5, { FarIntensity = 0.15 })
	end
	local spotHolder = keep(part({ Transparency = 1, Size = Vector3.new(1, 1, 1) }))
	spotHolder.CFrame = CFrame.lookAt(base.Position + Vector3.new(0, 26, 0), base.Position)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 28
	spot.Range = 40
	spot.Brightness = 0
	spot.Color = Color3.fromRGB(255, 250, 235)
	spot.Shadows = true
	spot.Parent = spotHolder
	tw(spot, 0.6, { Brightness = 4.5 })
	local cone = keep(part({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 250, 225), Transparency = 1, Material = Enum.Material.ForceField }))
	cone.Size = Vector3.new(26, 9, 9)
	cone.CFrame = CFrame.new(base.Position + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90))
	tw(cone, 0.8, { Transparency = 0.6 })

	local light = keep(Instance.new("PointLight"))
	light.Color = c1
	light.Range = 6
	light.Brightness = 0
	light.Shadows = false
	light.Parent = egg
	local hl = keep(Instance.new("Highlight"))
	hl.FillColor = c1
	hl.OutlineColor = c2
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0.7
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = egg
	hl.Parent = egg

	-- the egg's motion is driven every frame from these
	local lift, spin, spinVel, wob, hop, scalePulse = 0, 0, 0, 0, 0, 1
	local eggConn = RunService.RenderStepped:Connect(function(dt)
		dt *= speed
		spin += spinVel * dt
		local t = os.clock()
		local rot = CFrame.Angles(math.sin(t * 23) * wob * 0.6, spin, math.sin(t * 29) * wob)
		local jitter = Vector3.new((math.random() - 0.5) * wob * 0.6, math.abs(math.sin(t * 37)) * hop, (math.random() - 0.5) * wob * 0.6)
		egg.Size = eggSize * scalePulse
		egg.CFrame = (base + Vector3.new(0, lift, 0) + jitter) * rot * CFrame.new(0, egg.Size.Y / 2, 0)
	end)

	-- heartbeat: accelerating thumps, egg pulses and glows
	local beats = if tier.slow then 6 elseif rarity == "EPIC" then 4 else 2
	for i = 1, beats do
		sound("CountdownTick", 0.7, 0.75 + i * 0.05)
		scalePulse = 1.09
		hl.FillTransparency = 0.55
		light.Brightness = 1 + i * 0.6
		light.Range = 8 + i * 2
		tw(hl, 0.35, { FillTransparency = 0.9 })
		task.spawn(function()
			for k = 1, 8 do
				scalePulse = 1 + 0.09 * (1 - k / 8)
				RunService.RenderStepped:Wait()
			end
			scalePulse = 1
		end)
		wait_(math.max(0.62 - i * 0.07, 0.3))
	end

	------------------------------------------------------------ float up + spin faster and faster
	sound("PressDescend", 0.5, 1.4)
	local floatT = 0
	local spinUp = RunService.RenderStepped:Connect(function(dt)
		floatT += dt * speed
		lift = math.min(floatT / 1.2, 1) * 3.2
		spinVel = math.min(floatT * 9, 26)
		wob = math.rad(4 + floatT * 5)
	end)
	keep(Instance.new("Folder")) -- placeholder so trash is never empty
	local swirl = {}
	for i = 1, 4 do
		local a = keep(part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), Color = i % 2 == 0 and c2 or c1 }))
		local p = fx(a, {
			Rate = 60, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(0, 0.3),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
			Color = if tier.rainbow and i % 2 == 0 then RAINBOW else ColorSequence.new(i % 2 == 0 and c2 or c1),
		})
		p.Enabled = true
		local trailA0 = Instance.new("Attachment", a)
		trailA0.Position = Vector3.new(0, 0.25, 0)
		local trailA1 = Instance.new("Attachment", a)
		trailA1.Position = Vector3.new(0, -0.25, 0)
		local tr = Instance.new("Trail")
		tr.Attachment0 = trailA0
		tr.Attachment1 = trailA1
		tr.Lifetime = 0.35
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.Color = if tier.rainbow then RAINBOW else ColorSequence.new(c1, c2)
		tr.Transparency = NumberSequence.new(0, 1)
		tr.Parent = a
		table.insert(swirl, { a = a, off = i * math.pi / 2 })
	end
	local swirlT = 0
	local swirlConn = RunService.RenderStepped:Connect(function(dt)
		swirlT += dt * speed
		for i, s in swirl do
			local ang = swirlT * (5 + swirlT * 1.5) + s.off
			local rad = math.max(5 - swirlT * 0.9, 1.2)
			s.a.CFrame = CFrame.new(base.Position + Vector3.new(math.cos(ang) * rad, 2 + lift + math.sin(swirlT * 3 + i) * 1.5, math.sin(ang) * rad))
		end
	end)
	wait_(if rarity == "RARE" then 0.7 else 1.3)

	------------------------------------------------------------ cracks in stages
	local cracks = {}
	local function addCracks(n: number, len: number)
		local rx, ry = eggSize.X / 2, eggSize.Y / 2
		for _ = 1, n do
			local a = math.random() * math.pi * 2
			local h = (math.random() - 0.3) * 0.85
			local l = Vector3.new(math.cos(a) * rx * math.sqrt(1 - h * h), h * ry, math.sin(a) * rx * math.sqrt(1 - h * h))
			local cp = keep(part({ Color = c1, Size = Vector3.new(0.14, 0.05, 0.16), Transparency = 0 }))
			table.insert(cracks, { p = cp, l = l, tilt = math.rad((math.random() - 0.5) * 80) })
			tw(cp, 0.18, { Size = Vector3.new(0.2, len * (0.7 + math.random() * 0.6), 0.2) }, Enum.EasingStyle.Back)
		end
	end
	local crackConn = RunService.RenderStepped:Connect(function()
		for _, c in cracks do
			c.p.CFrame = egg.CFrame * CFrame.lookAt(c.l, c.l * 2) * CFrame.Angles(0, 0, c.tilt)
		end
	end)
	local leak = fx(egg, {
		Rate = 0, Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.35, 0), Color = ColorSequence.new(Color3.new(1, 1, 1), c1),
	})
	leak.Enabled = true
	for stage = 1, tier.cracks do
		sound("StoneCrack" .. math.clamp(stage, 1, 3), 1, 1 + stage * 0.08)
		addCracks(3 + stage, 0.9 + stage * 0.45)
		leak.Rate = 25 * stage
		hl.FillTransparency = 0.75 - stage * 0.15
		tw(light, 0.3, { Brightness = 2 + stage * 1.5, Range = 12 + stage * 4 })
		shockwave(stage % 2 == 0 and c2 or c1, 14 + stage * 6, 0.8)
		shake = 0.12 * stage
		task.delay(0.18, function() shake = 0.04 * stage end)
		if mine and cc then
			cc.TintColor = c1:Lerp(Color3.new(1, 1, 1), 0.55)
			tw(cc, 0.35, { TintColor = Color3.fromRGB(190, 195, 235) })
		end
		wait_(if tier.slow then 0.85 else 0.65)
	end

	------------------------------------------------------------ charge: god-ray beam, inward rush
	local beamH = tier.beam
	local beam = keep(part({ Shape = Enum.PartType.Cylinder, Color = c1, Transparency = 0.25, Material = Enum.Material.ForceField }))
	beam.Size = Vector3.new(0.1, 1.5, 1.5)
	beam.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, 0, math.rad(90))
	local beamCore = keep(part({ Shape = Enum.PartType.Cylinder, Color = Color3.new(1, 1, 1), Transparency = 0 }))
	beamCore.Size = Vector3.new(0.1, 0.6, 0.6)
	beamCore.CFrame = beam.CFrame
	local beamW = if tier.slow then 5 else 3
	tw(beam, 0.9, { Size = Vector3.new(beamH, beamW, beamW), CFrame = CFrame.new(base.Position + Vector3.new(0, beamH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quart)
	tw(beamCore, 0.9, { Size = Vector3.new(beamH, beamW * 0.4, beamW * 0.4), CFrame = CFrame.new(base.Position + Vector3.new(0, beamH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quart)
	-- rotating god rays
	local rays = {}
	for i = 1, (if tier.slow then 8 else 5) do
		local r = keep(part({ Color = if tier.rainbow then CONFETTI[(i % 5) + 1] else (i % 2 == 0 and c2 or c1), Transparency = 1, Size = Vector3.new(0.4, 40, 0.4) }))
		table.insert(rays, { p = r, a = i / 8 * math.pi * 2 })
		tw(r, 0.6, { Transparency = 0.45 })
	end
	local rayT = 0
	local rayConn = RunService.RenderStepped:Connect(function(dt)
		rayT += dt * speed
		for _, r in rays do
			local a = r.a + rayT * 1.6
			r.p.CFrame = CFrame.new(base.Position + Vector3.new(0, 3 + lift, 0)) * CFrame.Angles(0, a, math.rad(62)) * CFrame.new(0, 20, 0)
		end
	end)
	local suck = keep(part({ Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 16), Transparency = 1 }))
	suck.CFrame = CFrame.new(base.Position + Vector3.new(0, 3 + lift, 0))
	local inward = fx(suck, {
		Rate = 160, Lifetime = NumberRange.new(0.35), Speed = NumberRange.new(-26), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Size = NumberSequence.new(0.4, 0.05), Color = if tier.rainbow then RAINBOW else ColorSequence.new(Color3.new(1, 1, 1), c1),
	})
	inward.Enabled = true
	sound("JackhammerStart", 0.35, 1.6)
	if mine then
		orbit = if tier.slow then 0.5 else 0.25
		tw(cam, 1.2, { FieldOfView = 54 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	for i = 1, (if rarity == "RARE" then 6 else 12) do
		shake = 0.05 + i * 0.03
		wob = math.rad(10 + i * 2)
		hop = i * 0.03
		wait_(0.1)
	end

	------------------------------------------------------------ slow motion (Legendary)
	if tier.slow then
		speed = 0.22
		for _, e in emitters do if e.Parent then e.TimeScale = 0.25 end end
		sound("CountdownTick", 1, 0.5)
		if mine and cc then tw(cc, 0.3, { Saturation = -0.4 }) end
		wait_(0.18) -- ~0.8 s of real time
	end

	------------------------------------------------------------ BURST
	inward.Enabled = false
	leak.Enabled = false
	crackConn:Disconnect()
	for _, c in cracks do c.p.Transparency = 1 end
	egg.Transparency = 1
	hl.Enabled = false
	ring.Transparency = 1
	tw(spot, 0.4, { Brightness = 0 })
	tw(cone, 0.4, { Transparency = 1 })
	sound("PressImpact", 1, 0.8)
	sound("GeodeReveal", 1, 1)
	-- stop orbiting and swing back to face the pet's landing spot
	orbit = 0
	task.spawn(function()
		local a0 = orbitAng
		for k = 1, 30 do
			orbitAng = a0 * (1 - k / 30)
			task.wait()
		end
		orbitAng = 0
	end)
	if mine then
		cam.FieldOfView = 82 -- the slam
		tw(cam, 0.9, { FieldOfView = 62 }, Enum.EasingStyle.Back)
		task.spawn(function() -- shake curve: hard hit, decaying
			for i = 1, 40 do
				shake = 1.4 * math.exp(-i * 0.12)
				task.wait()
			end
			shake = 0
		end)
		local flashGui = keep(Instance.new("ScreenGui"))
		flashGui.IgnoreGuiInset = true
		flashGui.DisplayOrder = 50
		local flash = Instance.new("Frame", flashGui)
		flash.Size = UDim2.fromScale(1, 1)
		flash.BorderSizePixel = 0
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flashGui.Parent = player.PlayerGui
		task.spawn(function() -- chromatic-style colour pop: white, rarity colour, gone
			flash.BackgroundTransparency = 0.3
			task.wait(0.06)
			flash.BackgroundColor3 = c1
			flash.BackgroundTransparency = 0.35
			TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
		end)
		if cc then
			cc.Brightness = 0.15
			cc.TintColor = c1:Lerp(Color3.new(1, 1, 1), 0.3)
			cc.Saturation = 0.5
			tw(cc, 0.7, { Brightness = -0.12, Contrast = 0.22, TintColor = Color3.new(1, 1, 1), Saturation = 0.2 })
		end
		if bloom then
			bloom.Intensity = 1.4
			tw(bloom, 0.5, { Intensity = 0 })
		end
	end
	light.Brightness = 8
	light.Range = 30
	tw(light, 1.2, { Brightness = 0.5, Range = 10 })
	if tier.slow then
		-- the lobby-wide beam stays up, thin, so everyone in the lobby sees a Legendary was hatched
		tw(beam, 0.5, { Transparency = 0.55, Size = Vector3.new(beamH, 2.2, 2.2) })
		tw(beamCore, 0.5, { Transparency = 0.6, Size = Vector3.new(beamH, 0.5, 0.5) })
		task.delay(5, function()
			if beam.Parent then
				tw(beam, 1.5, { Transparency = 1 })
				tw(beamCore, 1.5, { Transparency = 1 })
			end
		end)
	else
		tw(beam, 0.6, { Transparency = 1 })
		tw(beamCore, 0.4, { Transparency = 1 })
	end
	for _, r in rays do tw(r.p, 0.8, { Transparency = 1 }) end

	-- exploding sphere + rings
	-- the blast stays smaller than the camera distance so it never swallows the screen
	local blast = keep(part({ Shape = Enum.PartType.Ball, Color = c1, Size = Vector3.new(2, 2, 2), Transparency = 0.15 }))
	blast.CFrame = CFrame.new(base.Position + Vector3.new(0, 3 + lift, 0))
	tw(blast, 0.45, { Size = Vector3.new(16, 16, 16), Transparency = 1 }, Enum.EasingStyle.Quart)
	local blast2 = keep(part({ Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Size = Vector3.new(1, 1, 1), Transparency = 0.2, Material = Enum.Material.ForceField }))
	blast2.CFrame = blast.CFrame
	tw(blast2, 0.8, { Size = Vector3.new(22, 22, 22), Transparency = 1 }, Enum.EasingStyle.Quart)
	shockwave(Color3.new(1, 1, 1), 46, 0.9, 0.2)
	shockwave(c1, 64, 1.2, 0.35)
	shockwave(c2, 84, 1.5, 0.5)
	if tier.slow then shockwave(Color3.fromRGB(255, 90, 220), 110, 1.9, 0.65) end

	local boom = keep(Instance.new("Attachment"))
	boom.Parent = workspace.Terrain
	boom.WorldPosition = base.Position + Vector3.new(0, 3.5 + lift, 0)
	local stars = fx(boom, {
		Lifetime = NumberRange.new(0.8, 1.7), Speed = NumberRange.new(28, 50), SpreadAngle = Vector2.new(180, 180),
		Drag = 3, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
		Color = if tier.rainbow then RAINBOW else ColorSequence.new(c1, c2), RotSpeed = NumberRange.new(-200, 200),
	})
	stars:Emit(if tier.slow then 140 else 80)
	for _, col in CONFETTI do
		local conf = fx(boom, {
			Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 0.2,
			Lifetime = NumberRange.new(2.2, 3.4), Speed = NumberRange.new(30, 52), SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -28, 0), Drag = 1.2,
			Size = NumberSequence.new(0.45), Color = ColorSequence.new(col), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-400, 400), Squash = NumberSequence.new(-1.2),
		})
		conf:Emit(if tier.slow then 40 else 24)
	end
	if tier.slow then
		for _, e in emitters do if e.Parent then e.TimeScale = 0.25 end end
	end

	-- shell chunks + coin fountain: hand-animated so slow motion works on them too
	local flyers = {}
	for i = 1, tier.chunks do
		local kit = ReplicatedStorage:FindFirstChild("EggKitMeshes")
		local srcPart = kit and kit:FindFirstChild(if i % 3 == 0 then "Shard" else "Shell_Out")
		local s
		if srcPart and srcPart:IsA("BasePart") then
			s = keep(srcPart:Clone())
		else
			s = keep(Instance.new("WedgePart"))
			s.Size = Vector3.new(0.5, 1.2, 1.2)
		end
		s.Size = s.Size * ((math.random() * 0.7 + 1.0) / s.Size.Magnitude * 1.8)
		s.Color = (i % 4 == 0) and c1 or Color3.fromRGB(250, 246, 236)
		s.Material = Enum.Material.SmoothPlastic
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.Parent = workspace
		local a = math.random() * math.pi * 2
		table.insert(flyers, {
			p = s, pos = base.Position + Vector3.new(0, 3 + lift, 0),
			vel = Vector3.new(math.cos(a) * (12 + math.random() * 18), 18 + math.random() * 20, math.sin(a) * (12 + math.random() * 18)),
			rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			spinv = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14, bounces = 0,
		})
	end
	for i = 1, tier.coins do
		local cpart = keep(part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 0.9, 0.9), Color = Color3.fromRGB(255, 205, 50), Material = Enum.Material.Neon }))
		local a = math.random() * math.pi * 2
		table.insert(flyers, {
			p = cpart, pos = base.Position + Vector3.new(0, 3 + lift, 0), coin = true,
			vel = Vector3.new(math.cos(a) * (4 + math.random() * 9), 30 + math.random() * 22, math.sin(a) * (4 + math.random() * 9)),
			rot = CFrame.Angles(0, a, 0), spinv = Vector3.new(0, 0, 12), bounces = 0,
		})
	end
	local groundY = base.Position.Y - 1.4
	local flyConn = RunService.RenderStepped:Connect(function(dt)
		dt *= speed
		for _, f in flyers do
			if f.p.Parent then
				f.vel += Vector3.new(0, -62 * dt, 0)
				f.pos += f.vel * dt
				if f.pos.Y < groundY + 0.3 and f.vel.Y < 0 then
					f.pos = Vector3.new(f.pos.X, groundY + 0.3, f.pos.Z)
					f.bounces += 1
					f.vel = Vector3.new(f.vel.X * 0.55, -f.vel.Y * 0.38, f.vel.Z * 0.55)
					if f.coin and f.bounces == 1 and math.random() < 0.3 then sound("Pickup", 0.25, 1 + math.random() * 0.4, f.p) end
				end
				f.rot *= CFrame.Angles(f.spinv.X * dt, f.spinv.Y * dt, f.spinv.Z * dt)
				f.p.CFrame = CFrame.new(f.pos) * f.rot
			end
		end
	end)
	task.delay(4.5, function()
		for _, f in flyers do if f.p.Parent then tw(f.p, 0.5, { Transparency = 1 }) end end
	end)

	if tier.slow then
		wait_(0.35) -- savour the blast in slow motion
		speed = 1
		for _, e in emitters do if e.Parent then e.TimeScale = 1 end end
		if mine and cc then tw(cc, 0.4, { Saturation = 0.15 }) end
	end
	swirlConn:Disconnect()
	for _, s in swirl do s.a:Destroy() end
	eggConn:Disconnect()
	spinUp:Disconnect()

	------------------------------------------------------------ reveal: silhouette, flash to colour, squash landing
	-- the place's hand-made pet model when it has one (ReplicatedStorage.PetModels), else the game's own pet model
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local srcPet = models and models:FindFirstChild(petName)
	local pet = srcPet and srcPet:Clone()
	if not pet then
		local okPet, built = pcall(PetModel.build, spec, { NoLight = true })
		if okPet and built then
			pet = built
			pet.WorldPivot = (pet:GetBoundingBox()) -- pivot at the centre, like the PetModels clones the show expects
		end
	end
	if pet then
		for _, d in pet:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		local _, sz = pet:GetBoundingBox()
		local target = 7 / math.max(sz.X, sz.Y, sz.Z)
		local baseScale = pet:GetScale() * target
		pet:ScaleTo(baseScale)
		pet.Parent = workspace
		keep(pet)
		local restY = (sz.Y * target) / 2 + 0.4
		local faceCam = Vector3.new(camPos.X, base.Position.Y, camPos.Z)
		local look = CFrame.lookAt(base.Position, faceCam)
		local sil = Instance.new("Highlight")
		sil.FillColor = Color3.new(0, 0, 0)
		sil.FillTransparency = 0
		sil.OutlineColor = c1
		sil.OutlineTransparency = 0
		sil.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		sil.Parent = pet
		-- silhouette hovers and turns, mystery moment
		local hoverY = restY + 3.5
		local st0 = os.clock()
		local silDur = tier.silhouette
		while os.clock() - st0 < silDur do
			local t = os.clock() - st0
			pet:ScaleTo(baseScale * math.min(1, 0.2 + t / silDur * 1.2))
			pet:PivotTo(CFrame.new(base.Position + Vector3.new(0, hoverY + math.sin(t * 6) * 0.3, 0)) * (look - look.Position) * CFrame.Angles(0, t * 9, 0))
			task.wait()
		end
		-- flash to full colour
		sound("RarityAccent", 1, 1)
		if tier.beam >= 90 then sound("HatchSparkle", 0.8, 1) end -- EPIC and LEGENDARY: sparkle swell (pets never roar)
		if tier.slow then sound("HatchDrum", 0.85, 1); sound("MatchWin", 0.9, 1) end -- LEGENDARY: drum hit + jingle
		sil.FillColor = Color3.new(1, 1, 1)
		sil.FillTransparency = 0
		TweenService:Create(sil, TweenInfo.new(0.45), { FillTransparency = 1 }):Play()
		task.delay(0.5, function()
			sil.DepthMode = Enum.HighlightDepthMode.Occluded
			sil.OutlineColor = Color3.fromRGB(35, 20, 50) -- dark rim so the pet pops off the bright ground
		end)
		local disc = keep(part({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(40, 30, 70), Material = Enum.Material.SmoothPlastic, Transparency = 1, Size = Vector3.new(0.1, 7, 7) }))
		disc.CFrame = CFrame.new(base.Position + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
		tw(disc, 0.4, { Transparency = 0.25 })
		local conf2 = fx(boom, {
			Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 0.3,
			Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(18, 30), SpreadAngle = Vector2.new(80, 80),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -24, 0), Drag = 1,
			Size = NumberSequence.new(0.4), Color = if tier.rainbow then RAINBOW else ColorSequence.new(c1, c2),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Squash = NumberSequence.new(-1.2),
		})
		conf2:Emit(if tier.slow then 90 elseif rarity == "EPIC" then 60 else 30)
		local pop = fx(boom, {
			Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(12, 22), SpreadAngle = Vector2.new(180, 180), Drag = 4,
			Size = NumberSequence.new(1, 0), Color = if tier.rainbow then RAINBOW else ColorSequence.new(Color3.new(1, 1, 1), c1),
		})
		boom.WorldPosition = base.Position + Vector3.new(0, hoverY, 0)
		pop:Emit(60)
		if mine and cc then
			cc.Brightness = 0.1
			tw(cc, 0.5, { Brightness = -0.1 })
		end
		-- drop + squash-and-stretch landing (uniform scale pulses + a dip)
		local d0 = os.clock()
		local landed = false
		local auraA = keep(Instance.new("Attachment"))
		auraA.Parent = workspace.Terrain
		auraA.WorldPosition = base.Position + Vector3.new(0, 0.6, 0)
		local aura = fx(auraA, {
			Rate = if tier.slow then 50 else 30, Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			Color = if tier.rainbow then RAINBOW else ColorSequence.new(c1, c2), Shape = Enum.ParticleEmitterShape.Cylinder,
		})
		aura.Enabled = true
		local auraRing = keep(part({ Shape = Enum.PartType.Cylinder, Color = c1, Transparency = 0.4, Size = Vector3.new(0.15, 9, 9) }))
		auraRing.CFrame = CFrame.new(base.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local petLight = Instance.new("PointLight")
		petLight.Color = c1
		petLight.Range = 14
		petLight.Brightness = 1.2
		local pp = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart", true)
		if pp then petLight.Parent = pp end
		local popConn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - d0
			local h, s
			if t < 0.32 then -- falling, stretched
				local x = t / 0.32
				h = hoverY - (hoverY - restY) * x * x
				s = 1.08
			elseif t < 0.5 then -- squash on impact
				local x = (t - 0.32) / 0.18
				h = restY - 0.5 * math.sin(x * math.pi)
				s = 1 - 0.14 * math.sin(x * math.pi)
				if not landed then
					landed = true
					shockwave(c1, 18, 0.6, 0.2)
					sound("HammerHit2", 0.6, 0.8)
				end
			elseif t < 0.85 then -- bounce up, stretched
				local x = (t - 0.5) / 0.35
				h = restY + 1.8 * math.sin(x * math.pi)
				s = 1 + 0.08 * math.sin(x * math.pi)
			else -- settle with a happy idle bob
				h = restY + 0.18 * math.sin((t - 0.85) * 3)
				s = 1 + 0.03 * math.sin((t - 0.85) * 14) * math.exp(-(t - 0.85) * 3)
			end
			pet:ScaleTo(baseScale * s)
			local turn = math.max(0, 1 - t / 1.2)
			pet:PivotTo(CFrame.new(base.Position + Vector3.new(0, h, 0)) * (look - look.Position) * CFrame.Angles(0, turn * turn * math.pi * 2, 0))
			auraRing.CFrame = CFrame.new(base.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		end)
		local bannerGui
		if mine then
			bannerGui = keep((bigBanner(GeodeGen.displayName(spec :: any), rarity, tier)))
		end
		wait_(if tier.slow then 4.2 elseif rarity == "EPIC" then 3.4 else 2.4)
		-- fade out the pet with a sparkle puff
		aura.Enabled = false
		popConn:Disconnect()
		if bannerGui then
			local holder = bannerGui:FindFirstChildOfClass("Frame")
			if holder then
				TweenService:Create(holder, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.fromScale(1.6, 0.06) }):Play()
			end
		end
		local endPivot = pet:GetPivot()
		local s0 = os.clock()
		while os.clock() - s0 < 0.45 do
			local x = (os.clock() - s0) / 0.45
			pet:ScaleTo(baseScale * math.max(0.02, 1 - x * x))
			pet:PivotTo(endPivot * CFrame.Angles(0, x * 6, 0) + Vector3.new(0, x * 3, 0))
			task.wait()
		end
		boom.WorldPosition = endPivot.Position + Vector3.new(0, 3, 0)
		stars:Emit(30)
		pet:Destroy()
		tw(auraRing, 0.5, { Transparency = 1 })
	else
		wait_(4)
	end

	------------------------------------------------------------ restore
	flyConn:Disconnect()
	rayConn:Disconnect()
	tw(spot, 0.2, { Brightness = 0 })
	if mine then
		orbit = 0
		if cc then tw(cc, 0.9, { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) }) end
		if bloom then tw(bloom, 0.9, { Intensity = 0 }) end
		if dof then tw(dof, 0.9, { FarIntensity = 0 }) end
		if camConn then camConn:Disconnect() end
		tw(cam, 1.0, { CFrame = from, FieldOfView = oldFov }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		wait_(1.05)
		cam.CameraType = Enum.CameraType.Custom
		cam:SetAttribute("CT_Cinematic", nil)
		for _, x in trash do
			if typeof(x) == "RBXScriptConnection" then x:Disconnect() elseif type(x) == "function" then x() end
		end
		for _, gg in hidden do
			if gg.Parent then gg.Enabled = true end
		end
	end
	CameraMode.cinematic("HatchShow", false)
	wait_(0.2)
	for _, x in trash do
		if typeof(x) == "Instance" and x.Parent then x:Destroy() end
	end
	speed = 1
	playing = false
end

function HatchShow.playing(): boolean
	return playing
end

-- Plays the show on `eggPart` (standing on a pedestal: its bottom is where the pet lands) for pet record `petSpec`
-- (GeodeGen.public). `ringPart` hides during the burst. `onDone` runs after the camera is back. One show at a time.
function HatchShow.play(eggPart: BasePart, petSpec: { [string]: any }, ringPart: BasePart?, onDone: (() -> ())?)
	if playing then
		return
	end
	egg = eggPart
	ring = ringPart or eggPart
	spec = petSpec
	eggHome = egg.CFrame
	eggSize = egg.Size
	base = eggHome * CFrame.new(0, -eggSize.Y / 2, 0)
	local rarity = string.upper(tostring(petSpec.Rarity or "Rare"))
	if not TIERS[rarity] then
		rarity = if rarity == "COMMON" or rarity == "UNCOMMON" then "RARE" else "EPIC"
	end
	CameraMode.cinematic("HatchShow", true)
	task.spawn(function()
		local ok, err = pcall(play, "Pet_" .. tostring(petSpec.Mineral), rarity, player.UserId)
		if not ok then
			warn("[HatchShow] " .. tostring(err))
			playing = false
			speed = 1
			local cam = workspace.CurrentCamera
			cam.CameraType = Enum.CameraType.Custom
			cam:SetAttribute("CT_Cinematic", nil)
			CameraMode.cinematic("HatchShow", false)
			for _, gg in player.PlayerGui:GetChildren() do
				if gg:IsA("ScreenGui") then
					gg.Enabled = true
				end
			end
		end
		if onDone then
			task.spawn(onDone)
		end
	end)
end

return HatchShow
