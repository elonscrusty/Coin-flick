--!strict
-- FIND THE GEODE! UI v2 theme (docs/ui_v2/BRIEF_UI_V2.md, boards docs/ui_v2/*.png). Every colour, font, size,
-- border and radius of the interface lives here; UI.luau builds the components from these values only.
--
-- Look (docs/UI_STYLE.md, 2026-10-12): bright sky-blue gradient panels with a thick navy border and round corners; chunky white lettering with a black outline
-- (strong on headings and floating HUD text, light on supporting text); gold primary buttons with dark text, gray
-- secondary buttons, red close buttons with a white X; green cash; orange / gold counts and selected states.

local Theme = {}

-- Pet style (owner's reference clip 2026-10-15, docs/UI_STYLE_REF.md): white patterned sheets, navy tab strips with
-- a lime pill, lime / cyan / red buttons with white outlined Fredoka words, titles floating over the panel's edge.
-- Every colour measured on the clip lives in Theme.Pet (ui/PetStyle draws with them); the older sky-blue look is
-- what Theme.Color held before and comes back by setting PetStyle false (HudArt pictures and word art return too).
Theme.PetStyle = true
Theme.Pet = {
	TabBar = Color3.fromRGB(16, 46, 66),
	TabBarEdge = Color3.fromRGB(8, 22, 32),
	TabText = Color3.fromRGB(206, 220, 230),
	LimeTop = Color3.fromRGB(210, 254, 0),
	Lime = Color3.fromRGB(114, 254, 0),
	LimeHover = Color3.fromRGB(160, 255, 60),
	LimeEdge = Color3.fromRGB(46, 110, 0),
	RedTop = Color3.fromRGB(255, 90, 90),
	Red = Color3.fromRGB(240, 49, 49),
	RedEdge = Color3.fromRGB(122, 10, 18),
	Panel = Color3.fromRGB(255, 255, 255),
	PanelPattern = Color3.fromRGB(226, 238, 248),
	PanelEdge = Color3.fromRGB(214, 232, 248),
	TitleEdge = Color3.fromRGB(0, 69, 107),
	TitleShadow = Color3.fromRGB(0, 40, 66),
	PriceTop = Color3.fromRGB(200, 255, 40),
	Price = Color3.fromRGB(121, 253, 0),
	PriceEdge = Color3.fromRGB(36, 96, 0),
	BlueTop = Color3.fromRGB(90, 214, 255),
	Blue = Color3.fromRGB(30, 170, 255),
	BlueEdge = Color3.fromRGB(0, 60, 120),
	CyanTop = Color3.fromRGB(76, 242, 255), -- HUD squares
	Cyan = Color3.fromRGB(39, 204, 254),
	CyanLip = Color3.fromRGB(0, 108, 142),
	CyanEdge = Color3.fromRGB(0, 52, 70),
	QuestBody = Color3.fromRGB(240, 249, 254), -- the NEXT UP bar and the HUD cards
	QuestEdge = Color3.fromRGB(150, 214, 255),
	QuestTitle = Color3.fromRGB(30, 150, 240),
	Tag = Color3.fromRGB(255, 218, 52), -- the tilted yellow "NEXT UP!" tag
	TagEdge = Color3.fromRGB(150, 96, 0),
	RibbonGold = Color3.fromRGB(255, 196, 30),
	RibbonRed = Color3.fromRGB(232, 30, 60),
	RibbonPink = Color3.fromRGB(255, 70, 140),
	CardEdge = Color3.fromRGB(28, 22, 40),
	Ink = Color3.fromRGB(28, 22, 40),
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 216, 74),
	Shade = Color3.fromRGB(0, 0, 0),
	Holo = { Color3.fromRGB(47, 198, 255), Color3.fromRGB(120, 230, 255), Color3.fromRGB(20, 140, 245) }, -- the pet card
	HoloEdge = Color3.fromRGB(10, 90, 200),
	HoloGlow = Color3.fromRGB(95, 244, 255),
}

Theme.Color = {
	-- surfaces
	Panel = Color3.fromRGB(255, 255, 255), -- modal body (white sheet with the faint diamond pattern)
	PanelRim = Theme.Pet.PanelEdge, -- the pale blue line around a sheet
	PanelEdge = Color3.fromRGB(8, 22, 32), -- dark border around HUD cards and buttons
	Inset = Color3.fromRGB(226, 238, 248), -- rows, cards and wells inside a sheet (pale blue)
	InsetEdge = Color3.fromRGB(196, 220, 240), -- 1-2 px line around an inset
	InsetHover = Color3.fromRGB(208, 230, 250),
	Hud = Theme.Pet.TabBar, -- floating HUD cards (navy, slightly see-through)
	Shade = Color3.fromRGB(8, 8, 10), -- backdrop behind a modal
	-- text
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(60, 108, 142), -- notes on a white sheet (dark: no outline)
	Faint = Color3.fromRGB(106, 146, 176),
	Outline = Color3.fromRGB(0, 0, 0),
	DarkText = Color3.fromRGB(42, 28, 6), -- on gold
	-- accents
	Gold = Color3.fromRGB(255, 196, 36), -- selected rows, counts, the coin
	GoldDeep = Color3.fromRGB(172, 112, 8),
	GoldHover = Color3.fromRGB(255, 212, 84),
	GoldDim = Color3.fromRGB(150, 116, 30), -- equipped / in-use wells (dark gold)
	Count = Color3.fromRGB(255, 176, 32), -- important counts ("3/5", "1/3")
	Cash = Color3.fromRGB(121, 253, 0), -- money
	CashDeep = Color3.fromRGB(36, 96, 0),
	Gray = Theme.Pet.TabBar, -- secondary buttons, unselected tabs (navy)
	GrayDeep = Theme.Pet.TabBarEdge,
	GrayHover = Color3.fromRGB(26, 68, 96),
	Red = Theme.Pet.Red, -- close, destructive
	RedDeep = Theme.Pet.RedEdge,
	Green = Theme.Pet.Price, -- ready, success, ON switches, progress
	GreenDeep = Theme.Pet.PriceEdge,
	Warn = Color3.fromRGB(240, 60, 50), -- error text
	Disabled = Color3.fromRGB(154, 168, 184),
	DisabledText = Color3.fromRGB(236, 240, 246),
}

Theme.Font = {
	Display = Enum.Font.FredokaOne, -- panel titles, big counts, timer (the clip uses one round font everywhere)
	Bold = Enum.Font.FredokaOne, -- buttons, labels, names, body
	Body = Enum.Font.FredokaOne,
}

-- Text sizes (logical px before UIScale). Fitted text never grows past these and shrinks to MinText.
Theme.Text = {
	Title = 30, -- modal titles
	Head = 20, -- headings, big buttons
	Body = 16,
	Small = 15,
	Tiny = 14, -- captions; never smaller on purpose
	MinText = 14, -- the text floor (shared/UiKit.MinText): fitted words never shrink below it
	Count = 22, -- HUD counters
	Timer = 26,
}

-- Outline thickness on text (UIStroke, contextual).
Theme.Outline = {
	Strong = 3.4, -- titles, HUD floating text, big counts
	Normal = 2.6, -- buttons, labels (polish 2026-10-15: thicker dark outlines read chunkier on a phone)
	Light = 1.4, -- supporting text
}

Theme.Size = {
	Touch = 44, -- minimum touch target (logical; UI.button pads hit areas so it also holds in real px, see UI.minTouch)
	Button = 44,
	Close = 48, -- red close square (44 px or more: a thumb target, phone review 2026-10-15)
	Gap = 8,
	Pad = 12,
	Edge = 12, -- distance from the safe-area edge
	Radius = 12, -- controls and rows (round, cartoon)
	RadiusSm = 8, -- chips, gems, small thumbnails
	RadiusLg = 16, -- panels
	Border = 4, -- panel border
	BorderThin = 3, -- rows, buttons
	Tab = 44, -- tab bars are tapped like buttons
	Row = 56,
	HudTile = 54, -- lobby menu tiles
	Primary = Vector2.new(124, 64), -- hunt action button
}

-- Motion (Reduce Motion turns every one of these into an instant change).
Theme.Motion = {
	Press = 0.07, -- button dip
	PressScale = 0.95,
	ModalIn = 0.14,
	ModalOut = 0.1,
	ModalFrom = 0.96, -- starting scale of a modal (no bounce)
	PanelShrink = 0.16, -- a closed menu or dialog shrinks away over this long
	PanelShrinkTo = 0.3,
	Toast = 0.16,
	ToastHold = 2.8, -- seconds a notification stays
	ToastHoldLong = 4.2, -- important ones (purchases, geode added)
	ToastSlide = 0.28, -- notices slide in from the right
	Blur = 10, -- BlurEffect size behind an open menu (camera effect, not Lighting)
	BlurIn = 0.18,
}

-- Springs (Vendor/spr: damping ratio, frequency in Hz). Under 1 damping overshoots = the cartoon bounce.
Theme.Spring = {
	Press = { 0.7, 7 }, -- finger down: quick dip
	Release = { 0.32, 4.5 }, -- finger up: bounce back past 1 and settle
	PressScale = 0.9,
	Panel = { 0.45, 3.6 }, -- menus and dialogs spring in from PanelFrom
	PanelFrom = 0.7,
	Pop = { 0.38, 4 }, -- new things (dots, stamps, cards)
}

-- Cartoon button look: a darker lip along the bottom (UIGradient multiplies the fill; keypoint = where it starts).
Theme.Button = {
	Lip = 0.78, -- 0..1 down the button
	LipShade = Color3.fromRGB(150, 150, 150), -- (polish 2026-10-15: a deeper lip makes every button a chunky block)
	MidShade = Color3.fromRGB(226, 226, 226), -- just above the lip (soft curve into it)
	TopShade = Color3.fromRGB(255, 255, 255),
}

-- Panel gradient (multiplies the fill: lighter top, deeper bottom) and the glossy top highlight on buttons.
Theme.Panel = {
	Top = Color3.fromRGB(255, 255, 255),
	Bottom = Color3.fromRGB(236, 244, 252),
}
Theme.Gloss = {
	Transparency = 0.64, -- white sheen over the top half of a button (polish: brighter top)
	Height = 0.46,
}

-- Idle loops (Reduce Motion stops them).
Theme.Loop = {
	ShineEvery = 3.2, -- seconds between glints across a main / buy button
	ShineTime = 0.55,
	WiggleEvery = 2.6, -- seconds between "tap me" tilts on the main button
	WiggleAngle = 5,
	HoverScale = 1.06,
	RaysSpin = 40, -- degrees per second
	DotHopEvery = 4.5, -- seconds between the little hops of red "new" dots
}

-- Accent colours for UI juice (one place, so every screen matches).
Theme.Fx = {
	NewDot = Color3.fromRGB(235, 52, 44), -- red "!" dot on new things
	NewDotEdge = Color3.fromRGB(120, 14, 10),
	Confetti = {
		Color3.fromRGB(255, 196, 36),
		Color3.fromRGB(110, 230, 70),
		Color3.fromRGB(80, 170, 255),
		Color3.fromRGB(255, 104, 160),
		Color3.fromRGB(190, 120, 255),
	},
	Shine = Color3.fromRGB(255, 255, 255),
	Danger = Color3.fromRGB(255, 70, 60), -- timer in its last seconds
}

return Theme
