-- Master Prompt 7, Pass E: lifecycle rules that are pure enough for Lune. The client wiring (HUD cleared on return,
-- no cinematic camera after the reveal) is checked in the preview scene `loop` (step=lobby) and the `fp` scenes.
return function(t)
	local test = t.test
	local CameraModeRules = t.shared("CameraModeRules")

	-- every order in which three holders (menu, results card, reveal) can let go
	local orders = {
		{ "a", "b", "c" },
		{ "a", "c", "b" },
		{ "b", "a", "c" },
		{ "b", "c", "a" },
		{ "c", "a", "b" },
		{ "c", "b", "a" },
	}

	test("m7 modal stack: any close order restores play exactly once", function()
		for _, order in orders do
			local s = CameraModeRules.newStack()
			local blockedNow = false
			local restores = 0
			local function set(key: string, on: boolean)
				local b = CameraModeRules.hold(s, key, on)
				if blockedNow and not b then
					restores += 1
				end
				blockedNow = b
			end
			set("a", true)
			set("b", true)
			set("c", true)
			for _, k in order do
				set(k, false)
			end
			assert(restores == 1, "restored " .. restores .. " times for order " .. table.concat(order, ","))
			assert(not blockedNow, "free after the last release")
			-- a late duplicate close (a panel closed twice) changes nothing and restores nothing
			set("a", false)
			assert(restores == 1 and not blockedNow, "duplicate close is harmless")
			local d = CameraModeRules.decide({ FirstPerson = true, Blocked = blockedNow, Cinematic = false })
			assert(d.Actions and d.Reticle and not d.CursorFree, "play state back: reticle, actions, locked cursor")
		end
	end)

	test("m7 modal stack: a menu opened over a held panel never restores play early", function()
		local s = CameraModeRules.newStack()
		CameraModeRules.hold(s, "results", true)
		CameraModeRules.hold(s, "collection", true)
		assert(CameraModeRules.hold(s, "results", false), "results gone, the collection still holds")
		local d = CameraModeRules.decide({ FirstPerson = true, Blocked = true, Cinematic = false })
		assert(d.CursorFree and not d.Actions and not d.Reticle)
		assert(not CameraModeRules.hold(s, "collection", false))
	end)

	test("m7 reveal: when the reveal camera lets go no cinematic state is left behind", function()
		-- the reveal holds a cinematic key and a modal key; each is released once, in either order
		for _, cinematicFirst in { true, false } do
			local cine, modal = CameraModeRules.newStack(), CameraModeRules.newStack()
			CameraModeRules.hold(cine, "reveal", true)
			CameraModeRules.hold(modal, "reveal", true)
			local c, m
			if cinematicFirst then
				c = CameraModeRules.hold(cine, "reveal", false)
				m = CameraModeRules.hold(modal, "reveal", false)
			else
				m = CameraModeRules.hold(modal, "reveal", false)
				c = CameraModeRules.hold(cine, "reveal", false)
			end
			local d = CameraModeRules.decide({ FirstPerson = true, Blocked = m, Cinematic = c })
			assert(d.Mode == "LockFirstPerson" and d.Actions and d.Reticle and not d.CursorFree, "play state after the reveal")
		end
	end)
end
