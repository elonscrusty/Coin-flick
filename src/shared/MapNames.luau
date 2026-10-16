--!strict
-- Names the game code looks for in the lobby map. The owner builds the lobby by hand in Studio (Workspace.FTP_Lobby);
-- the code finds its hooks by these names (and attributes), so a name can change here, in one place. Where a hook
-- has a list, the first name is the owner's real map and the others are accepted too. Full list of what each piece
-- needs (attributes, attachments, prompts): docs/MAP_HOOKS.md.
--
-- If Workspace holds a Model (or Folder) named one of MapNames.Roots, that is the hand-built map: the code does not build the
-- procedural park (ParkBuilder) or the old lodge and only adopts the hooks it finds inside it. Without one, the
-- procedural park is built as a simple fallback, using the same names.

local MapNames = {}

MapNames.Roots = { "FTP_Lobby", "Lobby", "PetPark" } -- a hand-built map: a Model or Folder directly under Workspace

-- Hunt queue: QueuePads/QueuePad1..4 (a Model whose touch part is "Pad", or a single Part) and their "Countdown"
-- signs (SurfaceGuis with a TextLabel "Text"); the queue text also goes to an optional single QueueBoard/QueueText.
MapNames.QueuePad = "QueuePad"
MapNames.QueuePadCount = 4
MapNames.QueuePadTouch = "Pad"
MapNames.QueueCountdown = "Countdown"
MapNames.CountdownText = "Text"
MapNames.QueueBoard = "QueueBoard" -- PartyService writes the queue text into QueueBoard/QueueText
MapNames.QueueText = "QueueText"

-- Plots: Plots/Plot1..N (a Model; PrimaryPart "Floor"; the plot faces its PlotSign, i.e. the street)
MapNames.Plot = "Plot"
MapNames.PlotCount = 6 -- plots expected in the hand-built lobby (owner may add more: Plot7.. are found automatically)
MapNames.PlotFloor = "Floor"
MapNames.DomeCount = 3 -- display slots shown on stands (the rest stand in the yard)
-- Display slot k -> the part the pet stands on (accepted names, preferred first): slot 1 under the big glass Dome1
-- on Dome1Base, slots 2 and 3 on Stand1 / Stand2.
MapNames.SlotParts = {
	{ "Dome1Base", "DomeSlot1" },
	{ "Stand1", "Dome2Base", "DomeSlot2" },
	{ "Stand2", "Dome3Base", "DomeSlot3" },
}
MapNames.PlotSign = { "PlotSign", "Nameplate" } -- owner's name sign (TextLabel "Text" or "OwnerText" inside)
MapNames.SignText = { "Text", "OwnerText" }
MapNames.OwnerText = "OwnerText" -- the TextLabel the code makes when a sign has none
MapNames.LikePost = "LikePost" -- optional LIKE part; without it the LIKE prompt goes on the plot sign (or the floor)
MapNames.LikeText = "LikeText" -- optional TextLabel for the like count

-- Buildings (anywhere in the map; FTP_Lobby keeps them in Buildings/)
MapNames.EggShop = "EggShop" -- RobuxService opens the shop through the first ProximityPrompt in it
MapNames.ShopCounter = "Counter"
MapNames.BuildingSign = "Sign"
MapNames.HatchStand = "HatchStand"
MapNames.HatchPoint = "HatchPoint" -- Attachment on the stand's top part
MapNames.TowerEntrance = "TowerEntrance"
MapNames.TowerPortal = "TowerPortal" -- the doorway touch part (attribute TowerPortal = true)
MapNames.TowerExit = "TowerExit" -- optional Part where players come back out of the tower (front = the way they face)
MapNames.SecretEgg = "SecretEgg"
MapNames.SecretEggPrompt = "Take"
MapNames.WhatsNewBoard = "WhatsNewBoard"
MapNames.Spawn = "LobbySpawn" -- a SpawnLocation; any SpawnLocation in the map also works
-- First five minutes (optional Parts; without them the code places these near the lobby spawn):
MapNames.VoidStatueSpot = "VoidStatueSpot" -- old Void Dragon podium spot (removed 2026-10-14: the dragon perches on the leaderboard tree's DragonPerch)
MapNames.StarterEggSpot = "StarterEggSpot" -- a new player's free starter egg sits here

-- Leaderboards (FTP_Lobby: Leaderboards/RarestPetBoard and Leaderboards/TowerFloorBoard, each with a "Board" part
-- holding a SurfaceGui and a TextLabel "Text": the rows are written there as text). A plain Part gets drawn rows.
MapNames.Boards = {
	{ Parts = { "RarestPetBoard", "RarestBoard" }, Id = "Biggest" },
	{ Parts = { "TowerFloorBoard", "TowerBoard" }, Id = "Tower" },
	{ Parts = { "CoinsBoard", "MostCoinsBoard" }, Id = "Coins" },
}
MapNames.BoardFace = "Board"
MapNames.BoardText = "Text"

-- Optional spots where the code builds its existing stalls (a Part; the stall's front faces the Part's LookVector).
MapNames.StallSpots = { Upgrades = "UpgradesSpot", PetBook = "PetBookSpot", Seller = "SellerSpot" }

function MapNames.plot(i: number): string
	return MapNames.Plot .. tostring(i)
end

function MapNames.queuePad(n: number): string
	return MapNames.QueuePad .. tostring(n)
end

-- Accepted names for display slot k's stand part, preferred first.
function MapNames.slotParts(k: number): { string }
	return MapNames.SlotParts[k] or {}
end

-- The hand-built map root among `children` (Workspace:GetChildren()), or nil; earlier Roots win. Pure: tests pass
-- plain tables.
function MapNames.findRoot(children: { any }): any?
	for _, name in MapNames.Roots do
		for _, c in children do
			if c.Name == name and (type(c) == "table" or c:IsA("Model") or c:IsA("Folder")) then
				return c
			end
		end
	end
	return nil
end

return MapNames
