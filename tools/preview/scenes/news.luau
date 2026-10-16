-- news: the WHAT'S NEW pop-up (shared/WhatsNew) that opens by itself in the lobby for a player who has not seen
-- this version yet (tutorial done). Prints whether the server stored the version (profile LastSeenNews) after it showed.
-- --set seen=1 starts with the current version already seen (no pop-up expected).
local C = lib("ctr")
local WhatsNew = preview.shared("WhatsNew")
local s = C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
		data.Onboard.Skipped = true
		data.LastSeenNews = if preview.args.seen then WhatsNew.Version else ""
	end,
})
C.settle(4)
local hits = preview.findGui(function(obj)
	return obj.Name == "Modal_WhatsNew"
end)
print(if hits[1] then "WHATSNEW popup shown" else "WHATSNEW popup not shown")
local Profiles = C.server("Profiles")
local data = if Profiles then Profiles.get(s.me) else nil
print("WHATSNEW LastSeenNews", if data then data.LastSeenNews else "?", "version", WhatsNew.Version)
C.followCamera()
