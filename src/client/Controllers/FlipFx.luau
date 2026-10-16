--!strict
-- The juicy part: coins jump, spin, bounce, sparkle and pop numbers.
-- Purely visual. The server already decided the result and tells us.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CoinLook = require(ReplicatedStorage.Shared.Util.CoinLook)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
local Sounds = require(script.Parent.Sounds)

type FlipEvent = Types.FlipEvent

type Anim = {
	coin: BasePart,
	base: Vector3,
	start: number,
	duration: number,
	fromRoll: number,
	totalRoll: number,
	height: number,
	event: FlipEvent,
	landed: boolean,
	mine: boolean,
	rare: Config.RarityDef?,
	-- How the coin looks at rest, so a rare flip can put it back.
	restSize: Vector3,
	restColor: Color3,
	restMaterial: Enum.Material,
	shadow: BasePart?,
	yaw: number, -- table's spin direction (FlipArc.spinYaw), set by the server
	restReflectance: number,
	restMarks: { [Instance]: Color3 }, -- face marks/rims and their resting colors
	dressed: boolean,
	grow: number, -- how big this coin may get on its slot (capped so it never touches neighbours)
}

local FlipFx = {}

local player = Players.LocalPlayer
local active: { [BasePart]: Anim } = {}
local POP_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAIN = FlipArc.MAIN
local OTHERS_MAX_DISTANCE = 220

local function rollFor(face: unknown): number
	return FlipArc.restRoll(face)
end

local function easeOut(u: number): number
	return 1 - (1 - u) ^ 3
end

-- Flight extras (made on this client only): a soft glow trail and a shadow
-- on the table that shrinks as the coin goes up.
local fxFolder: Folder? = nil
local function fxParent(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = Instance.new("Folder")
	f.Name = "CoinFlickFx"
	f.Parent = workspace
	fxFolder = f
	return f
end

local function trailOn(coin: BasePart, on: boolean)
	local trail = coin:FindFirstChild("FlipTrail")
	-- Thin ribbon on the spin axis (never wider than the coin, never a slab), re-fitted every flip.
	local r = CoinLook.trailHalfWidth(coin.Size.Y)
	if not trail then
		if not on then
			return
		end
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA"
		a0.Parent = coin
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailB"
		a1.Parent = coin
		local t = Instance.new("Trail")
		t.Name = "FlipTrail"
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Lifetime = 0.3
		t.LightEmission = 0.35
		t.FaceCamera = true
		t.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 200, 60))
		t.Transparency = NumberSequence.new(0.35, 1)
		t.WidthScale = NumberSequence.new(1, 0.2)
		t.Parent = coin
		trail = t
	end
	local a0 = coin:FindFirstChild("TrailA")
	local a1 = coin:FindFirstChild("TrailB")
	if a0 and a0:IsA("Attachment") and a1 and a1:IsA("Attachment") then
		a0.Position = Vector3.new(0, 0, -r)
		a1.Position = Vector3.new(0, 0, r)
	end
	if trail and trail:IsA("Trail") then
		trail.Enabled = on
	end
end

