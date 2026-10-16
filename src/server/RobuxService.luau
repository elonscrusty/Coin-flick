--!strict
-- Robux shop (owner decision 2026-10-11; tuning in shared/RobuxConfig, luck rules in shared/LuckEvents).
-- Sells: paid pet eggs (Basic / Rare / Mythic as 1x, 3x, 10x; GeodeGen rolls for the buyer's best zone with the egg's
-- rarity table, full odds shown on the card; one receipt = 1, 3 or 10 pets), 15-minute luck
-- potions and three game passes (2x coins, extra plot slots, more pet storage). Runs the free luck events too:
-- 2x luck every UTC weekend and random 15-minute server-wide luck storms.
--
-- Purchases: the client names an item (RobuxAction "Buy"); the server checks it (real id > 0, paid eggs allowed by
-- PolicyService for this player, Pet Book room for every pet of the batch, potion stack not at the cap, pass not owned) and
-- opens the Roblox prompt. Nothing is granted by the prompt. Developer Products are granted in ProcessReceipt, keyed by
-- the receipt's PurchaseId: the id is recorded in the profile (Robux.Receipts) together with the grant, the profile is
-- saved, and only then PurchaseGranted is returned. A replayed receipt changes nothing; a missing / released profile or
-- a failed save answers NotProcessedYet so Roblox retries later. Game passes are recorded in the profile when bought
-- (PromptGamePassPurchaseFinished) and re-checked on join (UserOwnsGamePassAsync).
--
-- The EGG SHRINE (the public hatch stand, prompt added by MapHooks) sells the same eggs for coins (RobuxAction
-- "BuyEggCoins"; prices in RobuxConfig.CoinEggs): same hatch code, show and notices as a Robux egg.
--
-- There is one ProcessReceipt per server (StoreService owns it); this service registers a receipt route there
-- (Store.addReceiptRoute) for its own product ids.
--
-- With every id at 0 (RobuxConfig, REPLACE markers) nothing can be prompted or granted. NOT tested against real
-- purchases (needs the owner's ids and a Studio / live test).

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GeodeGen = require(Shared.GeodeGen)
local RobuxConfig = require(Shared.RobuxConfig)
local LuckEvents = require(Shared.LuckEvents)
local EggPerks = require(Shared.EggPerks)
local LaunchPerks = require(Shared.LaunchPerks)
local Profiles = require(script.Parent.Profiles)
local Kit = require(script.Parent.KitParts)
local CoinYard = require(Shared.CoinYard)
local RareHatch = require(script.Parent.RareHatch)

local Robux = {}

local HUT_NAME = require(Shared.MapNames).EggShop -- the hut model (hand-built map or fallback park)
local PANEL = "RobuxShop" -- client panel name (Main.client panels table)

local rng = Random.new()
-- PolicyService answer per player: false = paid random items allowed; true or missing = not allowed (hidden).
local restricted: { [Player]: boolean } = {}

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end

local function toastAll(text: string, kind: string?)
	Net.event("Toast"):FireAllClients(text, kind or "info")
end

-- Paid random items (eggs, and the luck potion that boosts random pet odds) are only offered once PolicyService
-- said they are allowed for this player. The server-set attribute mirrors `restricted` (clients cannot change a
-- server attribute); either one saying "restricted" blocks.
function Robux.eggsAllowed(player: Player): boolean
	return restricted[player] == false and player:GetAttribute("PaidRandomRestricted") == false
end

-- A failed PolicyService call keeps the player locked out and retries with backoff until it answers.
local function checkPolicy(player: Player)
	local delay = 2
	while player.Parent do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" and player.Parent then
			local blocked = info.ArePaidRandomItemsRestricted ~= false
			restricted[player] = blocked
			player:SetAttribute("PaidRandomRestricted", blocked) -- the shop hides paid eggs when true
			return
		end
		if player.Parent and restricted[player] == nil then
			restricted[player] = true
			player:SetAttribute("PaidRandomRestricted", true) -- locked until an answer arrives
		end
		task.wait(delay)
		delay = math.min(delay * 2, 60)
	end
end

local function stormUntil(): number
	local v = ReplicatedStorage:GetAttribute("LuckStormUntil")
	return if type(v) == "number" then v else 0
end

-- The luck a bought egg rolls with: 0 unless RobuxConfig.EggsUseLuck (then pets + potion + weekend + storm).
function Robux.eggLuck(data): number
	if not RobuxConfig.EggsUseLuck then
		return 0
	end
	local t = LuckEvents.timed(os.time(), tonumber(data.Robux.LuckUntil) or 0, stormUntil())
	return LuckEvents.total({ Pet = Profiles.petBoosts(data).Luck, Potion = t.Potion, Weekend = t.Weekend, Storm = t.Storm, Hour = t.Hour, Vip = RobuxConfig.vipLuck(data.Robux) })
end

-- Public hatch stand -------------------------------------------------------------------------------------------------

-- The stand (built by the park helper): a BasePart with attribute HatchStand = true (Attachment "HatchPoint" on it).
local function hatchStand(): BasePart?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
			return d
		end
	end
	return nil
end

-- Shows play one after another for every client (HatchStandView); with no stand in the world nothing is queued
-- (the buyer still gets the notice and the pets).
local shows: { any } = {}
local showing = false
local function queueShow(player: Player, egg: any, pets: { any }, best: any)
	if not hatchStand() or #shows >= RobuxConfig.Show.QueueMax then
		return
	end
	table.insert(shows, { Buyer = player.DisplayName, BuyerId = player.UserId, Egg = egg.Name, Count = #pets, Pet = GeodeGen.public(best) })
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #shows > 0 do
			local s = table.remove(shows, 1) :: any
			s.Waiting = #shows
			Net.event("HatchShow"):FireAllClients(s)
			task.wait(RobuxConfig.Show.Seconds)
		end
		showing = false
	end)
end

-- Egg hatching (shared by the Robux receipt and the coin shrine) -------------------------------------------------------

-- Rolls `count` pets of `egg` for the buyer's best zone (GeodeGen.roll with the egg's rarity table; Basic = the race
-- egg odds) and grants each under the award key "<keyBase>:<n>". Bought pets are granted even into a full Pet Book
-- (the buy request checked room). Returns the pets actually granted.
local function hatchLoop(player: Player, data, egg: any, count: number, keyBase: string): { any }
	local pets = {}
	local tierId = RobuxConfig.eggTier(data.UnlockedTiers)
	local luck = Robux.eggLuck(data)
	local perks = EggPerks.sanitize(data.EggPerks)
	data.EggPerks = perks
	for i = 1, count do
		local awardKey = keyBase .. ":" .. i
		-- Lucky Meter full: this egg is Epic or better (its Legendary chance unchanged, EggPerks.pityWeights)
		local lucky = EggPerks.full(perks.Meter)
		local weights = RobuxConfig.eggRarity(egg)
		if lucky then
			weights = EggPerks.pityWeights(weights)
		end
		local pet = GeodeGen.roll(Random.new(rng:NextInteger(1, 2 ^ 30)), tierId, HttpService:GenerateGUID(false), awardKey, os.time(), true, luck, weights, egg.ShinyOneIn)
		if Profiles.grantSpecimen(player, awardKey, pet, "Bought") then
			table.insert(pets, pet)
			perks.Meter = EggPerks.meterAfter(perks.Meter, egg.Id, pet.Rarity)
			if lucky then
				toast(player, "LUCKY METER full! Guaranteed " .. pet.Rarity:upper() .. " pet!", "rare")
			end
		end
	end
	return pets
end

local hatching: { [Player]: boolean } = {}
local function hatchEggs(player: Player, data, egg: any, count: number, keyBase: string): { any }
	-- grantSpecimen fires Profiles.changed, whose handlers run at once: openFreeEggs must not hatch a banked egg in the
	-- middle of this loop (it would read the same full Lucky Meter, so one meter paid two pity eggs)
	local outer = not hatching[player]
	hatching[player] = true
	local ok, pets = pcall(function()
		return hatchLoop(player, data, egg, count, keyBase)
	end)
	if outer then
		hatching[player] = nil
		task.defer(function()
			Robux.openFreeEggs(player) -- banked eggs wait until this hatch is done
		end)
	end
	if not ok then
		error(pets, 0)
	end
	return pets
end

-- One notice for the buyer (the best pet of the batch), one server-wide line per Rare+ pet (owner rule), the rare
-- hatch alert for the best one (banner + fireworks, and the sky beam over the shrine for Epic / Legendary; lobby
-- hangout idea 2) and the public hatch-stand show.
local function announceHatch(player: Player, data, egg: any, pets: { any })
	local best = pets[1]
	for _, pet in pets do
		if table.find(Config.Rarities, pet.Rarity) > table.find(Config.Rarities, best.Rarity) then
			best = pet
		end
	end
	for _, pet in pets do
		if pet ~= best and Config.Pets.AnnounceRarities[pet.Rarity] then
			toastAll(player.DisplayName .. " hatched a " .. pet.Rarity:upper() .. " " .. GeodeGen.displayName(pet) .. " from a " .. egg.Name .. "!", "rare")
		end
	end
	if best then
		RareHatch.announce(player, best)
		queueShow(player, egg, pets, best)
		local name = best.Rarity:upper() .. " " .. GeodeGen.displayName(best)
		local follows = table.find(data.EquippedPets or {}, best.Id) ~= nil
		toast(player, if #pets == 1 then "You hatched a " .. name .. (if follows then "! It follows you now." else "! It is in your Pet Book.") else "You hatched " .. #pets .. " pets! Best: " .. name .. ". See your Pet Book.", "rare")
	end
end

-- Hatch / potion notice per receipt key, shown once the grant is saved (a failed first save is retried by Roblox and
-- the retry is no longer "fresh", so the notice waits here).
local pendingNotice: { [string]: () -> () } = {}

-- Receipts ------------------------------------------------------------------------------------------------------------

-- Grants one Robux shop product for a receipt. Returns nil for a product this service does not sell (the dispatcher
-- then hands it to StoreService).
function Robux.processReceipt(info: { PlayerId: number, PurchaseId: any, ProductId: number }): Enum.ProductPurchaseDecision?
	local kind, item, count = RobuxConfig.productKind(info.ProductId)
	if not kind then
		return nil
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted when they are back on a server
	end
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) or Profiles.lockLost(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- the grant must land on the server that can save it
	end
	local key = tostring(info.PurchaseId)
	local state = data.Robux
	local fresh = not RobuxConfig.granted(state, key)
	local pets: { any } = {}
	if fresh then
		if kind == "Egg" then
			-- `count` rolls under this one receipt: GeodeGen.roll for the buyer's best zone with the egg's rarity table
			-- (Basic = the race egg odds). Paid pets are granted even into a full Pet Book (the prompt checked room).
			pets = hatchEggs(player, data, item, count, "robux:" .. key)
			state.EggsBought += #pets
		elseif kind == "Pack" then
			-- Starter pack: its eggs (hatched like bought eggs, one award key each) and its potion time, once. A second
			-- receipt (bought on two servers at once) is still granted in full: Roblox charged it.
			local pack = RobuxConfig.StarterPack
			for eggId, n in pack.Eggs do
				local egg = RobuxConfig.egg(eggId)
				if egg then
					for _, pet in hatchEggs(player, data, egg, n, "robux:" .. key .. ":" .. eggId) do
						table.insert(pets, pet)
					end
				end
			end
			state.EggsBought += #pets
			RobuxConfig.addPotion(state, os.time(), pack.PotionSeconds)
			state.StarterPack = true
		else
			RobuxConfig.addPotion(state, os.time())
		end
		RobuxConfig.remember(state, key) -- same mutation as the grant: saved together or not at all
		Profiles.changed(player, kind == "Potion")
	end
	-- PurchaseGranted only once the grant and the receipt id are saved; a failed save is retried by Roblox.
	if fresh then
		pendingNotice[key] = if kind == "Egg"
			then function()
				announceHatch(player, data, item, pets)
			end
			elseif kind == "Pack" then function()
				toast(player, "STARTER PACK! " .. #pets .. " pets and 2x luck for " .. LuckEvents.clock(RobuxConfig.potionLeft(state, os.time())) .. "!", "rare")
				if #pets > 0 then
					announceHatch(player, data, RobuxConfig.egg("RareEgg"), pets)
				end
			end
			else function()
				toast(player, "Luck potion on: 2x luck for " .. LuckEvents.clock(RobuxConfig.potionLeft(state, os.time())) .. "!", "ok")
			end
	end
	if not Profiles.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local notice = pendingNotice[key]
	if notice then
		pendingNotice[key] = nil
		notice()
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Game passes ---------------------------------------------------------------------------------------------------------

-- Pass looks other players see (server attributes; NameTag draws them): VIP = gold name tag.
local function passAttributes(player: Player, data: any)
	player:SetAttribute("VIP", if RobuxConfig.hasPass(data and data.Robux, "VIP") then true else nil)
end

local function grantPass(player: Player, key: string): boolean
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) or RobuxConfig.hasPass(data.Robux, key) then
		return false
	end
	data.Robux.Passes[key] = true
	passAttributes(player, data)
	Profiles.changed(player, true)
	return true
end

local function checkPasses(player: Player)
	for key, pass in RobuxConfig.Passes do
		if pass.PassId > 0 then
			local ok, owns = false, nil
			for attempt = 1, 3 do -- a pass bought on the website must not be lost to one failed check
				ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.PassId)
				end)
				if ok or not player.Parent then
					break
				end
				task.wait(2 * attempt)
			end
			if ok and owns == true and player.Parent then
				grantPass(player, key)
			end
		end
	end
