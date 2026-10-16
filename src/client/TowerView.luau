--!strict
-- Pet Tower 3D view: draws the pets and mobs of the current floor, health bars, hit lunges, damage pops
-- ("SUPER!" / "weak"), faints and special bursts. Pure presentation: every number comes from the server.
-- Pets use the shared PetModel when it exists (Find The Pet), else a round stand-in; mobs are procedural
-- stand-ins (REPLACE with real mob meshes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerConfig = require(Shared.TowerConfig)
local FightFxRules = require(Shared.FightFxRules)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)
local TowerFx = require(script.Parent.TowerFx)
local TowerMotion = require(script.Parent.TowerMotion)
local PetMotionBridge = require(script.Parent.PetMotionBridge)

local TowerView = {}

TowerView.TypeColor = {
	Fire = Color3.fromRGB(255, 120, 60),
	Nature = Color3.fromRGB(110, 210, 90),
	Earth = Color3.fromRGB(200, 150, 90),
	Storm = Color3.fromRGB(250, 220, 70),
	Ice = Color3.fromRGB(120, 210, 255),
	Cosmic = Color3.fromRGB(190, 120, 255),
} :: { [string]: Color3 }

type UnitView = {
	Model: Model,
	Home: CFrame,
	Fill: Frame,
	Shield: Frame,
	Max: number,
	Billboard: BillboardGui,
	Fainted: boolean,
	Boss: boolean,
	Element: string?,
	Hp: number,
	FillColor: Color3,
	Shaking: boolean,
	Pet: boolean,
	Ghost: Frame?, -- boss only: the pale bar that drains slowly behind the real one
}

