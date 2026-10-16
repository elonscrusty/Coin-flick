--!strict
-- EGG SHOP (Robux): paid pet eggs, luck potions and game passes (server: RobuxService; tuning: shared/RobuxConfig).
-- Opened from the lobby EGG SHOP hut (a world prompt with Panel = "RobuxShop") and from the Robux tab of UPGRADES.
--
-- Layout like the UPGRADES shop: tabs (Eggs / Potions / Passes), a luck status line, the catalog on the left and one
-- selected-item card on the right (portrait: stacked). An egg card lists the FULL odds (rarity, variant, species)
-- above its buy button (Roblox rule for paid random items); the odds come from LuckEvents.eggOdds, the same weights
-- GeodeGen.roll uses on the server. Paid eggs are hidden for accounts PolicyService restricts (player attribute
-- PaidRandomRestricted, set by the server; until it is known they are hidden too). Luck potions are hidden the same way.
--
-- EGG SHRINE (coin mode, RobuxShopPanel.openCoins; the lobby hatch stand's "Buy Eggs" prompt, Panel = "EggShrine"):
-- the same egg cards and full odds, priced in coins for the player's best zone (RobuxConfig.eggCoinPrice), with the
-- coin balance on the status line. BUY sends RobuxAction "BuyEggCoins"; the server re-checks everything and answers
-- with the pets (profile update + notice) or a refusal notice. No tabs: eggs only.
--
-- Prices are read from Roblox (MarketplaceService:GetProductInfo, pcall), never written in the game; "R$ ?" until
-- known. An item whose id is still 0 shows NOT FOR SALE YET. Tapping BUY only asks the server, which re-checks and
-- opens Roblox's own purchase prompt; the grant arrives as a profile update and a notification.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local RobuxConfig = require(Shared.RobuxConfig)
local LuckEvents = require(Shared.LuckEvents)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)
local Juice = require(script.Parent.Juice)

local T = UI.T
local TC = Theme.Color
local K = Theme.Pet
local RobuxShopPanel = {}

local player = Players.LocalPlayer
local TABS = { { "Eggs", "Eggs" }, { "Potions", "Potions" }, { "Passes", "Passes" } }

local tab = "Eggs"
local coinMode = false -- true: the EGG SHRINE (eggs for coins)
local got: { Text: string, Until: number }? = nil -- "You got: ..." after a shrine buy (RobuxAction "Hatched")
local modalName = "RobuxShop"
local open = false
local body: Frame? = nil
local selected: { [string]: string } = {}
local pending: { Key: string, At: number }? = nil
local PENDING_SECONDS = 4
local render: () -> ()
local tickers: { () -> () } = {} -- labels with a countdown, refreshed every second while open

local function now(): number
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.time()
end

-- Prices from Roblox, cached per kind and id ------------------------------------------------------------------------

local priceCache: { [string]: string } = {}
local priceAsked: { [string]: boolean } = {}
local function priceText(id: number, isPass: boolean): string
	if id <= 0 then
		return ""
	end
	local key = (if isPass then "p" else "d") .. id
	if priceCache[key] then
		return priceCache[key]
	end
	if not priceAsked[key] then
		priceAsked[key] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				priceCache[key] = "R$ " .. info.PriceInRobux
				render()
			end
		end)
	end
	return "R$ ?"
end

-- Luck the player has right now (the same sources the server adds up for a hunt pet, without friends luck).
local function luckParts(prof): { [string]: number }
	local storm = ReplicatedStorage:GetAttribute("LuckStormUntil")
	local t = LuckEvents.timed(now(), prof and prof.Robux and tonumber(prof.Robux.LuckUntil) or 0, if type(storm) == "number" then storm else 0)
	local pet = prof and prof.PetBoosts and tonumber(prof.PetBoosts.Luck) or 0
	return { Pet = pet, Potion = t.Potion, Weekend = t.Weekend, Storm = t.Storm, Hour = t.Hour, Vip = RobuxConfig.vipLuck(prof and prof.Robux) }
end

