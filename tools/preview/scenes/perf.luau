-- perf: mock-runtime performance numbers (docs/PERF.md). NOT device FPS: Lune on Linux running
-- the real server and client modules against the preview mock. Use it to compare runs of the
-- same scene before and after a change, never to promise a frame rate.
--
-- 1. LOBBY: 16 players, each with the biggest gallery (20 specimens) rendered by GalleryService.
--    Reports part counts (whole lobby, galleries alone) and the server cost per Heartbeat while idle.
-- 2. HUNT: four of them form a party and hunt a Meteor pile (1600 rocks). Each member has a machine
--    installed (Crusher, Crusher, Press, Auto Cracker), and all four also hand-strike the whole
--    time. Reports part counts (rocks rendered by the client, machines), the server step
--    per Heartbeat, client callbacks per frame, and remote payload sizes per second
--    (estimated serialisation: numbers 3-9 bytes, strings length + 2, tables nested).
--   --set seconds=20   measured hunt seconds (the hunt may end sooner when the geode is found)
--   --set top=14       rows per table
--   --set phase=lobby|hunt|all   (default all)
--   --set json=1       also print one JSON line PERFJSON {...} with the headline numbers
-- Prints PASS/FAIL for the budgets at the end (budgets are for the mock, see docs/PERF.md).
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local args = preview.args
local SECONDS = tonumber(args.seconds) or 20
local TOP = tonumber(args.top) or 14
local PHASE = args.phase or "all"
local fails = {}
local function check(name: string, ok: boolean, detail: string)
	print(string.format("[%s] %s: %s", if ok then "PASS" else "FAIL", name, detail))
	if not ok then
		table.insert(fails, name)
	end
end

local names = {}
for i = 1, 15 do
	table.insert(names, { "Guest" .. i, 100 + i })
end
preview.setFrameLayout(false) -- the mock's GUI layout is not game code
local s = C.boot({
	others = names,
	profile = function(data)
		data.Cash = 5000
		data.TutorialStep = 1
	end,
})
local Config = s.Config
local Gallery = C.server("GalleryService")
local all = { s.me }
for _, p in ipairs(s.others) do
	table.insert(all, p)
end

-- every player: biggest gallery (20 slots), 20 specimens on display, Meteor unlocked; four have a machine
local MACHINES = { "IndustrialCrusher", "IndustrialCrusher", "HydraulicPress", "AutoCracker" }
local specs = C.fakeSpecimens(20)
for i, p in ipairs(all) do
	local d = s.Profiles.get(p)
	if not d then
		preview.warn("profile not loaded for " .. p.Name)
		continue
	end
	d.TutorialStep = 1
	d.DisplayCapacity = #Config.Display
	d.CapacityTier = #Config.Capacity
	d.UnlockedTiers.Meteor = true
	d.UnlockedTiers.Quarry = true
	d.InventoryGeodes = {}
	d.DisplayAssignments = {}
	for k, g in ipairs(specs) do
		local copy = table.clone(g)
		copy.Id = string.format("%s-%d-%d", p.Name, i, k)
		table.insert(d.InventoryGeodes, copy)
		table.insert(d.DisplayAssignments, copy.Id)
	end
	if i <= 4 then
		d.EquipmentOwned[MACHINES[i]] = true
		d.InstalledMachine = MACHINES[i]
	end
	s.Profiles.changed(p)
	Gallery.render(p)
end
preview.advance(1)

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local function folderParts(name: string): number
	local n = 0
	for _, d in Workspace:GetDescendants() do
		if d.Name == name and (d:IsA("Folder") or d:IsA("Model")) then
			n += countParts(d)
		end
	end
	return n
end

local J = {} -- headline numbers for the json line

