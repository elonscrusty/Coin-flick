local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
local HatBuilder = require(ReplicatedStorage.Shared.Builders.HatBuilder)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)

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
		expect(#rows).toBe(PanelView.MIN_BOARD_ROWS)
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
		expect(#rows).toBe(PanelView.MIN_BOARD_ROWS)
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
