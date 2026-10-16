-- materials: Material Discoveries through the REAL server (docs/m6/DISCOVERIES.md). A solo hunt is played with the
-- V3 loop (pickup, deposit, crush); then the profile, the replicated messages and the sale are checked:
--   * every finished ordinary crush is counted once for its owner (counts add up to RocksCracked and to the rubble),
--   * a first-time category is announced exactly once ("MaterialFound"), repeats are silent,
--   * no cash, rubble or capacity change comes from a category (cash only changes through the sale),
--   * recording the same rock key twice changes nothing (idempotent),
--   * the public profile view carries the found set and the rubble value; one sale pays once, a double tap pays nothing.
-- Prints "MATERIALS PASS" / "MATERIALS FAIL: ..." (run by tools/run_regressions.sh).
local C = lib("ctr")
local START_CASH = 123
local s = C.boot({
	profile = function(data)
		data.Cash = START_CASH
		data.TutorialStep = 1
		data.CapacityTier = 2 -- 100 rubble: room for the whole test
		data.Onboard.Skipped = true
	end,
})
local Profiles = s.Profiles
local Economy = C.server("EconomyService")
local Config = s.Config
local fails = {}
local function check(name: string, ok: boolean, detail: string?)
	if not ok then
		table.insert(fails, name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

local data0 = Profiles.get(s.me)
check("fresh profile has an empty Materials table", type(data0.Materials) == "table" and next(data0.Materials.Found) == nil and next(data0.Materials.Counts) == nil)

local w = C.watchMatch()
local announced: { [string]: number } = {}
local ev = game:GetService("ReplicatedStorage").Remotes.MatchEvent
ev.OnClientEvent:Connect(function(kind, data)
	if kind == "MaterialFound" then
		for _, id in ipairs(data.New or {}) do
			announced[id] = (announced[id] or 0) + 1
		end
	end
end)
C.startSolo(w)
C.waitPhase(w, "Searching", 6)
C.crackUntilFound(w, { s.me }, 900, { stopAfterDone = 30 })
preview.advance(1)

local d = Profiles.get(s.me)
local cracked = d.Stats.RocksCracked
local sum, kinds = 0, 0
for id, n in pairs(d.Materials.Counts) do
	sum += n
	kinds += 1
	check("count belongs to a configured category " .. id, Config.Materials[id] ~= nil)
	check("a counted category is in the found set " .. id, d.Materials.Found[id] == true)
end
preview.log(string.format("cracked %d, counted %d, categories %d", cracked, sum, kinds))
check("at least ten rocks were cracked", cracked >= 10, tostring(cracked))
check("counts add up to cracked rocks", sum == cracked, sum .. " vs " .. cracked)
check("rubble equals cracked rocks (no extra output)", Profiles.rubbleTotal(d) == cracked, Profiles.rubbleTotal(d) .. " vs " .. cracked)
check("cash untouched by cracking", d.Cash == START_CASH, tostring(d.Cash))
check("capacity untouched", d.CapacityTier == 2)
for id, n in pairs(announced) do
	check("announced once per category " .. id, n == 1, tostring(n))
	check("announced category is in the found set " .. id, d.Materials.Found[id] == true)
end
for id in pairs(d.Materials.Found) do
	check("every found category was announced " .. id, announced[id] == 1)
end

-- idempotent per rock
local before = d.Materials.Counts.CommonStone or 0
local counted1 = Profiles.recordMaterial(s.me, "test:key:1", "CommonStone")
local counted2 = Profiles.recordMaterial(s.me, "test:key:1", "CommonStone")
check("first record counts", counted1 == true)
check("duplicate record is ignored", counted2 == false)
check("count rose by exactly one", (d.Materials.Counts.CommonStone or 0) == before + 1)
check("unknown category is ignored", select(1, Profiles.recordMaterial(s.me, "test:key:2", "NopeStone")) == false)
d.Materials.Counts.CommonStone = before -- keep the sums above meaningful for later checks

-- the client-facing view
local view = Profiles.publicView(s.me, false)
check("public view lists found categories", view.Materials ~= nil and next(view.Materials.Found) ~= nil)
local rate = Config.Tiers.Gravel.CashPerRubble
check("public view rubble value = rubble x rate", view.RubbleValue == Profiles.rubbleTotal(d) * rate, tostring(view.RubbleValue))

-- one sale pays once; a double tap pays nothing more
local rubble = Profiles.rubbleTotal(d)
local cash0 = d.Cash
Economy.sellRubble(s.me)
check("sale paid rubble x rate", d.Cash == cash0 + rubble * rate, d.Cash .. " vs " .. (cash0 + rubble * rate))
check("bag empty after the sale", Profiles.rubbleTotal(d) == 0)
local cash1 = d.Cash
Economy.sellRubble(s.me)
check("a double tap pays nothing", d.Cash == cash1)
check("materials survive the sale", next(d.Materials.Found) ~= nil)

print(if #fails == 0 then "MATERIALS PASS" else ("MATERIALS FAIL: " .. table.concat(fails, ", ")))
