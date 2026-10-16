-- Lobby hangout rules (shared/Hangout): daily likes, the mini-game coin cap, rock rules, the hourly
-- event rotation, secrets, the lookout and the group bonus.
return function(t)
	local test, shared = t.test, t.shared
	local H = shared("Hangout")
	local R = shared("Retention")

	test("hangout: found hidden eggs round-trip through the player attribute (audit F25)", function()
		local st = H.empty()
		assert(H.foundList(st) == "", "none found")
		H.claimSecret(st, "HiddenEgg10")
		H.claimSecret(st, "HiddenEgg2")
		st.Secrets.Junk = true
		local text = H.foundList(st)
		assert(text == "HiddenEgg2,HiddenEgg10", text)
		local set = H.parseFound(text .. ",Bogus,,")
		assert(set.HiddenEgg2 and set.HiddenEgg10 and not set.Bogus and not set.Junk, "parsed")
		assert(next(H.parseFound(nil)) == nil and next(H.parseFound(5)) == nil, "junk is empty")
	end)

	test("hangout: a like counts once per visitor per owner per day, never your own, and resets the next day", function()
		local v, o = H.empty(), H.empty()
		local ok, why = H.like(v, 1, v, 1, 100)
		assert(not ok and why == "own")
		assert(H.like(v, 1, o, 2, 100))
		ok, why = H.like(v, 1, o, 2, 100)
		assert(not ok and why == "again")
		assert(H.likesToday(o, 100) == 1 and H.likesToday(o, 101) == 0)
		assert(H.like(v, 1, o, 2, 101), "a new day allows a new like")
		assert(H.likesToday(o, 101) == 1, "yesterday's likes do not carry over")
	end)

	test("hangout: the liked list is capped", function()
		local v = H.empty()
		for i = 1, H.Likes.LikedMax do
			assert(H.like(v, 1, H.empty(), 1000 + i, 5))
		end
		local ok, why = H.like(v, 1, H.empty(), 99999, 5)
		assert(not ok and why == "max")
	end)

	test("hangout: sanitize repairs a broken save", function()
		local s = H.sanitize({ Day = "x", LikesToday = -4, Liked = 7, GameCoins = 0 / 0, Secrets = "no", GroupGift = 1 })
		assert(s.Day == 0 and s.LikesToday == 0 and type(s.Liked) == "table" and s.GameCoins == 0)
		assert(type(s.Secrets) == "table" and s.GroupGift == false)
		assert(type(H.sanitize(nil).Liked) == "table")
	end)

	test("hangout: mini-game coins stop at the daily cap and reset each day", function()
		local s = H.empty()
		local cap = H.Games.DailyCoinCap
		assert(H.payGame(s, 1, cap - 10) == cap - 10)
		assert(H.payGame(s, 1, 50) == 10, "only what is left today")
		assert(H.payGame(s, 1, 50) == 0)
		assert(H.payGame(s, 2, 50) == 50, "a new day")
		assert(H.payGame(s, 2, -5) == 0)
	end)

	test("hangout: whack prize is per hit and capped", function()
		assert(H.whackPrize(0) == 0 and H.whackPrize(3) == 3 * H.Games.Whack.CoinsPerHit)
		assert(H.whackPrize(10000) == H.Games.Whack.MaxCoins)
	end)

	test("hangout: the pet race and the egg toss are gone (owner picks 2026-10-14)", function()
		assert(H.Games.Race == nil and H.raceOrder == nil and H.tapOk == nil and H.racePrize == nil)
		assert(H.animKind("RaceStart") == nil, "no race start glow")
		assert(H.Games.Toss == nil and H.tossHit == nil and H.tossOffset == nil)
		assert(H.animKind("Target") == nil, "no toss target glow")
	end)

	test("hangout: one event per UTC hour, rotating, the same in every server", function()
		local I = H.Events.Interval
		assert(H.nextEventTime(I * 5 + 10) == I * 6)
		local seen = {}
		for slot = 0, #H.Events.Order - 1 do
			seen[H.eventAt(slot * I + 1)] = true
		end
		for _, k in H.Events.Order do
			assert(seen[k], k .. " is in the rotation")
			assert(H.Events.Names[k], k .. " has a name")
		end
		assert(H.eventAt(I * 7) == H.eventAt(I * 7 + I - 1), "the whole hour is one event")
		assert(H.rockHits(0) == H.Events.GoldenRock.MinHits and H.rockHits(10) == 10 * H.Events.GoldenRock.HitsPerPlayer)
		assert(H.rainRoom(0) == H.Events.CoinRain.PlayerCap and H.rainRoom(1e6) == 0)
	end)

	test("hangout: hidden eggs pay once each, the lookout once a day", function()
		local s = H.empty()
		assert(H.secretIndex("HiddenEgg3") == 3 and H.secretIndex("HiddenEggX") == nil and H.secretIndex("SecretEgg") == nil)
		assert(H.claimSecret(s, "HiddenEgg1") and not H.claimSecret(s, "HiddenEgg1"))
		assert(not H.claimSecret(s, "Rock"), "only hidden egg names")
		assert(H.claimSecret(s, "HiddenEgg2") and H.secretsFound(s) == 2)
		assert(H.claimLookout(s, 9) and not H.claimLookout(s, 9) and H.claimLookout(s, 10))
	end)

	test("hangout: sit spot names", function()
		assert(H.isSitName("Bench3") and H.isSitName("SitSpot") and H.isSitName("DockSeat1") and H.isSitName("Swing"))
		assert(not H.isSitName("Tree") and not H.isSitName("Campfire"))
	end)

	test("hangout: the group bonus is off until the owner sets the group id", function()
		local old = R.Group.Id
		R.Group.Id = 0
		assert(not H.groupOn() and H.groupLuck(true) == 0 and not H.inGroup({ { Id = 0 } }))
		R.Group.Id = 4242
		assert(H.groupOn() and H.groupLuck(true) == H.Group.Luck and H.groupLuck(false) == 0)
		assert(H.inGroup({ { Id = 1 }, { Id = 4242, Name = "x" } }) and not H.inGroup({ { Id = 1 } }) and not H.inGroup("bad"))
		R.Group.Id = old
	end)

	test("hangout: beam only for Epic and Legendary", function()
		assert(H.beamFor("Legendary") and H.beamFor("Epic") and not H.beamFor("Rare") and not H.beamFor(nil))
	end)

	test("hangout anim: every hangout piece has a look, near pieces only, half range with Low Effects", function()
		for name, kind in {
			GoldenRock = "GoldenRock", MysteryEgg = "MysteryEgg", WhackRock = "WhackRock", RainCoin = "RainCoin",
			HiddenEgg4 = "HiddenEgg", LookoutChest = "Lookout", CampfireLight = "Campfire", CT_TopPlotGlow = "TopPlot",
			CT_Park_PlotCrown = "Crown", SkyBeam = "Beam", WhackStump = "Stump",
		} do
			assert(H.animKind(name) == kind, name)
		end
		assert(H.animKind("Tree") == nil and H.animKind("HiddenEggX") == nil)
		local n = H.Anim.Near
		assert(H.animNear(n, false) and not H.animNear(n + 1, false))
		assert(H.animNear(n / 2, true) and not H.animNear(n / 2 + 1, true))
		for _, t in { 0, 0.3, 1.7, 99 } do
			local v = H.pulse(t, 0.8, 0.2)
			assert(v >= 0 and v <= 1)
		end
	end)

	test("pet zzz bubble: half the old 52 x 30 size and never fully solid", function()
		local Z = shared("Config").PetZzz
		assert(Z.Width <= 26 and Z.Height <= 16, "half size")
		assert(Z.TextSize <= 12 and Z.TextSize >= 12, "small but readable (text floor 12)")
		assert(Z.Faint >= 0.4 and Z.Faint < 1, "fainter")
	end)
end
