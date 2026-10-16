--!strict
-- Small camera feel on top of Roblox's own camera (client only, cosmetic):
--   * CameraFx.shake(strength, seconds): the ONE shared shake helper. Used only for big moments (the pet is found,
--     a hatch pops at the stand right next to you). A small rotation that decays to nothing; never while Reduce
--     Motion is on, never during a cinematic (Scriptable camera).
--   * Lobby smooth follow: in the third-person lobby the camera trails the avatar by a fraction of a second (a soft
--     spring on position, at most MAX_LAG studs behind). Not in first person (the eye must stay in the head).
--   * CameraFx.punch(degrees, seconds): a field of view kick for fight moments (FightFx), added on top of the boots.
--   * Speed boots: while the own avatar wears the boots sparkles (EggFx "EggBootsSparkles") and runs, the field of
--     view widens by a few degrees, easing back when the boots end or the player stops.
--
-- How it stays out of the way of PlayerModule (CameraMode never writes Camera.CFrame): the offset is added AFTER the
-- default camera and CameraGuard have run (RenderPriority.Camera + 3) and taken off again BEFORE the default camera
-- runs next frame (RenderPriority.Camera - 1), so the camera scripts always see their own last CFrame and nothing
-- drifts. Field of view only changes while the boost runs and returns exactly to Config.Camera.Fov.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local State = require(script.Parent.State)

local CameraFx = {}

local MAX_LAG = 1.6 -- studs the lobby camera may trail the avatar
local LAG_RATE = 14 -- spring speed (higher = tighter)
local BOOTS_FOV = 8 -- extra degrees with speed boots
local FOV_RATE = 4 -- per second, towards the goal
local RUNNING = 10 -- studs/s horizontal before the boots widen the view

local player = Players.LocalPlayer
local started = false
local applied: CFrame? = nil -- the offset added this frame (taken off before the next default camera step)
local appliedOn: CFrame? = nil -- the CFrame after the offset (only undone if nothing else wrote since)
local lagPos: Vector3? = nil
local fovExtra = 0
local fovOwned = false
type Punch = { Start: number, Dur: number, Deg: number }
local punches: { Punch } = {}

type Shake = { Start: number, Dur: number, Amp: number, Seed: number }
local shakes: { Shake } = {}

local function reduced(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.ReducedMotion == true
end

local function cinematic(cam: Camera): boolean
	return cam.CameraType == Enum.CameraType.Scriptable or cam:GetAttribute("CT_Cinematic") == true
end

-- Shake the camera a little for `seconds` (strength 0..1; 1 = about 1.2 degrees). Several shakes add up to a cap.
function CameraFx.shake(strength: number, seconds: number?)
	if reduced() or #shakes >= 4 then
		return
	end
	table.insert(shakes, { Start = os.clock(), Dur = math.clamp(seconds or 0.35, 0.05, 1.5), Amp = math.clamp(strength, 0, 1), Seed = math.random() * 100 })
end

-- Field of view kick for a fight moment (FightFx): jumps `degrees` wider at once and eases back over `seconds`.
-- Never with Reduce Motion or during a cinematic; at most 3 at once.
function CameraFx.punch(degrees: number, seconds: number?)
	if reduced() or #punches >= 3 then
		return
	end
	table.insert(punches, { Start = os.clock(), Dur = math.clamp(seconds or 0.5, 0.1, 1.5), Deg = math.clamp(degrees, 0, 20) })
end

local function punchNow(now: number): number
	local sum = 0
	for i = #punches, 1, -1 do
		local p = punches[i]
		local k = (now - p.Start) / p.Dur
		if k >= 1 then
			table.remove(punches, i)
		else
			sum += p.Deg * (1 - k) * (1 - k)
		end
	end
	return math.min(sum, 20)
end

local function shakeOffset(now: number): CFrame?
	if #shakes == 0 then
		return nil
	end
	local rx, ry, rz = 0, 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = (now - s.Start) / s.Dur
		if k >= 1 then
			table.remove(shakes, i)
		else
			local a = math.rad(1.2) * s.Amp * (1 - k) * (1 - k)
			local t = now * 31 + s.Seed
			rx += math.noise(t, 0.5) * a * 2
			ry += math.noise(t, 7.5) * a * 2
			rz += math.noise(t, 13.5) * a
		end
	end
	return CFrame.Angles(rx, ry, rz)
end

local function undo()
	local cam = Workspace.CurrentCamera
	local off, on = applied, appliedOn
	applied, appliedOn = nil, nil
	if cam and off and on and cam.CFrame == on then
		cam.CFrame = on * off:Inverse()
	end
end

local function apply(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	if cinematic(cam) then
		lagPos = nil
		table.clear(shakes)
		table.clear(punches)
		return
	end
	local now = os.clock()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local thirdPerson = player.CameraMode ~= Enum.CameraMode.LockFirstPerson
	-- lobby trail: a spring towards the avatar; the camera is moved by (trail - avatar), clamped
	local move = Vector3.zero
	if thirdPerson and State.Match == nil and root and root:IsA("BasePart") and not reduced() then
		local target = root.Position
		local lp = lagPos
		if not lp or (lp - target).Magnitude > 12 then
			lp = target -- spawn / teleport: no long slide
		end
		local k = 1 - math.exp(-LAG_RATE * dt)
		lp = (lp :: Vector3):Lerp(target, k)
		lagPos = lp
		local d = (lp :: Vector3) - target
		if d.Magnitude > MAX_LAG then
			d = d.Unit * MAX_LAG
		end
		move = d
	else
		lagPos = nil
	end
	-- speed boots: wider view while running with the boots sparkles on
	local goal = 0
	if root and root:IsA("BasePart") and root:FindFirstChild("EggBootsSparkles") and not reduced() then
		local v = root.AssemblyLinearVelocity
		if Vector2.new(v.X, v.Z).Magnitude > RUNNING then
			goal = BOOTS_FOV
		end
	end
	local kick = punchNow(now)
	if goal ~= fovExtra or fovOwned or kick > 0 then
		local step = FOV_RATE * BOOTS_FOV * dt
		fovExtra = if goal > fovExtra then math.min(goal, fovExtra + step) else math.max(goal, fovExtra - step)
		cam.FieldOfView = Config.Camera.Fov + fovExtra + kick
		fovOwned = fovExtra > 0 or kick > 0
	end
	local rot = shakeOffset(now)
	if move.Magnitude < 1e-3 and not rot then
		return
	end
	local off = CFrame.new(cam.CFrame.Rotation:PointToObjectSpace(move)) * (rot or CFrame.identity)
	local on = cam.CFrame * off
	cam.CFrame = on
	applied, appliedOn = off, on
end

function CameraFx.start()
	if started then
		return
	end
	started = true
	RunService:BindToRenderStep("CTR_CameraFxUndo", Enum.RenderPriority.Camera.Value - 1, undo)
	RunService:BindToRenderStep("CTR_CameraFx", Enum.RenderPriority.Camera.Value + 3, apply)
end

return CameraFx
