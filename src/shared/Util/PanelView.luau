--!strict
-- What every shop card, top 10 row and reset line SAYS and which button LOOK it
-- uses, worked out from the player's snapshot. Pure (snapshot in, tables out)
-- so the rules are tested offline; client/Controllers/Panels only draws them.
--
-- Rules the tests hold:
-- * a button that can't be pressed never uses the "buy" look (MAX is gold, not blue)
-- * every card line is short enough to fit on ONE line on a phone
-- * owned helpers come first in the CREW list
-- * the MORE tab only shows when at least one Robux item is for sale or owned
-- * the top 10 always has 10 rows ("—" for empty spots)

local Config = require(script.Parent.Parent.Config)
local Economy = require(script.Parent.Economy)
local EventText = require(script.Parent.EventText)
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Parent.Types)

type Snapshot = Types.Snapshot

-- buy = can buy now, poor = can't afford yet, max = all done, locked = needs
-- resets first, owned = yours (tap to use), equipped = in use right now,
-- soon = not for sale yet.
export type Look = "buy" | "poor" | "max" | "locked" | "owned" | "equipped" | "soon" | "done"

export type Card = {
	id: string,
	title: string,
	line: string, -- one short line under the title
	button: string,
	look: Look,
	order: number, -- LayoutOrder in the list
	price: number?, -- what a press would spend (nil when it spends nothing)
	currency: ("cash" | "hat")?,
	badge: string?, -- small tag next to the title, e.g. "Lv 3/9" or "WORKING"
	team: { text: string, look: Look }?, -- helpers only: the work/rest toggle
}

export type Medal = "gold" | "silver" | "bronze" | "none"

export type BoardRow = {
	rank: string,
	name: string,
	value: string,
	medal: Medal,
	me: boolean,
	empty: boolean,
}

export type ResetLine = { kind: "lose" | "keep" | "get" | "need", text: string }

local PanelView = {}

-- Longest card line we allow (characters). Longer text gets squeezed tiny on
-- phones, so the tests hold every line to this.
PanelView.MAX_LINE = 28
PanelView.OPEN_SEATS = 2 -- placeholder rows shown under the real players

-- Width of each of `count` shown tabs sharing one row: (scale, offset).
function PanelView.tabSize(count: number, gap: number): (number, number)
	local n = math.max(1, count)
	return 1 / n, -(gap * (n - 1)) / n
end

PanelView.TAB_ORDER = { "upgrades", "helpers", "hats", "daily", "pets", "goals", "robux" }
PanelView.TAB_LABEL = {
	upgrades = "COINS",
	helpers = "CREW",
	hats = "HATS",
	daily = "GIFTS",
	pets = "PETS",
	goals = "GOALS",
	robux = "MORE",
}

local SHORT_DESC: { [string]: string } = {
	moreCoins = "+1 coin on your table",
	bigCoins = "More cash each heads!",
	luck = "+3% heads chance",
	speed = "Coins land faster",
}

-- Small numbers keep one decimal so x1.5 of $1 shows $1.5, not $1 or $2.
function PanelView.money(n: number): string
	if n < 100 and n ~= math.floor(n) then
		local text = string.format("%.1f", math.floor(n * 10) / 10)
		return "$" .. (string.gsub(text, "%.0$", ""))
	end
	return "$" .. Format.short(n)
end

local function priceLook(have: number, cost: number): Look
	return if have >= cost then "buy" else "poor"
end

-- A price of 0 reads FREE in bright green (never a grey "$0").
function PanelView.freePrice(card: Card)
	if card.price ~= nil and card.price <= 0 and (card.look == "buy" or card.look == "poor") then
		card.button = "FREE"
		card.look = "buy"
	end
end

function PanelView.upgradeCards(s: Snapshot): { Card }
	local cards: { Card } = {}
	for i, id in Config.UPGRADE_ORDER do
		local def = Config.Upgrades[id]
		local level = s.upgrades[id :: Types.UpgradeId]
		local cost = Economy.upgradeCost(id, level)
		local card: Card = {
			id = id,
			title = def.name,
			line = if cost then (SHORT_DESC[id] or def.desc) else "Fully upgraded!",
			badge = `Lv {level}/{def.maxLevel}`,
			button = if cost then PanelView.money(cost) else "MAXED ★",
			look = if cost then priceLook(s.cash, cost) else "max",
			price = cost,
			currency = if cost then "cash" else nil,
			order = i,
		}
		PanelView.freePrice(card)
		table.insert(cards, card)
	end
	return cards
