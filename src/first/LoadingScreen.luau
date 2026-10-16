--!strict
-- FIND THE GEODE! title / loading screen (ReplicatedFirst, runs before the rest of the client).
--
-- Progress is step based and only reports things that really happened, in order:
--   1. the place finished loading (game:IsLoaded)
--   2. your character exists
--   3. the game interface is up (the HUD ScreenGui that src/client/ui/UI.luau creates)
-- While those run, the pet meshes and textures (ReplicatedStorage.PetModels) are preloaded in the background so
-- pets do not pop in grey; the screen waits for them at most 8 s more (and never past TIMEOUT).
-- No percentages and no fake timers. If a step takes longer than TIMEOUT seconds in total, the screen
-- removes itself anyway so a slow or missing step can never trap the player behind it.
-- Uses only engine services: the shared UI module is not loaded yet at this point.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LoadingScreen = {}

local NAME = "FindThePetLoading"
local HUD_NAME = "CrackTheRocks" -- UI.screen() (internal id kept)
local TIMEOUT = 25
local FADE = 0.25

-- Pet style look (src/client/ui/Theme.luau, Theme.Pet). ReplicatedFirst runs before the client modules replicate,
-- so the few colours are mirrored here; keep them in step with Theme.Pet.
local SKY_TOP = Color3.fromRGB(76, 242, 255) -- Theme.Pet.CyanTop
local SKY = Color3.fromRGB(30, 170, 255) -- Theme.Pet.Blue
local PANEL = Color3.fromRGB(255, 255, 255) -- Theme.Pet.Panel
local PANEL_PATTERN = Color3.fromRGB(226, 238, 248) -- Theme.Pet.PanelPattern
local PANEL_EDGE = Color3.fromRGB(214, 232, 248) -- Theme.Pet.PanelEdge
local TITLE_EDGE = Color3.fromRGB(0, 69, 107) -- Theme.Pet.TitleEdge
local TITLE_SHADOW = Color3.fromRGB(0, 40, 66) -- Theme.Pet.TitleShadow
local LIME_TOP = Color3.fromRGB(210, 254, 0) -- Theme.Pet.LimeTop
local LIME = Color3.fromRGB(114, 254, 0) -- Theme.Pet.Lime
local LIME_EDGE = Color3.fromRGB(46, 110, 0) -- Theme.Pet.LimeEdge
local INK = Color3.fromRGB(28, 22, 40) -- Theme.Pet.Ink
local NOTE = Color3.fromRGB(60, 108, 142) -- Theme.Color.Muted (dark notes on a white sheet)
local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(255, 244, 220) -- the loading egg
local SPOT = Color3.fromRGB(39, 204, 254) -- Theme.Pet.Cyan (egg spots)

export type Screen = {
	Gui: ScreenGui,
	setStep: (Screen, number, string) -> (),
	close: (Screen) -> (),
}

-- Short kid-simple tips; one is picked at random each launch (local list: shared modules are not loaded yet).
local TIPS = {
	"Rare pets give bigger boosts!",
	"Hatch eggs to fill your Pet Book.",
	"Tap fast to hatch eggs quicker!",
	"Pets follow you and help out.",
	"Better nests hatch rarer pets.",
	"Friends make the hunt more fun!",
	"Check the Pet Book for new pets.",
	"Legendary pets are super rare!",
}

LoadingScreen.Steps = { "Loading the meadow…", "Getting your eggs ready…", "Opening the nest…" }

