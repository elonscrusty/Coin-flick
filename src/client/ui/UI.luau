--!strict
-- UI kit v2 (docs/ui_v2/BRIEF_UI_V2.md): one theme (ui/Theme.luau) and the shared components every screen is
-- built from: fitted outlined text, drawn icons, buttons with hover / pressed / selected / disabled / pending
-- states, tabs, catalog rows, specimen cards, counters, empty / loading / error states, sliders, toggles, the
-- modal shell (header + red close), stacked confirmation dialogs and coalesced notifications.
--
-- Screen manager: UI.modal is the one primary-menu slot (opening one closes the previous one); UI.confirm
-- stacks a dialog above it without touching the menu's state; UI.block(key) is the input stack CameraMode
-- reads (free cursor, suspended look / move / tool, first person restored once when the last key goes).
--
-- Text sizing: Roblox's "Text size" accessibility setting scales TextSize-sized labels but not their boxes, so
-- every label here is TextScaled inside a box sized for the designed size with a UITextSizeConstraint whose
-- MaxTextSize is that size: designed size when it fits, shrinks (never below MinText) when it would not.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local NoticeLayout = require(Shared.NoticeLayout)
local UiMotion = require(Shared.UiMotion)
local UiKit = require(Shared.UiKit)
local PopupRules = require(Shared.PopupRules)
local Audio = require(script.Parent.Parent.Audio)
local PopupGate = require(script.Parent.Parent.PopupGate)
local Theme = require(script.Parent.Theme)
local UiJuice = require(script.Parent.UiJuice)
local spr = require(Shared.Vendor.spr)

local UI = {}
UI.Theme = Theme

local TC = Theme.Color
local P = Config.Palette

-- Colours: the theme plus the legacy names older callers (RevealView, GuideArrow, Reticle) still read.
UI.Colors = {
	Panel = TC.Panel,
	PanelEdge = TC.PanelEdge,
	Inset = TC.Inset,
	InsetEdge = TC.InsetEdge,
	Hud = TC.Hud,
	Text = TC.Text,
	Muted = TC.Muted,
	Faint = TC.Faint,
	Outline = TC.Outline,
	DarkText = TC.DarkText,
	Gold = TC.Gold,
	GoldDeep = TC.GoldDeep,
	Count = TC.Count,
	Cash = TC.Cash,
	Gray = TC.Gray,
	GrayDeep = TC.GrayDeep,
	Red = TC.Red,
	RedDeep = TC.RedDeep,
	Green = TC.Green,
	GreenDeep = TC.GreenDeep,
	Warn = TC.Warn,
	Disabled = TC.Disabled,
	DisabledText = TC.DisabledText,
	-- legacy names
	Slate = TC.Hud,
	SlateRaised = TC.Gray,
	SlateDeep = TC.Inset,
	SlateLine = TC.InsetEdge,
	Amber = TC.Gold,
	AmberDeep = TC.GoldDeep,
	Yellow = TC.Gold,
	Orange = TC.Count,
	Ok = TC.Green,
	Ink = TC.DarkText,
	InkMuted = TC.Muted,
	Dark = TC.DarkText,
	Cream = TC.Panel,
	Paper = TC.Inset,
	Parchment = TC.Inset,
	Honey = TC.PanelEdge,
	HoneyLine = TC.InsetEdge,
	Card = TC.Inset,
	Stroke = TC.InsetEdge,
	PanelLight = TC.Gray,
	Violet = P.Violet,
	Cyan = P.Cyan,
	Rock = P.Rock,
}

local TS = Theme.Size
local PET = Theme.Pet
local TT = Theme.Text
UI.T = {
	Title = TT.Title,
	Head = TT.Head,
	Body = TT.Body,
	Small = TT.Small,
	Tiny = TT.Tiny,
	MinText = TT.MinText,
	Count = TT.Count,
	Touch = TS.Touch,
	Tab = TS.Tab,
	Gap = TS.Gap,
	Pad = TS.Pad,
	Radius = TS.Radius,
	RadiusLg = TS.RadiusLg,
	RadiusSm = TS.RadiusSm,
	Primary = TS.Primary,
	ModalMaxW = 560,
	Edge = TS.Edge,
	MenuCard = Vector2.new(TS.HudTile, TS.HudTile),
}
local T = UI.T

UI.Head = Theme.Font.Display
UI.Bold = Theme.Font.Bold
UI.Body = Theme.Font.Body
UI.BodyStrong = Theme.Font.Bold
UI.Reduced = false -- Reduce Motion (from settings)
UI.Juice = UiJuice -- the shared juice primitives (sweep, pulse, badge wiggle, tab slide, number count)
UiJuice.gameReduced = function(): boolean
	return UI.Reduced
end

-- Motion helpers (one feel everywhere) -------------------------------------------------------------------
-- Springs come from Vendor/spr; Reduce Motion turns each one into an instant change.

-- Springs `props` on `inst` with a { damping, frequency } pair from Theme.Spring.
function UI.spring(inst: Instance, params: { number }, props: { [string]: any })
	if UI.Reduced then
		spr.stop(inst)
		for k, v in props do
			(inst :: any)[k] = v
		end
		return
	end
	spr.target(inst, params[1], params[2], props)
end

-- The one press scale of an object (buttons, rows, cards, tiles): a UIScale named "Squash".
function UI.squashScale(obj: Instance): UIScale
	local s = obj:FindFirstChild("Squash")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "Squash"
	n.Parent = obj
	return n
end

-- Finger down: quick dip; finger up: bounce back past 1 and settle (the cartoon squash).
function UI.squash(obj: Instance, down: boolean)
	local s = UI.squashScale(obj)
	if down then
		UI.spring(s, Theme.Spring.Press, { Scale = Theme.Spring.PressScale })
	else
		local hover = obj:GetAttribute("Hover") == true and UserInputService.MouseEnabled
		UI.spring(s, Theme.Spring.Release, { Scale = if hover then Theme.Loop.HoverScale else 1 })
	end
end

-- Idle shine sweeps share one loop: each entry drops out once its button leaves the game. Reduce Motion pauses it.
local shines: { Frame } = {}
local shineLoop = false
local SHINE_STYLES = { gold = true, green = true, blue = true }

-- White glint that slides across a button every Theme.Loop.ShineEvery seconds while the button is gold, green or blue
-- and enabled (the "buy me" sparkle of simulator games). Added by UI.button; safe to call twice.
function UI.shine(b: GuiObject)
	if b:FindFirstChild("Shine") then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Shine"
	f.BackgroundColor3 = Theme.Fx.Shine
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 0 -- under the caption and icons (siblings)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, T.Radius)
	c.Parent = f
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1.2, 0)
	g.Parent = f
	f.Parent = b
	table.insert(shines, f)
	if shineLoop then
		return
	end
	shineLoop = true
	task.spawn(function()
		while #shines > 0 do
			task.wait(Theme.Loop.ShineEvery)
			for i = #shines, 1, -1 do
				local sf = shines[i]
				local owner = sf.Parent
				if owner == nil then
					table.remove(shines, i)
				elseif not UI.Reduced and owner:IsA("GuiObject") and owner.Visible and not owner:GetAttribute("Disabled")
					and SHINE_STYLES[owner:GetAttribute("Style") :: any] then
					local sg = sf:FindFirstChildOfClass("UIGradient")
					if sg then
						sg.Offset = Vector2.new(-1.2, 0)
						TweenService:Create(sg, TweenInfo.new(Theme.Loop.ShineTime, Enum.EasingStyle.Quad), { Offset = Vector2.new(1.2, 0) }):Play()
					end
				end
			end
		end
		shineLoop = false
	end)
end

-- Soft white sheen over the top half of a button (glossy toy look). Never takes input.
function UI.gloss(b: GuiObject)
	if b:FindFirstChild("Gloss") then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Gloss"
	f.BackgroundColor3 = Theme.Fx.Shine
	f.BackgroundTransparency = Theme.Gloss.Transparency
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(4, 3)
	f.Size = UDim2.new(1, -8, Theme.Gloss.Height, -3)
	f.ZIndex = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, math.max(T.Radius - 4, 4))
	c.Parent = f
	f.Parent = b
end

-- "Tap me" wiggle on the one object the player should press next (PLAY): a quick tilt left-right every few
-- seconds (rotation, so it never fights the press squash scale). Returns stop().
function UI.wiggle(obj: GuiObject): () -> ()
	local alive = true
	task.spawn(function()
		local steps = { -Theme.Loop.WiggleAngle, Theme.Loop.WiggleAngle, -Theme.Loop.WiggleAngle * 0.5, 0 }
		while alive and obj.Parent do
			task.wait(Theme.Loop.WiggleEvery)
			if alive and obj.Parent and obj.Visible and not UI.Reduced and not obj:GetAttribute("Disabled") then
				for _, a in steps do
					TweenService:Create(obj, TweenInfo.new(0.09, Enum.EasingStyle.Sine), { Rotation = a }):Play()
					task.wait(0.09)
				end
			end
		end
	end)
	return function()
		alive = false
		obj.Rotation = 0
	end
end

-- Lighter-top, deeper-bottom gradient over a panel's fill (bright cartoon panels instead of flat ones).
function UI.panelShade(f: GuiObject): UIGradient
	local old = f:FindFirstChild("PanelShade")
	if old and old:IsA("UIGradient") then
		return old
	end
	local g = Instance.new("UIGradient")
	g.Name = "PanelShade"
	g.Rotation = 90
	g.Color = ColorSequence.new(Theme.Panel.Top, Theme.Panel.Bottom)
	g.Parent = f
	return g
end

UI.Sweeps = {} :: { RBXScriptConnection } -- pattern drift loops; each ends with its card (Destroying)

-- The faint diamond pattern on cards and sheets (pet style): rotated squares that drift slowly to the right, in a
-- clipped host under the card's other children (ZIndex 0). `w0`/`h0` is the card's logical size (its AbsoluteSize
-- is not known while it is built); `most` caps the squares (60 on a card, more on a sheet).
function UI.pattern(card: GuiObject, color: Color3, alpha: number, cell: number, w0: number?, h0: number?, most: number?)
	local host = Instance.new("Frame")
	host.Name = "Pattern"
	host.BackgroundTransparency = 1
	host.ClipsDescendants = true
	host.Size = UDim2.fromScale(1, 1)
	host.ZIndex = 0
	host.Parent = card
	UI.corner(host, 10)
	-- the squares sit on a wider inner frame that drifts inside the clipped host (the host itself stays put, so no
	-- square ever shows outside the card)
	local drift = Instance.new("Frame")
	drift.Name = "Drift"
	drift.BackgroundTransparency = 1
	drift.Size = UDim2.new(1, cell * 2, 1, 0)
	drift.Position = UDim2.fromOffset(-cell, 0)
	drift.ZIndex = 0
	drift.Parent = host
	local w = w0 or 400
	local h = h0 or 160
	local cols = math.ceil(w / cell) + 2
	local rows = math.ceil(h / cell) + 1
	local cap = most or 60
	local n = 0
	for r = 0, rows do
		for c = -1, cols do
			n += 1
			if n > cap then
				break
			end
			local d = Instance.new("Frame")
			d.BackgroundColor3 = color
			d.BackgroundTransparency = alpha
			d.BorderSizePixel = 0
			d.Rotation = 45
			d.Size = UDim2.fromOffset(cell * 0.32, cell * 0.32)
			d.Position = UDim2.fromOffset((c + 1) * cell + (r % 2) * cell / 2, r * cell - cell * 0.2)
			d.ZIndex = 0
			UI.corner(d, 3)
			d.Parent = drift
		end
	end
	if not UI.Reduced then
		local t0 = os.clock()
		local conn = RunService.RenderStepped:Connect(function()
			if not host.Parent then
				return
			end
			local dx = ((os.clock() - t0) * 0.012 * w) % cell
			drift.Position = UDim2.fromOffset(dx - cell, 0)
		end)
		table.insert(UI.Sweeps, conn)
		card.Destroying:Once(function()
			conn:Disconnect()
			local i = table.find(UI.Sweeps, conn)
			if i then
				table.remove(UI.Sweeps, i)
			end
		end)
	end
end

-- Wires the squash to a button's own press / release (rows, cards and tiles that are not UI.button).
function UI.bouncy(b: GuiButton)
	b.MouseButton1Down:Connect(function()
		if not b:GetAttribute("Disabled") then
			UI.squash(b, true)
		end
	end)
	b.MouseButton1Up:Connect(function()
		UI.squash(b, false)
	end)
	b.MouseLeave:Connect(function()
		UI.squash(b, false)
	end)
	b.SelectionLost:Connect(function()
		UI.squash(b, false)
	end)
end

-- Pops an object in: scale from `from` (default 0.6) to 1 with an overshoot, after `delay` seconds.
function UI.pop(obj: Instance, from: number?, delay: number?)
	local s = UI.squashScale(obj)
	if UI.Reduced then
		s.Scale = 1
		return
	end
	s.Scale = from or 0.6
	local function go()
		if s.Parent then
			UI.spring(s, Theme.Spring.Pop, { Scale = 1 })
		end
	end
	if delay and delay > 0 then
		task.delay(delay, go)
	else
		go()
	end
end

-- Counts a label up from `from` to `to` over `duration` seconds (results XP / coins, rewards). `fmt` turns the
-- number into text (default: whole number). Returns stop(), which jumps to the final text. Reduce Motion: instant.
function UI.countUp(label: TextLabel, from: number, to: number, duration: number?, fmt: ((number) -> string)?): () -> ()
	local f = fmt or function(n: number): string
		return tostring(math.floor(n + 0.5))
	end
	local d = duration or 0.8
	local stopped = false
	local function stop()
		if not stopped then
			stopped = true
			if label.Parent then
				label.Text = f(to)
			end
		end
	end
	if UI.Reduced or d <= 0 or from == to then
		stop()
		return stop
	end
	label.Text = f(from)
	local t0 = os.clock()
	task.spawn(function()
		while not stopped and label.Parent do
			local a = math.clamp((os.clock() - t0) / d, 0, 1)
			local e = 1 - (1 - a) ^ 3 -- ease out: fast first, slows into the final number
			label.Text = f(from + (to - from) * e)
			if a >= 1 then
				break
			end
			task.wait(1 / 30)
		end
		stop()
	end)
	return stop
end

-- Every shown red dot hops a little every few seconds (one shared loop; hidden or destroyed dots are skipped
-- or dropped). Position only, so the hop never fights the appear pop (scale).
local DOT_HOME = UDim2.new(1, -4, 0, 4)
local dots: { Frame } = {}
local dotLoop = false
local function hopDots()
	if dotLoop then
		return
	end
	dotLoop = true
	task.spawn(function()
		while #dots > 0 do
			task.wait(Theme.Loop.DotHopEvery)
			for i = #dots, 1, -1 do
				local d = dots[i]
				if d.Parent == nil then
					table.remove(dots, i)
				elseif d.Visible and not UI.Reduced then
					local up = TweenService:Create(d, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = DOT_HOME + UDim2.fromOffset(0, -6) })
					up.Completed:Connect(function()
						if d.Parent then
							TweenService:Create(d, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = DOT_HOME }):Play()
						end
					end)
					up:Play()
				end
			end
		end
		dotLoop = false
	end)
end

-- Red "!" dot on something new (top-right corner of `parent`). `on` false hides it; a number shows the count
-- instead of "!". Pops when it appears, then hops now and then while shown. Returns the dot.
function UI.newDot(parent: GuiObject, on: boolean, count: number?): Frame
	local dot = parent:FindFirstChild("NewDot") :: Frame?
	if not dot then
		local d = Instance.new("Frame")
		d.Name = "NewDot"
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = DOT_HOME
		d.Size = UDim2.fromOffset(20, 20)
		d.BackgroundColor3 = Theme.Fx.NewDot
		d.BorderSizePixel = 0
		d.Visible = false
		d.ZIndex = parent.ZIndex + 5
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = d
		local st = Instance.new("UIStroke")
		st.Color = Theme.Fx.NewDotEdge
		st.Thickness = 2
		st.Parent = d
		UI.kitSkin(d, "badge_dot") -- kit badge picture (drawn red dot while its id is 0)
		d.Parent = parent
		dot = d
		table.insert(dots, d)
		hopDots()
	end
	local d = dot :: Frame
	local label = d:FindFirstChild("Mark") :: TextLabel?
	if not label then
		local l = UI.text(d, "!", { Name = "Mark", Font = UI.Head, TextSize = T.Tiny, Outline = "Light", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = d.ZIndex + 1 })
		l.TextWrapped = false
		label = l
	end
	local text = if count and count > 0 then tostring(math.min(count, 99)) else "!"
	if label and label.Text ~= text then
		label.Text = text
		if on and d.Visible then
			UI.pop(d, 0.7)
			UiJuice.wiggle(d) -- a new number: the badge wiggles
		end
	end
	if on and not d.Visible then
		d.Visible = true
		UI.pop(d, 0.3)
		UiJuice.wiggle(d)
	elseif not on then
		d.Visible = false
	end
	return d
end

-- Rarity glow: a border in the rarity colour, and for the rarest ones (shimmer = true) a light band that slowly
-- travels round it. One shared loop (15 Hz) turns every shimmer; destroyed ones drop out.
local shimmers: { UIGradient } = {}
local shimmerLoop = false
function UI.rarityGlow(obj: GuiObject, color: Color3, shimmer: boolean?): UIStroke
	local st = obj:FindFirstChild("RarityGlow") :: UIStroke?
	if not st then
		local n = Instance.new("UIStroke")
		n.Name = "RarityGlow"
		n.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		n.LineJoinMode = Enum.LineJoinMode.Round
		n.Parent = obj
		st = n
	end
	local s = st :: UIStroke
	-- an object has one visible border: hide the ordinary one under the glow
	local plain = obj:FindFirstChild("Border")
	if plain and plain:IsA("UIStroke") then
		plain.Enabled = false
	end
	s.Color = color
	s.Thickness = 2.5
	if shimmer and not s:FindFirstChild("Shimmer") then
		local g = Instance.new("UIGradient")
		g.Name = "Shimmer"
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.45, color),
			ColorSequenceKeypoint.new(0.5, Theme.Fx.Shine),
			ColorSequenceKeypoint.new(0.55, color),
			ColorSequenceKeypoint.new(1, color),
		})
		g.Parent = s
		table.insert(shimmers, g)
		if not shimmerLoop and not UI.Reduced then
			shimmerLoop = true
			task.spawn(function()
				while #shimmers > 0 do
					local r = (os.clock() * 90) % 360
					for i = #shimmers, 1, -1 do
						local gi = shimmers[i]
						if gi.Parent == nil then
							table.remove(shimmers, i)
						elseif not UI.Reduced then
							gi.Rotation = r
						end
					end
					task.wait(1 / 15)
				end
				shimmerLoop = false
			end)
		end
	end
	return s
end

local player = Players.LocalPlayer
local layers: { [string]: ScreenGui } = {}

