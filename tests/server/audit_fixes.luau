-- Server checks for the AUDIT_REPORT fixes (run by tests/test_audit_fixes.luau) through the real handlers on the
-- offline mock: a forged party Kick cannot pull a stranger out of the hunt queue, the luck potion follows the paid
-- random item policy, the sell hopper prompt re-checks range, MatchAction Sync is rate limited, the teleport check
-- judges the live position at action time (walking still works), and the overtime glow waits for a carried pet egg.
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
local Profiles, MatchService, PartyService, Config = s.Profiles, s.MatchService, s.PartyService, s.Config
do
	local d = Profiles.get(ava)
	if d then
		d.TutorialStep = 1
		d.Onboard.Skipped = true
	end
end
local HuntQueue = C.shared("HuntQueue")
local RobuxConfig = C.shared("RobuxConfig")
local RoundRocks = C.shared("RoundRocks")
local RockService = C.server("RockService")
local Economy = C.server("EconomyService")
local data = Profiles.get(me)

local function step(dt: number?)
	preview.advance(dt or 0.1)
end

case("party Kick of a stranger leaves the stranger in the hunt queue", function()
	preview.fireServerAs(ava, "PartyAction", "Queue")
	step(0.5)
	local _, g = HuntQueue.find(PartyService.Queue, ava.UserId)
	assert(g, "Ava queued")
	preview.fireServerAs(me, "PartyAction", "Create")
	step(0.3)
	assert(PartyService.of(me.UserId), "my party")
	for _ = 1, 3 do
		preview.fireServerAs(me, "PartyAction", "Kick", ava.UserId)
		step(0.3)
	end
	local _, g2 = HuntQueue.find(PartyService.Queue, ava.UserId)
	assert(g2, "a forged Kick must not unqueue a stranger")
	preview.fireServerAs(ava, "PartyAction", "Unqueue")
	step(0.3)
	local _, g3 = HuntQueue.find(PartyService.Queue, ava.UserId)
	eq(g3, nil, "Ava left the queue herself")
end)

