--!strict
-- Carry basket (V3 loop): a small crate that follows each hunter's avatar and shows 1 to 5 neutral
-- rock miniatures (the exact rocks they hold, from the server's Basket lists, public to everyone).
-- Also the pickup arc (the exact pile rock flies into the basket), the scoop motion, and stowing
-- the hand tool while its owner is collecting (tool only shows at the own table with an empty basket).
--
-- The crate is a Model of anchored, non-colliding parts that follows the torso every frame
-- (RunService.Heartbeat), so it works on R15 (UpperTorso), R6 (Torso) and any other rig (falls back
-- to HumanoidRootPart with a larger offset), never touches a joint and cannot push the avatar.
-- Purely cosmetic: the server owns the baskets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeModel = require(Shared.GeodeModel)
local KitModels = require(Shared.KitModels)
local Anim = require(script.Parent.Anim)
local ToolAnim = require(script.Parent.ToolAnim)
local CameraMode = require(script.Parent.CameraMode)
local State = require(script.Parent.State)

local CarryView = {}

local WOOD = Color3.fromRGB(150, 112, 74)
local WOOD_DARK = Color3.fromRGB(112, 82, 54)
local SLOTS = {
	Vector3.new(-0.55, 0.38, -0.26), Vector3.new(0, 0.38, -0.26), Vector3.new(0.55, 0.38, -0.26),
	Vector3.new(-0.27, 0.66, 0.26), Vector3.new(0.27, 0.66, 0.26),
}

-- Same five spots inside the kit basket (Basket_Empty at BASKET_SCALE): two rows resting on the load.
local BASKET_SCALE = 0.8
local SLOTS_KIT = {
	Vector3.new(-0.46, 1.04, -0.2), Vector3.new(0, 1.04, -0.2), Vector3.new(0.46, 1.04, -0.2),
	Vector3.new(-0.23, 1.36, 0.2), Vector3.new(0.23, 1.36, 0.2),
}

-- Phase / Bump drive the walk bounce and the landing plop; Rels are the minis' rest spots inside the crate.
type Basket = { Model: Model, Ids: { number }, Minis: { Model }, Rels: { CFrame }, Kit: boolean?, Phase: number, Bump: number }

local baskets: { [number]: Basket } = {}
local lists: { [number]: { number } } = {} -- uid -> basket ids from the last snapshot
local flying: { [number]: boolean } = {} -- rock ids in the air (not yet shown in the basket)
local tablePos: { [number]: Vector3 } = {} -- uid -> own table position
local caps: { [number]: number } = {} -- uid -> basket capacity from the last snapshot
local seed = 1
local active = false
local toolClock = 0
local started = false

local function part(parent: Instance, name: string, size: Vector3, offset: Vector3, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(offset)
	p.Color = color
	p.Material = mat or Enum.Material.WoodPlanks
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local METAL = Color3.fromRGB(52, 58, 64)

local function buildCrate(): (Model, boolean)
	local kit = KitModels.clone("Basket_Empty", BASKET_SCALE)
	if kit then
		kit.Name = "CT_Rocks_Basket"
		kit:PivotTo(CFrame.new())
		return kit, true
	end
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Basket"
	local floor = part(m, "Floor", Vector3.new(1.9, 0.16, 1.3), Vector3.zero, WOOD)
	part(m, "Front", Vector3.new(1.9, 0.62, 0.12), Vector3.new(0, 0.36, -0.59), WOOD_DARK)
	part(m, "Back", Vector3.new(1.9, 0.62, 0.12), Vector3.new(0, 0.36, 0.59), WOOD_DARK)
	part(m, "Left", Vector3.new(0.12, 0.62, 1.3), Vector3.new(-0.89, 0.36, 0), WOOD)
	part(m, "Right", Vector3.new(0.12, 0.62, 1.3), Vector3.new(0.89, 0.36, 0), WOOD)
	-- dark metal corner straps and rim, a yellow band like the station trim
	for _, sx in { -0.9, 0.9 } do
		for _, sz in { -0.6, 0.6 } do
			part(m, "Strap", Vector3.new(0.2, 0.66, 0.2), Vector3.new(sx, 0.36, sz), METAL, Enum.Material.Metal)
		end
	end
	part(m, "RimFront", Vector3.new(1.96, 0.08, 0.16), Vector3.new(0, 0.7, -0.59), METAL, Enum.Material.Metal)
	part(m, "RimBack", Vector3.new(1.96, 0.08, 0.16), Vector3.new(0, 0.7, 0.59), METAL, Enum.Material.Metal)
	part(m, "Band", Vector3.new(1.94, 0.1, 0.14), Vector3.new(0, 0.3, -0.62), Config.Palette.Yellow, Enum.Material.SmoothPlastic)
	-- arch handle (two posts and a bar) so it reads as a carry basket
	for _, sx in { -0.82, 0.82 } do
		part(m, "HandlePost", Vector3.new(0.1, 0.55, 0.1), Vector3.new(sx, 0.95, 0), METAL, Enum.Material.Metal)
	end
	part(m, "HandleBar", Vector3.new(1.74, 0.1, 0.1), Vector3.new(0, 1.22, 0), METAL, Enum.Material.Metal)
	m.PrimaryPart = floor
	m:PivotTo(CFrame.new())
	return m, false
end

-- The part the crate rides on, and its offset, for any rig.
local function anchorOf(char: Model): (BasePart?, CFrame)
	local t = char:FindFirstChild("UpperTorso")
	if t and t:IsA("BasePart") then
		return t, CFrame.new(0, -0.55, -1.05)
	end
	t = char:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		return t, CFrame.new(0, -0.65, -1.05)
	end
	t = char:FindFirstChild("HumanoidRootPart")
	if t and t:IsA("BasePart") then
		return t, CFrame.new(0, -0.9, -1.45)
	end
	return nil, CFrame.new()
end

local function charOf(uid: number): Model?
	local p = Players:GetPlayerByUserId(uid)
	return p and p.Character
end

local function reducedMotion(): boolean
	local st = State.Profile and State.Profile.Settings
	return st ~= nil and st.ReducedMotion == true
end

-- Rides the crate on the torso. While its carrier walks the crate bounces in step and the eggs inside
-- jiggle; a landing egg gives one short plop (Bump). Reduced Motion keeps it still.
local function follow(uid: number, b: Basket, dt: number?)
	local char = charOf(uid)
	if not char then
		return
	end
	local a, off = anchorOf(char)
	if not a then
		return
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local amp = 0
	if root and root:IsA("BasePart") and dt and not reducedMotion() then
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		amp = math.clamp((speed - 1) / 14, 0, 1)
		b.Phase = (b.Phase + dt * (6 + speed * 0.45)) % (math.pi * 2)
	end
	local bk = math.clamp((os.clock() - b.Bump) / 0.28, 0, 1)
	local plop = if bk < 1 and not reducedMotion() then math.sin(bk * math.pi) * (1 - bk) else 0
	local bob = math.abs(math.sin(b.Phase)) * 0.12 * amp - plop * 0.12
	local roll = math.sin(b.Phase) * 0.06 * amp
	local cf = a.CFrame * off * CFrame.new(0, bob, 0) * CFrame.Angles(plop * 0.08, 0, roll)
	b.Model:PivotTo(cf)
	if amp > 0 or plop > 0 or b.Phase ~= 0 then
		for i, m in b.Minis do
			local rel = b.Rels[i]
			if rel and m.Parent then
				local j = math.sin(b.Phase * 2 + i * 1.7)
				m:PivotTo(cf * rel * CFrame.new(0, (j * 0.035) * amp + plop * 0.06, 0) * CFrame.Angles(j * 0.12 * amp, 0, j * 0.1 * amp))
			end
		end
	end
end

local function rebuildMinis(b: Basket, ids: { number })
	for _, m in b.Minis do
		m:Destroy()
	end
	table.clear(b.Minis)
	table.clear(b.Rels)
	b.Ids = ids
	local base = b.Model:GetPivot()
	local slots = if b.Kit then SLOTS_KIT else SLOTS
	for i, id in ids do
		if i > #slots then
			break
		end
		local variant, tint, yaw = GeodeModel.rockLook(id, seed)
		local mini = GeodeModel.rockShell(variant, 0.62, "m" .. i, { Tint = tint, Mini = true })
		local rel = CFrame.new(slots[i]) * CFrame.Angles(0, math.rad(yaw), 0)
		mini:PivotTo(base * rel)
		mini.Parent = b.Model
		table.insert(b.Minis, mini)
		table.insert(b.Rels, rel)
	end
end

local function shownIds(uid: number): { number }
	local out = {}
	for _, id in (lists[uid] or ({} :: { number })) do
		if not flying[id] then
			table.insert(out, id)
		end
	end
	return out
end

local function sameList(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i, v in a do
		if b[i] ~= v then
			return false
		end
	end
	return true
end

-- A soft gold outline while the basket is full ("go to your nest").
local function updateFullGlow(uid: number, b: Basket)
	local full = #b.Ids >= (caps[uid] or Config.Carry.Capacity)
	local glow = b.Model:FindFirstChild("FullGlow")
	if full and not glow then
		local h = Instance.new("Highlight")
		h.Name = "FullGlow"
		h.FillTransparency = 1
		h.OutlineColor = Color3.fromRGB(255, 212, 80)
		h.OutlineTransparency = 0.25
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = b.Model
		h.Parent = b.Model
	elseif glow and not full then
		glow:Destroy()
	end
end

local function refresh(uid: number)
	local want = shownIds(uid)
	local b = baskets[uid]
	if not active or lists[uid] == nil or charOf(uid) == nil then
		if b then
			CameraMode.showLocally(b.Model)
			b.Model:Destroy()
			baskets[uid] = nil
		end
		return
	end
	if not b then
		local model, isKit = buildCrate()
		model.Parent = game:GetService("Workspace")
		local fresh: Basket = { Model = model, Ids = {}, Minis = {}, Rels = {}, Kit = isKit, Phase = 0, Bump = 0 }
		b = fresh
		baskets[uid] = fresh
		if uid == Players.LocalPlayer.UserId then
			-- first person: the own crate would sit in the view; others still see it (CarryGlimpse shows a small lip)
			CameraMode.hideLocally(model)
		end
		follow(uid, fresh)
		rebuildMinis(fresh, want)
	elseif not sameList(b.Ids, want) then
		follow(uid, b)
		rebuildMinis(b, want)
	end
	updateFullGlow(uid, b)
end

-- Hand tool: only shown at the own table with an empty basket (never fights the carry pose).
local function setToolShown(char: Model, shown: boolean)
	local tool = char:FindFirstChild("CT_Rocks_HeldTool")
	if not tool then
		return
	end
	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			if shown then
				local orig = d:GetAttribute("CTOrigT")
				if orig ~= nil then
					d.Transparency = orig :: number
					d:SetAttribute("CTOrigT", nil)
				end
			elseif d:GetAttribute("CTOrigT") == nil then
				d:SetAttribute("CTOrigT", d.Transparency)
				d.Transparency = 1
			end
		end
	end
end

local function updateTools()
	local stowOn = active
	local seen: { [Model]: boolean } = {}
	for uid, ids in lists do
		local char = charOf(uid)
		if char then
			seen[char] = true
			local show = true
			if stowOn then
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local tp = tablePos[uid]
				local near = false
				if root and tp then
					local d = Vector3.new(root.Position.X - tp.X, 0, root.Position.Z - tp.Z).Magnitude
					near = d <= Config.Station.DepositRange + 3
				end
				show = #ids == 0 and near
			end
			setToolShown(char, show)
			-- coherent carry pose for avatars seen from outside (the own first-person view is unchanged)
			local mine = uid == Players.LocalPlayer.UserId
			local want = stowOn and #ids > 0 and not (mine and CameraMode.firstPerson())
			local settings = State.Profile and State.Profile.Settings
			ToolAnim.carry(char, want, settings ~= nil and settings.ReducedMotion == true)
		end
	end
end

function CarryView.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(function(dt: number)
		for uid, b in baskets do
			follow(uid, b, dt)
		end
		toolClock += dt
		if toolClock >= 0.25 then
			toolClock = 0
			if active then
				updateTools()
				-- avatars can load after the snapshot: add baskets that were waiting for one
				for uid in lists do
					if not baskets[uid] then
						refresh(uid)
					end
				end
			end
		end
	end)
end

-- A round began (Init): remember the seed and the tables, show crates for the stations.
function CarryView.init(payload: any)
	CarryView.clear()
	seed = payload.Seed or 1
	active = true
	for _, t in payload.Tables or {} do
		if t.Owner and t.Owner ~= 0 and t.Position then
			tablePos[t.Owner] = t.Position
		end
	end
	CarryView.setStations(payload.Stations or {})
end

function CarryView.setStations(stations: { any })
	local present: { [number]: boolean } = {}
	for _, st in stations do
		present[st.UserId] = true
		lists[st.UserId] = st.Basket or {}
		caps[st.UserId] = st.CarryCap
		refresh(st.UserId)
	end
	for uid in table.clone(lists) do
		if not present[uid] then
			lists[uid] = nil
			refresh(uid)
		end
	end
end

-- Where a flying rock should land: the crate, else the avatar's chest.
function CarryView.basketPoint(uid: number): Vector3?
	if uid == Players.LocalPlayer.UserId and CameraMode.firstPerson() then
		-- first person: rocks fly to the lower edge of the view, where the small basket lip is drawn
		local cam = game:GetService("Workspace").CurrentCamera
		if cam then
			return (cam.CFrame * CFrame.new(Config.Camera.Glimpse.Offset)).Position
		end
	end
	local b = baskets[uid]
	if b then
		return b.Model:GetPivot().Position + Vector3.new(0, 0.5, 0)
	end
	local char = charOf(uid)
	local a = if char then anchorOf(char) else nil
	return if a then (a :: BasePart).Position else nil
end

-- True when an avatar exists for the user (flights need somewhere to go).
function CarryView.hasAvatar(uid: number): boolean
	return charOf(uid) ~= nil
end

-- The exact rock `model` (just removed from the pile) arcs into the carrier's crate and shrinks.
function CarryView.fly(uid: number, model: Model, id: number)
	flying[id] = true
	local start = model:GetPivot()
	local startPos = start.Position
	local spin = CFrame.Angles(0, 0, 0)
	local rot0 = start - startPos
	Anim.run(0.5, function(k)
		if not model.Parent then
			return
		end
		local goal = CarryView.basketPoint(uid) or startPos
		local e = Anim.easeInOut(k)
		local pos = Anim.arc(startPos, goal, 2.6, e)
		spin = CFrame.Angles(k * 2.4, k * 3.1, 0)
		model:PivotTo(CFrame.new(pos) * spin * rot0)
		-- squash before the lift: the egg presses down for the first moments, then springs up and shrinks
		local squash = if k < 0.14 then 1 - 0.14 * (k / 0.14) else 1
		Anim.scale(model, (1 - 0.7 * e) * squash)
	end, function()
		model:Destroy()
		flying[id] = nil
		local b = baskets[uid]
		if b then
			b.Bump = os.clock() -- plop: the crate dips as the egg lands
		end
		refresh(uid)
	end)
end

-- Short reach / scoop motion on the picker's right arm (the tool is stowed, so nothing fights).
function CarryView.scoop(uid: number)
	local char = charOf(uid)
	if char then
		ToolAnim.scoop(char)
	end
end

-- The rocks shown in a hunter's basket (accepted by the server, not still in the air), for the first-person lip.
function CarryView.shown(uid: number): { number }
	return shownIds(uid)
end

function CarryView.count(uid: number): number
	return #(lists[uid] or {})
end

function CarryView.clear()
	for _, b in baskets do
		CameraMode.showLocally(b.Model)
		b.Model:Destroy()
	end
	table.clear(baskets)
	-- give every tool back before forgetting the players
	active = false
	updateTools()
	table.clear(lists)
	table.clear(caps)
	table.clear(flying)
	table.clear(tablePos)
end

return CarryView
