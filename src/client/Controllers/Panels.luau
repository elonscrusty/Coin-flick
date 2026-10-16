--!strict
-- Everything that pops up over the game: the SHOP (coins, crew, hats, more),
-- the RESET popup, the TOP 10 boards, little toasts, and the big banners for
-- rare coins and the mega flip. What each card says comes from the pure
-- shared/Util/PanelView (tested); this file only draws it.
--
-- Panels live in their own ScreenGui above the HUD, with a dim backdrop, so
-- nothing on the HUD ever pokes out from behind an open panel.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Kit = require(script.Parent.Parent.Ui.Kit)
local Icons = require(script.Parent.Parent.Ui.Icons)
local CameraView = require(script.Parent.CameraView)
local Sounds = require(script.Parent.Sounds)
local State = require(script.Parent.State)

type Snapshot = Types.Snapshot

local Panels = {}

local player = Players.LocalPlayer

local CARD_HEIGHT = 66
local SCROLLBAR = 10
local TAB_COLORS: { [string]: Color3 } = {
	upgrades = Kit.GOLD,
	helpers = Kit.BLUE,
	hats = Kit.PURPLE,
	robux = Color3.fromRGB(255, 110, 190),
	flips = Kit.ORANGE,
	biggestFlip = Kit.GREEN,
	resets = Kit.BLUE,
}
local MEDAL_COLORS: { [string]: Color3 } = {
	gold = Kit.GOLD,
	silver = Kit.SILVER,
	bronze = Kit.BRONZE,
	none = Kit.SLATE,
}
local RESET_COLORS: { [string]: Color3 } = {
	lose = Kit.RED,
	keep = Kit.BLUE,
	get = Kit.GREEN,
	need = Kit.SLATE,
}

type CardUi = {
	frame: Frame,
	title: TextLabel,
	line: TextLabel,
	badge: TextLabel,
	buy: TextButton,
	team: TextButton?,
	scale: UIScale,
	outline: UIStroke,
}

local panelGui: ScreenGui
local popGui: ScreenGui
local backdrop: TextButton
local panels: { [string]: Frame } = {}
local openName: string? = nil
local openListeners: { (boolean) -> () } = {}

local cards: { [string]: { [string]: CardUi } } = { upgrades = {}, helpers = {}, hats = {}, robux = {} }
local icons: { [string]: { ViewportFrame } } = { upgrades = {}, helpers = {}, hats = {}, robux = {} }
local shopTabs: { [string]: TextButton } = {}
local shopLists: { [string]: ScrollingFrame } = {}
local shopTab = "upgrades"
local helperHeader: TextLabel
local lastPressed: CardUi? = nil

local boards: Types.Leaderboards = {}
local boardShown = "flips"
local boardTabs: { [string]: TextButton } = {}
local boardRows: { { frame: Frame, medal: TextLabel, name: TextLabel, value: TextLabel } } = {}
local myRow: TextLabel

local resetLines: { TextLabel } = {}
local resetYes: TextButton

local toastLabel: TextLabel
local toastToken = 0
local banner: Frame
local bannerTitle: TextLabel
local bannerText: TextLabel
local bannerStroke: UIStroke
local bannerScale: UIScale
local bannerToken = 0
local flash: Frame

local prices: { [string]: string } = {}
local lastHat: string? = nil

-- Open / close -----------------------------------------------------------------

local function setOpen(name: string?)
	local was = openName ~= nil
	openName = name
	for key, panel in panels do
		panel.Visible = key == name
	end
	backdrop.Visible = name ~= nil
	if (name ~= nil) ~= was then
		for _, fn in openListeners do
			task.spawn(fn, name ~= nil)
		end
	end
end

function Panels.anyOpen(): boolean
	return openName ~= nil
end

-- fn(true) when a panel opens, fn(false) when the last one closes.
function Panels.onOpenChanged(fn: (boolean) -> ())
	table.insert(openListeners, fn)
end

function Panels.closeAll()
	setOpen(nil)
end

local onShopOpen: () -> () = function() end

function Panels.open(name: string)
	local panel = panels[name]
	if not panel then
		return
	end
	if name == "shop" then
		onShopOpen()
	end
	local narrow = panelGui.AbsoluteSize.X < 700
	panel.Size = UDim2.new(if narrow then 0.94 else (if name == "reset" then 0.5 else 0.64), 0, if name == "reset" then 0.7 else 0.78, -8)
	setOpen(name)
	local scale = panel:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, Kit.BOUNCY, { Scale = 1 }):Play()
	end
