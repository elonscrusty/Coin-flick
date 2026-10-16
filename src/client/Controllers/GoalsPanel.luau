--!strict
-- The GOALS tab of the shop: streak ladder (wear a coin look), weekly challenges (+ bonus) and
-- the coin book. Draws what Shared/Util/GoalsPanelView says and sends intents only
-- ("claim challenge N", "wear ladder look X"). The server decides and pays every prize.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local GoalsConfig = require(ReplicatedStorage.Shared.GoalsConfig)
local GoalRules = require(ReplicatedStorage.Shared.Util.Goals)
local GoalsPanelView = require(ReplicatedStorage.Shared.Util.GoalsPanelView)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Kit = require(script.Parent.Parent.Ui.Kit)
local Widgets = require(script.Parent.Parent.Ui.PanelWidgets)

local GoalsPanel = {}
local label, makeBar, setBar, guard, card = Widgets.label, Widgets.makeBar, Widgets.setBar, Widgets.guard, Widgets.card

local ROW_H = 62
local HEAD_H = 28
local NOTE_H = 24
local PAGE_H = 54
local BADGE_H = 54

type LadderUi = {
	frame: Frame,
	outline: UIStroke,
	name: TextLabel,
	line: TextLabel,
	button: TextButton,
	bar: Widgets.Bar,
}
type ChallengeUi = { frame: Frame, title: TextLabel, bar: Widgets.Bar, button: TextButton, reward: TextLabel }
type PageUi = { frame: Frame, title: TextLabel, line: TextLabel, prize: TextLabel }

local view: GoalRules.GoalsView? = nil
local receivedAt = 0
local ladderNote: TextLabel
local weekTimer: TextLabel
local ladderUis: { [string]: LadderUi } = {}
local challengeUis: { ChallengeUi } = {}
local bookBar: Widgets.Bar
local bookBonus: TextLabel
local pageUis: { [string]: PageUi } = {}
local goalsList: ScrollingFrame
local badgeHeader: TextLabel
local badgeGrid: Frame
local badgeUis: { [string]: { frame: Frame, name: TextLabel, line: TextLabel } } = {}

local function header(list: ScrollingFrame, text: string, order: number): TextLabel
	local l = label({ Text = text, Size = UDim2.new(1, -10, 0, HEAD_H), LayoutOrder = order }, 22, true)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = list
	return l
end

local function note(list: ScrollingFrame, order: number): TextLabel
	local l = label({ Size = UDim2.new(1, -10, 0, NOTE_H), LayoutOrder = order }, 16, true)
	l.TextColor3 = Kit.MUTED
	l.Parent = list
	return l
end

