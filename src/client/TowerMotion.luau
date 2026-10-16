--!strict
-- Pet Tower fight motion (client only, pure presentation): the pet's turn hop, the hit flinch with a white
-- flash, the knocked-out puff (tip over is TowerView's slide; this fades the body away in a puff of dust),
-- and the revive halo. Every piece cleans itself up; Reduce Motion drops the moves (a flash or fade stays),
-- Low Effects drops the dust and thins the halo.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local TowerMotion = {}

local function setting(key: string): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings[key] == true
end

local function fxFolder(): Folder
	local f = Workspace:FindFirstChild("TowerFx")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "TowerFx"
	nf.Parent = Workspace
	return nf
end

-- Drives a 0..1 value over `t` seconds and calls `step` each change (the NumberValue is destroyed at the end).
local function drive(t: number, style: Enum.EasingStyle, dir: Enum.EasingDirection, step: (number) -> (), done: (() -> ())?)
	local n = Instance.new("NumberValue")
	n.Value = 0
	n.Changed:Connect(step)
	local tw = TweenService:Create(n, TweenInfo.new(t, style, dir), { Value = 1 })
	tw.Completed:Connect(function()
		n:Destroy()
		if done then
			done()
		end
	end)
	tw:Play()
end

-- Pet's turn: a small hop forward (an arc up and toward the target), then a hop back home.
-- `ok` is checked before the way back so a pet knocked out mid-hop is not pulled upright again.
function TowerMotion.hop(model: Model, home: CFrame, toward: Vector3, ok: () -> boolean)
	if setting("ReducedMotion") then
		return
	end
	local function arc(from: CFrame, to: CFrame, t: number, h: number, done: (() -> ())?)
		drive(t, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, function(a)
			if model.Parent then
				model:PivotTo(from:Lerp(to, a) * CFrame.new(0, math.sin(a * math.pi) * h, 0))
			end
		end, done)
	end
	local out = home + toward.Unit * 1.4
	arc(home, out, 0.13, 1.1, function()
		if model.Parent and ok() then
			arc(out, home, 0.16, 0.5)
		end
	end)
end

-- Hit: a quick white flash over the whole body, plus a short flinch back (away from the attacker).
function TowerMotion.flinch(model: Model, home: CFrame, away: Vector3, ok: () -> boolean)
	local h = Instance.new("Highlight")
	h.Name = "HitFlash"
	h.FillColor = Color3.new(1, 1, 1)
	h.OutlineColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.15
	h.OutlineTransparency = 0.4
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, 0.2)
	if setting("ReducedMotion") or away.Magnitude < 0.1 then
		return
	end
	local back = home + away.Unit * 0.6
	drive(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
		if model.Parent and ok() then
			model:PivotTo(home:Lerp(back, a))
		end
	end, function()
		drive(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			if model.Parent and ok() then
				model:PivotTo(back:Lerp(home, a))
			end
		end)
	end)
end

-- Fades every visible piece of a model with LocalTransparencyModifier (client only, the parts keep their own
-- Transparency, so `unpuff` can bring them back exactly).
local function fadeTo(model: Model, goal: number, t: number)
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if t <= 0 then
				(d :: any).LocalTransparencyModifier = goal
			else
				TweenService:Create(d, info, { LocalTransparencyModifier = goal }):Play()
			end
		elseif d:IsA("Highlight") then
			d.Enabled = goal < 1 -- the boss's red glow and light go with the body
		elseif d:IsA("PointLight") then
			d.Enabled = goal < 1
		end
	end
end

-- Knocked out: after the tip over, a puff of dust and the body fades away (it stays in place, invisible,
-- so a revived pet can come back). `delay` waits for the tip-over slide.
function TowerMotion.puff(model: Model, delay: number, ok: () -> boolean)
	task.delay(delay, function()
		if not model.Parent or not ok() then
			return
		end
		fadeTo(model, 1, 0.3)
		if setting("LowEffects") then
			return -- Low Effects: just the fade, no dust
		end
		local cf, size = model:GetBoundingBox()
		local a = Instance.new("Part")
		a.Name = "KoPuff"
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CanTouch = false
		a.Transparency = 1
		a.Size = Vector3.new(math.max(size.X, 1), 0.5, math.max(size.Z, 1))
		a.CFrame = CFrame.new(cf.Position)
		a.Parent = fxFolder()
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(235, 232, 225))
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(0.4, 0.7)
		pe.Speed = NumberRange.new(3, 6)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Drag = 4
		pe.Rate = 0
		pe.Parent = a
		pe:Emit(10)
		Debris:AddItem(a, 1)
	end)
end

-- Revived: the body shows again (undoes `puff`).
function TowerMotion.unpuff(model: Model)
	fadeTo(model, 0, 0)
end

-- Revive halo: a ring of small gold lights that rises with the pet over its head, then fades.
-- `from` / `to` are the pet's feet before and after the rise; `height` puts the ring above its head.
function TowerMotion.halo(from: CFrame, to: CFrame, height: number, t: number)
	local low = setting("LowEffects")
	local n = if low then 6 else 12
	local ring = Instance.new("Model")
	ring.Name = "ReviveHalo"
	local gold = Color3.fromRGB(255, 225, 110)
	for i = 1, n do
		local ang = (i / n) * math.pi * 2
		local p = Instance.new("Part")
		p.Name = "Bead"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 0.35
		p.Color = gold
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.CFrame = CFrame.new(math.cos(ang) * 1.1, 0, math.sin(ang) * 1.1)
		p.Parent = ring
	end
	ring.WorldPivot = CFrame.new()
	local up = CFrame.new(0, height, 0)
	ring:PivotTo(from * up)
	ring.Parent = fxFolder()
	if not setting("ReducedMotion") then
		drive(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(a)
			if ring.Parent then
				-- rises with the pet and turns slowly
				ring:PivotTo(from:Lerp(to, a) * up * CFrame.Angles(0, a * math.pi, 0))
			end
		end)
	else
		ring:PivotTo(to * up)
	end
	local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, t + 0.6)
	for _, p in ring:GetChildren() do
		if p:IsA("BasePart") then
			TweenService:Create(p, fade, { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(ring, t + 1.2)
end

return TowerMotion
