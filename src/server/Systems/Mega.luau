--!strict
-- The shared MEGA coin in the middle of the server. Everyone taps the same
-- coin; when the server's taps reach the goal it flips (always a happy flip,
-- no chance involved). Everyone who tapped gets a reward, and the whole
-- server gets 2x cash for a minute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MegaLook = require(ReplicatedStorage.Shared.Util.MegaLook)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local MegaCoin = require(script.Parent.Parent.Util.MegaCoin)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Mega = {}

local counter = MegaCoin.new()
local limiter = RateLimiter.new(Config.MEGA_TAP_RATE, Config.MEGA_TAP_BURST, os.clock)
local flipping = false
local dirty = true

local DEBUG_LEFTOVER = 3 -- Studio MEGA button stops this many taps short first

local function goal(): number
	return Economy.megaGoal(#Players:GetPlayers())
end

-- One face of the mega coin: gold gradient disc, a raised rim ring and a bright inner ring,
-- a ring of stars, a big emblem ($ or star) and a white shine bar. See Util/MegaLook.
local function coinFace(parent: BasePart, face: Enum.NormalId, emblem: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = `Face_{face.Name}`
	gui.Face = face
	gui.LightInfluence = 0.2
	gui.CanvasSize = Vector2.new(400, 400)
	gui.Parent = parent

	local function disc(name: string, scale: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(scale, scale)
		frame.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		frame.Parent = gui
		return frame
	end

	local base = disc("Gold", MegaLook.RIM_SCALE)
	base.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(MegaLook.FACE_TOP, MegaLook.FACE_BOTTOM)
	gradient.Parent = base
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Thickness = 26
	rim.Color = MegaLook.RIM
	rim.Parent = base

	local ring = disc("Ring", MegaLook.RING_SCALE)
	ring.BackgroundTransparency = 1
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 7
	ringStroke.Color = MegaLook.RING
	ringStroke.Parent = ring

	for _, spot in MegaLook.starSpots() do
		local star = Instance.new("TextLabel")
		star.Name = "Star"
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(spot.x, spot.y)
		star.Size = UDim2.fromScale(0.09, 0.09)
		star.BackgroundTransparency = 1
		star.Text = "★"
		star.TextScaled = true
		star.Font = Enum.Font.FredokaOne
		star.TextColor3 = MegaLook.STAR
		star.TextStrokeColor3 = MegaLook.STAR_STROKE
		star.TextStrokeTransparency = 0
		star.Parent = gui
	end

	local label = Instance.new("TextLabel")
	label.Name = "Emblem"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(MegaLook.EMBLEM_SCALE, MegaLook.EMBLEM_SCALE)
	label.BackgroundTransparency = 1
	label.Text = emblem
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = MegaLook.EMBLEM
	label.TextStrokeColor3 = MegaLook.EMBLEM_STROKE
	label.TextStrokeTransparency = 0
	label.Parent = gui

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.3, 0.3)
	shine.Size = UDim2.fromScale(0.1, 0.8)
	shine.Rotation = 40
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = MegaLook.SHINE_ALPHA
	shine.BorderSizePixel = 0
	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0.5, 0)
	shineCorner.Parent = shine
	shine.Parent = gui
end

local function build()
	local model = Instance.new("Model")
	model.Name = "MegaCoin"
	local make = World.makePart
	-- Chunky stepped pedestal.
	local steps = {
		{ height = 1.2, diameter = 20, color = Color3.fromRGB(255, 255, 255) },
		{ height = 1.2, diameter = 16, color = Color3.fromRGB(90, 200, 255) },
		{ height = 0.8, diameter = 12, color = Color3.fromRGB(255, 120, 190) },
	}
	local y = 0
	for i, step in steps do
		local part = make({
			Name = `Step{i}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(step.height, step.diameter, step.diameter),
			CFrame = CFrame.new(0, y + step.height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = step.color,
		})
		part.Parent = model
		y += step.height
	end
	-- The coin stands on its edge, facing the spawn. The client spins it.
	local coin = make({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, Config.MEGA_DIAMETER, Config.MEGA_DIAMETER),
		CFrame = CFrame.new(0, Config.MEGA_HEIGHT, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color = MegaLook.BASE,
		Material = Enum.Material.Foil,
		Reflectance = MegaLook.REFLECTANCE,
		CanCollide = false,
		CanQuery = false,
	})
	coinFace(coin, Enum.NormalId.Right, "$")
	coinFace(coin, Enum.NormalId.Left, "★")
	-- A darker ridge ring around the edge (welded, so it follows the coin when the client moves it).
	local ridgeThickness, ridgeDiameter = MegaLook.ridge(coin.Size.X, coin.Size.Y)
	local ridge = make({
		Name = "Ridge",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(ridgeThickness, ridgeDiameter, ridgeDiameter),
		CFrame = coin.CFrame,
		Color = MegaLook.RIDGE,
		Material = Enum.Material.Foil,
		Anchored = false,
		Massless = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = coin
	weld.Part1 = ridge
	weld.Parent = ridge
	ridge.Parent = model
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Rate = MegaLook.SPARKLE_RATE
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(4, 10)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, MegaLook.SPARKLE_SIZE), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 255, 255))
	sparkle.LightEmission = 0.5
	sparkle.Parent = coin
	coin.Parent = model

	-- A big still ball for taps (the coin itself moves on each client).
	local hitbox = make({
		Name = "Hitbox",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (Config.MEGA_DIAMETER + 2),
		Position = Vector3.new(0, Config.MEGA_HEIGHT, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = true,
		CastShadow = false,
	})
	hitbox:SetAttribute("Mega", true)
	hitbox.Parent = model
	model.Parent = workspace
end

local function notify(player: Player, text: string)
	local notice: Types.Notice = { kind = "mega", text = text }
	Net.event("Notice"):FireClient(player, notice)
end

local function megaFlip()
	Net.event("MegaFlipped"):FireAllClients()
	local helpers = counter:finish()
	Boosts.startMega(os.clock())
	dirty = true
	local helped: { [number]: boolean } = {}
	for _, userId in helpers do
		helped[userId] = true
		local player = Players:GetPlayerByUserId(userId)
		local profile = player and PlayerData.get(player)
		if player and profile then
			local cash, hats = GameLogic.megaReward(profile)
			PlayerData.changed(player)
			notify(player, `MEGA FLIP! You got +${Format.short(cash)} and +{hats} 🎩. 2x cash for everyone!`)
		end
	end
	for _, player in Players:GetPlayers() do
		if not helped[player.UserId] then
			notify(player, "MEGA FLIP! 2x cash for everyone! Tap the mega coin next time for a prize!")
		end
	end
	task.wait(3) -- let the big flip finish before counting again
	flipping = false
	dirty = true
end

local function onTap(player: Player)
	if flipping or not limiter:allow(player) or not PlayerData.get(player) then
		return
	end
	dirty = true
	if counter:tap(player.UserId, goal()) then
		flipping = true
		task.spawn(megaFlip)
	end
end

-- Studio test button: flip the mega coin now (this player counts as a helper).
function Mega.debugFlip(player: Player)
	if flipping then
		return
	end
	if MegaCoin.debugStep(counter.taps, goal(), DEBUG_LEFTOVER) == "charge" then
		counter.taps = goal() - DEBUG_LEFTOVER
		dirty = true
		return
	end
	counter:tap(player.UserId, 1)
	flipping = true
	task.spawn(megaFlip)
end

function Mega.init()
	build()
	Net.event("TapMega").OnServerEvent:Connect(onTap)
	Players.PlayerAdded:Connect(function()
		dirty = true
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		counter:forget(player.UserId)
		limiter:remove(player)
		dirty = true
	end)
end

function Mega.start()
	local stateRemote = Net.event("MegaState")
	local lastSent = 0
	while true do
		task.wait(0.25)
		local now = os.clock()
		local boostLeft = Boosts.megaLeft(now)
		-- Send on change, plus once a second while the boost counts down.
		if dirty or (boostLeft > 0 and now - lastSent >= 1) then
			dirty = false
			lastSent = now
			local state: Types.MegaState = {
				taps = counter.taps,
				goal = goal(),
				boostLeft = boostLeft,
			}
			stateRemote:FireAllClients(state)
		end
	end
end

return Mega
