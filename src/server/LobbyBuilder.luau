--!strict
-- Builds the public shared lobby: the dino-jungle pet park (owner picks 2026-10-10). ParkBuilder makes the valley,
-- the paths, the clearing with the queue nests, the 12 plots, the spawn plaza and the PET TOWER gate; this module puts
-- the stalls (LodgeBuilder: UPGRADES, PET BOOK, SHELL SELL on the plaza, the EGG SHOP at the north end, the crowned
-- HUNT WINS board in the clearing and two boards on the plaza) on it and makes the spawn on the plaza, facing the
-- clearing. Layout numbers: src/shared/ParkConfig.luau.
-- World.buildLobby (WorldBuilder) delegates here and returns the same fields as before:
-- { Root, Spawn, Alcoves (= the plots, see ParkBuilder.Plot), Stands }.
-- World frame: the ground top is y = Config.Lodge.FloorY (0); the plaza and the spawn are at +Z, the EGG SHOP at -Z.

local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.KitParts)
local KitPlace = require(script.Parent.KitPlace)
local LodgeBuilder = require(script.Parent.LodgeBuilder)
local ParkBuilder = require(script.Parent.ParkBuilder)
local MapHooks = require(script.Parent.MapHooks)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ParkConfig = require(Shared.ParkConfig)
local MapNames = require(Shared.MapNames)

local folder = Kit.folder

local LobbyBuilder = {}

export type Alcove = ParkBuilder.Plot

local FLOOR = Config.Lodge.FloorY
local PAVE_TOP = FLOOR + 0.05 -- plaza paving top (ParkBuilder)

-- Ground height under a world point (the park is flat) and whether it is inside the walkable park. Used by the
-- placement audit (tools/preview/scenes/placement.luau).
function LobbyBuilder.groundAt(_p: Vector3): number
	return FLOOR
end

function LobbyBuilder.insideLodge(p: Vector3): boolean
	return ParkConfig.inside(p.X, p.Z)
end

-- Walking routes that must stay clear (world X / Z), audited by tools/preview/scenes/placement.luau and
-- tools/preview/check_lobby.py: the spawn walk, the main and ring paths, the walk between the nests, the stall,
-- shop, tower and board fronts.
LobbyBuilder.ClearZones = {
	{ Name = "SpawnWalk", MinX = -6, MaxX = 6, MinZ = 96, MaxZ = 124 },
	{ Name = "MainSouth", MinX = -4.5, MaxX = 4.5, MinZ = 50, MaxZ = 92 },
	{ Name = "MainNorth", MinX = -4.5, MaxX = 4.5, MinZ = -96, MaxZ = -50 },
	{ Name = "RingSouth", MinX = -84, MaxX = 84, MinZ = 40, MaxZ = 48 },
	{ Name = "RingNorth", MinX = -84, MaxX = 84, MinZ = -48, MaxZ = -40 },
	{ Name = "RingWest", MinX = -48, MaxX = -40, MinZ = -84, MaxZ = 84 },
	{ Name = "RingEast", MinX = 40, MaxX = 48, MinZ = -84, MaxZ = 84 },
	{ Name = "ClearingWalk", MinX = -4, MaxX = 4, MinZ = -30, MaxZ = 30 },
	{ Name = "UpgradesFront", MinX = -43, MaxX = -36, MinZ = 101, MaxZ = 123 },
	{ Name = "PetBookFront", MinX = 36, MaxX = 43, MinZ = 101, MaxZ = 123 },
	{ Name = "SellerFront", MinX = -30, MaxX = -22, MinZ = 118, MaxZ = 124 },
	{ Name = "EggShopFront", MinX = -5, MaxX = 5, MinZ = -100, MaxZ = -96 },
	{ Name = "TowerApproach", MinX = -92, MaxX = -86, MinZ = -4, MaxZ = 4 },
	{ Name = "BoardFront", MinX = 20, MaxX = 27, MinZ = -14, MaxZ = 14 },
	{ Name = "HatchFront", MinX = 14, MaxX = 28, MinZ = -90, MaxZ = -86 },
	{ Name = "NewsFront", MinX = 15, MaxX = 29, MinZ = 99, MaxZ = 104 },
}

-- Lobby spawn pad (docs/m11/CAMERA_SPAWN_FIX.md): a SOLID, invisible 8 x 0.2 x 6 SpawnLocation lying on the plaza
-- paving at LobbyBuilder.spawnCFrame (top 0.02 above the paving), facing the clearing. Made once (Main.server calls
-- this before the mesh wait); build() re-parents it into the lobby folder.
LobbyBuilder.SpawnPadSize = Vector3.new(8, 0.2, 6)

function LobbyBuilder.spawnCFrame(): CFrame
	local p = Vector3.new(ParkConfig.Spawn.X, PAVE_TOP, ParkConfig.Spawn.Z)
	return CFrame.new(p) -- faces -Z (north, toward the clearing)
