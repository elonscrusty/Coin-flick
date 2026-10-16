--!strict
-- COIN FLICK server entry point. The ONLY server Script; everything else is a module.
-- Two phases: init() every system (wire things up), then start() them (loops).

local Systems = script.Systems

-- Fixed order: Net creates the remotes the others need.
local ORDER = {
	"Net",
	"Boosts",
	"World",
	"PlayerData",
	"Tables",
	"Shop",
	"Mega",
	"Pets",
	"Hats",
	"Robux",
	"Leaderboards",
	"Daily",
	"Goals",
	"Friends",
	"Cheats",
}

type System = { init: (() -> ())?, start: (() -> ())? }

local loaded: { System } = {}
for _, name in ORDER do
	local module = Systems:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `missing system {name}`)
	table.insert(loaded, (require :: any)(module) :: System)
end

for _, system in loaded do
	if system.init then
		system.init()
	end
end

for _, system in loaded do
	if system.start then
		task.spawn(system.start)
	end
end

print("[COIN FLICK] server started")
