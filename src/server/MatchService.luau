--!strict
-- Private hunts. Phase 1 runs in "SinglePlace" mode: each party gets its own walled quarry
-- arena in this server (far from the lobby, no paths in). Only party members are moved in and
-- only they can act on the pile. Phase 2 swaps the arena hand-off for a reserved Match place.
--
-- Lifecycle: Countdown (3 s, everyone frozen) -> Searching -> RewardPending -> Reveal ->
-- Results -> (Rematch -> Countdown) or Return to lobby.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local HuntPlacement = require(Shared.HuntPlacement)
local Net = require(Shared.Net)
local RoundRocks = require(Shared.RoundRocks)
local GeodeGen = require(Shared.GeodeGen)
local Profiles = require(script.Parent.Profiles)
local PartyService = require(script.Parent.PartyService)
local Ledger = require(script.Parent.AwardLedger)
local World = require(script.Parent.WorldBuilder)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local MachineModels = require(script.Parent.MachineModels)
local StationModels = require(script.Parent.StationModels)
local RockService = require(script.Parent.RockService)
local Economy = require(script.Parent.EconomyService)
local HuntLedger = require(Shared.HuntLedger)
local EggEvents = require(script.Parent.EggEvents)
local RareHatch = require(script.Parent.RareHatch)
local WinnerBoard = require(script.Parent.WinnerBoard)
local PetFlair = require(Shared.PetFlair)
local RacerCollision = require(script.Parent.RacerCollision)
local PracticeBots = require(script.Parent.PracticeBots)
local HuntQueue = require(Shared.HuntQueue)
local QueueConfig = require(Shared.QueueConfig)
local FriendBonus = require(script.Parent.FriendBonus)
local Hangout = require(Shared.Hangout)
local LuckEvents = require(Shared.LuckEvents)
local RobuxConfig = require(Shared.RobuxConfig)
local HuntFun = require(Shared.HuntFun)

local MatchService = {}

type Match = {
	Key: string,
	Slot: number,
	Arena: { [string]: any },
	Party: PartyService.Party,
	Round: number,
	Core: any,
	Phase: string,
	EndsAt: number,
	Tutorial: boolean,
	Solo: boolean,
	Present: { [number]: boolean },
	Rematch: { [number]: boolean },
	SpawnRot: number,
	Models: { [number]: Model }, -- machine model per owner
	ModelOf: { [number]: string }, -- machine id each model was built for
	BayOf: { [number]: number }, -- bay index per member for this round
	MachineSent: { [number]: string }, -- last machine state sent per owner
	LastFlush: number,
	Results: any?,
	Ledger: any,
	Start: number,
	SearchStart: number?,
	SearchEnd: number?, -- server time the geode was found (the hunt clock stops there)
	FullWarned: { [number]: number },
	FinishedRound: number?, -- round whose geode was already resolved (finishRound runs once per round)
	FoundRound: number?, -- RockService: round whose Found result was already applied
}

local matches: { [string]: Match } = {}
local matchOf: { [number]: string } = {}
local arenas: { [number]: { [string]: any } } = {}
local slotBusy: { [number]: boolean } = {}
local serverRng = Random.new()
local lobby: { [string]: any } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function playerOf(uid: number): Player?
	return Players:GetPlayerByUserId(uid)
end

local function send(m: Match, kind: string, payload: any)
	local ev = Net.event("MatchEvent")
	for uid in m.Present do
		local p = playerOf(uid)
		if p then
			ev:FireClient(p, kind, payload)
		end
	end
end

local function memberList(m: Match)
	local out = {}
	for _, uid in m.Party.Members do
		local p = playerOf(uid)
		local core = m.Core and m.Core.Members[uid]
		table.insert(out, {
			UserId = uid,
			Name = if p then p.DisplayName else "?",
			Present = m.Present[uid] == true,
			Cracked = if core then core.Cracked else 0,
			Leader = m.Party.Leader == uid,
			Station = if core then core.Index else nil,
			Rematch = m.Rematch[uid] == true,
		})
	end
	return out
end

local function setFrozen(player: Player, frozen: boolean)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		-- Speed pets (Config.Pets) only count inside a hunt; PetService refuses pet swaps while MatchKey is set, so the
		-- pet that started the hunt is the one whose speed and luck apply.
		local pdata = if player:GetAttribute("MatchKey") ~= nil then Profiles.get(player) else nil
		local speed = if pdata then Profiles.petBoosts(pdata).Speed else 0
		local free = if pdata then Config.Pets.BaseWalkSpeed * (1 + speed) else Config.Lobby.WalkSpeed
		hum.WalkSpeed = if frozen then 0 else free
		hum.JumpPower = if frozen then 0 else 42
	end
end

-- Lobby spawn (docs/m11/CAMERA_SPAWN_FIX.md): every character that appears outside a hunt is put on the lobby spawn
-- pad by the server. Roblox's own spawn placement lifts a character above anything it thinks overlaps the spawn,
-- and a character that spawned before the lobby was built stood at the lodge centre; either way it could end up on
-- the ceiling collider ("I spawn in the roof"). PivotTo does no such lift.
local function toLobbySpawn(player: Player)
	local char = player.Character
	-- A tower climber's respawn is put back on their floor by TowerService (InTower), never on the lobby pad.
	if char and lobby and lobby.Spawn and matchOf[player.UserId] == nil and player:GetAttribute("InTower") ~= true
		and player:GetAttribute("InBattle") ~= true then
		RacerCollision.apply(char, false)
		char:PivotTo(lobby.Spawn)
		-- lobby only: a touch faster than Roblox's 16 (hunts set their own speed; speed boots re-set theirs)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and math.abs(hum.WalkSpeed - 16) < 0.01 then
			hum.WalkSpeed = Config.Lobby.WalkSpeed
		end
	end