end

local spawnPad: SpawnLocation? = nil
function LobbyBuilder.ensureSpawn(): SpawnLocation
	if spawnPad and spawnPad.Parent then
		return spawnPad
	end
	local hand = MapHooks.root()
	local own = if hand then (hand:FindFirstChild(MapNames.Spawn, true) or hand:FindFirstChildWhichIsA("SpawnLocation", true)) else nil
	if own and own:IsA("SpawnLocation") then
		return own -- the hand-built map's spawn
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CT_Rocks_LobbySpawn"
	spawn.Size = LobbyBuilder.SpawnPadSize
	spawn.CFrame = LobbyBuilder.spawnCFrame() * CFrame.new(0, 0.02 - LobbyBuilder.SpawnPadSize.Y / 2, 0)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = true
	spawn.CanQuery = false
	spawn.CastShadow = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = Workspace
	spawnPad = spawn
	return spawn
end

-- The stall spot Parts in a hand-built map (shared/MapNames.StallSpots): the stall's front faces the Part's
-- LookVector, its base sits on the Part's bottom.
local function spotFrame(map: Instance, name: string): CFrame?
	local p = map:FindFirstChild(name, true)
	if p and p:IsA("BasePart") then
		local look = p.CFrame.LookVector
		return KitPlace.facing(p.Position - Vector3.new(0, p.Size.Y / 2, 0), Vector3.new(look.X, 0, look.Z))
	end
	return nil
end

function LobbyBuilder.build(_toolModel: (string) -> Model): { [string]: any }
	local handMap = MapHooks.root()
	-- with a hand-built map there is NO CT_Rocks_Lobby (no lodge, no park, no code spawn, and the client's park camera
	-- box stays off); the few helper pieces (hidden queue board, board mounts, stalls on stall spots) go in
	-- CT_Rocks_LobbyHooks
	local root = folder(Workspace, if handMap then "CT_Rocks_LobbyHooks" else "CT_Rocks_Lobby")
	local stalls = folder(root, "CT_Rocks_Lodge")
	local lights = folder(stalls, "CT_Rocks_LodgeLights")
	if handMap then
		-- the owner's hand-built lobby (Workspace.FTP_Lobby; also Lobby / PetPark): no procedural park and no old lodge or
		-- code spawn; only the hooks it holds are adopted (docs/MAP_HOOKS.md), and the code stalls are built on any
		-- stall spots it marks
		local hooks = MapHooks.ensure(handMap, root, true)
		local S = MapNames.StallSpots
		local up, book, sell = spotFrame(handMap, S.Upgrades), spotFrame(handMap, S.PetBook), spotFrame(handMap, S.Seller)
		if up then
			LodgeBuilder.buildUpgrades(stalls, lights, up)
		end
		if book then
			LodgeBuilder.buildCollection(stalls, lights, book)
		end
		if sell then
			LodgeBuilder.buildSeller(stalls, lights, sell)
		end
		local spawn = handMap:FindFirstChild(MapNames.Spawn, true) or handMap:FindFirstChildWhichIsA("SpawnLocation", true)
		local spawnCF: CFrame
		if spawn and spawn:IsA("BasePart") then
			spawnCF = spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2, 0)
			if spawnPad and spawnPad ~= spawn then
				spawnPad:Destroy() -- the map's own spawn wins
				spawnPad = nil
			end
		else
			spawnCF = LobbyBuilder.spawnCFrame()
			LobbyBuilder.ensureSpawn().Parent = root
		end
		KitPlace.decorPolicy(stalls)
		return { Root = root, Spawn = spawnCF * CFrame.new(0, 3.5, 0), Alcoves = hooks.Plots, Stands = {}, HandBuilt = true }
	end

	-- fallback: the procedural park (same hook names, shared/MapNames)
	local park = ParkBuilder.build(root)
	-- the plaza stalls and the record boards (BoardMounts must be a direct child of the lobby root: LobbyBoards)
	local fr = ParkBuilder.stallFrames()
	LodgeBuilder.buildUpgrades(stalls, lights, fr.Upgrades)
	LodgeBuilder.buildCollection(stalls, lights, fr.PetBook)
	LodgeBuilder.buildSeller(stalls, lights, fr.Seller)
	LodgeBuilder.buildEggShop(stalls, lights, fr.EggShop)
	LodgeBuilder.buildBoards(root, lights, fr.Boards)

	local spawnCF = LobbyBuilder.spawnCFrame()
	LobbyBuilder.ensureSpawn().Parent = root

	-- every decorative part in the lobby (now and added later) ignores the camera and the interaction ray
	KitPlace.decorPolicy(root)
	MapHooks.ensure(root, root, false) -- the same hook checks as a hand-built map (all present here)

	return {
		Root = root,
		Spawn = spawnCF * CFrame.new(0, 3.5, 0),
		Alcoves = park.Plots,
		Stands = {},
	}
end

return LobbyBuilder