end

-- Toasts and banners -------------------------------------------------------------

function Panels.toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or Kit.WHITE
	-- Under an open panel, else low in the middle (between thumbstick and jump).
	local y = if openName then 0.93 else 0.84
	toastLabel.Position = UDim2.fromScale(0.5, y + 0.03)
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.12
	local stroke = toastLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	TweenService:Create(toastLabel, Kit.BOUNCY, { Position = UDim2.fromScale(0.5, y) }):Play()
	task.delay(2.6, function()
		if token ~= toastToken then
			return
		end
		local fade = TweenService:Create(toastLabel, Kit.COUNT, { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		if stroke then
			TweenService:Create(stroke, Kit.COUNT, { Transparency = 1 }):Play()
		end
		fade.Completed:Wait()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local function confetti(count: number)
	local colors = { Kit.GOLD, Kit.GREEN, Kit.BLUE, Kit.RED, Kit.PURPLE, Color3.fromRGB(255, 110, 190) }
	for i = 1, count do
		local bit = Instance.new("Frame")
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Position = UDim2.fromScale(0.5, 0.3)
		bit.Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20))
		bit.Rotation = math.random(0, 360)
		bit.BackgroundColor3 = colors[(i % #colors) + 1]
		bit.BorderSizePixel = 0
		bit.ZIndex = 30
		Kit.corner(bit, 0.3)
		bit.Parent = popGui
		local angle = math.random() * math.pi * 2
		local reach = 0.15 + math.random() * 0.3
		local target = UDim2.fromScale(0.5 + math.cos(angle) * reach, 0.3 + math.sin(angle) * reach * 0.8 + 0.15)
		local t = TweenInfo.new(0.9 + math.random() * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(bit, t, { Position = target, Rotation = bit.Rotation + 360, BackgroundTransparency = 1 }):Play()
		task.delay(1.5, function()
			bit:Destroy()
		end)
	end
end

-- Big banner near the top: rare coins (whole server) and the mega flip payout.
-- A new banner replaces the old one at once, so the words always match the coin.
local function showBanner(title: string, text: string, color: Color3, rainbow: boolean, seconds: number)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerText.Text = text
	bannerStroke.Color = color
	banner.Visible = true
	banner.BackgroundTransparency = 0.1
	bannerTitle.TextTransparency = 0
	bannerText.TextTransparency = 0
	bannerScale.Scale = 0.3
	TweenService:Create(bannerScale, Kit.BOUNCY, { Scale = 1 }):Play()
	task.spawn(function()
		local started = os.clock()
		while token == bannerToken and os.clock() - started < seconds do
			if rainbow then
				local c = Color3.fromHSV((os.clock() * 0.8) % 1, 0.75, 1)
				bannerTitle.TextColor3 = c
				bannerStroke.Color = c
			end
			task.wait()
		end
		if token ~= bannerToken then
			return
		end
		local t = TweenService:Create(bannerScale, Kit.FAST, { Scale = 0.6 })
		TweenService:Create(banner, Kit.FAST, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerTitle, Kit.FAST, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerText, Kit.FAST, { TextTransparency = 1 }):Play()
		t:Play()
		t.Completed:Wait()
		if token == bannerToken then
			banner.Visible = false
		end
	end)
end

local function screenFlash()
	flash.Visible = true
	flash.BackgroundTransparency = 0.35
	local t = TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
	t:Play()
	t.Completed:Connect(function()
		flash.Visible = false
	end)
end

local function shout(notice: Types.Notice)
	local def = notice.rarity and Economy.rarityDef(notice.rarity)
	local name = if def then def.name else "RARE"
	showBanner(`{name} COIN!`, notice.text, if def then def.color else Kit.GOLD, notice.rarity == "rainbow", 3.5)
	if notice.rarity == "giant" then
		confetti(30)
	end
	if notice.ownerId ~= player.UserId then
		Sounds.play("Rare", 0.5) -- the flipper already hears it from their coin
	end
end

-- Building blocks ------------------------------------------------------------------

local function makePanel(name: string, title: string, color: Color3, maxSize: Vector2): (Frame, Frame, TextLabel)
	local panel = Instance.new("Frame")
	panel.Name = name
	-- Starts under the cash bar and ends above the toast strip.
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.13, 8)
	panel.Size = UDim2.new(0.64, 0, 0.78, -8)
	panel.BackgroundColor3 = Kit.PANEL
	panel.Visible = false
	panel.ZIndex = 5
	Kit.corner(panel, 0.06)
	Kit.stroke(panel, 4)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = maxSize
	size.MinSize = Vector2.new(300, 220)
	size.Parent = panel
	Instance.new("UIScale").Parent = panel

	-- Colored header ribbon with a big outlined title.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.Size = UDim2.new(1, 0, 0, 46)
	ribbon.BackgroundColor3 = color
	ribbon.ZIndex = 6
	Kit.corner(ribbon, 0.3)
	ribbon.Parent = panel
	local ribbonFill = Instance.new("Frame") -- squares off the ribbon's bottom corners
	ribbonFill.Size = UDim2.new(1, 0, 0.4, 0)
	ribbonFill.Position = UDim2.fromScale(0, 0.6)
	ribbonFill.BackgroundColor3 = color
	ribbonFill.BorderSizePixel = 0
	ribbonFill.ZIndex = 6
	ribbonFill.Parent = ribbon

	local header = Kit.label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -84, 0, 36),
		Position = UDim2.fromOffset(18, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	Kit.outline(header, 3)
	Kit.textLimit(header, 34)
	header.Parent = panel

	local close = Kit.button("X", Kit.RED, function()
		Sounds.play("Tap", 0.4)
		Panels.closeAll()
	end)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 4)
	close.Size = UDim2.fromOffset(40, 40) -- big enough for a thumb
	close.ZIndex = 8
	Kit.textLimit(close, 26)
	close.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 54)
	body.Size = UDim2.new(1, -24, 1, -62)
	body.ZIndex = 6
	body.Parent = panel
	panel.Parent = panelGui
	return panel, body, header
end

-- A scroll list with room for its scrollbar (rows never get cut on the right),
-- padding top and bottom, and a fade + arrow when more rows are below.
local function scrollList(parent: Frame, top: number, bottom: number?): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, top)
	list.Size = UDim2.new(1, 0, 1, -top - (bottom or 0))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = Kit.ORANGE
	list.ScrollBarImageTransparency = 0
	list.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 28) -- the last row can scroll clear of the fade
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = list
	list.Parent = parent

	local fade = Instance.new("Frame")
	fade.Name = "MoreBelow"
	fade.AnchorPoint = Vector2.new(0, 1)
	fade.Position = UDim2.new(0, 0, 1, -(bottom or 0))
	fade.Size = UDim2.new(1, -SCROLLBAR, 0, 30)
	fade.BackgroundColor3 = Kit.PANEL
	fade.BorderSizePixel = 0
	fade.ZIndex = 9
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new(1, 0)
	gradient.Parent = fade
	local arrow = Kit.label({
		Text = "▼",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(28, 22),
		TextColor3 = Kit.ORANGE,
		ZIndex = 10,
	})
	Kit.outline(arrow, 2)
	arrow.Parent = fade
	fade.Parent = parent
	local function update()
		local maxY = list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y
		fade.Visible = list.Visible and maxY > 4 and list.CanvasPosition.Y < maxY - 4
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
	list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update)
	list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update)
	list:GetPropertyChangedSignal("Visible"):Connect(update)
	return list
