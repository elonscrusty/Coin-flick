-- _juice: mid-animation frames of the UI juice pass (not in --all).
--   --set fx=pop  --set at=S   the DAILY panel S seconds after its tile is tapped (pop-in with overshoot)
--   --set fx=coin --set at=S   S seconds after CLAIM on a finished quest: coins fly along an arc to the cash header
--   --set fx=close --set at=S  S seconds after the panel's X is tapped (shrink and shade fade)
local C = lib("ctr")
local Quests = preview.shared("Quests")
local fx = preview.args.fx or "pop"
local at = tonumber(preview.args.at) or 0.08
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
		data.Onboard.Skipped = true
		local me = game:GetService("Players").LocalPlayer
		local today = Quests.day(os.time())
		data.Daily = Quests.empty()
		data.Daily.GiftDay, data.Daily.Streak = today - 1, 1
		local q = Quests.forDay(me.UserId, today)[1]
		Quests.bump(data.Daily, me.UserId, today, q.Kind, q.Goal)
	end,
})
C.settle(1)
C.followCamera()
local tile = preview.findGui(function(obj)
	return obj:IsA("GuiButton") and obj.Name == "Quests" and obj.Parent ~= nil and obj.Parent.Name == "Left"
end)[1]
if not tile then
	print("[FAIL] QUESTS tile missing")
	return
end
preview.click(tile)
if fx == "pop" then
	preview.advance(at, 60)
	print("JUICE pop at " .. at)
	return
end
C.settle(1)
if fx == "close" then
	local x = preview.findGui(function(obj)
		return obj:IsA("GuiButton") and obj.Name == "Hit" and obj.Parent ~= nil and obj.Parent.Name == "Close"
	end)[1]
	if x then
		preview.click(x)
		preview.advance(at, 60)
		print("JUICE close at " .. at)
	else
		print("[FAIL] close button missing")
	end
	return
end
local claim = preview.findGui(function(obj)
	return obj:IsA("GuiButton") and obj.Name == "Claim" and obj.Visible and string.find((obj:FindFirstChild("Label") :: any).Text or "", "CLAIM +", 1, true) ~= nil
end)[1]
if not claim then
	print("[FAIL] no claimable quest")
	return
end
preview.click(claim)
preview.advance(at, 60)
local layer = preview.findGui(function(obj)
	return obj.Name == "CoinFly"
end)
print("JUICE coin at " .. at .. " flying layers=" .. #layer)
