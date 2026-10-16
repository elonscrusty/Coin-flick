-- Master Prompt 4 / M1 interaction rules: action context sequence, jump/action separation, one world
-- prompt, camera distance. Pure modules only (the client wiring is checked by the preview scenes).
return function(t)
	local test, shared = t.test, t.shared
	local ActionRules = shared("ActionRules")
	local TouchLayout = shared("TouchLayout")
	local PromptPick = shared("PromptPick")
	local CameraSolve = shared("CameraSolve")

	local function inputs(over)
		local i = {
			Phase = "Searching", Active = true, HasStation = true,
			Basket = 0, Capacity = 5, Queue = 0, QueueCapacity = 10, Current = false,
			Machine = false, MachineFull = false, Rubble = 0, RubbleFull = false,
			NearHopper = false, AtTable = false, NearTable = false, HasTarget = false, NearPile = false,
		}
		for k, v in over do
			i[k] = v
		end
		return i
	end
	local function id(over)
		return ActionRules.decide(inputs(over)).Id
	end

	test("m4 action: the full label sequence of one loop", function()
		assert(id({ HasTarget = true }) == "pickup", "empty basket at the pile")
		assert(id({ HasTarget = true, Basket = 3 }) == "pickup", "partly full")
		assert(id({ HasTarget = true, Basket = 5 }) == "take", "full at the pile is a status, not a pickup")
		assert(id({ Basket = 5 }) == "none", "full, far from everything: no button")
		assert(ActionRules.decide(inputs({ Basket = 5 })).Arrow == "table", "route hint to the table")
		assert(id({ Basket = 5, NearTable = true }) == "closer", "just outside the table")
		assert(id({ Basket = 5, AtTable = true }) == "deposit", "own table with room")
		assert(id({ Queue = 5, AtTable = true }) == "crush", "after the deposit")
		assert(id({ Queue = 0, Current = true, AtTable = true }) == "crush", "rock on the plate")
		assert(id({ AtTable = true }) == "collect", "queue empty")
		assert(id({ AtTable = true, Machine = true }) == "machine", "machine running, nothing carried")
		assert(id({ AtTable = true, Machine = true, MachineFull = true }) == "bagfull")
		assert(id({ AtTable = true, Queue = 3, RubbleFull = true }) == "bagfull", "full rubble bag blocks the hand tool")
		assert(id({ Rubble = 12, NearHopper = true }) == "sell", "hopper with rubble")
		assert(id({ NearHopper = true }) == "none", "hopper without rubble: no sell button")
	end)

	test("m4 action: deposit beats crush, machine only deposits", function()
		assert(id({ AtTable = true, Basket = 2, Queue = 4 }) == "deposit")
		assert(id({ AtTable = true, Basket = 2, Queue = 4, Machine = true }) == "deposit")
		assert(id({ AtTable = true, Basket = 2, Queue = 10 }) == "crush", "tray full: crush, never discard")
		assert(id({ AtTable = true, Basket = 2, Queue = 10, Machine = true }) == "machine")
	end)

	test("m4 action: no phantom button next to scenery or in other phases", function()
		assert(id({}) == "none", "exploring far from the pile and the table")
		assert(id({ NearPile = true }) == "closer", "just outside pickup reach")
		assert(id({ NearPile = true, Basket = 5 }) == "none", "full basket never asks for the pile")
		assert(ActionRules.decide(inputs({})).Arrow == "pile", "empty hands: route hint to the pile")
		assert(not ActionRules.visible("none") and not ActionRules.visible("wait") and not ActionRules.visible("securing"))
		assert(ActionRules.visible("pickup") and ActionRules.visible("closer"))
		assert(id({ Phase = "Countdown", HasTarget = true }) == "wait")
		assert(id({ Phase = "Reveal", AtTable = true, Basket = 5 }) == "securing")
		assert(id({ Phase = "Results", AtTable = true, Basket = 5 }) == "wait")
		local noHunt = inputs({})
		noHunt.Phase = nil
		assert(ActionRules.decide(noHunt).Id == "wait", "outside a hunt")
		assert(id({ Active = false, HasTarget = true }) == "wait", "stale after the round")
		assert(id({ HasStation = false, HasTarget = true }) == "wait", "no own table, no loop")
	end)

	test("m4 layout: the action never overlaps the reserved jump area", function()
		local sizes = { { 1108, 512 }, { 844, 390 }, { 390, 844 }, { 667, 375 }, { 1024, 768 }, { 852, 393 } }
		for _, s in sizes do
			local w, h = s[1], s[2]
			local actH = 72 * math.clamp(math.min(w / 800, h / 400), 0.8, 1.3)
			local actW = 112 * math.clamp(math.min(w / 800, h / 400), 0.8, 1.3)
			local right, bottom, mode = TouchLayout.place(w, h, actH, h - 58 - 70, true)
			assert(not TouchLayout.overlapsJump(w, h, right, bottom, actW, actH), "overlap at " .. w .. "x" .. h .. " mode " .. mode)
			-- and with a visible gap to the model's own jump rectangle
			local j = TouchLayout.jumpRect(w, h)
			local clearX = right >= j.Left + 8 or right + actW <= j.Right - 8
			local clearY = bottom >= j.Top + 8
			assert(clearX or clearY, "no gap to the modelled jump button at " .. w .. "x" .. h)
		end
	end)

	test("m4 layout: keyboard and mouse keep the corner, a tight screen falls back to the left of jump", function()
		local r, b, mode = TouchLayout.place(1920, 1080, 90, 900, false)
		assert(mode == "corner" and r == 20 and b == 90)
		local _, _, m2 = TouchLayout.place(844, 390, 70, 120, true) -- almost no room above
		assert(m2 == "left")
	end)

	test("m4 prompts: exactly one winner, nearest, facing helps, hysteresis holds", function()
		local function c(key, d, facing, range)
			return { Key = key, Distance = d, Range = range or 10, Facing = facing }
		end
		assert(PromptPick.pick({}, nil) == nil)
		assert(PromptPick.pick({ c("far", 12, 1) }, nil) == nil, "out of range")
		assert(PromptPick.pick({ c("a", 6, 0), c("b", 4, 0) }, nil) == "b", "nearest")
		assert(PromptPick.pick({ c("a", 5, 1), c("b", 4, 0) }, nil) == "a", "facing bonus")
		-- current winner kept inside the margin, replaced beyond it
		assert(PromptPick.pick({ c("a", 5, 0), c("b", 4, 0) }, "a") == "a")
		assert(PromptPick.pick({ c("a", 9, 0), c("b", 4, 0) }, "a") == "b")
		-- the current winner that left its range is gone
		assert(PromptPick.pick({ c("a", 11, 0), c("b", 9.5, 0) }, "a") == "b")
		-- deterministic tie
		assert(PromptPick.pick({ c("y", 5, 0), c("x", 5, 0) }, nil) == "x")
	end)

	test("m4 camera: pulls in at once, never past the minimum, eases out", function()
		assert(CameraSolve.allowed(12, {}) == 12)
		assert(CameraSolve.allowed(12, { nil, nil }) == 12)
		local d = CameraSolve.allowed(12, { 9, 15, nil })
		assert(math.abs(d - (9 - CameraSolve.Margin)) < 1e-9)
		assert(CameraSolve.allowed(12, { 0.5 }) == CameraSolve.MinDistance, "wall right behind the head")
		assert(CameraSolve.allowed(1.5, { 0.5 }) == 1.5, "the default camera is already closer than the minimum")
		assert(CameraSolve.smooth(10, 4, 0.016) == 4, "snap in")
		local s = CameraSolve.smooth(4, 12, 0.1)
		assert(s > 4 and s < 12, "ease out")
		assert(CameraSolve.smooth(nil, 7, 0.1) == 7)
	end)
end
