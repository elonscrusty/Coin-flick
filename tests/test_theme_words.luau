-- Theme sweep: no rock / mining / crushing wording in player-visible text (shared/ThemeWords.luau is the one list).
-- Part 1 walks the shared text tables (item names, descriptions, quests, news, events, tower moves). Part 2 scans the
-- string literals of the player-facing client/server files that hold UI text, toasts and prompts.
return function(t)
	local test, shared = t.test, t.shared
	local fs = require("@lune/fs")
	local ThemeWords = shared("ThemeWords")
	local Config = shared("Config")
	local ProgressConfig = shared("ProgressConfig")
	local WhatsNew = shared("WhatsNew")
	local Hangout = shared("Hangout")
	local RobuxConfig = shared("RobuxConfig")
	local TowerConfig = shared("TowerConfig")

	-- keys whose values are ids / enum names, not text
	local SKIP = { Id = true, Key = true, Kind = true, Group = true, Material = true, Look = true, Element = true, Tier = true, Minerals = true }

	local function walk(label: string, v: any, bad: { string }, depth: number)
		if depth > 6 then
			return
		end
		if type(v) == "string" then
			local w = ThemeWords.find(v)
			if w then
				table.insert(bad, label .. ' has "' .. w .. '": ' .. v)
			end
		elseif type(v) == "table" then
			for k, x in v do
				if not (type(k) == "string" and SKIP[k]) then
					walk(label .. "." .. tostring(k), x, bad, depth + 1)
				end
			end
		end
	end

	local function assertClean(label: string, v: any)
		local bad = {}
		walk(label, v, bad, 0)
		if #bad > 0 then
			error(table.concat(bad, "\n"), 0)
		end
	end

	test("theme words: the finder is whole-word and case-insensitive", function()
		assert(ThemeWords.find("Crack eggs at your nest") == "crack")
		assert(ThemeWords.find("GOLDEN ROCK") == "rock")
		assert(ThemeWords.find("Hatch eggs at your nest") == nil)
		assert(ThemeWords.find("Rocketship") == nil, "whole word only")
		assert(ThemeWords.find("Ore") == "ore")
		assert(ThemeWords.find("more shells, store them") == "shells", "egg shells were the old rubble: candy now")
		assert(ThemeWords.find("Sell candy for coins") == nil)
		assert(ThemeWords.find(12) == nil)
	end)

	test("theme words: upgrade gear and nest upgrades have pet names", function()
		local assertEq = function(a, b)
			assert(a == b, tostring(a) .. " ~= " .. tostring(b))
		end
		assertEq(Config.Handhelds.Hammer.Name, "Lucky Collar")
		assertEq(Config.Handhelds.SteelHammer.Name, "Treat Bag")
		assertEq(Config.Handhelds.Jackhammer.Name, "Pet Whistle")
		assertEq(Config.Machines.AutoCracker.Name, "Auto Nest")
		assert(Config.Handhelds.Hammer.Id == "Hammer" and Config.Machines.AutoCracker.Id == "AutoCracker", "ids unchanged")
	end)

	test("theme words: shared text tables are clean", function()
		assertClean("Config.Tiers", Config.Tiers)
		assertClean("Config.Handhelds", Config.Handhelds)
		assertClean("Config.Machines", Config.Machines)
		assertClean("Config.Materials", Config.Materials)
		assertClean("Config.Products", Config.Products)
		assertClean("Config.CosmeticKinds", Config.CosmeticKinds)
		assertClean("Config.Minerals", Config.Minerals)
		assertClean("ProgressConfig.Baskets", ProgressConfig.Baskets)
		assertClean("ProgressConfig.Nests", ProgressConfig.Nests)
		assertClean("ProgressConfig.QuestKinds", ProgressConfig.QuestKinds)
		assertClean("ProgressConfig.Badges", ProgressConfig.Badges)
		assertClean("WhatsNew", { WhatsNew.Title, WhatsNew.Lines })
		assertClean("Hangout.Events.Names", Hangout.Events.Names)
		assertClean("RobuxConfig.Eggs", RobuxConfig.Eggs)
		assertClean("RobuxConfig.Passes", RobuxConfig.Passes)
		assertClean("RobuxConfig.Luck", RobuxConfig.Luck)
		assertClean("TowerConfig.TypeMoves", TowerConfig.TypeMoves)
		assertClean("TowerConfig.Mobs", TowerConfig.Mobs)
		assertClean("TowerConfig.Species", TowerConfig.Species)
		assertClean("TowerConfig.Specials", TowerConfig.Specials)
	end)

	-- String literals of the files that hold player text. A literal counts as text when it has a space or is all
	-- capitals (single identifiers like "Crush" or "Rocks" are remote / action names, not text).
	-- every source file (whole structure, not a hand-kept list); these hold no player text: generated mesh notes,
	-- sound asset titles, the Studio-only dev command help, and third-party code
	local SKIP_FILES = {
		["src/shared/MeshCatalog.luau"] = true, ["src/shared/PetSoundIds.luau"] = true,
		["src/server/DevCommands.server.luau"] = true,
	}
	local FILES = {}
	local function collect(dir: string)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if name ~= "Vendor" then
					collect(path)
				end
			elseif string.sub(name, -5) == ".luau" and not SKIP_FILES[path] then
				table.insert(FILES, path)
			end
		end
	end
	collect("src")
	table.sort(FILES)
	local function isText(s: string): boolean
		return string.find(s, " ", 1, true) ~= nil or (string.find(s, "^[A-Z][A-Z%d%p]+$") ~= nil and #s > 3)
	end
	-- A literal is also player text, whatever its shape, when the code right before it hands it to the screen: a Text /
	-- ActionText / ObjectText / PlaceholderText property, UI.text / UI.button / UI.chip / UI.toast, a toast remote or a
	-- sign helper. That catches one-word labels ("Shells", "Rock") that the shape test lets through.
	local TEXT_CONTEXT = {
		"Text%s*=%s*$", "Title%s*=%s*$", "Sub%s*=%s*$", "Label%s*=%s*$", "Caption%s*=%s*$", "Hint%s*=%s*$",
		"UI%.text%([^,()]*,%s*$", "UI%.button%([^,()]*,%s*$", "UI%.chip%([^,()]*,%s*$", "UI%.toast%(%s*$",
		"[Tt]oast%([^()]*,%s*$", "[Tt]oast%(%s*$", "[Tt]oast[%w_]*:FireClient%([^,()]*,%s*$", '"Toast"%):FireClient%([^,()]*,%s*$', "[Tt]oast[%w_]*%([^()]*,%s*$", "[Ss]ign%([^()]*,%s*$", "word%([^,()]*,%s*$",
	}
	local function textContext(before: string): boolean
		for _, pat in TEXT_CONTEXT do
			if string.find(before, pat) then
				return true
			end
		end
		return false
	end
	-- Every string literal on a line ("..", '..', `..`), with the code before it; a trailing -- comment ends the scan.
	-- Escapes (\n, \u{b7}, \") read as a space, so "SELL\nSHELLS" is caught too; `{...}` interpolations read as a space.
	local function literals(line: string): { { text: string, before: string } }
		local out = {}
		local i, n = 1, #line
		local code = {}
		while i <= n do
			local c = string.sub(line, i, i)
			if c == "-" and string.sub(line, i + 1, i + 1) == "-" then
				break
			elseif c == '"' or c == "'" or c == "`" then
				local buf = {}
				local j = i + 1
				local depth = 0
				while j <= n do
					local d = string.sub(line, j, j)
					if d == "\\" then
						table.insert(buf, " ")
						j += 2
					elseif c == "`" and d == "{" then
						depth += 1
						j += 1
					elseif c == "`" and d == "}" and depth > 0 then
						depth -= 1
						table.insert(buf, " ")
						j += 1
					elseif depth > 0 then
						j += 1
					elseif d == c then
						break
					else
						table.insert(buf, d)
						j += 1
					end
				end
				table.insert(out, { text = table.concat(buf), before = table.concat(code) })
				table.insert(code, c .. table.concat(buf) .. c)
				i = j + 1
			else
				table.insert(code, c)
				i += 1
			end
		end
		return out
	end
	test("theme words: the literal scanner sees one-word labels, all quote kinds and skips comments", function()
		local l = literals([[x.Text = "Shells" -- "rock" in a comment]])
		assert(#l == 1 and l[1].text == "Shells" and textContext(l[1].before), "a Text property label")
		local l2 = literals([[UI.button(row, 'Rock', "gold", fn)]])
		assert(l2[1].text == "Rock" and textContext(l2[1].before), "single quotes, a button caption")
		assert(not textContext(literals([[if d.Name == "Rock" then]])[1].before), "an instance name is code")
		assert(literals("toast(p, `Sold {n} geodes!`)")[1].text == "Sold   geodes!", "interpolated string")
		assert(textContext(literals("toast(p, `Sold {n} geodes!`)")[1].before), "a toast")
		local l3 = literals([[Net.event("Toast"):FireClient(player, "Rubble", "ok")]])
		assert(l3[2].text == "Rubble" and textContext(l3[2].before), "a toast remote")
		assert(not textContext(literals([[remote:FireClient(p, "Rocks", payload)]])[1].before), "an event name is code")
		assert(literals([["SELL\nSHELLS"]])[1].text == "SELL SHELLS", "escapes")
	end)
	test("theme words: player-facing source files hold no banned wording in their text strings", function()
		local bad = {}
		for _, f in FILES do
			if fs.isFile(f) then
				local lineNo = 0
				for line in string.gmatch(fs.readFile(f) .. "\n", "(.-)\n") do
					lineNo += 1
					if not string.find(line, "^%s*%-%-") then
						for _, lit in literals(line) do
							local w = (isText(lit.text) or textContext(lit.before)) and ThemeWords.find(lit.text)
							if w then
								table.insert(bad, f .. ":" .. lineNo .. ' "' .. w .. '" in "' .. lit.text .. '"')
							end
						end
					end
				end
			end
		end
		if #bad > 0 then
			error(table.concat(bad, "\n"), 0)
		end
	end)
	test("theme: toasts and empty states default to an egg, not a rock or geode", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/client/ui/UI.luau")
		assert(string.find(src, 'icon or "egg"', 1, true), "empty state default icon")
		local kinds = string.match(src, "local KIND_ICON = (%b{})")
		assert(kinds, "KIND_ICON table")
		assert(not string.find(kinds, '"rock"', 1, true) and not string.find(kinds, '"geode"', 1, true), "toast icons: " .. kinds)
	end)
end
