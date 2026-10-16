--!strict
-- Pet style kit (owner's reference clip, Pet Simulator style; docs/UI_STYLE_REF.md): the colours, cards, pills,
-- ribbons, tab strip and motion every screen shares. First drawn for the Pet Shop (PetShop.luau), then applied to
-- every menu through UI.modal / UI.tabs / UI.button and the HUD. Pure drawing: no game state, no remotes.
--
-- Children draw above their parent in Roblox, so a drop shadow is a sibling under a face (PetStyle.shadowed).
-- Cards tilt toward the pointer and lift on hover (PetStyle.card); Reduce Motion stops every loop (PetStyle.still).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)

local PetStyle = {}
PetStyle.On = true -- the whole interface uses this look (Theme / UI read it)
PetStyle.Sweeps = {} :: { RBXScriptConnection } -- pattern drift loops; each ends with its card (Destroying)

-- Colours measured on the reference clip (Theme.Pet; docs/UI_STYLE_REF.md section 2).
PetStyle.K = Theme.Pet
PetStyle.Tones = ({
	purple = { Color3.fromRGB(70, 110, 255), Color3.fromRGB(150, 60, 255), Color3.fromRGB(240, 80, 220) },
	gold = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 150, 40), Color3.fromRGB(220, 70, 40) },
	blue = { Color3.fromRGB(40, 120, 255), Color3.fromRGB(30, 190, 255), Color3.fromRGB(90, 90, 255) },
	pink = { Color3.fromRGB(255, 110, 190), Color3.fromRGB(220, 90, 255), Color3.fromRGB(170, 90, 255) },
	green = { Color3.fromRGB(60, 200, 90), Color3.fromRGB(120, 230, 60), Color3.fromRGB(30, 160, 120) },
	sky = { Color3.fromRGB(70, 200, 255), Color3.fromRGB(40, 150, 255), Color3.fromRGB(80, 110, 255) },
	violet = { Color3.fromRGB(120, 60, 220), Color3.fromRGB(80, 30, 160), Color3.fromRGB(60, 20, 110) },
	sun = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 190, 40), Color3.fromRGB(255, 140, 30) },
}) :: { [string]: { Color3 } }
-- Motion (docs/UI_STYLE_REF.md section 4). Reduce Motion stops all of it (UI.Reduced).
PetStyle.Motion = {
	TiltDeg = 3, -- card tilt toward the pointer, degrees at the card's edge
	TiltPx = 5, -- card slide toward the pointer, logical px at the edge
	Hover = 1.035, -- card lift
	TiltSpring = { 0.55, 5 }, -- damping, Hz
	TabSlide = { 0.7, 7 },
	PatternSpeed = 0.012, -- pattern drift (card widths per second)
	StripeSpeed = 0.08, -- HUD square streaks (card widths per second)
}
local K, TONES, MOTION = PetStyle.K, PetStyle.Tones, PetStyle.Motion

function PetStyle.still(): boolean
	return UI.Reduced
end

