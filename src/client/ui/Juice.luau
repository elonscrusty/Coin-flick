--!strict
-- Client-only UI juice shared by the panels: big pop-in banners ("10 EGGS LEFT!"), confetti and coin bursts, a
-- checkmark stamp, a waiting shake, and a slow turntable for 3D pet cards. Presentation only: nothing here sends
-- anything to the server or reads anything the server has not already shown the player.
-- Every effect cleans itself up (Debris), keeps its particle count small, and respects Reduce Motion (UI.Reduced).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local UiMotion = require(Shared.UiMotion)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local UiJuice = require(script.Parent.UiJuice)

local TC = Theme.Color

local Juice = {}

-- Logical centre of `src` inside its own ScreenGui (the layers carry a UIScale, so absolute pixels are divided
-- back by it). Effects are parented to that ScreenGui so they fly over scrollers and panel edges.
local function anchor(src: GuiObject): (ScreenGui?, Vector2)
	local sg = src:FindFirstAncestorOfClass("ScreenGui")
	if not sg then
		return nil, Vector2.zero
	end
	local sc = if UI.Scale > 0 then UI.Scale else 1
	local c = src.AbsolutePosition + src.AbsoluteSize / 2 - sg.AbsolutePosition
	return sg, c / sc
end

local function fxLayer(sg: ScreenGui): Frame
	local f = Instance.new("Frame")
	f.Name = "Juice"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 50
	f.Parent = sg
	return f
end

