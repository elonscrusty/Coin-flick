-- Every RobuxAction a client screen sends must be one the server answers (src/server/RobuxService.luau). Studio
-- 2026-10-15: the Pet Shop sent "BuyEgg" / "BuyPotion" / "BuyPass", the server only knows "Buy", so those buttons
-- did nothing (no purchase prompt).
return function(t)
	local test = t.test

	test("robux actions: every client RobuxAction name has a server handler", function()
		local fs = require("@lune/fs")
		local handled = {}
		for name in string.gmatch(fs.readFile("src/server/RobuxService.luau"), 'action == "(%w+)"') do
			handled[name] = true
		end
		assert(handled.Buy, "server handles Buy")
		local bad = {}
		for _, dir in { "src/client", "src/client/ui" } do
			for _, name in fs.readDir(dir) do
				local f = dir .. "/" .. name
				if fs.isFile(f) and string.sub(name, -5) == ".luau" then
					local src = fs.readFile(f)
					for action in string.gmatch(src, 'Net%.event%("RobuxAction"%):FireServer%("(%w+)"') do
						if not handled[action] then
							table.insert(bad, f .. ": " .. action)
						end
					end
				end
			end
		end
		assert(#bad == 0, "no server handler for " .. table.concat(bad, ", "))
	end)
end
