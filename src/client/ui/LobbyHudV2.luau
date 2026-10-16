--!strict
-- Lobby HUD v2: carter's lobby screen (ChatGPT prototype + carter's painted buttons, 2026-10-15). LIVE: on for
-- everyone in the lobby (carter "put it in the game"); Workspace attribute LobbyHudV2 = false turns it off.
--   coin pill (real coins), FIND THE PET title, MY PETS / PET BOOK left, DAILY / SPIN / SHOP right,
--   TRAIN / PLAY / FIGHT bottom, and a queue line over PLAY while a hunt queue is counting.
-- Each button opens the same thing its old HUD button did (Main passes the actions in). While it shows, the old
-- lobby column and tile menu hide (Hud.setLobbyHidden) and come back in hunts, the tower and battles. It also hides
-- while a menu is open. carter asked for no Settings / Party / Upgrade / Gift buttons on this screen (2026-10-15).
-- Every piece is its own object so each can move on its own:
--   <Piece> (Frame, placed by shared/LobbyHudLayout)
--     Visual + UIScale "CosmeticScale"  <- entrance pop, press squash, hover grow
--       Art (carter's picture) [+ ShineClip/Shine on PLAY], or the drawn stand-in when an id is 0
--     Hit (TextButton, invisible)        <- input (never moves, so the tap target stays put)
-- Idle personality (shared/LobbyHudIdle): now and then one button does its own short move (Visual's Position / Size /
-- Rotation, so the press squash on CosmeticScale never fights it), with a light decoration of its own (stars, a glow
-- under TRAIN, an edge flash on FIGHT). DAILY only wiggles while a reward is claimable. A press or hover stops the
-- move at once; menus over the HUD pause it; Reduce Motion turns it off; Low Effects drops the decorations.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LobbyHudLayout = require(Shared.LobbyHudLayout)
local LobbyHudArt = require(Shared.LobbyHudArt)
local LobbyHudIdle = require(Shared.LobbyHudIdle)
local PopupRules = require(Shared.PopupRules)
local UI = require(script.Parent.UI)
local State = require(script.Parent.Parent.State)

local LobbyHudV2 = {}
LobbyHudV2.Motion = true -- one switch for every cosmetic tween (UI.Reduced also turns them off)
LobbyHudV2.Attr = "LobbyHudV2" -- Workspace attribute; false = off

export type Actions = {
	open: { [string]: () -> () }, -- piece name -> what a tap does
	status: () -> string?, -- the queue line over PLAY
	hideOld: (boolean) -> (), -- the old lobby HUD steps aside
	claimable: (() -> boolean)?, -- a daily reward is ready (DAILY's reminder wiggle)
}
local actions: Actions? = nil

local NAVY = Color3.fromHex("071747")
local CYAN = Color3.fromHex("25E8FF")
local BLUE = Color3.fromHex("009DFF")
local PURPLE = Color3.fromHex("8734F5")
local LIME_TOP = Color3.fromHex("B9FF16")
local LIME = Color3.fromHex("80FF32")
local ORANGE = Color3.fromHex("FFA008")
local YELLOW = Color3.fromHex("FFD72D")
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne

type Spec = { Label: string, Sub: string?, Icon: string, Fill: Color3, Top: Color3 }
local SPECS: { [string]: Spec } = {
	MyPets = { Label = "MY PETS", Icon = "\u{1F43E}", Fill = BLUE, Top = Color3.fromHex("4FC3FF") },
	PetBook = { Label = "PET BOOK", Icon = "\u{1F4D6}", Fill = PURPLE, Top = Color3.fromHex("B07BFF") },
	Daily = { Label = "DAILY", Icon = "\u{1F381}", Fill = BLUE, Top = Color3.fromHex("4FC3FF") },
	Spin = { Label = "SPIN", Icon = "\u{1F3A1}", Fill = BLUE, Top = Color3.fromHex("4FC3FF") },
	Shop = { Label = "SHOP", Icon = "\u{1F6CD}", Fill = BLUE, Top = Color3.fromHex("4FC3FF") },
	Train = { Label = "TRAIN", Icon = "\u{1F3F0}", Fill = Color3.fromHex("1EC8F0"), Top = Color3.fromHex("6BE6FF") },
	Play = { Label = "PLAY", Sub = "3-MIN HUNT", Icon = "\u{1F95A}", Fill = LIME, Top = LIME_TOP },
	Fight = { Label = "FIGHT", Icon = "\u{2694}", Fill = ORANGE, Top = Color3.fromHex("FFC44D") },
}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local pieces: { [string]: Frame } = {}
local scales: { [string]: UIScale } = {}
local visuals: { [string]: Frame } = {}
local arts: { [string]: ImageLabel } = {}
local shown = false
local stepped: { [ScreenGui]: boolean } = {}

local function settings(): { [string]: any }
	local prof: any = State.Profile
	return (prof and type(prof.Settings) == "table" and prof.Settings) or {}
end

local function motion(): boolean
	return LobbyHudV2.Motion and not UI.Reduced and settings().ReducedMotion ~= true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function stroke(p: Instance, color: Color3, thick: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end

local function frame(parent: Instance, name: string, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

-- fitted text: scaled to its box with a floor and a ceiling, navy outline
local function words(parent: Instance, name: string, text: string, props: { [string]: any }, min: number, max: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = WHITE
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = min
	c.MaxTextSize = max
	c.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = NAVY
	s.Thickness = 2.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = l
	l.Parent = parent
	return l
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Idle personality ---------------------------------------------------------------------------------------------
local busy: { [string]: boolean? } = {} -- held down or hovered: no idle move
local token: { [string]: number } = {}
local running: { [string]: Tween } = {}
local decor: { [string]: { Instance } } = {}

local REST_POS = UDim2.fromScale(0.5, 0.5)
local REST_SIZE = UDim2.fromScale(1, 1)

local function atRest(name: string)
	local v = visuals[name]
	if v then
		v.Position, v.Size, v.Rotation = REST_POS, REST_SIZE, 0
	end
	local art = arts[name]
	if art then
		art.ScaleType = Enum.ScaleType.Fit
	end
end

local function clearDecor(name: string)
	local list = decor[name]
	decor[name] = nil
	if list then
		for _, d in list do
			d:Destroy()
		end
	end
end

-- stop a button's move now and put it back at rest (press feedback wins over idle; menus pause it)
local function idleStop(name: string)
	token[name] = (token[name] or 0) + 1
	local tw = running[name]
	if tw then
		tw:Cancel()
		running[name] = nil
	end
	atRest(name)
	clearDecor(name)
end

local function idleStopAll()
	for name in visuals do
		if running[name] or decor[name] then
			idleStop(name)
		end
	end
end

local function keep(name: string, obj: Instance)
	local list = decor[name] or {}
	table.insert(list, obj)
	decor[name] = list
end

local function fade(obj: Instance, t: number, delay: number, props: { [string]: any })
	task.delay(delay, function()
		if obj.Parent then
			TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
		end
	end)
end

-- tiny separate stars that pop and fade round the button's edges
local function stars(name: string, holder: Frame)
	local spots = (LobbyHudIdle.StarSpots :: any)[name] or {}
	local big = if name == "Play" then 0.3 else 0.2
	for i, spot in spots do
		local star = Instance.new("TextLabel")
		star.Name = "IdleStar"
		star.BackgroundTransparency = 1
		star.Font = FONT
		star.Text = "\u{2605}"
		star.TextScaled = true
		star.TextColor3 = if i % 2 == 0 then WHITE else Color3.fromHex("FFE14D")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(spot.x, spot.y)
		star.SizeConstraint = Enum.SizeConstraint.RelativeYY
		star.Size = UDim2.fromScale(0, 0)
		star.ZIndex = 6
		local edge = Instance.new("UIStroke")
		edge.Color = NAVY
		edge.Thickness = 1.5
		edge.Parent = star
		star.Parent = holder
		keep(name, star)
		local wait = (i - 1) * 0.06
		task.delay(wait, function()
			if star.Parent then
				TweenService:Create(star, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(big, big), Rotation = 30 }):Play()
			end
		end)
		fade(star, 0.25, wait + 0.24, { TextTransparency = 1, Rotation = 60 })
		fade(edge, 0.25, wait + 0.24, { Transparency = 1 })
	end
end

-- a soft cyan glow under the button (behind the picture)
local function glow(name: string, holder: Frame)
	local g = frame(holder, "IdleGlow", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.96), Size = UDim2.fromScale(0.6, 0.16), BackgroundColor3 = CYAN, BackgroundTransparency = 1, ZIndex = 0 })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = g
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = g
	keep(name, g)
	fade(g, 0.16, 0, { BackgroundTransparency = 0.15, Size = UDim2.fromScale(0.9, 0.24) })
	fade(g, 0.35, 0.3, { BackgroundTransparency = 1, Size = UDim2.fromScale(0.7, 0.18) })
end

-- a quick white flash round the button's edge (tilts with the picture)
local function flash(name: string, visual: Frame)
	local f = frame(visual, "IdleFlash", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.97, 0.9), ZIndex = 3 })
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.22, 0)
	c.Parent = f
	local edge = stroke(f, WHITE, 4)
	edge.Transparency = 1
	keep(name, f)
	fade(edge, 0.05, 0, { Transparency = 0.05 })
	fade(edge, 0.25, 0.08, { Transparency = 1 })