end

-- Spawn spot (and machine bay) of a member this round: party order, rotated between rounds.
local function spawnIndex(m: Match, uid: number): number
	local idx = table.find(m.Party.Members, uid) or 1
	return ((idx - 1 + m.SpawnRot) % #m.Arena.Spawns) + 1
end

local function placeAtSpawn(m: Match, player: Player)
	local spawns = m.Arena.Spawns
	-- This round's bay (fixed at round start), so a member who leaves the party mid-round does not shift the others'
	-- respawn spots onto someone else's table; spawnIndex only for someone not in this round's core.
	local uid = player.UserId
	local bay = if m.Core and m.Core.Members[uid] then m.BayOf[uid] else nil
	local cf = spawns[bay or spawnIndex(m, uid)]
	if typeof(m.Arena.Center) == "Vector3" then
		cf = HuntPlacement.faceCentre(cf, m.Arena.Center) -- start every round looking at the egg pile
	end
	local char = player.Character
	if char then
		RacerCollision.apply(char, true) -- hunters pass through each other
		char:PivotTo(cf)
		RockService.resetMotion(player.UserId) -- a server move, not a teleport cheat
	end
end

local function phase(m: Match, name: string, duration: number?)
	m.Phase = name
	m.EndsAt = if duration then now() + duration else 0
	if name ~= "Countdown" and name ~= "Searching" then
		PracticeBots.clear(m.Key) -- practice bots only live while the hunt runs, whatever ended it
	end
	if m.Core then
		m.Core:setPhase(name)
	end
	local frozen = name == "Countdown"
	for uid in m.Present do
		local p = playerOf(uid)
		if p then
			setFrozen(p, frozen)
		end
	end
	send(m, "Phase", { Phase = name, EndsAt = m.EndsAt, Round = m.Round, Members = memberList(m), SearchStart = m.SearchStart, SearchEnd = m.SearchEnd })
end

-- Machines ----------------------------------------------------------------------------------

local function machineList(m: Match): { any }
	local out = {}
	local core = m.Core
	if not core then
		return out
	end
	for uid, mem in core.Members do
		if mem.Machine and mem.Active and m.Present[uid] then
			table.insert(out, { UserId = uid, Bay = m.BayOf[uid], Id = mem.Machine, State = core:machineState(uid) })
		end
	end
	table.sort(out, function(a, b)
		return a.UserId < b.UserId
	end)
	return out
end

-- Tells the match's clients the machine states, only when something changed.
local function broadcastMachines(m: Match, force: boolean?)
	local core = m.Core
	if not core then
		return
	end
	local changed = force == true
	for uid, mem in core.Members do
		local st = if mem.Machine and mem.Active then core:machineState(uid) .. ":" .. mem.Machine else "None"
		if m.MachineSent[uid] ~= st then
			m.MachineSent[uid] = st
			changed = true
		end
	end
	if changed then
		send(m, "Machines", { Round = m.Round, List = machineList(m) })
	end
end

-- Keeps each owner's model in the bay matching the machine the core is running.
local function syncMachineModel(m: Match, uid: number)
	local core = m.Core
	local mem = core and core.Members[uid]
	local want = if mem and mem.Active then mem.Machine else nil
	if m.ModelOf[uid] == want then
		return
	end
	local old = m.Models[uid]
	if old then
		old:Destroy()
		m.Models[uid] = nil
	end
	m.ModelOf[uid] = want
	if want then
		local bayCf = m.Arena.Bays[m.BayOf[uid] or 1]
		local p = playerOf(uid)
		local model = MachineModels.build(want, bayCf, m.Arena.MachineFolder, uid, if p then p.DisplayName else "?")
		if model then
			m.Models[uid] = model
		end
	end
end

local function clearMachineModels(m: Match)
	for _, model in m.Models do
		model:Destroy()
	end
	table.clear(m.Models)
	table.clear(m.ModelOf)
	local folder = m.Arena.MachineFolder
	if folder then
		folder:ClearAllChildren()
	end
end

local function initPayload(m: Match)
	local core = m.Core
	local payload = {
		Key = m.Key,
		Round = m.Round,
		Tier = core.Tier,
		Seed = core.Seed,
		Tutorial = m.Tutorial,
		Center = m.Arena.Center,
		Phase = m.Phase,
		EndsAt = m.EndsAt,
		SearchStart = m.SearchStart,
		SearchEnd = m.SearchEnd,
		Members = memberList(m),
		Machines = machineList(m),
		Hp = {}, -- pre-V3 field: progress now lives in Stations[i].Progress
	}
	-- pile layout (Stacks), what left it (Removed), stations, tables and counters: ids and states only
	for k, v in RockService.initFields(m) do
		payload[k] = v
	end
	return payload
end

local function startRound(m: Match)
	m.Round += 1
	m.SearchStart, m.SearchEnd = nil, nil -- the hunt clock restarts with this round's Searching phase
	table.clear(m.Rematch)
	m.Results = nil
	local members = {}
	for _, uid in m.Party.Members do
		if m.Present[uid] then
			local p = playerOf(uid)
			local data = p and Profiles.get(p)
			local machine = nil
			if Config.MachinesEnabled and data and data.InstalledMachine and data.EquipmentOwned[data.InstalledMachine] then
				machine = data.InstalledMachine
			end
			local station = spawnIndex(m, uid) -- spawn spot = crushing table = machine bay, same index
			m.BayOf[uid] = station
			table.insert(members, {
				UserId = uid,
				Tool = if data then data.EquippedHandheld else "Hammer",
				Machine = machine,
				Station = station,
			})
		end
	end
	m.Solo = #members == 1
	local tutorial = false
	if m.Solo then
		local p = playerOf(members[1].UserId)
		local data = p and Profiles.get(p)
		tutorial = data ~= nil and data.TutorialStep == 0
	end
	m.Tutorial = tutorial
	if tutorial then
		Profiles.onboard(playerOf(members[1].UserId) :: Player, "Started")
	end
	m.Ledger = HuntLedger.new()
	local tier = if tutorial then Config.Tutorial.Tier else m.Party.Tier
	-- the reused arena takes this round's zone look (ground, boundary tint, landmarks); scenery never blocks a round
	local okZone, zoneErr = pcall(function()
		ArenaBuilder.applyZone(m.Arena, tier)
		return nil
	end)
	if not okZone then
		warn("[MatchService] zone scenery failed: " .. tostring(zoneErr))
	end
	m.Core = RoundRocks.new({
		MatchKey = m.Key,
		RoundId = m.Round,
		Tier = tier,
		Seed = serverRng:NextInteger(1, 2 ^ 30),
		TargetRng = Random.new(serverRng:NextInteger(1, 2 ^ 30)),
		Members = members,
		Tutorial = tutorial,
	})
	for _, mem in members do
		RockService.refreshSpace(m, mem.UserId)
	end
	-- tables: owners' names and accents on, the rest stay calm (plain "TABLE n")
	for i, tbl in m.Arena.Tables do
		local owner: number? = nil
		for _, mem in members do
			if mem.Station == i then
				owner = mem.UserId
			end
		end
		local p = if owner then playerOf(owner) else nil
		StationModels.setOwner(tbl, owner, if p then p.DisplayName else nil)
	end
	-- the practice pile: friendly bots race at the free nests (scenery only, they can never find the pet)
	if tutorial then
		local used: { [number]: boolean } = {}
		for _, mem in members do
			used[mem.Station] = true
		end
		PracticeBots.spawn(m.Key, m.Arena, used)
	else
		PracticeBots.clear(m.Key)
	end
	clearMachineModels(m)
	table.clear(m.MachineSent)
	for _, mem in members do
		syncMachineModel(m, mem.UserId)
	end
	m.Start = now()
	m.FullWarned = {}
	for uid in m.Present do
		local p = playerOf(uid)
		if p then
			placeAtSpawn(m, p)
		end
	end
	m.Phase = "Countdown"
	m.EndsAt = now() + Config.Match.CountdownSeconds
	send(m, "Init", initPayload(m))
	phase(m, "Countdown", Config.Match.CountdownSeconds)
	m.SpawnRot += 1 -- next round starts from rotated spots
end

-- The profile's rubble bag as the results screen shows it: count, capacity and what the bag would sell for.
local function bagOf(p: Player?): { Count: number, Capacity: number, Value: number }
	local data = p and Profiles.get(p)
	if not data then
		return { Count = 0, Capacity = 0, Value = 0 }
	end
	return { Count = Profiles.rubbleTotal(data), Capacity = Profiles.capacity(data), Value = Profiles.rubbleValue(data) }
end

local leaveMatch: (number, boolean) -> ()

local COMMON_ONLY = { Common = 1 } -- rarity table for practice and bonus pets

-- Helpers' lucky common: a non-finder who cracked enough eggs this round may get a Common pet of the zone.
-- Server-rolled; granted as "Bonus" (no win or find stat, never auto-follows) under its own award key.
local function rollBonusPets(m: Match, core: any, winnerUid: number, tierId: string, awardKey: string): { [number]: string }
	local out: { [number]: string } = {}
	if m.Tutorial then
		return out
	end
	for uid, mem in core.Members do
		local p = playerOf(uid)
		local data = p and Profiles.get(p)
		local eligible = p and data and mem.Active and Profiles.isLoaded(p) and not Profiles.isReleased(p)
			and HuntQueue.bonusEligible(mem.Cracked or 0, uid == winnerUid, m.Tutorial, QueueConfig.Bonus.MinCracked)
			and serverRng:NextNumber() < QueueConfig.Bonus.Chance
		local full = eligible and #(data :: any).InventoryGeodes >= Profiles.petCapacity(data)
		if full then
			-- the bonus is skipped, but never silently
			task.delay(Config.Match.RevealSeconds, function()
				if p and p.Parent then
					PartyService.toast(p, "Your Pet Book is full, so a bonus pet was missed. Sell or release a pet!", "warn")
				end
			end)
		end
		if p and data and eligible and not full then
			-- rolled from a Common-only table, so the species is a Common one too (never a Common chase pet)
			local pet = GeodeGen.roll(Random.new(serverRng:NextInteger(1, 2 ^ 30)), tierId, HttpService:GenerateGUID(false), awardKey, os.time(), true, 0, COMMON_ONLY)
			pet.Modifier = Config.Modifiers[1]
			pet.Value = GeodeGen.value(tierId, pet.Rarity, pet.Modifier, pet.Mass, pet.Shiny)
			if Profiles.grantSpecimen(p, awardKey .. ":bonus:" .. uid, pet, "Bonus") then
				local name = GeodeGen.displayName(pet)
				out[uid] = name
				task.delay(Config.Match.RevealSeconds, function() -- after the finder's reveal, not over it
					if p.Parent then
						PartyService.toast(p, "Lucky! You found a Common " .. name .. " in your eggs!", "rare")
					end
				end)
			end
		end
	end
	return out
end

-- Prizes for everyone (owner pick 2026-10-15, shared/HuntFun.Prizes): the racers who did not find the pet get a medal
-- by eggs finished, coins and pet XP, paid now (before the award yields) so a racer who leaves keeps them.
local function payPrizes(m: Match, core: any, winnerUid: number, tierId: string): { [number]: HuntFun.Prize }
	if m.Tutorial then
		return {}
	end
	local racers = {}
	for uid, mem in core.Members do
		if mem.Active then
			table.insert(racers, { UserId = uid, Eggs = mem.Cracked or 0 })
		end
	end
	local prizes = HuntFun.prizes(racers, winnerUid, tierId)
	for uid, prize in prizes do
		local p = playerOf(uid)
		local data = p and Profiles.get(p)
		if p and data and uid ~= winnerUid and Profiles.isLoaded(p) and not Profiles.isReleased(p) then
			data.Cash += prize.Coins
			if RockService.onPetXp then
				RockService.onPetXp(p, prize.Xp)
			end
			Profiles.changed(p, true)
		end
	end
	return prizes
end

local function finishRound(m: Match, winnerUid: number, rockId: number)
	-- Exactly one finish per round: a second report (duplicate result, late callback) changes nothing.
	if m.FinishedRound == m.Round or not m.Core then
		return
	end
	m.FinishedRound = m.Round
	PracticeBots.clear(m.Key) -- the pet is found: the practice bots step off for the reveal
	RockService.flush(m)
	HuntLedger.close(m.Ledger) -- later sales no longer count as "this hunt"
	local core = m.Core
	local awardKey = m.Key .. ":" .. m.Round
	local tierId = core.Tier
	local kind = if m.Tutorial then "Tutorial" elseif m.Solo then "Solo" else "Multiplayer"
	local winner = playerOf(winnerUid)
	m.SearchEnd = now()
	phase(m, "RewardPending")
	send(m, "Found", { Round = m.Round, RockId = rockId, Winner = winnerUid, WinnerName = if winner then winner.DisplayName else "?" })

	-- Hold the winner's profile open until the prize is saved, even if they leave right now.
	if winner then
		Profiles.hold(winner)
	end
	-- The award runs under pcall: an error (roll, ledger, reveal) must never leave the winner's profile held
	-- or the phase stuck at RewardPending. The hold is released exactly once, whatever happens.
	local held = winner ~= nil
	local function release()
		if held and winner then
			held = false
			Profiles.unhold(winner)
		end
	end
	local round = m.Round
	-- Helpers' bonus pets are rolled and granted now, before the award below yields on the DataStore: a helper who
	-- leaves the server during that wait still has the pet in their profile when it is saved on the way out.
	local bonusOk, bonusRes = pcall(rollBonusPets, m, core, winnerUid, tierId, awardKey)
	local bonusPets: { [number]: string } = if bonusOk then bonusRes else {}
	if not bonusOk then
		warn("[MatchService] bonus pets for " .. awardKey .. " failed: " .. tostring(bonusRes))
	end
	local prizeOk, prizeRes = pcall(payPrizes, m, core, winnerUid, tierId)
	local prizes: { [number]: HuntFun.Prize } = if prizeOk then prizeRes else {}
	if not prizeOk then
		warn("[MatchService] hunt prizes for " .. awardKey .. " failed: " .. tostring(prizeRes))
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local wdata = winner and Profiles.get(winner)
			local luck = if wdata then Profiles.petBoosts(wdata).Luck else 0
			-- friend bonus (QueueConfig.FriendLuck): Roblox friends of the finder in this server lift the odds a little
			local friendLuck = 0
			if winner and not m.Tutorial then
				friendLuck = FriendBonus.luck(winner) -- added below by LuckEvents.total
				-- Roblox group members (lobby hangout idea 10; LobbyHangout sets GroupMember from GroupService)
				friendLuck += Hangout.groupLuck(winner:GetAttribute("GroupMember") == true)
			end
			-- Robux luck potion + weekend 2x luck + luck storm (LuckEvents); every source adds up, the total is clamped.
			local storm = game:GetService("ReplicatedStorage"):GetAttribute("LuckStormUntil")
			local timed = LuckEvents.timed(os.time(), if wdata then tonumber(wdata.Robux.LuckUntil) else 0, if type(storm) == "number" then storm else 0)
			local eventLuck = timed.Potion + timed.Weekend + timed.Storm + timed.Hour
			luck = LuckEvents.total({ Pet = luck, Friends = friendLuck, Potion = timed.Potion, Weekend = timed.Weekend, Storm = timed.Storm, Hour = timed.Hour, Vip = if wdata then RobuxConfig.vipLuck(wdata.Robux) else 0 })
			local specimen = GeodeGen.roll(Random.new(serverRng:NextInteger(1, 2 ^ 30)), tierId, HttpService:GenerateGUID(false), awardKey, os.time(), kind ~= "Multiplayer", luck, if m.Tutorial then COMMON_ONLY else nil)
			if m.Tutorial then
				-- the practice pile always gives a plain Common pet (never a 1-in-1000 chase pet on the first round)
				specimen.Modifier = Config.Modifiers[1]
				specimen.Shiny = nil
				specimen.Value = GeodeGen.value(tierId, specimen.Rarity, specimen.Modifier, specimen.Mass, specimen.Shiny)
			end
			local offline = winner ~= nil and Profiles.isOffline(winner)
			if not m.Tutorial and not offline then
				-- Durable decision first; the stored entry is canonical if one already exists.
				local entry = Ledger.record(awardKey, winnerUid, specimen)
				specimen = entry.Specimen or specimen
			end
			local stillHere = winner ~= nil and Profiles.isLoaded(winner)
			if stillHere then
				Ledger.apply(winner :: Player, awardKey, specimen, kind)
				if m.Tutorial then
					local data = Profiles.get(winner :: Player)
					if data then
						data.TutorialStep = math.max(data.TutorialStep, 1)
						Profiles.changed(winner :: Player)
					end
				end
			elseif not m.Tutorial and not offline then
				Ledger.ensurePending(winnerUid, awardKey)
			end
			release()
			-- Stats for everyone who took part (not the practice pile).
			for uid, mem in core.Members do
				local p = playerOf(uid)
				local data = p and Profiles.get(p)
				if data and not m.Tutorial and mem.Active then
					data.Stats.MatchesPlayed += 1
					Profiles.changed(p :: Player, true)
				end
			end
			if matches[m.Key] ~= m then
				return nil
			end
			-- the reveal lasts as long as this rarity's hatch (about 2 s, Rare+ about 6 s slow motion; Config.Hatch)
			local revealFor = PetFlair.revealSeconds(specimen.Rarity)
			phase(m, "Reveal", revealFor)
			-- Owner: rare hatches get fireworks and a gold banner in this server and a banner in every other server
			-- (RareHatch), after the finder's own reveal has played.
			if not m.Tutorial and winner and Config.Pets.AnnounceRarities[specimen.Rarity] then
				local finder: Player, hatched = winner, specimen
				task.delay(revealFor, function()
					RareHatch.announce(finder, hatched)
				end)
			end
			if not m.Tutorial and winner then
				WinnerBoard.record(winner.DisplayName, GeodeGen.displayName(specimen), specimen.Rarity) -- lobby LAST WINNERS (memory only)
			end
			local results = {
				Round = m.Round,
				Winner = winnerUid,
				WinnerName = if winner then winner.DisplayName else "?",
				Kind = kind,
				Specimen = GeodeGen.public(specimen),
				Tier = tierId,
				Elapsed = if m.SearchStart and m.SearchEnd then math.max(0, m.SearchEnd - m.SearchStart) else nil, -- informational only
				Members = {},
				FriendLuck = friendLuck, -- extra Luck the finder had from Roblox friends in the server (informational)
				EventLuck = eventLuck, -- potion + weekend + storm luck before the clamp (informational)
			}
			for uid, mem in core.Members do
				local p = playerOf(uid)
				-- the results row is the ledger snapshot plus who it is (a wider record than HuntLedger.Snapshot)
				local snap: { [string]: any } = HuntLedger.snapshot(m.Ledger, uid, bagOf(p), if uid == winnerUid then specimen.Value else nil) :: any
				snap.UserId = uid
				snap.Name = if p then p.DisplayName else "?"
				snap.Winner = uid == winnerUid
				snap.BonusPet = bonusPets[uid] -- "Common <name>" a helper found in their eggs (nil for most)
				snap.Prize = prizes[uid] -- medal, coins and pet XP for the racers who did not find the pet (shared/HuntFun)
				table.insert(results.Members, snap)
			end
			m.Results = results
			send(m, "Reveal", results)
			task.wait(revealFor)
			if matches[m.Key] == m and m.Phase == "Reveal" then
				phase(m, "Results")
				send(m, "Results", results)
				-- Idle parties must not hold an arena forever.
				task.delay(Config.Match.ResultsReturnSeconds, function()
					if matches[m.Key] == m and m.Round == round and m.Phase == "Results" then
						for uid in table.clone(m.Present) do
							leaveMatch(uid, true)
						end
					end
				end)
			end
			return nil -- explicit value: under --!strict pcall then types as (boolean, any)
		end)
		release()
		if not ok then
			warn("[MatchService] finishing round " .. awardKey .. " failed: " .. tostring(err))
			if matches[m.Key] == m and m.Round == round and (m.Phase == "RewardPending" or m.Phase == "Reveal") then
				for uid in table.clone(m.Present) do
					local p = playerOf(uid)
					if p then
						PartyService.toast(p, "Something went wrong finishing this hunt. Back to the lobby.", "warn")
					end
					leaveMatch(uid, true)
				end
			end
		end
	end)
