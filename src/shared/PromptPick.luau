--!strict
-- Which ONE world prompt wins (Master Prompt 4, section 27). Pure: the client collects candidates
-- (distance to the prompt's anchor, how directly the camera faces it) and gets one winner back.
-- Nearest wins, a candidate the camera faces gets a bonus, and the current winner is kept until another
-- beats it by a margin (so the label never flickers between two benches or two pedestals).
local PromptPick = {}

export type Candidate = {
	Key: any, -- the prompt (or any stable key)
	Distance: number, -- studs from the avatar to the prompt's anchor
	Range: number, -- the prompt's MaxActivationDistance
	Facing: number, -- 0..1, how much the camera looks at it (1 = straight at it)
}

PromptPick.FacingBonus = 4 -- studs of advantage for a prompt dead ahead
PromptPick.Hysteresis = 2.5 -- studs the challenger must beat the current winner by

local function score(c: Candidate): number
	return c.Distance - PromptPick.FacingBonus * math.clamp(c.Facing, 0, 1)
end

-- Returns the winning key or nil. Candidates outside their own range are never chosen.
function PromptPick.pick(cands: { Candidate }, current: any?): any?
	local best: Candidate? = nil
	local cur: Candidate? = nil
	for _, c in cands do
		if c.Distance <= c.Range then
			if c.Key == current then
				cur = c
			end
			if not best or score(c) < score(best) or (score(c) == score(best) and tostring(c.Key) < tostring(best.Key)) then
				best = c
			end
		end
	end
	if not best then
		return nil
	end
	if cur and score(cur) <= score(best) + PromptPick.Hysteresis then
		return cur.Key
	end
	return best.Key
end

return PromptPick
