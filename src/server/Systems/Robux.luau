--!strict
-- The Robux shop: 2x cash pass, auto-flip pass, coin skin passes, and extra
-- helper slots (a developer product). No random boxes, ever.
-- Ids come from carter (Config.Products / Config.Skins). Id 0 = SOON: nothing
-- can be bought. Prices are set on the Roblox website, never here.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.Tables)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Robux = {}

local limiter = RateLimiter.new(2, 4, os.clock)

-- Every game pass: key -> pass id. Skins use their skin id as the key.
local function passIds(): { [string]: number }
	local ids: { [string]: number } = {
		doubleCash = Config.Products.DoubleCashPassId,
		autoFlip = Config.Products.AutoFlipPassId,
	}
	for _, skin in Config.Skins do
		ids[skin.id] = skin.passId
	end
	return ids
end

local function notify(player: Player, kind: string, text: string)
	local notice: Types.Notice = { kind = kind, text = text }
	Net.event("Notice"):FireClient(player, notice)
end

local function checkPasses(player: Player)
	for key, id in passIds() do
		if id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok then
				Boosts.setPass(player, key, owns == true)
			end
		end
	end
	Tables.refresh(player) -- skins
	PlayerData.changed(player)
end

local function onBuy(player: Player, item: unknown)
	if not limiter:allow(player) or typeof(item) ~= "string" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if item == "helperSlot" then
		local id = Config.Products.ExtraHelperSlotProductId
		if id <= 0 then
			notify(player, "soon", "Coming soon!")
		elseif profile.helperSlots >= Config.MAX_EXTRA_HELPER_SLOTS then
			notify(player, "soon", "You have every helper slot!")
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
		return
	end
	local id = passIds()[item]
	if not id then
		return
	end
	if id <= 0 then
		notify(player, "soon", "Coming soon!")
	elseif Boosts.owns(player, item) then
		notify(player, "soon", "You already have this!")
	else
		MarketplaceService:PromptGamePassPurchase(player, id)
	end
end

local function onPassBought(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for key, id in passIds() do
		if id > 0 and id == passId then
			Boosts.setPass(player, key, true)
			local profile = PlayerData.get(player)
			if profile and profile.skin == "" and key ~= "doubleCash" and key ~= "autoFlip" then
				profile.skin = key -- show a new skin straight away
			end
			Tables.refresh(player)
			PlayerData.changed(player)
			notify(player, "bought", "Thank you! Your new power is on!")
		end
	end
end

-- Roblox calls this for developer products, and retries until we say granted.
-- We only say granted once the purchase is safely saved.
local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = player and PlayerData.get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- they'll get it next time they join
	end
	local id = Config.Products.ExtraHelperSlotProductId
	if id <= 0 or info.ProductId ~= id then
		warn(`[Robux] unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = GameLogic.grantProduct(profile, tostring(info.PurchaseId), "helperSlot")
	if result == "unknown" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result == "maxed" then
		warn(`[Robux] {player.UserId} bought a helper slot with every slot full ({info.PurchaseId})`)
	end
	if not PlayerData.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries; the receipt stops a double grant
	end
	if result == "granted" then
		PlayerData.changed(player)
		notify(player, "bought", "Thank you! New helper slot!")
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onChooseSkin(player: Player, skinId: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	local owned = typeof(skinId) == "string" and Boosts.owns(player, skinId)
	if profile and GameLogic.chooseSkin(profile, skinId, owned) then
		Tables.refresh(player)
		PlayerData.changed(player)
	end
end

function Robux.init()
	Net.event("BuyRobux").OnServerEvent:Connect(onBuy)
	Net.event("ChooseSkin").OnServerEvent:Connect(onChooseSkin)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassBought)
	MarketplaceService.ProcessReceipt = processReceipt
	PlayerData.onLoaded(function(player: Player)
		checkPasses(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		limiter:remove(player)
	end)
end

return Robux