-- Scale: design canvas ~800 x 400. Landscape phones 667-1108 wide land at 0.83-1.3 (unchanged). Bigger screens keep
-- growing with the height so a menu takes about the same share of a 1080p or 1440p monitor as of a phone:
-- past 1.3 the logical canvas is held at ~600 tall (1080p -> 1.8, 1440p -> 2.4, 4K -> 3.6). A 1366 x 768
-- laptop stays at 1.3.
local DESIGN_W, DESIGN_H, BIG_H = 800, 400, 600
-- Portrait phones are held to a ~390 wide canvas (390 -> 1.0, 430 -> 1.1): the landscape rule would floor them at
-- 0.8 and shrink every label by a fifth.
local PORTRAIT_W = 390
function UI.scaleFor(v: Vector2): number
	if v.Y > v.X then
		return math.clamp(v.X / PORTRAIT_W, 0.8, 1.3)
	end
	local s = math.min(v.X / DESIGN_W, v.Y / DESIGN_H)
	if s <= 1.3 then
		return math.max(s, 0.8)
	end
	return math.max(1.3, math.min(s, v.Y / BIG_H))
end

-- Every constraint UI.fit made, with its design (size, minSize): re-applied when UI.Scale changes so the real-pixel
-- text floor follows the screen (weak keys: a destroyed label drops out).
local fitted: { [UITextSizeConstraint]: { number | any } } = setmetatable({}, { __mode = "k" }) :: any
local fittedScale = 1
local function refitText()
	if math.abs(UI.Scale - fittedScale) < 0.001 then
		return
	end
	fittedScale = UI.Scale
	for c, d in fitted do
		if c.Parent then
			local hi, lo = UiKit.textRange(d[1], d[2], UI.Scale)
			c.MaxTextSize = hi
			c.MinTextSize = lo
		end
	end
end

local function fitScale(gui: ScreenGui, scale: UIScale)
	local function fit()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local v = gui.AbsoluteSize
		if v.X < 2 or v.Y < 2 then
			v = cam.ViewportSize
		end
		scale.Scale = UI.scaleFor(v)
		UI.Scale = scale.Scale
		refitText()
		local l = v / scale.Scale
		-- rounded so "Logical.Y >= 600" holds exactly on screens held at the 600 canvas
		local logical = Vector2.new(math.floor(l.X * 1000 + 0.5) / 1000, math.floor(l.Y * 1000 + 0.5) / 1000)
		if logical ~= UI.Logical then
			UI.Logical = logical
			UI.Resized:Fire()
		end
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
end

UI.Logical = Vector2.new(800, 400)
UI.Resized = Instance.new("BindableEvent") -- fires after UI.Logical changes (a window resized, a phone turned)
UI.ButtonWord = nil :: ((label: TextLabel) -> ())? -- HudArt installs it: owner word pictures on buttons
UI.Scale = 1 -- current UIScale of every layer (they share the viewport)

-- Touch floor in REAL pixels. Theme.Size.Touch (44) is logical and UIScale goes down to 0.8 on small phones, so a
-- 44 logical control can be 35 real px. UI.minTouch() is the logical size that is 44 real px right now.
function UI.minTouch(): number
	return math.max(TS.Touch, math.ceil(TS.Touch / math.max(UI.Scale, 0.1)))
end

-- On touch screens a button smaller than 44 real px gets invisible strips around it that take the tap too
-- (the drawn button and the layout stay as designed). Sized in scale units of the button, so any UIScale above it
-- (layer, modal pop-in, press dip) is already included in AbsoluteSize.
local TOUCH_PAD = UserInputService.TouchEnabled
local function touchPad(b: GuiButton, fire: () -> (), press: ((boolean) -> ())?)
	if not TOUCH_PAD then
		return
	end
	local strips: { [string]: TextButton } = {}
	for _, side in { "Top", "Bottom", "Left", "Right" } do
		local s = Instance.new("TextButton")
		s.Name = "TouchPad" .. side
		s.Text = ""
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.AutoButtonColor = false
		s.Selectable = false
		s.Visible = false
		s.Parent = b
		s.Activated:Connect(fire)
		if press then
			s.MouseButton1Down:Connect(function()
				press(true)
			end)
			s.MouseButton1Up:Connect(function()
				press(false)
			end)
			s.MouseLeave:Connect(function()
				press(false)
			end)
		end
		strips[side] = s
	end
	local function fit()
		local a = b.AbsoluteSize
		if a.X < 1 or a.Y < 1 then
			return
		end
		local real = TS.Touch
		local fy = math.max(0, (real - a.Y) / 2) / a.Y
		local fx = math.max(0, (real - a.X) / 2) / a.X
		strips.Top.Visible = fy > 0
		strips.Bottom.Visible = fy > 0
		strips.Top.Position = UDim2.fromScale(0, -fy)
		strips.Top.Size = UDim2.fromScale(1, fy)
		strips.Bottom.Position = UDim2.fromScale(0, 1)
		strips.Bottom.Size = UDim2.fromScale(1, fy)
		strips.Left.Visible = fx > 0
		strips.Right.Visible = fx > 0
		strips.Left.Position = UDim2.fromScale(-fx, -fy)
		strips.Left.Size = UDim2.fromScale(fx, 1 + 2 * fy)
		strips.Right.Position = UDim2.fromScale(1, -fy)
		strips.Right.Size = UDim2.fromScale(fx, 1 + 2 * fy)
	end
	fit()
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
end
UI.touchPad = touchPad

local function layer(name: string, order: number): ScreenGui
	local have = layers[name]
	if have and have.Parent then
		return have
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = name
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	sg.DisplayOrder = order
	sg.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = sg
	fitScale(sg, scale)
	layers[name] = sg
	return sg
end

-- HUD layer (the loading screen waits for this ScreenGui by name).
function UI.screen(): ScreenGui
	return layer("CrackTheRocks", 5)
end
-- Primary menus and the reveal.
function UI.overlay(): ScreenGui
	return layer("CrackTheRocksModal", 20)
end
-- Confirmation dialogs, above any menu.
function UI.dialogLayer(): ScreenGui
	return layer("CrackTheRocksDialog", 25)
end
-- Notifications, above everything (so a message is never hidden behind a menu).
function UI.noticeLayer(): ScreenGui
	return layer("CrackTheRocksNotice", 30)
end

function UI.isPortrait(): boolean
	return UI.Logical.Y > UI.Logical.X
end

-- Compact phones: logical height under ~480 (landscape phones).
function UI.isShort(): boolean
	return not UI.isPortrait() and UI.Logical.Y < 480
end

-- Builders -----------------------------------------------------------------------------

local function apply(obj: Instance, props: { [string]: any }?)
	if props then
		for k, v in props do
			(obj :: any)[k] = v
		end
	end
end
UI.apply = apply

function UI.corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or T.Radius)
	c.Parent = parent
	return c
end

-- Border around a frame or button (never on text: text outlines come from UI.outline).
function UI.stroke(parent: Instance, color: Color3?, thick: number?)
	local s = Instance.new("UIStroke")
	s.Name = "Border"
	s.Color = color or TC.PanelEdge
	s.Thickness = thick or TS.BorderThin
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

-- Black outline on a text object (strength: "Strong" | "Normal" | "Light").
function UI.outline(label: Instance, strength: string?)
	local old = label:FindFirstChild("Outline")
	if old then
		old:Destroy()
	end
	local s = Instance.new("UIStroke")
	s.Name = "Outline"
	s.Color = TC.Outline
	local base = Theme.Outline[strength or "Normal"] or Theme.Outline.Normal
	s.Thickness = base
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = label
	-- contrast floor: light words carry at least UiKit.LightOutline px of dark outline, also after a recolour
	if label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox") then
		local tl = label :: any
		local function thick()
			if s.Parent == (label :: Instance) then
				s.Thickness = UiKit.outlineFor(tl.TextColor3, base)
			end
		end
		thick()
		label:GetPropertyChangedSignal("TextColor3"):Connect(thick)
	end
	-- the stroke ignores TextTransparency, so hidden text would still draw as a black blob: keep them in step
	if label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox") then
		local tl = label :: any
		s.Transparency = tl.TextTransparency
		label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			if s.Parent == (label :: Instance) then
				s.Transparency = tl.TextTransparency
			end
		end)
	end
	return s
end

function UI.pad(parent: Instance, px: number, py: number?)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, py or px)
	p.PaddingBottom = UDim.new(0, py or px)
	p.Parent = parent
	return p
end

