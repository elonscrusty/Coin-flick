--!strict
-- Owns every player's save. Gameplay changes the in-memory profile only;
-- this module loads it (with a session lock), autosaves it, and saves it on
-- leave and on server shutdown. If loading fails the player is kicked, so a
-- blank profile can never overwrite real progress.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(script.Parent.Net)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local KeyedMutex = require(script.Parent.Parent.Util.KeyedMutex)
local MemoryStore = require(script.Parent.Parent.Util.MemoryStore)
local SessionStore = require(script.Parent.Parent.Util.SessionStore)

type Profile = Types.Profile
type LoadedCallback = (player: Player, profile: Profile, offlineCash: number) -> ()

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local dirty: { [Player]: boolean } = {}
local leaderstats: { [Player]: { cash: NumberValue, resets: IntValue } } = {}
local loadedCallbacks: { LoadedCallback } = {}
local loading: { [Player]: boolean } = {}
-- Profiles whose final (releasing) save already ran. Later saves are dropped.
local released: { [Profile]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local pendingSaves = 0
local session: SessionStore.SessionStore
-- Only one DataStore call per player at a time, so saves can't land out of order.
local keyLock = KeyedMutex.new(function(seconds: number)
	task.wait(seconds)
end)

local function keyFor(player: Player): string
	return `u_{player.UserId}`
end

local function chooseStore(): SessionStore.Store
	if RunService:IsStudio() then
		if Config.STUDIO_USE_REAL_TEST_STORE then
			print("[Save] Studio: using the separate STUDIO test DataStore")
			return DataStoreService:GetDataStore(Config.STUDIO_DATASTORE_NAME) :: any
		end
		print("[Save] Studio: using a throwaway in-memory store (real saves untouched)")
		return MemoryStore.new()
	end
	return DataStoreService:GetDataStore(Config.DATASTORE_NAME) :: any
end

local function makeLeaderstats(player: Player, profile: Profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("NumberValue")
	cash.Name = "Cash"
	cash.Value = profile.cash
	cash.Parent = folder
	local resets = Instance.new("IntValue")
	resets.Name = "Resets"
	resets.Value = profile.resets
	resets.Parent = folder
	folder.Parent = player
	leaderstats[player] = { cash = cash, resets = resets }
end

local function saveNow(player: Player, profile: Profile, release: boolean): SessionStore.SaveResult
	local result: SessionStore.SaveResult = "error"
	pendingSaves += 1
	keyLock:run(player.UserId, function()
		if released[profile] then
			result = "ok" -- this session already handed its save back; nothing to do
			return
		end
		profile.lastSeen = os.time()
		result = session:save(keyFor(player), profile, release, player.UserId)
		if release then
			released[profile] = true
		end
	end)
	pendingSaves -= 1
	return result
end

local function autosaveLoop(player: Player, profile: Profile)
	-- Stagger players so they don't all save on the same tick.
	task.wait(player.UserId % Config.AUTOSAVE_INTERVAL)
	while profiles[player] == profile do
		local result = saveNow(player, profile, false)
		if result == "lost" and profiles[player] == profile then
			-- Another server took over this save. Stop here so nothing gets mixed up.
			profiles[player] = nil
			player:Kick("You joined from another server. Please rejoin!")
			return
		end
		task.wait(Config.AUTOSAVE_INTERVAL)
	end
end

local function onPlayerAdded(player: Player)
	if loading[player] or profiles[player] then
		return -- already loading (PlayerAdded and the startup loop can both fire)
	end
	loading[player] = true
	local profile: Profile? = nil
	local err: SessionStore.LoadError? = nil
	-- Waits for any save of this player still running here (fast rejoin).
	keyLock:run(player.UserId, function()
		profile, err = session:load(keyFor(player), player.UserId)
	end)
	loading[player] = nil
	if player.Parent ~= Players then
		-- Left while loading: hand the lock straight back.
		if profile then
			saveNow(player, profile, true)
		end
		return
	end
	if not profile then
		if err == "locked" then
			player:Kick("Your coins are still saving from your last game. Please rejoin in a minute!")
		else
			player:Kick("We couldn't load your coins right now. Please rejoin!")
		end
		return
	end
	local offlineCash = GameLogic.applyOffline(profile, os.time())
	profiles[player] = profile
	makeLeaderstats(player, profile)
	dirty[player] = true
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile, offlineCash)
	end
	task.spawn(autosaveLoop, player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	dirty[player] = nil
	leaderstats[player] = nil
	if profile then
		saveNow(player, profile, true)
	end
end

local function onClose()
	-- Server is shutting down: save everyone left, in parallel.
	for player, profile in profiles do
		profiles[player] = nil
		task.spawn(saveNow, player, profile, true)
	end
	local deadline = os.clock() + 25
	task.wait() -- let the saves start
	while pendingSaves > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerData.init()
	session = SessionStore.new({
		store = chooseStore(),
		jobId = if game.JobId ~= "" then game.JobId else `studio-{HttpService:GenerateGUID(false)}`,
		now = os.time,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		warn = function(message: string)
			warn(message)
		end,
		lockAttempts = 8,
		lockStaleSeconds = Config.AUTOSAVE_INTERVAL * 3, -- a crashed server frees saves after 3 min
	})
	game:BindToClose(onClose)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Push HUD updates at most 5 times a second per player.
	local stateRemote = Net.event("State")
	while true do
		task.wait(0.2)
		for player in dirty do
			dirty[player] = nil
			local profile = profiles[player]
			if profile then
				stateRemote:FireClient(player, GameLogic.snapshot(profile))
				local stats = leaderstats[player]
				if stats then
					stats.cash.Value = profile.cash
					stats.resets.Value = profile.resets
				end
			end
		end
	end
end

-- The live profile, or nil if not loaded (yet / any more). Always check for nil.
function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

-- Tell the client its numbers changed.
function PlayerData.changed(player: Player)
	if profiles[player] then
		dirty[player] = true
	end
end

function PlayerData.onLoaded(callback: LoadedCallback)
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile, 0)
	end
end

return PlayerData