end

function PanelView.helperHeader(s: Snapshot): string
	return `Working: {#s.team}/{s.maxHelpers} • they flip while you're away`
end

function PanelView.helperCards(s: Snapshot): { Card }
	local cards: { Card } = {}
	for i, def in Config.HelperTypes do
		local level = s.crew[def.id]
		local card: Card
		if level then
			local working = table.find(s.team, def.id) ~= nil
			local cost = Economy.helperLevelCost(def, level)
			local interval = Economy.helperInterval(def, level)
			local mult = Economy.helperCashMult(def, level)
			card = {
				id = def.id,
				title = def.name,
				line = `Lv {level} • every {string.format("%.1f", interval)}s • x{string.format("%.1f", mult)}`,
				button = if cost then `⬆ {PanelView.money(cost)}` else "MAXED ★",
				look = if cost then priceLook(s.cash, cost) else "max",
				price = cost,
				currency = if cost then "cash" else nil,
				order = i, -- owned helpers first, in unlock order
				team = {
					text = if working then "WORKING" else "REST",
					look = if working then "equipped" else "owned",
				},
			}
		elseif s.resets < def.resets then
			card = {
				id = def.id,
				title = def.name,
				line = `Needs {def.resets} reset{if def.resets == 1 then "" else "s"}, then {PanelView.money(def.cost)}`,
				button = `🔒 {def.resets} RESET{if def.resets == 1 then "" else "S"}`,
				look = "locked",
				order = 100 + i,
			}
		else
			card = {
				id = def.id,
				title = def.name,
				line = `Flips every {string.format("%.1f", def.interval)}s • x{def.mult}`,
				button = PanelView.money(def.cost),
				look = priceLook(s.cash, def.cost),
				price = def.cost,
				currency = "cash",
				order = 100 + i,
			}
		end
		PanelView.freePrice(card)
		table.insert(cards, card)
	end
	return cards
end

PanelView.HAT_HEADER = "Tails flips give 🎩 points. Spend them here!"

local HAT_LINES: { [string]: string } = {
	party = "Every day is a party",
	cone = "Safety first!",
	cowboy = "Yee-haw!",
	chef = "Cooking up heads",
	propeller = "Spins in the wind",
	duck = "Quack quack",
	tophat = "Very fancy",
	crown = "King of the flips",
}

function PanelView.hatCards(s: Snapshot): { Card }
	local cards: { Card } = {}
	for i, def in Config.Hats do
		local owned = table.find(s.hats, def.id) ~= nil
		local card: Card
		if s.hat == def.id then
			card = {
				id = def.id,
				title = def.name,
				line = "On! Tap to take it off",
				button = "✔ ON",
				look = "equipped",
				order = i,
			}
		elseif owned then
			card = {
				id = def.id,
				title = def.name,
				line = "Yours! Tap to wear",
				button = "WEAR",
				look = "owned",
				order = i,
			}
		else
			card = {
				id = def.id,
				title = def.name,
				line = HAT_LINES[def.id] or "A silly hat",
				button = `🎩 {Format.short(def.cost)}`,
				look = priceLook(s.hatPoints, def.cost),
				price = def.cost,
				currency = "hat",
				order = i,
			}
		end
		PanelView.freePrice(card)
		table.insert(cards, card)
	end
	return cards
end

export type RobuxItem = { key: string, title: string, line: string, id: number, kind: "pass" | "product" }

function PanelView.robuxItems(): { RobuxItem }
	local items: { RobuxItem } = {
		{
			key = "doubleCash",
			title = "2x Cash Forever",
			line = "Double cash every heads",
			id = Config.Products.DoubleCashPassId,
			kind = "pass",
		},
		{
			key = "autoFlip",
			title = "Auto Flip",
			line = "Coins flip by themselves",
			id = Config.Products.AutoFlipPassId,
			kind = "pass",
		},
		{
			key = "helperSlot",
			title = "+1 Helper Slot",
			line = "",
			id = Config.Products.ExtraHelperSlotProductId,
			kind = "product",
		},
	}
	for _, skin in Config.Skins do
		table.insert(
			items,
			{ key = skin.id, title = skin.name, line = "A new look for every coin", id = skin.passId, kind = "pass" }
		)
	end
	return items