function UI.list(parent: Instance, dir: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or T.Gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = valign or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

function UI.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = TC.Panel
	f.BorderSizePixel = 0
	apply(f, props)
	f.Parent = parent
	return f
end

-- Fits text into its box: designed size when it fits, shrinks otherwise (see top comment).
function UI.fit(label: any, size: number, minSize: number?)
	local c = label:FindFirstChild("Fit") :: UITextSizeConstraint?
	if not c then
		local nc = Instance.new("UITextSizeConstraint")
		nc.Name = "Fit"
		nc.Parent = label
		c = nc
	end
	-- the text floor (UiKit.textRange): designed at 14 px or more, and never drawn under 12 REAL px at the current scale
	local hi, lo = UiKit.textRange(size, minSize, UI.Scale)
	;(c :: UITextSizeConstraint).MaxTextSize = hi
	;(c :: UITextSizeConstraint).MinTextSize = lo
	label.TextScaled = true
	fitted[c :: UITextSizeConstraint] = { size, minSize }
end

-- A one-line label: no wrapping, and the scaled text shrinks to show the whole line instead of wrapping and hiding
-- its second half in a one-line box. Studio check 2026-10-16: with TextTruncate on, scaled text stopped shrinking
-- and showed "GOLDEN..." in a box wide enough for the whole name, so truncation stays off; and a long name may go
-- under the usual text floor (down to `minSize`, default 8) rather than lose letters.
function UI.oneLine(label: TextLabel, minSize: number?)
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.None
	label.TextScaled = true
	local c = label:FindFirstChild("Fit") :: UITextSizeConstraint?
	if c then
		fitted[c] = nil -- a scale change must not lift the floor back up
		c.MinTextSize = math.min(c.MinTextSize, minSize or 8)
	end
end

-- Text label. props.TextSize is the designed size (default Body). props.Outline = "Strong" | "Normal" | "Light" |
-- false (default: Strong for the display font, Light otherwise; none on dark-on-gold text).
function UI.text(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = UI.Body
	t.TextColor3 = TC.Text
	t.Text = text
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	local size = T.Body
	local outline: any = nil
	if props then
		if props.TextSize then
			size = props.TextSize
		end
		if props.Outline ~= nil then
			outline = props.Outline
		end
		props = table.clone(props)
		props.Outline = nil
	end
	t.Size = UDim2.new(1, 0, 0, math.ceil(size * 1.35))
	apply(t, props)
	UI.fit(t, size)
	if outline == nil then
		-- dark text (on gold, or navy notes on a white sheet) never takes the dark outline: it would turn the letters
		-- into one blot
		outline = if t.TextColor3 == TC.DarkText or (Theme.PetStyle and not UiKit.isLight(t.TextColor3)) then false elseif t.Font == UI.Head then "Strong" else "Light"
	end
	if outline == "Normal" and size <= T.Small then
		outline = "Light" -- small body text under the full outline reads heavy and blotted
	end
	if not outline and UiKit.isLight(t.TextColor3) then
		outline = "Light" -- contrast floor: light words over colour always get a dark outline (UI.outline: 2 px or more)
	end
	if outline then
		UI.outline(t, outline)
	else
		-- dark words recoloured light later (row hover, state colours) get their outline then
		t:GetPropertyChangedSignal("TextColor3"):Connect(function()
			if UiKit.isLight(t.TextColor3) and not t:FindFirstChild("Outline") then
				UI.outline(t, "Light")
			end
		end)
	end
	if t.Font == UI.Head and UI.Head ~= UI.Bold then
		-- the display font is drawn in capitals only (its lower case reads as odd small caps); the pet style's one
		-- round font keeps its mixed case
		local function caps()
			local u = UI.caps(t.Text)
			if u ~= t.Text then
				t.Text = u
			end
		end
		caps()
		t:GetPropertyChangedSignal("Text"):Connect(caps)
	end
	t.Parent = parent
	return t
end

-- "PET BOOK" -> "Pet Book" (a title given in capitals for the old bubble font); mixed case stays as it is.
function UI.titleCase(s: string): string
	if s ~= string.upper(s) then
		return s
	end
	local out = {}
	for word in string.gmatch(string.lower(s), "%S+") do
		table.insert(out, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(out, " ")
end

-- Upper case outside rich-text tags ("Find the <font color=...>geode</font>" keeps its tag intact).
function UI.caps(s: string): string
	local parts = {}
	local i = 1
	while i <= #s do
		local a = string.find(s, "<", i, true)
		if not a then
			table.insert(parts, string.upper(string.sub(s, i)))
			break
		end
		table.insert(parts, string.upper(string.sub(s, i, a - 1)))
		local b = string.find(s, ">", a, true) or #s
		table.insert(parts, string.sub(s, a, b))
		i = b + 1
	end
	return table.concat(parts)
end

-- One number formatter for coins: commas below 100,000 ("12,345"), short above ("123K", "1.2M", "3.4B").
function UI.num(n: number): string
	local v = math.floor(n)
	local neg = v < 0
	v = math.abs(v)
	local out: string
	if v < 100000 then
		local s = tostring(v)
		out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if out:sub(1, 1) == "," then
			out = out:sub(2)
		end
	else
		local sizes = { 1e9, 1e6, 1e3 }
		local names = { "B", "M", "K" }
		out = tostring(v)
		for i, size in sizes do
			if v >= size then
				local x = v / size
				local t = if x >= 100 then tostring(math.floor(x)) else string.format("%.1f", math.floor(x * 10) / 10)
				out = (string.gsub(t, "%.0$", "")) .. names[i]
				break
			end
		end
	end
	return if neg then "-" .. out else out
end

function UI.money(n: number): string
	return UI.num(n) .. " coins"
end

-- Icons ------------------------------------------------------------------------------------
-- One illustrated family drawn from rounded blocks: flat fills, one black outline weight (size / 16), a
-- lighter top facet where it helps. props.Color tints the main shape (muted / disabled glyphs).
-- kinds: cash rubble basket rock tray queue hammer jackhammer hand machine press crusher geode gem gear party user
-- shop home exit results lock sell arrow back close plus check star crown clock trophy pickaxe book calendar music
-- speaker camera motion sparkle hint display storage tier1..tier5 warn info

local TIER_COLORS = {
	{ Color3.fromRGB(205, 120, 70), Color3.fromRGB(150, 76, 40) }, -- bronze
	{ Color3.fromRGB(200, 210, 222), Color3.fromRGB(130, 140, 156) }, -- silver
	{ Color3.fromRGB(255, 200, 40), Color3.fromRGB(196, 132, 10) }, -- gold
	{ Color3.fromRGB(240, 96, 60), Color3.fromRGB(150, 40, 24) }, -- volcanic
	{ Color3.fromRGB(150, 110, 255), Color3.fromRGB(80, 50, 170) }, -- meteor
}
UI.TierColors = TIER_COLORS

function UI.icon(parent: Instance, kind: string, size: number, props: { [string]: any }?): Frame
	local box = UI.frame(parent, { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	local tint: Color3? = nil
	local noOutline = false
	if props then
		tint = props.Color
		noOutline = props.Flat == true
		props = table.clone(props)
		props.Color, props.Accent, props.Bg, props.Flat = nil, nil, nil, nil
	end
	apply(box, props)
	if kind == "cash" then
		-- the kit coin picture (UiKit icon_coin) replaces the drawn coin stack once it has an id
		local k = UiKit.skinFor("icon_coin")
		if k then
			local il = Instance.new("ImageLabel")
			il.Name = "KitIcon"
			il.BackgroundTransparency = 1
			il.Size = UDim2.fromScale(1, 1)
			il.Image = k.Image
			il.ScaleType = Enum.ScaleType.Fit
			il.ZIndex = box.ZIndex
			if tint then
				il.ImageColor3 = tint
			end
			il.Parent = box
			return box
		end
	end
	local lw = math.max(1, size / 16)
	local function sq(x: number, y: number, w: number, h: number, color: Color3, rot: number?, round: number?, line: boolean?): Frame
		local f = UI.frame(box, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = tint or color,
			Rotation = rot or 0,
		})
		UI.corner(f, round or math.max(1, math.floor(size * 0.1)))
		if line ~= false and not noOutline then
			UI.stroke(f, TC.Outline, lw)
		end
		return f
	end
	local function disc(x: number, y: number, d: number, color: Color3, line: boolean?)
		return sq(x, y, d, d, color, 0, 999, line)
	end
	local function glyph(text: string, color: Color3, scale: number?)
		local g = UI.text(box, text, { Name = "Glyph", Size = UDim2.fromScale(1, 1), TextSize = math.max(8, size * (scale or 0.62)), Font = UI.Head, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = color, Outline = "Normal" })
		return g
	end
	local WHITE = Color3.fromRGB(250, 250, 250)
	local STEEL = Color3.fromRGB(150, 160, 172)
	local STEEL_HI = Color3.fromRGB(200, 208, 218)
	local WOOD = Color3.fromRGB(168, 104, 52)
	local STONE = Color3.fromRGB(128, 132, 140)
	local STONE_HI = Color3.fromRGB(170, 174, 182)
	local WICKER = Color3.fromRGB(214, 150, 66)
	local WICKER_D = Color3.fromRGB(160, 98, 36)
	local PURPLE = Color3.fromRGB(160, 80, 240)
	local PURPLE_HI = Color3.fromRGB(214, 168, 255)
	local GOLD = TC.Gold
	if kind == "cash" then
		-- a gold coin (the currency is COINS; a bill read as a different money)
		disc(0.54, 0.56, 0.84, Color3.fromRGB(214, 140, 28))
		disc(0.48, 0.48, 0.84, GOLD)
		disc(0.48, 0.48, 0.56, Color3.fromRGB(255, 214, 92), false)
		sq(0.48, 0.48, 0.12, 0.34, Color3.fromRGB(214, 140, 28), 0, 2, false)
	elseif kind == "egg" or string.sub(kind, 1, 4) == "egg_" then
		-- an egg (shop tiers: egg_basic / egg_rare / egg_mythic). Tiers differ in shell and spot colour AND in the gold
		-- marks on top (none / one / three), so they never rely on colour alone.
		local tier = string.sub(kind, 5)
		local shell = if tier == "rare" then Color3.fromRGB(120, 196, 255) elseif tier == "mythic" then Color3.fromRGB(196, 140, 255) else Color3.fromRGB(255, 244, 222)
		local spot = if tier == "rare" then Color3.fromRGB(40, 120, 220) elseif tier == "mythic" then Color3.fromRGB(255, 206, 70) else Color3.fromRGB(120, 200, 110)
		sq(0.5, 0.54, 0.64, 0.86, shell, 0, 999)
		disc(0.38, 0.62, 0.16, spot, false)
		disc(0.62, 0.72, 0.12, spot, false)
		disc(0.6, 0.44, 0.1, spot, false)
		sq(0.4, 0.32, 0.1, 0.2, WHITE, -20, 999, false)
		local marks: { number } = if tier == "rare" then { 0.5 } elseif tier == "mythic" then { 0.3, 0.5, 0.7 } else {}
		for _, x in marks do
			sq(x, 0.12, 0.18, 0.18, GOLD, 45, 2)
		end
	elseif kind == "rubble" then
		-- the candy the eggs leave (old rubble id): a wrapped sweet, pink with a white stripe
		local pink, pinkD = Color3.fromRGB(255, 120, 190), Color3.fromRGB(220, 70, 150)
		sq(0.18, 0.5, 0.26, 0.3, pinkD, 45, 2)
		sq(0.82, 0.5, 0.26, 0.3, pinkD, 45, 2)
		sq(0.5, 0.5, 0.52, 0.52, pink, 0, 999)
		sq(0.5, 0.5, 0.1, 0.5, WHITE, 30, 2, false)
	elseif kind == "basket" then
		local handle = sq(0.5, 0.36, 0.6, 0.5, WICKER_D, 0, 999)
		handle.BackgroundTransparency = 1
		local hs = handle:FindFirstChild("Border") :: UIStroke?
		if hs then
			hs.Color = WICKER_D
			hs.Thickness = math.max(2, size / 10)
		end
		sq(0.36, 0.42, 0.24, 0.2, STONE, 30)
		sq(0.62, 0.42, 0.26, 0.22, STONE_HI, -20)
		sq(0.5, 0.7, 0.86, 0.44, WICKER, 0, 3)
		sq(0.5, 0.52, 0.92, 0.1, WICKER_D, 0, 2)
		sq(0.5, 0.72, 0.7, 0.05, WICKER_D, 0, 1, false)
	elseif kind == "rock" then
		sq(0.5, 0.62, 0.86, 0.6, STONE, 0, math.floor(size * 0.22))
		sq(0.42, 0.44, 0.5, 0.32, STONE_HI, -12, math.floor(size * 0.14), false)
	elseif kind == "tray" or kind == "queue" then
		sq(0.32, 0.46, 0.3, 0.28, STONE, 30)
		sq(0.66, 0.44, 0.32, 0.3, STONE_HI, -20)
		sq(0.5, 0.74, 0.94, 0.24, WOOD, 0, 3)
	elseif kind == "hammer" then
		sq(0.42, 0.62, 0.16, 0.72, WOOD, 40, 3)
		sq(0.64, 0.32, 0.56, 0.28, STEEL, 40, 3)
		sq(0.64, 0.28, 0.4, 0.1, STEEL_HI, 40, 2, false)
	elseif kind == "jackhammer" then
		sq(0.5, 0.14, 0.76, 0.14, Color3.fromRGB(60, 62, 68), 0, 4)
		sq(0.5, 0.44, 0.46, 0.42, GOLD, 0, 5)
		sq(0.5, 0.84, 0.12, 0.3, STEEL, 0, 2)
	elseif kind == "hand" then
		-- a work glove: palm, four fingers, thumb
		local GLOVE = Color3.fromRGB(255, 206, 60)
		for i = 0, 3 do
			sq(0.3 + i * 0.13, 0.3, 0.12, 0.4, GLOVE, 0, 999)
		end
		sq(0.18, 0.56, 0.12, 0.34, GLOVE, -40, 999)
		sq(0.48, 0.62, 0.56, 0.44, GLOVE, 0, math.floor(size * 0.16))
		sq(0.48, 0.86, 0.5, 0.12, Color3.fromRGB(206, 150, 30), 0, 2)
	elseif kind == "machine" then
		sq(0.5, 0.62, 0.86, 0.5, GOLD, 0, 4)
		sq(0.5, 0.26, 0.4, 0.22, Color3.fromRGB(60, 62, 68), 0, 3)
		disc(0.3, 0.62, 0.2, Color3.fromRGB(60, 62, 68))
		disc(0.7, 0.62, 0.2, Color3.fromRGB(60, 62, 68))
	elseif kind == "press" then
		sq(0.5, 0.12, 0.84, 0.16, Color3.fromRGB(60, 62, 68), 0, 3)
		sq(0.5, 0.34, 0.16, 0.3, STEEL, 0, 2)
		sq(0.5, 0.56, 0.6, 0.14, GOLD, 0, 3)
		sq(0.5, 0.86, 0.86, 0.16, Color3.fromRGB(60, 62, 68), 0, 3)
	elseif kind == "crusher" then
		sq(0.5, 0.78, 0.86, 0.28, GOLD, 0, 4)
		disc(0.3, 0.4, 0.4, STEEL)
		disc(0.7, 0.4, 0.4, STEEL)
	elseif kind == "geode" then
		sq(0.5, 0.54, 0.86, 0.8, STONE, 0, 999)
		sq(0.5, 0.56, 0.58, 0.54, PURPLE, 0, 999)
		sq(0.42, 0.5, 0.16, 0.24, PURPLE_HI, 20, 2, false)
		sq(0.6, 0.6, 0.14, 0.2, PURPLE_HI, -25, 2, false)
	elseif kind == "gem" then
		sq(0.5, 0.52, 0.62, 0.62, PURPLE, 45, 4)
		sq(0.42, 0.42, 0.2, 0.2, PURPLE_HI, 45, 2, false)
	elseif kind == "gear" then
		for i = 0, 3 do
			sq(0.5, 0.5, 0.92, 0.22, WHITE, i * 45, 2, false)
		end
		disc(0.5, 0.5, 0.66, WHITE)
		disc(0.5, 0.5, 0.26, Color3.fromRGB(44, 45, 49))
	elseif kind == "party" then
		disc(0.32, 0.28, 0.3, Color3.fromRGB(70, 140, 255))
		sq(0.32, 0.72, 0.46, 0.44, Color3.fromRGB(70, 140, 255), 0, 6)
		disc(0.7, 0.32, 0.28, Color3.fromRGB(240, 70, 60))
		sq(0.7, 0.74, 0.42, 0.4, Color3.fromRGB(240, 70, 60), 0, 6)
	elseif kind == "user" then
		disc(0.5, 0.3, 0.38, Color3.fromRGB(170, 174, 182))
		sq(0.5, 0.78, 0.74, 0.42, Color3.fromRGB(170, 174, 182), 0, 8)
	elseif kind == "shop" then
		sq(0.42, 0.62, 0.16, 0.72, WOOD, 40, 3)
		sq(0.64, 0.32, 0.56, 0.28, STEEL, 40, 3)
	elseif kind == "home" or kind == "exit" then
		sq(0.42, 0.52, 0.56, 0.8, WOOD, 0, 3)
		sq(0.42, 0.52, 0.36, 0.64, Color3.fromRGB(60, 40, 22), 0, 2, false)
		sq(0.78, 0.52, 0.34, 0.14, GOLD, 0, 2)
		sq(0.84, 0.44, 0.14, 0.18, GOLD, 45, 2, false)
		sq(0.84, 0.6, 0.14, 0.18, GOLD, -45, 2, false)
	elseif kind == "results" then
		sq(0.5, 0.5, 0.72, 0.88, WHITE, 0, 4)
		for i = 0, 2 do
			sq(0.5, 0.3 + i * 0.2, 0.44, 0.08, if i == 0 then GOLD else STONE, 0, 1, false)
		end
	elseif kind == "lock" then
		local sh = sq(0.5, 0.34, 0.46, 0.46, STEEL, 0, 999)
		sh.BackgroundTransparency = 1
		local s = sh:FindFirstChild("Border") :: UIStroke?
		if s then
			s.Color = STEEL
			s.Thickness = math.max(2, size / 9)
		end
		sq(0.5, 0.68, 0.72, 0.5, GOLD, 0, 4)
		disc(0.5, 0.66, 0.12, Color3.fromRGB(60, 40, 10), false)
	elseif kind == "sell" then
		sq(0.5, 0.74, 0.86, 0.3, WICKER, 0, 4)
		sq(0.5, 0.36, 0.5, 0.3, Color3.fromRGB(70, 196, 64), -8)
	elseif kind == "arrow" then
		sq(0.5, 0.6, 0.18, 0.6, WHITE, 0, 3)
		sq(0.36, 0.36, 0.18, 0.46, WHITE, 45, 3)
		sq(0.64, 0.36, 0.18, 0.46, WHITE, -45, 3)
	elseif kind == "back" then
		sq(0.42, 0.36, 0.18, 0.5, WHITE, 45, 3)
		sq(0.42, 0.64, 0.18, 0.5, WHITE, -45, 3)
	elseif kind == "close" then
		sq(0.5, 0.5, 0.2, 0.82, WHITE, 45, 2)
		sq(0.5, 0.5, 0.2, 0.82, WHITE, -45, 2)
		sq(0.5, 0.5, 0.2, 0.82, WHITE, 45, 2, false)
	elseif kind == "plus" then
		sq(0.5, 0.5, 0.18, 0.72, WHITE, 0, 3)
		sq(0.5, 0.5, 0.72, 0.18, WHITE, 0, 3)
		sq(0.5, 0.5, 0.18, 0.72, WHITE, 0, 3, false)
	elseif kind == "check" then
		disc(0.5, 0.5, 0.92, Color3.fromRGB(70, 190, 70))
		sq(0.38, 0.56, 0.12, 0.3, WHITE, -45, 2, false)
		sq(0.58, 0.48, 0.12, 0.5, WHITE, 45, 2, false)
	elseif kind == "star" then
		sq(0.5, 0.5, 0.6, 0.6, GOLD, 0, 2)
		sq(0.5, 0.5, 0.6, 0.6, GOLD, 45, 2)
	elseif kind == "crown" then
		sq(0.5, 0.7, 0.8, 0.26, GOLD, 0, 3)
		sq(0.24, 0.44, 0.18, 0.4, GOLD, -12, 3)
		sq(0.5, 0.38, 0.18, 0.46, GOLD, 0, 3)
		sq(0.76, 0.44, 0.18, 0.4, GOLD, 12, 3)
		sq(0.5, 0.7, 0.8, 0.26, GOLD, 0, 3, false)
	elseif kind == "clock" then
		disc(0.5, 0.5, 0.86, WHITE)
		sq(0.5, 0.36, 0.08, 0.32, Color3.fromRGB(44, 45, 49), 0, 2, false)
		sq(0.62, 0.52, 0.28, 0.08, Color3.fromRGB(44, 45, 49), 0, 2, false)
	elseif kind == "trophy" then
		sq(0.5, 0.36, 0.6, 0.5, GOLD, 0, 8)
		sq(0.5, 0.7, 0.14, 0.22, GOLD, 0, 2)
		sq(0.5, 0.86, 0.5, 0.12, Color3.fromRGB(196, 132, 10), 0, 2)
	elseif kind == "pickaxe" then
		sq(0.5, 0.56, 0.12, 0.8, WOOD, 40, 3)
		sq(0.5, 0.36, 0.86, 0.16, STEEL, -12, 999)
	elseif kind == "book" then
		-- the Pet Book: a red cover with its page edge showing and a gold paw-pad on the front
		sq(0.5, 0.52, 0.74, 0.84, Color3.fromRGB(214, 64, 56), 0, 3)
		sq(0.79, 0.52, 0.1, 0.74, WHITE, 0, 1, false)
		sq(0.2, 0.52, 0.1, 0.84, Color3.fromRGB(150, 36, 32), 0, 2, false)
		disc(0.47, 0.56, 0.3, GOLD)
		disc(0.36, 0.36, 0.12, GOLD, false)
		disc(0.58, 0.36, 0.12, GOLD, false)
	elseif kind == "calendar" then
		sq(0.5, 0.56, 0.84, 0.74, WHITE, 0, 4)
		sq(0.5, 0.28, 0.84, 0.2, Color3.fromRGB(240, 70, 60), 0, 3)
		for i = 0, 2 do
			for j = 0, 1 do
				sq(0.28 + i * 0.22, 0.54 + j * 0.2, 0.12, 0.1, Color3.fromRGB(70, 140, 255), 0, 1, false)
			end
		end
	elseif kind == "music" then
		disc(0.32, 0.76, 0.3, WHITE)
		disc(0.74, 0.66, 0.3, WHITE)
		sq(0.42, 0.44, 0.08, 0.6, WHITE, 0, 1, false)
		sq(0.84, 0.36, 0.08, 0.6, WHITE, 0, 1, false)
		sq(0.63, 0.16, 0.5, 0.12, WHITE, -12, 1)
	elseif kind == "speaker" then
		sq(0.26, 0.5, 0.24, 0.32, WHITE, 0, 2)
		sq(0.44, 0.5, 0.26, 0.58, WHITE, 0, 3)
		sq(0.72, 0.5, 0.08, 0.32, WHITE, 0, 2)
		sq(0.88, 0.5, 0.08, 0.54, WHITE, 0, 2)
	elseif kind == "camera" then
		sq(0.5, 0.58, 0.9, 0.62, WHITE, 0, 5)
		sq(0.5, 0.24, 0.34, 0.14, WHITE, 0, 2)
		disc(0.5, 0.58, 0.38, Color3.fromRGB(44, 45, 49))
		disc(0.5, 0.58, 0.18, WHITE, false)
	elseif kind == "motion" then
		disc(0.6, 0.18, 0.22, WHITE)
		sq(0.52, 0.48, 0.18, 0.42, WHITE, 20, 4)
		sq(0.36, 0.8, 0.14, 0.36, WHITE, 30, 3)
		sq(0.66, 0.8, 0.14, 0.34, WHITE, -25, 3)
		sq(0.18, 0.4, 0.22, 0.07, WHITE, 0, 1, false)
		sq(0.14, 0.54, 0.2, 0.07, WHITE, 0, 1, false)
	elseif kind == "sparkle" then
		sq(0.42, 0.52, 0.18, 0.7, GOLD, 0, 999)
		sq(0.42, 0.52, 0.7, 0.18, GOLD, 0, 999)
		sq(0.76, 0.24, 0.1, 0.34, WHITE, 0, 999)
		sq(0.76, 0.24, 0.34, 0.1, WHITE, 0, 999)
	elseif kind == "hint" then
		disc(0.5, 0.4, 0.62, GOLD)
		sq(0.5, 0.78, 0.32, 0.18, STEEL, 0, 2)
	elseif kind == "display" then
		sq(0.5, 0.74, 0.92, 0.22, WOOD, 0, 3)
		for i = 0, 2 do
			sq(0.22 + i * 0.28, 0.46, 0.22, 0.32, Color3.fromRGB(60, 62, 68), 0, 3)
		end
	elseif kind == "storage" then
		sq(0.5, 0.56, 0.84, 0.74, WOOD, 0, 3)
		sq(0.5, 0.56, 0.84, 0.08, Color3.fromRGB(120, 70, 30), 0, 1, false)
		sq(0.5, 0.56, 0.08, 0.74, Color3.fromRGB(120, 70, 30), 0, 1, false)
	elseif string.sub(kind, 1, 4) == "tier" then
		local n = tonumber(string.sub(kind, 5)) or 1
		local col = TIER_COLORS[math.clamp(n, 1, #TIER_COLORS)]
		sq(0.5, 0.5, 0.74, 0.74, col[2], 45, 4)
		sq(0.5, 0.5, 0.5, 0.5, col[1], 45, 3, false)
		sq(0.44, 0.42, 0.16, 0.16, Color3.new(1, 1, 1), 45, 2, false).BackgroundTransparency = 0.45
	elseif kind == "boostCoins" then
		-- pet type icons (Coins / Speed / Luck): procedural stand-ins. REPLACE with the owner's icon art when uploaded.
		disc(0.5, 0.5, 0.9, Color3.fromRGB(255, 196, 40))
		disc(0.5, 0.5, 0.6, Color3.fromRGB(255, 226, 120), false)
		sq(0.5, 0.5, 0.14, 0.38, Color3.fromRGB(200, 140, 20), 0, 2, false)
	elseif kind == "boostSpeed" then
		disc(0.5, 0.5, 0.9, Color3.fromRGB(40, 120, 200))
		sq(0.58, 0.32, 0.16, 0.42, Color3.fromRGB(150, 230, 255), 25, 1, false)
		sq(0.5, 0.5, 0.42, 0.12, Color3.fromRGB(150, 230, 255), -20, 1, false)
		sq(0.42, 0.68, 0.16, 0.42, Color3.fromRGB(150, 230, 255), 25, 1, false)
	elseif kind == "boostLuck" then
		local LEAF = Color3.fromRGB(96, 220, 110)
		disc(0.5, 0.5, 0.9, Color3.fromRGB(30, 110, 50))
		disc(0.36, 0.36, 0.3, LEAF, false)
		disc(0.64, 0.36, 0.3, LEAF, false)
		disc(0.36, 0.62, 0.3, LEAF, false)
		disc(0.64, 0.62, 0.3, LEAF, false)
	elseif kind == "statPower" then
		-- pet stat icons (PetStatView): POWER (the one big number) = a gold bolt on red, Attack = a sword,
		-- Health = a heart, attack speed = two chevrons
		disc(0.5, 0.5, 0.9, Color3.fromRGB(226, 52, 60))
		sq(0.56, 0.3, 0.16, 0.42, GOLD, 25, 1, false)
		sq(0.5, 0.5, 0.42, 0.14, GOLD, -20, 1, false)
		sq(0.44, 0.7, 0.16, 0.42, GOLD, 25, 1, false)
	elseif kind == "statAttack" then
		disc(0.5, 0.5, 0.9, Color3.fromRGB(240, 120, 40))
		sq(0.54, 0.46, 0.16, 0.56, WHITE, 45, 2, false)
		sq(0.36, 0.64, 0.34, 0.12, Color3.fromRGB(120, 60, 20), 45, 2, false)
		sq(0.3, 0.7, 0.12, 0.2, Color3.fromRGB(120, 60, 20), 45, 2, false)
	elseif kind == "statHealth" then
		local HEART = Color3.fromRGB(240, 60, 90)
		disc(0.5, 0.5, 0.9, Color3.fromRGB(255, 200, 210))
		disc(0.38, 0.42, 0.3, HEART, false)
		disc(0.62, 0.42, 0.3, HEART, false)
		sq(0.5, 0.56, 0.3, 0.3, HEART, 45, 2, false)
	elseif kind == "statSpeed" then
		disc(0.5, 0.5, 0.9, Color3.fromRGB(150, 90, 220))
		sq(0.36, 0.4, 0.12, 0.3, WHITE, -45, 2, false)
		sq(0.36, 0.6, 0.12, 0.3, WHITE, 45, 2, false)
		sq(0.6, 0.4, 0.12, 0.3, WHITE, -45, 2, false)
		sq(0.6, 0.6, 0.12, 0.3, WHITE, 45, 2, false)
	elseif kind == "warn" then
		disc(0.5, 0.5, 0.9, TC.Red)
		glyph("!", WHITE, 0.62)
	elseif kind == "info" then
		disc(0.5, 0.5, 0.9, Color3.fromRGB(70, 140, 255))
		glyph("i", WHITE, 0.6)
	end
	return box
end

-- Buttons -----------------------------------------------------------------------------------
-- Styles: "gold" primary (dark text), "gray" secondary, "red" destructive / close, "green" confirm-ready,
-- "blue" lobby HUD tiles and the DAILY button.
-- Legacy names map: yellow / orange -> gold, dark / light -> gray. States: hover (lighter), pressed (dip),
-- selected (gold ring, UI.setSelected), disabled (flat gray, no input: UI.setEnabled), pending (UI.pending).

type ButtonStyle = { Fill: Color3, Hover: Color3, Line: Color3, Text: Color3, Flat: boolean? }
-- Pet style (Theme.PetStyle): the primary is the clip's lime, the secondary a flat navy, HUD tiles cyan; every
-- caption white with the dark outline.
local STYLE: { [string]: ButtonStyle } = if Theme.PetStyle then {
	gold = { Fill = PET.Lime, Hover = PET.LimeHover, Line = PET.LimeEdge, Text = TC.Text },
	gray = { Fill = PET.TabBar, Hover = TC.GrayHover, Line = PET.TabBarEdge, Text = PET.TabText, Flat = true },
	red = { Fill = PET.Red, Hover = PET.RedTop, Line = PET.RedEdge, Text = TC.Text },
	green = { Fill = PET.Price, Hover = PET.PriceTop, Line = PET.PriceEdge, Text = TC.Text },
	blue = { Fill = PET.Cyan, Hover = PET.CyanTop, Line = PET.CyanEdge, Text = TC.Text }, -- lobby HUD tiles
} else {
	gold = { Fill = TC.Gold, Hover = TC.GoldHover, Line = TC.GoldDeep, Text = TC.DarkText },
	-- secondary: flat desaturated slate with a thin edge, no gloss or lip, never a kit picture (UiKit.ButtonFor), so a
	-- filter or a locked reward never reads like the primary button next to it (Studio check 2026-10-14)
	gray = { Fill = Color3.fromRGB(70, 80, 100), Hover = Color3.fromRGB(88, 100, 124), Line = Color3.fromRGB(34, 40, 54), Text = TC.Text, Flat = true },
	red = { Fill = TC.Red, Hover = Color3.fromRGB(240, 80, 70), Line = TC.RedDeep, Text = TC.Text },
	green = { Fill = TC.Green, Hover = Color3.fromRGB(110, 220, 104), Line = TC.GreenDeep, Text = TC.Text },
	blue = { Fill = TC.Hud, Hover = Color3.fromRGB(70, 132, 240), Line = TC.PanelEdge, Text = TC.Text }, -- lobby HUD tiles
}
local ALIAS = { yellow = "gold", orange = "gold", primary = "gold", dark = "gray", light = "gray", secondary = "gray", destructive = "red" }

local function styleOf(style: string?): string
	local s = style or "gold"
	s = ALIAS[s] or s
	return if STYLE[s] then s else "gold"
end
UI.styleOf = styleOf

-- Cartoon button look: a darker lip along the bottom (the gradient multiplies whatever fill the button has).
function UI.bevel(b: GuiObject): UIGradient
	local old = b:FindFirstChild("Bevel")
	if old and old:IsA("UIGradient") then
		return old
	end
	local g = Instance.new("UIGradient")
	g.Name = "Bevel"
	g.Rotation = 90
	local lip = Theme.Button.Lip
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Button.TopShade),
		ColorSequenceKeypoint.new(0.35, Theme.Button.TopShade),
		ColorSequenceKeypoint.new(lip - 0.02, Theme.Button.MidShade),
		ColorSequenceKeypoint.new(lip, Theme.Button.LipShade),
		ColorSequenceKeypoint.new(1, Theme.Button.LipShade),
	})
	g.Parent = b
	return g
end

-- UI kit skins (shared/UiKit, "Polygon Adventure" pictures) ------------------------------------------------------
-- One ImageLabel "KitSkin" under an object's children draws the kit picture (9-slice or whole); the drawn fill,
-- border strokes and gloss step aside while it shows. An entry whose id is 0 (UiKit.skinFor nil) removes the picture
-- and gives the drawn look back. The owner's earlier HUD pictures (HudArt.skin) win: they set "OwnerSkin".

-- The drawn look (fill, border strokes, gloss) on or off under a kit picture.
local function kitDrawn(obj: GuiObject, on: boolean)
	obj.BackgroundTransparency = if on then ((obj:GetAttribute("KitBgT") :: number?) or 0) else 1
	for _, c in obj:GetChildren() do
		if c:IsA("UIStroke") then
			if on and c:GetAttribute("KitOff") then
				c.Enabled = true
				c:SetAttribute("KitOff", nil)
			elseif not on and c.Enabled then
				c.Enabled = false
				c:SetAttribute("KitOff", true)
			end
		elseif c.Name == "Gloss" and c:IsA("GuiObject") then
			c.Visible = on
		end
	end
end

-- Fits a kit picture to its object after layout (AbsoluteSize, UIScale removed): the slice scale per element
-- (UiKit.fitScale: corners never overlap or stretch; a menu panel's corners also shrink on short screens), the drawn
-- look instead when the picture's shape does not suit the object (UiKit.fits), and for a menu panel the inner content
-- rect (UiKit.contentInset): a "KitPad" UIPadding puts header, tabs, body and footer inside the rim, the picture
-- itself spans the whole panel and the solid backing fills exactly the content rect.
local function kitFit(obj: GuiObject, img: ImageLabel, skin: UiKit.Skin)
	if skin.ScaleType ~= "Slice" then
		return
	end
	local sc = math.max(UI.Scale, 0.01)
	local w = if obj.AbsoluteSize.X > 0 then obj.AbsoluteSize.X / sc else obj.Size.X.Offset
	local h = if obj.AbsoluteSize.Y > 0 then obj.AbsoluteSize.Y / sc else obj.Size.Y.Offset
	-- AbsoluteSize also holds the panel's pop-in UIScale: measure at rest
	local enter = obj:FindFirstChild("Enter")
	if enter and enter:IsA("UIScale") and enter.Scale > 0.01 then
		w /= enter.Scale
		h /= enter.Scale
	end
	local panel = obj:GetAttribute("KitPanel") == true
	local fits = UiKit.fits(skin, w, h)
	if img.Visible ~= fits then
		img.Visible = fits
		kitDrawn(obj, not fits)
	end
	local s = UiKit.fitScale(skin, w, h, if panel then UiKit.panelCap(UI.Logical.Y) else nil)
	if img.SliceScale ~= s then
		img.SliceScale = s
	end
	if not panel then
		return
	end
	local l, t, r, b = UiKit.contentInset(skin, s)
	local rimT = t
	if obj:GetAttribute("KitHeaderOnRim") then
		t = 0 -- a menu's header (title tab, coins, X) sits on the top rim by design; the body starts under it
	end
	local pad = obj:FindFirstChild("KitPad") :: UIPadding?
	if not pad then
		local n = Instance.new("UIPadding")
		n.Name = "KitPad"
		n.Parent = obj
		pad = n
	end
	local p = pad :: UIPadding
	p.PaddingLeft = UDim.new(0, l)
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r)
	p.PaddingBottom = UDim.new(0, b)
	img.Position = UDim2.fromOffset(-l, -t)
	img.Size = UDim2.new(1, l + r, 1, t + b)
	local back = obj:FindFirstChild("KitBacking")
	if back and back:IsA("GuiObject") then
		-- the fill stays inside the rim even when the header sits on it: filling up to the panel's top edge showed a
		-- white strip above the header plate wherever the rim picture is see-through (Daily, Egg Shrine walkthrough)
		local top = UiKit.backingTop(t, rimT)
		back.Position = UDim2.fromOffset(0, top)
		back.Size = UDim2.new(1, 0, 1, -top)
	end
end

-- The content insets a kit panel uses now (0s while it is drawn): panels that place things against the panel's own
-- edge read this instead of guessing the rim.
function UI.kitInset(panel: Instance): (number, number, number, number)
	local p = panel:FindFirstChild("KitPad")
	if p and p:IsA("UIPadding") then
		return p.PaddingLeft.Offset, p.PaddingTop.Offset, p.PaddingRight.Offset, p.PaddingBottom.Offset
	end
	return 0, 0, 0, 0
end

-- A menu panel's kit picture plus a solid fill under its middle (a panel must hide the HUD behind it even where the
-- picture's middle is light or soft). Returns true when the picture shows.
function UI.kitPanel(panel: GuiObject, key: string): boolean
	panel:SetAttribute("KitPanel", true)
	local on = UI.kitSkin(panel, key)
	if on and not panel:FindFirstChild("KitBacking") then
		local f = Instance.new("Frame")
		f.Name = "KitBacking"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = panel.BackgroundColor3
		f.BackgroundTransparency = (panel:GetAttribute("KitBgT") :: number?) or 0
		f.ZIndex = -2
		f.Active = false
		f.Parent = panel
		local img = panel:FindFirstChild("KitSkin") :: ImageLabel
		local s = UiKit.skinFor(key)
		if s then
			kitFit(panel, img, s)
		end
		-- panels recoloured after this (PanelSkin) keep the fill in their colour
		panel:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			f.BackgroundColor3 = panel.BackgroundColor3
		end)
	end
	return on
end

-- Draws kit picture `key` behind `obj`'s children (pressed: the _pressed picture when the kit has one). Returns true
-- when a picture shows. Safe to call again on every state change: it only updates the one ImageLabel.
function UI.kitSkin(obj: GuiObject, key: string?, pressed: boolean?): boolean
	-- the pet style draws everything itself: no kit picture ever shows (Theme.PetStyle)
	local skin = if obj:GetAttribute("OwnerSkin") or Theme.PetStyle then nil else UiKit.skinFor(key)
	local img = obj:FindFirstChild("KitSkin") :: ImageLabel?
	if not skin then
		if img then
			-- back to the drawn look
			img:Destroy()
			for _, n in { "KitBacking", "KitPad" } do
				local c = obj:FindFirstChild(n)
				if c then
					c:Destroy()
				end
			end
			kitDrawn(obj, true)
			obj:SetAttribute("KitOn", nil)
		end
		return false
	end
	local s = skin :: UiKit.Skin
	if not img then
		local n = Instance.new("ImageLabel")
		n.Name = "KitSkin"
		n.BackgroundTransparency = 1
		n.Size = UDim2.fromScale(1, 1)
		n.ZIndex = -1 -- under the shine sweep (ZIndex 0), the caption and every other child
		n.Active = false
		n.Parent = obj
		img = n
		obj:SetAttribute("KitBgT", obj.BackgroundTransparency)
		obj:SetAttribute("KitOn", true)
		kitDrawn(obj, false)
		obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local cur = UiKit.skinFor(obj:GetAttribute("KitKey") :: string?)
			if cur and n.Parent then
				kitFit(obj, n, cur)
			end
		end)
	end
	local i = img :: ImageLabel
	obj:SetAttribute("KitKey", key)
	i.Image = if pressed and s.Pressed then s.Pressed else s.Image
	i.ScaleType = if s.ScaleType == "Slice" then Enum.ScaleType.Slice else Enum.ScaleType.Fit
	local rect, center = UiKit.crop(s)
	i.ImageRectOffset = Vector2.zero
	i.ImageRectSize = if rect ~= s.Pixels then rect else Vector2.zero -- zero: the whole picture
	i.SliceCenter = center
	kitFit(obj, i, s)
	return true
end

-- The kit picture a UI.button shows now: its "Kit" attribute (tabs: "tab", the selected one "tab_active"; the close X
-- "close_x"), else its style's button (UiKit.ButtonFor). Pressed swaps in the _pressed picture; disabled tints grey.
local function kitPaint(b: GuiButton)
	local base = b:GetAttribute("Kit")
	local key: string?
	if base == "tab" then
		key = if b:GetAttribute("Style") == "gold" or b:GetAttribute("Selected") == true then "tab_active" else "tab"
	elseif type(base) == "string" then
		key = base
	else
		key = UiKit.buttonKey(b:GetAttribute("Style") :: string?)
	end
	local disabled = b:GetAttribute("Disabled") == true
	if UI.kitSkin(b, key, b:GetAttribute("Pressed") == true and not disabled) then
		local img = b:FindFirstChild("KitSkin") :: ImageLabel
		img.ImageColor3 = if disabled then Color3.fromRGB(150, 150, 150) elseif b:GetAttribute("Hover") == true then Color3.new(1, 1, 1) else Color3.fromRGB(242, 242, 242)
	end
end

local function paint(b: GuiButton)
	local st = STYLE[styleOf(b:GetAttribute("Style") :: string?)]
	local disabled = b:GetAttribute("Disabled") == true
	local hover = b:GetAttribute("Hover") == true and not disabled
	local label = b:FindFirstChild("Label") :: TextLabel?
	local line = b:FindFirstChild("Border") :: UIStroke?
	b.BackgroundColor3 = if disabled then (b:GetAttribute("DisabledFill") :: Color3? or TC.Disabled) elseif hover then st.Hover else st.Fill
	if b:GetAttribute("Pressed") == true and not disabled then
		b.BackgroundColor3 = b.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.22) -- darker while the finger is down
	end
	local flat = st.Flat == true
	if line then
		line.Color = if b:GetAttribute("Selected") then TC.Text elseif disabled then TC.GrayDeep else st.Line
		line.Thickness = if b:GetAttribute("Selected") then (if flat then 2.5 else 3) elseif flat then 1.5 else TS.BorderThin
	end
	if flat and b:GetAttribute("Selected") and not disabled then
		b.BackgroundColor3 = if Theme.PetStyle then PET.Blue else Color3.fromRGB(112, 128, 160) -- the picked filter: lighter with a white edge
	end
	-- flat: no gloss band and no lip gradient (they follow the style, so a restyled button gets them back)
	local gl = b:FindFirstChild("Gloss")
	if gl and gl:IsA("GuiObject") and not b:GetAttribute("KitOn") then
		gl.Visible = not flat
	end
	local bev = b:FindFirstChild("Bevel")
	if bev and bev:IsA("UIGradient") then
		bev.Enabled = not flat
	end
	if label then
		local fg = if disabled then (b:GetAttribute("DisabledText") :: Color3? or TC.DisabledText) else st.Text
		label.TextColor3 = fg
		local o = label:FindFirstChild("Outline") :: UIStroke?
		if o then
			o.Enabled = fg ~= TC.DarkText
		end
	end
	kitPaint(b) -- the kit picture follows style, press, hover and disabled (fallback: the drawn look above)
