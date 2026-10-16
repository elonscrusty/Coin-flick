-- Second audit batch, server checks (run by tests/test_audit_batch2.luau) through the real handlers on the offline
-- mock: tower Start/Leave spam builds at most one arena per gap (a team-edit burst never swallows a Start), a tower climber's respawn stays on the floor, the
-- Display quest cannot be farmed through DisplayAt, speed boots keep a pet's speed bonus, a batch of cracked eggs
-- fires one Profiles.changed per player, and a helper's bonus pet is granted before the award yields.
local C = lib("ctr")

local function case(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		print("CASE " .. name .. " PASS")
	else
		print("[FAIL] CASE " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data, Config)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.CapacityTier = #Config.Capacity
	end,
})
local me, ava = s.me, s.others[1]
local Profiles, MatchService, Config = s.Profiles, s.MatchService, s.Config
for _ = 1, 50 do
	if Profiles.isLoaded(ava) then
		break
	end
	preview.advance(0.1)
end
do
	local d = Profiles.get(ava)
	if d then
		d.TutorialStep = 1
		d.Onboard.Skipped = true
	end
end
local RockService = C.server("RockService")
local EggEvents = C.server("EggEvents")
local QuestService = C.server("QuestService")
local TowerBuilder = C.server("TowerBuilder")
local EggConfig = C.shared("EggConfig")
local QueueConfig = C.shared("QueueConfig")
local data = Profiles.get(me)

local function step(dt: number?)
	preview.advance(dt or 0.1)
end