function PetStyle.words(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = { Font = UI.Bold, TextColor3 = K.White, Outline = "Normal" }
	local oColor: Color3? = nil
	local oThick: number? = nil
	if props then
		for k, v in props do
			if k == "OutlineColor" then
				oColor = v
			elseif k == "OutlineThick" then
				oThick = v
			else
				p[k] = v
			end
		end
	end
	p.TextSize = size
	local t = UI.text(parent, text, p)
	local o = t:FindFirstChild("Outline")
	if o and o:IsA("UIStroke") then
		o.Color = oColor or K.Ink
		if oThick then
			o.Thickness = oThick
		end
	end
	return t
end

-- Vertical gradient (lighter top) over a fill: the glossy pill look.
function PetStyle.vgrad(obj: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = obj
	return g
end

function PetStyle.hgrad(obj: GuiObject, stops: { Color3 }): UIGradient
	local kps = {}
	for i, c in stops do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#stops - 1), c))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(kps)
	g.Rotation = 0
	g.Parent = obj
	return g
end

function PetStyle.round(obj: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

function PetStyle.edge(obj: GuiObject, color: Color3, thick: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = obj
	return s
end

-- A wrapper holding a dark copy `dy` px lower (the drop shadow) under a face frame. Children draw above their
-- parent in Roblox, so the shadow has to be a sibling of the face, not its child. Layout props (Name, Size,
-- Position, LayoutOrder, Anchor) go on the wrapper; the face fills it. Returns (wrapper, face).
function PetStyle.shadowed(parent: Instance, r: number, dy: number, color: Color3?, props: { [string]: any }?): (Frame, Frame)
	local wrap = Instance.new("Frame")
	wrap.Name = "Card"
	wrap.BackgroundTransparency = 1
	wrap.ZIndex = 2
	UI.apply(wrap, props)
	local d = Instance.new("Frame")
	d.Name = "Drop"
	d.BackgroundColor3 = color or K.Shade
	d.BackgroundTransparency = if color then 0 else 0.5
	d.BorderSizePixel = 0
	d.Size = UDim2.fromScale(1, 1)
	d.Position = UDim2.fromOffset(0, dy)
	d.ZIndex = 1
	PetStyle.round(d, r)
	d.Parent = wrap
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = K.White
	face.BorderSizePixel = 0
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 2
	PetStyle.round(face, r)
	face.Parent = wrap
	wrap.Parent = parent
	return wrap, face
end

-- The faint diamond pattern on cards and sheets (drawn by UI.pattern, which the modal sheet shares).
PetStyle.pattern = UI.pattern

-- A gradient card with the drop shadow and the pattern. Tilts toward the pointer (CardTilt) and lifts on hover.
function PetStyle.card(parent: Instance, tone: string, props: { [string]: any }?): Frame
	local f, face = PetStyle.shadowed(parent, 12, 4, nil, props)
	PetStyle.hgrad(face, TONES[tone] or TONES.blue)
	PetStyle.edge(face, K.CardEdge, 2.5)
	local sz = if props and props.Size then props.Size :: UDim2 else UDim2.fromOffset(400, 160)
	PetStyle.pattern(face, K.White, 0.9, 34, sz.X.Offset, sz.Y.Offset)
	-- tilt and lift
	local tilt = Instance.new("UIScale")
	tilt.Name = "Lift"
	tilt.Parent = f
	local base = f.Position -- captured once: re-reading it mid-spring made the card drift away
	local function settle()
		UI.spring(f, MOTION.TiltSpring, { Rotation = 0, Position = base })
		UI.spring(tilt, Theme.Spring.Release, { Scale = 1 })
	end
	f.MouseEnter:Connect(function()
		if UserInputService.MouseEnabled and not PetStyle.still() then
			UI.spring(tilt, Theme.Spring.Release, { Scale = MOTION.Hover })
		end
	end)
	f.MouseLeave:Connect(settle)
	f.MouseMoved:Connect(function(x: number, y: number)
		if PetStyle.still() or not UserInputService.MouseEnabled then
			return
		end
		local size = f.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local dx = math.clamp(((x - f.AbsolutePosition.X) / size.X - 0.5) * 2, -1, 1)
		local dy = math.clamp(((y - f.AbsolutePosition.Y) / size.Y - 0.5) * 2, -1, 1)
		UI.spring(f, MOTION.TiltSpring, {
			Rotation = dx * MOTION.TiltDeg,
			Position = base + UDim2.fromOffset(dx * MOTION.TiltPx, dy * MOTION.TiltPx * 0.6),
		})
	end)
	f:SetAttribute("Tone", tone)
	return face
end

-- A rounded pill with a glossy vertical gradient and a dark edge; returns the pill and its label.
function PetStyle.pill(parent: Instance, text: string, top: Color3, bottom: Color3, edgeColor: Color3, props: { [string]: any }?, size: number?): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.Name = "Pill"
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = K.White
	b.BorderSizePixel = 0
	b.ZIndex = 4
	UI.apply(b, props)
	PetStyle.round(b, 999)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.55, bottom),
		ColorSequenceKeypoint.new(0.8, bottom),
		ColorSequenceKeypoint.new(0.81, bottom:Lerp(edgeColor, 0.55)),
		ColorSequenceKeypoint.new(1, bottom:Lerp(edgeColor, 0.55)),
	})
	g.Rotation = 90
	g.Parent = b
	PetStyle.edge(b, edgeColor, 2.5)
	b.Parent = parent
	local l = PetStyle.words(b, text, size or 18, {
		Name = "Label", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -16, 1, -4), Position = UDim2.fromOffset(8, 0), ZIndex = 5,
		OutlineColor = edgeColor, OutlineThick = 2.4,
	})
	UI.squashScale(b)
	b.MouseButton1Down:Connect(function()
		UI.squash(b, true)
	end)
	b.MouseButton1Up:Connect(function()
		UI.squash(b, false)
	end)
	b.MouseLeave:Connect(function()
		UI.squash(b, false)
	end)
	return b, l
end

-- A small tilted ribbon tag ("BEST DEAL", "LIMITED!").
function PetStyle.ribbon(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = "Ribbon"
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(84, 20)
	f.ZIndex = 6
	UI.apply(f, props)
	PetStyle.round(f, 999)
	PetStyle.edge(f, K.Ink, 2)
	f.Parent = parent
	PetStyle.words(f, text, 12, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), ZIndex = 7, OutlineThick = 1.6 })
	return f
end

