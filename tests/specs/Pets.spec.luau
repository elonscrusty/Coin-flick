local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local PetRules = require(ReplicatedStorage.Shared.Util.PetRules)
local ProfileSchema = require(ReplicatedStorage.Shared.Util.ProfileSchema)

describe("Coin pets: starting pet and saving", function()
	it("a brand new player owns the free puppy and it is out", function()
		local p = ProfileSchema.default()
		expect(p.pets.puppy.level).toBe(1)
		expect(p.petActive).toBe("puppy")
		expect(p.pets.pig).toBe(nil)
	end)

	it("an old save without pets gets the puppy", function()
		local p = ProfileSchema.migrate({ version = 2, cash = 5 })
		expect(p.pets.puppy.level).toBe(1)
		expect(p.petActive).toBe("puppy")
	end)

	it("bad pet data is cleaned: unknown pets, huge levels, bad active pet", function()
		local p = ProfileSchema.migrate({
			version = 2,
			pets = { pig = { level = 99, xp = 7 }, ghost = { level = 3, xp = 0 }, cat = "x" },
			petActive = "dragon", -- not owned
			petProgress = { megaBeats = 3.7 },
		})
		expect(p.pets.pig.level).toBe(PetConfig.MAX_LEVEL)
		expect(p.pets.pig.xp).toBe(0)
		expect(p.pets.ghost).toBe(nil)
		expect(p.pets.cat).toBe(nil)
		expect(p.petActive).toBe("puppy")
		expect(p.petProgress.megaBeats).toBe(3)
	end)

	it("pets survive a save round trip", function()
		local p = ProfileSchema.default()
		p.pets.bunny = { level = 4, xp = 9 }
		p.petActive = "bunny"
		local back = ProfileSchema.migrate(p)
		expect(back.pets.bunny.level).toBe(4)
		expect(back.pets.bunny.xp).toBe(9)
		expect(back.petActive).toBe("bunny")
	end)

	it("no pet can be bought or rolled: every goal is a plain count", function()
		for _, def in PetConfig.Pets do
			expect(def.goal == "free" or def.target > 0).toBeTruthy()
		end
	end)
end)

