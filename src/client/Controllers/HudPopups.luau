--!strict
-- The HUD's celebrations: the heads-in-a-row counter and its prize pop, the
-- friend 2x chip, and the big "Welcome back" card. Words and numbers come from
-- StreakView (tested); this file only draws and animates. Owned by the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)
local EventText = require(ReplicatedStorage.Shared.Util.EventText)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local StreakView = require(ReplicatedStorage.Shared.Util.StreakView)
local CameraView = require(script.Parent.CameraView)
local Sounds = require(script.Parent.Sounds)
local UiStyle = require(script.Parent.UiStyle)

local HudPopups = {}

local player = Players.LocalPlayer

local INK = UiStyle.INK
local WHITE = UiStyle.WHITE
local GOLD = UiStyle.GOLD
local corner = UiStyle.corner
local stroke = UiStyle.stroke
local label = UiStyle.label
local textLimit = UiStyle.textLimit

local gui: ScreenGui
local streakChip: TextLabel
local streakScale: UIScale
local streakHint: TextLabel
local alertChip: TextLabel
local alertTap: TextButton
local alertHook: { fn: (string) -> () } = { fn = function() end }
local shownAlert = ""
local eventView: Types.EventView? = nil
local giftView: Types.PlayGiftView? = nil
local giftAt = 0
local friendMult: number? = nil
local lastStreak = 0
local streakToken = 0
local pulse: Tween? = nil
local welcome: Frame? = nil
local alertScale: UIScale

local function setMax(g: GuiObject, height: number)
	local c = g:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = math.max(HudLayout.MIN_TEXT, math.floor(height * 0.75))
	end
end

local function place(g: GuiObject, r: HudLayout.Rect)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + r.h / 2)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

-- A solid, outlined chip (same look as the HUD's other chips).
local function chip(name: string, fill: Color3): TextLabel
	local l = label({ Name = name, Text = "", TextColor3 = WHITE })
	textLimit(l, 24)
	l.BackgroundColor3 = fill
	l.BackgroundTransparency = 0
	corner(l, 0.4)
	stroke(l, 3)
	local outline = l:FindFirstChild("TextOutline")
	if outline and outline:IsA("UIStroke") then
		outline.Thickness = 1.5
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0.06, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.Parent = l
	l.Visible = false
	l.Parent = gui
	return l
end

local function confetti(count: number, fromY: number)
	local colors = { GOLD, UiStyle.GREEN, UiStyle.BLUE, UiStyle.RED, UiStyle.PURPLE, UiStyle.ORANGE }
	for i = 1, count do
		local bit = Instance.new("Frame")
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Position = UDim2.fromScale(0.5, fromY)
		bit.Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20))
		bit.Rotation = math.random(0, 360)
		bit.BackgroundColor3 = colors[(i % #colors) + 1]
		bit.BorderSizePixel = 0
		bit.ZIndex = 30
		corner(bit, 0.3)
		bit.Parent = gui
		local angle = math.random() * math.pi * 2
		local reach = 0.12 + math.random() * 0.3
		local goal = UDim2.fromScale(0.5 + math.cos(angle) * reach, fromY + math.sin(angle) * reach * 0.8 + 0.12)
		local fly = TweenService:Create(
			bit,
			TweenInfo.new(0.9 + math.random() * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = goal, Rotation = bit.Rotation + math.random(-300, 300), BackgroundTransparency = 1 }
		)
		fly:Play()
		fly.Completed:Connect(function()
			bit:Destroy()
		end)
	end
end

-- Streak counter ----------------------------------------------------------

local function stopPulse()
	if pulse then
		pulse:Cancel()
		pulse = nil
	end
	streakScale.Scale = 1
end

local function hideStreak()
	streakToken += 1
	stopPulse()
	streakChip.Visible = false
	streakHint.Visible = false
end

local function showWin(cash: number, hats: number, goal: number)
	local pop = Instance.new("Frame")
	pop.Name = "StreakWin"
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Position = UDim2.fromScale(0.5, 0.3)
	pop.Size = UDim2.fromScale(0.5, 0.3)
	pop.BackgroundTransparency = 1
	pop.ZIndex = 20
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 190)
	limit.Parent = pop
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = pop
	local title = label({
		Name = "Title",
		Text = StreakView.winTitle(goal),
		TextColor3 = GOLD,
		Size = UDim2.fromScale(1, 0.55),
		ZIndex = 21,
	})
	textLimit(title, 64)
	title.Parent = pop
	local prize = label({
		Name = "Prize",
		Text = StreakView.winLine(cash, hats),
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.38),
		ZIndex = 21,
	})
	textLimit(prize, 40)
	prize.Parent = pop
	pop.Parent = gui
	TweenService:Create(scale, UiStyle.BOUNCY, { Scale = 1 }):Play()
	Sounds.play("Mega", 0.7)
	CameraView.shake(0.4, 0.5)
	confetti(30, 0.3)
	task.delay(2.6, function()
		for _, child in pop:GetChildren() do
			if child:IsA("TextLabel") then
				UiStyle.fadeText(child, 1)
			end
		end
		task.wait(UiStyle.COUNT.Time + 0.05)
		pop:Destroy()
	end)