local function outline(parent: Instance, thick: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Name = "Outline"
	s.Color = color or INK
	s.Thickness = thick
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function label(parent: Instance, text: string, font: Enum.Font, color: Color3, maxSize: number, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = font
	t.TextColor3 = color
	t.TextScaled = true -- fitted to its box, capped below
	t.TextWrapped = true
	for k, v in props do
		(t :: any)[k] = v
	end
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.MinTextSize = 14
	cap.Parent = t
	t.Parent = parent
	return t
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function vgrad(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
end

local function edge(parent: Instance, color: Color3, thick: number)
	local s = Instance.new("UIStroke")
	s.Name = "Border"
	s.Color = color
	s.Thickness = thick
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

-- Title words: white Fredoka with the dark blue outline over a darker drop copy (PetStyle.title).
local function title(parent: Instance, text: string, maxSize: number, props: { [string]: any }): TextLabel
	local shadowProps = table.clone(props)
	shadowProps.Name = (props.Name or "Title") .. "Shadow"
	shadowProps.Position = (props.Position or UDim2.new()) + UDim2.fromOffset(0, 3)
	shadowProps.ZIndex = (props.ZIndex or 1) - 1
	local sh = label(parent, text, Enum.Font.FredokaOne, TITLE_SHADOW, maxSize, shadowProps)
	outline(sh, 4, TITLE_SHADOW)
	local t = label(parent, text, Enum.Font.FredokaOne, WHITE, maxSize, props)
	outline(t, 3.4, TITLE_EDGE)
	return t
end

-- Builds the screen (no waiting). `parent` defaults to the local PlayerGui.
function LoadingScreen.new(parent: Instance?): Screen
	local gui = Instance.new("ScreenGui")
	gui.Name = NAME
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None -- edge to edge, under the notch and home bar too
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Name = "Backdrop"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = SKY
	bg.BorderSizePixel = 0
	bg.Active = true -- swallows taps while loading
	bg.Parent = gui
	vgrad(bg, SKY_TOP, SKY) -- bright sky, lighter at the top

	-- centred column: gem mark, title, tagline, the step card
	local col = Instance.new("Frame")
	col.Name = "Column"
	col.AnchorPoint = Vector2.new(0.5, 0.5)
	col.Position = UDim2.fromScale(0.5, 0.5)
	col.Size = UDim2.new(0.9, 0, 0, 300)
	col.BackgroundTransparency = 1
	col.Parent = bg
	local maxW = Instance.new("UISizeConstraint")
	maxW.MaxSize = Vector2.new(700, 300)
	maxW.Parent = col

	-- the logo mark: a spotted cream egg that bounces (squashes on landing) while the game loads
	local egg = Instance.new("Frame")
	egg.Name = "Egg"
	egg.AnchorPoint = Vector2.new(0.5, 1)
	egg.Position = UDim2.new(0.5, 0, 0, 48)
	egg.Size = UDim2.fromOffset(34, 44)
	egg.BackgroundColor3 = CREAM
	egg.BorderSizePixel = 0
	egg.ZIndex = 2
	egg.Parent = col
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0.5, 0)
	ec.Parent = egg
	edge(egg, INK, 3)
	for i, spot in { { 0.32, 0.38, 9 }, { 0.66, 0.3, 6 }, { 0.6, 0.66, 8 } } do
		local sp = Instance.new("Frame")
		sp.Name = "Spot" .. i
		sp.AnchorPoint = Vector2.new(0.5, 0.5)
		sp.Position = UDim2.fromScale(spot[1], spot[2])
		sp.Size = UDim2.fromOffset(spot[3], spot[3])
		sp.BackgroundColor3 = SPOT
		sp.BorderSizePixel = 0
		sp.ZIndex = 3
		sp.Parent = egg
		corner(sp, spot[3])
	end
	local shadow = Instance.new("Frame")
	shadow.Name = "EggShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 0, 49)
	shadow.Size = UDim2.fromOffset(30, 6)
	shadow.BackgroundColor3 = TITLE_SHADOW
	shadow.BackgroundTransparency = 0.6
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 0
	shadow.Parent = col
	corner(shadow, 3)
	local t0 = os.clock()
	local bounce: RBXScriptConnection? = RunService.Heartbeat:Connect(function()
		local ph = ((os.clock() - t0) * 1.6) % 1 -- one hop every 0.62 s
		local h = 4 * ph * (1 - ph) -- 0 on the ground, 1 at the top
		local land = math.max(0, 1 - ph / 0.12) + math.max(0, (ph - 0.9) / 0.1) -- squash around the touch-down
		egg.Position = UDim2.new(0.5, 0, 0, 48 - h * 22)
		egg.Size = UDim2.fromOffset(34 + land * 6, 44 - land * 6)
		shadow.Size = UDim2.fromOffset(30 - h * 12, 6)
	end)

	title(col, "FIND THE <font color=\"#72FE00\">PET!</font>", 68, { -- the lime is Theme.Pet.Lime
		Name = "Logo",
		RichText = true,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 74),
		ZIndex = 3,
	})
	local tag = label(col, "One pile. One pet.", Enum.Font.FredokaOne, WHITE, 22, {
		Name = "Tagline",
		Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 0, 28),
	})
	outline(tag, 2, TITLE_EDGE)

	-- step card: the current real step and three dots (finished steps gold)
	local card = Instance.new("Frame")
	card.Name = "Track"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 176)
	card.Size = UDim2.new(0.8, 0, 0, 82)
	card.BackgroundColor3 = PANEL
	card.BorderSizePixel = 0
	card.ZIndex = 2
	card.Parent = col
	local cmax = Instance.new("UISizeConstraint")
	cmax.MaxSize = Vector2.new(380, 82)
	cmax.Parent = card
	corner(card, 14)
	edge(card, PANEL_EDGE, 3)
	-- the sheet's drop copy (a sibling under it: children draw above their parent)
	local drop = Instance.new("Frame")
	drop.Name = "TrackDrop"
	drop.AnchorPoint = card.AnchorPoint
	drop.Position = card.Position + UDim2.fromOffset(0, 4)
	drop.Size = card.Size
	drop.BackgroundColor3 = TITLE_SHADOW
	drop.BackgroundTransparency = 0.5
	drop.BorderSizePixel = 0
	drop.ZIndex = 1
	drop.Parent = col
	local dmax = Instance.new("UISizeConstraint")
	dmax.MaxSize = Vector2.new(380, 82)
	dmax.Parent = drop
	corner(drop, 14)
	local status = label(card, LoadingScreen.Steps[1], Enum.Font.FredokaOne, NOTE, 22, {
		Name = "Status",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 30),
		ZIndex = 3,
	})
	-- lime progress bar: one segment per finished step, a dot at each step mark
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 50)
	track.Size = UDim2.new(1, -40, 0, 16)
	track.BackgroundColor3 = PANEL_PATTERN
	track.BorderSizePixel = 0
	track.ZIndex = 3
	track.Parent = card
	corner(track, 8)
	edge(track, PANEL_EDGE, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = LIME
	fill.BorderSizePixel = 0
	fill.ZIndex = 4
	fill.Parent = track
	corner(fill, 8)
	vgrad(fill, LIME_TOP, LIME)
	local dots: { Frame } = {}
	for i = 1, #LoadingScreen.Steps do
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.new(i / #LoadingScreen.Steps, 0, 0.5, 0)
		d.Size = UDim2.fromOffset(16, 16)
		d.BackgroundColor3 = PANEL
		d.BorderSizePixel = 0
		d.ZIndex = 5
		d.Parent = track
		corner(d, 8)
		edge(d, PANEL_EDGE, 2)
		dots[i] = d
	end
	local tipLine = label(col, "Tip: " .. TIPS[math.random(#TIPS)], Enum.Font.FredokaOne, WHITE, 18, {
		Name = "Tip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 268),
		Size = UDim2.new(1, 0, 0, 24),
	})
	outline(tipLine, 2, TITLE_EDGE)

	gui.Parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui")

	local self = {} :: any
	self.Gui = gui
	local closed = false
	-- step `n` of #Steps is in progress: finished steps are gold, the current one white
	function self.setStep(_: Screen, n: number, text: string)
		if closed then
			return
		end
		status.Text = text
		for i, d in dots do
			-- finished marks turn lime, the current one blue, the rest stay white
			d.BackgroundColor3 = if i < n then LIME elseif i == n then SKY else PANEL
			local e = d:FindFirstChild("Border")
			if e and e:IsA("UIStroke") then
				e.Color = if i < n then LIME_EDGE elseif i == n then TITLE_EDGE else PANEL_EDGE
			end
		end
		fill.Size = UDim2.fromScale(math.clamp((n - 1) / #LoadingScreen.Steps, 0, 1), 1)
	end
	function self.close(_: Screen)
		if closed then
			return
		end
		closed = true
		if bounce then
			bounce:Disconnect()
			bounce = nil
		end
		bg.Active = false
		for _, d in dots do
			d.BackgroundColor3 = LIME
		end
		fill.Size = UDim2.fromScale(1, 1)
		local info = TweenInfo.new(FADE)
		TweenService:Create(bg, info, { BackgroundTransparency = 1 }):Play()
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			elseif d:IsA("Frame") and d ~= bg and d.BackgroundTransparency < 1 then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(FADE + 0.05, function()
			gui:Destroy()
		end)
	end
	return self :: Screen
end

-- Waits for `ready()` (polled) until `deadline`. True when it became ready.
local function waitFor(ready: () -> boolean, deadline: number): boolean
	while not ready() do
		if os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Shows the screen and walks the real steps, then removes it. Safe to call once per client.
function LoadingScreen.run()
	pcall(function()
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end)
	local player = Players.LocalPlayer
	local screen = LoadingScreen.new()
	local deadline = os.clock() + TIMEOUT
	screen:setStep(1, LoadingScreen.Steps[1])
	waitFor(function()
		return game:IsLoaded()
	end, deadline)
	local petsReady = false
	task.spawn(function()
		pcall(function()
			local folder = game:GetService("ReplicatedStorage"):FindFirstChild("PetModels")
			if folder then
				game:GetService("ContentProvider"):PreloadAsync({ folder })
			end
		end)
		petsReady = true
	end)
	screen:setStep(2, LoadingScreen.Steps[2])
	waitFor(function()
		return player.Character ~= nil
	end, deadline)
	screen:setStep(3, LoadingScreen.Steps[3])
	local pg = player:WaitForChild("PlayerGui")
	waitFor(function()
		return pg:FindFirstChild(HUD_NAME) ~= nil
	end, deadline)
	waitFor(function()
		return petsReady
	end, math.min(deadline, os.clock() + 8)) -- at most 8 s more just for pets

	screen:close()
end

return LoadingScreen