end

-- A row of tabs, each in its own color: bright when picked, pale when not.
local function tabRow(parent: Frame, tabs: { { string } }, onPick: (string) -> ()): { [string]: TextButton }
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundTransparency = 1
	row.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local buttons: { [string]: TextButton } = {}
	for i, tab in tabs do
		local key = tab[1]
		local b = Kit.button(tab[2], TAB_COLORS[key] or Kit.ORANGE, function()
			Sounds.play("Tap", 0.4)
			onPick(key)
		end)
		b.Name = `Tab_{key}`
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #tabs, -6, 1, 0)
		b.ZIndex = 7
		Kit.textLimit(b, 22)
		b.Parent = row
		buttons[key] = b
	end
	row.Parent = parent
	return buttons
end

local function paintTabs(buttons: { [string]: TextButton }, picked: string)
	for key, b in buttons do
		local color = TAB_COLORS[key] or Kit.ORANGE
		local on = key == picked
		b.BackgroundColor3 = if on then color else color:Lerp(Kit.WHITE, 0.5)
		for _, child in b:GetChildren() do
			if child:IsA("UIStroke") then
				if child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
					child.Thickness = if on then 4 else 2
				else
					child.Transparency = if on then 0 else 0.3
				end
			end
		end
	end
end

local function newCard(list: ScrollingFrame, id: string, icon: GuiObject?, withTeam: boolean, onBuy: () -> (), onTeam: (() -> ())?): CardUi
	local frame = Instance.new("Frame")
	frame.Name = id
	frame.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	frame.BackgroundColor3 = Kit.CARD
	frame.ZIndex = 6
	Kit.corner(frame, 0.18)
	local outline = Kit.stroke(frame, 2)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.Position = UDim2.fromOffset(5, 5)
	iconBox.Size = UDim2.fromOffset(CARD_HEIGHT - 10, CARD_HEIGHT - 10)
	iconBox.BackgroundColor3 = Color3.fromRGB(255, 236, 190)
	iconBox.ZIndex = 7
	Kit.corner(iconBox, 0.25)
	iconBox.Parent = frame
	if icon then
		icon.Size = UDim2.fromScale(1, 1)
		icon.ZIndex = 8
		icon.Parent = iconBox
	end

	-- Buttons on the right; the text area fills the rest.
	local buyWidth = 0.3
	local teamWidth = if withTeam then 0.22 else 0
	local textLeft = CARD_HEIGHT + 2
	local textRight = buyWidth + teamWidth

	local title = Kit.label({
		Name = "Title",
		Size = UDim2.new(1 - textRight, -textLeft - 8, 0, 26),
		Position = UDim2.fromOffset(textLeft, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.INK,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	Kit.textLimit(title, 24)
	title.TextWrapped = false
	title:SetAttribute("BaseWidth", -textLeft - 8)
	title:SetAttribute("BaseScale", 1 - textRight)
	title.Parent = frame

	local badge = Kit.label({
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1 - textRight, -8, 0, 8),
		Size = UDim2.fromOffset(66, 20),
		BackgroundColor3 = Kit.SLATE,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 8,
	})
	Kit.corner(badge, 0.5)
	Kit.outline(badge, 1.5)
	Kit.textLimit(badge, 16)
	Kit.padding(badge, UDim.new(0, 6), UDim.new(0, 2))
	badge.Parent = frame

	local line = Kit.label({
		Name = "Line",
		Size = UDim2.new(1 - textRight, -textLeft - 8, 0, 22),
		Position = UDim2.fromOffset(textLeft, CARD_HEIGHT - 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Kit.MUTED,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	Kit.textLimit(line, 18, 12)
	line.TextWrapped = false
	line.Parent = frame

	local buy = Kit.button("", Kit.GREEN, function()
		Sounds.play("Tap", 0.4)
		onBuy()
	end)
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -8, 0.5, 0)
	buy.Size = UDim2.new(buyWidth, -10, 1, -16)
	buy.ZIndex = 8
	Kit.textLimit(buy, 24)
	buy.Parent = frame

	local team: TextButton? = nil
	if onTeam then
		local t = Kit.button("", Kit.BLUE, function()
			Sounds.play("Tap", 0.4)
			onTeam()
		end)
		t.Name = "Team"
		t.AnchorPoint = Vector2.new(1, 0.5)
		t.Position = UDim2.new(1 - buyWidth, -10, 0.5, 0)
		t.Size = UDim2.new(teamWidth, -8, 1, -24)
		t.ZIndex = 8
		Kit.textLimit(t, 18)
		t.Parent = frame
		team = t
	end

	frame.Parent = list
	local ui: CardUi = {
		frame = frame,
		title = title,
		line = line,
		badge = badge,
		buy = buy,
		team = team,
		scale = scale,
		outline = outline,
	}
	-- Remember which card was pressed, so its purchase can pop it.
	buy.Activated:Connect(function()
		lastPressed = ui
	end)
	return ui
end

local function paintCard(ui: CardUi, view: PanelView.Card)
	ui.frame.LayoutOrder = view.order
	ui.title.Text = view.title
	ui.line.Text = view.line
	ui.buy.Text = view.button
	Kit.applyLook(ui.buy, view.look)
	ui.badge.Visible = view.badge ~= nil
	local base = ui.title:GetAttribute("BaseWidth")
	local baseScale = ui.title:GetAttribute("BaseScale")
	if typeof(base) == "number" and typeof(baseScale) == "number" then
		ui.title.Size = UDim2.new(baseScale, base - (if view.badge then 74 else 0), 0, 26)
	end
	if view.badge then
		ui.badge.Text = view.badge
		ui.badge.BackgroundColor3 = if view.badge == "WORKING" then Kit.TEAL else Kit.SLATE
	end
	local team = ui.team
	if team then
		team.Visible = view.team ~= nil
		if view.team then
			team.Text = view.team.text
			Kit.applyLook(team, view.team.look)
		end
	end
	local highlight = view.look == "equipped" or (view.team ~= nil and view.team.look == "equipped")
	ui.outline.Color = if highlight then Kit.TEAL else Kit.INK
	ui.outline.Thickness = if highlight then 4 else 2
end

-- Shop ---------------------------------------------------------------------------

local function robuxPrice(key: string, id: number, kind: string)
	if id <= 0 or prices[key] then
		return
	end
	local info = if kind == "product" then Enum.InfoType.Product else Enum.InfoType.GamePass
	task.spawn(function()
		local ok, result = pcall(function()
			return MarketplaceService:GetProductInfo(id, info)
		end)
		if ok and typeof(result) == "table" and typeof(result.PriceInRobux) == "number" then
			prices[key] = `R$ {result.PriceInRobux}`
			local s = State.get()
			if s then
				Panels.render(s)
			end
		end
	end)
end

local function pickShopTab(key: string)
	shopTab = key
	paintTabs(shopTabs, key)
	for k, list in shopLists do
		list.Visible = k == key
	end
end

local function buildShop()
	local panel, body = makePanel("Shop", "SHOP", Kit.GREEN, Vector2.new(600, 470))
	panels.shop = panel
	local tabs: { { string } } = {}
	for _, key in PanelView.TAB_ORDER do
		table.insert(tabs, { key, PanelView.TAB_LABEL[key] })
	end
	shopTabs = tabRow(body, tabs, pickShopTab)

	-- COINS
	local list = scrollList(body, 44)
	shopLists.upgrades = list
	local buyRemote = ClientNet.event("BuyUpgrade")
	for _, id in Config.UPGRADE_ORDER do
		local icon = Icons.thing(id)
		cards.upgrades[id] = newCard(list, id, icon, false, function()
			buyRemote:FireServer(id)
		end)
		if icon then
			table.insert(icons.upgrades, icon)
		end
	end

	-- CREW: unlock with cash, level up, put to work.
	local crewList = scrollList(body, 44)
	shopLists.helpers = crewList
	helperHeader = Kit.label({
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Kit.INK,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	Kit.textLimit(helperHeader, 20)
	helperHeader.Parent = crewList
	local unlockRemote = ClientNet.event("BuyHelper")
	local levelRemote = ClientNet.event("LevelHelper")
	local teamRemote = ClientNet.event("TeamHelper")
	for _, def in Config.HelperTypes do
		local icon = Icons.helper(def)
		table.insert(icons.helpers, icon)
		cards.helpers[def.id] = newCard(crewList, def.id, icon, true, function()
			local s = State.get()
			if s and s.crew[def.id] then
				levelRemote:FireServer(def.id)
			elseif s and s.resets < def.resets then
				Sounds.play("Denied", 0.5)
				Panels.toast(`Reset {def.resets} time{if def.resets == 1 then "" else "s"} to meet {def.name}!`)
			else
				unlockRemote:FireServer(def.id)
			end
		end, function()
			local s = State.get()
			if s and s.crew[def.id] then
				teamRemote:FireServer(def.id, not table.find(s.team, def.id))
			end
		end)
	end

	-- HATS: buy with 🎩, tap again to wear or take off.
	local hatList = scrollList(body, 44)
	shopLists.hats = hatList
	local hatHeader = Kit.label({
		Name = "Header",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 22),
		Text = PanelView.HAT_HEADER,
		TextColor3 = Kit.INK,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	Kit.textLimit(hatHeader, 20)
	hatHeader.Parent = hatList
	local buyHat = ClientNet.event("BuyHat")
	local wearHat = ClientNet.event("WearHat")
	for _, def in Config.Hats do
		local icon = Icons.hat(def.id)
		if icon then
			table.insert(icons.hats, icon)
		end
		cards.hats[def.id] = newCard(hatList, def.id, icon, false, function()
			local s = State.get()
			if not s then
				return
			end
			if s.hat == def.id then
				wearHat:FireServer("")
			elseif table.find(s.hats, def.id) then
				wearHat:FireServer(def.id)
			else
				buyHat:FireServer(def.id)
			end
		end)
	end

	-- MORE (Robux). No random boxes. Hidden until something is for sale.
	local robuxList = scrollList(body, 44)
	shopLists.robux = robuxList
	local buyRobux = ClientNet.event("BuyRobux")
	local chooseSkin = ClientNet.event("ChooseSkin")
	for _, item in PanelView.robuxItems() do
		local icon = Icons.thing(item.key)
		if icon then
			table.insert(icons.robux, icon)
		end
		cards.robux[item.key] = newCard(robuxList, item.key, icon, false, function()
			local s = State.get()
			local skin = Economy.skinDef(item.key)
			if skin and s and s.passes[item.key] then
				chooseSkin:FireServer(if s.skin == item.key then "" else item.key)
			else
				buyRobux:FireServer(item.key)
			end
		end)
		robuxPrice(item.key, item.id, item.kind)
	end
	shopTabs.robux.Visible = PanelView.showRobuxTab(nil)

	pickShopTab("upgrades")
	onShopOpen = function()
		pickShopTab("upgrades")
		for _, l in shopLists do
			l.CanvasPosition = Vector2.zero
		end
	end
end

-- Top 10 ---------------------------------------------------------------------------

local function renderBoard()
	local rows = PanelView.boardRows(boardShown, boards[boardShown], player.DisplayName)
	for i, view in rows do
		local ui = boardRows[i]
		if not ui then
			continue
		end
		ui.medal.Text = view.rank
		ui.medal.BackgroundColor3 = MEDAL_COLORS[view.medal]
		ui.name.Text = view.name
		ui.name.TextColor3 = if view.empty then Kit.MUTED else Kit.INK
		ui.value.Text = view.value
		ui.frame.BackgroundColor3 = if view.me then Color3.fromRGB(200, 250, 200) else Kit.CARD
	end
	paintTabs(boardTabs, boardShown)
	local s = State.get()
	if s and myRow then
		local unit = PanelView.BOARD_UNITS[boardShown]
		myRow.Text = `YOU: {PanelView.myValue(boardShown, s)}{if unit ~= "" then " " .. unit else ""}  •  board updates every minute`
	end
end

local function buildTop()
	local panel, body = makePanel("Top", "TOP 10", Kit.PURPLE, Vector2.new(560, 470))
	panels.top = panel
	boardTabs = tabRow(body, PanelView.BOARD_TABS, function(key)
		boardShown = key
		renderBoard()
	end)
	local list = scrollList(body, 44, 34)
	for i = 1, Config.LEADERBOARD_SIZE do
		local frame = Instance.new("Frame")
		frame.Name = `Row{i}`
		frame.LayoutOrder = i
		frame.Size = UDim2.new(1, 0, 0, 36)
		frame.BackgroundColor3 = Kit.CARD
		frame.ZIndex = 7
		Kit.corner(frame, 0.3)
		Kit.stroke(frame, 2)
		local medal = Kit.label({
			Name = "Rank",
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.fromOffset(30, 30),
			BackgroundTransparency = 0,
			ZIndex = 8,
		})
		Kit.corner(medal, 0.5)
		Kit.outline(medal, 1.5)
		Kit.padding(medal, UDim.new(0, 4), UDim.new(0, 4))
		medal.Parent = frame
		local name = Kit.label({
			Name = "Name",
			Position = UDim2.fromOffset(42, 5),
			Size = UDim2.new(0.65, -46, 1, -10),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Kit.INK,
			TextStrokeTransparency = 1,
			ZIndex = 8,
		})
		Kit.textLimit(name, 20)
		name.Parent = frame
		local value = Kit.label({
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 5),
			Size = UDim2.new(0.35, -10, 1, -10),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Kit.INK,
			TextStrokeTransparency = 1,
			ZIndex = 8,
		})
		Kit.textLimit(value, 20)
		value.Parent = frame
		frame.Parent = list
		boardRows[i] = { frame = frame, medal = medal, name = name, value = value }
	end
	myRow = Kit.label({
		Name = "You",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Kit.GREEN,
		BackgroundTransparency = 0,
		ZIndex = 8,
	})
	Kit.corner(myRow, 0.3)
	Kit.outline(myRow, 2)
	Kit.padding(myRow, UDim.new(0, 10), UDim.new(0, 4))
	Kit.textLimit(myRow, 18)
	myRow.Parent = body
	renderBoard()
end

-- Reset popup ---------------------------------------------------------------------

local function buildReset()
	local panel, body = makePanel("Reset", "RESET TABLE?", Kit.ORANGE, Vector2.new(460, 340))
	panels.reset = panel
	panel.Size = UDim2.new(0.5, 0, 0.7, -8)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 0.7)
	holder.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.04, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	for i = 1, 4 do
		local line = Kit.label({
			Name = `Line{i}`,
			LayoutOrder = i,
			Size = UDim2.fromScale(1, 0.21),
			BackgroundTransparency = 0,
			ZIndex = 7,
		})
		Kit.corner(line, 0.35)
		Kit.outline(line, 2)
		Kit.padding(line, UDim.new(0, 10), UDim.new(0.12, 0))
		Kit.textLimit(line, 22)
		line.Parent = holder
		resetLines[i] = line
	end
	holder.Parent = body

	resetYes = Kit.button("YES!", Kit.GREEN, function()
		ClientNet.event("ResetTable"):FireServer()
		Panels.closeAll()
	end)
	resetYes.Size = UDim2.fromScale(0.47, 0.24)
	resetYes.Position = UDim2.fromScale(0, 0.76)
	resetYes.ZIndex = 8
	Kit.textLimit(resetYes, 28)
	resetYes.Parent = body
	local no = Kit.button("NO", Kit.RED, function()
		Sounds.play("Tap", 0.4)
		Panels.closeAll()
	end)
	no.Size = UDim2.fromScale(0.47, 0.24)
	no.Position = UDim2.fromScale(0.53, 0.76)
	no.ZIndex = 8
	Kit.textLimit(no, 28)
	no.Parent = body
end

-- Render ---------------------------------------------------------------------------

function Panels.render(s: Snapshot)
	for _, view in PanelView.upgradeCards(s) do
		paintCard(cards.upgrades[view.id], view)
	end
	helperHeader.Text = PanelView.helperHeader(s)
	for _, view in PanelView.helperCards(s) do
		paintCard(cards.helpers[view.id], view)
	end
	for _, view in PanelView.hatCards(s) do
		paintCard(cards.hats[view.id], view)
	end
	for _, view in PanelView.robuxCards(s, prices) do
		paintCard(cards.robux[view.id], view)
	end
	shopTabs.robux.Visible = PanelView.showRobuxTab(s)

	local lines = PanelView.resetLines(s)
	for i, line in resetLines do
		local view = lines[i]
		line.Size = UDim2.fromScale(1, if #lines >= 4 then 0.21 else 0.29) -- no empty gap with 3 lines
		line.Visible = view ~= nil
		if view then
			line.Text = view.text
			line.BackgroundColor3 = RESET_COLORS[view.kind]
		end
	end
	Kit.applyLook(resetYes, if s.tableFull then "buy" else "poor")

	-- Wearing a different hat: say so (the hat itself is on your head, out of view).
	if lastHat ~= nil and s.hat ~= lastHat then
		local def = Economy.hatDef(s.hat)
		if def then
			Panels.toast(`{def.name} on! Looking good`, Color3.fromRGB(150, 255, 230))
		end
	end
	lastHat = s.hat
	renderBoard()
end

-- Init / start ---------------------------------------------------------------------

function Panels.init()
	panelGui = Instance.new("ScreenGui")
	panelGui.Name = "CoinFlickPanels"
	panelGui.ResetOnSpawn = false
	panelGui.DisplayOrder = 5 -- above the HUD
	panelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	panelGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Position = UDim2.fromOffset(0, -80) -- reaches under the top inset too
	backdrop.Size = UDim2.new(1, 0, 1, 160)
	backdrop.Visible = false
	backdrop.ZIndex = 1
	backdrop.Activated:Connect(Panels.closeAll)
	backdrop.Parent = panelGui

	popGui = Instance.new("ScreenGui")
	popGui.Name = "CoinFlickPopups"
	popGui.ResetOnSpawn = false
	popGui.DisplayOrder = 10 -- above panels
	popGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	popGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	toastLabel = Kit.label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.075),
		BackgroundColor3 = Kit.INK,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 20,
	})
	Kit.corner(toastLabel, 0.5)
	Kit.outline(toastLabel, 2)
	Kit.padding(toastLabel, UDim.new(0, 16), UDim.new(0.14, 0))
	Kit.textLimit(toastLabel, 26)
	local toastSize = Instance.new("UISizeConstraint")
	toastSize.MaxSize = Vector2.new(560, 56)
	toastSize.MinSize = Vector2.new(260, 36)
	toastSize.Parent = toastLabel
	toastLabel.Parent = popGui

	-- Banner: a dark pill near the top with a colored border, so it reads on
	-- any coin color and never sits on the table.
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.29)
	banner.Size = UDim2.fromScale(0.62, 0.17)
	banner.BackgroundColor3 = Color3.fromRGB(35, 25, 50)
	banner.BackgroundTransparency = 0.1
	banner.Visible = false
	banner.ZIndex = 25
	Kit.corner(banner, 0.3)
	bannerStroke = Kit.stroke(banner, 5, Kit.GOLD)
	local bannerSize = Instance.new("UISizeConstraint")
	bannerSize.MaxSize = Vector2.new(620, 110)
	bannerSize.MinSize = Vector2.new(280, 64)
	bannerSize.Parent = banner
	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	bannerTitle = Kit.label({
		Name = "Title",
		Position = UDim2.fromScale(0.04, 0.06),
		Size = UDim2.fromScale(0.92, 0.52),
		ZIndex = 26,
	})
	Kit.outline(bannerTitle, 3)
	Kit.textLimit(bannerTitle, 44)
	bannerTitle.Parent = banner
	bannerText = Kit.label({
		Name = "Text",
		Position = UDim2.fromScale(0.04, 0.6),
		Size = UDim2.fromScale(0.92, 0.32),
		ZIndex = 26,
	})
	Kit.outline(bannerText, 2)
	Kit.textLimit(bannerText, 24)
	bannerText.Parent = banner
	banner.Parent = popGui

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.fromRGB(255, 250, 210)
	flash.BackgroundTransparency = 1
	flash.Position = UDim2.fromOffset(0, -80)
	flash.Size = UDim2.new(1, 0, 1, 160)
	flash.Visible = false
	flash.ZIndex = 1
	flash.Parent = popGui

	buildShop()
	buildReset()
	buildTop()
	panelGui.Parent = player:WaitForChild("PlayerGui")
	popGui.Parent = player:WaitForChild("PlayerGui")
end

function Panels.start()
	State.onChange(Panels.render)
	ClientNet.event("Leaderboards").OnClientEvent:Connect(function(data: Types.Leaderboards)
		boards = data
		renderBoard()
	end)
	ClientNet.event("Notice").OnClientEvent:Connect(function(notice: Types.Notice)
		if notice.kind == "reset" then
			Sounds.play("Reset", 0.8)
			CameraView.shake(0.35, 0.5)
			showBanner("NEW TABLE!", notice.text, Kit.ORANGE, false, 3)
			confetti(24)
		elseif notice.kind == "shout" then
			shout(notice)
		elseif notice.kind == "mega" then
			showBanner("MEGA FLIP!", notice.text, Kit.GOLD, false, 3.5)
			screenFlash()
			confetti(36)
		elseif notice.kind == "bought" then
			Sounds.play("Buy", 0.6)
			local card = lastPressed
			if openName and card then
				-- The card already changed; pop it instead of covering cards with a toast.
				Kit.popScale(card.scale, 1.08)
			else
				Panels.toast(notice.text, Color3.fromRGB(150, 255, 150))
			end
		elseif notice.kind == "soon" or notice.kind == "full" then
			Sounds.play("Denied", 0.5)
			Panels.toast(notice.text)
		elseif notice.kind == "offline" then
			Sounds.play("Gift", 0.7)
			Panels.toast(notice.text)
		else
			Panels.toast(notice.text)
		end
	end)
	-- Icons on the open shop tab sway gently so the shop feels alive.
	RunService.RenderStepped:Connect(function()
		if openName ~= "shop" then
			return
		end
		local list = icons[shopTab]
		if not list then
			return
		end
		local t = os.clock()
		for i, vp in list do
			local base = vp:GetAttribute("Yaw")
			if typeof(base) == "number" then
				Icons.turn(vp, base + math.sin(t * 1.6 + i) * 0.45)
			end
		end
	end)
end

return Panels
