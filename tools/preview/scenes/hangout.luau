-- hangout: the lobby with an hourly event on (status card) and a sky beam over the egg shrine.
-- --set race=off shows the plain lobby HUD with the emote grid open instead (the pet race itself was removed).
local C = lib("ctr")
local s = C.boot({
	profile = function(data)
		data.Cash = 1250
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version
	end,
})
local me = s.me
if preview.args.race ~= "off" then
	preview.fireClient("HangoutEvent", "Event", { State = "Start", Name = "Coin Rain" })
	preview.fireClient("RareHatch", "Local", { Name = "Sam", Pet = "Void Dragon", Rarity = "Legendary" })
else
	local gui = me.PlayerGui:FindFirstChild("CT_Hangout", true)
	local row = gui and gui:FindFirstChild("EmoteRow")
	if row then
		row.Visible = true
	end
end
preview.advance(1.5)
