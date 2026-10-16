-- shop: the SHOP panel (HUD button) with some cash: --set tab=Tools|Storage|Tiers|Gallery,
-- --set cash=N, --set mock=N (N made-up Tools entries, development only).
local C = lib("ctr")
-- --set store=on gives the cosmetics fake product ids (PREVIEW ONLY) so the Store tab shows.
if preview.args.store == "on" then
	local cfg = preview.shared("Config")
	local n = 900
	for _, id in ipairs(cfg.CosmeticOrder) do
		n += 1
		cfg.Products[id].ProductId = n
	end
end
C.boot({
	profile = function(data)
		data.Cash = tonumber(preview.args.cash) or 2600
		data.TutorialStep = 1
		data.EquipmentOwned.SteelHammer = true
		data.EquippedHandheld = "SteelHammer"
		data.RubbleByTier = { Gravel = 22 }
		data.Onboard.Skipped = true
		if preview.args.owned then
			-- --set owned=AutoCracker: machine owned and installed (Machines tab shows INSTALLED)
			data.EquipmentOwned[preview.args.owned] = true
			data.InstalledMachine = preview.args.owned
		end
		if preview.args.store == "on" then
			data.Cosmetics.Owned.SkinCopper = true
			data.Cosmetics.Equipped.ToolSkin = "SkinCopper"
		end
	end,
})
if preview.args.mock then
	-- development-only mock catalog (3 / 12 / 30 entries) for the renderer; never granted
	game:GetService("ReplicatedStorage"):SetAttribute("DevShopMock", tonumber(preview.args.mock))
end
C.settle(1)
C.tap("^SHOP$")
preview.advance(0.3)
local tab = preview.args.tab
if tab then
	C.tap("^" .. string.upper(tab) .. "$")
end
C.settle(1)
if preview.args.pick then
	-- --set pick=Basket: select a catalog row by its key (Row_<key>; the detail view shows that entry)
	local hits = preview.findGui(function(obj)
		return obj.Name == "Row_" .. preview.args.pick
	end)
	local row = hits[1]
	local btn = if row and row:IsA("GuiButton") then row else (row and row:FindFirstChildWhichIsA("GuiButton", true))
	if btn then
		preview.click(btn)
	else
		preview.warn("no catalog row " .. preview.args.pick)
	end
	C.settle(0.5)
end
C.followCamera()
if preview.args.confirm then
	-- --set confirm=1: tap the first BUY / UPGRADE / UNLOCK badge: the purchase confirmation (item, price, CONFIRM)
	if not C.tap("^BUY$") then
		if not C.tap("^UPGRADE$") then
			C.tap("^UNLOCK$")
		end
	end
	preview.advance(0.4)
	if C.findText("^CONFIRM$", "GuiButton") and C.findText("^CANCEL$", "GuiButton") then
		print("CONFIRM PASS (confirmation shown, nothing sent yet)")
	else
		print("[FAIL] CONFIRM dialog missing")
	end
end
