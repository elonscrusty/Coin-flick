-- perf-round: leak check over several rounds (docs/m9/PERF.md). NOT device numbers (Lune + preview mock).
-- Four players in one Meteor party, a machine each (Crusher, Crusher, Press, Auto Cracker), all four
-- also pick up rocks and deposit them (full queues) for the whole hunt. After every round the game
-- returns to the lobby; this scene samples, at the same point of each round (hunt Searching phase
-- start, before any play) and after the round has been cleaned up:
--   instances alive (tree / not destroyed), parts in Workspace, connections still connected,
--   waiting task threads, active tweens, live Sounds, and the per-signal connection growth.
-- A count that keeps rising round after round is a leak. Prints PASS/FAIL per growth check.
--   --set rounds=4   --set json=1
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local ROUNDS = tonumber(preview.args.rounds) or 4
local fails = {}
local function check(name: string, ok: boolean, detail: string)
	print(string.format("[%s] %s: %s", if ok then "PASS" else "FAIL", name, detail))
	if not ok then
		table.insert(fails, name)
	end
end

preview.setFrameLayout(false)
local s = C.boot({
	others = { { "Ava", 2 }, { "Ben", 3 }, { "Cy", 4 } },
	profile = function(data)
		data.Cash = 5000
		data.TutorialStep = 1
	end,
})
local Config = s.Config
local all = { s.me }
for _, p in ipairs(s.others) do
	table.insert(all, p)
end
local MACHINES = { "IndustrialCrusher", "IndustrialCrusher", "HydraulicPress", "AutoCracker" }
for i, p in ipairs(all) do
	local d = s.Profiles.get(p)
	d.TutorialStep = 1
	d.CapacityTier = #Config.Capacity
	d.UnlockedTiers.Meteor = true
	d.UnlockedTiers.Quarry = true
	d.EquipmentOwned[MACHINES[i]] = true
	d.InstalledMachine = MACHINES[i]
	s.Profiles.changed(p)
end
preview.advance(1)

local function parts(): number
	local n = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local function sample(label: string)
	local tree, alive = preview.liveInstances()
	local live = preview.liveCounts()
	return { label = label, tree = tree, alive = alive, parts = parts(), conns = live.connections, waiting = live.waiting, tweens = live.tweens, sounds = live.sounds, bySignal = live.bySignal }
end
local function show(x)
	print(string.format("   %-22s tree %6d  alive %6d  parts %6d  conns %5d  waiting %4d  tweens %3d  sounds %3d", x.label, x.tree, x.alive, x.parts, x.conns, x.waiting, x.tweens, x.sounds))
end

local w = C.watchMatch()
game:GetService("ReplicatedStorage").Remotes.Toast.OnClientEvent:Connect(function(t, k)
	if k == "warn" then
		print("[toast]", k, t)
	end
end)
local rows = {}
local frameMs = {}
for round = 1, ROUNDS do
	w.last.Found = nil
	w.last.Init = nil
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(s.me.UserId)
	C.fireServer("PartyAction", "Tier", "Meteor")
	preview.advance(0.3)
	for i = 1, 3 do
		local p = s.others[i]
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", party and party.Id)
		preview.advance(0.3)
	end
	for i = 1, 3 do
		preview.fireServerAs(s.others[i], "PartyAction", "Ready", true)
		preview.advance(0.3)
	end
	C.fireServer("PartyAction", "Ready", true)
	preview.advance(0.3)
	C.fireServer("PartyAction", "Start")
	for _ = 1, 30 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
	if not w.last.Init then
		check("round " .. round .. " starts", false, "no Init")
		break
	end
	C.waitPhase(w, "Searching", 8)
	preview.advance(1)
	rows[#rows + 1] = sample("round " .. round .. " start")
	show(rows[#rows])
	-- hunt: pick up, deposit, machines run; per-frame cost of the whole mock (client + server callbacks)
	preview.profile(true)
	local frames = 0
	local conn = game:GetService("RunService").Heartbeat:Connect(function()
		frames += 1
	end)
	local t0 = preview.now()
	C.followCamera(14, 7)
	C.crackUntilFound(w, all, tonumber(preview.args.hunt) or 120)
	local dt = preview.now() - t0
	conn:Disconnect()
	local rep = preview.profileReport()
	preview.profile(false)
	local total = 0
	for _, t in pairs(rep.time) do
		total += t.excl
	end
	table.insert(frameMs, total * 1000 / math.max(frames, 1))
	print(string.format("   round %d: hunt %.1f s, %d frames, %.3f mock ms/frame in all callbacks", round, dt, frames, frameMs[#frameMs]))
	-- reveal, results, back to the lobby
	preview.advance(8)
	for _, p in ipairs(all) do
		preview.fireServerAs(p, "MatchAction", "Return")
		preview.advance(0.3)
	end
	preview.advance(8)
	rows[#rows + 1] = sample("round " .. round .. " cleaned up")
	show(rows[#rows])
end

-- Compare the same point of each round (start of round k against round 1) and the cleaned-up points.
local first, last = rows[1], rows[#rows - 1]
if first and last and ROUNDS >= 2 then
	local function grew(key: string, slack: number)
		return last[key] - first[key] <= slack
	end
	check("instances alive (start of last vs first round)", grew("alive", 150), string.format("%d -> %d", first.alive, last.alive))
	check("parts in Workspace (start of last vs first round)", grew("parts", 50), string.format("%d -> %d", first.parts, last.parts))
	check("connections (start of last vs first round)", grew("conns", 30), string.format("%d -> %d", first.conns, last.conns))
	check("tweens (start of last vs first round)", grew("tweens", 5), string.format("%d -> %d", first.tweens, last.tweens))
	check("sounds (start of last vs first round)", grew("sounds", 5), string.format("%d -> %d", first.sounds, last.sounds))
	local worst, worstKey = 0, ""
	for k, v in pairs(last.bySignal) do
		local d = v - (first.bySignal[k] or 0)
		if d > worst then
			worst, worstKey = d, k
		end
	end
	print(string.format("   largest connection growth by signal: %s +%d", worstKey, worst))
	check("per-frame cost (last round vs first)", frameMs[#frameMs] <= frameMs[1] * 1.5 + 0.3, string.format("%.3f -> %.3f mock ms/frame", frameMs[1], frameMs[#frameMs]))
end
if preview.args.json then
	for _, x in ipairs(rows) do
		print(string.format("PERFROW %s tree=%d alive=%d parts=%d conns=%d waiting=%d tweens=%d sounds=%d", x.label, x.tree, x.alive, x.parts, x.conns, x.waiting, x.tweens, x.sounds))
	end
end
print(if #fails == 0 then "PERF-ROUND PASS" else ("PERF-ROUND FAIL: " .. table.concat(fails, ", ")))
