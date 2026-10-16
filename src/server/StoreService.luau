--!strict
-- Cosmetic Robux store (brief section 15: cosmetics only, never power). Owned cosmetics live in
-- the profile (Cosmetics.Owned); equipping only changes colours (tool skin, gallery alcove theme).
--
-- Purchases: the client names a cosmetic id, the server checks it is a visible catalogue entry
-- (ProductId > 0) the player does not own yet and opens the Roblox purchase prompt. Nothing is
-- granted by the prompt: the grant happens in MarketplaceService.ProcessReceipt, keyed by the
-- receipt's PurchaseId (stored in the profile, so a retried or replayed receipt never grants
-- twice) and the receipt is only answered PurchaseGranted after the profile is saved. With
-- every ProductId at 0 nothing here is reachable and the game works without the store.
-- NOT tested against real purchases (needs product ids from the owner and a Studio/live test).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)
local Profiles = require(script.Parent.Profiles)
local Economy = require(script.Parent.EconomyService)
local Gallery = require(script.Parent.GalleryService)

local Store = {}

local RECEIPTS_KEPT = 300

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end

-- Called by Roblox when a Developer Product purchase completes (possibly several times for the
-- same receipt, possibly after a rejoin). Pure of side effects when already granted.
-- Other services that sell developer products (tower revive, Robux eggs) register a route here. A route returns a
-- decision when the product is its own, or nil to pass. Only one ProcessReceipt callback can exist per server.
type Receipt = { PlayerId: number, PurchaseId: string, ProductId: number }
local routes: { (Receipt) -> Enum.ProductPurchaseDecision? } = {}
function Store.addReceiptRoute(fn: (Receipt) -> Enum.ProductPurchaseDecision?)
	table.insert(routes, fn)
end

function Store.processReceipt(info: Receipt): Enum.ProductPurchaseDecision
	if info.ProductId > 0 then
		for _, route in routes do
			local decision = route(info)
			if decision ~= nil then
				return decision
			end
		end
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- granted when they rejoin
	end
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried after the player is back with a live profile
	end
	local entry = Cosmetics.byProductId(info.ProductId)
	if not entry then
		warn("[Store] receipt for unknown product", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = tostring(info.PurchaseId)
	local state = data.Cosmetics
	local fresh = not state.Receipts[key]
	if fresh then
		state.Owned[entry.Id] = true
		Cosmetics.rememberReceipt(state, key, RECEIPTS_KEPT)
		Profiles.changed(player, true)
	end
	-- Granted only once it is saved; a failed save is answered "not yet" and retried by Roblox.
	if not Profiles.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if fresh then
		toast(player, "Unlocked " .. entry.Name .. "! Equip it in the Store tab.", "ok")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function handle(player: Player, action: any, arg: any)
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) or type(action) ~= "string" then
		return
	end
	local state = data.Cosmetics
	if action == "Buy" then
		local entry = Cosmetics.get(arg)
		if not entry or not Cosmetics.visible(entry) then
			return
		end
		if Cosmetics.owned(state, entry.Id) then
			toast(player, "You already own " .. entry.Name .. ".", "info")
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, entry.ProductId)
		end)
	elseif action == "Equip" then
		local entry = Cosmetics.get(arg)
		if not entry or not Cosmetics.visible(entry) or not Cosmetics.owned(state, entry.Id) then
			return
		end
		if state.Equipped[entry.Kind] == entry.Id then
			return
		end
		state.Equipped[entry.Kind] = entry.Id
		Profiles.changed(player, true)
		if entry.Kind == "ToolSkin" then
			Economy.attachTool(player)
		else
			Gallery.render(player)
		end
	elseif action == "Unequip" then
		local kind = if type(arg) == "string" then arg else ""
		if (kind ~= "ToolSkin" and kind ~= "GalleryTheme") or state.Equipped[kind] == nil then
			return
		end
		state.Equipped[kind] = nil
		Profiles.changed(player, true)
		if kind == "ToolSkin" then
			Economy.attachTool(player)
		else
			Gallery.render(player)
		end
	end
end

function Store.start()
	local last: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
	Net.event("StoreAction").OnServerEvent:Connect(function(player, action, arg)
		local t = os.clock()
		if last[player] and t - last[player] < 0.4 then
			return
		end
		last[player] = t
		handle(player, action, arg)
	end)
	MarketplaceService.ProcessReceipt = function(info)
		local ok, result = pcall(Store.processReceipt, info)
		if ok then
			return result
		end
		warn("[Store] receipt failed", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return Store