local units: { [string]: UnitView } = {}
local mobOrder: { string } = {} -- this wave's mobs in server order (pets hit the first standing one)
local livePops = 0
local popParts: { [BasePart]: boolean } = {} -- hit numbers on screen (TowerView.hush takes them all down)
local hushed = false -- floor over: no new hit numbers until the next wave is drawn
local marker: BillboardGui? = nil -- small arrow over the mob the pets are hitting
-- Called with (mobs standing, mobs in the wave) whenever that changes; TowerPanel shows it on the floor card.
TowerView.onMobsLeft = function(_left: number, _total: number) end
-- Pet Battle (PvpPanel) draws the rival's pets in the mob line; there is no single front target, so no arrow.
TowerView.showTarget = true
-- Studs between pets in a line (Pet Battle spreads both lines wider so names and bars never overlap).
TowerView.petGap = 5
TowerView.foeGap = 6
TowerView.foeZ = -4 -- Pet Battle: the rival's pet line (PvpPanel sets it from the fight's layout)
TowerView.petZ = -14 -- our pet line (the tower's; the lobby arena puts it nearer the middle)
local MAX_POPS = 3 -- floating hit numbers on screen at once (LowEffects uses LOW_POPS)
local lastOrigin: CFrame? = nil
local popRng = Random.new()
local popState: { [string]: number } = {} -- FightFxRules.popSlot: when each pet's next pop may land
local popSide: { [UnitView]: number } = {} -- which side of each pet its last pop took
-- Bottom of the tower HUD's top-centre block (floor card + LEAVE) in viewport pixels; TowerPanel sets it.
-- Hit numbers start below it. 0 = no limit.
TowerView.topClear = function(): number
	return 0
end

-- Viewer settings: Low Effects keeps at most LOW_POPS damage pops on screen at once (extra ones are skipped);
-- Reduce Motion drops the lunges and hops (units stay home, faints snap).
local LOW_POPS = 3
local function setting(key: string): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings[key] == true
end
local folder: Folder? = nil
local petModel: any = nil

do
	local m = Shared:FindFirstChild("PetModel")
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok then
			petModel = mod
		end
	end
end

local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "TowerView"
	f.Parent = Workspace
	folder = f
	return f
end

local function ball(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Round critter with big eyes; pivot at the feet, facing -Z. Used for every mob and as the pet fallback.
-- The owner's low-poly mobs (Studio: ReplicatedStorage.MobModels.Mob_<Id>, textured, base-centre pivot, facing -Z):
-- cloned at MOB_HEIGHT; the tower's own slides, lunges and hops move them (PetMotion would pin the pivot).
-- nil when the mob has no model yet, so the round critter stands in.
local MOB_HEIGHT = 3.2
local BOSS_HEIGHT = MOB_HEIGHT * 2.4 -- a boss is drawn this tall (visible height, see visibleHeight): reads as a boss from spawn
local MOB_Z = 3 -- mob line, studs in front of the arena centre (pets stand at -14)

-- Height of what can actually be seen: parts that are fully see-through (a mesh's invisible root or hitbox box,
-- an effect anchor) are left out. Measuring them made a boss whose model carries a big invisible part look "tall
-- enough" already, so it was never scaled up and stood as small as a normal mob (Studio report: /boss 5).
local function visibleHeight(model: Model): number
	local lo, hi = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local cf, half = d.CFrame, d.Size / 2
			-- world-space vertical reach of the part's box
			local reach = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			lo = math.min(lo, cf.Position.Y - reach)
			hi = math.max(hi, cf.Position.Y + reach)
		end
	end
	if hi < lo then
		return model:GetExtentsSize().Y
	end
	return hi - lo
end
local function mobBody(kind: string, name: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("MobModels")
	local src = lib and lib:FindFirstChild("Mob_" .. kind)
	if not (src and src:IsA("Model")) then
		return nil
	end
	local m = src:Clone()
	m.Name = name
	local h = visibleHeight(m)
	if h > 0 then
		m:ScaleTo(m:GetScale() * MOB_HEIGHT / h)
	end
	return m
end

local function critter(name: string, color: Color3, scale: number, boss: boolean): Model
	local m = Instance.new("Model")
	m.Name = name
	local s = scale
	local body = ball(m, "Body", Vector3.new(3.2, 2.8, 3.2) * s, CFrame.new(0, 1.4 * s, 0), color)
	for _, x in { -0.6, 0.6 } do
		ball(m, "Eye", Vector3.new(0.8, 0.9, 0.5) * s, CFrame.new(x * s, 1.9 * s, -1.35 * s), Color3.new(1, 1, 1))
		ball(m, "Pupil", Vector3.new(0.42, 0.5, 0.3) * s, CFrame.new(x * s, 1.85 * s, -1.55 * s), Color3.fromRGB(30, 30, 40))
	end
	if boss then
		local crown = Instance.new("Part")
		crown.Name = "Crown"
		crown.Size = Vector3.new(1.6, 0.8, 1.6) * s
		crown.CFrame = CFrame.new(0, 3.1 * s, 0)
		crown.Color = Color3.fromRGB(255, 200, 60)
		crown.Material = Enum.Material.Neon
		crown.Anchored = true
		crown.CanCollide = false
		crown.CanQuery = false
		crown.Parent = m
	end
	m.PrimaryPart = body
	m.WorldPivot = CFrame.new()
	return m
end

local function petBody(u: any): Model
	if petModel and u.Spec then
		local ok, model = pcall(petModel.build, u.Spec)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
	end
	return critter(u.Name, TowerView.TypeColor[u.Element] or Color3.new(1, 1, 1), 0.8, false)
end

-- Boss (carter): a giant, angry version of a pet: scaled up, tinted red, glowing red eyes.
local ANGRY = Color3.fromRGB(220, 40, 40)
local function bossBody(u: any, petId: string): Model
	local model: Model? = nil
	if petModel then
		local ok, m = pcall(petModel.build, { Mineral = petId, Rarity = "Epic", Modifier = "Natural", Formation = "Standing", Mass = 2, Seed = 1 }, { Scale = 3 })
		if ok and typeof(m) == "Instance" and m:IsA("Model") then
			model = m
		end
	end
	if model == nil then
		return critter(u.Name, TowerView.TypeColor[u.Element] or ANGRY, 2.4, true)
	end
	local textured = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Eye" then
				d.Color = Color3.fromRGB(255, 40, 30)
				d.Material = Enum.Material.Neon
			else
				d.Color = d.Color:Lerp(ANGRY, 0.45)
			end
			if d:IsA("MeshPart") and d.TextureID ~= "" then
				textured = true
			end
		end
	end
	-- the owner's low-poly pets are textured meshes, which ignore Color: TowerFx.bossGlow keeps a stronger red fill
	model:SetAttribute("TexturedBoss", textured)
	return model
end

local PLATE_MIN_TEXT = 12 -- nameplate words (name, HP numbers) never draw under this many px
local PLATE_LIFT = 0.8 -- studs between a fighter's top and the centre of its nameplate (a boss: BOSS_PLATE_LIFT, bottom edge)
local BOSS_PLATE_LIFT = 2.2
local POP_ABOVE_PLATE = 28 -- px between the nameplate's top edge and a hit number's bottom edge when it pops

local function billboard(model: Model, u: any, height: number): (BillboardGui, Frame, Frame, Frame?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "TowerBar"
	-- small enemies show just their health bar (red), pets and bosses their name too: fewer stacked labels,
	-- and the type shows as the name's colour instead of a second word
	-- sizes (bug 240): names and bars read at phone size next to the hit numbers; a boss gets a wide name bar
	local named = u.Owner ~= 0 or u.Boss == true
	local boss = u.Boss == true
	-- (Studio check 2026-10-15: names and numbers read small at phone size): taller lines, text never under 12 px
	local nameH = if boss then 26 else 22
	local barH = if boss then 20 else 18
	bb.Size = if boss then UDim2.fromOffset(210, nameH + barH + 5)
		elseif named then UDim2.fromOffset(150, nameH + barH + 5)
		else UDim2.fromOffset(104, 14)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, nameH)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = (Color3.new(1, 1, 1):Lerp(TowerView.TypeColor[u.Element] or Color3.new(1, 1, 1), 0.35))
	name.TextStrokeTransparency = 0.2
	name.Text = u.Name
	name.Visible = named
	local nameMin = Instance.new("UITextSizeConstraint")
	nameMin.MinTextSize = PLATE_MIN_TEXT
	nameMin.Parent = name
	name.Parent = bb
	local track = Instance.new("Frame")
	track.Position = if named then UDim2.fromOffset(10, nameH + 3) else UDim2.fromOffset(4, 1)
	track.Size = if named then UDim2.new(1, -20, 0, barH) else UDim2.new(1, -8, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	track.BorderSizePixel = 0
	track.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(u.Hp / math.max(u.Max, 1), 0, 1), 1)
	fill.BackgroundColor3 = if u.Owner == 0 then Color3.fromRGB(240, 80, 70) else Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track
	c:Clone().Parent = fill
	fill.ZIndex = 2
	local ghost: Frame? = nil
	if u.Boss == true then
		-- boss "ghost" bar: a pale strip under the fill that catches up slowly after each hit (see setFill)
		local g = Instance.new("Frame")
		g.Name = "Ghost"
		g.Size = fill.Size
		g.BackgroundColor3 = Color3.fromRGB(255, 225, 200)
		g.BorderSizePixel = 0
		g.ZIndex = 1
		g.Parent = track
		c:Clone().Parent = g
		ghost = g
	end
	if u.Owner ~= 0 then
		-- pet bars carry their numbers so health stays readable at a glance
		local hpText = Instance.new("TextLabel")
		hpText.Name = "HpText"
		hpText.BackgroundTransparency = 1
		hpText.Size = UDim2.fromScale(1, 1)
		hpText.Font = Enum.Font.FredokaOne
		hpText.TextScaled = true
		hpText.TextColor3 = Color3.new(1, 1, 1)
		hpText.TextStrokeTransparency = 0.2
		hpText.ZIndex = 3
		hpText.Text = string.format("%d/%d", math.ceil(u.Hp), u.Max)
		local hpMin = Instance.new("UITextSizeConstraint")
		hpMin.MinTextSize = PLATE_MIN_TEXT
		hpMin.Parent = hpText
		hpText.Parent = track
	end
	local shield = Instance.new("Frame")
	shield.Size = UDim2.fromScale(0, 0.4)
	shield.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	shield.BorderSizePixel = 0
	shield.ZIndex = 2
	shield.Parent = track
	-- adorned to a part of this model (pet and mob meshes keep their parts in sub-models, so search deep): a bar
	-- with no adornee drew at the world origin, which put every bar in one pile at the top of the screen.
	-- It floats just above the model's real top, whatever the model's size.
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if adornee then
		bb.Adornee = adornee
		local cf, size = model:GetBoundingBox()
		local top = cf.Position.Y + size.Y / 2 - adornee.Position.Y
		if boss then
			-- a boss's wide name + bar sits well clear of its head, bottom edge on the anchor (SizeOffset), so it
			-- never lands on the pets' bars in front of it on screen
			bb.StudsOffsetWorldSpace = Vector3.new(0, math.max(top + BOSS_PLATE_LIFT, 3), 0)
			bb.SizeOffset = Vector2.new(0, 0.5)
		else
			bb.StudsOffsetWorldSpace = Vector3.new(0, math.max(top + PLATE_LIFT, 1.5), 0)
		end
		-- a bar whose part goes away (a mesh swapped or removed) would lose its adornee and draw at the world
		-- origin, which is the lobby (bug 252: dark bars floating in the pen): it goes with its part
		adornee.AncestryChanged:Connect(function()
			if not adornee:IsDescendantOf(Workspace) then
				bb:Destroy()
			end
		end)
	else
		bb.Enabled = false
	end
	bb.Parent = model
	return bb, fill, shield, ghost
end

-- Sets a bar's fill: eases to the new size (snaps with Reduce Motion) and keeps the pet "hp/max" text readable.
local function setFill(v: UnitView, hp: number)
	local f = math.clamp(hp / math.max(v.Max, 1), 0, 1)
	if setting("ReducedMotion") then
		v.Fill.Size = UDim2.fromScale(f, 1)
	else
		TweenService:Create(v.Fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(f, 1) }):Play()
	end
	local g = v.Ghost
	if g then
		if f >= g.Size.X.Scale or setting("ReducedMotion") then
			g.Size = UDim2.fromScale(f, 1) -- healed (or Reduce Motion): the ghost snaps with the bar
			g:SetAttribute("To", f)
		elseif g:GetAttribute("To") ~= f then
			-- only a new value restarts the drain (batches repeat unchanged health every tick)
			g:SetAttribute("To", f)
			-- drains after a short wait, slower than the real bar (a new tween on Size replaces the old one)
			TweenService:Create(g, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0.45), { Size = UDim2.fromScale(f, 1) }):Play()
		end
	end
	local track = v.Fill.Parent
	local t = if track then track:FindFirstChild("HpText") else nil
	if t and t:IsA("TextLabel") then
		t.Text = string.format("%d/%d", math.ceil(hp), v.Max)
	end
end

-- World height of the fighting floor's top: TowerBuilder's floor collider ends at the arena origin's height.
local FLOOR_TOP = 0
local function floorTop(origin: CFrame): number
	return origin.Position.Y + FLOOR_TOP
end

-- The home spot moved up or down so the model's lowest point rests on the floor top (whatever its pivot).
local function seat(model: Model, home: CFrame, floorY: number): CFrame
	model:PivotTo(home)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	return home + Vector3.new(0, math.clamp(floorY - bottom, -4, 4), 0)
end

-- Floor cleared: the far gate lights up (the way on).
function TowerView.cleared()
	if not setting("ReducedMotion") then
		-- happy hop: every standing pet jumps twice (no faces involved)
		for _, v in units do
			if not v.Fainted and not v.Boss and v.Billboard.Parent and v.Home.LookVector.Z > 0 then
				task.spawn(function()
					for _ = 1, 2 do
						if not v.Model.Parent then
							return
						end
						TowerView.slide(v.Model, v.Home * CFrame.new(0, 1.6, 0), 0.14)
						task.wait(0.16)
						TowerView.slide(v.Model, v.Home, 0.14)
						task.wait(0.18)
					end
				end)
			end
		end
	end
	if lastOrigin then
		TowerFx.gateLight(lastOrigin)
	end
end

-- Floor over (cleared or lost): every hit number and SPECIAL! word comes down at once so none shows behind the
-- floor-end card (bug 241); new ones stay off until the next wave is drawn.
function TowerView.hush()
	hushed = true
	TowerFx.fightStopped()
	for p in popParts do
		p:Destroy()
	end
	table.clear(popParts)
	livePops = 0
	table.clear(popState)
	table.clear(popSide)
	if marker then
		marker:Destroy()
		marker = nil
	end
end

function TowerView.clear()
	TowerView.hush()
	TowerFx.clear()
	lastOrigin = nil
	for _, v in units do
		v.Model:Destroy()
	end
	table.clear(units)
	table.clear(mobOrder)
	-- the whole view folder goes too, so no bar or label is left behind in the lobby (bug 252)
	if folder then
		folder:Destroy()
		folder = nil
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BillboardGui") and (d.Name == "TowerBar" or d.Name == "TowerTarget") then
			d:Destroy()
		end
	end
end

-- Puts the target arrow over the first standing mob (the one the pets hit) and reports how many are left.
local function refreshTargets()
	local front: UnitView? = nil
	local left = 0
	for _, id in mobOrder do
		local v = units[id]
		if v and not v.Fainted then
			left += 1
			if front == nil then
				front = v
			end
		end
	end
	TowerView.onMobsLeft(left, #mobOrder)
	if not TowerView.showTarget then
		front = nil
	end
	local bar: BillboardGui? = if front and front.Billboard.Parent then front.Billboard else nil
	local at: Instance? = if bar then bar.Adornee else nil
	if marker and (at == nil or hushed or marker.Adornee ~= at) then
		marker:Destroy()
		marker = nil
	end
	if bar == nil or at == nil or hushed or marker then
		return
	end
	local m = Instance.new("BillboardGui")
	m.Name = "TowerTarget"
	m.Adornee = at
	m.StudsOffsetWorldSpace = bar.StudsOffsetWorldSpace
	m.Size = UDim2.fromOffset(34, 30)
	-- sits just above the name / health bar on screen
	m.SizeOffset = Vector2.new(0, 0.5 + bar.Size.Y.Offset / 30 * (0.5 + bar.SizeOffset.Y) + 0.2)
	m.AlwaysOnTop = true
	m.MaxDistance = 140
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = "▼"
	l.TextColor3 = Color3.fromRGB(255, 220, 70)
	l.TextStrokeTransparency = 0
	l.Parent = m
	if not setting("ReducedMotion") then
		l.Position = UDim2.fromOffset(0, -4)
		TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, 3) }):Play()
	end
	m.Parent = bar.Parent
	marker = m
