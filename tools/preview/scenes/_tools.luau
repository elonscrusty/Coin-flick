-- _tools: the held tool on the stand-in avatar at a crushing-table-height work surface.
--   --set tool=Hammer|SteelHammer|Jackhammer, --set t=S (seconds into a stroke; omit = carry pose),
--   --set cam=side|front|back, --set rig=R6 (an R6-shaped stand-in instead of R15)
local C = lib("ctr")
local tool = preview.args.tool or "Hammer"
local s = C.boot({ profile = function(data)
	data.EquippedHandheld = tool
	data.OwnedHandhelds = data.OwnedHandhelds or {}
end })
local me = game:GetService("Players").LocalPlayer
local Economy = C.server("EconomyService")
local spot = CFrame.new(400, 0, 400) -- open ground away from the lobby buildings
if preview.args.rig == "R6" then
	-- classic R6 body: one Torso, 1x2x1 limbs, the standard R6 shoulder joints (turned 90 degrees)
	local old = me.Character
	local m = Instance.new("Model")
	m.Name = me.Name
	local function p(name, size, offset, color)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.CFrame = spot * CFrame.new(offset)
		part.Parent = m
		return part
	end
	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), Color3.new(1, 1, 1))
	root.Transparency = 1
	root.Anchored = true
	local torso = p("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), Color3.fromRGB(60, 120, 200))
	p("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0), Color3.fromRGB(240, 200, 160))
	p("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), Color3.fromRGB(240, 200, 160))
	p("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), Color3.fromRGB(240, 200, 160))
	p("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Color3.fromRGB(40, 50, 70))
	p("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Color3.fromRGB(40, 50, 70))
	local function j(name, p0, p1, c0, c1)
		local mo = Instance.new("Motor6D")
		mo.Name = name
		mo.C0 = c0
		mo.C1 = c1
		mo.Part0 = p0
		mo.Part1 = m:FindFirstChild(p1)
		mo.Parent = p0
	end
	j("RootJoint", root, "Torso", CFrame.identity, CFrame.identity)
	j("Neck", torso, "Head", CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	j("Right Shoulder", torso, "Right Arm", CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0), CFrame.new(-0.5, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0))
	j("Left Shoulder", torso, "Left Arm", CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0), CFrame.new(0.5, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	j("Right Hip", torso, "Right Leg", CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0), CFrame.new(0.5, 1, 0) * CFrame.Angles(0, math.pi / 2, 0))
	j("Left Hip", torso, "Left Leg", CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0), CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.Parent = m
	m.PrimaryPart = root
	m.Parent = workspace
	me.Character = m
	if old then
		old:Destroy()
	end
end
C.place(me, spot)
Economy.attachTool(me)
preview.advance(0.2)
local char = me.Character
local root = char:FindFirstChild("HumanoidRootPart")
-- table like StationModels: work surface top y = 3.35 above the floor, plate 2.4 studs ahead
local floor = spot.Position.Y
local function block(name, size, cf, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Parent = workspace
	return p
end
block("Floor", Vector3.new(40, 1, 40), CFrame.new(400, -0.5, 400), Color3.fromRGB(176, 160, 130))
local ahead = root.CFrame * CFrame.new(0.7, 0, -2.6)
local base = CFrame.new(ahead.Position.X, floor, ahead.Position.Z) * root.CFrame.Rotation
block("Top", Vector3.new(7, 0.5, 4), base * CFrame.new(0, 2.75, -0.6), Color3.fromRGB(146, 100, 62))
local plate = block("Plate", Vector3.new(1.9, 0.35, 1.9), base * CFrame.new(0, 3.175, 0), Color3.fromRGB(120, 124, 130))
local at = Instance.new("Attachment")
at.Name = "Plate" -- as StationModels: top centre of the plate
at.Position = Vector3.new(0, 0.175, 0)
at.Parent = plate
block("Rock", Vector3.new(1.3, 0.9, 1.2), base * CFrame.new(0, 3.35 + 0.45, 0), Color3.fromRGB(110, 112, 118))
local t = tonumber(preview.args.t)
if t then
	local ToolAnim = preview.client("ToolAnim")
	ToolAnim.strike(char, tool, false, nil)
	if tool == "Jackhammer" then
		-- keep the pulses coming at the tool's rate
		local n = math.floor(t / 0.2)
		for _ = 1, n do
			preview.advance(0.2)
			ToolAnim.strike(char, tool, false, nil)
		end
		preview.advance(t - n * 0.2)
	else
		preview.advance(t)
	end
end
local v = preview.args.cam or "side"
local off = if v == "front" then Vector3.new(2, 2, -11) elseif v == "back" then Vector3.new(4, 4, 10) else Vector3.new(11, 1.5, -1.5)
C.cameraAt(root.Position + Vector3.new(0, 0.5, -1.2), root.CFrame:VectorToWorldSpace(off), 50)
local held = char:FindFirstChild("CT_Rocks_HeldTool")
if held then
	for _, d in held:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Grip" or d.Name == "Bit" or d.Name == "Head" or d.Name == "Body") then
			preview.log(d.Name .. " " .. tostring(root.CFrame:PointToObjectSpace(d.Position)) .. " size " .. tostring(d.Size))
		end
	end
end