-- A rarity dot: a small disc in the rarity colour with a dark edge.
function PetStyle.dot(parent: Instance, color: Color3, size: number, props: { [string]: any }?): Frame
	local d = Instance.new("Frame")
	d.Name = "Dot"
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.Size = UDim2.fromOffset(size, size)
	d.ZIndex = 5
	UI.apply(d, props)
	PetStyle.round(d, 999)
	PetStyle.edge(d, K.Ink, 2)
	PetStyle.vgrad(d, K.White:Lerp(color, 0.55), color)
	d.Parent = parent
	return d
end


-- Stops every pattern drift loop (called when a screen that made them closes).
function PetStyle.clearSweeps()
	for _, c in PetStyle.Sweeps do
		c:Disconnect()
	end
	PetStyle.Sweeps = {}
end

-- A navy pill with a gold coin and the amount (the clip's currency readout). Returns the pill and a setter.
function PetStyle.coinPill(parent: Instance, w: number, h: number, props: { [string]: any }?): (Frame, (number) -> ())
	local coin = UI.frame(parent, { Name = "Coins", BackgroundColor3 = K.TabBar, Size = UDim2.fromOffset(w, h), ZIndex = 3 })
	UI.apply(coin, props)
	PetStyle.round(coin, 999)
	PetStyle.edge(coin, K.TabBarEdge, 2.5)
	local disc = PetStyle.dot(coin, K.Gold, h - 10, { Position = UDim2.fromOffset(5, 5) })
	PetStyle.words(disc, "$", math.floor((h - 10) * 0.6), { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(140, 90, 0), Outline = false, ZIndex = 6 })
	local amt = PetStyle.words(coin, "0", math.floor(h * 0.45), { Name = "Amount", Position = UDim2.fromOffset(h, 0), Size = UDim2.new(1, -(h + 8), 1, 0), OutlineThick = 1.6, ZIndex = 5 })
	amt.TextWrapped = false
	local last: number? = nil
	return coin, function(n: number)
		UI.Juice.countTo(amt, last or n, n, UI.num)
		last = n
	end
end

-- The red X square (tilted a touch like the clip's).
function PetStyle.closeX(parent: Instance, size: number, onClick: () -> (), props: { [string]: any }?): TextButton
	local x = PetStyle.pill(parent, "X", K.RedTop, K.Red, K.RedEdge, props, math.floor(size * 0.52))
	x.Name = "Close"
	x.Size = UDim2.fromOffset(size, size)
	x.Rotation = 4
	local c = x:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, math.floor(size * 0.26))
	end
	x.Activated:Connect(onClick)
	return x
end

-- Big menu title with a dark drop copy ("Shop", "Pets"): white Fredoka, blue edge.
function PetStyle.title(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = props or {}
	local shadowProps = table.clone(p)
	shadowProps.Name = "TitleShadow"
	shadowProps.Position = (p.Position or UDim2.new()) + UDim2.fromOffset(0, 3)
	shadowProps.TextColor3 = K.TitleShadow
	shadowProps.OutlineColor = K.TitleShadow
	shadowProps.OutlineThick = 4
	shadowProps.ZIndex = (p.ZIndex or 3) - 1
	PetStyle.words(parent, text, size, shadowProps)
	local tp = table.clone(p)
	tp.Name = tp.Name or "Title"
	tp.OutlineColor = K.TitleEdge
	tp.OutlineThick = 3.4
	return PetStyle.words(parent, text, size, tp)
end

-- Navy tab strip with a lime pill that slides to the picked tab. `items` = { { id, label } }; returns the strip and
-- a function that moves the pill (instant or sprung) and recolours the words.
function PetStyle.tabStrip(parent: Instance, items: { { string } }, current: string, onPick: (string) -> (), props: { [string]: any }?): (Frame, (string, boolean?) -> ())
	local strip = UI.frame(parent, { Name = "Tabs", BackgroundColor3 = K.TabBar, Size = UDim2.new(1, 0, 0, 38), ZIndex = 3 })
	UI.apply(strip, props)
	PetStyle.round(strip, 999)
	PetStyle.edge(strip, K.TabBarEdge, 2.5)
	local n = #items
	local sel = UI.frame(strip, { Name = "Selected", BackgroundColor3 = K.Lime, Position = UDim2.new(0, 4, 0, 3), Size = UDim2.new(1 / n, -8 / n, 1, -6), ZIndex = 4 })
	PetStyle.round(sel, 999)
	PetStyle.vgrad(sel, K.LimeTop, K.Lime)
	PetStyle.edge(sel, K.LimeEdge, 2)
	local labels: { [string]: TextLabel } = {}
	local cur = current
	local function place(id: string, instant: boolean?)
		cur = id
		local i = 1
		for k, it in items do
			if it[1] == id then
				i = k
			end
		end
		local target = UDim2.new((i - 1) / n, 4, 0, 3)
		if instant or UI.Reduced then
			sel.Position = target
		else
			UI.spring(sel, MOTION.TabSlide, { Position = target })
		end
		for k, l in labels do
			l.TextColor3 = if k == id then K.Ink else K.TabText
			local o = l:FindFirstChild("Outline")
			if o and o:IsA("UIStroke") then
				o.Transparency = if k == id then 1 else 0
			end
		end
	end
	for i, it in items do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. it[1]
		b.BackgroundTransparency = 1
		b.Text = ""
		b.AutoButtonColor = false
		b.Position = UDim2.new((i - 1) / n, 4, 0, 0)
		b.Size = UDim2.new(1 / n, -8 / n, 1, 0)
		b.ZIndex = 5
		b.Parent = strip
		local l = PetStyle.words(b, it[2], 16, { Name = "Label", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.TabText, OutlineThick = 1.4, ZIndex = 6 })
		l.TextWrapped = false
		labels[it[1]] = l
		b.Activated:Connect(function()
			if cur ~= it[1] then
				place(it[1], false)
				onPick(it[1])
			end
		end)
	end
	place(current, true)
	return strip, place
end

-- Drifting diagonal light stripes inside a clipped host (the video's HUD squares: pale streaks sliding across the
-- blue). Stops with the card. Lives under everything else on the card (ZIndex 0).
function PetStyle.stripes(card: GuiObject, color: Color3, alpha: number, radius: number)
	local host = Instance.new("Frame")
	host.Name = "Shine"
	host.BackgroundTransparency = 1
	host.ClipsDescendants = true
	host.Size = UDim2.fromScale(1, 1)
	host.ZIndex = 0
	host.Parent = card
	PetStyle.round(host, radius)
	local band = Instance.new("Frame")
	band.Name = "Drift"
	band.BackgroundTransparency = 1
	band.Size = UDim2.fromScale(3, 1)
	band.Position = UDim2.fromScale(-1, 0)
	band.ZIndex = 0
	band.Parent = host
	-- three streaks of two widths per card width, repeated over the wide band
	local widths = { 0.09, 0.05, 0.12 }
	local n = 0
	for rep = 0, 2 do
		for i, w in widths do
			n += 1
			local st = Instance.new("Frame")
			st.Name = "Streak"
			st.BackgroundColor3 = color
			st.BackgroundTransparency = alpha
			st.BorderSizePixel = 0
			st.AnchorPoint = Vector2.new(0.5, 0.5)
			st.Rotation = -32
			st.Size = UDim2.new(w / 3, 0, 2.2, 0)
			st.Position = UDim2.fromScale((rep + (i - 1) * 0.36 + 0.1) / 3, 0.5)
			st.ZIndex = 0
			st.Parent = band
		end
	end
	if not PetStyle.still() then
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			if not host.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local t = (os.clock() - t0) * MOTION.StripeSpeed
			band.Position = UDim2.fromScale(-1 + (t % 1) / 3, 0)
		end)
		card.Destroying:Connect(function()
			if conn then
				conn:Disconnect()
			end
		end)
	end
end

-- Dresses a square HUD button like the video's: cyan face with a lighter top, a darker lip along the bottom, drifting
-- light streaks and a white rim. The button's own fill is left to it (hover / press colours stay on the face).
function PetStyle.iconTile(b: GuiObject, size: number)
	local r = math.floor(size * 0.2)
	PetStyle.vgrad(b, K.CyanTop, K.Cyan)
	local border = b:FindFirstChild("Border")
	if border and border:IsA("UIStroke") then
		border.Color = K.White
		border.Thickness = 2.5
	else
		PetStyle.edge(b, K.White, 2.5)
	end
	PetStyle.stripes(b, K.White, 0.8, r)
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = K.CyanLip
	lip.BackgroundTransparency = 0.55
	lip.BorderSizePixel = 0
	lip.AnchorPoint = Vector2.new(0.5, 1)
	lip.Position = UDim2.new(0.5, 0, 1, 0)
	lip.Size = UDim2.new(1, 0, 0, math.floor(size * 0.12))
	lip.ZIndex = 1
	lip.Parent = b
	PetStyle.round(lip, r)
	-- the lip's top corners are squared off by a strip over them (a frame's corners round on every side)
	local fillTop = Instance.new("Frame")
	fillTop.Name = "LipTop"
	fillTop.BackgroundColor3 = K.CyanLip
	fillTop.BackgroundTransparency = 0.55
	fillTop.BorderSizePixel = 0
	fillTop.Size = UDim2.new(1, -2 * r, 0, r)
	fillTop.Position = UDim2.fromOffset(r, 0)
	fillTop.ZIndex = 1
	fillTop.Parent = lip
end

return PetStyle
