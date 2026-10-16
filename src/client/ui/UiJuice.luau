--!strict
-- UI juice primitives shared by every panel and the HUD (the 2026-10-14 juice pass). UI.luau wires them into its
-- builders (buttons, cards, red dots, tab bars, cash readouts); Juice.luau builds the bigger effects (coin flights)
-- on top. Only TweenService: nothing here runs a per-frame loop while the screen is idle (a running tween is the
-- engine's job and stops on its own; the claim glow is one repeating tween on a stroke).
-- Reduce Motion (the game setting UI.Reduced, or Roblox's own ReducedMotion) skips every motion: the end state is
-- set at once. Pure numbers live in shared/UiMotion (tested offline).

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UiMotion = require(Shared.UiMotion)
local Theme = require(script.Parent.Theme)

local UiJuice = {}

-- UI installs the game's Reduce Motion flag here (UI requires this module, not the other way round).
UiJuice.gameReduced = function(): boolean
	return false
end

local function systemReduced(): boolean
	local ok, v = pcall(function()
		return (settings() :: any).ReducedMotion
	end)
	return ok and v == true
end

-- True when effects should be skipped (either reduced-motion setting is on).
function UiJuice.still(): boolean
	return not UiMotion.animate(UiJuice.gameReduced(), systemReduced())
end

-- Card shine: one white band sweeps across `obj` once (hover or select), then the band is removed. Rounded like
-- the card, on top of its picture, never takes input.
function UiJuice.sweep(obj: GuiObject, radius: number?)
	if UiJuice.still() or not obj.Parent or obj:FindFirstChild("Sweep") then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Sweep"
	f.BackgroundColor3 = Theme.Fx.Shine
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = obj.ZIndex + 6
	f.Active = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = f
	local g = Instance.new("UIGradient")
	g.Rotation = 25
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1.1, 0)
	g.Parent = f
	f.Parent = obj
	local tw = TweenService:Create(g, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Offset = Vector2.new(1.1, 0) })
	tw.Completed:Connect(function()
		f:Destroy()
	end)
	tw:Play()
end

-- Claimable glow: a ring frame over `b` whose stroke breathes (thicker and fainter, back again) while `b` exists.
-- Its own frame, so the button's border stroke stays as UI.paint draws it. Static ring under reduced motion.
function UiJuice.pulse(b: GuiObject, color: Color3?, radius: number?): Frame
	local old = b:FindFirstChild("ClaimGlow")
	if old and old:IsA("Frame") then
		return old
	end
	local ring = Instance.new("Frame")
	ring.Name = "ClaimGlow"
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Size = UDim2.fromScale(1, 1)
	ring.ZIndex = b.ZIndex
	ring.Active = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = ring
	local st = Instance.new("UIStroke")
	st.Color = color or Color3.fromRGB(255, 236, 130)
	st.Thickness = 3
	st.Transparency = 0.15
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = ring
	ring.Parent = b
	if not UiJuice.still() then
		TweenService:Create(st, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6, Transparency = 0.6 }):Play()
	end
	return ring
end

-- Red-dot wiggle: the badge tilts and springs back (elastic) when it appears or its number changes. Rotation only,
-- so it never fights the appear pop (scale) or the idle hop (position).
function UiJuice.wiggle(obj: GuiObject)
	if UiJuice.still() then
		obj.Rotation = 0
		return
	end
	obj.Rotation = -22
	TweenService:Create(obj, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
end

-- Tab switch: freshly built content starts `dx` studs to the side (UiMotion.slideFrom: the side of the tab that was
-- tapped) and glides home.
function UiJuice.slideIn(objs: { GuiObject }, dx: number)
	if dx == 0 or UiJuice.still() then
		return
	end
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, c in objs do
		local to = c.Position
		c.Position = to + UDim2.fromOffset(dx, 0)
		TweenService:Create(c, info, { Position = to }):Play()
	end
end

-- Number counter: `label` counts from `from` to `to` (up or down) over `duration` seconds, text from `fmt`. One
-- tween per label (a new value cancels the running count and starts from what is shown). Reduce Motion: instant.
local counting: { [TextLabel]: Tween } = {}
function UiJuice.countTo(label: TextLabel, from: number, to: number, fmt: (number) -> string, duration: number?)
	local running = counting[label]
	if running then
		running:Cancel()
		counting[label] = nil
	end
	if from == to or UiJuice.still() then
		label.Text = fmt(to)
		return
	end
	local a = Instance.new("NumberValue")
	a.Value = 0
	a.Changed:Connect(function(v: number)
		if label.Parent then
			label.Text = fmt(UiMotion.countValue(from, to, v))
		end
	end)
	local tw = TweenService:Create(a, TweenInfo.new(duration or 0.45, Enum.EasingStyle.Linear), { Value = 1 })
	counting[label] = tw
	tw.Completed:Connect(function(state: Enum.PlaybackState)
		if counting[label] == tw then
			counting[label] = nil
		end
		if state == Enum.PlaybackState.Completed and label.Parent then
			label.Text = fmt(to)
		end
		a:Destroy()
	end)
	label.Text = fmt(from)
	tw:Play()
end

return UiJuice
