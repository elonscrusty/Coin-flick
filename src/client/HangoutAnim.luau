--!strict
-- Lobby hangout animation (owner ask 2026-10-14: "animate what you can on all of them, glowing aura etc").
-- Client only and cosmetic: the server's parts are never moved for gameplay. Every hangout piece is found by name
-- (Hangout.animKind) when it appears and gets its look:
--   GoldenRock  bobs, turns slowly, gold aura light pulses, gold sparkles; shakes on every hit
--   MysteryEgg  bobs and wobbles, purple aura pulses through colours, sparkles
--   WhackRock   pops up out of its hole with a little bounce
--   RainCoin    a glint of sparkles
--   HiddenEgg   a soft twinkle and a faint glow (a hint, not a sign post)
--   Lookout     a warm gold glow that breathes, sparkles
--   Campfire    the light flickers and warm embers float up
--   TopPlot     the top plot's gold glow breathes; Crown sparkles
--   Beam        the sky beam shimmers (width pulse)
--   Stump                          a soft pulsing "play here" glow ring light
-- Only pieces within Hangout.Anim.Near studs of the camera move or sparkle (half that with Low Effects); one
-- RenderStepped loop drives them all. Code-made pieces (rock, egg, whack rock, beam) are moved locally from the
-- CFrame they had when they appeared (the server never moves them after); map props only get lights and sparkles.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local HangoutAnim = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

type Item = {
	Kind: string,
	Inst: Instance,
	Part: BasePart?,
	Base: CFrame?,
	Light: PointLight?,
	Emitters: { ParticleEmitter },
	Seed: number,
	Near: boolean,
	Born: number,
	Shake: number,
	BaseSize: Vector3?,
}

local items: { Item } = {}
local byInst: { [Instance]: Item } = {}