end
UI.paint = paint

-- Button with a caption child "Label" (fitted, outlined unless dark-on-gold). onClick runs on Activated (mouse,
-- touch, gamepad A and keyboard selection alike) and never while the button is disabled or pending.
function UI.button(parent: Instance, text: string, style: string?, onClick: (() -> ())?, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(140, TS.Button)
	b:SetAttribute("Style", styleOf(style))
	local size = T.Head
	local word = true -- props.Word = false keeps the caption as text even when the word has a picture
	if props and (props.TextSize or props.Word ~= nil) then
		size = props.TextSize or size
		word = props.Word ~= false
		props = table.clone(props)
		props.TextSize = nil
		props.Word = nil
	end
	apply(b, props)
	UI.corner(b, T.Radius)
	UI.stroke(b, TC.PanelEdge, TS.BorderThin)
	-- sheen and glint sit under the caption (ZIndex 0)
	UI.gloss(b)
	UI.shine(b)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, -6)
	label.Position = UDim2.fromOffset(6, 3)
	label.Font = UI.Head
	label.TextWrapped = true
	label.Text = text
	label.Parent = b
	UI.fit(label, size)
	if word and UI.ButtonWord then
		UI.ButtonWord(label) -- the owner's word picture when this word has one (HudArt sets the hook)
	end
	UI.outline(label, "Normal")
	-- display-font captions are capitals only (a caller may switch the label to the body font for mixed case)
	local function caps()
		if label.Font == UI.Head and UI.Head ~= UI.Bold then
			local u = UI.caps(label.Text)
			if u ~= label.Text then
				label.Text = u
			end
		end
	end
	caps()
	label:GetPropertyChangedSignal("Text"):Connect(caps)
	UI.bevel(b)
	paint(b)
	b.Parent = parent
	UI.squashScale(b)
	-- press: quick dip, release: spring back past 1 and settle (Theme.Spring)
	local function press(on: boolean)
		UI.squash(b, on)
		b:SetAttribute("Pressed", on)
		paint(b)
	end
	b.MouseButton1Down:Connect(function()
		if not b:GetAttribute("Disabled") then
			press(true)
		end
	end)
	b.MouseButton1Up:Connect(function()
		press(false)
	end)
	b.MouseEnter:Connect(function()
		b:SetAttribute("Hover", true)
		paint(b)
		if UserInputService.MouseEnabled and not b:GetAttribute("Disabled") then
			UI.spring(UI.squashScale(b), Theme.Spring.Release, { Scale = Theme.Loop.HoverScale })
		end
	end)
	b.MouseLeave:Connect(function()
		b:SetAttribute("Hover", false)
		paint(b)
		press(false)
	end)
	b.SelectionGained:Connect(function()
		b:SetAttribute("Hover", true)
		paint(b)
	end)
	b.SelectionLost:Connect(function()
		b:SetAttribute("Hover", false)
		paint(b)
	end)
	if onClick then
		local function fire()
			if b:GetAttribute("Disabled") then
				Audio.play("Denied", { Key = "ui:denied" }) -- a greyed-out button: soft "not yet" bonk
				return
			end
			Audio.button()
			onClick()
		end
		b.Activated:Connect(fire)
		touchPad(b, fire, function(on: boolean)
			if not on or not b:GetAttribute("Disabled") then
				press(on)
			end
		end)
	end
	return b
end

-- One caption size for a row of buttons: the largest size (<= `size`) at which every button's caption fits its
-- label box, so a long caption (SKIP TUTORIAL) no longer shrinks alone next to a short one (LOBBY).
-- Re-checked when the row resizes; measured in logical px (UI.Scale removed).
function UI.sameTextSize(row: GuiObject, size: number)
	local function layout()
		local labels: { TextLabel } = {}
		for _, b in row:GetChildren() do
			local l = if b:IsA("GuiButton") then b:FindFirstChild("Label") else nil
			if l and l:IsA("TextLabel") then
				table.insert(labels, l)
			end
		end
		local k = math.max(UI.Scale, 0.01)
		local best = math.floor(size)
		for _, l in labels do
			-- the button's own squash scale is undone too, so a press never re-sizes the row
			local sq = (l.Parent :: Instance):FindFirstChild("Squash") :: UIScale?
			local f = k * (if sq then math.max(sq.Scale, 0.01) else 1)
			local w, h = l.AbsoluteSize.X / f, l.AbsoluteSize.Y / f
			if w <= 0 or h <= 0 then
				return
			end
			while best > T.MinText do
				local need = TextService:GetTextSize(l.Text, best, l.Font, Vector2.new(w, 10000))
				if need.X <= w and need.Y <= h then
					break
				end
				best -= 1
			end
		end
		for _, l in labels do
			UI.fit(l, best, T.MinText)
		end
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	task.defer(layout)
end

function UI.setText(b: GuiButton, text: string)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

-- Disabled buttons look flat gray and do not accept input (Activated is ignored, AutoButtonColor off).
function UI.setEnabled(b: GuiButton, enabled: boolean, style: string?)
	if style then
		b:SetAttribute("Style", styleOf(style))
	end
	b:SetAttribute("Disabled", not enabled)
	b.Selectable = enabled
	paint(b)
end

function UI.setStyle(b: GuiButton, style: string)
	b:SetAttribute("Style", styleOf(style))
	paint(b)
end

-- Selected ring (tabs, slots, chosen options).
function UI.setSelected(b: GuiButton, on: boolean)
	b:SetAttribute("Selected", on)
	paint(b)
end

-- Marks a button as waiting for the server: disabled with `text` until done() runs or `timeout` seconds pass
-- (default 4), and a refusal notice (kind "warn") ends it at once. Returns done. Safe if the button was rebuilt.
UI.Notice = Instance.new("BindableEvent") -- (text, kind): every notification, so panels can react
function UI.pending(b: GuiButton, text: string, timeout: number?): () -> ()
	local label = b:FindFirstChild("Label") :: TextLabel?
	local before = if label then label.Text else ""
	local wasDisabled = b:GetAttribute("Disabled") == true
	UI.setEnabled(b, false)
	b:SetAttribute("Pending", true)
	if label then
		label.Text = text
	end
	local finished = false
	local conn: RBXScriptConnection? = nil
	local function done()
		if finished then
			return
		end
		finished = true
		if conn then
			conn:Disconnect()
		end
		if b.Parent then
			b:SetAttribute("Pending", nil)
			if label then
				label.Text = before
			end
			UI.setEnabled(b, not wasDisabled)
		end
	end
	conn = UI.Notice.Event:Connect(function(_, kind)
		if kind == "warn" then
			done()
		end
	end)
	task.delay(timeout or 4, done)
	return done
