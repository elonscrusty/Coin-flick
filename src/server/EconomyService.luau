--!strict
-- Cash, rubble sales, equipment, capacity, tier unlocks, collection actions and settings.
-- Every price is read from Config on the server; clients only name what they want.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ProgressConfig = require(Shared.ProgressConfig)
local WhatsNew = require(Shared.WhatsNew)
local Profiles = require(script.Parent.Profiles)
local GearKit = require(Shared.GearKit)
local KitModels = require(Shared.KitModels)
local QuestService = require(script.Parent.QuestService)
local BadgeService = require(script.Parent.BadgeService)

local Economy = {}

local saleListener: ((Player, number, number) -> ())? = nil
function Economy.setSaleListener(fn: (Player, number, number) -> ())
	saleListener = fn
end

local toolChangedHandler: ((Player, string) -> ())? = nil
local displayChangedHandler: ((Player) -> ())? = nil
local machineHandler: ((Player, string, string?) -> ())? = nil -- (player, "Install" | "Toggle", machine id)
local skipHandler: ((Player) -> ())? = nil -- tutorial skipped (Main: PetService.ensureStarter)

function Economy.onTutorialSkipped(fn: (Player) -> ())
	skipHandler = fn
end

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end

-- Upgrade levels the world reads from the player (StationModels.setOwner dresses a nest in its owner's nest
-- level). The round core reads the sizes from the profile itself (RockService.refreshSpace).
function Economy.syncLevels(player: Player)
	local data = Profiles.get(player)
	if data then
		player:SetAttribute("NestLevel", ProgressConfig.clampLevel(data.NestLevel, #ProgressConfig.Nests))
		player:SetAttribute("BasketLevel", ProgressConfig.clampLevel(data.BasketLevel, #ProgressConfig.Baskets))
	end
end

local function spend(player: Player, data, price: number): boolean
	if data.Cash < price then
		toast(player, "Not enough coins (need " .. price .. ").", "warn")
		return false
	end
	data.Cash -= price
	return true
end

-- Tool visual: the equipped handheld welded to the character's right hand.
-- Standing height of an avatar in studs (R15, R6 or a custom rig), for sizing held tools.
function Economy.avatarHeight(char: Model): number
	local head = char:FindFirstChild("Head")
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if head and head:IsA("BasePart") and root and root:IsA("BasePart") and hum then
		local legs = if hum.RigType == Enum.HumanoidRigType.R15 then hum.HipHeight else 2
		local h = head.Position.Y + head.Size.Y / 2 - (root.Position.Y - root.Size.Y / 2 - legs)
		if h > 2 and h < 30 then
			return h
		end
	end
	local ok, size = pcall(function()
		return char:GetExtentsSize()
	end)
	if ok and size.Y > 2 and size.Y < 30 then
		return size.Y
	end
	return 5.3
end

-- Rest (carry) rotation of the held tool in the hand's frame (hand hanging: -Y down, -Z forward).
function Economy.restGrip(toolId: string): CFrame
	if toolId == "Jackhammer" then
		return CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(-62))
	end
	-- the head turned to run front-to-back (a quarter turn about the handle): sideways it reached into the hip and leg of
	-- the avatar (owner video: the pink head clipped the body)
	return CFrame.Angles(math.rad(-28), 0, 0) * CFrame.Angles(0, math.rad(90), 0)
end

-- The held tool is a hunt thing: it shows only while the player is in a hunt (MatchKey set by MatchService, also in the
-- Match place). In the lobby the hands are empty (owner video: the pink hammer showed in the lobby).
local toolWatch: { [Player]: RBXScriptConnection } = {}
local function inHunt(player: Player): boolean
	return player:GetAttribute("MatchKey") ~= nil
end

function Economy.attachTool(player: Player)
	local char = player.Character
	local data = Profiles.get(player)
	if not char or not data then
		return
	end
	local old = char:FindFirstChild("CT_Rocks_GearAccessory")
	if old then
		old:Destroy()
	end
	if not toolWatch[player] then
		toolWatch[player] = player:GetAttributeChangedSignal("MatchKey"):Connect(function()
			Economy.attachTool(player) -- entering a hunt attaches it, leaving takes it away
		end)
		player.AncestryChanged:Connect(function(_, parent)
			if parent == nil and toolWatch[player] then
				toolWatch[player]:Disconnect()
				toolWatch[player] = nil
			end
		end)
	end
	if not inHunt(player) then
		return
	end
	-- Pet gear is passive: nothing is held. The owned gear shows as a small hip accessory (kit model, welded,
	-- massless, non-colliding) when the owner's Gear_<Id> model exists; otherwise nothing at all.
	local toolId = data.EquippedHandheld
	local gearName = GearKit.accessoryModel(toolId)
	local template = if gearName then KitModels.template(gearName) else nil
	local root = char:FindFirstChild("HumanoidRootPart")
	if not template or not root or not root:IsA("BasePart") then
		return
	end
	local acc = template:Clone()
	acc.Name = "CT_Rocks_GearAccessory"
	acc:SetAttribute("ToolId", toolId)
	local height = Economy.avatarHeight(char)
	-- measure only what shows: hidden helper parts made the box bigger, so the visible gear came out small
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in acc:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			for _, sx in { -0.5, 0.5 } do
				for _, sy in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local p = d.CFrame:PointToWorldSpace(d.Size * Vector3.new(sx, sy, sz))
						lo, hi = lo:Min(p), hi:Max(p)
					end
				end
			end
		end
	end
	local size = if lo.X < math.huge then hi - lo else select(2, acc:GetBoundingBox())
	local longest = math.max(size.X, size.Y, size.Z, 0.1)
	acc:ScaleTo(GearKit.accessoryScale(longest, height) * acc:GetScale())
	for _, d in acc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local primary = acc.PrimaryPart or acc:FindFirstChildWhichIsA("BasePart")
	if not primary then
		acc:Destroy()
		return
	end
	acc.PrimaryPart = primary
	acc:PivotTo(root.CFrame * CFrame.new(1.1, -0.9, 0.35) * CFrame.Angles(0, 0, math.rad(25)))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "GearWeld"
	weld.Part0 = root
	weld.Part1 = primary
	weld.Parent = primary
	acc.Parent = char
end

local lastSale: { [Player]: number } = {}
local SALE_GAP = 0.6 -- a second sell request this soon is a double tap, not a new sale

-- The one rubble sale (hopper prompt and the HUD button). The receipt the player sees is built from the
-- numbers returned here (count, total, new balance), never from what the client previewed.
local function sellRubble(player: Player, at: Vector3?)
	local data = Profiles.get(player)
	if not data then
		return
	end
	local t = os.clock()
	if t - (lastSale[player] or -math.huge) < SALE_GAP then
		return
	end
	-- Only rubble this build can price is sold; rubble of an unknown (newer) tier stays in the bag.
	local count, total = Profiles.sellableRubble(data)
	if count == 0 then
		toast(player, "Your candy bag is empty. Nothing to sell.", "info")
		return
	end
	lastSale[player] = t
	for tierId: string in table.clone(data.RubbleByTier) :: { [string]: number } do
		if Config.Tiers[tierId] then
			data.RubbleByTier[tierId] = nil
		end
	end
	data.Cash += total
	data.Stats.CashEarned += total
	Profiles.changed(player, true)
	Profiles.onboard(player, "Sold")
	Net.event("Toast"):FireClient(player, "Sold " .. count .. " candy for " .. total .. " coins", "cash")
	Net.event("Fx"):FireClient(player, "Sell", { Pos = at, Count = count, Total = total, Cash = data.Cash })
	if saleListener then
		saleListener(player, count, total) -- the hunt ledger (MatchService)
	end
	QuestService.note(player, "Sell", 1)
end
Economy.sellRubble = sellRubble

-- The HUD's SELL RUBBLE button (the same sale as the hopper prompt): only when the avatar is close
-- to a hopper, measured by the server from the character, never from anything the client sends.
-- Hoppers are found by one Workspace scan that is cached server-wide and redone at most once per
-- HOPPER_RESCAN seconds (a miss can trigger it), so spamming the button never walks the whole world.
local HOPPER_RESCAN = 2
local hopperBodies: { BasePart } = {}
local hopperScanAt = -math.huge
local function scanHoppers()
	hopperScanAt = os.clock()
	table.clear(hopperBodies)
	for _, d in game:GetService("Workspace"):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Hopper") then
			local body = d:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				table.insert(hopperBodies, body)
			end
		end
	end
end

local function nearestHopperBody(player: Player, range: number): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local function nearest(): BasePart?
		local best: BasePart? = nil
		local bestD = range
		for _, body in hopperBodies do
			if body.Parent and body:IsDescendantOf(game:GetService("Workspace")) then
				local dist = Vector3.new(body.Position.X - root.Position.X, 0, body.Position.Z - root.Position.Z).Magnitude
				if dist <= bestD then
					best, bestD = body, dist
				end
			end
		end
		return best
	end
	local best = nearest()
	if not best and os.clock() - hopperScanAt >= HOPPER_RESCAN then
		scanHoppers() -- a hopper built since the last scan (new arena) is picked up here
		best = nearest()
	end
	return best
end

-- Level purchases (storage, gallery slots) have no item id, so a double tap would buy two levels. A repeat
-- of the same kind this soon is dropped; a client may also send the level it expects to buy as `id`
-- (a number), and a request for any other level is refused (the shop showed stale data).
local LEVEL_GAP = 1.0
local lastLevelBuy: { [Player]: { [string]: number } } = {}
local displayQuestSeen: { [Player]: { Day: string, Ids: { [string]: boolean } } } = {} -- pets counted for today's Display quest
-- The daily Display quest counts different pets, so placing and removing one pet again (by any display action)
-- does not farm it.
local function noteDisplay(player: Player, id: string)
	local day = os.date("!%Y%m%d")
	local prev = displayQuestSeen[player]
	local ids: { [string]: boolean } = if prev and prev.Day == day then prev.Ids else {}
	displayQuestSeen[player] = { Day = day, Ids = ids }
	if not ids[id] then
		ids[id] = true
		QuestService.note(player, "Display")
	end
end
local function levelRequestOk(player: Player, kind: string, expected: any, nextLevel: number): boolean
	if type(expected) == "number" and expected ~= nextLevel then
		return false
	end
	local t = os.clock()
	local mine = lastLevelBuy[player]
	if not mine then
		mine = {}
		lastLevelBuy[player] = mine
	end
	if t - (mine[kind] or -math.huge) < LEVEL_GAP then
		return false
	end
	mine[kind] = t
	return true
end

local function handleShop(player: Player, action: any, id: any)
	local data = Profiles.get(player)
	if not data or type(action) ~= "string" then
		return
	end
	if action == "SellAtHopper" then
		local body = nearestHopperBody(player, 12)
		if body then
			sellRubble(player, body.Position)
		else
			toast(player, "Walk up to a SELL bin first.", "info")
		end
		return
	end
	if action == "BuyHandheld" then
		local h = if type(id) == "string" then Config.Handhelds[id] else nil
		if not h then
			return
		end
		if data.EquipmentOwned[h.Id] then
			toast(player, "You already own the " .. h.Name .. ".", "info")
			return
		end
		if spend(player, data, h.Price) then
			data.EquipmentOwned[h.Id] = true
			data.EquippedHandheld = h.Id
			toast(player, "Bought and equipped the " .. h.Name .. "!", "ok")
			Profiles.changed(player, true)
			Economy.attachTool(player)
			if toolChangedHandler then
				toolChangedHandler(player, h.Id)
			end
		end
	elseif action == "Equip" then
		local h = if type(id) == "string" then Config.Handhelds[id] else nil
		if h and data.EquipmentOwned[h.Id] and data.EquippedHandheld ~= h.Id then
			data.EquippedHandheld = h.Id
			Profiles.changed(player, true)
			Economy.attachTool(player)
			if toolChangedHandler then
				toolChangedHandler(player, h.Id)
			end
		end
	elseif action == "BuyMachine" then
		-- Price comes from Config on the server; one machine is installed at a time, owned ones do not stack.
		local mc = type(id) == "string" and Config.Machines[id]
		if not Config.MachinesEnabled or not mc then
			return
		end
		if data.EquipmentOwned[mc.Id] then
			toast(player, "You already own the " .. mc.Name .. ".", "info")
			return
		end
		if spend(player, data, mc.Price) then
			data.EquipmentOwned[mc.Id] = true
			data.InstalledMachine = mc.Id
			toast(player, "Bought and installed the " .. mc.Name .. "!", "ok")
			Profiles.changed(player, true)
			if machineHandler then
				machineHandler(player, "Install", mc.Id)
			end
		end
	elseif action == "InstallMachine" then
		local mc = type(id) == "string" and Config.Machines[id]
		if Config.MachinesEnabled and mc and data.EquipmentOwned[mc.Id] and data.InstalledMachine ~= mc.Id then
			data.InstalledMachine = mc.Id
			Profiles.changed(player, true)
			if machineHandler then
				machineHandler(player, "Install", mc.Id)
			end
		end
	elseif action == "ToggleMachine" then
		if Config.MachinesEnabled and data.InstalledMachine and machineHandler then
			machineHandler(player, "Toggle", nil)
		end
	elseif action == "BuyCapacity" then
		local nextLvl = Config.Capacity[data.CapacityTier + 1]
		if not nextLvl or not levelRequestOk(player, "Capacity", id, data.CapacityTier + 1) then
			return
		end
		if spend(player, data, nextLvl.Price) then
			data.CapacityTier += 1
			toast(player, "Candy bag now holds " .. nextLvl.Size .. ".", "ok")
			Profiles.changed(player, true)
		end
	elseif action == "BuyBasket" or action == "BuyNest" then
		-- Coins only (ProgressConfig prices). One level at a time; `id` is the level the shop showed.
		local isBasket = action == "BuyBasket"
		local list = if isBasket then ProgressConfig.Baskets else ProgressConfig.Nests
		local field = if isBasket then "BasketLevel" else "NestLevel"
		local cur = data[field]
		local nextLvl: any = list[cur + 1]
		if not nextLvl or cur < 1 or not levelRequestOk(player, field, id, cur + 1) then
			return
		end
		if spend(player, data, nextLvl.Price) then
			data[field] = cur + 1
			if isBasket then
				toast(player, nextLvl.Name .. ": carry " .. nextLvl.Carry .. " eggs per trip!", "ok")
			else
				toast(player, nextLvl.Name .. ": your nest holds " .. nextLvl.Queue .. " eggs!", "ok")
			end
			Profiles.changed(player, true)
			Economy.syncLevels(player)
		end
	elseif action == "ClaimGift" or action == "ClaimQuest" then
		QuestService.handle(player, action, id)
	elseif action == "BuyDisplay" then
		local nextLvl = Config.Display[data.DisplayCapacity + 1]
		if not nextLvl or not levelRequestOk(player, "Display", id, data.DisplayCapacity + 1) then
			return
		end
		if spend(player, data, nextLvl.Price) then
			data.DisplayCapacity += 1
			toast(player, "Pet Lodge now shows " .. nextLvl.Slots .. " pets.", "ok")
			Profiles.changed(player, true)
		end
	elseif action == "UnlockTier" then
		local tier = if type(id) == "string" then Config.Tiers[id] else nil
		if not tier or data.UnlockedTiers[tier.Id] then
			return
		end
		local finds = Profiles.finds(data)
		if finds < tier.UnlockFinds then
			toast(player, "Need " .. tier.UnlockFinds .. " pet finds (you have " .. finds .. ").", "warn")
			return
		end
		-- previous tier must be unlocked first
		local prev = Config.TierOrder[tier.Order - 1]
		if prev and not data.UnlockedTiers[prev] then
			toast(player, "Unlock " .. prev .. " first.", "warn")
			return
		end
		if spend(player, data, tier.UnlockCash) then
			data.UnlockedTiers[tier.Id] = true
			toast(player, tier.Name .. " zone unlocked!", "ok")
			Profiles.changed(player, true)
		end
	end
end

local function handleCollection(player: Player, action: any, a: any, b: any)
	local data = Profiles.get(player)
	if not data or type(action) ~= "string" then
		return
	end
	if action == "Favorite" then
		local _, g = Profiles.findGeode(data, if type(a) == "string" then a else "")
		if g then
			g.Favorite = b == true
			Profiles.changed(player)
		end
	elseif action == "Display" then
		local id = if type(a) == "string" then a else ""
		local _, g = Profiles.findGeode(data, id)
		if not g then
			return
		end
		local idx = table.find(data.DisplayAssignments, id)
		if b == true and not idx then
			if #data.DisplayAssignments >= Profiles.displaySlots(data) then
				toast(player, "Pet Lodge is full. Upgrade slots or remove one.", "warn")
				return
			end
			table.insert(data.DisplayAssignments, id)
			data.Onboard.Displayed = true
			noteDisplay(player, id)
		elseif b ~= true and idx then
			table.remove(data.DisplayAssignments, idx)
			data.RoamPets = Profiles.roamList(data) -- a pet off display stops roaming
		else
			return
		end
		Profiles.changed(player)
		if displayChangedHandler then
			displayChangedHandler(player)
		end
	elseif action == "DisplayAt" then
		-- Slot chooser: a = specimen id, b = slot number (1..slots). DisplayAssignments stays a dense list whose
		-- position is the alcove slot. Empty slot: place (or move to the end). Occupied slot: replace (the old
		-- specimen simply returns to the collection) or, for a specimen already on show, swap the two slots.
		local id = if type(a) == "string" then a else ""
		local slotNo = if type(b) == "number" and b == b and b >= 1 and b <= 64 then math.floor(b) else 0
		local _, g = Profiles.findGeode(data, id)
		if not g or slotNo == 0 or slotNo > Profiles.displaySlots(data) then
			return
		end
		local list = data.DisplayAssignments
		local from = table.find(list, id)
		if slotNo > #list then
			if from then
				table.remove(list, from)
				table.insert(list, id)
			else
				table.insert(list, id)
				data.Onboard.Displayed = true
				noteDisplay(player, id)
			end
		elseif from == slotNo then
			return
		elseif from then
			list[from], list[slotNo] = list[slotNo], list[from]
		else
			list[slotNo] = id
			data.RoamPets = Profiles.roamList(data) -- the replaced pet left the display, so it stops roaming
			data.Onboard.Displayed = true
			noteDisplay(player, id)
		end
		Profiles.changed(player)
		if displayChangedHandler then
			displayChangedHandler(player)
		end
	elseif action == "Sell" then
		-- a = list of specimen ids, b = expected total the client showed (must match exactly)
		if type(a) ~= "table" or #a == 0 or #a > #data.InventoryGeodes then
			return
		end
		local seen = {}
		local total = 0
		local idxs = {}
		for _, id in a do
			if type(id) ~= "string" or seen[id] then
				return
			end
			seen[id] = true
			local i, g = Profiles.findGeode(data, id)
			if not i then
				toast(player, "Some of those pets are gone. Refresh and try again.", "warn")
				return
			end
			if type(g.Value) ~= "number" or g.Value ~= g.Value or g.Value < 0 then
				toast(player, "One of those pets can't be sold right now.", "warn")
				return
			end
			if g.Favorite then
				toast(player, "Favourites can't be sold. Unfavourite first.", "warn")
				return
			end
			if table.find(data.DisplayAssignments, id) then
				toast(player, "Remove displayed pets from the Pet Lodge first.", "warn")
				return
			end
			-- Robux egg pets sell for a token share (Profiles.priceValue), so Robux never turns into coins
			total += math.floor(Profiles.priceValue(g) * Config.Sell.SpecimenFraction)
			table.insert(idxs, i)
		end
		if b ~= total then
			toast(player, "Sale value changed. Check and confirm again.", "warn")
			return
		end
		table.sort(idxs, function(x, y)
			return x > y
		end)
		for _, i in idxs do
			table.remove(data.InventoryGeodes, i)
		end
		data.Cash += total
		data.Stats.CashEarned += total
		Profiles.changed(player)
		toast(player, "Sold " .. #idxs .. " pet" .. (if #idxs == 1 then "" else "s") .. " for " .. total .. " coins", "cash")
	end
end

local function handleSettings(player: Player, s: any)
	local data = Profiles.get(player)
	if not data or type(s) ~= "table" then
		return
	end
	local out = data.Settings
	for _, k in { "Music", "Sfx", "CameraSensitivity" } do
		if type(s[k]) == "number" and s[k] == s[k] then
			out[k] = math.clamp(s[k], 0, 1)
		end
	end
	for _, k in { "ReducedMotion", "LowEffects", "Hints" } do
		if type(s[k]) == "boolean" then
			out[k] = s[k]
		end
	end
	local news = WhatsNew.accept(s.LastSeenNews) -- WHAT'S NEW pop-up seen (only the current version is stored)
	if news then
		data.LastSeenNews = news
	end
	Profiles.changed(player, true)
end

function Economy.onToolChanged(fn: (Player, string) -> ())
	toolChangedHandler = fn
end

function Economy.onMachine(fn: (Player, string, string?) -> ())
	machineHandler = fn
end

function Economy.onDisplayChanged(fn: (Player) -> ())
	displayChangedHandler = fn
end

function Economy.start()
	-- Daily gift / quests and badges ride on the profile and shop remotes, so they start with the economy.
	QuestService.start()
	BadgeService.start()
	Profiles.onLoaded(Economy.syncLevels)
	Players.PlayerRemoving:Connect(function(p)
		lastSale[p] = nil
		lastLevelBuy[p] = nil
		displayQuestSeen[p] = nil
	end)
	local function limited(fn)
		local last: { [Player]: { n: number, t: number } } = {}
		Players.PlayerRemoving:Connect(function(p)
			last[p] = nil
		end)
		return function(player: Player, ...)
			local t = os.clock()
			local l = last[player]
			if not l or t - l.t > 1 then
				local fresh = { n = 0, t = t }
				last[player] = fresh
				l = fresh
			end
			l.n += 1
			if l.n <= 6 then
				if Profiles.isReleased(player) then
					return -- profile handed over for a teleport: nothing may change here now
				end
				fn(player, ...)
			end
		end
	end
	Net.event("ShopAction").OnServerEvent:Connect(limited(handleShop))
	Net.event("CollectionAction").OnServerEvent:Connect(limited(handleCollection))
	Net.event("SettingsAction").OnServerEvent:Connect(limited(handleSettings))
	Net.event("TutorialAction").OnServerEvent:Connect(limited(function(player: Player, action: any)
		if action == "Skip" then
			Profiles.onboard(player, "Skipped")
			-- skipping also ends the practice requirement so the next solo hunt is a real one
			local data = Profiles.get(player)
			if data and data.TutorialStep == 0 then
				data.TutorialStep = 1
				Profiles.changed(player, true)
			end
			-- and never costs the free starter pet (granted once; a no-op when it was already given)
			if skipHandler then
				skipHandler(player)
			end
		elseif action == "Goal" then
			Profiles.onboard(player, "Goal")
		end
	end))
	-- Hopper prompts are server objects, but Triggered is not proof of range (an exploit client can fire it):
	-- the server re-checks the avatar's distance to the prompt like the HUD button path does.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt:GetAttribute("Sell") and not Profiles.isReleased(player) then
			local parent = prompt.Parent
			local at = if parent and parent:IsA("BasePart") then parent.Position else nil
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not at or not root or not root:IsA("BasePart") or (root.Position - at).Magnitude > prompt.MaxActivationDistance + 6 then
				return
			end
			sellRubble(player, at)
		end
	end)
end

return Economy
