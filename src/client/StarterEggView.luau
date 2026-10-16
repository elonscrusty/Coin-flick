--!strict
-- The free starter egg (client only, cosmetic; the server decides and saves the pet: RetentionService "Starter").
-- A brand-new player (profile StarterEgg) sees a big glowing egg on a pedestal right next to the lobby spawn, with
-- the route arrow pointing at it and "FREE PET!" over it. Tapping the egg (or its prompt) asks the server to hatch
-- it; the answer plays the big hatch show (HatchShow) and the egg is gone for good. Action in the first 10 seconds,
-- no menus. The egg is local to this player: nobody else sees it.
--
-- Where: a Part named MapNames.StarterEggSpot in the map; else 16 studs in front of the lobby spawn.
-- REPLACE: the egg uses a "Lobby_ShrineEgg" mesh when the place has one in ReplicatedStorage, a gold spotted egg
-- otherwise. Either way it glows (Highlight + light + sparkles), bobs and turns, under a bouncing "FREE PET! ▼".

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapNames = require(Shared.MapNames)
local HintRules = require(Shared.HintRules)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local GuideArrow = require(script.Parent.GuideArrow)
local HatchShow = require(script.Parent.HatchShow)

local StarterEggView = {}

StarterEggView.Hatched = Instance.new("BindableEvent") -- (pet) after the show (RetentionView cheers)
StarterEggView.Label = "EGG" -- the route arrow's chip text (the HUD leaves this arrow alone in the lobby)
local FORWARD = 16 -- studs in front of the spawn when the map has no StarterEggSpot

local player = Players.LocalPlayer
local model: Model? = nil
local eggPart: BasePart? = nil
local ringPart: BasePart? = nil
local asked = 0 -- os.clock of the last hatch request (one at a time)
local hatched = false
local spin: RBXScriptConnection? = nil -- the egg's slow bob + turn while it waits
-- the "FREE PET!" world tag follows the one hint rule (shared/HintRules): gone for good once hatched, and it retires
-- after HintRules.Timeout.FreePet seconds in view (it covered the arena sign from spawn; the egg keeps glowing)
local tagHints = HintRules.new()

local function inLobby(): boolean
	return State.Match == nil and player:GetAttribute("MatchKey") == nil and (player:GetAttribute("InTower") ~= true and player:GetAttribute("InBattle") ~= true) and not State.Teleport
end

local function wanted(): boolean
	local p = State.Profile
	return p ~= nil and p.StarterEgg == true and not hatched and inLobby()
end

