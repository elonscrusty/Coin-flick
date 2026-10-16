-- Phone speed budget (run by tests/test_m10_server.luau): what the server builds for the lobby, one hunt arena and one
-- fight island on the offline mock, and that nothing piles up round after round. NOT device numbers: this is the
-- code-built world (the procedural lobby stands in for the owner's hand-built map, which only Studio can count).
-- Budgets sit about 25-35% above the 2026-10-15 counts (lobby 2211 parts, hunt arena 1629, island stand-in 39):
-- a change that blows one is a real jump, look at it before raising the number (docs/PERF.md).
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local function case(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		print("CASE " .. name .. " PASS")
	else
		print("[FAIL] CASE " .. name .. ": " .. tostring(err))
	end
end

local BUDGET = { LobbyParts = 3000, LobbyLights = 64, ArenaParts = 2200, ArenaLights = 16, IslandParts = 120 }

local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
preview.advance(2)

local function count(root: Instance)
	local out = { Parts = 0, Loose = 0, Lights = 0, LooseNames = {} }
	local chars = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			out.Parts += 1
			if not d.Anchored then
				local inChar = false
				for _, ch in chars do
					if d:IsDescendantOf(ch) then
						inChar = true
						break
					end
				end
				if not inChar then
					out.Loose += 1
					if #out.LooseNames < 5 then
						table.insert(out.LooseNames, d:GetFullName())
					end
				end
			end
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			out.Lights += 1
		end
	end
	return out
end
local function arenaRoot(slot: number?): Instance?
	for _, ch in Workspace:GetChildren() do
		if string.find(ch.Name, "Arena_" .. (if slot then tostring(slot) else ""), 1, true) then
			return ch
		end
	end
	return nil
end

local lobby = count(Workspace)
print(("   lobby: %d parts, %d lights"):format(lobby.Parts, lobby.Lights))

case("lobby: parts and lights within budget, no loose (unanchored) parts", function()
	assert(lobby.Parts <= BUDGET.LobbyParts, ("lobby has %d parts (budget %d)"):format(lobby.Parts, BUDGET.LobbyParts))
	assert(lobby.Lights <= BUDGET.LobbyLights, ("lobby has %d lights (budget %d)"):format(lobby.Lights, BUDGET.LobbyLights))
	assert(lobby.Loose == 0, "loose parts: " .. table.concat(lobby.LooseNames, ", "))
end)

local w = C.watchMatch()
local samples = {}
for round = 1, 3 do
	w.last.Found = nil
	w.last.Init = nil
	C.startSolo(w)
	C.waitPhase(w, "Searching", 10)
	preview.advance(1)
	local a = arenaRoot()
	local ac = if a then count(a) else nil
	local all = count(Workspace)
	if round == 1 then
		print(("   hunt arena: %s parts, %s lights"):format(tostring(ac and ac.Parts), tostring(ac and ac.Lights)))
		case("hunt arena: parts and lights within budget, no loose parts", function()
			assert(ac, "no hunt arena model in Workspace")
			assert(ac.Parts <= BUDGET.ArenaParts, ("arena has %d parts (budget %d)"):format(ac.Parts, BUDGET.ArenaParts))
			assert(ac.Lights <= BUDGET.ArenaLights, ("arena has %d lights (budget %d)"):format(ac.Lights, BUDGET.ArenaLights))
			assert(all.Loose == 0, "loose parts: " .. table.concat(all.LooseNames, ", "))
		end)
	end
	C.crackUntilFound(w, { s.me }, 120)
	preview.advance(8)
	C.fireServer("MatchAction", "Return")
	preview.advance(10)
	local live = preview.liveCounts()
	table.insert(samples, { Parts = count(Workspace).Parts, Conns = live.connections, Waiting = live.waiting })
end

case("three hunts in a row reuse one arena and nothing grows (parts, connections, threads)", function()
	local a, b = samples[1], samples[#samples]
	assert(arenaRoot(2) == nil, "a second arena was built for hunts one after another")
	assert(b.Parts <= a.Parts, ("parts grew %d -> %d"):format(a.Parts, b.Parts))
	assert(b.Conns <= a.Conns, ("connections grew %d -> %d"):format(a.Conns, b.Conns))
	assert(b.Waiting <= a.Waiting + 1, ("waiting threads grew %d -> %d"):format(a.Waiting, b.Waiting))
end)

case("two hunts at once: the extra arena is taken down once it stands empty, the first stays warm", function()
	local M = s.Config.Match
	assert(M.ArenaKeepWarm == 1, "slot 1 is the warm arena")
	local ava = s.others[1]
	C.startSolo(w) -- me: slot 1 (the warm arena)
	C.waitPhase(w, "Searching", 10)
	preview.fireServerAs(ava, "PartyAction", "Solo")
	preview.advance(3)
	assert(arenaRoot(1) and arenaRoot(2), "two arenas while two hunts run")
	preview.fireServerAs(ava, "MatchAction", "Return")
	C.fireServer("MatchAction", "Return")
	preview.advance(3)
	assert(arenaRoot(2), "the extra arena stays a while (a quick rematch reuses it)")
	preview.advance(M.ArenaIdleSeconds + 5)
	assert(arenaRoot(2) == nil, "the extra arena is still in every client's world after standing empty")
	assert(arenaRoot(1), "the warm arena stays")
	-- the slot works again: a new hunt there rebuilds it
	C.startSolo(w)
	C.waitPhase(w, "Searching", 10)
	preview.fireServerAs(ava, "PartyAction", "Solo")
	preview.advance(3)
	assert(arenaRoot(2), "slot 2 is rebuilt for the next busy spell")
	preview.fireServerAs(ava, "MatchAction", "Return")
	C.fireServer("MatchAction", "Return")
	preview.advance(3)
end)

case("fight island: within budget, anchored, gone when the fight ends", function()
	local SkyIsland = C.server("SkyIsland")
	local before = count(Workspace).Parts
	local isl = SkyIsland.claim()
	local ic = count(isl.Model)
	print(("   fight island (%s): %d parts, %d lights"):format(tostring(isl.Model:GetAttribute("IslandSource")), ic.Parts, ic.Lights))
	assert(ic.Parts <= BUDGET.IslandParts, ("island has %d parts (budget %d)"):format(ic.Parts, BUDGET.IslandParts))
	assert(ic.Loose == 0, "loose island parts: " .. table.concat(ic.LooseNames, ", "))
	SkyIsland.free(isl.Slot, isl.Model)
	preview.advance(0.5)
	assert(SkyIsland.count() == 0, "island slot still in use")
	assert(count(Workspace).Parts == before, "island parts left behind")
end)

print("BUDGET DONE")
