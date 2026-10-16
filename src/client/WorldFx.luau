--!strict
-- Small world effects (client only, cosmetic, nothing is sent anywhere):
--   * Plot pedestal glow: a pet shown on a plot stand (display slots, GalleryService "Display" folders) gets a soft
--     glowing disc under it in its rarity colour (Uncommon and up). The rarity is read from the plaque the server
--     already writes in Config.RarityTextColors; an "+ ADD PET" plaque or a Common pet gets no glow.
--   * Water ripples: a player walking or swimming in water (terrain water, or a part named like "Water" / "Pond")
--     leaves fading rings. Nearby players only, a few rings at a time. Stepping or dropping into the water makes a
--     splash: a wider ring and a few droplets (one shared emitter, Emit only).
--   * Feet dust (PlayerDust) and the race portal flash (PortalFx) are started from here.
--   * Secret egg: the hidden lobby egg (attribute SecretEgg = true, MapNames.SecretEgg) gives off a very faint sparkle.
--   * Zone weather in a hunt: snow in the Snow zone, ash and embers in the Volcano, twinkling stars in Space
--     (ZoneThemes landmark of the round's tier). The emitter box follows the camera.
-- Low effects: no weather, no ripples, no secret-egg sparkle; pedestal glow stays (static). Reduce Motion: weather is
-- thinner and the glow does not pulse. Every emitter and part is bounded and cleaned up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapNames = require(Shared.MapNames)
local ZoneThemes = require(Shared.ZoneThemes)
local State = require(script.Parent.State)

local WorldFx = {}

local MAX_RIPPLES = 10
local RIPPLE_NEAR = 60
local RIPPLE_EVERY = 0.22

local fxFolder: Folder? = nil

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function low(): boolean
	return settings().LowEffects == true
end

local function reduced(): boolean
	return settings().ReducedMotion == true
end

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "CT_Rocks_WorldFx"
	nf.Parent = Workspace
	fxFolder = nf
	return nf
end

local function deco(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("CameraIgnore", true)
end

-- Plot pedestal glow ----------------------------------------------------------------------------------------

local RANK: { [string]: number } = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
type Glow = { Parts: { BasePart } }
local glows: { [Instance]: Glow } = {}
local watched: { [Instance]: RBXScriptConnection } = {}
local glowParts: { BasePart } = {}

local function rarityOfInk(c: Color3): string?
	for name, col in Config.RarityTextColors :: any do
		local d = math.abs(col.R - c.R) + math.abs(col.G - c.G) + math.abs(col.B - c.B)
		if d < 0.02 then
			return name
		end
	end
	return nil
end

local function clearGlow(display: Instance)
	local g = glows[display]
	if not g then
		return
	end
	glows[display] = nil
	for _, p in g.Parts do
		local i = table.find(glowParts, p)
		if i then
			table.remove(glowParts, i)
		end
		p:Destroy()
	end
end

local function buildGlow(display: Instance)
	clearGlow(display)
	if not display.Parent or not watched[display] then
		return
	end
	local g: Glow = { Parts = {} }
	glows[display] = g
	local pets: { Model } = {}
	for _, c in display:GetChildren() do
		if c:IsA("Model") and not c:FindFirstChild("Stand") then -- wanderers carry an invisible "Stand" prompt part
			table.insert(pets, c)
		end
	end
	for _, c in display:GetChildren() do
		if c:IsA("BasePart") and c.Name == "Label" then
			local gui = c:FindFirstChildOfClass("SurfaceGui")
			local t = gui and gui:FindFirstChild("Text")
			local rarity = if t and t:IsA("TextLabel") then rarityOfInk(t.TextColor3) else nil
			if rarity and (RANK[rarity] or 1) >= 2 then
				-- the pet standing nearest this plaque
				local best: Model? = nil
				local bestD = 12
				for _, m in pets do
					local d = (m:GetPivot().Position - c.Position).Magnitude
					if d < bestD then
						best, bestD = m, d
					end
				end
				if best then
					local r = tonumber(best:GetAttribute("Radius")) or 1.5
					local at = best:GetPivot().Position
					local disc = Instance.new("Part")
					disc.Name = "PedestalGlow"
					disc.Shape = Enum.PartType.Cylinder
					disc.Size = Vector3.new(0.06, r * 2 + 1.2, r * 2 + 1.2)
					disc.CFrame = CFrame.new(at + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90))
					disc.Material = Enum.Material.Neon
					disc.Color = (Config.RarityColors :: any)[rarity] or Color3.new(1, 1, 1)
					disc.Transparency = 0.55
					deco(disc)
					disc:SetAttribute("Rank", RANK[rarity])
					disc.Parent = folder()
					table.insert(g.Parts, disc)
					table.insert(glowParts, disc)
				end
			end
		end
	end
end

local pendingGlow: { [Instance]: boolean } = {}
local function scheduleGlow(display: Instance)
	if pendingGlow[display] then
		return
	end
	pendingGlow[display] = true
	task.delay(0.6, function()
		pendingGlow[display] = nil
		buildGlow(display)
	end)
end

local function unwatch(display: Instance)
	local conn = watched[display]
	if conn then
		conn:Disconnect()
		watched[display] = nil
	end
	clearGlow(display)
end

local function watchDisplay(display: Instance)
	if watched[display] then
		return
	end
	watched[display] = display.ChildAdded:Connect(function()
		scheduleGlow(display)
	end)
	scheduleGlow(display)
	display.AncestryChanged:Connect(function()
		if not display:IsDescendantOf(Workspace) then
			unwatch(display)
		end
	end)
end

local function isDisplay(d: Instance): boolean
	return d.Name == "Display" and d:IsA("Folder") and d.Parent ~= nil
end

-- Secret egg sparkle ----------------------------------------------------------------------------------------

local eggSparkles: { ParticleEmitter } = {}

local function addEggSparkle(part: BasePart)
	if part:FindFirstChild("CT_SecretSparkle") then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "CT_SecretSparkle"
	e.Rate = 0.8
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.2, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.28), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.35)
	e.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160))
	e.LightEmission = 0.8
	e.LightInfluence = 0
	e.Enabled = not low()
	e.Parent = part
	table.insert(eggSparkles, e)
