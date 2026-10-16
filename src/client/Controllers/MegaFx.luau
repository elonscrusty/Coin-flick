--!strict
-- The mega coin's show: slow spin, a wobble when tapped, a progress sign
-- above it, and a huge spinning jump when the whole server fills it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
local Sounds = require(script.Parent.Sounds)

local MegaFx = {}

local coin: BasePart? = nil
local base: CFrame = CFrame.new()
local bar: Frame? = nil
local countLabel: TextLabel? = nil
local wobbleAt = -10
local flipAt = -10
local FLIP_TIME = 2.6

local function buildSign(part: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MegaSign"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(18, 5)
	-- Just above the coin's top edge (the HUD now keeps the middle of the screen clear).
	gui.StudsOffsetWorldSpace = Vector3.new(0, Config.MEGA_DIAMETER / 2 + 3, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 48 -- up close only; from your yard the HUD shows the count
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.45)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "MEGA COIN - TAP IT!"
	title.TextColor3 = Color3.fromRGB(255, 220, 60)
	title.TextStrokeColor3 = Color3.fromRGB(45, 30, 20)
	title.TextStrokeTransparency = 0
	title.Parent = gui
	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.05, 0.55)
	track.Size = UDim2.fromScale(0.9, 0.4)
	track.BackgroundColor3 = Color3.fromRGB(70, 50, 40) -- dark, so the white count reads when the bar is empty
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0.5, 0)
	trackCorner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(45, 30, 20)
	stroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 210, 110)
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = track
	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromScale(1, 1)
	count.Font = Enum.Font.FredokaOne
	count.TextScaled = true
	count.TextColor3 = Color3.fromRGB(255, 255, 255)
	count.TextStrokeColor3 = Color3.fromRGB(45, 30, 20)
	count.TextStrokeTransparency = 0
	count.Text = ""
	count.ZIndex = 2
	count.Parent = track
	track.Parent = gui
	gui.Parent = part
	bar = fill
	countLabel = count
end

local function onState(state: Types.MegaState)
	if bar then
		bar.Size = UDim2.fromScale(math.clamp(state.taps / math.max(1, state.goal), 0, 1), 1)
	end
	if countLabel then
		countLabel.Text = `{state.taps} / {state.goal}`
	end
end

local function onFlipped()
	flipAt = os.clock()
	Sounds.play("Mega", 0.9)
	CameraView.shake(0.6, 1)
	local sparkle = coin and coin:FindFirstChild("Sparkle")
	if sparkle and sparkle:IsA("ParticleEmitter") then
		sparkle:Emit(120)
	end
end

local function step()
	local part = coin
	if not part then
		return
	end
	local now = os.clock()
	local height = 0
	local turn = 0
	local sinceFlip = now - flipAt
	if sinceFlip < FLIP_TIME then
		local u = sinceFlip / FLIP_TIME
		height = 6 * 4 * u * (1 - u)
		turn = FlipArc.megaSpin(u)
	end
	-- A face always points at you (swaying a little), so it is never an edge-on pole.
	local camera = workspace.CurrentCamera
	local facing = 0
	if camera then
		local away = camera.CFrame.Position - base.Position
		facing = FlipArc.megaFacing(away.X, away.Z)
	end
	local sway = math.sin(now * 1.3) * 0.35
	local wobble = 0
	local sinceTap = now - wobbleAt
	if sinceTap < 0.3 then
		wobble = math.sin(sinceTap * 40) * 0.08 * (1 - sinceTap / 0.3)
	end
	part.CFrame = CFrame.new(base.Position + Vector3.new(0, height, 0))
		* CFrame.Angles(0, math.pi / 2 + facing + sway + turn, 0)
		* CFrame.Angles(wobble, 0, 0)
end

-- Called by CoinTap when you tap the mega coin.
function MegaFx.poke()
	wobbleAt = os.clock()
end

function MegaFx.init()
	ClientNet.event("MegaState").OnClientEvent:Connect(onState)
	ClientNet.event("MegaFlipped").OnClientEvent:Connect(onFlipped)
end

function MegaFx.start()
	local model = workspace:WaitForChild("MegaCoin", 60)
	local part = model and model:WaitForChild("Coin", 10)
	if not part or not part:IsA("BasePart") then
		return
	end
	coin = part
	base = part.CFrame
	buildSign(part)
	RunService.RenderStepped:Connect(step)
end

return MegaFx
