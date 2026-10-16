--!strict
-- Crushing-table visuals (V3 loop), all cosmetic: the server owns every rock and every hit.
--
-- Fed by the authoritative station snapshots (`Stations` in Init and every `Rocks` batch) and the
-- ordered events (Deposit, Start, Hit, Done, Found). The snapshot is the truth: after the events of
-- a batch are played, every table is reconciled to it, so a missed event can only cost an animation.
--   * queued rocks sit on the input tray slots (slot 1 = next), the current rock on the plate;
--   * fracture progression from the server's Progress: intact -> hairline seams -> wider seams and
--     chips with the pieces drifting apart -> split into rubble that drops into the output tray;
--   * hand tools swing AT the plate (ToolAnim; the local avatar turns to face it), the jackhammer
--     vibrates the rock; machine rocks ride from the tray to the machine feed (MachineView animates
--     the machine itself from the same Start events);
--   * the geode rock opens slowly on the plate (hollow shell halves part, crystals and light inside).
-- Everything is anchored, non-colliding and bounded (rubble ring of 12, chips capped, one shared
-- animation scheduler), so a four-player round with four machines stays cheap.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PetFlair = require(Shared.PetFlair)
local PetMotionBridge = require(script.Parent.PetMotionBridge)
local GeodeModel = require(Shared.GeodeModel)
local KitModels = require(Shared.KitModels)
local Anim = require(script.Parent.Anim)
local State = require(script.Parent.State)
local ToolAnim = require(script.Parent.ToolAnim)
local Audio = require(script.Parent.Audio)
local CarryView = require(script.Parent.CarryView)
local HitFx = require(script.Parent.HitFx)
local TapCombo = require(script.Parent.TapCombo)

local StationView = {}

local player = Players.LocalPlayer
local TRAY_ROCK = 0.58 -- diameter of a queued rock (Part stand-in tray)
local TRAY_ROCK_KIT = 0.5 -- the kit input tray is 2.3 x 1.9 studs: ten smaller rocks fit
local PLATE_ROCK = 1.1 -- diameter of the rock on the plate
local RUBBLE_MAX = 12
local MAX_CHIPS = 24
local YELLOW = Config.Palette.Yellow

type Attached = { Part: BasePart, Rel: CFrame, Dir: Vector3, Tilt: Vector3, Color: Color3 }
type SV = {
	UserId: number,
	Index: number,
	Model: Model,
	Slots: { Vector3 }, -- world positions of tray slots 1..10
	PlatePos: Vector3,
	OutPos: CFrame,
	FeedPos: Vector3,
	Frame: CFrame, -- table frame (-Z toward the player)
	Tray: { [number]: Model },
	Busy: { [number]: number }, -- rock id -> os.clock() until which an animation owns its model
	PlateId: number?,
	Plate: Model?,
	Base: CFrame?, -- plate rock pivot at rest
	Parts: { Attached },
	Size: number,
	Progress: number,
	Seams: number,
	Cracks: HitFx.Cracks, -- shared crack-stage lines on the plate rock (HitFx)
	Spread: Vector2, -- rubble spread (x, z) around the output tray centre
	Rubble: { Model },
	NextRubble: number,
	Tool: string,
	Auto: boolean,
	LastHit: number,
	Geode: Model?,
	Halves: { Model },
	Light: PointLight?,
	FxT: number, -- time up to which scheduled plate animations are booked
	Pending: any?, -- snapshot waiting for those animations
}

local views: { [number]: SV } = {} -- by user id
local round = 0
local seed = 1
local folder: Folder? = nil
local chips = 0
local myIndex: number? = nil
local tableRefs: { [number]: Model } = {} -- station index -> table model
StationView.Latest = nil :: { [number]: any }?

local function trayRock(): number
	return if KitModels.template("Rock_01_Wedge") then TRAY_ROCK_KIT else TRAY_ROCK
end

local function settings(): any
	return State.Profile and State.Profile.Settings or {}
end

local function look(id: number): (number, number, number)
	return GeodeModel.rockLook(id, seed)
end

local function frameYaw(cf: CFrame): number
	local _, y = cf:ToEulerAnglesYXZ()
	return y
end

-- Finding the table models --------------------------------------------------------------------

local function findTable(index: number, pos: Vector3?): Model?
	local best: Model? = nil
	local bestD = math.huge
	for _, arena in Workspace:GetChildren() do
		if string.sub(arena.Name, 1, 15) == "CT_Rocks_Arena_" then
			local m = arena:FindFirstChild("CT_Rocks_Station_" .. index)
			if m and m:IsA("Model") and m.PrimaryPart then
				local d = if pos then (m.PrimaryPart.Position - pos).Magnitude else 0
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
	end
	return best
end

local function attachPos(model: Model, partName: string, attName: string): Vector3?
	local p = model:FindFirstChild(partName)
	if p and p:IsA("BasePart") then
		local a = p:FindFirstChild(attName)
		if a and a:IsA("Attachment") then
			return p.CFrame:PointToWorldSpace(a.Position)
		end
	end
	return nil
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_StationFx"
	f.Parent = Workspace
	folder = f
	return f
end

