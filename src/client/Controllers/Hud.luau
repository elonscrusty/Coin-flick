--!strict
-- Phone-first HUD: cash + hat points on top, big SHOP / RESET / TOP / VIEW
-- buttons on the right (clear of the thumbstick and jump button), the shop
-- combo counter and mega boost timer. The shop, reset popup, top 10, toasts
-- and banners are in Panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)
local HudText = require(ReplicatedStorage.Shared.Util.HudText)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
local Panels = require(script.Parent.Panels)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)

type Snapshot = Types.Snapshot

local Hud = {}

local player = Players.LocalPlayer

local UiStyle = require(script.Parent.UiStyle)

local INK = UiStyle.INK
local WHITE = UiStyle.WHITE
local GREEN = UiStyle.GREEN
local PURPLE = UiStyle.PURPLE
local ORANGE = UiStyle.ORANGE
local BLUE = UiStyle.BLUE
local GREY = UiStyle.GREY

local COUNT = UiStyle.COUNT

-- Small UI helpers (shared look lives in UiStyle) ---------------------------

local corner = UiStyle.corner
local stroke = UiStyle.stroke
local textLimit = UiStyle.textLimit
local label = UiStyle.label
local button = UiStyle.button
local popScale = UiStyle.popScale

-- Anchored at the middle so pop animations (UIScale) grow from the center.
local function place(g: GuiObject, r: HudLayout.Rect)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + r.h / 2)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

local function setMaxText(g: GuiObject, max: number)
	local c = g:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = math.max(HudLayout.MIN_TEXT, math.floor(max))
	end
end

-- Build ---------------------------------------------------------------------

local gui: ScreenGui
local cashLabel: TextLabel
local cashScale: UIScale
local hatLabel: TextLabel
local hatScale: UIScale
local infoLabel: TextLabel
local resetButton: TextButton
local resetBar: Frame
local resetFill: Frame
local resetCount: TextLabel
local resetWord: TextLabel
local resetPulse: Tween?
local megaLabel: TextLabel
local boostLabel: TextLabel
local boostEnds = 0
local comboLabel: TextLabel
local comboScale: UIScale
local comboToken = 0
local layout: HudLayout.Layout = HudLayout.compute(844, 390, true) -- redone in applyLayout
local cheatFrame: Frame? = nil
local layoutListeners: { (HudLayout.Layout) -> () } = {}

local shownCash = Instance.new("NumberValue")
local render: (Snapshot) -> ()

local function anyPanelOpen(): boolean
	return Panels.anyOpen()
end

-- Info / boost cards: fixed spots in the left band (HudLayout); hidden when
-- empty or while a panel is open.
local function setStrip(l: TextLabel, text: string)
	l.Text = text
	place(l, if l == boostLabel then layout.boost elseif l == megaLabel then layout.mega else layout.info)
	l.Visible = text ~= "" and (l ~= infoLabel or not anyPanelOpen())
end

-- Combo counter: grows with every quick tap, fades when the chain breaks.
local function showCombo(combo: number)
	comboToken += 1
	local token = comboToken
	comboLabel.Text = `🔥 x{combo}\nCOMBO`
	comboLabel.TextColor3 = Color3.fromHSV(math.max(0, 0.15 - combo * 0.007), 0.85, 1)
	UiStyle.showText(comboLabel)
	comboLabel.BackgroundTransparency = 0.2
	local card = comboLabel:FindFirstChild("Card")
	if card and card:IsA("UIStroke") then
		card.Transparency = 0
	end
	comboLabel.Visible = true
	popScale(comboScale, 1 + math.min(0.6, combo * 0.03))
	if combo % 5 == 0 then
		Sounds.play("Combo", 0.5, 1 + math.min(1, combo / 20))
	end
	task.delay(Config.COMBO_WINDOW, function()
		if token ~= comboToken then
			return
		end
		local fade = UiStyle.fadeText(comboLabel, 1)
		TweenService:Create(comboLabel, COUNT, { BackgroundTransparency = 1 }):Play()
		if card and card:IsA("UIStroke") then
			TweenService:Create(card, COUNT, { Transparency = 1 }):Play()
		end
		fade.Completed:Wait()
		if token == comboToken then
			comboLabel.Visible = false
		end
	end)
end

-- Big icon on top, word underneath (the icon is the thing kids spot).
local function sideButton(
	icon: string,
	word: string,
	color: Color3,
	onPress: () -> ()
): (TextButton, TextLabel, TextLabel)
	local b = button("", color, onPress)
	local iconLabel = label({
		Name = "Icon",
		Text = icon,
		Size = UDim2.fromScale(1, 0.6),
		TextStrokeTransparency = 1,
		ZIndex = 3,
	})
	iconLabel.Parent = b
	local wordLabel = label({
		Name = "Word",
		Text = word,
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.38),
		ZIndex = 3,
	})
	textLimit(wordLabel, 22)
	wordLabel.Parent = b
	return b, iconLabel, wordLabel