end

-- Hopper sales: the hunt counters take what the server really sold; a sale after the snapshot only
-- refreshes the bag figures (never the hunt counters) so the results screen is not stale.
Economy.setSaleListener(function(player: Player, count: number, cash: number)
	local m = matches[matchOf[player.UserId] or ""]
	if not m or not m.Ledger then
		return
	end
	HuntLedger.sold(m.Ledger, player.UserId, count, cash)
	if m.Results and (m.Phase == "Results" or m.Phase == "Reveal") then
		for _, row in m.Results.Members do
			if row.UserId == player.UserId then
				local bag = bagOf(player)
				row.BagCount, row.BagCapacity, row.BagValue = bag.Count, bag.Capacity, bag.Value
				Net.event("MatchEvent"):FireClient(player, "ResultsBag", { Round = m.Round, Bag = bag })
			end
		end
	end
end)

local function endMatch(m: Match)
	PracticeBots.clear(m.Key)
	clearMachineModels(m)
	for _, tbl in m.Arena.Tables do
		StationModels.setOwner(tbl, nil, nil)
	end
	matches[m.Key] = nil
	slotBusy[m.Slot] = false
	-- an extra arena that stays empty is taken down (every client holds its parts; Config.Match.ArenaIdleSeconds)
	local slot, built = m.Slot, m.Arena
	if slot > Config.Match.ArenaKeepWarm then
		task.delay(Config.Match.ArenaIdleSeconds, function()
			if not slotBusy[slot] and arenas[slot] == built then
				arenas[slot] = nil
				local root = built.Root
				if typeof(root) == "Instance" then
					root:Destroy()
				end
			end
		end)
	end
	for uid in m.Present do
		matchOf[uid] = nil
	end
	if PartyService.get(m.Party.Id) == m.Party then
		PartyService.setLocked(m.Party, false, nil)
	end