end

local STYLE: { [string]: Enum.EasingStyle } = { Quad = Enum.EasingStyle.Quad, Sine = Enum.EasingStyle.Sine, Back = Enum.EasingStyle.Back }

-- play one button's move (returns when it ends or is stopped)
local function idlePlay(name: string)
	local move = LobbyHudIdle.Moves[name]
	local v, holder = visuals[name], pieces[name]
	if not move or not v or not holder then
		return
	end
	idleStop(name)
	local my = token[name]
	local art = arts[name]
	if move.Stretch and art then
		art.ScaleType = Enum.ScaleType.Stretch -- the picture box keeps the picture's own shape at rest, so squash reads
	end
	if move.Fx and not lowFx() then
		task.delay(move.FxAt or 0, function()
			if token[name] ~= my then
				return
			end
			if move.Fx == "Stars" or move.Fx == "Burst" then
				stars(name, holder)
			elseif move.Fx == "Glow" then
				glow(name, holder)
			elseif move.Fx == "Flash" then
				flash(name, v)
			end
		end)
	end
	for _, s in move.Steps do
		local dir = if s.dir == "In" then Enum.EasingDirection.In else Enum.EasingDirection.Out
		local tw = TweenService:Create(v, TweenInfo.new(s.d, STYLE[s.style or "Quad"] or Enum.EasingStyle.Quad, dir), {
			Position = UDim2.fromScale(0.5 + (s.x or 0), 0.5 + (s.y or 0)),
			Size = UDim2.fromScale(s.sx or 1, s.sy or 1),
			Rotation = s.rot or 0,
		})
		running[name] = tw
		tw:Play()
		task.wait(s.d)
		if token[name] ~= my then
			return
		end
	end
	running[name] = nil
	atRest(name)
	task.delay(0.6, function()
		if token[name] == my then
			clearDecor(name)
		end
	end)
