--!strict
-- Countdown number rules for client/RoundIntro (pure, tested in tests/test_hunt_fun.luau).
-- Studio 2026-10-15: a big "1" stayed on screen for a whole hunt. Round numbers restart at 1 in every new match, so
-- "GO already shown for round 1" from the last hunt blocked this hunt's GO. Rounds are keyed by match key + round.

local IntroRules = {}

-- One id per round of one match (the match key alone repeats nothing, the round alone repeats every match).
function IntroRules.roundKey(matchKey: any, round: any): string
	return tostring(matchKey) .. ":" .. tostring(round)
end

local DIGITS = { ["1"] = true, ["2"] = true, ["3"] = true }

-- What the centre number becomes once the hunt is Searching: "GO!" the first time this round, "" for any countdown
-- digit still showing after that, nil = leave it as it is.
function IntroRules.onSearching(shown: string, goKey: string?, key: string): string?
	if not DIGITS[shown] then
		return nil
	end
	return if goKey ~= key then "GO!" else ""
end

return IntroRules