local function groundBelow(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else pos
end

-- Where the egg stands: (feet position, facing direction).
local function spot(): (Vector3?, Vector3)
	local hook = Workspace:FindFirstChild(MapNames.StarterEggSpot, true)
	if hook and hook:IsA("BasePart") then
		return hook.Position - Vector3.new(0, hook.Size.Y / 2, 0), hook.CFrame.LookVector
	end
	local spawn = Workspace:FindFirstChild(MapNames.Spawn, true) or Workspace:FindFirstChild("CT_Rocks_LobbySpawn", true)
	if not (spawn and spawn:IsA("BasePart")) then
		spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	end
	if spawn and spawn:IsA("BasePart") then
		local look = spawn.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
		return spawn.Position + dir * FORWARD, -dir
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local look = root.CFrame.LookVector
		return root.Position + Vector3.new(look.X, 0, look.Z) * FORWARD, -look
	end
	return nil, Vector3.new(0, 0, 1)
end

local function block(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function askHatch()
	if hatched or HatchShow.playing() or os.clock() - asked < 2 then
		return
	end
	asked = os.clock()
	Net.event("RetentionAction"):FireServer("Starter")
end

local function build()
	if model then
		return
	end
	local feet, face = spot()
	if not feet then
		return
	end
	local m = Instance.new("Model")
	m.Name = "StarterEgg_Local"
	local ground = groundBelow(feet, { m, player.Character :: any })
	local at = CFrame.lookAt(ground, ground + Vector3.new(face.X, 0, face.Z))
	-- chunky pedestal: two steps, a gold rim and a glowing ring (low-poly like the pets)
	block(m, "Pedestal", Enum.PartType.Cylinder, Vector3.new(1.6, 9, 9), at * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(176, 118, 70), Enum.Material.Wood)
	block(m, "PedestalTop", Enum.PartType.Cylinder, Vector3.new(0.5, 7.4, 7.4), at * CFrame.new(0, 1.85, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 204, 64), Enum.Material.Foil)
	local ring = block(m, "GlowRing", Enum.PartType.Cylinder, Vector3.new(0.2, 8.4, 8.4), at * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 224, 120), Enum.Material.Neon)
	ring.CanCollide = false
	ring.Transparency = 0.35
	ringPart = ring
	local top = 2.1
	local egg: BasePart
	local mesh = ReplicatedStorage:FindFirstChild("Lobby_ShrineEgg", true)
	if mesh and mesh:IsA("BasePart") then
		egg = mesh:Clone()
		local k = 6.5 / math.max(egg.Size.Y, 0.1)
		egg.Size = egg.Size * k
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(5.6, 7.4, 5.6)
		ball.Color = Color3.fromRGB(255, 196, 40) -- rarity gold: it must read as a special egg, never a plain white blob
		ball.Material = Enum.Material.SmoothPlastic
		ball.Reflectance = 0.15
		egg = ball
		for i, c in { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 190), Color3.fromRGB(110, 210, 255) } do
			-- three chunky spots so it reads as a special egg, not a plain ball
			local a = i * 2.1
			local spotPart = block(m, "Spot" .. i, Enum.PartType.Ball, Vector3.new(1.4, 1.4, 0.6), CFrame.new(), c)
			spotPart.CanCollide = false
			spotPart:SetAttribute("Angle", a)
			spotPart:SetAttribute("Height", (i - 2) * 1.1)
		end
	end
	egg.Name = "Egg"
	egg.Anchored = true
	egg.CanCollide = true
	egg.CanTouch = false
	egg.CFrame = at * CFrame.new(0, top + egg.Size.Y / 2, 0)
	egg.Parent = m
	eggPart = egg
	-- spots ride on the egg's surface
	for _, sp in m:GetChildren() do
		local a = sp:GetAttribute("Angle")
		if sp:IsA("BasePart") and type(a) == "number" then
			local h = (sp:GetAttribute("Height") :: number?) or 0
			local r = egg.Size.X / 2 * math.sqrt(math.max(0, 1 - (h / (egg.Size.Y / 2)) ^ 2))
			local p = egg.Position + Vector3.new(math.cos(a) * r, h, math.sin(a) * r)
			sp.CFrame = CFrame.lookAt(p, p + (p - egg.Position))
			local weldTo = Instance.new("WeldConstraint")
			weldTo.Part0, weldTo.Part1 = egg, sp
			weldTo.Parent = sp
			sp.Anchored = false -- rides the egg's bob and turn through the weld
		end
	end
	-- a soft gold glow around the egg
	local glow = Instance.new("Highlight")
	glow.Name = "Glow"
	glow.Adornee = egg
	glow.FillColor = Color3.fromRGB(255, 220, 90)
	glow.FillTransparency = 0.75
	glow.OutlineColor = Color3.fromRGB(255, 240, 160)
	glow.OutlineTransparency = 0.1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = m
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 214, 120)
	light.Range = 16
	light.Brightness = 2
	light.Shadows = false
	light.Parent = egg
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Rate = 14
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140))
	sparkle.Parent = egg
	-- "FREE PET!" over the egg, bobbing
	local bb = Instance.new("BillboardGui")
	bb.Name = "FreePet"
	bb.Size = UDim2.fromScale(7, 3.5) -- compact: the big 10x5 tag reached up over the signs behind the egg
	bb.StudsOffsetWorldSpace = Vector3.new(0, egg.Size.Y / 2 + 2.1, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 70
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.6)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = "FREE PET!"
	t.TextColor3 = Color3.fromRGB(255, 214, 64)
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = Color3.fromRGB(60, 30, 10)
	st.Parent = t
	t.Parent = bb
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.fromScale(0.3, 0.55)
	arrow.Size = UDim2.fromScale(0.4, 0.45)
	arrow.Font = Enum.Font.FredokaOne
	arrow.TextScaled = true
	arrow.Text = "\u{25BC}"
	arrow.TextColor3 = Color3.fromRGB(255, 214, 64)
	local ast = st:Clone()
	ast.Parent = arrow
	arrow.Parent = bb
	bb.Parent = egg
	task.spawn(function()
		local last = os.clock()
		while bb.Parent do
			task.wait(0.25)
			local now = os.clock()
			if hatched then
				HintRules.done(tagHints, "FreePet")
			end
			if not HintRules.visible(tagHints, "FreePet", HintRules.Timeout.FreePet, StarterEggView.visible(), now - last) then
				bb.Enabled = false
				break
			end
			last = now
		end
	end)
	if not (State.Profile and State.Profile.Settings and State.Profile.Settings.ReducedMotion) then
		TweenService:Create(bb, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true), { StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 1.2, 0) }):Play()
		TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 4 }):Play()
		-- the egg bobs and slowly turns (stops the moment the hatch show takes it)
		local home = egg.CFrame
		local t0 = os.clock()
		spin = RunService.Heartbeat:Connect(function()
			if HatchShow.playing() or not egg.Parent then
				return
			end
			local tt = os.clock() - t0
			egg.CFrame = home * CFrame.new(0, 0.35 + 0.35 * math.sin(tt * 2.2), 0) * CFrame.Angles(0, tt * 0.6, math.rad(4) * math.sin(tt * 1.3))
		end)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HatchStarter"
	prompt.ActionText = "Hatch!"
	prompt.ObjectText = "Free pet"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = egg
	prompt.Triggered:Connect(askHatch)
	m.Parent = Workspace
	model = m
	GuideArrow.set(egg.Position, StarterEggView.Label, ground.Y)
