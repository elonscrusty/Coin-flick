--!strict
-- COIN FLICK client entry point. The ONLY LocalScript. The client draws things
-- and sends taps; it never decides results.

local Controllers = script.Controllers

local ORDER = { "State", "Sounds", "CameraView", "FlipFx", "MegaFx", "Helpers", "CoinTap", "Hud" }

type Controller = { init: (() -> ())?, start: (() -> ())? }

local loaded: { Controller } = {}
for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `missing controller {name}`)
	table.insert(loaded, (require :: any)(module) :: Controller)
end

for _, controller in loaded do
	if controller.init then
		controller.init()
	end
end

for _, controller in loaded do
	if controller.start then
		task.spawn(controller.start)
	end
end
