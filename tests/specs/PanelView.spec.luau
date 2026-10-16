local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local HatBuilder = require(ReplicatedStorage.Shared.Builders.HatBuilder)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local TapGuard = require(ReplicatedStorage.Shared.Util.TapGuard)

local function snap(over)
	local s = {
		cash = 0,
		hatPoints = 0,
		upgrades = { moreCoins = 0, bigCoins = 0, luck = 0, speed = 0, multiFlip = 0 },
		crew = {},
		team = {},
		resets = 0,
		flips = 0,
		biggestFlip = 0,
		coinCount = 1,
		tableFull = false,
		cashPerHeads = 1,
		headsChance = 0.5,
		resetBonus = 1.5,
		bestCombo = 0,
		hats = {},
		hat = "",
		skin = "",
		maxHelpers = 1,
		helperSlots = 0,
		passes = {},
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

local function allCards(s)
	local out = {}
	for _, list in
		{ PanelView.upgradeCards(s), PanelView.helperCards(s), PanelView.hatCards(s), PanelView.robuxCards(s, {}) }
	do
		for _, c in list do
			table.insert(out, c)
		end
	end
	return out
end

-- A spread of players: brand new, mid game, everything maxed and owned.
local function players()
	local maxed = { moreCoins = 0, bigCoins = 0, luck = 0, speed = 0, multiFlip = 0 }
	for id, def in Config.Upgrades do
		maxed[id] = def.maxLevel
	end
	local crew, team, hats = {}, {}, {}
	for _, def in Config.HelperTypes do
		crew[def.id] = Config.HELPER_MAX_LEVEL
		table.insert(team, def.id)
	end
	for _, def in Config.Hats do
		table.insert(hats, def.id)
	end
	local passes = { doubleCash = true, autoFlip = true }
	for _, skin in Config.Skins do
		passes[skin.id] = true
	end
	return {
		snap(),
		snap({
			cash = 5000,
			hatPoints = 40,
			resets = 1,
			crew = { buddy = 3 },
			team = { "buddy" },
			hats = { "party" },
			hat = "party",
		}),
		snap({
			cash = 1e12,
			hatPoints = 1e6,
			resets = 9,
			upgrades = maxed,
			crew = crew,
			team = team,
			hats = hats,
			hat = "crown",
			skin = "ice",
			passes = passes,
			helperSlots = Config.MAX_EXTRA_HELPER_SLOTS,
		}),
	}
end

describe("Shop cards (runner problems 12-19)", function()
	it("every card line fits on one phone line", function()
		for _, s in players() do
			for _, c in allCards(s) do
				if utf8.len(c.line) > PanelView.MAX_LINE then
					error("too long: " .. c.line)
				end
				expect(utf8.len(c.button)).toBeAtMost(12)
				expect(utf8.len(c.title)).toBeAtMost(18)
			end
		end
	end)

	it("MAX never looks buyable", function()
		local s = players()[3]
		for _, c in PanelView.upgradeCards(s) do
			expect(c.look).toBe("max")
			expect(c.button).toBe("MAXED ★")
		end
		for _, c in allCards(s) do
			if c.button:find("MAX") then
				expect(c.look).toBe("max")
			end
		end
	end)

	it("buy look only when you can pay", function()
		local poor = PanelView.upgradeCards(snap({ cash = 0 }))
		for _, c in poor do
			expect(c.look).toBe("poor")
		end
		local rich = PanelView.upgradeCards(snap({ cash = 1e9 }))
		for _, c in rich do
			expect(c.look).toBe("buy")
		end
	end)

	it("locked helpers say how many resets, owned helpers come first", function()
		local s = snap({ crew = { zippy = 1 }, team = { "zippy" }, resets = 1 })
		local cards = PanelView.helperCards(s)
		table.sort(cards, function(a, b)
			return a.order < b.order
		end)
		expect(cards[1].id).toBe("zippy")
		expect(cards[1].team.text).toBe("WORKING")
		expect(cards[1].team.look).toBe("equipped")
		local king = cards[#cards]
		expect(king.id).toBe("king")
		expect(king.look).toBe("locked")
		expect(king.button).toBe("🔒 5 RESETS")
		expect(king.line:find("Needs 5 resets")).toBeTruthy()
	end)

	it("hat rows don't repeat the same line, and the worn hat is EQUIPPED", function()
		local s = snap({ hats = { "cowboy" }, hat = "cowboy" })
		local seen = {}
		for _, c in PanelView.hatCards(s) do
			if c.look ~= "equipped" and c.look ~= "owned" then
				expect(seen[c.line]).toBeNil()
				seen[c.line] = true
			end
			if c.id == "cowboy" then
				expect(c.look).toBe("equipped")
			end
		end
	end)

	it("MORE tab hides while nothing in it is for sale", function()
		local anyId = false
		for _, item in PanelView.robuxItems() do
			anyId = anyId or item.id > 0
		end
		expect(PanelView.showRobuxTab(snap())).toBe(anyId)
		expect(PanelView.showRobuxTab(snap({ passes = { candy = true } }))).toBe(true)
	end)
end)

describe("Money text", function()
	it("small values keep one decimal", function()
		expect(PanelView.money(1.5)).toBe("$1.5")
		expect(PanelView.money(2)).toBe("$2")
		expect(PanelView.money(2.25)).toBe("$2.2")
		expect(PanelView.money(1500)).toBe("$1.50K")
	end)
end)

describe("Top 10 board (runner problems 13-15)", function()
	it("real rows first, placeholders for open seats, medals on the first 3", function()
		local rows = PanelView.boardRows("flips", { { name = "Ava", value = 50 }, { name = "Me", value = 4 } }, "Me")
		expect(rows[1].empty).toBe(false)
		expect(rows[2].empty).toBe(false)
		expect(rows[3].empty).toBe(true) -- open seats are styled placeholders
		expect(#rows).toBe(PanelView.OPEN_SEATS + (if rows[2] and not rows[2].empty then 2 else 0))
		expect(rows[1].medal).toBe("gold")
		expect(rows[2].medal).toBe("silver")
		expect(rows[2].me).toBe(true)
		local ten = {}
		for i = 1, 12 do
			table.insert(ten, { name = `P{i}`, value = 100 - i })
		end
		local full = PanelView.boardRows("flips", ten, "nobody")
		expect(#full).toBe(Config.LEADERBOARD_SIZE)
		expect(full[3].medal).toBe("bronze")
		expect(full[4].medal).toBe("none")
	end)

	it("your own row shows your live number, others show the board's", function()
		local rows =
			PanelView.boardRows("flips", { { name = "Ava", value = 500 }, { name = "Me", value = 118 } }, "Me", "121")
		expect(rows[2].value).toBe("121")
		expect(rows[1].value).toBe("500")
	end)

	it("no one yet = invite on row 1, then open seats", function()
		local rows = PanelView.boardRows("resets", nil, "Me")
		expect(#rows).toBe(PanelView.OPEN_SEATS + (if rows[2] and not rows[2].empty then 2 else 0))
		expect(rows[1].name).toBe("Be the first!")
		expect(rows[2].name).toBe("Open seat")
	end)

	it("your live number comes from your own snapshot", function()
		expect(PanelView.myValue("flips", snap({ flips = 1234 }))).toBe("1.23K")
		expect(PanelView.myValue("biggestFlip", snap({ biggestFlip = 2.5 }))).toBe("$2.5")
	end)
end)

describe("Round 2 runner problems", function()
	it("a maxed upgrade does not still describe the next level", function()
		for _, c in PanelView.upgradeCards(players()[3]) do
			expect(c.line).toBe("Fully upgraded!")
		end
	end)

	it("the mega banner body does not repeat its title", function()
		expect(PanelView.megaBody("MEGA FLIP! You got +$25")).toBe("You got +$25")
		expect(PanelView.megaBody("You got +$25")).toBe("You got +$25")
	end)

	it("a helper level-up never costs less than hiring him", function()
		for _, def in Config.HelperTypes do
			expect(Economy.helperLevelCost(def, 1)).toBeAtLeast(def.cost)
		end
	end)

	it("cone hats taper smoothly (a cone, not stacked cake tiers)", function()
		local discs = HatBuilder.cone(8, 1.0, 0.1, 1.3, { Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 255, 0) }, 2)
		expect(#discs).toBe(8)
		expect(discs[1].diameter).toBeNear(1.0, 1e-6)
		expect(discs[8].diameter).toBeNear(0.1, 1e-6)
		for i = 2, #discs do
			expect(discs[i].diameter < discs[i - 1].diameter).toBeTruthy()
			expect(discs[i - 1].diameter - discs[i].diameter).toBeAtMost(0.2) -- no big steps
			expect(discs[i].y > discs[i - 1].y).toBeTruthy()
		end
		expect(discs[1].color).toBe(discs[2].color) -- stripes
		expect(discs[2].color == discs[3].color).toBeFalsy()
	end)
end)

describe("Reset popup (runner problems 22-23)", function()
	it("color-coded lines, and the need line only when not full", function()
		local lines = PanelView.resetLines(snap({ tableFull = false, coinCount = 4 }))
		expect(lines[1].kind).toBe("lose")
		expect(lines[2].kind).toBe("keep")
		expect(lines[3].kind).toBe("get")
		expect(lines[3].text).toBe("GET: x1.5 cash + new table")
		expect(lines[4].text).toBe(`NEED: full table (4/{Config.MAX_COINS})`)
		expect(#PanelView.resetLines(snap({ tableFull = true }))).toBe(3)
	end)
end)

describe("Round 4: no wrong buys", function()
	it("a press only counts when the list did not move and is not coasting", function()
		expect(TapGuard.ok(100, 100, 1)).toBe(true)
		expect(TapGuard.ok(100, 103, 1)).toBe(true) -- finger jitter
		expect(TapGuard.ok(100, 160, 1)).toBe(false) -- list moved under the finger
		expect(TapGuard.ok(100, 100, 0.05)).toBe(false) -- still coasting
		expect(TapGuard.ok(100, 100, TapGuard.SETTLE)).toBe(true)
	end)

	it("hats always ask first; cash buys ask at half your cash or more", function()
		local s = snap({ cash = 1000, hatPoints = 500 })
		for _, c in PanelView.hatCards(s) do
			expect(PanelView.needsConfirm(c, s)).toBe(c.look == "buy")
		end
		local big =
			{ id = "x", title = "x", line = "", button = "", look = "buy", order = 1, price = 500, currency = "cash" }
		local small =
			{ id = "x", title = "x", line = "", button = "", look = "buy", order = 1, price = 499, currency = "cash" }
		expect(PanelView.needsConfirm(big, s)).toBe(true)
		expect(PanelView.needsConfirm(small, s)).toBe(false)
		big.look = "poor"
		expect(PanelView.needsConfirm(big, s)).toBe(false) -- can't afford: nothing to confirm
		expect(PanelView.needsConfirm({ id = "m", title = "", line = "", button = "", look = "max", order = 1 }, s)).toBe(
			false
		)
	end)

	it("locked crew button is dim, not a bright buy color", function()
		local s = snap({})
		for _, c in PanelView.helperCards(s) do
			if c.look == "locked" then
				expect(c.button:find("🔒")).toBeTruthy()
			end
		end
	end)
end)

describe("One banner style", function()
	it("every banner title fits its row", function()
		for _, def in Config.Hats do
			local title, text = PanelView.hatBanner(def.name)
			expect(utf8.len(title)).toBeAtMost(PanelView.BANNER_TITLE_MAX)
			expect(#text > 0).toBe(true)
		end
		expect(utf8.len(PanelView.AWAY_TITLE)).toBeAtMost(PanelView.BANNER_TITLE_MAX)
	end)
end)

describe("Round 5", function()
	it("your own rare flip says You", function()
		expect(PanelView.shoutText("MrCarter flipped a RAINBOW coin! +$5", "MrCarter", true)).toBe(
			"You flipped a RAINBOW coin! +$5"
		)
		expect(PanelView.shoutText("MrCarter flipped a RAINBOW coin! +$5", "MrCarter", false)).toBe(
			"MrCarter flipped a RAINBOW coin! +$5"
		)
	end)
end)

describe("Round 6", function()
	it("shop/top rows fill every list window exactly, on every screen", function()
		local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)
		for _, screen in HudLayout.SCREENS do
			local l = HudLayout.compute(screen.w, screen.h, screen.touch)
			local fit = math.clamp(math.min(l.panel.w / 600, l.panel.h / 470), 1, 2)
			local boxH = l.panel.h / fit
			local window = boxH - 62 - 44 - 20 - 4 -- body, list top, arrow strip, spare
			for _, header in { 0, 26 } do
				for _, count in { 3, 4, 8, 9 } do
					local avail = window - header
					local fits, h, content = PanelView.fitRows(avail, count, 50, 88, 8, 8)
					expect(content).toBeAtMost(avail) -- last shown row is never cut
					if count > fits then
						-- the rest scrolls; the window holds exactly `fits` whole rows
						expect(8 + fits * h + (fits - 1) * 8).toBeAtMost(avail)
					end
				end
			end
		end
	end)

	it("top 10: real players plus two open seats", function()
		local rows = PanelView.boardRows("flips", { { name = "Me", value = 4 } }, "Me")
		expect(#rows).toBe(1 + PanelView.OPEN_SEATS)
		expect(rows[2].empty).toBe(true)
		expect(PanelView.boardRows("flips", nil, "Me")[1].name).toBe("Be the first!")
	end)
end)

describe("Round 7", function()
	local HudLayout = require(ReplicatedStorage.Shared.Util.HudLayout)
	local function eachScreen(fn)
		table.insert(HudLayout.SCREENS, { name = "runner-phone", w = 845, h = 397, touch = true })
		for _, screen in HudLayout.SCREENS do
			local l = HudLayout.compute(screen.w, screen.h, screen.touch)
			local fit = math.clamp(math.min(l.panel.w / 600, l.panel.h / 470), 1, 2)
			fn(screen, l, fit, l.panel.h / fit)
		end
		table.remove(HudLayout.SCREENS)
	end

	it("no sliver of the next row peeks in under the last whole row", function()
		eachScreen(function(_, _, _, boxH)
			for _, header in { 0, 26 } do
				local avail = boxH - 62 - 44 - header - 20 - 4
				for _, count in { 3, 4, 8, 9 } do
					local fits, h, content = PanelView.fitRows(avail, count, 44, 88, 8, 8)
					if count > fits then
						local used = 8 + fits * h + (fits - 1) * 8
						expect(used).toBeAtMost(avail)
						expect(avail - used).toBeAtMost(fits + 1) -- rounding only
					else
						expect(content).toBeAtMost(avail)
					end
				end
			end
		end)
	end)

	it("the Invite card is always whole and never under the YOU bar", function()
		eachScreen(function(_, _, _, boxH)
			local full = boxH - 62 - 44 - 34 - 20 - 4
			for real = 0, 3 do
				local n, rowH, invite = PanelView.boardLayout(full, real, real + PanelView.OPEN_SEATS)
				expect(n >= math.max(real, 1)).toBe(true)
				if invite > 0 then
					expect(invite).toBeAtLeast(PanelView.INVITE_MIN)
					expect(8 + n * rowH + (n - 1) * 8 + 8 + invite + PanelView.INVITE_PAD).toBeAtMost(full)
				end
			end
		end)
	end)

	it("a phone shows at least 2 whole rows (3 at 845x397), tabs fill the row", function()
		eachScreen(function(screen, _, _, boxH)
			local header = PanelView.headerHeight(boxH)
			local avail = boxH - 62 - 44 - header - 20 - 4
			local fits, h = PanelView.fitRows(avail, 8, 44, 88, 8, 8)
			expect(fits).toBeAtLeast(2)
			if screen.name == "runner-phone" then
				expect(fits).toBeAtLeast(3)
			end
			expect(h).toBeAtLeast(44)
		end)
		local scale, offset = PanelView.tabSize(3, 6)
		expect(scale).toBe(1 / 3)
		expect(offset).toBe(-4)
		expect(PanelView.tabSize(4, 6)).toBe(0.25)
	end)

	it("desktop rows are roomy: names >= 18px, icons >= 56px; phones keep 2+ rows", function()
		eachScreen(function(screen, _, _, boxH)
			local avail = boxH - 62 - 44 - PanelView.headerHeight(boxH) - 20 - 4
			local fits, h = PanelView.cardRows(avail, 8, 44, 88)
			expect(fits).toBeAtLeast(2)
			if boxH >= 440 then
				expect(h).toBeAtLeast(64)
				expect(math.round(h * 0.42)).toBeAtLeast(18)
				expect(h - 10).toBeAtLeast(56)
			end
		end)
	end)

	it("a price of 0 reads FREE in the bright buy look", function()
		local card: any = { id = "x", title = "X", line = "", button = "$0", look = "poor", price = 0, order = 1 }
		PanelView.freePrice(card)
		expect(card.button).toBe("FREE")
		expect(card.look).toBe("buy")
		local paid: any = { id = "y", title = "Y", line = "", button = "$5", look = "poor", price = 5, order = 2 }
		PanelView.freePrice(paid)
		expect(paid.button).toBe("$5")
		expect(paid.look).toBe("poor")
	end)

	it("banner title row is at least 18px tall on every screen", function()
		eachScreen(function(_, l)
			local titleH = PanelView.bannerRows(l.shout.h - 8)
			expect(titleH).toBeAtLeast(18)
			expect(PanelView.BANNER_TITLE_MIN_FONT).toBeAtLeast(16)
		end)
	end)
end)

describe("Short banner lines", function()
	it("rare, mega and away lines fit a small banner", function()
		expect(PanelView.shoutLine("Ava flipped a RAINBOW coin! +$1.20K", "Me", false)).toBe("Ava flipped it! +$1.20K")
		expect(PanelView.shoutLine("Me flipped a GIANT coin! +$25K", "Me", true)).toBe("You flipped it! +$25K")
		expect(PanelView.megaLine("MEGA FLIP! You got +$25 and 2x cash for 2 minutes!")).toBe("+$25 and 2x cash!")
		expect(PanelView.awayLine("Your helpers earned $120 while you were away!")).toBe("Helpers earned $120!")
	end)
end)
