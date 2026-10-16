--!strict
-- First five minutes and comeback hooks on screen (client only; the server decides and pays everything:
-- RetentionService). Shows what the server sends and sends intents only ("Ready", "Gift").
--   FREE GIFT card   in the HUD's left column under PLAY: "in 0:42" counts down to the next play-time gift (1, 3, 5
--                    and 10 minutes of play a day); when one is ready it turns green "OPEN!" and wiggles. Tap = open.
--   gift opened      coin burst + confetti + "+100 coins!" banner
--   away nest        "While you were away, 2 eggs hatched!" card with the coins (and the pet, after a long break)
--   friend / group   a cheer banner with the coins
--   level up         hunter level from the profile stats (Retention.level): "LEVEL 3!" banner + confetti
--   starter pet      after the starter egg show: "YOUR FIRST PET!" + confetti, then the NEXT GOAL card: your pet's
--                    power counting up next to the Void Dragon's, a bar, and HUNT (queues a race) / TRAIN / BATTLE (Pet Battle cards)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Retention = require(Shared.Retention)
local GeodeGen = require(Shared.GeodeGen)
local PetStats = require(Shared.PetStats)
local State = require(script.Parent.State)
local PopupGate = require(script.Parent.PopupGate)
local UI = require(script.Parent.ui.UI)
local Theme = require(script.Parent.ui.Theme)
local PetStyle = require(script.Parent.ui.PetStyle)
local HudArt = require(script.Parent.ui.HudArt)
local Juice = require(script.Parent.ui.Juice)
local Effects = require(script.Parent.Effects)
local StarterEggView = require(script.Parent.StarterEggView)
local SpinView = require(script.Parent.SpinView)

local T = UI.T
local TC = Theme.Color
local RetentionView = {}

local WIDTH = 172 -- the HUD's left column width (PlayButton WIDTH)
local HEIGHT = 60 -- the same card as TOWER / BATTLE (58 squashed the OPEN! pill)
local player = Players.LocalPlayer

local giftBtn: TextButton? = nil
local subLabel: TextLabel? = nil
local readyAt = 0 -- os.clock when the next gift is ready (from the last profile view)
local nextIndex: number? = nil
local readyCount = 0
local styleNow = ""
local stopWiggle: (() -> ())? = nil
local lastLevel: number? = nil
local asked = 0
local lastCheer = 0 -- os.clock of the last reward cheer
local cheer: (string, number?) -> () -- defined below (the profile fallback calls it)