end

-- Teleport mode: the Match place sets this so "back to the lobby" is a teleport. Nil = the
-- Phase 1 single-place behaviour (walk back to the lobby spawn).
local returnHandler: ((Player) -> ())? = nil

function MatchService.setReturnHandler(fn: (Player) -> ())
	returnHandler = fn
end

local function sendToLobby(player: Player)
	local handler = returnHandler
	if handler then
		player:SetAttribute("MatchKey", nil)
		Net.event("MatchEvent"):FireClient(player, "Left", {})
		handler(player)
		return
	end
	player:SetAttribute("MatchKey", nil)
	setFrozen(player, false)
	local char = player.Character
	RacerCollision.apply(char, false)
	if char and lobby.Spawn then
		char:PivotTo(lobby.Spawn * CFrame.new(math.random(-6, 6), 0, math.random(-3, 3)))
	end
	Net.event("MatchEvent"):FireClient(player, "Left", {})
end

-- Removes a member from the hunt (return to lobby, disconnect). Party membership is kept
-- unless they left the game.
function leaveMatch(uid: number, toLobby: boolean)
	local key = matchOf[uid]
	local m = key and matches[key]
	if not m then
		return
	end
	matchOf[uid] = nil
	m.Present[uid] = nil
	m.Rematch[uid] = nil
	if m.Core and (m.Phase == "Countdown" or m.Phase == "Searching") then
		RockService.leave(m, uid) -- forfeits this hunt; resolved rubble stays; carried, queued and plate rocks go back to the pile
		syncMachineModel(m, uid)
	end
	local p = playerOf(uid)
	if p and toLobby then
		sendToLobby(p)
	end
	local anyone = next(m.Present) ~= nil
	if not anyone then
		endMatch(m)
		return
	end
	send(m, "Members", { Members = memberList(m) })
	broadcastMachines(m)
