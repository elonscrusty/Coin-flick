--!strict
-- Progression tuning (Find The Pet part 2): basket and nest upgrades, the daily gift, daily quests and badges.
-- Kept apart from Config.luau so it can be tuned on its own. Every price here is in-game COINS (earned by
-- selling shells and pets), never Robux: upgrades are not sold for real money (never pay-to-win).

local Config = require(script.Parent.Config)
local SpeciesPool = require(script.Parent.SpeciesPool)

local ProgressConfig = {}

export type Basket = { Id: string, Name: string, Carry: number, Price: number }
export type Nest = { Id: string, Name: string, Queue: number, Price: number, Color: Color3, Dark: Color3, Material: string }

-- Baskets: eggs carried per trip, 3 up to 20. Level 1 is free (Config.Carry.Capacity, 3 eggs). The avatar's basket
-- model shows at most its own slot count (CarryView); the HUD shows the real count. Prices invented for the
-- in-game economy (a Meadow shell sells for 2 coins, a Forest shell for 5): the first upgrade is a few hunts away.
ProgressConfig.Baskets = {
	{ Id = "Starter", Name = "Starter Basket", Carry = Config.Carry.Capacity, Price = 0 },
	{ Id = "Picnic", Name = "Picnic Basket", Carry = 4, Price = 400 },
	{ Id = "Big", Name = "Big Basket", Carry = 5, Price = 1500 },
	{ Id = "Mega", Name = "Mega Basket", Carry = 6, Price = 7500 },
	{ Id = "Wagon", Name = "Egg Wagon", Carry = 8, Price = 40000 },
	{ Id = "Barrow", Name = "Wheelbarrow", Carry = 10, Price = 90000 },
	{ Id = "Cart", Name = "Egg Cart", Carry = 12, Price = 180000 },
	{ Id = "Crate", Name = "Giant Crate", Carry = 15, Price = 350000 },
	{ Id = "Golden", Name = "Golden Basket", Carry = 20, Price = 700000 }, -- owner: the biggest basket holds 20
} :: { Basket }

-- Nests: how many eggs wait in your nest tray (Config.Station.QueueCapacity is level 1) and how the nest looks.
-- Material is an Enum.Material name (this module stays free of Roblox enums so the offline tests can load it).
ProgressConfig.Nests = {
	{ Id = "Straw", Name = "Straw Nest", Queue = Config.Station.QueueCapacity, Price = 0, Color = Color3.fromRGB(246, 214, 128), Dark = Color3.fromRGB(214, 170, 90), Material = "SmoothPlastic" },
	{ Id = "Wood", Name = "Wood Nest", Queue = Config.Station.QueueCapacity + 2, Price = 800, Color = Color3.fromRGB(176, 118, 70), Dark = Color3.fromRGB(122, 80, 48), Material = "Wood" },
	{ Id = "Stone", Name = "Clay Nest", Queue = Config.Station.QueueCapacity + 4, Price = 2500, Color = Color3.fromRGB(168, 170, 176), Dark = Color3.fromRGB(110, 112, 120), Material = "Slate" },
	{ Id = "Gold", Name = "Gold Nest", Queue = Config.Station.QueueCapacity + 6, Price = 15000, Color = Color3.fromRGB(255, 204, 64), Dark = Color3.fromRGB(214, 150, 30), Material = "Foil" },
} :: { Nest }

-- The biggest tray any nest has (StationModels builds this many tray slots).
ProgressConfig.MaxQueue = Config.Station.QueueCapacity + 6

-- Level lookups clamp to the levels this build knows (a level from a newer build gets the biggest known one).
local function clampLevel(n: any, count: number): number
	if type(n) ~= "number" or n ~= n then
		return 1
	end
	return math.clamp(math.floor(n), 1, count)
end
ProgressConfig.clampLevel = clampLevel