end

-- True while the starter egg (and with it the route arrow) is drawn in view: the HUD objective banner steps aside then.
function StarterEggView.visible(): boolean
	local egg = eggPart
	if not egg or not egg.Parent or hatched then
		return false
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return false
	end
	local _, onScreen = cam:WorldToViewportPoint(egg.Position)
	return onScreen
end

local function remove()
	if spin then
		spin:Disconnect()
		spin = nil
	end
	if model then
		model:Destroy()
		model = nil
		eggPart, ringPart = nil, nil
	end
	if GuideArrow.label() == StarterEggView.Label then
		GuideArrow.clear()
	end
end

local function refresh()
	if HatchShow.playing() then
		return
	end
	if wanted() then
		build()
	else
		remove()
	end
end

-- The server hatched the starter pet: play the show on our egg (or just celebrate if the egg is not here).
local function onHatched(pet: any)
	hatched = true
	if GuideArrow.label() == StarterEggView.Label then
		GuideArrow.clear()
	end
	local egg = eggPart
	if not egg then
		build()
		egg = eggPart
	end
	if egg and type(pet) == "table" then
		HatchShow.play(egg, pet, ringPart, function()
			remove()
			StarterEggView.Hatched:Fire(pet)
		end)
	else
		remove()
		StarterEggView.Hatched:Fire(pet)
	end
end

function StarterEggView.start()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" or what == "Match" then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("MatchKey"):Connect(refresh)
	player:GetAttributeChangedSignal("InTower"):Connect(refresh)
	player:GetAttributeChangedSignal("InBattle"):Connect(refresh)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refresh()
	end)
	Net.event("Retention").OnClientEvent:Connect(function(kind, data)
		if kind == "Starter" and type(data) == "table" then
			onHatched(data.Pet)
		end
	end)
	-- a tap or click right on the egg hatches it too (not only the prompt pill)
	UserInputService.InputEnded:Connect(function(input, processed)
		if processed or not eggPart then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local cam = Workspace.CurrentCamera
		local ray = cam:ViewportPointToRay(input.Position.X, input.Position.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { model :: any }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
		if hit then
			askHatch()
		end
	end)
	refresh()
end

return StarterEggView
