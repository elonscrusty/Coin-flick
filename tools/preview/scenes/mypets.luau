-- mypets: the MY PETS screen (client/ui/MyPetsPanel, carter's low-poly reference) with made-up pets in the real
-- profile. --set count=N pets (default 9, 0 = empty), --set swap=1 the full-team slot pick for the 5th pet,
-- --set search=TEXT types in the search box, --set art=1 shows carter's frame pictures early with preview-only ids
-- (art/artmap.json 1016000001..15, never used in the game).
local C = lib("ctr")
local count = tonumber(preview.args.count) or 9
local specs
C.boot({
	profile = function(data)
		data.Cash = 5300
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version
		specs = C.fakeSpecimens(count)
		data.InventoryGeodes = specs
		for i, g in ipairs(specs) do
			g.TowerXP = (count - i) * 140
			if i == 4 then
				g.Favorite = true
			end
		end
		data.EquippedPets = {}
		for i = 1, math.min(3, #specs) do
			table.insert(data.EquippedPets, specs[i].Id)
		end
		if specs[2] then
			data.DisplayAssignments = { specs[2].Id }
		end
	end,
})
C.settle(1.5)
if preview.args.art then
	local Art = C.shared("MyPetsArt")
	for i, n in Art.Order do
		Art.Pieces[n].Id = 1016000000 + i
	end
end
local Panel = preview.require(preview.clientFolder().ui.MyPetsPanel)
Panel.Debug = preview.args.debug ~= nil
if preview.args.swap and specs and specs[5] then
	Panel.openSwap(specs[5].Id)
else
	Panel.open()
end
C.settle(1)
if preview.args.search then
	local box = preview.findGui(function(o)
		return o:IsA("TextBox") and o.Name == "Box"
	end)[1]
	if box then
		box.Text = preview.args.search
		C.settle(0.5)
	end
end
print("MYPETS open=" .. tostring(Panel.isOpen()))
