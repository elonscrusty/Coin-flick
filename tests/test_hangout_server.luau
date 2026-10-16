-- Lobby hangout, server side: runs tests/server/hangout.luau (the REAL server modules on the offline Roblox mock,
-- like tests/test_m10_server.luau) in its own Lune process. Every "CASE <name> PASS" / "[FAIL] CASE <name>: why" line
-- becomes one test; a scene that errors or never prints "HANGOUT DONE" fails.
return function(t)
	local test = t.test
	local fs = require("@lune/fs")
	local process = require("@lune/process")

	local name = "hangout"
	local tools = process.env.CTR_TOOLS or "/tmp/ctr-tools"
	local lune = tools .. "/lune/lune"
	local cwd = process.cwd

	local root = (process.env.TMPDIR or "/tmp") .. "/ctr-hangout-tests-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 1e9))
	fs.writeDir(root .. "/scenes/lib")
	fs.writeDir(root .. "/.cache/fonts")
	for _, f in fs.readDir("tools/preview/scenes/lib") do
		fs.writeFile(root .. "/scenes/lib/" .. f, fs.readFile("tools/preview/scenes/lib/" .. f))
	end
	local metrics = "tools/preview/.cache/fonts/metrics.json"
	fs.writeFile(root .. "/.cache/fonts/metrics.json", if fs.isFile(metrics) then fs.readFile(metrics) else "{}")
	fs.writeFile(root .. "/scenes/" .. name .. ".luau", fs.readFile("tests/server/" .. name .. ".luau"))

	local res = process.exec(lune, {
		"run", "tools/preview/runtime/main.luau", "--",
		"--scene", name, "--out", root .. "/" .. name .. ".json", "--repo", cwd, "--root", root,
		"--max-time", "900", "--set", "headless=on",
	}, { cwd = cwd })
	local out = res.stdout .. "\n" .. res.stderr
	local done, cases = false, 0
	for line in string.gmatch(out, "[^\n]+") do
		local passName = string.match(line, "CASE (.-) PASS%s*$")
		local failName, why = string.match(line, "%[FAIL%] CASE (.-): (.*)$")
		if failName then
			cases += 1
			test("hangout server: " .. failName, function()
				error(why, 0)
			end)
		elseif passName then
			cases += 1
			test("hangout server: " .. passName, function() end)
		elseif string.find(line, "HANGOUT DONE", 1, true) then
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
		test("hangout server: scene ran to the end without game errors", function()
			error(("exit %s, done=%s, cases=%d\n%s"):format(tostring(res.code), tostring(done), cases, table.concat(tail, "\n", math.max(1, #tail - 12))), 0)
		end)
	end
	pcall(fs.removeDir, root)
end
