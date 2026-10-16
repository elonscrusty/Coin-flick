--!strict
-- The GIFTS and PETS tabs of the shop. Draws what Shared/Util/GiftPetView says and
-- sends intents only: "claim today's gift", "claim job N", "equip pet X". The server
-- (Systems/Daily, Systems/Pets) decides every reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local GiftPetView = require(ReplicatedStorage.Shared.Util.GiftPetView)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local PetRules = require(ReplicatedStorage.Shared.Util.PetRules)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Kit = require(script.Parent.Parent.Ui.Kit)
local Widgets = require(script.Parent.Parent.Ui.PanelWidgets)

local GiftPets = {}
local label, makeBar, setBar, guard, card = Widgets.label, Widgets.makeBar, Widgets.setBar, Widgets.guard, Widgets.card

local CAL_H = 76
local GIFT_H = 50
local TIMER_H = 24
local JOB_H = 66
local PET_H = 70
local DAY_COLORS = {
	claimed = Color3.fromRGB(205, 225, 245),
	ready = Color3.fromRGB(255, 226, 120),
	later = Kit.CARD,
}

type Bar = Widgets.Bar
type CellUi = { frame: Frame, outline: UIStroke, day: TextLabel, amount: TextLabel, extra: TextLabel }
type JobUi = { frame: Frame, title: TextLabel, bar: Bar, button: TextButton, reward: TextLabel }
type PetUi = {
	frame: Frame,
	outline: UIStroke,
	icon: TextLabel,
	name: TextLabel,
	line: TextLabel,
	bar: Bar,
	button: TextButton,
}

local daily: Types.DailyView? = nil
local pets: { PetRules.PetView } = {}
local cells: { CellUi } = {}
local jobs: { JobUi } = {}
local petUis: { [string]: PetUi } = {}
local giftButton: TextButton
local timerLabel: TextLabel
local dailyList: ScrollingFrame
local playHeader: TextLabel
local playView: Types.PlayGiftView? = nil
local playAt = 0
local playUis: { JobUi } = {}
local petList: ScrollingFrame
local dotHook: { fn: (boolean) -> () } = { fn = function() end }

-- GIFTS -------------------------------------------------------------------------

local function buildDaily(list: ScrollingFrame)
	local calendar = Instance.new("Frame")
	calendar.Name = "Calendar"
	calendar.Size = UDim2.new(1, -10, 0, CAL_H)
	calendar.LayoutOrder = 1
	calendar.BackgroundTransparency = 1
	calendar.ZIndex = 6
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 4)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = calendar
	local scale, offset = PanelView.tabSize(7, 4)
	for i = 1, 7 do
		local frame = Instance.new("Frame")
		frame.Name = `Day{i}`
		frame.LayoutOrder = i
		frame.Size = UDim2.new(scale, offset, 1, 0)
		frame.BackgroundColor3 = Kit.CARD
		frame.ZIndex = 6
		Kit.corner(frame, 0.2)
		local outline = Kit.stroke(frame, 2)
		local day = label({
			Text = `DAY {i}`,
			Position = UDim2.fromScale(0, 0.05),
			Size = UDim2.fromScale(1, 0.27),
		}, 14, true)
		day.Parent = frame
		local amount = label({
			Position = UDim2.fromScale(0, 0.33),
			Size = UDim2.fromScale(1, 0.34),
		}, 22, true)
		amount.Parent = frame
		local extra = label({
			Position = UDim2.fromScale(0, 0.69),
			Size = UDim2.fromScale(1, 0.26),
		}, 14, true)
		extra.Parent = frame
		frame.Parent = calendar
		table.insert(cells, { frame = frame, outline = outline, day = day, amount = amount, extra = extra })
	end
	calendar.Parent = list

	giftButton = Kit.button("", Kit.GREEN, function() end)
	giftButton.Name = "GiftButton"
	giftButton.Size = UDim2.new(1, -10, 0, GIFT_H)
	giftButton.LayoutOrder = 2
	giftButton.ZIndex = 8
	Kit.textLimit(giftButton, 26)
	giftButton.Parent = list
	local claimGift = ClientNet.event("ClaimGift")
	guard(list, giftButton, function()
		if daily and daily.gift.ready then
			claimGift:FireServer()
		end
	end)

	timerLabel = label({
		Name = "Timer",
		Size = UDim2.new(1, -10, 0, TIMER_H),
		LayoutOrder = 3,
		TextColor3 = Kit.MUTED,
	}, 16, true)
	timerLabel.TextColor3 = Kit.MUTED
	timerLabel.Parent = list

	playHeader = label({ Text = GiftPetView.PLAY_HEADER, Size = UDim2.new(1, -10, 0, 28), LayoutOrder = 20 }, 22, true)
	playHeader.TextXAlignment = Enum.TextXAlignment.Left
	playHeader.Visible = false
	playHeader.Parent = list

	local claimJob = ClientNet.event("ClaimJob")
	for slot = 1, 3 do
		local frame = card(list, `Job{slot}`, JOB_H, 3 + slot)
		local title = label({
			Name = "Title",
			Position = UDim2.fromOffset(10, 5),
			Size = UDim2.new(0.66, -10, 0.4, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 20, true)
		title.Parent = frame
		local bar = makeBar(frame, UDim2.fromScale(0.02, 0.55), UDim2.fromScale(0.62, 0.32), Kit.GREEN)
		local button = Kit.button("", Kit.GREEN, function() end)
		button.Name = "Claim"
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -8, 0, 6)
		button.Size = UDim2.new(0.3, -8, 0.5, 0)
		button.ZIndex = 8
		Kit.textLimit(button, 20)
		button.Parent = frame
		local reward = label({
			Name = "Reward",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0.6, 0),
			Size = UDim2.new(0.3, -8, 0.32, 0),
		}, 16, true)
		reward.Parent = frame
		guard(list, button, function()
			claimJob:FireServer(slot)
		end)
		table.insert(jobs, { frame = frame, title = title, bar = bar, button = button, reward = reward })
	end
