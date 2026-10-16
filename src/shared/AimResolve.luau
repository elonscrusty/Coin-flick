--!strict
-- First-person aiming as pure functions (docs/m6/FIRST_PERSON.md). The client collects explicitly tagged
-- candidates (source rocks, the own table, a sell hopper, a lobby counter), each a point with a radius,
-- and gets back the ONE the camera-centre ray points at. Nothing here touches the engine, so it is tested
-- offline. The client's choice is a convenience only: the server validates every request on its own.
local AimResolve = {}

export type Candidate = {
	Key: any, -- stable id (rock id, "table", "sell", a prompt)
	Kind: string, -- "rock" | "table" | "sell" | "counter"
	Pos: Vector3,
	Radius: number, -- studs: how big the thing is to the ray
}

-- Perpendicular miss distance and distance along the ray of a point, or nil when it is behind the origin.
local function approach(origin: Vector3, dir: Vector3, pos: Vector3): (number?, number)
	local v = pos - origin
	local t = v:Dot(dir)
	if t < 0 then
		return nil, 0
	end
	local miss = (v - dir * t).Magnitude
	return t, miss
end

-- The candidate the ray passes through (within Radius + slack), nearest along the ray first; a rock the
-- ray passes through beats one it only grazes. Candidates farther than maxDist (plus their radius) are
-- ignored. Returns the candidate and its distance along the ray.
function AimResolve.pick(origin: Vector3, dir: Vector3, cands: { Candidate }, maxDist: number, slack: number): (Candidate?, number?)
	local best: Candidate? = nil
	local bestScore = math.huge
	local bestT = 0
	for _, c in cands do
		local t, miss = approach(origin, dir, c.Pos)
		if t ~= nil and t <= maxDist + c.Radius then
			local allow = c.Radius + slack
			if miss <= allow then
				local score = t + miss * 2
				if score < bestScore or (score == bestScore and best ~= nil and tostring(c.Key) < tostring(best.Key)) then
					best, bestScore, bestT = c, score, t
				end
			end
		end
	end
	return best, if best then bestT else nil
end

-- Reticle presentation from the contextual action id (ActionRules ids) and whether the ray is on a target.
--   eligible    the press does something now
--   unavailable the ray is on something that cannot be used; Reason is one concise line (nil = no text)
--   neutral     nothing to say (exploring)
export type Reticle = { State: string, Reason: string? }

local ELIGIBLE = { pickup = true, deposit = true, crush = true, sell = true, collect = false }
local REASONS: { [string]: string } = {
	take = "Basket full: put your eggs in your nest",
	bagfull = "Candy bag full: sell it",
	closer = "Move closer",
}

function AimResolve.reticle(ctxId: string, aimed: boolean): Reticle
	if ELIGIBLE[ctxId] then
		return { State = "eligible" }
	end
	local reason = REASONS[ctxId]
	if reason and (aimed or ctxId == "bagfull") then
		return { State = "unavailable", Reason = reason }
	end
	return { State = "neutral" }
end

return AimResolve