local function makeShadow(coin: BasePart, base: Vector3): BasePart
	local d = coin.Size.Y
	local shadow = Instance.new("Part")
	shadow.Name = "CoinShadow"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CastShadow = false
	shadow.Material = Enum.Material.SmoothPlastic
	shadow.Color = Color3.fromRGB(40, 25, 15)
	shadow.Transparency = FlipArc.shadowFade(0)
	shadow.Size = Vector3.new(0.04, d, d)
	-- Just above the table top (the coin's rest centre is half a coin above it).
	shadow.CFrame = CFrame.new(base - Vector3.new(0, Config.COIN_THICKNESS / 2 - 0.03, 0))
		* CFrame.Angles(0, 0, math.pi / 2)
	shadow.Parent = fxParent()
	return shadow
end

local function popText(coin: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = coin
	gui.Size = UDim2.fromScale(math.max(5, #text * 0.6), 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(40, 30, 20)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(gui, POP_INFO, { StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0) }):Play()
	TweenService:Create(label, POP_INFO, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(POP_INFO.Time, function()
		gui:Destroy()
	end)
end

local function onLanded(anim: Anim)
	local ev = anim.event
	if not anim.mine then
		return
	end
	Sounds.play("Land", 0.5)
	local rare = anim.rare
	if rare then
		Sounds.play("Rare", if rare.shout then 0.9 else 0.5)
		CameraView.shake(if rare.id == "giant" then 0.9 else 0.25, if rare.shout then 0.8 else 0.3)
		local prize = if ev.result == "heads" then `+${Format.short(ev.cash)}` else `+{ev.hats} 🎩`
		popText(anim.coin, `{rare.name}! {prize}`, rare.color)
		local sparkle = anim.coin:FindFirstChild("Sparkle")
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle:Emit(CoinLook.forRarity(rare.id).landBurst)
		end
		return
	end
	if ev.result == "heads" then
		Sounds.play("Heads", 0.7)
		popText(anim.coin, `+${Format.short(ev.cash)}`, Color3.fromRGB(120, 255, 120))
		local sparkle = anim.coin:FindFirstChild("Sparkle")
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle:Emit(CoinLook.NORMAL.landBurst)
		end
	else
		Sounds.play("Skull", 0.45)
		popText(anim.coin, `+{ev.hats} 🎩`, Color3.fromRGB(220, 160, 255))
	end
end

-- Rare coins wear their CoinLook in the air: color (rainbow cycles), shine,
-- recolored marks, a sparkle trail and an outline. They grow evenly (never squished).
local function setMarks(anim: Anim, text: Color3?, rim: Color3?)
	for inst, restColor in anim.restMarks do
		if inst:IsA("TextLabel") then
			inst.TextColor3 = text or restColor
		elseif inst:IsA("UIStroke") then
			inst.Color = rim or restColor
		end
	end
end

local function sparkleColors(colors: { Color3 }): ColorSequence
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return ColorSequence.new(keys)
end

-- Paint every rainbow color across both faces (behind the marks).
local function paintRainbow(coin: BasePart)
	local stops = CoinLook.rainbowStops(6)
	local keys = {}
	for i, c in stops do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / #stops, c))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, stops[1]))
	for _, gui in coin:GetChildren() do
		if gui:IsA("SurfaceGui") then
			local disc = Instance.new("Frame")
			disc.Name = "RainbowFace"
			disc.AnchorPoint = Vector2.new(0.5, 0.5)
			disc.Position = UDim2.fromScale(0.5, 0.5)
			disc.Size = UDim2.fromScale(0.94, 0.94)
			disc.BackgroundColor3 = Color3.new(1, 1, 1)
			disc.BorderSizePixel = 0
			disc.ZIndex = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = disc
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(keys)
			gradient.Parent = disc
			disc.Parent = gui
		end
	end
end

-- A ring of stars around both faces (gold coins).
local function paintStars(coin: BasePart, color: Color3)
	for _, gui in coin:GetChildren() do
		if gui:IsA("SurfaceGui") then
			local ring = Instance.new("Frame")
			ring.Name = "StarRing"
			ring.Size = UDim2.fromScale(1, 1)
			ring.BackgroundTransparency = 1
			ring.ZIndex = 3
			for _, spot in CoinLook.starRing(10, 0.34) do
				local star = Instance.new("TextLabel")
				star.AnchorPoint = Vector2.new(0.5, 0.5)
				star.Position = UDim2.fromScale(spot.x, spot.y)
				star.Size = UDim2.fromScale(0.14, 0.14)
				star.BackgroundTransparency = 1
				star.Text = "★"
				star.TextScaled = true
				star.Font = Enum.Font.FredokaOne
				star.TextColor3 = color
				star.TextStrokeColor3 = Color3.fromRGB(90, 35, 0)
				star.TextStrokeTransparency = 0
				star.Parent = ring
			end
			ring.Parent = gui
		end
	end
end

local function dressRare(anim: Anim, now: number, t: number)
	local rare = anim.rare
	if not rare then
		return
	end
	local coin = anim.coin
	local look = CoinLook.forRarity(rare.id)
	if not anim.dressed then
		anim.dressed = true
		coin.Material = Enum.Material:FromName(look.material) or Enum.Material.SmoothPlastic
		coin.Reflectance = look.reflectance
		setMarks(anim, look.text, look.rim)
		if look.rainbow then
			paintRainbow(coin)
		end
		if look.stars then
			paintStars(coin, Color3.fromRGB(255, 250, 200))
		end
		local sparkle = coin:FindFirstChild("Sparkle")
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle.Color = sparkleColors(look.sparkle)
			sparkle.LightEmission = CoinLook.SPARKLE_LIGHT
			sparkle.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, look.sparkleSize),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Rate = look.trail
			sparkle.Enabled = look.trail > 0
		end
		-- Outline hugs the coin only. (A PointLight here lit the whole table pale yellow.)
		if look.outline and not coin:FindFirstChild("RareOutline") then
			local outline = Instance.new("Highlight")
			outline.Name = "RareOutline"
			outline.Adornee = coin
			outline.FillTransparency = 1
			outline.OutlineColor = look.outline
			outline.OutlineTransparency = 0
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.Parent = coin
		end
	end
	coin.Color = if look.rainbow then CoinLook.rainbowColor(now) else look.color
	if look.rainbow then
		for _, gui in coin:GetChildren() do
			local disc = gui:FindFirstChild("RainbowFace")
			local gradient = disc and disc:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Rotation = (now * 360) % 360 -- colors swirl while it spins
			end
		end
	end
	coin.Size = CoinLook.size(anim.restSize, CoinLook.scale(anim.grow, t, MAIN))
	local ridge = coin:FindFirstChild("RareRidge")
	if not ridge then
		local part = Instance.new("Part")
		part.Name = "RareRidge"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = coin
		ridge = part
	end
	if ridge and ridge:IsA("BasePart") then
		local thickness, diameter = CoinLook.ridge(coin.Size.X, coin.Size.Y)
		ridge.Size = Vector3.new(thickness, diameter, diameter)
		ridge.Color = if look.rainbow then CoinLook.darker(CoinLook.rainbowColor(now + 0.5), 0.55) else look.rim
	end
end

local function undressRare(anim: Anim)
	local coin = anim.coin
	coin.Size = anim.restSize
	coin.Color = anim.restColor
	coin.Material = anim.restMaterial
	coin.Reflectance = anim.restReflectance
	setMarks(anim, nil, nil)
	local normal = CoinLook.NORMAL
	local sparkle = coin:FindFirstChild("Sparkle")
	if sparkle and sparkle:IsA("ParticleEmitter") then
		sparkle.Enabled = false
		sparkle.Rate = 0
		-- Particles already thrown keep their colors; new ones use the plain look.
		sparkle.Color = sparkleColors(normal.sparkle)
		sparkle.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, normal.sparkleSize), NumberSequenceKeypoint.new(1, 0) })
	end
	local outline = coin:FindFirstChild("RareOutline")
	if outline then
		outline:Destroy()
	end
	local ridge = coin:FindFirstChild("RareRidge")
	if ridge then
		ridge:Destroy()
	end
	for _, gui in coin:GetChildren() do
		for _, name in { "RainbowFace", "StarRing" } do
			local extra = gui:FindFirstChild(name)
			if extra then
				extra:Destroy()
			end
		end
	end
	anim.dressed = false
end

-- The coin's resting look, from the attributes the server put on it (falls back to the part itself).
local function restOf<T>(coin: BasePart, name: string, fallback: T): T
	local value = coin:GetAttribute(name)
	if value ~= nil and typeof(value) == typeof(fallback) then
		return value :: any
	end
	return fallback
end

local function onFlipped(ev: FlipEvent)
	local folder = workspace:FindFirstChild("Tables")
	local model = folder and folder:FindFirstChild(`Table_{ev.ownerId}`)
	local coins = model and model:FindFirstChild("Coins")
	local coin = coins and coins:FindFirstChild(`Coin_{ev.coin}`)
	if not coin or not coin:IsA("BasePart") then
		return
	end
	local yawAttr = model and model:GetAttribute("SpinYaw")
	local mine = ev.ownerId == player.UserId
	local camera = workspace.CurrentCamera
	if not mine and camera and (camera.CFrame.Position - coin.Position).Magnitude > OTHERS_MAX_DISTANCE then
		return -- too far to see; the server still puts it on the right face
	end
	local old = active[coin]
	if old then
		undressRare(old) -- a re-flip mid-air starts from the plain coin
	end
	-- The slot the coin always returns to (from the server), never wherever the part happens to be.
	local base = restOf(coin, "RestPos", if old then old.base else coin.Position)
	local restSize = restOf(coin, "RestSize", coin.Size)
	local restColor = restOf(coin, "RestColor", coin.Color)
	local restMaterial = Enum.Material:FromName(restOf(coin, "RestMaterial", coin.Material.Name)) or coin.Material
	local restReflectance = restOf(coin, "RestReflectance", coin.Reflectance)
	local restMarks: { [Instance]: Color3 } = if old then old.restMarks else {}
	if not old then
		for _, d in coin:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Mark" then
				restMarks[d] = d.TextColor3
			elseif d:IsA("UIStroke") then
				restMarks[d] = d.Color
			end
		end
	end
	local rare = Economy.rarityDef(ev.rarity)
	local fromRoll = rollFor(coin:GetAttribute("Face"))
	local spins = FlipArc.spins(ev.duration)
	local toRoll = rollFor(ev.result)
	active[coin] = {
		coin = coin,
		base = base,
		start = os.clock(),
		duration = ev.duration,
		fromRoll = fromRoll,
		totalRoll = (toRoll - fromRoll) + spins * math.pi * 2,
		height = Config.FLIP_HEIGHT, -- the ZOOM camera is placed so this always fits (CameraMath)
		event = ev,
		landed = false,
		mine = mine,
		rare = rare,
		restSize = restSize,
		restColor = restColor,
		restMaterial = restMaterial,
		yaw = if typeof(yawAttr) == "number" then yawAttr else 0,
		shadow = if old and old.shadow then old.shadow else makeShadow(coin, base),
		restReflectance = restReflectance,
		restMarks = restMarks,
		dressed = false,
		grow = CoinLook.growFor(rare and rare.grow or 1, coin:GetAttribute("CoinIndex") :: number? or 1, restSize.Y),
	}
	trailOn(coin, true)
	if mine then
		Sounds.play("Flip", 0.45)
	end
end

local function step()
	local now = os.clock()
	for coin, anim in active do
		if coin.Parent == nil then
			if anim.shadow then
				anim.shadow:Destroy()
			end
			active[coin] = nil
			continue
		end
		local t = math.clamp((now - anim.start) / anim.duration, 0, 1)
		local height = FlipArc.height(t, anim.height)
		local roll: number
		if t < MAIN then
			roll = anim.fromRoll + anim.totalRoll * easeOut(t / MAIN)
		else
			if not anim.landed then
				anim.landed = true
				local drift = Vector3.new(coin.Position.X - anim.base.X, 0, coin.Position.Z - anim.base.Z).Magnitude
				if Config.LOG_COIN_DRIFT and drift > 0.3 then
					warn(
						`CoinFlick: {coin.Name} landed {string.format("%.2f", drift)} studs off its slot (snapped back)`
					)
				end
				trailOn(coin, false)
				onLanded(anim)
			end
			roll = anim.fromRoll + anim.totalRoll
		end
		local shadow = anim.shadow
		if shadow then
			local d = anim.restSize.Y * FlipArc.shadowScale(height, anim.height)
			shadow.Size = Vector3.new(shadow.Size.X, d, d)
			shadow.Transparency = FlipArc.shadowFade(height, anim.height)
		end
		if not pcall(dressRare, anim, now, t) then
			warn("CoinFlick: rare coin look failed (the coin still lands normally)")
		end
		-- Never let the spinning (or grown) coin cut into the table top.
		height = CoinLook.flightHeight(height, roll, coin.Size.X, coin.Size.Y, anim.restSize.X, anim.restSize.Y)
		coin.CFrame = CFrame.new(anim.base + Vector3.new(0, height, 0))
			* CFrame.Angles(0, anim.yaw, 0)
			* CFrame.Angles(0, 0, roll)
		local ridge = coin:FindFirstChild("RareRidge")
		if ridge and ridge:IsA("BasePart") then
			ridge.CFrame = coin.CFrame
		end
		if t >= 1 then
			undressRare(anim)
			-- Landing: always the slot's rest pose for this result, whatever happened in the air.
			coin.CFrame = CFrame.new(anim.base)
				* CFrame.Angles(0, restOf(coin, "RestYaw", anim.yaw), 0)
				* CFrame.Angles(0, 0, rollFor(anim.event.result))
			if anim.shadow then
				anim.shadow:Destroy()
			end
			active[coin] = nil
		end
	end
end

-- True while one of your coins is still in the air (skip pointless taps).
function FlipFx.isFlying(coin: BasePart): boolean
	return active[coin] ~= nil
end

function FlipFx.init()
	ClientNet.event("Flipped").OnClientEvent:Connect(onFlipped)
	RunService.RenderStepped:Connect(step)
end

return FlipFx