-- Per-table geometry, read from the server's named parts.
local function buildView(st: any, tablePos: Vector3?): SV?
	local model = tableRefs[st.Index] or findTable(st.Index, tablePos)
	if not model or not model.PrimaryPart then
		return nil
	end
	tableRefs[st.Index] = model
	local surface = model.PrimaryPart :: BasePart
	-- frame: table floor origin, -Z toward the player
	local frame = surface.CFrame * CFrame.new(0, -2.75, 0)
	local slots: { Vector3 } = {}
	local slotCount = model:GetAttribute("SlotCount") -- bigger nests build more slots (StationModels)
	for i = 1, math.max(Config.Station.QueueCapacity, if type(slotCount) == "number" then slotCount else 0) do
		slots[i] = attachPos(model, "InputTray", "Slot" .. i) or frame:PointToWorldSpace(Vector3.new(2.4, 3.5, -1.2 + ((i - 1) // 2) * 0.6))
	end
	local out = model:FindFirstChild("OutputTray")
	local outCf = if out and out:IsA("BasePart") then out.CFrame else frame * CFrame.new(-2.4, 3.09, 0)
	return {
		UserId = st.UserId,
		Index = st.Index,
		Model = model,
		Slots = slots,
		PlatePos = attachPos(model, "Plate", "Plate") or frame:PointToWorldSpace(Vector3.new(0, 3.35, 0)),
		OutPos = outCf,
		FeedPos = attachPos(model, "Feed", "MachineFeed") or frame:PointToWorldSpace(Vector3.new(0, 2.6, 2.4)),
		Frame = frame,
		Tray = {},
		Busy = {},
		PlateId = nil,
		Plate = nil,
		Base = nil,
		Parts = {},
		Size = PLATE_ROCK,
		Progress = 0,
		Seams = 0,
		Cracks = HitFx.newCracks(),
		Spread = Vector2.new(if out then (out:GetAttribute("SpreadX") :: number?) or 0.6 else 0.6, if out then (out:GetAttribute("SpreadZ") :: number?) or 1.2 else 1.2),
		Rubble = {},
		NextRubble = 1,
		Tool = st.Tool or "Hammer",
		Auto = false,
		LastHit = 0,
		Geode = nil,
		Halves = {},
		Light = nil,
		FxT = 0,
		Pending = nil,
	}
end

-- Small helpers ---------------------------------------------------------------------------------

local function mini(id: number, size: number): Model
	local variant, tint, yaw = look(id)
	local m = GeodeModel.rockShell(variant, size, tostring(id), { Tint = tint, Mini = true })
	m:SetAttribute("Yaw", math.rad(yaw))
	return m
end

local function placeMini(m: Model, pos: Vector3, yawExtra: number?)
	local yaw = (m:GetAttribute("Yaw") or 0) :: number
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw + (yawExtra or 0), 0))
end

local function restY(m: Model): number
	local b = m.PrimaryPart
	return if b then b.Size.Y * 0.4 else 0.2
end

-- A few dull chips that burst out and fall (bounded, short lived).
local function burst(pos: Vector3, n: number, spread: number)
	if settings().LowEffects then
		n = math.max(1, n // 3)
	end
	local rng = Random.new(math.floor(os.clock() * 1000) % 100000)
	for _ = 1, n do
		if chips >= MAX_CHIPS then
			return
		end
		chips += 1
		local c = GeodeModel.grit(rng, 0.3)
		c.Parent = ensureFolder()
		local a = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0.4, 1) * spread
		local goal = pos + Vector3.new(math.cos(a) * dist, -0.2, math.sin(a) * dist)
		local spin = rng:NextNumber(-4, 4)
		Anim.run(0.4, function(k)
			c.CFrame = CFrame.new(Anim.arc(pos, goal, 0.7, Anim.easeOut(k))) * CFrame.Angles(k * spin, k * spin * 0.7, 0)
			c.Transparency = k * k
		end, function()
			chips -= 1
			c:Destroy()
		end)
	end
end

-- Rubble in the output tray ---------------------------------------------------------------------

local function rubbleSpot(sv: SV, i: number): CFrame
	local rng = Random.new(i * 977 + sv.Index)
	local x = rng:NextNumber(-sv.Spread.X, sv.Spread.X)
	local z = rng:NextNumber(-sv.Spread.Y, sv.Spread.Y)
	local layer = (i - 1) // 6
	return sv.OutPos * CFrame.new(x, 0.3 + layer * 0.18, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
end

-- Material Discoveries: the finished rock's output chips are solid visual variants (the server told us the
-- material only after the crush completed). Quartz = pale solid chips; metal = bright specks on grey stone.
-- Common stone keeps the ordinary look. Looks only: same size, same rubble.
-- Shells keep the cracked egg's own pastel colour whatever the material (a grey Slate / Marble re-colour made the tray
-- read as trash, owner video): a speckled shell gets small brown flecks, a golden one small gold flecks.
local SPECKLE = Color3.fromRGB(176, 128, 96)
local function styleChip(m: Model, matId: string?)
	local mat = matId and Config.Materials[matId]
	if not mat or mat.Look == "stone" then
		return
	end
	local bounds = m.PrimaryPart
	if bounds then
		local golden = mat.Look == "specks"
		local rng = Random.new(#m.Name * 131 + math.floor(bounds.Size.X * 100))
		local at = m:GetPivot()
		for _ = 1, if golden then 4 else 5 do
			local p = Instance.new("Part")
			p.Name = "Speck"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.one * rng:NextNumber(0.06, 0.1)
			p.Color = if golden then mat.Accent else SPECKLE
			p.Material = if golden then Enum.Material.Metal else Enum.Material.SmoothPlastic
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.CFrame = at * CFrame.new(rng:NextNumber(-0.4, 0.4) * bounds.Size.X, rng:NextNumber(-0.1, 0.35) * bounds.Size.Y, rng:NextNumber(-0.4, 0.4) * bounds.Size.Z)
			p.Parent = m
		end
	end
end

local function addRubble(sv: SV, from: Vector3?, color: number?, matId: string?)
	local i = sv.NextRubble
	sv.NextRubble = i % RUBBLE_MAX + 1
	local old = sv.Rubble[i]
	if old then
		-- the oldest shell shrinks away instead of vanishing
		if settings().ReducedMotion or not old.Parent then
			old:Destroy()
		else
			Anim.run(0.25, function(k)
				if old.Parent then
					Anim.scale(old, 1 - 0.95 * k)
				end
			end, function()
				old:Destroy()
			end)
		end
	end
	local rng = Random.new(i * 31 + round)
	local variant = ({ 2, 4, 12, 7, 11, 6 })[rng:NextInteger(1, 6)]
	local tintIdx = color or rng:NextInteger(1, 8)
	local m = GeodeModel.rubble(rng:NextNumber(0.5, 0.75), tintIdx, "rubble" .. i)
		or GeodeModel.rockShell(variant, rng:NextNumber(0.32, 0.46), "rubble", { Tint = tintIdx, Mini = true })
	m.Parent = ensureFolder()
	styleChip(m, matId)
	sv.Rubble[i] = m
	local goal = rubbleSpot(sv, i)
	if from then
		local start = from
		Anim.run(0.42, function(k)
			if m.Parent then
				m:PivotTo((goal - goal.Position) + Anim.arc(start, goal.Position, 1.2, Anim.easeOut(k)))
			end
		end)
	else
		m:PivotTo(goal)
	end
end

-- Fracture on the plate (crack lines come from HitFx; see seamParts) ---------------------------------------------------------------------------

-- Poses the plate rock and its seams for progress p (pieces drift apart as it breaks). `lean` (rotation only,
-- world axes) turns the whole egg about its foot on the plate: tap recoil and the settle roll.
local function pose(sv: SV, jitter: Vector3?, lean: CFrame?)
	local base = sv.Base
	if not base or not sv.Plate then
		return
	end
	local b = (base :: CFrame) + (jitter or Vector3.zero)
	if lean then
		local foot = Vector3.new(b.X, sv.PlatePos.Y, b.Z)
		b = CFrame.new(foot) * lean * CFrame.new(-foot) * b
	end
	local p = sv.Progress
	local D = sv.Size
	for _, a in sv.Parts do
		if a.Part.Parent then
			local drift = a.Dir * (p ^ 1.3 * 0.2 * D)
			local tilt = CFrame.Angles(a.Tilt.X * p, a.Tilt.Y * p, a.Tilt.Z * p)
			a.Part.CFrame = b * CFrame.new(drift) * a.Rel * tilt
			if a.Dir.Magnitude > 0 then
				a.Part.Color = a.Color:Lerp(Color3.fromRGB(60, 62, 66), p * 0.3)
			end
		end
	end
end

-- Kit rock stages (neutral dark ribbons, never a colour): hairline, then wide cracks, then the split
-- chunks replace the whole rock.
local function kitStage(sv: SV)
	local p = sv.Progress
	local stage = if p <= 0.001 then 0 elseif p < 0.5 then 1 elseif p < 0.85 then 2 else 3
	for _, a in sv.Parts do
		local n = a.Part.Name
		if n == "Rock" then
			a.Part.Transparency = if stage >= 3 then 1 else 0
		elseif n == "Hairline" or n == "Wide" then
			a.Part.Transparency = 1 -- the HitFx crack lines are the one crack look for every rock
		elseif n == "Chunk" then
			a.Part.Transparency = if stage >= 3 then 0 else 1
		end
	end
end

local function seamParts(sv: SV)
	local model = sv.Plate
	if not model or not sv.Base then
		return
	end
	local base = sv.Base :: CFrame
	local made = HitFx.setCracks(sv.Cracks, model, sv.Frame, base.Position, sv.Size, sv.Progress)
	for _, part in made do
		-- lines ride with the rock (jitter, vibration, drift)
		table.insert(sv.Parts, { Part = part :: BasePart, Rel = base:ToObjectSpace(part.CFrame), Dir = Vector3.zero, Tilt = Vector3.zero, Color = part.Color })
	end
	sv.Seams = sv.Cracks.Stage
	if model:GetAttribute("Kit") == true then
		kitStage(sv)
	end
end

local function clearPlate(sv: SV)
	if sv.Plate then
		sv.Plate:Destroy()
	end
	sv.Plate = nil
	sv.Base = nil
	table.clear(sv.Parts)
	sv.Seams = 0
	HitFx.clearCracks(sv.Cracks)
	sv.Progress = 0
end

local function showPlate(sv: SV, id: number, progress: number)
	clearPlate(sv)
	sv.PlateId = id
	local variant, tint, yaw = look(id)
	local m = GeodeModel.rockShell(variant, PLATE_ROCK, tostring(id), { Tint = tint, Mini = true, Cracks = true })
	m:SetAttribute("PlateEgg", true) -- HitFx takes its chip colour from this egg only
	m.Parent = ensureFolder()
	sv.Plate = m
	if sv.UserId == player.UserId and not settings().ReducedMotion then
		-- a soft pulsing glow on your own egg: it is ready to tap (dies with the model)
		local hl = Instance.new("Highlight")
		hl.Name = "ReadyGlow"
		hl.FillColor = Color3.fromRGB(255, 244, 200)
		hl.OutlineTransparency = 1
		hl.FillTransparency = 0.88
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
		game:GetService("TweenService"):Create(hl, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.7 }):Play()
	end
	local sit = restY(m)
	sv.Base = CFrame.new(sv.PlatePos + Vector3.new(0, sit, 0)) * CFrame.Angles(0, math.rad(yaw) + frameYaw(sv.Frame), 0)
	m:PivotTo(sv.Base :: CFrame)
	local rng = Random.new(id * 3 + 1)
	local kit = m:GetAttribute("Kit") == true
	for _, d in m:GetChildren() do
		if kit and d:IsA("BasePart") and (d.Name == "Hairline" or d.Name == "Wide" or d.Name == "Chunk") then
			-- kit crack ribbons ride with the rock; its split chunks drift apart once it breaks
			local rel = (sv.Base :: CFrame):ToObjectSpace(d.CFrame)
			local still = d.Name ~= "Chunk"
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 0.5), rng:NextNumber(-1, 1))
			table.insert(sv.Parts, {
				Part = d, Rel = rel, Dir = if still or dir.Magnitude < 0.05 then Vector3.zero else dir.Unit,
				Tilt = if still then Vector3.zero else Vector3.new(rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.35, 0.35)), Color = d.Color,
			})
		elseif d:IsA("BasePart") and d.Name == "Rock" then
			local rel = (sv.Base :: CFrame):ToObjectSpace(d.CFrame)
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 0.6), rng:NextNumber(-1, 1))
			table.insert(sv.Parts, {
				Part = d, Rel = rel, Dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.new(1, 0, 0),
				Tilt = Vector3.new(rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.35, 0.35)), Color = d.Color,
			})
		end
	end
	-- the egg must show before its first crack: clear any leftover local fade and fetch its mesh now (a clone whose
	-- mesh had not downloaded yet drew nothing until the crack lines rebuilt it)
	local meshes: { Instance } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			if d:IsA("MeshPart") then
				table.insert(meshes, d)
			end
		end
	end
	if #meshes > 0 then
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync(meshes)
			end)
		end)
	end
	-- the first piece stays put; the others drift
	if sv.Parts[1] then
		sv.Parts[1].Dir = Vector3.new(0, 0, 0)
		sv.Parts[1].Tilt = Vector3.zero
	end
	sv.Progress = progress
	seamParts(sv)
	pose(sv)
