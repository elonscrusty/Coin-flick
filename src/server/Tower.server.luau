--!strict
-- Pet Tower boot (its own Script so Main.server.luau stays untouched). See TowerService.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TowerConfig = require(Shared.TowerConfig)
local TowerService = require(script.Parent.TowerService)

TowerService.start()
-- StoreService owns MarketplaceService.ProcessReceipt; the revive product is routed here.
require(script.Parent.StoreService).addReceiptRoute(function(info)
	if info.ProductId > 0 and info.ProductId == TowerConfig.Revive.ProductId then
		return TowerService.processReceipt(info)
	end
	return nil
end)
