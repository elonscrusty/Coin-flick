--!strict
-- Player profiles: load with a session lock, autosave, release on leave and on shutdown.
-- Rules: never save a default profile over data we could not read; never save a profile we
-- do not hold the lock for. Studio uses separate "_Studio" stores. If DataStores are not
-- reachable in Studio (API access off), the player gets a session-only profile that is never
-- written, and the HUD shows "SAVES OFF".

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Cosmetics = require(Shared.Cosmetics)
local Materials = require(Shared.Materials)
local ProgressConfig = require(Shared.ProgressConfig)
local Quests = require(Shared.Quests)
local Retention = require(Shared.Retention)
local Hangout = require(Shared.Hangout)
local PetRules = require(Shared.PetRules)
local PetStats = require(Shared.PetStats)

-- A loaded save (reconciled against the defaults below); fields are read loosely, as saved.
type Data = { [string]: any }
local PetFlair = require(Shared.PetFlair)
local RobuxConfig = require(Shared.RobuxConfig)
local EggPerks = require(Shared.EggPerks)
local HuntFun = require(Shared.HuntFun)
local LaunchPerks = require(Shared.LaunchPerks)
local Net = require(Shared.Net)

local Profiles = {}

local IS_STUDIO = RunService:IsStudio()
local SUFFIX = if IS_STUDIO then "_Studio" else ""
local JOB = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local store: DataStore? = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.Save.StoreName .. SUFFIX)
end)

local loaded: { [Player]: any } = {}
local releasing: { [Player]: boolean } = {}
local loadAttempts: number = Config.Save.LoadAttempts
local joinGate: ((Player) -> boolean)? = nil
local loading: { [Player]: boolean } = {}
local holds: { [Player]: number } = {} -- award code holding a profile open (hold / unhold)
local changedHandlers: { (Player) -> () } = {}
local loadedHandlers: { (Player, any) -> () } = {}
local speciesHandlers: { (Player, string, number) -> () } = {}
local shutdownHandlers: { () -> () } = {} -- final writes BindToClose waits for (leaderboards, ledger)
-- run (spawned) after every committed save of a player's profile, with the os.clock() the winning attempt started at
local savedHandlers: { (Player, number) -> () } = {}
local shuttingDown = false -- BindToClose started: retries back off briefly so every save fits the shutdown budget

function Profiles.isStudio(): boolean
	return IS_STUDIO
end

function Profiles.defaults(): { [string]: any }
	return {
		Schema = Config.Save.SchemaVersion,
		Cash = 0,
		RubbleByTier = {},
		EquipmentOwned = { Hammer = true },
		EquippedHandheld = "Hammer",
		InstalledMachine = nil,
		CapacityTier = 1,
		UnlockedTiers = { Gravel = true },
		InventoryGeodes = {},
		DisplayAssignments = {},
		-- display picks the owner set to roam (owner ask 2026-10-13): they walk around the plot pen instead of a dome.
		-- Always a subset of DisplayAssignments (EconomyService "Roam"); added without a schema bump.
		RoamPets = {},
		DisplayCapacity = 1,
		DiscoveryIndex = {},
		-- mineral -> rarity -> count: the index silhouettes (Discovery index, mineral x rarity)
		DiscoveryRarity = {},
		-- Robux cosmetics only: Owned, Equipped (kind -> id), Receipts (PurchaseId keys, idempotent grants)
		Cosmetics = Cosmetics.empty(),
		-- Material Discoveries: Found (category -> true) and Counts (category -> finished ordinary crushes).
		-- Presentation only; added without a schema bump (reconcile fills it for older profiles).
		Materials = Materials.empty(),
		TutorialStep = 0, -- 0 until the practice pile is done
		-- Onboarding steps, tracked apart from the prize so the order can vary and nothing repeats:
		-- Started (practice begun), Cracked (an ordinary rock), Geode (first find), Sold (rubble
		-- sold), Displayed (a specimen in the gallery), Goal (saw the cash / first upgrade goal).
		Onboard = { Started = false, PickedUp = false, Deposited = false, Cracked = false, Geode = false, Sold = false, Displayed = false, Goal = false, Skipped = false },
		Settings = { Music = 0.6, Sfx = 0.8, CameraSensitivity = 0.5, ReducedMotion = false, LowEffects = false, Hints = true },
		Stats = { SoloFinds = 0, MultiplayerWins = 0, MatchesPlayed = 0, RocksCracked = 0, CashEarned = 0, BestGeodeValue = 0 },
		RecentAwardIds = {},
		PendingAwards = {},
		-- Find The Pet: specimen ids of the pets following the player (max Config.Pets.Slots); StarterPet = the free
		-- starter pet every player hatches once (Rare or better, PetService.ensureStarter).
		EquippedPets = {},
		StarterPet = false,
		TowerBest = 0, -- highest pet tower floor cleared (TowerService)
		TowerXP = {}, -- pet id -> tower XP (TowerService owns levels)
		TowerReviveCredits = 0, -- bought tower revives not yet used (TowerService)
		TowerReceipts = {}, -- PurchaseIds already granted for tower revives
		-- Tower pet pity (TowerRules.dropChance / TowerConfig.Pity): boss clears in a row without a pet drop.
		TowerPity = 0,
		-- Pet Battle (PvpService): trophies, current and best win streak, wins and losses.
		Pvp = { Trophies = 0, Streak = 0, BestStreak = 0, Wins = 0, Losses = 0 },
		-- Pet Master title earned (PetFlair.allFound once true). Kept so a weekly pet released later never takes it away.
		PetMaster = false,
		-- Pet Book slots on top of Config.Inventory.Max (Profiles.petCapacity). 0 for everyone now; a future game pass
		-- helper (made by the owner) may raise it. Never lowered by this build.
		ExtraPetSlots = 0,
		LastSeenNews = "", -- last WHAT'S NEW version the player saw (shared/WhatsNew, set via SettingsAction)
		-- Find The Pet part 2 (shared/ProgressConfig): basket and nest upgrade levels (1 = free starter), the daily
		-- gift + daily quests (shared/Quests, server/QuestService) and the badges already awarded (server/BadgeService).
		BasketLevel = 1,
		NestLevel = 1,
		Daily = Quests.empty(),
		SecretEggFound = false, -- found the hidden lobby egg (BadgeService)
		TowerFloorsToday = 0, -- tower floors cleared on Daily.Day (QuestService resets it each UTC day)
		Badges = {},
		-- Robux shop (shared/RobuxConfig, server/RobuxService): Receipts (granted PurchaseIds), LuckUntil (potion end,
		-- os.time), Passes (owned game passes), purchase counters. Added without a schema bump (reconcile fills it).
		Robux = RobuxConfig.emptyState(),
		-- First five minutes and comeback hooks (shared/Retention, server/RetentionService): last seen time, today's
		-- play-time gifts, friend gifts paid today, last group gift day. Added without a schema bump.
		Retention = Retention.empty(),
		-- Lobby hangout (shared/Hangout): daily likes, mini-game coins today, hidden eggs, lookout, group gift.
		-- Added without a schema bump (reconcile fills it; Hangout.sanitize repairs it).
		Hangout = Hangout.empty(),
		-- Reasons to want eggs (shared/EggPerks): Lucky Meter, banked free eggs, fight-win and quest-egg counters.
		-- Added without a schema bump (reconcile fills it; EggPerks.sanitize repairs it).
		EggPerks = EggPerks.empty(),
		-- Launch picks (shared/LaunchPerks): spin wheel clock and count, the auto-hatch egg. Added without a schema bump.
		Perks = LaunchPerks.empty(),
	}