case("luck potion: refused while paid random items are restricted; a paid receipt still grants", function()
	RobuxConfig.Potion.ProductId = 9200 -- test-only id (the config keeps 0 + REPLACE)
	step(1)
	local before = #preview.marketPrompts()
	me:SetAttribute("PaidRandomRestricted", true)
	preview.fireServerAs(me, "RobuxAction", "Buy", RobuxConfig.Potion.Id)
	step(1)
	eq(#preview.marketPrompts(), before, "no prompt while restricted")
	local receipt = game:GetService("MarketplaceService").ProcessReceipt
	eq(receipt({ PlayerId = me.UserId, PurchaseId = "AUD-pot", ProductId = 9200 }), Enum.ProductPurchaseDecision.PurchaseGranted, "already-paid receipt granted")
	assert(RobuxConfig.potionLeft(data.Robux, os.time()) > 0, "potion time added")
	me:SetAttribute("PaidRandomRestricted", false)
	data.Robux.LuckUntil = 0
	preview.fireServerAs(me, "RobuxAction", "Buy", RobuxConfig.Potion.Id)
	step(1)
	eq(#preview.marketPrompts(), before + 1, "prompt once allowed")
	RobuxConfig.Potion.ProductId = 0
end)

case("sell hopper prompt: refused out of range, sells in range", function()
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	local body = Instance.new("Part")
	body.Anchored = true
	body.Position = root.Position + Vector3.new(80, 0, 0)
	local pp = Instance.new("ProximityPrompt")
	pp.MaxActivationDistance = 12
	pp:SetAttribute("Sell", true)
	pp.Parent = body
	body.Parent = workspace
	local pps = game:GetService("ProximityPromptService")
	data.Cash = 0
	data.RubbleByTier = { Gravel = 10 }
	pps.PromptTriggered:_fire(pp, me)
	step(1)
	eq(data.Cash, 0, "far prompt does not sell")
	body.Position = root.Position + Vector3.new(5, 0, 0)
	pps.PromptTriggered:_fire(pp, me)
	step(1)
	eq(data.Cash, 10 * Config.Tiers.Gravel.CashPerRubble, "near prompt sells")
	body:Destroy()
	local _ = Economy
end)

-- a solo hunt for the rest
local w = C.watchMatch()
preview.fireServerAs(me, "PartyAction", "Leave")
step(0.3)
C.startSolo(w)
C.waitPhase(w, "Searching", Config.Match.CountdownSeconds + 3)
local m = MatchService.matchFor(me.UserId)
if not m or m.Phase ~= "Searching" then
	print("[FAIL] CASE solo hunt starts: phase " .. tostring(m and m.Phase))
	print("AUDIT_FIXES DONE")
	return
end
local core = m.Core

local function standAt(localPos: Vector3)
	me.Character:PivotTo(CFrame.new(m.Arena.Center + Vector3.new(localPos.X, 3, localPos.Z)))
end
local function rockAct(action, id)
	preview.fireServerAs(me, "RockAction", action, m.Round, id)
end
local function pickable(): number?
	for _, id in core.Pile:pickableIds(Config.Carry.ReachLevels) do
		if id ~= core.TargetId then
			return id
		end
	end
	return nil
end

case("MatchAction Sync: one full Init per 2 seconds", function()
	local function inits(): number
		local n = 0
		for _, k in w.kinds do
			n += if k == "Init" then 1 else 0
		end
		return n
	end
	step(2.5)
	local n0 = inits()
	for _ = 1, 5 do
		preview.fireServerAs(me, "MatchAction", "Sync")
		step(0.3)
	end
	eq(inits(), n0 + 1, "five Syncs in 1.5 s -> one Init")
	step(1)
	preview.fireServerAs(me, "MatchAction", "Sync")
	step(0.1)
	eq(inits(), n0 + 2, "another Init after the gap")
end)

case("teleport check: a teleport-pick-teleport is refused at action time; walking there works", function()
	Config.Motion.Enabled = true
	local ok, err = pcall(function()
		local station = RoundRocks.stationPosition(core.Members[me.UserId].Index)
		standAt(station)
		RockService.resetMotion(me.UserId)
		step(Config.Motion.Grace + 0.5)
		local id = pickable() :: number
		local lp = core.Pile:localPosition(id) :: Vector3
		local spot = lp + Vector3.new(2, 0, 0)
		-- teleport in, pick in the same frame, teleport out: never sampled by the scheduler
		standAt(spot)
		rockAct("Pickup", id)
		standAt(station)
		eq(core.Rocks[id].State, "InPile", "teleport pickup refused")
		step(Config.Motion.Lock + 0.5)
		-- walk there at normal speed (16 studs/s), then pick: allowed
		local from = Vector3.new(station.X, 0, station.Z)
		local to = Vector3.new(spot.X, 0, spot.Z)
		local n = math.ceil((to - from).Magnitude / 1.6)
		for i = 1, n do
			standAt(from:Lerp(to, i / n))
			step(0.1)
		end
		step(0.5)
		rockAct("Pickup", id)
		step(0.1)
		eq(core.Rocks[id].State, "Carried", "walked-up pickup works")
	end)
	Config.Motion.Enabled = false
	if not ok then
		error(err, 0)
	end
end)

case("overtime: a carried pet egg at 3:00 glows once it is back in the pile", function()
	local EggConfig = C.shared("EggConfig")
	local seen: { any } = {}
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local ev = folder and folder:FindFirstChild("EggEvent")
	assert(ev, "EggEvent remote")
	ev.OnClientEvent:Connect(function(kind, payload)
		if kind == "Overtime" or kind == "Wobble" then
			table.insert(seen, { Kind = kind, Data = payload, At = preview.now() })
		end
	end)
	-- the solo hunter carries the pet egg (straight into the basket, like the rock audit's grab)
	local target = core.TargetId
	local r = core.Rocks[target]
	eq(r.State, "InPile", "pet egg in the pile")
	core.Pile:remove(target)
	r.State, r.Carrier, r.Station = "Carried", me.UserId, nil
	table.insert(core.Members[me.UserId].Basket, target)
	local t0 = w.at.Searching or preview.now()
	preview.advance(math.max(0, EggConfig.Overtime.RoundSeconds + 5 - (preview.now() - t0)), 10)
	for _, e in seen do
		assert(e.Kind ~= "Overtime", "no glow while the pet egg is carried")
	end
	local wobblesBefore = 0
	for _, e in seen do
		wobblesBefore += if e.Kind == "Wobble" then 1 else 0
	end
	assert(wobblesBefore > 0, "wobbles keep going (with decoys) while the pet egg is out of the pile")
	-- the hunter resets: the basket drops back on the pile
	RockService.characterReset(m, me.UserId)
	step(0.5)
	local glow = nil
	for _, e in seen do
		if e.Kind == "Overtime" then
			glow = e.Data
		end
	end
	assert(glow, "glow sent once the pet egg is back")
	eq(glow.Id, target, "the glow names the pet egg")
end)

case("party blockers: a member climbing the pet tower blocks the start", function()
	local fake: any = { Tier = "Gravel" }
	eq(#PartyService.blockers(fake, ava.UserId), 0, "free before the tower")
	ava:SetAttribute("InTower", true)
	local b = PartyService.blockers(fake, ava.UserId)
	ava:SetAttribute("InTower", nil)
	assert(table.find(b, "In the pet tower"), "tower blocker listed")
end)

case("ledger: an award whose own save failed is marked applied by the next committed save", function()
	local Ledger = C.server("AwardLedger")
	local GeodeGen = C.shared("GeodeGen")
	local key = "audit:ledger:1"
	local spec = GeodeGen.roll(Random.new(7), "Gravel", "audit-ledger-pet", "m", 0, true, 3)
	Ledger.record(key, me.UserId, spec)
	local ds = game:GetService("DataStoreService"):GetDataStore(Config.Save.LedgerName)
	eq(ds:GetAsync(key).State, "pending", "decision stored")
	preview.failDataStores(false, true)
	local saved: boolean? = nil
	task.spawn(function()
		local _, s2 = Ledger.apply(me, key, spec, "Multiplayer")
		saved = s2
	end)
	preview.advance(40, 10)
	preview.failDataStores(false, false)
	eq(saved, false, "the award's own save failed")
	eq(ds:GetAsync(key).State, "pending", "still pending after the failed save")
	local ok: boolean? = nil
	task.spawn(function()
		ok = Profiles.saveNow(me)
	end)
	preview.advance(2, 10)
	eq(ok, true, "a later save commits")
	eq(ds:GetAsync(key).State, "applied", "the later save marks the entry applied")
end)

print("AUDIT_FIXES DONE")
