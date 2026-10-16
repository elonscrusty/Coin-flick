--!strict
-- WHAT'S NEW: the short update notes shown on the park's WHAT'S NEW board and once per version in a pop-up.
-- To announce an update: change Version (any new string) and the 3-5 Lines. Every player then sees the pop-up once;
-- the server stores the last version a player saw in the profile field LastSeenNews (SettingsAction).

local WhatsNew = {}

WhatsNew.Version = "2026.10.11"
WhatsNew.Title = "WHAT'S NEW"
WhatsNew.Lines = {
	"New jungle Pet Park lobby!",
	"Your own plot shows off your pets",
	"Visit other plots and tap LIKE",
	"Most liked plot wears the crown",
	"Boards: Rarest Pet and Highest Floor",
}

-- Pop-up rule: show when this version was not seen yet. Brand-new players finish the tutorial first.
function WhatsNew.shouldShow(lastSeen: any, onboardDone: boolean): boolean
	return onboardDone and lastSeen ~= WhatsNew.Version
end

-- Server rule for the intent: only the current version can be stored (nothing else is accepted).
function WhatsNew.accept(value: any): string?
	if type(value) == "string" and value == WhatsNew.Version then
		return value
	end
	return nil
end

return WhatsNew