end

-- The egg rolls into place on the plate: a decaying spin plus a small rocking roll, then rest (same for every egg).
-- A tap during it wins (impact poses the egg from then on).
local function settleIn(sv: SV)
	local m = sv.Plate
	if not m or settings().ReducedMotion then
		return
	end
	local t0 = os.clock()
	local side = sv.Frame:VectorToWorldSpace(Vector3.xAxis)
	Anim.run(0.42, function(k)
		if sv.Plate ~= m or sv.LastHit > t0 then
			return
		end
		local spin = -0.9 * (1 - Anim.easeOut(k))
		local roll = math.sin(k * math.pi * 2.5) * 0.2 * (1 - k)
		pose(sv, nil, CFrame.fromAxisAngle(Vector3.yAxis, spin) * CFrame.fromAxisAngle(side, roll))
	end, function()
		if sv.Plate == m and sv.LastHit <= t0 then
			pose(sv)
		end
	end)
	HitFx.nest(sv.PlatePos + Vector3.new(0, 0.15, 0), true)
end

local function setProgress(sv: SV, p: number)
	p = math.clamp(p, 0, 1)
	if p < sv.Progress - 1e-4 then
		return -- progress never goes backward on one rock
	end
	local before = sv.Seams
	sv.Progress = p
	seamParts(sv)
	pose(sv)
	local _ = before
	-- every egg warms up the same way as it nears the end (no hint which one hides the pet)
	local plate = sv.Plate
	local core = plate and (plate.PrimaryPart or plate:FindFirstChildWhichIsA("BasePart", true))
	if core then
		local glow = core:FindFirstChild("HatchGlow")
		if p > 0.6 and not settings().ReducedMotion then
			local light: PointLight
			if glow and glow:IsA("PointLight") then
				light = glow
			else
				light = Instance.new("PointLight")
				light.Name = "HatchGlow"
				light.Color = Color3.fromRGB(255, 232, 170)
				light.Range = 9
				light.Parent = core
			end
			light.Brightness = 2.5 * ((p - 0.6) / 0.4) ^ 2
		elseif glow then
			glow:Destroy()
		end
	end
