--!strict
-- Equipped pets following their owners (client only, purely cosmetic). The server sets on each Player the attribute
-- "PetsShown" = JSON array of { Id, Mineral, Rarity, Modifier, Formation, Seed, Mass }. For every player this builds
-- the pets with PetModel (small scale, no lights) and, every frame, eases each one toward a slot behind / beside the
-- character with a little hop while it moves. Anchored parts moved with PivotTo; no physics, nothing sent anywhere.
-- A small name tag (type icon on a glow pill in the type colour, then the nickname or rarity word + pet name in the
-- rarity text colour) floats over each follower, which also stands on a soft neon disc in its type colour, visible within
-- 35 studs only so a full server never clutters the screen. In a hunt only the one pet helper follows (marked Helper
-- by the server, shared/HuntFun); none in the pet tower or a Pet Battle. A pet that comes within FADE_NEAR studs of the camera, or sits
-- between the camera and the local character's head, fades out locally (LocalTransparencyModifier) so it never
-- blocks the view. Rebuilt on attribute change; cleaned up when a player leaves or respawns. When the owner stops,
-- the pets turn to look at them. PetFx adds a ground shadow, the breathing rarity aura, Golden / Rainbow shimmer,
-- a per-element particle trait, dust thumps for heavy pets and the level-up ring (PetLevelFx via PetFollow.modelFor).
-- Small touches: pets hop when the owner jumps, bank into turns, spin on a level up (PetFollow.spin), get sleepy (head
-- droop + "Zzz") after the owner stands still SLEEP_AFTER seconds, float hearts when equipped and shrink away in a poof
-- when unequipped (PetMoodFx). Mesh pets also get "LookAt" (owner's head while stopped), "Sleepy" and "WalkRate"
-- (step speed, faster with speed boots) model attributes for PetMotion.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetModel = require(Shared.PetModel)
local GeodeGen = require(Shared.GeodeGen)
local Config = require(Shared.Config)
local PetRules = require(Shared.PetRules)
local PetFlair = require(Shared.PetFlair)
local Rules = require(Shared.PetFxRules)
local UI = require(script.Parent.ui.UI)
local PetFx = require(script.Parent.PetFx)
local State = require(script.Parent.State)
local PetMoodFx = require(script.Parent.PetMoodFx)
local MotionBridge = require(script.Parent.PetMotionBridge)

local PetFollow = {}

-- Optional: the owner's ReplicatedStorage.PetMotion (walk / idle animation for the real pet meshes). API used:
-- start(model), setBase(model, cframe), model attribute "Moving". Missing module = the built-in hop below.
local Motion: any = nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("PetMotion")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" and type(res.start) == "function" and type(res.setBase) == "function" then
			Motion = res
		end
	end
end

local SCALE = 2.1 -- owner 2026-10-12: pets 3x the old size (PS99 style)
local TYPE_ICON = { Coins = "boostCoins", Speed = "boostSpeed", Luck = "boostLuck" }
-- slots in the character's local space (x right, z behind)
local SLOTS = { Vector3.new(7, 0, 8), Vector3.new(-7, 0, 8), Vector3.new(0, 0, 12.5) }
-- bug 243: every follower is normalised to one height (about an avatar's chest) whatever its species or SizeBoost,
-- and its footprint is capped so wide wings (Griffin) never reach the owner; mass varies it only a little
local FOLLOW_H = 4.6 -- studs
local FOLLOW_W = 7 -- studs: widest footprint a follower may have

local FADE_NEAR = 3.5 -- studs from the camera
local FADE_LINE = 1.5 -- studs from the camera -> head segment
local FAR_FX = 60 -- studs from the camera: beyond this a pet's effects and animation updates are skipped
local FAR_FX_BACK = 52 -- hysteresis: effects come back inside this distance
local SNAP_FAR = 40 -- studs: a pet left this far behind snaps to its slot with a poof
local SLEEP_AFTER = 30 -- s of the owner standing still before the pets get sleepy
local JUMP_TIME = 0.5 -- s of a follower's hop when the owner jumps
local SPIN_TIME = 0.6 -- s of the level-up spin
local FLYERS = { dragon = true, griffin = true, phoenix = true, pterodactyl = true, wyvern = true }

type Pet = { Id: any, Fx: PetFx.Fx?, Model: Model, Pos: Vector3, Look: Vector3, Phase: number, Height: number, Parts: { BasePart }, Tag: BillboardGui?, CentreY: number, Fade: number, Flying: boolean, Size: number, Far: boolean, Eyes: { BasePart }, EyeSizes: { Vector3 }, NextBlink: number, BlinkEnd: number, HopS: number,
	JumpT: number, BounceT: number, SpinT: number, Bank: number, Droop: number, Sleepy: boolean, EyesShut: boolean, Zzz: BillboardGui?, LookSet: Vector3?, Rate: number }

-- Happy bounce for one follower: the hop (step) and PetFx's squash and star sparkle. Reduce Motion: no hop.
local function startBounce(p: Pet)
	if not (UI.Reduced or (State.Profile and State.Profile.Settings and State.Profile.Settings.ReducedMotion == true)) then
		p.BounceT = os.clock()
	end
	pcall(PetFx.happy, p.Model)
end
-- Known: pet ids last shown (nil until the first list arrives, so joining never plays the equip hearts)
type Entry = { Pets: { Pet }, Raw: string?, Conns: { RBXScriptConnection }, Spread: number, Air: number, Known: { [string]: boolean }?, WasJump: boolean, Still: number }

local entries: { [Player]: Entry } = {}
local folder: Folder? = nil


-- Followers walk with the player all the time, so their effects stay quiet: the engine Sparkles (a dense star spray)
-- become a few small, slow glints, and the soft rarity aura ring is fainter. Rewards, hits and hatches keep the
-- strong bursts (owner review 2026-10-12: idle walking looked like a reward going off).
local function calmFx(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("Sparkles") then
			local e = Instance.new("ParticleEmitter")
			e.Name = "CalmSparkle"
			e.Color = ColorSequence.new(d.SparkleColor)
			e.LightEmission = 0.6
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.18), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.2, 1)
			e.Lifetime = NumberRange.new(0.6, 0.9)
			e.Rate = 1.5
			e.Speed = NumberRange.new(0.2, 0.5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Enabled = d.Enabled
			CollectionService:AddTag(e, "PetSparkle") -- Low Effects still turns it off (PetSparkle)
			e.Parent = d.Parent
			d:Destroy()
		elseif d:IsA("BasePart") and d.Name == "Aura" then
			d.Transparency = math.max(d.Transparency, 0.8)
		end
	end
end

-- Dust puffs at the feet of big pets while they walk (owner's low-poly puff, IMPORT_NOW5 DustPuff_tex). Only pets
-- about the player's height or taller get them; none with Low Effects.
local DUST_TEX = "rbxassetid://135782428554903"
local function dust(m: Model, on: boolean)
	local root = m.PrimaryPart
	if not root then
		return
	end
	local e = root:FindFirstChild("WalkDust", true) :: ParticleEmitter?
	if not e then
		if not on then
			return
		end
		local cf, size = m:GetBoundingBox()
		if size.Y < 5 then
			return
		end
		local a = Instance.new("Attachment")
		a.Name = "WalkDustAt"
		a.Parent = root
		a.WorldPosition = Vector3.new(cf.X, cf.Y - size.Y / 2 + 0.2, cf.Z)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "WalkDust"
		pe.Texture = DUST_TEX
		pe.Rate = 6
		pe.Lifetime = NumberRange.new(0.4)
		pe.Speed = NumberRange.new(0.5, 1.2)
		pe.SpreadAngle = Vector2.new(60, 20)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		pe.LightInfluence = 0.6
		pe.Parent = a
		e = pe
	end
	if e then
		-- (not tagged PetSparkle: that would switch it on while standing still) Low Effects: no dust
		local prof = State.Profile
		local low = prof ~= nil and prof.Settings ~= nil and prof.Settings.LowEffects == true
		e.Enabled = on and not low
	end
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "CTR_Pets"
	f.Parent = Workspace
	folder = f
	return f
end

local function clearPets(e: Entry)
	for _, p in e.Pets do
		p.Model:Destroy()
		if p.Fx then
			PetFx.destroy(p.Fx)
		end
	end
	table.clear(e.Pets)
	e.Spread = 1
end

-- rarity rank for slot order (rarest first)
local function rankOf(spec: any): number
	local r = if type(spec) == "table" then tostring(spec.Rarity) else ""
	return table.find(Config.Rarities :: any, r) or 0
end

-- Shortest-arc turn of a flat direction toward `want` (no snap when the target flips sideways or backwards).
local function turnToward(look: Vector3, want: Vector3, k: number): Vector3
	local a = math.atan2(look.X, look.Z)
	local d = (math.atan2(want.X, want.Z) - a + math.pi) % (2 * math.pi) - math.pi
	a += d * math.min(1, k)
	return Vector3.new(math.sin(a), 0, math.cos(a))
end

local function rebuild(player: Player, e: Entry)
	local raw = player:GetAttribute("PetsShown")
	e.Raw = if type(raw) == "string" then raw else nil
	local list: any = nil
	if type(raw) == "string" and raw ~= "" and raw ~= "[]" then
		local ok, res = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		list = if ok and type(res) == "table" then res else nil
	end
	-- equip / unequip touches: only for a real change, not the hunt / tower hiding every follower (server rule)
	local hidden = (player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true) or State.Teleport == true
	-- in a hunt only the pet helper follows (owner pick 2026-10-15, server Profiles.huntHelper marks it Helper); the
	-- lobby list may still be on its way when the hunt starts, so anything not marked Helper stays hidden there
	local inHunt = player:GetAttribute("MatchKey") ~= nil or (player == Players.LocalPlayer and State.Match ~= nil)
	if inHunt and list then
		local keep = {}
		for _, spec in list :: { any } do
			if type(spec) == "table" and spec.Helper == true and #keep < 1 then
				table.insert(keep, spec)
			end
		end
		list = if #keep > 0 then keep else nil
	end
	local newIds: { [string]: boolean } = {}
	for _, spec in (list or {}) :: { any } do
		if type(spec) == "table" and spec.Id ~= nil then
			newIds[tostring(spec.Id)] = true
		end
	end
	if hidden then
		-- no followers in the pet tower or a Pet Battle (the fighting pets are the show there)
		list = nil
	end
	local known = if hidden or inHunt then nil else e.Known -- entering or leaving a hunt is not an equip change
	if known then
		for i = #e.Pets, 1, -1 do
			local p = e.Pets[i]
			if p.Id ~= nil and not newIds[tostring(p.Id)] then
				table.remove(e.Pets, i)
				if p.Fx then
					PetFx.destroy(p.Fx)
				end
				dust(p.Model, false)
				PetMoodFx.shrinkAway(p.Model)
			end
		end
	end
	if not hidden and not inHunt and type(raw) == "string" then
		e.Known = newIds
	end
	clearPets(e)
	if not list then
		return
	end
	-- equipped pets sit in slots by rarity: the rarest first (stable for equal rarities)
	local ordered: { any } = {}
	for k, spec in list :: { any } do
		ordered[k] = { Spec = spec, K = k }
	end
	table.sort(ordered, function(a, b)
		local ra, rb = rankOf(a.Spec), rankOf(b.Spec)
		if ra ~= rb then
			return ra > rb
		end
		return a.K < b.K
	end)
	for i, o in ordered do
		local spec = o.Spec
		if i > #SLOTS then
			break
		end
		if type(spec) == "table" and type(spec.Mineral) == "string" then
			local s = SCALE * math.clamp(GeodeGen.visualScale(tonumber(spec.Mass) or 1), 0.85, 1.3)
			local okB, m = pcall(PetModel.build, spec, { Scale = s, Lod = true, NoLight = true })
			if okB and m then
				-- followers are fitted to one set height (bug 243), so big pets never fill the screen or clip their
				-- owner; the lobby displays and the Pet Book keep the full size
				local vary = math.clamp(GeodeGen.visualScale(tonumber(spec.Mass) or 1), 0.92, 1.1)
				local grow = PetFlair.evolveScale(spec.Evolve) -- evolved pets follow a bit bigger
				PetModel.fitHeight(m, FOLLOW_H * vary * grow, FOLLOW_W * vary * grow)
			end
			if okB and Motion and m:GetAttribute("Mesh") then
				pcall(Motion.start, m)
			end
			if okB and m then
				m.Name = "Pet_" .. player.UserId .. "_" .. i
				require(script.Parent.PetTrail).attach(m, spec.Modifier) -- Golden / Rainbow sparkle trail
				local head = m:FindFirstChild("Head")
				local tag: BillboardGui? = nil
				-- pet type colour (the tag pill); no glowing disc under the pet (owner: it read as a glowing plate)
				local kind = PetRules.kindOf(spec)
				local kindColor = PetRules.kindColor(kind)
				calmFx(m)
				if head and head:IsA("BasePart") then
					local bb = Instance.new("BillboardGui")
					bb.Name = "PetTag"
					bb.Adornee = head
					bb.Size = UDim2.fromOffset(170, 30)
					bb.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 0.9, 0)
					bb.MaxDistance = 35
					bb.AlwaysOnTop = false
					bb.LightInfluence = 0
					bb.ResetOnSpawn = false
					local rarity = tostring(spec.Rarity or "Common")
					-- the nickname (server-filtered) when the owner named the pet, else rarity + species
					local nick = if type(spec.Nickname) == "string" and spec.Nickname ~= "" then spec.Nickname else nil
					local row = Instance.new("Frame")
					row.Name = "Row"
					row.BackgroundTransparency = 1
					row.Size = UDim2.fromScale(1, 1)
					row.Parent = bb
					-- type icon on a small glow pill in the type colour
					local pill = Instance.new("Frame")
					pill.Name = "TypeGlow"
					pill.BackgroundColor3 = kindColor
					pill.BackgroundTransparency = 0.45
					pill.Position = UDim2.fromOffset(0, 3)
					pill.Size = UDim2.fromOffset(24, 24)
					pill.Parent = row
					UI.corner(pill, 12)
					UI.icon(pill, TYPE_ICON[kind] or "boostCoins", 20, { Position = UDim2.fromOffset(2, 2) })
					-- full dark outline so pale rarity colours still read on the snow
					UI.text(row, if nick then nick else string.upper(rarity) .. " " .. PetModel.name(spec.Mineral), {
						TextSize = 14, Font = UI.Head, Outline = "Strong", Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -28, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = (Config.RarityTextColors :: any)[rarity] or Color3.new(1, 1, 1),
					})
					bb.Parent = m
					tag = bb
				end
				local parts: { BasePart } = {}
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						table.insert(parts, d)
					end
				end
				local cy = m:GetAttribute("CentreY")
				local okF, fx = pcall(PetFx.attach, m, spec, s, ensureFolder())
				local petFx: PetFx.Fx? = if okF then fx else nil
				if petFx then
					table.insert(parts, petFx.Shadow) -- fades with the pet near the camera
				end
				m.Parent = ensureFolder()
				-- blinking: the procedural pets' round eyes (and shines) squash shut now and then; mesh pets skip
				local eyes: { BasePart } = {}
				local eyeSizes: { Vector3 } = {}
				if m:GetAttribute("Mesh") ~= true then
					for _, d in m:GetDescendants() do
						if d:IsA("Part") and (d.Name == "Eye" or d.Name == "Shine") and d.Shape == Enum.PartType.Ball then
							table.insert(eyes, d)
							table.insert(eyeSizes, d.Size)
						end
					end
				end
				table.insert(e.Pets, { Id = spec.Id, Fx = petFx, Model = m, Pos = Vector3.zero, Look = Vector3.new(0, 0, -1), Phase = i * 1.3, Height = 0, Parts = parts, Tag = tag, CentreY = if type(cy) == "number" then cy else 1, Fade = 0,
					Flying = FLYERS[tostring(m:GetAttribute("Kind"))] == true, Size = s / SCALE, Far = false,
					Eyes = eyes, EyeSizes = eyeSizes, NextBlink = os.clock() + 1 + math.random() * 4, BlinkEnd = 0, HopS = 0,
					JumpT = 0, BounceT = 0, SpinT = 0, Bank = 0, Droop = 0, Sleepy = false, EyesShut = false, Zzz = nil, LookSet = nil, Rate = 1 })
				if known and spec.Id ~= nil and not known[tostring(spec.Id)] then
					PetMoodFx.hearts(m) -- just equipped
					startBounce(e.Pets[#e.Pets]) -- and a happy bounce
				end
			end
		end
	end
	-- spread the slots so big pets never overlap their neighbours (slot gap is ~7.6 studs)
	local maxR = 0
	for _, p in e.Pets do
		local r = p.Model:GetAttribute("Radius")
		maxR = math.max(maxR, if type(r) == "number" then r else p.Size * 1.3)
	end
	e.Spread = math.max(1, (2 * maxR + 0.5) / 7.6)
	-- snap into place on the next frame
	for _, p in e.Pets do
		p.Height = -1
	end
end

local function track(player: Player)
	if entries[player] then
		return
	end
	local e: Entry = { Pets = {}, Raw = nil, Conns = {}, Spread = 1, Air = 0, Known = nil, WasJump = false, Still = 0 }
	entries[player] = e
	table.insert(e.Conns, player:GetAttributeChangedSignal("PetsShown"):Connect(function()
		rebuild(player, e)
	end))
	for _, attr in { "MatchKey", "InTower", "InBattle" } do
		table.insert(e.Conns, player:GetAttributeChangedSignal(attr):Connect(function()
			rebuild(player, e)
		end))
	end
	if player == Players.LocalPlayer then
		local inHunt = State.Match ~= nil
		table.insert(e.Conns, State.Changed.Event:Connect(function(what)
			if what == "Match" and (State.Match ~= nil) ~= inHunt then
				inHunt = State.Match ~= nil
				rebuild(player, e)
			end
		end))
	end
	table.insert(e.Conns, player.CharacterRemoving:Connect(function()
		for _, p in e.Pets do
			p.Height = -1 -- teleport to the new character instead of gliding across the map
			p.Model.Parent = nil
			if p.Fx then
				PetFx.setShown(p.Fx, false, ensureFolder())
			end
		end
	end))
	rebuild(player, e)
end

local function untrack(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	for _, c in e.Conns do
		c:Disconnect()
	end
	clearPets(e)
	entries[player] = nil
end

-- distance from point p to the segment a..b
local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 1e-6 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (a + ab * t - p).Magnitude
end

-- fade a pet toward 1 when it is too close to the camera or blocks the view of the local head
local function fade(p: Pet, centre: Vector3, camPos: Vector3, headPos: Vector3?, dt: number)
	local goal = 0
	if (centre - camPos).Magnitude < FADE_NEAR or (headPos and segDist(centre, camPos, headPos) < FADE_LINE) then
		goal = 1
	end
	if p.Fade == goal then
		return
	end
	local f = p.Fade + (goal - p.Fade) * math.min(1, dt * 10)
	if math.abs(goal - f) < 0.02 then
		f = goal
	end
	p.Fade = f
	for _, part in p.Parts do
		part.LocalTransparencyModifier = f
	end
	if p.Tag then
		p.Tag.Enabled = f < 0.5
	end
end

-- Ground snap: each pet raycasts down at its own spot (throttled, staggered) so it stands on slopes, hills and
-- cliffs instead of floating or sinking at the owner's height. Characters and the pets folder are excluded.
local RAY_EVERY = 0.12
local RAY_UP, RAY_DOWN = 6, 30
local groundY: { [Pet]: number } = setmetatable({} :: any, { __mode = "k" })
local smoothY: { [Pet]: number } = setmetatable({} :: any, { __mode = "k" })
local nextRay: { [Pet]: number } = setmetatable({} :: any, { __mode = "k" })
local farPivot: { [Pet]: number } = setmetatable({} :: any, { __mode = "k" }) -- next low-rate move of a skipped pet
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true -- only solid ground: no leaves, effects or invisible non-colliding helpers

local function petGround(p: Pet, goal: Vector3, ownerGround: number, now: number, dt: number): number
	local y = smoothY[p] or ownerGround
	if now >= (nextRay[p] or 0) then
		nextRay[p] = now + RAY_EVERY + math.random() * 0.04
		local ignore: { Instance } = { ensureFolder() }
		for _, pl in Players:GetPlayers() do
			if pl.Character then
				table.insert(ignore, pl.Character)
			end
		end
		rayParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(Vector3.new(goal.X, ownerGround + RAY_UP, goal.Z), Vector3.new(0, -(RAY_UP + RAY_DOWN), 0), rayParams)
		local target = if hit then hit.Position.Y else ownerGround
		if groundY[p] == nil then
			y = target -- first sample: snap, don't glide
		end
		groundY[p] = target
	end
	local want = groundY[p] or y
	y = y + (want - y) * math.min(1, dt * 12)
	smoothY[p] = y
	return y
end

-- Simple avoidance (owner video: followers walked through props and in front of the player). A pet whose slot is
-- behind its owner goes round the owner's side instead of straight across the front, and a short sideways probe
-- slides it along solid props instead of through them. No pathfinding.
local AVOID_OWNER = 4.5 -- studs: the ring kept round the owner while a pet walks round
local probeParams = RaycastParams.new()
probeParams.FilterType = Enum.RaycastFilterType.Exclude
probeParams.IgnoreWater = true
probeParams.RespectCanCollide = true -- solid props only (no leaves, effects or invisible helpers)

local function roundOwner(p: Pet, goal: Vector3, ownerPos: Vector3, look: Vector3): Vector3
	local rel = Vector3.new(p.Pos.X - ownerPos.X, 0, p.Pos.Z - ownerPos.Z)
	local relGoal = Vector3.new(goal.X - ownerPos.X, 0, goal.Z - ownerPos.Z)
	if rel:Dot(look) < -1 or relGoal:Dot(look) > 0 then
		return goal -- already behind (or the slot is not behind): straight there
	end
	local right = look:Cross(Vector3.yAxis)
	local side = if rel:Dot(right) + relGoal:Dot(right) * 0.5 >= 0 then 1 else -1
	local ring = math.max(AVOID_OWNER, rel.Magnitude)
	local via = ownerPos + right * side * ring - look * 1.5
	return Vector3.new(via.X, goal.Y, via.Z)
end

local function slideOffProps(p: Pet, prev: Vector3, ignore: { Instance }): Vector3
	local move = Vector3.new(p.Pos.X - prev.X, 0, p.Pos.Z - prev.Z)
	local len = move.Magnitude
	if len < 1e-3 then
		return p.Pos
	end
	local r = p.Model:GetAttribute("Radius")
	local radius = math.clamp(if type(r) == "number" then r * 0.6 else p.Size, 0.6, 3)
	probeParams.FilterDescendantsInstances = ignore
	local from = prev + Vector3.new(0, 1.2, 0)
	local hit = Workspace:Raycast(from, move.Unit * (len + radius), probeParams)
	if not hit or hit.Normal.Y > 0.6 then
		return p.Pos -- free, or only a slope of the ground ahead
	end
	local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if n.Magnitude < 1e-3 then
		return p.Pos
	end
	n = n.Unit
	local into = move:Dot(n)
	if into < 0 then
		move -= n * into -- keep only the part along the prop's face
	end
	return Vector3.new(prev.X + move.X, p.Pos.Y, prev.Z + move.Z)
end

-- Solid props the probe ray cannot see (polish #146). The lobby's fences, signs and stall counters are decor that
-- does not answer raycasts (KitPlace decor policy: CanQuery off) with an invisible collision box beside it
-- (KitPlace.blocker: CanCollide on, CanQuery off), so the ray above never hit them and pets walked straight through.
-- Spatial queries skip CanQuery-off parts too, so the client keeps its own index: every anchored, colliding part
-- (blockers included) in a coarse XZ grid, kept up to date as parts come and go. A walking pet is pushed out of any
-- such box it overlaps between two probe heights above its ground (low steps and the floor never count), in short
-- sub-steps so a thin fence cannot be skipped over in one frame.
local CELL = 12 -- studs per grid cell
local MAX_SPAN = 200 -- studs: wider parts (ground slabs, terrain stand-ins) are not obstacles
local PROBE_LOW, PROBE_HIGH = 1.4, 2.6 -- studs above the pet's ground (steps up to 1.4 studs stay walkable)
local cells: { [number]: { [BasePart]: boolean } } = {} -- key: cellKey(gx, gz)
local cellsOf: { [BasePart]: { number } } = {}

-- one number per grid cell (Vector2 keys would compare by identity, not value)
local function cellKey(gx: number, gz: number): number
	return gx * 65536 + gz
end

local function unindex(part: BasePart)
	local keys = cellsOf[part]
	if not keys then
		return
	end
	for _, k in keys do
		local c = cells[k]
		if c then
			c[part] = nil
			if next(c) == nil then
				cells[k] = nil
			end
		end
	end
	cellsOf[part] = nil
end

local function index(part: BasePart)
	if cellsOf[part] or not part.Anchored or not part.CanCollide then
		return
	end
	if folder and part:IsDescendantOf(folder) then
		return
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return -- characters and NPCs move; never obstacles
	end
	local cf, size = part.CFrame, part.Size
	-- world-axis extent of the (possibly rotated) box
	local ex = math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z
	local ez = math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
	if ex > MAX_SPAN or ez > MAX_SPAN or ex ~= ex or ez ~= ez then
		return
	end
	local p = cf.Position
	local keys: { number } = {}
	for gx = math.floor((p.X - ex / 2) / CELL), math.floor((p.X + ex / 2) / CELL) do
		for gz = math.floor((p.Z - ez / 2) / CELL), math.floor((p.Z + ez / 2) / CELL) do
			local k = cellKey(gx, gz)
			local c = cells[k]
			if not c then
				c = {}
				cells[k] = c
			end
			(c :: { [BasePart]: boolean })[part] = true
			table.insert(keys, k)
		end
	end
	cellsOf[part] = keys
end

local indexStarted = false
local function startIndex()
	if indexStarted then
		return
	end
	indexStarted = true
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			index(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			index(d)
		end
	end)
	Workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			unindex(d)
		end
	end)
end

-- Reused by pushOutOfBoxes (called per pet per sub-step): no per-call tables.
local PROBE_HEIGHTS = { PROBE_LOW, PROBE_HIGH }
local seenBuf: { [BasePart]: boolean } = {}

-- Pushes the XZ point `pos` (at ground height `gy`) out of every indexed box it overlaps within `radius`.
local function pushOutOfBoxes(pos: Vector3, gy: number, radius: number): Vector3
	local x, z = pos.X, pos.Z
	local seen = seenBuf
	for _ = 1, 2 do
		local moved = false
		table.clear(seen)
		for gx = math.floor((x - radius) / CELL), math.floor((x + radius) / CELL) do
			for gz = math.floor((z - radius) / CELL), math.floor((z + radius) / CELL) do
				local c = cells[cellKey(gx, gz)]
				if not c then
					continue
				end
				for part in c do
					if seen[part] then
						continue
					end
					seen[part] = true
					if not part.Parent or not part.CanCollide then
						continue
					end
					local cf, half = part.CFrame, part.Size / 2
					for _, hy in PROBE_HEIGHTS do
						local probe = Vector3.new(x, gy + hy, z)
						local l = cf:PointToObjectSpace(probe)
						local cl = Vector3.new(math.clamp(l.X, -half.X, half.X), math.clamp(l.Y, -half.Y, half.Y), math.clamp(l.Z, -half.Z, half.Z))
						local w = cf:PointToWorldSpace(cl)
						if math.abs(w.Y - probe.Y) > 0.05 then
							continue -- the box is wholly above or below this probe height here
						end
						local dx, dz = x - w.X, z - w.Z
						local d = math.sqrt(dx * dx + dz * dz)
						if d >= radius then
							continue
						end
						if d > 1e-3 then
							x += dx / d * (radius - d)
							z += dz / d * (radius - d)
						else
							-- centre inside the box: out through the nearest side face (box X or Z)
							local px, pz = half.X - math.abs(l.X), half.Z - math.abs(l.Z)
							local outL = if px <= pz then Vector3.new((if l.X >= 0 then 1 else -1) * (px + radius), 0, 0) else Vector3.new(0, 0, (if l.Z >= 0 then 1 else -1) * (pz + radius))
							local o = cf:VectorToWorldSpace(outL)
							x += o.X
							z += o.Z
						end
						moved = true
						break
					end
				end
			end
		end
		if not moved then
			break
		end
	end
	table.clear(seen) -- drop part references between calls
	return Vector3.new(x, pos.Y, z)
end

-- Moves a pet from `prev` to `p.Pos` in sub-steps no longer than half its radius, pushed out of solid boxes on the way.
local function walkOutOfBoxes(p: Pet, prev: Vector3, radius: number): Vector3
	local to = p.Pos
	local dx, dz = to.X - prev.X, to.Z - prev.Z
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.clamp(math.ceil(len / math.max(radius * 0.5, 0.3)), 1, 8)
	local at = prev
	for _ = 1, n do
		local target = Vector3.new(at.X + dx / n, to.Y, at.Z + dz / n)
		at = pushOutOfBoxes(target, prev.Y, radius)
	end
	return Vector3.new(at.X, to.Y, at.Z)
end

-- Personal space (polish #147): a pet never ends inside or on top of its owner; it stops on a ring round them.
local OWNER_GAP = 2.4 -- studs between the owner's centre and the pet's edge

local function petRadius(p: Pet): number
	local r = p.Model:GetAttribute("Radius")
	return math.clamp(if type(r) == "number" then r * 0.8 else p.Size, 0.6, 3.6)
end

local function keepOffOwner(pos: Vector3, ownerPos: Vector3, look: Vector3, radius: number): Vector3
	local dx, dz = pos.X - ownerPos.X, pos.Z - ownerPos.Z
	local d = math.sqrt(dx * dx + dz * dz)
	local keep = OWNER_GAP + radius
	if d >= keep then
		return pos
	end
	if d < 1e-3 then
		dx, dz, d = -look.X, -look.Z, 1 -- straight behind
	end
	return Vector3.new(ownerPos.X + dx / d * keep, pos.Y, ownerPos.Z + dz / d * keep)
end

local function step(dt: number)
	local t = os.clock()
	local alpha = 1 - math.exp(-dt * 7)
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local camLook = if cam then cam.CFrame.LookVector else Vector3.zAxis
	local myChar = Players.LocalPlayer and Players.LocalPlayer.Character
	local myHead = myChar and myChar:FindFirstChild("Head")
	local headPos: Vector3? = if myHead and myHead:IsA("BasePart") then myHead.Position else nil
	local probeIgnore: { Instance }? = nil -- built once per frame, only when a pet moves near the camera
	for player, e in entries do
		if #e.Pets == 0 then
			continue
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not hum then
			for _, p in e.Pets do
				p.Model.Parent = nil
				if p.Fx then
					PetFx.setShown(p.Fx, false, ensureFolder())
				end
			end
			continue
		end
		local rcf = root.CFrame
		local ground = rcf.Position.Y - root.Size.Y / 2 - hum.HipHeight
		local flatLook = Vector3.new(rcf.LookVector.X, 0, rcf.LookVector.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1)
		end
		flatLook = flatLook.Unit
		local yawCF = CFrame.lookAt(Vector3.zero, flatLook)
		-- the owner jumps: the pets stop where they are for a moment (at most 0.7 s, so they never fall behind)
		local st = hum:GetState()
		if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
			e.Air += dt
		else
			e.Air = 0
		end
		local paused = e.Air > 0 and e.Air < 0.7
		-- the owner just jumped: every pet hops too, a beat apart
		local jumping = st == Enum.HumanoidStateType.Jumping
		if jumping and not e.WasJump then
			for i, p in e.Pets do
				if Motion and p.Model:GetAttribute("Mesh") and type(Motion.hop) == "function" then
					task.delay((i - 1) * 0.07, pcall, Motion.hop, p.Model)
				else
					p.JumpT = t + (i - 1) * 0.07
				end
			end
		end
		e.WasJump = jumping
		-- the owner stands still a long while: the pets get sleepy; any move wakes them
		local v = root.AssemblyLinearVelocity
		if e.Air == 0 and v.X * v.X + v.Z * v.Z < 0.25 then
			e.Still += dt
		else
			e.Still = 0
		end
		local sleepy = e.Still >= SLEEP_AFTER
		for i, p in e.Pets do
			local slot = (SLOTS[i] or SLOTS[1]) * Vector3.new(e.Spread, 1, e.Spread)
			local goal = Vector3.new(rcf.Position.X, ground, rcf.Position.Z) + yawCF:VectorToWorldSpace(slot)
			if p.Height >= 0 then
				local dx, dz = goal.X - p.Pos.X, goal.Z - p.Pos.Z
				if dx * dx + dz * dz > SNAP_FAR * SNAP_FAR then
					-- left far behind: catch up at once with a small poof
					p.Pos = goal
					groundY[p] = nil
					smoothY[p] = nil
					nextRay[p] = 0
					p.Look = flatLook
					pcall(function()
						require(script.Parent.HitFx).poof(goal)
					end)
				end
			end
			if p.Height < 0 then
				p.Pos = goal
				p.Height = 0
				groundY[p] = nil
				smoothY[p] = nil
				nextRay[p] = 0
				p.Look = flatLook
			end
			local prev = p.Pos
			-- ease in near the slot: critically damped, so it never overshoots; round the owner's side, not across the front
			if not paused then
				p.Pos = p.Pos:Lerp(roundOwner(p, goal, rcf.Position, flatLook), alpha)
				local near = p.Pos - camPos
				if near:Dot(near) < FAR_FX * FAR_FX then
					if not probeIgnore then
						local list: { Instance } = { ensureFolder() }
						for _, pl in Players:GetPlayers() do
							if pl.Character then
								table.insert(list, pl.Character)
							end
						end
						probeIgnore = list
					end
					p.Pos = slideOffProps(p, prev, probeIgnore :: { Instance })
					p.Pos = walkOutOfBoxes(p, prev, petRadius(p))
				end
				p.Pos = keepOffOwner(p.Pos, rcf.Position, flatLook, petRadius(p))
			end
			-- far from the camera or behind it: skip ground rays, hop, effects and animation (cheap check)
			local toCam = p.Pos - camPos
			local d2 = toCam:Dot(toCam)
			local farNow = if p.Far then d2 > FAR_FX_BACK * FAR_FX_BACK else d2 > FAR_FX * FAR_FX
			if farNow ~= p.Far then
				p.Far = farNow
				if p.Fx then
					PetFx.setFar(p.Fx, p.Model, farNow)
				end
			end
			if farNow or (cam and d2 > 225 and toCam:Dot(camLook) < 0) then
				if not farNow and p.Model.Parent == nil then
					p.Model.Parent = ensureFolder()
				end
				if p.Model:GetAttribute("Moving") then
					-- skipped pets stop their walk dust (it comes back on the next visible step)
					p.Model:SetAttribute("Moving", false)
					dust(p.Model, false)
				end
				if p.BlinkEnd > 0 then
					-- a blink cut short by the skip: open the eyes again
					for k, eye in p.Eyes do
						eye.Size = p.EyeSizes[k]
					end
					p.BlinkEnd = 0
				end
				if p.EyesShut then
					for k, eye in p.Eyes do
						eye.Size = p.EyeSizes[k]
					end
					p.EyesShut = false
				end
				-- skipped pets still follow a few times a second (no rays, hop or animation), so they never stand frozen
				if p.Model.Parent and t >= (farPivot[p] or 0) then
					farPivot[p] = t + 0.25
					local look = if p.Look.Magnitude > 0.01 then p.Look.Unit else flatLook
					local at = p.Pos + Vector3.new(0, if p.Flying then 1.1 else 0, 0)
					local cf = CFrame.lookAt(at, at + look)
					if not (Motion and p.Model:GetAttribute("Mesh") and pcall(Motion.setBase, p.Model, cf)) then
						p.Model:PivotTo(cf)
					end
				end
				continue
			end
			local gy = petGround(p, p.Pos, goal.Y, t, dt)
			p.Pos = Vector3.new(p.Pos.X, gy, p.Pos.Z)
			local move = p.Pos - prev
			local speed = Vector3.new(move.X, 0, move.Z).Magnitude / math.max(dt, 1e-3)
			local hop: number
			local bankGoal = 0
			local lift = 0
			if p.Flying then
				lift = 1.1 + math.sin(t * 2.6 + i * 1.7) * 0.25 -- flyers hover and bob higher than walkers
			end
			if speed > 0.6 then
				-- big pets hop slower, small ones quicker
				p.Phase += dt * math.clamp(speed, 4, 14) * 0.9 / math.clamp(p.Size, 0.8, 1.4)
				local sn = math.sin(p.Phase)
				hop = sn * sn * (if p.Flying then 0.3 else 0.55) -- zero slope at the ground: a soft landing
				local a0 = math.atan2(p.Look.X, p.Look.Z)
				p.Look = turnToward(p.Look, move, dt * 10)
				-- bank into the turn (lean toward its inside; flyers bank harder)
				local da = (math.atan2(p.Look.X, p.Look.Z) - a0 + math.pi) % (2 * math.pi) - math.pi
				bankGoal = math.clamp(da / math.max(dt, 1e-3) * 0.05, -0.28, 0.28) * (if p.Flying then 1.6 else 1)
			else
				hop = (math.sin(t * 2 + i) + 1) * (if p.Flying then 0.1 else 0.04) -- idle bob
				-- owner stopped: turn to look at them
				local toOwner = Vector3.new(rcf.Position.X - p.Pos.X, 0, rcf.Position.Z - p.Pos.Z)
				local want = if toOwner.Magnitude > 0.3 then toOwner.Unit else flatLook
				-- now and then glance at a neighbouring pet of the same owner for about a second
				local n = #e.Pets
				if n > 1 and (t * 0.12 + i * 0.37) % 1 < 0.14 then
					local other = e.Pets[i % n + 1]
					local d = Vector3.new(other.Pos.X - p.Pos.X, 0, other.Pos.Z - p.Pos.Z)
					if d.Magnitude > 0.3 and d.Magnitude < 16 then
						want = d.Unit
					end
				end
				p.Look = turnToward(p.Look, want, dt * 4)
			end
			-- smooth the hop so starting / stopping never snaps the pet's height
			p.HopS = if p.HopS == 0 and hop ~= 0 then hop else p.HopS + (hop - p.HopS) * math.min(1, dt * 14)
			hop = p.HopS
			p.Bank += (bankGoal - p.Bank) * math.min(1, dt * 8)
			-- the owner's jump: a quick hop (procedural pets; mesh pets hop in PetMotion)
			local jumpH = 0
			if p.JumpT > 0 then
				local k = (t - p.JumpT) / JUMP_TIME
				if k >= 1 then
					p.JumpT = 0
				elseif k > 0 then
					jumpH = math.sin(k * math.pi) * 0.9 * math.clamp(p.Size, 0.8, 1.3)
				end
			end
			-- level-up spin: one full turn with a small lift
			local spin = 0
			if p.SpinT > 0 then
				local k = (t - p.SpinT) / SPIN_TIME
				if k >= 1 then
					p.SpinT = 0
				else
					spin = (k * k * (3 - 2 * k)) * math.pi * 2
					jumpH += math.sin(k * math.pi) * 0.5
				end
			end
			-- happy bounce: two hops (PetFx squashes and stretches the body)
			if p.BounceT > 0 then
				local k = (t - p.BounceT) / Rules.BOUNCE_TIME
				if k >= 1 then
					p.BounceT = 0
				elseif k > 0 then
					local h = Rules.squash(k)
					jumpH += h * math.clamp(p.Size, 0.8, 1.3)
				end
			end
			-- sleepy: Zzz bubble, half-shut eyes and a small droop (mesh pets droop their head in PetMotion)
			if sleepy ~= p.Sleepy then
				p.Sleepy = sleepy
				p.Model:SetAttribute("Sleepy", sleepy)
				p.Zzz = PetMoodFx.setZzz(p.Model, sleepy)
			end
			if p.Zzz then
				PetMoodFx.updateZzz(p.Zzz, t, i * 0.33)
			end
			p.Droop += ((if sleepy then 0.08 else 0) - p.Droop) * math.min(1, dt * 2)
			-- blink
			if #p.Eyes > 0 and sleepy then
				if not p.EyesShut then
					for k, eye in p.Eyes do
						local sz = p.EyeSizes[k]
						eye.Size = Vector3.new(sz.X, sz.Y * 0.3, sz.Z)
					end
					p.EyesShut = true
					p.BlinkEnd = 0
				end
			elseif p.EyesShut then
				for k, eye in p.Eyes do
					eye.Size = p.EyeSizes[k]
				end
				p.EyesShut = false
				p.NextBlink = t + 0.4 -- a waking blink
			elseif #p.Eyes > 0 then
				if p.BlinkEnd > 0 and t >= p.BlinkEnd then
					for k, eye in p.Eyes do
						eye.Size = p.EyeSizes[k]
					end
					p.BlinkEnd = 0
					p.NextBlink = t + 2.5 + math.random() * 3.5
				elseif p.BlinkEnd == 0 and t >= p.NextBlink then
					for k, eye in p.Eyes do
						local sz = p.EyeSizes[k]
						eye.Size = Vector3.new(sz.X, sz.Y * 0.1, sz.Z)
					end
					p.BlinkEnd = t + 0.13
				end
			end
			local look = if p.Look.Magnitude > 0.01 then p.Look.Unit else flatLook
			local at = p.Pos + Vector3.new(0, hop + lift + jumpH, 0)
			local tilt = CFrame.Angles(0, spin, 0) * CFrame.Angles(-p.Droop, 0, p.Bank)
			if not p.Model.Parent then
				p.Model.Parent = ensureFolder()
			end
			if p.Fx then
				PetFx.setShown(p.Fx, true, ensureFolder())
				local mesh = Motion ~= nil and p.Model:GetAttribute("Mesh") == true
				PetFx.update(p.Fx, p.Pos, if mesh then 0 else hop, p.Phase, speed > 0.6 and not mesh, t, camPos, lift + jumpH, speed > 0.6)
			end
			if Motion and p.Model:GetAttribute("Mesh") then
				-- the owner's PetMotion animates walk / idle around this base
				local moving = speed > 0.6
				if p.Model:GetAttribute("Moving") ~= moving then
					p.Model:SetAttribute("Moving", moving)
					dust(p.Model, moving)
				end
				-- a sprinting owner (speed boots) makes the pet run (owner's "run" clip when PetClips has it); a
				-- "train" clip set by the Train card is left alone
				local cur = p.Model:GetAttribute("Anim")
				if cur == nil or cur == "run" then
					MotionBridge.setAnim(p.Model, if speed > 22 then "run" else nil)
				end
				-- step speed follows the owner's speed (speed boots: quicker steps), in 0.1 steps
				local rate = if moving then math.floor(math.clamp(speed / 16, 0.8, 1.8) * 10 + 0.5) / 10 else 1
				if rate ~= p.Rate then
					p.Rate = rate
					p.Model:SetAttribute("WalkRate", rate)
				end
				-- stopped: the head turns to the owner's face (eased and limited in PetMotion)
				local head = (char :: Model):FindFirstChild("Head")
				local want: Vector3? = if not moving and head and head:IsA("BasePart") then head.Position else nil
				if want ~= p.LookSet and (want == nil or p.LookSet == nil or (want - (p.LookSet :: Vector3)).Magnitude > 0.25) then
					p.LookSet = want
					p.Model:SetAttribute("LookAt", want)
				end
				local base = p.Pos + Vector3.new(0, lift + jumpH, 0)
				pcall(Motion.setBase, p.Model, CFrame.lookAt(base, base + look) * CFrame.Angles(0, 0, p.Bank))
			else
				p.Model:PivotTo(CFrame.lookAt(at, at + look) * tilt)
			end
			if cam then
				fade(p, at + Vector3.new(0, p.CentreY, 0), camPos, headPos, dt)
			end
		end
	end
end

-- The follower model of one of a player's pets (by pet Id), or nil when it is not following / not shown.
function PetFollow.modelFor(player: Player, id: any): Model?
	local e = entries[player]
	if not e then
		return nil
	end
	for _, p in e.Pets do
		if p.Id ~= nil and tostring(p.Id) == tostring(id) and p.Model.Parent then
			return p.Model
		end
	end
	return nil
end

-- A follower (by pet Id) spins once on the spot (level up). Reduce Motion: nothing.
function PetFollow.spin(player: Player, id: any)
	local e = entries[player]
	if not e or UI.Reduced or (State.Profile and State.Profile.Settings and State.Profile.Settings.ReducedMotion == true) then
		return
	end
	for _, p in e.Pets do
		if p.Id ~= nil and tostring(p.Id) == tostring(id) and p.Model.Parent then
			if Motion and p.Model:GetAttribute("Mesh") and type(Motion.spin) == "function" then
				pcall(Motion.spin, p.Model)
			else
				p.SpinT = os.clock()
			end
		end
	end
end

-- A follower (by pet Id) does a happy bounce: two hops with squash and stretch and a star sparkle (petting, a win, a
-- training goal). Reduce Motion: only the sparkle.
function PetFollow.bounce(player: Player, id: any)
	local e = entries[player]
	if not e then
		return
	end
	for _, p in e.Pets do
		if p.Id ~= nil and tostring(p.Id) == tostring(id) and p.Model.Parent then
			startBounce(p)
		end
	end
end

-- Every follower model shown right now, with its owner and pet id (tap-to-inspect, PetInspectTap).
function PetFollow.shown(): { { Player: Player, Id: string, Model: Model } }
	local out = {}
	for pl, e in entries do
		for _, p in e.Pets do
			if p.Id ~= nil and p.Model.Parent then
				table.insert(out, { Player = pl, Id = tostring(p.Id), Model = p.Model })
			end
		end
	end
	return out
end

-- Every shown follower of `player` does its victory dance (a beat apart).
function PetFollow.celebrate(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	local Bridge = require(script.Parent.PetMotionBridge)
	for i, p in e.Pets do
		if p.Model.Parent then
			task.delay((i - 1) * 0.15, Bridge.celebrate, p.Model)
		end
	end
end

local started = false
function PetFollow.start()
	if started then
		return
	end
	started = true
	for _, pl in Players:GetPlayers() do
		track(pl)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	task.defer(startIndex) -- the obstacle index (one pass over the world, then kept up to date)
	RunService.RenderStepped:Connect(step)
end

return PetFollow
