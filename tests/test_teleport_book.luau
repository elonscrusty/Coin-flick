-- Teleport bookkeeping (shared/TeleportBook, used by server/LobbyLaunch and server/MatchPlace).
return function(t)
	local test, shared = t.test, t.shared
	local TB = shared("TeleportBook")

	test("teleport book: dissolve clears every entry of the launch, not only the current roster", function()
		local launchOf = { [1] = "p7", [2] = "p7", [3] = "p8", [4] = "p7" } -- 4 left the party mid-prepare
		local n = TB.dissolve(launchOf, "p7")
		assert(n == 3, "three entries: " .. n)
		assert(launchOf[1] == nil and launchOf[2] == nil and launchOf[4] == nil, "all of party 7 gone")
		assert(launchOf[3] == "p8", "another party's entry stays")
		assert(TB.dissolve(launchOf, "p7") == 0, "second dissolve is a no-op")
	end)

	test("teleport book: a member who left during Saving is not teleported", function()
		local here = { [1] = true, [2] = true, [3] = true }
		local ok, why = TB.stillHere({ 1, 2, 3 }, { 1, 2, 3 }, function(u) return here[u] == true end)
		assert(ok and why == nil, "everyone present")
		here[2] = nil -- left the server while the save yielded
		ok, why = TB.stillHere({ 1, 2, 3 }, { 1, 2, 3 }, function(u) return here[u] == true end)
		assert(not ok and why == "A party member left.", "left the server")
		here[2] = true
		ok = TB.stillHere({ 1, 3 }, { 1, 2, 3 }, function(u) return here[u] == true end) -- left the party
		assert(not ok, "left the party")
	end)

	test("teleport book: a second Return for a player already returning is skipped", function()
		local returning: { [number]: number } = {}
		local first = TB.takeReturns(returning, { 10, 11 }, 1, false)
		assert(#first == 2 and returning[10] == 1 and returning[11] == 1)
		local second = TB.takeReturns(returning, { 10, 12 }, 2, false)
		assert(#second == 1 and second[1] == 12, "10 skipped, 12 taken")
		assert(returning[10] == 1, "the first return keeps its token")
		assert(TB.stillOwns(returning, 10, 1) and not TB.stillOwns(returning, 10, 2))
		local retry = TB.takeReturns(returning, { 10 }, 3, true) -- the caller's own retry goes through
		assert(#retry == 1 and returning[10] == 3)
		assert(not TB.stillOwns(returning, 10, 1), "the old watchdog no longer owns it")
		returning[10] = nil
		assert(not TB.stillOwns(returning, 10, 3), "cleared on arrival")
	end)
end
