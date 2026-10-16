-- Dumps PetPose channel values per frame for preview renders (tools/pet_motion_render.py). Lune:
--   /tmp/ctr-tools/lune/lune run tools/pet_pose_dump.luau > out.json
-- Scenes: each gait walking at follower speed, idle, plus the shared clips; height 5 studs (a follower is ~4.6).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local cache = {}
local function node(path)
	return setmetatable({ __path = path }, { __index = function(t, k)
		if k == "Parent" then return node(string.match(t.__path, "^(.*)/[^/]+$") or "") end
		return node(t.__path .. "/" .. k)
	end })
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = node(path), require = function(n) return load(n.__path) end }, { __index = _G })
	cache[path] = luau.load(fs.readFile(path .. ".luau"), { debugName = path, environment = env })()
	return cache[path]
end
local PetPose = load("src/shared/PetPose")

local H = 5
local function run(gait, opts, seconds, fps)
	local s = PetPose.new(1)
	local frames = {}
	for f = 1, math.floor(seconds * fps) do
		local i = { moving = opts.moving or false, speed = opts.speed or 0, height = H, gait = gait, rigged = true,
			anim = opts.anim, yaw = 0 }
		if f == 1 and opts.shot then PetPose.play(s, opts.shot) end
		if f == 1 and opts.pop then PetPose.pop(s, opts.pop) end
		local V = PetPose.step(s, i, 1 / fps)
		local copy = {}
		for _, ch in PetPose.CH do copy[ch] = V[ch] / (if ch == "rootY" or ch == "rootZ" then H / 5 else 1) end
		table.insert(frames, copy)
	end
	return frames
end
local out = {}
for g in PetPose.GAITS do
	out["walk_" .. g] = run(g, { moving = true, speed = 14 }, 1.2, 60)
end
out.idle = run("quad", {}, 4, 15)
for _, c in { "attack", "hit", "win" } do out[c] = run("quad", { shot = c }, PetPose.Clips[c].dur, 30) end
out.run = run("quad", { moving = true, speed = 26, anim = "run" }, 0.8, 60)
out.train = run("quad", { anim = "train" }, 1.6, 30)
out.hatch = run("quad", { pop = "hatch" }, PetPose.HOP_TIME, 30)
print(serde.encode("json", out))