end

local function showStreak(streak: number, goal: number)
	streakToken += 1
	local stage = StreakView.stage(streak, goal)
	streakChip.Text = StreakView.counter(streak, goal)
	streakChip.BackgroundColor3 = if stage == "drama" then UiStyle.RED else UiStyle.ORANGE
	streakChip.Visible = true
	UiStyle.popScale(streakScale, StreakView.pop(streak, goal))
	local hint = StreakView.hint(streak, goal)
	streakHint.Text = hint
	streakHint.Visible = hint ~= ""
	Sounds.play("Combo", 0.5, 1 + 0.12 * streak)
	local power = StreakView.shake(streak, goal)
	if power > 0 then
		CameraView.shake(power, 0.3)
	end
	-- Dramatic: the counter keeps throbbing until the next flip decides it.
	stopPulse()
	if stage == "drama" then
		local beat = TweenService:Create(
			streakScale,
			TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.12 }
		)
		beat:Play()
		pulse = beat
	end
end

local function showLost(streak: number)
	streakToken += 1
	local token = streakToken
	stopPulse()
	streakChip.Text = StreakView.lostLine(streak)
	streakChip.BackgroundColor3 = UiStyle.GREY
	streakChip.Visible = true
	streakHint.Visible = false
	Sounds.play("Skull", 0.4)
	task.delay(1.4, function()
		if token == streakToken then
			streakChip.Visible = false
		end
	end)
end

function HudPopups.onFlipped(ev: Types.FlipEvent, goal: number)
	if ev.ownerId ~= player.UserId or ev.byHelper or ev.combo < 1 then
		return
	end
	if ev.streakWin then
		lastStreak = 0
		hideStreak()
		showWin(ev.streakCash, ev.streakHats, goal)
	elseif ev.streak >= StreakView.SHOW_FROM then
		lastStreak = ev.streak
		showStreak(ev.streak, goal)
	elseif ev.streak == 0 then
		local was = lastStreak
		lastStreak = 0
		if StreakView.worthMourning(was) then
			showLost(was)
		else
			hideStreak()
		end
	else
		lastStreak = ev.streak
		hideStreak()
	end
end

-- Alert chip: friend 2x, weekend event and "gift ready" take turns --------

local ALERT_COLORS: { [string]: Color3 } = {
	gift = UiStyle.GREEN,
	event = UiStyle.PURPLE,
	friend = UiStyle.BLUE,
}

local function refreshAlert()
	local now = os.time()
	local list = EventText.alerts(eventView, giftView, os.clock() - giftAt, friendMult, now)
	local pick = EventText.pick(list, os.clock())
	if not pick then
		alertChip.Visible = false
		shownAlert = ""
		return
	end
	if pick.kind == "event" and eventView and eventView.rain then
		alertChip.BackgroundColor3 = UiStyle.BLUE
	else
		alertChip.BackgroundColor3 = ALERT_COLORS[pick.kind] or UiStyle.ORANGE
	end
	alertChip.Text = pick.text
	alertChip.Visible = true
	alertTap.Active = pick.tap
	alertTap.Visible = pick.tap
	if shownAlert ~= pick.kind then
		shownAlert = pick.kind
		UiStyle.popScale(alertScale, 1.15)
	end
end

function HudPopups.setFriend(on: boolean)
	friendMult = if on then Config.FRIEND_CASH_MULT else nil
	refreshAlert()
end

function HudPopups.setEvent(view: Types.EventView)
	eventView = view
	refreshAlert()
end

function HudPopups.setGifts(view: Types.PlayGiftView)
	giftView = view
	giftAt = os.clock()
	refreshAlert()
end

-- fn(kind) runs when a tappable alert (a ready gift) is pressed.
function HudPopups.onAlertTap(fn: (string) -> ())
	alertHook.fn = fn
end

-- Call about once a second: keeps countdowns and the turn-taking moving.
function HudPopups.tick()
	refreshAlert()
end

-- Welcome back --------------------------------------------------------------

