--!strict
-- PET SHOP: the Robux shop drawn in the style of the owner's reference clip (docs/UI_STYLE_REF.md on branch
-- claude/project-thread-lb94zs: Pet Simulator style). No panel sheet: a "Shop" title, a navy tab strip with a lime
-- selected pill, a coin pill and a red X float over the blurred world; the content is wide gradient cards with a
-- faint diamond pattern, white heavy-outlined names, green price pills and small ribbons. Cards tilt toward the
-- pointer and lift on hover (CardTilt); the selected tab pill slides.
--
-- Content comes from shared/RobuxConfig (eggs with full odds, luck potion, game passes). Prices are read from
-- Roblox (MarketplaceService:GetProductInfo); "R$ ?" until known; an id of 0 shows SOON. Tapping a price pill asks
-- the server (RobuxAction), which re-checks and opens Roblox's own prompt; the panel never grants anything.
--
-- Opened by the EGG SHOP hut prompt (Main.client panels.RobuxShop) and the Robux tab of UPGRADES (ShopPanel).
-- Preview scene: `petshop`.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RobuxConfig = require(Shared.RobuxConfig)
local LuckEvents = require(Shared.LuckEvents)
local EggPerks = require(Shared.EggPerks)
local LaunchPerks = require(Shared.LaunchPerks)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)

local PetStyle = require(script.Parent.PetStyle)
local ShopEgg = require(script.Parent.ShopEgg)
local PetShop = {}
local player = Players.LocalPlayer

local K, TONES, MOTION = PetStyle.K, PetStyle.Tones, PetStyle.Motion
local still, words, vgrad, round, edge, shadowed, pattern, card, pill, ribbon, dot =
	PetStyle.still, PetStyle.words, PetStyle.vgrad, PetStyle.round, PetStyle.edge, PetStyle.shadowed, PetStyle.pattern, PetStyle.card, PetStyle.pill, PetStyle.ribbon, PetStyle.dot
local RARITY_HEX: { [string]: Color3 } = {
	Common = Color3.fromRGB(236, 240, 244),
	Uncommon = Color3.fromRGB(120, 240, 110),
	Rare = Color3.fromRGB(90, 190, 255),
	Epic = Color3.fromRGB(220, 110, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
}
local EGG_TONE: { [string]: string } = { BasicEgg = "sky", RareEgg = "gold", MythicEgg = "purple" }
local EGG_TAG: { [string]: string } = { BasicEgg = "STARTER", RareEgg = "POPULAR", MythicEgg = "BEST ODDS" }
local EGG_BLURB: { [string]: string } = {
	BasicEgg = "Same odds as a race egg. Pets from your best zone.",
	RareEgg = "1 in 200 Legendary. Rare pets twice as likely.",
	MythicEgg = "1 in 100 Legendary. The best egg in the game.",
}
local PASS_TONE: { [string]: string } = { VIP = "gold", DoubleCoins = "sun", TripleHatch = "purple", AutoHatch = "green", PetStorage = "blue", ExtraPlots = "pink" }
local PASS_EFFECT: { [string]: string } = { VIP = "+50% luck", DoubleCoins = "2x coins", TripleHatch = "3 at once", AutoHatch = "hands free", PetStorage = "+250 pets", ExtraPlots = "+10 spots" }
local PASS_ICON: { [string]: string } = { VIP = "crown", DoubleCoins = "cash", TripleHatch = "egg", AutoHatch = "clock", PetStorage = "book", ExtraPlots = "display" }
local LIMITED_TONE = "pink"

local TABS = { "Featured", "Eggs", "Passes", "Potions" }
local tab = "Featured"
local open = false
local content: ScrollingFrame? = nil
local contentW = 600 -- logical width of the content column (build sets it)
local render: () -> ()
local rendering = false
local renderQueued = false
local function requestRender()
	if not open then
		return
	end
	if rendering then
		renderQueued = true
		return
	end
	task.defer(function()
		if open and not rendering then
			render()
		end
	end)
end

-- Prices from Roblox, cached ---------------------------------------------------------------------------------------

local priceCache: { [string]: string } = {}
local priceAsked: { [string]: boolean } = {}
local function priceText(id: number, isPass: boolean): string
	if id <= 0 then
		return "SOON"
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
				priceCache[key] = UI.num(info.PriceInRobux)
				requestRender()
			end
		end)
	end
	return "..."
end

-- Countdowns (shared/LaunchPerks view) ------------------------------------------------------------------------------
-- Labels that count down are updated once a second in place (never a re-render): `tickers` holds one function per
-- live label; the content ones are dropped by every render, the header one lives with build().

local tickers: { [string]: (() -> ())? } = {}
local tickRun = 0
local function startTicking()
	tickRun += 1
	local token = tickRun
	task.spawn(function()
		while open and tickRun == token do
			task.wait(1)
			if not open or tickRun ~= token then
				return
			end
			for _, fn in table.clone(tickers) do
				local ok, err = pcall(fn :: any)
				if not ok then
					warn("[PetShop] tick failed: " .. tostring(err))
				end
			end
		end
	end)
end

-- "2d 4h" from a day up, else "1:59:59" / "43:12".
local function endsText(secs: number): string
	local s = math.max(0, math.floor(secs))
	if s >= 86400 then
		return string.format("%dd %dh", s // 86400, (s % 86400) // 3600)
	end
	return LuckEvents.clock(s)
end

local function prof(): any
	return State.Profile
end

-- The profile's Perks view carries seconds-left numbers (Limited.EndsIn, LuckyHourIn) that are true when the view
-- arrives: they are anchored to the clock once per view so the countdowns keep running between syncs.
local perksSeen: any = nil
local limitedEndsAt = 0
local luckyStartAt = 0
local function perks(): any
	local p = prof()
	local pk = if p and type(p.Perks) == "table" then p.Perks else nil
	if pk ~= perksSeen then
		perksSeen = pk
		local now = os.time()
		limitedEndsAt = if pk and type(pk.Limited) == "table" then now + (tonumber(pk.Limited.EndsIn) or 0) else 0
		luckyStartAt = if pk then now + (tonumber(pk.LuckyHourIn) or 0) else 0
	end
	return pk
end

-- The limited egg on sale for this player (RobuxConfig.LimitedEggs entry named by Perks.Limited), or nil.
local function limitedEgg(): RobuxConfig.Egg?
	local pk = perks()
	if not pk or type(pk.Limited) ~= "table" then
		return nil
	end
	local egg = RobuxConfig.egg(pk.Limited.Id)
	return if egg and egg.Limited then egg else nil
end

-- Lucky hour chip state: "on" (running, ReplicatedStorage.LuckyHourUntil) with seconds left, "soon" (under two
-- hours away) with seconds until it starts, or nil (no chip).
local LUCKY_SOON = 2 * 3600
local function luckyMode(): (string?, number)
	local now = os.time()
	local untilT = ReplicatedStorage:GetAttribute("LuckyHourUntil")
	if type(untilT) == "number" and untilT > now then
		return "on", untilT - now
	end
	if perks() and luckyStartAt > now and luckyStartAt - now < LUCKY_SOON then
		return "soon", luckyStartAt - now
	end
	return nil, 0
end
local function luckyText(mode: string, left: number): string
	return if mode == "on" then "LUCKY HOUR 2x \u{b7} " .. LuckEvents.clock(left) else "LUCKY HOUR in " .. LuckEvents.clock(left)
end

-- Drawing kit ----------------------------------------------------------------------------------------------------

-- The Robux mark: a white ring with a square dot (no asset id).
local function robuxMark(parent: Instance, size: number, props: { [string]: any }?): Frame
	local ring = Instance.new("Frame")
	ring.Name = "Robux"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(size, size)
	ring.ZIndex = 6
	UI.apply(ring, props)
	round(ring, 999)
	edge(ring, K.White, math.max(1.6, size * 0.11))
	local dot = Instance.new("Frame")
	dot.BackgroundColor3 = K.White
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.42, 0.42)
	dot.Rotation = 45
	dot.ZIndex = 6
	round(dot, 2)
	dot.Parent = ring
	ring.Parent = parent
	return ring
