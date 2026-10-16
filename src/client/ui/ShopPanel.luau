--!strict
-- UPGRADES (boards 4, 5 and additional 1-3): one shop shell for every category. Tabs only for categories that
-- exist (Tools, Machines when enabled, Storage, Tiers, Gallery, and the cosmetic Store once a real product id is
-- set). Each tab builds Specs from Config and the profile (names, prices, effects, ownership: nothing invented
-- here); the shell shows them as a catalog list on the left and ONE selected-item view on the right (portrait:
-- stacked) with a picture, one effect line, the real price or requirement and one action in its true state:
-- BUY / UPGRADE / UNLOCK / EQUIP / INSTALL, or EQUIPPED / OWNED / LOCKED / NOT ENOUGH CASH / PURCHASING.
-- Purchases ask for confirmation first (item, price, consequence); nothing is sent until CONFIRM. The server
-- re-checks everything and the interface follows its reply (profile update or a refusal notification).
--
-- Entry points: ShopPanel.open(tab?) (the HUD tile and the lobby Upgrades counter both call it).

local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)
local ProgressConfig = require(Shared.ProgressConfig)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local HudArt = require(script.Parent.HudArt)
local Theme = require(script.Parent.Theme)
local Juice = require(script.Parent.Juice)
local ModelThumb = require(script.Parent.ModelThumb)
local ItemView = require(script.Parent.ItemView)
local UpgradePreview = require(script.Parent.Parent.UpgradePreview)
local PetShop = require(script.Parent.PetShop)
local StyleKit = require(script.Parent.StyleKit)

local T = UI.T
local TC = Theme.Color
local ShopPanel = {}

-- Preview/development only: the ReplicatedStorage attribute "DevShopMock" = N appends N made-up Tools entries
-- (never granted, never sent to the server) so the shell can be checked with long lists. Nothing in the game sets
-- it; the offline preview scene `shop --set mock=N` does.
local function devMock(): number
	local n = game:GetService("ReplicatedStorage"):GetAttribute("DevShopMock")
	return if type(n) == "number" then math.clamp(math.floor(n), 0, 100) else 0
end

local tab = "Gear"
local body: Frame? = nil
local panelRef: Frame? = nil
local open = false
local selected: { [string]: string } = {} -- tab -> Spec.Key
local listScroll = Vector2.zero
local pending: { Key: string, At: number }? = nil -- a purchase / equip waiting for the server
local PENDING_SECONDS = 6

local TABS = { "Gear", "Nests", "Storage", "Tiers", "Gallery", "Store", "Robux" } -- "Robux" opens the EGG SHOP

-- `px` real pixels in logical units at the current layer scale (rows and tags are set from the real size they
-- must reach: a 50 logical row drew about 40 real px on the Studio phone window)
local function realPx(px: number): number
	return math.ceil(px / math.max(UI.Scale, 0.5))
end

-- Style test #1 POLYGON ADVENTURE (visual only): parchment panel, tan edges, gold gems, green active tab / buy button,
-- cream cards with a green selected outline, dark brown words. Re-applied after every render.
local PARCH, TAN, CREAMC = Color3.fromRGB(248, 236, 208), Color3.fromRGB(184, 144, 86), Color3.fromRGB(255, 249, 232)
local BROWN, GREENF, GREENL = Color3.fromRGB(70, 44, 20), Color3.fromRGB(120, 200, 110), Color3.fromRGB(58, 140, 52)
local ORANGE = Color3.fromRGB(232, 120, 30)
local GREEN_BTN: StyleKit.ButtonSkin = { Fill = GREENF, Hover = Color3.fromRGB(140, 214, 128), Line = GREENL, Text = BROWN, OffFill = Color3.fromRGB(214, 204, 178), OffText = Color3.fromRGB(120, 104, 78) }
local CREAM_BTN: StyleKit.ButtonSkin = { Fill = CREAMC, Hover = Color3.fromRGB(255, 240, 200), Line = TAN, Text = BROWN, OffFill = Color3.fromRGB(214, 204, 178), OffText = Color3.fromRGB(120, 104, 78) }

-- The kit panel picture is on (UI.kitPanel): the style test's drawn extras (gems, rail, recoloured buttons) step
-- aside and the kit draws the frame; only the parchment fill and the dark words stay (Studio check 2026-10-14).
local function kitOn(): boolean
	return panelRef ~= nil and (panelRef :: Frame):GetAttribute("KitOn") == true
end

local function skinPanel(panel: Frame)
	if Theme.PetStyle then
		return -- the shared pet look draws the sheet
	end
	StyleKit.panel(panel, PARCH, TAN, 4, Color3.fromRGB(214, 176, 80), GREENF, GREENL, BROWN)
	if panel:GetAttribute("KitOn") then
		return
	end
	for _, c in panel:GetChildren() do
		if c:IsA("ImageLabel") then
			c.Visible = false
		end
	end
	StyleKit.cornerGems(panel, Color3.fromRGB(255, 200, 60), Color3.fromRGB(150, 100, 20), 14, true)
end

