-- Pet Tower team picker (TowerPanel.openPicker): each pet row with its type and grade pills and the Power / Health
-- stat tiles (1-5 segments, PetStatView). --set count=N pets (default 6).
local C = lib("ctr")

local count = tonumber(preview.args.count) or 6
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		local specs = C.fakeSpecimens(count)
		data.InventoryGeodes = specs
		data.TowerXP = {}
		for i, g in ipairs(specs) do
			data.TowerXP[tostring(g.Id)] = (i - 1) * 400 -- a spread of levels, so the stars differ
		end
	end,
})
C.settle(1)
local net = game:GetService("ReplicatedStorage"):FindFirstChild("TowerNet")
if net then
	C.try("open tower picker", function()
		(net :: any).TowerAction:FireServer({ Op = "Open" })
	end)
else
	print("TOWERPICK FAIL no TowerNet (Tower.server not started)")
end
C.settle(2)
local rows = preview.findGui(function(obj)
	return obj:IsA("TextButton") and string.sub(obj.Name, 1, 4) == "Pet_"
end)
print(if #rows > 0 then "TOWERPICK PASS rows " .. #rows else "TOWERPICK FAIL no pet rows")
