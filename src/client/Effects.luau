--!strict
-- Small client-only screen and world effects, all pooled, all <= 1 s per piece, no camera shake:
--   cashFly      few little coins fly from a sale spot to the HUD cash row
--   revealBurst  tinted bloom + bounded sparks from the cavity (target reveal)
--   shimmer      soft sparkles around the geode in the reveal
--   confetti     gentle 2 s confetti for the winner (spawned over 2 s, each piece lives <= 1 s)
--   glint        machine-recovery sparkle at a world position (hook point for the machine code)
-- Reduced motion shows nothing moving; Low effects halves the counts.
-- Nothing here is replicated or authoritative; it only decorates what the server already decided.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local Effects = {}

local MAX_PIECES = 40
local LIFE_MAX = 1.0

local gui: ScreenGui? = nil
local probe: Frame? = nil
local cashTarget: GuiObject? = nil
local free: { Frame } = {}
local used = 0
local inUse: { [Frame]: boolean } = {}
local session = 0 -- bumped by clear(), stops running spawners

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return settings().ReducedMotion == true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

local function layer(): (ScreenGui, Frame)
	if gui and probe and gui.Parent then
		return gui :: ScreenGui, probe :: Frame
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "CrackTheRocksFx"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = false
	sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 30
	sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local p = Instance.new("Frame")
	p.Name = "Probe"
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.Size = UDim2.fromScale(1, 1)
	p.Active = false
	p.Parent = sg
	gui, probe = sg, p
	free = {}
	used = 0
	inUse = {}
	return sg, p
end

-- Per-frame use counter and live tweens: a delayed release only frees the use it was scheduled for, and a recycled
-- frame never keeps animating its old use.
local uses: { [Frame]: number } = {}
local tweens: { [Frame]: { Tween } } = {}

local function track(f: Frame, tw: Tween)
	local list = tweens[f]
	if not list then
		list = {}
		tweens[f] = list
	end
	table.insert(list, tw)
	tw:Play()
end

-- A pooled rounded piece (coin, spark or confetti strip).
local function piece(parent: Instance): Frame?
	if used >= MAX_PIECES then
		return nil
	end
	used += 1
	local fr: Frame
	local pooled = table.remove(free)
	if pooled then
		fr = pooled
		-- the reveal bloom rounds its piece into a circle; pooled pieces start square-cornered again
		local uc = fr:FindFirstChildOfClass("UICorner")
		if uc then
			uc.CornerRadius = UDim.new(0, 8)
		end
	else
		fr = Instance.new("Frame")
		fr.BorderSizePixel = 0
		fr.Active = false
		fr.AnchorPoint = Vector2.new(0.5, 0.5)
		local c = Instance.new("UICorner")
		c.Parent = fr
	end
	fr.BackgroundTransparency = 0
	fr.Rotation = 0
	fr.Parent = parent
	inUse[fr] = true
	uses[fr] = (uses[fr] or 0) + 1
	return fr
end

