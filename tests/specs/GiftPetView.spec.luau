local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Daily = require(ReplicatedStorage.Shared.Util.Daily)
local GiftPetView = require(ReplicatedStorage.Shared.Util.GiftPetView)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local PetRules = require(ReplicatedStorage.Shared.Util.PetRules)

local DAY = 20000
local NOW = DAY * 86400 + 3600

local function view(d)
	return Daily.view(d, 12345, DAY, 2)
end

describe("GIFTS tab", function()
	it("shows 7 days; today's is ready until it is taken", function()
		local rows = GiftPetView.dailyRows(view(Daily.empty()), NOW)
		expect(#rows.cells).toBe(7)
		expect(rows.cells[1].state).toBe("ready")
		expect(rows.cells[2].state).toBe("later")
		expect(rows.gift.look).toBe("buy")
		expect(rows.giftReady).toBe(true)
		local d = Daily.empty()
		Daily.claimGift(d, DAY)
		local after = GiftPetView.dailyRows(view(d), NOW)
		expect(after.cells[1].state).toBe("claimed")
		expect(after.cells[2].state).toBe("later")
		expect(after.gift.look).toBe("done")
		expect(after.giftReady).toBe(false)
	end)

	it("the timer counts down to UTC midnight", function()
		local rows = GiftPetView.dailyRows(view(Daily.empty()), NOW)
		expect(rows.timer).toBe("New gifts in 23h 00m")
		expect(GiftPetView.timeLeft(125)).toBe("2:05")
		expect(GiftPetView.timeLeft(9)).toBe("0:09")
		expect(GiftPetView.timeLeft(-5)).toBe("0:00")
	end)

	it("3 jobs: NOT YET, then CLAIM!, then DONE", function()
		local d = Daily.empty()
		local jobs = Daily.jobsFor(12345, DAY)
		local rows = GiftPetView.dailyRows(view(d), NOW)
		expect(#rows.jobs).toBe(3)
		expect(rows.jobs[1].button.text).toBe("NOT YET")
		expect(rows.jobs[1].button.look).toBe("poor")
		expect(rows.jobs[1].canClaim).toBe(false)
		Daily.rollover(d, DAY)
		d.progress[1] = jobs[1].goal
		rows = GiftPetView.dailyRows(view(d), NOW)
		expect(rows.jobs[1].button.text).toBe("CLAIM!")
		expect(rows.jobs[1].button.look).toBe("buy")
		expect(rows.jobs[1].canClaim).toBe(true)
		expect(rows.jobs[1].frac).toBe(1)
		Daily.claimJob(d, 12345, DAY, 1)
		rows = GiftPetView.dailyRows(view(d), NOW)
		expect(rows.jobs[1].button.text).toBe("DONE")
		expect(rows.jobs[1].canClaim).toBe(false)
	end)

	it("the red dot follows what can be claimed", function()
		expect(GiftPetView.dailyDot(view(Daily.empty()))).toBe(true)
		expect(GiftPetView.dailyDot(nil)).toBe(false)
	end)
end)

local function pet(id, owned, active)
	return {
		id = id,
		owned = owned,
		active = active,
		level = 3,
		xp = 10,
		xpNeeded = 30,
		goalText = "Flip 1,000 coins",
		have = 250,
		need = 1000,
		seconds = 3.4,
		cashPerFlip = 5,
	}
end

describe("PETS tab", function()
	it("an owned pet shows level, xp bar and EQUIP / PUT AWAY", function()
		local rows = GiftPetView.petRows({ pet("puppy", true, false), pet("pig", true, true) })
		expect(rows[1].button.text).toBe("EQUIP")
		expect(rows[1].action).toBe("equip")
		expect(math.abs(rows[1].frac - 1 / 3)).toBeAtMost(0.001)
		expect(rows[1].bar).toBe("XP 10/30")
		expect(rows[2].button.text).toBe("PUT AWAY")
		expect(rows[2].action).toBe("away")
		expect(rows[2].button.look).toBe("equipped")
	end)

	it("a locked pet shows its goal and progress, and cannot be equipped", function()
		local rows = GiftPetView.petRows({ pet("pig", false, false) })
		expect(rows[1].line).toBe("Flip 1,000 coins")
		expect(rows[1].bar).toBe("250/1.00K")
		expect(rows[1].frac).toBe(0.25)
		expect(rows[1].action).toBe("none")
		expect(rows[1].button.look).toBe("poor")
	end)

	it("a max level pet has a full bar", function()
		local v = pet("puppy", true, false)
		v.level = PetConfig.MAX_LEVEL
		v.xpNeeded = 0
		local rows = GiftPetView.petRows({ v })
		expect(rows[1].frac).toBe(1)
		expect(rows[1].bar).toBe("MAX LEVEL ★")
	end)

	it("every pet in the config gets a row", function()
		local views = {}
		for _, def in PetConfig.Pets do
			table.insert(views, pet(def.id, false, false))
		end
		expect(#GiftPetView.petRows(views)).toBe(GiftPetView.petCount())
		expect(PetRules.def("nope")).toBeNil()
	end)
end)

describe("Shop tabs", function()
	it("GIFTS and PETS are shop tabs with labels", function()
		local PanelView = require(ReplicatedStorage.Shared.Util.PanelView)
		expect(table.find(PanelView.TAB_ORDER, "daily") ~= nil).toBe(true)
		expect(table.find(PanelView.TAB_ORDER, "pets") ~= nil).toBe(true)
		for _, key in PanelView.TAB_ORDER do
			expect(PanelView.TAB_LABEL[key] ~= nil).toBe(true)
		end
		expect(PanelView.TAB_LABEL.daily).toBe(GiftPetView.GIFT_TAB)
		expect(PanelView.TAB_LABEL.pets).toBe(GiftPetView.PETS_TAB)
	end)
end)