end

-- Green price pill: Robux mark + the price (or SOON / ...). `onBuy` runs on tap when the price is known.
local function pricePill(parent: Instance, price: string, props: { [string]: any }?, size: number?, onBuy: (() -> ())?): TextButton
	local b, l = pill(parent, price, K.PriceTop, K.Price, K.PriceEdge, props, size)
	b.Name = "Buy"
	local s = size or 18
	local w = s * 1.05
	robuxMark(b, w, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, s * 0.6, 0.5, 0) })
	l.Position = UDim2.fromOffset(s * 0.6 + w + 4, 0)
	l.Size = UDim2.new(1, -(s * 0.6 + w + 10), 1, -4)
	l.TextXAlignment = Enum.TextXAlignment.Center
	if onBuy then
		b.Activated:Connect(function()
			if price ~= "SOON" and price ~= "..." then
				onBuy()
			end
		end)
	end
	if not still() then
		-- a glint sweeps the pill now and then (the clip's buttons shine)
		task.spawn(function()
			while b.Parent and open do
				task.wait(Theme.Loop.ShineEvery + (string.len(price) % 3) * 0.4)
				if b.Parent and open then
					UI.Juice.sweep(b, 999)
				end
			end
		end)
	end
	return b
end

-- A gold pill with a coin and the coin price (the Eggs tab paid with coins); grey "NEED n" when the player is short.
local function coinPill(parent: Instance, price: number, cash: number, props: { [string]: any }?, size: number?, onBuy: (() -> ())?): TextButton
	local short = cash < price
	local text = UI.num(price) -- short of coins: the pill goes grey and does nothing (the server also refuses)
	local top, bottom, edgeColor = K.Gold, K.RibbonGold, Theme.Color.GoldDeep
	if short then
		top, bottom, edgeColor = Theme.Color.Disabled, Theme.Color.Disabled, Theme.Color.GrayDeep
	end
	local b, l = pill(parent, text, top, bottom, edgeColor, props, size)
	b.Name = "BuyCoins"
	local s = size or 18
	local w = s * 1.05
	UI.icon(b, "cash", w, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, s * 0.6, 0.5, 0), ZIndex = b.ZIndex + 1 })
	l.Position = UDim2.fromOffset(s * 0.6 + w + 4, 0)
	l.Size = UDim2.new(1, -(s * 0.6 + w + 10), 1, -4)
	l.TextXAlignment = Enum.TextXAlignment.Center
	if onBuy and not short then
		b.Activated:Connect(onBuy)
	end
	return b
end

-- One of the three shop eggs, each with its own look (ShopEgg), spinning slowly on a halo disc.
local function eggView(parent: Instance, eggId: string, variant: number, props: { [string]: any }?, yaw: number?, pitch: number?, halo: boolean?): GuiObject
	local egg = RobuxConfig.egg(eggId)
	return ShopEgg.view(parent, eggId, props, { Yaw = yaw, Pitch = pitch, Variant = variant, Halo = halo ~= false, Image = if egg then egg.Image else nil })
end

-- Section heading: icon disc, big name, grey one-liner.
local function heading(parent: Instance, icon: string, name: string, blurb: string, order: number)
	local row = UI.frame(parent, { Name = "Head_" .. name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order })
	local disc = dot(row, K.Blue, 28, { Position = UDim2.fromOffset(2, 3) })
	UI.icon(disc, icon, 18, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	-- an upright phone stacks the one-liner under the name (each on its own row; centred in one 48 px row they met)
	local portrait = UI.isPortrait()
	words(row, name, 26, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(0, 220, 0, if portrait then 30 else 34), OutlineColor = K.TitleEdge, OutlineThick = 2.6 })
	words(row, blurb, 13, { Position = UDim2.fromOffset(if portrait then 38 else 250, if portrait then 30 else 2), Size = UDim2.new(1, if portrait then -48 else -260, 0, if portrait then 18 else 30), OutlineThick = 1.6 })
	if portrait then
		row.Size = UDim2.new(1, 0, 0, 50)
	end
end

-- Buying ----------------------------------------------------------------------------------------------------------

local function buyEgg(egg: RobuxConfig.Egg, count: number)
	Net.event("RobuxAction"):FireServer("Buy", egg.Id, count)
end
-- the same egg for coins (the old hatch stand's shrine route; the server checks the price, the room and the distance)
local payCoins = false -- Eggs tab: prices in coins instead of Robux (the "Pay with" switch)
local function buyEggCoins(egg: RobuxConfig.Egg, count: number)
	Net.event("RobuxAction"):FireServer("BuyEggCoins", egg.Id, count)
end
local function buyPotion()
	Net.event("RobuxAction"):FireServer("Buy", RobuxConfig.Potion.Id)
end
local function buyPass(key: string)
	Net.event("RobuxAction"):FireServer("Buy", key)
end
-- the Starter Pack is one Developer Product (RobuxConfig.StarterPack); the server hides nothing, it re-checks
local function buyPack()
	Net.event("RobuxAction"):FireServer("Buy", RobuxConfig.StarterPack.Id)
end
-- Auto Hatch (the pass): the shrine re-buys this coin egg; "" stops it. The server refuses without the pass (toast).
local function setAuto(eggId: string)
	Net.event("RobuxAction"):FireServer("AutoHatch", eggId)
end

-- Cards -------------------------------------------------------------------------------------------------------------

local function eggOdds(egg: RobuxConfig.Egg)
	local p = prof()
	local tierId = RobuxConfig.eggTier(if p then p.UnlockedTiers else nil)
	return LuckEvents.eggOdds(tierId, 0, RobuxConfig.eggRarity(egg))
end

local function pct(p: number): string
	if p >= 0.1 then
		return string.format("%d%%", math.floor(p * 100 + 0.5))
	elseif p >= 0.01 then
		return string.format("%.1f%%", p * 100)
	end
	return string.format("%.2g%%", p * 100)
end

-- Hero card (Featured): the Mythic egg with three eggs, a tag, a blurb and the 1-egg price.
local function heroCard(parent: Instance, egg: RobuxConfig.Egg, w: number, h: number, order: number): Frame
	local c = card(parent, EGG_TONE[egg.Id] or "purple", { Name = "Hero", Size = UDim2.fromOffset(w, h), LayoutOrder = order })
	local k = h / 190 -- the reference hero is 0.32 of the screen height; everything scales with it
	-- rows from the top: ribbon, title, a two-line blurb, then the price pill on the bottom row. Computed from the
	-- card height so a short card (844x390 window) never cuts the blurb ("The best egg in the") or stacks rows.
	local ribbonY = math.floor(6 + 4 * k)
	local titleY = ribbonY + 20
	local pillH = math.floor(math.clamp(h * 0.24, 26, 34))
	local pillTop = h - 8 - pillH
	local blurbH = 32 -- two lines of body words
	local blurbY = pillTop - 2 - blurbH
	local titleH = math.max(22, blurbY - titleY - 2)
	ribbon(c, EGG_TAG[egg.Id] or "FEATURED", K.RibbonPink, { Position = UDim2.fromOffset(16, ribbonY), Size = UDim2.fromOffset(108, 20) }) -- wide enough for BEST ODDS on one line at the text floor
	local title = words(c, egg.Name .. "!", math.floor(36 * k + 6), { Position = UDim2.fromOffset(16, titleY), Size = UDim2.new(0.56, 0, 0, titleH), OutlineThick = 3, ZIndex = 5 })
	title.TextWrapped = false
	words(c, EGG_BLURB[egg.Id] or "", 14, { Position = UDim2.fromOffset(16, blurbY), Size = UDim2.new(0.56, 0, 0, blurbH), TextYAlignment = Enum.TextYAlignment.Top, OutlineThick = 1.6, ZIndex = 5 })
	pricePill(c, priceText(egg.Products[1] or 0, false), { Position = UDim2.fromOffset(16, pillTop), Size = UDim2.fromOffset(104, pillH) }, 20, function()
		buyEgg(egg, 1)
	end)
	-- three eggs on glowing discs
	local cx = w * 0.74
	local big = math.min(h * 0.84, w * 0.26)
	local function disc(x: number, y: number, s: number, variant: number, yaw: number)
		local d = Instance.new("Frame")
		d.BackgroundColor3 = K.White
		d.BackgroundTransparency = 0.72
		d.BorderSizePixel = 0
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(x, y)
		d.Size = UDim2.fromOffset(s, s)
		d.ZIndex = 4
		round(d, 999)
		edge(d, K.White, 2)
		d.Parent = c
		eggView(d, egg.Id, variant, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.05, 1.05) }, yaw, 0, false)
		return d
	end
	disc(cx - big * 0.7, h * 0.54, big * 0.7, 2, -40)
	disc(cx + big * 0.7, h * 0.54, big * 0.7, 3, 30)
	disc(cx, h * 0.48, big, 1, -15)
	-- carousel dots (one page for now)
	local nav = UI.frame(c, { Name = "Nav", BackgroundColor3 = K.Shade, BackgroundTransparency = 0.6, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12), Size = UDim2.fromOffset(60, 18), ZIndex = 5 })
	round(nav, 999)
	local pip = UI.frame(nav, { BackgroundColor3 = K.White, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 8), ZIndex = 6 })
	round(pip, 999)
	return c