case("Display quest: placing, removing and re-placing one pet through DisplayAt counts once", function()
	local specs = C.fakeSpecimens(2)
	for _, g in specs do
		table.insert(data.InventoryGeodes, g)
	end
	data.DisplayAssignments = {}
	local notes = 0
	local real = QuestService.note
	QuestService.note = function(p, kind, ...)
		if p == me and kind == "Display" then
			notes += 1
		end
		return real(p, kind, ...)
	end
	local ok, err = pcall(function()
		local a, b = specs[1].Id, specs[2].Id
		for _ = 1, 3 do
			preview.fireServerAs(me, "CollectionAction", "DisplayAt", a, #data.DisplayAssignments + 1)
			step(0.3)
			assert(table.find(data.DisplayAssignments, a), "placed")
			preview.fireServerAs(me, "CollectionAction", "Display", a, false)
			step(0.3)
			assert(not table.find(data.DisplayAssignments, a), "removed")
		end
		eq(notes, 1, "one pet counts once")
		preview.fireServerAs(me, "CollectionAction", "DisplayAt", b, #data.DisplayAssignments + 1)
		step(0.3)
		eq(notes, 2, "a different pet counts")
	end)
	QuestService.note = real
	data.DisplayAssignments = {}
	if not ok then
		error(err, 0)
	end
end)

-- Tower: the remote lives in ReplicatedStorage.TowerNet.
local towerAction = game:GetService("ReplicatedStorage"):WaitForChild("TowerNet"):WaitForChild("TowerAction")
local function tower(op: string)
	towerAction.OnServerEvent:_fire(me, { Op = op })
end

case("tower: Start/Leave spam builds at most one arena per gap; a Start inside the gap waits, never drops", function()
	local claims = 0
	local real = TowerBuilder.claim
	TowerBuilder.claim = function(...)
		claims += 1
		return real(...)
	end
	local ok, err = pcall(function()
		tower("Start")
		step(0.3)
		eq(me:GetAttribute("InTower"), true, "first start enters the tower")
		for _ = 1, 4 do
			tower("Leave")
			step(0.3)
			tower("Start")
			step(0.3)
		end
		eq(claims, 1, "no rebuilds inside the gap")
		eq(me:GetAttribute("InTower"), nil, "the last Start is waiting for the gap")
		step(3.5)
		eq(claims, 2, "the waiting Start builds once the gap is over")
		eq(me:GetAttribute("InTower"), true)
		tower("Start")
		step(0.3)
		eq(claims, 2, "Start while climbing does nothing")
		-- a Leave calls off a waiting Start
		tower("Leave")
		step(0.1)
		tower("Start") -- the gap since the last build is over: builds at once
		step(0.1)
		eq(claims, 3, "start after the gap builds at once")
		tower("Leave")
		step(0.1)
		tower("Start") -- inside the gap: waits
		step(0.1)
		tower("Leave")
		step(4)
		eq(claims, 3, "called-off start never builds")
		eq(me:GetAttribute("InTower"), nil)
	end)
	TowerBuilder.claim = real
	if not ok then
		error(err, 0)
	end
end)

case("tower: a burst of EquipBest right before Start does not swallow the Start", function()
	step(3.5) -- past the build gap
	tower("Open")
	for _ = 1, 6 do
		tower("EquipBest")
	end
	tower("Start")
	step(0.3)
	eq(me:GetAttribute("InTower"), true, "the run started")
end)

case("tower: a climber who respawns is put back on the floor, not the lobby pad", function()
	eq(me:GetAttribute("InTower"), true, "climbing")
	local root = me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local stand = root.Position
	local lobby = C.lobbySpawn().Position
	assert((stand - lobby).Magnitude > 20, "the tower floor is away from the lobby pad")
	C.makeCharacter(me, CFrame.new(0, 0, 0)) -- respawn
	step(0.5)
	local root2 = me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	assert((root2.Position - stand).Magnitude < 2, "back on the floor (" .. tostring(root2.Position) .. " vs " .. tostring(stand) .. ")")
	tower("Leave")
	step(0.5)
	eq(me:GetAttribute("InTower"), nil, "left")
end)

-- A two-player party hunt for the rest (Ava helps).
local function party(p, ...)
	preview.fireServerAs(p, "PartyAction", ...)
end
local w = C.watchMatch()
party(me, "Create")
step(0.3)
local pt = s.PartyService.of(me.UserId)
party(me, "Invite", ava.UserId)
step(0.3)
party(ava, "Accept", pt and pt.Id)
step(0.3)
party(me, "Ready", true)
party(ava, "Ready", true)
step(0.3)
party(me, "Start")
step(0.3)
C.waitPhase(w, "Searching", Config.Match.CountdownSeconds + 3)
local m = MatchService.matchFor(me.UserId)
if not m or m.Phase ~= "Searching" or MatchService.matchFor(ava.UserId) ~= m then
	print("[FAIL] CASE party hunt starts: phase " .. tostring(m and m.Phase))
	print("AUDIT_BATCH2 DONE")
	return
end
local core = m.Core

case("speed boots multiply the hunter's speed (pet bonus kept) and restore it", function()
	local hum = me.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local chance = EggConfig.Boots.Chance
	EggConfig.Boots.Chance = 1
	hum.WalkSpeed = 24 -- as if a speed pet lifted the base 18 by a third
	EggEvents.cracked(m, me.UserId)
	EggConfig.Boots.Chance = chance
	assert(math.abs(hum.WalkSpeed - 24 * (1 + EggConfig.Boots.Bonus)) < 0.01, "boosted from 24: " .. hum.WalkSpeed)
	step(EggConfig.Boots.Seconds + 0.5)
	assert(math.abs(hum.WalkSpeed - 24) < 0.01, "restored to 24, not the plain base: " .. hum.WalkSpeed)
end)

case("a batch of cracked eggs fires one Profiles.changed per player", function()
	data.Onboard.Cracked = true
	local chance = EggConfig.Boots.Chance
	EggConfig.Boots.Chance = 0
	-- counts the calls RockService makes, not the ones listeners make in reaction (a nested call)
	local calls, depth = 0, 0
	local real = Profiles.changed
	Profiles.changed = function(p, ...)
		if p == me and depth == 0 then
			calls += 1
		end
		depth += 1
		local ok, e = pcall(real, p, ...)
		depth -= 1
		if not ok then
			error(e, 0)
		end
	end
	local before = data.Stats.RocksCracked
	local ok, err = pcall(function()
		local mat = "NotAMaterial" -- not counted, so Profiles.recordMaterial (its own notice per egg) stays quiet
		RockService.apply(m, {
			{ Kind = "Cracked", UserId = me.UserId, RockId = 90001, Material = mat },
			{ Kind = "Cracked", UserId = me.UserId, RockId = 90002, Material = mat },
			{ Kind = "Cracked", UserId = me.UserId, RockId = 90003, Material = mat },
		})
	end)
	Profiles.changed = real
	EggConfig.Boots.Chance = chance
	if not ok then
		error(err, 0)
	end
	eq(data.Stats.RocksCracked, before + 3, "every egg counted")
	eq(calls, 1, "one change notice for the batch")
end)

case("a respawn uses this round's bay, even after the party list shifted", function()
	local bay = m.BayOf[ava.UserId]
	assert(bay, "Ava has a bay this round")
	-- shift every party index by one (a member leaving shifts the ones after them the same way)
	table.insert(m.Party.Members, 1, 999999)
	local ok, err = pcall(function()
		C.makeCharacter(ava, CFrame.new(0, 0, 0)) -- respawn
		step(0.3)
		local root = ava.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		local want = m.Arena.Spawns[bay].Position
		assert((root.Position - want).Magnitude < 1, "Ava back on her own spot")
	end)
	table.remove(m.Party.Members, 1)
	if not ok then
		error(err, 0)
	end
end)

case("a helper's bonus pet is granted at the find, before the award yields", function()
	local bonus = QueueConfig.Bonus
	local chance, minCracked = bonus.Chance, bonus.MinCracked
	bonus.Chance, bonus.MinCracked = 1, 0
	core.Members[ava.UserId].Cracked = 50
	local adata = Profiles.get(ava) :: any
	local n = #adata.InventoryGeodes
	local ok, err = pcall(function()
		RockService.apply(m, { { Kind = "Found", UserId = me.UserId, RockId = core.TargetId } })
	end)
	local granted = #adata.InventoryGeodes -- read in the same frame: no time has passed
	bonus.Chance, bonus.MinCracked = chance, minCracked
	if not ok then
		error(err, 0)
	end
	eq(granted, n + 1, "Ava has her bonus pet already")
	step(1)
end)

print("AUDIT_BATCH2 DONE")