end

-- Where the tool meets the rock: upper front face for hammers, the top for the jackhammer bit.
local function contactPoint(sv: SV): Vector3
	local c = if sv.Base then (sv.Base :: CFrame).Position else sv.PlatePos + Vector3.new(0, 0.55, 0)
	local D = sv.Size
	if sv.Tool == "Jackhammer" then
		return c + Vector3.new(0, 0.42 * D, 0)
	end
	return c + sv.Frame:VectorToWorldSpace(Vector3.new(0, 0.3, -0.5)) * D
end

local function impact(sv: SV)
	sv.LastHit = os.clock()
	Audio.strike(sv.Tool == "Jackhammer", sv.PlatePos)
	if not sv.Plate then
		return
	end
	if sv.Tool == "Jackhammer" then
		HitFx.dust(contactPoint(sv))
		return -- the vibration loop below shakes it
	end
	-- dip and squash in fast, hold a beat at the bottom (a tiny hit-stop), then spring back; meanwhile the egg
	-- tips away from the tap and springs back upright with a small overshoot
	local m = sv.Plate :: Model
	local base = m:GetAttribute("BaseScale") :: number?
	if not base then
		base = m:GetScale()
		m:SetAttribute("BaseScale", base)
	end
	local s0 = base :: number
	local squash = if sv.Tool == "SteelHammer" then 0.12 else 0.09
	local away = sv.Frame:VectorToWorldSpace(Vector3.zAxis) -- the tap lands on the front (-Z) face
	local axis = Vector3.yAxis:Cross(Vector3.new(away.X, 0, away.Z).Unit)
	local lean = if sv.Tool == "SteelHammer" then 0.2 else 0.15
	local lastD = -1
	Anim.run(0.45, function(k)
		local ks = math.min(1, k / 0.44) -- the squash keeps its 0.2 s timing
		local d = if ks < 0.2 then ks / 0.2 elseif ks < 0.45 then 1 else 1 - Anim.easeOut((ks - 0.45) / 0.55)
		if m.Parent and d ~= lastD then
			lastD = d
			m:ScaleTo(s0 * (1 - squash * d))
		end
		local x = (k - 0.15) / 0.85
		local a = if k < 0.15 then math.sin(k / 0.15 * math.pi / 2) else math.cos(x * math.pi * 1.5) * (1 - x)
		pose(sv, Vector3.new(0, -0.1 * d, 0), CFrame.fromAxisAngle(axis, lean * a))
	end, function()
		if m.Parent then
			m:ScaleTo(s0)
			pose(sv)
		end
	end)
	HitFx.contact(contactPoint(sv), sv.Tool == "SteelHammer")
end

-- Ordinary rock finished: it splits and its chunks drop into the output tray.
local function splitOrdinary(sv: SV, pos: Vector3?, matId: string?)
	local at = pos or (sv.PlatePos + Vector3.new(0, 0.7, 0))
	local colorIdx = if sv.PlateId then select(2, look(sv.PlateId)) else nil
	clearPlate(sv)
	sv.PlateId = nil
	Audio.rockCracked(at)
	HitFx.split(at)
	HitFx.poof(at) -- empty egg: a little cloud
	if sv.UserId == player.UserId then
		HitFx.bump(0.18) -- last tap: a small screen bump on the own nest only
	end
	for _ = 1, 3 do
		addRubble(sv, at + Vector3.new(0, 0.2, 0), colorIdx, matId)
	end
end

-- Geode ------------------------------------------------------------------------------------------

local function destroyGeode(sv: SV)
	if sv.Geode then
		sv.Geode:Destroy()
	end
	sv.Geode = nil
	for _, h in sv.Halves do
		h:Destroy()
	end
	table.clear(sv.Halves)
	if sv.Light and sv.Light.Parent then
		sv.Light.Parent:Destroy() -- (usually already gone with the geode)
	end
	sv.Light = nil
end

local function buildGeode(sv: SV, spec: { [string]: any })
	destroyGeode(sv)
	local s = 0.72
	local R = 1.25 * s
	local frame = CFrame.new(sv.PlatePos) * CFrame.Angles(0, frameYaw(sv.Frame), 0)
	local geode = GeodeModel.build(spec, { Scale = s })
	geode:PivotTo(frame)
	geode.Parent = ensureFolder()
	sv.Geode = geode
	local cy = (geode:GetAttribute("CentreY") :: number?) or (R + 0.05 * s) -- hinge and glow sit at the shell centre
	local halves = GeodeModel.frontHalves(spec, s)
	for _, h in halves do
		h:PivotTo(frame * CFrame.new(0, cy, 0))
		h.Parent = ensureFolder()
		table.insert(sv.Halves, h)
	end
	local lightPart = Instance.new("Part")
	lightPart.Name = "GeodeGlow"
	lightPart.Transparency = 1
	lightPart.Anchored = true
	lightPart.CanCollide = false
	lightPart.CanQuery = false
	lightPart.Size = Vector3.one * 0.2
	lightPart.CFrame = frame * CFrame.new(0, cy, R * 0.4)
	lightPart.Parent = geode
	local pl = Instance.new("PointLight")
	pl.Range = 9
	pl.Brightness = 0
	local mineral = Config.Minerals[spec.Mineral] or Config.Minerals.Raptor
	pl.Color = mineral.Crystal
	pl.Parent = lightPart
	sv.Light = pl
	return halves, frame, R, s
end