end

local function buildCheats(parent: ScreenGui)
	local cheat = ClientNet.find("Cheat")
	if not cheat then
		return -- only exists in Studio
	end
	local frame = Instance.new("Frame")
	frame.Name = "StudioCheats"
	frame.BackgroundTransparency = 1
	local layoutList = Instance.new("UIListLayout")
	layoutList.Padding = UDim.new(0, HudLayout.GAP)
	layoutList.SortOrder = Enum.SortOrder.LayoutOrder
	layoutList.Parent = frame
	local items = {
		{ "+1M", "cash" },
		{ "FILL", "fill" },
		{ "RARE", "rare" },
		{ "MEGA", "mega" },
		{ "AWAY", "away" },
		{ "WIPE", "wipe" },
	}
	assert(#items == HudLayout.CHEATS, "HudLayout.CHEATS must match the test buttons")
	for i, item in items do
		local b = button(`🧪{item[1]}`, GREY, function()
			cheat:FireServer(item[2])
		end)
		b.Name = item[2]
		b.LayoutOrder = i
		b.Parent = frame
	end
	frame.Parent = parent
	cheatFrame = frame
end

render = function(s: Snapshot)
	-- Cash counts up instead of snapping.
	local oldCash = shownCash.Value
	TweenService:Create(shownCash, COUNT, { Value = s.cash }):Play()
	if s.cash > oldCash then
		popScale(cashScale, 1.15)
	end
	local oldHats = tonumber(hatLabel:GetAttribute("Value")) or 0
	hatLabel:SetAttribute("Value", s.hatPoints)
	hatLabel.Text = `🎩 {Format.short(s.hatPoints)}`
	if s.hatPoints > oldHats then
		popScale(hatScale, 1.15)
	end
	setStrip(infoLabel, HudText.info(s.cashPerHeads, s.headsChance, if boostEnds > os.clock() then 2 else 1))

	-- One button shape in every state: the word on top, a big bar with the
	-- count inside. Full just turns the bar bright and the word to RESET!.
	local full = s.tableFull
	resetFill.Size =
		UDim2.fromScale(if s.coinCount <= 0 then 0 else math.clamp(s.coinCount / Config.MAX_COINS, 0.12, 1), 1)
	resetFill.BackgroundColor3 = if full then Color3.fromRGB(255, 245, 120) else Color3.fromRGB(255, 205, 40)
	resetCount.Text = HudText.resetCount(s.coinCount, Config.MAX_COINS)
	resetWord.Text = HudText.reset(full)
	-- Glow the RESET button's outline when the table is full. (Pulsing the
	-- outline, not the size, so the press-pop animation can't cancel it.)
	local outline = resetButton:FindFirstChildOfClass("UIStroke")
	if s.tableFull and not resetPulse and outline and not anyPanelOpen() then
		local tween = TweenService:Create(
			outline,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 7, Color = Color3.fromRGB(255, 255, 120) }
		)
		tween:Play()
		resetPulse = tween
	elseif not s.tableFull and resetPulse then
		resetPulse:Cancel()
		resetPulse = nil
		if outline then
			outline.Thickness = 3
			outline.Color = INK
		end
	end
end

local topFrame: Frame
local pillGui: ScreenGui
local sideFrame: Frame
local sideButtons: { TextButton } = {}

-- Put every HUD piece in its HudLayout slot for this screen size. Runs on
-- start and whenever the screen changes (phone turned, window resized).
local function applyLayout()
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	layout = HudLayout.compute(size.X, size.Y, UserInputService.TouchEnabled)
	local s = layout.scale

	place(topFrame, layout.top)
	setMaxText(cashLabel, layout.top.h * 0.62)
	setMaxText(hatLabel, layout.top.h * 0.62)
	setMaxText(infoLabel, layout.info.h * 0.4)
	setStrip(infoLabel, infoLabel.Text)
	setMaxText(megaLabel, layout.mega.h * 0.75)
	setStrip(megaLabel, megaLabel.Text)
	setMaxText(boostLabel, layout.boost.h * 0.75)
	setStrip(boostLabel, boostLabel.Text)
	place(comboLabel, layout.combo)
	setMaxText(comboLabel, layout.combo.h * 0.42)

	place(sideFrame, layout.side)
	for i, b in sideButtons do
		local r = layout.sideButtons[i]
		place(b, { x = r.x - layout.side.x, y = r.y - layout.side.y, w = r.w, h = r.h })
		local word = b:FindFirstChild("Word")
		if word and word:IsA("GuiObject") then
			setMaxText(word, r.h * 0.24)
		end
	end

	if cheatFrame then
		place(cheatFrame, layout.cheats)
		local list = cheatFrame:FindFirstChildOfClass("UIListLayout")
		local row = layout.cheats.w > layout.cheats.h
		if list then
			list.FillDirection = if row then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
			list.Padding = UDim.new(0, HudLayout.GAP * s)
		end
		local count = HudLayout.CHEATS
		for _, b in cheatFrame:GetChildren() do
			if b:IsA("TextButton") then
				b.Size = if row
					then UDim2.new(1 / count, -HudLayout.GAP * s, 1, 0)
					else UDim2.new(1, 0, 1 / count, -HudLayout.GAP * s)
			end
		end
	end

	Panels.setLayout(layout)
	for _, fn in layoutListeners do
		task.spawn(fn, layout)
	end
