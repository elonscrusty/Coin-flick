--!strict
-- Feet dust for avatars (client only, cosmetic, nothing is sent anywhere):
--   * running on the ground kicks up small puffs behind the feet (throttled per player)
--   * landing a jump (a real fall, not a step down) leaves a soft dust ring that swells and fades
-- The local player and nearby players only (a few at a time). The dust takes a pale tint of the ground it rises from;
-- water is left to WorldFx's ripples and splashes. One shared emitter (world-space particles, Emit only) and a small
-- pool of ring parts: nothing grows with player count. Low effects: off. Reduce Motion: fewer puffs, smaller ring.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local PlayerDust = {}

local NEAR = 50 -- studs from the camera
local MAX_PLAYERS = 6 -- avatars checked per tick (the local player first)
local TICK = 0.1
local PUFF_EVERY = 0.2 -- per player
local RUN_SPEED = 11 -- horizontal studs/s that counts as running (default walk speed is 16)
local LAND_SPEED = 28 -- downward studs/s before touching down that counts as a landing
local MAX_RINGS = 4
local PALE = Color3.fromRGB(236, 228, 214)

type Track = { Grounded: boolean, MinVy: number, NextPuff: number, Seen: number }
local tracks: { [Player]: Track } = {}

local fxFolder: Folder? = nil
local host: BasePart? = nil
local emitter: ParticleEmitter? = nil
local freeRings: { BasePart } = {}
local liveRings = 0

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "CT_Rocks_PlayerDust"
	nf.Parent = Workspace
	fxFolder = nf
	host, emitter = nil, nil
	table.clear(freeRings)
	liveRings = 0
	return nf
end

local function deco(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("CameraIgnore", true)
end

local function dustEmitter(): (BasePart, ParticleEmitter)
	local f = folder()
	local h, e = host, emitter
	if h and e and h.Parent == f then
		return h, e
	end
	local p = Instance.new("Part")
	p.Name = "DustHost"
	p.Size = Vector3.new(0.6, 0.2, 0.6)
	p.Transparency = 1
	deco(p)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Dust"
	pe.Enabled = false -- Emit() only
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Lifetime = NumberRange.new(0.35, 0.6)
	pe.Speed = NumberRange.new(1.2, 2.6)
	pe.SpreadAngle = Vector2.new(55, 55)
	pe.Acceleration = Vector3.new(0, -1.5, 0)
	pe.Drag = 3
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	pe.RotSpeed = NumberRange.new(-60, 60)
	pe.Rotation = NumberRange.new(0, 360)
	pe.LightInfluence = 1
	pe.Parent = p
	p.Parent = f
	host, emitter = p, pe
	return p, pe
end

local function tint(c: Color3): Color3
	return c:Lerp(PALE, 0.55)
end

local function puff(pos: Vector3, colour: Color3, count: number, speed: NumberRange?)
	local h, e = dustEmitter()
	h.CFrame = CFrame.new(pos)
	e.Color = ColorSequence.new(tint(colour))
	e.Speed = speed or NumberRange.new(1.2, 2.6)
	e:Emit(count)
end

local function ring(pos: Vector3, colour: Color3, size: number)
	if liveRings >= MAX_RINGS then
		return
	end
	liveRings += 1
	local p = table.remove(freeRings)
	if not p then
		local np = Instance.new("Part")
		np.Name = "LandRing"
		np.Shape = Enum.PartType.Cylinder
		np.Material = Enum.Material.SmoothPlastic
		deco(np)
		p = np
	end
	local part = p :: BasePart
	part.Size = Vector3.new(0.05, 1.4, 1.4)
	part.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = tint(colour)
	part.Transparency = 0.35
	part.Parent = folder()
	local tw = TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, size, size), Transparency = 1 })
	tw.Completed:Once(function()
		liveRings = math.max(0, liveRings - 1)
		if part.Parent and #freeRings < MAX_RINGS then
			part.Parent = nil
			table.insert(freeRings, part)
		else
			part:Destroy()
		end
	end)
	tw:Play()
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function stepPlayer(pl: Player, root: BasePart, hum: Humanoid, now: number, reduced: boolean)
	local old = tracks[pl]
	local tr: Track = if old and now - old.Seen <= 0.5 then old else { Grounded = true, MinVy = 0, NextPuff = 0, Seen = now }
	tracks[pl] = tr -- new, or out of range for a while: start fresh so an old fall never rings late
	tr.Seen = now
	local v = root.AssemblyLinearVelocity
	local reach = root.Size.Y * 0.5 + hum.HipHeight + 0.8
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	local water = hit ~= nil and (hit.Material == Enum.Material.Water or string.find(string.lower(hit.Instance.Name), "water", 1, true) ~= nil)
	local grounded = hit ~= nil and hum:GetState() ~= Enum.HumanoidStateType.Swimming
	if not grounded then
		tr.Grounded = false
		tr.MinVy = math.min(tr.MinVy, v.Y)
		return
	end
	local h = hit :: RaycastResult
	local colour = if h.Instance:IsA("Terrain") then Workspace.Terrain:GetMaterialColor(h.Material) else h.Instance.Color
	if not tr.Grounded then
		-- just touched down: a ring for a real fall
		if tr.MinVy < -LAND_SPEED and not water then
			ring(h.Position, colour, if reduced then 5 else 7.5)
			puff(h.Position, colour, if reduced then 3 else 6, NumberRange.new(3, 5))
			tr.NextPuff = now + PUFF_EVERY
		end
		tr.Grounded = true
		tr.MinVy = 0
	end
	local flat = Vector3.new(v.X, 0, v.Z)
	if not water and flat.Magnitude > RUN_SPEED and now >= tr.NextPuff then
		tr.NextPuff = now + PUFF_EVERY * (if reduced then 2 else 1)
		puff(h.Position - flat.Unit * 0.6, colour, if reduced then 1 else 2)
	end
end

local function step()
	local s = settings()
	if s.LowEffects == true then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local reduced = s.ReducedMotion == true
	local now = os.clock()
	local camPos = cam.CFrame.Position
	local list: { Player } = { Players.LocalPlayer }
	for _, pl in Players:GetPlayers() do
		if pl ~= Players.LocalPlayer and #list < MAX_PLAYERS then
			local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") and (r.Position - camPos).Magnitude < NEAR then
				table.insert(list, pl)
			end
		end
	end
	local chars: { Instance } = { folder() }
	for _, pl in list do
		if pl.Character then
			table.insert(chars, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = chars
	for _, pl in list do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 then
			stepPlayer(pl, root, hum, now, reduced)
		end
	end
end

local started = false
function PlayerDust.start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(pl)
		tracks[pl] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= TICK then
			acc = 0
			step()
		end
	end)
end

return PlayerDust
