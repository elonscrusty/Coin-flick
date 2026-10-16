-- spin: the LUCKY SPIN wheel panel (ui/SpinPanel) from the HUD SPIN card. The profile's spin clock starts ready.
--   --set land=Rare   spins the wheel onto that slice id (LaunchPerks.Spin.Slices) as the server's answer would
--   --set wait=1      the spin was used: the panel shows the countdown instead of SPIN!
local C = lib("ctr")
local LaunchPerks = preview.shared("LaunchPerks")
C.boot({
	profile = function(data)
		data.Cash = 1250
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version
		data.Perks = LaunchPerks.empty()
		if preview.args.wait then
			data.Perks.SpinAt = os.time() - 600 -- spun ten minutes ago
		end
	end,
})
C.settle(1)
local SpinView = preview.client("SpinView")
SpinView.openPanel()
C.settle(1)
local land = preview.args.land
if land then
	local sl = LaunchPerks.slice(land)
	if sl then
		local text = LaunchPerks.sliceText(sl, "Meadow")
		task.spawn(function()
			SpinView.landPanel(sl.Id, text)
		end)
		C.settle(5)
	else
		print("[FAIL] spin: no slice " .. tostring(land))
	end
end
C.followCamera()