end

-- The MORE tab only makes sense once something in it can be bought (or is owned).
function PanelView.showRobuxTab(s: Snapshot?): boolean
	for _, item in PanelView.robuxItems() do
		if item.id > 0 then
			return true
		end
		if s and (s.passes[item.key] or (item.key == "helperSlot" and s.helperSlots > 0)) then
			return true
		end
	end
	return false
end

function PanelView.robuxCards(s: Snapshot, prices: { [string]: string }): { Card }
	local cards: { Card } = {}
	for i, item in PanelView.robuxItems() do
		local card: Card = {
			id = item.key,
			title = item.title,
			line = item.line,
			button = "SOON",
			look = "soon",
			order = i,
		}
		if item.key == "helperSlot" then
			card.line = `+1 helper ({s.helperSlots}/{Config.MAX_EXTRA_HELPER_SLOTS})`
			if s.helperSlots >= Config.MAX_EXTRA_HELPER_SLOTS then
				card.button, card.look = "MAXED ★", "max"
				table.insert(cards, card)
				continue
			end
		end
		local skin = Economy.skinDef(item.key)
		if skin and s.passes[item.key] then
			local on = s.skin == item.key
			card.line = if on then "On your coins! Tap for gold" else "Yours! Tap to use"
			card.button = if on then "✔ ON" else "USE"
			card.look = if on then "equipped" else "owned"
		elseif s.passes[item.key] then
			card.button, card.look = "OWNED ✔", "max"
		elseif item.id > 0 then
			card.button, card.look = prices[item.key] or "BUY", "buy"
		end
		PanelView.freePrice(card)
		table.insert(cards, card)
	end
	return cards
end

-- Ask "Buy X?" first for every hat, and for anything that costs half your cash or more.
function PanelView.needsConfirm(card: Card, s: Snapshot): boolean
	if card.price == nil or card.look ~= "buy" then
		return false
	end
	if card.currency == "hat" then
		return true
	end
	return card.price >= s.cash * 0.5
end

-- Rows that fill a list window exactly. `avail` is the window height (after any
-- header row), rows have `gap` between them and `pad` above the first. Picks how
-- many rows fit, then stretches them (up to `maxH`) so none is cut off at the bottom.
function PanelView.fitRows(
	avail: number,
	count: number,
	minH: number,
	maxH: number,
	gap: number,
	pad: number
): (number, number, number)
	local fits = math.clamp(math.floor((avail - pad + gap) / (minH + gap)), 1, math.max(1, count))
	local h = math.floor((avail - pad - (fits - 1) * gap) / fits)
	if count <= fits then
		h = math.min(h, maxH) -- everything fits: rows may stay smaller than the window
	end -- else rows share the whole window, so no sliver of the next row peeks in
	h = math.max(h, minH)
	local shown = math.min(fits, count)
	local content = pad + shown * h + math.max(0, shown - 1) * gap
	return fits, h, content
end

-- Shop rows: roomy (CARD_PREF) when at least 3 fit, else squeezed to CARD_MIN so
-- a short phone panel still shows 2-3 whole rows.
PanelView.CARD_PREF = 64
function PanelView.cardRows(avail: number, count: number, minH: number, maxH: number): (number, number)
	local fits, h = PanelView.fitRows(avail, count, PanelView.CARD_PREF, maxH, 8, 8)
	if fits >= math.min(3, count) then
		return fits, h
	end
	local f2, h2 = PanelView.fitRows(avail, count, minH, maxH, 8, 8)
	return f2, h2
end

-- Top 10 rows: the real players, up to two open seats, and an "Invite friends!"
-- card that must always be fully visible. Open seats go first when space is short.
PanelView.INVITE_MIN = 56
PanelView.INVITE_PAD = 6 -- air under the invite card so its border is never cut
PanelView.ROW_MIN = 34
PanelView.ROW_MAX = 62