local function skinBody(b: Frame)
	if Theme.PetStyle then
		return
	end
	for _, d in b:GetDescendants() do
		if d:IsA("GuiButton") and d:GetAttribute("Style") ~= nil then
			if kitOn() then
				continue -- kit primaries and flat secondaries keep their own look
			end
			local st = d:GetAttribute("Style")
			if st == "gold" or st == "green" then
				StyleKit.button(d, GREEN_BTN)
			elseif st == "gray" then
				StyleKit.button(d, CREAM_BTN)
			end
		elseif d:IsA("TextButton") and string.sub(d.Name, 1, 4) == "Row_" then
			StyleKit.holdBg(d, { TC.Inset, TC.InsetHover }, CREAMC)
			local sk = d:FindFirstChildOfClass("UIStroke")
			if sk then
				sk.Color = if d:GetAttribute("Selected") == true then GREENL else TAN
			end
		elseif d:IsA("Frame") and (d.Name == "Detail" or d.Name == "Status") then
			local equipped = d.Name == "Status" and StyleKit.near(d.BackgroundColor3, TC.GoldDim)
			local fr = d :: Frame
			fr.BackgroundColor3 = if equipped then GREENF elseif d.Name == "Detail" then CREAMC else PARCH
			local sk = fr:FindFirstChildOfClass("UIStroke")
			if sk then
				sk.Color = if equipped then GREENL else TAN
			end
		elseif d:IsA("TextLabel") and d.Name == "MoreHint" then
			d.BackgroundColor3 = Color3.fromRGB(150, 110, 60)
		end
	end
	StyleKit.text(b, function(l: TextLabel): Color3?
		if l.Name == "MoreHint" or l.Name == "Label" and l.Parent and l.Parent:GetAttribute("Style") ~= nil then
			return nil
		end
		local c = l.TextColor3
		if l.Name == "PickedArrow" then
			return ORANGE
		elseif l.Name == "Word" and l.Parent and l.Parent.Name == "Status" then
			local pf = l.Parent :: Frame
			return if StyleKit.near(pf.BackgroundColor3, GREENF) then BROWN else nil
		elseif StyleKit.near(c, TC.DarkText) then
			return nil
		elseif c.R + c.G + c.B > 2.3 then
			return BROWN -- white / pale words made for a blue panel
		elseif c.R > 0.9 and c.B < 0.3 then
			return Color3.fromRGB(176, 100, 10) -- gold and orange counts
		elseif c.G > 0.8 and c.R < 0.6 then
			return GREENL -- coin green
		end
		return nil
	end)
	-- a quiet row of low-poly accents: the tabs sit on a green rail
	local tabs = b:FindFirstChild("Tabs")
	if tabs and tabs:IsA("GuiObject") and not b:FindFirstChild("TabRail") and not kitOn() then
		local rail = Instance.new("Frame")
		rail.Name = "TabRail"
		rail.BackgroundColor3 = Color3.fromRGB(196, 226, 168)
		rail.BorderSizePixel = 0
		rail.Position = UDim2.new(0, -4, 0, -3)
		rail.Size = UDim2.new(1, 8, 0, T.Tab + 6)
		rail.ZIndex = math.max(tabs.ZIndex - 1, 0)
		local rs = Instance.new("UIStroke")
		rs.Color = GREENL
		rs.Thickness = 2
		rs.Parent = rail
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 10)
		rc.Parent = rail
		rail.Parent = b
	end
end

local function shop(action: string, id: any?)
	Net.event("ShopAction"):FireServer(action, id)
end

local function store(action: string, id: string)
	Net.event("StoreAction"):FireServer(action, id)
end

-- Robux price as Roblox reports it for the product (never invented here); until known the config placeholder.
local priceCache: { [number]: string } = {}
local priceAsked: { [number]: boolean } = {}
local render
local function robuxPrice(entry): string
	local cached = priceCache[entry.ProductId]
	if cached then
		return cached
	end
	if not priceAsked[entry.ProductId] then
		priceAsked[entry.ProductId] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(entry.ProductId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				priceCache[entry.ProductId] = "R$ " .. info.PriceInRobux
				render()
			end
		end)
	end
	return entry.PriceText
end

-- One catalog entry.
--   State: "buy" (cash purchase: Buy / Upgrade / Unlock), "equip" (owned, can be equipped / installed),
--          "equipped" (in use), "owned" (included / already bought), "locked" (a requirement is missing),
--          "fixed" (a capacity with no upgrade), "max" (fully upgraded), "robux" (cosmetic store)
export type Spec = {
	Key: string,
	Title: string,
	Thumb: (Instance, number) -> (), -- draws the picture into a container (size hint)
	Effect: string, -- one real effect / stat line
	Note: string?, -- one more line (requirement, consequence)
	State: string,
	Price: number?,
	PriceText: string?, -- Robux text
	Verb: string?, -- BUY / UPGRADE / UNLOCK / EQUIP / INSTALL / REMOVE
	Confirm: string?, -- confirmation question for cash purchases
	Consequence: string?, -- what the purchase does (shown in the confirmation)
	Reason: string?, -- why it is locked
	Action: (() -> ())?,
	Preview: string?, -- tool / machine id for the lobby pedestal
	Capacity: number?, -- "fixed" entries: the size shown in the detail view
	Unit: string?,
}