end

-- Red close square with a white X (44 px hit area).
function UI.closeButton(parent: Instance, onClick: () -> (), props: { [string]: any }?): TextButton
	local x = UI.button(parent, "", "red", onClick, { Name = "Close", Size = UDim2.fromOffset(TS.Close, TS.Close) })
	apply(x, props)
	local l = x:FindFirstChild("Label")
	if l then
		l:Destroy()
	end
	local xIcon = UI.icon(x, "close", math.floor(TS.Close * 0.55), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	x:SetAttribute("Kit", "close_x")
	paint(x)
	if x:GetAttribute("KitOn") then
		xIcon.Visible = false -- the kit picture has its own X
	end
	-- the square is 40 px (smaller on notices), the touch area at least 44 (plus the real-px pad from UI.button)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.new(1, 6, 1, 6)
	hit.Selectable = false
	local minHit = Instance.new("UISizeConstraint")
	minHit.MinSize = Vector2.new(TS.Touch, TS.Touch)
	minHit.Parent = hit
	hit.Parent = x
	hit.Activated:Connect(function()
		Audio.button()
		onClick()
	end)
	-- the X squashes on press and bounces back like every button
	hit.MouseButton1Down:Connect(function()
		UI.squash(x, true)
	end)
	hit.MouseButton1Up:Connect(function()
		UI.squash(x, false)
	end)
	hit.MouseLeave:Connect(function()
		UI.squash(x, false)
	end)
	return x
end

-- Components -------------------------------------------------------------------------------

-- Card. tone: "inset" (dark row inside a panel, default) | "panel" (charcoal) | "hud" (floating HUD card).
function UI.card(parent: Instance, tone: string?, props: { [string]: any }?): Frame
	local t = tone or "inset"
	local f = UI.frame(parent, {
		BackgroundColor3 = if t == "panel" then TC.Panel elseif t == "hud" then TC.Hud else TC.Inset,
		BackgroundTransparency = if t == "hud" then 0.1 else 0,
	})
	apply(f, props)
	UI.corner(f, T.Radius)
	UI.stroke(f, if t == "inset" then TC.InsetEdge elseif t == "panel" then TC.PanelRim else TC.PanelEdge, if t == "inset" then 2 else TS.BorderThin)
	if t ~= "inset" then
		UI.panelShade(f)
	end
	return f
end

-- Progress bar. Returns (track, fill); set fill.Size = UDim2.fromScale(v, 1).
function UI.bar(parent: Instance, props: { [string]: any }?, color: Color3?): (Frame, Frame)
	local track = UI.frame(parent, { Name = "Bar", Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = TC.Inset })
	apply(track, props)
	UI.corner(track, 4)
	UI.stroke(track, if Theme.PetStyle then PET.QuestEdge else TC.Outline, 1.5)
	local fill = UI.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or (if Theme.PetStyle then TC.Green else TC.Gold) })
	UI.corner(fill, 4)
	-- kit progress pictures (drawn bar while their ids are 0)
	UI.kitSkin(track, "progress_bg")
	UI.kitSkin(fill, "progress_fill")
	-- shine sweep: a light band runs along the fill each time it grows (not while one is still running)
	fill.ClipsDescendants = true
	local shine = UI.frame(fill, { Name = "Shine", BackgroundColor3 = Theme.Fx.Shine, BackgroundTransparency = 0.25, Position = UDim2.fromScale(-0.5, 0), Size = UDim2.fromScale(0.4, 1), Visible = false })
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sg.Parent = shine
	local last, sweeping = 0, false
	fill:GetPropertyChangedSignal("Size"):Connect(function()
		local v = fill.Size.X.Scale
		local grew = v > last + 0.001
		last = v
		if not grew or sweeping or UI.Reduced or v <= 0 then
			return
		end
		sweeping = true
		shine.Position = UDim2.fromScale(-0.5, 0)
		shine.Visible = true
		local tw = TweenService:Create(shine, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.1, 0) })
		tw.Completed:Connect(function()
			shine.Visible = false
			sweeping = false
		end)
		tw:Play()
	end)
	return track, fill
end

-- Cash readout: cash-stack icon + green outlined amount. Returns (frame, set(n)).
function UI.cash(parent: Instance, size: number, props: { [string]: any }?): (Frame, (number) -> ())
	local f = UI.frame(parent, { Name = "Cash", BackgroundTransparency = 1, Size = UDim2.fromOffset(size * 5.4, size) })
	apply(f, props)
	if Theme.PetStyle then
		-- the clip's readout: a navy pill with the coin over its left end and white digits
		f.BackgroundTransparency = 0
		f.BackgroundColor3 = PET.TabBar
		UI.corner(f, 999)
		UI.stroke(f, PET.TabBarEdge, 2)
	else
		UI.kitSkin(f, "coin_pill") -- kit coin pill behind the readout (none while its id is 0)
	end
	UI.icon(f, "cash", size, { Position = UDim2.fromOffset(if Theme.PetStyle then 2 else 0, 0) })
	local l = UI.text(f, "0", { Name = "Amount", Font = UI.Head, TextSize = size * 0.92, TextColor3 = if Theme.PetStyle then TC.Text else TC.Cash, Outline = "Strong", Position = UDim2.fromOffset(size + 6, 0), Size = UDim2.new(1, -(size + 10), 1, 0) })
	l.TextWrapped = false
	local last: number? = nil
	return f, function(n: number)
		-- the amount counts up (or down) to the new value instead of jumping
		UiJuice.countTo(l, last or n, n, UI.num)
		if last and n > last then
			UI.pop(l, 0.85) -- the readout bumps when coins arrive
		end
		last = n
	end
end

-- Icon + caption + value card for the HUD ("CARRIED 3/5"). Returns (card, set(value, cap?)).
function UI.counter(parent: Instance, icon: string, caption: string, props: { [string]: any }?): (Frame, (number, number?) -> ())
	local f = UI.card(parent, "hud", { Name = "Counter", Size = UDim2.fromOffset(124, 50) })
	apply(f, props)
	UI.icon(f, icon, 30, { Position = UDim2.fromOffset(7, 13) })
	UI.text(f, caption, { Name = "Caption", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Text, Outline = "Normal", Position = UDim2.fromOffset(44, 3), Size = UDim2.new(1, -48, 0, 17) })
	local v = UI.text(f, "", { Name = "Value", Font = UI.Head, TextSize = T.Count, TextColor3 = TC.Count, Outline = "Strong", Position = UDim2.fromOffset(44, 19), Size = UDim2.new(1, -48, 0, 28) })
	v.TextWrapped = false
	return f, function(n: number, cap: number?)
		local txt = if cap then (tostring(n) .. "/" .. tostring(cap)) else tostring(n)
		if txt ~= v.Text and v.Text ~= "" then
			UI.pop(v, 1.25) -- the number pops when it changes
		end
		v.Text = txt
		v.TextColor3 = if cap and n >= cap then TC.Warn else TC.Count
	end
end

-- Tab words: designed size and the readable floor (Studio sweep #177: words shrank to about 8 px on a phone).
-- (#230 / #237: still small on a phone, so body size with a body-size floor, and bigger tab icons)
local TAB_TEXT = T.Body + 2
local TAB_MIN = T.Body
local TAB_ICON = TS.Tab - 8

-- A button with a picture left of its word: the picture shows only while the word still fits beside it at `minSize`
-- (measured in logical px); otherwise it hides and the word takes the whole width. Re-checked when the button resizes.
function UI.iconWord(b: GuiObject, l: TextLabel, icon: GuiObject, iconW: number, minSize: number)
	local x0 = l.Position.X.Offset
	local w0 = l.Size.X.Offset
	local function layout()
		local w = b.AbsoluteSize.X / math.max(UI.Scale, 0.01)
		if w <= 0 then
			return
		end
		local need = TextService:GetTextSize(l.Text, minSize, l.Font, Vector2.new(2000, 100)).X
		local room = w + w0 - (iconW + 6) - 2
		local show = need <= room
		icon.Visible = show
		if show then
			l.Position = UDim2.new(l.Position.X.Scale, x0 + iconW + 6, l.Position.Y.Scale, l.Position.Y.Offset)
			l.Size = UDim2.new(l.Size.X.Scale, w0 - (iconW + 6), l.Size.Y.Scale, l.Size.Y.Offset)
		else
			l.Position = UDim2.new(l.Position.X.Scale, x0, l.Position.Y.Scale, l.Position.Y.Offset)
			l.Size = UDim2.new(l.Size.X.Scale, w0, l.Size.Y.Scale, l.Size.Y.Offset)
		end
	end
	layout()
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
end

-- A tab's picture and word as one centred group (the picture at the left edge pushed the word off-centre, Studio):
-- the word is measured at its current fitted size and the pair sits in the middle of the tab. The picture hides when
-- the word would not fit beside it at the readable minimum. Re-placed on resize and when the bar's text size changes.
function UI.tabIconWord(b: GuiObject, l: TextLabel, icon: GuiObject, iconSize: number?, minText: number?)
	local gap = 6
	local ICON = iconSize or TAB_ICON
	local MIN = minText or TAB_MIN
	local function place()
		local w = b.AbsoluteSize.X / math.max(UI.Scale, 0.01)
		if w <= 0 then
			return
		end
		local fc = l:FindFirstChild("Fit") :: UITextSizeConstraint?
		local size = if fc then fc.MaxTextSize else TAB_TEXT
		local room = w - 8 - (ICON + gap)
		local show = TextService:GetTextSize(l.Text, MIN, l.Font, Vector2.new(2000, 100)).X <= room
		icon.Visible = show
		if show then
			local tw = math.min(TextService:GetTextSize(l.Text, size, l.Font, Vector2.new(2000, 100)).X, room)
			local left = math.floor((w - (ICON + gap + tw)) / 2)
			icon.Position = UDim2.new(0, left, 0.5, 0)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.new(0, left + ICON + gap, 0.5, -13)
			l.Size = UDim2.new(0, math.max(1, w - 4 - (left + ICON + gap)), 0, 26)
		else
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.Position = UDim2.new(0, 4, 0.5, -13)
			l.Size = UDim2.new(1, -8, 0, 26)
		end
	end
	place()
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	local fc = l:FindFirstChild("Fit")
	if fc then
		fc:GetPropertyChangedSignal("MaxTextSize"):Connect(place)
	end
end

-- Segmented tabs: gray pills, the selected one gold. `items` = { { Id, Label } }. Up to five share the row;
-- more scroll sideways. Returns the row.
function UI.tabs(parent: Instance, items: { { string } }, current: string, onPick: (string) -> (), props: { [string]: any }?): Frame
	local row = UI.frame(parent, { Name = "Tabs", Size = UDim2.new(1, 0, 0, TS.Tab), BackgroundTransparency = 1 })
	apply(row, props)
	if Theme.PetStyle then
		-- the clip's tab bar: a navy strip, the picked tab a lime pill, the others plain words on the navy
		row.BackgroundTransparency = 0
		row.BackgroundColor3 = PET.TabBar
		UI.corner(row, 999)
		UI.stroke(row, PET.TabBarEdge, 2.5)
		UI.pad(row, 4, 4)
	end
	local n = #items
	-- an upright phone with five or more tabs: fixed-width tabs in a sideways strip (the last one peeks out, so it
	-- reads as "slide for more") instead of words squeezed too small to read
	local crowded = UI.isPortrait() and n >= 5
	local strip: GuiObject = row
	if crowded then
		local sc = Instance.new("ScrollingFrame")
		sc.Name = "Strip"
		sc.BackgroundTransparency = 1
		sc.BorderSizePixel = 0
		sc.Size = UDim2.fromScale(1, 1)
		sc.ScrollingDirection = Enum.ScrollingDirection.X
		sc.AutomaticCanvasSize = Enum.AutomaticSize.X
		sc.CanvasSize = UDim2.new()
		sc.ScrollBarThickness = 0
		sc.Parent = row
		strip = sc
	end
	UI.list(strip, Enum.FillDirection.Horizontal, 6)
	local curIndex: number? = nil
	for i, it in items do
		if it[1] == current then
			curIndex = i
		end
	end
	for i, it in items do
		local id, label = it[1], it[2]
		local on = id == current
		local tb = UI.button(strip, label, if on then "gold" else "gray", function()
			if not on then
				local host = row.Parent
				local before: { [Instance]: boolean } = {}
				if host then
					for _, c in host:GetChildren() do
						before[c] = true
					end
				end
				onPick(id)
				-- the new tab's content slides in from the side of the tab that was tapped (right of the old tab: from
				-- the right; left of it: from the left); only content the pick just built moves (persistent headers
				-- and bars stay put and never drift on quick taps), never inside a layout
				if host and not host:FindFirstChildWhichIsA("UIGridStyleLayout") then
					local fresh: { GuiObject } = {}
					for _, c in host:GetChildren() do
						if c:IsA("GuiObject") and not before[c] and c.Name ~= "Tabs" and c ~= row then
							table.insert(fresh, c)
						end
					end
					UiJuice.slideIn(fresh, UiMotion.slideFrom(curIndex, i, 28))
				end
			end
		end, { Name = "Tab_" .. id, LayoutOrder = i, TextSize = T.Small + 1, Size = if crowded then UDim2.new(0, 96, 1, 0) else UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0) })
		tb:SetAttribute("Selected", false)
		tb:SetAttribute("Kit", "tab") -- kit tab pictures (tab / tab_active) instead of the button ones
		paint(tb)
		if Theme.PetStyle then
			UI.corner(tb, 999)
			local border = tb:FindFirstChild("Border")
			if border and border:IsA("UIStroke") then
				border.Enabled = on -- an unpicked tab is just its word on the strip
			end
			local gl = tb:FindFirstChild("Gloss")
			if gl and gl:IsA("GuiObject") then
				gl.Visible = false
			end
		end
		local l = tb:FindFirstChild("Label") :: TextLabel?
		if l then
			l.Font = UI.Bold
			l.Text = label -- mixed case in the body font
			l.TextWrapped = false
			-- one line only: a box too short for two lines makes TextScaled shrink the word instead of splitting it
			l.Size = UDim2.new(1, -8, 0, 26)
			l.Position = UDim2.new(0, 4, 0.5, -13)
			UI.fit(l, TAB_TEXT, TAB_MIN)
			l.TextWrapped = false
			-- optional third entry: an uploaded icon id drawn left of the word (HudArt low-poly icons); it steps aside
			-- whenever the word would not fit beside it at a readable size (UI.iconWord)
			-- (an entry that is not an rbxassetid is a drawn UI.icon kind: the fallback while an upload is missing)
			local pic = it[3]
			if pic and pic ~= "" and not string.match(pic, "^rbxassetid://0$") then
				local img: GuiObject
				if string.match(pic, "^rbxassetid://") then
					local il = Instance.new("ImageLabel")
					il.BackgroundTransparency = 1
					il.Image = pic
					il.ScaleType = Enum.ScaleType.Fit
					il.Size = UDim2.fromOffset(TAB_ICON, TAB_ICON)
					il.Parent = tb
					img = il
				else
					img = UI.icon(tb, pic, TAB_ICON)
				end
				img.Name = "TabIcon"
				img.AnchorPoint = Vector2.new(0, 0.5)
				img.Position = UDim2.new(0, 4, 0.5, 0)
				img.ZIndex = l.ZIndex
				UI.tabIconWord(tb, l, img)
			end
		end
	end
	-- one text size for the whole bar: the designed size when every word fits its tab, else the readable minimum
	-- for all of them (measured, so a tab never shrinks its word below T.Small)
	local function equalize()
		if not row.Parent then
			return
		end
		local labels: { TextLabel } = {}
		local all = true
		for _, tb in strip:GetChildren() do
			local l = tb:FindFirstChild("Label")
			if l and l:IsA("TextLabel") and l:FindFirstChild("Fit") and tb:IsA("GuiObject") then
				table.insert(labels, l)
				local w = l.AbsoluteSize.X / math.max(UI.Scale, 0.01)
				if w > 0 and TextService:GetTextSize(l.Text, TAB_TEXT, l.Font, Vector2.new(2000, 100)).X > w then
					all = false
				end
			end
		end
		for _, l in labels do
			UI.fit(l, if all then TAB_TEXT else TAB_MIN, TAB_MIN) -- also keeps the real-pixel floor and re-fits on a scale change
		end
	end
	task.defer(equalize)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(equalize)
	end)
	return row
end
UI.tabBar = UI.tabs