end

-- Fills missing fields from defaults (never removes data). Migrations go here by Schema.
local function reconcile(data: Data): Data
	local def = Profiles.defaults()
	local hadRarity = type(data.DiscoveryRarity) == "table"
	for k, v in def do
		if data[k] == nil then
			data[k] = v
		elseif type(v) == "table" and type(data[k]) ~= "table" then
			data[k] = v -- a corrupt value where a table belongs (nothing to keep): use the default
		elseif type(v) == "table" and (k == "Settings" or k == "Stats" or k == "Pvp") then
			for k2, v2 in v do
				local cur = data[k][k2]
				if type(v2) == "number" and (type(cur) ~= "number" or cur ~= cur) then
					local n = tonumber(cur)
					data[k][k2] = if n and n == n then n else v2 -- missing or wrong type (an old or hand-edited save)
				elseif type(cur) ~= type(v2) then
					data[k][k2] = v2
				end
			end
		elseif type(v) == "number" and (type(data[k]) ~= "number" or data[k] ~= data[k]) then
			local n = tonumber(data[k])
			data[k] = if n and n == n then n else v
		end
	end
	local st = data.Settings
	for _, k in { "Music", "Sfx" } do
		st[k] = if st[k] == st[k] then math.clamp(st[k], 0, 1) else def.Settings[k]
	end
	-- Rubble counts must be whole non-negative numbers; unknown tier ids (a newer build) are kept untouched.
	for tierId, n in data.RubbleByTier do
		if type(tierId) ~= "string" or type(n) ~= "number" or n ~= n or n < 0 then
			data.RubbleByTier[tierId] = nil
		else
			data.RubbleByTier[tierId] = math.floor(n)
		end
	end
	-- Specimens are tables; anything else in the list is corrupt and cannot be shown, sold or displayed.
	for i = #data.InventoryGeodes, 1, -1 do
		local g = data.InventoryGeodes[i]
		if type(g) ~= "table" then
			table.remove(data.InventoryGeodes, i)
		else
			if type(g.Mass) ~= "number" or g.Mass ~= g.Mass then
				g.Mass = 2 -- every rolled specimen has a mass; the gallery sizes models from it (GeodeGen.visualScale)
			end
			if g.Nickname ~= nil and (type(g.Nickname) ~= "string" or g.Nickname == "") then
				g.Nickname = nil -- a pet nickname is a filtered string (PetService) or absent
			end
			if g.Shiny ~= nil and g.Shiny ~= true then
				g.Shiny = nil -- shiny pets (LaunchPerks.Shiny) carry true; anything else is not shiny
			end
			if g.Evolve ~= nil and (type(g.Evolve) ~= "number" or g.Evolve ~= g.Evolve or g.Evolve < 1) then
				g.Evolve = nil -- evolve stage (PvpService): a whole number from 1, or absent
			elseif g.Evolve ~= nil then
				g.Evolve = math.floor(g.Evolve)
			end
		end
	end
	for i = #data.DisplayAssignments, 1, -1 do
		if type(data.DisplayAssignments[i]) ~= "string" then
			table.remove(data.DisplayAssignments, i)
		end
	end
	data.RoamPets = Profiles.roamList(data)
	if type(data.EquippedHandheld) ~= "string" or not Config.Handhelds[data.EquippedHandheld] then
		data.EquippedHandheld = "Hammer" -- unknown (future) tool id: hold the hammer, keep the ownership record
	end
	-- Older saves: rebuild the mineral x rarity index from the specimens still owned (sold ones
	-- are lost to the index silhouettes; the per-mineral counts above stay as they were).
	if not hadRarity and type(data.InventoryGeodes) == "table" then
		for _, g in data.InventoryGeodes do
			if type(g) == "table" and type(g.Mineral) == "string" and type(g.Rarity) == "string" then
				local row = data.DiscoveryRarity[g.Mineral] or {}
				data.DiscoveryRarity[g.Mineral] = row
				row[g.Rarity] = (row[g.Rarity] or 0) + 1
			end
		end
	end
	data.Materials = Materials.normalize(data.Materials)
	local cos = data.Cosmetics
	for k, v in Cosmetics.empty() do
		if type(cos[k]) ~= "table" then
			cos[k] = v
		end
	end
	-- Saves from before onboarding steps existed: infer what was already done (never repeat it).
	if type(data.Onboard) ~= "table" then
		data.Onboard = {}
	end
	local ob = data.Onboard
	for _, k in { "Started", "PickedUp", "Deposited", "Cracked", "Geode", "Sold", "Displayed", "Goal", "Skipped" } do
		if type(ob[k]) ~= "boolean" then
			ob[k] = false
		end
	end
	if data.TutorialStep >= 1 then
		ob.Started, ob.Cracked, ob.Geode = true, true, true
	end
	-- V3 loop: "Cracked" used to mean cracking at the pile. Saves that already crushed (or finished
	-- the practice round) have necessarily been through the new first two steps, so never repeat them.
	if ob.Cracked or ob.Geode then
		ob.PickedUp, ob.Deposited = true, true
	end
	if data.Stats.CashEarned > 0 then
		ob.Sold = true
	end
	if #data.DisplayAssignments > 0 then
		ob.Displayed = true
	end
	-- Find The Pet: geode saves name minerals and the old traits. Move each to a pet species / trait (the same specimen
	-- id, rarity, value and history), and merge the discovery rows the same way. Nothing is deleted.
	for _, g in data.InventoryGeodes do
		if type(g.Mineral) == "string" and not Config.Minerals[g.Mineral] and Config.MineralMigration[g.Mineral] then
			g.Mineral = Config.MineralMigration[g.Mineral] -- an id from a newer build is kept as it is
		end
		if type(g.Modifier) == "string" and Config.ModifierMigration[g.Modifier] then
			g.Modifier = Config.ModifierMigration[g.Modifier]
		end
	end
	for oldId, n in table.clone(data.DiscoveryIndex) do
		if type(oldId) == "string" and not Config.Minerals[oldId] and Config.MineralMigration[oldId] then
			local newId = Config.MineralMigration[oldId]
			data.DiscoveryIndex[oldId] = nil
			data.DiscoveryIndex[newId] = (tonumber(data.DiscoveryIndex[newId]) or 0) + (tonumber(n) or 0)
		end
	end
	for oldId, row in table.clone(data.DiscoveryRarity) do
		if type(oldId) == "string" and not Config.Minerals[oldId] and Config.MineralMigration[oldId] and type(row) == "table" then
			local newId = Config.MineralMigration[oldId]
			data.DiscoveryRarity[oldId] = nil
			local dest = data.DiscoveryRarity[newId]
			if type(dest) ~= "table" then
				dest = {}
				data.DiscoveryRarity[newId] = dest
			end
			for r, c in row :: { [any]: any } do
				dest[r] = (tonumber(dest[r]) or 0) + (tonumber(c) or 0)
			end
		end
	end
	-- Equipped pets: only owned ids, no repeats, at most Config.Pets.Slots.
	local seen, kept = {}, {}
	for _, id in data.EquippedPets do
		if type(id) == "string" and not seen[id] and #kept < Config.Pets.Slots and select(2, Profiles.findGeode(data, id)) then
			seen[id] = true
			table.insert(kept, id)
		end
	end
	data.EquippedPets = kept
	if type(data.StarterPet) ~= "boolean" then
		data.StarterPet = false
	end
	if type(data.PetMaster) ~= "boolean" then
		data.PetMaster = false
	end
	if not data.PetMaster and PetFlair.allFound(data.DiscoveryIndex) then
		data.PetMaster = true -- saves from before the flag: earned under today's species list
	end
	data.TowerPity = math.max(0, math.floor(data.TowerPity))
	-- Upgrade levels: whole numbers from 1; a level above this build's table is kept (lookups clamp it).
	data.ExtraPetSlots = math.max(0, math.floor(data.ExtraPetSlots))
	data.BasketLevel = math.max(1, math.floor(data.BasketLevel))
	data.NestLevel = math.max(1, math.floor(data.NestLevel))
	data.Daily = Quests.sanitize(data.Daily)
	data.Retention = Retention.sanitize(data.Retention)
	for k, v in data.Badges do
		if type(k) ~= "string" or v ~= true then
			data.Badges[k] = nil
		end
	end
	data.Robux = RobuxConfig.sanitize(data.Robux)
	data.EggPerks = EggPerks.sanitize(data.EggPerks)
	data.Perks = LaunchPerks.sanitize(data.Perks)
	-- never lower the marker: a save written by a newer build keeps its schema when an older server (a rolling update)
	-- loads it, so the newer build does not run its migrations twice
	local schema = tonumber(data.Schema)
	data.Schema = if schema and schema == schema and schema > Config.Save.SchemaVersion then math.floor(schema) else Config.Save.SchemaVersion
	-- Only an owned, known machine can be installed.
	if data.InstalledMachine ~= nil and not (type(data.InstalledMachine) == "string" and Config.Machines[data.InstalledMachine] and data.EquipmentOwned[data.InstalledMachine]) then
		data.InstalledMachine = nil
	end
	data.EquipmentOwned.Hammer = true
	data.UnlockedTiers.Gravel = true
	if not data.EquipmentOwned[data.EquippedHandheld] then
		data.EquippedHandheld = "Hammer"
	end
	return data
