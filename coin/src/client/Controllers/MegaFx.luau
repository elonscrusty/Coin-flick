--!strict
-- The mega coin's show: slow spin, a wobble when tapped, a progress sign
-- above it, and a huge spinning jump when the whole server fills it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
local Sounds = require(script.Parent.Sounds)

local MegaFx = {}

local coin: BasePart? = nil
local base: CFrame = CFrame.new()
local sign: BillboardGui? = nil
local wobbleAt = -10
local flipAt = -10
local FLIP_TIME = 2.6

local function buildSign(part: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MegaSign"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(20, 3)
	-- Just above the coin's top edge (the HUD now keeps the middle of the screen clear).
	gui.StudsOffsetWorldSpace = Vector3.new(0, Config.MEGA_DIAMETER / 2 + 4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 48 -- up close only; the HUD chip shows the count
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "MEGA COIN - TAP IT!"
	title.TextColor3 = Color3.fromRGB(255, 220, 60)
	title.TextStrokeColor3 = Color3.fromRGB(45, 30, 20)
	title.TextStrokeTransparency = 0
	title.Parent = gui
	gui.Parent = part
	sign = gui
end

local function onFlipped()
	flipAt = os.clock()
	Sounds.play("Mega", 0.9)
	CameraView.shake(0.6, 1)
	local sparkle = coin and coin:FindFirstChild("Sparkle")
	if sparkle and sparkle:IsA("ParticleEmitter") then
		sparkle:Emit(400)
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
	if sign then
		-- The sign would fly off the top of the screen with the coin; the HUD chip shows the count.
		sign.Enabled = sinceFlip >= FLIP_TIME
	end
	if sinceFlip < FLIP_TIME then
		local u = sinceFlip / FLIP_TIME
		height = Config.MEGA_JUMP * 4 * u * (1 - u)
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