-- The geode rock was finished: the plate rock splits open slowly, shell halves part, the cavity lights.
local function openGeode(sv: SV)
	clearPlate(sv)
	sv.PlateId = nil
	-- The real pet is not known yet (the server sends it with the reveal), so the stand-in is built hidden: only the
	-- egg halves and the glow show until showSpecimen swaps in the pet that actually hatched.
	local spec = { Mineral = Config.Pets.Starter, Formation = "Cluster", Modifier = "Natural", Mass = 1.2, Seed = round * 17 + sv.Index }
	local halves, frame, R, s = buildGeode(sv, spec)
	if not halves then
		return
	end
	if sv.Geode then
		for _, d in sv.Geode:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			elseif d:IsA("Beam") then
				d.Enabled = false
			elseif d:IsA("BillboardGui") then
				d.Enabled = false
			elseif d:IsA("Light") and d ~= sv.Light then
				d.Enabled = false
			end
		end
	end
	Audio.rockCracked(sv.PlatePos)
	burst(sv.PlatePos + Vector3.new(0, 1, 0), 8, 1.4)
	if sv.UserId == player.UserId then
		HitFx.bump(0.3) -- the winning tap lands a little harder
	end
	local centre = CFrame.new(0, (sv.Geode and sv.Geode:GetAttribute("CentreY") :: number?) or (R + 0.05 * s), 0)
	Anim.run(1.8, function(k)
		local e = Anim.easeInOut(k)
		local shake = if k < 0.25 then math.sin(k * 90) * 0.04 * (1 - k * 4) else 0
		for i, h in halves do
			local side = if i == 1 then -1 else 1
			if h.Parent then
				h:PivotTo(frame * centre * CFrame.new(side * e * R * 1.05 + shake, e * R * 0.12, -e * R * 0.55) * CFrame.Angles(0, side * e * math.rad(70), side * e * math.rad(14)))
			end
		end
		if sv.Light then
			sv.Light.Brightness = 3.5 * e
		end
	end)
end

-- Reveal arrived with the real specimen: rebuild the opened geode from it (halves stay open).
function StationView.showSpecimen(uid: number, spec: { [string]: any })
	local sv = views[uid]
	if not sv or not sv.Geode or type(spec) ~= "table" or not spec.Mineral then
		return
	end
	local old = sv.Halves
	local pose0: { CFrame } = {}
	for i, h in old do
		pose0[i] = h:GetPivot()
	end
	local halves = buildGeode(sv, spec)
	if halves then
		for i, h in halves do
			if pose0[i] then
				h:PivotTo(pose0[i])
			end
		end
		if sv.Geode then
			-- the real mesh pet (ReplicatedStorage.PetModels, via PetModel.template) plays its hatch animation;
			-- a procedural stand-in or a missing PetMotion just stays as it is
			PetMotionBridge.hatch(sv.Geode)
		end
		if sv.Light then
			sv.Light.Brightness = 3.5
			if PetFlair.hatchTiming(spec.Rarity).Glow then
				-- Rare+: the nest glows in the rarity colour while the slow-motion reveal plays
				local rc = (Config.RarityColors :: any)[spec.Rarity]
				if rc then
					sv.Light.Color = rc
				end
				sv.Light.Brightness = 6
				sv.Light.Range = 14
			end
		end
	end
end

-- Reconcile with the server's snapshot -------------------------------------------------------------

-- Own nest: a small "N waiting" tag by the tray while eggs queue up.
local countParts: { [number]: Part } = {}

local function waitingTag(sv: SV, n: number)
	if sv.UserId ~= player.UserId then
		return
	end
	local old = countParts[sv.UserId]
	if n <= 0 then
		if old then
			old:Destroy()
			countParts[sv.UserId] = nil
		end
		return
	end
	local p: Part
	if old and old.Parent then
		p = old
	else
		p = Instance.new("Part")
		p.Name = "WaitingTag"
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Position = (sv.Slots[1] or sv.PlatePos) + Vector3.new(0, 1.1, 0)
		-- a world tag, not a HUD piece: the nest and eggs hide it (AlwaysOnTop drew it through everything, and from the
		-- work spot it peeked out round the objective banner), and it only shows from near the nest
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(80, 22)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = 30
		gui.Enabled = false -- switched on below once its spot is on screen
		gui.Adornee = p
		gui.Parent = p
		local l = Instance.new("TextLabel")
		l.Name = "Count"
		l.BackgroundColor3 = Color3.fromRGB(32, 34, 38)
		l.BackgroundTransparency = 0.25
		l.TextColor3 = Color3.fromRGB(255, 212, 80)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Size = UDim2.fromScale(1, 1)
		l.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = l
		p.Parent = ensureFolder()
		countParts[sv.UserId] = p
		-- only while the tray is really in view and near: a billboard whose spot is behind the camera or off screen
		-- was drawn in the top left corner over Roblox's buttons on phones, so it is switched off there
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			if not p.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local cam = Workspace.CurrentCamera
			local on = false
			if cam then
				local vp = cam.ViewportSize
				local pt, inView = cam:WorldToViewportPoint(p.Position)
				on = inView and pt.Z > 0 and pt.Z < gui.MaxDistance and pt.X > 0 and pt.X < vp.X and pt.Y > vp.Y * 0.15 and pt.Y < vp.Y
			end
			if gui.Enabled ~= on then
				gui.Enabled = on
			end
		end)
	end
	local l = p:FindFirstChild("Count", true)
	if l and l:IsA("TextLabel") then
		l.Text = n .. " waiting"
	end
end