end
Profiles.reconcile = reconcile -- tests (tests/server/profiles.luau)

local function key(userId: number): string
	return "u_" .. userId
end

-- A lock belongs to one load (session id), not to the server: a quick rejoin on the same
-- server must wait for the previous session's release save.
local function lockFree(lock: any): boolean
	if type(lock) ~= "table" then
		return true
	end
	return os.time() - (tonumber(lock.Time) or 0) > Config.Save.LockSeconds
end

local function budgetWait(kind: Enum.DataStoreRequestType)
	local t0 = os.clock()
	while DataStoreService:GetRequestBudgetForRequestType(kind) < 1 and os.clock() - t0 < (if shuttingDown then 2 else 10) do
		task.wait(0.5)
	end
end

-- Returns profile record or nil + reason. Never returns defaults when the read failed.
local function loadRecord(player: Player): (any?, string?)
	if not storeOk or not store then
		if IS_STUDIO then
			return { Data = reconcile(Profiles.defaults()), Offline = true }, nil
		end
		return nil, "DataStore unavailable"
	end
	local ds = store :: DataStore
	local lastErr = "unknown"
	local session = HttpService:GenerateGUID(false)
	for attempt = 1, loadAttempts do
		budgetWait(Enum.DataStoreRequestType.UpdateAsync)
		local result: any = nil
		local blocked = false
		local corrupt = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player.UserId), function(old)
				old = old or nil
				-- our own lock from an earlier attempt of this same load (the write landed but the call errored)
				local mine = old and type(old.Lock) == "table" and old.Lock.Session == session
				if old and not mine and not lockFree(old.Lock) then
					blocked = true
					return nil -- keep stored value untouched
				end
				if old ~= nil and type(old.Data) ~= "table" then
					corrupt = true
					return nil -- never overwrite a save we cannot read
				end
				local data = if old then old.Data else Profiles.defaults()
				-- Rev moves on every lock take-over and release, so a server that lost the lock can tell a newer
				-- copy was written (saveRecord). Saves from before Rev existed count as 0.
				local rev = (if old and type(old.Rev) == "number" then old.Rev else 0) + (if mine then 0 else 1)
				result = { Data = data, Lock = { Job = JOB, Session = session, Time = os.time() }, Rev = rev }
				return result
			end)
		end)
		if ok and result then
			-- An odd save must never kill the join thread: on a reconcile error hand the lock straight back
			-- (the stored data is left exactly as it was) and report it, so the player is kicked with a message.
			local rok, rerr = pcall(reconcile, result.Data)
			if not rok then
				warn("[Profiles] save could not be prepared", player.UserId, rerr)
				pcall(function()
					ds:UpdateAsync(key(player.UserId), function(old)
						if old and type(old.Lock) == "table" and old.Lock.Session == session then
							old.Lock = nil
							return old
						end
						return nil
					end)
				end)
				return nil, "save could not be read"
			end
			result.Data = rerr
			result.Session = session
			result.Rev = result.Rev or 0
			return result, nil
		end
		if not ok then
			lastErr = tostring(err)
			-- Studio without API access: run offline, never write.
			if IS_STUDIO and (string.find(lastErr, "403") or string.find(lastErr, "API")) then
				return { Data = reconcile(Profiles.defaults()), Offline = true }, nil
			end
		elseif blocked then
			lastErr = "profile is open on another server"
		elseif corrupt then
			return nil, "save could not be read"
		end
		if not player.Parent then
			return nil, "left"
		end
		task.wait(math.min(2 ^ attempt, 12))
	end
	return nil, lastErr
