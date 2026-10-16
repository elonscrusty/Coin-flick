-- quests: the DAILY panel (daily gift + three daily quests) from the HUD DAILY button (left column). Today's quests come from the
-- real shared/Quests rules for this player and day; --set done=1 finishes the first quest (claimable) and claims
-- yesterday's gift so the streak strip shows day 2; --set day=N makes streak day N today's claimable tile (day=7: the
-- big day with its free Rare Egg, LaunchPerks.StreakEgg).
local C = lib("ctr")
local Quests = preview.shared("Quests")
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version -- no What's New popup racing the Daily open on phones
		local day = tonumber(preview.args.day)
		if day and day >= 1 then
			local today = Quests.day(os.time())
			data.Daily = Quests.empty()
			data.Daily.GiftDay, data.Daily.Streak = today - 1, day - 1
		end
		if preview.args.done then
			local me = game:GetService("Players").LocalPlayer
			local today = Quests.day(os.time())
			data.Daily = Quests.empty()
			data.Daily.GiftDay, data.Daily.Streak = today - 1, 1
			local q = Quests.forDay(me.UserId, today)[1]
			Quests.bump(data.Daily, me.UserId, today, q.Kind, q.Goal)
		end
	end,
})
C.settle(1)
local hits = preview.findGui(function(obj)
	-- the DAILY button sits in Left (keyboard) or in the Actions row (touch screens, SafeZones.lobbyLayout)
	return obj:IsA("GuiButton") and obj.Name == "Quests" and obj.Parent ~= nil and (obj.Parent.Name == "Left" or obj.Parent.Name == "Actions")
end)
if hits[1] then
	preview.click(hits[1])
	print("QUESTS tile found")
else
	print("[FAIL] QUESTS tile missing")
end
C.settle(1)
C.followCamera()
