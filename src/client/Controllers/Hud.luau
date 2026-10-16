--!strict
-- Phone-first HUD: cash + hat points on top, big SHOP / RESET / VIEW buttons
-- on the right (clear of the thumbstick and jump button), the upgrade shop,
-- the reset popup, and little toast messages.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
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
local RED = Color3.fromRGB(255, 90, 90)
local GREY = Color3.fromRGB(170, 170, 175)
local PANEL = Color3.fromRGB(255, 248, 230)

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
local toastLabel: TextLabel
local shopPanel: Frame
local resetPanel: Frame
local resetBody: TextLabel
local resetButton: TextButton
local resetPulse: Tween?
local shopCards: { [string]: { level: TextLabel, buy: TextButton } } = {}
local helperCard: { level: TextLabel, buy: TextButton }

local shownCash = Instance.new("NumberValue")
local toastToken = 0

local function toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or WHITE
	toastLabel.Visible = true
	toastLabel.Position = UDim2.fromScale(0.5, 0.12)
	toastLabel.TextTransparency = 0
	toastLabel.TextStrokeTransparency = 0.2
	TweenService:Create(toastLabel, BOUNCY, { Position = UDim2.fromScale(0.5, 0.17) }):Play()
	task.delay(2.6, function()
		if token ~= toastToken then
			return
		end
		local fade = TweenService:Create(toastLabel, COUNT, { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local function openPanel(panel: Frame)
	local scale = panel:FindFirstChildOfClass("UIScale")
	panel.Visible = true
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, BOUNCY, { Scale = 1 }):Play()
	end
end

local function closePanels()
	shopPanel.Visible = false
	resetPanel.Visible = false
end

local function makePanel(name: string, title: string): (Frame, Frame)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.55)
	panel.Size = UDim2.fromScale(0.62, 0.8)
	panel.BackgroundColor3 = PANEL
	panel.Visible = false
	panel.ZIndex = 5
	corner(panel, 0.06)
	stroke(panel, 4)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(560, 460)
	size.MinSize = Vector2.new(300, 220)
	size.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local header = label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -70, 0, 44),
		Position = UDim2.fromOffset(16, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = ORANGE,
		ZIndex = 6,
	})
	textLimit(header, 36)
	header.Parent = panel

	local close = button("X", RED, closePanels)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Size = UDim2.fromOffset(48, 48) -- big enough for a thumb
	close.ZIndex = 7
	close.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 62)
	body.Size = UDim2.new(1, -24, 1, -74)
	body.ZIndex = 6
	body.Parent = panel
	panel.Parent = gui
	return panel, body
end