end

-- The save lock was lost (another server took the profile): progress made here can no longer be saved. Never
-- silent: tell the player, then send them away so their next join loads the newest copy. Once per session;
-- not while the player is already leaving.
local function lockLostNotice(player: Player, rec: any)
	if rec.LockLostNotified or releasing[player] or loaded[player] ~= rec or not player.Parent then
		return
	end
	rec.LockLostNotified = true
	pcall(function()
		Net.event("Toast"):FireClient(player, "Your save moved to another server. Rejoin to keep saving!", "warn")
	end)
	task.delay(3, function()
		if player.Parent then
			player:Kick("FIND THE PET! Your save was opened on another server, so this one stopped saving. Rejoin to keep saving.")
		end
	end)
end

-- Writes the profile if we still own the lock. release=true clears the lock.
local function saveRecord(player: Player, rec: any, release: boolean, attempts: number?, maxWait: number?): boolean
	if rec.Released and not release then
		return false -- the lock was handed over (teleport): a late save would take it back
	end
	if rec.Offline or not store then
		return true
	end
	if rec.LockLost then
		return false -- another server owns this profile now: nothing this session holds may be written
	end
	local ds = store :: DataStore
	for attempt = 1, attempts or 4 do
		budgetWait(Enum.DataStoreRequestType.UpdateAsync)
		if rec.Released and not release then
			return false
		end
		local startedAt = os.clock() -- the data written below is at least this fresh
		local lost = false
		local skipped = false
		local newRev = rec.Rev or 0
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player.UserId), function(old)
				if rec.Released and not release then
					skipped = true -- released while this save waited: leave the stored value alone
					return nil
				end
				-- A plain save also needs our lock to still be there: a missing lock means this session
				-- already released (a late save after leaving) or another server took and released it.
				local ours = old and type(old.Lock) == "table" and old.Lock.Session == rec.Session
				if old and (if release then type(old.Lock) == "table" and not ours else not ours) then
					lost = true
					return nil
				end
				-- Rev moves on every lock take-over and release. A stored Rev above ours means another server took
				-- this profile (and maybe released it) after us: its copy is newer, so never write over it, not
				-- even on our own release after a long DataStore outage.
				local storedRev = if old and type(old.Rev) == "number" then old.Rev else 0
				if old and storedRev > (rec.Rev or 0) then
					lost = true
					return nil
				end
				newRev = math.max(storedRev, rec.Rev or 0) + (if release then 1 else 0)
				return {
					Data = rec.Data,
					Lock = if release then nil else { Job = JOB, Session = rec.Session, Time = os.time() },
					Rev = newRev,
				}
			end)
		end)
		if ok then
			if skipped then
				return false
			end
			if lost then
				warn("[Profiles] lock lost for", player.UserId, "- not saving")
				rec.LockLost = true
				lockLostNotice(player, rec)
				return false
			end
			rec.Rev = newRev
			rec.Dirty = false
			rec.LastSave = os.clock()
			for _, fn in savedHandlers do
				task.spawn(fn, player, startedAt)
			end
			return true
		end
		warn("[Profiles] save failed", player.UserId, err)
		if attempt < (attempts or 4) then
			task.wait(math.min(2 ^ attempt, maxWait or math.huge, if shuttingDown then 2 else math.huge))
		end
	end
	return false
end

function Profiles.get(player: Player): { [string]: any }?
	local rec = loaded[player]
	return if rec then rec.Data else nil
end

function Profiles.isOffline(player: Player): boolean
	local rec = loaded[player]
	return rec ~= nil and rec.Offline == true
end

function Profiles.isLoaded(player: Player): boolean
	return loaded[player] ~= nil
end

function Profiles.onChanged(fn: (Player) -> ())
	table.insert(changedHandlers, fn)
end

-- A species hatched for the first time (pet index): (player, species id, coins already paid).
function Profiles.onSpeciesFound(fn: (Player, string, number) -> ())
	table.insert(speciesHandlers, fn)
end

function Profiles.onLoaded(fn: (Player, any) -> ())
	table.insert(loadedHandlers, fn)
end

-- Call after any mutation. Marks dirty and notifies listeners (UI sync, debounced there).
-- light = true when only cash / rubble / equipment changed (the client keeps its inventory).
function Profiles.changed(player: Player, light: boolean?)
	local rec = loaded[player]
	if rec then
		rec.Dirty = true
		if not light then
			rec.InventoryDirty = true
		end
	end
	for _, fn in changedHandlers do
		task.spawn(fn, player)
	end
end

-- True once per inventory change: the next client sync must include the inventory.
function Profiles.takeInventoryDirty(player: Player): boolean
	local rec = loaded[player]
	if rec and rec.InventoryDirty then
		rec.InventoryDirty = false
		return true
	end
	return false
end

function Profiles.saveNow(player: Player): boolean
	local rec = loaded[player]
	if not rec then
		return false
	end
	return saveRecord(player, rec, false)
end

-- Teleport hand-off ------------------------------------------------------------------------
-- Before a player is teleported to another place of this experience, the profile is saved and
-- the session lock released, so the destination can take it at once. Bounded retries; if the
-- release fails the caller must NOT teleport (the destination would wait on a held lock).
-- After a release the in-memory profile is frozen for writes: gameplay code checks isReleased.

function Profiles.isReleased(player: Player): boolean
	local rec = loaded[player]
	return rec ~= nil and rec.Released == true
end

