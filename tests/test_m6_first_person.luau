-- Master Prompt 6, first person: the pure parts (aim resolver, reticle states, camera/cursor decision, modal stack,
-- input grace, touch layout with the first-person action). The client wiring is checked by the preview scenes.
return function(t)
	local test, shared, V3 = t.test, t.shared, t.Vector3
	local AimResolve = shared("AimResolve")
	local CameraModeRules = shared("CameraModeRules")
	local TouchLayout = shared("TouchLayout")
	local ActionRules = shared("ActionRules")

	local origin = V3.new(0, 5, 0)
	local fwd = V3.new(0, 0, -1)
	local function rock(key, x, y, z, r)
		return { Key = key, Kind = "rock", Pos = V3.new(x, y, z), Radius = r or 0.9 }
	end

	test("m6 aim: the ray picks the rock it passes through, nearest first", function()
		local cands = { rock(1, 0, 5, -6), rock(2, 0.2, 5, -4), rock(3, 5, 5, -4) }
		local c, d = AimResolve.pick(origin, fwd, cands, 11, 0.35)
		assert(c and c.Key == 2, "nearest rock on the ray")
		assert(d and math.abs(d - 4) < 1e-6)
		table.remove(cands, 2)
		c = AimResolve.pick(origin, fwd, cands, 11, 0.35)
		assert(c and c.Key == 1, "next one behind it")
	end)

	test("m6 aim: nothing when the ray misses, is behind or is too far", function()
		assert(AimResolve.pick(origin, fwd, { rock(1, 4, 5, -4) }, 11, 0.35) == nil, "off to the side")
		assert(AimResolve.pick(origin, fwd, { rock(1, 0, 5, 4) }, 11, 0.35) == nil, "behind the eye")
		assert(AimResolve.pick(origin, fwd, { rock(1, 0, 5, -20) }, 11, 0.35) == nil, "beyond the reach")
		assert(AimResolve.pick(origin, fwd, {}, 11, 0.35) == nil, "no candidates")
	end)

	test("m6 aim: slack forgives a near miss but not a wide one", function()
		local near = rock(1, 1.1, 5, -4, 0.9) -- 1.1 off the ray, radius 0.9 + slack 0.35
		assert(AimResolve.pick(origin, fwd, { near }, 11, 0.35) ~= nil)
		assert(AimResolve.pick(origin, fwd, { near }, 11, 0.1) == nil)
	end)

	test("m6 aim: a rock the ray goes through beats a nearer one it only grazes", function()
		local graze = rock(1, 1.2, 5, -2, 0.9) -- close but at the edge
		local centre = rock(2, 0, 5, -3, 0.9)
		local c = AimResolve.pick(origin, fwd, { graze, centre }, 11, 0.35)
		assert(c and c.Key == 2)
	end)

	test("m6 aim: equal candidates resolve the same way every time", function()
		local a, b = rock(7, 0, 5, -4), rock(3, 0, 5, -4)
		for _ = 1, 5 do
			local c = AimResolve.pick(origin, fwd, { a, b }, 11, 0.35)
			assert(c and c.Key == 3, "lower key wins a tie")
			c = AimResolve.pick(origin, fwd, { b, a }, 11, 0.35)
			assert(c and c.Key == 3, "order does not matter")
		end
	end)

	test("m6 reticle: states follow the one action context", function()
		assert(AimResolve.reticle("pickup", true).State == "eligible")
		assert(AimResolve.reticle("deposit", false).State == "eligible")
		assert(AimResolve.reticle("crush", false).State == "eligible")
		assert(AimResolve.reticle("sell", true).State == "eligible")
		local take = AimResolve.reticle("take", true)
		assert(take.State == "unavailable" and take.Reason ~= nil, "basket full on a rock says why")
		assert(AimResolve.reticle("take", false).State == "neutral", "no reason when not aimed")
		assert(AimResolve.reticle("closer", false).Reason == nil, "no constant Move closer while exploring")
		assert(AimResolve.reticle("closer", true).Reason == "Move closer", "only when the ray is on the thing")
		assert(AimResolve.reticle("none", true).State == "neutral")
		assert(AimResolve.reticle("wait", false).State == "neutral")
		assert(AimResolve.reticle("bagfull", false).Reason ~= nil, "a full rubble bag at the table is worth saying")
	end)

	test("m6 camera: first person, free cursor exactly while something blocks", function()
		local play = CameraModeRules.decide({ FirstPerson = true, Blocked = false, Cinematic = false })
		assert(play.Mode == "LockFirstPerson" and not play.CursorFree and play.Reticle and play.Actions)
		local menu = CameraModeRules.decide({ FirstPerson = true, Blocked = true, Cinematic = false })
		assert(menu.Mode == "LockFirstPerson" and menu.CursorFree and not menu.Reticle and not menu.Actions)
		local cine = CameraModeRules.decide({ FirstPerson = true, Blocked = false, Cinematic = true })
		assert(cine.CursorFree and not cine.Actions)
		local third = CameraModeRules.decide({ FirstPerson = false, Blocked = false, Cinematic = false })
		assert(third.Mode == "Classic" and not third.Reticle, "the third-person fallback has no reticle")
	end)

	test("m6 modal stack: gameplay returns only when the LAST panel closes", function()
		local s = CameraModeRules.newStack()
		assert(CameraModeRules.hold(s, "modal", true))
		assert(CameraModeRules.hold(s, "reveal", true))
		assert(CameraModeRules.hold(s, "modal", false), "one layer closed, the other still holds")
		assert(CameraModeRules.hold(s, "modal", true), "reopen while the reveal is up")
		assert(CameraModeRules.hold(s, "reveal", false), "reveal gone, the panel still holds")
		assert(not CameraModeRules.hold(s, "modal", false), "last one released")
		assert(not CameraModeRules.hold(s, "modal", false), "releasing twice is harmless")
		assert(CameraModeRules.hold(s, "modal", true) and CameraModeRules.hold(s, "modal", true), "holding twice is one key")
		assert(not CameraModeRules.hold(s, "modal", false), "and one release frees it")
	end)

	test("m6 input: the input that closed a menu cannot act", function()
		assert(not CameraModeRules.mayAct(true, 10, -math.huge, 0.25), "panel open")
		assert(not CameraModeRules.mayAct(false, 10.1, 10, 0.25), "right after the last panel closed")
		assert(CameraModeRules.mayAct(false, 10.3, 10, 0.25), "a fresh press later")
		assert(CameraModeRules.mayAct(false, 1, -math.huge, 0.25), "no panel was ever open")
	end)

	test("m6 touch: the first-person action stays clear of the jump button", function()
		for _, size in { { 1108, 512 }, { 844, 390 }, { 667, 375 }, { 390, 844 }, { 1024, 768 } } do
			local w, h = size[1], size[2]
			local right, bottom = TouchLayout.place(w, h, 76, h - 120, true)
			assert(not TouchLayout.overlapsJump(w, h, right, bottom, 96, 76), "action overlaps jump on " .. w .. "x" .. h)
		end
	end)

	test("m6 context: aiming decides pickup, the table keeps deposit and crush", function()
		local function id(over)
			local i = {
				Phase = "Searching", Active = true, HasStation = true, Basket = 0, Capacity = 5, Queue = 0, QueueCapacity = 10,
				Current = false, Machine = false, MachineFull = false, Rubble = 0, RubbleFull = false, NearHopper = false,
				AtTable = false, NearTable = false, HasTarget = false, NearPile = false,
			}
			for k, v in over do
				i[k] = v
			end
			return ActionRules.decide(i).Id
		end
		assert(id({}) == "none", "exploring: no button and no message")
		assert(id({ HasTarget = true }) == "pickup")
		assert(id({ HasTarget = true, Basket = 5 }) == "take")
		assert(id({ Basket = 3, AtTable = true }) == "deposit")
		assert(id({ Queue = 2, AtTable = true }) == "crush")
		assert(id({ Rubble = 4, NearHopper = true }) == "sell")
	end)
end