local function fmt(sec: number): string
	sec = math.max(0, math.ceil(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function setStyle(style: string)
	local b = giftBtn
	if not b or styleNow == style then
		return
	end
	styleNow = style
	UI.setStyle(b, style)
	if style == "green" and not stopWiggle then
		stopWiggle = UI.wiggle(b)
	elseif style ~= "green" and stopWiggle then
		(stopWiggle :: () -> ())()
		stopWiggle = nil
	end
end

local function refresh()
	local b, sub = giftBtn, subLabel
	if not b or not sub then
		return
	end
	local lobby = State.Match == nil and player:GetAttribute("MatchKey") == nil and (player:GetAttribute("InTower") ~= true and player:GetAttribute("InBattle") ~= true)
	local p = State.Profile
	-- shown in the lobby while a gift is left today (in a hunt the screen stays on the race)
	b.Visible = lobby and p ~= nil and nextIndex ~= nil and not SpinView.wanted()
	if not b.Visible then
		return
	end
	local left = readyAt - os.clock()
	if readyCount > 0 or left <= 0 then
		sub.Text = "OPEN!"
		setStyle("green")
	else
		sub.Text = "in " .. fmt(left)
		setStyle("blue")
	end
end

local function onProfile()
	local p = State.Profile
	local g = p and p.Gifts
	if type(g) == "table" then
		-- the gift we asked for was opened (the timer moved on) but its notice did not show: cheer from the profile
		local before = nextIndex
		local now = g.NextGift
		if os.clock() - asked < 4 and os.clock() - lastCheer > 4 and before ~= nil and (now == nil or now > before) then
			local p0 = State.Profile
			local paid = p0 and p0.Gifts and p0.Gifts.Coins and p0.Gifts.Coins[before]
			cheer("+" .. UI.num(tonumber(paid) or 0) .. " COINS!", tonumber(paid))
		end
		nextIndex = g.NextGift
		readyCount = tonumber(g.Ready) or 0
		readyAt = os.clock() + (tonumber(g.NextIn) or 0)
	end
	-- hunter level pop (the first profile only sets the baseline, so joining never plays it)
	if p and p.Stats then
		local lv = Retention.level(Retention.xp(p.Stats))
		if lastLevel and lv > lastLevel then
			task.delay(1.2, PopupGate.later, "Toast", function() -- never over a fight
				Juice.banner("LEVEL " .. lv .. "!", TC.Gold, 2)
				Effects.confetti()
			end)
		end
		lastLevel = lv
	end
	refresh()
end

local function openGift()
	local b = giftBtn
	if not b then
		return
	end
	if readyCount <= 0 and readyAt - os.clock() > 0 then
		-- a shake alone read as "nothing happened" (Studio check): say how long is left
		Juice.nope(b)
		local left = math.max(1, math.ceil(readyAt - os.clock()))
		Juice.floatText(b, string.format("Next gift in %d:%02d", left // 60, left % 60), TC.Gold)
		return
	end
	if os.clock() - asked < 1 then
		return
	end
	asked = os.clock()
	Net.event("RetentionAction"):FireServer("Gift")
end

-- A big "+50" over `src` that springs in, holds and floats up: about 1.6 s on screen (Juice.floatText is a quick one).
local function bigPop(src: GuiObject, text: string)
	local layer = UI.noticeLayer()
	local at = src.AbsolutePosition + src.AbsoluteSize / 2
	local l = UI.text(layer, text, {
		Name = "GiftPop", Font = UI.Head, TextSize = 52, TextColor3 = TC.Gold, Outline = "Strong",
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X + src.AbsoluteSize.X * 0.35, at.Y), Size = UDim2.fromOffset(220, 64),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 60,
	})
	l.TextWrapped = false
	UI.pop(l, 0.2)
	if not UI.Reduced then
		TweenService:Create(l, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = l.Position - UDim2.fromOffset(0, 70) }):Play()
	end
	task.delay(1.2, function()
		if not l.Parent then
			return
		end
		local fade = TweenInfo.new(0.4)
		TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
		local o = l:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			TweenService:Create(o, fade, { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(l, 1.8)
end

-- Big, obvious reward feedback (Studio proof 2026-10-14: the first version was too quick to see): a banner held
-- 2.5 s in the middle of the screen, confetti across the screen and from the button, flying coins, and a big
-- "+50" pop over the button that floats for over a second.
function cheer(text: string, coins: number?)
	lastCheer = os.clock()
	Juice.banner(text, TC.Gold, 2.5)
	Effects.confetti()
	local b = giftBtn
	local src: GuiObject? = if b and b.Visible then b else nil
	if src then
		Juice.confetti(src, 30)
		if coins and coins > 0 then
			Juice.coins(src, 10)
			bigPop(src, "+" .. UI.money(coins))
			Effects.cashFly(nil, coins)
		end
		Juice.rays(src, TC.Gold, 1.4)
	end
end

-- Runs `fn` now if the player is free, else once they are back in the lobby: the one popup gate (PopupGate, Card).
local function whenCalm(fn: (...any) -> (), ...: any)
	local args = table.pack(...)
	PopupGate.later("Card", function()
		fn(table.unpack(args, 1, args.n))
	end)
end

-- The away-nest card: a small dialog that says what hatched while the player was gone.
local function awayCard(data: { [string]: any })
	local layer = UI.dialogLayer()
	local old = layer:FindFirstChild("AwayNest")
	if old then
		old:Destroy()
	end
	local card = UI.card(layer, "panel", {
		Name = "AwayNest", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 210), ZIndex = 30,
	})
	local eggs = tonumber(data.Eggs) or 1
	local title = if data.WelcomeBack then "WELCOME BACK!" else "YOU'RE BACK!"
	UI.text(card, title, { Name = "Title", Font = UI.Head, TextSize = T.Title, TextColor3 = TC.Gold, Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	local line = "While you were away, " .. eggs .. (if eggs == 1 then " egg" else " eggs") .. " hatched in your nest!"
	UI.text(card, line, { Name = "Line", Font = UI.Bold, TextSize = T.Body, Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 48), TextXAlignment = Enum.TextXAlignment.Center })
	local got = "+" .. UI.num(tonumber(data.Coins) or 0) .. " coins"
	if type(data.Pet) == "table" then
		got ..= " and a " .. GeodeGen.displayName(data.Pet :: any) .. "!"
	end
	UI.text(card, got, { Name = "Got", Font = UI.Head, TextSize = T.Head, TextColor3 = TC.Gold, Position = UDim2.fromOffset(16, 104), Size = UDim2.new(1, -32, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	UI.button(card, "YAY!", "gold", function()
		card:Destroy()
	end, { Name = "Ok", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(150, T.Touch) })
	UI.pop(card, 0.4)
	Effects.confetti()
end

-- NEXT GOAL card after the first hatch: what to chase (the 1 in 1000 Void Dragon) and the two real ways to get
-- stronger from here (the core loop: FIND -> TRAIN -> FIGHT). Only shows numbers (PetStats is the same rule the server uses); buttons send intents only.
function RetentionView.goalCard(pet: any)
	if type(pet) ~= "table" or type(pet.Mineral) ~= "string" then
		return
	end
	local layer = UI.dialogLayer()
	local old = layer:FindFirstChild("NextGoal")
	if old then
		old:Destroy()
	end
	local ok, stats = pcall(PetStats.roll, pet, 0)
	local power = if ok and stats then math.floor(stats.Power) else 0
	local dream = math.floor(Retention.dreamPower())
	local card = UI.card(layer, "panel", {
		Name = "NextGoal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 250), ZIndex = 30,
	})
	UI.text(card, "NEXT GOAL!", { Name = "Title", Font = UI.Head, TextSize = T.Title, TextColor3 = TC.Gold, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	local name = string.upper(GeodeGen.displayName(pet :: any))
	local mine = UI.text(card, "YOUR " .. name .. ": \u{26A1}0", { Name = "Mine", Font = UI.Bold, TextSize = T.Body, Position = UDim2.fromOffset(16, 52), Size = UDim2.new(1, -32, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	UI.countUp(mine, 0, power, 1.2, function(n: number): string
		return "YOUR " .. name .. ": \u{26A1}" .. UI.num(math.floor(n))
	end)
	UI.text(card, "VOID DRAGON (1 in 1000): \u{26A1}" .. UI.num(dream), { Name = "Dream", Font = UI.Bold, TextSize = T.Body, TextColor3 = Theme.Pet.RibbonPink, Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	-- the progress track: the pale inset of the sheets with the quest bar's blue edge (UI.bar's colours)
	local track = UI.frame(card, { Name = "Track", BackgroundColor3 = TC.Inset, Position = UDim2.fromOffset(24, 116), Size = UDim2.new(1, -48, 0, 18) })
	UI.corner(track, 9)
	PetStyle.edge(track, Theme.Pet.QuestEdge, 1.5)
	local fill = UI.frame(track, { Name = "Fill", BackgroundColor3 = TC.Gold, Size = UDim2.fromScale(0, 1) })
	UI.corner(fill, 9)
	local frac = math.max(Retention.dreamProgress(power), 0.03)
	TweenService:Create(fill, TweenInfo.new(if UI.Reduced then 0 else 1.2, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(frac, 1) }):Play()
	UI.text(card, "Hunt eggs, train your pet and win battles to get stronger!", { Name = "How", Font = UI.Bold, TextSize = T.Small, Position = UDim2.fromOffset(16, 140), Size = UDim2.new(1, -32, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	-- HUNT queues a race; TRAIN / BATTLE open Pet Battle's own cards (ui/PvpPanel, loaded on tap so boot order never matters)
	type Choice = { Name: string, Text: string, Style: string, Go: () -> () }
	local choices: { Choice } = {
		{ Name = "Hunt", Text = "HUNT", Style = "gold", Go = function()
			Net.event("PartyAction"):FireServer("Queue")
		end },
		{ Name = "Train", Text = "TRAIN", Style = "blue", Go = function()
			require(script.Parent.ui.PvpPanel).openTrain()
		end },
		{ Name = "Battle", Text = "BATTLE", Style = "red", Go = function()
			require(script.Parent.ui.PvpPanel).openBattle()
		end },
	}
	local bw, gap = 104, 8
	for i, c in choices do
		UI.button(card, c.Text, c.Style, function()
			card:Destroy()
			c.Go()
		end, { Name = c.Name, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, (i - 2) * (bw + gap), 1, -12), Size = UDim2.fromOffset(bw, T.Touch) })
	end
	UI.closeButton(card, function()
		card:Destroy()
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8) })
	UI.pop(card, 0.4)
	Juice.rays(card, TC.Gold, 1.4)
	-- never stays up: gone after PopupRules.CardLife, or at once when a hunt / climb / battle starts under it
	local shownAt = os.clock()
	task.spawn(function()
		while card.Parent do
			if not PopupGate.cardStays(os.clock() - shownAt) then
				card:Destroy()
				break
			end
			task.wait(0.25)
		end
	end)
end

local function onRetention(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "Gift" then
		if os.clock() - lastCheer < 2 then
			return -- the profile fallback already cheered for this gift
		end
		cheer("+" .. UI.num(tonumber(data.Coins) or 0) .. " COINS!", tonumber(data.Coins))
	elseif kind == "GiftReady" then
		readyCount = math.max(readyCount, 1)
		refresh()
		local b = giftBtn
		if b and b.Visible then
			UI.pop(b, 0.6)
		end
	elseif kind == "Away" then
		task.delay(2, whenCalm, awayCard, data) -- after the loading screen and the first look around; never over a fight
	elseif kind == "Friend" then
		cheer(string.upper(tostring(data.Name or "FRIEND")) .. " IS HERE! +" .. UI.num(tonumber(data.Coins) or 0) .. " COINS", tonumber(data.Coins))
	elseif kind == "Group" then
		cheer("GROUP GIFT! +" .. UI.num(tonumber(data.Coins) or 0) .. " COINS", tonumber(data.Coins))
	end
end

local function build()
	local screen = UI.screen()
	local left = screen:FindFirstChild("Left", true) -- the HUD's left column list (under PLAY); else a fixed spot
	local b = HudArt.bigButton(left or screen, {
		Name = "FreeGift", Style = "blue", Art = "IconDaily", Title = "GIFT", Sub = "in 1:00", Width = WIDTH, Height = HEIGHT, LayoutOrder = 55,
		OnClick = openGift,
	})
	if not left then
		b.Position = UDim2.fromOffset(T.Edge, T.Edge + 160)
	end
	b.Visible = false
	giftBtn = b
	subLabel = b:FindFirstChild("Sub", true) :: TextLabel?
	styleNow = "blue"
end

function RetentionView.start()
	build()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			onProfile()
		elseif what == "Match" then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("MatchKey"):Connect(refresh)
	player:GetAttributeChangedSignal("InTower"):Connect(refresh)
	player:GetAttributeChangedSignal("InBattle"):Connect(refresh)
	Net.event("Retention").OnClientEvent:Connect(onRetention)
	StarterEggView.Hatched.Event:Connect(function(pet)
		cheer("YOUR FIRST PET!")
		task.delay(2.6, whenCalm, RetentionView.goalCard, pet) -- never over a hunt, tower or Pet Battle
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	onProfile()
	Net.event("RetentionAction"):FireServer("Ready") -- any waiting notice (away nest, friend gift) comes now
end

return RetentionView
