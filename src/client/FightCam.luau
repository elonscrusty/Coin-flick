--!strict
-- Pet Battle camera director (carter 2026-10-14: "when they are fighting the camera should pan and do cool
-- animations"). Client only, cosmetic; the fight itself is the server's. While the local player fights:
--   * intro   a wide high orbit round the whole arena that sweeps in behind the player's team (the count-in)
--   * base    a high three-quarter view behind the player's team that slowly pans side to side and breathes in/out
--   * cut     crits and type SUPER hits cut to a side-on close-up of the pet that was hit, then ease back
--   * charge  the player's SPECIAL: over the shoulder of the caster, looking at the rival team
--   * ko      a slow orbit round the pet that fainted (FightFx runs the slow motion), then a low hero shot of the winner
--   * hero    a low push-in on one pet that holds (the winner, or the rival that beat you) until the fight closes
-- Every shot is a target camera the real camera eases towards each frame, so cuts never snap. Reduce Motion keeps one
-- still high view (no orbit, no cuts). FightCam.stop() hands the camera back to the player.
-- FightCamRules (shared) holds the shot maths, tested offline.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rules = require(Shared.FightCamRules)
local UI = require(script.Parent.ui.UI)
local CameraMode = require(script.Parent.CameraMode)
local PopupGate = require(script.Parent.PopupGate)

local FightCam = {}

type Shot = { Kind: string, Started: number, Until: number, Fn: (t: number) -> CFrame, Ease: number, Focus: (() -> Vector3)?, Of: string? }

local active = false
local stage: Rules.Stage? = nil
local shot: Shot? = nil
local startedAt = 0
local lastCut = -math.huge
local conn: RBXScriptConnection? = nil
local baseFov: number? = nil -- the player's lens before the fight, given back by stop()
local heroLens = false -- the lens is narrowed (or easing back) for the hero shot
local baseFrom = 0 -- when the base orbit's clock starts (after the intro, so the intro lands on base(0))
local nudgeAt: (() -> Vector3?)? = nil -- the pet the last hit landed on (the base view leans in on it)
local nudgeStart = -math.huge
local backUntil = 0 -- the wide shot comes back quickly until this time after a close-up
local NUDGE_IN, NUDGE_OUT = 0.15, 0.75
local hidden: { [Instance]: boolean } = {} -- the player's own avatar parts made see-through for the fight
local BIND = "CT_FightCam"
local CINEMATIC = "FightCam" -- CameraMode.cinematic key held for the whole fight
local dimmed: { [Instance]: { [string]: number } } = {} -- lobby bloom / exposure turned down for the fight
local BIND_HIDE = "CT_FightHideSelf"

-- The island top washes out under the lobby's bloom (Studio check 2026-10-14): while the player fights, the world's
-- own bloom and exposure are turned down (FightFx's own CT_ effects are left alone), and given back at the end.
local Lighting = game:GetService("Lighting")
local FIGHT_BLOOM, FIGHT_EXPOSURE = 0.35, -0.35
local function dimLights(on: boolean)
	if on then
		if next(dimmed) ~= nil then
			return
		end
		dimmed[Lighting] = { ExposureCompensation = Lighting.ExposureCompensation }
		Lighting.ExposureCompensation += FIGHT_EXPOSURE
		for _, e in Lighting:GetChildren() do
			if e:IsA("BloomEffect") and string.sub(e.Name, 1, 3) ~= "CT_" then
				dimmed[e] = { Intensity = e.Intensity }
				e.Intensity *= FIGHT_BLOOM
			end
		end
	else
		for inst, props in dimmed do
			if inst.Parent or inst == Lighting then
				for k, v in props do
					(inst :: any)[k] = v
				end
			end
		end
		table.clear(dimmed)
	end
end

local function reduced(): boolean
	return UI.Reduced == true
end

local function centreOf(m: Model?): Vector3?
	if not m or not m.Parent then
		return nil
	end
	local ok, cf, size = pcall(m.GetBoundingBox, m)
	if not ok then
		return nil
	end
	return (cf :: CFrame).Position + Vector3.new(0, -(size :: Vector3).Y * 0.1, 0)
end

local function sizeOf(m: Model): number
	local ok, _, size = pcall(m.GetBoundingBox, m)
	return if ok then math.max((size :: Vector3).Magnitude, 2) else 3
end

local function base(t: number): CFrame
	local s = stage :: Rules.Stage
	return Rules.base(s, t)
end

-- Keeps the view clear of anything solid between the fight and the camera (island trees, rocks, statues, walls),
-- decor without collision included. The fight's own pets, avatars and see-through parts never block. A blocked shot is
-- first lifted (same distance, so the framing holds), and only pulled in if lifting does not clear it; either way it is
-- re-aimed at what it was looking at (Studio 2026-10-15: a pulled-in shot kept its old angle, so the player's pet sat
-- cropped in a corner and the rival drifted off screen).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local LIFTS = { 0, 4, 8, 12 }
local blockedBy = "" -- what last blocked the shot (the Studio check log)

-- First solid hit between `from` and `to` (nil = clear); see-through parts are added to `skip` and looked past.
local function blocker(from: Vector3, to: Vector3, skip: { Instance }): RaycastResult?
	for _ = 1, 6 do
		rayParams.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(from, to - from, rayParams)
		if not hit or hit.Instance.Transparency <= 0.5 then
			return hit
		end
		table.insert(skip, hit.Instance)
	end
	return nil
end

local function unblocked(want: CFrame, focus: Vector3?): CFrame
	local s = stage
	if not s then
		return want
	end
	local look = focus or s.Centre -- close shots check from the pet they frame
	local skip: { Instance } = {}
	local drawn = Workspace:FindFirstChild("TowerView") -- the fight's own pets and effects (TowerView)
	if drawn then
		table.insert(skip, drawn)
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	-- the point the shot frames: on its view line, level with `look`
	local fwd = want.LookVector
	local aim = want.Position + fwd * math.max((look - want.Position):Dot(fwd), 4)
	local out = want
	blockedBy = ""
	pcall(function()
		for i, lift in LIFTS do
			local pos = want.Position + Vector3.yAxis * lift
			local hit = blocker(look, pos, skip)
			if hit and i == 1 then
				blockedBy = hit.Instance:GetFullName()
			end
			if not hit then
				out = if i == 1 then want else CFrame.lookAt(pos, aim)
				return
			end
			if i == #LIFTS then
				local dir = want.Position - look
				local keep = math.max((hit.Position - look).Magnitude - 1.5, 4)
				out = CFrame.lookAt(look + dir.Unit * math.min(keep, dir.Magnitude), aim)
			end
		end
	end)
	return out
end

-- The player's own avatar stands on its mark behind its pets, between the camera and the fight: it is hidden for the
-- player (LocalTransparencyModifier, re-applied every frame because the default camera scripts reset it), others
-- still see it. Studio test 2026-10-14: the avatar filled the foreground.
local function hideSelf(on: boolean)
	local char = game:GetService("Players").LocalPlayer.Character
	if on and char then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then -- Decal covers Texture and the face; accessory handles are BaseParts
				d.LocalTransparencyModifier = 1
				hidden[d] = true
			end
		end
	end
	if not on then
		for d in hidden do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		table.clear(hidden)
	end
end

local function nudgeK(now: number): number
	local u = now - nudgeStart
	if u < 0 or u > NUDGE_OUT then
		return 0
	elseif u < NUDGE_IN then
		return u / NUDGE_IN
	end
	return 1 - (u - NUDGE_IN) / (NUDGE_OUT - NUDGE_IN)
end

-- Studio check log: with Workspace attribute FightCamLog = true, every 0.2 s of a fight prints one line
-- "FCLOG {json}" with the shot, the real camera (position, look, lens, screen size), whether anything else moved the
-- camera since FightCam last set it, and every drawn pet (Workspace.TowerView, client side: centre, size, screen point).
-- The first line of a fight ("Shot":"start") carries what the base view was fitted to.
local HttpService = game:GetService("HttpService")
local logAt = 0
local lastSet: CFrame? = nil
local moved = 0 -- frames since the last log line where the camera was not where FightCam left it
local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end
local function v3(v: Vector3): { number }
	return { r2(v.X), r2(v.Y), r2(v.Z) }
end
local function logLine(cam: Camera, kind: string, extra: { [string]: any }?)
	local pets = {}
	local drawn = Workspace:FindFirstChild("TowerView")
	if drawn then
		for _, m in drawn:GetChildren() do
			if m:IsA("Model") then
				local ok, cf, size = pcall(m.GetBoundingBox, m)
				if ok then
					local c, sz = (cf :: CFrame).Position, size :: Vector3
					local sp, on = cam:WorldToViewportPoint(c)
					local top = cam:WorldToViewportPoint(c + Vector3.new(0, sz.Y / 2, 0))
					local foot = cam:WorldToViewportPoint(c - Vector3.new(0, sz.Y / 2, 0))
					table.insert(pets, { N = m.Name, C = v3(c), S = v3(sz), X = r2(sp.X), Y = r2(sp.Y), Top = r2(top.Y), Foot = r2(foot.Y), On = on })
				end
			end
		end
	end
	local s = stage
	local line = {
		T = r2(os.clock() - startedAt), Shot = kind, Type = cam.CameraType.Name, Cam = v3(cam.CFrame.Position),
		Look = v3(cam.CFrame.LookVector), Up = v3(cam.CFrame.UpVector), Fov = r2(cam.FieldOfView), Vp = { cam.ViewportSize.X, cam.ViewportSize.Y },
		Moved = moved, Blocked = blockedBy, R = s and r2(s.R), H = s and r2(s.H), Pets = pets,
	}
	for k, v in (extra or {}) :: { [string]: any } do
		line[k] = v
	end
	moved = 0
	pcall(function()
		print("FCLOG " .. HttpService:JSONEncode(line))
	end)
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	if not active or not stage or not cam then
		return
	end
	local now = os.clock()
	if lastSet and (cam.CFrame.Position - lastSet.Position).Magnitude > 0.01 then
		moved += 1 -- something other than FightCam moved the camera since the last frame
	end
	local want: CFrame
	local ease = 4
	local sh = shot
	if sh and now < sh.Until then
		want = sh.Fn(now - sh.Started)
		ease = sh.Ease
	else
		if sh then
			backUntil = now + 0.5 -- a close-up just ended: swing back to the wide shot quickly (both teams in shot)
		end
		shot = nil
		if now < backUntil then
			ease = 12
		end
		if reduced() then
			want = Rules.still(stage)
		else
			want = base(math.max(now - baseFrom, 0))
			local k = nudgeK(now)
			local at = if k > 0 and nudgeAt then nudgeAt() else nil
			if at then
				want = Rules.nudge(want, stage, at, k)
				ease = 7
			end
		end
	end
	want = unblocked(want, if sh and sh.Focus and now < sh.Until then sh.Focus() else nil)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	cam.CFrame = cam.CFrame:Lerp(want, Rules.alpha(ease, dt))
	lastSet = cam.CFrame
	if Workspace:GetAttribute("FightCamLog") == true and now - logAt >= 0.2 then
		logAt = now
		local live = sh ~= nil and now < sh.Until
		logLine(cam, if live and sh then sh.Kind else "base", if live and sh and sh.Of then { Of = sh.Of } else nil)
	end
	hideSelf(true)
	-- the fight runs on a narrower lens (pets read big) and the hero shot narrows it more; FightFx's short lens
	-- kicks on hits still show (the lens eases back slowly)
	local lens = if sh and sh.Kind == "hero" and now < sh.Until then Rules.HERO_FOV else Rules.FIGHT_FOV
	heroLens = true
	cam.FieldOfView += (lens - cam.FieldOfView) * Rules.alpha(3, dt)
end

-- What the base view has to fit (FightCamRules.View): this screen's shape, how tall the drawn pets are (TowerView
-- draws them, client side, under Workspace.TowerView) and how many stand in each line.
local function viewOf(cam: Camera, units: { any }?): Rules.View
	local size = cam.ViewportSize
	local tall = 0
	local drawn = Workspace:FindFirstChild("TowerView")
	if drawn then
		for _, m in drawn:GetChildren() do
			if m:IsA("Model") then
				local ok, _, s = pcall(m.GetBoundingBox, m)
				if ok then
					tall = math.max(tall, (s :: Vector3).Y)
				end
			end
		end
	end
	local pets, foes = 0, 0
	for _, u in (units or {}) :: { any } do
		if u.Owner == 0 then
			foes += 1
		else
			pets += 1
		end
	end
	return {
		Aspect = if size.Y > 0 then size.X / size.Y else nil,
		Height = if tall > 0 then tall else nil,
		Pets = if pets > 0 then pets else nil,
		Foes = if foes > 0 then foes else nil,
	}
end

-- Starts directing for a fight seen from `origin` (the player's own view origin) with PvpConfig layout `layout`.
-- `intro` = the count-in is still running: open with the wide orbit. `units`: the fight's units (Start message), so
-- the base view fits every pet on this screen.
function FightCam.start(origin: CFrame, layout: any, intro: boolean?, introTime: number?, units: { any }?)
	FightCam.stop()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local view = viewOf(cam, units)
	stage = Rules.stage(origin, layout, view)
	lastSet = nil
	moved = 0
	baseFov = cam.FieldOfView
	-- FightCam owns the camera for the whole fight. Without this CameraMode takes a Scriptable camera back to Custom
	-- the moment it changes (its guard against a stuck camera), so the default camera, centred on the player's
	-- avatar behind its own pets, and FightCam fought over it every frame (Studio camera log 2026-10-15: both teams
	-- fully in shot in 3% of frames).
	CameraMode.cinematic(CINEMATIC, true)
	UI.holdNotices(true) -- toasts wait until the fight ends
	PopupGate.hold("Fight", true) -- and every other non-fight popup (the one gate)
	dimLights(true)
	active = true
	startedAt = os.clock()
	baseFrom = startedAt
	lastCut = -math.huge
	backUntil = 0
	nudgeAt = nil
	cam.CameraType = Enum.CameraType.Scriptable
	if Workspace:GetAttribute("FightCamLog") == true then
		local s = stage :: Rules.Stage
		logLine(cam, "start", {
			Origin = v3(origin.Position), OriginLook = v3(origin.LookVector), Layout = layout, View = view,
			Centre = v3(s.Centre), Back = v3(s.Back), Focus = v3(Rules.focus(s)),
		})
	end
	if intro and not reduced() then
		local s = stage :: Rules.Stage
		local len = math.max(introTime or 3, 1.5)
		baseFrom = startedAt + len
		local from = Rules.introAt(s, 0)
		cam.CFrame = from
		shot = { Kind = "intro", Started = os.clock(), Until = os.clock() + len, Ease = 10, Fn = function(t: number): CFrame
			return Rules.intro(s, math.clamp(t / len, 0, 1), base(t))
		end }
	else
		cam.CFrame = if reduced() then Rules.still(stage :: Rules.Stage) else base(0)
	end
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 2, step)
	-- the avatar stays hidden after every other render step (the default camera's transparency pass included) and
	-- after physics, so nothing that runs later in the frame can show it again
	RunService:BindToRenderStep(BIND_HIDE, Enum.RenderPriority.Last.Value, function()
		hideSelf(true)
	end)
	conn = RunService.Heartbeat:Connect(function()
		if active then
			hideSelf(true)
		end
	end)
end

-- A short cut to a pet (crit / SUPER hit): a side-on close-up, then back to the base view.
function FightCam.cut(kind: string, target: Model?, attacker: Model?)
	if not active or reduced() or not stage then
		return
	end
	local now = os.clock()
	local cur = shot
	if cur and (cur.Kind == "ko" or cur.Kind == "hero" or cur.Kind == "intro") and now < cur.Until then
		return -- the big shots are never cut away from
	end
	local gap = if kind == "special" or kind == "charge" then 0.8 else Rules.CUT_GAP
	if now - lastCut < gap then
		return
	end
	local at = centreOf(target)
	if not at then
		return
	end
	lastCut = now
	local from = centreOf(attacker)
	local s = stage :: Rules.Stage
	local size = sizeOf(target :: Model)
	local len = if kind == "special" then 1.4 elseif kind == "charge" then 1.1 else 0.9
	shot = { Kind = kind, Of = (target :: Model).Name, Started = now, Until = now + len, Ease = 9, Fn = function(t: number): CFrame
		local a = centreOf(target) or at
		if kind == "charge" then
			return Rules.shoulder(s, a, from or a)
		end
		return Rules.closeUp(s, a, from, size, t)
	end, Focus = function(): Vector3
		return centreOf(target) or at
	end }
end

-- K.O.: orbit the pet that fainted, then the winner's hero shot (holds `hold` seconds, or until stop()).
function FightCam.ko(fainted: Model?, winner: Model?, hold: number?)
	if not active or not stage then
		return
	end
	local s = stage :: Rules.Stage
	local now = os.clock()
	local at = centreOf(fainted)
	if reduced() then
		return
	end
	local orbit = if at then 1.5 else 0
	if at then
		local size = sizeOf(fainted :: Model)
		shot = { Kind = "ko", Of = (fainted :: Model).Name, Started = now, Until = now + orbit, Ease = 7, Fn = function(t: number): CFrame
			return Rules.orbit(s, at :: Vector3, size, t)
		end, Focus = function(): Vector3
			return at :: Vector3
		end }
	end
	if winner then
		task.delay(orbit, function()
			if active then
				FightCam.hero(winner, hold)
			end
		end)
	end
end

-- A low push-in on `model` that holds `hold` seconds (default: until stop()).
function FightCam.hero(model: Model, hold: number?)
	if not active or not stage then
		return
	end
	local s = stage :: Rules.Stage
	local now = os.clock()
	local size = sizeOf(model)
	local last = centreOf(model) or s.Centre
	shot = { Kind = "hero", Of = model.Name, Started = now, Until = now + (hold or 1e6), Ease = if reduced() then 20 else 3.5, Fn = function(t: number): CFrame
		last = centreOf(model) or last
		return Rules.hero(s, last, size, if reduced() then 1 else t)
	end, Focus = function(): Vector3
		return last
	end }
end

-- Every hit: the base view leans towards the pet that was hit and pushes in a little, then eases back. (Crits and
-- SUPER hits also cut to a close-up: FightCam.cut.)
function FightCam.nudge(target: Model?)
	if not active or reduced() or not target then
		return
	end
	local last = centreOf(target)
	if not last then
		return
	end
	nudgeAt = function(): Vector3?
		last = centreOf(target) or last
		return last
	end
	nudgeStart = os.clock()
end

function FightCam.active(): boolean
	return active
end

-- Hands the camera back to the player.
function FightCam.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep(BIND)
	end)
	pcall(function()
		RunService:UnbindFromRenderStep(BIND_HIDE)
	end)
	local was = active
	active = false
	if was then
		CameraMode.cinematic(CINEMATIC, false)
		UI.holdNotices(false)
		PopupGate.hold("Fight", false)
	end
	shot = nil
	stage = nil
	local cam = Workspace.CurrentCamera
	if was and cam then
		cam.CameraType = Enum.CameraType.Custom
		if baseFov and heroLens then
			cam.FieldOfView = baseFov
		end
	end
	if was then
		dimLights(false)
	end
	baseFov = nil
	heroLens = false
	nudgeAt = nil
	hideSelf(false)
end

return FightCam
