--!strict
-- DAILY: the daily login gift (7-day streak, day 7 pays the most) and today's three quests (Find The Pet part 2).
-- Everything shown comes from the server's profile view (`prof.Daily`, built by shared/Quests.view); the buttons
-- only send claims (ShopAction "ClaimGift" / "ClaimQuest", index) and the server decides and pays. Coins only.
-- Entry point: QuestPanel.open() (the HUD "Daily" tile).

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local UiKit = require(Shared.UiKit)
local LaunchPerks = require(Shared.LaunchPerks)
local RobuxConfig = require(Shared.RobuxConfig)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local Juice = require(script.Parent.Juice)
local HudArt = require(script.Parent.HudArt)
local PanelSkin = require(script.Parent.PanelSkin)
local PetStyle = require(script.Parent.PetStyle)
local ShopEgg = require(script.Parent.ShopEgg)

local T = UI.T
local TC = Theme.Color
local PET = Theme.Pet
local QuestPanel = {}

local body: any = nil
local isOpen = false
local openPanel: Instance? = nil -- the panel isOpen belongs to; an older panel closing late must not clear it
local started = false
-- Celebrations play only once the server's profile shows the claim went through (never on the tap itself).
local giftAsked = false -- OPEN was tapped and the gift was still ready
local questAsked: { [number]: boolean } = {} -- CLAIM was tapped for quest i

local function shop(action: string, id: any?)
	Net.event("ShopAction"):FireServer(action, id)
end

-- "5h 12m" / "12m" until the UTC midnight turnover.
local function untilText(at: number): string
	local left = math.max(0, at - os.time())
	local h = math.floor(left / 3600)
	local m = math.floor((left % 3600) / 60)
	return if h > 0 then (h .. "h " .. m .. "m") else (math.max(m, 1) .. "m")
end

-- Pet style (Theme.Pet, docs/UI_STYLE_REF.md): the white patterned sheet comes from UI.modal; the gift box and the
-- quest rows are light QuestBody cards with the soft blue QuestEdge, headings in the clip's QuestTitle blue, body words
-- in the deep title blue (no outline on the light cards), the seven days as glossy blue tiles (day 7 gold), the streak
-- and the next-gift countdown on the tilted yellow Tag, CLAIM / OPEN as lime pills (UI.button "gold" draws lime).
-- Picture slots (HudArt.Buttons daily_*) stay off under the pet style (HudArt.skin returns false).
local NAVY, BLUE, BAR = PET.TitleEdge, PET.QuestTitle, PET.Blue
local box, content, word = PanelSkin.box, PanelSkin.content, PanelSkin.word