end

-- Match place helpers (Teleport mode). A member leaves the hunt without any lobby walk-back.
function MatchService.removePlayer(uid: number)
	leaveMatch(uid, false)
end

-- A roster member came back to the same live Match server. They watch the current round (their
-- seat in it was given up when they left: no second target, no extra reward) and play again from
-- the next round. Returns false when no hunt of theirs is running any more.
function MatchService.rejoin(uid: number): boolean
	local p = playerOf(uid)
	if not p or matchOf[uid] then
		return p ~= nil and matchOf[uid] ~= nil
	end
	for key, m in matches do
		if table.find(m.Party.Members, uid) then
			m.Present[uid] = true
			matchOf[uid] = key
			p:SetAttribute("MatchKey", key)
			placeAtSpawn(m, p)
			if m.Core then
				Net.event("MatchEvent"):FireClient(p, "Init", initPayload(m))
				if m.Results and (m.Phase == "Results" or m.Phase == "Reveal") then
					Net.event("MatchEvent"):FireClient(p, "Results", m.Results)
				end
			end
			send(m, "Members", { Members = memberList(m) })
			return true
		end
	end
	return false
end

-- Match place: build the single arena up front so arrivals wait on its spawn pads.
function MatchService.prepareArena(slot: number): { [string]: any }
	if not arenas[slot] then
		arenas[slot] = World.buildArena(slot)
	end
	return arenas[slot]