end

-- Draws a fresh wave: pets keep their spots, mobs are replaced.
-- The origin's flat +Z: the way our pets face (towards the mobs or the rival team). The lobby stadium's origin is
-- turned, so world +Z would leave both teams side-on (Studio test 2026-10-14).
local function forward(origin: CFrame): Vector3
	local z = origin:VectorToWorldSpace(Vector3.zAxis)
	z = Vector3.new(z.X, 0, z.Z)
	return if z.Magnitude > 1e-3 then z.Unit else Vector3.zAxis
end

function TowerView.floor(msg: any)
	local origin: CFrame = msg.Origin
	lastOrigin = origin
	hushed = false
	local pets, mobs = {}, {}
	for _, u in msg.Units do
		if u.Owner == 0 then
			table.insert(mobs, u)
		else
			table.insert(pets, u)
		end
	end
	local keep: { [string]: boolean } = {}
	for i, u in pets do
		keep[u.Id] = true
		if units[u.Id] == nil then
			local x = (i - (#pets + 1) / 2) * TowerView.petGap
			local pos = origin * Vector3.new(x, 0, TowerView.petZ)
			local home = CFrame.lookAt(pos, pos + forward(origin)) -- faces the mobs / the rival team (the origin's +Z)
			local model = petBody(u)
			model:PivotTo(home)
			model.Parent = root()
			local bb, fill, shield = billboard(model, u, 5)
			units[u.Id] = {
				Model = model, Home = home, Fill = fill, Shield = shield, Max = u.Max, Billboard = bb, Fainted = u.Hp <= 0,
				Boss = false, Element = u.Element, Hp = u.Hp, FillColor = fill.BackgroundColor3, Shaking = false, Pet = true,
			}
		else
			local v = units[u.Id]
			if v.Fainted and u.Hp > 0 then
				-- revived: stand back up (a kept unit would otherwise stay lying down with its bar hidden)
				v.Fainted = false
				v.Hp = u.Hp
				v.Max = u.Max
					setFill(v, u.Hp)
				v.Billboard.Enabled = true
				-- rises up from the floor, upright, under a ring of gold lights
				local below = v.Home * CFrame.new(0, -2, 0)
				TowerMotion.unpuff(v.Model)
				v.Model:PivotTo(below)
				local _, size = v.Model:GetBoundingBox() -- measured upright, not lying down
				TowerView.slide(v.Model, v.Home, 0.6)
				TowerMotion.halo(below, v.Home, size.Y + 0.6, 0.6)
			end
		end
	end
	table.clear(mobOrder)
	for i, u in mobs do
		keep[u.Id] = true
		table.insert(mobOrder, u.Id)
		if units[u.Id] == nil then
			local x = (i - (#mobs + 1) / 2) * (if u.Boss then 9 else TowerView.foeGap)
			-- close to the pet line (z -14), so a new wave is in the fight at once (bug 250: z 12 read as far away)
			local pos = origin * Vector3.new(x, 0, if u.Boss then MOB_Z + 5 elseif u.Foe then TowerView.foeZ else MOB_Z)
			local mob = TowerConfig.Mobs[u.Kind]
			-- a rival's pet (Pet Battle) is drawn as the pet it is
			local model = if u.Foe then petBody(u)
				elseif mob and mob.Pet then bossBody(u, mob.Pet)
				else (not u.Boss and mobBody(tostring(u.Kind), u.Name))
					or critter(u.Name, TowerView.TypeColor[u.Element] or Color3.new(1, 1, 1), if u.Boss then 2.4 else 1, u.Boss)
			if u.Boss then
				-- a boss always towers over the normal mobs (bug 251: a pet mesh that ignored PetModel's Scale
				-- came out normal-sized)
				local h = visibleHeight(model)
				if h > 0 and (h < BOSS_HEIGHT or h > BOSS_HEIGHT * 1.6) then
					model:ScaleTo(model:GetScale() * BOSS_HEIGHT / h)
				end
			end
			-- faces the pets (-Z), feet on the floor top (a mesh whose pivot is not at its base sank into the floor)
			local home = seat(model, CFrame.lookAt(pos, pos - forward(origin)), floorTop(origin))
			model:PivotTo(home * CFrame.new(0, 0, -0.01))
			model.Parent = root()
			local bb, fill, shield, ghost = billboard(model, u, if u.Boss then 9 else 4.5)
			units[u.Id] = {
				Model = model, Home = home, Fill = fill, Shield = shield, Max = u.Max, Billboard = bb, Fainted = false,
				Boss = u.Boss == true, Element = u.Element, Hp = u.Hp, FillColor = fill.BackgroundColor3, Shaking = false, Pet = false,
				Ghost = ghost,
			}
			-- pop in from the gate
			model:PivotTo(home * CFrame.new(0, 0, 8))
			TowerView.slide(model, home, 0.5)
			if u.Boss then
				-- entrance: the ground rumbles as it lands, and it flares red
				TowerFx.bossGlow(model)
				task.delay(0.4, function()
					if model.Parent then
						TowerFx.shake(0.3, 0.7)
					end
				end)
			end
		end
	end
	for id, v in units do
		if not keep[id] then
			v.Model:Destroy()
			units[id] = nil
		end
	end
	refreshTargets()
end

function TowerView.slide(model: Model, to: CFrame, t: number)
	if setting("ReducedMotion") then
		model:PivotTo(to)
		return
	end
	local v = Instance.new("CFrameValue")
	v.Value = model:GetPivot()
	v.Changed:Connect(function(cf)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)
	local tw = TweenService:Create(v, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = to })
	tw.Completed:Connect(function()
		v:Destroy()
	end)
	tw:Play()
end

-- Floating hit number: pops in big (a quick scale bounce), drifts up and a little sideways, then fades.
-- Strong hits can carry a type badge: the attacker's type colour with an arrow (up = strong, down = weak).
-- `abovePx`: the label's bottom edge sits this many px above `at` on screen (it rises from above the nameplate,
-- never through it: the "Weak" tag sat on "Shadowfang 183/222", Studio check 2026-10-15).
local function pop(at: Vector3, text: string, color: Color3, big: boolean, badge: Color3?, badgeUp: boolean?, crit: boolean?, slot: number?, abovePx: number?)
	if hushed or (setting("LowEffects") and livePops >= LOW_POPS) or (livePops >= MAX_POPS and not big) then
		return -- a few numbers at once stay readable; a pile of them hides the fighters (big hits always show)
	end
	livePops += 1
	local reduced = setting("ReducedMotion")
	at += Vector3.new(0, popRng:NextNumber(-0.3, 0.3), 0)
	local bbH = if crit then 42 elseif big then 34 else 26
	local liftPx = (abovePx or 0) + bbH / 2 -- where the label's centre lands above `at`, in screen px
	-- never under the tower HUD at the top centre (floor card, LEAVE) nor off the top of the screen (a lifted number
	-- over a fighter near the top edge): a number that would land there is moved down below it and does not drift up
	local rise = if (abovePx or 0) > 0 then 0.9 else 1.4 -- a number already lifted over the plate needs less climb
	local cam = Workspace.CurrentCamera
	local band = math.max(TowerView.topClear(), 0)
	if cam then
		local sp, onScreen = cam:WorldToViewportPoint(at)
		local want = band + (if crit then 40 else 30) + liftPx
		if onScreen and sp.Z > 0 and sp.Y < want then
			local ray = cam:ViewportPointToRay(sp.X, want)
			local along = ray.Direction:Dot(cam.CFrame.LookVector)
			if along > 0.05 then
				at = ray.Origin + ray.Direction * (sp.Z / along)
				rise = 0
			end
		end
		-- and its climb stops short of the top too (a fighter near the top edge sent its number off the screen)
		if rise > 0 then
			local ep, endOn = cam:WorldToViewportPoint(at + Vector3.new(0, rise, 0))
			if endOn and ep.Z > 0 and ep.Y < want then
				rise = 0
			end
		end
	end
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.Transparency = 1
	a.Size = Vector3.one * 0.2
	a.Position = at
	a.Parent = root()
	popParts[a] = true
	local bb = Instance.new("BillboardGui")
	-- kept modest (bug 240): the numbers must not outshout the names and bars over the fighters
	bb.Size = UDim2.fromOffset(if crit then 150 elseif big then 118 else 80, bbH)
	bb.AlwaysOnTop = true
	bb.Adornee = a
	-- the label starts `abovePx` over its anchor (clear of the nameplate), and a pet's second and third live pop sit
	-- one label height higher each, in screen space (FightFxRules.popSlot), so they never cover each other however
	-- far the camera is
	bb.SizeOffset = Vector2.new(0, liftPx / bbH + (slot or 0) * 1.1)
	local scale = Instance.new("UIScale")
	scale.Scale = if reduced then 1 else 0.4
	scale.Parent = bb
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 1
	l.Text = if crit then "CRIT! " .. text else text
	if crit then
		l.TextColor3 = Color3.fromRGB(255, 210, 60)
	end
	-- thick near-black outline: numbers stay readable over the red danger floor, fire and bright skies
	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.Color = Color3.fromRGB(20, 16, 28)
	outline.Thickness = if big or crit then 3 else 2.5
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = l
	l.Parent = bb
	local fades: { Instance } = { l }
	if badge then
		-- type badge left of the number: coloured disc with an up/down arrow, flashing twice
		bb.Size += UDim2.fromOffset(28, 0)
		l.Position = UDim2.fromOffset(28, 0)
		l.Size = UDim2.new(1, -28, 1, 0)
		local d = Instance.new("TextLabel")
		d.Name = "TypeBadge"
		d.AnchorPoint = Vector2.new(0, 0.5)
		d.Position = UDim2.new(0, 2, 0.5, 0)
		d.Size = UDim2.fromOffset(24, 24)
		d.BackgroundColor3 = badge
		d.Font = Enum.Font.FredokaOne
		d.TextScaled = true
		d.TextColor3 = Color3.new(1, 1, 1)
		d.TextStrokeTransparency = 0.3
		d.Text = if badgeUp then "▲" else "▼"
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = d
		local st = Instance.new("UIStroke")
		st.Color = Color3.new(1, 1, 1)
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = d
		d.Parent = bb
		table.insert(fades, d)
		if not reduced then
			TweenService:Create(d, TweenInfo.new(0.12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 3, true), { BackgroundColor3 = Color3.new(1, 1, 1) }):Play()
		end
	end
	bb.Parent = a
	local drift = if reduced then Vector3.zero else Vector3.new((math.random() - 0.5) * 1.6, 0, 0)
	if not reduced then
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if crit then 1.2 elseif big then 1.08 else 1 }):Play()
		if crit then
			-- crit: the number spins once as it pops in
			l.Rotation = -360
			TweenService:Create(l, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		end
	end
	TweenService:Create(a, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = at + Vector3.new(0, rise, 0) + drift }):Play()
	local fadeInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4)
	for _, f in fades do
		if f:IsA("TextLabel") then
			TweenService:Create(f, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }):Play()
			local st = f:FindFirstChildOfClass("UIStroke")
			if st then
				TweenService:Create(st, fadeInfo, { Transparency = 1 }):Play()
			end
		end
	end
	task.delay(0.9, function()
		if popParts[a] then
			popParts[a] = nil
			livePops -= 1
		end
		a:Destroy()
	end)