end

local function checkSecret(d: Instance)
	if d:IsA("BasePart") and (d:GetAttribute("SecretEgg") == true or d.Name == MapNames.SecretEgg) then
		addEggSparkle(d)
	elseif d:IsA("Model") and d:GetAttribute("SecretEgg") == true then
		local p = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
		if p then
			addEggSparkle(p)
		end
	end
end

-- Water ripples ---------------------------------------------------------------------------------------------

local liveRipples = 0
local lastRipple: { [Player]: number } = {}

local function isWater(hit: RaycastResult): boolean
	if hit.Material == Enum.Material.Water then
		return true
	end
	local n = string.lower(hit.Instance.Name)
	return string.find(n, "water", 1, true) ~= nil or string.find(n, "pond", 1, true) ~= nil
end

local function ripple(pos: Vector3, wide: number?)
	if liveRipples >= MAX_RIPPLES then
		return
	end
	liveRipples += 1
	local reach = wide or 6
	local p = Instance.new("Part")
	p.Name = "Ripple"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.05, 1.2, 1.2)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(235, 248, 255)
	p.Transparency = 0.45
	deco(p)
	p.Parent = folder()
	local tw = TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, reach, reach), Transparency = 1 })
	tw.Completed:Once(function()
		liveRipples -= 1
		p:Destroy()
	end)
	tw:Play()
end

local inWater: { [Player]: boolean } = {}
local splashHost: BasePart? = nil
local splashEmitter: ParticleEmitter? = nil

-- A splash where a player steps or drops into the water: a wide ring, a second one a moment later, and droplets.
local function splash(pos: Vector3)
	ripple(pos, 9)
	task.delay(0.15, ripple, pos, 5)
	local f = folder()
	local h, e = splashHost, splashEmitter
	if not (h and e and h.Parent == f) then
		local np = Instance.new("Part")
		np.Name = "SplashHost"
		np.Size = Vector3.new(1.4, 0.2, 1.4)
		np.Transparency = 1
		deco(np)
		local ne = Instance.new("ParticleEmitter")
		ne.Enabled = false -- Emit() only
		ne.Shape = Enum.ParticleEmitterShape.Box
		ne.EmissionDirection = Enum.NormalId.Top
		ne.Lifetime = NumberRange.new(0.45, 0.7)
		ne.Speed = NumberRange.new(6, 10)
		ne.SpreadAngle = Vector2.new(30, 30)
		ne.Acceleration = Vector3.new(0, -40, 0)
		ne.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.12) })
		ne.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8) })
		ne.Color = ColorSequence.new(Color3.fromRGB(225, 244, 255))
		ne.LightEmission = 0.3
		ne.Parent = np
		np.Parent = f
		h, e = np, ne
		splashHost, splashEmitter = np, ne
	end
	(h :: BasePart).CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0));
	(e :: ParticleEmitter):Emit(if reduced() then 4 else 10)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function rippleStep()
	if low() then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local now = os.clock()
	local chars: { Instance } = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(chars, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = chars
	for _, pl in Players:GetPlayers() do
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - cam.CFrame.Position).Magnitude < RIPPLE_NEAR then
			local v = root.AssemblyLinearVelocity
			local moving = Vector2.new(v.X, v.Z).Magnitude > 2
			if (moving or v.Y < -4) and now - (lastRipple[pl] or 0) >= RIPPLE_EVERY * 2 then
				local hit = Workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
				local wet = hit ~= nil and isWater(hit)
				if hit and wet then
					lastRipple[pl] = now
					if not inWater[pl] then
						splash(hit.Position)
					elseif moving then
						ripple(hit.Position)
					end
				end
				inWater[pl] = wet
			end
		end
	end
end

-- Zone weather ----------------------------------------------------------------------------------------------

local weatherPart: BasePart? = nil
local weatherKind = ""

type WeatherLook = { Box: Vector3, Up: number, Rate: number, Life: NumberRange, Speed: NumberRange, Size: NumberSequence, Colour: ColorSequence, Trans: NumberSequence, Accel: Vector3, Light: number, Spread: Vector2 }