end

function MatchService.phaseOf(uid: number): string?
	local key = matchOf[uid]
	local m = key and matches[key]
	return if m then m.Phase else nil
end

-- The live match a user is in (server-side only; offline tests in tests/server use it to inspect state).
function MatchService.matchFor(uid: number): Match?
	local key = matchOf[uid]
	return if key then matches[key] else nil
end

function MatchService.isBusy(uid: number): boolean
	return matchOf[uid] ~= nil
end

local function freeSlot(): number?
	for i = 1, Config.Match.MaxArenas do
		if not slotBusy[i] then
			return i
		end
	end
	return nil
end

function MatchService.startParty(party: PartyService.Party): (boolean, string?)
	for _, uid in party.Members do
		if matchOf[uid] then
			return false, "Someone is still in a hunt."
		end
		local p = playerOf(uid)
		if not p or not p.Character then
			return false, "Waiting for every member to spawn."
		end
	end
	local slot = freeSlot()
	if not slot then
		return false, "All quarries are busy. Try again in a moment."
	end
	slotBusy[slot] = true
	if not arenas[slot] then
		-- A builder error must not leak the slot or leave half an arena behind (it would block every later start).
		local ok, built = pcall(World.buildArena, slot)
		if not ok then
			slotBusy[slot] = false
			local half = Workspace:FindFirstChild("CT_Rocks_Arena_" .. slot)
			if half then
				half:Destroy()
			end
			warn("[MatchService] arena build failed: " .. tostring(built))
			return false, "Could not build the hunt area. Try again."
		end
		arenas[slot] = built
	end
	local key = HttpService:GenerateGUID(false)
	local m: Match = {
		Key = key,
		Slot = slot,
		Arena = arenas[slot],
		Party = party,
		Round = 0,
		Core = nil,
		Phase = "Waiting",
		EndsAt = 0,
		Tutorial = false,
		Solo = false,
		Present = {},
		Rematch = {},
		SpawnRot = 0,
		Models = {},
		ModelOf = {},
		BayOf = {},
		MachineSent = {},
		LastFlush = 0,
		Results = nil,
		Start = 0,
		FullWarned = {},
	}
	matches[key] = m
	for _, uid in party.Members do
		m.Present[uid] = true
		matchOf[uid] = key
		local p = playerOf(uid) :: Player
		p:SetAttribute("MatchKey", key)
	end
	if PartyService.get(party.Id) == party then
		PartyService.setLocked(party, true, key)
	end
	startRound(m)
	return true, nil