local function shopCard(parent: ScrollingFrame, order: number, icon: string, name: string, onBuy: () -> ())
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -10, 0, 78)
	card.BackgroundColor3 = WHITE
	card.ZIndex = 6
	corner(card, 0.18)
	stroke(card, 2)

	local iconLabel = label({
		Text = icon,
		Size = UDim2.new(0, 56, 1, -12),
		Position = UDim2.fromOffset(8, 6),
		ZIndex = 7,
	})
	iconLabel.Parent = card

	local title = label({
		Text = name,
		Size = UDim2.new(0.62, -76, 0.45, 0),
		Position = UDim2.fromOffset(70, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = INK,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	textLimit(title, 26)
	title.Parent = card

	local level = label({
		Name = "Level",
		Text = "",
		Size = UDim2.new(0.62, -76, 0.38, 0),
		Position = UDim2.new(0, 70, 0.52, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(110, 100, 90),
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	textLimit(level, 18)
	level.Parent = card

	local buy = button("$0", GREEN, onBuy)
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -8, 0.5, 0)
	buy.Size = UDim2.new(0.36, 0, 1, -16)
	buy.ZIndex = 8
	buy.Parent = card
	textLimit(buy, 28)

	card.Parent = parent
	return { level = level, buy = buy }
end

local function buildShop()
	local panel, body = makePanel("Shop", "UPGRADES")
	shopPanel = panel
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = list
	list.Parent = body

	local buyRemote = ClientNet.event("BuyUpgrade")
	for i, id in Config.UPGRADE_ORDER do
		local def = Config.Upgrades[id]
		shopCards[id] = shopCard(list, i, def.icon, def.name, function()
			buyRemote:FireServer(id)
		end)
	end
	local helperRemote = ClientNet.event("BuyHelper")
	helperCard = shopCard(list, 100, "👷", "Helper Guy", function()
		helperRemote:FireServer()
	end)
end

local function buildReset()
	local panel, body = makePanel("Reset", "RESET TABLE?")
	resetPanel = panel
	panel.Size = UDim2.fromScale(0.55, 0.66)
	resetBody = label({
		Size = UDim2.fromScale(1, 0.62),
		TextColor3 = INK,
		TextStrokeTransparency = 1,
		TextWrapped = true,
		ZIndex = 7,
	})
	textLimit(resetBody, 24)
	resetBody.Parent = body

	local yes = button("YES!", GREEN, function()
		ClientNet.event("ResetTable"):FireServer()
		closePanels()
	end)
	yes.Size = UDim2.fromScale(0.46, 0.3)
	yes.Position = UDim2.fromScale(0, 0.68)
	yes.ZIndex = 8
	yes.Parent = body
	local no = button("NO", RED, closePanels)
	no.Size = UDim2.fromScale(0.46, 0.3)
	no.Position = UDim2.fromScale(0.54, 0.68)
	no.ZIndex = 8
	no.Parent = body
end

local function sideButton(order: number, text: string, color: Color3, onPress: () -> ()): TextButton
	local b = button(text, color, onPress)
	b.LayoutOrder = order
	b.Size = UDim2.fromScale(1, 0.3)
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
	frame.Position = UDim2.new(0, 8, 0.2, 0)
	frame.Size = UDim2.fromOffset(90, 150)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	for _, item in { { "+1M", "cash" }, { "FILL", "fill" }, { "WIPE", "wipe" } } do
		local b = button(`🧪{item[1]}`, GREY, function()
			cheat:FireServer(item[2])
		end)
		b.Size = UDim2.fromOffset(90, 40)
		b.Parent = frame
	end
	frame.Parent = parent
end

local function render(s: Snapshot)
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

	for id, card in shopCards do
		local level = s.upgrades[id :: Types.UpgradeId]
		local def = Config.Upgrades[id]
		local cost = Economy.upgradeCost(id, level)
		card.level.Text = `Level {level}/{def.maxLevel}  •  {def.desc}`
		if cost then
			card.buy.Text = `${Format.short(cost)}`
			card.buy.BackgroundColor3 = if s.cash >= cost then GREEN else GREY
		else
			card.buy.Text = "MAX"
			card.buy.BackgroundColor3 = BLUE
		end
	end
	local helperCost = Economy.helperCost(s.helpers)
	helperCard.level.Text = `{s.helpers}/{Config.MAX_HELPERS}  •  Flips for you, even when you're away`
	if helperCost then
		helperCard.buy.Text = `${Format.short(helperCost)}`
		helperCard.buy.BackgroundColor3 = if s.cash >= helperCost then GREEN else GREY
	else
		helperCard.buy.Text = "MAX"
		helperCard.buy.BackgroundColor3 = BLUE
	end

	resetBody.Text =
		`You LOSE: cash and upgrades\nYou KEEP: helper guys and 🎩\nYou GET: cash x{s.resetBonus} forever + a new table!`
	resetButton.BackgroundColor3 = if s.tableFull then ORANGE else GREY
	if s.tableFull and not resetPulse then
		local scale = resetButton:FindFirstChildOfClass("UIScale")
		if scale then
			local tween = TweenService:Create(
				scale,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.12 }
			)
			tween:Play()
			resetPulse = tween
		end
	elseif not s.tableFull and resetPulse then
		resetPulse:Cancel()
		resetPulse = nil
		local scale = resetButton:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1
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
	infoLabel.Parent = gui

	toastLabel = label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(0.7, 0.07),
		Visible = false,
		ZIndex = 10,
	})
	textLimit(toastLabel, 30)
	toastLabel.Parent = gui

	-- Right side: big buttons, above the phone jump button.
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.AnchorPoint = Vector2.new(1, 0.5)
	side.Position = UDim2.new(1, -10, 0.42, 0)
	side.Size = UDim2.fromScale(0.2, 0.52)
	side.BackgroundTransparency = 1
	local sideLayout = Instance.new("UIListLayout")
	sideLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sideLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	sideLayout.Padding = UDim.new(0.04, 0)
	sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sideLayout.Parent = side
	local shopButton = sideButton(1, "🛒\nSHOP", GREEN, function()
		Sounds.play("Tap", 0.4)
		closePanels()
		openPanel(shopPanel)
	end)
	shopButton.Parent = side
	resetButton = sideButton(2, "🔄\nRESET", GREY, function()
		Sounds.play("Tap", 0.4)
		local s = State.get()
		if s and s.tableFull then
			closePanels()
			openPanel(resetPanel)
		else
			local count = if s then s.coinCount else 1
			toast(`Fill your table first! ({count}/{Config.MAX_COINS} coins)`)
		end
	end)
	resetButton.Parent = side
	local viewButton = sideButton(3, "👀\nVIEW", BLUE, function()
		local tableView = CameraView.toggle()
		toast(if tableView then "Table view" else "Walk around view")
	end)
	viewButton.Parent = side
	side.Parent = gui

	buildShop()
	buildReset()
	buildCheats(gui)

	shownCash.Changed:Connect(function(value: number)
		cashLabel.Text = `${Format.short(value)}`
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function Hud.start()
	State.onChange(render)
	ClientNet.event("Notice").OnClientEvent:Connect(function(notice: Types.Notice)
		if notice.kind == "reset" then
			Sounds.play("Reset", 0.8)
			CameraView.shake(0.35, 0.5)
			toast(notice.text, ORANGE)
		elseif notice.kind == "bought" then
			Sounds.play("Buy", 0.6)
			toast(notice.text, Color3.fromRGB(150, 255, 150))
		else
			toast(notice.text)
		end
	end)
end

return Hud