end

local function renderDaily()
	if not daily then
		giftButton.Text = GiftPetView.NO_DAILY
		Kit.applyLook(giftButton, "poor")
		return
	end
	local rows = GiftPetView.dailyRows(daily, os.time(), playView, os.time() - playAt)
	for i, ui in cells do
		local cell = rows.cells[i]
		if not cell then
			ui.frame.Visible = false
			continue
		end
		ui.frame.Visible = true
		ui.frame.BackgroundColor3 = DAY_COLORS[cell.state]
		ui.outline.Color = if cell.state == "ready" then Kit.ORANGE else Kit.INK
		ui.outline.Thickness = if cell.state == "ready" then 4 else 2
		ui.amount.Text = cell.text
		ui.extra.Text = if cell.state == "claimed" then "✔" elseif cell.hats > 0 then `🎩{cell.hats}` else ""
	end
	giftButton.Text = rows.gift.text
	Kit.applyLook(giftButton, rows.gift.look)
	timerLabel.Text = rows.timer
	for i, ui in jobs do
		local job = rows.jobs[i]
		ui.frame.Visible = job ~= nil
		if job then
			ui.title.Text = job.text
			setBar(ui.bar, job.frac, job.count)
			ui.button.Text = job.button.text
			Kit.applyLook(ui.button, job.button.look)
			ui.reward.Text = job.reward
			ui.bar.fill.BackgroundColor3 = if job.canClaim then Kit.GOLD else Kit.GREEN
		end
	end
end

-- PLAY GIFTS (a few gifts for time played today; rows are made when the first view arrives) ------

