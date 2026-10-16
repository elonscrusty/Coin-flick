--!strict
-- Lobby ambience (Master Prompt 8 sections 3-5, 20): a little cheap, purely visual life in the public lobby.
--   * trees sway gently: the canopy parts (Leaf / LeafDark / Leaves) of models the server marked with the
--     attribute Sway rock a degree or two about their SwayPivot (LobbyBuilder / KitPlace.sway);
--   * a waterfall, when the lobby has one (CT_Rocks_Waterfall): its streaks slide down the sheet, the foam breathes;
--   * a few butterflies flutter over the plaza ferns, three birds circle high over the north cliffs;
--   * (plot pets no longer wander: they stand on fixed yard spots, GalleryService, owner 2026-10-14)
--   * fireflies drift along the park edges (Config.Lodge box, inset): a few invisible emitter boxes, soft warm dots;
--     on only while the camera is in the lobby, off with Reduce Motion or Low effects.
-- (The park: src/server/ParkBuilder.luau, layout numbers src/shared/ParkConfig.luau.)
-- Client only (nothing replicates, nothing is authoritative), anchored, non-colliding, CanQuery off,
-- CameraIgnore. One Heartbeat step at 30 Hz, and only while the camera is in the lobby (a hunt arena is far
-- away). Reduced Motion: nothing moves (trees and water at rest, no critters). Low effects: no
-- critters, only every other tree sways. Bounded: at most 40 trees, 6 butterflies, 3 birds,
-- the waterfall's own parts.


local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)
local MapNames = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("MapNames"))
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local LobbyAmbience = {}

local RATE = 1 / 30
local LOBBY_CENTRE = Vector3.new(0, 0, 0)
local NEAR = 320 -- camera within this of the lobby centre = in the lobby
local MAX_TREES = 40
local BUTTERFLIES = 6
local BIRDS = 3
local CANOPY = { Leaf = true, LeafDark = true, Leaves = true }
-- The owner keeps lobby props still (only the portal and water move): trees are collected for their drifting
-- leaves but no longer sway.
local TREE_SWAY = false

type Tree = { Parts: { BasePart }, Base: { CFrame }, Pivot: Vector3, Phase: number, Amp: number, Axis: Vector3 }
type Critter = { Parts: { BasePart }, Kind: string, Home: Vector3, Phase: number, Speed: number, Radius: number }

local trees: { Tree } = {}
local critters: { Critter } = {}
local streaks: { BasePart } = {}
local streakBase: { [BasePart]: CFrame } = {}
local foam: { BasePart } = {}
local folder: Folder? = nil
local acc = 0
local t0 = os.clock()
local atRest = true
local started = false
local parkLobby: Instance? = nil -- the procedural park being animated (collected again when it changes)
local parkDirty = false
local lastCollect = 0

