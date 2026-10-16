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
	restReflectance: number,
	restMarks: { [Instance]: Color3 }, -- face marks/rims and their resting colors
	dressed: boolean,
}

local FlipFx = {}

local player = Players.LocalPlayer
local active: { [BasePart]: Anim } = {}
local POP_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAIN = 0.8 -- share of the flip spent in the air before the little bounce
local OTHERS_MAX_DISTANCE = 220

local function rollFor(face: unknown): number
	return if face == "skull" then -math.pi / 2 else math.pi / 2
end

local function easeOut(u: number): number
	return 1 - (1 - u) ^ 3
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
-- recolored marks, a sparkle trail and a glow. They grow evenly (never squished).
local function setMarks(anim: Anim, text: Color3?, rim: Color3?)
	for inst, restColor in anim.restMarks do
		if inst:IsA("TextLabel") then
			inst.TextColor3 = text or restColor
		elseif inst:IsA("UIStroke") then
			inst.Color = rim or restColor
		end
	end
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
		local sparkle = coin:FindFirstChild("Sparkle")
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle.Color = ColorSequence.new(look.sparkle[1], look.sparkle[2])
			sparkle.Size =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, look.sparkleSize), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Rate = look.trail
			sparkle.Enabled = look.trail > 0
		end
		if look.glow > 0 and not coin:FindFirstChild("RareGlow") then
			local glow = Instance.new("PointLight")
			glow.Name = "RareGlow"
			glow.Color = look.color
			glow.Brightness = look.glow
			glow.Range = 6 + anim.restSize.Y * rare.grow
			glow.Shadows = false
			glow.Parent = coin
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
	coin.Size = CoinLook.size(anim.restSize, CoinLook.scale(rare.grow, t, MAIN))
end

local function undressRare(anim: Anim)
	if not anim.dressed then
		return
	end
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
		sparkle.Color = ColorSequence.new(normal.sparkle[1], normal.sparkle[2])
		sparkle.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, normal.sparkleSize), NumberSequenceKeypoint.new(1, 0) })
	end
	local glow = coin:FindFirstChild("RareGlow")
	if glow then
		glow:Destroy()
	end
	for _, gui in coin:GetChildren() do
		local disc = gui:FindFirstChild("RainbowFace")
		if disc then
			disc:Destroy()
		end
	end
	anim.dressed = false
end

local function onFlipped(ev: FlipEvent)
	local folder = workspace:FindFirstChild("Tables")
	local model = folder and folder:FindFirstChild(`Table_{ev.ownerId}`)
	local coins = model and model:FindFirstChild("Coins")
	local coin = coins and coins:FindFirstChild(`Coin_{ev.coin}`)
	if not coin or not coin:IsA("BasePart") then
		return
	end
	local mine = ev.ownerId == player.UserId
	local camera = workspace.CurrentCamera
	if not mine and camera and (camera.CFrame.Position - coin.Position).Magnitude > OTHERS_MAX_DISTANCE then
		return -- too far to see; the server still puts it on the right face
	end
	local old = active[coin]
	if old then
		undressRare(old) -- a re-flip mid-air starts from the plain coin
	end
	local base = if old then old.base else coin.Position
	local restSize = if old then old.restSize else coin.Size
	local restColor = if old then old.restColor else coin.Color
	local restMaterial = if old then old.restMaterial else coin.Material
	local restReflectance = if old then old.restReflectance else coin.Reflectance
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
	local fromRoll = rollFor(coin:GetAttribute("Face"))
	local spins = 2 + math.floor(ev.duration * 2)
	local toRoll = rollFor(ev.result)
	active[coin] = {
		coin = coin,
		base = base,
		start = os.clock(),
		duration = ev.duration,
		fromRoll = fromRoll,
		totalRoll = (toRoll - fromRoll) + spins * math.pi * 2,
		height = 2 + ev.duration * 1.5, -- low arc keeps the coin in view in ZOOM
		event = ev,
		landed = false,
		mine = mine,
		rare = Economy.rarityDef(ev.rarity),
		restSize = restSize,
		restColor = restColor,
		restMaterial = restMaterial,
		restReflectance = restReflectance,
		restMarks = restMarks,
		dressed = false,
	}
	if mine then
		Sounds.play("Flip", 0.45)
	end
end

local function step()
	local now = os.clock()
	for coin, anim in active do
		if coin.Parent == nil then
			active[coin] = nil
			continue
		end
		local t = math.clamp((now - anim.start) / anim.duration, 0, 1)
		local height: number
		local roll: number
		if t < MAIN then
			local u = t / MAIN
			height = anim.height * 4 * u * (1 - u)
			roll = anim.fromRoll + anim.totalRoll * easeOut(u)
		else
			if not anim.landed then
				anim.landed = true
				onLanded(anim)
			end
			local u = (t - MAIN) / (1 - MAIN)
			height = anim.height * 0.12 * 4 * u * (1 - u) -- little bounce
			roll = anim.fromRoll + anim.totalRoll
		end
		dressRare(anim, now, t)
		-- Never let the spinning (or grown) coin cut into the table top.
		height += CoinLook.lift(roll, coin.Size.X, coin.Size.Y, anim.restSize.X, anim.restSize.Y)
		coin.CFrame = CFrame.new(anim.base + Vector3.new(0, height, 0)) * CFrame.Angles(0, 0, roll)
		if t >= 1 then
			undressRare(anim)
			coin.CFrame = CFrame.new(anim.base) * CFrame.Angles(0, 0, rollFor(anim.event.result))
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