local function lowEffects(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.LowEffects == true
end

local function partOf(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function light(part: BasePart, color: Color3, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Name = "HangoutAura"
	l.Color = color
	l.Range = range
	l.Brightness = 1
	l.Shadows = false
	l.Parent = part
	return l
end

local function sparkles(part: BasePart, color: Color3, rate: number, size: number, up: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "HangoutSparkle"
	e.Texture = SPARK
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, up or 1, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Enabled = false
	e.Parent = part
	return e
end

local GOLD = Color3.fromRGB(255, 206, 64)
local PURPLE = Color3.fromRGB(190, 120, 255)
local WARM = Color3.fromRGB(255, 160, 80)
local SOFT = Color3.fromRGB(255, 240, 200)

local function add(inst: Instance, kind: string)
	if byInst[inst] then
		return
	end
	local host: Instance? = if kind == "Campfire" or kind == "TopPlot" then inst.Parent else inst
	local part = if kind == "Campfire" then (if host and host:IsA("BasePart") then host else nil) elseif kind == "TopPlot" then nil else partOf(inst)
	local it: Item = {
		Kind = kind,
		Inst = inst,
		Part = part,
		Base = nil,
		Light = nil,
		Emitters = {},
		Seed = math.random(),
		Near = false,
		Born = os.clock(),
		Shake = 0,
		BaseSize = nil,
	}
	local p = part
	if kind == "GoldenRock" and p then
		it.Base = p.CFrame
		it.Light = p:FindFirstChildOfClass("PointLight") or light(p, GOLD, 20)
		table.insert(it.Emitters, sparkles(p, GOLD, 14, 0.6, 2))
	elseif kind == "MysteryEgg" and p then
		it.Base = p.CFrame
		it.Light = p:FindFirstChildOfClass("PointLight") or light(p, PURPLE, 14)
		table.insert(it.Emitters, sparkles(p, PURPLE, 10, 0.5, 1.5))
	elseif kind == "WhackRock" and p then
		it.Base = p.CFrame
		p.CFrame = p.CFrame * CFrame.new(0, -1.4, 0)
	elseif kind == "RainCoin" and p then
		table.insert(it.Emitters, sparkles(p, GOLD, 2, 0.35, 0))
	elseif kind == "HiddenEgg" and p then
		it.Light = light(p, SOFT, 6)
		table.insert(it.Emitters, sparkles(p, SOFT, 1.2, 0.35, 0.5))
	elseif kind == "Lookout" and p then
		it.Light = light(p, GOLD, 12)
		table.insert(it.Emitters, sparkles(p, GOLD, 4, 0.45, 1.5))
	elseif kind == "Campfire" and p then
		it.Light = (inst :: any) :: PointLight
		table.insert(it.Emitters, sparkles(p, WARM, 5, 0.3, 4))
	elseif kind == "Crown" and p then
		table.insert(it.Emitters, sparkles(p, GOLD, 6, 0.5, 1))
	elseif kind == "Beam" and p then
		it.BaseSize = p.Size
	elseif kind == "Stump" and p then
		it.Light = light(p, GOLD, 10)
	elseif kind ~= "TopPlot" then
		return
	end
	byInst[inst] = it
	table.insert(items, it)
end

local function consider(d: Instance)
	local kind = Hangout.animKind(d.Name)
	if kind then
		task.defer(add, d, kind) -- let its children (prompt, light) arrive first
	end
end

local function cull()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local low = lowEffects()
	local inHunt = State.Match ~= nil
	local i = 1
	while i <= #items do
		local it = items[i]
		if not it.Inst.Parent then
			byInst[it.Inst] = nil
			table.remove(items, i)
			continue
		end
		local at: Vector3? = if it.Part then it.Part.Position
			elseif it.Inst:IsA("Highlight") and it.Inst.Adornee and it.Inst.Adornee:IsA("Model") then (it.Inst.Adornee :: Model):GetPivot().Position
			else nil
		it.Near = not inHunt and at ~= nil and Hangout.animNear((at - camPos).Magnitude, low)
		for _, e in it.Emitters do
			e.Enabled = it.Near and not low
		end
		i += 1
	end
end

local function step()
	local t = os.clock()
	for _, it in items do
		if not it.Near then
			continue
		end
		local p = it.Part
		local k = it.Kind
		if k == "GoldenRock" and p and it.Base then
			local shake = if it.Shake > t then (math.random() - 0.5) * 0.5 else 0
			p.CFrame = it.Base * CFrame.new(shake, math.sin(t * 2 + it.Seed * 6) * 0.4, 0) * CFrame.Angles(0, t * 0.4, 0)
			if it.Light then
				it.Light.Brightness = 1.2 + 1.6 * Hangout.pulse(t, 0.8, it.Seed)
			end
		elseif k == "MysteryEgg" and p and it.Base then
			p.CFrame = it.Base * CFrame.new(0, math.sin(t * 2.4) * 0.6 + 0.3, 0) * CFrame.Angles(0, t * 0.8, math.sin(t * 5) * 0.12)
			if it.Light then
				it.Light.Brightness = 1 + 2 * Hangout.pulse(t, 1, it.Seed)
				it.Light.Color = Color3.fromHSV((0.75 + 0.1 * math.sin(t)) % 1, 0.55, 1)
			end
		elseif k == "WhackRock" and p and it.Base then
			local a = math.clamp((t - it.Born) / 0.15, 0, 1)
			local bounce = if a < 1 then -1.4 * (1 - a) else math.max(0, math.sin((t - it.Born - 0.15) * 18) * 0.15 * math.exp(-(t - it.Born) * 6))
			p.CFrame = it.Base * CFrame.new(0, bounce, 0)
		elseif (k == "HiddenEgg" or k == "Lookout" or k == "Stump") and it.Light then
			local top = if k == "HiddenEgg" then 0.6 elseif k == "Lookout" then 2 else 1.2
			it.Light.Brightness = top * (0.35 + 0.65 * Hangout.pulse(t, 0.5, it.Seed))
		elseif k == "Campfire" and it.Light then
			it.Light.Brightness = 1.3 + 0.5 * math.noise(t * 3, it.Seed * 10) + 0.2 * Hangout.pulse(t, 2.3, it.Seed)
		elseif k == "TopPlot" and it.Inst:IsA("Highlight") then
			local h = it.Inst :: Highlight
			local b = Hangout.pulse(t, 0.6, 0)
			h.FillTransparency = 0.88 - 0.14 * b
			h.OutlineTransparency = 0.4 - 0.35 * b
		elseif k == "Beam" and p and it.BaseSize then
			local w = 1 + 0.12 * math.sin(t * 8)
			p.Size = Vector3.new(it.BaseSize.X, it.BaseSize.Y * w, it.BaseSize.Z * w)
		end
	end
end

function HangoutAnim.start()
	for _, d in Workspace:GetDescendants() do
		consider(d)
	end
	Workspace.DescendantAdded:Connect(consider)
	Net.event("HangoutEvent").OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "RockHit" and type(data) == "table" then
			for _, it in items do
				if it.Kind == "GoldenRock" then
					it.Shake = os.clock() + 0.15
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			cull()
			task.wait(Hangout.Anim.CullEvery)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

-- Tests / previews: run one distance check now and report what is animated.
function HangoutAnim.debug(): { [string]: number }
	cull()
	local out = {}
	for _, it in items do
		if it.Near then
			out[it.Kind] = (out[it.Kind] or 0) + 1
		end
	end
	return out
end

return HangoutAnim
