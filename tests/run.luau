-- Offline test runner for the pure shared modules (run with Lune: bash tools/test.sh).
-- Loads src/shared/*.luau with a fake `script` so `require(script.Parent.X)` works outside Roblox.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ROOT = "src/shared/"

-- Lune has no Random; a small deterministic stand-in (Park-Miller LCG) with the same API.
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	local s = math.floor(seed or os.clock() * 1e6) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	local r = setmetatable({ s = s }, Random)
	for _ = 1, 12 do -- decorrelate nearby seeds
		r:_next()
	end
	return r
end
function Random:_next(): number
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a: number?, b: number?): number
	local lo, hi = a or 0, b or 1
	return lo + self:_next() * (hi - lo)
end
function Random:NextInteger(a: number, b: number): number
	return a + math.floor(self:_next() * (b - a + 1))
end
local cache = {}
local env

local function node(path: string)
	return setmetatable({ __path = path }, {
		__index = function(t, k)
			if k == "Parent" then
				return node(string.match(t.__path, "^(.*)/[^/]+$") or "")
			end
			return node(t.__path .. "/" .. k)
		end,
	})
end

local function load(path: string)
	if cache[path] ~= nil then
		return cache[path]
	end
	local file = path .. ".luau"
	local src = fs.readFile(file)
	local chunk = luau.load(src, { debugName = file, environment = env(path) })
	local result = chunk()
	cache[path] = result
	return result
end

function env(path: string)
	local e = {
		script = node(path),
		require = function(n)
			if type(n) == "table" and n.__path then
				return load(n.__path)
			end
			return require(n)
		end,
	}
	for _, name in { "Vector3", "Vector2", "Color3", "CFrame", "Rect" } do
		e[name] = roblox[name]
	end
	e.typeof = function(v)
		if type(v) == "userdata" then
			return "Vector3" -- the only userdata the shared modules inspect
		end
		return type(v)
	end
	e.Random = Random
	return setmetatable(e, { __index = _G })
end

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("PASS " .. name)
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local ctx = {
	test = test,
	shared = function(name: string)
		return load(ROOT .. name)
	end,
	Random = Random,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	Rect = roblox.Rect,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	-- recorded data for tests (tests/fixtures/<dir>/*): { [file name] = text }
	fixtures = function(dir: string): { [string]: string }
		local out = {}
		local path = "tests/fixtures/" .. dir
		if fs.isDir(path) then
			for _, f in fs.readDir(path) do
				out[f] = fs.readFile(path .. "/" .. f)
			end
		end
		return out
	end,
	json = function(text: string): any
		return serde.decode("json", text)
	end,
}

-- CTR_ONLY=pvp_tap runs only test files whose name holds that text (quick checks while tuning)
local only = process.env.CTR_ONLY
for _, f in fs.readDir("tests") do
	if string.match(f, "^test_.*%.luau$") and (only == nil or only == "" or string.find(f, only, 1, true) ~= nil) then
		local chunk = luau.load(fs.readFile("tests/" .. f), { debugName = f, environment = setmetatable({}, { __index = _G }) })
		chunk()(ctx)
	end
end

print(string.format("TESTS: %d passed, %d failed", passed, failed))
process.exit(if failed == 0 then 0 else 1)