-- Big pop-in banner across the upper middle of the screen (notice layer): springs in, holds, fades.
function Juice.banner(text: string, color: Color3?, hold: number?)
	local root = UI.noticeLayer()
	local old = root:FindFirstChild("JuiceBanner")
	if old then
		old:Destroy()
	end
	local f = UI.frame(root, {
		Name = "JuiceBanner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(0.9, 0, 0, 64), BackgroundTransparency = 1, ZIndex = 40,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(560, 64)
	lim.Parent = f
	local l = UI.text(f, text, { Name = "Text", Font = UI.Head, TextSize = 48, TextColor3 = color or TC.Gold, Outline = "Strong", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 41 })
	l.TextWrapped = false
	l.Rotation = if UI.Reduced then 0 else -4
	UI.pop(f, 0.3)
	if not UI.Reduced then
		TweenService:Create(l, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end
	local stay = hold or 1.8
	task.delay(stay, function()
		if not f.Parent then
			return
		end
		local info = TweenInfo.new(0.3)
		TweenService:Create(l, info, { TextTransparency = 1 }):Play()
		local o = l:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			TweenService:Create(o, info, { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(f, stay + 0.4)
end

-- One flying piece: up and out with an ease out, then down with an ease in, spinning and fading.
local function fling(layer: Frame, piece: GuiObject, from: Vector2, dx: number, up: number, fall: number, life: number)
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Position = UDim2.fromOffset(from.X, from.Y)
	piece.Parent = layer
	local top = from + Vector2.new(dx * 0.6, -up)
	local a = TweenService:Create(piece, TweenInfo.new(life * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(top.X, top.Y), Rotation = piece.Rotation + dx,
	})
	a.Completed:Connect(function()
		if piece.Parent then
			local props: { [string]: any } = { Position = UDim2.fromOffset(from.X + dx, top.Y + fall), Rotation = piece.Rotation + dx * 2 }
			if piece:IsA("Frame") then
				props.BackgroundTransparency = 1
			end
			TweenService:Create(piece, TweenInfo.new(life * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), props):Play()
		end
	end)
	a:Play()
end

-- Confetti from the centre of `src` (at most 24 pieces, gone after ~1.3 s).
function Juice.confetti(src: GuiObject, count: number?)
	if UI.Reduced then
		return
	end
	local sg, at = anchor(src)
	if not sg then
		return
	end
	local layer = fxLayer(sg)
	local colors = Theme.Fx.Confetti
	for i = 1, math.min(count or 20, 24) do
		local p = Instance.new("Frame")
		p.BorderSizePixel = 0
		p.Size = UDim2.fromOffset(math.random(6, 10), math.random(10, 15))
		p.BackgroundColor3 = colors[(i - 1) % #colors + 1]
		p.Rotation = math.random(0, 180)
		p.ZIndex = 51
		fling(layer, p, at, math.random(-130, 130), math.random(60, 140), math.random(120, 200), 1.1 + math.random() * 0.2)
	end
	Debris:AddItem(layer, 1.5)
end

-- A burst of small coins from `src` (at most 10).
function Juice.coins(src: GuiObject, count: number?)
	if UI.Reduced then
		return
	end
	local sg, at = anchor(src)
	if not sg then
		return
	end
	local layer = fxLayer(sg)
	for _ = 1, math.min(count or 8, 10) do
		local c = UI.icon(layer, "cash", 20, { ZIndex = 51 })
		fling(layer, c, at, math.random(-90, 90), math.random(40, 100), math.random(60, 110), 0.9 + math.random() * 0.2)
	end
	Debris:AddItem(layer, 1.2)
end

-- "+50"-style number pop-up: springs in big over `src`, floats up and fades (simulator reward numbers).
function Juice.floatText(src: GuiObject, text: string, color: Color3?)
	local sg, at = anchor(src)
	if not sg then
		return
	end
	local layer = fxLayer(sg)
	local l = UI.text(layer, text, {
		Name = "FloatText", Font = UI.Head, TextSize = 30, TextColor3 = color or TC.Gold, Outline = "Strong",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(160, 36),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 52,
	})
	l.TextWrapped = false
	if UI.Reduced then
		Debris:AddItem(layer, 1)
		return
	end
	l.Rotation = math.random(-8, 8)
	UI.pop(l, 0.3)
	local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- the layer starts under Roblox's top bar (IgnoreGuiInset off): a pop near the top (the coin pill) floats down
	-- instead of up, so it never draws over the Roblox menu and chat buttons
	local endY = if at.Y - 56 < 22 then at.Y + 40 else at.Y - 56
	TweenService:Create(l, rise, { Position = UDim2.fromOffset(at.X + math.random(-12, 12), endY) }):Play()
	task.delay(0.55, function()
		if not l.Parent then
			return
		end
		local fade = TweenInfo.new(0.35)
		TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
		local o = l:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			TweenService:Create(o, fade, { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(layer, 1.1)
end

-- Spinning sun rays behind `target` (a reward card or prize icon), gone after `life` seconds (default 2.5).
-- Parented beside the target, one ZIndex below it, so the target stays on top.
function Juice.rays(target: GuiObject, color: Color3?, life: number?)
	if UI.Reduced or not target.Parent then
		return
	end
	local span = math.max(target.AbsoluteSize.X, target.AbsoluteSize.Y) / (if UI.Scale > 0 then UI.Scale else 1) * 1.9
	local hub = Instance.new("Frame")
	hub.Name = "Rays"
	hub.BackgroundTransparency = 1
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.new(target.Position.X.Scale, target.Position.X.Offset + target.Size.X.Offset * (0.5 - target.AnchorPoint.X),
		target.Position.Y.Scale, target.Position.Y.Offset + target.Size.Y.Offset * (0.5 - target.AnchorPoint.Y))
	hub.Size = UDim2.fromOffset(span, span)
	hub.ZIndex = target.ZIndex - 1
	for i = 0, 7 do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = color or TC.Gold
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(1, 0, 0, math.max(span * 0.09, 8))
		ray.Rotation = i * 22.5
		ray.ZIndex = hub.ZIndex
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
		ray.Parent = hub
	end
	hub.Parent = target.Parent
	UI.pop(hub, 0.2)
	local t = life or 2.5
	TweenService:Create(hub, TweenInfo.new(t, Enum.EasingStyle.Linear), { Rotation = Theme.Loop.RaysSpin * t }):Play()
	task.delay(math.max(t - 0.4, 0), function()
		for _, r in hub:GetChildren() do
			if r:IsA("Frame") then
				TweenService:Create(r, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(hub, t)
end

-- A green checkmark stamp slammed onto `target` (springs down from big, tilted), stays with the target.
function Juice.stamp(target: GuiObject)
	local old = target:FindFirstChild("Stamp")
	if old then
		old:Destroy()
	end
	local s = UI.frame(target, {
		Name = "Stamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = TC.Green, Rotation = -12, ZIndex = target.ZIndex + 10,
	})
	UI.corner(s, 20)
	UI.stroke(s, TC.GreenDeep, 3)
	UI.icon(s, "check", 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = s.ZIndex + 1 })
	if UI.Reduced then
		return
	end
	local sc = UI.squashScale(s)
	sc.Scale = 2.4
	UI.spring(sc, { 0.5, 5 }, { Scale = 1 })
end

-- Waiting shake: `obj` wiggles a few degrees every couple of seconds until it leaves the screen.
function Juice.shake(obj: GuiObject)
	if UI.Reduced then
		return
	end
	task.spawn(function()
		while obj.Parent do
			for _, r in { -8, 8, -6, 6, -3, 0 } do
				if not obj.Parent then
					return
				end
				obj.Rotation = r
				task.wait(0.05)
			end
			task.wait(1.6)
		end
	end)
end

-- Turntable for 3D pet cards: the model sways slowly round its starting yaw (±0.5 rad). One shared loop at
-- 12 Hz, at most MAX_TURN viewports at once, only while they are on screen and inside their scroller; a touch on
-- the view pauses it for a few seconds so a drag (GeodeView) is never fought.
local MAX_TURN = 8
type Turn = { Vp: ViewportFrame, Model: Model, Base: CFrame, Phase: number, PauseUntil: number }
local turns: { Turn } = {}
local turnLoop = false

local function onScreen(vp: ViewportFrame): boolean
	if not vp.Visible or vp.AbsoluteSize.X < 2 then
		return false
	end
	local sf = vp:FindFirstAncestorOfClass("ScrollingFrame")
	if sf then
		local a, b = vp.AbsolutePosition, sf.AbsolutePosition
		if a.Y + vp.AbsoluteSize.Y < b.Y or a.Y > b.Y + sf.AbsoluteSize.Y then
			return false
		end
	end
	return true
end

function Juice.turntable(vp: ViewportFrame, model: Model)
	if UI.Reduced or #turns >= MAX_TURN then
		return
	end
	local t: Turn = { Vp = vp, Model = model, Base = model:GetPivot(), Phase = math.random() * 6, PauseUntil = 0 }
	table.insert(turns, t)
	vp.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			t.PauseUntil = os.clock() + 4
		end
	end)
	if turnLoop then
		return
	end
	turnLoop = true
	task.spawn(function()
		while #turns > 0 do
			local now = os.clock()
			for i = #turns, 1, -1 do
				local x = turns[i]
				if x.Vp.Parent == nil or x.Model.Parent == nil then
					table.remove(turns, i)
				elseif now >= x.PauseUntil and not UI.Reduced and onScreen(x.Vp) then
					x.Model:PivotTo(CFrame.Angles(0, math.sin(now * 0.7 + x.Phase) * 0.5, 0) * x.Base)
				end
			end
			task.wait(1 / 12)
		end
		turnLoop = false
	end)
end

-- Counter flip: `label` (its text just changed) drops in from a little above and fades up into place, like a
-- flip counter turning over. The resting position is remembered so a flip mid-flip never drifts.
function Juice.flip(label: TextLabel)
	if UI.Reduced or not label.Parent then
		return
	end
	local base = label:GetAttribute("FlipBase")
	if typeof(base) ~= "UDim2" then
		base = label.Position
		label:SetAttribute("FlipBase", base)
	end
	local home = base :: UDim2
	label.Position = home + UDim2.fromOffset(0, -8)
	label.TextTransparency = 0.7
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = home, TextTransparency = 0 }):Play()
end

-- "No" shake for a locked thing that was tapped: a quick side-to-side jolt (position, so it never fights the
-- press squash scale). Inside a list or grid the layout owns the position, so it jolts by rotation there.
-- Ignored while one is already running.
function Juice.nope(obj: GuiObject)
	if UI.Reduced or obj:GetAttribute("Nope") then
		return
	end
	obj:SetAttribute("Nope", true)
	local parent = obj.Parent
	local laidOut = parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
	local home, turn = obj.Position, obj.Rotation
	task.spawn(function()
		for _, dx in { -7, 7, -5, 5, -2, 0 } do
			if not obj.Parent then
				return
			end
			if laidOut then
				obj.Rotation = turn + dx * 0.8
			else
				obj.Position = home + UDim2.fromOffset(dx, 0)
			end
			task.wait(0.04)
		end
		obj.Position = home
		obj.Rotation = turn
		obj:SetAttribute("Nope", nil)
	end)
end

-- One full turn of a coin icon when coins arrive (the readout's own bump is separate). Rotation only.
function Juice.spin(obj: GuiObject)
	if UI.Reduced or obj:GetAttribute("Spinning") then
		return
	end
	obj:SetAttribute("Spinning", true)
	obj.Rotation = 0
	local tw = TweenService:Create(obj, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 360 })
	tw.Completed:Connect(function()
		obj.Rotation = 0
		obj:SetAttribute("Spinning", nil)
	end)
	tw:Play()
end

-- List rows slide in from the right one after another (`order` = 1, 2, ...). Rows inside a UIListLayout cannot
-- move themselves, so the row is placed in a same-size holder that takes its place in the list and the row
-- slides inside it.
function Juice.slideIn(row: GuiObject, order: number)
	if UI.Reduced or not row.Parent then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = row.Name
	holder.BackgroundTransparency = 1
	holder.Size = row.Size
	holder.LayoutOrder = row.LayoutOrder
	holder.Parent = row.Parent
	row.Size = UDim2.fromScale(1, 1)
	row.Position = UDim2.new(0.6, 0, 0, 0)
	row.Parent = holder
	TweenService:Create(row, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, (order - 1) * 0.05), { Position = UDim2.new() }):Play()
end

-- Idle wobble for shop egg tiles: every registered icon rocks a few degrees on its own phase. One shared loop
-- (15 Hz), at most MAX_WOBBLE at once, only while visible; Reduce Motion holds them still.
local MAX_WOBBLE = 12
type Wob = { Obj: GuiObject, Phase: number }
local wobbles: { Wob } = {}
local wobbleLoop = false

function Juice.wobble(obj: GuiObject)
	if #wobbles >= MAX_WOBBLE then
		return
	end
	table.insert(wobbles, { Obj = obj, Phase = math.random() * 6 })
	if wobbleLoop then
		return
	end
	wobbleLoop = true
	task.spawn(function()
		while #wobbles > 0 do
			local now = os.clock()
			for i = #wobbles, 1, -1 do
				local w = wobbles[i]
				if w.Obj.Parent == nil then
					table.remove(wobbles, i)
				elseif UI.Reduced then
					w.Obj.Rotation = 0
				elseif w.Obj.Visible and w.Obj.AbsoluteSize.X > 1 then
					-- a rock with a short pause at the ends (sin cubed): gentle, not a constant swing
					local a = math.sin(now * 2.4 + w.Phase)
					w.Obj.Rotation = a * a * a * 7
				end
			end
			task.wait(1 / 15)
		end
		wobbleLoop = false
	end)
end

-- Timer ring: RING_DOTS dots round a circle, lit clockwise from the top; set(f) lights the first f (0..1) of them
-- so the ring drains as the time runs out. Returns (frame, set).
local RING_DOTS = 20
function Juice.ring(parent: Instance, size: number, color: Color3, props: { [string]: any }?): (Frame, (number) -> ())
	local f = UI.frame(parent, { Name = "Ring", BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) })
	for k, v in (props or {}) :: { [string]: any } do
		(f :: any)[k] = v
	end
	local d = math.max(math.floor(size * 0.2), 4)
	local r = size / 2 - d / 2
	local dots: { Frame } = {}
	for i = 1, RING_DOTS do
		local a = (i - 1) / RING_DOTS * math.pi * 2
		local dot = UI.frame(f, {
			Name = "Dot" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(d, d), BackgroundColor3 = color,
			Position = UDim2.fromOffset(size / 2 + math.sin(a) * r, size / 2 - math.cos(a) * r),
		})
		UI.corner(dot, d)
		dots[i] = dot
	end
	local lit = -1
	return f, function(frac: number)
		local n = math.ceil(math.clamp(frac, 0, 1) * RING_DOTS)
		if n == lit then
			return
		end
		lit = n
		for i, dot in dots do
			dot.BackgroundTransparency = if i <= n then 0 else 0.78 -- spent time stays as a faint trace of the ring
		end
	end
end

-- Claimable glow (quest CLAIM, daily gift, upgrades you can afford, new pets): see UiJuice.pulse.
Juice.pulse = UiJuice.pulse
-- One shine sweep across a card (hover / select): see UiJuice.sweep.
Juice.sweep = UiJuice.sweep

-- Coin flight -------------------------------------------------------------------------------------------------
-- Coins fly from where they were earned (a CLAIM / OPEN / SELL button) to the coin counter that is on screen (the
-- open menu's cash header, else the HUD coin pill) along an arc, then the counter bumps. The tap only remembers
-- where the button was (Juice.coinSource); the flight starts when the server's new cash arrives (Juice.payout,
-- called by the HUD), so nothing flies for a claim the server refused.
local hudCoins: GuiObject? = nil
local source: { At: Vector2, Time: number }? = nil
local SOURCE_TTL = 4 -- seconds a tap waits for its coins

function Juice.setCoinTarget(obj: GuiObject?)
	hudCoins = obj
end

local function centre(obj: GuiObject): Vector2
	return obj.AbsolutePosition + obj.AbsoluteSize / 2
end

-- Remembers `obj` (its screen centre, now) as where the next coins come from.
function Juice.coinSource(obj: GuiObject)
	if obj.Parent and obj.AbsoluteSize.X > 0 then
		source = { At = centre(obj), Time = os.clock() }
	end
end

local function coinTarget(): GuiObject?
	local m = UI.modalCashTarget()
	if m then
		return m
	end
	local h = hudCoins
	if h and h.Parent and h.Visible and h.AbsoluteSize.X > 0 then
		return h
	end
	return nil
end

-- A few small coins fly from the absolute screen point `fromAbs` to `target` along UiMotion's arc; the last one
-- bumps the target. One tween per coin (nothing keeps running once they land).
function Juice.coinFlyFrom(fromAbs: Vector2, target: GuiObject, amount: number)
	if UiJuice.still() or not target.Parent then
		return
	end
	local sg = UI.noticeLayer()
	local sc = if UI.Scale > 0 then UI.Scale else 1
	local p0 = (fromAbs - sg.AbsolutePosition) / sc
	local p1 = (centre(target) - sg.AbsolutePosition) / sc
	local layer = fxLayer(sg)
	layer.Name = "CoinFly"
	local n = UiMotion.coinCount(amount)
	local flight = 0.55
	for i = 1, n do
		local c = UI.icon(layer, "cash", 22, { Name = "FlyCoin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p0.X, p0.Y), ZIndex = 52 })
		local from = p0 + Vector2.new((i - (n + 1) / 2) * 10, (i % 2) * 8 - 4)
		local lift = 50 + i * 6
		c.Position = UDim2.fromOffset(from.X, from.Y)
		local a = Instance.new("NumberValue")
		a.Changed:Connect(function(t: number)
			local pt = UiMotion.arcPoint(from, p1, lift, t)
			c.Position = UDim2.fromOffset(pt.X, pt.Y)
		end)
		local tw = TweenService:Create(a, TweenInfo.new(flight, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, (i - 1) * 0.06), { Value = 1 })
		tw.Completed:Connect(function()
			c:Destroy()
			a:Destroy()
			if i == n and target.Parent then
				UI.pop(target, 1.18) -- the counter bumps as the last coin lands
			end
		end)
		tw:Play()
	end
	Debris:AddItem(layer, flight + n * 0.06 + 0.5)
end

-- Coins were paid (`amount` > 0: the HUD saw the cash go up): fly them from the remembered source while it is
-- fresh. Returns true when coins flew.
function Juice.payout(amount: number): boolean
	local s = source
	if not s or amount <= 0 or os.clock() - s.Time > SOURCE_TTL then
		return false
	end
	source = nil
	local t = coinTarget()
	if not t then
		return false
	end
	Juice.coinFlyFrom(s.At, t, amount)
	return true
end

-- Is `obj` really drawn: in a parent chain of visible GuiObjects under an enabled ScreenGui, with a size? A hidden pill
-- keeps a stale AbsolutePosition (in a hunt the coin pill's spot is under the hunt clock card), so effects aimed at a
-- hidden object landed on whatever is there now (Studio 2026-10-15: "+4 coins" on the clock).
function Juice.onScreen(obj: GuiObject?): boolean
	if not obj or not obj.Parent or obj.AbsoluteSize.X <= 0 then
		return false
	end
	local chain: { boolean } = {}
	local cur: Instance? = obj
	while cur do
		if cur:IsA("GuiObject") then
			table.insert(chain, cur.Visible)
		elseif cur:IsA("LayerCollector") then
			table.insert(chain, cur.Enabled)
			break
		end
		cur = cur.Parent
	end
	return UiMotion.shownChain(chain)
end

-- The HUD coin counter coins fly to (nil while it is hidden).
Juice.coinTarget = coinTarget

return Juice
