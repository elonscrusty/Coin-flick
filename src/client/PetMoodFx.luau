--!strict
-- Small mood touches on follower pets (client only, purely cosmetic; PetFollow calls these):
--   hearts     a few little hearts float up over a pet that was just equipped
--   zzz        a "Zzz" bubble that keeps floating up over a sleepy pet (owner standing still a long while)
--   shrinkAway an unequipped pet shrinks down and vanishes in a poof instead of blinking out
-- The hearts are drawn from rounded frames (no asset ids). Low Effects: one heart, no Zzz bubble. Reduce Motion: no
-- floating, the unequipped pet just goes. Every piece lives under the pet model or is cleaned up with Debris.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)
local Anim = require(script.Parent.Anim)
local ZZZ = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config")).PetZzz

local PetMoodFx = {}

local PINK = Color3.fromRGB(255, 105, 150)

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return UI.Reduced or settings().ReducedMotion == true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

-- the part a billboard hangs on: the head when there is one, else the body / primary part
local function anchorOf(m: Model): BasePart?
	local h = m:FindFirstChild("Head", true)
	if h and h:IsA("BasePart") then
		return h
	end
	local b = m.PrimaryPart or m:FindFirstChild("Body", true)
	return if b and b:IsA("BasePart") then b else nil
end

local function topOf(m: Model, part: BasePart): number
	local h = m:GetAttribute("Height")
	local height = if type(h) == "number" then h else 2
	-- studs from the anchor part's centre up to a little above the pet's top
	return math.max(part.Size.Y * 0.5, height - (part.Position.Y - m:GetPivot().Position.Y)) + 0.6
end

-- A heart from a rotated square and two round lobes (centred in a size x size box).
local function heart(parent: Instance, size: number): { Frame }
	local half = size * 0.5
	local pieces: { Frame } = {}
	local sq = Instance.new("Frame")
	sq.BorderSizePixel = 0
	sq.BackgroundColor3 = PINK
	sq.AnchorPoint = Vector2.new(0.5, 0.5)
	sq.Size = UDim2.fromOffset(half, half)
	sq.Position = UDim2.new(0.5, 0, 0.5, size * 0.12)
	sq.Rotation = 45
	sq.Parent = parent
	table.insert(pieces, sq)
	for _, dx in { -1, 1 } do
		local lobe = Instance.new("Frame")
		lobe.BorderSizePixel = 0
		lobe.BackgroundColor3 = PINK
		lobe.AnchorPoint = Vector2.new(0.5, 0.5)
		lobe.Size = UDim2.fromOffset(half, half)
		lobe.Position = UDim2.new(0.5, dx * size * 0.18, 0.5, -size * 0.06)
		lobe.Parent = parent
		UI.corner(lobe, half)
		table.insert(pieces, lobe)
	end
	return pieces
end

-- Little hearts rise over a pet that was just equipped (about 1.3 s, a beat apart).
function PetMoodFx.hearts(m: Model)
	local part = anchorOf(m)
	if not part then
		return
	end
	local top = topOf(m, part)
	local n = if lowFx() then 1 else 3
	local still = reduced()
	for i = 1, n do
		task.delay((i - 1) * 0.18, function()
			if not part.Parent then
				return
			end
			local bb = Instance.new("BillboardGui")
			bb.Name = "PetHeart"
			bb.Adornee = part
			bb.Size = UDim2.fromOffset(28, 28)
			bb.LightInfluence = 0
			bb.MaxDistance = 60
			bb.ResetOnSpawn = false
			local dx = (i - (n + 1) / 2) * 0.7
			bb.StudsOffsetWorldSpace = Vector3.new(dx, top, 0)
			local pieces = heart(bb, if i == 2 then 22 else 18)
			bb.Parent = m
			local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if not still then
				TweenService:Create(bb, info, { StudsOffsetWorldSpace = Vector3.new(dx * 1.4, top + 2.2, 0) }):Play()
			end
			local fadeInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.65)
			for _, p in pieces do
				TweenService:Create(p, fadeInfo, { BackgroundTransparency = 1 }):Play()
			end
			Debris:AddItem(bb, 1.2)
		end)
	end
end

-- Sleepy bubble: on = show / keep the floating "Zzz" over the pet, off = remove it. Call update() every frame with
-- the clock while it is on (the bubble rises and fades on a 2 s loop, no tweens).
function PetMoodFx.setZzz(m: Model, on: boolean): BillboardGui?
	local bb = m:FindFirstChild("PetZzz")
	if not on or lowFx() then
		if bb then
			bb:Destroy()
		end
		return nil
	end
	if bb and bb:IsA("BillboardGui") then
		return bb
	end
	local part = anchorOf(m)
	if not part then
		return nil
	end
	local g = Instance.new("BillboardGui")
	g.Name = "PetZzz"
	g.Adornee = part
	g.Size = UDim2.fromOffset(ZZZ.Width, ZZZ.Height) -- small and faint (Config.PetZzz)
	g.LightInfluence = 0
	g.MaxDistance = 45
	g.ResetOnSpawn = false
	g:SetAttribute("Top", topOf(m, part))
	UI.text(g, "Zzz", {
		Name = "Z", Font = UI.Bold, TextSize = ZZZ.TextSize, Outline = "Normal", TextColor3 = Color3.fromRGB(200, 225, 255),
		TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
	})
	g.Parent = m
	return g
end

function PetMoodFx.updateZzz(g: BillboardGui, t: number, phase: number)
	local top = g:GetAttribute("Top")
	local y = if type(top) == "number" then top else 2
	local k = if reduced() then 0.3 else ((t * 0.5 + phase) % 1)
	g.StudsOffsetWorldSpace = Vector3.new(0.5 + 0.4 * k, y + 1.4 * k, 0)
	local lbl = g:FindFirstChild("Z")
	if lbl and lbl:IsA("TextLabel") then
		local a = if k < 0.2 then 1 - k / 0.2 else (k - 0.2) / 0.8
		local fade = ZZZ.Faint + (1 - ZZZ.Faint) * a * a
		lbl.TextTransparency = fade
		local stroke = lbl:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = fade
		end
	end
end

-- An unequipped follower shrinks away (0.3 s) and leaves a little poof; the model is destroyed afterwards.
-- The caller has already taken it out of its follower list.
function PetMoodFx.shrinkAway(m: Model)
	if not m.Parent then
		m:Destroy()
		return
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	local at = m:GetPivot().Position
	local okS, s0 = pcall(function()
		return m:GetScale()
	end)
	local base = if okS then s0 else 1
	Anim.run(0.3, function(k)
		if m.Parent then
			local e = 1 - (1 - k) * (1 - k)
			pcall(function()
				m:ScaleTo(base * math.max(0.05, 1 - 0.95 * e))
			end)
		end
	end, function()
		pcall(function()
			require(script.Parent.HitFx).poof(at + Vector3.new(0, 0.5, 0))
		end)
		m:Destroy()
	end)
end

return PetMoodFx