end

-- Small side card (Featured right column): name, one line, a price pill, an egg or an icon.
local function sideCard(parent: Instance, tone: string, name: string, line: string, price: string, w: number, h: number, order: number, tag: string?, tagColor: Color3?, art: (Frame) -> (), onBuy: (() -> ())?): Frame
	local c = card(parent, tone, { Name = "Side_" .. name, Size = UDim2.fromOffset(w, h), LayoutOrder = order })
	local artBox = UI.frame(c, { Name = "Art", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(h - 8, h - 8), ZIndex = 4 })
	art(artBox)
	-- rows from the top, right of the art: ribbon (when there is a tag), name, one-line blurb; the price pill sits on
	-- the bottom row. Everything is computed from the card height: a short card drops the blurb, then shrinks the
	-- name, rather than letting a row sit over another (the 844x390 window showed "15 MIN" over "Luck Potion").
	local x0 = h + 2
	local tw = w - (h + 10)
	local ph = math.floor(math.clamp(h * 0.36, 24, 28)) -- holds the price words at the text floor
	local pillTop = h - 3 - ph
	local ns = math.floor(math.clamp(h * 0.26, 15, 22))
	local titleH = ns + 4
	local lineH = 15
	local y = 1
	if tag then
		ribbon(c, tag, tagColor or K.RibbonGold, { Position = UDim2.fromOffset(x0, y), Size = UDim2.fromOffset(66, 16) })
		y += 17
	end
	local room = pillTop - y
	local showLine = room >= titleH + lineH
	if not showLine and room < titleH then
		titleH = math.max(room, 17)
		ns = math.clamp(titleH - 4, 14, ns)
	end
	local nameL = words(c, name, ns, { Position = UDim2.fromOffset(x0, y), Size = UDim2.new(0, tw, 0, titleH), OutlineThick = 2.4, ZIndex = 5 })
	nameL.TextWrapped = false
	y += titleH
	if showLine then
		words(c, line, 12, { Position = UDim2.fromOffset(x0, y), Size = UDim2.new(0, tw, 0, lineH), OutlineThick = 1.4, TextWrapped = false, ZIndex = 5 })
	end
	pricePill(c, price, { Position = UDim2.fromOffset(x0, pillTop), Size = UDim2.fromOffset(84, ph) }, 14, onBuy)
	return c
end

local EGG_ROW_H = 44 -- a thumb-sized buy row; the pill fills it less 6
local EGG_ROW_GAP = 10
local function portraitArtW(w: number): number
	return math.min(150, math.floor(w * 0.4))
end
-- Height of an upright-phone egg card (the egg, the odds row, the Lucky Meter and the buy rows stacked).
local function eggCardHeight(w: number): number
	local n = 5 -- rarities (RARITY_HEX)
	local colW = (w - 20) / n
	local ds = math.floor(math.clamp(math.min(44, colW * 0.6), 28, 44))
	local oy = portraitArtW(w) + 24
	local my = oy + ds + 40
	local colY = my + 16 + 10
	return colY + (if payCoins then 4 else 0) + #RobuxConfig.EggCounts * (EGG_ROW_H + EGG_ROW_GAP) - EGG_ROW_GAP + 10
end
-- A limited egg's wide card is taller by its ENDS IN chip row (an upright phone keeps the chip beside the egg).
local function limitedCardH(eggH: number): number
	return if UI.isPortrait() then eggH else eggH + 26
end