-- The tilted yellow tag (the clip's "NEXT UP!"): gold fill, brown edge, dark words. Returns the tag and its label.
-- `light` draws the words white with the dark outline instead (the small "Streak 1" in brown on orange was hard to
-- read at phone size, Studio check 2026-10-15).
local function tag(parent: Instance, text: string, size: number, props: { [string]: any }, light: boolean?): (Frame, TextLabel)
	local f = UI.frame(parent, props)
	f.Name = props.Name or "Tag"
	f.BackgroundColor3 = PET.Tag
	PetStyle.round(f, 999)
	PetStyle.edge(f, PET.TagEdge, 2)
	PetStyle.vgrad(f, PET.Gold:Lerp(PET.White, 0.25), PET.Tag)
	local l = word(f, text, size, {
		Name = "Text", Font = UI.Head, TextColor3 = if light then PET.White else PET.TagEdge, Outline = if light then "Normal" else false,
		Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = f.ZIndex + 1,
	})
	return f, l
end

-- Short landscape screens (the Studio 844 x 390 window, landscape phones: under 420 logical px tall) see the quest
-- list through a ~200 px window. The gift box compacts there (streak tag beside the heading, no coin picture on the
-- day tiles, less padding) so one whole quest row shows under it without scrolling.
local function shortScreen(): boolean
	return not UI.isPortrait() and UI.Logical.Y < 420
end

-- How much shorter (logical px) the quest window should be (its height now plus `extra`) so that, at the top, it
-- ends on a whole row (UiKit.snapCut, like UI.rowCut). Pixels per logical px come from the gift box's own drawn
-- height against the height it was given, so the cut is right under any stack of UIScales above the list (the
-- layer's, the menu's pop-in spring, a preview wrapper): a guessed scale cut the first quest row mid-way.
local function rowCut(sc: ScrollingFrame, extra: number): number
	local gift = sc:FindFirstChild("Gift") :: GuiObject?
	local k = if gift and gift.AbsoluteSize.Y > 0 and gift.Size.Y.Offset > 0 then gift.AbsoluteSize.Y / gift.Size.Y.Offset else math.max(UI.Scale, 0.01)
	local window = sc.AbsoluteWindowSize.Y / k + extra
	local top = sc.AbsolutePosition.Y
	local bottoms: { number } = {}
	local heights: { number } = {}
	for _, c in sc:GetChildren() do
		if c:IsA("GuiObject") and c.Visible and c.AbsoluteSize.Y > 0 then
			table.insert(bottoms, (c.AbsolutePosition.Y + c.AbsoluteSize.Y - top) / k + sc.CanvasPosition.Y + 2)
			table.insert(heights, c.AbsoluteSize.Y / k)
		end
	end
	return UiKit.snapCut(bottoms, window, nil, heights)
end

local MORE_H = 62 -- footer strip under the list for the MORE QUESTS button (it overlapped the third quest)
local MORE_H_TIGHT = 46 -- the same on a very short landscape phone, where the list needs every stud

local function oneLine(b: GuiButton)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.TextWrapped = false
		-- the button is built before the list lays out (size 0), so a one-off fit leaves the words tiny: scale with the box
		UI.fit(l, T.Body + 4, T.MinText) -- the shared text floor (14 logical, 12 real px), re-fitted with the scale
	end
end

-- The free egg the day 7 gift banks (LaunchPerks.StreakEgg): its shop look in a still viewport (ShopEgg: drawn
-- stand-in parts, or the owner's egg picture when RobuxConfig has one; no asset ids invented here).
local function streakEgg(parent: Instance, props: { [string]: any }): GuiObject
	local id = LaunchPerks.StreakEgg.Egg
	local egg = RobuxConfig.egg(id)
	local v = ShopEgg.view(parent, id, props, { Spin = false, Halo = false, Variant = 1, Yaw = -25, Image = if egg then egg.Image else nil })
	v.Name = "FreeEgg"
	return v
end

-- OPEN +N: the owner's OPEN picture (word baked in) drawn whole, with the coin amount in a small badge on its corner.
local function openPicture(b: TextButton, reward: number)
	local k = HudArt.Buttons.btn_open
	if Theme.PetStyle or not HudArt.hasSkin("btn_open") then
		HudArt.skin(b, "btn_yellow", 48) -- the pet style keeps the drawn lime pill with "OPEN +N" on it
		return
	end
	b.BackgroundTransparency = 1
	for _, c in b:GetChildren() do
		if c:IsA("UIStroke") then
			c.Enabled = false
		elseif c:IsA("GuiObject") then
			c.Visible = false
		end
	end
	local r = k.Rect
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	-- the picture keeps the left part and the amount sits beside it, never on the word (+25 covered OPEN, Studio #187)
	img.Size = UDim2.fromScale(0.68, 1)
	img.Image = k.Image
	img.ImageRectOffset = Vector2.new(r[1], r[2])
	img.ImageRectSize = Vector2.new(r[3], r[4])
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 0
	img.Parent = b
	tag(b, "+" .. reward, T.Body, { Name = "Amount", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.3, 0.7), ZIndex = 3 })
end

local function render()
	if not isOpen or not body or not body.Parent then
		return
	end
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local prof = State.Profile
	local daily = prof and prof.Daily
	if not daily then
		UI.loadingState(body, "Loading daily quests")
		return
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Daily gift: title and OPEN on top, the seven days under it ---------------------------------------
	local gift = daily.Gift
	local short = shortScreen()
	-- the top row holds the OPEN button: at least 44 real px tall whatever the scale (UI.minTouch)
	local topH = math.max(48, UI.minTouch())
	local padY = if short then 5 else 8
	local stripH = if short then 54 else 80 -- the day tiles' row (about 50 px tiles on a short screen, 75 otherwise)
	local giftH = padY * 2 + topH + 6 + stripH -- 150 at the design size, ~124 on a short screen
	local gc = box(body, "Gift", PET.QuestBody, PET.QuestEdge, 3, { Size = UDim2.new(1, -6, 0, giftH), LayoutOrder = nextOrder() })
	HudArt.skin(gc, "daily_gift_box", giftH)
	PetStyle.pattern(gc, PET.QuestEdge, 0.82, 34, 540, giftH, 80)
	local gin = content(gc) -- pictures and layouts never share a parent (a layout would place the picture too)
	UI.pad(gin, 10, padY)
	UI.list(gin, Enum.FillDirection.Vertical, 6)
	local top = UI.frame(gin, { Name = "Top", Size = UDim2.new(1, 0, 0, topH), BackgroundTransparency = 1, LayoutOrder = 1 })
	-- placed by position, not a list layout: a word picture (HudArt.word) anchors on its label's centre line, which a
	-- list layout pushed half a line down, so the "Day 7" line showed behind the Day 1 / Day 2 tiles
	local titles = UI.frame(top, { Name = "Titles", Size = UDim2.fromScale(0.58, 1), BackgroundTransparency = 1, ClipsDescendants = true })
	-- the streak tag sits under the heading, or beside it on a short screen (the box has no second line there)
	local CHIP_H = if short then 26 else 24
	local gTitle = word(titles, "Daily Gift", T.Head + 4, {
		Name = "Title", Font = UI.Head, TextColor3 = BLUE, Outline = false,
		Size = if short then UDim2.fromScale(0.46, 1) else UDim2.fromScale(1, 0.55),
	})
	HudArt.word(gTitle)
	local streak = gift.Streak or 0
	if streak > 0 then
		-- the streak sits on a tilted yellow tag: star + "Streak N", the shield count and the gift multiplier (hidden at 0)
		local parts = { "Streak " .. streak }
		if (gift.Shields or 0) > 0 then
			table.insert(parts, "Shields " .. gift.Shields)
		end
		if (gift.Mult or 1) > 1 then
			table.insert(parts, "x" .. string.format("%.2g", gift.Mult))
		end
		-- white words with the dark outline at body size: the brown-on-orange caption was too faint at phone size
		local chipProps = if short
			then { Name = "StreakChip", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.47, 0, 0.5, 0), Size = UDim2.new(0.53, 0, 0, CHIP_H), Rotation = -2 }
			else { Name = "StreakChip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, 0), Size = UDim2.new(0.74, 0, 0, CHIP_H), Rotation = -2 }
		local chip, chipText = tag(titles, table.concat(parts, if short then " \u{b7} " else "  \u{b7}  "), T.Body, chipProps, true)
		chipText.Name = "StreakText"
		chipText.Size = UDim2.new(1, -32, 1, 0)
		chipText.Position = UDim2.fromOffset(26, 0)
		chipText.TextXAlignment = Enum.TextXAlignment.Left
		UI.icon(chip, "star", 16, { Name = "StreakIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = chip.ZIndex + 1 })
	else
		HudArt.word(word(titles, "Day 7 is the big one!", T.Small, {
			Name = "Sub", Font = UI.Bold, TextColor3 = NAVY, Outline = false,
			Position = if short then UDim2.fromScale(0.47, 0) else UDim2.fromScale(0, 0.58),
			Size = if short then UDim2.fromScale(0.53, 1) else UDim2.fromScale(1, 0.42),
		}))
	end
	local bProps = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.4, 1), TextSize = T.Head }
	if gift.Ready then
		local open: TextButton
		open = UI.button(top, "OPEN +" .. gift.Reward, "gold", function()
			giftAsked = true
			Juice.coinSource(open) -- the gift's coins fly from here once the server pays
			shop("ClaimGift")
		end, bProps)
		open.Name = "ClaimGift"
		openPicture(open, gift.Reward)
		Juice.pulse(open, nil, T.Radius) -- ready to open: a soft glow breathes round it
		Juice.shake(open) -- the gift waits: a little shake every couple of seconds
	else
		-- a friendly countdown, not a dead grey button: the yellow tag with a clock and dark words
		local nextPill, nextText = tag(top, "Next gift in " .. untilText(daily.NextReset), T.Body, { Name = "Next", AnchorPoint = bProps.AnchorPoint, Position = bProps.Position, Size = UDim2.fromScale(0.4, 0.86), Rotation = -2 }, true)
		UI.icon(nextPill, "clock", 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = nextPill.ZIndex + 1 })
		nextText.Position = UDim2.fromOffset(36, 0)
		nextText.Size = UDim2.new(1, -42, 1, 0)
		if giftAsked then
			-- the server took the claim: the box pops with confetti
			giftAsked = false
			UI.pop(gc, 1.06)
			task.defer(Juice.confetti, gc, 22)
		end
	end
	-- the 7 streak days: one row of equal glossy blue tiles. Claimed days grey with a big tick, today's claimable day a
	-- green ring with TODAY on it, day 7 marked only by its gold colour and a star (Studio: day 7 sat taller and
	-- day 1 was gold like day 7, so the current day was unclear)
	local strip = UI.frame(gin, { Name = "Days", Size = UDim2.new(1, 0, 0, stripH), BackgroundTransparency = 1, LayoutOrder = 2 })
	local sl = UI.list(strip, Enum.FillDirection.Horizontal, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	sl.Padding = UDim.new(0.008, 0)
	local n = #gift.Rewards
	local W = (1 - 0.008 * math.max(n - 1, 0)) / math.max(n, 1) - 0.002 -- every day the same width, gaps included
	for i, coins in gift.Rewards do
		local isNext = i == gift.StreakDay
		local today = isNext and gift.Ready
		local done = i < gift.StreakDay or (not gift.Ready and isNext)
		local last = i == n
		local tile = box(strip, "Day" .. i, if done then TC.Disabled elseif last then PET.Tag else PET.Blue, if done then TC.GrayDeep elseif last then PET.TagEdge else PET.BlueEdge, 2.5, {
			LayoutOrder = i, Size = UDim2.fromScale(W, 0.94),
		})
		local tin = content(tile)
		if not done then
			HudArt.skin(tile, if last then "tile_cream" else "tile_blue", 92) -- claimed days keep the plain grey tile
			PetStyle.vgrad(tile, if last then PET.Gold:Lerp(PET.White, 0.3) else PET.BlueTop, if last then PET.Tag else PET.Blue)
		end
		UI.pad(tin, 2, 3)
		UI.list(tin, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		-- an upright phone's tiles are too narrow for "Day 2" at the 14 px text floor: the number alone (today keeps its
		-- green colour and ring)
		local dayText = if UI.isPortrait() then tostring(i) elseif today then "TODAY" else "Day " .. i
		-- white outlined words on the blue tile (dark words on the gold day 7 and the grey claimed tiles)
		local dark = last or done
		-- day word and amount at body / heading size (fitted, never under the shared floor); a short screen's ~50 px
		-- tile has no room for the coin picture between them
		word(tin, dayText, T.Body, {
			Name = "Day", Font = if today then UI.Head else UI.Bold, TextColor3 = if today then PET.LimeTop elseif dark then NAVY else PET.White, Outline = if dark then false else "Normal",
			Size = UDim2.fromScale(1, if short then 0.42 else 0.24), LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center,
		})
		local coin: GuiObject? = nil
		-- day 7 also banks a free Rare Egg (LaunchPerks.StreakEgg): the egg takes the coin picture's place with a
		-- small "RARE EGG" ribbon over its foot, so the tile reads "Day 7: 300 coins + Rare Egg"
		local freeEgg = LaunchPerks.streakEgg(i) ~= nil
		if not short then
			if freeEgg then
				local eggBox = UI.frame(tin, { Name = "EggBox", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.4), LayoutOrder = 2 })
				local ar = Instance.new("UIAspectRatioConstraint")
				ar.AspectRatio = 1
				ar.Parent = eggBox
				streakEgg(eggBox, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(1.25, 1.25), ZIndex = tile.ZIndex + 2 })
				coin = eggBox
			else
				local c = HudArt.image(tin, "Coin", 28, { Size = UDim2.fromScale(1, 0.4), LayoutOrder = 2 })
				local ar = Instance.new("UIAspectRatioConstraint")
				ar.AspectRatio = 1
				ar.Parent = c
				coin = c
			end
		end
		if short and freeEgg then
			-- a short screen's tile has no picture row: the egg sits beside the amount ("300 [egg]")
			local line = UI.frame(tin, { Name = "CoinsLine", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.56), LayoutOrder = 3 })
			word(line, tostring(coins), T.Head, {
				Name = "Coins", Font = UI.Head, TextColor3 = if dark then NAVY else PET.White, Outline = if dark then false else "Normal",
				Size = UDim2.new(1, -26, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
			})
			local eggBox = UI.frame(line, { Name = "EggBox", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(26, 26) })
			streakEgg(eggBox, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.5, 1.5), ZIndex = tile.ZIndex + 2 })
		else
			word(tin, tostring(coins), T.Head, {
				Name = "Coins", Font = UI.Head, TextColor3 = if dark then NAVY else PET.White, Outline = if dark then false else "Normal",
				Size = UDim2.fromScale(1, if short then 0.56 else 0.34), LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		if freeEgg and not short then
			-- the ribbon hangs over the egg's foot (inside the tile: anything over its edge gets clipped by the gift box).
			-- An upright phone's tile is too narrow for "RARE EGG" at the text floor: "+EGG" there.
			-- (fitted text wraps when it cannot shrink further, so the word must fit the ~45 px upright tile: "EGG")
			local rb = PetStyle.ribbon(tile, if UI.isPortrait() then "EGG" else "RARE EGG", PET.Lime, {
				Name = "EggRibbon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.58, 0), Size = UDim2.new(1, -4, 0, 16), Rotation = -4, ZIndex = tile.ZIndex + 3,
			})
			local rl = rb:FindFirstChildOfClass("TextLabel")
			if rl then
				rl.ZIndex = rb.ZIndex + 1
				rl.Position = UDim2.fromOffset(2, 0)
				rl.Size = UDim2.new(1, -4, 1, 0)
				UI.fit(rl, T.Tiny, T.MinText)
			end
		end
		if last and not done then
			-- the big day: a small star badge on the corner (colour and icon only, same size as the others)
			-- inside the tile beside the coin: hanging over the corner, the gift box clipped it to a stray dot (Studio check
			-- 2026-10-14), and the top corner covered "Day 7"
			UI.icon(tile, "star", 16, { Name = "Star", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.45, 0), ZIndex = tile.ZIndex + 4 })
		end
		if today then
			-- the one to open now: a thick green ring over the tile (drawn on top so a tile picture never hides it)
			local ring = UI.frame(tile, { Name = "TodayRing", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = tile.ZIndex + 3 })
			UI.corner(ring, 12)
			UI.stroke(ring, PET.Lime, 4)
			if coin then
				Juice.shake(coin) -- today's coin waits to be opened
			end
		end
		if done then
			-- claimed: the tile greys out and a big green check sits over it (a tiny tick was easy to miss)
			for _, c in tin:GetDescendants() do
				if c:IsA("TextLabel") and c.Name == "Coins" then
					-- the check takes the amount's place; the label keeps its room so the day word stays at the top
					-- (hidden, the list centred the word under the check)
					c.TextTransparency = 1
					local o = c:FindFirstChild("Outline")
					if o and o:IsA("UIStroke") then
						o.Enabled = false
					end
				elseif c:IsA("TextLabel") then
					c.TextTransparency = 0.45
				elseif c:IsA("ImageLabel") then
					c.ImageTransparency = 0.55
				end
			end
			local big = UI.frame(tile, { Name = "Claimed", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = tile.ZIndex + 4 })
			-- the check sits below the day word, not over it (a 40 px check covered "Day 3" on a short screen's tile)
			local ck = UI.icon(big, "check", if short then 26 else 34, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, if short then 0.66 else 0.6), ZIndex = tile.ZIndex + 5 })
			local cr = Instance.new("UIAspectRatioConstraint")
			cr.AspectRatio = 1
			cr.Parent = ck
		end
	end

	-- Quests ---------------------------------------------------------------------------------------------
	local qh = UI.frame(body, { Name = "QuestsTitle", Size = UDim2.new(1, -6, 0, if short then 30 else 34), BackgroundTransparency = 1, LayoutOrder = nextOrder() })
	local qt = word(qh, "Today's Quests", T.Head + 4, { Name = "Title", Font = UI.Head, TextColor3 = BLUE, Outline = false, Size = UDim2.fromScale(0.5, 1) })
	HudArt.word(qt)
	-- right of the title: when the quests renew (an empty unlabelled bar sat here before, Studio report)
	UI.icon(qh, "clock", 22, { Name = "ResetIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 6, 0.5, 0) })
	word(qh, "New quests in " .. untilText(daily.NextReset), T.Body, {
		Name = "Reset", Font = UI.Bold, TextColor3 = NAVY, Outline = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.5, -34, 0, 26), TextXAlignment = Enum.TextXAlignment.Right,
	})
	for i, q in daily.Quests do
		local row = box(body, "Quest" .. i, PET.QuestBody, PET.QuestEdge, 3, { Size = UDim2.new(1, -6, 0, 64), LayoutOrder = nextOrder() })
		HudArt.skin(row, "quest_row", 64)
		local rin = content(row)
		UI.pad(rin, 12, 8)
		-- left: name over the bar and count; right: the reward button
		local info = UI.frame(rin, { Name = "Info", Size = UDim2.fromScale(0.66, 1), BackgroundTransparency = 1 })
		UI.list(info, Enum.FillDirection.Vertical, 4)
		word(info, q.Text, T.Head, { Name = "Text", Font = UI.Bold, TextColor3 = NAVY, Outline = false, Size = UDim2.fromScale(1, 0.5), LayoutOrder = 1 })
		local line = UI.frame(info, { Name = "Line", Size = UDim2.fromScale(1, 0.42), BackgroundTransparency = 1, LayoutOrder = 2 })
		-- the count sits right after the bar's end on the same centre line (it floated off at the row's far edge,
		-- Studio #187): bar and count share one fixed split
		local COUNT_W = 64
		local track, fill = UI.bar(line, { Name = "Progress", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, -(COUNT_W + 6), 0, 16) }, if q.Done then TC.Green else BAR)
		fill.Size = UDim2.fromScale(math.clamp(q.Progress / math.max(q.Goal, 1), 0, 1), 1)
		track.BackgroundColor3 = PET.White -- light track so an empty bar reads empty
		UI.stroke(track, PET.QuestEdge, 2)
		HudArt.skin(track, "bar_track", 16)
		if not q.Done then
			HudArt.skin(fill, "bar_fill", 16)
		end
		word(line, q.Progress .. "/" .. q.Goal, T.Body, {
			Name = "Count", Font = UI.Head, TextColor3 = NAVY, Outline = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(0, COUNT_W, 0, 22), TextXAlignment = Enum.TextXAlignment.Left,
		})
		local cProps = { Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromScale(0.31, 0.92), TextSize = T.Body + 2 }
		-- three clearly different states: claimed = dim green CLAIMED, claimable = bright green CLAIM with a pulsing
		-- glow, locked = grey with a lock and the progress (the old dimmed gold read brown, much like the claimable one)
		if q.Claimed then
			local b = UI.button(rin, "CLAIMED", "gold", nil, cProps)
			UI.setEnabled(b, false, "gold")
			b:SetAttribute("Disabled", false) -- keep the green (claimed), it still takes no taps (no onClick)
			UI.paint(b)
			oneLine(b)
			b.BackgroundTransparency = 0.5
			local cl = b:FindFirstChild("Label") :: TextLabel?
			if cl then
				cl.TextTransparency = 0.3
			end
			if questAsked[i] then
				-- the server paid it: a stamp on the button and a burst of coins
				questAsked[i] = nil
				Juice.stamp(b)
				-- after the rebuilt row has been laid out: a deferred call still saw the new button at the list's
				-- origin, so the coins and "+80" flew off from the panel's left edge instead of from this button
				task.delay(0.1, function()
					if b.Parent and b.AbsoluteSize.X > 0 then
						Juice.coins(b, 8)
						Juice.floatText(b, "+" .. q.Reward .. " COINS", TC.Cash)
					end
				end)
			end
		elseif q.Done then
			local b: TextButton
			b = UI.button(rin, "CLAIM +" .. q.Reward, "gold", function()
				questAsked[i] = true
				Juice.coinSource(b) -- the coins fly from here once the server pays
				shop("ClaimQuest", i)
			end, cProps)
			HudArt.skin(b, "btn_green", 64)
			oneLine(b)
			Juice.shake(b)
			Juice.pulse(b, nil, T.Radius) -- a claimable reward breathes a soft glow
		else
			-- the reward, not the progress again (the bar beside it already shows "0/30")
			local b = UI.button(rin, "+" .. q.Reward, "gray", nil, cProps)
			HudArt.skin(b, "btn_grey", 64)
			UI.setEnabled(b, false, "gray")
			oneLine(b)
			-- a lock left of the reward, the reward takes the rest of the button
			UI.icon(b, "lock", 18, { Name = "Lock", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = b.ZIndex + 1 })
			local ll = b:FindFirstChild("Label") :: TextLabel?
			if ll then
				ll.Position = UDim2.fromOffset(28, 3)
				ll.Size = UDim2.new(1, -34, 1, -6)
			end
		end
	end
	word(body, "Quests renew at midnight UTC. Rewards are coins.", T.Small, {
		Name = "ResetNote", Font = UI.Bold, TextColor3 = NAVY, Outline = false, LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
	})