local function iconThumb(kind: string): (Instance, number) -> ()
	return function(parent: Instance, size: number)
		UI.icon(parent, kind, size, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
end

-- the owner's 3D pet gear model (Assets.Kit.Gear_<Id> via ItemView; ItemView draws its own icon when it is missing)
local function gearThumb(id: string): (Instance, number) -> ()
	return function(parent: Instance, size: number)
		ItemView.make(parent, id, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size) }, size)
	end
end

local function kitThumb(kit: string, icon: string): (Instance, number) -> ()
	return function(parent: Instance, size: number)
		ModelThumb.make(parent, kit, icon, size)
	end
end

-- Catalog data per tab ------------------------------------------------------------------------

local function cashState(price: number, cash: number): string
	return if cash >= price then "buy" else "poor"
end


local function toolSpecs(prof, cash: number): { Spec }
	local specs = {}
	for _, id in Config.HandheldOrder do
		local h = Config.Handhelds[id]
		local unit = if h.Hold then "pulses/s" else "taps/s"
		local spec: Spec = {
			Key = id, Title = h.Name, Thumb = gearThumb(id), Preview = id,
			Effect = "Find power " .. h.Damage .. " \u{b7} " .. string.format("%.1f", h.Rate) .. " " .. unit,
			Note = if h.Hold then "Hold to hatch eggs faster at your nest." else "Helps you hatch eggs at your nest.",
			State = cashState(h.Price, cash), Price = h.Price, Verb = "BUY",
			Confirm = "Buy this gear?", Consequence = "It is equipped right away.",
			Action = function()
				shop("BuyHandheld", id)
			end,
		}
		-- side by side with what you hold now, so the step up is easy to see
		local now = Config.Handhelds[prof.EquippedHandheld]
		if now and prof.EquippedHandheld ~= id then
			spec.Effect ..= "  (yours: Find power " .. now.Damage .. ")"
			-- the confirmation shows the change: what you hold now -> what you get
			local nowUnit = if now.Hold then "pulses/s" else "taps/s"
			spec.Consequence = "Find power " .. now.Damage .. " -> " .. h.Damage .. ", " .. string.format("%.1f", now.Rate) .. " " .. nowUnit
				.. " -> " .. string.format("%.1f", h.Rate) .. " " .. unit .. ". It is equipped right away."
		end
		if prof.EquippedHandheld == id then
			spec.State = "equipped"
		elseif prof.EquipmentOwned[id] then
			spec.State, spec.Verb = "equip", "EQUIP"
			spec.Action = function()
				shop("Equip", id)
			end
		end
		table.insert(specs, spec)
	end
	for i = 1, devMock() do
		table.insert(specs, {
			Key = "DevMock" .. i, Title = "Test item " .. i .. (if i % 5 == 0 then " with a very long catalog name" else ""), Thumb = iconThumb("boostLuck"),
			Effect = "Development mock: not a real item", State = if i % 3 == 0 then "equip" elseif i % 3 == 1 then "poor" else "locked",
			Price = i * 100, Verb = "EQUIP", Reason = "Development mock", Action = function() end,
		})
	end
	return specs
end

local MACHINE_ICON = { AutoCracker = "machine", HydraulicPress = "press", IndustrialCrusher = "crusher" }

local function machineSpecs(prof, cash: number): { Spec }
	local specs = {}
	for _, id in Config.MachineOrder do
		local mc = Config.Machines[id]
		local rate = mc.RocksPerBatch / mc.BatchSeconds
		local spec: Spec = {
			Key = id, Title = mc.Name, Thumb = gearThumb(id), Preview = id,
			Effect = "Hatches eggs for you automatically.",
			Note = string.format("%.1f eggs/s at your nest. It never fetches eggs.", rate),
			State = cashState(mc.Price, cash), Price = mc.Price, Verb = "BUY",
			Confirm = "Buy this nest upgrade?", Consequence = "It is set up at your nest right away.",
			Action = function()
				shop("BuyMachine", id)
			end,
		}
		if prof.InstalledMachine == id then
			spec.State = "equipped"
		elseif prof.EquipmentOwned[id] then
			spec.State, spec.Verb = "equip", "INSTALL"
			spec.Action = function()
				shop("InstallMachine", id)
			end
		end
		local _ = MACHINE_ICON
		table.insert(specs, spec)
	end
	return specs
end