end

-- one button at a time, a few quiet seconds between moments, only while the HUD shows and motion is on
local function idleLoop()
	task.spawn(function()
		local lastAt: { [string]: number } = {}
		local last: string? = nil
		local wait = LobbyHudIdle.FirstWait
		while gui and gui.Parent do
			task.wait(wait)
			wait = 0.5
			if shown and motion() then
				local a = actions
				local claim = a ~= nil and a.claimable ~= nil and a.claimable()
				local now = os.clock()
				local name = LobbyHudIdle.pick(now, lastAt, last, claim, math.random(), busy)
				if name then
					lastAt[name], last = now, name
					idlePlay(name)
					wait = LobbyHudIdle.gap(math.random())
				end
			end
		end
	end)
end

-- press / hover feedback on one piece (never stacks: every tween sets an absolute target)
local function hook(name: string, hit: TextButton, sc: UIScale)
	local hover, down = false, false
	local function mark()
		busy[name] = (hover or down) or nil
		if hover or down then
			idleStop(name) -- press feedback wins: the idle move snaps home first
		end
	end
	local function rest(): number
		return if down then 0.96 elseif hover then 1.04 else 1
	end
	local function go(t: number, style: Enum.EasingStyle?)
		mark()
		if motion() then
			tween(sc, t, { Scale = rest() }, style)
		else
			sc.Scale = 1
		end
	end
	hit.MouseEnter:Connect(function()
		hover = true
		go(0.12)
	end)
	hit.MouseLeave:Connect(function()
		hover, down = false, false
		go(0.12)
	end)
	hit.MouseButton1Down:Connect(function()
		down = true
		go(0.06)
	end)
	local function up()
		if down then
			down = false
			go(0.14, Enum.EasingStyle.Back)
		end
	end
	hit.MouseButton1Up:Connect(up)
	hit.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			up()
		end
	end)
	hit.Activated:Connect(function()
		local a = actions
		local fn = a and a.open[name]
		if fn then
			fn()
		end
	end)