end

function QuestPanel.open()
	QuestPanel.start()
	local moreH = if not UI.isPortrait() and UI.Logical.Y < 395 then MORE_H_TIGHT else MORE_H
	local h = if UI.isPortrait() then 600 else 480
	local panel, b, close, footer = UI.modal("Quests", "DAILY", Vector2.new(560, h), { Cash = true, Footer = moreH })
	local _ = close
	PanelSkin.dress(panel, "Calendar", "DAILY")
	body = b
	isOpen = true
	openPanel = panel
	local gap = if shortScreen() then 6 else 8
	local listLayout = UI.list(b, Enum.FillDirection.Vertical, gap)
	if b:IsA("ScrollingFrame") then
		-- the canvas is measured from the list (+ one card gap), so the last quest card always scrolls fully into view
		UI.fitCanvas(b :: ScrollingFrame, listLayout, gap)
	end
	-- the quest list scrolls on short screens: a solid scroll bar and a "more below" tag until the end is in view
	if b:IsA("ScrollingFrame") and footer then
		local sc = b :: ScrollingFrame
		-- the list gives the footer strip back when nothing is left below (the button hides then)
		local short = sc.Size
		local full = UDim2.new(short.X.Scale, short.X.Offset, short.Y.Scale, short.Y.Offset + moreH)
		-- a real button, not a small tag: tapping it scrolls the quests into view (#232: the tag alone went unnoticed)
		-- below the list in the modal's footer strip, so it never covers a quest row
		local more = UI.button(footer, "MORE QUESTS", "blue", function()
			local target = Vector2.new(0, math.max(0, sc.AbsoluteCanvasSize.Y - sc.AbsoluteWindowSize.Y) / math.max(UI.Scale, 0.01))
			if UI.Reduced then
				sc.CanvasPosition = target
			else
				TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target }):Play()
			end
		end, {
			Name = "MoreHint", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(190, if moreH == MORE_H_TIGHT then 30 else 40), TextSize = T.Body + 1,
		})
		-- hint() resizes the scroller, which re-fires AbsoluteWindowSize; a guard keeps it to one pass per change
		-- (Studio: "Maximum event re-entrancy depth exceeded", and the list came up empty)
		local hinting = false
		local function hint()
			if hinting then
				return
			end
			hinting = true
			local below = sc.CanvasPosition.Y + sc.AbsoluteWindowSize.Y < sc.AbsoluteCanvasSize.Y - 6
			more.Visible = below
			local want = if below then short else full
			-- the window ends on a whole row (a card cut mid-way looked broken, Studio check 2026-10-14): measured from
			-- the window it would have at `want`, the freed strip stays as bottom padding
			local cut = if sc.AbsoluteWindowSize.Y > 0 then rowCut(sc, want.Y.Offset - sc.Size.Y.Offset) else 0
			local size = UDim2.new(want.X.Scale, want.X.Offset, want.Y.Scale, want.Y.Offset - cut)
			if sc.Size ~= size then
				sc.Size = size
			end
			hinting = false
		end
		sc:GetPropertyChangedSignal("CanvasPosition"):Connect(hint)
		sc:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(hint)
		sc:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(hint)
		hint()
		task.delay(0.2, hint) -- after the first render has filled the list
	end
	if State.Profile then
		UI.modalCash(State.Profile.Cash)
	end
	-- A closing panel is destroyed after its close tween (~0.2 s); reopening inside that window made the old
	-- panel's Destroying clear isOpen for the new one (audit 28), so only the current panel may close it.
	panel.Destroying:Connect(function()
		if openPanel == panel then
			isOpen = false
			openPanel = nil
		end
	end)
	panel.AncestryChanged:Connect(function()
		if openPanel == panel and not panel:IsDescendantOf(game) then
			isOpen = false
			openPanel = nil
		end
	end)
	render()
end

function QuestPanel.start()
	if started then
		return
	end
	started = true
	State.Changed.Event:Connect(function(what)
		if what == "Profile" and isOpen and UI.modalOpen() == "Quests" then
			if State.Profile then
				UI.modalCash(State.Profile.Cash)
			end
			render()
		end
	end)
end

return QuestPanel
