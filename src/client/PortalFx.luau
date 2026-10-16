--!strict
-- Race portal moment (client only, cosmetic, nothing is sent anywhere): when an avatar steps onto a hunt portal pad
-- (attribute HuntPortal = true: ParkBuilder's QueuePad1..4 or a MapHooks pad), the pad flashes once and a burst of
-- sparkles is pulled in toward its middle. Purely a picture of the step; the server alone decides the queue join
-- (PartyService.onPortalTouch). The local player and nearby players only, a short cooldown per pad.
-- Low effects: flash only, no sparkles. Reduce Motion: a softer flash that does not grow, no sparkles.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local PortalFx = {}

local NEAR = 70 -- studs from the camera to the pad
local TICK = 0.12
local COOLDOWN = 0.8 -- per pad
local ABOVE = 5 -- studs above the pad surface that still count as "on" it
local SPARK = Color3.fromRGB(255, 244, 200)

local pads: { BasePart } = {}
local inside: { [BasePart]: { [Player]: boolean } } = {}
local lastFx: { [BasePart]: number } = {}
local fxFolder: Folder? = nil

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "CT_Rocks_PortalFx"
	nf.Parent = Workspace
	fxFolder = nf
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

-- The pad's local axis that points most nearly up (a flat cylinder pad lies on its side: X is up).
local function upAxis(p: BasePart): (Vector3, number)
	local up = p.CFrame:VectorToObjectSpace(Vector3.yAxis)
	local ax, ay, az = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
	if ax >= ay and ax >= az then
		return Vector3.xAxis * math.sign(up.X), p.Size.X
	elseif ay >= az then
		return Vector3.yAxis * math.sign(up.Y), p.Size.Y
	end
	return Vector3.zAxis * math.sign(up.Z), p.Size.Z
end

local function isOn(p: BasePart, pos: Vector3): boolean
	local lp = p.CFrame:PointToObjectSpace(pos)
	local axis, thick = upAxis(p)
	local h = lp:Dot(axis) -- height above the pad's middle
	local flat = lp - axis * h
	local half = p.Size * 0.5
	local flatHalf = half - Vector3.new(math.abs(axis.X) * half.X, math.abs(axis.Y) * half.Y, math.abs(axis.Z) * half.Z)
	local radius = math.max(flatHalf.X, flatHalf.Y, flatHalf.Z)
	return h > -thick * 0.5 - 0.5 and h < thick * 0.5 + ABOVE and flat.Magnitude <= radius + 0.5
end

local function burst(p: BasePart)
	local s = settings()
	local low, reduced = s.LowEffects == true, s.ReducedMotion == true
	local _, thick = upAxis(p)
	local top = p.Position + Vector3.yAxis * (thick * 0.5 + 0.05)
	local d = math.max(p.Size.X, p.Size.Y, p.Size.Z)
	-- flash: a bright disc over the pad that swells a little and fades
	local disc = Instance.new("Part")
	disc.Name = "PortalFlash"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = p.Color:Lerp(Color3.new(1, 1, 1), 0.55)
	disc.Size = Vector3.new(0.12, d, d)
	disc.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90))
	disc.Transparency = if reduced then 0.55 else 0.15
	deco(disc)
	disc.Parent = folder()
	local grow = if reduced then d else d * 1.3
	TweenService:Create(disc, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, grow, grow), Transparency = 1 }):Play()
	Debris:AddItem(disc, 0.5)
	if low or reduced then
		return
	end
	-- sparkles: born on a sphere around the pad and pulled in to its middle
	local life = 0.55
	local r = d * 0.6
	local host = Instance.new("Part")
	host.Name = "PortalPull"
	host.Shape = Enum.PartType.Ball
	host.Size = Vector3.one * r * 2
	host.Transparency = 1
	host.CFrame = CFrame.new(top + Vector3.yAxis * 1.5)
	deco(host)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.Lifetime = NumberRange.new(life)
	e.Speed = NumberRange.new(r / life * 0.9, r / life)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 0.4) })
	e.Color = ColorSequence.new(SPARK, p.Color:Lerp(SPARK, 0.4))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = host
	host.Parent = folder()
	e:Emit(22)
	Debris:AddItem(host, life + 0.3)
end

local function addPad(d: Instance)
	if not d:IsA("BasePart") or d:GetAttribute("HuntPortal") ~= true or table.find(pads, d) then
		return
	end
	local parent = d.Parent
	if parent and parent:GetAttribute("HuntPortal") == true then
		return -- MapHooks' touch volume over a pad: the pad itself already counts
	end
	table.insert(pads, d)
	inside[d] = {}
end

local function step()
	local cam = Workspace.CurrentCamera
	if not cam or State.Match ~= nil then
		return
	end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	for i = #pads, 1, -1 do
		local p = pads[i]
		if not p:IsDescendantOf(Workspace) then
			table.remove(pads, i)
			inside[p] = nil
			lastFx[p] = nil
		elseif (p.Position - camPos).Magnitude < NEAR then
			local on = inside[p]
			for _, pl in Players:GetPlayers() do
				local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				local nowOn = root ~= nil and root:IsA("BasePart") and isOn(p, root.Position)
				if nowOn and not on[pl] and now - (lastFx[p] or 0) >= COOLDOWN then
					lastFx[p] = now
					burst(p)
				end
				on[pl] = nowOn
			end
		end
	end