local function luckLine(prof): string
	local p = luckParts(prof)
	local total = LuckEvents.total(p :: any)
	local bits = {}
	if p.Potion > 0 then
		table.insert(bits, "Potion " .. LuckEvents.clock(RobuxConfig.potionLeft(prof.Robux, now())))
	end
	if p.Weekend > 0 then
		table.insert(bits, "Weekend")
	end
	if p.Storm > 0 then
		local storm = ReplicatedStorage:GetAttribute("LuckStormUntil")
		table.insert(bits, "Storm " .. LuckEvents.clock((if type(storm) == "number" then storm else 0) - now()))
	end
	if p.Hour > 0 then
		table.insert(bits, "Lucky Hour")
	end
	if p.Vip > 0 then
		table.insert(bits, "VIP")
	end
	if p.Pet > 0 then
		table.insert(bits, "Pets")
	end
	local factor = LuckEvents.factor(total)
	local head = "Your luck: x" .. (if factor == math.floor(factor) then tostring(factor) else string.format("%.1f", factor))
	return if #bits > 0 then head .. "  \u{b7}  " .. table.concat(bits, " \u{b7} ") else head .. "  \u{b7}  2x luck every weekend"
end

local function eggsHidden(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

-- Catalog ------------------------------------------------------------------------------------------------------------

type Item = {
	Key: string,
	Title: string,
	Icon: string,
	Sub: string,
	SubColor: Color3?,
	Id: number, -- product or pass id (0 = not created yet)
	IsPass: boolean,
	Owned: boolean?,
	Block: string?, -- why it cannot be bought now (button text)
	Egg: RobuxConfig.Egg?,
}

local function items(prof): { Item }
	local out: { Item } = {}
	if coinMode then
		local room = (prof.InventoryMax or 0) - (prof.InventoryCount or 0)
		local tierId = RobuxConfig.eggTier(prof.UnlockedTiers)
		for _, e in RobuxConfig.Eggs do
			local one = RobuxConfig.eggCoinPrice(e.Id, tierId, 1) or 0
			table.insert(out, {
				Key = e.Id, Title = e.Name, Icon = "egg_" .. string.lower((string.gsub(e.Id, "Egg$", ""))), Id = 1, IsPass = false, Egg = e,
				Block = if room <= 0 then "PET BOOK FULL" else nil,
				Sub = if room <= 0 then "Pet Book full" else "1x " .. UI.money(one),
				SubColor = if room <= 0 then TC.Faint else TC.Cash,
			})
		end
	elseif tab == "Eggs" then
		local room = (prof.InventoryMax or 0) - (prof.InventoryCount or 0)
		for _, e in RobuxConfig.Eggs do
			local one = e.Products[1] or 0
			local any = false
			for _, n in RobuxConfig.EggCounts do
				any = any or (e.Products[n] or 0) > 0
			end
			table.insert(out, {
				Key = e.Id, Title = e.Name, Icon = "egg_" .. string.lower((string.gsub(e.Id, "Egg$", ""))), Id = if any then 1 else 0, IsPass = false, Egg = e,
				Block = if room <= 0 then "PET BOOK FULL" else nil,
				Sub = if not any then "Not for sale yet" elseif room <= 0 then "Pet Book full" elseif one > 0 then "1x " .. priceText(one, false) else "3x / 10x",
				SubColor = if not any or room <= 0 then TC.Faint else TC.Cash,
			})
		end
	elseif tab == "Potions" then
		local p = RobuxConfig.Potion
		local left = RobuxConfig.potionLeft(prof.Robux, now())
		table.insert(out, {
			Key = p.Id, Title = p.Name, Icon = "sparkle", Id = p.ProductId, IsPass = false,
			Block = if left + p.Seconds > p.MaxStackSeconds then "LOTS OF TIME LEFT" else nil,
			Sub = if left > 0 then "Active " .. LuckEvents.clock(left) elseif p.ProductId <= 0 then "Not for sale yet" else priceText(p.ProductId, false),
			SubColor = if left > 0 then TC.Green elseif p.ProductId <= 0 then TC.Faint else TC.Cash,
		})
	else
		local icons = { DoubleCoins = "cash", PetStorage = "storage", ExtraPlots = "home" }
		for _, key in RobuxConfig.PassOrder do
			local pass = RobuxConfig.Passes[key]
			local owned = RobuxConfig.hasPass(prof.Robux, key)
			table.insert(out, {
				Key = key, Title = pass.Name, Icon = icons[key] or "star", Id = pass.PassId, IsPass = true, Owned = owned,
				Sub = if owned then "Owned" elseif pass.PassId <= 0 then "Not for sale yet" else priceText(pass.PassId, true),
				SubColor = if owned then TC.Green elseif pass.PassId <= 0 then TC.Faint else TC.Cash,
			})
		end
	end
	return out
end

local function buy(it: Item, count: number?)
	if pending or it.Id <= 0 or it.Block or it.Owned then
		return
	end
	pending = { Key = it.Key .. ":" .. tostring(count or 1), At = os.clock() }
	Net.event("RobuxAction"):FireServer(if coinMode then "BuyEggCoins" else "Buy", it.Key, count)
	render()
	local mine = pending
	task.delay(PENDING_SECONDS, function()
		if pending == mine then
			pending = nil
			render()
		end
	end)
end

-- Card ----------------------------------------------------------------------------------------------------------------

local function line(parent: Instance, order: number, text: string, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = { Font = UI.Bold, TextSize = T.Small, Outline = "Light", LayoutOrder = order, Size = UDim2.new(1, -6, 0, 20) }
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	return UI.text(parent, text, p)
end

local justPicked: string? = nil -- row tapped just now (its picture bounces once after the re-render)

local function oddsRow(parent: Instance, order: number, name: string, p: number, color: Color3?)
	local row = UI.frame(parent, { Name = "Odds_" .. name, BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 18) })
	local x = 0
	if color then
		-- rarity dot in front of the name
		local dot = UI.frame(row, { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = color })
		UI.corner(dot, 5)
		UI.stroke(dot, TC.Outline, 1)
		x = 16
	end
	UI.text(row, name, { Font = UI.Bold, TextSize = T.Small, TextColor3 = color or TC.Text, Outline = if color then "Strong" else "Light", Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0.45, -x, 1, 0) })
	UI.text(row, LuckEvents.chanceText(p), { Name = "Chance", Font = UI.Bold, TextSize = T.Small, Outline = "Light", Position = UDim2.fromScale(0.45, 0), Size = UDim2.new(0.55, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
end

local function eggInfo(scroll: ScrollingFrame, it: Item, prof)
	local egg = it.Egg :: RobuxConfig.Egg
	local luck = if RobuxConfig.EggsUseLuck then LuckEvents.total(luckParts(prof) :: any) else 0
	local tierId = RobuxConfig.eggTier(prof.UnlockedTiers)
	local odds = LuckEvents.eggOdds(tierId, luck, RobuxConfig.eggRarity(egg))
	local tier = Config.Tiers[tierId]
	local o = 0
	local function nextOrder(): number
		o += 1
		return o
	end
	line(scroll, nextOrder(), "RARITY ODDS", { Font = UI.Head, TextColor3 = TC.Gold })
	for _, r in odds.Rarity do
		oddsRow(scroll, nextOrder(), r.Name, r.P, (Config.RarityTextColors :: any)[r.Name])
	end
	UI.frame(scroll, { Name = "Gap1", BackgroundTransparency = 1, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 8) })
	line(scroll, nextOrder(), "VARIANT ODDS", { Font = UI.Head, TextColor3 = TC.Gold })
	for _, v in odds.Variant do
		oddsRow(scroll, nextOrder(), v.Name, v.P)
	end
	line(scroll, nextOrder(), "Hatches " .. (if tier then tier.Name else tierId) .. " pets (your best zone) with their normal boost.", { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
	UI.frame(scroll, { Name = "Gap2", BackgroundTransparency = 1, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 8) })
	line(scroll, nextOrder(), "PET ODDS", { Font = UI.Head, TextColor3 = TC.Gold })
	for _, sp in odds.SpeciesP do
		oddsRow(scroll, nextOrder(), sp.Name .. (if sp.Chase then " (Legendary only)" else ""), sp.P)
	end
	line(scroll, nextOrder(), (if egg.Rarity then "Better rarity odds than a race egg. " else "Same odds as a race egg. ") .. (if RobuxConfig.EggsUseLuck then "Includes your luck now." else "Luck boosts don't change bought eggs."), { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
	if coinMode then
		line(scroll, nextOrder(), "The coin price grows with your best zone (" .. (if tier then tier.Name else tierId) .. " now).", { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
	end
	-- room under the last line, so the list never ends cut off at the card's bottom edge
	UI.frame(scroll, { Name = "EndGap", BackgroundTransparency = 1, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 18) })
end

local function potionInfo(scroll: ScrollingFrame, prof)
	local p = RobuxConfig.Potion
	line(scroll, 1, "2x luck for " .. math.floor(p.Seconds / 60) .. " minutes: Rare and better pets twice as likely.", { Size = UDim2.new(1, -6, 0, 34) })
	line(scroll, 2, (if RobuxConfig.EggsUseLuck then "" else "Works on the pet you find in a hunt. ") .. "More potions add more time, even while you are away.", { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
	line(scroll, 3, "Stacks with weekend luck and luck storms (best x" .. LuckEvents.factor(RobuxConfig.MaxLuck) .. ").", { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
	-- the timer with a ring of dots that drains as the potion runs out (the last potion's worth of time)
	local row = UI.frame(scroll, { Name = "PotionTimerRow", BackgroundTransparency = 1, LayoutOrder = 4, Size = UDim2.new(1, -6, 0, 34) })
	local ring, setRing = Juice.ring(row, 30, TC.Green, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0) })
	local timer = line(row, 0, "", { Name = "PotionTimer", TextColor3 = TC.Green, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40, 1, 0) })
	local function tick()
		local left = RobuxConfig.potionLeft(State.Profile and State.Profile.Robux, now())
		timer.Text = if left > 0 then "Active: " .. LuckEvents.clock(left) .. " left" else "No potion active"
		ring.Visible = left > 0
		timer.Position = UDim2.fromOffset(if left > 0 then 40 else 0, 0)
		setRing(left / p.Seconds)
	end
	tick()
	table.insert(tickers, tick)
	local _ = prof
end

local function passInfo(scroll: ScrollingFrame, it: Item)
	local pass = RobuxConfig.Passes[it.Key]
	line(scroll, 1, pass.Desc, { Size = UDim2.new(1, -6, 0, 34) })
	local note = if it.Key == "DoubleCoins" then "Works with your Coins pets. Forever, on every server."
		elseif it.Key == "PetStorage" then "+" .. RobuxConfig.ExtraPetSlots .. " Pet Book slots (" .. Config.Inventory.Max .. " -> " .. (Config.Inventory.Max + RobuxConfig.ExtraPetSlots) .. ")."
		else "+" .. RobuxConfig.ExtraDisplaySlots .. " display spots. Extra pets walk around inside your plot fence."
	line(scroll, 2, note, { TextColor3 = TC.Muted, Size = UDim2.new(1, -6, 0, 34) })
end

-- buyHost: landscape egg cards put the 1x / 3x / 10x buttons under the egg list (the odds then fill the whole card).
-- One calm "coming soon" tag in place of buy buttons that can't be pressed yet (a row of grey SOON buttons read
-- like a broken shop).
local function soonTag(parent: Instance)
	local tag = UI.frame(parent, { Name = "ComingSoon", Size = UDim2.fromScale(1, 1), BackgroundColor3 = TC.Inset })
	UI.corner(tag, T.Radius)
	UI.stroke(tag, TC.Gold, 2)
	UI.icon(tag, "clock", 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0) })
	local l = UI.text(tag, "COMING SOON", { Name = "Text", Font = UI.Head, TextSize = T.Head, TextColor3 = TC.Gold, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -54, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	l.TextWrapped = false
end

local function detail(parent: Instance, it: Item, prof, buyHost: Frame?, soon: boolean?)
	local f = UI.card(parent, "inset", { Name = "Detail", Size = UDim2.fromScale(1, 1) })
	UI.pad(f, 8, 6)
	local head = UI.frame(f, { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32) })
	UI.icon(head, it.Icon, 30, { Position = UDim2.fromOffset(0, 1) })
	local title = UI.text(head, it.Title, { Name = "Title", Font = UI.Head, TextSize = T.Head + 2, Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -36, 1, 0) })
	title.TextWrapped = false
	local footH = if buyHost and it.Egg then 0 else 44
	-- the odds (or the description) sit ABOVE the buy button, always visible before buying
	local scroll = UI.scroller(f, { Name = "Info", Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -(36 + footH + (if footH > 0 then 6 else 0))) })
	UI.list(scroll, Enum.FillDirection.Vertical, 2)
	if it.Egg then
		eggInfo(scroll, it, prof)
	elseif tab == "Potions" then
		potionInfo(scroll, prof)
	else
		passInfo(scroll, it)
	end
	local foot = if buyHost and it.Egg then buyHost else UI.frame(f, { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, footH) })
	if soon then
		soonTag(foot)
		return
	end
	if it.Egg and coinMode then
		-- 1x / 3x / 10x for coins at the player's zone price; a batch needs Pet Book room for every pet. A button the
		-- player can't afford is gray and reads "NEED N" (how many more coins).
		local room = (prof.InventoryMax or 0) - (prof.InventoryCount or 0)
		local tierId = RobuxConfig.eggTier(prof.UnlockedTiers)
		local counts = RobuxConfig.CoinEggs.Counts
		local n = #counts
		UI.list(foot, Enum.FillDirection.Horizontal, 6)
		for i, count in counts do
			local price = RobuxConfig.eggCoinPrice(it.Key, tierId, count) or 0
			local key = it.Key .. ":" .. count
			local cash = tonumber(prof.Cash) or 0
			local short = cash < price
			-- too few coins: the gray button says how many more (tapping it does nothing)
			local text, enabled, style = RobuxConfig.coinButton(count, price, cash, room, pending ~= nil and pending.Key == key, UI.num)
			local b = UI.button(foot, text, style, function()
				if enabled and not short then
					buy(it, count)
				end
			end, { Name = "Buy" .. count, LayoutOrder = i, Size = UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0), TextSize = T.Body })
			if not enabled then
				UI.setEnabled(b, false)
			end
		end
		return
	end
	if it.Egg then
		-- 1x / 3x / 10x: each its own product; a batch needs Pet Book room for every pet
		local egg = it.Egg :: RobuxConfig.Egg
		local room = (prof.InventoryMax or 0) - (prof.InventoryCount or 0)
		local n = #RobuxConfig.EggCounts
		UI.list(foot, Enum.FillDirection.Horizontal, 6)
		for i, count in RobuxConfig.EggCounts do
			local id = egg.Products[count] or 0
			local key = it.Key .. ":" .. count
			local text, enabled
			if pending and pending.Key == key then
				text, enabled = "\u{2026}", false
			elseif id <= 0 then
				text, enabled = count .. "x  SOON", false
			elseif room < count then
				text, enabled = count .. "x  NO ROOM", false
			else
				text, enabled = count .. "x  " .. priceText(id, false), true
			end
			local b = UI.button(foot, text, "gold", function()
				if enabled then
					buy(it, count)
				end
			end, { Name = "Buy" .. count, LayoutOrder = i, Size = UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0), TextSize = T.Body })
			if not enabled then
				UI.setEnabled(b, false)
			end
		end
		return
	end
	local text, enabled = "", true
	if pending and pending.Key == it.Key .. ":1" then
		text, enabled = "OPENING\u{2026}", false
	elseif it.Owned then
		text, enabled = "OWNED", false
	elseif it.Id <= 0 then
		text, enabled = "NOT FOR SALE YET", false
	elseif it.Block then
		text, enabled = it.Block, false
	else
		text = "BUY " .. priceText(it.Id, it.IsPass)
	end
	local b = UI.button(foot, text, "gold", function()
		buy(it)
	end, { Name = "Buy", Size = UDim2.fromScale(1, 1), TextSize = T.Head })
	if not enabled then
		UI.setEnabled(b, false)
	end
end

function render()
	if not open or not body then
		return
	end
	local b = body :: Frame
	for _, c in b:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	tickers = {}
	local prof = State.Profile
	if not prof then
		UI.loadingState(b, "Loading shop", { Position = UDim2.fromOffset(0, 60) })
		return
	end
	local tabsH = if coinMode then 0 else T.Gap + T.Tab
	if coinMode then
		tab = "Eggs"
	else
		UI.tabs(b, TABS, tab, function(name)
			tab = name
			render()
		end)
	end
	local function statusText(p): string
		return if coinMode then UI.num(tonumber(p.Cash) or 0) else luckLine(p)
	end
	local statusH = if coinMode then 34 else 20
	local status: TextLabel
	if coinMode then
		-- the coin balance as the pet-style coin pill (navy, gold coin, white outlined number), centred over the shop
		local pill, setCoins = PetStyle.coinPill(b, 170, statusH, { Name = "CoinPill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, tabsH) })
		setCoins(tonumber(prof.Cash) or 0)
		status = pill:FindFirstChild("Amount") :: TextLabel
		status.Name = "Luck"
		status.TextXAlignment = Enum.TextXAlignment.Center
		status.Text = statusText(prof)
	else
		status = UI.text(b, statusText(prof), { Name = "Luck", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Count, Outline = "Normal", Position = UDim2.fromOffset(0, tabsH), Size = UDim2.new(1, 0, 0, 20) })
	end
	status.TextWrapped = false
	table.insert(tickers, function()
		if State.Profile then
			status.Text = statusText(State.Profile)
		end
	end)
	local top = tabsH + statusH + 4
	if coinMode and got and got.Until > os.clock() then
		-- what the last buy hatched, under the coin pill: a glossy lime strip with the pet-style outlined words
		local strip = UI.frame(b, { Name = "GotStrip", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = K.Lime })
		PetStyle.round(strip, 999)
		PetStyle.vgrad(strip, K.LimeTop, K.Lime)
		PetStyle.edge(strip, K.LimeEdge, 2)
		PetStyle.words(strip, got.Text, T.Small, { Name = "Text", Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, OutlineColor = K.LimeEdge, OutlineThick = 2 })
		top += 30
	end
	local content = UI.frame(b, { Name = "Content", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1 })
	if tab == "Eggs" and eggsHidden() then
		UI.emptyState(content, "Eggs not available", if coinMode then "Pet eggs can't be bought on your account." else "Pet eggs can't be bought with Robux on your account.", "lock", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		return
	end
	-- luck potions follow the same paid-random-item rule (the server refuses them too)
	if tab == "Potions" and eggsHidden() then
		UI.emptyState(content, "Potions not available", "Luck potions can't be bought with Robux on your account.", "lock", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		return
	end
	local list = items(prof)
	-- nothing on this tab can be bought yet (ids not set): say so plainly at the top instead of the luck line,
	-- so the gray SOON buttons don't look like a broken shop
	local soon = not coinMode
	for _, it in list do
		if it.Id > 0 or it.Owned == true then
			soon = false
		end
	end
	if soon then
		table.clear(tickers)
		-- a calm yellow ribbon (red read like an error)
		status.Text = "Coming soon! Have a look at what will be inside."
		status.TextColor3 = TC.DarkText
		status.BackgroundColor3 = TC.Gold
		status.BackgroundTransparency = 0
		status.TextXAlignment = Enum.TextXAlignment.Center
		local ol = status:FindFirstChildOfClass("UIStroke")
		if ol then
			ol.Enabled = false
		end
		UI.corner(status, 8)
	end
	local sel: Item? = nil
	for _, it in list do
		if it.Key == selected[tab] then
			sel = it
		end
	end
	sel = sel or list[1]
	local portrait = UI.isPortrait()
	local sideBuy = not portrait and tab == "Eggs"
	local listHost = UI.frame(content, { Name = "ListHost", BackgroundTransparency = 1, Size = if portrait then UDim2.new(1, 0, 0.4, -4) elseif sideBuy then UDim2.new(0.46, -4, 1, -50) else UDim2.new(0.46, -4, 1, 0) })
	local buyHost = if sideBuy then UI.frame(content, { Name = "BuyRow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.46, -14, 0, 44) }) else nil
	local pane = UI.frame(content, {
		Name = "Pane", BackgroundTransparency = 1,
		Position = if portrait then UDim2.new(0, 0, 0.4, 4) else UDim2.new(0.46, 4, 0, 0),
		Size = if portrait then UDim2.new(1, 0, 0.6, -4) else UDim2.new(0.54, -4, 1, 0),
	})
	local scroller = UI.scroller(listHost, { Name = "List", Size = UDim2.fromScale(1, 1) })
	UI.list(scroller, Enum.FillDirection.Vertical, 6)
	UI.pad(scroller, 2, 2)
	local rowH = if UI.isShort() then 48 else 56
	for i, it in list do
		local row = UI.catalogRow(scroller, i, {
			Name = "Row_" .. it.Key, Title = it.Title, Sub = if soon then "Coming soon" else it.Sub, SubColor = if soon then TC.Count else it.SubColor, Selected = sel ~= nil and it.Key == sel.Key, Height = rowH,
			Thumb = function(c)
				local ic = UI.icon(c, it.Icon, rowH - 14, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
				if it.Egg then
					Juice.wobble(ic) -- egg tiles rock gently while the shop is open
				end
			end,
			OnSelect = function()
				selected[tab] = it.Key
				justPicked = it.Key
				render()
			end,
		})
		if justPicked == it.Key then
			-- the picked egg / potion / pass picture bounces once
			local th = row:FindFirstChild("Thumb")
			if th then
				UI.pop(th, 0.7)
			end
		end
	end
	justPicked = nil
	-- keep the selected row in view (the buy buttons below the list belong to it)
	local selIndex = if sel then table.find(list, sel) else nil
	if selIndex then
		task.defer(function()
			if scroller.Parent then
				local bottom = selIndex * (rowH + 6) + 4
				scroller.CanvasPosition = Vector2.new(0, math.max(0, bottom - scroller.AbsoluteSize.Y))
			end
		end)
	end
	if sel then
		detail(pane, sel, prof, buyHost, soon)
	end
end

local function modalSize(): Vector2
	if UI.isPortrait() then
		return Vector2.new(480, 700)
	elseif UI.Logical.Y >= 600 then
		return Vector2.new(740, 460)
	end
	return Vector2.new(680, 380)
end

-- onBack: set when another menu opened this one (Upgrades); adds a BACK button to the header that returns there.
local function openAs(coins: boolean, openTab: string?, onBack: (() -> ())?)
	coinMode = coins
	modalName = if coins then RobuxConfig.CoinEggs.Panel else "RobuxShop"
	pending = nil
	if openTab == "Eggs" or openTab == "Potions" or openTab == "Passes" then
		tab = openTab
	end
	local heading = if coins then "EGG SHRINE" else "EGG SHOP"
	local panel, b = UI.modal(modalName, heading, modalSize(), { Fixed = true })
	local head = panel:FindFirstChild("Header")
	if onBack and head then
		UI.button(head, "BACK", "gray", onBack, {
			Name = "Back", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 2), Size = UDim2.fromOffset(84, T.Touch), TextSize = T.Body,
		})
		local title = head:FindFirstChild("Title") :: TextLabel?
		if title then
			title.Position = UDim2.fromOffset(106, title.Position.Y.Offset)
			title.Size = UDim2.new(title.Size.X.Scale, title.Size.X.Offset - 90, title.Size.Y.Scale, title.Size.Y.Offset)
		end
	end
	-- centred tab: the BACK button holds the left side of the header
	PanelSkin.dress(panel, "Egg", heading, { Center = true })
	body = b
	open = true
	local conn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= modalName then
			open = false
			body = nil
			tickers = {}
			conn:Disconnect()
		end
	end)
	render()
end

function RobuxShopPanel.open(openTab: string?, onBack: (() -> ())?)
	openAs(false, openTab, onBack)
end

-- The EGG SHRINE (hatch stand prompt): eggs for coins.
function RobuxShopPanel.openCoins()
	openAs(true)
end

function RobuxShopPanel.start()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			if not coinMode then -- coin buys wait for their own reply (Hatched / warn notice) or the timeout
				pending = nil
			end
			render()
		end
	end)
	Net.event("RobuxAction").OnClientEvent:Connect(function(kind, text)
		if kind == "Hatched" and type(text) == "string" then
			pending = nil
			local mine = { Text = text, Until = os.clock() + 8 }
			got = mine
			render()
			task.delay(8.1, function()
				if got == mine then
					got = nil
					render()
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
		render()
	end)
	for _, name in { "LuckStormUntil", "LuckWeekend" } do
		ReplicatedStorage:GetAttributeChangedSignal(name):Connect(function()
			render()
		end)
	end
	-- refusals (warn notices) end the pending state at once
	UI.Notice.Event:Connect(function(_, kind)
		if kind == "warn" and pending then
			pending = nil
			render()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if open then
				for _, fn in tickers do
					fn()
				end
			end
		end
	end)
end

return RobuxShopPanel