local function reconcile(sv: SV, st: any)
	waitingTag(sv, #(st.Queue or {}))
	sv.Tool = st.Tool or sv.Tool
	sv.Auto = st.Machine ~= nil and st.State ~= "Paused"
	local now = os.clock()
	-- tray
	local want: { [number]: number } = {}
	for i, id in st.Queue or {} do
		if i <= #sv.Slots then
			want[id] = i
		end
	end
	for id, m in sv.Tray do
		if want[id] == nil and (sv.Busy[id] or 0) <= now then
			m:Destroy()
			sv.Tray[id] = nil
		end
	end
	for id, i in want do
		local m = sv.Tray[id]
		local target = sv.Slots[i] + Vector3.new(0, -0.12, 0)
		if not m then
			local fresh = mini(id, trayRock())
			fresh.Parent = ensureFolder()
			sv.Tray[id] = fresh
			placeMini(fresh, target)
		elseif (sv.Busy[id] or 0) <= now then
			local cur = m:GetPivot().Position
			if (cur - target).Magnitude > 0.05 then
				local from = cur
				local mm = m
				Anim.run(0.18, function(k)
					if mm.Parent then
						placeMini(mm, from:Lerp(target, Anim.easeOut(k)))
					end
				end)
			end
		end
	end
	-- plate (hand-tool station only; machine rocks ride the machine)
	local cur = st.Current
	if cur and not sv.Auto then
		if sv.PlateId ~= cur or not sv.Plate then
			if (sv.Busy[cur] or 0) <= now then
				if not sv.Geode then
					showPlate(sv, cur, st.Progress or 0)
				end
			end
		else
			setProgress(sv, st.Progress or sv.Progress)
		end
	elseif not cur and sv.Plate and (sv.Busy[sv.PlateId or 0] or 0) <= now then
		clearPlate(sv)
		sv.PlateId = nil
	end
end

local function nameplate(sv: SV, mine: boolean)
	local plate = sv.Model:FindFirstChild("Nameplate")
	if not plate or not plate:IsA("BasePart") then
		return
	end
	local label = plate:FindFirstChild("Name", true)
	if mine then
		plate.Color = YELLOW
		if label and label:IsA("TextLabel") then
			label.BackgroundColor3 = YELLOW
			label.TextColor3 = Color3.fromRGB(32, 34, 38)
		end
	end
	local strip = sv.Model:FindFirstChild("ColorStrip")
	if strip and strip:IsA("BasePart") and mine then
		strip.Color = YELLOW
	end
	if mine then
		for _, d in sv.Model:GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("AccentSlot") == true then
				d.Color = YELLOW -- kit tables: the Accent pieces carry the owner colour
			end
		end
	end
end

-- First-person work tool (Master Prompt 7). In first person the avatar's own third-person stroke raises the right
-- forearm about two studs in front of the eye, where it covers a third of the screen (docs/m7/quarry). So in first
-- person the local stroke is shown by a LOCAL copy of the held tool that swings from the player's right onto the rock
-- on the plate (contact at 0.3 s, when the crack shows), the real held tool is hidden locally for the stroke and the
-- arm stays at rest. Other players are unaffected: their clients play the full third-person swing from the Hit event.
-- The stroke copy leaves right after its recoil (a hammer stroke is 0.6 s; the tapper buzzes every 0.2 s): left at the
-- ready it hung in the air over the nest with no hand on it (owner video). Between strokes no first-person copy shows
-- (a resting copy at the lower right also floated with no hand on it, so it was removed).
local FP_LINGER = 0.65
local FP_LINGER_TAPPER = 0.4
local fp = { Tool = nil :: Model?, Len = 2, Kind = "Hammer", Start = 0, Until = 0, Conn = nil :: RBXScriptConnection?, Hidden = {} :: { [BasePart]: number } }

local function firstPerson(): boolean
	return player.CameraMode == Enum.CameraMode.LockFirstPerson
end

local function hideHeld(char: Model?, on: boolean)
	if on then
		local tool = char and char:FindFirstChild("CT_Rocks_HeldTool")
		if tool then
			for _, d in tool:GetDescendants() do
				if d:IsA("BasePart") and fp.Hidden[d] == nil then
					fp.Hidden[d] = d.Transparency
					d.Transparency = 1
				end
			end
		end
	else
		for p, t in fp.Hidden do
			if p.Parent then
				p.Transparency = t
			end
		end
		table.clear(fp.Hidden)
	end
end

local function fpClear()
	if fp.Conn then
		fp.Conn:Disconnect()
		fp.Conn = nil
	end
	if fp.Tool then
		fp.Tool:Destroy()
		fp.Tool = nil
	end
	hideHeld(nil, false)
end

-- A visual-only copy of the held tool (no joints, anchored, ignored by everything).
local function fpBuild(char: Model): Model?
	local src = char:FindFirstChild("CT_Rocks_HeldTool")
	if not src or not src:IsA("Model") then
		return nil
	end
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Attachment") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.LocalTransparencyModifier = 0
		end
	end
	m.Name = "CT_Rocks_FpTool"
	pcall(function()
		m:ScaleTo(m:GetScale() * 0.7) -- close to the eye a full-size head and handle read huge
	end)
	m.Parent = ensureFolder()
	fp.Len = math.max(m:GetExtentsSize().Y, 1)
	return m
end

-- Hammer angle (degrees above the contact pose) at time t of a stroke: wind-up, strike, recoil, ready.
local function fpAngle(t: number): number
	if t < 0.24 then
		local k = t / 0.24
		return 25 + 40 * (1 - (1 - k) ^ 2)
	elseif t < 0.3 then
		local k = (t - 0.24) / 0.06
		return 65 * (1 - k * k)
	elseif t < 0.35 then
		return 0 -- hit-stop: the head rests on the egg for a beat
	elseif t < 0.45 then
		return 12 * math.sin((t - 0.35) / 0.1 * math.pi / 2)
	elseif t < 0.6 then
		return 12 + 13 * (t - 0.45) / 0.15
	end
	return 25
end

local function fpPose(sv: SV, now: number)
	local tool, cam = fp.Tool, Workspace.CurrentCamera
	if not tool or not cam then
		return
	end
	local U = Vector3.yAxis
	local look = cam.CFrame.LookVector
	local F = Vector3.new(look.X, 0, look.Z)
	F = if F.Magnitude > 1e-3 then F.Unit else Vector3.new(0, 0, -1)
	local R = F:Cross(U).Unit
	-- the strike lands on the rock's upper front face (toward the player), so contact sits in the middle of the view
	local top = sv.PlatePos + U * (sv.Size * 0.62) - F * (sv.Size * 0.3)
	if fp.Kind == "Jackhammer" then
		-- leaning in from the right, bit on the rock, buzzing while hits come in (never across the screen centre)
		local h = (U * 0.55 + R * 0.55 - F * 0.45).Unit
		local buzz = if now < fp.Start + 0.35 then (if (now * 60) % 2 < 1 then 0.05 else -0.05) else 0
		local pos = top + h * (fp.Len * 0.92 + buzz)
		local X = h:Cross(F).Unit
		tool:PivotTo(CFrame.fromMatrix(pos, X, h))
		return
	end
	local h0 = (-R * 0.5 + F * 0.8 + U * 0.22).Unit -- grip -> head at contact: the grip is low and near, to the player's right
	local reach = fp.Len * 0.85
	local st = now - fp.Start
	local hit = (st - 0.29) / 0.15 -- the head squashes a bit on the egg (contact + hit-stop)
	ToolAnim.squash(tool, if hit < 0 or hit > 1 or settings().ReducedMotion == true then 0 else 0.13 * math.sin(hit * math.pi))
	local a = math.rad(fpAngle(st))
	local h = (h0 * math.cos(a) + U * math.sin(a)).Unit
	local grip = top + U * 0.1 - h0 * reach + U * (0.3 * math.sin(a))
	local X = h:Cross(F).Unit
	if X.Y > 0 then
		X = -X
	end
	tool:PivotTo(CFrame.fromMatrix(grip, X, h))
end

local function fpSwing(sv: SV, char: Model)
	if not fp.Tool or not fp.Tool.Parent then
		fp.Tool = fpBuild(char)
		if not fp.Tool then
			return
		end
	end
	hideHeld(char, true)
	local now = os.clock()
	fp.Kind = sv.Tool
	local linger = if fp.Kind == "Jackhammer" then FP_LINGER_TAPPER else FP_LINGER
	if fp.Kind ~= "Jackhammer" and now - fp.Start < 0.55 then
		fp.Until = fp.Start + 0.55 + linger -- still swinging; the server cadence is what counts
		return
	end
	fp.Start = if settings().ReducedMotion == true then now - 0.3 else now
	fp.Until = now + linger
	fpPose(sv, now)
	if fp.Conn then
		return -- the running pose loop picks up the new stroke
	end
	fp.Conn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cur = views[player.UserId]
		if t > fp.Until or not cur or not firstPerson() then
			fpClear()
			return
		end
		fpPose(cur, t)
	end)