end

local function onRockAction(player: Player, action: any, round: any, rockId: any)
	local key = matchOf[player.UserId]
	local m = key and matches[key]
	if m then
		RockService.action(m, player, action, round, rockId)
	end
end

local function step()
	local t = os.clock()
	for _, m in matches do
		if m.Phase == "Countdown" and now() >= m.EndsAt then
			m.SearchStart = now()
			phase(m, "Searching")
		end
		if m.Phase ~= "Searching" then
			continue
		end
		RockService.step(m, t)
		EggEvents.step(m, t) -- wobble hint
		if m.Phase == "Searching" then
			for uid in m.Present do
				syncMachineModel(m, uid) -- a swap lands here
			end
			broadcastMachines(m)
		end
	end
end

local SYNC_GAP = 2
local lastSync: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function onMatchAction(player: Player, action: any)
	local uid = player.UserId
	local key = matchOf[uid]
	local m = key and matches[key]
	if not m then
		return
	end
	if action == "Return" then
		leaveMatch(uid, true)
	elseif action == "Rematch" then
		if m.Phase == "Results" or m.Phase == "Reveal" then
			m.Rematch[uid] = not m.Rematch[uid]
			send(m, "Members", { Members = memberList(m) })
		end
	elseif action == "StartRematch" then
		if m.Phase ~= "Results" then
			return
		end
		-- leader = party leader if present, else earliest present member
		local leader = m.Party.Leader
		if not m.Present[leader] then
			for _, u in m.Party.Members do
				if m.Present[u] then
					leader = u
					break
				end
			end
		end
		if uid ~= leader then
			return
		end
		for u in m.Present do
			if u ~= leader and not m.Rematch[u] then
				PartyService.toast(player, "Waiting for everyone to tap REMATCH.", "warn")
				return
			end
			local p = playerOf(u)
			local data = p and Profiles.get(p)
			if data and #data.InventoryGeodes >= Profiles.petCapacity(data) then
				PartyService.toast(player, (p :: Player).DisplayName .. "'s Pet Book is full.", "warn")
				return
			end
		end
		startRound(m)
	elseif action == "Sync" then
		-- a full Init is big: at most one per SYNC_GAP seconds per player
		local t = os.clock()
		if t - (lastSync[player] or -math.huge) < SYNC_GAP then
			return
		end
		lastSync[player] = t
		if m.Core then
			Net.event("MatchEvent"):FireClient(player, "Init", initPayload(m))
			EggEvents.resend(m, player) -- the overtime glow, if it is already on
			if m.Results and (m.Phase == "Results" or m.Phase == "Reveal") then
				Net.event("MatchEvent"):FireClient(player, "Results", m.Results)
			end
		end
	end
end

-- Machine install / start-stop from the shop or the bay panel. An install during a batch waits
-- for that batch to resolve (the core keeps it pending), so a swap never resets a cooldown.
function MatchService.machineChanged(player: Player, kind: string, id: string?)
	local uid = player.UserId
	local key = matchOf[uid]
	local m = key and matches[key]
	local core = m and m.Core
	if not m or not core then
		return
	end
	local mem = core.Members[uid]
	if not mem or not mem.Active then
		return
	end
	if kind == "Install" then
		local data = Profiles.get(player)
		if id and data and Config.MachinesEnabled and data.EquipmentOwned[id] then
			core:setMachine(uid, id)
			syncMachineModel(m, uid)
		end
	elseif kind == "Toggle" and mem.Machine then
		core:setMachineRunning(uid, not mem.Running, os.clock())
	end
	broadcastMachines(m)