describe("Coin pets: goals unlock the other four", function()
	it("pig = 1,000 flips", function()
		local p = ProfileSchema.default()
		p.stats.flips = 999
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		p.stats.flips = 1000
		local fresh = PetRules.checkUnlocks(p)
		expect(fresh[1]).toBe("pig")
		expect(p.pets.pig.level).toBe(1)
	end)

	it("bunny = 10 heads in a row (the streak system's best streak)", function()
		local p = ProfileSchema.default()
		p.stats.bestStreak = 9
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		p.stats.bestStreak = Config.STREAK_GOAL
		expect(PetRules.checkUnlocks(p)[1]).toBe("bunny")
		p.stats.bestStreak = 0 -- a later skull never takes the pet away
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		expect(p.pets.bunny ~= nil).toBeTruthy()
	end)

	it("bunny goal matches the streak goal", function()
		local bunny = PetRules.def("bunny") :: PetConfig.PetDef
		expect(bunny.target).toBe(Config.STREAK_GOAL)
	end)

	it("dragon = beat the mega coin 10 times", function()
		local p = ProfileSchema.default()
		for _ = 1, 9 do
			PetRules.recordMegaBeat(p)
		end
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		PetRules.recordMegaBeat(p)
		expect(PetRules.checkUnlocks(p)[1]).toBe("dragon")
	end)

	it("cat = reach the space plot", function()
		local p = ProfileSchema.default()
		p.resets = PetConfig.SPACE_PLOT_RESETS - 1
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		p.resets = PetConfig.SPACE_PLOT_RESETS
		expect(PetRules.checkUnlocks(p)[1]).toBe("cat")
	end)

	it("unlocking twice does not give it twice or reset its level", function()
		local p = ProfileSchema.default()
		p.stats.flips = 5000
		PetRules.checkUnlocks(p)
		p.pets.pig.level = 6
		expect(#PetRules.checkUnlocks(p)).toBe(0)
		expect(p.pets.pig.level).toBe(6)
	end)

	it("progress is capped at the goal and starts at zero", function()
		local p = ProfileSchema.default()
		local pig = PetRules.def("pig") :: PetConfig.PetDef
		local have, need = PetRules.progress(p, pig)
		expect(have).toBe(0)
		expect(need).toBe(1000)
		p.stats.flips = 99999
		have = PetRules.progress(p, pig)
		expect(have).toBe(1000)
	end)
end)

describe("Coin pets: flipping and leveling", function()
	it("the active pet pays cash and gives xp", function()
		local p = ProfileSchema.default()
		local before = p.cash
		local result = PetRules.flip(p, 1)
		expect(result ~= nil).toBeTruthy()
		expect(p.cash > before).toBeTruthy()
		expect(p.pets.puppy.xp).toBe(PetConfig.XP_PER_FLIP)
	end)

	it("no pet out means no flip", function()
		local p = ProfileSchema.default()
		expect(PetRules.setActive(p, "")).toBeTruthy()
		expect(PetRules.flip(p, 1)).toBe(nil)
		expect(p.cash).toBe(0)
	end)

	it("you can only put out pets you own", function()
		local p = ProfileSchema.default()
		for _, bad in { "dragon", "nope", 5, {}, false } do
			expect(PetRules.setActive(p, bad)).toBeFalsy()
		end
		expect(p.petActive).toBe("puppy")
	end)

	it("enough flips level the pet up, and max level stops at 10", function()
		local p = ProfileSchema.default()
		local levelUps = 0
		for _ = 1, 2000 do
			local r = PetRules.flip(p, 1)
			if r and r.leveled then
				levelUps += 1
			end
		end
		expect(p.pets.puppy.level).toBe(PetConfig.MAX_LEVEL)
		expect(p.pets.puppy.xp).toBe(0)
		expect(levelUps).toBe(PetConfig.MAX_LEVEL - 1)
		expect(PetRules.xpToNext(PetConfig.MAX_LEVEL)).toBe(nil)
	end)

	it("higher level = more cash and faster flips", function()
		local p = ProfileSchema.default()
		local def = PetRules.def("pig") :: PetConfig.PetDef
		expect(PetRules.flipCash(p, def, 10, 1) > PetRules.flipCash(p, def, 1, 1)).toBeTruthy()
		expect(PetRules.interval(def, 10) < PetRules.interval(def, 1)).toBeTruthy()
	end)

	it("the boost (mega 2x, pass) pays more, and never less than 1x", function()
		local p = ProfileSchema.default()
		p.upgrades.bigCoins = 6
		local def = PetRules.def("dragon") :: PetConfig.PetDef
		local one = PetRules.flipCash(p, def, 1, 1)
		expect(PetRules.flipCash(p, def, 1, 2) > one).toBeTruthy()
		expect(PetRules.flipCash(p, def, 1, 0.1)).toBe(one)
	end)

	it("later pets are worth more than the puppy", function()
		local p = ProfileSchema.default()
		p.upgrades.bigCoins = 20 -- big enough that rounding hides nothing
		local last = 0
		for _, def in PetConfig.Pets do
			local perSecond = PetRules.flipCash(p, def, 1, 1) / PetRules.interval(def, 1)
			expect(perSecond > last).toBeTruthy()
			last = perSecond
		end
	end)

	it("a pet's cash grows with resets like everything else", function()
		local p = ProfileSchema.default()
		local def = PetRules.def("puppy") :: PetConfig.PetDef
		local a = PetRules.flipCash(p, def, 1, 1)
		p.resets = 3
		expect(PetRules.flipCash(p, def, 1, 1) > a).toBeTruthy()
		expect(Economy.cashPerHeads(p) > 0).toBeTruthy()
	end)

	it("the pet card list shows all five, owned or not", function()
		local p = ProfileSchema.default()
		local views = PetRules.view(p)
		expect(#views).toBe(5)
		expect(views[1].owned).toBeTruthy()
		expect(views[1].active).toBeTruthy()
		expect(views[2].owned).toBeFalsy()
		expect(views[2].need).toBe(1000)
	end)
end)
