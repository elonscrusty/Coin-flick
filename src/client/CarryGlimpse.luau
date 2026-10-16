--!strict
-- First-person carried load (docs/m6/FIRST_PERSON.md section 6). The avatar's own crate is hidden from the
-- own view (CameraMode.hideLocally), so a small readable glimpse of the load rides at the lower edge of the
-- view instead: a basket lip with the real rocks (the exact silhouettes in the server's basket list) peeking
-- over it, never near the centre, the horizon, the target rock or the table plate.
--
--   * one bounded local model (a lip, two end posts, at most Config.Camera.Glimpse.Max stone minis),
--     rebuilt only when the accepted basket list changes, moved with the camera in one render step
--   * a pickup cue when the count goes UP after the server accepted it: a short dip of the lip and a quiet
--     stone sound (no predicted feedback exists, so a refused pickup has nothing to undo)
--   * shown only in first person, during a hunt, with a non-empty basket and no panel open; gone with the
--     round (clear) and on any view change; other players see the normal crate on the avatar
-- Purely visual and local: anchored, non-colliding, non-queryable parts, no physics, nothing to collect.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeModel = require(Shared.GeodeModel)
local State = require(script.Parent.State)
local CarryView = require(script.Parent.CarryView)
local CameraMode = require(script.Parent.CameraMode)
local Audio = require(script.Parent.Audio)
local UI = require(script.Parent.ui.UI)

local CarryGlimpse = {}

local player = Players.LocalPlayer
local WOOD = Color3.fromRGB(150, 112, 74)
local WOOD_DARK = Color3.fromRGB(112, 82, 54)
local METAL = Color3.fromRGB(150, 140, 128) -- warm light grey: the dark rim read as a black strip under the hotbar

local model: Model? = nil
local shownIds: { number } = {}
local seed = 1
local bump = 0 -- 0..1 dip amount of the pickup cue
local bumpTween: Tween? = nil
local bumpValue: NumberValue? = nil
local clock = 0

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Local frame: x right, y up, z toward the viewer's back (the model is placed in front of the camera).
local function build(ids: { number })
	if model then
		model:Destroy()
		model = nil
	end
	if #ids == 0 then
		return
	end
	local m = Instance.new("Model")
	m.Name = "CT_Rocks_Glimpse"
	local anchor = part(m, "Anchor", Vector3.new(0.1, 0.1, 0.1), CFrame.new(), METAL, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	m.PrimaryPart = anchor -- the pivot is the local origin, not the bounding box centre
	-- the lip: a front board, a darker back board and a yellow band like the station trim
	part(m, "LipFront", Vector3.new(1.9, 0.5, 0.14), CFrame.new(0, 0, 0.5), WOOD_DARK, Enum.Material.WoodPlanks)
	part(m, "Band", Vector3.new(1.94, 0.1, 0.16), CFrame.new(0, 0.1, 0.5), Config.Palette.Yellow, Enum.Material.SmoothPlastic)
	part(m, "Rim", Vector3.new(1.98, 0.07, 0.2), CFrame.new(0, 0.27, 0.5), METAL, Enum.Material.Metal)
	part(m, "Floor", Vector3.new(1.8, 0.1, 0.9), CFrame.new(0, -0.22, 0.1), WOOD, Enum.Material.WoodPlanks)
	for _, sx in { -0.93, 0.93 } do
		part(m, "End", Vector3.new(0.12, 0.5, 0.9), CFrame.new(sx, 0, 0.1), WOOD, Enum.Material.WoodPlanks)
	end
	local slots = {
		Vector3.new(-0.62, 0.42, 0.2), Vector3.new(0, 0.44, 0.2), Vector3.new(0.62, 0.42, 0.2),
		Vector3.new(-0.3, 0.62, -0.1), Vector3.new(0.3, 0.62, -0.1),
	}
	for i, id in ids do
		if i > math.min(Config.Camera.Glimpse.Max, #slots) then
			break
		end
		local variant, tint, yaw = GeodeModel.rockLook(id, seed)
		local mini = GeodeModel.rockShell(variant, 0.6, "g" .. i, { Tint = tint, Mini = true })
		mini:PivotTo(CFrame.new(slots[i]) * CFrame.Angles(0, math.rad(yaw), 0))
		mini.Parent = m
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	m.Parent = Workspace
	model = m
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

local function wanted(): boolean
	local m = State.Match
	return CameraMode.firstPerson() and m ~= nil and (m.Phase == "Searching" or m.Phase == "Countdown") and not UI.blocked()
end

local function cue()
	if UI.Reduced then
		return
	end
	if bumpTween then
		bumpTween:Cancel()
	end
	local nv = bumpValue
	if not nv then
		local made = Instance.new("NumberValue")
		made:GetPropertyChangedSignal("Value"):Connect(function()
			bump = made.Value
		end)
		bumpValue = made
		nv = made
	end
	local value = nv :: NumberValue
	value.Value = 1
	local tw = TweenService:Create(value, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 })
	bumpTween = tw
	tw:Play()
end

local function refresh()
	local ids = CarryView.shown(player.UserId)
	if sameList(ids, shownIds) and (model ~= nil) == (#ids > 0) then
		return
	end
	local grew = #ids > #shownIds
	shownIds = ids
	build(ids)
	if grew and wanted() then
		cue()
		Audio.pickup()
	end
end

local function place()
	local cam = Workspace.CurrentCamera
	local m = model
	if not m or not cam then
		return
	end
	if not wanted() then
		if m.Parent then
			m.Parent = nil
		end
		return
	end
	if m.Parent ~= Workspace then
		m.Parent = Workspace
	end
	local off = Config.Camera.Glimpse.Offset
	-- facing the same way as the camera, tipped toward the viewer a little so the load reads from above
	m:PivotTo(cam.CFrame * CFrame.new(off.X, off.Y + bump * 0.16, off.Z) * CFrame.Angles(math.rad(-14), 0, math.rad(4)))
end

-- No resting first-person tool: the avatar's own held tool is hidden locally (CameraMode) and a small copy parked at the
-- lower-right edge read as a mallet floating in the air with no hand on it (Studio sweep 189). Between strokes the
-- first-person view shows no tool; StationView's stroke copy swings in for each hit. Other players see the normal tool.

function CarryGlimpse.start()
	RunService:BindToRenderStep("CTR_CarryGlimpse", Enum.RenderPriority.Camera.Value + 3, function(dt)
		clock += dt
		if clock >= 0.1 then
			clock = 0
			refresh()
		end
		place()
	end)
	State.Changed.Event:Connect(function(what)
		if what == "Match" then
			local m = State.Match
			if m == nil then
				CarryGlimpse.clear()
			end
		end
	end)
end

function CarryGlimpse.setSeed(s: number)
	seed = s
end

function CarryGlimpse.clear()
	shownIds = {}
	if model then
		model:Destroy()
		model = nil
	end
	bump = 0
end

return CarryGlimpse
