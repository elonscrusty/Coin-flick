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
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Parent.Types)

type Snapshot = Types.Snapshot

-- buy = can buy now, poor = can't afford yet, max = all done, locked = needs
-- resets first, owned = yours (tap to use), equipped = in use right now,
-- soon = not for sale yet.
export type Look = "buy" | "poor" | "max" | "locked" | "owned" | "equipped" | "soon"

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
PanelView.MIN_BOARD_ROWS = 5 -- the top 10 always shows at least this many rows

PanelView.TAB_ORDER = { "upgrades", "helpers", "hats", "robux" }
PanelView.TAB_LABEL = {
	upgrades = "COINS",
	helpers = "CREW",
	hats = "HATS",
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

-- Top 10 --------------------------------------------------------------------

PanelView.BOARD_TABS = { { "flips", "FLIPS" }, { "biggestFlip", "BIGGEST" }, { "resets", "RESETS" } }
PanelView.BOARD_UNITS = { flips = "flips", biggestFlip = "", resets = "resets" }

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
	-- Open seats stay as styled placeholders (never a blank cream panel).
	for i = #out + 1, PanelView.MIN_BOARD_ROWS do
		table.insert(out, {
			rank = tostring(i),
			name = if #out == 0 then "Be the first!" else "Open seat",
			value = "",
			medal = MEDALS[i] or "none",
			me = false,
			empty = true,
		})
	end
	return out
end

-- Your own live number, pinned under the list (the board itself refreshes slowly).
function PanelView.myValue(key: string, s: Snapshot): string
	local value = if key == "flips" then s.flips elseif key == "biggestFlip" then s.biggestFlip else s.resets
	return PanelView.boardValue(key, value)
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

-- One banner shape for every message: a short title row and one text row.
PanelView.BANNER_TITLE_MAX = 18

function PanelView.hatBanner(hatName: string): (string, string)
	return `{string.upper(hatName)} ON!`, "Looking good!"
end

PanelView.AWAY_TITLE = "WELCOME BACK!"

-- Reset popup ---------------------------------------------------------------

function PanelView.resetLines(s: Snapshot): { ResetLine }
	local lines: { ResetLine } = {
		{ kind = "lose", text = "LOSE: cash + upgrades" },
		{ kind = "keep", text = "KEEP: helpers + 🎩 hats" },
		{ kind = "get", text = `GET: x{string.format("%.4g", s.resetBonus)} cash + new table` },
	}
	if not s.tableFull then
		table.insert(lines, { kind = "need", text = `NEED: full table ({s.coinCount}/{Config.MAX_COINS})` })
	end
	return lines
end

return PanelView
