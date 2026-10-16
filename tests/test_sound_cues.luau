-- Find The Pet sounds (Item 20): every key the client plays exists, no roars anywhere, every made file is wired, and
-- every key moment in shared/SoundCues.Moments maps to a key that some code actually plays.
return function(t)
	local test, shared = t.test, t.shared
	local fs = require("@lune/fs")
	local SoundIds = shared("SoundIds")
	local PetSoundIds = shared("PetSoundIds")
	local SoundConfig = shared("SoundConfig")
	local SoundCues = shared("SoundCues")

	local VARIANT_BASES = { HammerHit = true, StoneCrack = true, GravelSpill = true } -- Audio.VARIANTS (Name1..N)

	local function known(key: string): boolean
		return SoundIds[key] ~= nil or SoundConfig.Ids[key] ~= nil or PetSoundIds[key] ~= nil or VARIANT_BASES[key] == true
	end

	local function walk(dir: string, out: { [string]: string })
		for _, name in fs.readDir(dir) do
			local p = dir .. "/" .. name
			if fs.isDir(p) then
				walk(p, out)
			elseif string.match(name, "%.luau$") then
				out[p] = fs.readFile(p)
			end
		end
		return out
	end
	local client = walk("src/client", {})

	-- every sound name the client code asks for: Audio.play("X" ...) and HatchShow's sound("X" ...)
	local function playedKeys(): { [string]: { string } }
		local used: { [string]: { string } } = {}
		for path, src in client do
			for _, pat in { 'Audio%.play%(%s*"([%w_]+)"', '[^%w_]sound%(%s*"([%w_]+)"' } do
				for key in string.gmatch(src, pat) do
					used[key] = used[key] or {}
					table.insert(used[key], path)
				end
			end
		end
		return used
	end

	local function madeNames(): { string }
		local src = fs.readFile("tools/synth_pet_sfx.py")
		local body = string.match(src, "\nSOUNDS = {(.-)\n}")
		assert(body, "SOUNDS table in tools/synth_pet_sfx.py")
		local out = {}
		for name in string.gmatch(body, '"([%w_]+)"%s*:') do
			table.insert(out, name)
		end
		return out
	end

	test("sound cues: every key the client plays exists in SoundIds / SoundConfig / PetSoundIds", function()
		local bad = {}
		for key, where in playedKeys() do
			if not known(key) then
				table.insert(bad, key .. " (" .. where[1] .. ")")
			end
		end
		assert(#bad == 0, "unknown sound keys: " .. table.concat(bad, ", "))
		-- Audio's own named sounds (button, hatch choir, egg crunch / pop, wind bed, machine loops)
		for _, key in { "ButtonClickSoft", "HatchChoir", "EggCrunch", "EggPop", "HuntWindBed", "LobbyMusic", "RaceMusic", "UIWhooshSoft" } do
			assert(known(key), key)
		end
	end)

	test("sound cues: no roar keys or roar sounds anywhere (owner rule: pets never roar)", function()
		local tables = { SoundIds = SoundIds, PetSoundIds = PetSoundIds, SoundConfig = SoundConfig.Ids, Fallback = SoundCues.Fallback }
		for label, tbl in tables do
			for k, v in tbl do
				assert(not string.find(string.lower(k), "roar", 1, true), label .. "." .. k)
				if type(v) == "string" then
					assert(not string.find(string.lower(v), "roar", 1, true), label .. "." .. k .. " = " .. v)
				end
			end
		end
		for _, m in SoundCues.Moments do
			assert(not string.find(string.lower(m.Key), "roar", 1, true), m.Moment)
		end
		for key in playedKeys() do
			assert(not string.find(string.lower(key), "roar", 1, true), "played: " .. key)
		end
		for _, name in madeNames() do
			assert(not string.find(string.lower(name), "roar", 1, true), "made: " .. name)
		end
		for _, f in fs.readDir("art/sfx") do
			assert(not string.find(string.lower(f), "roar", 1, true), "file: " .. f)
		end
		assert(SoundConfig.Roar == nil, "no per-species roar table")
	end)

	test("sound cues: every made file exists, is a PetSoundIds key and is referenced by code", function()
		local names = madeNames()
		assert(#names >= 26, "made sounds listed: " .. #names)
		for _, name in names do
			assert(fs.isFile("art/sfx/" .. name .. ".ogg"), "missing art/sfx/" .. name .. ".ogg (run tools/synth_pet_sfx.py)")
			assert(PetSoundIds[name] ~= nil, "made sound not wired in PetSoundIds: " .. name)
		end
		-- every file the uploader will send is known to the id tables (none orphaned)
		for _, f in fs.readDir("art/sfx") do
			local name = string.match(f, "^(.-)%.ogg$")
			if name then
				assert(SoundIds[name] ~= nil or PetSoundIds[name] ~= nil, "art/sfx/" .. f .. " is in no id table")
			end
		end
		-- every new moment sound is actually played: by name in client code or through a SoundCues rule
		local used = playedKeys()
		local cuesSrc = fs.readFile("src/shared/SoundCues.luau")
		-- SoundConfig aliases (EggCrunch = PetSoundIds.EggTap): the made file plays under the alias name
		local alias: { [string]: string } = {}
		for key, made in string.gmatch(fs.readFile("src/shared/SoundConfig.luau"), "([%w_]+) = PetSoundIds%.([%w_]+)") do
			alias[made] = key
		end
		for _, name in names do
			local inCode = used[name] ~= nil or string.find(cuesSrc, '"' .. name .. '"', 1, true) ~= nil
				or (alias[name] ~= nil and string.find(fs.readFile("src/client/Audio.luau"), '"' .. alias[name] .. '"', 1, true) ~= nil)
			assert(inCode, "made sound never played: " .. name)
		end
	end)

	test("sound cues: every key moment maps to a known key that some code plays", function()
		local used = playedKeys()
		local cuesSrc = fs.readFile("src/shared/SoundCues.luau")
		local audioSrc = fs.readFile("src/client/Audio.luau")
		local keys = {}
		for _, m in SoundCues.Moments do
			assert(known(m.Key), m.Moment .. " -> unknown key " .. m.Key)
			local played = used[m.Key] ~= nil or string.find(cuesSrc, 'Key = "' .. m.Key .. '"', 1, true) ~= nil
				or string.find(cuesSrc, 'return "' .. m.Key .. '"', 1, true) ~= nil
				or string.find(cuesSrc, '"' .. m.Key .. '" else', 1, true) ~= nil
				or string.find(cuesSrc, 'then "' .. m.Key .. '"', 1, true) ~= nil
				or string.find(audioSrc, '"' .. m.Key .. '"', 1, true) ~= nil
			assert(played, m.Moment .. " -> " .. m.Key .. " is never played")
			keys[m.Key] = true
		end
		-- the owner's moment list (Item 20)
		for _, k in {
			"GeodeReveal", "HatchSparkle", "HatchDrum", "PetFound", "EggGrab", "EggDrop", "BattleMatched", "TowerHit",
			"PetCrit", "TowerSpecial", "PetKO", "BattleWin", "BattleLose", "TrainTap", "LevelUp", "Evolve", "FloorClear",
			"DailyClaim", "GiftOpen", "CoinPickup", "ButtonClickSoft", "UIWhooshSoft", "QuestDone", "LuckyMeter", "Denied",
		} do
			assert(keys[k], "moment list misses " .. k)
		end
		-- a stand-in is an uploaded sound, so a moment that had a sound keeps one until its new file is uploaded
		for new, old in SoundCues.Fallback do
			assert(PetSoundIds[new] ~= nil, new)
			assert((SoundIds[old] or 0) ~= 0, new .. " stand-in " .. old .. " has no uploaded id")
		end
	end)

	test("sound cues: hatch reveal grows with rarity; Legendary and Void get the drum, Epic+ the sparkle", function()
		local function has(cues, key)
			for _, c in cues do
				if c.Key == key then
					return true
				end
			end
			return false
		end
		local common = SoundCues.reveal("Common", false)
		assert(has(common, "GeodeReveal") and has(common, "RarityAccent"))
		assert(not has(common, "HatchSparkle") and not has(common, "HatchDrum"))
		assert(not has(SoundCues.reveal("Rare", false), "HatchSparkle"))
		local epic = SoundCues.reveal("Epic", false)
		assert(has(epic, "HatchSparkle") and not has(epic, "HatchDrum"))
		local leg = SoundCues.reveal("Legendary", false)
		assert(has(leg, "HatchSparkle") and has(leg, "HatchDrum"))
		assert(#leg > #epic and #epic > #common)
		for _, r in { "Mythic", "Void", "Secret" } do
			assert(has(SoundCues.reveal(r, false), "HatchDrum"), r)
		end
		local void = SoundCues.reveal("Legendary", true)
		assert(has(void, "HatchDrum") and has(void, "HatchSparkle"), "the Void Dragon")
		assert(#SoundCues.reveal(nil, false) == 1, "unknown rarity: the plain reveal only")
	end)

	test("sound cues: server messages pick the right moment sound", function()
		-- toasts, with the server's own wording (QuestService, RobuxService, EconomyService)
		assert(SoundCues.toast("Quest done: +50 coins!", "cash") == "QuestDone")
		assert(SoundCues.toast("3 day streak! Daily gift: +40 coins!", "cash") == "DailyClaim")
		assert(SoundCues.toast("LUCKY METER full! Guaranteed EPIC pet!", "rare") == "LuckyMeter")
		assert(SoundCues.toast("Every quest done! You earned a FREE Basic Egg!", "rare") == "QuestDone")
		assert(SoundCues.toast("Candy bag full! Sell candy at the candy stand.", "warn") == "Denied")
		assert(SoundCues.toast("Bought!", "ok") == "ShopKaChing")
		assert(SoundCues.toast("You already opened today's gift. Come back tomorrow!", "info") == nil)
		-- Pet Battle
		assert(SoundCues.pvp({ Kind = "Start" }) == "BattleMatched")
		assert(SoundCues.pvp({ Kind = "Result", Result = "Loss" }) == "BattleLose")
		assert(SoundCues.pvp({ Kind = "Result", Result = "Win" }) == nil, "the panel plays BattleWin itself")
		assert(SoundCues.pvp({ Kind = "Trained", Gain = 5 }) == "TrainTap")
		assert(SoundCues.pvp({ Kind = "Trained", Gain = 5, LevelUp = true }) == nil, "the panel plays LevelUp")
		assert(SoundCues.pvp({ Kind = "Trained", Gain = 0, Maxed = true }) == nil)
		assert(SoundCues.pvp("junk") == nil)
		-- tower and gifts
		assert(SoundCues.tower({ Kind = "FloorEnd", Result = "Cleared" }) == "FloorClear")
		assert(SoundCues.tower({ Kind = "FloorEnd", Result = "Lost" }) == "BattleLose")
		assert(SoundCues.tower({ Kind = "Floor" }) == nil)
		assert(SoundCues.retention("Gift") == "GiftOpen")
		assert(SoundCues.retention("GiftReady") == nil)
	end)
end