local function addPlayRow(slot: number)
	local frame = card(dailyList, `Play{slot}`, 54, 20 + slot)
	local title = label({
		Name = "Title",
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(0.6, -10, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 20, true)
	title.Parent = frame
	local reward = label({
		Name = "Reward",
		Position = UDim2.new(0, 10, 0.52, 0),
		Size = UDim2.new(0.6, -10, 0.4, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 16, true)
	reward.TextColor3 = Kit.MUTED
	reward.Parent = frame
	local button = Kit.button("", Kit.GREEN, function() end)
	button.Name = "Claim"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.new(0.34, -8, 1, -14)
	button.ZIndex = 8
	Kit.textLimit(button, 20)
	button.Parent = frame
	local claim = ClientNet.event("ClaimPlayGift")
	guard(dailyList, button, function()
		claim:FireServer(slot)
	end)
	local bar = makeBar(frame, UDim2.fromScale(2, 2), UDim2.fromScale(0, 0), Kit.GREEN) -- unused, keeps JobUi shape
	bar.track.Visible = false
	playUis[slot] = { frame = frame, title = title, bar = bar, button = button, reward = reward }
end

local function renderPlay()
	local view = playView
	if not view then
		return
	end
	playHeader.Visible = #view.gifts > 0
	local rows = GiftPetView.playGiftRows(view, os.time() - playAt)
	for _, row in rows do
		if not playUis[row.slot] then
			addPlayRow(row.slot)
		end
		local ui = playUis[row.slot]
		ui.title.Text = row.text
		ui.reward.Text = row.reward
		ui.button.Text = row.button.text
		Kit.applyLook(ui.button, row.button.look)
	end
end

-- PETS --------------------------------------------------------------------------

local function buildPets(list: ScrollingFrame)
	local equip = ClientNet.event("PetEquip")
	for i, def in PetConfig.Pets do
		local frame, outline = card(list, def.id, PET_H, i)
		local tile = Instance.new("Frame")
		tile.Name = "IconBox"
		tile.Position = UDim2.fromOffset(5, 5)
		tile.Size = UDim2.fromOffset(PET_H - 10, PET_H - 10)
		tile.BackgroundColor3 = Color3.fromRGB(150, 200, 250)
		tile.ZIndex = 7
		Kit.corner(tile, 0.25)
		tile.Parent = frame
		local icon = label({ Name = "Icon", Text = def.icon, Size = UDim2.fromScale(1, 1) }, 40, false)
		icon.Parent = tile
		local name = label({
			Name = "Title",
			Position = UDim2.fromOffset(PET_H + 2, 4),
			Size = UDim2.new(0.5, -(PET_H + 2), 0.3, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 22, true)
		name.Parent = frame
		local line = label({
			Name = "Line",
			Position = UDim2.new(0, PET_H + 2, 0.32, 0),
			Size = UDim2.new(0.62, -(PET_H + 2), 0.28, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 16, true)
		line.TextColor3 = Kit.MUTED
		line.Parent = frame
		local bar = makeBar(frame, UDim2.new(0, PET_H + 2, 0.64, 0), UDim2.new(0.62, -(PET_H + 2), 0.28, 0), def.accent)
		local button = Kit.button("", Kit.GREEN, function() end)
		button.Name = "Equip"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.new(0.3, -8, 1, -16)
		button.ZIndex = 8
		Kit.textLimit(button, 20)
		button.Parent = frame
		local petId = def.id
		guard(list, button, function()
			for _, view in pets do
				if view.id == petId and view.owned then
					equip:FireServer(if view.active then "" else petId)
				end
			end
		end)
		petUis[def.id] = {
			frame = frame,
			outline = outline,
			icon = icon,
			name = name,
			line = line,
			bar = bar,
			button = button,
		}
	end
end

local function renderPets()
	for _, row in GiftPetView.petRows(pets) do
		local ui = petUis[row.id]
		if ui then
			ui.name.Text = row.name
			ui.line.Text = row.line
			setBar(ui.bar, row.frac, row.bar)
			ui.button.Text = row.button.text
			Kit.applyLook(ui.button, row.button.look)
			ui.outline.Color = if row.active then Kit.TEAL else Kit.INK
			ui.outline.Thickness = if row.active then 4 else 2
			ui.icon.TextTransparency = if row.owned then 0 else 0.6
		end
	end
end

-- Public --------------------------------------------------------------------------

-- Builds both lists with `makeList` (the shop's own scroll list maker).
function GiftPets.build(makeList: () -> ScrollingFrame): (ScrollingFrame, ScrollingFrame)
	dailyList = makeList()
	buildDaily(dailyList)
	petList = makeList()
	buildPets(petList)
	renderDaily()
	renderPets()
	return dailyList, petList
end

-- `dot(true)` when something can be claimed (the GIFTS tab shows a red dot).
function GiftPets.start(dot: (boolean) -> ())
	dotHook.fn = dot
	ClientNet.event("DailyState").OnClientEvent:Connect(function(view: Types.DailyView)
		daily = view
		renderDaily()
		dotHook.fn(GiftPetView.dailyDot(view, playView))
	end)
	ClientNet.event("PlayGiftState").OnClientEvent:Connect(function(view: Types.PlayGiftView)
		playView = view
		playAt = os.time()
		renderPlay()
		renderDaily()
		dotHook.fn(GiftPetView.dailyDot(daily, view))
	end)
	ClientNet.event("PetState").OnClientEvent:Connect(function(views: { PetRules.PetView })
		pets = views
		renderPets()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if daily and dailyList.Visible then
				renderDaily()
			end
			if playView and dailyList.Visible then
				renderPlay()
			end
		end
	end)
end

return GiftPets
