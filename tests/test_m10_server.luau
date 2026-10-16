-- Pass 6 server rules and safety audit (docs/m10/RULES_AUDIT_2.md).
-- The cases in tests/server/*.luau drive the REAL server modules (PartyService, MatchService, RockService,
-- EconomyService, Profiles) through the real remotes on the offline Roblox mock (tools/preview/runtime), each
-- scene in its own Lune process. Every "CASE <name> PASS" / "[FAIL] CASE <name>: why" line a scene prints
-- becomes one test here; a scene that errors or never prints "<SCENE> DONE" fails as a whole.
-- Needs Lune (tools/setup_tools.sh). The preview fonts are optional (headless: no client GUI is built).
return function(t)
	local test = t.test
	local fs = require("@lune/fs")
	local process = require("@lune/process")

	local SCENES = { "rocks", "party", "economy", "profiles", "pets", "robux", "retention", "pvp", "budget" }
	local tools = process.env.CTR_TOOLS or "/tmp/ctr-tools"
	local lune = tools .. "/lune/lune"
	local cwd = process.cwd

	-- a private preview root: scene helpers, these scenes, and the font metrics if the preview is set up
	local root = (process.env.TMPDIR or "/tmp") .. "/ctr-server-tests-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 1e9))
	fs.writeDir(root .. "/scenes/lib")
	fs.writeDir(root .. "/.cache/fonts")
	for _, f in fs.readDir("tools/preview/scenes/lib") do
		fs.writeFile(root .. "/scenes/lib/" .. f, fs.readFile("tools/preview/scenes/lib/" .. f))
	end
	local metrics = "tools/preview/.cache/fonts/metrics.json"
	fs.writeFile(root .. "/.cache/fonts/metrics.json", if fs.isFile(metrics) then fs.readFile(metrics) else "{}")
	for _, name in SCENES do
		fs.writeFile(root .. "/scenes/" .. name .. ".luau", fs.readFile("tests/server/" .. name .. ".luau"))
	end

	for _, name in SCENES do
		local res = process.exec(lune, {
			"run", "tools/preview/runtime/main.luau", "--",
			"--scene", name, "--out", root .. "/" .. name .. ".json", "--repo", cwd, "--root", root,
			"--max-time", "900", "--set", "headless=on",
		}, { cwd = cwd })
		local out = res.stdout .. "\n" .. res.stderr
		local done = false
		local cases = 0
		for line in string.gmatch(out, "[^\n]+") do
			local passName = string.match(line, "CASE (.-) PASS%s*$")
			local failName, why = string.match(line, "%[FAIL%] CASE (.-): (.*)$")
			if failName then
				cases += 1
				test("m10 " .. name .. ": " .. failName, function()
					error(why, 0)
				end)
			elseif passName then
				cases += 1
				test("m10 " .. name .. ": " .. passName, function() end)
			elseif string.find(line, string.upper(name) .. " DONE", 1, true) then
				done = true
			end
		end
		if not done or not res.ok or cases == 0 then
			local tail = {}
			for line in string.gmatch(out, "[^\n]+") do
				if string.find(line, "rror") or string.find(line, "FAIL") or string.find(line, "%[preview%]") then
					table.insert(tail, line)
				end
			end
			test("m10 " .. name .. ": scene ran to the end without game errors", function()
				error(("exit %s, done=%s, cases=%d\n%s"):format(tostring(res.code), tostring(done), cases, table.concat(tail, "\n", math.max(1, #tail - 12))), 0)
			end)
		end
	end
	pcall(fs.removeDir, root)
end
