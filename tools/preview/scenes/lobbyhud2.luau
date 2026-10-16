-- lobbyhud2: the live lobby HUD v2 (client/ui/LobbyHudV2, carter's painted buttons) over the lobby.
--   --set queue=1    joined the hunt queue: the queue line over PLAY
--   --set press=Play   that button held down (squash) when the shot is taken
--   --set idle=Play --set at=S   that button's idle move, S seconds in (stars, glow, flash, wiggles)
--   --set lowpoly=1    carter's low-poly button set (preview-only ids until the real uploads)
--   --set low=1        with Low Effects on (moves, no decorations)
local C = lib("ctr")
if preview.args.lowpoly then
	local Art = preview.shared("LobbyHudArt")
	for i, n in { "Play", "Train", "Fight", "MyPets", "PetBook", "Daily", "Spin", "Shop" } do
		Art.LowPoly[n].Id = 1015000000 + i -- preview-only (art/artmap.json)
	end
end
C.boot({
	profile = function(data)
		data.Cash = 12450
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version
		if preview.args.low then
			data.Settings.LowEffects = true
		end
	end,
})
C.settle(2)
if preview.args.queue then -- --set queue=1: joined the hunt queue (the line over PLAY)
	preview.fireServerAs(game:GetService("Players").LocalPlayer, "PartyAction", "Queue")
	C.settle(1.5)
end
local press = preview.args.press
if press then
	local sg = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("LobbyHudV2")
	local p = sg and sg.SafeHUDRoot:FindFirstChild(press)
	local hit = p and p:FindFirstChild("Hit")
	if hit then
		hit.MouseButton1Down:_fire()
		C.settle(0.3)
	end
end
local idle = preview.args.idle
if idle then
	preview.require(preview.clientFolder().ui.LobbyHudV2).idle(idle)
	preview.advance(tonumber(preview.args.at) or 0.2, 60)
	print("IDLE " .. idle .. " at " .. tostring(preview.args.at))
end
C.followCamera()
