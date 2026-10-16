--!strict
-- Public hatch stand (owner pick, 2026-10-11): every egg bought in the EGG SHOP is cracked at the stand by the shop for
-- everyone to watch. The server rolls the pet first, then sends HatchShow { Buyer, BuyerId, Egg, Count, Pet } to every
-- client, one show at a time (RobuxService queue). Here: an egg appears over the stand's "HatchPoint", wobbles, pops
-- and the pet rises with a name tag ("<Buyer> hatched a RARE Golden Raptor!"). Cosmetic only; nothing is decided here.
-- The stand is a part with attribute HatchStand = true (built by the park helper); without it nothing is drawn.
-- While a show runs, a local spotlight shines down on the stand and a glowing ring pulses on the ground around it
-- (where the crowd gathers); both fade away with the show. Players right next to it get a small camera shake at the pop.
-- Polish: the egg floats up and spins faster before it cracks; the pet card flips over, its name types in and the
-- rarity stars fill one by one (HatchCard); players nearby get a gentle zoom (field of view) during the reveal, given
-- back exactly afterwards and dropped the moment anything else moves the field of view. Eggs still waiting in the
-- queue (optional show.Waiting count) sit beside the stand rocking gently. Reduce Motion: none of the motion.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GeodeModel = require(Shared.GeodeModel)
local PetModel = require(Shared.PetModel)
local GeodeGen = require(Shared.GeodeGen)
local PetStatView = require(Shared.PetStatView)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)
local CameraFx = require(script.Parent.CameraFx)
local HatchCard = require(script.Parent.HatchCard)

local HatchStandView = {}

local WOBBLE, POP, SHOW = 1.6, 0.35, 3.6 -- seconds (the server waits RobuxConfig.Show.Seconds between shows)

local standPart: BasePart? = nil
local FLOAT, SPINS = 1.6, 2.5 -- studs the egg rises and turns it makes before it cracks
local ZOOM, ZOOM_NEAR = 6, 40 -- degrees of field of view taken off; studs from the stand to get the zoom
local zoomToken = 0

local function standPoint(): CFrame?
	local found = standPart
	if not (found and found.Parent and found:GetAttribute("HatchStand") == true) then
		found = nil
		for _, d in Workspace:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
				found = d
				break
			end
		end
		standPart = found
	end
	local d = found
	if not d then
		return nil
	end
	local a = d:FindFirstChild("HatchPoint")
	if a and a:IsA("Attachment") then
		return CFrame.new(a.WorldPosition)
	end
	return CFrame.new(d.Position + Vector3.new(0, d.Size.Y * 0.5, 0))
end

local RING_SEGMENTS = 18

local function glowPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p:SetAttribute("CameraIgnore", true)
	p.Parent = parent
	return p
end

-- Spotlight from above plus a ring of glowing bars on the ground around the stand. Returns the ring parts (for the
-- pulse) and the light.
local function stage(folder: Instance, at: CFrame, color: Color3): ({ BasePart }, SpotLight?)
	local stand = standPart
	local floorY = if stand then stand.Position.Y - stand.Size.Y * 0.5 + 0.06 else at.Position.Y
	local r = if stand then math.max(stand.Size.X, stand.Size.Z) * 0.5 + 4 else 7
	local c = Vector3.new(at.Position.X, floorY, at.Position.Z)
	local ring: { BasePart } = {}
	local seg = 2 * math.pi * r / RING_SEGMENTS * 0.7
	for i = 1, RING_SEGMENTS do
		local a = (i / RING_SEGMENTS) * 2 * math.pi
		local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local p = glowPart(folder, Vector3.new(seg, 0.12, 0.5), CFrame.lookAt(pos, c), color) -- long side along the circle
		p.Transparency = 1
		table.insert(ring, p)
	end
	local holder = Instance.new("Part")
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(at.Position + Vector3.new(0, 16, 0))
	holder.Parent = folder
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 45
	light.Range = 24
	light.Brightness = 0
	light.Color = color:Lerp(Color3.new(1, 1, 1), 0.5)
	light.Shadows = false
	light.Parent = holder
	return ring, light