end

-- Shop requests -------------------------------------------------------------------------------------------------------

local function buy(player: Player, data, id: string, count: any)
	local egg = RobuxConfig.egg(id)
	if egg then
		local n = if type(count) == "number" and table.find(RobuxConfig.EggCounts, count) then count else nil
		local productId = if n then egg.Products[n] or 0 else 0
		if productId <= 0 then
			return
		end
		if not RobuxConfig.eggOnSale(egg, os.time()) then
			toast(player, egg.Name .. " is not for sale anymore.", "info")
			return
		end
		if not Robux.eggsAllowed(player) then
			toast(player, "Pet eggs can't be bought with Robux on your account.", "warn")
			return
		end
		local full = RobuxConfig.roomRefusal(Profiles.inventoryMax(data) - #data.InventoryGeodes, n :: number)
		if full then
			toast(player, full, "warn")
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
		return
	end
	local pack = RobuxConfig.StarterPack
	if id == pack.Id then
		if pack.ProductId <= 0 then
			return
		end
		if data.Robux.StarterPack == true then
			toast(player, "You already have the Starter Pack.", "info")
			return
		end
		if not Robux.eggsAllowed(player) then -- it holds eggs: a paid random item
			toast(player, "The Starter Pack can't be bought with Robux on your account.", "warn")
			return
		end
		local eggs = 0
		for _, n in pack.Eggs do
			eggs += n
		end
		local full = RobuxConfig.roomRefusal(Profiles.inventoryMax(data) - #data.InventoryGeodes, eggs)
		if full then
			toast(player, full, "warn")
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, pack.ProductId)
		end)
		return
	end
	local potion = RobuxConfig.Potion
	if id == potion.Id then
		if potion.ProductId <= 0 then
			return
		end
		-- The potion raises the odds of a random pet reward, so it is a paid random-outcome item too: same
		-- PolicyService gate as the eggs. A receipt Roblox already charged is still granted (processReceipt).
		if not Robux.eggsAllowed(player) then
			toast(player, "Luck potions can't be bought with Robux on your account.", "warn")
			return
		end
		if RobuxConfig.potionLeft(data.Robux, os.time()) + potion.Seconds > potion.MaxStackSeconds then
			toast(player, "You have lots of potion time left. Try again later.", "warn")
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, potion.ProductId)
		end)
		return
	end
	local pass = RobuxConfig.Passes[id]
	if pass then
		if pass.PassId <= 0 then
			return
		end
		if RobuxConfig.hasPass(data.Robux, id) then
			toast(player, "You already own " .. pass.Name .. ".", "info")
			return
		end
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.PassId)
		end)
	end