end

-- Current HUD slots (toast, shout, panel box...) for other screen code.
function Hud.getLayout(): HudLayout.Layout
	return layout
end

-- Called with the new slots whenever the screen size changes.
function Hud.onLayout(fn: (HudLayout.Layout) -> ())
	table.insert(layoutListeners, fn)
	fn(layout)
end

function Hud.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoinFlickHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	-- Top bar: cash + hat points.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.Padding = UDim.new(0, 8) -- a clear gap between the two pills
	topLayout.Parent = top
	topFrame = top

	local function pill(color: Color3, width: number): (Frame, TextLabel, UIScale)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(width, 1)
		frame.BackgroundColor3 = color
		corner(frame, 0.5)
		stroke(frame, 3)
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		local text = label({ Size = UDim2.fromScale(0.86, 0.8), Position = UDim2.fromScale(0.07, 0.1) })
		textLimit(text, 40)
		text.Parent = frame
		frame.Parent = top
		return frame, text, scale
	end
	local _cashFrame, cl, cs = pill(GREEN, 0.48)
	cashLabel, cashScale = cl, cs
	local _hatFrame, hl, hs = pill(PURPLE, 0.44)
	hatLabel, hatScale = hl, hs
	cashLabel.Text = "$0"
	hatLabel.Text = "🎩 0"
	-- The cash and hat pills sit in their own ScreenGui above the panels' dim,
	-- so they stay bright while a shop is open.
	pillGui = Instance.new("ScreenGui")
	pillGui.Name = "CoinFlickPills"
	pillGui.ResetOnSpawn = false
	pillGui.DisplayOrder = 6 -- money, hats and chips stay bright above the shop's dim
	pillGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pillGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	top.Parent = pillGui

	-- Solid cards so the text reads on any sky. The info card is dark; the
	-- chips are bright and chunky.
	local function strip(name: string, text: string, color: Color3, fill: Color3, parent: ScreenGui): TextLabel
		local l = label({ Name = name, Text = text, TextColor3 = color })
		textLimit(l, 24)
		l.BackgroundColor3 = fill
		l.BackgroundTransparency = 0
		corner(l, 0.4)
		stroke(l, 3)
		local outline = l:FindFirstChild("TextOutline")
		if outline and outline:IsA("UIStroke") then
			outline.Thickness = 1.5 -- thin, so the letters stay open
		end
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0.06, 0)
		pad.PaddingBottom = UDim.new(0.06, 0)
		pad.Parent = l
		l.Parent = parent
		return l
	end
	infoLabel = strip("Info", "Tap a coin to flip it!", WHITE, INK, gui)
	boostLabel = strip("Boost", "", WHITE, Color3.fromRGB(232, 96, 20), pillGui)
	boostLabel.Visible = false
	megaLabel = strip("Mega", "", WHITE, PURPLE, pillGui)
	megaLabel.Visible = false

	-- Left side, under the Roblox menu, above the thumbstick.
	comboLabel = label({
		Name = "Combo",
		Visible = false,
		ZIndex = 9,
	})
	textLimit(comboLabel, 34)
	-- A dark card so any flame color reads, big number, "COMBO" under it.
	comboLabel.BackgroundColor3 = INK
	comboLabel.BackgroundTransparency = 0.2
	corner(comboLabel, 0.25)
	stroke(comboLabel, 3).Name = "Card"
	local comboPad = Instance.new("UIPadding")
	comboPad.PaddingLeft = UDim.new(0, 6)
	comboPad.PaddingRight = UDim.new(0, 6)
	comboPad.PaddingTop = UDim.new(0, 3)
	comboPad.PaddingBottom = UDim.new(0, 3)
	comboPad.Parent = comboLabel
	comboScale = Instance.new("UIScale")
	comboScale.Parent = comboLabel
	comboLabel.Parent = gui

	-- Right side: 2x2 big buttons, above the phone jump button.
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.BackgroundTransparency = 1
	sideFrame = side
	local shopButton = sideButton("🛒", "SHOP", GREEN, function()
		Sounds.play("Tap", 0.4)
		Panels.open("shop")
	end)
	local resetB, resetI, resetW = sideButton("🔄", "RESET", ORANGE, function()
		Sounds.play("Tap", 0.4)
		local s = State.get()
		if s and s.tableFull then
			Panels.open("reset")
		else
			local count = if s then s.coinCount else 1
			Panels.toast(`Fill your table first! ({count}/{Config.MAX_COINS} coins)`)
		end
	end)
	resetButton, resetWord = resetB, resetW
	resetI.Visible = false -- no icon: the bar says it all
	resetWord.Position = UDim2.fromScale(0, 0.04)
	resetWord.Size = UDim2.fromScale(1, 0.4)
	-- The word sits on top; a roomy gold bar with the coin count fills the bottom.
	resetBar = Instance.new("Frame")
	resetBar.Name = "Bar"
	resetBar.Position = UDim2.fromScale(0.06, 0.46)
	resetBar.Size = UDim2.fromScale(0.88, 0.5)
	resetBar.BackgroundColor3 = Color3.fromRGB(24, 28, 52) -- dark track
	resetBar.BackgroundTransparency = 0
	resetBar.ZIndex = 2
	corner(resetBar, 0.5)
	stroke(resetBar, 2).Color = WHITE
	resetBar.Parent = resetButton
	resetFill = Instance.new("Frame")
	resetFill.Name = "Fill"
	resetFill.BackgroundColor3 = Color3.fromRGB(255, 205, 40)
	resetFill.Size = UDim2.fromScale(0, 1)
	resetFill.ZIndex = 3
	corner(resetFill, 0.5)
	resetFill.Parent = resetBar
	resetCount = label({ Name = "Count", Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	textLimit(resetCount, 26)
	resetCount.Parent = resetBar
	local topButton = sideButton("🏆", "TOP", PURPLE, function()
		Sounds.play("Tap", 0.4)
		Panels.open("top")
	end)
	local viewIcon: TextLabel
	local viewWord: TextLabel
	local viewButton
	viewButton, viewIcon, viewWord = sideButton("🔍", "ZOOM", BLUE, function()
		local tableView = CameraView.toggle()
		viewIcon.Text = if tableView then "🏃" else "🔍"
		viewWord.Text = if tableView then "WALK" else "ZOOM"
	end)
	sideButtons = { shopButton, resetButton, topButton, viewButton }
	for i, b in sideButtons do
		b.Name = ({ "Shop", "Reset", "Top", "View" })[i]
		b.Parent = side
	end
	side.Parent = gui

	buildCheats(gui)

	-- Panels hide the touch controls (Panels) and our test buttons and strips.
	Panels.onOpenChanged(function(open: boolean)
		if cheatFrame then
			cheatFrame.Visible = not open
		end
		-- The RESET glow would shine through the dim, so pause it behind panels.
		if open and resetPulse then
			resetPulse:Cancel()
			resetPulse = nil
			local outline = resetButton:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Thickness = 3
				outline.Color = INK
			end
		elseif not open then
			local s = State.get()
			if s then
				render(s)
			end
		end
		-- Only the info card hides; money, hats and chips stay in view.
		infoLabel.Visible = infoLabel.Text ~= "" and not open
	end)

	shownCash.Changed:Connect(function(value: number)
		cashLabel.Text = `${Format.short(value)}`
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	pillGui.Parent = playerGui
	gui.Parent = playerGui
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
end

function Hud.start()
	State.onChange(render)
	ClientNet.event("Flipped").OnClientEvent:Connect(function(ev: Types.FlipEvent)
		if ev.ownerId == player.UserId and ev.combo >= 2 then
			showCombo(ev.combo)
		end
	end)
	local mega: Types.MegaState = { taps = 0, goal = 1, boostLeft = 0 }
	ClientNet.event("MegaState").OnClientEvent:Connect(function(state: Types.MegaState)
		boostEnds = os.clock() + state.boostLeft
		mega = state
	end)
	task.spawn(function()
		while true do
			local left = boostEnds - os.clock()
			local text = HudText.boost(left)
			if text ~= boostLabel.Text then
				setStrip(boostLabel, text)
				local snap = State.get()
				if snap then
					-- the Heads card doubles while the boost runs
					setStrip(infoLabel, HudText.info(snap.cashPerHeads, snap.headsChance, if left > 0 then 2 else 1))
				end
			end
			local megaText = HudText.mega(mega.taps, mega.goal)
			if megaText ~= megaLabel.Text then
				setStrip(megaLabel, megaText)
			end
			task.wait(0.25)
		end
	end)
end

return Hud