-- Wide egg card: big egg, name, tag, the full rarity odds, and the 1 / 3 / 10 egg price rows on the right.
local function eggCard(parent: Instance, egg: RobuxConfig.Egg, w: number, h: number, order: number): Frame
	local limited = egg.Limited == true
	local c = card(parent, EGG_TONE[egg.Id] or (if limited then LIMITED_TONE else "gold"), { Name = "EggCard_" .. egg.Id, Size = UDim2.fromOffset(w, h), LayoutOrder = order })
	local portrait = UI.isPortrait()
	local rows = RobuxConfig.EggCounts
	local rowH = EGG_ROW_H
	local gap = EGG_ROW_GAP
	local colWidth = if portrait then w - 20 else math.floor(w * 0.27)
	local colX = if portrait then 10 else w - colWidth - 14
	local artW = if portrait then portraitArtW(w) else math.min(h * 0.86, w * 0.2)
	eggView(c, egg.Id, 1, { Position = UDim2.fromOffset(12, if portrait then 10 else (h - artW) / 2), Size = UDim2.fromOffset(artW, artW) }, -25, 0)
	ribbon(c, EGG_TAG[egg.Id] or (if limited then "LIMITED" else ""), K.RibbonRed, { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(108, 20), Rotation = -8 })
	local x0 = artW + 26
	local textW = if portrait then w - x0 - 10 else colX - x0 - 12
	local titleL = words(c, egg.Name, 30, { Position = UDim2.fromOffset(x0, 8), Size = UDim2.fromOffset(math.min(200, textW), 38), OutlineThick = 3, ZIndex = 5 })
	titleL.TextWrapped = false -- one line, shrunk to fit (two lines ran into the blurb on an upright phone)
	if textW > 300 and not limited then
		-- tags are fitted text, which wraps when the box is narrower than the words at the text floor: the boxes are
		-- wide enough for the longest tag on one line (BETTER ODDS broke into two lines on a phone)
		ribbon(c, if egg.Rarity then "BETTER ODDS" else "RACE ODDS", K.Blue, { Position = UDim2.fromOffset(x0 + 204, 16), Size = UDim2.fromOffset(118, 22) })
	end
	-- the blurb wraps to two lines beside a tall egg on an upright phone, and on a narrow landscape window where one
	-- line of body words (about 7.5 px a letter) would not fit: the box is tall enough for both, and the odds row
	-- starts under it (the second line ran into the dots on the 844x390 window)
	local blurb = EGG_BLURB[egg.Id] or (if limited then string.format("1 in %d SHINY! Gone when time's up.", egg.ShinyOneIn or LaunchPerks.Shiny.OneIn) else "")
	local blurbLines = if portrait or textW < #blurb * 7.5 then 2 else 1
	local blurbH = if blurbLines == 2 then 34 else 18
	words(c, blurb, 13, { Position = UDim2.fromOffset(x0, 48), Size = UDim2.fromOffset(textW, blurbH), TextYAlignment = Enum.TextYAlignment.Top, OutlineThick = 1.6, ZIndex = 5 })
	-- limited egg: a dark chip with the clock counting down to the end of the sale (label updated once a second)
	local chipH = 0
	if limited then
		chipH = 26
		local chip = UI.frame(c, { Name = "EndsIn", BackgroundColor3 = K.TabBar, Position = UDim2.fromOffset(x0, 48 + blurbH + 2), Size = UDim2.fromOffset(math.min(176, textW), 22), ZIndex = 5 })
		round(chip, 999)
		edge(chip, K.TabBarEdge, 2)
		UI.icon(chip, "clock", 14, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = 6 })
		local lbl = words(chip, "ENDS IN " .. endsText(limitedEndsAt - os.time()), 12, { Name = "Text", Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -32, 1, 0), TextColor3 = K.Gold, OutlineThick = 1.4, ZIndex = 6 })
		lbl.TextWrapped = false
		tickers.Limited = function()
			if lbl.Parent then
				lbl.Text = "ENDS IN " .. endsText(limitedEndsAt - os.time())
			end
		end
	end
	-- odds: a dot per rarity with its name and chance
	local odds = eggOdds(egg)
	local n = #odds.Rarity
	local oddsX = if portrait then 10 else x0
	local oddsW = if portrait then w - 20 else textW
	local colW = oddsW / n
	local meterH = 16
	local autoH = if payCoins then 26 else 0 -- the AUTO pill shares the meter row and sits a little lower
	local meterY = if portrait then 0 else h - 6 - meterH - (if payCoins then 4 else 0) -- (portrait: set after the odds row)
	-- the dots row sits under the blurb (never over it or the BETTER ODDS ribbon), and above the Lucky Meter with
	-- room for the name and the chance under each dot; dots are 28 px or more (a fingertip)
	local oy = if portrait then artW + 24 else 48 + blurbH + 4 + chipH
	local dotRoom = if portrait then 44 else meterY - 4 - oy - 40 -- name (18) + chance (18) rows under the dots
	local ds = math.floor(math.clamp(math.min(44, colW * 0.6, h * 0.24, dotRoom), 28, 44))
	for i, r in odds.Rarity do
		local x = oddsX + (i - 1) * colW
		local col = RARITY_HEX[r.Name] or K.White
		dot(c, col, ds, { Position = UDim2.fromOffset(x + (colW - ds) / 2, oy) })
		if portrait or colW < 78 then
			-- narrow columns: the chance sits inside the dot and the names zigzag over two rows so neighbours never touch
			words(c, pct(r.P), 12, { Position = UDim2.fromOffset(x + (colW - ds) / 2, oy), Size = UDim2.fromOffset(ds, ds), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.Ink, Outline = false, ZIndex = 6 })
			local nameL = words(c, r.Name, 12, { Position = UDim2.fromOffset(x - 8, oy + ds + 2 + (i % 2) * 15), Size = UDim2.fromOffset(colW + 16, 15), TextXAlignment = Enum.TextXAlignment.Center, OutlineThick = 1.6, ZIndex = 5 })
			nameL.TextWrapped = false
		else
			local nameL = words(c, r.Name, 12, { Position = UDim2.fromOffset(x - 6, oy + ds + 2), Size = UDim2.fromOffset(colW + 12, 18), TextXAlignment = Enum.TextXAlignment.Center, OutlineThick = 1.6, ZIndex = 5 })
			nameL.TextWrapped = false -- one word stays one line (never "Legendar" over a clipped second line)
			words(c, pct(r.P), 13, { Position = UDim2.fromOffset(x - 6, oy + ds + 20), Size = UDim2.fromOffset(colW + 12, 18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = col, OutlineThick = 1.6, ZIndex = 5 })
		end
	end
	-- Lucky Meter (shared/EggPerks): every shop egg fills it; full = the next egg is Epic or better. Shown with the
	-- odds, so a Robux egg's pity rule is disclosed before buying.
	local me = prof()
	local eggPerks: any = if me then me.EggPerks else nil
	local meter = if type(eggPerks) == "table" then tonumber(eggPerks.Meter) or 0 else 0
	local need = if type(eggPerks) == "table" then tonumber(eggPerks.MeterNeed) or EggPerks.Meter.Need else EggPerks.Meter.Need
	local pts = EggPerks.Meter.Points[egg.Id] or 1
	local my = if portrait then oy + ds + 40 else meterY
	local mh = meterH
	-- paying with coins: the AUTO pill (Auto Hatch pass) takes the right end of the meter row
	local autoW = if payCoins then 92 else 0
	local trackW = oddsW - (if payCoins then autoW + 8 else 0)
	local track = UI.frame(c, { Name = "LuckyMeter", BackgroundColor3 = K.Ink, BackgroundTransparency = 0.82, Position = UDim2.fromOffset(oddsX, my), Size = UDim2.fromOffset(trackW, mh), ZIndex = 4 })
	round(track, 999)
	local fill = UI.frame(track, { Name = "Fill", BackgroundColor3 = K.Lime, Size = UDim2.new(math.clamp(meter / math.max(need, 1), 0, 1), 0, 1, 0), ZIndex = 5 })
	round(fill, 999)
	PetStyle.vgrad(fill, K.LimeTop, K.Lime)
	local meterText = string.format("LUCKY METER %d/%d  \u{b7}  +%d per egg  \u{b7}  full = EPIC or better", meter, need, pts)
	if trackW < 240 then
		meterText = string.format("METER %d/%d  \u{b7}  EPIC+", meter, need)
	elseif trackW < 420 then
		meterText = string.format("LUCKY METER %d/%d  \u{b7}  full = EPIC+", meter, need)
	end
	local ml = words(track, meterText, 12, { Name = "Text", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center, OutlineThick = 1.4, ZIndex = 6 })
	ml.TextWrapped = false
	if payCoins then
		-- AUTO: green "AUTO ON" when this is the egg the shrine is auto-hatching (Perks.AutoEgg), blue "AUTO" otherwise.
		-- The colour is the only thing the client decides: the server checks the pass and toasts without it.
		local pk = perks()
		local on = pk ~= nil and pk.AutoEgg == egg.Id
		local pos = { Name = "Auto", Position = UDim2.fromOffset(oddsX + oddsW - autoW, my + mh / 2 - autoH / 2), Size = UDim2.fromOffset(autoW, autoH) }
		local b = if on
			then pill(c, "AUTO ON", K.LimeTop, K.Lime, K.LimeEdge, pos, 13)
			else pill(c, "AUTO", K.BlueTop, K.Blue, K.BlueEdge, pos, 13)
		b.Name = "Auto"
		b.Activated:Connect(function()
			setAuto(if on then "" else egg.Id)
		end)
	end
	-- buy rows (right column, or a bottom stack in portrait)
	local colY = if portrait then my + mh + 10 + (if payCoins then 4 else 0) else math.floor((h - (#rows * rowH + (#rows - 1) * gap)) / 2)
	for i, count in rows do
		local y = colY + (i - 1) * (rowH + gap)
		local row = UI.frame(c, { Name = "Row" .. count, BackgroundColor3 = K.White, Position = UDim2.fromOffset(colX, y), Size = UDim2.fromOffset(colWidth, rowH), ZIndex = 4 })
		round(row, 999)
		edge(row, K.Ink, 2)
		local countL = words(row, count .. (if count == 1 then " Egg" else " Eggs"), 17, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 1, 0), TextColor3 = K.Ink, Outline = false, ZIndex = 5 })
		countL.TextWrapped = false
		if i == #rows then
			-- the tag hangs on the row's top edge, inside the gap above it (never over the odds dots to the left)
			ribbon(row, "BEST VALUE", K.RibbonGold, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(120, 18), Rotation = -4 })
		end
		local pillProps = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(math.min(96, colWidth * 0.5), rowH - 6) }
		if payCoins then
			local p = prof()
			local tierId = RobuxConfig.eggTier(if p then p.UnlockedTiers else nil)
			local price = RobuxConfig.eggCoinPrice(egg.Id, tierId, count) or 0
			coinPill(row, price, if p then tonumber(p.Cash) or 0 else 0, pillProps, 16, function()
				buyEggCoins(egg, count)
			end)
		else
			pricePill(row, priceText(egg.Products[count] or 0, false), pillProps, 16, function()
				buyEgg(egg, count)
			end)
		end
	end
	return c