function PanelView.boardLayout(full: number, real: number, wanted: number): (number, number, number)
	if wanted > 5 then -- a long list: just scroll, no invite card
		local _, rowH = PanelView.fitRows(full, wanted, PanelView.ROW_MIN, PanelView.ROW_MAX, 8, 8)
		return wanted, rowH, 0
	end
	for n = wanted, math.max(real, 1), -1 do
		local rowMax = math.floor((full - 8 - 8 - PanelView.INVITE_PAD - (n - 1) * 8 - PanelView.INVITE_MIN) / n)
		if rowMax >= PanelView.ROW_MIN then
			local rowH = math.min(PanelView.ROW_MAX, rowMax)
			local invite = math.min(130, full - (8 + n * rowH + (n - 1) * 8) - 8 - PanelView.INVITE_PAD)
			return n, rowH, invite
		end
	end
	local _, rowH = PanelView.fitRows(full, math.max(real, 1), PanelView.ROW_MIN, PanelView.ROW_MAX, 8, 8)
	return math.max(real, 1), rowH, 0
end

-- Height of the one-line caption above the CREW / HATS lists: none on a short
-- panel, so a phone shows more rows.
PanelView.HEADER_H = 26
function PanelView.headerHeight(boxH: number): number
	return if boxH < 340 then 0 else PanelView.HEADER_H
end

-- Banner rows (title over text) inside a banner `h` pixels tall.
PanelView.BANNER_TITLE_MIN_FONT = 16
function PanelView.bannerRows(h: number): (number, number)
	return math.floor(h * 0.55), math.floor(h * 0.34)
end

-- Top 10 --------------------------------------------------------------------

PanelView.BOARD_TABS = {
	{ "flips", "FLIPS" },
	{ "weekFlips", "THIS WEEK" },
	{ "biggestFlip", "BIGGEST" },
	{ "resets", "RESETS" },
}
PanelView.BOARD_UNITS = { flips = "flips", weekFlips = "flips", biggestFlip = "", resets = "resets" }

local MEDALS: { Medal } = { "gold", "silver", "bronze" }

function PanelView.boardValue(key: string, value: number): string
	if key == "biggestFlip" then
		return PanelView.money(value)
	end
	return Format.short(value)
end