-- the Pet Tower's glowing aura (ParkBuilder buildTower, Blender model TowerAura): looked up every 2 s until found;
-- its glow breathes (a shell with an AuraSpin attribute also turns about the temple's centre)
local towerAura: Model? = nil
local auraShells: { { Part: BasePart, Home: CFrame, Base: number, Dir: number } } = {}
local lastAuraLook = -10

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function decorative(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("CameraIgnore", true)
end

local function mk(parent: Instance, name: string, size: Vector3, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	decorative(p)
	p.Parent = parent
	return p
end

-- Rest CFrame of every animated part, taken the first time it is seen (a streamed-in part arrives at rest; a part
-- already being swayed keeps its first base, so collecting again never drifts).
local baseOf: { [BasePart]: CFrame } = {}
local function baseFor(p: BasePart): CFrame
	local b = baseOf[p]
	if not b then
		b = p.CFrame
		baseOf[p] = b
	end
	return b
end

-- Collect what the server built. Runs again when the lobby changes (StreamingEnabled streams trees and the
-- waterfall in and out by distance), so late parts join and removed ones leave.
local function collect(lobby: Instance)
	table.clear(trees)
	table.clear(streaks)
	table.clear(streakBase)
	table.clear(foam)
	for p in baseOf do
		if not p.Parent then
			baseOf[p] = nil
		end
	end
	local seed = 0
	for _, d in lobby:GetDescendants() do
		if #trees < MAX_TREES and d:IsA("Model") and d:GetAttribute("Sway") == true then
			local pivot = d:GetAttribute("SwayPivot")
			local parts, base = {}, {}
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") and CANOPY[p.Name] then
					table.insert(parts, p)
					table.insert(base, baseFor(p))
				end
			end
			if #parts > 0 and typeof(pivot) == "Vector3" then
				seed += 1
				local a = seed * 2.399 -- golden angle: every tree leans a slightly different way
				table.insert(trees, {
					Parts = parts,
					Base = base,
					Pivot = pivot,
					Phase = seed * 1.37,
					Amp = math.rad(1.1 + (seed % 3) * 0.25),
					Axis = Vector3.new(math.cos(a), 0, math.sin(a)),
				})
			end
		end
	end
	local fall = lobby:FindFirstChild("CT_Rocks_Waterfall")
	if fall then
		for _, p in fall:GetChildren() do
			if p:IsA("BasePart") and p.Name == "FallStreak" then
				table.insert(streaks, p)
				streakBase[p] = baseFor(p)
			elseif p:IsA("BasePart") and p.Name == "Foam" then
				table.insert(foam, p)
			end
		end
	end
end

-- Butterflies over the planting beds, birds circling high over the north cliffs.
local function spawnCritters(lobby: Instance)
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_LobbyAmbience"
	f.Parent = Workspace
	folder = f
	-- butterflies flutter over the clearing's corner bushes and the plaza's back corners (ParkBuilder)
	local _ = lobby
	local homes: { Vector3 } = {
		Vector3.new(-32, 0.4, -32), Vector3.new(32, 0.4, 30), Vector3.new(-33, 0.4, 28), Vector3.new(30, 0.4, -32),
		Vector3.new(-34, 0.4, 126), Vector3.new(34, 0.4, 126),
	}
	local wingColours = { Color3.fromRGB(240, 226, 170), Color3.fromRGB(236, 236, 228), Color3.fromRGB(198, 214, 170) }
	for i = 1, BUTTERFLIES do
		local col = wingColours[(i - 1) % #wingColours + 1]
		local parts = {
			mk(f, "Wing", Vector3.new(0.32, 0.03, 0.26), col),
			mk(f, "Wing", Vector3.new(0.32, 0.03, 0.26), col),
			mk(f, "Body", Vector3.new(0.06, 0.06, 0.24), Color3.fromRGB(70, 64, 58)),
		}
		table.insert(critters, { Parts = parts, Kind = "Butterfly", Home = homes[(i - 1) % #homes + 1], Phase = i * 1.9, Speed = 0.5 + (i % 3) * 0.12, Radius = 1.6 + (i % 2) * 0.8 })
	end
	for i = 1, BIRDS do
		local col = Color3.fromRGB(62, 64, 70)
		local parts = {
			mk(f, "Wing", Vector3.new(1.1, 0.06, 0.4), col),
			mk(f, "Wing", Vector3.new(1.1, 0.06, 0.4), col),
			mk(f, "Body", Vector3.new(0.22, 0.2, 0.7), col),
		}
		table.insert(critters, { Parts = parts, Kind = "Bird", Home = Vector3.new(-40 + i * 20, 46 + i * 5, -70 + i * 40), Phase = i * 2.1, Speed = 0.14 + i * 0.02, Radius = 16 + i * 5 })
	end
end

local function hideCritters(hidden: boolean)
	for _, c in critters do
		for _, p in c.Parts do
			p.Transparency = if hidden then 1 else 0
		end
	end
end

local function rest()
	if atRest then
		return
	end
	atRest = true
	for _, tr in trees do
		for i, p in tr.Parts do
			if p.Parent then
				p.CFrame = tr.Base[i]
			end
		end
	end
	for p, cf in streakBase do
		if p.Parent then
			p.CFrame = cf
		end
	end
	hideCritters(true)
end

local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}

-- Fireflies at the park edges ----------------------------------------------------------------------------------

local FIREFLY_INSET = 12 -- studs inside the park boundary
local fireflies: { ParticleEmitter } = {}
local firefliesOn = false

local function buildFireflies()
	if #fireflies > 0 then
		return
	end
	local L = Config.Lodge
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_Fireflies"
	f.Parent = Workspace
	local x0, x1 = L.MinX + FIREFLY_INSET, L.MaxX - FIREFLY_INSET
	local z0, z1 = L.MinZ + FIREFLY_INSET, L.MaxZ - FIREFLY_INSET
	local w, d = x1 - x0, z1 - z0
	-- two boxes per side, low over the ground (each box emits over its whole volume)
	local boxes = {
		{ Vector3.new(x0 + w * 0.25, 2.5, z0), Vector3.new(w * 0.4, 3, 6) },
		{ Vector3.new(x0 + w * 0.75, 2.5, z0), Vector3.new(w * 0.4, 3, 6) },
		{ Vector3.new(x0 + w * 0.25, 2.5, z1), Vector3.new(w * 0.4, 3, 6) },
		{ Vector3.new(x0 + w * 0.75, 2.5, z1), Vector3.new(w * 0.4, 3, 6) },
		{ Vector3.new(x0, 2.5, z0 + d * 0.25), Vector3.new(6, 3, d * 0.4) },
		{ Vector3.new(x0, 2.5, z0 + d * 0.75), Vector3.new(6, 3, d * 0.4) },
		{ Vector3.new(x1, 2.5, z0 + d * 0.25), Vector3.new(6, 3, d * 0.4) },
		{ Vector3.new(x1, 2.5, z0 + d * 0.75), Vector3.new(6, 3, d * 0.4) },
	}
	for i, b in boxes do
		local p = Instance.new("Part")
		p.Name = "FireflyBox"
		p.Size = b[2]
		p.CFrame = CFrame.new(b[1] + Vector3.new(0, Config.Lodge.FloorY, 0))
		p.Transparency = 1
		decorative(p)
		p.Parent = f
		local e = Instance.new("ParticleEmitter")
		e.Name = "Fireflies"
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 1.2
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(0.2, 0.7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 0.08, 0)
		e.RotSpeed = NumberRange.new(-20, 20)
		e.Size = NumberSequence.new(0.22)
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.2),
			NumberSequenceKeypoint.new(0.35, 0.7),
			NumberSequenceKeypoint.new(0.55, 0.15),
			NumberSequenceKeypoint.new(0.8, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Color = ColorSequence.new(if i % 2 == 0 then Color3.fromRGB(255, 236, 140) else Color3.fromRGB(214, 255, 150))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Enabled = false
		e.Parent = p
		table.insert(fireflies, e)
	end
end

local function setFireflies(on: boolean)
	if on == firefliesOn then
		return
	end
	firefliesOn = on
	if on then
		buildFireflies()
	end
	for _, e in fireflies do
		e.Enabled = on
		if not on then
			e:Clear()
		end
	end
end

-- Drifting leaves near a few trees (tiny counts; off with Low effects / Reduced Motion) ---------------------------

local LEAF_TREES = 4
local leafEmitters: { ParticleEmitter } = {}

local function setLeaves(on: boolean)
	for i = #leafEmitters, 1, -1 do
		if not leafEmitters[i].Parent then
			table.remove(leafEmitters, i) -- streamed out
		end
	end
	if on and #leafEmitters < LEAF_TREES then
		for _, tr in trees do
			local part = tr.Parts[1]
			if part and part.Parent and not part:FindFirstChild("DriftLeaves") then
				local e = Instance.new("ParticleEmitter")
				e.Name = "DriftLeaves"
				e.Rate = 0.6
				e.Lifetime = NumberRange.new(6, 9)
				e.Speed = NumberRange.new(0.3, 0.8)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Acceleration = Vector3.new(0.4, -0.7, 0.2)
				e.RotSpeed = NumberRange.new(-60, 60)
				e.Size = NumberSequence.new(0.35)
				e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(0.85, 0.3), NumberSequenceKeypoint.new(1, 1) })
				-- soft green to pale gold, unlit: lit by the warm lobby light they read as red specks (video 2026-10-13)
				e.Color = ColorSequence.new(Color3.fromRGB(168, 214, 110), Color3.fromRGB(236, 214, 120))
				e.LightInfluence = 0
				e.Parent = part
				table.insert(leafEmitters, e)
				if #leafEmitters >= LEAF_TREES then
					break
				end
			end
		end
	end
	for _, e in leafEmitters do
		e.Enabled = on
		if not on then
			e:Clear()
		end
	end
end

-- Own plot: a gold outline on its yard floor (local Highlight, only this player sees it) --------------------------

local plotLight: Highlight? = nil
local function updatePlotOutline()
	local idx = Players.LocalPlayer:GetAttribute("Alcove")
	local a = if type(idx) == "number" then Workspace:FindFirstChild(MapNames.plot(idx), true) else nil
	local floor = a and a:FindFirstChild(MapNames.PlotFloor, true)
	if not (floor and floor:IsA("BasePart")) then
		if plotLight then
			plotLight.Adornee = nil
		end
		return
	end
	if not plotLight then
		local h = Instance.new("Highlight")
		h.Name = "CT_Rocks_OwnPlotOutline"
		h.FillTransparency = 1
		h.OutlineColor = Color3.fromRGB(255, 205, 70)
		h.OutlineTransparency = 0.25
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = Workspace
		plotLight = h
	end
	if (plotLight :: Highlight).Adornee ~= floor then
		(plotLight :: Highlight).Adornee = floor
	end
end

local function step(dt: number)
	acc += dt
	if acc < RATE then
		return
	end
	acc = 0
	local cam = Workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - LOBBY_CENTRE).Magnitude > NEAR then
		setFireflies(false)
		setLeaves(false)
		return -- in a hunt (the arenas are far from the lobby): nothing to update
	end
	local s = settings()
	setFireflies(s.ReducedMotion ~= true and s.LowEffects ~= true)
	setLeaves(s.ReducedMotion ~= true and s.LowEffects ~= true)
	-- Pet Tower aura: a slow breath of the glow (held steady with Reduced Motion)
	if not (towerAura and towerAura.Parent) and os.clock() - lastAuraLook >= 2 then
		lastAuraLook = os.clock()
		local found = parkLobby and parkLobby:FindFirstChild("TowerAura", true)
		towerAura = if found and found:IsA("Model") then found else nil
		table.clear(auraShells)
		if towerAura then
			for _, d in towerAura:GetDescendants() do
				if d:IsA("BasePart") then
					local base = d:GetAttribute("AuraBase")
					local spin = d:GetAttribute("AuraSpin")
					table.insert(auraShells, { Part = d, Home = d.CFrame, Base = if type(base) == "number" then base else d.Transparency, Dir = if type(spin) == "number" then spin else 0 })
				end
			end
		end
	end
	if towerAura and towerAura.Parent then
		local still = s.ReducedMotion == true
		local now = os.clock()
		local centre = towerAura:GetAttribute("AuraCentre")
		for _, sh in auraShells do
			-- (transparency is left alone: changing it every frame makes see-through layers flicker)
			if sh.Dir ~= 0 and not still and typeof(centre) == "Vector3" then
				local axis = Vector3.new(centre.X, sh.Home.Position.Y, centre.Z)
				local spin = CFrame.new(axis) * CFrame.Angles(0, now * 0.25 * sh.Dir, 0) * CFrame.new(-axis)
				sh.Part.CFrame = spin * sh.Home
			end
		end
	end
	if s.ReducedMotion == true then
		rest()
		return
	end
	local lobby = parkLobby
	if parkDirty and lobby and os.clock() - lastCollect >= 2 then
		parkDirty = false
		lastCollect = os.clock()
		collect(lobby)
	end
	local low = s.LowEffects == true
	if atRest then
		atRest = false
		hideCritters(low)
	end
	local t = os.clock() - t0
	table.clear(moveParts)
	table.clear(moveCFs)
	-- trees: a slow sway plus a faster flutter, about the pivot low on the trunk
	for k, tr in trees do
		if not TREE_SWAY then
			break
		end
		if low and k % 2 == 0 then
			continue
		end
		local a = math.sin(t * 0.9 + tr.Phase) * tr.Amp + math.sin(t * 2.3 + tr.Phase * 1.7) * tr.Amp * 0.3
		local rot = CFrame.new(tr.Pivot) * CFrame.fromAxisAngle(tr.Axis, a) * CFrame.new(-tr.Pivot)
		for i, p in tr.Parts do
			if p.Parent then -- streamed out since the last collect
				table.insert(moveParts, p)
				table.insert(moveCFs, rot * tr.Base[i])
			end
		end
	end
	-- waterfall streaks slide down the sheet and wrap; foam breathes
	for _, p in streaks do
		local base = streakBase[p]
		local top = (p:GetAttribute("Top") or 24) :: number
		local phase = (p:GetAttribute("Phase") or 0) :: number
		local y = top - ((t * 7 + phase * top) % top) -- the fall stands on the ground (y 0 at its foot)
		if p.Parent then
			table.insert(moveParts, p)
			table.insert(moveCFs, CFrame.new(base.Position.X, y - 0.4, base.Position.Z) * base.Rotation)
		end
	end
	for i, p in foam do
		p.Transparency = 0.18 + 0.12 * math.sin(t * 2.6 + i)
	end
	-- critters
	if not low then
		for _, c in critters do
			local u = t * c.Speed + c.Phase
			local pos, dir, flap
			if c.Kind == "Butterfly" then
				pos = c.Home + Vector3.new(math.sin(u * 1.3) * c.Radius, 1.4 + 0.5 * math.sin(u * 2.1) + 0.2 * math.sin(u * 7), math.cos(u * 0.9) * c.Radius * 0.7)
				dir = Vector3.new(math.cos(u * 1.3) * 1.3, 0, -math.sin(u * 0.9) * 0.63)
				flap = math.rad(55) * math.sin(t * 16 + c.Phase)
			else
				pos = c.Home + Vector3.new(math.cos(u) * c.Radius, math.sin(u * 0.5) * 1.2, math.sin(u) * c.Radius)
				dir = Vector3.new(-math.sin(u), 0, math.cos(u))
				flap = math.rad(22) * math.sin(t * 3 + c.Phase)
			end
			if dir.Magnitude < 1e-3 then
				dir = Vector3.zAxis
			end
			local body = CFrame.lookAt(pos, pos + dir.Unit)
			local half = c.Parts[1].Size.X / 2
			table.insert(moveParts, c.Parts[1])
			table.insert(moveCFs, body * CFrame.Angles(0, 0, flap) * CFrame.new(-half, 0, 0))
			table.insert(moveParts, c.Parts[2])
			table.insert(moveCFs, body * CFrame.Angles(0, 0, -flap) * CFrame.new(half, 0, 0))
			table.insert(moveParts, c.Parts[3])
			table.insert(moveCFs, body)
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function LobbyAmbience.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		-- the procedural fallback park (CT_Rocks_Lobby) or the owner's hand-built lobby (shared/MapNames.Roots)
		local lobby: Instance? = nil
		local hand = false
		local tries = 0
		while true do -- every 0.5 s for a minute, then every 5 s (a streamed lobby can arrive late)
			tries += 1
			lobby = Workspace:FindFirstChild("CT_Rocks_Lobby")
			if lobby then
				break
			end
			local root = MapNames.findRoot(Workspace:GetChildren())
			if root then
				lobby, hand = root, true
				break
			end
			task.wait(if tries <= 120 then 0.5 else 5)
		end
		if not lobby then
			return
		end
		task.wait(0.5) -- the lobby builds in one go on the server; give replication a moment
		if not hand then
			-- sway, waterfall and critters belong to the procedural park; the owner's map is never moved
			collect(lobby)
			lastCollect = os.clock()
			parkLobby = lobby
			local function changed(d: Instance)
				if d:IsA("BasePart") or d:IsA("Model") then
					parkDirty = true
				end
			end
			lobby.DescendantAdded:Connect(changed)
			lobby.DescendantRemoving:Connect(changed)
			spawnCritters(lobby)
			hideCritters(true)
		end
		RunService.Heartbeat:Connect(step)
		task.spawn(function()
			while true do
				updatePlotOutline()
				task.wait(1)
			end
		end)
	end)
end

-- Test / preview hook: counts of what is animated.
function LobbyAmbience.stats(): { [string]: number }
	return { Trees = #trees, Streaks = #streaks, Foam = #foam, Critters = #critters, Folder = if folder then 1 else 0 }
end

return LobbyAmbience