end

local function hitBox(holder: Frame, name: string, sc: UIScale)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	hit.AutoButtonColor = false
	hit.Parent = holder
	hook(name, hit, sc)
end

-- carter's painted button: the whole picture (label, icon, rim, shadow baked in) moves as one; PLAY gets a light
-- sweep clipped to its face
local function picture(holder: Frame, visual: Frame, name: string, image: string)
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = image
	art.ScaleType = Enum.ScaleType.Fit
	art.Size = UDim2.fromScale(1, 1)
	art.Parent = visual
	arts[name] = art
	if name == "Play" then
		local face = frame(visual, "ShineClip", { Position = UDim2.fromScale(0.04, 0.08), Size = UDim2.fromScale(0.92, 0.74), ClipsDescendants = true, ZIndex = 2 })
		corner(face, 18)
		frame(face, "Shine", { Size = UDim2.new(0.12, 0, 1.6, 0), Position = UDim2.new(-0.3, 0, -0.3, 0), Rotation = 20, BackgroundColor3 = WHITE, BackgroundTransparency = 0.65 })
	end
	local _ = holder
end

-- one chunky button: carter's picture when its id is set, else the drawn stand-in (shadow, body with gradient,
-- navy outline, cyan rim, gloss, icon, label (+ sub))
local function button(root: Instance, name: string, spec: Spec): Frame
	local holder = frame(root, name, {})
	local visual = frame(holder, "Visual", { AnchorPoint = Vector2.new(0.5, 0.5), Position = REST_POS, Size = REST_SIZE })
	visuals[name] = visual
	local sc = Instance.new("UIScale")
	sc.Name = "CosmeticScale"
	sc.Parent = visual
	scales[name] = sc
	local image = LobbyHudArt.image(name)
	if image then
		picture(holder, visual, name, image)
		hitBox(holder, name, sc)
		return holder
	end
	local big = name == "Play"
	local r = if big then 22 else 16
	local shadow = frame(visual, "Shadow", { Size = UDim2.new(1, 0, 1, 0), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = NAVY, BackgroundTransparency = 0 })
	corner(shadow, r)
	local body = frame(visual, "Body", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, ClipsDescendants = true })
	corner(body, r)
	stroke(body, NAVY, 3.5)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(spec.Top, spec.Fill)
	g.Rotation = 90
	g.Parent = body
	local rim = frame(body, "Rim", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3) })
	corner(rim, r - 3)
	stroke(rim, CYAN, 2).Transparency = if big then 0.35 else 0.1
	local gloss = frame(body, "Gloss", { Size = UDim2.new(1, -16, 0.36, 0), Position = UDim2.fromOffset(8, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.72 })
	corner(gloss, r - 6)
	if big then
		local shine = frame(body, "Shine", { Size = UDim2.new(0.18, 0, 1.6, 0), Position = UDim2.new(-0.3, 0, -0.3, 0), Rotation = 20, BackgroundColor3 = WHITE, BackgroundTransparency = 0.6 })
		local _ = shine
		words(visual, "Icon", spec.Icon, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.06, 0, 0.5, 0), Size = UDim2.new(0.2, 0, 0.72, 0), TextStrokeTransparency = 1 }, 14, 64)
		words(visual, "Label", spec.Label, { Position = UDim2.new(0.28, 0, 0.06, 0), Size = UDim2.new(0.68, 0, 0.6, 0) }, 18, 72)
		local sub = words(visual, "Sub", spec.Sub or "", { Position = UDim2.new(0.28, 0, 0.64, 0), Size = UDim2.new(0.68, 0, 0.26, 0), TextColor3 = Color3.fromHex("0F6B1E") }, 10, 26)
		local subEdge = sub:FindFirstChildOfClass("UIStroke")
		if subEdge then
			subEdge.Color = WHITE
		end
	else
		words(visual, "Icon", spec.Icon, { Position = UDim2.new(0.1, 0, 0.06, 0), Size = UDim2.new(0.8, 0, 0.56, 0) }, 12, 56)
		words(visual, "Label", spec.Label, { Position = UDim2.new(0.04, 0, 0.62, 0), Size = UDim2.new(0.92, 0, 0.32, 0) }, 11, 30)
	end
	hitBox(holder, name, sc)
	return holder