end

-- Public API ------------------------------------------------------------------------------------------

-- True while the local first-person stroke copy of the tool is on screen.
function StationView.strokeActive(): boolean
	return fp.Tool ~= nil
end

function StationView.clear()
	fpClear()
	HitFx.clear()
	TapCombo.clear()
	for _, sv in views do
		destroyGeode(sv)
	end
	table.clear(views)
	table.clear(tableRefs)
	table.clear(countParts)
	if folder then
		folder:Destroy()
	end
	folder = nil
	chips = 0
	myIndex = nil
	StationView.Latest = nil
end

function StationView.init(payload: any)
	StationView.clear()
	round = payload.Round or 0
	seed = payload.Seed or 1
	local tp: { [number]: Vector3 } = {}
	for _, t in payload.Tables or {} do
		if t.Position then
			tp[t.Index] = t.Position
		end
	end
	local latest: { [number]: any } = {} -- newest snapshot per user (for tables that were not streamed in yet)
	local function attempt(st: any)
		if views[st.UserId] then
			return
		end
		local sv = buildView(st, tp[st.Index])
		if sv then
			views[st.UserId] = sv
			if st.UserId == player.UserId then
				myIndex = st.Index
			end
			nameplate(sv, st.UserId == player.UserId)
			reconcile(sv, latest[st.UserId] or st)
		end
	end
	local missing = false
	for _, st in payload.Stations or {} do
		latest[st.UserId] = st
		attempt(st)
		missing = missing or views[st.UserId] == nil
	end
	StationView.Latest = latest
	if missing then
		-- the arena may still be replicating to this client (or, with StreamingEnabled, a far table streams in only
		-- when the player gets near): retry every 0.5 s at first, then every 2 s for the rest of the round
		local r = round
		task.spawn(function()
			local tries = 0
			while true do
				tries += 1
				task.wait(if tries <= 20 then 0.5 else 2)
				if round ~= r or StationView.Latest ~= latest then
					return
				end
				local still = false
				for uid, st in latest do
					attempt(st)
					still = still or views[uid] == nil
				end
				if not still then
					return
				end
			end
		end)
	end
end

-- Books a plate animation after the ones already booked for this table, so a batch like
-- Start / Hit / Done plays as one readable sequence (swing, crack, split) instead of at once.
local function sched(sv: SV, gap: number, fn: () -> (), dur: number?)
	local now = os.clock()
	local reduced = settings().ReducedMotion == true
	local t = math.max(now, sv.FxT) + (if reduced then 0 else gap)
	sv.FxT = t + (if reduced then 0 else (dur or 0))
	local function run()
		if views[sv.UserId] == sv then -- the round may have ended meanwhile
			fn()
		end
	end
	if t - now <= 0.001 then
		run()
	else
		task.delay(t - now, run)
	end
end

function StationView.onStations(stations: { any }?)
	for _, st in (stations or ({} :: { any })) do
		local keep = StationView.Latest
		if keep then
			keep[st.UserId] = st
		end
		local sv = views[st.UserId]
		if sv then
			if sv.FxT > os.clock() then
				-- animations are still booked: reconcile right after them
				local first = sv.Pending == nil
				sv.Pending = st
				if first then
					sched(sv, 0.02, function()
						local pend = sv.Pending
						sv.Pending = nil
						if pend and views[st.UserId] == sv then
							reconcile(sv, pend)
						end
					end)
				end
			else
				reconcile(sv, st)
			end
		end
	end
end

local function basketFrom(uid: number, fallback: Vector3): Vector3
	return CarryView.basketPoint(uid) or fallback
end

