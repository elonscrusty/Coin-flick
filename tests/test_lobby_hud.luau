-- Lobby HUD v2 layout (shared/LobbyHudLayout): every piece on screen, nothing overlaps, the jump corner stays clear,
-- PLAY is the biggest, touch targets big enough, on the phones and screens we preview.
return function(t)
	local test, shared = t.test, t.shared
	local L = shared("LobbyHudLayout")
	local SafeZones = shared("SafeZones")

	-- same rule as UI.scaleFor (client): design canvas 800 x 400
	local function scaleFor(w: number, h: number): number
		if h > w then
			return math.clamp(w / 390, 0.8, 1.3)
		end
		local s = math.min(w / 800, h / 400)
		if s <= 1.3 then
			return math.max(s, 0.8)
		end
		return math.max(1.3, math.min(s, h / 600))
	end
	-- real screen, side notch insets, top bar inset, touch
	local SCREENS = {
		{ "phone 844x390", 844, 390, 47, 36, true },
		{ "phone-small 667x375", 667, 375, 0, 36, true },
		{ "phone-1108 1108x512", 1108, 512, 0, 36, true },
		{ "iphone 852x393", 852, 393, 59, 36, true },
		{ "laptop 1366x768", 1366, 768, 0, 36, false },
		{ "pc 1920x1080", 1920, 1080, 0, 36, false },
		{ "tablet 1024x768", 1024, 768, 0, 36, true },
		{ "phone-portrait 390x844", 390, 844, 0, 94, true },
	}

	local function checkAll()
		for _, sc in SCREENS do
			local name, W, H, notch, top, touch = sc[1], sc[2], sc[3], sc[4], sc[5], sc[6]
			local rw, rh = W - 2 * notch, H - top
			local k = scaleFor(rw, rh)
			local w, h = rw / k, rh / k
			local lay = L.layout(w, h, k, touch)
			local names = L.names()
			for _, n in names do
				local r = lay[n]
				assert(r, name .. ": " .. n .. " placed")
				assert(r.x >= 0 and r.y >= 0 and r.x + r.w <= w + 1e-6 and r.y + r.h <= h + 1e-6, name .. ": " .. n .. " on screen")
			end
			for i = 1, #names do
				for j = i + 1, #names do
					assert(not SafeZones.overlaps(lay[names[i]], lay[names[j]]), name .. ": " .. names[i] .. " overlaps " .. names[j])
				end
			end
			if touch then
				local jz = SafeZones.jumpZone(w, h, k)
				for _, n in names do
					assert(not SafeZones.overlaps(lay[n], jz), name .. ": " .. n .. " under the jump button")
				end
			end
			local play = lay.Play
			for _, n in names do
				if n ~= "Play" and n ~= "Title" and n ~= "Status" then
					assert(play.w * play.h > lay[n].w * lay[n].h, name .. ": PLAY bigger than " .. n)
				end
			end
			for _, n in { "MyPets", "PetBook", "Daily", "Spin", "Shop", "Train", "Fight" } do
				assert(math.min(lay[n].w, lay[n].h) * k >= 48, name .. ": " .. n .. " at least 48 real px")
			end
			-- the world centre stays open: no piece covers the middle of the screen
			local mid = if h > w then { x = w * 0.3, y = h * 0.3, w = w * 0.4, h = h * 0.3 } else { x = w * 0.35, y = h * 0.3, w = w * 0.3, h = h * 0.35 }
			for _, n in names do
				assert(not SafeZones.overlaps(lay[n], mid), name .. ": " .. n .. " covers the world centre")
			end
		end
	end

	test("lobby hud v2: on screen, no overlaps, jump corner clear, PLAY biggest, touch size on every screen", checkAll)

	test("lobby hud v2: the same holds with carter's low-poly button pictures (their own shapes)", function()
		local Art = shared("LobbyHudArt")
		local saved = {}
		for n, a in Art.LowPoly do
			saved[n] = a.Id
			a.Id = 1
		end
		local ok, err = pcall(checkAll)
		for n, a in Art.LowPoly do
			a.Id = saved[n]
		end
		for n in Art.Buttons do
			assert(Art.get(n) == Art.LowPoly[n] and Art.LowPoly[n].Id > 1, n .. ": the low-poly picture is uploaded and shown")
		end
		assert(ok, err)
	end)
end
