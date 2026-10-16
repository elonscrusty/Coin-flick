-- petshop: the PET SHOP (Pet Simulator style trial). --set tab=Featured|Eggs|Passes|Potions, --set pay=coins
--   --set ids=on   fake product / pass ids (PREVIEW ONLY) so prices show from the mock
-- Launch perks (PREVIEW ONLY fakes, shared/LaunchPerks):
--   --set pack=1          the Starter Pack is already bought (its card hides)
--   --set limited=1|short the limited egg is on sale: ends in 2d 4h, or "short" = 1:59:59
--   --set auto=BasicEgg   the shrine is auto-hatching that coin egg (AUTO ON; needs --set pay=coins)
--   --set lucky=1|soon    a lucky hour runs (43:12 left), or "soon" = the next one starts in 1-2 hours
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local C = lib("ctr")
local RobuxConfig = preview.shared("RobuxConfig")
if preview.args.ids == "on" then
	local n = 9000
	for _, list in ipairs({ RobuxConfig.Eggs, RobuxConfig.LimitedEggs }) do
		for _, e in ipairs(list) do
			for _, c in ipairs(RobuxConfig.EggCounts) do
				n += 1
				e.Products[c] = n
			end
		end
	end
	RobuxConfig.Potion.ProductId = 9100
	RobuxConfig.StarterPack.ProductId = 9101
	for _, key in ipairs(RobuxConfig.PassOrder) do
		n += 1
		RobuxConfig.Passes[key].PassId = n
	end
end
local now = os.time()
local limitedArg = preview.args.limited
if limitedArg == "1" or limitedArg == "on" then
	RobuxConfig.LimitedEggs[1].EndsAt = now + 2 * 86400 + 4 * 3600 + 90
elseif limitedArg == "short" then
	RobuxConfig.LimitedEggs[1].EndsAt = now + 2 * 3600
end
-- lucky hour: the profile view's LuckyHourIn comes from the real clock and RobuxConfig.Events.LuckyHours (the server
-- re-sends the view, so a client-side edit would not stick): no flag = no lucky hours today (no chip); "soon" = the
-- next one starts within the hour after next (1:00:xx to 2:00:00 away); "1" = one runs now (a ReplicatedStorage
-- attribute, set after boot; the server's clock loop only rewrites it on a change).
if preview.args.lucky == "soon" then
	RobuxConfig.Events.LuckyHours = { ((now % 86400) // 3600 + 2) % 24 }
else
	RobuxConfig.Events.LuckyHours = {}
end
local s = C.boot({
	profile = function(data)
		data.Cash = 12480
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.UnlockedTiers.Quarry = true
		if preview.args.pack == "1" then
			data.Robux.StarterPack = true
		end
		if type(preview.args.auto) == "string" and preview.args.auto ~= "" then
			data.Perks.AutoEgg = preview.args.auto
		end
	end,
})
local me = s.me
preview.advance(0.5)
me:SetAttribute("PaidRandomRestricted", false)
C.settle(1)
if preview.args.lucky == "1" or preview.args.lucky == "on" then
	ReplicatedStorage:SetAttribute("LuckyHourUntil", now + 43 * 60 + 12)
end
local PetShop = preview.require(preview.clientFolder().ui.PetShop)
PetShop.setPayCoins(preview.args.pay == "coins") -- --set pay=coins: the Eggs tab priced in coins
PetShop.open(preview.args.tab)
C.settle(1.2)
