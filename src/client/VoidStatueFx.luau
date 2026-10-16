--!strict
-- The Void Dragon statue comes alive (client only, cosmetic; server/VoidStatue builds it):
--   a slow breathing hover of the dragon (+-0.4 studs over 4 s, a tiny sway), a ring of sparkles orbiting it, and a
--   pulsing "1 in 1000" sign. One Heartbeat connection while the statue is near; nothing is sent anywhere.
-- Reduce Motion: no hover or orbit (the sparkles still twinkle in place, the sign stays still).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local VoidStatueFx = {}

local HOVER = 0.4 -- studs up and down
local PERIOD = 4 -- seconds per breath
local ORBITERS = 8
local NEAR = 400 -- studs: farther than this, nothing moves (saves phones)

local function reduced(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.ReducedMotion == true
end

local function lowFx(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.LowEffects == true
end

local function sparkle(parent: Instance, color: Color3): Attachment
	local a = Instance.new("Attachment")
	a.Name = "Orbiter"
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Rate = if lowFx() then 4 else 10
	p.Lifetime = NumberRange.new(0.6, 1.1)
	p.Speed = NumberRange.new(0, 0.5)
	p.LightEmission = 1
	p.LockedToPart = false
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	p.Color = ColorSequence.new(color)
	p.Parent = a
	a.Parent = parent
	return a
end

local function attach(statue: Model)
	local dragon = statue:FindFirstChild("Dragon") :: Model?
	local home = dragon and dragon:GetAttribute("Home")
	local height = (statue:GetAttribute("Height") :: number?) or 16
	local top = (statue:GetAttribute("Top") :: number?) or 0
	local base = statue.PrimaryPart
	if not base then
		return
	end
	local floor = base.CFrame * CFrame.new(0, -base.Size.Y / 2, 0)
	local centre = (if typeof(home) == "CFrame" then home.Position else floor.Position + Vector3.new(0, top, 0)) + Vector3.new(0, height * 0.5, 0)
	local radius = height * 0.75
	local orbiters: { Attachment } = {}
	local terrain = Workspace.Terrain
	for i = 1, ORBITERS do
		table.insert(orbiters, sparkle(terrain, if i % 2 == 0 then Color3.fromRGB(240, 140, 255) else Color3.fromRGB(255, 220, 110)))
	end
	local odds: { TextLabel } = {}
	for _, d in statue:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Odds" then
			table.insert(odds, d)
		end
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if not statue.Parent then
			for _, a in orbiters do
				a:Destroy()
			end
			if conn then
				conn:Disconnect()
			end
			return
		end
		local cam = Workspace.CurrentCamera
		if cam and (cam.CFrame.Position - centre).Magnitude > NEAR then
			return
		end
		local t = os.clock() - t0
		local calm = reduced()
		if dragon and typeof(home) == "CFrame" and not calm then
			local breath = math.sin(t * 2 * math.pi / PERIOD)
			dragon:PivotTo(home * CFrame.new(0, HOVER + HOVER * breath, 0) * CFrame.Angles(0, math.rad(3) * math.sin(t * 0.7), 0))
		end
		for i, a in orbiters do
			local ang = (if calm then 0 else t * 0.8) + (i / ORBITERS) * math.pi * 2
			local bob = if calm then 0 else math.sin(t * 1.6 + i) * height * 0.08
			a.WorldPosition = centre + Vector3.new(math.cos(ang) * radius, bob + (i % 2) * height * 0.2 - height * 0.1, math.sin(ang) * radius)
		end
		if not calm then
			local pulse = 0.5 + 0.5 * math.sin(t * 3)
			for _, l in odds do
				l.TextTransparency = 0.25 * (1 - pulse)
				l.Rotation = 2 * math.sin(t * 1.5)
				local st = l:FindFirstChildOfClass("UIStroke")
				if st then
					st.Thickness = 3 + 3 * pulse
				end
			end
		end
	end)
end

function VoidStatueFx.start()
	-- the server can rebuild the statue later (moved onto the leaderboard tree's DragonPerch): attach to each new one
	local seen: { [Instance]: boolean } = {}
	local function try(d: Instance)
		if d.Name == "VoidDragonStatue" and d:IsA("Model") and not seen[d] then
			seen[d] = true
			d.Destroying:Connect(function()
				seen[d] = nil
			end)
			task.defer(attach, d)
		end
	end
	Workspace.DescendantAdded:Connect(try)
	task.spawn(function()
		local found = Workspace:FindFirstChild("VoidDragonStatue", true)
		if found then
			try(found)
		end
	end)
end

return VoidStatueFx
