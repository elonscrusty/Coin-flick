-- loading: the FIND THE GEODE! title / loading screen (src/first/LoadingScreen, ReplicatedFirst).
--   --set step=1|2|3  the screen frozen at that real step (default 2: place loaded, waiting for the character)
--   --set step=run    LoadingScreen.run() during the real server + client boot; prints "loading PASS" when
--                     it walked its steps and removed itself once the HUD existed
local C = lib("ctr")
local RF = game:GetService("ReplicatedFirst")
local folder = RF:FindFirstChild("Loading")
local mod = folder and folder:FindFirstChild("LoadingScreen")
if not mod then
	print("[FAIL] ReplicatedFirst.Loading.LoadingScreen is missing (default.project.json mapping)")
	return
end
local LoadingScreen = preview.require(mod)
local step = preview.args.step or "2"

if step == "run" then
	task.spawn(LoadingScreen.run)
	preview.advance(0.2)
	local pg = preview.playerGui()
	local shownEarly = pg:FindFirstChild("FindTheGeodeLoading") ~= nil
	C.boot({
		profile = function(data)
			data.TutorialStep = 1
		end,
	})
	C.settle(2)
	local gone = pg:FindFirstChild("FindTheGeodeLoading") == nil
	local hud = pg:FindFirstChild("CrackTheRocks") ~= nil
	if shownEarly and gone and hud then
		print("loading PASS (shown before the client booted, removed after the HUD appeared)")
	else
		print(("[FAIL] loading: shownEarly=%s gone=%s hud=%s"):format(tostring(shownEarly), tostring(gone), tostring(hud)))
	end
	C.followCamera()
	return
end

local n = tonumber(step) or 2
local screen = LoadingScreen.new()
screen:setStep(n, LoadingScreen.Steps[n] or LoadingScreen.Steps[2])
preview.advance(0.5)
