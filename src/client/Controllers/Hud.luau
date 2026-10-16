--!strict
-- Phone-first HUD: cash + hat points on top, big SHOP / RESET / TOP / VIEW
-- buttons on the right (clear of the thumbstick and jump button), the shop
-- combo counter and mega boost timer. The shop, reset popup, top 10, toasts
-- and banners are in Panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
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
local resetFill: Frame
local resetWord: TextLabel
local resetPulse: Tween?
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

-- Info / boost strips: as wide as their words (so they hide less of the
-- world), centered in their slot; hidden when empty or a panel is open.
local function setStrip(l: TextLabel, text: string)
	l.Text = text
	local slot = if l == boostLabel then layout.boost else layout.info
	local cap = l:FindFirstChildOfClass("UITextSizeConstraint")
	local size = if cap then cap.MaxTextSize else 20
	local textW = TextService:GetTextSize(text, size, UiStyle.FONT, Vector2.new(10000, 1000)).X
	local w = math.min(slot.w, textW * 1.1 + 28)
	place(l, { x = slot.x + (slot.w - w) / 2, y = slot.y, w = w, h = slot.h })
	l.Visible = text ~= "" and not anyPanelOpen()
end

-- Combo counter: grows with every quick tap, fades when the chain breaks.
local function showCombo(combo: number)
	comboToken += 1
	local token = comboToken
	comboLabel.Text = `🔥 x{combo}\nCOMBO`
	comboLabel.TextColor3 = Color3.fromHSV(math.max(0, 0.15 - combo * 0.007), 0.85, 1)
	UiStyle.showText(comboLabel)
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
	setStrip(infoLabel, HudText.info(s.cashPerHeads, s.headsChance, s.coinCount, Config.MAX_COINS))

	-- Not full: a gold bar fills up inside the button (progress, not "off").
	resetButton.BackgroundColor3 = if s.tableFull then ORANGE else Color3.fromRGB(120, 95, 70)
	resetFill.Visible = not s.tableFull
	resetFill.Size = UDim2.fromScale(math.clamp(s.coinCount / Config.MAX_COINS, 0, 1), 1)
	resetWord.Text = HudText.reset(s.coinCount, Config.MAX_COINS, s.tableFull)
	-- Glow the RESET button's outline when the table is full. (Pulsing the
	-- outline, not the size, so the press-pop animation can't cancel it.)
	local outline = resetButton:FindFirstChildOfClass("UIStroke")
	if s.tableFull and not resetPulse and outline then
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
	setMaxText(infoLabel, layout.info.h * 0.72)
	setStrip(infoLabel, infoLabel.Text)
	setMaxText(boostLabel, layout.boost.h * 0.72)
	setStrip(boostLabel, boostLabel.Text)
	place(comboLabel, layout.combo)
	setMaxText(comboLabel, layout.combo.h * 0.4)

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
	topLayout.Padding = UDim.new(0.03, 0)
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
	local _cashFrame, cl, cs = pill(GREEN, 0.58)
	cashLabel, cashScale = cl, cs
	local _hatFrame, hl, hs = pill(PURPLE, 0.36)
	hatLabel, hatScale = hl, hs
	cashLabel.Text = "$0"
	hatLabel.Text = "🎩 0"
	top.Parent = gui

	-- Dark see-through strips so the white text reads on bright sky.
	local function strip(name: string, text: string, color: Color3): TextLabel
		local l = label({ Name = name, Text = text, TextColor3 = color })
		textLimit(l, 24)
		l.BackgroundColor3 = INK
		l.BackgroundTransparency = 0.3
		corner(l, 0.5)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = l
		l.Parent = gui
		return l
	end
	infoLabel = strip("Info", "Tap a coin to flip it!", WHITE)
	boostLabel = strip("Boost", "", UiStyle.GOLD)
	boostLabel.Visible = false

	-- Left side, under the Roblox menu, above the thumbstick.
	comboLabel = label({
		Name = "Combo",
		Visible = false,
		ZIndex = 9,
	})
	textLimit(comboLabel, 34)
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
	local resetB, _resetIcon, resetW = sideButton("🔄", "RESET", GREY, function()
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
	-- Gold tank that fills with coins; the button glows when it's full.
	resetFill = Instance.new("Frame")
	resetFill.Name = "Fill"
	resetFill.BackgroundColor3 = UiStyle.GOLD
	resetFill.BackgroundTransparency = 0.15
	resetFill.Size = UDim2.fromScale(0, 1)
	resetFill.ZIndex = 2
	corner(resetFill, 0.2)
	resetFill.Parent = resetButton
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
		if open then
			infoLabel.Visible = false
			boostLabel.Visible = false
		else
			setStrip(infoLabel, infoLabel.Text)
			setStrip(boostLabel, boostLabel.Text)
		end
	end)

	shownCash.Changed:Connect(function(value: number)
		cashLabel.Text = `${Format.short(value)}`
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
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
			local text = HudText.boost(mega.taps, mega.goal, left)
			boostLabel.TextColor3 = if left > 0 then UiStyle.GOLD else WHITE
			if text ~= boostLabel.Text then
				setStrip(boostLabel, text)
			end
			task.wait(0.25)
		end
	end)
end

return Hud