local function report(title: string, rep, seconds: number, frames: number)
	print(string.format("-- %s (%.1f simulated s, %d frames; mock ms, not device ms)", title, seconds, frames))
	local rows = {}
	for label, t in pairs(rep.time) do
		table.insert(rows, { label = label, excl = t.excl, calls = t.calls })
	end
	table.sort(rows, function(a, b)
		return a.excl > b.excl
	end)
	print(string.format("   %-52s %9s %8s %9s", "callback", "ms/frame", "calls", "ms/call"))
	for i = 1, math.min(TOP, #rows) do
		local r = rows[i]
		print(string.format("   %-52s %9.3f %8d %9.4f", string.sub(r.label, 1, 52), r.excl * 1000 / math.max(frames, 1), r.calls, r.excl * 1000 / math.max(r.calls, 1)))
	end
	local rem = {}
	for name, r in pairs(rep.remotes) do
		table.insert(rem, { name = name, calls = r.calls, bytes = r.bytes })
	end
	table.sort(rem, function(a, b)
		return a.bytes > b.bytes
	end)
	local total = 0
	for _, r in ipairs(rem) do
		total += r.bytes
	end
	print(string.format("   remotes (all recipients together): %.2f KB/s over %d kinds", total / 1024 / math.max(seconds, 0.001), #rem))
	for i = 1, math.min(8, #rem) do
		local r = rem[i]
		print(string.format("   %-40s %7.1f calls/s %9.2f KB/s", string.sub(r.name, 1, 40), r.calls / seconds, r.bytes / 1024 / seconds))
	end
	return rows, total
end

local function sumLabel(rows, pattern: string): number
	local t = 0
	for _, r in ipairs(rows) do
		if string.find(r.label, pattern) then
			t += r.excl
		end
	end
	return t
end

----------------------------------------------------------------------------------------------
-- 1. lobby with 16 galleries
----------------------------------------------------------------------------------------------
if PHASE == "all" or PHASE == "lobby" then
	local total = countParts(Workspace)
	local gallery = 0
	for _, d in Workspace:GetDescendants() do
		if d.Name == "Display" and d:IsA("Folder") then
			gallery += countParts(d)
		end
	end
	local displayed = 0
	for _, p in ipairs(all) do
		local d = s.Profiles.get(p)
		displayed += d and #d.DisplayAssignments or 0
	end
	print(string.format("LOBBY: %d players, %d specimens on display, %d parts in Workspace, %d of them in galleries (%.1f per specimen)", #all, displayed, total, gallery, gallery / math.max(displayed, 1)))
	J.lobbyParts = total
	J.galleryParts = gallery
	preview.profile(true)
	local frames = 0
	local t0 = preview.now()
	local conn = game:GetService("RunService").Heartbeat:Connect(function()
		frames += 1
	end)
	preview.advance(10)
	conn:Disconnect()
	local rep = preview.profileReport()
	preview.profile(false)
	local rows = report("lobby idle, 16 players", rep, preview.now() - t0, frames)
	local hb = sumLabel(rows, "Heartbeat") * 1000 / math.max(frames, 1)
	J.lobbyHeartbeatMs = hb
	check("lobby gallery parts per specimen", gallery / math.max(displayed, 1) <= 40, string.format("%.1f (budget 40)", gallery / math.max(displayed, 1)))
	check("lobby Heartbeat callbacks (mock)", hb < 2.0, string.format("%.3f ms/frame (budget 2.0 mock ms)", hb))
end

----------------------------------------------------------------------------------------------
-- 2. Meteor hunt, party of 4, a machine each
----------------------------------------------------------------------------------------------
if PHASE == "all" or PHASE == "hunt" then
	local w = C.watchMatch()
	local function sizeOf(v, depth): number
		local t = typeof(v)
		if t == "number" then
			return (v == math.floor(v) and math.abs(v) < 32768) and 3 or 9
		elseif t == "string" then
			return #v + 2
		elseif t == "boolean" or t == "nil" then
			return 1
		elseif t == "table" then
			if depth > 8 then
				return 0
			end
			local n = 2
			for k, x in pairs(v) do
				n += sizeOf(k, depth + 1) + sizeOf(x, depth + 1)
			end
			return n
		elseif t == "Color3" or t == "Vector3" then
			return 13
		elseif t == "CFrame" then
			return 25
		end
		return 4
	end
	local kindBytes, kindCalls = {}, {}
	local measuring = false
	local cracked = 0
	game:GetService("ReplicatedStorage").Remotes.MatchEvent.OnClientEvent:Connect(function(kind, data)
		if measuring then
			kindBytes[kind] = (kindBytes[kind] or 0) + sizeOf(data, 0) + #kind + 2
			kindCalls[kind] = (kindCalls[kind] or 0) + 1
			if kind == "Rocks" then
				for _, e in ipairs(data.Ev or {}) do
					if e.Kind == "Done" then
						cracked += 1
					end
				end
			end
		end
	end)

	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(s.me.UserId)
	C.fireServer("PartyAction", "Tier", "Meteor")
	preview.advance(0.3)
	local members = { s.me }
	for i = 1, 3 do
		local p = s.others[i]
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", party and party.Id)
		preview.advance(0.3)
		table.insert(members, p)
	end
	for i = 2, #members do
		preview.fireServerAs(members[i], "PartyAction", "Ready", true)
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
	local init = w.last.Init
	if not init then
		check("hunt starts", false, "no Init after Start; the party did not launch")
		print("PERF FAIL: hunt did not start")
		return
	end
	check("hunt starts", init.Tier == "Meteor" and init.Rocks == Config.Tiers.Meteor.Rocks, string.format("tier %s, %s rocks", tostring(init.Tier), tostring(init.Rocks)))
	C.waitPhase(w, "Searching", 8)
	preview.advance(1)

	local rockParts = folderParts("CT_Rocks_LocalPile")
	local machineParts = folderParts("CT_Rocks_Machines")
	print(string.format("HUNT: Meteor %d rocks; client pile renders %d parts; machines %d parts; Workspace %d parts", init.Rocks, rockParts, machineParts, countParts(Workspace)))
	J.huntRockParts = rockParts
	J.machineParts = machineParts
	J.workspaceParts = countParts(Workspace)

	preview.profile(true)
	measuring = true
	local frames = 0
	local conn = game:GetService("RunService").Heartbeat:Connect(function()
		frames += 1
	end)
	local t0 = preview.now()
	C.followCamera(14, 7) -- MachineView and Audio only work near the camera
	C.crackUntilFound(w, members, SECONDS)
	local dt = preview.now() - t0
	measuring = false
	conn:Disconnect()
	local rep = preview.profileReport()
	preview.profile(false)
	print(string.format("   hunt window %.1f s%s; %d rocks cracked in it (machines and hands)", dt, if w.last.Found then " (geode found, round ended)" else "", cracked))
	local rows, totalBytes = report("Meteor hunt, 4 members + 12 in the lobby", rep, dt, frames)
	local serverStep = sumLabel(rows, "MatchService")
	local clientRs = sumLabel(rows, "PileView") + sumLabel(rows, "MachineView")
	print(string.format("   MatchEvent as ONE recipient receives it (%.1f s):", dt))
	local kinds = {}
	for k in pairs(kindBytes) do
		table.insert(kinds, k)
	end
	table.sort(kinds, function(a, b)
		return kindBytes[a] > kindBytes[b]
	end)
	local oneTotal = 0
	for _, k in ipairs(kinds) do
		oneTotal += kindBytes[k]
		print(string.format("   %-12s %7.1f msgs/s %9.2f KB/s", k, kindCalls[k] / dt, kindBytes[k] / 1024 / dt))
	end
	J.matchEventKBsPerRecipient = oneTotal / 1024 / dt
	J.remotesKBsAllRecipients = totalBytes / 1024 / dt
	J.serverStepMsPerFrame = serverStep * 1000 / math.max(frames, 1)
	J.clientPileMachineMsPerFrame = clientRs * 1000 / math.max(frames, 1)
	J.frames = frames
	J.windowSeconds = dt
	J.rocksCracked = cracked
	check("hunt window long enough", dt >= 5, string.format("%.1f s measured", dt))
	check("hunt server step (mock)", J.serverStepMsPerFrame < 3.0, string.format("%.3f ms/frame in MatchService callbacks (budget 3.0 mock ms)", J.serverStepMsPerFrame))
	check("hunt client PileView+MachineView (mock)", J.clientPileMachineMsPerFrame < 3.0, string.format("%.3f ms/frame (budget 3.0 mock ms)", J.clientPileMachineMsPerFrame))
	check("MatchEvent per recipient", J.matchEventKBsPerRecipient < 20, string.format("%.2f KB/s (budget 20 KB/s)", J.matchEventKBsPerRecipient))
	check("rendered rock parts", rockParts <= 6000, string.format("%d client rock parts at start (budget 6000)", rockParts))
end

if args.json then
	local parts = {}
	for k, v in pairs(J) do
		table.insert(parts, string.format("%q:%.3f", k, v))
	end
	table.sort(parts)
	print("PERFJSON {" .. table.concat(parts, ",") .. "}")
end
print(if #fails == 0 then "PERF PASS" else ("PERF FAIL: " .. table.concat(fails, ", ")))
