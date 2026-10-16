-- Egg gravity on the hunt pile (carter 2026-10-16): shared/EggFall.
return function(t)
	local test, shared = t.test, t.shared
	local EggFall = shared("EggFall")
	local Config = shared("Config")
	local Vector3 = t.Vector3

	local function close(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude < 1e-3
	end

	test("egg fall: a settle drops straight down, speeds up, lands exactly and bounces once", function()
		local from, to = Vector3.new(1, 3, 2), Vector3.new(1, 1.6, 2)
		local p = EggFall.plan(from, to, Config.Match.EggGravity, 0.3, 1.1, 5)
		assert(p.Vy0 == 0, "a plain drop never jumps up first")
		assert(close(EggFall.at(p, 0), from) and close(EggFall.at(p, p.Dur), to))
		assert(close(EggFall.at(p, p.Flight), to), "touches down at the end of the flight")
		-- gravity, not ease-out: the second half of the flight falls further than the first half (it speeds up)
		local mid = EggFall.at(p, p.Flight / 2)
		assert(from.Y - mid.Y < mid.Y - to.Y, "it accelerates as it falls")
		-- never goes below its spot, one bounce no higher than the cap
		local top = 0
		for i = 0, 100 do
			local y = EggFall.at(p, p.Dur * i / 100).Y
			assert(y >= to.Y - 1e-6, "never sinks into the egg below")
			if i / 100 * p.Dur > p.Flight then
				top = math.max(top, y - to.Y)
			end
		end
		assert(top > 0 and top <= 0.3 + 1e-6, "one small bounce")
		assert(p.Dur < 0.6, "snappy: a one-layer settle is done fast")
	end)

	test("egg fall: a sideways or upward move hops over the pile in an arc", function()
		local from, to = Vector3.new(0, 2, 0), Vector3.new(9, 0.7, 0)
		local p = EggFall.plan(from, to, Config.Match.EggGravity, 0.3, 1.1, 5)
		assert(p.Vy0 > 0, "it jumps up first")
		local peak = 0
		for i = 0, 100 do
			peak = math.max(peak, EggFall.at(p, p.Flight * i / 100).Y)
		end
		assert(peak >= from.Y + 2.9, "clears the mound (a third of the 9-stud hop)")
		assert(close(EggFall.at(p, p.Dur), to))
		local up = EggFall.plan(Vector3.new(0, 0.7, 0), Vector3.new(0, 0.7, 0) + Vector3.new(0, 1, 0), 90, 0.3)
		assert(up.Vy0 > 0 and close(EggFall.at(up, up.Dur), Vector3.new(0, 1.7, 0)), "a rise arcs up and lands")
		local still = EggFall.plan(Vector3.new(0, 1, 0), Vector3.new(0, 1, 0), 90, 0.3)
		assert(still.Dur > 0 and close(EggFall.at(still, still.Dur), Vector3.new(0, 1, 0)), "no move is safe")
		assert(EggFall.turn(p, 0) == 0 and EggFall.turn(p, p.Dur) == 1)
	end)

	test("egg fall: wired into the pile view for settles, returns and the overtime move", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/client/PileView.luau")
		assert(string.find(src, "EggFall.plan", 1, true), "PileView uses EggFall")
		assert(not string.find(src, "Anim.easeOut(math.min(1, t / 0.6))", 1, true), "the floaty ease-out settle is gone")
		assert(not string.find(src, "3 * (1 - Anim.easeOut(k))", 1, true), "the floaty return pop is gone")
	end)

	test("egg fall: the gold overtime egg hops in an arc from deep in the pile to its edge spot", function()
		local RoundRocks = shared("RoundRocks")
		local hops = 0
		for seed = 1, 30 do
			local core = RoundRocks.new({ Tier = "Gravel", Seed = seed, TargetRng = t.Random.new(seed), Members = { { UserId = 1, Station = 1, Tool = "Hammer" } } } :: any)
			local id = core.TargetId
			local from = core.Pile:localPosition(id)
			if core:surface(id) then
				hops += 1
				local to = core.Pile:localPosition(id)
				local s = core.Pile.RockSize
				-- the same numbers PileView.fall uses
				local p = EggFall.plan(from, to, Config.Match.EggGravity, s * 0.12, s * 0.5, s * 2.5)
				assert(close(EggFall.at(p, p.Dur), to), "lands on its new spot")
				local horiz = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
				if horiz > s * 0.5 then
					assert(p.Vy0 > 0, "jumps up out of the pile (seed " .. seed .. ")")
					local peak = -math.huge
					for k = 0, 50 do
						peak = math.max(peak, EggFall.at(p, p.Flight * k / 50).Y)
					end
					assert(peak > math.max(from.Y, to.Y), "arcs over, never slides through the eggs")
				end
				assert(p.Dur < 1.5, "a quick hop")
			end
		end
		assert(hops > 0, "some seeds bury the gold egg")
		local src = require("@lune/fs").readFile("src/client/PileView.luau")
		local mv = string.find(src, 'e.Kind == "Move"', 1, true)
		assert(mv and string.find(src, "touched[e.Col] = true", mv, true), "the Move event re-renders the new column (which falls via EggFall)")
	end)

	test("pet names: battle and tower cards show the Pet Book name (Skeleton / Golden, nickname)", function()
		local PetRules = shared("PetRules")
		local g = { Id = "x", Mineral = "Mosswhip", Rarity = "Rare", Modifier = "Skeleton", Seed = 1 }
		local name = PetRules.label(g)
		assert(string.find(name, "Skeleton", 1, true) and string.find(name, "Mosswhip", 1, true), name)
		local fs = require("@lune/fs")
		for _, f in { "src/server/PvpService.luau", "src/server/TowerService.luau" } do
			assert(not string.find(fs.readFile(f), "TowerConfig.PetNames[g.Mineral]", 1, true), f .. " uses the base species name")
		end
		-- long names stay on one line (shrunk to fit) on the BATTLE card and the Pet Book tile; the level moved to the
		-- power line (Studio 844x390: "Skeleton Thunderstrut  Lv 1" showed only "Skeleton")
		local ui = fs.readFile("src/client/ui/UI.luau")
		assert(string.find(ui, "UI.oneLine(cap)", 1, true), "tile caption is one line")
		local pvp = fs.readFile("src/client/ui/PvpPanel.luau")
		assert(string.find(pvp, "local nameH = ", 1, true) and not string.find(pvp, 'p.Name .. "  Lv " .. p.Level', 1, true), "battle card name alone, two lines")
		assert(string.find(pvp, "UI.oneLine(UI.text(row, \"\", { Name = \"Level\"", 1, true), "train row name + level shrink on one line")
		local UiMotion = shared("UiMotion")
		assert(UiMotion.twoLineName("Golden Razorclaw") and UiMotion.twoLineName("Skeleton Thunderstrut"))
		assert(not UiMotion.twoLineName("Shadowfang") and not UiMotion.twoLineName("Unicorn") and not UiMotion.twoLineName("Inferno Rex"))
		-- Pet Book tiles: one shrinking line, never "..." (two lines cut "Golder / Puffquill" and crowded the tags)
		local col = fs.readFile("src/client/ui/CollectionPanel.luau")
		assert(string.find(col, "UI.oneLine(cap)", 1, true) and not string.find(col, "twoLineName", 1, true))
		assert(not string.find(ui, "cap.TextTruncate = Enum.TextTruncate.AtEnd", 1, true), "specimen card caption never truncates")
		assert(string.find(col, "UI.oneLine(name) -- below the text floor too", 1, true), "Pet Book detail name shrinks past the floor")
		-- the level pill never sits under the info dot: the dot hides when the pill reaches it
		assert(UiMotion.clearOf(100, 104, 2) and not UiMotion.clearOf(103, 104, 2) and not UiMotion.clearOf(120, 104, 2))
		assert(string.find(col, "hint.Visible = UiMotion.clearOf(lvChip.AbsolutePosition.X + lvChip.AbsoluteSize.X, hint.AbsolutePosition.X, 2)", 1, true))
		-- Training Tower rows: the Pet Book name
		assert(string.find(fs.readFile("src/server/TowerService.luau"), "Name = PetRules.label(g), -- the Pet Book name", 1, true))
		-- cards ask the server again when the cached roster is old (TRAIN kept Lv 1 after /maxpet)
		assert(string.find(pvp, "if stale() then", 1, true) and string.find(pvp, "rosterAt = os.clock()", 1, true))
	end)
end
