--!strict
-- Phone-first HUD: cash + hat points on top, big SHOP / RESET / TOP / VIEW
-- buttons on the right (clear of the thumbstick and jump button), the shop
-- (upgrades, hats, Robux), the reset popup, top 10 boards, combo counter,
-- mega boost timer, and little toast messages.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)
local HudText = require(ReplicatedStorage.Shared.Util.HudText)
local ClientNet = require(script.Parent.Parent.ClientNet)
local CameraView = require(script.Parent.CameraView)
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
local RED = UiStyle.RED
local GREY = UiStyle.GREY
local PANEL = UiStyle.PANEL

local BOUNCY = UiStyle.BOUNCY
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
local toastLabel: TextLabel
local shoutLabel: TextLabel
local shoutScale: UIScale
local shoutToken = 0
local shopPanel: Frame
local resetPanel: Frame
local resetBody: TextLabel
local resetButton: TextButton
local resetFill: Frame
local resetWord: TextLabel
local resetPulse: Tween?
type Card = { level: TextLabel, buy: TextButton, team: TextButton? }
local shopCards: { [string]: Card } = {}
local helperCards: { [string]: Card } = {}
local helperSlotsLabel: TextLabel
local hatCards: { [string]: Card } = {}
local robuxCards: { [string]: Card } = {}
local topPanel: Frame
local topRows: { TextLabel } = {}
local topTabs: { [string]: TextButton } = {}
local topShown = "flips"
local boards: Types.Leaderboards = {}
local boostLabel: TextLabel
local boostEnds = 0
local comboLabel: TextLabel
local comboScale: UIScale
local comboToken = 0
local prices: { [string]: string } = {} -- live Robux prices from Roblox
local layout: HudLayout.Layout = HudLayout.compute(844, 390, true) -- redone in applyLayout
local cheatFrame: Frame? = nil
local layoutListeners: { (HudLayout.Layout) -> () } = {}

local shownCash = Instance.new("NumberValue")
local render: (Snapshot) -> ()
local toastToken = 0

local function anyPanelOpen(): boolean
	return shopPanel.Visible or resetPanel.Visible or topPanel.Visible
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

local function toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or WHITE
	toastLabel.Visible = true
	-- Its own slot under the top strips; below an open panel while one is up.
	local slot = if anyPanelOpen() then layout.toastLow else layout.toast
	place(toastLabel, slot)
	local rest = toastLabel.Position
	toastLabel.Position = rest - UDim2.fromOffset(0, 6)
	UiStyle.showText(toastLabel)
	TweenService:Create(toastLabel, BOUNCY, { Position = rest }):Play()
	task.delay(2.6, function()
		if token ~= toastToken then
			return
		end
		local fade = UiStyle.fadeText(toastLabel, 1)
		fade.Completed:Wait()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

-- Big banner everyone sees when someone flips a super rare coin.
local function shout(notice: Types.Notice)
	shoutToken += 1
	local token = shoutToken
	local def = notice.rarity and Economy.rarityDef(notice.rarity)
	shoutLabel.Text = `⭐ {notice.text} ⭐`
	shoutLabel.TextColor3 = if def then def.color else ORANGE
	UiStyle.showText(shoutLabel)
	shoutLabel.Visible = true
	shoutScale.Scale = 0.2
	TweenService:Create(shoutScale, BOUNCY, { Scale = 1 }):Play()
	if notice.ownerId ~= player.UserId then
		Sounds.play("Rare", 0.5) -- the flipper already hears it from their coin
	end
	task.spawn(function()
		local started = os.clock()
		while token == shoutToken and os.clock() - started < 4 do
			if notice.rarity == "rainbow" then
				shoutLabel.TextColor3 = Color3.fromHSV((os.clock() * 0.8) % 1, 0.7, 1)
			end
			task.wait()
		end
		if token ~= shoutToken then
			return
		end
		local fade = UiStyle.fadeText(shoutLabel, 1)
		fade.Completed:Wait()
		if token == shoutToken then
			shoutLabel.Visible = false
		end
	end)
end

local onShopOpen: (() -> ())? = nil -- set by buildShop: back to the first tab, scrolled to the top

local function openPanel(panel: Frame)
	local scale = panel:FindFirstChildOfClass("UIScale")
	if panel == shopPanel and onShopOpen then
		onShopOpen()
	end
	panel.Visible = true
	-- Panels may reach over the thumbstick, so hide Roblox's touch controls
	-- (and the Studio test buttons) while one is open.
	GuiService.TouchControlsEnabled = false
	if cheatFrame then
		cheatFrame.Visible = false
	end
	infoLabel.Visible = false
	boostLabel.Visible = false
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, BOUNCY, { Scale = 1 }):Play()
	end