-- One ordered event from a "Rocks" batch (the snapshot follows it).
function StationView.onEvent(e: any, stations: { any }?)
	local sv = views[e.UserId]
	if not sv then
		return
	end
	local now = os.clock()
	if e.Kind == "Deposit" then
		for n, id in e.Ids or {} do
			local want = nil
			for _, st in (stations or ({} :: { any })) do
				if st.UserId == e.UserId then
					for i, q in st.Queue do
						if q == id then
							want = i
						end
					end
				end
			end
			local slot = want and sv.Slots[want]
			if slot and not sv.Tray[id] then
				local m = mini(id, trayRock())
				m.Parent = ensureFolder()
				sv.Tray[id] = m
				sv.Busy[id] = now + 0.12 * (n - 1) + 0.4
				local from = basketFrom(e.UserId, slot + Vector3.new(0, 2, 0))
				local target = slot + Vector3.new(0, -0.12, 0)
				local delay = 0.08 * (n - 1)
				placeMini(m, from)
				task.delay(delay, function()
					Anim.run(0.32, function(k)
						if m.Parent then
							placeMini(m, Anim.arc(from, target, 1.4, Anim.easeOut(k)), k * 3)
						end
					end, function()
						if m.Parent then
							HitFx.nest(target, false) -- straw puffs where it lands
						end
					end)
				end)
			end
		end
		return
	end
	local jack = sv.Tool == "Jackhammer"
	local lag = sv.FxT - now
	local fast = lag > 0.5 -- far behind (jackhammer on one-hit rocks): skip the long flourishes
	if e.Kind == "Start" then
		local id = e.Id
		if e.Duration then
			-- machine rock: rides from the tray to the machine feed
			sv.Busy[id] = now + 0.6
			local m = sv.Tray[id]
			if m then
				local from = m:GetPivot().Position
				Anim.run(0.4, function(k)
					if m.Parent then
						placeMini(m, Anim.arc(from, sv.FeedPos, 0.8, Anim.easeInOut(k)))
						Anim.scale(m, 1 - 0.6 * k)
					end
				end, function()
					m:Destroy()
					if sv.Tray[id] == m then
						sv.Tray[id] = nil
					end
				end)
			end
			return
		end
		if sv.Geode then
			return
		end
		sv.Busy[id] = now + 1.2
		sched(sv, 0, function()
			if sv.Geode or not views[e.UserId] then
				return
			end
			sv.PlateId = id
			local m = sv.Tray[id]
			if m and not fast then
				local from = m:GetPivot().Position
				local to = sv.PlatePos + Vector3.new(0, 0.6, 0)
				Anim.run(0.24, function(k)
					if m.Parent then
						placeMini(m, Anim.arc(from, to, 0.9, Anim.easeOut(k)), k * 2.5) -- rolls in with a little spin
						Anim.scale(m, 1 + (PLATE_ROCK / trayRock() - 1) * k)
					end
				end, function()
					m:Destroy()
					if sv.Tray[id] == m then
						sv.Tray[id] = nil
					end
					if sv.PlateId == id and not sv.Plate and not sv.Geode then
						showPlate(sv, id, 0)
						settleIn(sv)
					end
				end)
			else
				if m then
					m:Destroy()
					sv.Tray[id] = nil
				end
				showPlate(sv, id, 0)
			end
		end, if fast then 0.02 else 0.26)
	elseif e.Kind == "Hit" then
		if e.UserId ~= player.UserId then
			local pl = Players:GetPlayerByUserId(e.UserId)
			local c = pl and pl.Character
			if c then
				ToolAnim.strike(c, sv.Tool, settings().ReducedMotion == true, nil)
			end
		end
		-- the tool lands about 0.3 s after the swing starts: show the crack then
		sched(sv, if jack or fast then 0 else 0.3, function()
			if sv.Geode then
				return
			end
			if not sv.Plate or sv.PlateId ~= e.Id then
				showPlate(sv, e.Id, 0)
			end
			setProgress(sv, e.Progress or sv.Progress)
			impact(sv)
			if e.UserId == player.UserId and not jack then
				TapCombo.hit(sv.PlatePos)
			end
		end, 0.02)
	elseif e.Kind == "Done" then
		sched(sv, 0, function()
			if sv.Auto then
				-- machine rock: the machine view animates it; the tray just gets rubble
				addRubble(sv, nil, nil, e.Mat)
				return
			end
			if not sv.Plate then
				showPlate(sv, e.Id, 0)
			end
			local from = sv.Progress
			if from < 0.95 and not jack and not fast then
				-- a one-hit rock still shows its crack before it splits
				Anim.run(0.26, function(k)
					if sv.Plate then
						setProgress(sv, from + (1 - from) * k)
					end
				end, function()
					splitOrdinary(sv, nil, e.Mat)
				end)
			else
				splitOrdinary(sv, nil, e.Mat)
			end
		end, if jack or fast then 0.02 else 0.3)
	elseif e.Kind == "Found" then
		sched(sv, 0, function()
			openGeode(sv)
		end, 0)
	end
end

-- Crack edges glow softly between taps: off right after a hit, then a slow warm pulse (~1.4 s). Same on
-- every egg; skipped with Low Effects.
local function pulseCracks(sv: SV, now: number, low: boolean)
	local idle = now - sv.LastHit
	if low or not sv.Plate or sv.Seams <= 0 or idle < 0.35 then
		HitFx.glowCracks(sv.Cracks, 0)
		return
	end
	local ramp = math.min(1, (idle - 0.35) / 0.5)
	HitFx.glowCracks(sv.Cracks, ramp * (0.25 + 0.75 * (0.5 - 0.5 * math.cos(now * math.pi * 2 / 1.4))))
end

-- Jackhammer vibration over the plate while hits keep coming (every frame, from PileView); also the crack pulse.
function StationView.vibrate()
	local now = os.clock()
	local low = settings().LowEffects == true
	for _, sv in views do
		pulseCracks(sv, now, low)
		if sv.Plate and sv.Tool == "Jackhammer" and now - sv.LastHit < 0.3 then
			local k = (now * 60) % 2 < 1
			pose(sv, Vector3.new(if k then 0.06 else -0.06, if k then 0.03 else -0.03, 0))
			HitFx.dust(contactPoint(sv))
		end
	end
end

-- The local avatar swings its hammer at the plate (called when a Crush is sent).
function StationView.localSwing()
	local sv = views[player.UserId]
	local char = player.Character
	if not sv or not char then
		return
	end
	if firstPerson() then
		fpSwing(sv, char)
		return
	end
	ToolAnim.face(char, sv.PlatePos)
	ToolAnim.strike(char, sv.Tool, settings().ReducedMotion == true, nil)
end

-- True when `inst` is part of the egg on the LOCAL player's nest plate (tap-to-crack in PileView).
function StationView.isOwnPlatePart(inst: Instance?): boolean
	local sv = views[player.UserId]
	local plate = sv and sv.Plate
	return inst ~= nil and plate ~= nil and inst:IsDescendantOf(plate)
end

-- The local player's plate egg model, or nil (raycast include list for tap-to-crack).
function StationView.ownPlate(): Model?
	local sv = views[player.UserId]
	return sv and sv.Plate
end

-- Seconds of booked plate animation still to play (the reveal screen waits for the geode to open).
function StationView.fxRemaining(): number
	local worst = 0
	local now = os.clock()
	for _, sv in views do
		worst = math.max(worst, sv.FxT - now)
	end
	return worst
end

function StationView.platePosition(uid: number): Vector3?
	local sv = views[uid]
	return if sv then sv.PlatePos else nil
end

function StationView.tablePosition(uid: number): Vector3?
	local sv = views[uid]
	return if sv then sv.Frame.Position else nil
end

function StationView.myIndex(): number?
	return myIndex
end

-- Where the reticle aims to work at a nest: the egg on its plate (the old aim point was the table top, so the ring
-- opened on the nest below the egg).
function StationView.aimPoint(uid: number): Vector3?
	local sv = views[uid]
	return if sv then sv.PlatePos + Vector3.new(0, sv.Size * 0.5, 0) else nil
end

function StationView.ownModel(): Model?
	local sv = views[player.UserId]
	return if sv then sv.Model else nil
end

return StationView