end

-- The lobby's TowerPortal (attribute TowerPortal = true): a plain neon slab in the door is dressed as a portal swirl on
-- this client. ForceField material draws its own moving swirl (no image ids), the slab stays where it is (the server's
-- touch part is not moved), and soft sparkles drift in toward the middle. Low effects: the swirl only.
local dressed: { [BasePart]: boolean } = {}
local function dressTower(d: Instance)
	if not d:IsA("BasePart") or d:GetAttribute("TowerPortal") ~= true or dressed[d] then
		return
	end
	if d.Transparency >= 0.95 then
		return -- an invisible touch volume: the map's own doorway shows the look
	end
	dressed[d] = true
	local tint = d.Color
	d.Material = Enum.Material.ForceField
	d.Color = tint:Lerp(Color3.fromRGB(150, 110, 255), 0.35) -- a little violet in the cyan, like the hunt portals
	d.Transparency = 0
	d.CastShadow = false
	-- a solid pale core inside the shimmer (ForceField alone read as nearly clear from the path): a client-only copy of
	-- the slab, a bit smaller and thinner, so the swirl draws over it
	local ok, core = pcall(function(): BasePart
		return d:Clone()
	end)
	if ok and core then
		for _, c in core:GetChildren() do
			c:Destroy()
		end
		local sz = d.Size
		local thin = math.min(sz.X, sz.Y, sz.Z)
		core.Name = "CT_PortalCore"
		core.Size = Vector3.new(
			if sz.X == thin then sz.X * 0.5 else sz.X * 0.96,
			if sz.Y == thin then sz.Y * 0.5 else sz.Y * 0.96,
			if sz.Z == thin then sz.Z * 0.5 else sz.Z * 0.96
		)
		core.CFrame = d.CFrame
		core.Material = Enum.Material.SmoothPlastic -- Neon blew out to a flat white oval
		core.Color = Color3.fromRGB(96, 92, 210) -- deep blue-violet
		core.Transparency = 0.35
		core:SetAttribute("TowerPortal", nil)
		deco(core)
		core.Parent = folder()
		-- the swirl: two rings of short glowing dashes in the doorway's plane, turning opposite ways
		local thinAxis = if sz.X == thin then "X" elseif sz.Y == thin then "Y" else "Z"
		local plane = d.CFrame * (if thinAxis == "X" then CFrame.Angles(0, math.pi / 2, 0) elseif thinAxis == "Y" then CFrame.Angles(math.pi / 2, 0, 0) else CFrame.identity)
		local w = if thinAxis == "X" then sz.Z else sz.X
		local h = if thinAxis == "Y" then sz.Z else sz.Y
		local r = 0.4 * math.min(w, h)
		local dashes: { { Part: Part, R: number, A: number, Dir: number } } = {}
		for ring = 1, 2 do
			local n = if ring == 1 then 12 else 7
			local rr = if ring == 1 then r else r * 0.55
			for i = 1, n do
				local dash = Instance.new("Part")
				dash.Name = "CT_PortalDash"
				dash.Size = Vector3.new(rr * 0.32, math.max(0.18, r * 0.05), 0.15)
				dash.Material = Enum.Material.Neon
				dash.Color = if ring == 1 then Color3.fromRGB(190, 150, 255) else Color3.fromRGB(150, 220, 255)
				dash.Transparency = 0.15
				deco(dash)
				dash.Parent = folder()
				table.insert(dashes, { Part = dash, R = rr, A = (i - 1) / n * math.pi * 2, Dir = if ring == 1 then 1 else -1.6 })
			end
		end
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			if not d.Parent then
				for _, x in dashes do
					x.Part:Destroy()
				end
				core:Destroy()
				if conn then
					conn:Disconnect()
				end
				return
			end
			local t = os.clock() * 0.9
			for _, x in dashes do
				local a = x.A + t * x.Dir
				-- tangent dashes, each a little in front of the slab so the shimmer does not hide them
				x.Part.CFrame = plane * CFrame.new(math.cos(a) * x.R, math.sin(a) * x.R, -thin * 0.5 - 0.1) * CFrame.Angles(0, 0, a + math.pi / 2)
			end
		end)
	end
	if settings().LowEffects == true then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "CT_PortalSwirl"
	a.Parent = d
	local e = Instance.new("ParticleEmitter")
	e.Name = "CT_PortalSparkle"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.4))
	e.LightEmission = 0.8
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1, 1.6)
	e.Rate = 28
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Drag = 1
	e.Parent = a
end

local started = false
function PortalFx.start()
	if started then
		return
	end
	started = true
	for _, d in Workspace:GetDescendants() do
		addPad(d)
		dressTower(d)
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d.Name == "TowerPortal" or d:GetAttribute("TowerPortal") == true then
			task.defer(dressTower, d) -- MapHooks sets the attribute right after the part appears
		end
		if d:GetAttribute("HuntPortal") == true then
			addPad(d)
		elseif d:IsA("BasePart") and (string.sub(d.Name, 1, 8) == "QueuePad" or d.Name == "Pad") then
			task.defer(addPad, d) -- MapHooks sets the attribute right after the pad appears
		end
	end)
	Players.PlayerRemoving:Connect(function(pl)
		for _, on in inside do
			on[pl] = nil
		end
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

return PortalFx