end

-- A gentle zoom for players near the stand: the field of view eases in by ZOOM degrees over `seconds`, then back.
-- Only starts from the normal field of view (no speed boots, no cinematic) and stops at once, without touching the
-- camera again, if anything else writes the field of view meanwhile.
local function zoom(at: Vector3, seconds: number)
	local cam = Workspace.CurrentCamera
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if UI.Reduced or not cam or not (root and root:IsA("BasePart")) or (root.Position - at).Magnitude > ZOOM_NEAR then
		return
	end
	local base = Config.Camera.Fov
	if cam.CameraType == Enum.CameraType.Scriptable or math.abs(cam.FieldOfView - base) > 0.01 then
		return
	end
	local _, onScreen = cam:WorldToViewportPoint(at)
	if not onScreen then
		return
	end
	zoomToken += 1
	local token = zoomToken
	local name = "CTR_HatchZoom"
	local t0 = os.clock()
	local last = cam.FieldOfView
	pcall(RunService.UnbindFromRenderStep, RunService, name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 4, function()
		local t = os.clock() - t0
		-- Someone else moving the field of view owns it from then on; any other interruption (a cutscene taking the
		-- camera, a camera swap, a newer zoom) still gives our zoom back (audit 30: it used to stay zoomed in).
		local taken = math.abs(cam.FieldOfView - last) > 0.01
		local stop = taken or token ~= zoomToken or cam ~= Workspace.CurrentCamera or cam.CameraType == Enum.CameraType.Scriptable
		if stop or t >= seconds then
			if token == zoomToken then
				RunService:UnbindFromRenderStep(name)
			end
			if not taken then
				cam.FieldOfView = base
			end
			return
		end
		local back = math.clamp((seconds - t) / 0.7, 0, 1) -- the last 0.7 s ease back out
		local k = math.min(math.clamp(t / (seconds * 0.6), 0, 1), back)
		last = base - ZOOM * (0.5 - 0.5 * math.cos(k * math.pi))
		cam.FieldOfView = last
	end)
end

-- Eggs still waiting their turn sit in a short row beside the stand and rock gently (all alike, bought eggs only).
local function waiting(folder: Instance, at: CFrame, count: number, lowFx: boolean): { Model }
	local n = math.min(count, if lowFx then 2 else 4)
	local stand = standPart
	local floorY = if stand then stand.Position.Y - stand.Size.Y * 0.5 else at.Position.Y
	local off = if stand then math.max(stand.Size.X, stand.Size.Z) * 0.5 + 2 else 5
	local eggs: { Model } = {}
	for i = 1, n do
		local ok, egg = pcall(GeodeModel.rockShell, i, 1.8, "WaitingEgg", {})
		if ok and egg then
			local cf = CFrame.new(at.Position.X + off, floorY + 0.9, at.Position.Z + (i - (n + 1) / 2) * 2.2)
			egg:SetAttribute("Home", cf)
			egg:PivotTo(cf)
			egg.Parent = folder
			table.insert(eggs, egg)
		end
	end
	return eggs
end