end

-- Health bar hit: the bar flashes red/white and gives a short horizontal shake (no shake with Reduce Motion).
local HIT_RED = Color3.fromRGB(255, 60, 50)
local function barHit(v: UnitView)
	local fill = v.Fill
	local track = fill.Parent :: Frame?
	if track == nil then
		return
	end
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = v.FillColor }):Play()
	track.BackgroundColor3 = HIT_RED
	TweenService:Create(track, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(30, 30, 34) }):Play()
	if v.Shaking or setting("ReducedMotion") then
		return
	end
	v.Shaking = true
	local home = track.Position
	task.spawn(function()
		for i, dx in { -4, 4, -3, 2, 0 } do
			if not track.Parent then
				break
			end
			track.Position = home + UDim2.fromOffset(dx, 0)
			if i < 5 then
				task.wait(0.03)
			end
		end
		track.Position = home
		v.Shaking = false
	end)
end

-- Where a unit's hit number is anchored: the centre of its nameplate (the same point `billboard` floats the plate
-- at), stepped a little left or right as the camera sees it. The label itself is lifted above the plate in screen
-- px (pop's `abovePx`, from popClear), so it rises from over the name, never through it.
local function popSpot(v: UnitView, lift: number?, slot: number?): Vector3
	local cf, size = v.Model:GetBoundingBox()
	local cam = Workspace.CurrentCamera
	local right = if cam then cam.CFrame.RightVector * Vector3.new(1, 0, 1) else Vector3.xAxis
	right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
	-- a pet's first pop takes a random side, the next ones swap sides and climb a step (FightFxRules.popSlot)
	local side = popSide[v]
	if not side or (slot or 0) == 0 then
		side = if popRng:NextNumber() < 0.5 then -1 else 1
	else
		side = -side
	end
	popSide[v] = side
	local out = popRng:NextNumber(0.3, 0.9)
	local plateY = cf.Position.Y + size.Y * 0.5 + (if v.Boss then BOSS_PLATE_LIFT else PLATE_LIFT)
	local pivot = v.Model:GetPivot().Position
	return Vector3.new(pivot.X, math.max(plateY, pivot.Y + 1.5), pivot.Z) + right * side * out + Vector3.new(0, lift or 0, 0)
end

-- Screen px from a unit's plate anchor to where its hit numbers start: the plate's half height (its whole height
-- for a boss, whose plate hangs its bottom edge on the anchor) plus POP_ABOVE_PLATE.
local function popClear(v: UnitView): number
	local plateH = v.Billboard.Size.Y.Offset
	return plateH * (if v.Boss then 1 else 0.5) + POP_ABOVE_PLATE
end

-- A pop on unit `v`, staggered in time and place so one batch of hits never lands as one stack of text.
local function popOn(key: string, v: UnitView, lift: number?, text: string, color: Color3, big: boolean, badge: Color3?, badgeUp: boolean?, crit: boolean?)
	local wait, slot = FightFxRules.popSlot(popState, key, os.clock())
	local function go()
		if v.Model.Parent then
			pop(popSpot(v, lift, slot), text, color, big, badge, badgeUp, crit, slot, popClear(v))
		end
	end
	if wait <= 0 then
		go()
	else
		task.delay(wait, go)
	end
end

-- Middle of a unit's body (for move effects).
local function bodyAt(v: UnitView): Vector3
	local cf, size = v.Model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y * 0.1, 0)
