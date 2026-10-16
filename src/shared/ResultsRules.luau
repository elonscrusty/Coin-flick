--!strict
-- RESULTS RULES: what the hunt results card leads with and which few lines it shows (pure; tests/test_results_rules.luau).
-- The card's job is "go again": the primary (gold) button is PLAY AGAIN (READY! once a party member tapped it), or
-- TRAIN PET while the tutorial runs (find -> train -> fight, owner pick 2026-10-14). Selling candy is never the
-- primary button and never a button on this card (walkthrough 2026-10-14 #12: "GO SELL SHELLS" led the card).
-- Details are capped at MaxLines short rows: the reward line first, then one stat row, then the party lines.

local ResultsRules = {}

export type Primary = "PlayAgain" | "Ready" | "TrainPet"
export type Ctx = {
	Tutorial: boolean, -- the tutorial is still running (profile.OnboardDone false)
	Leader: boolean, -- this player starts the rematch
	Ready: boolean, -- a member who already tapped PLAY AGAIN
	Racers: number, -- players in the results
}

ResultsRules.MaxLines = 3

ResultsRules.Label = {
	PlayAgain = "PLAY AGAIN",
	Ready = "READY!",
	TrainPet = "TRAIN PET",
} :: { [string]: string }

function ResultsRules.primary(c: Ctx): Primary
	if c.Tutorial then
		return "TrainPet"
	end
	if not c.Leader and c.Ready then
		return "Ready"
	end
	return "PlayAgain"
end

-- The detail rows, in order, at most MaxLines: "Reward" (pet added / who hatched it), "Stats" (eggs hatched + candy
-- in one row), "Racers" (party hunts only). The bag strip, the pile-left line and the tutorial stage chips' extra
-- captions are left out: they were the tiny lines (bug #227).
function ResultsRules.lines(c: Ctx): { string }
	local out = { "Reward", "Stats" }
	if c.Racers > 1 and not c.Tutorial then
		table.insert(out, "Racers")
	end
	while #out > ResultsRules.MaxLines do
		table.remove(out)
	end
	return out
end

return ResultsRules
