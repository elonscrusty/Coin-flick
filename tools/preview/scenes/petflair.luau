-- petflair: rare hatch banner + fireworks, lobby name tags (title + best tower floor), pet index first-find coins.
-- --set banner=local (default: Ava hatched a Legendary in this server, fireworks) | global (another server, no
-- fireworks) | none. --set at=S seconds after the banner starts (default 0.4). --set view=tags (default, close on the
-- name tags) | follow (the usual camera behind the player).
-- Also checks on the server (printed): the first hatch of a species pays Config.PetIndex.FirstFindCoins once, and a
-- second grant of the same award key pays nothing.
local C = lib("ctr")
local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
		data.TowerBest = 12
		-- nine species found: the tenth (Phoenix) is hatched below through the real grant
		for _, id in { "Raptor", "Ostrich", "DireWolf", "Griffin", "FrostWyvern", "Mammoth", "LavaTRex", "CosmicDragon", "StarPterodactyl" } do
			data.DiscoveryIndex[id] = 1
		end
	end,
})
local Profiles = s.Profiles
local me = s.me
local ava = s.others[1]
C.place(ava, me.Character.HumanoidRootPart.CFrame * CFrame.new(7, 0, -3)) -- beside the player, so both tags show
local avaData = Profiles.get(ava)
if avaData then
	avaData.TowerBest = 4
	Profiles.changed(ava)
end
C.settle(0.5)

-- pet index: the real grant path (Profiles.grantSpecimen)
local spec = C.fakeSpecimens(1)[1]
spec.Mineral = "Phoenix"
spec.Rarity = "Epic"
local before = Profiles.get(me).Cash
local okA = Profiles.grantSpecimen(me, "flair-test-1", spec, "Solo")
local after1 = Profiles.get(me).Cash
local okB = Profiles.grantSpecimen(me, "flair-test-1", spec, "Solo")
local after2 = Profiles.get(me).Cash
local spec2 = table.clone(spec)
spec2.Id = spec.Id .. "-b"
Profiles.grantSpecimen(me, "flair-test-2", spec2, "Solo")
local after3 = Profiles.get(me).Cash
print(string.format("PETINDEX first=%s paid=%d again=%s paid=%d sameSpecies paid=%d", tostring(okA), after1 - before, tostring(okB), after2 - after1, after3 - after2))
C.settle(0.5)
print("NAMETAG me Title=" .. tostring(me:GetAttribute("Title")) .. " TowerBest=" .. tostring(me:GetAttribute("TowerBest")))
print("NAMETAG ava Title=" .. tostring(ava:GetAttribute("Title")) .. " TowerBest=" .. tostring(ava:GetAttribute("TowerBest")))

-- clear the reward toasts out of the picture (they wait for the longest reveal, then hold a few seconds)
C.settle(14)

local banner = preview.args.banner or "local"
if banner == "local" then
	local RareHatch = C.server("RareHatch")
	local legendary = table.clone(spec)
	legendary.Mineral = "CosmicDragon"
	legendary.Rarity = "Legendary"
	legendary.Modifier = "Golden"
	C.try("announce", RareHatch.announce, ava, legendary)
elseif banner == "global" then
	local Net = C.shared("Net")
	Net.event("RareHatch"):FireAllClients("Global", { Name = "Mia", Pet = "Solar Phoenix", Rarity = "Rare" })
end
preview.advance(tonumber(preview.args.at) or 0.4, 30)

if preview.args.view == "follow" then
	C.followCamera()
else
	-- side-on, so both players' tags are apart (Ava stands 4 studs to the player's side)
	local root = me.Character.HumanoidRootPart.CFrame
	local mid = (root * CFrame.new(2, 2.5, 1)).Position
	C.cameraAt(mid, root.LookVector * 14 + Vector3.new(0, 2, 0), 60)
end

-- --set reveal=Common|Rare|Epic|Legendary [--set rt=S]: the hatch reveal (RevealView) for that rarity, S real seconds
-- in (Common runs about 2 s, Rare+ about 6 s in slow motion with the rarity glow; Config.Hatch).
local revealRarity = preview.args.reveal
if revealRarity then
	local RevealView = preview.client("RevealView")
	local GeodeGen = C.shared("GeodeGen")
	local pet = table.clone(spec)
	pet.Rarity = revealRarity
	pet.Mineral = "CosmicDragon"
	C.try("reveal", RevealView.play, { Specimen = GeodeGen.public(pet), Kind = "Solo" }, "You found the pet!", true)
	preview.advance(tonumber(preview.args.rt) or 2, 30)
	print("REVEAL playing=" .. tostring(RevealView.isPlaying()))
end
