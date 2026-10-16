--!strict
-- Pet Tower server (design: project file plans/pet-tower.md). The one authority for tower runs: who is in, which
-- pets fight, every hit, faint, floor and coin. Clients send intents only ("Open", "Start", "Special", "Next",
-- "Leave", "SetTeam"); the fight itself is shared/TowerRules stepped here.
--
-- Kept in its own files so the egg race code is untouched. Own remotes (ReplicatedStorage.TowerNet) so Net.luau
-- does not change. Solo, endless floors, pet XP levels, free revive, tower-only pet drops (carter's picks).
-- Hooks into main: Profiles defaults (TowerBest, TowerXP, TowerReviveCredits, TowerReceipts), InTower = busy,
-- QuestService "TowerFloors", tower-only species in Config.Minerals, the lobby TowerPortal, StoreService receipt route.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerConfig = require(Shared.TowerConfig)
local TowerRules = require(Shared.TowerRules)
local MapNames = require(Shared.MapNames)
local PetStats = require(Shared.PetStats)
local Profiles = require(script.Parent.Profiles)
local TowerBuilder = require(script.Parent.TowerBuilder)
local Config = require(Shared.Config)
local PetRules = require(Shared.PetRules)
local GeodeGen = require(Shared.GeodeGen)
local EggPerks = require(Shared.EggPerks)
local QuestService = require(script.Parent.QuestService)
local Workspace = game:GetService("Workspace")

local TowerService = {}

type Run = {
	Key: string,
	Slot: number,
	Members: { Player },
	Rules: TowerRules.Run,
	Arena: Model,
	Origin: CFrame,
	Coins: { [number]: number },
	Idle: number, -- seconds waiting on NEXT/LEAVE after a floor ends
	PromptUntil: number?, -- os.clock() until which a revive purchase prompt is open (the idle clock waits)
	SendIn: number,
	Pending: { TowerRules.Event },
	Specs: { [string]: any }, -- pet unit id -> look data for the client model
	PetIds: { [string]: any }, -- pet unit id -> saved pet Id (for XP)
	Revives: number,
	PaidRevives: number,
	Xp: number, -- XP each team pet earned this climb
	LostPaid: boolean,
	HoldLeft: number?, -- seconds before this floor's fight starts (TowerRules.introHold: the theme title shows first)
}

local runs: { [string]: Run } = {}
local runOf: { [Player]: Run } = {}
local lastAction: { [Player]: number } = {}
local returnCF: { [Player]: CFrame } = {}
local serial = 0
local action: RemoteEvent
local event: RemoteEvent

local ACTION_GAP = 0.15 -- seconds between accepted intents per player
local IDLE_LIMIT = 45 -- seconds on a floor-end card before the run closes by itself
local SEND_EVERY = 0.2 -- hit batches per second cap

local function inventory(player: Player): { any }
	local data = Profiles.get(player)
	local inv = data and data.InventoryGeodes
	return if type(inv) == "table" then inv else {}
end

local function petById(player: Player, id: string): any?
	for _, g in inventory(player) do
		if g.Id == id then
			return g
		end
	end
	return nil
end

local function xpOf(player: Player, petId: any): number
	local data = Profiles.get(player)
	local book = data and data.TowerXP
	local x = if type(book) == "table" then book[tostring(petId)] else nil
	return if type(x) == "number" and x == x then math.max(x, 0) else 0
end

local function score(g: any, xp: number?): number
	local s = PetStats.roll(g, xp)
	return s.Power * 3 + s.Health * 0.5 + s.Speed * 0.2
end

-- ONE team (carter 2026-10-15): the saved EquippedPets both follow the player and fight (tower, Pet Battle); no
-- team yet = their strongest pets.
local function teamOf(player: Player): { any }
	local out = {}
	local data = Profiles.get(player)
	local chosen: { string } = if data and type(data.EquippedPets) == "table" then data.EquippedPets else {}
	for _, id in chosen do
		local g = petById(player, id)
		if g and #out < TowerConfig.TeamSize then
			table.insert(out, g)
		end
	end
	if #out == 0 then
		local all = table.clone(inventory(player))
		table.sort(all, function(a, b)
			return score(a, xpOf(player, a.Id)) > score(b, xpOf(player, b.Id))
		end)
		for i = 1, math.min(TowerConfig.TeamSize, #all) do
			table.insert(out, all[i])
		end
	end
	return out
end

-- Sets the one shared team (ids already checked as owned), or the strongest pets for nil (PetRules.best, the same
-- pick as MY PETS' EQUIP BEST).
local function setShared(player: Player, ids: { string }?)
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) then
		return
	end
	local list = ids
	if list == nil or #list == 0 then
		list = PetRules.best(data.InventoryGeodes, Config.Pets.Slots, if type(data.TowerXP) == "table" then data.TowerXP else nil)
	end
	local kept = {}
	for _, id in list :: { string } do
		if #kept < Config.Pets.Slots then
			table.insert(kept, id)
		end
	end
	data.EquippedPets = kept
	Profiles.changed(player)
end

local function best(player: Player): number
	local data = Profiles.get(player)
	local b = data and data.TowerBest
	return if type(b) == "number" and b == b then math.clamp(math.floor(b), 0, 1e6) else 0
end

-- Every XP gain (tower, Pet Battle, training) passes here: +10% per full Pet Book page (EggPerks.xpMult). `raw` =
-- an exact amount (dev /xp, /maxpet), no bonus.
local function addXp(player: Player, petId: any, amount: number, raw: boolean?)
	local data = Profiles.get(player)
	if not data or amount <= 0 or not petById(player, tostring(petId)) then
		return -- a pet sold mid-climb earns nothing (no XP rows for pets that are gone)
	end
	if not raw then
		amount = math.floor(amount * EggPerks.xpMult(data.DiscoveryIndex) + 0.5)
	end
	if type(data.TowerXP) ~= "table" then
		data.TowerXP = {}
	end
	local key = tostring(petId)
	if raw or type(data.EquippedPets) ~= "table" then
		data.TowerXP[key] = xpOf(player, petId) + amount
		return
	end
	-- a team pet at MAX passes the XP it can't use to its teammates (PetRules.spillXp)
	local gains = PetRules.spillXp(key, amount, data.EquippedPets, function(id: string): number
		local g = petById(player, id)
		return if g then PetStats.xpForLevel(PetStats.cap(g)) - xpOf(player, id) else 0
	end)
	for id, gain in gains do
		data.TowerXP[id] = xpOf(player, id) + gain
	end
end

local function petView(g: any, xp: number?)
	local s = PetStats.roll(g, xp)
	local sp = PetStats.special(s.Special)
	return {
		Id = g.Id,
		Name = PetRules.label(g), -- the Pet Book name (variant, nickname), not just the species
		Spec = { Mineral = g.Mineral, Rarity = g.Rarity, Modifier = g.Modifier, Formation = g.Formation, Mass = g.Mass, Seed = g.Seed, Evolve = g.Evolve },
		Rarity = g.Rarity,
		Power = s.Power,
		Health = s.Health,
		Speed = s.Speed,
		Grade = s.Grade,
		Level = s.Level,
		Element = s.Element,
		Basic = s.Basic,
		Move = s.Move,
		Special = if sp then sp.Name else s.Special,
	}
end

local function roster(player: Player)
	local pets = {}
	for _, g in inventory(player) do
		table.insert(pets, petView(g, xpOf(player, g.Id)))
	end
	local chosen = {}
	for _, g in teamOf(player) do
		table.insert(chosen, g.Id)
	end
	event:FireClient(player, {
		Kind = "Roster",
		Pets = pets,
		Team = chosen,
		Best = best(player),
		Checkpoint = TowerRules.checkpoint(best(player)),
	})
end

-- Open / SetTeam / EquipBest each resend the whole roster (stats for every pet): at most one send per
-- ROSTER_GAP per player, a burst collapses into one delayed send.
local ROSTER_GAP = 1
local rosterAt: { [Player]: number } = {}
local rosterQueued: { [Player]: boolean } = {}
local function rosterSoon(player: Player)
	local left = (rosterAt[player] or -math.huge) + ROSTER_GAP - os.clock()
	if left <= 0 then
		rosterAt[player] = os.clock()
		roster(player)
	elseif not rosterQueued[player] then
		rosterQueued[player] = true
		task.delay(left, function()
			rosterQueued[player] = nil
			if player.Parent then
				rosterAt[player] = os.clock()
				roster(player)
			end
		end)
	end
end

local function unitsView(r: TowerRules.Run, specs: { [string]: any })
	local out = {}
	for _, list in { r.Pets, r.Mobs } do
		for _, u in list do
			table.insert(out, {
				Id = u.Id,
				Owner = u.Owner,
				Kind = u.Kind,
				Name = u.Name,
				Max = u.Max,
				Hp = u.Hp,
				Element = u.Element,
				Boss = u.Boss,
				Spec = specs[u.Id],
			})
		end
	end
	return out
end

local function broadcast(run: Run, msg: any)
	for _, p in run.Members do
		event:FireClient(p, msg)
	end
end

local function sendFloor(run: Run)
	local theme = TowerRules.theme(run.Rules.Floor)
	TowerBuilder.theme(run.Arena, theme, run.Origin)
	local hold = TowerRules.introHold(run.Rules.Floor, run.Rules.Wave)
	run.HoldLeft = if hold > 0 then hold else nil
	broadcast(run, {
		Hold = hold,
		Theme = theme.Name,
		Kind = "Floor",
		Floor = run.Rules.Floor,
		Wave = run.Rules.Wave,
		Waves = #run.Rules.Waves,
		Boss = TowerRules.isBoss(run.Rules.Floor),
		Units = unitsView(run.Rules, run.Specs),
		Origin = run.Origin,
	})
end

local function moveTo(player: Player, cf: CFrame)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if char and root then
		char:PivotTo(cf)
	end
end

-- The lobby spot to put a player back on. Someone who walked in through the tower portal would land inside it
-- (and their camera inside its glow), so near the portal they come out at the exit instead: the lobby's
-- `TowerExit` part (stair landing in front of the gate; its front faces the way out) when the map has one, else a
-- few studs out along the portal's front (-LookVector side). Height comes from the ground under that spot, so the
-- player never lands inside rock. Anyone who entered elsewhere (the TOWER button) goes back where they were.
local function ground(pos: Vector3, ignore: Instance?): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	if ignore then
		table.insert(skip, ignore) -- the TowerExit marker itself is not ground
	end
	params.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else nil
end

local function lobbySpot(back: CFrame): CFrame
	local portal: BasePart? = nil
	local exit: BasePart? = nil
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("TowerPortal") == true then
				local flat = Vector3.new(back.Position.X - d.Position.X, 0, back.Position.Z - d.Position.Z)
				if flat.Magnitude <= math.max(d.Size.X, d.Size.Z) * 0.5 + 20 then
					portal = d
				end
			elseif d.Name == MapNames.TowerExit or d:GetAttribute("TowerExit") == true then
				exit = d
			end
		end
	end
	if not portal then
		return back
	end
	local pos: Vector3, out: Vector3
	if exit then
		pos = exit.Position
		out = Vector3.new(exit.CFrame.LookVector.X, 0, exit.CFrame.LookVector.Z)
	else
		local p = portal :: BasePart
		out = Vector3.new(-p.CFrame.LookVector.X, 0, -p.CFrame.LookVector.Z)
		if out.Magnitude < 0.1 then
			out = Vector3.new(-back.LookVector.X, 0, -back.LookVector.Z)
		end
		pos = p.Position + out.Unit * (math.min(p.Size.X, p.Size.Z) * 0.5 + 12)
	end
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.zAxis
	local g = ground(pos, exit)
	local at = if g then Vector3.new(pos.X, g.Y + 3.5, pos.Z) else Vector3.new(pos.X, back.Position.Y, pos.Z)
	return CFrame.lookAt(at, at + out)
end

local function closeRun(run: Run, why: string)
	if runs[run.Key] ~= run then
		return
	end
	runs[run.Key] = nil
	for _, p in run.Members do
		if runOf[p] == run then
			runOf[p] = nil
			p:SetAttribute("InTower", nil)
			event:FireClient(p, { Kind = "Closed", Why = why })
			local back = returnCF[p]
			returnCF[p] = nil
			if back and p.Parent then
				moveTo(p, lobbySpot(back))
			end
		end
	end
	TowerBuilder.free(run.Slot, run.Arena)
end

-- A tower-only pet from a boss floor. Granted only when the core game lists the species (Config.Minerals),
-- so the drop stays off until those pets exist in the collection.
-- Pity (TowerConfig.Pity): profile TowerPity counts boss clears without a drop; it raises the next boss's chance and
-- resets on a drop. A tower pet the player never had is favoured (TowerRules.dropSpecies with the discovery index).
local function rollDrop(player: Player, floor: number): string?
	if not TowerRules.isBoss(floor) then
		return nil
	end
	local data = Profiles.get(player)
	if not data then
		return nil
	end
	if #data.InventoryGeodes >= Profiles.petCapacity(data) then
		-- Pet Book full: no drop (the pity counter is kept as it is), and the player is told why
		pcall(function()
			require(Shared.Net).event("Toast"):FireClient(player, "Pet Book full! A boss pet could not drop. Sell pets to make room.", "warn")
		end)
		return nil
	end
	local misses = tonumber(data.TowerPity) or 0
	if math.random() >= TowerRules.dropChance(floor, misses) then
		data.TowerPity = TowerRules.pityAfter(misses, false)
		return nil
	end
	local species = TowerRules.dropSpecies(floor, math.random(), data.DiscoveryIndex)
	if species == nil or type(Config.Minerals) ~= "table" or Config.Minerals[species] == nil then
		data.TowerPity = TowerRules.pityAfter(misses, false)
		return nil
	end
	local rng = Random.new()
	local rarity = GeodeGen.pickWeighted(rng, Config.Rarities, TowerConfig.Drop.RarityWeights)
	local modifier = GeodeGen.pickWeighted(rng, Config.Modifiers, Config.ModifierWeights)
	local formation = GeodeGen.pickWeighted(rng, Config.Formations, Config.FormationWeights)
	-- priced like a hunt pet of the player's best unlocked zone (never the last zone's prices from floor 5)
	local tier = TowerRules.dropTier(Config.TierOrder, data.UnlockedTiers)
	local mass = GeodeGen.rollMass(rng)
	local id = "T" .. player.UserId .. "_" .. os.time() .. "_" .. rng:NextInteger(1, 1e6)
	local specimen = {
		Id = id,
		MatchKey = "tower",
		Tier = tier,
		Mineral = species,
		Rarity = rarity,
		Formation = formation,
		Modifier = modifier,
		Mass = mass,
		Seed = rng:NextInteger(1, 2 ^ 30),
		Value = if Config.Tiers[tier] then GeodeGen.value(tier, rarity, modifier, mass) else 0,
		ConfigVersion = Config.Version,
		Found = os.time(),
		Favorite = false,
		Solo = true,
	}
	if Profiles.grantSpecimen(player, "tower:" .. id, specimen, "Tower") then
		data.TowerPity = TowerRules.pityAfter(misses, true)
		return species
	end
	data.TowerPity = TowerRules.pityAfter(misses, false)
	return nil
end

local function grant(run: Run, floor: number, cleared: boolean): (number, string?)
	local coins = if cleared then TowerRules.reward(floor) else 0
	local xp = TowerRules.xp(floor, cleared)
	local drop: string? = nil
	run.Xp += xp
	for _, p in run.Members do
		local data = Profiles.get(p)
		if data and runOf[p] == run and not Profiles.isReleased(p) then
			data.Cash = (tonumber(data.Cash) or 0) + coins
			if cleared and floor > best(p) then
				data.TowerBest = floor
			end
			for unitId, petId in run.PetIds do
				if string.sub(unitId, 1, #tostring(p.UserId) + 1) == p.UserId .. ":" then
					addXp(p, petId, xp)
				end
			end
			if cleared then
				drop = rollDrop(p, floor)
				QuestService.bump(p, "TowerFloors", 1)
			end
			run.Coins[p.UserId] = (run.Coins[p.UserId] or 0) + coins
			Profiles.changed(p)
		end
	end
	return coins, drop
end

local function endFloor(run: Run)
	local r = run.Rules
	local cleared = r.State == "Cleared"
	-- A loss pays its XP once per floor (a revive and second loss on the same floor pays nothing more).
	local coins, drop = 0, nil
	if cleared or not run.LostPaid then
		coins, drop = grant(run, r.Floor, cleared)
	end
	if not cleared then
		run.LostPaid = true
	end
	run.Idle = 0
	for _, p in run.Members do
		event:FireClient(p, {
			Kind = "FloorEnd",
			Result = r.State,
			Floor = r.Floor,
			Coins = coins,
			RunCoins = run.Coins[p.UserId] or 0,
			Best = best(p),
			Xp = run.Xp,
			Drop = if drop then (TowerConfig.PetNames[drop] or drop) else nil,
			Revives = math.max(TowerConfig.Revive.Free - run.Revives, 0),
			Paid = if TowerConfig.Revive.ProductId > 0 then math.max(TowerConfig.Revive.MaxPaid - run.PaidRevives, 0) else 0,
		})
	end
end

local function hpView(r: TowerRules.Run)
	local hp = {}
	for _, list in { r.Pets, r.Mobs } do
		for _, u in list do
			hp[u.Id] = { u.Hp, u.Shield }
		end
	end
	return hp
end

local function flush(run: Run, list: { TowerRules.Event })
	if #list == 0 then
		return
	end
	broadcast(run, { Kind = "Events", List = list, Hp = hpView(run.Rules), Meters = run.Rules.Meters, Wave = run.Rules.Wave })
end

local function startRun(leader: Player)
	if runOf[leader] or leader:GetAttribute("MatchKey") ~= nil or leader:GetAttribute("InBattle") ~= nil or not Profiles.isLoaded(leader) then
		return
	end
	-- Solo (carter): one player and their pets.
	local members = { leader }
	local list: { TowerRules.TeamPet } = {}
	local specs = {}
	local petIds = {}
	local start = math.huge
	for _, p in members do
		for _, g in teamOf(p) do
			local id = p.UserId .. ":" .. tostring(g.Id)
			local xp = xpOf(p, g.Id)
			table.insert(list, { Owner = p.UserId, Id = id, Name = PetRules.label(g), Xp = xp, Pet = g })
			specs[id] = petView(g).Spec
			petIds[id] = g.Id
		end
		start = math.min(start, TowerRules.checkpoint(best(p)))
	end
	if #list == 0 then
		event:FireClient(leader, { Kind = "Notice", Text = "Hatch a pet first! Pets fight in the tower." })
		return
	end
	local slot, arena, origin = TowerBuilder.claim()
	serial += 1
	local run: Run = {
		Key = "tower" .. serial,
		Slot = slot,
		Members = members,
		Rules = TowerRules.newRun(list, start),
		Arena = arena,
		Origin = origin,
		Coins = {},
		Idle = 0,
		SendIn = 0,
		Pending = {},
		Specs = specs,
		PetIds = petIds,
		Revives = 0,
		PaidRevives = 0,
		Xp = 0,
		LostPaid = false,
	}
	runs[run.Key] = run
	for i, p in members do
		runOf[p] = run
		p:SetAttribute("InTower", true)
		local char = p.Character
		if char then
			returnCF[p] = char:GetPivot()
		end
		moveTo(p, TowerBuilder.standCFrame(origin, i))
	end
	sendFloor(run)
end

local function leave(player: Player, stay: boolean?)
	local run = runOf[player]
	if not run then
		return
	end
	if stay then
		returnCF[player] = nil -- a hunt took them; don't pull them back to the lobby
	end
	if #run.Members <= 1 then
		closeRun(run, "Left")
		return
	end
	-- One member leaves: their pets leave the fight, the rest keep climbing.
	local idx = table.find(run.Members, player)
	if idx then
		table.remove(run.Members, idx)
	end
	for _, u in run.Rules.Pets do
		if u.Owner == player.UserId then
			u.Hp = 0
		end
	end
	run.Rules.Meters[player.UserId] = nil
	runOf[player] = nil
	player:SetAttribute("InTower", nil)
	event:FireClient(player, { Kind = "Closed", Why = "Left" })
	local back = returnCF[player]
	returnCF[player] = nil
	if back then
		moveTo(player, lobbySpot(back))
	end
	if run.Rules.State == "Fighting" then
		local ev = {}
		local alive = false
		for _, u in run.Rules.Pets do
			alive = alive or u.Hp > 0
		end
		if not alive then
			run.Rules.State = "Lost"
			table.insert(ev, { Kind = "Lost" })
			flush(run, ev)
			endFloor(run)
		end
	end
end

-- BuyRevive may re-open the Roblox purchase prompt at most once per PROMPT_GAP seconds (weak keys: leavers drop out).
local PROMPT_GAP = 3
local PROMPT_HOLD = 120 -- at most this long the idle clock waits on an open revive prompt
-- Each start builds a whole arena (TowerBuilder.claim) and a leave destroys it, so arena builds are spaced per
-- player: at most one per START_GAP seconds. A Start inside the gap is never dropped; it waits for the gap (one
-- waiting Start per player; a Leave calls it off), so Start/Leave spam cannot rebuild arenas several times a second.
local START_GAP = 3
local lastStart: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local pendingStart: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local startToken = 0

local function requestStart(player: Player)
	if runOf[player] or pendingStart[player] then
		return -- already climbing, or a start is already on its way
	end
	local function go()
		lastStart[player] = os.clock()
		startRun(player)
	end
	local wait = (lastStart[player] or -math.huge) + START_GAP - os.clock()
	if wait <= 0 then
		go()
		return
	end
	startToken += 1
	local my = startToken
	pendingStart[player] = my
	task.delay(wait, function()
		if pendingStart[player] ~= my then
			return
		end
		pendingStart[player] = nil
		if player.Parent and not runOf[player] then
			go()
		end
	end)
end
local lastPrompt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function onAction(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.Op) ~= "string" then
		return
	end
	local now = os.clock()
	local op = msg.Op
	-- Only the team edits (each one scans the inventory) are rate-dropped. Every other op is guarded by state
	-- instead (Start: one arena build per START_GAP, deferred, never dropped; Next/Revive: floor state; Special:
	-- the meter; BuyRevive: PROMPT_GAP; Open: rosterSoon), so a burst of team edits can never swallow a Start.
	if op == "SetTeam" or op == "EquipBest" then
		if now - (lastAction[player] or 0) < ACTION_GAP then
			return
		end
		lastAction[player] = now
	end
	local run = runOf[player]
	if op == "Open" then
		rosterSoon(player)
	elseif op == "SetTeam" then
		if run or type(msg.Pets) ~= "table" or #msg.Pets > TowerConfig.TeamSize * 2 then
			return -- oversized lists are refused before any inventory scan
		end
		local ids, seen = {}, {}
		for i = 1, #msg.Pets do
			local id = msg.Pets[i]
			if #ids >= TowerConfig.TeamSize then
				break
			end
			if type(id) == "string" and not seen[id] and petById(player, id) then
				seen[id] = true
				table.insert(ids, id)
			end
		end
		setShared(player, ids)
		rosterSoon(player)
	elseif op == "EquipBest" then
		-- No saved picks = the strongest pets (teamOf).
		if not run then
			setShared(player, nil)
			rosterSoon(player)
		end
	elseif op == "Start" then
		requestStart(player)
	elseif op == "Special" then
		if run then
			local wave = run.Rules.Wave
			local ok, ev = TowerRules.useSpecial(run.Rules, player.UserId, math.random())
			if ok then
				for _, e in ev do
					table.insert(run.Pending, e)
				end
				flush(run, run.Pending)
				run.Pending = {}
				if run.Rules.State == "Fighting" and run.Rules.Wave ~= wave then
					sendFloor(run)
				end
				if run.Rules.State ~= "Fighting" then
					endFloor(run)
				end
			end
		end
	elseif op == "Next" then
		-- Any member may continue once the floor is cleared; a lost run can only be left.
		if run and run.Rules.State == "Cleared" then
			run.LostPaid = false
			TowerRules.startFloor(run.Rules, run.Rules.Floor + 1)
			sendFloor(run)
		end
	elseif op == "Revive" then
		-- Free revive(s) per climb (TowerConfig.Revive.Free). Paid revives are "BuyRevive" below (Robux product).
		if run and run.Rules.State == "Lost" and run.Revives < TowerConfig.Revive.Free and TowerRules.revive(run.Rules) then
			run.Revives += 1
			run.Idle = 0
			sendFloor(run)
		end
	elseif op == "BuyRevive" then
		-- Uses a revive the player already paid for, else opens the Roblox purchase prompt. Nothing is granted
		-- by the prompt; TowerService.processReceipt adds the credit.
		if run and run.Rules.State == "Lost" and TowerConfig.Revive.ProductId > 0 and run.PaidRevives < TowerConfig.Revive.MaxPaid then
			if not TowerService.useCredit(player) and now - (lastPrompt[player] or 0) >= PROMPT_GAP then
				lastPrompt[player] = now
				-- the idle clock waits while the Roblox purchase prompt is open (capped, so a lost prompt cannot hold
				-- an arena forever); the receipt or the prompt closing ends the wait
				run.Idle = 0
				run.PromptUntil = now + PROMPT_HOLD
				pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, TowerConfig.Revive.ProductId)
			end
		end
	elseif op == "Leave" then
		pendingStart[player] = nil -- a Start still waiting for its gap is called off
		leave(player)
	end
end

local function credits(data: any): number
	local c = data and data.TowerReviveCredits
	return if type(c) == "number" and c == c then math.max(math.floor(c), 0) else 0
end

-- Spends one paid revive credit on the player's lost floor. False when there is nothing to spend or revive.
function TowerService.useCredit(player: Player): boolean
	local run = runOf[player]
	local data = Profiles.get(player)
	if not run or not data or credits(data) <= 0 then
		return false
	end
	if run.Rules.State ~= "Lost" or run.PaidRevives >= TowerConfig.Revive.MaxPaid then
		return false
	end
	if not TowerRules.revive(run.Rules) then
		return false
	end
	data.TowerReviveCredits = credits(data) - 1
	run.PaidRevives += 1
	run.Idle = 0
	Profiles.changed(player)
	sendFloor(run)
	return true
end

-- Revive Developer Product receipt. StoreService owns MarketplaceService.ProcessReceipt and must hand receipts
-- for TowerConfig.Revive.ProductId here. A receipt adds one saved credit (once per PurchaseId), answered
-- PurchaseGranted only after the save; the credit is spent at once when the player is on a lost floor, else kept.
function TowerService.processReceipt(info: { PlayerId: number, PurchaseId: string, ProductId: number }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local data = player and Profiles.get(player)
	if not player or not data or Profiles.isReleased(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if type(data.TowerReceipts) ~= "table" then
		data.TowerReceipts = {}
	end
	local key = tostring(info.PurchaseId)
	if not table.find(data.TowerReceipts, key) then
		table.insert(data.TowerReceipts, key)
		while #data.TowerReceipts > 50 do
			table.remove(data.TowerReceipts, 1)
		end
		data.TowerReviveCredits = credits(data) + 1
		Profiles.changed(player, true)
	end
	if not Profiles.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	TowerService.useCredit(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio-only dev shortcut (DevCommands.server, "/boss N"): jumps the caller's tower run to boss floor N (rounded up
-- to the next boss floor; no N = the next boss floor above the current one). Refused outside Studio.
function TowerService.devJump(player: Player, floor: number?): (boolean, string)
	if not RunService:IsStudio() then
		return false, "studio only"
	end
	local run = runOf[player]
	if not run then
		return false, "enter the tower first"
	end
	local every = TowerConfig.BossEvery
	local want = if floor then math.max(math.floor(floor), 1) else run.Rules.Floor + 1
	local boss = math.ceil(want / every) * every
	run.Idle = 0
	run.LostPaid = false
	TowerRules.startFloor(run.Rules, boss)
	sendFloor(run)
	return true, "boss floor " .. boss
end

-- Shared with Pet Battle / training (PvpService): the same team, XP book and pet card data as the tower.
function TowerService.team(player: Player): { any }
	return teamOf(player)
end
function TowerService.setTeam(player: Player, ids: { string }?)
	setShared(player, ids)
end
TowerService.xpOf = xpOf
TowerService.addXp = addXp
TowerService.petView = petView
TowerService.petById = petById
function TowerService.inTower(player: Player): boolean
	return runOf[player] ~= nil
end

function TowerService.start()
	local folder = Instance.new("Folder")
	folder.Name = "TowerNet"
	action = Instance.new("RemoteEvent")
	action.Name = "TowerAction"
	action.Parent = folder
	event = Instance.new("RemoteEvent")
	event.Name = "TowerEvent"
	event.Parent = folder
	folder.Parent = ReplicatedStorage

	action.OnServerEvent:Connect(onAction)
	-- The lobby's TowerPortal (MapHooks tags it with the TowerPortal attribute): walking in opens the team picker.
	local touchedAt: { [Player]: number } = {}
	local function hookPortal(d: Instance)
		if d:IsA("BasePart") and d:GetAttribute("TowerPortal") == true and not d:GetAttribute("TowerHooked") then
			d:SetAttribute("TowerHooked", true)
			d.Touched:Connect(function(hit)
				local char = hit.Parent
				local p = char and Players:GetPlayerFromCharacter(char)
				if not p or runOf[p] or p:GetAttribute("MatchKey") ~= nil then
					return
				end
				local now = os.clock()
				if now - (touchedAt[p] or 0) < 4 then
					return
				end
				touchedAt[p] = now
				roster(p)
			end)
		end
	end
	for _, d in Workspace:GetDescendants() do
		hookPortal(d)
	end
	Workspace.DescendantAdded:Connect(hookPortal)
	-- The attribute can be set after the part is added (MapHooks runs once the map is in place).
	task.delay(10, function()
		for _, d in Workspace:GetDescendants() do
			hookPortal(d)
		end
	end)
	-- A closed or failed revive prompt brings the "fainted" card back (paid ones revive via the receipt).
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local p = Players:GetPlayerByUserId(userId)
		local run = p and runOf[p]
		if run and productId == TowerConfig.Revive.ProductId then
			run.PromptUntil = nil
			run.Idle = 0 -- a fresh idle window from the moment the prompt closed
			if not purchased and run.Rules.State == "Lost" then
				endFloor(run)
			end
		end
	end)
	local function watch(p: Player)
		-- A hunt that starts for a climber takes them out of the tower; a respawn puts them back on the floor.
		p:GetAttributeChangedSignal("MatchKey"):Connect(function()
			if p:GetAttribute("MatchKey") ~= nil and runOf[p] then
				leave(p, true)
			end
		end)
		p.CharacterAdded:Connect(function()
			local run = runOf[p]
			if run then
				task.defer(function()
					local i = table.find(run.Members, p)
					if i and runOf[p] == run then
						moveTo(p, TowerBuilder.standCFrame(run.Origin, i))
					end
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		leave(p)

		lastAction[p] = nil
		touchedAt[p] = nil
		rosterAt[p] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < TowerConfig.Tick then
			return
		end
		local step = math.min(acc, 0.5)
		acc = 0
		for _, run in runs do
			local r = run.Rules
			local hold = run.HoldLeft
			if r.State == "Fighting" and hold then
				-- the theme title is on screen: the pets wait for it (no hit lands under the pill)
				run.HoldLeft = if hold - step > 0 then hold - step else nil
			elseif r.State == "Fighting" then
				local before = r.Wave
				for _, e in TowerRules.step(r, step) do
					table.insert(run.Pending, e)
				end
				run.SendIn -= step
				-- Hit batches go out at most every SEND_EVERY; wave and floor changes go out at once.
				local changed = r.Wave ~= before or r.State ~= "Fighting"
				if #run.Pending > 0 and (run.SendIn <= 0 or changed) then
					flush(run, run.Pending)
					run.Pending = {}
					run.SendIn = SEND_EVERY
				end
				if r.Wave ~= before and r.State == "Fighting" then
					sendFloor(run)
				end
				if r.State ~= "Fighting" then
					endFloor(run)
				end
			elseif not (run.PromptUntil and os.clock() < run.PromptUntil) then
				run.Idle += step
				if run.Idle >= IDLE_LIMIT then
					closeRun(run, "Idle")
				end
			end
		end
	end)
end

return TowerService