end

local function coins(root: Instance): Frame
	local holder = frame(root, "Coins", {})
	local visual = frame(holder, "Visual", { Size = UDim2.fromScale(1, 1) })
	local sc = Instance.new("UIScale")
	sc.Name = "CosmeticScale"
	sc.Parent = visual
	scales.Coins = sc
	local shadow = frame(visual, "Shadow", { Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = NAVY, BackgroundTransparency = 0 })
	corner(shadow, 999)
	local body = frame(visual, "Body", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("10245E"), BackgroundTransparency = 0 })
	corner(body, 999)
	stroke(body, CYAN, 3)
	local coin = frame(visual, "CoinIcon", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.new(1, 0, 1, 6), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = YELLOW, BackgroundTransparency = 0 })
	corner(coin, 999)
	stroke(coin, NAVY, 3)
	words(coin, "Paw", "\u{1F43E}", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), TextStrokeTransparency = 1 }, 8, 30)
	words(visual, "AmountLabel", "0", { Position = UDim2.new(0.34, 0, 0.12, 0), Size = UDim2.new(0.6, 0, 0.76, 0) }, 14, 36)
	return holder
end

local function title(root: Instance): Frame
	local holder = frame(root, "Title", {})
	local visual = frame(holder, "Visual", { Size = UDim2.fromScale(1, 1) })
	local sc = Instance.new("UIScale")
	sc.Name = "CosmeticScale"
	sc.Parent = visual
	scales.Title = sc
	local a = words(visual, "FindTheLabel", "FIND THE", { Position = UDim2.fromScale(0.12, 0), Size = UDim2.fromScale(0.76, 0.42) }, 12, 48)
	local b = words(visual, "PetLabel", "PET", { Position = UDim2.fromScale(0.2, 0.36), Size = UDim2.fromScale(0.6, 0.64), TextColor3 = YELLOW }, 16, 80)
	for _, l in { a, b } do
		(l:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 3.5
	end
	return holder
end

local function statusLine(root: Instance): Frame
	local holder = frame(root, "Status", { Visible = false })
	local body = frame(holder, "Body", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("10245E"), BackgroundTransparency = 0.1 })
	corner(body, 999)
	stroke(body, CYAN, 2)
	words(holder, "Text", "", { Position = UDim2.fromScale(0.04, 0.1), Size = UDim2.fromScale(0.92, 0.8) }, 10, 22)
	return holder
end

local function place()
	local sg = gui
	local root = sg and sg:FindFirstChild("SafeHUDRoot") :: Frame?
	local scale = root and root:FindFirstChild("Scale") :: UIScale?
	if not sg or not root or not scale then
		return
	end
	-- own fit from this layer's real size (UI.scaleFor rule), so the logical canvas always matches the screen
	local v = sg.AbsoluteSize
	if v.X < 2 or v.Y < 2 then
		local cam = Workspace.CurrentCamera
		v = if cam then cam.ViewportSize else Vector2.new(800, 400)
	end
	local k = UI.scaleFor(v)
	scale.Scale = k
	local w, h = v.X / k, v.Y / k
	root.Size = UDim2.fromOffset(w, h)
	local lay = LobbyHudLayout.layout(w, h, k, true)
	for name, r in lay do
		local p = pieces[name]
		if p then
			p.Position = UDim2.fromOffset(r.x, r.y)
			p.Size = UDim2.fromOffset(r.w, r.h)
		end
	end
end

-- a short entrance: each group rises a few px and fades in, a little after the last
local function entrance()
	if not motion() then
		return
	end
	local groups = { { "Coins", "Title" }, { "MyPets", "PetBook" }, { "Daily", "Spin", "Shop" }, { "Train", "Play", "Fight" } }
	for i, group in groups do
		for _, n in group do
			local sc = scales[n]
			if sc then
				sc.Scale = 0.85
				task.delay((i - 1) * 0.06, function()
					tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end)
			end
		end
	end
end

-- one sparing light sweep across PLAY now and then
local function shineLoop()
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(6)
			local play = pieces.Play
			local shine = play and play:FindFirstChild("Shine", true) :: Frame?
			if shown and shine and motion() then
				shine.Position = UDim2.new(-0.3, 0, -0.3, 0)
				tween(shine, 0.7, { Position = UDim2.new(1.2, 0, -0.3, 0) }, Enum.EasingStyle.Sine)
			end
		end
	end)