end

-- Pass card: icon disc with a gift badge, name, effect pill, description, price.
local function passCard(parent: Instance, pass: RobuxConfig.Pass, w: number, h: number, order: number, owned: boolean, pos: UDim2?): Frame
	local c = card(parent, PASS_TONE[pass.Key] or "blue", { Name = "Pass_" .. pass.Key, Size = UDim2.fromOffset(w, h), LayoutOrder = order, Position = pos or UDim2.new() })
	local ds = math.floor(h * 0.3)
	local disc = dot(c, K.White:Lerp(TONES[PASS_TONE[pass.Key] or "blue"][1], 0.4), ds, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6) })
	if pass.Key == "DoubleCoins" then
		local coinD = dot(disc, K.Gold, ds * 0.62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		words(coinD, "$", ds * 0.4, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(140, 90, 0), Outline = false, ZIndex = 7 })
	else
		UI.icon(disc, PASS_ICON[pass.Key] or "star", ds * 0.6, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	end
	local gift = dot(c, K.RibbonPink, 22, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6) })
	UI.icon(gift, "star", 13, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	words(c, pass.Name, 17, { Position = UDim2.fromOffset(6, ds + 8), Size = UDim2.new(1, -12, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, OutlineThick = 2.4, ZIndex = 5 })
	local eff = UI.frame(c, { BackgroundColor3 = K.Shade, BackgroundTransparency = 0.45, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ds + 32), Size = UDim2.fromOffset(w * 0.72, 18), ZIndex = 4 })
	round(eff, 999)
	words(eff, PASS_EFFECT[pass.Key] or "", 12, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.Gold, OutlineThick = 1.4, ZIndex = 5 })
	words(c, pass.Desc, 11, { Position = UDim2.fromOffset(8, ds + 52), Size = UDim2.new(1, -16, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, OutlineThick = 1.3, ZIndex = 5 })
	if owned then
		local b = pill(c, "OWNED", K.BlueTop, K.Blue, K.BlueEdge, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(w * 0.84, 26) }, 14)
		b.Name = "Owned"
	else
		pricePill(c, priceText(pass.PassId, true), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(w * 0.84, 26) }, 14, function()
			buyPass(pass.Key)
		end)
	end
	return c
end

-- Potion card: a wide violet card with a bottle drawn from parts, the effect and the price.
local function potionCard(parent: Instance, w: number, h: number, order: number): Frame
	local c = card(parent, "violet", { Name = "Potion", Size = UDim2.fromOffset(w, h), LayoutOrder = order })
	local portrait = UI.isPortrait()
	-- an upright phone: the bottle keeps the top-left, the words run the card's width and the price pill sits on the
	-- bottom row (the title broke into two lines over the blurb, and the blurb ran under the pill)
	local ds = if portrait then math.min(h * 0.5, 72) else h * 0.68
	local disc = dot(c, Color3.fromRGB(120, 230, 90), ds, { Position = UDim2.fromOffset(14, if portrait then 12 else h * 0.16) })
	UI.icon(disc, "boostLuck", ds * 0.62, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	local x0 = math.floor(ds + (if portrait then 28 else 30))
	ribbon(c, "15 MIN", K.RibbonGold, { Position = UDim2.fromOffset(x0, 10), Size = UDim2.fromOffset(64, 18) })
	local title = words(c, RobuxConfig.Potion.Name, 28, { Position = UDim2.fromOffset(x0, 28), Size = if portrait then UDim2.new(1, -(x0 + 14), 0, 36) else UDim2.new(0.5, 0, 0, 36), OutlineThick = 3, ZIndex = 5 })
	title.TextWrapped = false -- one line, shrunk to fit
	local blurb = "Rare and better pets twice as likely for 15 minutes. Stacks."
	if portrait then
		words(c, blurb, 13, { Position = UDim2.fromOffset(x0, 66), Size = UDim2.new(1, -(x0 + 14), 0, 36), TextYAlignment = Enum.TextYAlignment.Top, OutlineThick = 1.6, ZIndex = 5 })
		pricePill(c, priceText(RobuxConfig.Potion.ProductId, false), { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -8), Size = UDim2.fromOffset(110, 38) }, 20, buyPotion)
	else
		words(c, blurb, 13, { Position = UDim2.fromOffset(x0, 64), Size = UDim2.new(1, -(x0 + 140), 0, 20), OutlineThick = 1.6, ZIndex = 5 })
		pricePill(c, priceText(RobuxConfig.Potion.ProductId, false), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(110, 38) }, 20, buyPotion)
	end
	return c
end