local function release(f: Frame)
	if not inUse[f] then
		return -- already released (clear() ran before this piece's timer)
	end
	inUse[f] = nil
	used = math.max(0, used - 1)
	local list = tweens[f]
	if list then
		for _, tw in list do
			tw:Cancel()
		end
		tweens[f] = nil
	end
	-- a reveal star rides on the piece; it must not come back with the pooled frame
	local star = f:FindFirstChild("Star")
	if star then
		star:Destroy()
	end
	f.Parent = nil
	if #free < MAX_PIECES then
		table.insert(free, f)
	else
		f:Destroy()
	end
end

local function fly(f: Frame, goal: { [string]: any }, life: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	track(f, TweenService:Create(f, TweenInfo.new(math.min(life, LIFE_MAX), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal))
	local use = uses[f]
	task.delay(math.min(life, LIFE_MAX) + 0.03, function()
		if uses[f] == use then
			release(f)
		end
	end)
end

-- HUD wiring ------------------------------------------------------------------------------

-- Hud passes its cash row so coins know where to fly.
function Effects.setCashTarget(obj: GuiObject?)
	cashTarget = obj
end

local function localPoint(abs: Vector2): Vector2
	local _, p = layer()
	return abs - p.AbsolutePosition
end

-- Cash ------------------------------------------------------------------------------------

-- Small coins fly from the world position `from` (a sale hopper) to the cash row.
function Effects.cashFly(from: Vector3?, amount: number)
	if reduced() or not cashTarget or not (cashTarget :: GuiObject).Parent then
		return
	end
	local _, p = layer()
	local cam = Workspace.CurrentCamera
	local start: Vector2
	if from and cam then
		local v, onScreen = cam:WorldToScreenPoint(from + Vector3.new(0, 3, 0))
		if not onScreen then
			start = p.AbsoluteSize * Vector2.new(0.5, 0.6)
		else
			start = localPoint(Vector2.new(v.X, v.Y))
		end
	else
		start = p.AbsoluteSize * Vector2.new(0.5, 0.6)
	end
	local t = cashTarget :: GuiObject
	local goalPos = localPoint(t.AbsolutePosition + t.AbsoluteSize * 0.5)
	local n = math.clamp(math.floor(math.log(math.max(amount, 1), 10)) + 1, 2, 6)
	if lowFx() then
		n = math.max(2, n // 2)
	end
	local s = session
	for i = 1, n do
		task.delay((i - 1) * 0.06, function()
			if s ~= session then
				return
			end
			local f = piece(p)
			if not f then
				return
			end
			f.Size = UDim2.fromOffset(14, 14)
			f.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
			local jitter = Vector2.new((math.random() - 0.5) * 36, (math.random() - 0.5) * 24)
			f.Position = UDim2.fromOffset(start.X + jitter.X, start.Y + jitter.Y)
			fly(f, { Position = UDim2.fromOffset(goalPos.X, goalPos.Y), BackgroundTransparency = 0.7, Size = UDim2.fromOffset(8, 8) }, 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
	end
end

-- Reveal ----------------------------------------------------------------------------------

local SPARK = Color3.fromRGB(255, 252, 235)
local HATCH_STAR = "rbxassetid://94200996021844" -- owner's hatch sparkle (IMPORT_NOW5 HatchSparkle_tex)

-- Soft sparkles around a screen rectangle (the geode viewport) over about 0.6 s.
function Effects.shimmer(topLeft: Vector2, size: Vector2)
	if reduced() then
		return
	end
	local _, p = layer()
	local n = if lowFx() then 6 else 12
	local s = session
	local origin = localPoint(topLeft)
	for _ = 1, n do
		task.delay(math.random() * 0.5, function()
			if s ~= session then
				return
			end
			local f = piece(p)
			if not f then
				return
			end
			local d = 6 + math.random() * 6
			f.Size = UDim2.fromOffset(d, d)
			f.BackgroundColor3 = SPARK
			f.Rotation = 45
			f.Position = UDim2.fromOffset(origin.X + size.X * (0.2 + 0.6 * math.random()), origin.Y + size.Y * (0.15 + 0.7 * math.random()))
			f.BackgroundTransparency = 1
			track(f, TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { BackgroundTransparency = 0.1, Size = UDim2.fromOffset(d * 1.5, d * 1.5) }))
			local use = uses[f]
			task.delay(0.55, function()
				if uses[f] == use then
					release(f)
				end
			end)
		end)
	end
end

-- Colour burst for the target reveal: a soft tinted bloom plus a bounded ring of sparks flying out
-- of the cavity, all in the specimen's real crystal colour. `intensity` 0..1 (from the rarity
-- config, see RevealView) scales the count and strength. Never a white flash: the bloom peaks at
-- about 0.75 transparency. Reduced motion shows nothing; Low effects halves the sparks.
function Effects.revealBurst(topLeft: Vector2, size: Vector2, tint: Color3, intensity: number)
	if reduced() then
		return
	end
	local ok = pcall(function()
		local _, p = layer()
		local k = math.clamp(intensity, 0, 1)
		local centre = localPoint(topLeft) + size * Vector2.new(0.5, 0.5)
		local reach = math.min(size.X, size.Y) * (0.28 + 0.14 * k)
		local bloom = piece(p)
		if bloom then
			local uc = bloom:FindFirstChildOfClass("UICorner")
			if uc then
				uc.CornerRadius = UDim.new(0.5, 0)
			end
			bloom.BackgroundColor3 = tint
			bloom.Position = UDim2.fromOffset(centre.X, centre.Y)
			bloom.Size = UDim2.fromOffset(reach * 0.5, reach * 0.5)
			bloom.BackgroundTransparency = 0.86 - 0.11 * k
			fly(bloom, { Size = UDim2.fromOffset(reach * 2.4, reach * 2.4), BackgroundTransparency = 1 }, 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
		local n = math.floor(6 + 12 * k)
		if lowFx() then
			n = math.max(3, n // 2)
		end
		for i = 1, n do
			local f = piece(p)
			if not f then
				break
			end
			local a = (i / n) * math.pi * 2 + math.random() * 0.4
			local d = 5 + 4 * k + math.random() * 4
			local r = reach * (0.7 + 0.6 * math.random())
			f.Size = UDim2.fromOffset(d * 1.8, d * 1.8)
			f.Rotation = math.random(-20, 20)
			f.BackgroundColor3 = tint:Lerp(SPARK, 0.35)
			f.Position = UDim2.fromOffset(centre.X, centre.Y)
			-- the owner's chunky 4-point star (IMPORT_NOW5 HatchSparkle_tex) instead of a plain diamond; it rides on the
			-- pooled piece and leaves with it
			f.BackgroundTransparency = 1
			local star = Instance.new("ImageLabel")
			star.Name = "Star"
			star.BackgroundTransparency = 1
			star.Size = UDim2.fromScale(1, 1)
			star.Image = HATCH_STAR
			star.ImageColor3 = Color3.new(1, 1, 1):Lerp(tint, 0.25)
			star.Parent = f
			local life = 0.55 + 0.25 * math.random()
			track(f, TweenService:Create(star, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 }))
			fly(f, {
				Position = UDim2.fromOffset(centre.X + math.cos(a) * r, centre.Y + math.sin(a) * r * 0.8),
				Size = UDim2.fromOffset(d * 0.3, d * 0.3),
				BackgroundTransparency = 1,
			}, life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)
	return ok
end

local CONFETTI = {
	Color3.fromRGB(255, 205, 60), Color3.fromRGB(120, 210, 255), Color3.fromRGB(160, 255, 150),
	Color3.fromRGB(255, 150, 190), Color3.fromRGB(210, 170, 255),
}

-- Gentle confetti for about 2 s: a few strips drift down from the upper screen. Each piece
-- lives <= 1 s and fades out, so nothing blocks the view or strobes.
function Effects.confetti()
	if reduced() then
		return
	end
	local _, p = layer()
	local total = if lowFx() then 12 else 26
	local s = session
	for i = 1, total do
		task.delay((i - 1) * (2 / total), function()
			if s ~= session then
				return
			end
			local f = piece(p)
			if not f then
				return
			end
			local w = p.AbsoluteSize.X
			f.Size = UDim2.fromOffset(6, 10)
			f.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]
			f.Rotation = math.random(0, 180)
			f.BackgroundTransparency = 0.15
			local x = w * (0.1 + 0.8 * math.random())
			local y = p.AbsoluteSize.Y * (0.08 + 0.12 * math.random())
			f.Position = UDim2.fromOffset(x, y)
			fly(f, {
				Position = UDim2.fromOffset(x + (math.random() - 0.5) * 70, y + 90 + math.random() * 50),
				Rotation = f.Rotation + (math.random() - 0.5) * 240,
				BackgroundTransparency = 1,
			}, 0.95, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end)
	end
end

-- World -----------------------------------------------------------------------------------

local glintPool: { Attachment } = {}
local glintNext = 1
local GLINT_SLOTS = 4

-- Machine recovery glint at a world position (hook point: call from the machine's recovery code).
function Effects.glint(pos: Vector3)
	if reduced() then
		return
	end
	if #glintPool < GLINT_SLOTS then
		local a = Instance.new("Attachment")
		a.Name = "CTR_Glint"
		a.Parent = Workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(2, 5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromRGB(255, 244, 190))
		e.LightEmission = 0.6
		e.Parent = a
		table.insert(glintPool, a)
	end
	local a = glintPool[glintNext]
	glintNext = glintNext % GLINT_SLOTS + 1
	if not a or not a.Parent then
		return
	end
	local e = a:FindFirstChildOfClass("ParticleEmitter")
	if e then
		a.WorldPosition = pos
		e:Emit(if lowFx() then 3 else 7)
	end
end

-- Stops pending spawns and removes what is on screen (reveal closed, match left).
function Effects.clear()
	session += 1
	if probe then
		for _, c in (probe :: Frame):GetChildren() do
			if c:IsA("Frame") then
				release(c)
			end
		end
	end
end

return Effects