-- True when another server took this player's session lock (this copy can no longer save).
function Profiles.lockLost(player: Player): boolean
	local rec = loaded[player]
	return rec ~= nil and rec.LockLost == true
end

function Profiles.releaseForTeleport(player: Player): (boolean, string?)
	local rec = loaded[player]
	if not rec then
		return false, "Profile not loaded"
	end
	if rec.Released then
		return true, nil
	end
	if releasing[player] then
		return false, "Leaving"
	end
	if rec.LockLost then
		return false, "Save lock lost"
	end
	-- an award being saved right now must land before the lock is handed over (bounded wait)
	local t0 = os.clock()
	while (holds[player] or 0) > 0 and os.clock() - t0 < Config.Match.RewardSaveTimeout do
		task.wait(0.1)
	end
	if rec.Released then
		return true, nil
	end
	if rec.Offline then
		rec.Released = true -- nothing stored, nothing to hand over
		return true, nil
	end
	if saveRecord(player, rec, true, Config.Teleport.ReleaseAttempts, 4) then
		rec.Released = true
		return true, nil
	end
	return false, "Could not save your profile"
end

-- Teleport failed: take the lock back. Only succeeds if nobody else holds the lock and nobody
-- released a newer copy (Rev unchanged); otherwise the profile is left alone and the caller
-- should send the player away from this server.
function Profiles.reacquire(player: Player): boolean
	local rec = loaded[player]
	if not rec then
		return false
	end
	if not rec.Released then
		return true
	end
	if rec.Offline or not store then
		rec.Released = false
		return true
	end
	local ds = store :: DataStore
	local session = HttpService:GenerateGUID(false)
	for attempt = 1, Config.Teleport.ReleaseAttempts do
		budgetWait(Enum.DataStoreRequestType.UpdateAsync)
		local refused = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player.UserId), function(old)
				if old and ((type(old.Lock) == "table" and not lockFree(old.Lock)) or (old.Rev or 0) ~= (rec.Rev or 0)) then
					refused = true
					return nil
				end
				return { Data = rec.Data, Lock = { Job = JOB, Session = session, Time = os.time() }, Rev = rec.Rev or 0 }
			end)
		end)
		if ok then
			if refused then
				warn("[Profiles] profile moved to another server, not re-acquiring", player.UserId)
				rec.LockLost = true
				return false
			end
			rec.Session = session
			rec.Released = false
			rec.Dirty = false
			rec.LastSave = os.clock()
			return true
		end
		warn("[Profiles] re-acquire failed", player.UserId, err)
		task.wait(math.min(2 ^ attempt, 4))
	end
	return false
end

-- Match server: a player is only loaded after the gate says yes (ticket check).
function Profiles.setJoinGate(fn: (Player) -> boolean)
	joinGate = fn
end

function Profiles.setLoadAttempts(n: number)
	loadAttempts = n
end

-- Helpers ---------------------------------------------------------------------------------

function Profiles.rubbleTotal(data: Data): number
	local n = 0
	for _, v in data.RubbleByTier do
		if type(v) == "number" then
			n += v
		end
	end
	return n
end

