--!strict
-- Server boot: remotes, world, saves, services, profile sync to clients.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)
local PlaceRole = require(Shared.PlaceRole)
Net.init()

-- "Single" (default, Studio): lobby + private arenas in this server, exactly as in Phase 1.
-- "Lobby" / "Match": Teleport mode (Config.Places), see docs/OWNER_STEPS.md.
local role = PlaceRole.resolve(Config.Places.Mode, game.PlaceId, Config.Places.LobbyPlaceId, Config.Places.MatchPlaceId)
local isMatch = role == "Match"

local Profiles = require(script.Parent.Profiles)
local Ledger = require(script.Parent.AwardLedger)
local World = require(script.Parent.WorldBuilder)
local PartyService = require(script.Parent.PartyService)
local MatchService = require(script.Parent.MatchService)
local Economy = require(script.Parent.EconomyService)
local Gallery = require(script.Parent.GalleryService)
local Leaderboards = require(script.Parent.LeaderboardService)
local LobbyBoards = require(script.Parent.LobbyBoards)
local Store = require(script.Parent.StoreService)

-- The lobby spawn pad exists BEFORE the mesh wait below (up to 8 s): a player who joins in that window (Studio Play
-- does) used to spawn with no SpawnLocation at all, at the centre of the lodge, and could end up on the ceiling
-- collider once the lodge appeared around them (docs/m11/CAMERA_SPAWN_FIX.md).
if not isMatch then
	require(script.Parent.LobbyBuilder).ensureSpawn()
end
require(script.Parent.MeshService).start() -- uploaded CT_Rocks_ meshes -> ReplicatedStorage.Assets (optional)
require(script.Parent.LowPolyStation).apply() -- owner's low-poly basket and tappers over those templates (when imported)
require(script.Parent.PreviewKit).build() -- shop pictures of the real tool / machine models
local lobby: { [string]: any } = if isMatch then {} else World.buildLobby()

-- Profile -> client sync, debounced so a burst of changes sends one update.
local dirty: { [Player]: boolean } = {}
Profiles.onChanged(function(player)
	if dirty[player] then
		return
	end
	dirty[player] = true
	task.delay(0.15, function()
		dirty[player] = nil
		if player.Parent then
			local view = Profiles.publicView(player, Profiles.takeInventoryDirty(player))
			if view then
				Net.event("ProfileState"):FireClient(player, view)
			end
		end
	end)
end)

Profiles.onLoaded(function(player)
	Ledger.reconcile(player)
	Economy.attachTool(player)
	PartyService.sync(player.UserId)
end)

Economy.onToolChanged(MatchService.toolChanged)
Economy.onMachine(MatchService.machineChanged)
-- One plot rebuild per player per half second, however fast the display buttons are tapped.
local renderPending: { [Player]: boolean } = {}
Economy.onDisplayChanged(function(player)
	if renderPending[player] then
		return
	end
	renderPending[player] = true
	task.delay(0.5, function()
		renderPending[player] = nil
		if player.Parent then
			Gallery.render(player)
		end
	end)
end)

local function onCharacter(player: Player)
	local char = player.Character
	if char then
		char:WaitForChild("Humanoid", 5)
		if not (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) then
			char:WaitForChild("RightHand", 5)
		end
	end
	if Profiles.isLoaded(player) then
		Economy.attachTool(player)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	-- appearance (bundle body parts) may finish after CharacterAdded: attach again
	player.CharacterAppearanceLoaded:Connect(function()
		if Profiles.isLoaded(player) then
			Economy.attachTool(player)
		end
	end)
	if player.Character then
		task.spawn(onCharacter, player)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

local lastReady: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(p)
	lastReady[p] = nil
end)
Net.event("ClientReady").OnServerEvent:Connect(function(player)
	local t = os.clock()
	if lastReady[player] and t - lastReady[player] < 5 then
		return -- once per player per 5 s
	end
	lastReady[player] = t
	local view = Profiles.publicView(player, true)
	if view then
		Net.event("ProfileState"):FireClient(player, view)
	end
	PartyService.sync(player.UserId)
end)

if not isMatch then
	PartyService.start()
end
MatchService.start(lobby)
require(script.Parent.EggEvents).start() -- wobble hint + speed boots
if role == "Lobby" then
	require(script.Parent.LobbyLaunch).start() -- replaces the in-server arena hand-off
elseif isMatch then
	require(script.Parent.MatchPlace).start() -- before Profiles.start: sets the ticket join gate
end
Economy.start()
if not isMatch then
	require(script.Parent.CoinYardService).start() -- coin yard east of the park + battle ring in the clearing
end
if not isMatch then
	Gallery.start(lobby)
	LobbyBoards.build(lobby.Root)
	require(script.Parent.WinnerBoard).start(lobby.Root) -- LAST WINNERS screen over the WHAT'S NEW board (memory only)
	local okStatue, statueErr = pcall(require(script.Parent.VoidStatue).build, lobby.Root, lobby.Spawn) -- the 1 in 1000 dream pet
	if not okStatue then
		warn("[Main] Void Dragon statue failed: " .. tostring(statueErr))
	end
end
Store.start()
require(script.Parent.RobuxService).start() -- Robux shop + luck events (receipts via Store.addReceiptRoute)
Leaderboards.start()
if not isMatch then
	require(script.Parent.TopStatues).start() -- top 3 STRONGEST PET players as statues on TopStatue pedestals
	task.defer(function()
		local ok, n = pcall(require(script.Parent.LobbyBloom).build) -- flowers + twinkles beside the lobby paths
		if not ok then
			warn("[Main] lobby flowers failed: " .. tostring(n))
		end
	end)
end
local PetService = require(script.Parent.PetService)
PetService.start() -- pets: starter, follower attribute, equip, renaming
local RetentionService = require(script.Parent.RetentionService)
RetentionService.start(isMatch) -- starter egg, play-time gifts, away nest, friend + group gifts
Economy.onTutorialSkipped(function(p)
	RetentionService.hatchStarter(p) -- skipping the tutorial still hatches the free starter pet (with its show)
end)
if not isMatch then
	PetService.onRenamed(Gallery.render) -- a renamed pet on display gets its new plaque
end
require(script.Parent.FriendBonus).start() -- friend bonus luck (Roblox friends in this server)
require(script.Parent.PetIndex).start() -- first-find coins, Pet Master title, name tag attributes
require(script.Parent.RareHatch).start() -- rare hatch banners from other servers (MessagingService)
if not isMatch then
	-- lobby hangout (shared/Hangout, docs/HANGOUT.md): sit spots, hidden eggs, lookout, group gift, mini-games, events
	local Robux = require(script.Parent.RobuxService)
	local hangoutRoots: { Instance } = { lobby.Root }
	local handMap = require(script.Parent.MapHooks).root()
	if handMap and handMap ~= lobby.Root then
		table.insert(hangoutRoots, handMap)
	end
	local meadow = workspace:FindFirstChild("LobbyMeadow")
	if meadow and not table.find(hangoutRoots, meadow) then
		table.insert(hangoutRoots, meadow)
	end
	require(script.Parent.LobbyHangout).start(hangoutRoots, Robux.giftEgg)
	require(script.Parent.LobbyGames).start(hangoutRoots)
	require(script.Parent.TreeBoardService).start(hangoutRoots) -- leaderboard tree: top pets by POWER + BATTLE pad
	require(script.Parent.LobbyEvents).start(hangoutRoots, if lobby.Spawn then lobby.Spawn.Position else nil, Robux.giftEgg)
end
Profiles.start() -- last, so every onLoaded handler is registered first
