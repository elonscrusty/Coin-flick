-- tutorial: onboarding hint bar plus the yellow world markers (SELL HERE / YOUR GALLERY) over
-- the lobby station they point at. --set step=sell (default) rubble in the bag, step=gallery a geode
-- ready to show, step=goal the SHOP nudge, step=crack the first-hunt hint inside a practice pile.
local C = lib("ctr")
local step = preview.args.step or "sell"
local s = C.boot({
	profile = function(data)
		data.TutorialStep = if step == "crack" then 0 else 1
		data.Cash = 120
		local ob = data.Onboard
		if step == "sell" then
			ob.Started, ob.Cracked = true, true
			data.RubbleByTier = { Gravel = 14 }
		elseif step == "gallery" then
			ob.Started, ob.Cracked, ob.Geode, ob.Sold = true, true, true, true
			data.InventoryGeodes = C.fakeSpecimens(1)
		elseif step == "goal" then
			ob.Started, ob.Cracked, ob.Geode, ob.Sold, ob.Displayed = true, true, true, true, true
			data.Cash = 260
			data.InventoryGeodes = C.fakeSpecimens(1)
		end
	end,
})
if step == "crack" then
	local w = C.watchMatch()
	C.startSolo(w)
	C.waitPhase(w, "Searching", 6)
	C.settle(1)
	C.followCamera()
	return
end
local Workspace = game:GetService("Workspace")
local hopper
for _, d in Workspace:GetDescendants() do
	if d:IsA("Model") and d:GetAttribute("Hopper") then
		hopper = d:FindFirstChild("Body")
		break
	end
end
if step == "sell" and hopper then
	C.place(s.me, CFrame.new(hopper.Position + Vector3.new(0, -hopper.Size.Y / 2 + 0.1, 16)) * CFrame.Angles(0, math.pi, 0))
end
C.settle(2)
C.followCamera()
