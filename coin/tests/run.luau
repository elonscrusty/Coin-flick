--!nocheck
-- Test runner for COIN FLICK's pure game logic. Runs under Lune (outside Roblox):
--   lune run tests/run.luau
-- It fakes just enough of Roblox (game:GetService, script.Parent, require of
-- module paths) to load the real src/ modules unchanged.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local task = require("@lune/task")

local ROOT = "src"
local SERVICE_MAP = {
	ReplicatedStorage = { Shared = ROOT .. "/shared" },
	ServerScriptService = { Server = ROOT .. "/server" },
}

-- Read all of src/ up front (Lune file calls can't run inside metamethods).
local files = {}
local dirs = {}
local function scan(dir)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			scan(p)
		else
			files[p] = fs.readFile(p)
		end
	end
end
scan(ROOT)

-- Fake Instance tree backed by folders/files ------------------------------
local nodeCache = {}
local function makeNode(path, parent)
	if nodeCache[path] then
		return nodeCache[path]
	end
	local node = setmetatable({ __path = path, Parent = parent }, {
		__index = function(self, name)
			local p = rawget(self, "__path")
			local filePath = p .. "/" .. name .. ".luau"
			local dirPath = p .. "/" .. name
			if files[filePath] then
				return makeNode(filePath, self)
			elseif dirs[dirPath] then
				return makeNode(dirPath, self)
			end
			error(`{name} is not a valid member of {p}`, 2)
		end,
		__tostring = function(self)
			return rawget(self, "__path")
		end,
	})
	nodeCache[path] = node
	return node
end

local services = {}
for serviceName, children in SERVICE_MAP do
	local service = {}
	for childName, path in children do
		service[childName] = makeNode(path, service)
	end
	services[serviceName] = service
end

local fakeGame = {
	GetService = function(_, name)
		local s = services[name]
		if not s then
			error(`fake game has no service {name}`)
		end
		return s
	end,
}

local fakeColor3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
}

-- Module loader ------------------------------------------------------------
local moduleCache = {}
local makeEnv

local function requireNode(node)
	local path = rawget(node, "__path")
	assert(path, "require() expects a module path node")
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local file = path
	if dirs[path] then
		file = path .. "/init.luau"
	end
	local source = files[file]
	assert(source, "no module at " .. file)
	local fn = luau.load(source, { debugName = file, environment = makeEnv(node) })
	local result = fn()
	moduleCache[path] = result
	return result
end

local extraGlobals = {}

makeEnv = function(scriptNode)
	local env = {
		script = scriptNode,
		require = requireNode,
		game = fakeGame,
		Color3 = fakeColor3,
		task = task,
		typeof = typeof,
		warn = function() end, -- quiet: tests check warnings through injected deps
	}
	for k, v in extraGlobals do
		env[k] = v
	end
	return env
end

-- Tiny describe/it/expect ---------------------------------------------------
local passed, failed = 0, 0
local prefix = {}

local function describe(name, fn)
	table.insert(prefix, name)
	fn()
	table.remove(prefix)
end

local function it(name, fn)
	local full = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  PASS  " .. full)
	else
		failed += 1
		print("  FAIL  " .. full)
		print("        " .. tostring(err))
	end
end

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(`expected {fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeNear(expected, eps)
		eps = eps or 1e-9
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			error(`expected ~{fmt(expected)}, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(`expected truthy, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(`expected falsy, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(`expected nil, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeAtLeast(n)
		if type(actual) ~= "number" or actual < n then
			error(`expected >= {n}, got {fmt(actual)}`, 2)
		end
	end
	function e.toBeAtMost(n)
		if type(actual) ~= "number" or actual > n then
			error(`expected <= {n}, got {fmt(actual)}`, 2)
		end
	end
	function e.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end
	return e
end

extraGlobals.describe = describe
extraGlobals.it = it
extraGlobals.expect = expect

-- Also make sure EVERY .luau file in src compiles (catches syntax errors in
-- the Roblox-only scripts that can't run here).
local compileErrors = 0
print("Compiling every script in src/ ...")
for p, source in files do
	if string.sub(p, -5) == ".luau" then
		local ok, err = pcall(luau.compile, source)
		if not ok then
			compileErrors += 1
			print("  COMPILE ERROR  " .. p .. ": " .. tostring(err))
		end
	end
end
if compileErrors == 0 then
	print("  PASS  all scripts compile")
	passed += 1
else
	failed += compileErrors
end

-- Run specs ----------------------------------------------------------------
local specDir = "tests/specs"
local specFiles = fs.readDir(specDir)
table.sort(specFiles)
for _, name in specFiles do
	if string.sub(name, -10) == ".spec.luau" then
		print("\n" .. name)
		local p = specDir .. "/" .. name
		local fn = luau.load(fs.readFile(p), { debugName = p, environment = makeEnv(makeNode(p, nil)) })
		local ok, err = pcall(fn)
		if not ok then
			failed += 1
			print("  FAIL  (spec file crashed) " .. tostring(err))
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