-- Only the seats that are taken (empty seats are not shown). Your own row shows
-- your live number (`myValue`) because the board itself refreshes slowly.
function PanelView.boardRows(key: string, rows: { Types.LeaderRow }?, myName: string, myValue: string?): { BoardRow }
	local out: { BoardRow } = {}
	for i = 1, math.min(Config.LEADERBOARD_SIZE, if rows then #rows else 0) do
		local row = (rows :: { Types.LeaderRow })[i]
		local me = row.name == myName
		table.insert(out, {
			rank = tostring(i),
			name = row.name,
			value = if me and myValue then myValue else PanelView.boardValue(key, row.value),
			medal = MEDALS[i] or "none",
			me = me,
			empty = false,
		})
	end
	-- A couple of open seats under the real players (never a blank panel).
	local real = #out
	for i = real + 1, math.min(Config.LEADERBOARD_SIZE, real + PanelView.OPEN_SEATS) do
		table.insert(out, {
			rank = tostring(i),
			name = if real == 0 and i == 1 then "Be the first!" else "Open seat",
			value = "",
			medal = MEDALS[i] or "none",
			me = false,
			empty = true,
		})
	end
	return out
end

-- Your own live number, pinned under the list (the board itself refreshes slowly).
-- `weekValue` = your flips this week, read from the weekly board (the snapshot does not carry it).
function PanelView.myValue(key: string, s: Snapshot, weekValue: number?): string
	local value = if key == "flips"
		then s.flips
		elseif key == "weekFlips" then weekValue or 0
		elseif key == "biggestFlip" then s.biggestFlip
		else s.resets
	return PanelView.boardValue(key, value)
end

-- Your own number on the weekly board (0 when you are not in the top 10 yet).
function PanelView.weekValueOf(rows: { Types.LeaderRow }?, myName: string): number
	if not rows then
		return 0
	end
	for _, row in rows do
		if row.name == myName then
			return row.value
		end
	end
	return 0
end

-- Extra words under the board: only THIS WEEK has a reset clock ("Resets in 3d 4h").
function PanelView.boardNote(key: string, weekEndsAt: number?, now: number): string
	if key ~= "weekFlips" or weekEndsAt == nil or weekEndsAt <= 0 then
		return ""
	end
	return EventText.weekReset(weekEndsAt, now)
end

-- Big banners ---------------------------------------------------------------

-- The server's mega text starts with "MEGA FLIP!", which the banner title already says.
function PanelView.megaBody(text: string): string
	local body = string.gsub(text, "^%s*MEGA FLIP!%s*", "")
	return body
end

-- The server writes "<name> flipped a ..." for everyone; your own flip says "You flipped".
function PanelView.shoutText(text: string, ownerName: string, isMe: boolean): string
	if not isMe then
		return text
	end
	local prefix = ownerName .. " flipped"
	if string.sub(text, 1, #prefix) == prefix then
		return "You flipped" .. string.sub(text, #prefix + 1)
	end
	return text
end

-- Banner body lines are short on purpose (the banner slot is small): the title
-- already says what happened, the line adds who and how much.
function PanelView.shoutLine(text: string, ownerName: string, isMe: boolean): string
	local who, prize = string.match(text, "^(.-) flipped an? .- coin! (.+)$")
	if not who or not prize then
		return PanelView.shoutText(text, ownerName, isMe)
	end
	return `{if isMe then "You" else who} flipped it! {prize}`
end

function PanelView.megaLine(text: string): string
	local prize = string.match(text, "%+%$[%w%.]+")
	if not prize then
		return PanelView.megaBody(text)
	end
	return if string.find(text, "2x", 1, true) then `{prize} and 2x cash!` else prize
end

function PanelView.awayLine(text: string): string
	local prize = string.match(text, "%$[%w%.]+")
	return if prize then `Crew earned {prize}!` else text
end

-- One banner shape for every message: a short title row and one text row.
PanelView.BANNER_TITLE_MAX = 18

function PanelView.hatBanner(hatName: string): (string, string)
	return string.upper(hatName), "Now wearing it!"
end

PanelView.AWAY_TITLE = "WELCOME BACK!"

-- "1 head", "2 times": numbers in goal texts agree with their word ("Get 1 heads" -> "Get 1 head").
local SINGULAR = { heads = "head", coins = "coin", upgrades = "upgrade", times = "time", flips = "flip" }
local PLURAL = { time = "times" }
function PanelView.fixCount(text: string): string
	local fixed = string.gsub(text, "([%d,]+) rare coins", function(num: string)
		return if tonumber((string.gsub(num, ",", ""))) == 1 then `{num} rare coin` else `{num} rare coins`
	end)
	local out, pos = "", 1
	while true do
		local first, last, num, word = string.find(fixed, "([%d,]+) (%a+)", pos)
		if not first or not last or not num or not word then
			break
		end
		local n = tonumber((string.gsub(num, ",", "")))
		local replaced = word
		if n == 1 and SINGULAR[word] then
			replaced = SINGULAR[word]
		elseif n ~= nil and n ~= 1 and PLURAL[word] then
			replaced = PLURAL[word]
		end
		out ..= string.sub(fixed, pos, first - 1) .. `{num} {replaced}`
		pos = last + 1
	end
	fixed = out .. string.sub(fixed, pos)
	return fixed
end

-- Unlock banners (new pet, new badge): one look, picture + name. nil = not an unlock notice.
function PanelView.unlockBanner(kind: string, text: string): (string?, string?, string?)
	if kind == "pet" then
		local icon, name = string.match(text, "^New pet!%s*(%S+)%s+(.-) is yours!?$")
		if icon and name then
			return "NEW PET!", name, icon
		end
		return "NEW PET!", text, "🐾"
	elseif kind == "badge" then
		local name = string.match(text, "^Badge:%s*(.-)!?$")
		return "NEW BADGE!", name or text, "🏅"
	end
	return nil, nil, nil
end

-- Reset popup ---------------------------------------------------------------

function PanelView.resetLines(s: Snapshot): { ResetLine }
	local lines: { ResetLine } = {
		{ kind = "lose", text = "LOSE: cash + upgrades" },
		{ kind = "keep", text = "KEEP: crew + 🎩 hats" },
		{ kind = "get", text = `GET: x{string.format("%.4g", s.resetBonus)} cash + new table` },
	}
	if not s.tableFull then
		table.insert(lines, { kind = "need", text = `NEED: full table ({s.coinCount}/{Config.MAX_COINS})` })
	end
	return lines
end

return PanelView