-- Catalog row: thumbnail on the left, title, a status line and an optional small badge button on the right.
-- opts = { Name, Title, Sub, SubColor, Selected, Thumb = fn(container), Badge, BadgeStyle, OnBadge, OnSelect, Height }
function UI.catalogRow(parent: Instance, order: number, opts: { [string]: any }): TextButton
	local h = opts.Height or TS.Row
	local b = Instance.new("TextButton")
	b.Name = opts.Name or ("Row_" .. order)
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.Size = UDim2.new(1, -6, 0, h)
	b.BackgroundColor3 = TC.Inset
	b.BorderSizePixel = 0
	b.Parent = parent
	UI.corner(b, T.Radius)
	local edge = UI.stroke(b, if opts.Selected then TC.Gold else TC.InsetEdge, if opts.Selected then 3.5 else 1.5)
	UI.kitSkin(b, if opts.Selected then "card_selected" else "card") -- kit card picture (drawn row while id 0)
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = TC.InsetHover
		UiJuice.sweep(b, T.Radius) -- one shine across the row on hover
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = TC.Inset
	end)
	local thumb = UI.frame(b, { Name = "Thumb", BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(h - 8, h - 8) })
	if opts.Thumb then
		opts.Thumb(thumb)
	end
	local badgeW = if opts.Badge then (if UI.isShort() then 78 else 92) else 0
	local textW = -(h + 6 + badgeW + (if badgeW > 0 then 8 else 4))
	local hasSub = opts.Sub ~= nil and opts.Sub ~= ""
	local title = UI.text(b, opts.Title or "", { Name = "Title", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(h + 4, if hasSub then 4 else 0), Size = UDim2.new(1, textW, 0, if hasSub then math.floor(h * 0.5) - 2 else h) })
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	if hasSub and opts.SubPill then
		-- status as a small badge (Owned / Equipped): tinted pill in the status colour
		-- sized from the measured text (nested AutomaticSize left the pill narrower than its word)
		local col: Color3 = opts.SubColor or TC.Muted
		-- body-size word in a pill as tall as the row's lower half allows (#237: "Equipped" / "Current" were tiny)
		local pillH = math.max(22, math.floor(h * 0.5) - 3)
		local textSize = math.min(T.Body, pillH - 4)
		local need = TextService:GetTextSize(opts.Sub, textSize, UI.Bold, Vector2.new(1000, 1000))
		local pill = UI.frame(b, { Name = "SubPill", Position = UDim2.fromOffset(h + 4, math.floor(h * 0.5) + 1), Size = UDim2.fromOffset(math.ceil(need.X) + 20, pillH), BackgroundColor3 = col, BackgroundTransparency = 0 })
		UI.corner(pill, 8)
		-- solid light pill with dark words (a see-through pill in its own colour was unreadable on the blue row, Studio)
		UI.stroke(pill, col:Lerp(Color3.new(0, 0, 0), 0.45), 2)
		local st = UI.text(pill, opts.Sub, { Name = "Sub", Font = UI.Bold, TextSize = textSize, TextColor3 = TC.DarkText, Outline = false, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
		st.TextWrapped = false
	elseif hasSub then
		-- prices: a strong dark outline so green / pale words read on the blue row
		UI.text(b, opts.Sub, { Name = "Sub", Font = UI.Bold, TextSize = T.Small, TextColor3 = opts.SubColor or TC.Muted, Outline = "Strong", Position = UDim2.fromOffset(h + 4, math.floor(h * 0.5)), Size = UDim2.new(1, textW, 0, math.floor(h * 0.5) - 4) })
	end
	if opts.Selected and not opts.Badge then
		-- picked row: a small gold arrow at the right edge points at the detail side
		local arrow = UI.text(b, "\u{25B6}", { Name = "PickedArrow", Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Gold, Outline = "Light", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(18, 22), TextXAlignment = Enum.TextXAlignment.Center })
		arrow.TextWrapped = false
	end
	if opts.Badge then
		local bb = UI.button(b, opts.Badge, opts.BadgeStyle or "gold", opts.OnBadge or opts.OnSelect, {
			Name = "Badge", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(badgeW, math.min(32, h - 12)), TextSize = T.Small,
		})
		if opts.BadgeEnabled == false then
			UI.setEnabled(bb, false)
		end
	end
	b.Activated:Connect(function()
		if opts.OnSelect then
			Audio.button()
			opts.OnSelect()
		end
	end)
	if opts.OnSelect then
		UI.bouncy(b)
	end
	if opts.Selected then
		task.defer(UiJuice.sweep, b, T.Radius) -- the picked row shines once
	end
	b:SetAttribute("Selected", opts.Selected == true)
	local _ = edge
	return b
end

-- Square specimen card: picture (fn(container)) over a caption; gold ring when selected; "Empty" style when
-- opts.Empty. opts = { Name, Caption, Picture, Selected, Empty, OnSelect, CaptionColor, RarityColor, Shimmer }
function UI.specimenCard(parent: Instance, order: number, opts: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Name = opts.Name or ("Card_" .. order)
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.BackgroundColor3 = TC.Inset
	b.BorderSizePixel = 0
	b.Parent = parent
	UI.corner(b, T.Radius)
	UI.stroke(b, if opts.Selected then TC.Gold else TC.InsetEdge, if opts.Selected then 2.5 else 1.5)
	if Theme.PetStyle and not opts.Empty then
		-- the clip's pet tiles: a blue gradient square with a white edge (gold when picked)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		local tg = Instance.new("UIGradient")
		tg.Name = "Tile"
		tg.Rotation = 90
		tg.Color = ColorSequence.new(PET.BlueTop, PET.Blue)
		tg.Parent = b
		local bs = b:FindFirstChild("Border")
		if bs and bs:IsA("UIStroke") and not opts.Selected then
			bs.Color = Color3.new(1, 1, 1)
			bs.Thickness = 2
		end
	end
	-- kit card picture: selected frame, else the rarity frame (opts.Rarity), else the plain card
	local kitted = UI.kitSkin(b, UiKit.cardKey(opts.Selected == true, opts.Rarity))
	local rarityFramed = kitted and not opts.Selected and opts.Rarity ~= nil and UiKit.RarityFor[opts.Rarity] ~= nil
	if opts.Glow then
		-- pet type glow: the card's lower part washes into the type colour (opts.Glow), under the picture
		local glow = UI.frame(b, { Name = "TypeGlow", BackgroundColor3 = opts.Glow, BackgroundTransparency = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4) })
		UI.corner(glow, T.Radius)
		local gr = Instance.new("UIGradient")
		gr.Rotation = 90
		gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.85), NumberSequenceKeypoint.new(1, 0.45) })
		gr.Parent = glow
	end
	local pic = UI.frame(b, { Name = "Picture", BackgroundTransparency = 1, Position = UDim2.new(0, 4, 0, 4), Size = UDim2.new(1, -8, 1, -26) })
	if opts.Picture then
		opts.Picture(pic)
	elseif opts.Empty then
		-- an open frame with a "+" (a grey rock blob read as something in the slot, Studio #183)
		b.BackgroundTransparency = 0.55
		local well = UI.frame(pic, { Name = "EmptyWell", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -4), BackgroundTransparency = 1 })
		UI.corner(well, T.RadiusSm)
		local ws = UI.stroke(well, TC.Faint, 2)
		ws.Transparency = 0.35
		local plus = UI.text(well, "+", { Name = "Plus", Font = UI.Head, TextSize = T.Title + 8, TextColor3 = TC.Faint, Outline = "Light", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		plus.TextWrapped = false
	end
	local cap = UI.text(b, opts.Caption or "", { Name = "Caption", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = opts.CaptionColor or (if opts.Empty then TC.Faint else TC.Text), Outline = "Light", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -3), Size = UDim2.new(1, -8, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	UI.oneLine(cap) -- "Skeleton Thunderstrut" wrapped and showed only "Skeleton"; it shrinks, never "..."
	if opts.TypeIcon then
		UI.icon(b, opts.TypeIcon, 18, { Name = "TypeIcon", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -22) })
	end
	-- rarity glow: the border in the rarity colour (the selected gold ring wins), shimmering for the rarest
	if opts.RarityColor and not opts.Selected and not rarityFramed then
		local g = UI.rarityGlow(b, opts.RarityColor, opts.Shimmer == true)
		if opts.Thick then
			g.Thickness = 4.5
		end
	end
	b.Activated:Connect(function()
		if opts.OnSelect then
			Audio.button()
			opts.OnSelect()
		end
	end)
	if opts.OnSelect then
		UI.bouncy(b)
		b.MouseEnter:Connect(function()
			UiJuice.sweep(b, T.Radius) -- one shine across the card on hover
		end)
	end
	if opts.Selected then
		task.defer(UiJuice.sweep, b, T.Radius) -- the picked card shines once
	end
	return b
end

-- Label left, value right (stats). `emphasis` = the value in the display font and count colour.
function UI.statRow(parent: Instance, order: number, label: string, value: string, emphasis: boolean?): Frame
	local row = UI.card(parent, "inset", { Name = "Stat", Size = UDim2.new(1, -6, 0, 40), LayoutOrder = order })
	UI.text(row, label, { Name = "Label", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.62, -12, 1, 0) })
	UI.text(row, value, { Name = "Value", Font = if emphasis then UI.Head else UI.Bold, TextSize = if emphasis then T.Head else T.Body, TextColor3 = if emphasis then TC.Count else TC.Text, Outline = "Normal", Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.38, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	return row
end

-- Empty state: picture, headline, one line, optional action button. Returns (frame, button?).
function UI.emptyState(parent: Instance, title: string, message: string, icon: string?, props: { [string]: any }?, action: { Text: string, OnClick: () -> () }?): (Frame, TextButton?)
	local f = UI.frame(parent, { Name = "Empty", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if action then 186 else 128) })
	apply(f, props)
	UI.list(f, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	UI.icon(f, icon or "egg", 54, { LayoutOrder = 1 })
	UI.text(f, title, { Name = "Headline", Font = UI.Head, TextSize = T.Head, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(f, message, { Name = "Message", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	local btn: TextButton? = nil
	if action then
		local gap = UI.frame(f, { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 4), LayoutOrder = 4 })
		local _ = gap
		btn = UI.button(f, action.Text, "gold", action.OnClick, { Name = "Action", LayoutOrder = 5, Size = UDim2.fromOffset(220, 46) })
	end
	return f, btn
end

-- Loading state: one line and three dots (the dots step unless Reduce Motion). Returns the frame.
function UI.loadingState(parent: Instance, text: string, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Name = "Loading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70) })
	apply(f, props)
	UI.text(f, text, { Name = "Text", Font = UI.Head, TextSize = T.Head, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
	local dots = {}
	for i = 1, 3 do
		local d = UI.frame(f, { Name = "Dot" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, (i - 2) * 22, 0, 40), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = if i == 1 then TC.Gold else TC.Gray })
		UI.corner(d, 7)
		UI.stroke(d, TC.Outline, 1.5)
		dots[i] = d
	end
	if not UI.Reduced then
		task.spawn(function()
			local k = 1
			while f.Parent do
				task.wait(0.35)
				k = k % 3 + 1
				for i, d in dots do
					d.BackgroundColor3 = if i == k then TC.Gold else TC.Gray
				end
			end
		end)
	end
	return f
end

-- Error state: a headline, an optional line and RETRY / CLOSE (CLOSE only when onClose is given).
function UI.errorState(parent: Instance, title: string, message: string?, onRetry: () -> (), onClose: (() -> ())?, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Name = "Error", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, if message then 122 else 98) })
	apply(f, props)
	UI.text(f, title, { Name = "Headline", Font = UI.Head, TextSize = T.Head, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
	if message then
		UI.text(f, message, { Name = "Message", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	end
	local row = UI.frame(f, { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 46) })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local r = UI.button(row, "RETRY", "gold", onRetry, { Name = "Retry", Size = UDim2.fromOffset(140, 46), LayoutOrder = 1 })
	local _ = r
	if onClose then
		UI.button(row, "CLOSE", "gray", onClose, { Name = "CloseState", Size = UDim2.fromOffset(140, 46), LayoutOrder = 2 })
	end
	return f
end

-- Slider (0..1 in 0.05 steps). Drag with mouse or touch; the camera never sees the drag because the panel blocks
-- input. Returns (holder, set(v)). onChange(v, final).
function UI.slider(parent: Instance, value: number, onChange: (number, boolean) -> (), props: { [string]: any }?): (TextButton, (number) -> ())
	local hit = Instance.new("TextButton")
	hit.Name = "Slider"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(0.5, 0, 0, T.Touch)
	apply(hit, props)
	-- invisible drag box: hold it to 44 real px on small phones (the track stays centred)
	if hit.Size.Y.Scale == 0 then
		hit.Size = UDim2.new(hit.Size.X.Scale, hit.Size.X.Offset, 0, math.max(hit.Size.Y.Offset, UI.minTouch()))
	end
	hit.Parent = parent
	local track = UI.frame(hit, { Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(1, -20, 0, 12), BackgroundColor3 = TC.Inset })
	UI.corner(track, 6)
	UI.stroke(track, TC.Outline, 1.5)
	local fill = UI.frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = TC.Gold })
	UI.corner(fill, 6)
	local knob = UI.frame(track, { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromRGB(245, 245, 245) })
	UI.corner(knob, 11)
	UI.stroke(knob, TC.Outline, 2)
	local v = math.clamp(value, 0, 1)
	local function show()
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
	end
	local function setFrom(x: number, final: boolean)
		local w = math.max(track.AbsoluteSize.X, 1)
		v = math.clamp(math.floor((x - track.AbsolutePosition.X) / w * 20 + 0.5) / 20, 0, 1)
		show()
		onChange(v, final)
	end
	local dragging: InputObject? = nil
	hit.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			setFrom(input.Position.X, false)
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseMovement) then
			setFrom(input.Position.X, false)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
			onChange(v, true)
		end
	end)
	-- gamepad / keyboard: left and right step the value while the slider is selected
	hit.SelectionImageObject = nil :: any -- no selection ring (the API type is not optional)
	local c3 = UserInputService.InputBegan:Connect(function(input)
		if GuiService.SelectedObject ~= hit then
			return
		end
		local step = if input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then 0.05 elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then -0.05 else 0
		if step ~= 0 then
			v = math.clamp(math.floor((v + step) * 20 + 0.5) / 20, 0, 1)
			show()
			onChange(v, true)
		end
	end)
	hit.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
		c3:Disconnect()
	end)
	show()
	return hit, function(nv: number)
		v = math.clamp(nv, 0, 1)
		show()
	end
end

-- ON / OFF switch (green when on). Returns (button, set(on)).
function UI.toggle(parent: Instance, on: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (TextButton, (boolean) -> ())
	local hit = Instance.new("TextButton")
	hit.Name = "Switch"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromOffset(84, T.Touch)
	apply(hit, props)
	hit.Parent = parent
	local sw = UI.frame(hit, { Name = "Track", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(78, 32) })
	UI.corner(sw, 16)
	UI.stroke(sw, TC.Outline, 2)
	local knob = UI.frame(sw, { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromRGB(245, 245, 245) })
	UI.corner(knob, 13)
	UI.stroke(knob, TC.Outline, 1.5)
	local word = UI.text(sw, "", { Name = "Word", Font = UI.Head, TextSize = T.Small, Outline = "Normal", Size = UDim2.new(0, 42, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	local state = on
	local function show()
		sw.BackgroundColor3 = if state then TC.Green else TC.Gray
		knob.Position = if state then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		word.Text = if state then "ON" else "OFF"
		word.Position = if state then UDim2.fromOffset(6, 0) else UDim2.new(1, -46, 0, 0)
	end
	local function flip()
		Audio.button()
		state = not state
		show()
		onChange(state)
	end
	hit.Activated:Connect(flip)
	touchPad(hit, flip)
	show()
	return hit, function(v: boolean)
		state = v
		show()
	end
end

-- Small tinted pill with text (rarity, status).
function UI.chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Size = UDim2.fromOffset(96, 24), BackgroundColor3 = color })
	apply(f, props)
	UI.corner(f, T.Radius)
	UI.stroke(f, TC.Outline, 1.5)
	UI.text(f, text, { Name = "Text", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextSize = T.Tiny, Font = UI.Bold, Outline = "Normal", TextXAlignment = Enum.TextXAlignment.Center })
	return f
end

UI.ScrollBar = 6
UI.ScrollBarColor = if Theme.PetStyle then PET.Blue else Color3.fromRGB(24, 38, 82)

-- Scrolling area that grows with its content.
function UI.scroller(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	-- a dark navy bar, solid: it reads on cream, sky and gold panels alike (gold on a yellow-brown list vanished)
	s.ScrollBarThickness = UI.ScrollBar
	s.ScrollBarImageColor3 = UI.ScrollBarColor
	s.ScrollBarImageTransparency = 0
	s.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Size = UDim2.fromScale(1, 1)
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	apply(s, props)
	s.Parent = parent
	return s
end

-- Sizes a scroller's canvas from its list layout instead of AutomaticCanvasSize (which Studio left short of the last
-- quest card, so it could not be scrolled fully into view): content + padding + `extra` (a card gap under the last
-- card, UiMotion.canvasHeight). Re-measured whenever the content or the scale changes.
function UI.fitCanvas(sc: ScrollingFrame, layout: UIListLayout, extra: number?)
	sc.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fit()
		local pad = sc:FindFirstChildOfClass("UIPadding")
		local top = if pad then pad.PaddingTop.Offset else 0
		local bottom = if pad then pad.PaddingBottom.Offset else 0
		local content = layout.AbsoluteContentSize.Y / math.max(UI.Scale, 0.01)
		sc.CanvasSize = UDim2.fromOffset(0, UiMotion.canvasHeight(content, top, bottom, extra))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	sc:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end

-- How much shorter (logical px) a scroll window should be (its height now plus `extra`) so that, scrolled to the top,
-- it ends on a whole row instead of cutting one mid-way (UiKit.snapCut over the bottoms of `sc`'s visible children). The panel
-- shows the strip it frees as bottom padding.
function UI.rowCut(sc: ScrollingFrame, extra: number?): number
	-- px per logical px right now: the layer's UIScale times any UIScale above (a menu's pop-in spring)
	local k = math.max(UI.Scale, 0.01)
	local a = sc.Parent
	while a and not a:IsA("ScreenGui") do
		local u = a:FindFirstChildOfClass("UIScale")
		if u and u.Scale > 0.01 then
			k *= u.Scale
		end
		a = a.Parent
	end
	local window = sc.AbsoluteWindowSize.Y / k + (extra or 0)
	local top = sc.AbsolutePosition.Y
	local bottoms: { number } = {}
	local heights: { number } = {}
	for _, c in sc:GetChildren() do
		if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.Y > 0 then
			table.insert(bottoms, (c.AbsolutePosition.Y + c.AbsoluteSize.Y - top) / k + sc.CanvasPosition.Y + 2)
			table.insert(heights, c.AbsoluteSize.Y / k)
		end
	end
	return UiKit.snapCut(bottoms, window, nil, heights)
end

-- Keeps a scroller's window ending on a whole row (UI.rowCut / UiKit.snapCut) instead of cutting one mid-way under a
-- footer, and gives its canvas at least `bottomPad` px of bottom padding (the height of whatever sits over the
-- bottom) so the last row can always scroll fully into view. Re-measured when the canvas or window changes.
function UI.endOnRow(sc: ScrollingFrame, bottomPad: number?)
	local base = sc.Size
	local cut = 0
	local busy = false
	local pad = sc:FindFirstChildOfClass("UIPadding")
	if pad and bottomPad and pad.PaddingBottom.Offset < bottomPad then
		pad.PaddingBottom = UDim.new(0, bottomPad)
	end
	local function measure()
		if busy or sc.AbsoluteWindowSize.Y <= 0 then
			return
		end
		busy = true
		local want = UI.rowCut(sc, cut)
		if want ~= cut then
			cut = want
			sc.Size = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - cut)
		end
		busy = false
	end
	sc:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		task.defer(measure)
	end)
	sc:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		task.defer(measure)
	end)
	task.defer(measure)
end

-- A row inside a list layout (fixed height, full width).
function UI.row(parent: Instance, height: number, order: number, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = order })
	apply(f, props)
	return f
end

-- Input stack ----------------------------------------------------------------------------------
-- UI.block(key, on) holds gameplay input while any key is present (menus, dialogs, the reveal, results).
-- CameraMode listens (free cursor, suspended look / move, hidden touch controls) and restores first person once
-- when the last key goes.

UI.ModalChanged = Instance.new("BindableEvent") -- (name or nil): the primary menu
UI.BlockChanged = Instance.new("BindableEvent") -- (blocked)
local blockers: { [string]: true } = {}
local lastUnblocked = -math.huge

-- os.clock() of the moment the last blocking key was released (set synchronously, so an input that arrives in the
-- same frame as the close is already inside the grace window; CameraMode.mayAct reads it).
function UI.unblockedAt(): number
	return lastUnblocked
end

function UI.block(key: string, on: boolean)
	local was = next(blockers) ~= nil
	if on then
		blockers[key] = true
	else
		blockers[key] = nil
	end
	local blocked = next(blockers) ~= nil
	if was and not blocked then
		lastUnblocked = os.clock()
	end
	pcall(function()
		GuiService.TouchControlsEnabled = not blocked
	end)
	UI.BlockChanged:Fire(blocked)
end

function UI.blocked(): boolean
	return next(blockers) ~= nil
end

-- Modal shell ------------------------------------------------------------------------------------

local function shadeButton(root: Instance, name: string, transparency: number): TextButton
	local shade = Instance.new("TextButton")
	shade.Name = name
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = TC.Shade
	shade.BackgroundTransparency = transparency
	shade.Size = UDim2.fromScale(1, 1)
	shade.Selectable = false
	shade.Parent = root
	return shade
end

-- Gamepad: navigation stays inside the panel and the first control is selected when the last input was a gamepad.
local function gamepadFocus(panel: GuiObject, isOpen: () -> boolean)
	pcall(function()
		panel.SelectionGroup = true
		panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
		panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
		panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
		panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	end)
	task.defer(function()
		pcall(function()
			if not isOpen() then
				return
			end
			if string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad" then
				local first: GuiObject? = nil
				for _, d in panel:GetDescendants() do
					if d:IsA("GuiButton") and d.Selectable and d.Name ~= "Close" and d.Name ~= "Hit" then
						first = d
						break
					end
				end
				if first then
					GuiService.SelectedObject = first
				end
			end
		end)
	end)
end

local function clearSelectionIn(root: Instance)
	pcall(function()
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
	end)
end

-- Header: title on the left (display font, strong outline), optional cash readout, red close on the right.
-- Returns (header, setCash or nil, title label).
-- The shortest landscape phones (about 310 px tall: under 395 logical) get a compact header and title tab, and a
-- thinner outer margin, so the kit rim does not eat the menu's content.
function UI.compactMenus(): boolean
	return not UI.isPortrait() and UI.Logical.Y < 395 -- same cut as the panels' own "tight" layouts (ShopPanel, QuestPanel)
end
-- Height of the gold title tab that sits on a menu's top edge (PanelSkin).
function UI.headerTab(): number
	return if UI.compactMenus() then 46 else 56
end

local function headerHeight(): number
	return if UI.compactMenus() then 44 else 54
end
local function header(panel: Frame, title: string, opts: { [string]: any }, close: () -> ()): (Frame, ((number) -> ())?, TextLabel)
	local h = UI.frame(panel, { Name = "Header", Size = UDim2.new(1, 0, 0, headerHeight()), BackgroundTransparency = 1 })
	local right = if opts.NoClose then 12 else TS.Close + 18
	local cashW = if opts.Cash then 118 else 0
	local t: TextLabel
	if Theme.PetStyle then
		-- the clip's menus: the title floats over the sheet's top edge at the left (centred: over the middle), white
		-- with a deep blue edge and a dark copy under it; the red X sits on the top right corner, a little tilted
		local tw = UDim2.new(1, -(28 + right + cashW + 6), 0, 40)
		local tp = { Name = "Title", Font = UI.Head, TextSize = T.Title + 2, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(14, 18), Size = tw, ZIndex = 3, TextXAlignment = if opts.Center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left }
		if opts.Center then
			tp.Position = UDim2.fromOffset(0, 18)
			tp.Size = UDim2.new(1, 0, 0, 40)
		end
		local sp = table.clone(tp)
		sp.Name = "TitleShadow"
		sp.Position = tp.Position + UDim2.fromOffset(0, 3)
		sp.TextColor3 = PET.TitleShadow
		sp.ZIndex = 2
		local shadow = UI.text(h, UI.titleCase(title), sp)
		shadow.TextWrapped = false
		local so = shadow:FindFirstChild("Outline")
		if so and so:IsA("UIStroke") then
			so.Color = PET.TitleShadow
			so.Thickness = 4
		end
		t = UI.text(h, UI.titleCase(title), tp)
		t.TextWrapped = false
		local o = t:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			o.Color = PET.TitleEdge
			o.Thickness = 3.4
		end
		t:GetPropertyChangedSignal("Text"):Connect(function()
			-- panels that retitle themselves ("PARTY 2/4") keep the mixed case and the dark copy in step
			local want = UI.titleCase(t.Text)
			if want ~= t.Text then
				t.Text = want
				return
			end
			shadow.Text = t.Text
		end)
	else
		t = UI.text(h, title, { Name = "Title", Font = UI.Head, TextSize = T.Title, Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -(16 + right + cashW + 6), 0, 44), TextXAlignment = if opts.Center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left })
		t.TextWrapped = false
	end
	local setCash: ((number) -> ())? = nil
	if opts.Cash then
		local _, set = UI.cash(h, 24, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(right + 2), if Theme.PetStyle then 0 else 0.5, if Theme.PetStyle then 14 else 2), Size = UDim2.fromOffset(cashW, 24) })
		setCash = set
	end
	if not opts.NoClose then
		if Theme.PetStyle then
			UI.closeButton(h, close, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -10, 0, 4), Rotation = 4, ZIndex = 4 })
		else
			UI.closeButton(h, close, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 2) })
		end
	end
	return h, setCash, t
