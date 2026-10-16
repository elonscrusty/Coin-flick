--!strict
-- The juicy part: coins jump, spin, bounce, sparkle and pop numbers.
-- Purely visual. The server already decided the result and tells us.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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
			sparkle:Emit(if rare.shout then 80 else 30)
		end
		return
	end
	if ev.result == "heads" then
		Sounds.play("Heads", 0.7)
		popText(anim.coin, `+${Format.short(ev.cash)}`, Color3.fromRGB(120, 255, 120))
		local sparkle = anim.coin:FindFirstChild("Sparkle")
		if sparkle and sparkle:IsA("ParticleEmitter") then
			sparkle:Emit(14)
		end
	else
		Sounds.play("Skull", 0.45)
		popText(anim.coin, `+{ev.hats} 🎩`, Color3.fromRGB(220, 160, 255))
	end
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
	local base = if old then old.base else coin.Position
	local restSize = if old then old.restSize else coin.Size
	local restColor = if old then old.restColor else coin.Color
	local restMaterial = if old then old.restMaterial else coin.Material
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
	}
	if mine then
		Sounds.play("Flip", 0.45)
	end
end

-- Rare coins change color (rainbow cycles) and puff up while in the air.
local function dressRare(anim: Anim, now: number, t: number)
	local rare = anim.rare
	if not rare then
		return
	end
	local coin = anim.coin
	if rare.id == "rainbow" or rare.id == "giant" then
		coin.Material = Enum.Material.Neon
	end
	coin.Color = if rare.id == "rainbow" then Color3.fromHSV((now * 1.5) % 1, 0.75, 1) else rare.color
	-- Grow fast, stay big, shrink back during the bounce.
	local puff = if t < 0.15 then t / 0.15 elseif t < MAIN then 1 else math.max(0, 1 - (t - MAIN) / (1 - MAIN))
	local scale = 1 + (rare.grow - 1) * puff
	coin.Size = Vector3.new(anim.restSize.X * math.sqrt(scale), anim.restSize.Y * scale, anim.restSize.Z * scale)
end

local function undressRare(anim: Anim)
	if anim.rare then
		anim.coin.Size = anim.restSize
		anim.coin.Color = anim.restColor
		anim.coin.Material = anim.restMaterial
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