local LOOKS: { [string]: WeatherLook } = {
	Snow = {
		Box = Vector3.new(90, 1, 90), Up = 26, Rate = 70, Life = NumberRange.new(6, 9), Speed = NumberRange.new(2, 4),
		Size = NumberSequence.new(0.28), Colour = ColorSequence.new(Color3.fromRGB(250, 252, 255)),
		Trans = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.15), NumberSequenceKeypoint.new(0.9, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Accel = Vector3.new(0.6, -1.5, 0.3), Light = 0.3, Spread = Vector2.new(25, 25),
	},
	Ash = {
		Box = Vector3.new(90, 1, 90), Up = 24, Rate = 45, Life = NumberRange.new(6, 9), Speed = NumberRange.new(1, 2.5),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.32) }),
		Colour = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 60)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(120, 112, 108)), ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 86, 84)) }),
		Trans = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.25), NumberSequenceKeypoint.new(0.85, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Accel = Vector3.new(0.4, -0.8, 0.2), Light = 0.15, Spread = Vector2.new(35, 35),
	},
	Stars = {
		Box = Vector3.new(260, 30, 260), Up = 70, Rate = 30, Life = NumberRange.new(3, 6), Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new(0.9), Colour = ColorSequence.new(Color3.fromRGB(235, 240, 255)),
		Trans = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(0.7, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Accel = Vector3.zero, Light = 1, Spread = Vector2.zero,
	},
}

local LANDMARK_WEATHER: { [string]: string } = { IceRocks = "Snow", LavaRocks = "Ash", Crystals = "Stars" }

local function wantWeather(): string
	local m = State.Match
	if not m or low() then
		return ""
	end
	local theme = (ZoneThemes.Themes :: any)[m.Tier]
	return if theme then LANDMARK_WEATHER[theme.Landmark] or "" else ""
end

local function setWeather(kind: string)
	if kind == weatherKind then
		return
	end
	weatherKind = kind
	if weatherPart then
		weatherPart:Destroy()
		weatherPart = nil
	end
	local look = LOOKS[kind]
	if not look then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Weather_" .. kind
	p.Size = look.Box
	p.Transparency = 1
	deco(p)
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = look.Rate * (if reduced() then 0.4 else 1)
	e.Lifetime = look.Life
	e.Speed = look.Speed
	e.Size = look.Size
	e.Color = look.Colour
	e.Transparency = look.Trans
	e.Acceleration = look.Accel
	e.LightEmission = look.Light
	e.LightInfluence = if kind == "Stars" then 0 else 0.6
	e.SpreadAngle = look.Spread
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = p
	p.Parent = folder()
	weatherPart = p
end

local function weatherStep()
	setWeather(wantWeather())
	local p = weatherPart
	local cam = Workspace.CurrentCamera
	if p and cam then
		local look = LOOKS[weatherKind]
		local c = cam.CFrame.Position
		p.CFrame = CFrame.new(c.X, c.Y + (if look then look.Up else 25), c.Z)
	end
end

-- Driver ----------------------------------------------------------------------------------------------------

local started = false
function WorldFx.start()
	if started then
		return
	end
	started = true
	for _, d in Workspace:GetDescendants() do
		if isDisplay(d) then
			watchDisplay(d)
		else
			checkSecret(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d.Name == "Display" then
			task.defer(function()
				if isDisplay(d) then
					watchDisplay(d)
				end
			end)
		elseif d.Name == MapNames.SecretEgg or d:GetAttribute("SecretEgg") == true then
			task.defer(checkSecret, d)
		end
	end)
	Players.PlayerRemoving:Connect(function(pl)
		lastRipple[pl] = nil
		inWater[pl] = nil
	end)
	local fxLow, fxReduced = low(), reduced()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			local on = not low()
			for i = #eggSparkles, 1, -1 do
				local e = eggSparkles[i]
				if e.Parent then
					e.Enabled = on
				else
					table.remove(eggSparkles, i)
				end
			end
		end
		if what == "Profile" and (low() ~= fxLow or reduced() ~= fxReduced) then
			fxLow, fxReduced = low(), reduced()
			weatherKind = "?" -- rebuild with the current settings
		end
		if what == "Profile" or what == "Match" then
			weatherStep()
		end
	end)
	require(script.Parent.PlayerDust).start()
	require(script.Parent.PortalFx).start()
	local accR, accW = 0, 0
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function(dt)
		accR += dt
		accW += dt
		if accR >= RIPPLE_EVERY then
			accR = 0
			rippleStep()
		end
		if accW >= 0.15 then
			accW = 0
			weatherStep()
			-- pedestal glow breathes gently (not with Reduce Motion / Low effects)
			if #glowParts > 0 and State.Match == nil then
				local still = reduced() or low()
				local t = os.clock() - t0
				for i, p in glowParts do
					p.Transparency = if still then 0.55 else 0.55 + 0.12 * math.sin(t * 2 + i)
				end
			end
		end
	end)
end

return WorldFx
