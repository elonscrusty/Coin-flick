--!strict
-- Tap combo counter (presentation only). Each crack the server accepted on the local player's own plate
-- (StationView's Hit event, hand mallets only) counts; hits that keep coming without a pause build a combo,
-- shown from x3 as a small "x5!" that pops above the nest and fades when the tapping stops.
-- Nothing here touches gameplay: the server's cadence decides how fast hits can come.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)

local TapCombo = {}

local GAP = 1.7 -- seconds between accepted hits that still keep the combo (mallet cadence is ~0.8 to 1.1 s)
local SHOW_FROM = 3
local LINGER = 1.1

local count = 0
local lastHit = 0
local popT = 0
local anchor: Part? = nil
local label: TextLabel? = nil
local conn: RBXScriptConnection? = nil

local function reduced(): boolean
	local s = State.Profile and State.Profile.Settings
	return s ~= nil and s.ReducedMotion == true
end

local function build(): (Part, TextLabel)
	if anchor and label and anchor.Parent then
		return anchor :: Part, label :: TextLabel
	end
	local a = Instance.new("Part")
	a.Name = "CT_Rocks_TapCombo"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one * 0.2
	a.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(96, 48)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Parent = a
	local t = UI.text(bb, "", {
		Font = UI.Head,
		TextSize = 34,
		TextColor3 = UI.Colors.Gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	t.TextWrapped = false
	local sc = Instance.new("UIScale")
	sc.Name = "Pop"
	sc.Parent = t
	anchor, label = a, t
	return a, t
end

local function step()
	local t = label
	if not t then
		return
	end
	local now = os.clock()
	local idle = now - lastHit
	if idle > LINGER + 0.4 then
		t.Visible = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		return
	end
	-- pop: a quick overshoot after each hit, then a fade once the taps stop
	local k = math.clamp((now - popT) / 0.18, 0, 1)
	local s = if reduced() then 1 else 1 + 0.35 * (1 - k) * (1 - k)
	local sc = t:FindFirstChild("Pop")
	if sc and sc:IsA("UIScale") then
		sc.Scale = s
	end
	t.TextTransparency = if idle > LINGER then math.clamp((idle - LINGER) / 0.4, 0, 1) else 0
end

-- One accepted hit on the own plate at `platePos`.
function TapCombo.hit(platePos: Vector3)
	local now = os.clock()
	count = if now - lastHit <= GAP then count + 1 else 1
	lastHit = now
	if count < SHOW_FROM then
		return
	end
	local a, t = build()
	a.CFrame = CFrame.new(platePos + Vector3.new(0, 2.4, 0))
	t.Text = "x" .. count .. "!"
	t.Visible = true
	popT = now
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
end

function TapCombo.clear()
	count = 0
	lastHit = 0
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if anchor then
		anchor:Destroy()
	end
	anchor, label = nil, nil
end

return TapCombo