-- Starter Pack card (Featured, once per player; RobuxConfig.StarterPack): the pack's eggs fanned on a disc, a ONE
-- TIME ONLY ribbon, what is inside and the Robux price. Hidden once Perks.StarterPack is true.
local function packCard(parent: Instance, w: number, h: number, order: number): Frame
	local pack = RobuxConfig.StarterPack
	local c = card(parent, "green", { Name = "Pack", Size = UDim2.fromOffset(w, h), LayoutOrder = order })
	local portrait = UI.isPortrait()
	local ds = if portrait then math.min(h * 0.5, 72) else h * 0.68
	local disc = dot(c, K.White:Lerp(TONES.green[1], 0.3), ds, { Position = UDim2.fromOffset(14, if portrait then 12 else h * 0.16) })
	local eggId, n = "RareEgg", 0
	local parts = {}
	for id, count in pack.Eggs do
		local e = RobuxConfig.egg(id)
		eggId = id
		n += count
		table.insert(parts, count .. " " .. (if e then e.Name else "Egg") .. (if count == 1 then "" else "s"))
	end
	table.sort(parts)
	-- the eggs inside, fanned on the disc, with their count on a small gold tag
	eggView(disc, eggId, 2, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.52), Size = UDim2.fromScale(0.62, 0.62), ZIndex = 6 }, -30, 0, false)
	eggView(disc, eggId, 3, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.52), Size = UDim2.fromScale(0.62, 0.62), ZIndex = 6 }, 30, 0, false)
	eggView(disc, eggId, 1, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.74, 0.74), ZIndex = 7 }, -10, 0, false)
	ribbon(disc, "x" .. n, K.RibbonGold, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 4, 1, 2), Size = UDim2.fromOffset(40, 18), ZIndex = 8 })
	local x0 = math.floor(ds + (if portrait then 28 else 30))
	ribbon(c, "ONE TIME ONLY", K.RibbonPink, { Position = UDim2.fromOffset(x0, 8), Size = UDim2.fromOffset(140, 20) }) -- wide enough for one line at the text floor
	local title = words(c, pack.Name .. "!", 28, { Position = UDim2.fromOffset(x0, 28), Size = if portrait then UDim2.new(1, -(x0 + 14), 0, 36) else UDim2.new(0.5, 0, 0, 36), OutlineThick = 3, ZIndex = 5 })
	title.TextWrapped = false -- one line, shrunk to fit
	local inside = table.concat(parts, " + ") .. " + " .. math.floor(pack.PotionSeconds / 60) .. " min 2x luck"
	local price = priceText(pack.ProductId, false)
	if portrait then
		words(c, inside, 13, { Position = UDim2.fromOffset(x0, 66), Size = UDim2.new(1, -(x0 + 14), 0, 36), TextYAlignment = Enum.TextYAlignment.Top, OutlineThick = 1.6, ZIndex = 5 })
		pricePill(c, price, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -8), Size = UDim2.fromOffset(110, 38) }, 20, buyPack)
	else
		words(c, inside, 13, { Position = UDim2.fromOffset(x0, 64), Size = UDim2.new(1, -(x0 + 140), 0, 20), OutlineThick = 1.6, ZIndex = 5 })
		pricePill(c, price, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(110, 38) }, 20, buyPack)
	end
	return c
end

