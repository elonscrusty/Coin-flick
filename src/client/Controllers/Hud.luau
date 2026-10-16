--!strict
-- Phone-first HUD: cash + hat points on top, big SHOP / RESET / TOP / VIEW
-- buttons on the right (clear of the thumbstick and jump button), combo
-- counter and mega boost timer. The shop, popups, top 10 boards, toasts and
-- banners are in Panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
local Panels = require(script.Parent.Panels)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)

type Snapshot = Types.Snapshot

local Hud = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(45, 30, 20)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREEN = Color3.fromRGB(70, 210, 110)
local PURPLE = Color3.fromRGB(170, 110, 255)
local ORANGE = Color3.fromRGB(255, 160, 40)
local BLUE = Color3.fromRGB(60, 170, 255)
local GREY = Color3.fromRGB(170, 170, 175)

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCY = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COUNT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Small UI helpers -------------------------------------------------------

local function corner(parent: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.25, 0)
	c.Parent = parent
end

local function stroke(parent: GuiObject, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function textLimit(label: TextLabel | TextButton, max: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = max
	c.MinTextSize = 10
	c.Parent = label
end

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = WHITE
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = 0.2
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

-- A chunky cartoon button that pops when pressed.
local function button(text: string, color: Color3, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextScaled = true
	b.Text = text
	b.TextColor3 = WHITE
	b.TextStrokeColor3 = INK
	b.TextStrokeTransparency = 0.2
	corner(b)
	stroke(b)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, FAST, { Scale = 0.9 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, BOUNCY, { Scale = 1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, BOUNCY, { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onPress)
	return b
end

local function popScale(scale: UIScale, amount: number)
	scale.Scale = amount
	TweenService:Create(scale, BOUNCY, { Scale = 1 }):Play()
end

-- Build ---------------------------------------------------------------------

local gui: ScreenGui
local cashLabel: TextLabel
local cashScale: UIScale
local hatLabel: TextLabel
local hatScale: UIScale
local infoLabel: TextLabel
local resetButton: TextButton
local resetPulse: Tween?
local boostLabel: TextLabel
local boostEnds = 0
local comboLabel: TextLabel
local comboScale: UIScale
local comboToken = 0

local shownCash = Instance.new("NumberValue")
local render: (Snapshot) -> ()

-- Combo counter: grows with every quick tap, fades when the chain breaks.
local function showCombo(combo: number)
	comboToken += 1
	local token = comboToken
	comboLabel.Text = `🔥 x{combo}\nCOMBO`
	comboLabel.TextColor3 = Color3.fromHSV(math.max(0, 0.15 - combo * 0.007), 0.85, 1)
	comboLabel.TextTransparency = 0
	comboLabel.TextStrokeTransparency = 0
	comboLabel.Visible = true
	popScale(comboScale, 1 + math.min(0.6, combo * 0.03))
	if combo % 5 == 0 then
		Sounds.play("Combo", 0.5, 1 + math.min(1, combo / 20))
	end
	task.delay(Config.COMBO_WINDOW, function()
		if token ~= comboToken then
			return
		end
		local fade = TweenService:Create(comboLabel, COUNT, { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if token == comboToken then
			comboLabel.Visible = false
		end
	end)
end

local function sideButton(order: number, text: string, color: Color3, onPress: () -> ()): TextButton
	local b = button(text, color, onPress)
	b.LayoutOrder = order
	b.Size = UDim2.fromScale(1, 0.22)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = b
	textLimit(b, 22)
	return b
end

local function buildCheats(parent: ScreenGui)
	local cheat = ClientNet.find("Cheat")
	if not cheat then
		return -- only exists in Studio
	end
	local frame = Instance.new("Frame")
	frame.Name = "StudioCheats"
	frame.BackgroundTransparency = 1
	-- Top-left, under the Roblox menu, clear of the combo counter and thumbstick.
	frame.Position = UDim2.fromOffset(8, 56)
	frame.Size = UDim2.fromOffset(72, 190)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	for _, item in { { "+1M", "cash" }, { "FILL", "fill" }, { "RARE", "rare" }, { "MEGA", "mega" }, { "WIPE", "wipe" } } do
		local b = button(`🧪{item[1]}`, GREY, function()
			cheat:FireServer(item[2])
		end)
		b.Size = UDim2.fromOffset(72, 32)
		b.Parent = frame
	end
	frame.Parent = parent
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
	infoLabel.Text =
		`${Format.short(s.cashPerHeads)} per heads  •  {Format.percent(s.headsChance)} heads  •  {s.coinCount}/{Config.MAX_COINS} coins`

	resetButton.BackgroundColor3 = if s.tableFull then ORANGE else Color3.fromRGB(205, 150, 90)
	resetButton.Text = if s.tableFull then "🔄\nRESET!" else `🔄\n{s.coinCount}/{Config.MAX_COINS}`
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

function Hud.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoinFlickHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	-- Top bar: cash + hat points.
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 6)
	top.Size = UDim2.fromScale(0.6, 0.11)
	top.BackgroundTransparency = 1
	local topSize = Instance.new("UISizeConstraint")
	topSize.MaxSize = Vector2.new(520, 64)
	topSize.MinSize = Vector2.new(240, 38)
	topSize.Parent = top
	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.Padding = UDim.new(0.03, 0)
	topLayout.Parent = top

	local function pill(color: Color3, width: number): (Frame, TextLabel, UIScale)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(width, 1)
		frame.BackgroundColor3 = color
		corner(frame, 0.5)
		stroke(frame, 3)
		local scale = Instance.new("UIScale")
		scale.Parent = frame
		local text = label({ Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) })
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

	infoLabel = label({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.11, 12),
		Size = UDim2.fromScale(0.6, 0.045),
		Text = "Tap a coin to flip it!",
	})
	textLimit(infoLabel, 20)
	-- Dark see-through strip so the white text reads on bright sky.
	infoLabel.BackgroundColor3 = INK
	infoLabel.BackgroundTransparency = 0.45
	corner(infoLabel, 0.5)
	infoLabel.Parent = gui

	boostLabel = label({
		Name = "Boost",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.155, 14),
		Size = UDim2.fromScale(0.4, 0.05),
		TextColor3 = Color3.fromRGB(255, 220, 60),
		Visible = false,
	})
	textLimit(boostLabel, 20)
	boostLabel.BackgroundColor3 = INK
	boostLabel.BackgroundTransparency = 0.45
	corner(boostLabel, 0.5)
	boostLabel.Parent = gui

	-- Left side, above the phone thumbstick.
	comboLabel = label({
		Name = "Combo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.56, 0),
		Size = UDim2.fromScale(0.16, 0.16),
		Visible = false,
		ZIndex = 9,
	})
	textLimit(comboLabel, 34)
	comboScale = Instance.new("UIScale")
	comboScale.Parent = comboLabel
	comboLabel.Parent = gui

	-- Right side: big buttons, above the phone jump button.
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.AnchorPoint = Vector2.new(1, 0.5)
	side.Position = UDim2.new(1, -10, 0.45, 0)
	side.Size = UDim2.fromScale(0.2, 0.64)
	side.BackgroundTransparency = 1
	local sideLayout = Instance.new("UIListLayout")
	sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sideLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	sideLayout.Padding = UDim.new(0.04, 0)
	sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sideLayout.Parent = side
	local shopButton = sideButton(1, "🛒\nSHOP", GREEN, function()
		Sounds.play("Tap", 0.4)
		Panels.open("shop")
	end)
	shopButton.Parent = side
	resetButton = sideButton(2, "🔄\nRESET", GREY, function()
		Sounds.play("Tap", 0.4)
		local s = State.get()
		if s and s.tableFull then
			Panels.open("reset")
		else
			local count = if s then s.coinCount else 1
			Panels.toast(`Fill your table first! ({count}/{Config.MAX_COINS} coins)`)
		end
	end)
	resetButton.Parent = side
	local topButton = sideButton(3, "🏆\nTOP", PURPLE, function()
		Sounds.play("Tap", 0.4)
		Panels.open("top")
	end)
	topButton.Parent = side
	local viewButton: TextButton
	viewButton = sideButton(4, "🔍\nZOOM", BLUE, function()
		local tableView = CameraView.toggle()
		viewButton.Text = if tableView then "🏃\nWALK" else "🔍\nZOOM"
	end)
	viewButton.Parent = side
	side.Parent = gui

	buildCheats(gui)

	shownCash.Changed:Connect(function(value: number)
		cashLabel.Text = `${Format.short(value)}`
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function Hud.start()
	State.onChange(render)
	ClientNet.event("Flipped").OnClientEvent:Connect(function(ev: Types.FlipEvent)
		if ev.ownerId == player.UserId and ev.combo >= 2 then
			showCombo(ev.combo)
		end
	end)
	local megaText = ""
	ClientNet.event("MegaState").OnClientEvent:Connect(function(state: Types.MegaState)
		boostEnds = os.clock() + state.boostLeft
		megaText = `🌟 Mega coin {state.taps}/{state.goal}  •  tap it together!`
	end)
	task.spawn(function()
		while true do
			local left = math.ceil(boostEnds - os.clock())
			if left > 0 then
				boostLabel.Text = `⚡ MEGA BOOST: 2x CASH  {left // 60}:{string.format("%02d", left % 60)}`
				boostLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
			else
				boostLabel.Text = megaText
				boostLabel.TextColor3 = WHITE
			end
			boostLabel.Visible = boostLabel.Text ~= ""
			task.wait(0.25)
		end
	end)
end

return Hud
