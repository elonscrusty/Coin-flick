--!strict
-- The living sky: clouds, balloons and floating islands (tagged "SkyBob" by the server) bob and
-- turn gently, and the haze takes the colour of the yard you stand in. Looks only; the server
-- decides nothing here.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PlotThemes = require(ReplicatedStorage.Shared.Util.PlotThemes)

local SkyFx = {}

local TAG = "SkyBob"
local TINT_TIME = 1.2

type Bobber = { model: Model, base: CFrame, amp: number, speed: number, spin: number, phase: number }

local bobbers: { [Model]: Bobber } = {}
local shownTheme = ""

local function add(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance
	bobbers[model] = {
		model = model,
		base = model:GetPivot(),
		amp = (model:GetAttribute("BobAmp") :: number?) or 1,
		speed = (model:GetAttribute("BobSpeed") :: number?) or 0.3,
		spin = (model:GetAttribute("BobSpin") :: number?) or 0,
		phase = (model:GetAttribute("BobPhase") :: number?) or 0,
	}
end

-- The theme id of the table this player owns, if it exists yet.
local function ownTheme(): string?
	local tables = workspace:FindFirstChild("Tables")
	if not tables then
		return nil
	end
	local model = tables:FindFirstChild(`Table_{Players.LocalPlayer.UserId}`)
	return model and (model:GetAttribute("PlotTheme") :: string?)
end

local function applyTheme(id: string)
	if id == shownTheme then
		return
	end
	shownTheme = id
	local theme = PlotThemes.get(id)
	if not theme then
		return
	end
	local info = TweenInfo.new(TINT_TIME, Enum.EasingStyle.Sine)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = theme.sky.atmosphere, Decay = theme.sky.decay }):Play()
	end
	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if color then
		TweenService:Create(color, info, { TintColor = theme.sky.tint }):Play()
	end
end

function SkyFx.init()
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		if instance:IsA("Model") then
			bobbers[instance] = nil
		end
	end)
end

function SkyFx.start()
	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, bob in bobbers do
			if model.Parent then
				local lift = math.sin(now * bob.speed * math.pi * 2 + bob.phase) * bob.amp
				local turn = if bob.spin ~= 0 then now * bob.spin else 0
				model:PivotTo(bob.base * CFrame.new(0, lift, 0) * CFrame.Angles(0, turn, 0))
			end
		end
		if now - lastCheck > 1 then
			lastCheck = now
			local id = ownTheme()
			if id then
				applyTheme(id)
			end
		end
	end)
end

return SkyFx
