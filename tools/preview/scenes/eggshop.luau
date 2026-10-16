-- eggshop: the EGG SHOP (Robux) panel, opened through UPGRADES -> Robux tab.
--   --set tab=Eggs|Potions|Passes   --set pick=<row key> (e.g. MythicEgg, LuckPotion, PetStorage)
--   --set ids=on      fake product / pass ids (PREVIEW ONLY) so prices and BUY buttons show ("R$ 49" from the mock)
--   --set restricted=on   PolicyService says paid random items are not allowed (eggs hidden)
--   --set storm=on    a luck storm is running; --set potion=on a potion is running
--   --set shrine=on   the EGG SHRINE (eggs for coins) instead of the Robux shop; --set pick works there too
--   --set show=on     no panel: a hatch-stand show (a stand part is placed in front of the player for the preview)
local C = lib("ctr")
local RobuxConfig = preview.shared("RobuxConfig")
if preview.args.ids == "on" then
	local n = 9000
	for _, e in ipairs(RobuxConfig.Eggs) do
		for _, c in ipairs(RobuxConfig.EggCounts) do
			n += 1
			e.Products[c] = n
		end
	end
	RobuxConfig.Potion.ProductId = 9100
	for _, key in ipairs(RobuxConfig.PassOrder) do
		n += 1
		RobuxConfig.Passes[key].PassId = n
	end
end
local s = C.boot({
	profile = function(data)
		data.Cash = 2600
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.UnlockedTiers.Quarry = true
		if preview.args.potion == "on" then
			data.Robux.LuckUntil = os.time() + 600
		end
		if preview.args.ids == "on" then
			data.Robux.Passes.DoubleCoins = true
		end
	end,
})
local me = s.me
preview.advance(0.5)
if preview.args.restricted == "on" then
	me:SetAttribute("PaidRandomRestricted", true)
end
if preview.args.storm == "on" then
	preview.server("RobuxService").startStorm(15 * 60)
end
C.settle(1)
if preview.args.show == "on" then
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local at = (root and root.CFrame or CFrame.new()) * CFrame.new(0, -2.5, -10)
	local stand = Instance.new("Part")
	stand.Name = "PreviewHatchStand"
	stand.Anchored = true
	stand.Size = Vector3.new(6, 1, 6)
	stand.CFrame = at
	stand:SetAttribute("HatchStand", true)
	local a = Instance.new("Attachment")
	a.Name = "HatchPoint"
	a.Position = Vector3.new(0, 0.5, 0)
	a.Parent = stand
	stand.Parent = workspace
	local pet = preview.shared("GeodeGen").roll(Random.new(4), "Quarry", "show", "k", os.time(), true, 0)
	pet.Rarity = "Legendary"
	preview.fireClient("HatchShow", { Buyer = "Builder", BuyerId = 1, Egg = "Mythic Egg", Count = 10, Pet = preview.shared("GeodeGen").public(pet) })
	preview.advance(tonumber(preview.args.at) or 2.6)
	local from = if root then (root.Position - stand.Position) * Vector3.new(1, 0, 1) else Vector3.new(0, 0, 1)
	C.cameraAt(stand.Position + Vector3.new(0, 3, 0), from.Unit * 12 + Vector3.new(0, 3, 0), 60)
	return
end
if preview.args.shrine == "on" then
	-- the EGG SHRINE (hatch stand prompt): eggs for coins
	preview.require(preview.clientFolder().ui.RobuxShopPanel).openCoins()
	C.settle(0.5)
	if preview.args.pick then
		local row = preview.findGui(function(obj)
			return obj.Name == "Row_" .. preview.args.pick
		end)[1]
		if row and row:IsA("GuiButton") then
			preview.click(row)
		end
		C.settle(0.5)
	end
	C.followCamera()
	return
end
C.tap("^SHOP$")
preview.advance(0.3)
C.tap(if C.findText("^ROBUX$", "GuiButton") then "^ROBUX$" else "^EGG SHOP")
C.settle(0.5)
local tab = preview.args.tab
if tab then
	C.tap("^" .. string.upper(tab) .. "$")
	C.settle(0.5)
end
if preview.args.pick then
	local hits = preview.findGui(function(obj)
		return obj.Name == "Row_" .. preview.args.pick
	end)
	local row = hits[1]
	if row and row:IsA("GuiButton") then
		preview.click(row)
	else
		preview.warn("no row " .. preview.args.pick)
	end
	C.settle(0.5)
end
C.followCamera()