end

-- Equipped tool changes mid-hunt apply to the next strike; cadence is not reset.
function MatchService.toolChanged(player: Player, tool: string)
	local key = matchOf[player.UserId]
	local m = key and matches[key]
	if m and m.Core then
		m.Core:setTool(player.UserId, tool)
	end
end

-- Studio-only dev shortcut (DevCommands.server, "/endround"): ends the caller's hunt round as if they found the pet
-- egg, through the normal finishRound path (award, results). Refused outside Studio.
function MatchService.devEndRound(player: Player): (boolean, string)
	if not RunService:IsStudio() then
		return false, "studio only"
	end
	local key = matchOf[player.UserId]
	local m = key and matches[key]
	if not m or not m.Core then
		return false, "not in a hunt"
	end
	if m.Phase ~= "Searching" then
		return false, "round is not running (" .. m.Phase .. ")"
	end
	local target = m.Core.TargetId
	finishRound(m, player.UserId, if type(target) == "number" then target else 1)
	return true, "round ended"
end

-- Studio-only dev shortcut (DevCommands.server, "/zone <name>"): shows hunt zone `name` (a zone name such as Forest
-- or a tier id such as Quarry, any case) on an arena. In a hunt it re-skins your own arena (looks only; the round's
-- rules stay); otherwise it skins a free arena and moves you onto its spawn pad. applyZone takes the arena record
-- ({ Root, Center, ... }), never the CT_Rocks_Arena_N model. Refused outside Studio.
function MatchService.devZone(player: Player, name: string): (boolean, string)
	if not RunService:IsStudio() then
		return false, "studio only"
	end
	local valid = {}
	local tierId: string? = nil
	for _, id in Config.TierOrder do
		local zoneName = Config.Tiers[id].Name
		table.insert(valid, string.lower(zoneName))
		if string.lower(name) == string.lower(zoneName) or string.lower(name) == string.lower(id) then
			tierId = id
		end
	end
	if not tierId then
		return false, "unknown zone '" .. name .. "'. Try: " .. table.concat(valid, ", ")
	end
	local zoneName = Config.Tiers[tierId].Name
	local key = matchOf[player.UserId]
	local m = key and matches[key]
	local arena = m and m.Arena
	local move = false
	if not arena then
		local slot = freeSlot()
		if not slot then
			return false, "no free arena"
		end
		if not arenas[slot] then
			local ok, built = pcall(World.buildArena, slot)
			if not ok then
				return false, "arena build failed: " .. tostring(built)
			end
			arenas[slot] = built
		end
		arena = arenas[slot]
		move = true
	end
	local zoneArena = arena :: { [string]: any }
	local ok, err = pcall(function()
		ArenaBuilder.applyZone(zoneArena, tierId)
		return nil
	end)
	if not ok then
		return false, "zone failed: " .. tostring(err)
	end
	if move then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local spawns = zoneArena.Spawns
		if char and root and root:IsA("BasePart") and type(spawns) == "table" and typeof(spawns[1]) == "CFrame" then
			char:PivotTo(spawns[1])
		end
		return true, zoneName .. " shown on an empty arena (you were moved there)"
	end
	return true, zoneName .. " shown on your hunt arena (looks only)"
end

function MatchService.start(lobbyInfo)
	lobby = lobbyInfo
	PartyService.onStart(MatchService.startParty)
	PartyService.setBusyCheck(MatchService.isBusy)
	-- The only gameplay remote of the V3 loop. There is no pile-damage remote any more.
	Net.event("RockAction").OnServerEvent:Connect(onRockAction)
	RockService.onFound(finishRound)
	local actLimit: { [Player]: number } = {}
	Net.event("MatchAction").OnServerEvent:Connect(function(player, action)
		local t = os.clock()
		if t - (actLimit[player] or 0) < 0.25 then
			return
		end
		actLimit[player] = t
		onMatchAction(player, action)
	end)
	-- Start / stop panel on the machine; only the owner's press counts.
	local promptLimit: { [Player]: number } = {}
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if not prompt:GetAttribute("MachineToggle") then
			return
		end
		local t = os.clock()
		if t - (promptLimit[player] or 0) < 0.4 then
			return
		end
		promptLimit[player] = t
		local model = if prompt.Parent then prompt.Parent.Parent else nil
		if not model or model:GetAttribute("OwnerId") ~= player.UserId then
			PartyService.toast(player, "Only the owner can start or stop this machine.", "warn")
			return
		end
		MatchService.machineChanged(player, "Toggle", nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		promptLimit[player] = nil
		actLimit[player] = nil
		RockService.forget(player)
		leaveMatch(player.UserId, false)
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait()
			local key = matchOf[player.UserId]
			local m = key and matches[key]
			if m then
				RockService.characterReset(m, player.UserId) -- a reset drops the basket back on the pile
				placeAtSpawn(m, player)
				setFrozen(player, m.Phase == "Countdown")
			else
				toLobbySpawn(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
		toLobbySpawn(p) -- a character that appeared before the lobby existed
	end
	RacerCollision.start()
	-- Fall safety (about once a second): anyone far below the ground goes back to their hunt spot or the lobby spawn.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and root.Position.Y < -40 then
					local key = matchOf[p.UserId]
					local m = key and matches[key]
					if m then
						placeAtSpawn(m, p)
					else
						toLobbySpawn(p)
					end
				end
			end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return MatchService