end

local function build()
	local sg = Instance.new("ScreenGui")
	sg.Name = "LobbyHudV2"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = false
	sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 6
	sg.Enabled = false
	-- the UIScale sits on the root frame (not the ScreenGui) so the root's logical canvas scales from its corner
	local root = frame(sg, "SafeHUDRoot", {})
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Scale = UI.Scale
	scale.Parent = root
	pieces.Coins = coins(root)
	pieces.Title = title(root)
	pieces.Status = statusLine(root)
	for name, spec in SPECS do
		pieces[name] = button(root, name, spec)
	end
	sg.Parent = player:WaitForChild("PlayerGui")
	gui = sg
	place()
	sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	shineLoop()
	idleLoop()
end

local function inLobby(): boolean
	return player:GetAttribute("MatchKey") == nil and player:GetAttribute("InTower") ~= true and player:GetAttribute("InBattle") ~= true
end

-- a big card (NEXT GOAL, away nest) is up: the HUD steps aside so the card never sits over PLAY (Studio 2026-10-15)
local function bigCard(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local layer = pg and pg:FindFirstChild("CrackTheRocksDialog")
	if layer then
		for _, n in PopupRules.Cards do
			if layer:FindFirstChild(n) then
				return true
			end
		end
	end
	return false
end

local lastLobby = false
local function refresh()
	local lobby = Workspace:GetAttribute(LobbyHudV2.Attr) ~= false and inLobby()
	local want = lobby and not UI.blocked() and not bigCard()
	if want and not gui then
		build()
	end
	local sg = gui
	if sg then
		sg.Enabled = want
	end
	local a = actions
	if a then
		a.hideOld(lobby)
	end
	-- the emote corner steps aside in the lobby (it sat on FIGHT); only what this module turned off comes back
	local pg = player:FindFirstChild("PlayerGui")
	local hang = pg and pg:FindFirstChild("CT_Hangout")
	if hang and hang:IsA("ScreenGui") then
		if lobby then
			if hang.Enabled then
				hang.Enabled = false
				stepped[hang] = true
			end
		elseif stepped[hang] then
			hang.Enabled = true
			stepped[hang] = nil
		end
	end
	if shown and not want then
		idleStopAll() -- a menu covers the HUD (or we left the lobby): everything back at rest
	end
	if want and not shown then
		place()
		if not lastLobby then
			entrance() -- the pop-in plays on arrival in the lobby, not after every menu closes
		end
	end
	shown = want
	lastLobby = lobby
end

-- coins and the queue line, a few times a second while showing
local function tick()
	local root = gui and gui:FindFirstChild("SafeHUDRoot")
	if not root or not shown then
		return
	end
	local prof: any = State.Profile
	local amount = root:FindFirstChild("AmountLabel", true) :: TextLabel?
	if amount and prof and type(prof.Cash) == "number" then
		local t = UI.num(prof.Cash)
		if amount.Text ~= t then
			amount.Text = t
		end
	end
	-- the old HUD's top-centre card (first-hunt hint, objective) keeps its place: the title steps aside for it
	local top = UI.screen():FindFirstChild("Top") :: GuiObject?
	local title = pieces.Title
	if title then
		title.Visible = not (top and top.Visible and top.AbsoluteSize.Y > 4)
	end
	local st = pieces.Status
	local a = actions
	local line = if a then a.status() else nil
	if st then
		st.Visible = line ~= nil
		local label = st:FindFirstChild("Text") :: TextLabel?
		if label and line and label.Text ~= line then
			label.Text = line
		end
	end
end

function LobbyHudV2.start(a: Actions)
	actions = a
	Workspace:GetAttributeChangedSignal(LobbyHudV2.Attr):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.25)
			refresh() -- menus opening / closing (UI.blocked) have no single signal
			tick()
		end
	end)
	for _, a in { "MatchKey", "InTower", "InBattle" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	refresh()
end

-- for the preview scene and tests
function LobbyHudV2.pieces(): { [string]: Frame }
	return pieces
end

-- play one button's idle move now (preview scene)
function LobbyHudV2.idle(name: string)
	task.spawn(idlePlay, name)
end

return LobbyHudV2
