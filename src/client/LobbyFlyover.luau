--!strict
-- First-join fly-over (client only, cosmetic): a brand-new player (profile onboarding not started yet) gets one
-- slow camera flight around the park before the camera settles behind their avatar. Once per session at most, never
-- during a hunt, never behind an open menu, skipped with Reduce Motion, and any tap / click / key ends it early.
-- A CameraMode cinematic: releasing it hands the camera back to Roblox's own lobby camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapNames = require(Shared.MapNames)
local State = require(script.Parent.State)
local CameraMode = require(script.Parent.CameraMode)
local UI = require(script.Parent.ui.UI)

local LobbyFlyover = {}

local CINE = "LobbyFlyover"
local SECONDS = 7
local player = Players.LocalPlayer
local done = false

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

local function isNew(): boolean
	local p = State.Profile
	if not p or p.OnboardDone == true or type(p.Onboard) ~= "table" then
		return false
	end
	if p.StarterEgg == true then
		return true -- a brand-new player: the short tour (dragon -> arena -> shrine -> their egg) comes first
	end
	return p.Onboard.Started ~= true
end

local function fly()
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not cam or not head or not head:IsA("BasePart") then
		return
	end
	local L = Config.Lodge
	local centre = Vector3.new((L.MinX + L.MaxX) / 2, 0, (L.MinZ + L.MaxZ) / 2)
	local radius = math.min(L.MaxX - L.MinX, L.MaxZ - L.MinZ) * 0.42
	local skip = false
	local conn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Gamepad1 then
			skip = true
		end
	end)
	CameraMode.cinematic(CINE, true)
	cam.CameraType = Enum.CameraType.Scriptable
	local function endFrame(): CFrame
		local hp = (head :: BasePart).Position
		local back = -(head :: BasePart).CFrame.LookVector
		back = Vector3.new(back.X, 0, back.Z)
		back = if back.Magnitude > 0.1 then back.Unit else Vector3.zAxis
		return CFrame.lookAt(hp + back * 14 + Vector3.new(0, 5, 0), hp)
	end
	local a0 = math.atan2((head :: BasePart).Position.Z - centre.Z, (head :: BasePart).Position.X - centre.X) + math.pi
	local t0 = os.clock()
	while not skip do
		local k = (os.clock() - t0) / SECONDS
		if k >= 1 or State.Match ~= nil or not head.Parent or UI.blocked() then
			break
		end
		-- 0..0.7: orbit high around the park; 0.7..1: glide down behind the avatar
		local orbitK = math.min(1, k / 0.7)
		local a = a0 + smooth(orbitK) * math.rad(220)
		local orbit = CFrame.lookAt(centre + Vector3.new(math.cos(a) * radius, 48 - 10 * orbitK, math.sin(a) * radius), centre + Vector3.new(0, 4, 0))
		if k > 0.7 then
			orbit = orbit:Lerp(endFrame(), smooth((k - 0.7) / 0.3))
		end
		cam.CFrame = orbit
		RunService.RenderStepped:Wait()
	end
	conn:Disconnect()
	if cam.Parent and head.Parent then
		cam.CFrame = endFrame()
	end
	CameraMode.cinematic(CINE, false)
end

-- The join tour for a brand-new player (owner north star 2026-10-14: hook them on the dream pet at once):
-- the Void Dragon statue ("1 in 1000"), the arena / PLAY portal, the egg shrine, then their own starter egg,
-- TOUR_SECONDS in all, any tap skips. Stops whose piece is not in the map are left out.
local TOUR_SECONDS = 5.5
LobbyFlyover.ArenaNames = { "BattleArena", "Arena", "FightArena", "PvpArena" } -- first match in the lobby map
LobbyFlyover.ShrineNames = { "EggShrine", "Shrine", "EggShop" }

type Stop = { Focus: Vector3, Size: number, Name: string }

local function centreOf(inst: Instance): (Vector3, number)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, math.max(size.X, size.Y, size.Z)
	elseif inst:IsA("BasePart") then
		return inst.Position, math.max(inst.Size.X, inst.Size.Y, inst.Size.Z)
	end
	return Vector3.zero, 0
end

local function findFirst(names: { string }): Instance?
	for _, n in names do
		local f = Workspace:FindFirstChild(n, true)
		if f and (f:IsA("Model") or f:IsA("BasePart")) then
			return f
		end
	end
	return nil
end