end

export type ModalOpts = {
	Dismissable: boolean?, -- tap outside closes (default true)
	Footer: number?, -- height reserved for footer buttons (returned as the 4th value)
	Fixed: boolean?, -- body is a plain Frame (the panel does its own scrolling)
	Subtitle: string?, -- one short line under the title
	NoClose: boolean?, -- no X (the panel offers its own way out)
	Cash: boolean?, -- cash readout in the header (UI.modalCash sets it)
	Center: boolean?, -- centred title
}

local current: { Close: () -> (), Name: string, SetCash: ((number) -> ())?, Panel: Frame, HeaderH: number }? = nil

-- Panel blur: a BlurEffect on the camera (a camera effect, Lighting is never touched) softens the world while a
-- menu is open. Closing one menu and opening the next in the same frame keeps it on.
local blurOn = false
local function setBlur(on: boolean)
	blurOn = on
	task.defer(function()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local b = cam:FindFirstChild("MenuBlur") :: BlurEffect?
		if not b then
			if not blurOn then
				return
			end
			local n = Instance.new("BlurEffect")
			n.Name = "MenuBlur"
			n.Size = 0
			n.Parent = cam
			b = n
		end
		local blur = b :: BlurEffect
		local goal = if blurOn then Theme.Motion.Blur else 0
		if UI.Reduced then
			blur.Size = goal
		else
			TweenService:Create(blur, TweenInfo.new(Theme.Motion.BlurIn), { Size = goal }):Play()
		end
	end)
end
-- Closing a menu or dialog: the panel shrinks away (ease in, slightly past small) while the shade fades, then
-- both are destroyed. Input is cut at once so a tap during the shrink reaches nothing. Reduce Motion: instant.
local function shrinkAway(shade: GuiObject, panel: GuiObject)
	if UI.Reduced then
		shade:Destroy()
		return
	end
	shade.Name = "Closing" -- lookups by name never find the panel on its way out
	shade.Active = false
	shade.Interactable = false
	panel.Interactable = false
	local t = Theme.Motion.PanelShrink
	TweenService:Create(shade, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	local sc = panel:FindFirstChild("Enter") :: UIScale?
	if not sc then
		local n = Instance.new("UIScale")
		n.Name = "Enter"
		n.Parent = panel
		sc = n
	end
	local s = sc :: UIScale
	spr.stop(s)
	TweenService:Create(s, TweenInfo.new(t, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = Theme.Motion.PanelShrinkTo }):Play()
	task.delay(t + 0.05, function()
		shade:Destroy()
	end)
end
-- Keeps the notification column clear of open menu headers (defined with the notifications below).
local fitNotices: () -> () = function() end

-- The one primary menu. Opening one closes the previous one (and any dialog over it). Returns
-- (panel, body, close, footer). Sizes are min(available, wanted) so the panel always fits the safe area.
local MODAL_TOPLEFT_CLEAR = 130 -- studs from the screen's left edge that Roblox's menu + chat buttons occupy
local MODAL_TAB_DROP = 16 -- extra top gap that keeps the gold title tab off those buttons
-- how far the gold title tab (PanelSkin: centred 4 px below the header top, UI.headerTab() tall, 3 px edge) rises
-- above the header
local function tabOverhang(): number
	return UI.headerTab() / 2 - 4 + 3
end
function UI.modal(name: string, title: string, size: Vector2, opts: ModalOpts?): (Frame, any, () -> (), Frame?)
	UI.closeDialog()
	if current then
		current.Close()
	end
	local o: ModalOpts = opts or {}
	local root = UI.overlay()
	local shade = shadeButton(root, "Modal_" .. name, 0.5)
	-- upright phones: the panel spans the width, so it starts under Roblox's top bar buttons (menu, chat) and keeps
	-- 16 px from the bottom edge
	local ok, tl = pcall(function()
		return (GuiService:GetGuiInset())
	end)
	local insetY = if ok and typeof(tl) == "Vector2" then tl.Y else 0
	local topGap = 0
	if UI.isPortrait() then
		topGap = math.max(insetY / math.max(UI.Scale, 0.1), 44) + 30 -- + room for the gold title tab that sits half above the panel
	end
	if topGap == 0 and (UI.Logical.X - size.X) / 2 < MODAL_TOPLEFT_CLEAR then
		-- a narrow landscape phone: the panel's left edge (and the gold title tab that sticks out above it) sits under
		-- Roblox's menu and chat buttons at the top left, so the panel starts lower
		topGap = MODAL_TAB_DROP
	end
	local panel = UI.frame(shade, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, topGap / 2),
		Size = UDim2.new(1, -24, 1, if topGap > 0 then -(topGap + 16) else -12),
		BackgroundColor3 = TC.Panel,
		Active = true,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = size
	limit.Parent = panel
	UI.corner(panel, T.RadiusLg)
	UI.stroke(panel, if Theme.PetStyle then TC.PanelRim else TC.PanelEdge, if Theme.PetStyle then 3 else TS.Border)
	UI.panelShade(panel)
	if Theme.PetStyle then
		UI.pattern(panel, PET.PanelPattern, 0.3, 46, size.X, size.Y, 160)
	end
	panel:SetAttribute("KitHeaderOnRim", true)
	UI.kitPanel(panel, "panel_large") -- the kit panel picture (drawn panel while its id is 0)
	-- every header stays inside the safe area (Studio check 2026-10-14: titles were clipped under the Roblox top bar on
	-- a 1434 x 658 window): the gap above the panel covers the GuiInset when this layer ignores it, plus whatever the
	-- header's title tab sticks out above the content rect's top edge
	local kitL, kitTop, kitR, kitB = UI.kitInset(panel)
	-- the content rect keeps the size the panel asked for where the screen has room: the rim comes on top
	limit.MaxSize = size + Vector2.new(kitL + kitR, kitTop + kitB)
	-- (the panel's top sits at least `edge` below the gap: Size leaves 2 * edge and the panel is centred under it)
	local edge = if UI.compactMenus() then 4 else 8
	local safe = UiKit.safeTop(insetY, root.IgnoreGuiInset, UI.Scale, tabOverhang() - kitTop - edge, UiKit.SafeTopMargin)
	if safe > topGap then
		topGap = safe
	end
	if topGap > 0 then
		panel.Position = UDim2.new(0.5, 0, 0.5, topGap / 2)
		panel.Size = UDim2.new(1, -24, 1, -(topGap + 2 * edge))
	end
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		Audio.play("UIWhooshSoft", { Pitch = 0.9, Volume = 0.8, Key = "ui:menuclose" })
		if current and current.Name == name then
			current = nil
		end
		UI.closeDialog()
		UI.block("modal", false)
		clearSelectionIn(shade)
		shrinkAway(shade, panel)
		setBlur(false)
		UI.ModalChanged:Fire(nil)
		fitNotices()
	end
	local _, setCash = header(panel, title, o :: any, close)
	local headerH = headerHeight()
	if o.Subtitle then
		UI.text(panel, o.Subtitle, {
			Name = "Subtitle", Font = UI.Bold, TextSize = T.Body + 1, Outline = "Normal", Position = UDim2.fromOffset(16, headerH - 6), Size = UDim2.new(1, -32, 0, 24),
			TextXAlignment = if o.Center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		})
		headerH += 22
	end
	local footerH = o.Footer or 0
	local body: GuiObject
	if o.Fixed then
		body = UI.frame(panel, { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, headerH), Size = UDim2.new(1, 0, 1, -(headerH + footerH)) })
	else
		body = UI.scroller(panel, { Name = "Body", Position = UDim2.fromOffset(0, headerH), Size = UDim2.new(1, 0, 1, -(headerH + footerH)) })
	end
	local bodyPad = UI.pad(body, T.Pad, 6)
	if body:IsA("ScrollingFrame") then
		-- a scroll bar gap: rows stopped right against the bar (Daily list, Studio check 2026-10-14)
		bodyPad.PaddingRight = UDim.new(0, T.Pad + UI.ScrollBar)
	end
	local footer: Frame? = nil
	if footerH > 0 then
		footer = UI.frame(panel, { Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, footerH), BackgroundTransparency = 1 })
		UI.pad(footer :: Frame, T.Pad, 8)
	end
	shade.Activated:Connect(function()
		if o.Dismissable ~= false then
			close()
		end
	end)
	if not UI.Reduced then
		-- springs in with a small overshoot (Theme.Spring.Panel)
		local s = Instance.new("UIScale")
		s.Name = "Enter"
		s.Scale = Theme.Spring.PanelFrom
		s.Parent = panel
		UI.spring(s, Theme.Spring.Panel, { Scale = 1 })
	end
	setBlur(true)
	Audio.play("UIWhooshSoft", { Volume = 0.8, Key = "ui:menuopen" })
	gamepadFocus(panel, function()
		return not closed and shade.Parent ~= nil
	end)
	current = { Close = close, Name = name, SetCash = setCash, Panel = panel, HeaderH = headerH }
	UI.block("modal", true)
	UI.ModalChanged:Fire(name)
	fitNotices()
	return panel, body, close, footer
end

-- Updates the cash readout of the open menu (when it has one).
function UI.modalCash(n: number)
	if current and current.SetCash then
		current.SetCash(n)
	end
end

-- The open menu's coin readout (where flying coins land while a menu with a cash header is open), or nil.
function UI.modalCashTarget(): GuiObject?
	local head = if current then current.Panel:FindFirstChild("Header") else nil
	local cash = if head then head:FindFirstChild("Cash") else nil
	if cash and cash:IsA("GuiObject") and cash.Visible and cash.AbsoluteSize.X > 0 then
		return cash
	end
	return nil
end

-- The open menu's coin readout flashes red and wiggles (tapped something you can't afford yet).
function UI.flashCash()
	local head = if current then current.Panel:FindFirstChild("Header") else nil
	local cash = if head then head:FindFirstChild("Cash") else nil
	local amt = if cash then cash:FindFirstChild("Amount", true) else nil
	if not (cash and cash:IsA("GuiObject") and amt and amt:IsA("TextLabel")) then
		return
	end
	local was = amt:GetAttribute("BaseColor")
	if typeof(was) ~= "Color3" then
		was = amt.TextColor3
		amt:SetAttribute("BaseColor", was)
	end
	amt.TextColor3 = TC.Red
	TweenService:Create(amt, TweenInfo.new(0.6), { TextColor3 = was :: Color3 }):Play()
	if not UI.Reduced then
		cash.Rotation = 6
		TweenService:Create(cash, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end
end

function UI.closeModal()
	if current then
		current.Close()
	end
end

function UI.modalOpen(): string?
	return if current then current.Name else nil
end

-- A modal panel sized to its content: changes the cap of the panel's size constraint (the panel still shrinks to
-- fit small screens). Used by panels whose views differ a lot in size.
function UI.fitModal(panel: Instance, size: Vector2)
	local lim = panel:FindFirstChildOfClass("UISizeConstraint")
	if lim then
		local l, t, r, b = UI.kitInset(panel)
		lim.MaxSize = size + Vector2.new(l + r, t + b) -- the size is the content rect's; the kit rim comes on top
	end
	fitNotices()
end

-- Confirmation dialogs -------------------------------------------------------------------------------------
-- Stacked above the current menu (its own layer and block key): the menu keeps its state, closing the dialog
-- returns to it. Nothing runs until CONFIRM is activated.
-- opts = { Name, Title, Message, Icon (kind) | Picture (fn(container)), Price (number, shows the cash line),
--          Confirm = "CONFIRM", Cancel = "CANCEL", Style = "gold" | "red", OnConfirm, OnCancel, NoCancel,
--          Sticky (a tap outside or Escape does not close it; only its buttons do) }
local dialog: { Close: () -> (), Cancel: () -> (), Name: string, Panel: Frame, Sticky: boolean? }? = nil

function UI.closeDialog()
	if dialog then
		dialog.Close()
	end
end

function UI.dialogOpen(): string?
	return if dialog then dialog.Name else nil
end

-- What gamepad B / Escape closes: the dialog first, then the menu. On a dialog it is the same as CANCEL or a tap
-- outside: OnCancel runs (a party invite closed with Escape is declined, not left pending; audit 18).
-- UI.closeDialog stays silent (code closing a card it replaces).
function UI.closeTop()
	if dialog and dialog.Sticky then
		return
	end
	if dialog then
		dialog.Cancel()
	elseif current then
		current.Close()
	end
end

function UI.topOpen(): string?
	return if dialog then dialog.Name elseif current then current.Name else nil
end

-- Restylers PanelSkin installs at load (UI cannot require it: PanelSkin requires UI). nil = the plain look.
UI.DialogDress = nil :: ((panel: Frame) -> ())?
UI.NoticeDress = nil :: ((card: Frame, kind: string) -> ())?

