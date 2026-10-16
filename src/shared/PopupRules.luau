--!strict
-- One rule for every popup that is not part of a fight (Studio 2026-10-14: the NEXT GOAL card and toasts popped over
-- a Pet Battle). Pure; the client wrapper is client/PopupGate (reads the player's attributes and the fight holds).
--   Toast  small notices: wait while a Pet Battle or a tower climb is on screen (a hunt keeps its toasts).
--   Card   big cards and dialogs (NEXT GOAL, away nest, welcome, level ups): also wait through a hunt round.
-- Popups that belong to the fight itself (the result card, "Floor N cleared!") are shown by the fight code directly
-- and never go through this gate.

local PopupRules = {}

export type Busy = {
	MatchKey: any?, -- player attribute: in a hunt (server)
	InTower: any?, -- player attribute: climbing the Training Tower
	InBattle: any?, -- player attribute: in a Pet Battle (set at the fight start, cleared after the result)
	Match: any?, -- client State.Match: a hunt round is open
	Held: boolean?, -- a client fight view holds popups (FightCam from the count-in to the hero shot's end)
	Shown: boolean?, -- a menu or another big card is already on screen (Studio 2026-10-15: NEXT GOAL over WHAT'S NEW)
}

PopupRules.Kinds = { Toast = true, Card = true }

-- Seconds a released popup waits after the fight view closes, so it never lands on the last frame of the fight.
PopupRules.Breath = 1.5

function PopupRules.fighting(s: Busy): boolean
	return s.Held == true or s.InBattle == true or s.InTower == true
end

-- Whether a popup of `kind` may show now.
function PopupRules.free(kind: string, s: Busy): boolean
	if PopupRules.fighting(s) then
		return false
	end
	if kind == "Card" then
		return s.MatchKey == nil and s.Match == nil and s.Shown ~= true -- big cards come one at a time
	end
	return true
end

-- Big cards that pop up on their own (UI.dialogLayer children); any of them on screen counts as Shown.
PopupRules.Cards = { "NextGoal", "AwayNest" }


-- A card that pops up on its own (NEXT GOAL, away nest) closes itself after CardLife seconds, and at once when its kind
-- stops being free (a hunt, tower climb or Pet Battle starts under it). Studio 2026-10-15: the NEXT GOAL card stayed
-- mid-screen into the hunt.
PopupRules.CardLife = 20
function PopupRules.cardStays(shownFor: number, s: Busy): boolean
	-- the card itself is on screen, so Shown never closes it; only a hunt / climb / battle or its age does
	return shownFor < PopupRules.CardLife and PopupRules.free("Card", { MatchKey = s.MatchKey, InTower = s.InTower, InBattle = s.InBattle, Match = s.Match, Held = s.Held })
end

-- The player's own avatar is hidden for the player (others still see it) for the whole of any fight view: a Pet Battle
-- or a tower climb, where it stands on its mark between the camera and the pets (Studio 2026-10-15: tower fight).
function PopupRules.hideSelf(inBattle: boolean, inTower: boolean): boolean
	return inBattle or inTower
end

return PopupRules