function HudPopups.welcomeBack(text: string)
	if welcome then
		welcome:Destroy()
		welcome = nil
	end
	local dim = Instance.new("Frame")
	dim.Name = "WelcomeBack"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = INK
	dim.BackgroundTransparency = 1
	dim.ZIndex = 40
	dim.Active = true
	dim.Parent = gui
	welcome = dim
	TweenService:Create(dim, UiStyle.COUNT, { BackgroundTransparency = 0.45 }):Play()

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.6, 0.7)
	card.BackgroundColor3 = UiStyle.PANEL
	card.ZIndex = 41
	corner(card, 0.12)
	stroke(card, 5)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(260, 200)
	limit.MaxSize = Vector2.new(520, 340)
	limit.Parent = card
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.05, 0)
	pad.PaddingBottom = UDim.new(0.06, 0)
	pad.Parent = card
	card.Parent = dim

	local title = label({
		Name = "Title",
		Text = PanelView.AWAY_TITLE,
		TextColor3 = GOLD,
		Size = UDim2.fromScale(1, 0.24),
		ZIndex = 42,
	})
	textLimit(title, 44)
	title.Parent = card
	local sun = label({
		Name = "Sun",
		Text = "🪙",
		Position = UDim2.fromScale(0, 0.26),
		Size = UDim2.fromScale(1, 0.26),
		ZIndex = 42,
		TextStrokeTransparency = 1,
	})
	textLimit(sun, 56)
	sun.Parent = card
	local line = label({
		Name = "Line",
		Text = PanelView.awayLine(text),
		TextColor3 = UiStyle.GREEN,
		Position = UDim2.fromScale(0, 0.53),
		Size = UDim2.fromScale(1, 0.2),
		ZIndex = 42,
	})
	textLimit(line, 38)
	line.Parent = card
	local grab = UiStyle.button("GRAB IT!", UiStyle.GREEN, function()
		Sounds.play("Tap", 0.4)
		if welcome == dim then
			welcome = nil
		end
		local fade = TweenService:Create(dim, UiStyle.FAST, { BackgroundTransparency = 1 })
		fade:Play()
		TweenService:Create(scale, UiStyle.FAST, { Scale = 0.01 }):Play()
		task.delay(0.2, function()
			dim:Destroy()
		end)
	end)
	grab.AnchorPoint = Vector2.new(0.5, 1)
	grab.Position = UDim2.fromScale(0.5, 1)
	grab.Size = UDim2.fromScale(0.6, 0.2)
	grab.ZIndex = 42
	textLimit(grab, 34)
	grab.Parent = card

	TweenService:Create(scale, UiStyle.BOUNCY, { Scale = 1 }):Play()
	-- the coin spins while the card is up
	TweenService
		:Create(sun, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 14 })
		:Play()
	Sounds.play("Gift", 0.8)
	confetti(24, 0.35)
	task.delay(9, function()
		if welcome == dim and dim.Parent then
			welcome = nil
			dim:Destroy()
		end
	end)
end

-- Setup ---------------------------------------------------------------------

function HudPopups.setLayout(l: HudLayout.Layout)
	place(streakChip, l.streak)
	setMax(streakChip, l.streak.h)
	place(alertChip, l.alert)
	setMax(alertChip, l.alert.h)
	streakHint.AnchorPoint = Vector2.new(0.5, 0)
	streakHint.Position = UDim2.fromOffset(l.streak.x + l.streak.w / 2, l.streak.y + l.streak.h + 2)
	streakHint.Size = UDim2.fromOffset(l.streak.w, 26)
end

function HudPopups.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "CoinFlickHudPop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 11 -- above panels and toasts
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	streakChip = chip("Streak", UiStyle.ORANGE)
	streakScale = Instance.new("UIScale")
	streakScale.Parent = streakChip
	streakHint = label({ Name = "Hint", Text = "", TextColor3 = GOLD, ZIndex = 5 })
	textLimit(streakHint, 24)
	streakHint.Visible = false
	streakHint.Parent = gui
	alertChip = chip("Alert", UiStyle.BLUE)
	alertScale = Instance.new("UIScale")
	alertScale.Parent = alertChip
	alertTap = Instance.new("TextButton")
	alertTap.Name = "Tap"
	alertTap.BackgroundTransparency = 1
	alertTap.Text = ""
	alertTap.Size = UDim2.fromScale(1, 1)
	alertTap.ZIndex = 6
	alertTap.Visible = false
	alertTap.Activated:Connect(function()
		alertHook.fn(shownAlert)
	end)
	alertTap.Parent = alertChip
	gui.Parent = player:WaitForChild("PlayerGui")
	HudPopups.setLayout(HudLayout.compute(844, 390, true)) -- redone by the HUD
end

return HudPopups
