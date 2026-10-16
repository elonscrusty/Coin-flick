-- Hint rules (shared/HintRules): device-aware hint wording and the one lifetime rule for tutorial / tip hints.
return function(t)
	local test, shared = t.test, t.shared
	local fs = require("@lune/fs")
	local H = shared("HintRules")

	local function hasKey(text: string): boolean
		-- a keyboard / gamepad key named as a control ("hold E", "press F", "ALT", "RT")
		for _, w in { "E", "F", "Q", "R", "ALT", "RT", "LT", "SHIFT", "SPACE", "CTRL" } do
			if string.find(" " .. text .. " ", "[%s%(]" .. w .. "[%s%)!,.]") then
				return true
			end
		end
		return false
	end

	test("hint rules: the input kind never reads a phone as a keyboard", function()
		assert(H.inputKind("Touch", true, false) == "Touch")
		assert(H.inputKind("Focus", true, false) == "Touch", "a phone after a focus event")
		assert(H.inputKind("None", true, false) == "Touch")
		assert(H.inputKind("MouseMovement", true, false) == "Touch", "a stray mouse event on a phone")
		assert(H.inputKind("Keyboard", false, true) == "Keyboard")
		assert(H.inputKind("MouseButton1", false, true) == "Keyboard")
		assert(H.inputKind("Gamepad1", false, false) == "Gamepad")
	end)

	test("hint rules: the hunt's first hint says the goal and the action, and names no key on touch", function()
		for _, input in { "Touch", "Keyboard", "Gamepad" } do
			local s = H.pickupTip(input)
			local low = string.lower(s)
			assert(string.find(low, "pet egg", 1, true), "goal: find the pet egg: " .. s)
			assert(string.find(low, "grab", 1, true) and string.find(low, "nest", 1, true) and string.find(low, "hatch", 1, true), "action: grab, nest, hatch: " .. s)
			assert(H.key(s) == H.PickupKey, "one id for every input")
		end
		assert(not hasKey(H.pickupTip("Touch")), H.pickupTip("Touch"))
		assert(not hasKey(H.candyTip("Touch")), H.candyTip("Touch"))
		assert(string.find(H.pickupTip("Keyboard"), "hold E", 1, true), "keyboard players get the key")
		assert(string.find(H.pickupTip("Gamepad"), "RT", 1, true))
	end)

	test("hint rules: a hint hides after its timeout on screen, a menu pauses the clock, done never comes back", function()
		local s = H.new()
		for _ = 1, 19 do
			assert(H.visible(s, "a", 10, true, 0.5), "still showing before 10 s")
		end
		for _ = 1, 100 do
			assert(H.visible(s, "a", 10, false, 0.5), "a menu over it: the clock waits")
		end
		assert(not H.visible(s, "a", 10, true, 0.5), "10 s on screen: retired")
		assert(not H.visible(s, "a", 10, true, 0), "and stays retired")
		assert(H.visible(s, "b", nil, true, 100), "no timeout: follows the action")
		H.done(s, "b")
		assert(not H.visible(s, "b", nil, true, 0), "done: hidden")
		assert(not H.visible(s, "b", nil, true, 0), "done: never comes back")
		assert(H.visible(s, "c", 10, true, 60), "a long frame counts at most 0.5 s")
		assert(H.key("Nice! You have $120! Buy upgrades!") == H.key("Nice! You have $300! Buy upgrades!"), "live numbers keep one clock")
	end)

	test("hint rules: the hint sources use the rule (no keyboard-only hunt tip, the FREE PET tag retires)", function()
		local main = fs.readFile("src/client/Main.client.luau")
		assert(not string.find(main, "hold E!", 1, true) and not string.find(main, "Aim the dot at an egg", 1, true), "old keyboard tip gone")
		assert(string.find(main, "HintRules.pickupTip(inputKind())", 1, true), "hunt tip from the rule")
		assert(string.find(main, "HintRules.visible(hintState", 1, true), "tutorial hints use the lifetime rule")
		assert(string.find(main, "HintRules.Timeout.Lobby", 1, true), "lobby hints time out (Tap PET BOOK ...)")
		local egg = fs.readFile("src/client/StarterEggView.luau")
		assert(string.find(egg, 'HintRules.visible(tagHints, "FreePet"', 1, true), "the FREE PET! world tag uses the rule")
		assert(H.Timeout.Lobby <= 15 and H.Timeout.Pickup <= 20 and H.Timeout.FreePet <= 45, "short timeouts")
	end)
end
