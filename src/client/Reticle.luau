--!strict
-- The centre reticle (docs/m6/FIRST_PERSON.md section 3): one small dot in the middle of the view.
--   neutral      a quiet dot (exploring; nothing to say)
--   eligible     the dot opens into a ring: the press does something now (the single action button / prompt
--                pill says what; this does not repeat the label)
--   unavailable  a dim red ring and ONE concise reason, only when the ray is on something that cannot be
--                used right now (basket full, rubble bag full). Never a "move closer" while exploring.
-- The state comes from the same resolver as the action (PileView.context in a hunt, the prompt chosen by
-- PromptArbiter in the lobby), so the reticle can never disagree with what a press does. Hidden while any
-- panel is open, during the reveal and results, and outside first person.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AimResolve = require(Shared.AimResolve)
local State = require(script.Parent.State)
local CameraMode = require(script.Parent.CameraMode)
local PileView = require(script.Parent.PileView)
local PromptArbiter = require(script.Parent.PromptArbiter)
local UI = require(script.Parent.ui.UI)

local Reticle = {}

local player = Players.LocalPlayer
local C = UI.Colors

local gui: ScreenGui? = nil
local dot: Frame? = nil
local ring: Frame? = nil
local ringStroke: UIStroke? = nil
local edge: Frame? = nil -- dark ring under the amber one, so it reads on pastel eggs and the yellow nest
local edgeStroke: UIStroke? = nil
local plate: Frame? = nil
local reasonLabel: TextLabel? = nil
local clock = 0
local shown = ""
Reticle.Current = { State = "hidden", Reason = nil :: string? }

local function circle(parent: Instance, name: string, px: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(px, px)
	f.BorderSizePixel = 0
	f.Parent = parent
	local r = Instance.new("UICorner")
	r.CornerRadius = UDim.new(0.5, 0)
	r.Parent = f
	return f
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "CT_Reticle"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 3
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local d = circle(g, "Dot", 8)
	d.ZIndex = 3
	d.BackgroundColor3 = C.Text
	local ds = Instance.new("UIStroke")
	ds.Color = C.Outline
	ds.Thickness = 2
	ds.Transparency = 0
	ds.Parent = d
	dot = d
	-- the ring: a thick amber band with a dark edge on both sides (a thin yellow line vanished on pastel eggs)
	local e = circle(g, "RingEdge", 27)
	e.BackgroundTransparency = 1
	e.ZIndex = 1
	local es = Instance.new("UIStroke")
	es.Color = C.Outline
	es.Thickness = 8
	es.Transparency = 1
	es.Parent = e
	edge, edgeStroke = e, es
	local r = circle(g, "Ring", 30)
	r.BackgroundTransparency = 1
	r.ZIndex = 2
	local rs = Instance.new("UIStroke")
	rs.Color = C.Amber
	rs.Thickness = 3.5
	rs.Transparency = 1
	rs.Parent = r
	ring, ringStroke = r, rs
	local p = Instance.new("Frame")
	p.Name = "ReasonPlate"
	p.AnchorPoint = Vector2.new(0.5, 0)
	-- well under the crosshair (bugs #223, #224: right under the dot it covered the aim and stacked on the nest's
	-- name board when aiming at a nest)
	p.Position = UDim2.new(0.5, 0, 0.5, 72)
	p.Size = UDim2.fromOffset(300, 36)
	p.BackgroundColor3 = C.Panel
	p.BackgroundTransparency = 0.05
	p.BorderSizePixel = 0
	p.Visible = false
	p.Parent = g
	UI.corner(p, 8)
	UI.stroke(p, C.PanelEdge, 2)
	local rl = UI.text(p, "", { Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), Font = UI.Bold, TextSize = UI.T.Body, Outline = "Normal", TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text })
	rl.TextWrapped = false
	UI.fit(rl, UI.T.Body, UI.T.Small)
	reasonLabel = rl
	plate = p
end

local function set(stateName: string, reason: string?)
	local key = stateName .. "|" .. (reason or "")
	if key == shown then
		return
	end
	shown = key
	Reticle.Current = { State = stateName, Reason = reason }
	local g = gui
	if not g or not ring or not ringStroke or not edge or not edgeStroke or not dot or not plate or not reasonLabel then
		return
	end
	g.Enabled = stateName ~= "hidden"
	local info = TweenInfo.new(UI.Reduced and 0 or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local size, strokeT, color = 30, 1, C.Amber
	if stateName == "eligible" then
		size, strokeT, color = 30, 0.05, C.Amber
	elseif stateName == "unavailable" then
		size, strokeT, color = 24, 0.3, C.Red
	end
	if stateName == "neutral" or stateName == "hidden" then
		size, strokeT = 22, 1
	end
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(size, size) }):Play()
	TweenService:Create(ringStroke, info, { Transparency = strokeT, Color = color }):Play()
	-- the edge sits 1.5 px inside the amber band and 3 px outside it
	TweenService:Create(edge, info, { Size = UDim2.fromOffset(size - 3, size - 3) }):Play()
	TweenService:Create(edgeStroke, info, { Transparency = if strokeT >= 1 then 1 else math.max(strokeT, 0.15) }):Play()
	dot.BackgroundColor3 = if stateName == "eligible" then C.Amber elseif stateName == "unavailable" then C.Muted else C.Text
	plate.Visible = reason ~= nil
	reasonLabel.Text = reason or ""
end

-- What the reticle shows right now (pure of drawing; used by the loop and by checks).
function Reticle.evaluate(): (string, string?)
	if not CameraMode.firstPerson() or UI.blocked() or CameraMode.cursorFree() then -- third-person lobby, a menu, or the free-cursor key
		return "hidden", nil
	end
	local m = State.Match
	if m == nil then
		-- lobby: eligible exactly when a counter / kiosk prompt is offered (the pill names it)
		if PromptArbiter.stats().Winner ~= nil then
			return "eligible", nil
		end
		return "neutral", nil
	end
	if m.Phase ~= "Searching" and m.Phase ~= "Countdown" then
		return "hidden", nil
	end
	if m.Phase == "Countdown" then
		return "neutral", nil
	end
	local ctx = PileView.context()
	local r = AimResolve.reticle(ctx.Id, PileView.aimedAtSomething())
	return r.State, r.Reason
end

function Reticle.start()
	if gui then
		return
	end
	build()
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock < 0.08 then
			return
		end
		clock = 0
		local s, reason = Reticle.evaluate()
		set(s, reason)
	end)
	CameraMode.Changed.Event:Connect(function()
		local s, reason = Reticle.evaluate()
		set(s, reason)
	end)
end

return Reticle