local function build(list: ScrollingFrame)
	-- Streak ladder.
	header(list, GoalsPanelView.LADDER_HEADER, 1)
	ladderNote = note(list, 2)
	local wear = ClientNet.event("WearLadder")
	for i, rung in GoalsConfig.Ladder do
		local frame, outline = card(list, rung.id, ROW_H, 2 + i)
		local tile = Instance.new("Frame")
		tile.Name = "IconBox"
		tile.Position = UDim2.fromOffset(5, 5)
		tile.Size = UDim2.fromOffset(ROW_H - 10, ROW_H - 10)
		tile.BackgroundColor3 = rung.coin
		tile.ZIndex = 7
		Kit.corner(tile, 0.25)
		tile.Parent = frame
		local icon = label({ Text = rung.icon, Size = UDim2.fromScale(1, 1) }, 36, false)
		icon.Parent = tile
		local name = label({
			Name = "Title",
			Position = UDim2.fromOffset(ROW_H + 2, 6),
			Size = UDim2.new(0.6, -(ROW_H + 2), 0.45, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 22, true)
		name.Parent = frame
		local line = label({
			Name = "Line",
			Position = UDim2.new(0, ROW_H + 2, 0.52, 0),
			Size = UDim2.new(0.6, -(ROW_H + 2), 0.38, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 16, true)
		line.TextColor3 = Kit.MUTED
		line.Parent = frame
		local button = Kit.button("", Kit.GREEN, function() end)
		button.Name = "Wear"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.new(0.3, -8, 1, -16)
		button.ZIndex = 8
		Kit.textLimit(button, 20)
		button.Parent = frame
		-- A locked look shows progress on a bright bar ("1/3"), not a dead button.
		local bar = makeBar(frame, UDim2.new(1, -8, 0.5, 0), UDim2.new(0.3, -8, 0.5, 0), Kit.GOLD)
		bar.track.AnchorPoint = Vector2.new(1, 0.5)
		bar.track.Visible = false
		local id = rung.id
		guard(list, button, function()
			local v = view
			if not v then
				return
			end
			for _, r in v.ladder.rungs do
				if r.id == id and r.owned then
					wear:FireServer(if r.worn then "" else id)
				end
			end
		end)
		ladderUis[id] = { frame = frame, outline = outline, name = name, line = line, button = button, bar = bar }
	end

	-- Weekly challenges (three, then the bonus as slot 0).
	header(list, GoalsPanelView.WEEK_HEADER, 10)
	weekTimer = note(list, 11)
	local claim = ClientNet.event("ClaimChallenge")
	for slot = 0, 3 do
		local frame = card(
			list,
			if slot == 0 then "Bonus" else `Challenge{slot}`,
			ROW_H,
			12 + (if slot == 0 then 3 else slot - 1)
		)
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
			claim:FireServer(slot)
		end)
		-- Index 1..3 = challenges, 4 = the bonus (the view lists the bonus last).
		challengeUis[if slot == 0 then 4 else slot] =
			{ frame = frame, title = title, bar = bar, button = button, reward = reward }
	end

	-- Badges: a 2-column grid, filled when BadgeState arrives.
	badgeHeader = header(list, "BADGES", 40)
	badgeGrid = Instance.new("Frame")
	badgeGrid.Name = "BadgeGrid"
	badgeGrid.LayoutOrder = 41
	badgeGrid.Size = UDim2.new(1, -10, 0, 0)
	badgeGrid.AutomaticSize = Enum.AutomaticSize.Y
	badgeGrid.BackgroundTransparency = 1
	badgeGrid.ZIndex = 6
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, BADGE_H)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = badgeGrid
	badgeGrid.Parent = list

	-- Coin book.
	header(list, GoalsPanelView.BOOK_HEADER, 20)
	local summary = Instance.new("Frame")
	summary.Name = "BookSummary"
	summary.Size = UDim2.new(1, -10, 0, 26)
	summary.LayoutOrder = 21
	summary.BackgroundTransparency = 1
	summary.Parent = list
	bookBar = makeBar(summary, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Kit.GOLD)
	bookBonus = note(list, 22)
	local pages = #Config.Rarities
	for i, def in Config.Rarities do
		-- Config lists the rarest first; the book reads easiest first.
		local frame = card(list, `Page_{def.id}`, PAGE_H, 22 + (pages - i + 1))
		local title = label({
			Name = "Title",
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(0.55, -10, 0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 22, true)
		title.Parent = frame
		local line = label({
			Name = "Line",
			Position = UDim2.new(0, 10, 0.52, 0),
			Size = UDim2.new(0.55, -10, 0.4, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 16, true)
		line.TextColor3 = Kit.MUTED
		line.Parent = frame
		local prize = label({
			Name = "Prize",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0.4, -8, 0.7, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, 18, true)
		prize.Parent = frame
		pageUis[def.id] = { frame = frame, title = title, line = line, prize = prize }
	end
end

-- BADGES (cards are made when the first view arrives) ----------------------------------------

local function renderBadges(badges: Types.BadgeView)
	badgeHeader.Text = GoalsPanelView.badgeHeader(badges)
	for i, b in GoalsPanelView.badgeCards(badges) do
		local ui = badgeUis[b.id]
		if not ui then
			local frame = Instance.new("Frame")
			frame.Name = b.id
			frame.BackgroundColor3 = Kit.CARD
			frame.ZIndex = 6
			Kit.corner(frame, 0.18)
			Kit.stroke(frame, 2)
			local name = label({
				Name = "Title",
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0.5, 0),
			}, 18, true)
			name.Parent = frame
			local line = label({
				Name = "Line",
				Position = UDim2.new(0, 8, 0.52, 0),
				Size = UDim2.new(1, -16, 0.4, 0),
			}, 14, true)
			line.Parent = frame
			frame.Parent = badgeGrid
			ui = { frame = frame, name = name, line = line }
			badgeUis[b.id] = ui
		end
		ui.frame.LayoutOrder = i
		ui.frame.BackgroundColor3 = if b.earned then Color3.fromRGB(255, 244, 190) else Color3.fromRGB(226, 224, 232)
		ui.name.Text = if b.earned then `★ {b.name}` else b.name
		ui.name.TextColor3 = if b.earned then Kit.INK else Kit.MUTED
		ui.line.Text = b.text
		ui.line.TextColor3 = Kit.MUTED
	end
end

local function render()
	local v = view
	if not v then
		return
	end
	ladderNote.Text = GoalsPanelView.ladderHeader(v)
	for _, row in GoalsPanelView.ladderRows(v) do
		local ui = ladderUis[row.id]
		if ui then
			ui.name.Text = row.name
			ui.line.Text = row.line
			ui.button.Visible = row.action ~= "none"
			ui.bar.track.Visible = row.action == "none"
			setBar(ui.bar, row.frac, row.count)
			ui.button.Text = row.button.text
			Kit.applyLook(ui.button, row.button.look)
			ui.outline.Color = if row.worn then Kit.TEAL else Kit.INK
			ui.outline.Thickness = if row.worn then 4 else 2
		end
	end
	weekTimer.Text = GoalsPanelView.weekTimer(v, os.time() - receivedAt)
	for i, row in GoalsPanelView.challengeRows(v) do
		local ui = challengeUis[i]
		if ui then
			ui.title.Text = row.text
			setBar(ui.bar, row.frac, row.count)
			ui.button.Text = row.button.text
			Kit.applyLook(ui.button, row.button.look)
			ui.reward.Text = row.reward
			ui.bar.fill.BackgroundColor3 = if row.canClaim then Kit.GOLD else Kit.GREEN
		end
	end
	local summary = GoalsPanelView.bookSummary(v)
	setBar(bookBar, summary.frac, summary.text)
	bookBonus.Text = summary.bonus
	for _, row in GoalsPanelView.pageRows(v) do
		local ui = pageUis[row.id]
		if ui then
			ui.title.Text = row.title
			ui.line.Text = row.line
			ui.prize.Text = row.prize
			ui.frame.BackgroundColor3 = if row.state == "hidden" then Color3.fromRGB(232, 228, 240) else Kit.CARD
			ui.prize.TextColor3 = if row.state == "paid" then Kit.TEAL else Kit.INK
		end
	end
end

-- Builds the list with the shop's own list maker.
function GoalsPanel.build(makeList: () -> ScrollingFrame): ScrollingFrame
	goalsList = makeList()
	build(goalsList)
	return goalsList
end

-- `dot(true)` when a challenge or the bonus can be claimed.
function GoalsPanel.start(dot: (boolean) -> ())
	ClientNet.event("GoalsState").OnClientEvent:Connect(function(goals: GoalRules.GoalsView)
		view = goals
		receivedAt = os.time()
		render()
		dot(GoalsPanelView.dot(goals))
	end)
	ClientNet.event("BadgeState").OnClientEvent:Connect(function(badges: Types.BadgeView)
		renderBadges(badges)
	end)
	task.spawn(function()
		while true do
			task.wait(30)
			local v = view
			if v and goalsList.Visible then
				weekTimer.Text = GoalsPanelView.weekTimer(v, os.time() - receivedAt)
			end
		end
	end)
end

return GoalsPanel
