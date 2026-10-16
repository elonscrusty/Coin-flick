-- inspect: the read-only INSPECT card for a specimen in someone's gallery, opened by the real
-- "Inspect" event. --set rarity=Legendary picks a specimen of that rarity, --set you=on (own gallery).
local C = lib("ctr")
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
C.settle(1)
local specs = C.fakeSpecimens(30)
local pick = specs[1]
for _, g in ipairs(specs) do
	if preview.args.rarity and g.Rarity == preview.args.rarity then
		pick = g
		break
	end
end
preview.fireClient("Inspect", { Owner = "Ben_the_Breaker", IsYou = preview.args.you == "on", Specimen = pick })
C.settle(1)
C.followCamera()