end

-- One server event batch. `hp` = { [id] = { hp, shield } } after the batch.
function TowerView.events(list: { any }, hp: { [string]: any })
	local critFrom: { [string]: boolean } = {}
	for _, e in list do
		if e.Kind == "Hit" then
			TowerFx.fightStarted() -- no title pill over a fight
			local from, to = units[e.From or ""], units[e.To or ""]
			if from and from.Pet and not from.Fainted and to then
				-- pet's turn: a little hop toward its target (TowerMotion skips it with Reduce Motion)
				local toward = (to.Home.Position - from.Home.Position) * Vector3.new(1, 0, 1)
				if toward.Magnitude > 0.1 then
					local f = from
					TowerMotion.hop(f.Model, f.Home, toward, function()
						return not f.Fainted
					end)
				end
			elseif from and not from.Fainted and to and not setting("ReducedMotion") then
				local toward = (to.Home.Position - from.Home.Position) * Vector3.new(1, 0, 1)
				if toward.Magnitude > 0.1 then
					local lunge = from.Home + toward.Unit * 1.6
					TowerView.slide(from.Model, lunge, 0.08)
					task.delay(0.1, function()
						TowerView.slide(from.Model, from.Home, 0.15)
					end)
				end
			end
			if to then
				local strong, weak = e.Id == "Strong", e.Id == "Weak"
				local text = tostring(e.Amount or 0) .. (if strong then " Strong!" elseif weak then " Weak" else "")
				local color = if strong then Color3.fromRGB(90, 235, 100) elseif weak then Color3.fromRGB(215, 215, 225) else Color3.new(1, 1, 1)
				local attacker = from and from.Element
				local badge = if (strong or weak) and attacker then TowerView.TypeColor[attacker] else nil
				local crit = e.Crit == true or (from ~= nil and critFrom[e.From or ""] == true)
				popOn(e.To or "", to, nil, text, color, strong or crit, badge, strong, crit)
				-- each move kind has its own look: attacker type sets the shape, the grade sets size / extras
				local grade = if crit then "Crit" elseif strong then "Strong" elseif weak then "Weak" else nil
				TowerFx.hit(if from then bodyAt(from) else nil, bodyAt(to), to.Home.Position.Y, attacker, grade)
				if not to.Fainted then
					local t = to
					local away = if from then (t.Home.Position - from.Home.Position) * Vector3.new(1, 0, 1) else Vector3.zero
					TowerMotion.flinch(t.Model, t.Home, away, function()
						return not t.Fainted
					end)
				end
				Audio.play("TowerHit", { Pos = to.Home.Position, Pitch = if strong then 1.12 elseif weak then 0.9 else 1 }) -- PetSoundIds.TowerHit
				if crit then
					Audio.play("PetCrit", { Pos = to.Home.Position }) -- PetSoundIds.PetCrit (0 = silent)
				end
			end
		elseif e.Kind == "Faint" then
			local v = units[e.To or ""]
			if v and not v.Fainted then
				v.Fainted = true
				Audio.play("PetKO", { Pos = v.Home.Position }) -- cartoon slide-whistle + puff, no voice (PetSoundIds.PetKO)
				TowerView.slide(v.Model, v.Home * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(80)), 0.35)
				v.Billboard.Enabled = false
				TowerMotion.puff(v.Model, if v.Boss then 0.5 else 0.4, function()
					return v.Fainted
				end)
				if v.Boss then
					local pivot = v.Model:GetPivot().Position
					TowerFx.bossBurst(pivot + Vector3.new(0, 4, 0), pivot.Y)
					TowerFx.shake(0.2, 0.4)
				end
			end
		elseif e.Kind == "Special" then
			-- a crit special (Lucky Hit): its hits later in this batch pop as crits
			local sp = TowerConfig.Specials
			local kind: string? = nil
			for _, d in sp do
				if d.Id == e.Id then
					kind = d.Kind
					if d.Kind == "Crit" and e.From then
						critFrom[e.From] = true
					end
				end
			end
			local v = units[e.From or ""]
			if v then
				if kind then
					local mobs, pets = {}, {}
					for _, id in mobOrder do
						local m = units[id]
						if m and not m.Fainted then
							table.insert(mobs, bodyAt(m))
						end
					end
					for _, u in units do
						if u.Pet and not u.Fainted then
							table.insert(pets, bodyAt(u))
						end
					end
					-- a rival's SPECIAL (Pet Battle) lands on our pets
					if v.Pet then
						TowerFx.special(kind, bodyAt(v), mobs, pets, v.Home.Position.Y)
					else
						TowerFx.special(kind, bodyAt(v), pets, mobs, v.Home.Position.Y)
					end
				end
				popOn(e.From or "", v, 0.6, "SPECIAL!", Color3.fromRGB(255, 170, 255), true)
				Audio.play("TowerSpecial", { Pos = v.Home.Position }) -- PetSoundIds.TowerSpecial
				if not setting("ReducedMotion") then
					TowerView.slide(v.Model, v.Home * CFrame.new(0, 2.5, 0), 0.12)
					task.delay(0.15, function()
						TowerView.slide(v.Model, v.Home, 0.2)
					end)
				end
			end
		end
	end
	for id, pair in hp do
		local v = units[id]
		if v and type(pair) == "table" then
			local now = pair[1] or 0
			if now < v.Hp and not v.Fainted then
				barHit(v)
			end
			v.Hp = now
				setFill(v, pair[1] or 0)
			v.Shield.Size = UDim2.fromScale(math.clamp((pair[2] or 0) / math.max(v.Max, 1), 0, 1), 0.4)
		end
	end
	refreshTargets()
