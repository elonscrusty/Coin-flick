return function(t)
	local test, shared = t.test, t.shared
	local Boards = shared("Boards")
	local Cosmetics = shared("Cosmetics")
	local Config = shared("Config")

	test("boards: values come from the right profile numbers, Solo stays separate", function()
		local v = Boards.values({
			Stats = { MultiplayerWins = 7, SoloFinds = 3, BestGeodeValue = 1234 },
			DiscoveryIndex = { Quartz = 4, Amethyst = 2 },
		})
		assert(v.Wins == 7 and v.Solo == 3 and v.Biggest == 1234 and v.Collection == 6)
		assert(Boards.Info.Solo.Sub ~= Boards.Info.Wins.Sub)
		local bad = Boards.values({ Stats = { MultiplayerWins = -5, SoloFinds = 0 / 0 } })
		assert(bad.Wins == 0 and bad.Solo == 0 and bad.Collection == 0 and bad.Tower == 0)
		assert(Boards.values({ TowerBest = 12 }).Tower == 12)
		assert(#Boards.Order == 4 and Boards.Order[1] == "Biggest" and Boards.Order[2] == "Tower" and Boards.Order[3] == "Coins" and Boards.Order[4] == "Power", "RAREST PET, HIGHEST FLOOR, MOST COINS, STRONGEST PET (tree)")
		assert(Boards.values({ Stats = { CashEarned = 4321 } }).Coins == 4321, "MOST COINS = coins earned ever")
	end)

	test("boards: write is due only for a larger value after the throttle", function()
		assert(Boards.writeDue(nil, 1, nil, 100, 60))
		assert(not Boards.writeDue(nil, 0, nil, 100, 60))
		assert(not Boards.writeDue(5, 5, nil, 100, 60), "no change, no write")
		assert(not Boards.writeDue(5, 4, nil, 100, 60), "boards never go down")
		assert(not Boards.writeDue(5, 6, 80, 100, 60), "throttled")
		assert(Boards.writeDue(5, 6, 30, 100, 60))
	end)

	test("boards: ranking sorts, drops junk, breaks ties by user id and keeps the top", function()
		local raw = {
			{ key = "30", value = 5 },
			{ key = "10", value = 9 },
			{ key = "20", value = 9 },
			{ key = "abc", value = 99 },
			{ key = "40", value = 0 },
			{ key = "10", value = 100 },
		}
		local rows = Boards.rank(raw, 3)
		assert(#rows == 3)
		assert(rows[1].UserId == 10 and rows[1].Rank == 1)
		assert(rows[2].UserId == 20 and rows[3].UserId == 30)
		assert(Boards.format("Biggest", 1234567) == "1,234,567") -- rarest-pet score, not money
		assert(Boards.format("Wins", 12) == "12")
	end)

	test("cosmetics: with every product id at 0 nothing is visible", function()
		assert(not Cosmetics.anyVisible(), "store tab hidden when every id is 0")
		for _, id in Config.CosmeticOrder do
			local e = Config.Products[id]
			assert(e and e.ProductId == 0, id .. " must ship with product id 0")
			assert(e.Kind == "ToolSkin" or e.Kind == "GalleryTheme", id .. " kind")
			assert(not Cosmetics.visible(e))
			assert(e.Price == nil, id .. " has no invented price")
		end
	end)

	test("cosmetics: equipped needs ownership and a visible entry; receipts are bounded", function()
		local e = Config.Products.SkinCopper
		local state = Cosmetics.empty()
		state.Equipped.ToolSkin = "SkinCopper"
		assert(Cosmetics.equipped(state, "ToolSkin") == nil, "not owned")
		state.Owned.SkinCopper = true
		assert(Cosmetics.equipped(state, "ToolSkin") == nil, "hidden while id is 0")
		e.ProductId = 77
		assert(Cosmetics.equipped(state, "ToolSkin") == e)
		assert(Cosmetics.byProductId(77) == e)
		assert(Cosmetics.equipped(state, "GalleryTheme") == nil)
		e.ProductId = 0
		for i = 1, 10 do
			Cosmetics.rememberReceipt(state, "p" .. i, 4)
		end
		assert(#state.ReceiptOrder == 4 and state.Receipts.p10 and not state.Receipts.p1)
		Cosmetics.rememberReceipt(state, "p10", 4)
		assert(#state.ReceiptOrder == 4, "same receipt twice is one entry")
	end)

	test("cosmetics: products carry no power fields", function()
		for _, id in Config.CosmeticOrder do
			local e = Config.Products[id]
			for k in e do
				assert(k ~= "Damage" and k ~= "Rate" and k ~= "Luck" and k ~= "Cash" and k ~= "Mult", id .. " has power field " .. k)
			end
		end
	end)
end