-- Storage: the three capacities a player deals with, each upgraded with coins: the candy bag (Config.Capacity), the
-- carry basket and the hatch nest (shared/ProgressConfig; the server enforces the sizes in the round core).
-- One level at a time; the request names the level shown so a stale screen cannot buy twice.
local function levelSpec(key: string, title: string, thumb: (Instance, number) -> (), level: number, list: { any }, size: (any) -> number, unit: string, action: string, cash: number): Spec
	local lvl = ProgressConfig.clampLevel(level, #list)
	local cur, nxt = list[lvl], list[lvl + 1]
	local spec: Spec = {
		Key = key, Title = cur.Name, Thumb = thumb,
		Effect = (if key == "Basket" then "Carry " .. size(cur) .. " eggs per trip." else "Holds " .. size(cur) .. " eggs in your nest."),
		State = "max",
	}
	if nxt then
		spec.Note = "Next: " .. nxt.Name .. " (" .. size(nxt) .. " " .. unit .. ")."
		spec.State = cashState(nxt.Price, cash)
		spec.Price = nxt.Price
		spec.Verb = "UPGRADE"
		spec.Confirm = "Upgrade to the " .. nxt.Name .. "?"
		spec.Consequence = "From " .. size(cur) .. " to " .. size(nxt) .. " " .. unit .. ". Paid with coins."
		spec.Action = function()
			shop(action, lvl + 1)
		end
	else
		spec.Note = "Best " .. string.lower(title) .. " reached."
	end
	return spec
end

local function storageSpecs(prof, cash: number): { Spec }
	local specs = {}
	local upgrades = {
		levelSpec("Basket", "Basket", iconThumb("basket"), prof.BasketLevel or 1, ProgressConfig.Baskets, function(b)
			return b.Carry
		end, "eggs per trip", "BuyBasket", cash),
		levelSpec("Queue", "Nest", iconThumb("queue"), prof.NestLevel or 1, ProgressConfig.Nests, function(n)
			return n.Queue
		end, "eggs waiting", "BuyNest", cash),
	}
	local curLvl = prof.CapacityTier
	local cur = Config.Capacity[curLvl]
	local nxt = Config.Capacity[curLvl + 1]
	local rubble: Spec = {
		Key = "Rubble", Title = "Candy bag", Thumb = kitThumb("Station_RubbleBin", "rubble"),
		Effect = "Stores " .. (if cur then cur.Size else prof.Capacity) .. " candy before you sell.",
		State = "max",
	}
	if nxt then
		rubble.Note = "Next: " .. nxt.Size .. " candy."
		rubble.State = cashState(nxt.Price, cash)
		rubble.Price = nxt.Price
		rubble.Verb = "UPGRADE"
		rubble.Confirm = "Upgrade candy bag?"
		rubble.Consequence = "Storage grows from " .. (if cur then cur.Size else prof.Capacity) .. " to " .. nxt.Size .. " candy."
		rubble.Action = function()
			shop("BuyCapacity", curLvl + 1) -- the level this screen showed (the server refuses a stale one)
		end
	else
		rubble.Note = "Largest size reached."
	end
	table.insert(specs, rubble)
	for _, u in upgrades do
		table.insert(specs, u)
	end
	return specs
end

local function tierSpecs(prof, cash: number): { Spec }
	local specs = {}
	for i, tid in Config.TierOrder do
		local tier = Config.Tiers[tid]
		local spec: Spec = {
			Key = tid, Title = tier.Name, Thumb = iconThumb("tier" .. i),
			Effect = tier.Rocks .. " eggs \u{b7} candy pays " .. tier.CashPerRubble .. " coins each",
			Note = "Eggs need " .. tier.HP .. " tap" .. (if tier.HP == 1 then "" else "s") .. " to hatch. Pets from " .. tier.GeodeBase .. " coins.",
			State = "owned",
		}
		if not prof.UnlockedTiers[tid] then
			local prevOk = i == 1 or prof.UnlockedTiers[Config.TierOrder[i - 1]]
			local findsOk = prof.Finds >= tier.UnlockFinds
			if not prevOk then
				spec.State = "locked"
				spec.Reason = "Unlock " .. Config.Tiers[Config.TierOrder[i - 1]].Name .. " first."
			elseif not findsOk then
				spec.State = "locked"
				spec.Reason = "Needs " .. tier.UnlockFinds .. " pet finds (you have " .. prof.Finds .. ")."
			else
				spec.State = cashState(tier.UnlockCash, cash)
			end
			spec.Price = tier.UnlockCash
			spec.Verb = "UNLOCK"
			spec.Confirm = "Unlock " .. tier.Name .. "?"
			spec.Consequence = "You can pick " .. tier.Name .. " piles when you start a hunt."
			spec.Action = function()
				shop("UnlockTier", tid)
			end
		else
			spec.Reason = "Pick it when you start a hunt."
		end
		table.insert(specs, spec)
	end
	return specs
end

local function gallerySpecs(prof, cash: number): { Spec }
	local specs = {}
	for lvl, info in Config.Display do
		local spec: Spec = {
			Key = "Disp" .. lvl, Title = info.Slots .. "-slot display", Thumb = kitThumb("Gallery_Cabinet", "display"),
			Effect = "Show up to " .. info.Slots .. " pets in the lobby.", State = "owned",
		}
		if prof.DisplayCapacity == lvl then
			spec.State = "equipped"
		elseif prof.DisplayCapacity > lvl then
			spec.State = "owned"
			spec.Note = "Included in your bigger display."
		elseif prof.DisplayCapacity + 1 == lvl then
			spec.State = cashState(info.Price, cash)
			spec.Price = info.Price
			spec.Verb = "UPGRADE"
			spec.Confirm = "Upgrade your display?"
			spec.Consequence = "Your lobby display grows to " .. info.Slots .. " slots."
			spec.Action = function()
				shop("BuyDisplay", lvl)
			end
		else
			spec.State = "locked"
			spec.Price = info.Price
			spec.Reason = "Buy the smaller display first."
		end
		table.insert(specs, spec)
	end
	return specs
end

local function storeSpecs(prof): { Spec }
	local specs = {}
	local state = prof.Cosmetics or { Owned = {}, Equipped = {} }
	for _, e in Cosmetics.list() do
		local spec: Spec = {
			Key = e.Id, Title = e.Name, Thumb = iconThumb("gem"), Effect = Config.CosmeticKinds[e.Kind] .. ". " .. e.Desc,
			Note = "Cosmetic only, never power.", State = "robux", PriceText = nil, Verb = "BUY",
		}
		if Cosmetics.owned(state, e.Id) then
			local on = state.Equipped[e.Kind] == e.Id
			spec.State, spec.Verb = "equip", if on then "REMOVE" else "EQUIP"
			spec.Action = function()
				if on then
					store("Unequip", e.Kind)
				else
					store("Equip", e.Id)
				end
			end
		else
			spec.PriceText = robuxPrice(e)
			spec.Action = function()
				store("Buy", e.Id) -- Roblox shows its own purchase prompt with the real price
			end
		end
		table.insert(specs, spec)
	end
	return specs
end

local function specsFor(prof): { Spec }
	local cash = prof.Cash
	if tab == "Gear" then
		return toolSpecs(prof, cash)
	elseif tab == "Nests" then
		return machineSpecs(prof, cash)
	elseif tab == "Storage" then
		return storageSpecs(prof, cash)
	elseif tab == "Tiers" then
		return tierSpecs(prof, cash)
	elseif tab == "Store" then
		return storeSpecs(prof)
	end
	return gallerySpecs(prof, cash)
end

-- Row status line and colour (what the row says under its name).
local function rowStatus(s: Spec): (string, Color3)
	if pending and pending.Key == s.Key then
		return "Purchasing\u{2026}", TC.Muted
	elseif s.State == "equipped" then
		return if tab == "Nests" then "Installed" elseif tab == "Gallery" then "Current" else "Equipped", if Theme.PetStyle then Theme.Pet.Blue else TC.Gold
	elseif s.State == "equip" then
		return "Owned", TC.Green
	elseif s.State == "owned" then
		return if tab == "Tiers" then "Unlocked" else "Owned", TC.Green
	elseif s.State == "fixed" then
		return "Holds " .. tostring(s.Capacity or "") .. " \u{b7} standard", TC.Muted
	elseif s.State == "max" then
		return "Max size", TC.Gold
	elseif s.State == "locked" then
		return "Locked", TC.Faint
	elseif s.State == "robux" then
		return s.PriceText or "", TC.Text
	elseif s.Price == 0 then
		return "Free", TC.Cash
	elseif s.Price then
		return UI.money(s.Price), if s.State == "poor" then TC.Faint else TC.Cash
	end
	return "", TC.Muted
end

-- Purchase flow: confirmation (real item, price, consequence), then the request; the item shows PURCHASING
-- until the server's profile update (or a refusal) arrives.
local function act(s: Spec)
	if not s.Action or pending then
		return
	end
	local function send()
		pending = { Key = s.Key, At = os.clock() }
		s.Action()
		render()
		local mine = pending
		task.delay(PENDING_SECONDS, function()
			if pending == mine then
				pending = nil
				render()
			end
		end)
	end
	if s.State == "buy" and s.Price and s.Price > 0 and s.Confirm then
		UI.confirm({
			Name = "ConfirmPurchase",
			Title = s.Confirm,
			Message = s.Title .. ". " .. (s.Consequence or s.Effect),
			Picture = function(c)
				s.Thumb(c, 54)
			end,
			Price = s.Price,
			Confirm = "CONFIRM",
			OnConfirm = send,
		})
	else
		send()
	end
end

-- Renderer -------------------------------------------------------------------------------------

local function detail(parent: Instance, s: Spec)
	local short = UI.isShort()
	local portrait = UI.isPortrait()
	-- a very short landscape phone (about 678 x 310): the pane is barely 120 studs tall, so no picture and one line of text
	local tight = not portrait and UI.Logical.Y < 395
	local f = UI.card(parent, "inset", { Name = "Detail", Size = UDim2.fromScale(1, 1) })
	UI.pad(f, 8, 6)
	local title = UI.text(f, s.Title, { Name = "Title", Font = UI.Head, TextSize = if tight then T.Head - 2 else T.Head + 2, Size = UDim2.new(1, 0, 0, if tight then 22 else 28), TextXAlignment = Enum.TextXAlignment.Center })
	title.TextWrapped = false
	local footH = if tight then 34 else 46
	local textH = if tight then 30 elseif short then 64 else 80 -- room for a two-line description at body size (#237: it shrank to fit)
	local pic = UI.frame(f, { Name = "Picture", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -(30 + textH + footH + 8)), Visible = not tight })
	local picSize = if portrait then 64 elseif short then 60 else 84
	if s.State == "fixed" and s.Capacity then
		-- capacity block: icon beside the size, the area is filled on purpose (no empty preview)
		local row = UI.frame(pic, { Name = "Capacity", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(220, 64) })
		s.Thumb(UI.frame(row, { BackgroundTransparency = 1, Size = UDim2.fromOffset(64, 64) }), 56)
		local n = UI.text(row, tostring(s.Capacity), { Name = "Size", Font = UI.Head, TextSize = 40, TextColor3 = TC.Count, Outline = "Strong", Position = UDim2.fromOffset(72, 0), Size = UDim2.fromOffset(148, 40) })
		n.TextWrapped = false
		UI.text(row, s.Unit or "", { Name = "Unit", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(72, 40), Size = UDim2.fromOffset(148, 22) })
	elseif s.Preview then
		-- gear models fill the whole picture area (a fixed 84 box left the model at about a sixth of the frame)
		local vp = ItemView.make(pic, s.Preview, { Name = "Model", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) }, picSize)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = vp
	else
		s.Thumb(pic, picSize)
	end
	local about = s.Effect
	local note = s.Reason or s.Note
	if tight then
		about, note = s.Reason or s.Effect, nil -- one line: why it is locked, else what it does
	end
	-- 10 px side padding: the wrapped lines never touch the card's edges (Studio phone window)
	local txt = UI.frame(f, { Name = "About", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -(footH + 4)), Size = UDim2.new(1, -20, 0, textH) })
	-- the description takes the whole block when there is no note, else the larger share (two body-size lines)
	local effH = if note then math.floor(textH * 0.6) else textH
	local eff = UI.text(txt, about, { Name = "Effect", Font = UI.Bold, TextSize = T.Body + 1, Outline = "Normal", Size = UDim2.new(1, 0, 0, effH), TextXAlignment = Enum.TextXAlignment.Center })
	eff.TextWrapped = true
	UI.fit(eff, T.Body + 1, T.Small)
	local noteLabel: TextLabel? = nil
	if note then
		local nl = UI.text(txt, note, { Name = "Note", Font = UI.Bold, TextSize = T.Body, TextColor3 = if s.State == "locked" then TC.Count else TC.Muted, Outline = "Light", Position = UDim2.fromOffset(0, effH), Size = UDim2.new(1, 0, 0, textH - effH), TextXAlignment = Enum.TextXAlignment.Center })
		nl.TextWrapped = true
		UI.fit(nl, T.Body, T.Small)
		noteLabel = nl
	end
	local foot = UI.frame(f, { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, footH) })
	local isPending = pending ~= nil and pending.Key == s.Key
	-- information only: plain text, nothing shaped like a button
	if s.State == "fixed" then
		UI.icon(foot, "info", 22, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0) })
		UI.text(foot, "Standard size \u{b7} nothing to buy", { Name = "InfoOnly", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, Outline = "Light", Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
		return
	end
	-- status states: no button repeating them
	if not isPending and (s.State == "equipped" or s.State == "owned" or s.State == "fixed" or s.State == "max") then
		local word = if s.State == "equipped" then (if tab == "Nests" then "INSTALLED" elseif tab == "Gallery" then "CURRENT" else "EQUIPPED")
			elseif s.State == "owned" then (if tab == "Tiers" then "UNLOCKED" else "OWNED")
			elseif s.State == "max" then "MAX SIZE"
			else "STANDARD SIZE"
		-- pet style: the equipped badge is a blue pill like the shop's OWNED pill (the muddy gold belonged to the old look)
		local pet = Theme.PetStyle and s.State == "equipped"
		local badge = UI.frame(foot, { Name = "Status", Size = UDim2.fromScale(1, 1), BackgroundColor3 = if pet then Theme.Pet.Blue elseif s.State == "equipped" then TC.GoldDim else TC.Inset })
		UI.corner(badge, if pet then 999 else T.Radius)
		UI.stroke(badge, if pet then Theme.Pet.BlueEdge elseif s.State == "equipped" then TC.Gold else TC.InsetEdge, if pet then 3 else 2)
		if pet then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(Theme.Pet.BlueTop, Theme.Pet.Blue)
			g.Rotation = 90
			g.Parent = badge
		end
		if s.State == "equipped" or s.State == "owned" then
			UI.icon(badge, "check", 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
		end
		UI.text(badge, word, { Name = "Word", Font = UI.Head, TextSize = T.Head, TextColor3 = if pet then Color3.new(1, 1, 1) elseif s.State == "equipped" then TC.Gold else TC.Text, Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(36, 0), TextXAlignment = Enum.TextXAlignment.Center })
		return
	end
	local text, style, enabled = "", "gold", true
	if isPending then
		text, enabled = "PURCHASING\u{2026}", false
	elseif s.State == "locked" then
		text, enabled = "LOCKED", false
	elseif s.State == "poor" then
		local have = if State.Profile then State.Profile.Cash else 0
		text, enabled = "NEED " .. UI.num(math.max(1, (s.Price or 0) - have)) .. " MORE", false
	elseif s.State == "buy" then
		text = (s.Verb or "BUY") .. (if s.Price and s.Price > 0 then " " .. UI.money(s.Price) elseif s.Price == 0 then " (FREE)" else "")
	elseif s.State == "robux" then
		text = "BUY " .. (s.PriceText or "")
	else
		text = s.Verb or "EQUIP"
	end
	local poor = s.State == "poor" and not isPending
	if poor then
		style = "red" -- NEED N MORE: white on red reads at a glance (grey on grey did not)
	end
	local b = UI.button(foot, text, style, function()
		if poor then
			UI.flashCash() -- a tap makes the coin counter blink red: this is what is missing (nothing is sent)
			return
		end
		act(s)
	end, { Name = "Action", Size = UDim2.fromScale(1, 1), TextSize = T.Head })
	if not enabled and not poor then
		UI.setEnabled(b, false)
	end
	if s.State == "buy" and s.Price and s.Price > 0 and not isPending then
		-- coin picture beside the price
		HudArt.image(b, "Coin", 26, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 3 })
		Juice.pulse(b, nil, T.Radius) -- an upgrade you can afford breathes a soft glow
	end
	if s.State == "locked" then
		-- a tap on LOCKED shakes the button and the reason under the picture (nothing is sent)
		b.Activated:Connect(function()
			Juice.nope(b)
			if noteLabel then
				Juice.nope(noteLabel)
			end
		end)
	end
end

function render()
	if not open or not body then
		return
	end
	local b = body :: Frame
	local old = b:FindFirstChild("List", true)
	if old and old:IsA("ScrollingFrame") then
		listScroll = old.CanvasPosition
	end
	for _, c in b:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	local prof = State.Profile
	if not prof then
		UI.loadingState(b, "Loading upgrades", { Position = UDim2.fromOffset(0, 60) })
		return
	end
	UI.modalCash(prof.Cash)
	-- tabs: only categories that exist
	local names = {}
	for _, n in TABS do
		if n == "Nests" and not Config.MachinesEnabled then
			continue
		end
		if n == "Store" and not (Cosmetics.anyVisible() and prof.OnboardDone) then
			continue
		end
		if n == "Robux" and UI.isPortrait() then
			continue -- portrait: no room for one more tab; an EGG SHOP button ends the list instead
		end
		table.insert(names, n)
	end
	if not table.find(names, tab) or tab == "Robux" then
		tab = "Gear"
	end
	local items = {}
	for _, n in names do
		local it: { string } = { n, n }
		if n == "Robux" and UI.Logical.X >= 900 then -- narrow phones: the word alone (an icon pushed it out past the tab edge)
			table.insert(it, HudArt.Slots.Egg.Image) -- the EGG SHOP's egg (the coin read as one more coin upgrade)
		end
		table.insert(items, it)
	end
	local tabRow = UI.tabs(b, items, tab, function(name)
		if name == "Robux" then
			PetShop.open() -- the Robux shop is its own menu (PetShop)
			return
		end
		tab = name
		listScroll = Vector2.zero
		render()
	end)
	-- the Robux tab opens another shop: green (gold is the selected tab, so a gold Robux tab read as a second
	-- selected one, Studio #184), so it never reads as one more free tab
	local rt = tabRow:FindFirstChild("Tab_Robux", true)
	if rt and rt:IsA("GuiButton") then
		UI.setStyle(rt, "green")
	end
	-- seven tabs on a phone-size window: the shared bar's floor (body size) still cut "Robux" to "Robu", so every
	-- tab word may shrink to the text floor instead; re-applied after the bar's own re-fit (same signal, later)
	local function wholeWords()
		if not tabRow.Parent then
			return
		end
		for _, tb in tabRow:GetDescendants() do
			if tb:IsA("TextLabel") and tb.Name == "Label" and tb.Parent and string.sub(tb.Parent.Name, 1, 4) == "Tab_" then
				local fc = tb:FindFirstChild("Fit") :: UITextSizeConstraint?
				tb.TextWrapped = false
				UI.fit(tb, if fc then fc.MaxTextSize else T.Body + 2, T.MinText)
				tb.TextWrapped = false
			end
		end
	end
	task.defer(function()
		task.defer(wholeWords)
	end)
	tabRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			task.defer(wholeWords)
		end)
	end)

	local specs = specsFor(prof)
	local sel: Spec? = nil
	for _, s in specs do
		if s.Key == selected[tab] then
			sel = s
		end
	end
	if not sel then
		for _, s in specs do
			if s.State == "equipped" then
				sel = s
				break
			end
		end
		sel = sel or specs[1]
	end

	local top = T.Gap + T.Tab
	local content = UI.frame(b, { Name = "Content", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1 })
	local portrait = UI.isPortrait()
	local listHost = UI.frame(content, { Name = "ListHost", BackgroundTransparency = 1, Size = if portrait then UDim2.new(1, 0, 0.5, -4) else UDim2.new(0.52, -4, 1, 0) })
	local pane = UI.frame(content, {
		Name = "Pane", BackgroundTransparency = 1,
		Position = if portrait then UDim2.new(0, 0, 0.5, 4) else UDim2.new(0.52, 4, 0, 0),
		Size = if portrait then UDim2.new(1, 0, 0.5, -4) else UDim2.new(0.48, -4, 1, 0),
	})
	local list = UI.scroller(listHost, { Name = "List", Size = UDim2.new(1, 0, 1, -26) })
	UI.list(list, Enum.FillDirection.Vertical, 6)
	UI.pad(list, 2, 2)
	-- a longer list than fits (Tiers): a "more below" tag until its end is in view
	local more = UI.text(listHost, "\u{25BC} more", {
		Name = "MoreHint", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(84, 22), TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.15, BackgroundColor3 = TC.PanelEdge, ZIndex = list.ZIndex + 5,
	})
	UI.corner(more, 10)
	local function hint()
		more.Visible = list.CanvasPosition.Y + list.AbsoluteWindowSize.Y < list.AbsoluteCanvasSize.Y - 6
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(hint)
	list:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(hint)
	list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(hint)
	task.defer(hint)
	-- rows at least 48 real px tall (50 logical drew about 40 on the Studio phone window)
	local rowH = math.max(if UI.isShort() then 50 else 58, realPx(48))
	if #specs <= 4 and not portrait then
		-- a short list (3 tools) left most of the column empty: taller rows with bigger pictures fill it instead
		rowH = math.max(rowH, if UI.isShort() then 66 else 92)
	end
	local tagH = realPx(20) -- the Equipped / Owned tag
	local arrowH = realPx(22) -- the picked row's arrow
	for i, s in specs do
		local status, color = rowStatus(s)
		local badge: string? = nil
		if s.State == "buy" or s.State == "equip" then
			badge = if s.State == "buy" then (s.Verb or "BUY") else (s.Verb or "EQUIP")
		end
		local row = UI.catalogRow(list, i, {
			Name = "Row_" .. s.Key, Title = s.Title, Sub = status, SubColor = color, Selected = sel ~= nil and s.Key == sel.Key,
			SubPill = s.State == "equipped" or s.State == "equip" or s.State == "owned" or s.State == "max",
			Height = rowH,
			Thumb = function(c)
				s.Thumb(c, rowH - 14)
			end,
			Badge = if pending and pending.Key == s.Key then nil else badge,
			OnBadge = function()
				selected[tab] = s.Key
				act(s)
			end,
			OnSelect = function()
				selected[tab] = s.Key
				-- in the lobby the Upgrades counter's pedestal shows the picked tool or machine (presentation only)
				if s.Preview and not State.Match then
					UpgradePreview.select(s.Preview)
				end
				render()
			end,
		})
		-- the shared row's small parts, sized for the phone window: the price line at body size, the Equipped /
		-- Owned tag at least 20 real px tall, the picked arrow at least 22 (they were tiny in Studio)
		local sub = row:FindFirstChild("Sub") :: TextLabel?
		if sub then
			sub.TextWrapped = false
			UI.fit(sub, T.Body, T.Small)
		end
		local pill = row:FindFirstChild("SubPill") :: Frame?
		if pill and pill.Size.Y.Offset < tagH then
			local word = pill:FindFirstChild("Sub") :: TextLabel?
			pill.Size = UDim2.fromOffset(pill.Size.X.Offset + 4, tagH)
			pill.Position = UDim2.new(0, pill.Position.X.Offset, 0, math.max(rowH - tagH - 4, math.floor(rowH * 0.5) - 2))
			if word then
				UI.fit(word, T.Body, T.Small)
			end
		end
		local arrow = row:FindFirstChild("PickedArrow") :: TextLabel?
		if arrow then
			arrow.Size = UDim2.fromOffset(arrowH + 6, arrowH + 6)
			UI.fit(arrow, arrowH, T.Body)
		end
	end
	if UI.isPortrait() then
		local eggShop = UI.button(list, "EGG SHOP (ROBUX)", "gray", function()
			PetShop.open()
		end, { Name = "RobuxShop", LayoutOrder = #specs + 1, Size = UDim2.new(1, -6, 0, T.Touch), TextSize = T.Body })
		-- the egg left of the words (centred text keeps clear of it on a full-width row)
		HudArt.image(eggShop, "Egg", 30, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
	end
	local keep = listScroll
	if keep == Vector2.zero and sel then
		-- first look at this tab: start with the picked (equipped) item in view
		for i, s in specs do
			if s.Key == sel.Key and i > 2 then
				keep = Vector2.new(0, (i - 2) * (rowH + 6))
				break
			end
		end
	end
	task.defer(function()
		if list.Parent then
			list.CanvasPosition = keep
		end
	end)
	if sel then
		detail(pane, sel)
	end
	skinBody(b)
end

local function modalSize(): Vector2
	if UI.isPortrait() then
		return Vector2.new(480, 680)
	elseif UI.Logical.Y >= 600 then
		return Vector2.new(720, 440)
	end
	return Vector2.new(660, 372)
end

function ShopPanel.open(openTab: string?)
	if type(openTab) == "string" and table.find(TABS, openTab) then
		tab = openTab
	end
	listScroll = Vector2.zero
	local panel, b = UI.modal("Shop", "UPGRADES", modalSize(), { Fixed = true, Cash = true })
	PanelSkin.dress(panel, "Hammer", "UPGRADES")
	panelRef = panel
	skinPanel(panel)
	body = b
	open = true
	local conn, noticeConn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "Shop" then
			open = false
			body = nil
			panelRef = nil
			if not State.Match then
				UpgradePreview.select(nil) -- the pedestal goes back to the equipped tool
			end
			conn:Disconnect()
			noticeConn:Disconnect()
		end
	end)
	-- a refusal (not enough cash, requirement) ends the pending state at once
	noticeConn = UI.Notice.Event:Connect(function(_, kind)
		if kind == "warn" and pending then
			pending = nil
			render()
		end
	end)
	render()
end

function ShopPanel.start()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			pending = nil -- the authoritative result arrived
			render()
		end
	end)
end

local _ = panelRef
return ShopPanel