end

-- A drawn unit's model (Pet Battle finisher camera).
function TowerView.model(id: string): Model?
	local v = units[id]
	return if v then v.Model else nil
end

-- Pet Battle finisher (the loser's view): the winning pet glows in its rarity colour under a big card with its power,
-- rarity and level, so the player sees exactly what beat them.
function TowerView.showcase(id: string, title: string, sub: string, color: Color3)
	local v = units[id]
	if not v then
		return
	end
	TowerFx.bossGlow(v.Model, color)
	local _, size = v.Model:GetBoundingBox()
	local bb = Instance.new("BillboardGui")
	bb.Name = "TowerBar" -- cleared with the other bars (TowerView.clear)
	bb.Adornee = (v.Model.PrimaryPart or v.Model:FindFirstChildWhichIsA("BasePart")) :: any
	bb.Size = UDim2.fromOffset(260, 76)
	bb.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.5 + 3.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local function line(text: string, y: number, h: number, c: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = c
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(20, 16, 28)
		st.Thickness = 3
		st.Parent = l
		l.Parent = bb
	end
	line(title, 0, 44, color)
	line(sub, 46, 30, Color3.new(1, 1, 1))
	bb.Parent = v.Model
	if not setting("ReducedMotion") then
		local sc = Instance.new("UIScale")
		sc.Scale = 0.3
		sc.Parent = bb
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- Pet Battle KO: a big "K.O.!" pop over the last pet to fall, a ground burst and a shake.
function TowerView.knockout(id: string?)
	local v = units[id or ""]
	if v then
		local at = v.Model:GetPivot().Position
		pop(at + Vector3.new(0, 5, 0), "K.O.!", Color3.fromRGB(255, 90, 70), true)
		TowerFx.bossBurst(at + Vector3.new(0, 3, 0), v.Home.Position.Y)
	end
	TowerFx.shake(0.35, 0.5)
end

-- Pet Battle victory pose: the standing pets of the winning side (`mine` = the viewer's) jump and spin three times
-- with a gold ring under them (no mouth or roar, carter's rule). Reduce Motion: one small hop.
function TowerView.cheer(mine: boolean)
	hushed = true
	for _, v in units do
		if v.Pet == mine and not v.Fainted then
			local model, home = v.Model, v.Home
			PetMotionBridge.play(model, "win") -- the owner's win clip when PetMotion has one (no roar, no mouth)
			if setting("ReducedMotion") then
				TowerView.slide(model, home * CFrame.new(0, 1, 0), 0.15)
				task.delay(0.2, function()
					TowerView.slide(model, home, 0.15)
				end)
			else
				TowerMotion.halo(home * CFrame.new(0, -1, 0), home, 1, 0.6)
				task.spawn(function()
					for i = 1, 3 do
						if not model.Parent then
							return
						end
						TowerView.slide(model, home * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(180 * i), 0), 0.22)
						task.wait(0.25)
						TowerView.slide(model, home * CFrame.Angles(0, math.rad(360 * i), 0), 0.2)
						task.wait(0.35)
					end
				end)
			end
		end
	end
end

return TowerView
