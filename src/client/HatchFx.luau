--!strict
-- World juice around a hatch (client only, cosmetic; the server already decided and saved everything before the
-- events that drive this arrive, and nothing here is sent anywhere):
--   onReveal(data)   the match Reveal event (only the hunt's members get it). Rare+ (PetFlair.shouldAnnounce): a
--                    rainbow ring blasts out across the arena from the winner's nest, and firework bursts pop above
--                    the pile, timed to the pet popping out of the egg on the nest. Once per round.
--   goldSky(sec)     Legendary: a warm gold wash over the whole view, driven by the RareHatch "Local" broadcast that
--                    already goes to every player in the server. A ColorCorrectionEffect on the local camera; the
--                    Lighting service is not touched.
-- Reduce Motion: no ring or fireworks (the gold wash stays, it does not move). Low Effects: fewer pieces.
-- Every part lives in one folder, is driven by one RenderStepped connection and is destroyed when it ends.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetFlair = require(Shared.PetFlair)
local State = require(script.Parent.State)
local StationView = require(script.Parent.StationView)

local HatchFx = {}

local pileCenter: Vector3? = nil
local lastRound: any = nil
local rng = Random.new()

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function reduced(): boolean
	return settings().ReducedMotion == true
end

local function lowFx(): boolean
	return settings().LowEffects == true
end

local function fxPart(parent: Instance, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Parent = parent
	return p
end

local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace
	return f
end

-- Run step(t) every frame for `life` seconds, then destroy the folder. step returns nothing.
local function drive(f: Folder, life: number, step: (number) -> ())
	local t = 0
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		if t >= life or not f.Parent then
			if conn then
				conn:Disconnect()
			end
			f:Destroy()
			return
		end
		step(t)
	end)
end

-- The pile centre of the current round (Main passes the Pile payload's Center).
function HatchFx.setPile(center: any)
	pileCenter = if typeof(center) == "Vector3" then center else nil
end

-- A flat rainbow ring of neon segments that grows from `pos` across the arena and fades.
function HatchFx.ring(pos: Vector3)
	if reduced() then
		return
	end
	local n = if lowFx() then 14 else 26
	local f = folder("CTR_HatchRing")
	local segs: { Part } = {}
	for i = 1, n do
		segs[i] = fxPart(f, Enum.PartType.Block, Vector3.new(1, 0.35, 0.5), Color3.fromHSV(i / n, 0.75, 1))
	end
	local life, maxR = 1.3, 60
	local y = pos.Y + 0.6
	drive(f, life, function(t)
		local k = t / life
		local r = 1.5 + (maxR - 1.5) * (1 - (1 - k) ^ 3)
		local len = 2 * math.pi * r / n * 0.9
		local spin = t * 0.8
		for i, p in segs do
			local a = i / n * math.pi * 2 + spin
			p.Size = Vector3.new(len, 0.35 + 0.6 * (1 - k), 0.5 + 0.8 * (1 - k))
			p.CFrame = CFrame.new(pos.X + math.cos(a) * r, y + 0.4 * (1 - k), pos.Z + math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0)
			p.Color = Color3.fromHSV((i / n + t * 0.6) % 1, 0.75, 1)
			p.Transparency = 0.1 + 0.9 * k * k
		end
	end)
end

-- A few firework bursts in the sky above `pos`.
function HatchFx.fireworks(pos: Vector3, tint: Color3?)
	if reduced() then
		return
	end
	local bursts = if lowFx() then 2 else 4
	local per = if lowFx() then 8 else 14
	local colors = { tint or Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 120, 170), Color3.fromRGB(120, 220, 255) }
	for b = 1, bursts do
		task.delay((b - 1) * 0.35, function()
			local f = folder("CTR_Firework")
			local at = pos + Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(20, 28), rng:NextNumber(-10, 10))
			local color = colors[(b - 1) % #colors + 1]
			local flash = fxPart(f, Enum.PartType.Ball, Vector3.one * 2.5, Color3.new(1, 1, 1))
			flash.CFrame = CFrame.new(at)
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 24
			light.Brightness = 3
			light.Shadows = false
			light.Parent = flash
			local sparks: { Part } = {}
			local vel: { Vector3 } = {}
			for i = 1, per do
				local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 1), rng:NextNumber(-1, 1))
				d = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
				sparks[i] = fxPart(f, Enum.PartType.Ball, Vector3.one * 0.7, if i % 4 == 0 then Color3.new(1, 1, 1) else color)
				vel[i] = d * rng:NextNumber(14, 20)
			end
			local life = 1.4
			drive(f, life, function(t)
				local k = t / life
				flash.Transparency = math.min(1, t / 0.25)
				light.Brightness = 3 * (1 - k)
				for i, p in sparks do
					local v = vel[i]
					local drag = (1 - math.exp(-2.2 * t)) / 2.2 -- slowing outward travel
					p.CFrame = CFrame.new(at + v * drag + Vector3.new(0, -4 * t * t, 0))
					p.Transparency = k * k
				end
			end)
		end)
	end
end

-- The match Reveal event: Rare+ ring from the winner's nest and fireworks above the pile, once per round.
function HatchFx.onReveal(data: any)
	if type(data) ~= "table" or type(data.Specimen) ~= "table" then
		return
	end
	local rarity = data.Specimen.Rarity
	if not PetFlair.shouldAnnounce(rarity) then
		return
	end
	local key = data.Round or data
	if key == lastRound then
		return -- a rejoin replays the Reveal payload; the blast plays once
	end
	lastRound = key
	local nest = if type(data.Winner) == "number" then StationView.platePosition(data.Winner) else nil
	local pile = pileCenter
	-- when the egg on the nest finishes opening (the pop), never later than 3 s
	local at = math.clamp(StationView.fxRemaining() - 0.2, 0, 3)
	task.delay(at, function()
		if nest then
			HatchFx.ring(nest)
		end
		local above = pile or nest
		if above then
			task.delay(0.25, function()
				HatchFx.fireworks(above, nil)
			end)
		end
	end)
end

local sky: ColorCorrectionEffect? = nil
local skyToken = 0

-- Legendary: the world washes warm gold for `seconds` (fades in and out).
function HatchFx.goldSky(seconds: number?)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local hold = math.clamp(seconds or 3, 1, 6)
	skyToken += 1
	local token = skyToken
	local cc = sky
	if not cc or not cc.Parent then
		local n = Instance.new("ColorCorrectionEffect")
		n.Name = "CTR_GoldSky"
		n.TintColor = Color3.new(1, 1, 1)
		n.Parent = cam
		cc = n
		sky = n
	end
	local e = cc :: ColorCorrectionEffect
	TweenService:Create(e, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { TintColor = Color3.fromRGB(255, 222, 150), Brightness = 0.06, Saturation = 0.2 }):Play()
	task.delay(hold, function()
		if token ~= skyToken then
			return
		end
		local tw = TweenService:Create(e, TweenInfo.new(0.8, Enum.EasingStyle.Sine), { TintColor = Color3.new(1, 1, 1), Brightness = 0, Saturation = 0 })
		tw:Play()
		tw.Completed:Connect(function()
			if token == skyToken then
				e:Destroy()
				if sky == e then
					sky = nil
				end
			end
		end)
	end)
end

return HatchFx
