local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)

local function snap(over)
	local s = {
		cash = 0,
		hatPoints = 0,
		upgrades = { moreCoins = 0, bigCoins = 0, luck = 0, speed = 0 },
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
	for _, list in { PanelView.upgradeCards(s), PanelView.helperCards(s), PanelView.hatCards(s), PanelView.robuxCards(s, {}) } do
		for _, c in list do
			table.insert(out, c)
		end
	end
	return out
end

-- A spread of players: brand new, mid game, everything maxed and owned.
local function players()
	local maxed = { moreCoins = 0, bigCoins = 0, luck = 0, speed = 0 }
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
		snap({ cash = 5000, hatPoints = 40, resets = 1, crew = { buddy = 3 }, team = { "buddy" }, hats = { "party" }, hat = "party" }),
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
				if utf8.len(c.line) > PanelView.MAX_LINE then error("too long: " .. c.line) end
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
	it("always 10 rows, medals on the first 3, empty rows dashed", function()
		local rows = PanelView.boardRows("flips", { { name = "Ava", value = 50 }, { name = "Me", value = 4 } }, "Me")
		expect(#rows).toBe(Config.LEADERBOARD_SIZE)
		expect(rows[1].medal).toBe("gold")
		expect(rows[2].medal).toBe("silver")
		expect(rows[2].me).toBe(true)
		expect(rows[3].medal).toBe("bronze")
		expect(rows[3].empty).toBe(true)
		expect(rows[4].name).toBe("—")
		expect(rows[4].medal).toBe("none")
	end)

	it("no one yet = invite on row 1", function()
		local rows = PanelView.boardRows("resets", nil, "Me")
		expect(rows[1].name).toBe("No one yet. Be first!")
	end)

	it("your live number comes from your own snapshot", function()
		expect(PanelView.myValue("flips", snap({ flips = 1234 }))).toBe("1.23K")
		expect(PanelView.myValue("biggestFlip", snap({ biggestFlip = 2.5 }))).toBe("$2.5")
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