-- What the rubble bag sells for (the server's price list; the HUD preview and the results screen use this).
function Profiles.rubbleValue(data: Data): number
	local _, value = Profiles.sellableRubble(data)
	return value
end

-- Rubble the current build can price: (count, cash). Rubble of a tier this build does not know (written
-- by a newer build) is neither priced nor sold, so a sale here can never destroy it for nothing.
function Profiles.sellableRubble(data: Data): (number, number)
	local count, value = 0, 0
	for tierId, n in data.RubbleByTier do
		local tier = Config.Tiers[tierId]
		if tier and type(n) == "number" and n > 0 then
			count += n
			value += n * tier.CashPerRubble
		end
	end
	-- EggPerks.coinMult: +10% per full Pet Book page
	return count, math.floor(value * (1 + Profiles.petCoinBoost(data)) * RobuxConfig.coinMult(data.Robux) * EggPerks.coinMult(data.DiscoveryIndex))
end

-- Boosts from the pets following the player: { Coins, Speed, Luck } fractions (Config.Pets). Pets are found in hunts,
-- never bought, so this is not pay-to-win. Coins only raise the shell sell price.
function Profiles.petBoosts(data: Data): { [string]: number }
	local out = { Coins = 0, Speed = 0, Luck = 0 }
	if type(data.EquippedPets) ~= "table" then
		return out
	end
	for _, id in data.EquippedPets do
		local _, g = Profiles.findGeode(data, id)
		local sp = g and Config.Minerals[g.Mineral]
		if g and sp and out[sp.BoostKind] then
			out[sp.BoostKind] += (sp.Boost + (Config.Pets.RarityBoost[g.Rarity] or 0)) * Config.Pets.KindScale[sp.BoostKind]
		end
	end
	for k, v in out do
		out[k] = math.clamp(math.floor(v * 100 + 0.5) / 100, 0, Config.Pets.KindCap[k])
	end
	return out
end

-- Pet Book size: Config.Inventory.Max, plus the Pet Storage+ game pass (RobuxConfig).
-- Same as petCapacity (kept for the Robux shop code).
function Profiles.inventoryMax(data: Data): number
	return Profiles.petCapacity(data)
end

function Profiles.petCoinBoost(data: Data): number
	return Profiles.petBoosts(data).Coins
end

-- Counts one finished ordinary crush toward the material discoveries. `key` identifies the rock
-- (match key, round, rock id); a key seen before changes nothing, so a duplicate completion cannot count twice.
-- Returns (counted, isNew).
local materialSeen: { [Player]: { [string]: boolean } } = {}
function Profiles.recordMaterial(player: Player, key: string, id: string): (boolean, boolean)
	local data = Profiles.get(player)
	if not data then
		return false, false
	end
	local seen = materialSeen[player]
	if not seen then
		seen = {}
		materialSeen[player] = seen
	end
	if seen[key] then
		return false, false
	end
	local counted, isNew = Materials.record(data.Materials, id)
	if counted then
		seen[key] = true
		Profiles.changed(player, true)
	end
	return counted, isNew
end

-- Level lookups clamp to the levels this build knows: a level bought in a newer build (above the table)
-- gets the biggest known size instead of falling back to level 1, and the stored level is never lowered.
local function level(list: { any }, n: any): any
	local i = if type(n) == "number" and n == n then math.clamp(math.floor(n), 1, #list) else 1
	return list[i]
end

function Profiles.capacity(data: Data): number
	return level(Config.Capacity, data.CapacityTier).Size
end

-- Pet Book capacity: Config.Inventory.Max plus the save's ExtraPetSlots. The hook a Robux game pass helper will use
-- later (it raises ExtraPetSlots); pets are cosmetic storage, never power, so more room is not pay-to-win.
-- Pet Book size: the base 100, plus the Pet Storage+ game pass (RobuxConfig), plus ExtraPetSlots.
function Profiles.petCapacity(data: any): number -- any: MatchService passes a Data? it narrowed at runtime
	return PetRules.capacity(RobuxConfig.inventoryMax(Config.Inventory.Max, data.Robux), data.ExtraPetSlots)
end

-- The roaming picks that are still on display, once each (older saves have no RoamPets).
function Profiles.roamList(data: Data): { string }
	local out, seen = {}, {}
	if type(data.RoamPets) == "table" then
		for _, id in data.RoamPets do
			if type(id) == "string" and not seen[id] and table.find(data.DisplayAssignments, id) then
				seen[id] = true
				table.insert(out, id)
			end
		end
	end
	return out
end

function Profiles.displaySlots(data: Data): number
	return RobuxConfig.displaySlots(level(Config.Display, data.DisplayCapacity).Slots, data.Robux)
end

function Profiles.onboardDone(data: Data): boolean
	local o = data.Onboard
	-- selling candy is optional (coins buy upgrades); the tutorial is the loop: find, show, then the goal card
	return o.Skipped or (o.Started and o.Cracked and o.Geode and o.Displayed and o.Goal)
end

-- Marks an onboarding step done (no-op if already done). Returns true if it changed.
function Profiles.onboard(player: Player, step: string): boolean
	local data = Profiles.get(player)
	if not data or data.Onboard[step] ~= false then
		return false
	end
	data.Onboard[step] = true
	Profiles.changed(player, true)
	return true
end

function Profiles.finds(data: Data): number
	return data.Stats.SoloFinds + data.Stats.MultiplayerWins
end

function Profiles.findGeode(data: Data, id: string): (number?, any)
	for i, g in data.InventoryGeodes do
		if g.Id == id then
			return i, g
		end
	end
	return nil, nil
end

-- Pets from Robux eggs sell for a token share of their value (audit fix: Robux must not buy coins / upgrades).
local BOUGHT_SELL_SHARE = 0.1

-- True for a pet that came out of a Robux egg: RobuxService grants them under the award key "robux:<PurchaseId>:<n>"
-- (kept as the pet's MatchKey by GeodeGen.roll); a pet may also carry Source = "Robux".
function Profiles.isBought(g: any): boolean
	if type(g) ~= "table" then
		return false
	end
	return g.Source == "Robux" or (type(g.MatchKey) == "string" and string.sub(g.MatchKey, 1, 6) == "robux:")
end

-- The pet that helps in the hunt (owner pick 2026-10-15, shared/HuntFun): the strongest equipped pet that was not
-- bought with Robux, and its POWER (tower XP book). nil when none qualifies.
function Profiles.huntHelper(data: Data): ({ [string]: any }?, number)
	local list = {}
	local book = (data :: any).TowerXP
	for _, id in data.EquippedPets do
		local _, g = Profiles.findGeode(data, id)
		if g then
			local xp = if type(book) == "table" then book[tostring(g.Id)] else nil
			table.insert(list, { Pet = g, Xp = if type(xp) == "number" and xp == xp then math.max(xp, 0) else 0, Bought = Profiles.isBought(g) })
		end
	end
	return HuntFun.pickHelper(list)
end

-- The value a pet sells for before Config.Sell.SpecimenFraction (EconomyService "Sell"); the client sees this as the
-- pet's Value (publicView), so the total it shows always matches what the server pays.
function Profiles.priceValue(g: any): number
	local v = if type(g) == "table" and type(g.Value) == "number" and g.Value == g.Value then g.Value else 0
	if Profiles.isBought(g) then
		return math.floor(v * BOUGHT_SELL_SHARE)
	end
	return v
end

-- Idempotent specimen grant keyed by award key. Returns true if newly granted.
-- Refused on a released profile (handed to another place for a teleport) or one whose lock was lost: the write would
-- never be saved here. The caller keeps the award pending (AwardLedger) so the next server grants it.
function Profiles.grantSpecimen(player: Player, awardKey: string, specimen, kind: string): boolean
	local rec = loaded[player]
	local data = if rec then rec.Data else nil
	if not data or rec.Released or rec.LockLost or rec.Closing then
		return false
	end
	for _, k in data.RecentAwardIds do
		if k == awardKey then
			return false
		end
	end
	if Profiles.findGeode(data, specimen.Id) then
		return false
	end
	table.insert(data.InventoryGeodes, specimen)
	table.insert(data.RecentAwardIds, awardKey)
	-- Find The Pet: the pet you just hatched joins the team when a slot is empty or when it is stronger than the weakest
	-- team member (PetRules.autoFollow, by POWER with the save's TowerXP). A "Bonus" pet (a helper's lucky common,
	-- MatchService) never auto-follows.
	if type(data.EquippedPets) == "table" and kind ~= "Bonus" then
		local xpBook = if type(data.TowerXP) == "table" then data.TowerXP else nil
		PetRules.autoFollow(data.EquippedPets, specimen.Id, Config.Pets.Slots, function(petId: string): number
			local _, g = Profiles.findGeode(data, petId)
			local xp = if xpBook then xpBook[petId] else nil
			return if g then PetStats.powerOfPet(g, if type(xp) == "number" then xp else nil) else -1
		end)
	end
	while #data.RecentAwardIds > Config.Save.RecentAwardsKept do
		table.remove(data.RecentAwardIds, 1)
	end
	-- Pet index reward: coins the first time this species is hatched. Read before the hatch is counted and paid in
	-- this same write, so the discovery row itself makes it idempotent (PetFlair.firstFindReward).
	local firstFind = PetFlair.firstFindReward(data.DiscoveryIndex, specimen.Mineral)
	if firstFind > 0 then
		data.Cash += firstFind
	end
	data.DiscoveryIndex[specimen.Mineral] = (data.DiscoveryIndex[specimen.Mineral] or 0) + 1
	local rarityRow = data.DiscoveryRarity[specimen.Mineral] or {}
	data.DiscoveryRarity[specimen.Mineral] = rarityRow
	rarityRow[specimen.Rarity] = (rarityRow[specimen.Rarity] or 0) + 1
	if not data.PetMaster and PetFlair.allFound(data.DiscoveryIndex) then
		data.PetMaster = true -- kept for good: a weekly pet released later never takes the title away
	end
	-- Competitive wins only come from multiplayer hunts; solo and practice finds are Solo Finds.
	-- A "Bonus" pet is neither a win nor a find. A "Bought" pet (Robux egg, RobuxService) is neither, and it does not
	-- count for the RAREST PET board either (boards stay earned in hunts). A "Gift" pet (the starter egg, an away-nest
	-- hatch: RetentionService) is none of these and does not count as the practice find either.
	if kind == "Multiplayer" then
		data.Stats.MultiplayerWins += 1
	elseif kind ~= "Bonus" and kind ~= "Bought" and kind ~= "Tower" and kind ~= "Gift" then
		data.Stats.SoloFinds += 1 -- tower drops are not finds (finds unlock zones)
	end
	if kind ~= "Gift" then
		data.Onboard.Geode = true
	end
	if kind ~= "Bought" and kind ~= "Tower" and kind ~= "Gift" then
		data.Stats.BestGeodeValue = math.max(data.Stats.BestGeodeValue, specimen.Value)
	end
	Profiles.changed(player)
	if firstFind > 0 then
		for _, fn in speciesHandlers do
			task.spawn(fn, player, specimen.Mineral, firstFind)
		end
	end
	return true
end

-- Public view sent to the owning client (no lock data, no ledger internals).
function Profiles.publicView(player: Player, withInventory: boolean?): { [string]: any }?
	local data = Profiles.get(player)
	if not data then
		return nil
	end
	local inv: { any }? = nil
	if withInventory ~= false then
		local list = table.create(#data.InventoryGeodes)
		inv = list
		local xpBook = if type(data.TowerXP) == "table" then data.TowerXP else nil
		for i, g in data.InventoryGeodes do
			local pub = GeodeGen.public(g)
			if Profiles.isBought(g) then
				pub.Value = Profiles.priceValue(g) -- the sell price the Pet Book shows and the server pays
				pub.Bought = true
			end
			local xp = xpBook and xpBook[tostring(g.Id)]
			if type(xp) == "number" then
				pub.TowerXP = xp -- tower XP lives in its own book (TowerService); the Pet Book level reads it here
			end
			list[i] = pub
		end
	end
	return {
		Cash = data.Cash,
		RubbleByTier = data.RubbleByTier,
		Rubble = Profiles.rubbleTotal(data),
		RubbleValue = Profiles.rubbleValue(data),
		Materials = Materials.publicView(data.Materials),
		Capacity = Profiles.capacity(data),
		CapacityTier = data.CapacityTier,
		EquipmentOwned = data.EquipmentOwned,
		EquippedHandheld = data.EquippedHandheld,
		InstalledMachine = data.InstalledMachine,
		UnlockedTiers = data.UnlockedTiers,
		Inventory = inv, -- nil = unchanged since the last full sync
		InventoryCount = #data.InventoryGeodes,
		InventoryMax = Profiles.petCapacity(data),
		DisplayAssignments = data.DisplayAssignments,
		RoamPets = Profiles.roamList(data),
		EquippedPets = data.EquippedPets,
		PetSlots = Config.Pets.Slots,
		PetCoinBoost = Profiles.petCoinBoost(data),
		PetBoosts = Profiles.petBoosts(data),
		PetBoost = (function(): { Kind: string?, Amount: number }
			local bs = Profiles.petBoosts(data)
			for _, k in { "Coins", "Speed", "Luck" } do
				if bs[k] > 0 then
					return { Kind = k, Amount = bs[k] }
				end
			end
			return { Kind = nil, Amount = 0 }
		end)(),
		BasketLevel = data.BasketLevel,
		NestLevel = data.NestLevel,
		TowerBest = data.TowerBest,
		Pvp = data.Pvp,
		SecretEggFound = data.SecretEggFound == true,
		CarryCapacity = ProgressConfig.carry(data.BasketLevel),
		NestQueue = ProgressConfig.queue(data.NestLevel),
		Daily = Quests.view(data.Daily, player.UserId, Quests.day(os.time())),
		Gifts = Retention.view(data.Retention, Retention.day(os.time())), -- play-time gifts (next one, time left)
		StarterEgg = data.StarterPet ~= true, -- the free starter egg near the spawn is still waiting
		DisplaySlots = Profiles.displaySlots(data),
		DisplayCapacity = data.DisplayCapacity,
		DiscoveryIndex = data.DiscoveryIndex,
		DiscoveryRarity = data.DiscoveryRarity,
		Cosmetics = { Owned = data.Cosmetics.Owned, Equipped = data.Cosmetics.Equipped },
		-- Robux shop: potion end (os.time, server clock), owned passes, plot slots (stub until plots exist)
		Robux = { LuckUntil = data.Robux.LuckUntil, Passes = data.Robux.Passes },
		EggPerks = EggPerks.view(data.EggPerks, data.DiscoveryIndex), -- Lucky Meter, free eggs, Pet Book pages
		Perks = LaunchPerks.view(data.Perks, data.Robux, os.time()), -- spin wheel, starter pack, limited egg, lucky hour
		TutorialStep = data.TutorialStep,
		Onboard = data.Onboard,
		OnboardDone = Profiles.onboardDone(data),
		Settings = data.Settings,
		LastSeenNews = data.LastSeenNews,
		Stats = data.Stats,
		Finds = Profiles.finds(data),
		SavesOff = Profiles.isOffline(player),
	}
end

-- Lifecycle -------------------------------------------------------------------------------

local releasingUser: { [number]: boolean } = {}
-- A leaver whose release save failed (DataStore outage): the record (pets, coins) stays here and the save is retried in
-- the background, at shutdown, or handed straight back to the same player if they rejoin this server. Our lock is still
-- on the stored copy, so no other server can load an older copy while this one waits.
local parked: { [number]: any } = {}
local PARK_RETRY_EVERY = 30
local PARK_RETRIES = 20 -- 10 minutes
local retryParked: (number, any) -> ()

-- Kick text for a failed load (plain words; the reason in brackets helps support).
local function loadFailText(err: string?): string
	if err == "profile is open on another server" then
		return "FIND THE PET! Your save is still open on another server (after a crash this can take up to 5 minutes). "
			.. "Your pets are safe. Please rejoin in a few minutes."
	end
	return "FIND THE PET! could not load your save safely. Your pets are safe. Please rejoin in a minute. (" .. tostring(err) .. ")"
end

local function onJoin(player: Player)
	if loading[player] or loaded[player] then
		return
	end
	loading[player] = true
	local rec: any = nil -- a record whose lock we took, so a failure below can hand it back
	local ok: boolean, perr: any = pcall(function()
		if joinGate and not (joinGate :: (Player) -> boolean)(player) then
			return -- not allowed here: no profile is touched
		end
		-- Same-server rejoin: let the previous session finish its release save first.
		local t0 = os.clock()
		while releasingUser[player.UserId] and os.clock() - t0 < 30 do
			task.wait(0.25)
		end
		local err: string? = nil
		local kept = parked[player.UserId]
		if kept then
			-- this server still holds the newest copy (its release save failed): hand it back, never reload an older one
			parked[player.UserId] = nil
			kept.Closing = nil
			rec, err = kept, nil
		else
			rec, err = loadRecord(player)
		end
		loading[player] = nil
		if not player.Parent then
			local r = rec
			rec = nil
			if r and not r.Offline then
				r.Closing = true
				-- release the lock we just took (or the copy we adopted); a failed release keeps the copy parked
				if not saveRecord(player, r, true) and not r.LockLost and store then
					parked[player.UserId] = r
					task.spawn(retryParked, player.UserId, r)
				end
			end
			return
		end
		if not rec then
			warn("[Profiles] could not load", player.UserId, err)
			player:Kick(loadFailText(err))
			return
		end
		rec.LastSave = os.clock()
		rec.Player = player
		loaded[player] = rec
		player:SetAttribute("ProfileLoaded", true)
		for _, fn in loadedHandlers do
			task.spawn(fn, player, rec.Data)
		end
		Profiles.changed(player)
	end)
	loading[player] = nil
	if not ok then
		-- Never leave a player in the game without a profile (and never leave our lock behind).
		warn("[Profiles] join failed", player.UserId, perr)
		local r = rec
		if r and loaded[player] ~= r and not r.Offline then
			task.spawn(saveRecord, player, r, true)
		end
		if loaded[player] == nil and player.Parent then
			player:Kick(loadFailText("join error"))
		end
	end
end

-- Award code can hold a profile open briefly so a leaving winner's prize lands before release.
function Profiles.hold(player: Player)
	holds[player] = (holds[player] or 0) + 1
end
function Profiles.unhold(player: Player)
	holds[player] = math.max(0, (holds[player] or 1) - 1)
end

-- Keeps trying a failed release save until it lands, the lock turns out lost, the player rejoins here (onJoin
-- adopts the record) or the retries run out.
retryParked = function(userId: number, rec: any)
	for _ = 1, PARK_RETRIES do
		task.wait(PARK_RETRY_EVERY)
		if parked[userId] ~= rec then
			return -- adopted by a rejoin, or saved by the shutdown pass
		end
		local ok = saveRecord(rec.Player, rec, true, 1)
		if parked[userId] ~= rec then
			return
		end
		if ok or rec.LockLost then
			parked[userId] = nil
			return
		end
	end
	if parked[userId] == rec then
		parked[userId] = nil
		warn("[Profiles] release save never landed for", userId, "- the lock expires on its own")
	end
end

local function onLeave(player: Player)
	local rec = loaded[player]
	if not rec or releasing[player] then
		return
	end
	releasing[player] = true
	releasingUser[player.UserId] = true
	local t0 = os.clock()
	while (holds[player] or 0) > 0 and os.clock() - t0 < Config.Match.RewardSaveTimeout do
		task.wait(0.2)
	end
	if type(rec.Data.Retention) == "table" then
		rec.Data.Retention.LastSeen = os.time() -- the away nest counts from here (RetentionService)
	end
	if not rec.Released then
		-- from here on a grant would miss the release save: grantSpecimen refuses it (the caller keeps it pending)
		rec.Closing = true
		-- a released profile was already saved; the lock is not ours
		if not saveRecord(player, rec, true) and not rec.LockLost and not rec.Offline and store then
			parked[player.UserId] = rec
			task.spawn(retryParked, player.UserId, rec)
		end
	end
	loaded[player] = nil
	releasing[player] = nil
	releasingUser[player.UserId] = nil
	holds[player] = nil
	materialSeen[player] = nil
end

function Profiles.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, p in Players:GetPlayers() do
		task.spawn(onJoin, p)
	end
	task.spawn(function()
		while true do
			task.wait(5)
			for player, rec in loaded do
				-- Clean profiles save too, so the lock's Time stays fresh and never looks abandoned.
				if not rec.Released and os.clock() - (rec.LastSave or 0) >= Config.Save.AutosaveSeconds and not releasing[player] then
					task.spawn(saveRecord, player, rec, false)
					rec.LastSave = os.clock()
				end
			end
		end
	end)
	game:BindToClose(function()
		shuttingDown = true
		-- Final writes of other services (leaderboards, ledger) run beside the profile saves, inside the same budget.
		-- They start first so they still see every loaded profile.
		local running = 0
		for _, fn in shutdownHandlers do
			running += 1
			task.spawn(function()
				local ok: boolean, err: any = pcall(fn)
				if not ok then
					warn("[Profiles] shutdown handler failed", err)
				end
				running -= 1
			end)
		end
		for player in loaded do
			task.spawn(onLeave, player)
		end
		-- leavers whose release save failed earlier: one last try each (their retry loop stops once they leave the list)
		for userId, rec in table.clone(parked) do
			running += 1
			task.spawn(function()
				local ok = saveRecord(rec.Player, rec, true)
				if parked[userId] == rec then
					parked[userId] = nil
				end
				if not ok then
					warn("[Profiles] shutdown: release save failed for", userId)
				end
				running -= 1
			end)
		end
		local t0 = os.clock()
		while next(loading) ~= nil and os.clock() - t0 < 10 do
			task.wait(0.2) -- a load still running takes a lock; let it land so it is released below
		end
		for player in loaded do
			task.spawn(onLeave, player) -- onLeave ignores players already releasing
		end
		while (next(loaded) ~= nil or running > 0) and os.clock() - t0 < 25 do
			task.wait(0.2)
		end
	end)
end

-- A final write BindToClose should wait for (bounded by the same 25 s as the profile saves). fn may yield.
function Profiles.onShutdown(fn: () -> ())
	table.insert(shutdownHandlers, fn)
end

-- Runs (spawned) after every committed save of a player's profile, including the release save on leave.
-- startedAt: os.clock() when that save attempt began; every in-memory change made before it is in the save.
function Profiles.onSaved(fn: (Player, number) -> ())
	table.insert(savedHandlers, fn)
end

return Profiles
