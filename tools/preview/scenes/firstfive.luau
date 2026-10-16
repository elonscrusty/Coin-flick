-- firstfive: the first five minutes for a brand-new player in the lobby. The starter egg next to the spawn with its
-- route arrow and "FREE PET!", the FREE GIFT timer under PLAY and the Void Dragon statue.
--   --set view=egg (default)  behind the player, looking at the starter egg
--   --set view=gift           the gift ready to open (the timer turned green "OPEN!")
--   --set view=statue         the Void Dragon statue and its "1 in 1000" plinth
--   --set view=goal           the NEXT GOAL card after the first hatch (HUNT / TRAIN / BATTLE)
local C = lib("ctr")
local s = C.boot({
	profile = function(data)
		data.TutorialStep = 0
		data.StarterPet = preview.args.view == "statue" or preview.args.view == "goal"
		if preview.args.view == "gift" then
			data.StarterPet = true
			data.Retention.Play = { Day = math.floor(os.time() / 86400), Seconds = 70, Claimed = 0 }
		end
	end,
})
preview.advance(2)
local Workspace = game:GetService("Workspace")
local v = preview.args.view or "egg"
if v == "goal" then
	preview.client("RetentionView").goalCard({ Mineral = "Raptor", Rarity = "Rare", Modifier = "Natural", Seed = 7 })
	preview.advance(1.6)
	C.followCamera(16, 6)
elseif v == "statue" then
	local statue = Workspace:FindFirstChild("VoidDragonStatue", true)
	if statue then
		local p = statue:GetPivot()
		C.cameraAt(p.Position + Vector3.new(0, 10, 0), p.LookVector * 34 + Vector3.new(0, 6, 0), 60)
	else
		print("[FAIL] firstfive: no statue")
	end
else
	local egg = Workspace:FindFirstChild("StarterEgg_Local", true)
	if v == "egg" and not egg then
		print("[FAIL] firstfive: no starter egg")
	end
	C.followCamera(16, 6)
end
print("FIRSTFIVE DONE")
