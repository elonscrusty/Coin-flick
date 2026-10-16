-- One popup gate (shared/PopupRules, client/PopupGate): no non-fight card or toast over a Pet Battle or tower climb
-- (Studio 2026-10-14: the NEXT GOAL card and toasts popped mid-fight); big cards also wait through a hunt.
return function(t)
	local test, shared = t.test, t.shared
	local PopupRules = shared("PopupRules")
	local Retention = shared("Retention")

	local function eq(a, b, msg)
		if a ~= b then
			error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	test("popups: free in the lobby, held in a fight, the tower and while a fight view holds them", function()
		for _, kind in { "Toast", "Card" } do
			eq(PopupRules.free(kind, {}), true, kind .. " lobby")
			eq(PopupRules.free(kind, { InBattle = true }), false, kind .. " battle")
			eq(PopupRules.free(kind, { InTower = true }), false, kind .. " tower")
			eq(PopupRules.free(kind, { Held = true }), false, kind .. " fight view still open (result / hero shot)")
		end
	end)

	test("popups: a hunt keeps its toasts but holds big cards", function()
		eq(PopupRules.free("Toast", { MatchKey = "m1" }), true)
		eq(PopupRules.free("Card", { MatchKey = "m1" }), false)
		eq(PopupRules.free("Card", { Match = {} }), false)
	end)

	test("popups: Retention.calm is the same Card rule (one rule for every popup)", function()
		for _, s in { {}, { InBattle = true }, { InTower = true }, { MatchKey = "x" }, { Match = {} }, { Held = true } } do
			eq(Retention.calm(s), PopupRules.free("Card", s))
		end
	end)

	-- Studio 2026-10-15: the NEXT GOAL card stayed mid-screen into the hunt; the avatar stood in front of the pets in the
	-- tower fight; "Tap PET BOOK!" showed before the starter egg hatched.
	test("popups: a self-opened card closes after CardLife or as soon as a hunt / climb / battle starts", function()
		eq(PopupRules.cardStays(0, {}), true, "just shown in the lobby")
		eq(PopupRules.cardStays(PopupRules.CardLife, {}), false, "timed out")
		for _, s in { { MatchKey = "m1" }, { Match = {} }, { InTower = true }, { InBattle = true }, { Held = true } } do
			eq(PopupRules.cardStays(1, s), false, "busy closes it")
		end
		local fs = require("@lune/fs")
		local rv = fs.readFile("src/client/RetentionView.luau")
		local goal = string.match(rv, "function RetentionView%.goalCard.-\nend\n")
		assert(goal and string.find(goal, "PopupGate.cardStays", 1, true), "the NEXT GOAL card watches PopupGate.cardStays")
		assert(string.find(goal, "UI.closeButton", 1, true), "the NEXT GOAL card has its own close button")
	end)

	test("fight views: own avatar hidden in a Pet Battle AND a tower climb, shown elsewhere", function()
		eq(PopupRules.hideSelf(true, false), true)
		eq(PopupRules.hideSelf(false, true), true, "tower climb")
		eq(PopupRules.hideSelf(false, false), false)
		local fs = require("@lune/fs")
		local main = fs.readFile("src/client/Main.client.luau")
		assert(string.find(main, "require(script.Parent.SelfHide).start()", 1, true), "Main starts SelfHide")
		local sh = fs.readFile("src/client/SelfHide.luau")
		assert(string.find(sh, "PopupRules.hideSelf(", 1, true) and string.find(sh, "BindToRenderStep", 1, true), "SelfHide follows the rule every frame")
	end)

	test("lobby hints wait until the starter egg has hatched", function()
		local fs = require("@lune/fs")
		local main = fs.readFile("src/client/Main.client.luau")
		local gate = string.find(main, "if prof.StarterEgg == true and not m then", 1, true)
		local book = string.find(main, '"Tap PET BOOK! Then tap PLACE ON DISPLAY!"', 1, true)
		assert(gate and book and gate < book, "the starter egg gate comes before the PET BOOK hint")
	end)

	test("popups: big cards come one at a time (NEXT GOAL never stacks on WHAT'S NEW)", function()
		assert(PopupRules.free("Card", {}) == true, "calm lobby: a card may show")
		assert(PopupRules.free("Card", { Shown = true }) == false, "a menu or card on screen: the next card waits")
		assert(PopupRules.free("Toast", { Shown = true }) == true, "toasts are not held by a menu")
		assert(PopupRules.cardStays(1, { Shown = true }) == true, "a card on screen never closes itself for being on screen")
		assert(PopupRules.cardStays(1, { Shown = true, MatchKey = "m" }) == false, "a hunt still closes it")
		assert(table.find(PopupRules.Cards, "NextGoal") and table.find(PopupRules.Cards, "AwayNest"), "both cards count")
		local fs = require("@lune/fs")
		local news = fs.readFile("src/client/ui/NewsPopup.luau")
		assert(string.find(news, 'PopupGate.later("Card"', 1, true), "WHAT'S NEW waits its turn through the popup gate")
		local goal = fs.readFile("src/client/RetentionView.luau")
		assert(string.find(goal, 'PopupGate.later("Card"', 1, true), "NEXT GOAL waits its turn through the popup gate")
		local ui = fs.readFile("src/client/ui/UI.luau")
		assert(string.find(ui, "PopupGate.onScreen = function", 1, true), "UI tells the gate what is on screen")
	end)

	test("popups: toasts wait while the spin wheel is up; NEXT GOAL never sits over the lobby HUD", function()
		local fs = require("@lune/fs")
		local spin = fs.readFile("src/client/ui/SpinPanel.luau")
		local on = string.find(spin, 'PopupGate.hold("SpinPanel", true)', 1, true)
		local off = string.find(spin, 'PopupGate.hold("SpinPanel", false)', 1, true)
		assert(on and off, "the spin panel holds toasts while open and lets them go on close")
		local hud = fs.readFile("src/client/ui/LobbyHudV2.luau")
		assert(string.find(hud, "not UI.blocked() and not bigCard()", 1, true), "the lobby HUD steps aside for a big card")
		assert(string.find(hud, "PopupRules.Cards", 1, true), "the same card list as the popup gate")
	end)
end
