local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventText = require(ReplicatedStorage.Shared.Util.EventText)
local WeekendEvents = require(ReplicatedStorage.Shared.Util.WeekendEvents)

local DAY = 86400
-- 1970-01-03 was a Saturday: day 2 since the epoch.
local SAT = 2 * DAY

local function view(claimable, lefts)
	local gifts = {}
	for i, left in lefts do
		table.insert(gifts, {
			slot = i,
			minutes = i,
			cash = 1,
			hats = 0,
			state = if left == 0 then "ready" else "waiting",
			left = left,
		})
	end
	return { seconds = 0, gifts = gifts, claimable = claimable }
end

describe("Event chip words", function()
	it("time spans are short", function()
		expect(EventText.span(45)).toBe("0:45")
		expect(EventText.span(125)).toBe("2:05")
		expect(EventText.span(3 * 3600 + 120)).toBe("3h 02m")
		expect(EventText.span(DAY + 5 * 3600)).toBe("1d 5h")
		expect(EventText.span(-4)).toBe("0:00")
	end)

	it("weekend shows luck and the time left; a weekday shows nothing", function()
		local weekend = WeekendEvents.status(SAT + 4000) -- not in a rain slot
		expect(weekend.weekend).toBeTruthy()
		local text = EventText.event({
			weekend = true,
			luckMult = 2,
			rain = false,
			cashMult = 1,
			endsAt = SAT + 2 * DAY,
			startsAt = 0,
			rainEndsAt = 0,
			nextRainAt = 0,
			weekEndsAt = 0,
		}, SAT + 4000)
		expect(text).toBe("🍀 2x LUCK 1d 22h")
		expect(EventText.event(WeekendEvents.status(0), 0)).toBe("")
		expect(EventText.event(nil, 0)).toBe("")
	end)

	it("rain beats weekend and counts down", function()
		local ev = {
			weekend = true,
			luckMult = 2,
			rain = true,
			cashMult = 2,
			endsAt = SAT + 2 * DAY,
			startsAt = 0,
			rainEndsAt = SAT + 45,
			nextRainAt = SAT + 600,
			weekEndsAt = 0,
		}
		expect(EventText.event(ev, SAT)).toBe("🌧 RAIN 2x 0:45")
		expect(EventText.event(ev, SAT + 30)).toBe("🌧 RAIN 2x 0:15")
	end)

	it("every chip text is short enough to read at 14px in the chip", function()
		local longest = {
			"🌧 RAIN 2x 59:59",
			"🍀 2x LUCK 1d 22h",
			"🎁 9 READY!",
			"👫 2x cash",
		}
		for _, t in longest do
			local chars = 0
			for _, c in utf8.codes(t) do
				chars += if c > 0x2600 then 1.2 else 0.55
			end
			-- the smallest chip is 190px * 0.6 wide in the top middle
			expect(chars).toBeAtMost(10.5)
		end
	end)

	it("gifts: ready ones tap-open the shop; a near one counts down; a far one hides", function()
		local text, tap = EventText.gift(view(2, { 0, 900 }), 0)
		expect(text).toBe("🎁 2 READY!")
		expect(tap).toBeTruthy()
		local near, nearTap = EventText.gift(view(0, { 200, 900 }), 20)
		expect(near).toBe("🎁 3:00")
		expect(nearTap).toBeFalsy()
		local ripe, ripeTap = EventText.gift(view(0, { 200 }), 200)
		expect(ripe).toBe("🎁 READY!")
		expect(ripeTap).toBeTruthy()
		expect(EventText.gift(view(0, { 1200 }), 0)).toBe("")
		expect(EventText.gift(nil, 0)).toBe("")
	end)

	it("several alerts take turns; a ready gift comes first", function()
		local ev = {
			weekend = true,
			luckMult = 2,
			rain = false,
			cashMult = 1,
			endsAt = SAT + 2 * DAY,
			startsAt = 0,
			rainEndsAt = 0,
			nextRainAt = 0,
			weekEndsAt = 0,
		}
		local list = EventText.alerts(ev, view(1, { 0 }), 0, 2, SAT + 4000)
		expect(#list).toBe(3)
		expect(list[1].kind).toBe("gift")
		expect(list[2].kind).toBe("event")
		expect(list[3].kind).toBe("friend")
		local seen = {}
		for tick = 0, 8 do
			local a = EventText.pick(list, tick)
			seen[a.kind] = true
		end
		expect(seen.gift and seen.event and seen.friend).toBeTruthy()
		expect(EventText.pick({}, 3)).toBe(nil)
	end)

	it("weekly board timer", function()
		expect(EventText.weekReset(1000 + 3 * DAY + 4 * 3600, 1000)).toBe("Resets in 3d 4h")
		expect(EventText.weekReset(1000, 2000)).toBe("Resets now!")
	end)

	it("banners: title and a clean line for each Notice kind", function()
		local t1, l1 = EventText.banner("event", "COIN RAIN! Heads pay x2!")
		expect(t1).toBe("COIN RAIN!")
		expect(l1).toBe("Heads pay x2!")
		local t2, l2 = EventText.banner("event", "WEEKEND! Rare coins x2 luck!")
		expect(t2).toBe("WEEKEND!")
		expect(l2).toBe("Rare coins x2 luck!")
		local t3, l3 = EventText.banner("playGift", "Play gift! +$1.50K and +10 🎩")
		expect(t3).toBe("PLAY GIFT!")
		expect(l3).toBe("+$1.50K and +10 🎩")
		local t4, l4 = EventText.banner("badge", "Badge: Flip Master!")
		expect(t4).toBe("NEW BADGE!")
		expect(l4).toBe("Flip Master!")
		expect(EventText.banner("bought", "x")).toBe(nil)
	end)
end)