local function play(show: any)
	if type(show) ~= "table" or type(show.Pet) ~= "table" or State.Match then
		return -- in a hunt the stand is far away: skip the show
	end
	local at = standPoint()
	if not at then
		return
	end
	local base = (at :: CFrame) * CFrame.new(0, 2.2, 0)
	local folder = Instance.new("Folder")
	folder.Name = "HatchShow"
	folder.Parent = Workspace
	local rarity0 = tostring(show.Pet.Rarity or "Common")
	local lowFx = State.Profile and State.Profile.Settings and State.Profile.Settings.LowEffects == true
	local ring, light = stage(folder, at, (Config.RarityColors :: any)[rarity0] or Color3.fromRGB(255, 214, 120))
	local queued: { Model } = if type(show.Waiting) == "number" and show.Waiting > 0 then waiting(folder, at, show.Waiting, lowFx == true) else {}
	local stageT0 = os.clock()
	local total = WOBBLE + SHOW
	local stageConn: RBXScriptConnection? = nil
	stageConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - stageT0
		if not folder.Parent or t > total + 3 then
			-- the show ended (or failed part-way): never leave the stage behind
			if stageConn then
				stageConn:Disconnect()
			end
			folder:Destroy()
			return
		end
		local fadeIn = math.min(1, t / 0.4)
		local fadeOut = math.clamp((total - t) / 0.5, 0, 1)
		local k = math.min(fadeIn, fadeOut)
		local pulse = if UI.Reduced or lowFx then 0 else 0.15 * math.sin(t * 5)
		for i, p in ring do
			p.Transparency = 1 - k * (0.55 + pulse * (if i % 2 == 0 then 1 else -1))
		end
		if light then
			light.Brightness = 3 * k
		end
		if not UI.Reduced then
			for i, e in queued do
				local home = e:GetAttribute("Home")
				if typeof(home) == "CFrame" and e.Parent then
					e:PivotTo(home * CFrame.Angles(math.sin(t * 2.4 + i * 1.3) * math.rad(7), 0, 0))
				end
			end
		end
	end)
	local ok, egg = pcall(GeodeModel.rockShell, (tonumber(show.Pet.Seed) or 1) % 8 + 1, 4, "ShowEgg", {})
	if ok and egg then
		egg:PivotTo(base)
		egg.Parent = folder
		local t0 = os.clock()
		while os.clock() - t0 < WOBBLE do
			local t = os.clock() - t0
			local k = t / WOBBLE
			local amp = if UI.Reduced then 0 else math.rad(6 + 14 * k)
			-- floats up and spins faster and faster, then the wobble cracks it
			local rise = if UI.Reduced then 0 else FLOAT * (1 - (1 - k) ^ 2)
			local spin = if UI.Reduced then 0 else SPINS * 2 * math.pi * k * k
			egg:PivotTo(base * CFrame.new(0, rise, 0) * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, math.sin(t * 18) * amp))
			RunService.Heartbeat:Wait()
		end
		egg:Destroy()
	end
	local rarity = tostring(show.Pet.Rarity or "Common")
	local okP, pet = pcall(PetModel.build, show.Pet, { Scale = 1.5, NoLight = false })
	if okP and pet then
		local lp = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if lp and lp:IsA("BasePart") and (lp.Position - at.Position).Magnitude < 30 then
			CameraFx.shake(0.35, 0.3) -- the pop, felt up close only
		end
		local cy = pet:GetAttribute("CentreY")
		local lift = if type(cy) == "number" then cy * 1.5 else 1.8
		pet.Parent = folder
		local head = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart", true)
		local who = tostring(show.Buyer or "Someone")
		local line = who .. " hatched a " .. string.upper(rarity)
			.. (if (tonumber(show.Count) or 1) > 1 then " (" .. show.Count .. " pets)" else "")
		local power = if type(show.Pet) == "table" then PetStatView.power(show.Pet) else nil
		if power then
			line ..= " \u{b7} POWER " .. UI.num(power) -- the one "bigger = better" number (PetStatView)
		end
		if head then
			HatchCard.show(head, line, GeodeGen.displayName(show.Pet) .. "!", rarity, (Config.RarityTextColors :: any)[rarity] or Color3.new(1, 1, 1))
		end
		zoom(at.Position, SHOW)
		local t0 = os.clock()
		while os.clock() - t0 < SHOW and pet.Parent do
			local t = os.clock() - t0
			local rise = math.min(1, t / POP)
			pet:PivotTo(at * CFrame.new(0, lift * rise, 0) * CFrame.Angles(0, if UI.Reduced then 0 else t * 1.6, 0))
			RunService.Heartbeat:Wait()
		end
	end
	if stageConn then
		stageConn:Disconnect()
	end
	folder:Destroy()
end

function HatchStandView.start()
	Net.event("HatchShow").OnClientEvent:Connect(function(show)
		task.spawn(function()
			local ok: boolean, err: any = pcall(play, show)
			if not ok then
				warn("[HatchStandView]", err)
			end
		end)
	end)
end

return HatchStandView