end

local function closePanels()
	shopPanel.Visible = false
	resetPanel.Visible = false
	topPanel.Visible = false
	GuiService.TouchControlsEnabled = true
	if cheatFrame then
		cheatFrame.Visible = true
	end
	setStrip(infoLabel, infoLabel.Text)
	setStrip(boostLabel, boostLabel.Text)
end

local function makePanel(name: string, title: string): (Frame, Frame)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromScale(0.62, 0.74) -- leaves a strip below for toasts
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

local function shopCard(
	parent: ScrollingFrame,
	order: number,
	icon: string,
	name: string,
	onBuy: () -> (),
	onTeam: (() -> ())?
): Card
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
		Size = UDim2.new(if onTeam then 0.4 else 0.62, -76, 0.45, 0),
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
		Size = UDim2.new(if onTeam then 0.4 else 0.62, -76, 0.38, 0),
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
	buy.Size = UDim2.new(if onTeam then 0.3 else 0.36, 0, 1, -16)
	buy.ZIndex = 8
	buy.Parent = card
	textLimit(buy, 28)

	local team: TextButton? = nil
	if onTeam then
		local t = button("", BLUE, onTeam)
		t.Name = "Team"
		t.AnchorPoint = Vector2.new(1, 0.5)
		t.Position = UDim2.new(0.7, -16, 0.5, 0)
		t.Size = UDim2.new(0.24, 0, 1, -16)
		t.ZIndex = 8
		t.Parent = card
		textLimit(t, 22)
		team = t
	end

	card.Parent = parent
	return { level = level, buy = buy, team = team }
end

local function scrollList(parent: Frame, top: number): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, top)
	list.Size = UDim2.new(1, 0, 1, -top)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 6
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = list
	list.Parent = parent
	return list
end

-- A row of big tab buttons. Returns the buttons by key.
local function tabRow(parent: Frame, tabs: { { string } }, onPick: (string) -> ()): { [string]: TextButton }
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundTransparency = 1
	row.ZIndex = 6
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0.02, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = row
	local buttons: { [string]: TextButton } = {}
	for i, tab in tabs do
		local key = tab[1]
		local b = button(tab[2], GREY, function()
			Sounds.play("Tap", 0.4)
			onPick(key)
		end)
		b.LayoutOrder = i
		b.Size = UDim2.fromScale(1 / #tabs - 0.02, 1)
		b.ZIndex = 7
		textLimit(b, 22)
		b.Parent = row
		buttons[key] = b
	end
	row.Parent = parent
	return buttons
end

local function pickTab(buttons: { [string]: TextButton }, lists: { [string]: GuiObject }, key: string)
	for k, b in buttons do
		b.BackgroundColor3 = if k == key then ORANGE else GREY
	end
	for k, list in lists do
		list.Visible = k == key
	end
end

local function robuxPrice(key: string, id: number, info: Enum.InfoType)
	if id <= 0 or prices[key] then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return MarketplaceService:GetProductInfo(id, info)
		end)
		if ok and typeof(result) == "table" and typeof(result.PriceInRobux) == "number" then
			prices[key] = `R$ {result.PriceInRobux}`
			local s = State.get()
			if s then
				render(s)
			end
		end
	end)
end