function UI.confirm(opts: { [string]: any }): () -> ()
	UI.closeDialog()
	local name = opts.Name or "Confirm"
	local root = UI.dialogLayer()
	local shade = shadeButton(root, "Dialog_" .. name, 0.45)
	shade.Active = not opts.Sticky -- a Sticky dialog ignores taps outside it (an inactive button never fires Activated)
	local w = 420 -- the cap; below it the dialog is (screen - 24) wide
	local hasPic = opts.Icon ~= nil or opts.Picture ~= nil
	-- the message box grows with its text (2 to 5 lines) instead of the fitter shrinking long text to a tiny size
	local msgH = 0
	if type(opts.Message) == "string" then
		local _, breaks = string.gsub(opts.Message, "\n", "")
		msgH = math.clamp(math.max(breaks + 1, math.ceil(#opts.Message / 34)) * 22, 44, 110)
	end
	local inputH = if opts.Input then 48 else 0
	local priceH = if opts.Price then 30 else 0
	local h = 56 + msgH + priceH + inputH + 64
	local panel = UI.frame(shade, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 0, h), BackgroundColor3 = TC.Panel, Active = true,
	})
	local dlim = Instance.new("UISizeConstraint")
	dlim.MaxSize = Vector2.new(w, h)
	dlim.Parent = panel
	UI.corner(panel, T.RadiusLg)
	UI.stroke(panel, TC.PanelEdge, TS.Border)
	UI.panelShade(panel)
	UI.kitPanel(panel, "panel_small") -- the kit dialog picture (drawn panel while its id is 0)
	do
		-- the content sits inside the kit rim (KitPad): the dialog grows by the rim so its rows keep their room
		local _, kt, _, kb = UI.kitInset(panel)
		if kt + kb > 0 then
			panel.Size = UDim2.new(1, -24, 0, h + kt + kb)
			dlim.MaxSize = Vector2.new(w, h + kt + kb)
		end
	end
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if dialog and dialog.Name == name then
			dialog = nil
		end
		clearSelectionIn(shade)
		shrinkAway(shade, panel)
		UI.block("dialog", false)
		fitNotices()
	end
	local left = 16
	if hasPic then
		local pic = UI.frame(panel, { Name = "Picture", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(64, 64) })
		if opts.Picture then
			opts.Picture(pic)
		else
			UI.icon(pic, opts.Icon, 54, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		end
		left = 84
	end
	local t = UI.text(panel, opts.Title or "Are you sure?", { Name = "Title", Font = UI.Head, TextSize = T.Head + 2, Position = UDim2.fromOffset(left, 10), Size = UDim2.new(1, -(left + TS.Close + 18), 0, 36) })
	t.TextWrapped = false
	if not opts.Sticky then -- a Sticky card has one way out (its own buttons), so no red X next to LEAVE
		UI.closeButton(panel, function()
			close()
			if opts.OnCancel then
				opts.OnCancel()
			end
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8) })
	end
	local y = 50
	if opts.Message then
		UI.text(panel, opts.Message, { Name = "Message", Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Muted, Outline = "Light", Position = UDim2.fromOffset(left, y), Size = UDim2.new(1, -(left + 14), 0, msgH), TextYAlignment = Enum.TextYAlignment.Top })
		y += msgH
	end
	if opts.Price then
		local _, set = UI.cash(panel, 22, { Name = "Price", Position = UDim2.fromOffset(left, y + 2), Size = UDim2.fromOffset(170, 24) })
		set(opts.Price)
		y += priceH
	end
	-- opts.Input = { Text, Placeholder, MaxLength }: one text box; OnConfirm receives what was typed
	local box: TextBox? = nil
	if opts.Input then
		local inp = opts.Input
		local tb = Instance.new("TextBox")
		tb.Name = "Input"
		tb.Text = tostring(inp.Text or "")
		tb.PlaceholderText = tostring(inp.Placeholder or "")
		tb.PlaceholderColor3 = TC.Faint
		tb.ClearTextOnFocus = false
		tb.TextColor3 = TC.Text
		tb.Font = UI.Bold
		tb.TextSize = T.Body
		tb.TextXAlignment = Enum.TextXAlignment.Left
		tb.BackgroundColor3 = TC.Inset
		tb.BorderSizePixel = 0
		tb.Position = UDim2.fromOffset(left, y + 4)
		tb.Size = UDim2.new(1, -(left + 14), 0, 40)
		tb.Parent = panel
		UI.corner(tb, T.RadiusSm)
		UI.stroke(tb, TC.InsetEdge, 1.5)
		UI.pad(tb, 10, 0)
		local maxLen = tonumber(inp.MaxLength)
		if maxLen then
			tb:GetPropertyChangedSignal("Text"):Connect(function()
				local n = utf8.len(tb.Text)
				if n and n > maxLen then
					tb.Text = string.sub(tb.Text, 1, (utf8.offset(tb.Text, maxLen + 1) or (#tb.Text + 1)) - 1)
				end
			end)
		end
		box = tb
		y += inputH
	end
	local row = UI.frame(panel, { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 46) })
	UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local cb = UI.button(row, opts.Confirm or "CONFIRM", opts.Style or "gold", function()
		local typed = if box then box.Text else nil
		close()
		if opts.OnConfirm then
			opts.OnConfirm(typed)
		end
	end, { Name = "Confirm", Size = UDim2.new(if opts.NoCancel then 1 else 0.5, -5, 1, 0), LayoutOrder = 1 })
	local _ = cb
	if not opts.NoCancel then
		UI.button(row, opts.Cancel or "CANCEL", "gray", function()
			close()
			if opts.OnCancel then
				opts.OnCancel()
			end
		end, { Name = "Cancel", Size = UDim2.new(0.5, -5, 1, 0), LayoutOrder = 2 })
	end
	local function cancel()
		if closed then
			return
		end
		close()
		if opts.OnCancel then
			opts.OnCancel()
		end
	end
	shade.Activated:Connect(cancel)
	if UI.DialogDress then
		UI.DialogDress(panel)
	end
	if not UI.Reduced then
		local s = Instance.new("UIScale")
		s.Name = "Enter"
		s.Scale = Theme.Spring.PanelFrom
		s.Parent = panel
		UI.spring(s, Theme.Spring.Panel, { Scale = 1 })
	end
	gamepadFocus(panel, function()
		return not closed
	end)
	dialog = { Close = close, Cancel = cancel, Name = name, Panel = panel, Sticky = opts.Sticky }
	UI.block("dialog", true)
	fitNotices()
	return close
end

-- Notifications -------------------------------------------------------------------------------------
-- Compact cards at the top centre, above every menu. Coalesced: the same text (or the same `Tag`) refreshes the
-- card already showing instead of stacking another; at most three at a time (the oldest leaves first).
-- kinds: info | ok | warn | cash | geode | material. opts = { Tag, Long (stay longer), Title }
-- Owner picture for the "ok" toast tick (HudArt sets it from the CheckGreen slot once uploaded); nil = drawn tick.
UI.OkPicture = nil :: string?
UI.OkPictureReady = false -- HudArt sets it once the tick picture has been fetched (the toast then shows it at once)

-- success toasts ("Bought!", "Equipped!") are a short confirmation: gone after about 3.5 s with the slide out
local OK_HOLD = 3.2

local KIND_ICON = { ok = "check", warn = "warn", cash = "cash", geode = "egg", material = "egg", basket = "basket", info = nil }
local noticeHolder: Frame? = nil
local noticeSeq = 0

local function holder(): Frame
	if noticeHolder and noticeHolder.Parent then
		return noticeHolder :: Frame
	end
	local root = UI.noticeLayer()
	local f = UI.frame(root, { Name = "Notices", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(320, 600) -- small: a phone toast must not cover the player and their name tag
	lim.Parent = f
	UI.list(f, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	noticeHolder = f
	local function refit()
		task.defer(fitNotices)
	end
	f.ChildAdded:Connect(refit)
	f.ChildRemoved:Connect(refit)
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	fitNotices()
	return f
end

-- Moves the notification column (the HUD keeps it under its top bar).
-- `left` / `right` (optional) keep the column between the HUD's side columns (portrait phones).
local noticeBase = { Y = 64, L = 12, R = 12 }
UI.MaxNotices = 3

function UI.placeNotices(y: number, left: number?, right: number?)
	noticeBase = { Y = y, L = left or 12, R = right or 12 }
	fitNotices()
end

-- Logical rectangle (top, height, width) of a centred panel whose size is min(available, its size constraint).
local function panelRect(panel: Frame): (number, number, number)
	local lim = panel:FindFirstChildOfClass("UISizeConstraint")
	local maxS = if lim then lim.MaxSize else Vector2.new(math.huge, math.huge)
	local sz = panel.Size
	local w = math.min(UI.Logical.X * sz.X.Scale + sz.X.Offset, maxS.X)
	local hgt = math.min(UI.Logical.Y * sz.Y.Scale + sz.Y.Offset, maxS.Y)
	return (UI.Logical.Y - hgt) / 2, hgt, w
end

-- Height of the notification column in logical units (cards wrap, so measure when the layout has run).
local function noticeHeight(h: Frame): number
	local n = 0
	for _, c in h:GetChildren() do
		if c:IsA("Frame") then
			n += 1
		end
	end
	if n == 0 then
		return 0
	end
	local sc = h:FindFirstAncestorOfClass("ScreenGui")
	local ui = sc and sc:FindFirstChildOfClass("UIScale")
	local measured = if ui and ui.Scale > 0 then h.AbsoluteSize.Y / ui.Scale else 0
	return math.max(measured, n * 52 - 6)
end

-- Notices never cover an open menu's header (title, cash, X) or a confirmation dialog. Wide screens (PC,
-- tablets) with room beside the menu put the column there, level with the menu top. Otherwise candidate tops, in
-- order: the HUD's own spot (no menu open), the top edge, just under the menu header, just under the dialog;
-- the first one whose column misses every protected band wins. Short phones (the menu fills the height) get the
-- column under the header, over the top of the menu body, where it still has its own X and leaves on its own.
local SIDE_MIN = NoticeLayout.SideMin -- logical width beside a menu that takes the notification column

fitNotices = function()
	local h = noticeHolder
	if not h then
		return
	end
	local l, r = noticeBase.L, noticeBase.R
	local y = noticeBase.Y
	local bands: { { number } } = {}
	local starts: { number } = {}
	local width = math.huge
	if current and current.Panel.Parent then
		local top, _, w = panelRect(current.Panel)
		-- the header and the tab row under it (Pet Book: Book / Records / Stats) stay uncovered
		local head = current.HeaderH + T.Tab + T.Gap * 2
		table.insert(bands, { top - 4, top + head })
		table.insert(starts, 8)
		table.insert(starts, top + head + 4)
		width = w - 24
	end
	local side = 0
	local menuOpen = current ~= nil and current.Panel.Parent ~= nil
	local dialogOpen = dialog ~= nil and dialog.Panel.Parent ~= nil
	local mode = "hud"
	if current and menuOpen then
		local _, _, mw = panelRect(current.Panel)
		mode = NoticeLayout.mode(true, dialogOpen, (UI.Logical.X - mw) / 2)
	end
	if current and mode == "side" then
		local top, _, w = panelRect(current.Panel)
		local gap = (UI.Logical.X - w) / 2
		if gap >= SIDE_MIN then
			side = math.min(gap - 20, 380)
			h:SetAttribute("Top", top)
			h.AnchorPoint = Vector2.new(0, 0)
			-- (pet style: the red X sticks out of the sheet's top right corner, so the stack starts a little lower and
			-- further right)
			h.Position = UDim2.fromOffset((UI.Logical.X + w) / 2 + (if Theme.PetStyle then 22 else 10), top + (if Theme.PetStyle then 18 else 0))
			h.Size = UDim2.new(0, side, 0, 0)
			return
		end
	end
	if dialog and dialog.Panel.Parent then
		local top, hgt, w = panelRect(dialog.Panel)
		table.insert(bands, { top - 4, top + hgt + 4 })
		table.insert(starts, 8)
		table.insert(starts, top + hgt + 8)
		width = math.min(width, math.max(w, 300))
	end
	if current and mode == "corner" then
		-- a menu fills the screen: one narrow card in the top-right corner, just under the menu header
		local top = panelRect(current.Panel)
		local cw = math.min(260, UI.Logical.X - 24)
		h:SetAttribute("Top", top + current.HeaderH + 4)
		h.AnchorPoint = Vector2.new(1, 0)
		h.Position = UDim2.new(1, -12, 0, top + current.HeaderH + 4)
		h.Size = UDim2.new(0, cw, 0, 0)
		return
	end
	if #bands > 0 then
		local need = noticeHeight(h)
		local pick = starts[#starts]
		for _, s0 in starts do
			local clear = s0 + need <= UI.Logical.Y - 8
			for _, b in bands do
				if s0 < b[2] and s0 + need > b[1] then
					clear = false
				end
			end
			if clear then
				pick = s0
				break
			end
		end
		y = pick
		l, r = 12, 12
	end
	h:SetAttribute("Top", y)
	h.AnchorPoint = Vector2.new(0.5, 0)
	h.Position = UDim2.new(0.5, (l - r) / 2, 0, y)
	local wcap = math.min(UI.Logical.X - (l + r), width)
	h.Size = UDim2.new(0, math.max(wcap, 200), 0, 0)
end

local function noticeTag(text: string): string
	return string.lower(text)
end

-- While a fight is on screen (FightCam) toasts wait and show when it ends, so nothing covers the fight (Studio
-- 2026-10-15: "New in your Pet Book" toasts drew over the fight). opts.Fight = true shows one anyway.
local noticesHeld = false
type HeldNotice = { Text: string, Kind: string?, Opts: { [string]: any }?, Tag: string }
local heldNotices: { HeldNotice } = {}
local function noticesWait(): boolean
	return noticesHeld or not PopupGate.free("Toast") -- one rule for every popup (shared/PopupRules)
end
function UI.holdNotices(on: boolean)
	noticesHeld = on
	if not noticesWait() then
		local queue = heldNotices
		heldNotices = {}
		for _, n in queue do
			UI.notify(n.Text, n.Kind, n.Opts)
		end
	end
end

function UI.notify(text: string, kind: string?, opts: { [string]: any }?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local k = kind or "info"
	local o: { [string]: any } = opts or {}
	local tag = o.Tag or noticeTag(text)
	if o.Fight ~= true and noticesWait() then
		for i, n in heldNotices do
			if n.Tag == tag then
				table.remove(heldNotices, i) -- the newest of the same message wins
				break
			end
		end
		table.insert(heldNotices, { Text = text, Kind = kind, Opts = opts, Tag = tag })
		if #heldNotices > 5 then
			table.remove(heldNotices, 1)
		end
		return
	end
	local h = holder()
	UI.Notice:Fire(text, k)
	noticeSeq += 1
	local seq = noticeSeq
	local hold = if o.Long or k == "geode" then Theme.Motion.ToastHoldLong elseif k == "ok" then OK_HOLD else Theme.Motion.ToastHold
	for _, c in h:GetChildren() do
		if c:IsA("Frame") and c:GetAttribute("Tag") == tag then
			-- coalesce: same message again refreshes the card already on screen; the exact same text counts up (x2, x3)
			local label = c:FindFirstChild("Text", true) :: TextLabel?
			local n = if c:GetAttribute("Text") == text then (tonumber(c:GetAttribute("Count")) or 1) + 1 else 1
			c:SetAttribute("Text", text)
			c:SetAttribute("Count", n)
			if label then
				label.Text = if n > 1 then text .. "  x" .. n else text
			end
			c:SetAttribute("Seq", seq)
			c.LayoutOrder = seq
			task.delay(hold, function()
				if c.Parent and c:GetAttribute("Seq") == seq then
					c:Destroy()
				end
			end)
			return
		end
	end
	local icon = KIND_ICON[k]
	-- slot in the column (laid out by the list) holding the visible card, so the card can slide in from the side
	local slot = UI.frame(h, { Name = "Notice", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = seq, BackgroundTransparency = 1 })
	slot:SetAttribute("Tag", tag)
	slot:SetAttribute("Text", text)
	slot:SetAttribute("Kind", k)
	slot:SetAttribute("Seq", seq)
	-- the card is as wide as its words (up to the column width) and centred, so a short notice is one line with no
	-- empty space on its right
	local f = UI.card(slot, "panel", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 200, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local edge = f:FindFirstChild("Border") :: UIStroke?
	if edge and (k == "ok" or k == "geode") then
		edge.Color = TC.Green
		edge.Thickness = 2.5
	elseif edge and k == "warn" then
		edge.Color = TC.Red
		edge.Thickness = 2.5
	end
	local left = 10
	if icon then
		-- drawn icon first; the owner's tick picture sits on top of it and only hides it once the picture has loaded
		-- (a picture that never loads left an empty gap on the toast's left)
		local drawn = UI.icon(f, icon, 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0) })
		left = 38
		local pic = UI.OkPicture
		if k == "ok" and pic then
			local img = Instance.new("ImageLabel")
			img.Name = "Icon"
			img.BackgroundTransparency = 1
			img.Image = pic
			img.ScaleType = Enum.ScaleType.Fit
			img.AnchorPoint = Vector2.new(0, 0.5)
			img.Position = UDim2.new(0, 6, 0.5, 0)
			img.Size = UDim2.fromOffset(28, 28)
			-- already fetched (HudArt preloads it): the picture shows from the first frame, no drawn tick first
			-- kept Visible but see-through until loaded (Roblox does not fetch a hidden image)
			img.ImageTransparency = if UI.OkPictureReady then 0 else 1
			drawn.Visible = not UI.OkPictureReady
			img.Parent = f
			local function shown()
				if img.IsLoaded then
					img.ImageTransparency = 0
					drawn.Visible = false
				end
			end
			img:GetPropertyChangedSignal("IsLoaded"):Connect(shown)
			shown()
		end
	end
	local label = UI.text(f, text, { Name = "Text", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(left, 0), Size = UDim2.new(1, -(left + 38), 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	label.TextScaled = false
	label.TextSize = T.Small
	local fitC = label:FindFirstChild("Fit")
	if fitC then
		fitC:Destroy()
	end
	-- card width: the text's one-line width plus the icon and X room, capped at the column width (wraps past that)
	local side = left + 38
	local function sizeCard()
		local hw = h.Size.X.Offset
		local maxW = math.max(160, (if hw > 0 then math.min(hw, 320) else 320) - side)
		local need = TextService:GetTextSize(label.Text, T.Small, UI.Bold, Vector2.new(maxW, 1000))
		f.Size = UDim2.new(0, math.ceil(math.min(need.X + 4, maxW)) + side, 0, 0)
	end
	sizeCard()
	label:GetPropertyChangedSignal("Text"):Connect(sizeCard)
	UI.pad(f, 0, 6)
	if UI.NoticeDress then
		UI.NoticeDress(f, k)
	end
	local x = UI.closeButton(f, function()
		slot:Destroy()
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), Size = UDim2.fromOffset(28, 28) })
	local _ = x
	-- at most UI.MaxNotices (the HUD lowers it to two during a search): the oldest leaves first
	local cards = {}
	for _, c in h:GetChildren() do
		if c:IsA("Frame") then
			table.insert(cards, c)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	-- one at a time over an open menu (a 10-egg buy stacked its Pet Book notices over the shop)
	local max = NoticeLayout.maxCards(current ~= nil and current.Panel.Parent ~= nil, UI.MaxNotices)
	while #cards > max do
		local old = table.remove(cards, 1)
		if old then
			old:Destroy()
		end
	end
	if not UI.Reduced then
		-- slides in from the right edge with a small overshoot
		f.Position = UDim2.new(1.5, 40, 0, 0)
		TweenService:Create(f, TweenInfo.new(Theme.Motion.ToastSlide, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0) }):Play()
	end
	task.delay(hold, function()
		if slot.Parent and slot:GetAttribute("Seq") == seq then
			if UI.Reduced then
				slot:Destroy()
				return
			end
			-- slides back out the way it came
			local tw = TweenService:Create(f, TweenInfo.new(Theme.Motion.Toast, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1.5, 40, 0, 0) })
			tw.Completed:Connect(function()
				slot:Destroy()
			end)
			tw:Play()
		end
	end)
end

-- Removes notifications whose tag starts with `prefix` ("" = all).
function UI.dismissNotices(prefix: string)
	local h = noticeHolder
	if not h then
		return
	end
	for _, c in h:GetChildren() do
		local t = c:GetAttribute("Tag")
		if c:IsA("Frame") and type(t) == "string" and string.sub(t, 1, #prefix) == prefix then
			c:Destroy()
		end
	end
end

-- Texts of the notifications on screen (checks).
function UI.noticeTexts(): { string }
	local out = {}
	local h = noticeHolder
	if h then
		for _, c in h:GetChildren() do
			local l = c:FindFirstChild("Text", true)
			if l and l:IsA("TextLabel") then
				table.insert(out, l.Text)
			end
		end
	end
	return out
end

-- big cards come one at a time: a menu or another big card on screen keeps the next one waiting (shared/PopupRules)
PopupGate.onScreen = function(): boolean
	if current ~= nil then
		return true
	end
	local d = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local layerGui = d and d:FindFirstChild("CrackTheRocksDialog")
	if layerGui then
		for _, n in PopupRules.Cards do
			if layerGui:FindFirstChild(n) then
				return true
			end
		end
	end
	return false
end

-- held toasts show as soon as the popup gate frees (a fight or tower climb ended)
PopupGate.Changed.Event:Connect(function()
	if #heldNotices > 0 and not noticesWait() then
		UI.holdNotices(noticesHeld)
	end
end)

return UI
