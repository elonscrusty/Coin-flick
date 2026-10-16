--!strict
-- HINT RULES: the one rule for tutorial / tip hints (pure; tests/test_hint_rules.luau).
--   * Each hint has an id. A hint hides for good once its step is done (done is remembered: it never comes back,
--     even if the caller asks again), and it hides after its timeout (seconds really on screen; time with a menu
--     over it does not count). A timed-out hint stays hidden for the rest of the session.
--   * Hint text is device aware: a key name only for a player who really uses a keyboard / mouse or a gamepad. Touch
--     players are never told to press a key (bug #221).
--   * The hunt's first hint says the goal and the action together: find the pet egg; grab eggs, bring them to your
--     nest, hatch them (walkthrough 2026-10-14 #9).

local HintRules = {}

export type Input = "Touch" | "Keyboard" | "Gamepad"

-- Seconds on screen before a hint retires for the session (nil = no timeout: the hint follows the action).
HintRules.Timeout = {
	Lobby = 10, -- every lobby tutorial hint (Pet Book, sell candy, goal): the marker and menus keep pointing the way
	Pickup = 15, -- the hunt's first hint (goal + controls)
	FreePet = 30, -- the world "FREE PET!" tag over the starter egg (the egg keeps glowing and sparkling)
}

-- Which input the wording should use. `last` is the name of UserInputService:GetLastInputType(); a phone whose last
-- input reads as something else (Focus, None, a stray mouse event) gets touch wording, never a key.
function HintRules.inputKind(last: string, touchEnabled: boolean, keyboardEnabled: boolean): Input
	if string.sub(last, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	local keys = last == "Keyboard" or string.sub(last, 1, 5) == "Mouse"
	if last == "Touch" or not keys or (touchEnabled and not keyboardEnabled) then
		return "Touch"
	end
	return "Keyboard"
end

-- The control that grabs an egg, named for the input (touch: the on-screen PICK UP button).
local GRAB = { Keyboard = "hold E", Gamepad = "hold RT", Touch = "hold PICK UP" }

-- The hunt's first hint: goal and action in one line.
function HintRules.pickupTip(input: Input): string
	return "Find the pet egg! Grab eggs (" .. GRAB[input] .. "), hatch them at your nest!"
end

-- After the first plain egg: keyboard players learn the cursor key, everyone else hears the goal again.
function HintRules.candyTip(input: Input): string
	if input == "Keyboard" then
		return "Just candy! Hold ALT to click buttons!"
	end
	return "Just candy! One egg hides the pet!"
end

-- Lifetime ----------------------------------------------------------------------------------------

export type State = { Shown: { [string]: number }, Retired: { [string]: boolean }, Done: { [string]: boolean } }

function HintRules.new(): State
	return { Shown = {}, Retired = {}, Done = {} }
end

-- Marks a hint done: it never shows again.
function HintRules.done(s: State, id: string)
	s.Done[id] = true
end

-- True when hint `id` may show now. `dt` = seconds since the last call, counted only when `onScreen` (the hint really
-- had the screen: no menu over it). `timeout` = seconds before it retires (nil = never times out).
function HintRules.visible(s: State, id: string, timeout: number?, onScreen: boolean, dt: number): boolean
	if s.Done[id] or s.Retired[id] then
		return false
	end
	if timeout then
		if onScreen then
			local t = (s.Shown[id] or 0) + math.clamp(dt, 0, 0.5)
			s.Shown[id] = t
			if t >= timeout then
				s.Retired[id] = true
				return false
			end
		end
	end
	return true
end

HintRules.PickupKey = "Find the pet egg!" -- the id of the hunt's first hint (any input)

-- One id per hint text, so a hint whose wording carries a live number ("Nice! You have 120 coins") keeps one clock.
function HintRules.key(text: string): string
	return string.match(text, "^(Nice! You have )") or string.match(text, "^(Find the pet egg!)") or text
end

return HintRules