local function buildShop()
	local panel, body = makePanel("Shop", "SHOP")
	shopPanel = panel
	local lists: { [string]: GuiObject } = {}
	local tabs: { [string]: TextButton } = {}
	tabs = tabRow(
		body,
		{ { "upgrades", "💰 COINS" }, { "helpers", "👷 CREW" }, { "hats", "🎩 HATS" }, { "robux", "💎 MORE" } },
		function(key)
			pickTab(tabs, lists, key)
		end
	)
	local list = scrollList(body, 52)
	lists.upgrades = list

	local buyRemote = ClientNet.event("BuyUpgrade")
	for i, id in Config.UPGRADE_ORDER do
		local def = Config.Upgrades[id]
		shopCards[id] = shopCard(list, i, def.icon, def.name, function()
			buyRemote:FireServer(id)
		end)
	end

	-- Helper guys: unlock with cash, level up, put on the team.
	local crewList = scrollList(body, 52)
	lists.helpers = crewList
	helperSlotsLabel = label({
		LayoutOrder = 0,
		Size = UDim2.new(1, -10, 0, 28),
		TextColor3 = INK,
		TextStrokeTransparency = 1,
		ZIndex = 7,
	})
	textLimit(helperSlotsLabel, 20)
	helperSlotsLabel.Parent = crewList
	local unlockRemote = ClientNet.event("BuyHelper")
	local levelRemote = ClientNet.event("LevelHelper")
	local teamRemote = ClientNet.event("TeamHelper")
	for i, def in Config.HelperTypes do
		helperCards[def.id] = shopCard(crewList, i, def.icon, def.name, function()
			local s = State.get()
			if s and s.crew[def.id] then
				levelRemote:FireServer(def.id)
			elseif s and s.resets < def.resets then
				toast(`Reset {def.resets} times to meet {def.name}!`)
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

	-- Hats: buy with 🎩, tap again to wear or take off.
	local hatList = scrollList(body, 52)
	lists.hats = hatList
	local buyHat = ClientNet.event("BuyHat")
	local wearHat = ClientNet.event("WearHat")
	for i, def in Config.Hats do
		hatCards[def.id] = shopCard(hatList, i, def.icon, def.name, function()
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

	-- Robux extras. No random boxes. SOON until carter adds the ids.
	local robuxList = scrollList(body, 52)
	lists.robux = robuxList
	local buyRobux = ClientNet.event("BuyRobux")
	local chooseSkin = ClientNet.event("ChooseSkin")
	local extras = {
		{ "doubleCash", "💰", "2x Cash Forever" },
		{ "autoFlip", "🤖", "Auto Flip" },
		{ "helperSlot", "👷", "+1 Helper Slot" },
	}
	for i, item in extras do
		local key = item[1]
		robuxCards[key] = shopCard(robuxList, i, item[2], item[3], function()
			buyRobux:FireServer(key)
		end)
	end
	for i, skin in Config.Skins do
		robuxCards[skin.id] = shopCard(robuxList, 10 + i, skin.icon, skin.name, function()
			local s = State.get()
			if s and s.passes[skin.id] then
				chooseSkin:FireServer(if s.skin == skin.id then "" else skin.id)
			else
				buyRobux:FireServer(skin.id)
			end
		end)
		robuxPrice(skin.id, skin.passId, Enum.InfoType.GamePass)
	end
	robuxPrice("doubleCash", Config.Products.DoubleCashPassId, Enum.InfoType.GamePass)
	robuxPrice("autoFlip", Config.Products.AutoFlipPassId, Enum.InfoType.GamePass)
	robuxPrice("helperSlot", Config.Products.ExtraHelperSlotProductId, Enum.InfoType.Product)
	pickTab(tabs, lists, "upgrades")
	onShopOpen = function()
		pickTab(tabs, lists, "upgrades")
		for _, l in lists do
			if l:IsA("ScrollingFrame") then
				l.CanvasPosition = Vector2.zero
			end
		end
	end
end

-- Top 10 boards ----------------------------------------------------------

local BOARD_TITLES: { [string]: string } = {
	flips = "MOST FLIPS",
	biggestFlip = "BIGGEST FLIP",
	resets = "MOST RESETS",
}

local function renderBoard()
	local rows = boards[topShown] or {}
	for i, rowLabel in topRows do
		local row = rows[i]
		if row then
			local value = if topShown == "biggestFlip" then `${Format.short(row.value)}` else Format.short(row.value)
			rowLabel.Text = `{i}. {row.name}  •  {value}`
			rowLabel.TextColor3 = if i == 1 then ORANGE elseif row.name == player.DisplayName then GREEN else INK
		else
			rowLabel.Text = if i == 1 then "No one yet. Be first!" else ""
			rowLabel.TextColor3 = INK
		end
	end
	for key, b in topTabs do
		b.BackgroundColor3 = if key == topShown then ORANGE else GREY
	end
	local title = topPanel:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = `🏆 {BOARD_TITLES[topShown]}`
	end
end

local function buildTop()
	local panel, body = makePanel("Top", "🏆 TOP 10")
	topPanel = panel
	topTabs = tabRow(body, { { "flips", "FLIPS" }, { "biggestFlip", "BIGGEST" }, { "resets", "RESETS" } }, function(key)
		topShown = key
		renderBoard()
	end)
	local list = scrollList(body, 52)
	for i = 1, Config.LEADERBOARD_SIZE do
		local row = label({
			Name = `Row{i}`,
			LayoutOrder = i,
			Size = UDim2.new(1, -10, 0, 30),
			TextColor3 = INK,
			TextStrokeTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		})
		textLimit(row, 22)
		row.Parent = list
		topRows[i] = row
	end
	renderBoard()
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

-- Big icon on top, word underneath (the icon is the thing kids spot).
local function sideButton(icon: string, word: string, color: Color3, onPress: () -> ()): (TextButton, TextLabel, TextLabel)
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
	helperSlotsLabel.Text = `Helpers working: {#s.team}/{s.maxHelpers}  •  They flip even when you're away`
	for _, def in Config.HelperTypes do
		local card = helperCards[def.id]
		local level = s.crew[def.id]
		local team = card.team
		if level then
			local interval = Economy.helperInterval(def, level)
			local mult = Economy.helperCashMult(def, level)
			card.level.Text = `Lv {level}  •  flips every {string.format("%.1f", interval)}s  •  x{string.format(
				"%.1f",
				mult
			)} cash`
			local cost = Economy.helperLevelCost(def, level)
			card.buy.Text = if cost then `⬆ ${Format.short(cost)}` else "MAX"
			card.buy.BackgroundColor3 = if not cost then BLUE elseif s.cash >= cost then GREEN else GREY
			if team then
				local working = table.find(s.team, def.id) ~= nil
				team.Visible = true
				team.Text = if working then "WORKING" else "RESTING"
				team.BackgroundColor3 = if working then ORANGE else GREY
			end
		else
			if team then
				team.Visible = false
			end
			if s.resets < def.resets then
				card.level.Text = `Unlocks after {def.resets} reset{if def.resets == 1 then "" else "s"}`
				card.buy.Text = "🔒"
				card.buy.BackgroundColor3 = GREY
			else
				card.level.Text = `Flips every {string.format("%.1f", def.interval)}s  •  x{def.mult} cash`
				card.buy.Text = `${Format.short(def.cost)}`
				card.buy.BackgroundColor3 = if s.cash >= def.cost then GREEN else GREY
			end
		end
	end

	for _, def in Config.Hats do
		local card = hatCards[def.id]
		local owned = table.find(s.hats, def.id) ~= nil
		if s.hat == def.id then
			card.level.Text = "On your head! Tap to take off"
			card.buy.Text = "ON ✓"
			card.buy.BackgroundColor3 = ORANGE
		elseif owned then
			card.level.Text = "Yours! Tap to wear"
			card.buy.Text = "WEAR"
			card.buy.BackgroundColor3 = BLUE
		else
			card.level.Text = "Buy with hat points from 🎩 flips"
			card.buy.Text = `🎩 {def.cost}`
			card.buy.BackgroundColor3 = if s.hatPoints >= def.cost then GREEN else GREY
		end
	end

	local function robuxButton(card: Card, key: string, desc: string, owned: boolean, id: number)
		card.level.Text = desc
		if owned then
			card.buy.Text = "OWNED"
			card.buy.BackgroundColor3 = BLUE
		elseif id <= 0 then
			card.buy.Text = "SOON"
			card.buy.BackgroundColor3 = Color3.fromRGB(185, 160, 235)
		else
			card.buy.Text = prices[key] or "BUY"
			card.buy.BackgroundColor3 = GREEN
		end
	end
	robuxButton(
		robuxCards.doubleCash,
		"doubleCash",
		"Double cash on every heads",
		s.passes.doubleCash == true,
		Config.Products.DoubleCashPassId
	)
	robuxButton(
		robuxCards.autoFlip,
		"autoFlip",
		"Your coins flip by themselves",
		s.passes.autoFlip == true,
		Config.Products.AutoFlipPassId
	)
	local slotsFull = s.helperSlots >= Config.MAX_EXTRA_HELPER_SLOTS
	robuxButton(
		robuxCards.helperSlot,
		"helperSlot",
		`One more helper can work ({s.helperSlots}/{Config.MAX_EXTRA_HELPER_SLOTS} bought)`,
		slotsFull,
		Config.Products.ExtraHelperSlotProductId
	)
	for _, skin in Config.Skins do
		local card = robuxCards[skin.id]
		if s.passes[skin.id] then
			card.level.Text = if s.skin == skin.id then "On your coins! Tap for gold" else "Yours! Tap to use"
			card.buy.Text = if s.skin == skin.id then "ON ✓" else "USE"
			card.buy.BackgroundColor3 = if s.skin == skin.id then ORANGE else BLUE
		else
			robuxButton(card, skin.id, "A new look for every coin", false, skin.passId)
		end
	end

	resetBody.Text =
		`You LOSE: cash and upgrades\nYou KEEP: helper guys and 🎩\nYou GET: cash x{s.resetBonus} forever + a new table!`
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
	place(shoutLabel, layout.shout)
	setMaxText(shoutLabel, layout.shout.h * 0.42)
	place(comboLabel, layout.combo)
	setMaxText(comboLabel, layout.combo.h * 0.4)
	setMaxText(toastLabel, layout.toast.h * 0.42)
	if toastLabel.Visible then
		local slot = if anyPanelOpen() then layout.toastLow else layout.toast
		place(toastLabel, slot)
	end

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

	for _, fn in layoutListeners do
		task.spawn(fn, layout)
	end

	-- Panels: centered in the free panel box, never bigger than it.
	for _, panel in { shopPanel, resetPanel, topPanel } do
		local box = layout.panel
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromOffset(box.x + box.w / 2, box.y + box.h / 2)
		local cap = panel:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			cap.MaxSize = Vector2.new(math.min(560 * s, box.w), box.h)
			cap.MinSize = Vector2.new(math.min(300, box.w), math.min(210, box.h))
		end
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

	toastLabel = label({
		Name = "Toast",
		TextWrapped = true,
		Visible = false,
		ZIndex = 10,
	})
	textLimit(toastLabel, 30)
	toastLabel.Parent = gui

	shoutLabel = label({
		Name = "Shout",
		TextWrapped = true,
		Visible = false,
		ZIndex = 11,
	})
	textLimit(shoutLabel, 40)
	shoutScale = Instance.new("UIScale")
	shoutScale.Parent = shoutLabel
	shoutLabel.Parent = gui

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
		closePanels()
		openPanel(shopPanel)
	end)
	local resetB, _resetIcon, resetW = sideButton("🔄", "RESET", GREY, function()
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
		closePanels()
		openPanel(topPanel)
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

	buildShop()
	buildReset()
	buildTop()
	buildCheats(gui)

	shownCash.Changed:Connect(function(value: number)
		cashLabel.Text = `${Format.short(value)}`
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
end

function Hud.start()
	State.onChange(render)
	ClientNet.event("Leaderboards").OnClientEvent:Connect(function(data: Types.Leaderboards)
		boards = data
		renderBoard()
	end)
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
	ClientNet.event("Notice").OnClientEvent:Connect(function(notice: Types.Notice)
		if notice.kind == "reset" then
			Sounds.play("Reset", 0.8)
			CameraView.shake(0.35, 0.5)
			toast(notice.text, ORANGE)
		elseif notice.kind == "shout" then
			shout(notice)
		elseif notice.kind == "mega" then
			toast(notice.text, Color3.fromRGB(255, 220, 60))
		elseif notice.kind == "bought" then
			Sounds.play("Buy", 0.6)
			if anyPanelOpen() then
				-- The card already changed; a toast here would cover the cards.
				local panelScale = shopPanel:FindFirstChildOfClass("UIScale")
				if panelScale then
					popScale(panelScale, 1.03)
				end
			else
				toast(notice.text, Color3.fromRGB(150, 255, 150))
			end
		elseif notice.kind == "soon" or notice.kind == "full" then
			Sounds.play("Denied", 0.5)
			toast(notice.text)
		elseif notice.kind == "offline" then
			Sounds.play("Gift", 0.7)
			toast(notice.text)
		else
			toast(notice.text)
		end
	end)
end

return Hud