function ProgressConfig.basket(level: any): Basket
	return ProgressConfig.Baskets[clampLevel(level, #ProgressConfig.Baskets)]
end

function ProgressConfig.nest(level: any): Nest
	return ProgressConfig.Nests[clampLevel(level, #ProgressConfig.Nests)]
end

function ProgressConfig.carry(level: any): number
	return ProgressConfig.basket(level).Carry
end

function ProgressConfig.queue(level: any): number
	return ProgressConfig.nest(level).Queue
end

-- Daily login gift: coins for day 1..7 of a streak (claim once per UTC day). Missing a day starts again at day 1;
-- after day 7 the streak goes round again at day 1.
ProgressConfig.DailyGift = { 25, 35, 45, 60, 75, 100, 300 }

-- Daily quests (owner pick 2026-10-11): every day has exactly one RACE quest (the egg hunt), one TOWER quest (the
-- pet tower) and one PET quest, in that order (Quests.forDay). Kind and goal are picked per player per UTC day.
-- Goals are picked from each list; Reward[i] pays for Goals[i]. Text uses %d for the goal; One is the text for 1.
-- Crack counts every egg opened in a hunt (most are empty); Hatch counts only hunt finds (the round's one pet), so
-- their words must differ (audit 2 #29: "Hatch 30 eggs 3/30" next to "Hatch any pet 0/1" read as a lost count).
export type QuestKind = { Kind: string, Group: string, Text: string, One: string?, Goals: { number }, Reward: { number } }
ProgressConfig.QuestGroups = { "Race", "Tower", "Pet" }
ProgressConfig.QuestsPerDay = #ProgressConfig.QuestGroups
ProgressConfig.QuestKinds = {
	{ Kind = "Crack", Group = "Race", Text = "Open %d eggs in hunts", Goals = { 10, 20, 30 }, Reward = { 40, 70, 100 } },
	{ Kind = "Sell", Group = "Race", Text = "Sell candy %d times", One = "Sell your candy once", Goals = { 1, 2 }, Reward = { 30, 60 } },
	{ Kind = "Hunt", Group = "Race", Text = "Play %d hunts", One = "Play a hunt", Goals = { 2, 3 }, Reward = { 50, 80 } },
	{ Kind = "Friend", Group = "Race", Text = "Play %d hunts with a friend", One = "Play a hunt with a friend", Goals = { 1 }, Reward = { 90 } },
	-- floors cleared today (QuestService.bump(player, "TowerFloors", n) from the tower, or the TowerFloorsToday field)
	{ Kind = "TowerFloors", Group = "Tower", Text = "Clear %d tower floors", One = "Clear a tower floor", Goals = { 3, 5, 8 }, Reward = { 50, 80, 120 } },
	{ Kind = "Hatch", Group = "Pet", Text = "Find the pet in %d hunts", One = "Find the pet in a hunt", Goals = { 1 }, Reward = { 80 } },
	{ Kind = "Display", Group = "Pet", Text = "Put %d pets on display", One = "Put a pet on display", Goals = { 1, 2 }, Reward = { 30, 50 } },
} :: { QuestKind }

-- Badges: REPLACE. The owner creates each badge on the Creator Dashboard (Experience > Associated items > Badges)
-- and pastes its id here. 0 = that badge is off (nothing is awarded, and it is awarded later once an id is set).
ProgressConfig.Badges = {
	FirstHatch = { Id = 0, Name = "First Hatch" }, -- hatch your first pet (the free starter pet does not count)
	FirstRare = { Id = 0, Name = "Rare Find" }, -- own a Rare, Epic or Legendary pet
	AllHuntPets = { Id = 0, Name = "Hunt Pet Master" }, -- find every hunt pet species (tower-only pets do not count)
	Tower25 = { Id = 0, Name = "Tower Floor 25" }, -- reach floor 25 of the pet tower (profile TowerBest)
	Forest = { Id = 0, Name = "Into the Forest" }, -- unlock the Forest zone
	SecretEgg = { Id = 0, Name = "Secret Egg" }, -- find the hidden egg in the lobby park (profile SecretEggFound)
}
ProgressConfig.BadgeOrder = { "FirstHatch", "FirstRare", "AllHuntPets", "Tower25", "Forest", "SecretEgg" }
ProgressConfig.RareRarities = { Rare = true, Epic = true, Legendary = true }
ProgressConfig.BadgeTowerFloor = 25
ProgressConfig.BadgeForestTier = "Quarry" -- the Forest zone's tier id (Config.Tiers.Quarry.Name = "Forest")

-- Hunt pet species: every species a hunt pile can hatch (listed by a zone), in zone order.
function ProgressConfig.huntSpecies(): { string }
	local out = {}
	for _, tid in Config.TierOrder do
		for _, id in SpeciesPool.list(tid, os.time()) do -- weekly pets count once they are out
			table.insert(out, id)
		end
	end
	return out
end

-- Pure milestone check used by the server badge service and the Stats tab: which badges this profile has reached.
-- `data` needs Stats, DiscoveryIndex, DiscoveryRarity, InventoryGeodes (or Inventory), TowerBest, UnlockedTiers and
-- SecretEggFound.
function ProgressConfig.badgeProgress(data: any): { [string]: { Done: boolean, Have: number, Need: number } }
	local stats = data.Stats or {}
	local finds = (tonumber(stats.SoloFinds) or 0) + (tonumber(stats.MultiplayerWins) or 0)
	local rare = false
	for _, list in { data.InventoryGeodes or {}, data.Inventory or {} } do
		for _, g in list do
			if type(g) == "table" and ProgressConfig.RareRarities[g.Rarity] then
				rare = true
			end
		end
	end
	for _, row in data.DiscoveryRarity or {} do
		if type(row) == "table" then
			for r, n in row do
				if ProgressConfig.RareRarities[r] and type(n) == "number" and n > 0 then
					rare = true
				end
			end
		end
	end
	local species = ProgressConfig.huntSpecies()
	local seen = 0
	for _, id in species do
		local idx = data.DiscoveryIndex and tonumber(data.DiscoveryIndex[id]) or 0
		local row = data.DiscoveryRarity and data.DiscoveryRarity[id]
		local any = idx > 0
		if not any and type(row) == "table" then
			for _, n in row do
				if type(n) == "number" and n > 0 then
					any = true
				end
			end
		end
		if any then
			seen += 1
		end
	end
	local tower = tonumber(data.TowerBest) or 0
	local forest = type(data.UnlockedTiers) == "table" and data.UnlockedTiers[ProgressConfig.BadgeForestTier] == true
	return {
		FirstHatch = { Done = finds >= 1, Have = math.min(finds, 1), Need = 1 },
		FirstRare = { Done = rare, Have = if rare then 1 else 0, Need = 1 },
		AllHuntPets = { Done = seen >= #species, Have = seen, Need = #species },
		Tower25 = { Done = tower >= ProgressConfig.BadgeTowerFloor, Have = math.min(tower, ProgressConfig.BadgeTowerFloor), Need = ProgressConfig.BadgeTowerFloor },
		Forest = { Done = forest, Have = if forest then 1 else 0, Need = 1 },
		SecretEgg = { Done = data.SecretEggFound == true, Have = if data.SecretEggFound == true then 1 else 0, Need = 1 },
	}
end

return ProgressConfig