end

-- Coin eggs at the EGG SHRINE (RobuxAction "BuyEggCoins", eggId, count; prices in RobuxConfig.CoinEggs) --------------

-- Same eggs, odds, pets and show as the Robux eggs, paid with coins. Checked here: the egg id and count, the paid
-- random item gate (PolicyService, same as the Robux eggs), Pet Book room for every pet (same refusal) and enough coins
-- for the buyer's zone price. The coins come off and the pets go in within one profile change, so a save holds both or
-- neither.
local SHRINE_SLACK = 10 -- studs beyond the prompt's reach
local buyCoinsAt: { [Player]: number } = {}
local hutPrompt: ProximityPrompt? = nil -- the EGG SHOP hut's prompt (hookHut): coin eggs sell there too

-- Near the EGG SHOP hut's prompt (the Pet Shop's Eggs tab sells the same eggs for coins).
local function nearHut(player: Player): boolean
	local pp = hutPrompt
	local part = if pp then pp.Parent else nil
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (pp and part and part:IsA("BasePart") and root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - part.Position).Magnitude <= pp.MaxActivationDistance + SHRINE_SLACK
end

local function nearStand(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- the coin yard's egg stand also sells eggs (server/CoinYardService)
	local yard = Workspace:FindFirstChild(CoinYard.FolderName)
	local yardStand = yard and yard:FindFirstChild(CoinYard.StandName)
	if yardStand and yardStand:IsA("BasePart") and root and root:IsA("BasePart") and (root.Position - yardStand.Position).Magnitude <= 14 + SHRINE_SLACK then
		return true
	end
	local stand = hatchStand()
	if not (stand and root and root:IsA("BasePart")) then
		return false
	end
	local prompt = stand:FindFirstChildWhichIsA("ProximityPrompt", true)
	local range = if prompt then prompt.MaxActivationDistance else 12
	return (root.Position - stand.Position).Magnitude <= range + SHRINE_SLACK
end

-- Returns true when the eggs were bought (auto hatch keeps going only then).
local function buyEggCoins(player: Player, data, id: any, count: any): boolean
	local now = os.clock()
	local prev = buyCoinsAt[player]
	if prev and now - prev < 0.45 then
		return false
	end
	-- the HUD SHOP button opens the Pet Shop anywhere; coin eggs still sell only at the EGG SHOP hut / hatch stand
	-- (Studio 2026-10-15: far away the tap did nothing at all, so say why)
	if not (nearStand(player) or nearHut(player)) then
		buyCoinsAt[player] = now
		toast(player, "Walk to the EGG SHOP to buy eggs with coins!", "info")
		return false
	end
	buyCoinsAt[player] = now
	local egg = RobuxConfig.egg(id)
	if not egg or type(count) ~= "number" or not table.find(RobuxConfig.CoinEggs.Counts, count) then
		return false
	end
	if not Robux.eggsAllowed(player) then
		toast(player, "Pet eggs can't be bought on your account.", "warn")
		return false
	end
	-- 3x / 10x need the Open 3 Eggs pass once that pass is on sale (RobuxConfig.CountPass)
	local needs = RobuxConfig.countPass(count)
	if needs and not RobuxConfig.hasPass(data.Robux, needs) then
		toast(player, "Get the " .. RobuxConfig.Passes[needs].Name .. " pass to hatch " .. count .. " at once!", "info")
		return false
	end
	local tierId = RobuxConfig.eggTier(data.UnlockedTiers)
	local price, why = RobuxConfig.coinEggCheck(egg.Id, count, tierId, data.Cash, Profiles.inventoryMax(data) - #data.InventoryGeodes)
	if not price then
		if why then
			toast(player, why, "warn")
		end
		return false
	end
	data.Cash -= price
	local pets = hatchEggs(player, data, egg, count, "coins:" .. HttpService:GenerateGUID(false))
	if #pets < count then
		data.Cash += (price // count) * (count - #pets) -- a pet that could not be granted is not paid for
	end
	Profiles.changed(player)
	if #pets > 0 then
		announceHatch(player, data, egg, pets)
		-- the shrine's "You got: ..." strip: each pet once, with how many
		local order, n = {}, {}
		for _, pet in pets do
			local name = pet.Rarity:upper() .. " " .. GeodeGen.displayName(pet)
			if not n[name] then
				table.insert(order, name)
			end
			n[name] = (n[name] or 0) + 1
		end
		local parts = {}
		for _, name in order do
			table.insert(parts, if n[name] > 1 then name .. " x" .. n[name] else name)
		end
		Net.event("RobuxAction"):FireClient(player, "Hatched", "You got: " .. table.concat(parts, ", "))
	end
	return #pets > 0
end

-- Auto hatch (Auto Hatch pass, idea 43): RobuxAction "AutoHatch", eggId (or "" to stop). The shrine buys the same
-- coin egg every RobuxConfig.Auto.Every seconds (3 at once with the Open 3 Eggs pass) while the player stays near it;
-- any refusal (coins, room, walked away, left) stops it. The chosen egg is remembered in Perks.AutoEgg for the UI.
local autoRun: { [Player]: number } = {} -- player -> run token (a new start or a stop ends the old loop)
local function stopAuto(player: Player, data: any?, why: string?)
	autoRun[player] = nil
	if data and data.Perks and data.Perks.AutoEgg ~= nil then
		data.Perks.AutoEgg = nil
		Profiles.changed(player, true)
	end
	if why then
		toast(player, why, "info")
	end
end

local function startAuto(player: Player, data: any, eggId: string)
	if eggId == "" then
		stopAuto(player, data, "Auto hatch off.")
		return
	end
	if RobuxConfig.Passes.AutoHatch.PassId <= 0 or not RobuxConfig.hasPass(data.Robux, "AutoHatch") then
		toast(player, "Get the Auto Hatch pass to hatch eggs on their own!", "info")
		return
	end
	if not (RobuxConfig.egg(eggId) and RobuxConfig.CoinEggs.Rounds[eggId]) then
		return
	end
	local token = (autoRun[player] or 0) + 1
	autoRun[player] = token
	local perks = LaunchPerks.sanitize(data.Perks)
	data.Perks = perks
	perks.AutoEgg = eggId
	Profiles.changed(player, true)
	toast(player, "Auto hatch on! Stay near the shrine.", "ok")
	task.spawn(function()
		local count = if RobuxConfig.hasPass(data.Robux, "TripleHatch") then 3 else 1
		for _ = 1, RobuxConfig.Auto.MaxHatches do
			if autoRun[player] ~= token or not player.Parent then
				return
			end
			local d = Profiles.get(player)
			if not d or Profiles.isReleased(player) then
				return
			end
			buyCoinsAt[player] = nil -- the auto loop is the one paced buyer here
			if not buyEggCoins(player, d, eggId, count) then
				if autoRun[player] == token then
					stopAuto(player, d, "Auto hatch stopped.")
				end
				return
			end
			task.wait(RobuxConfig.Auto.Every)
		end
		if autoRun[player] == token then
			stopAuto(player, Profiles.get(player), "Auto hatch stopped.")
		end
	end)
end

-- A free pet (lobby hangout: mystery egg drop, group gift), hatched from egg `eggId` exactly like a bought one (same
-- odds, show, notices and rare alert), only into a Pet Book with room. `keyBase` makes the award idempotent (the same
-- key never grants twice). Returns the pet, or nil (no room, unknown egg, profile not loaded).
function Robux.giftEgg(player: Player, eggId: string, keyBase: string): any?
	local data = Profiles.get(player)
	local egg = RobuxConfig.egg(eggId)
	if not data or not egg or Profiles.isReleased(player) or #data.InventoryGeodes >= Profiles.inventoryMax(data) then
		return nil
	end
	local pets = hatchEggs(player, data, egg, 1, keyBase)
	Profiles.changed(player)
	if pets[1] then
		announceHatch(player, data, egg, pets)
	end
	return pets[1]
end

-- Free eggs the player EARNED (EggPerks: every 3rd Pet Battle win, all daily quests) wait in profile EggPerks.Bank and
-- hatch here, best first, exactly like a bought egg (odds, Lucky Meter, show, notices), while the Pet Book has room.
-- Runs on every profile change, so a banked egg opens the moment a pet is sold or the player rejoins.
local opening: { [Player]: boolean } = {}
function Robux.openFreeEggs(player: Player): number
	local data = Profiles.get(player)
	if opening[player] or hatching[player] or not data or Profiles.isReleased(player) or not player.Parent then
		return 0
	end
	local perks = EggPerks.sanitize(data.EggPerks)
	data.EggPerks = perks
	if EggPerks.bankCount(perks) == 0 or #data.InventoryGeodes >= Profiles.inventoryMax(data) then
		return 0
	end
	opening[player] = true
	local opened = 0
	local pending: string? = nil -- taken from the bank, not hatched yet
	local ok, err = pcall(function()
		while #data.InventoryGeodes < Profiles.inventoryMax(data) do
			local id = EggPerks.bankTake(perks)
			local egg = if id then RobuxConfig.egg(id) else nil
			if not (id and egg) then
				break
			end
			pending = id
			local pets = hatchEggs(player, data, egg, 1, "free:" .. HttpService:GenerateGUID(false))
			pending = nil
			if #pets == 0 then
				EggPerks.bankAdd(perks, id) -- not granted: keep it for later
				break
			end
			opened += 1
			announceHatch(player, data, egg, pets)
		end
	end)
	if pending then
		EggPerks.bankAdd(perks, pending) -- the hatch failed before the pet was made: the egg goes back
	end
	Profiles.changed(player) -- before the flag clears: its handlers must not re-enter (a failing egg would loop)
	opening[player] = nil -- always cleared, so one error never blocks free eggs until a rejoin
	if not ok then
		warn("[Robux] free egg hatch failed: " .. tostring(err))
	end
	return opened
end

-- Luck events ---------------------------------------------------------------------------------------------------------

-- Starts a luck storm on this server now (also used by tests / previews).
function Robux.startStorm(seconds: number?)
	local secs = seconds or RobuxConfig.Events.StormSeconds
	ReplicatedStorage:SetAttribute("LuckStormUntil", os.time() + secs)
	toastAll("LUCK STORM! 2x luck for " .. math.floor(secs / 60 + 0.5) .. " minutes!", "rare")
end

local function runEvents()
	ReplicatedStorage:SetAttribute("LuckStormUntil", 0)
	local weekend = LuckEvents.isWeekend(os.time())
	ReplicatedStorage:SetAttribute("LuckWeekend", weekend)
	task.spawn(function()
		while true do
			task.wait(30)
			local w = LuckEvents.isWeekend(os.time())
			if w ~= weekend then
				weekend = w
				ReplicatedStorage:SetAttribute("LuckWeekend", w)
				toastAll(if w then "WEEKEND LUCK! 2x luck all weekend!" else "Weekend luck is over.", if w then "rare" else "info")
			end
		end
	end)
	-- lucky hour (LaunchPerks.luckyHourUntil): the same UTC hours on every server, announced when it starts and ends
	local hourUntil = LaunchPerks.luckyHourUntil(os.time())
	ReplicatedStorage:SetAttribute("LuckyHourUntil", hourUntil)
	task.spawn(function()
		while true do
			task.wait(15)
			local u = LaunchPerks.luckyHourUntil(os.time())
			if (u > 0) ~= (hourUntil > 0) then
				toastAll(if u > 0 then "LUCKY HOUR! 2x luck for " .. RobuxConfig.Events.LuckyHourMinutes .. " minutes!" else "Lucky hour is over.", if u > 0 then "rare" else "info")
			end
			if u ~= hourUntil then
				hourUntil = u
				ReplicatedStorage:SetAttribute("LuckyHourUntil", u)
			end
		end
	end)
	task.spawn(function()
		local gap = LuckEvents.nextGap(rng, true)
		while true do
			task.wait(gap)
			Robux.startStorm()
			task.wait(RobuxConfig.Events.StormSeconds)
			toastAll("The luck storm is over.", "info")
			gap = LuckEvents.nextGap(rng)
		end
	end)
end

-- EGG SHOP hut ---------------------------------------------------------------------------------------------------------

-- The lobby hut (a Model or part named MapNames.EggShop, built elsewhere) opens the shop through a ProximityPrompt whose
-- "Panel" attribute is "RobuxShop". A prompt the hut already has is reused; otherwise one is added to its
-- "PromptAnchor" / "Counter" part, its PrimaryPart or its first part.
local function hookHut(hut: Instance)
	if hut:GetAttribute("RobuxShopHooked") then
		return
	end
	local existing = hut:FindFirstChildWhichIsA("ProximityPrompt", true)
	if existing then
		-- the map hooks leave the counter prompt disabled until a shop exists; this is that shop. It opens even while
		-- every id is still 0 (owner, 2026-10-15): the Pet Shop shows SOON on those prices instead of a dead door.
		existing.Enabled = true
		existing.ActionText = "Open"
		existing:SetAttribute("Panel", PANEL)
		-- the prompt card's big line names the shop, the small one the action (the lodge stand-in had them the other
		-- way round, so the card read "COMING SOON" big over a small shop name)
		existing.ObjectText = "Egg Shop"
		hutPrompt = existing
	else
		local anchor: Instance? = hut:FindFirstChild("PromptAnchor", true) or hut:FindFirstChild("Counter", true)
		if not (anchor and anchor:IsA("BasePart")) then
			anchor = if hut:IsA("BasePart") then hut elseif hut:IsA("Model") and hut.PrimaryPart then hut.PrimaryPart else hut:FindFirstChildWhichIsA("BasePart", true)
		end
		if not (anchor and anchor:IsA("BasePart")) then
			return -- no part yet: DescendantAdded tries again when the hut's parts arrive
		end
		-- ObjectText is the shop's name (the prompt card shows it as its big line, the action under it)
		local pp = Kit.prompt(anchor, "Open", "Egg Shop", PANEL, 12)
		pp.Enabled = true
		pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		hutPrompt = pp
	end
	hut:SetAttribute("RobuxShopHooked", true)
end

local function watchHut()
	local found = Workspace:FindFirstChild(HUT_NAME, true)
	if found then
		hookHut(found)
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d.Name == HUT_NAME then
			task.defer(hookHut, d)
		elseif d:IsA("BasePart") then
			local hut = d:FindFirstAncestor(HUT_NAME)
			if hut and not hut:GetAttribute("RobuxShopHooked") then
				task.defer(hookHut, hut)
			end
		end
	end)
end

-- Boot -----------------------------------------------------------------------------------------------------------------

function Robux.start()
	local Store = require(script.Parent.StoreService)
	local last: { [Player]: number } = {}
	local function onPlayer(p: Player)
		task.spawn(checkPolicy, p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	-- banked free eggs (EggPerks) hatch on join and as soon as there is room
	Profiles.onLoaded(function(p)
		Robux.openFreeEggs(p)
	end)
	Profiles.onChanged(function(p)
		Robux.openFreeEggs(p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
		restricted[p] = nil
		opening[p] = nil
		buyCoinsAt[p] = nil
		autoRun[p] = nil
	end)
	Profiles.onLoaded(function(player)
		passAttributes(player, Profiles.get(player))
		checkPasses(player)
		task.delay(8, function()
			if not player.Parent then
				return
			end
			if stormUntil() > os.time() then
				toast(player, "A LUCK STORM is on: 2x luck for " .. LuckEvents.clock(stormUntil() - os.time()) .. "!", "rare")
			elseif ReplicatedStorage:GetAttribute("LuckWeekend") == true then
				toast(player, "WEEKEND LUCK is on: 2x luck all weekend!", "rare")
			end
		end)
	end)
	Net.event("RobuxAction").OnServerEvent:Connect(function(player, action, arg, count)
		local t = os.clock()
		if last[player] and t - last[player] < 0.4 then
			return
		end
		last[player] = t
		local data = Profiles.get(player)
		if not data or Profiles.isReleased(player) or type(arg) ~= "string" then
			return
		end
		if action == "Buy" then
			buy(player, data, arg, count)
		elseif action == "BuyEggCoins" then
			buyEggCoins(player, data, arg, count)
		elseif action == "AutoHatch" then
			startAuto(player, data, arg)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local key = RobuxConfig.passKey(passId)
		if not (purchased and key) then
			return
		end
		task.spawn(function()
			-- bought before the profile finished loading: wait for it instead of waiting for a rejoin
			local t0 = os.clock()
			while player.Parent and not Profiles.get(player) and os.clock() - t0 < 60 do
				task.wait(0.5)
			end
			-- The finished event is not proof of a purchase (an exploit client can make it fire with purchased =
			-- true): only Roblox's own ownership check grants the pass. A few tries cover the moment right after a
			-- real purchase; if none says yes, the next join's checkPasses grants it.
			local owns = false
			for attempt = 1, 4 do
				if not player.Parent then
					return
				end
				local ok, res = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
				end)
				if ok and res == true then
					owns = true
					break
				end
				task.wait(2 * attempt)
			end
			if owns and player.Parent and grantPass(player, key) then
				toast(player, "Thanks! " .. RobuxConfig.Passes[key].Name .. " is yours.", "ok")
				Profiles.saveNow(player)
			end
		end)
	end)
	-- Roblox allows one ProcessReceipt: StoreService owns it and hands Robux shop products to this route.
	Store.addReceiptRoute(Robux.processReceipt)
	runEvents()
	watchHut()
end

return Robux