-- The tour's stops in order (exposed for the preview scene).
function LobbyFlyover.tourStops(): { Stop }
	local stops: { Stop } = {}
	local function add(inst: Instance?, name: string, maxSize: number)
		if inst then
			local c, size = centreOf(inst)
			table.insert(stops, { Focus = c, Size = math.clamp(size, 6, maxSize), Name = name })
		end
	end
	-- the dragon itself (on top of the leaderboard tree), not the statue's bounding box with its tall sky beam
	local statue = Workspace:FindFirstChild("VoidDragonStatue", true)
	add(statue and statue:FindFirstChild("Dragon") or statue, "Dragon", 50)
	local meadow = Workspace:FindFirstChild("LobbyMeadow")
	local arena = meadow and meadow:FindFirstChild("BattleArena") -- the dream lobby's centre Battle Arena first
	add(arena or findFirst(LobbyFlyover.ArenaNames) or Workspace:FindFirstChild(MapNames.queuePad(1), true), "Arena", 60)
	add(findFirst(LobbyFlyover.ShrineNames), "Shrine", 40)
	add(Workspace:FindFirstChild("StarterEgg_Local", true), "Egg", 12)
	return stops
end

local function tour(): boolean
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local stops = LobbyFlyover.tourStops()
	if not cam or not head or not head:IsA("BasePart") or #stops < 2 then
		return false
	end
	local hp = head.Position
	-- each stop is seen from the spawn's side, a little above, framed by its size
	local shots: { CFrame } = {}
	for _, st in stops do
		local away = Vector3.new(hp.X - st.Focus.X, 0, hp.Z - st.Focus.Z)
		local dir = if away.Magnitude > 1 then away.Unit else Vector3.zAxis
		local dist = st.Size * 1.3 + 8
		table.insert(shots, CFrame.lookAt(st.Focus + dir * dist + Vector3.new(0, st.Size * 0.45 + 4, 0), st.Focus))
	end
	local back = -head.CFrame.LookVector
	back = Vector3.new(back.X, 0, back.Z)
	back = if back.Magnitude > 0.1 then back.Unit else Vector3.zAxis
	table.insert(shots, CFrame.lookAt(hp + back * 14 + Vector3.new(0, 5, 0), hp))
	local skip = false
	local conn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Gamepad1 then
			skip = true
		end
	end)
	CameraMode.cinematic(CINE, true)
	cam.CameraType = Enum.CameraType.Scriptable
	local legs = #shots - 1
	local t0 = os.clock()
	cam.CFrame = shots[1]
	while not skip do
		local k = (os.clock() - t0) / TOUR_SECONDS
		if k >= 1 or State.Match ~= nil or not head.Parent or UI.blocked() then
			break
		end
		-- each leg: hold on the stop for a moment, then glide to the next one
		local leg = math.min(legs, math.floor(k * legs) + 1)
		local lk = k * legs - (leg - 1)
		local glide = smooth(math.clamp((lk - 0.35) / 0.65, 0, 1))
		local slowPush = CFrame.new(0, 0, -lk * 2) -- a slow push-in while holding
		cam.CFrame = (shots[leg] * slowPush):Lerp(shots[leg + 1], glide)
		RunService.RenderStepped:Wait()
	end
	conn:Disconnect()
	if cam.Parent then
		cam.CFrame = shots[#shots]
	end
	CameraMode.cinematic(CINE, false)
	return true
end

function LobbyFlyover.start()
	task.spawn(function()
		-- wait for the profile (up to 20 s) and a character
		local t0 = os.clock()
		while not State.Profile and os.clock() - t0 < 20 do
			task.wait(0.25)
		end
		if done or not isNew() then
			return
		end
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("Head", 10)
		task.wait(1) -- let the lobby stream in around the spawn
		local w0 = os.clock()
		while UI.blocked() and os.clock() - w0 < 8 do
			task.wait(0.25)
		end
		local p = State.Profile
		local reduced = p and p.Settings and p.Settings.ReducedMotion == true
		if done or UI.blocked() or State.Match ~= nil or CameraMode.inHunt() or reduced or not isNew() then
			return
		end
		done = true
		local ok: boolean, err: any = pcall(function()
			-- a brand-new player gets the short tour; if the map has too few of its stops, the old park fly-over
			if not (p and p.StarterEgg == true and tour()) then
				fly()
			end
		end)
		if not ok then
			warn("[LobbyFlyover]", err)
			CameraMode.cinematic(CINE, false)
		end
	end)
end

return LobbyFlyover