-- White sheet with the pass cards in a row (a grid in portrait).
local function passSheet(parent: Instance, w: number, order: number): Frame
	local p = prof()
	local ownedN = 0
	local keys = RobuxConfig.PassOrder
	for _, k in keys do
		if p and p.Robux and p.Robux.Passes and p.Robux.Passes[k] then
			ownedN += 1
		end
	end
	local portrait = UI.isPortrait()
	local gap = 10
	-- one row of six on a wide screen; a phone on its side (844 wide) gets two rows of three, an upright phone three
	-- rows of two, so every card keeps at least 150 px for its name, effect pill and price
	local cols = if portrait then 2 elseif (w - 24 - gap * (#keys - 1)) / #keys >= 150 then #keys else math.ceil(#keys / 2)
	-- wide screens: the cards grow (up to 250) and the row sits in the middle, so no empty white field is left
	local cardW = if portrait then (w - 24 - gap) / 2 else math.floor(math.min(250, (w - 24 - gap * (cols - 1)) / cols))
	local rowX = if portrait then 12 else math.floor((w - (cols * cardW + (cols - 1) * gap)) / 2)
	local cardH = 180
	local rows = math.ceil(#keys / cols)
	local sheetH = 44 + rows * cardH + (rows - 1) * gap + 14
	local _, sheet = shadowed(parent, 14, 4, nil, { Name = "PassSheet", Size = UDim2.fromOffset(w, sheetH), LayoutOrder = order })
	edge(sheet, K.PanelEdge, 2)
	pattern(sheet, K.PanelPattern, 0.25, 40, w, sheetH)
	local disc = dot(sheet, K.Blue, 26, { Position = UDim2.fromOffset(12, 9) })
	UI.icon(disc, "egg", 16, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
	words(sheet, "Boosts", 22, { Position = UDim2.fromOffset(44, 6), Size = UDim2.fromOffset(120, 32), TextColor3 = K.Blue, OutlineColor = K.TitleEdge, OutlineThick = 2.2, ZIndex = 5 })
	local cnt = UI.frame(sheet, { BackgroundColor3 = K.TabBar, Position = UDim2.fromOffset(166, 12), Size = UDim2.fromOffset(84, 20), ZIndex = 4 })
	round(cnt, 999)
	words(cnt, ownedN .. "/" .. #keys .. " owned", 12, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, OutlineThick = 1.2, ZIndex = 5 })
	if not portrait then
		words(sheet, "More coins, more pets, more spots", 13, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(240, 20), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = K.TitleEdge, Outline = false, ZIndex = 5 })
	end
	for i, key in keys do
		local pass = RobuxConfig.Passes[key]
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		passCard(sheet, pass, cardW, cardH, i, p ~= nil and p.Robux ~= nil and p.Robux.Passes ~= nil and p.Robux.Passes[key] == true, UDim2.fromOffset(rowX + col * (cardW + gap), 44 + row * (cardH + gap)))
	end
	return sheet
end

-- Screen ------------------------------------------------------------------------------------------------------------

local function renderNow()
	local sc = content
	if not sc or not open then
		return
	end
	for _, ch in table.clone(sc:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	tickers.Limited = nil -- the content's countdown label is rebuilt below
	local portrait = UI.isPortrait()
	local w = contentW
	local p = prof()
	local pk = perks()
	local hidden = player:GetAttribute("PaidRandomRestricted") ~= false
	local limitedOn = limitedEgg() -- the limited egg on sale (Robux only: it has no coin price)
	local order = 0
	local function next(): number
		order += 1
		return order
	end
	local eggs = RobuxConfig.Eggs
	local mythic = eggs[#eggs]
	if tab == "Featured" then
		if not hidden then
			-- hero + side column
			local H = UI.Logical.Y
			-- 144 or taller: the two side cards (half of it each) need their ribbon, name and pill rows
			local heroH = if portrait then 150 else math.floor(math.clamp(H * 0.32, 144, 200))
			local eggH = if portrait then eggCardHeight(w) else math.floor(math.clamp(H * 0.38, 172, 230))
			if portrait then
				heroCard(sc, mythic, w, heroH, next())
				sideCard(sc, "gold", eggs[2].Name, "1 in 200 Legendary", priceText(eggs[2].Products[1] or 0, false), w, 64, next(), nil, nil, function(box)
					eggView(box, eggs[2].Id, 2, { Size = UDim2.fromScale(1, 1) }, -20, 0, false)
				end, function()
					buyEgg(eggs[2], 1)
				end)
				sideCard(sc, "violet", RobuxConfig.Potion.Name, "+1 luck for 15 minutes", priceText(RobuxConfig.Potion.ProductId, false), w, 64, next(), "15 MIN", K.RibbonGold, function(box)
					UI.icon(box, "boostLuck", 36, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
				end, buyPotion)
			else
				local rowF = UI.frame(sc, { Name = "TopRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(w, heroH), LayoutOrder = next() })
				local sideW = math.floor(w * 0.3)
				local heroW = w - sideW - 12
				heroCard(rowF, mythic, heroW, heroH, 1)
				local col = UI.frame(rowF, { Name = "Side", BackgroundTransparency = 1, Position = UDim2.fromOffset(heroW + 12, 0), Size = UDim2.fromOffset(sideW, heroH) })
				UI.list(col, Enum.FillDirection.Vertical, 12)
				local sh = (heroH - 12) / 2
				sideCard(col, "gold", eggs[2].Name, "1 in 200 Legendary", priceText(eggs[2].Products[1] or 0, false), sideW, sh, 1, nil, nil, function(box)
					eggView(box, eggs[2].Id, 2, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.3, 1.3) }, -20, 0, false)
				end, function()
					buyEgg(eggs[2], 1)
				end)
				sideCard(col, "violet", RobuxConfig.Potion.Name, "+1 luck for 15 minutes", priceText(RobuxConfig.Potion.ProductId, false), sideW, sh, 2, "15 MIN", K.RibbonGold, function(box)
					UI.icon(box, "boostLuck", math.min(36, sh * 0.6), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
				end, buyPotion)
			end
			-- Starter Pack (once per player; Perks.StarterPack hides it, the server re-checks) and the limited egg
			if not (pk and pk.StarterPack == true) then
				packCard(sc, w, if portrait then 160 else 110, next())
			end
			if limitedOn then
				eggCard(sc, limitedOn, w, limitedCardH(eggH), next())
			end
			eggCard(sc, mythic, w, eggH, next())
		end
		heading(sc, "egg", "Gamepasses", "Permanent. Pay once, keep forever", next())
		passSheet(sc, w, next())
	elseif tab == "Eggs" then
		if hidden then
			words(sc, "Eggs are not for sale on this account.", 16, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = next() })
		else
			-- "Pay with" switch: Robux (the products) or coins (the old hatch stand's prices, for the player's best zone)
			local sw = UI.frame(sc, { Name = "PayWith", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = next() })
			words(sw, "Pay with", 16, { Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(90, 36), OutlineThick = 2 })
			local function payPill(x: number, label: string, coins: boolean)
				local on = payCoins == coins
				local b = if on
					then pill(sw, label, K.LimeTop, K.Lime, K.LimeEdge, { Position = UDim2.fromOffset(x, 2), Size = UDim2.fromOffset(96, 32) }, 15)
					else pill(sw, label, K.TabBar, K.TabBar, K.TabBarEdge, { Position = UDim2.fromOffset(x, 2), Size = UDim2.fromOffset(96, 32) }, 15)
				b.Name = "Pay_" .. label
				b.Activated:Connect(function()
					if payCoins ~= coins then
						payCoins = coins
						requestRender()
					end
				end)
			end
			payPill(96, "Robux", false)
			payPill(200, "Coins", true)
			local H = UI.Logical.Y
			local eggH = if portrait then eggCardHeight(w) else math.floor(math.clamp(H * 0.38, 172, 230))
			if limitedOn and not payCoins then
				eggCard(sc, limitedOn, w, limitedCardH(eggH), next())
			end
			for i = #eggs, 1, -1 do
				eggCard(sc, eggs[i], w, eggH, next())
			end
		end
	elseif tab == "Passes" then
		heading(sc, "egg", "Gamepasses", "Permanent. Pay once, keep forever", next())
		passSheet(sc, w, next())
	elseif tab == "Potions" then
		if hidden then
			words(sc, "Potions are not for sale on this account.", 16, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = next() })
		else
			potionCard(sc, w, if portrait then 160 else 110, next()) -- upright: the words sit over the pill
			local until_ = if p and p.Robux then p.Robux.LuckUntil or 0 else 0
			local left = math.max(0, until_ - os.time())
			-- the status line sits on its own white strip (plain words straight on the world read unfinished)
			local _, strip = shadowed(sc, 12, 3, nil, { Name = "PotionStatus", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = next() })
			edge(strip, K.PanelEdge, 2)
			words(strip, if left > 0 then string.format("Potion running: %d min left", math.ceil(left / 60)) else "No potion running. Weekends are 2x luck for everyone.", 14, { Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextColor3 = K.TitleEdge, Outline = false, ZIndex = 5 })
		end
	end
	UI.frame(sc, { Name = "EndGap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = next() })
	-- the cards pop in one after another (Theme.Spring.Pop; Reduce Motion: none)
	local i = 0
	for _, ch in sc:GetChildren() do
		if ch:IsA("GuiObject") and ch.Visible and ch.Name ~= "EndGap" and ch.AbsoluteSize.Y ~= 0 then
			UI.pop(ch, 0.86, i * 0.04)
			i += 1
		end
	end
end

function render()
	if rendering then
		renderQueued = true
		return
	end
	rendering = true
	local ok, err = pcall(renderNow :: any)
	rendering = false
	if not ok then
		warn("[PetShop] render failed: " .. tostring(err))
	end
	if renderQueued then
		renderQueued = false
		task.defer(render)
	end
end

local function closeShop()
	open = false
	UI.closeModal()
end

local function build()
	-- the modal gives the shade, the blur, the gamepad focus and the close rules; its own sheet is hidden
	local pnl = UI.modal("PetShop", "", Vector2.new(4000, 4000), { Fixed = true, NoClose = true })
	pnl.BackgroundTransparency = 1
	pnl:SetAttribute("KitHeaderOnRim", nil)
	pnl:SetAttribute("KitPanel", nil)
	pnl:SetAttribute("OwnerSkin", true)
	for _, ch in table.clone(pnl:GetChildren()) do
		if ch.Name ~= "Body" and ch.Name ~= "Enter" and not ch:IsA("UISizeConstraint") then
			ch:Destroy()
		end
	end
	local body = pnl:FindFirstChild("Body") :: Frame
	body.Position = UDim2.fromOffset(0, 0)
	body.Size = UDim2.fromScale(1, 1)
	local bp = body:FindFirstChildOfClass("UIPadding")
	if bp then
		bp:Destroy()
	end
	local shade = pnl.Parent
	if shade and shade:IsA("GuiObject") then
		shade.BackgroundTransparency = 0.42
	end
	local portrait = UI.isPortrait()
	-- the modal panel is the screen less its margins (Size = 1 - 24 px wide, 1 - gap tall): laying out from the
	-- whole screen ran the cards past the panel's right edge (flat corners, buy pills on the rim)
	local W = UI.Logical.X + pnl.Size.X.Offset
	local H = UI.Logical.Y + pnl.Size.Y.Offset
	local sideGap = if portrait then 10 else math.floor(W * 0.07)
	local topY = if portrait then 8 else math.floor(H * 0.07)
	local barH = 44 -- the tab pills and the coin pill: a fingertip tall on every screen
	-- title
	local titleW = if portrait then 90 else 120
	local shadow = words(body, "Shop", if portrait then 34 else 42, { Name = "TitleShadow", Position = UDim2.fromOffset(sideGap, topY + 3), Size = UDim2.fromOffset(titleW, barH + 6), TextColor3 = K.TitleShadow, OutlineColor = K.TitleShadow, OutlineThick = 4, ZIndex = 3 })
	shadow.TextTransparency = 0
	words(body, "Shop", if portrait then 34 else 42, { Name = "Title", Position = UDim2.fromOffset(sideGap, topY), Size = UDim2.fromOffset(titleW, barH + 6), OutlineColor = K.TitleEdge, OutlineThick = 3.4, ZIndex = 4 })
	-- lucky hour chip (LaunchPerks): hangs under the coin pill while a lucky hour runs or is under two hours away;
	-- the rows under it move down by its height, and a change of state rebuilds the header (once an hour at most)
	local chipMode, chipLeft = luckyMode()
	local chipH = if chipMode then 24 else 0
	local chipGap = if chipMode then chipH + 4 else 0
	-- tab strip
	local coinW = if portrait then 134 else 144 -- upright: room for "12.4K" on one line beside the + disc
	local xW = barH + 8
	local stripX = sideGap + titleW + 8
	local stripW = W - sideGap - xW - 12 - coinW - 12 - stripX
	local stripY = topY + 4
	if portrait then
		stripX = sideGap
		stripY = topY + barH + 14 + chipGap
		stripW = W - 2 * sideGap
	end
	local strip = UI.frame(body, { Name = "Tabs", BackgroundColor3 = K.TabBar, Position = UDim2.fromOffset(stripX, stripY), Size = UDim2.fromOffset(stripW, barH), ZIndex = 3 })
	round(strip, 999)
	edge(strip, K.TabBarEdge, 2.5)
	local n = #TABS
	local tabW = (stripW - 8) / n
	local sel = UI.frame(strip, { Name = "Selected", BackgroundColor3 = K.Lime, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(tabW, barH - 6), ZIndex = 4 })
	round(sel, 999)
	vgrad(sel, K.LimeTop, K.Lime)
	edge(sel, K.LimeEdge, 2)
	local tabButtons: { [string]: TextLabel } = {}
	local function placeSel(instant: boolean)
		local i = table.find(TABS, tab) or 1
		local target = UDim2.fromOffset(4 + (i - 1) * tabW, 3)
		if instant or still() then
			sel.Position = target
		else
			UI.spring(sel, MOTION.TabSlide, { Position = target })
		end
		for name, l in tabButtons do
			l.TextColor3 = if name == tab then K.Ink else K.TabText
			local o = l:FindFirstChild("Outline")
			if o and o:IsA("UIStroke") then
				o.Transparency = if name == tab then 1 else 0
			end
		end
	end
	for i, name in TABS do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. name
		b.BackgroundTransparency = 1
		b.Text = ""
		b.AutoButtonColor = false
		b.Position = UDim2.fromOffset(4 + (i - 1) * tabW, 0)
		b.Size = UDim2.fromOffset(tabW, barH)
		b.ZIndex = 5
		b.Parent = strip
		local l = words(b, name, if portrait then 14 else 16, { Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.TabText, OutlineThick = 1.4, ZIndex = 6 })
		tabButtons[name] = l
		b.Activated:Connect(function()
			if tab ~= name then
				tab = name
				placeSel(false)
				render()
				if content then
					content.CanvasPosition = Vector2.new()
				end
			end
		end)
	end
	placeSel(true)
	-- coin pill
	local coinX = W - sideGap - xW - 12 - coinW
	local coinY = topY + 4
	local coin = UI.frame(body, { Name = "Coins", BackgroundColor3 = K.TabBar, Position = UDim2.fromOffset(coinX, coinY), Size = UDim2.fromOffset(coinW, barH), ZIndex = 3 })
	round(coin, 999)
	edge(coin, K.TabBarEdge, 2.5)
	local coinDisc = dot(coin, K.Gold, barH - 10, { Position = UDim2.fromOffset(5, 5) })
	words(coinDisc, "$", 16, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(140, 90, 0), Outline = false, ZIndex = 6 })
	local cashN = if prof() then prof().Cash or 0 else 0
	-- an upright phone's narrow pill shows 12.5K from 10,000 up (the full number split over two lines)
	local cashText = if portrait and cashN >= 10000 then (string.gsub(string.format("%.1f", math.floor(cashN / 100) / 10), "%.0$", "")) .. "K" else UI.num(cashN)
	-- the "+" disc is a fingertip wide (32 or more) and the amount keeps the room left of it
	local plusS = math.max(32, barH - 8)
	local cashL = words(coin, cashText, 17, { Position = UDim2.fromOffset(barH, 0), Size = UDim2.new(1, -(barH + plusS + 6), 1, 0), OutlineThick = 1.6, ZIndex = 5 })
	cashL.TextWrapped = false -- one line: on an upright phone the digits split over two (12,4 / 80)
	-- coins change while the shop is open (a coin egg, a gift): the amount follows them (Studio 2026-10-15 stayed 0)
	tickers.Cash = function()
		local n = if prof() then prof().Cash or 0 else 0
		local t = if portrait and n >= 10000 then (string.gsub(string.format("%.1f", math.floor(n / 100) / 10), "%.0$", "")) .. "K" else UI.num(n)
		if cashL.Parent and cashL.Text ~= t then
			cashL.Text = t
		end
	end
	local plus = dot(coin, K.Lime, plusS, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0) })
	words(plus, "+", 20, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.LimeEdge, Outline = false, ZIndex = 6 })
	-- the lucky hour chip: gold while it runs ("LUCKY HOUR 2x · 43:12"), navy with gold words before ("in 1:20:00")
	tickers.Lucky = nil
	if chipMode then
		local on = chipMode == "on"
		local chip = UI.frame(body, { Name = "LuckyHour", BackgroundColor3 = if on then K.Gold else K.TabBar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(coinX + coinW, coinY + barH + 4), Size = UDim2.fromOffset(if portrait then 176 else 190, chipH), ZIndex = 3 })
		round(chip, 999)
		edge(chip, if on then Theme.Color.GoldDeep else K.TabBarEdge, 2)
		if on then
			vgrad(chip, K.Gold:Lerp(K.White, 0.3), K.Gold)
		end
		local lbl = words(chip, luckyText(chipMode, chipLeft), 13, {
			Name = "Text", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if on then Theme.Color.DarkText else K.Gold, Outline = if on then false else nil, OutlineThick = 1.4, ZIndex = 5,
		})
		lbl.TextWrapped = false
		local mode0 = chipMode
		tickers.Lucky = function()
			local mode, left = luckyMode()
			if mode ~= mode0 then
				tickers.Lucky = nil
				task.defer(function()
					if open then
						build()
					end
				end)
			elseif lbl.Parent and mode then
				lbl.Text = luckyText(mode, left)
			end
		end
	else
		tickers.Lucky = function()
			if luckyMode() ~= nil then
				tickers.Lucky = nil
				task.defer(function()
					if open then
						build()
					end
				end)
			end
		end
	end
	-- red X
	local x = pill(body, "X", K.RedTop, K.Red, K.RedEdge, { Name = "Close", Position = UDim2.fromOffset(W - sideGap - xW, topY + 2), Size = UDim2.fromOffset(xW, xW) }, 24)
	x.Rotation = 4
	local xc = x:FindFirstChildOfClass("UICorner")
	if xc then
		xc.CornerRadius = UDim.new(0, 12)
	end
	x.Activated:Connect(closeShop)
	-- content
	local contentY = stripY + barH + (if portrait then 10 else 16 + chipGap)
	local sc = UI.scroller(body, { Name = "Content", Position = UDim2.fromOffset(sideGap, contentY), Size = UDim2.new(1, -2 * sideGap, 1, -contentY - 10) })
	sc.ScrollBarThickness = 6
	sc.ScrollBarImageColor3 = K.PanelEdge
	contentW = W - 2 * sideGap - UI.ScrollBar - 6
	UI.list(sc, Enum.FillDirection.Vertical, if portrait then 12 else 14)
	content = sc
	render()
	local conn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "PetShop" then
			open = false
					content = nil
			conn:Disconnect()
		end
	end)
end

function PetShop.open(openTab: string?)
	if openTab and table.find(TABS, openTab) then
		tab = openTab
	end
	open = true
	build()
	startTicking()
end

-- Eggs tab paid with coins (the preview scene flips it; the switch on the tab does in play).
function PetShop.setPayCoins(on: boolean)
	payCoins = on
end

function PetShop.isOpen(): boolean
	return open
end

function PetShop.start()
	State.Changed.Event:Connect(requestRender)
	-- a window resized or a phone turned while the shop is open: the header and cards are laid out for the old size
	UI.Resized.Event:Connect(function()
		if open then
			task.defer(function()
				if open then
					build()
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(requestRender)
end

return PetShop
