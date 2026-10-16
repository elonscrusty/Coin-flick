--!strict
-- Pet animation for the real skinned pet meshes (ReplicatedStorage.PetModels). Runs on the CLIENT: Bone /
-- Motor6D.Transform does not replicate. Lives at ReplicatedStorage.PetMotion; all the "how does it move" maths is in
-- ReplicatedStorage.Shared.PetPose (pure, tested) and the clips in Shared.PetClips. This file only finds the bones,
-- measures speed, aims the head and writes the pose.
--
-- API (used through client/PetMotionBridge, PetFollow, PetDisplay, RevealView, PvpPanel):
--   PetMotion.start(model)            animate it (idle / walk); safe to call twice
--   PetMotion.setBase(model, cf)      where the pet stands this frame (it is re-pivoted from here every frame)
--   PetMotion.hatch / celebrate / spin / hop(model)
--   PetMotion.play(model, "attack"|"hit"|"win") -> boolean   one-shot clip, then back to the loop
-- Model attributes read: Moving (bool), Anim ("idle"|"walk"|"run"|"train"|nil), WalkRate (number), Sleepy (bool),
-- LookAt (Vector3), Species (species id, set by PetModel), Gait ("quad"|"biped"|"heavy"|"hopper"|"waddle", optional override).
-- Rigs: Bones or Motor6Ds named Body, Head, Tail, LegL, LegR, LegBL, LegBR, WingL, WingR, Arms (optionally prefixed,
-- e.g. "Raptor_Head"). A rig without bones gets a gentle bob. Owner rules: no mouth opening (a Jaw bone is held
-- shut), no roar. Merged 2026-10-15 from the two copies that had split (clips + play / LookAt, Sleepy, spin, hop).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetPose")) :: any

local PetMotion = {}

type State = {
	pose: any, base: CFrame, gone: number, joints: { [string]: any }, fwd: number, height: number, scale: number,
	gait: string, rigged: boolean, speed: number, lastPos: Vector3?,
}
-- Strong on purpose: a weak Instance key can vanish while the pet still exists (Roblox may recycle the Lua wrapper).
-- Entries leave on Destroying, or after GONE seconds out of the DataModel; setBase restarts a pet that comes back.
local active: { [Model]: State } = {}
-- Weak keys: the bones are held by their pet's State while it animates; afterwards the entries can go.
local restRot: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local GONE = 2 -- seconds out of the game before a pet is dropped (start() may run just before parenting)
local CULL = 120 -- studs: world pets farther than this from the camera are not animated this frame
local TELEPORT = 12 -- studs in one frame: a jump of the base this big is a teleport, not walking speed

local function drop(model: Model)
	local s = active[model]
	if not s then return end
	active[model] = nil
	for _, jj in s.joints do
		if typeof(jj) == "Instance" then restRot[jj] = nil end
	end
end

local function jointPos(j: any, part: BasePart?): Vector3?
	if j == nil then return nil end
	if j:IsA("Bone") and part then return part.CFrame:PointToObjectSpace(j.WorldPosition) end
	if j:IsA("Motor6D") and j.Part0 then return j.Part0.CFrame:PointToObjectSpace((j.Part0.CFrame * j.C0).Position) end
	return nil
end

-- "CT_Pet_Raptor" / "Pet_Raptor" -> "Raptor"
local function speciesOf(model: Model): string?
	return model.Name:match("^CT_Pet_(.+)$") or model.Name:match("^Pet_(.+)$")
end

function PetMotion.start(model: Model)
	if active[model] then return end
	local joints: { [string]: any } = {}
	local part: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Bone") then joints[d.Name:match("_(%a+)$") or d.Name] = d end
		if d:IsA("Bone") then
			local p = d:FindFirstAncestorWhichIsA("BasePart")
			if p then
				part = p
				restRot[d] = p.CFrame.Rotation:Inverse() * d.WorldCFrame.Rotation
			end
		end
	end
	-- which way the face points along the part's Z: the head sits in front of the tail (tail first: a tall bird's
	-- head is right above its body)
	local fwd = 1
	local a = jointPos(joints.Head or joints.Jaw, part)
	local b = jointPos(joints.Tail or joints.Body, part)
	if a and b and math.abs(a.Z - b.Z) > 0.01 then fwd = if a.Z < b.Z then -1 else 1 end
	local hasMotors = false
	for _, jj in joints do if jj:IsA("Motor6D") then hasMotors = true end end
	local root = model.PrimaryPart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = (not hasMotors) or d == root
		end
	end
	local over = model:GetAttribute("Gait")
	local attr = model:GetAttribute("Species") -- set by PetModel; followers are renamed Pet_<uid>_n
	local id = if type(attr) == "string" then attr else speciesOf(model)
	local gait = if type(over) == "string" and PetPose.GAITS[over] then over
		else PetPose.gaitFor(id, model.Name, model:GetAttribute("Kind") :: string?, if next(joints) then joints.LegBL ~= nil else nil)
	local seed = 0
	for k = 1, #model.Name do seed = (seed * 31 + string.byte(model.Name, k)) % 9973 end
	active[model] = {
		pose = PetPose.new(seed + math.random(0, 50)), base = model:GetPivot(), gone = 0, joints = joints, fwd = fwd,
		height = math.max(model:GetExtentsSize().Y, 0.3), scale = model:GetScale(), gait = gait,
		rigged = next(joints) ~= nil, speed = 0, lastPos = nil,
	}
	model.Destroying:Once(function() drop(model) end)
end

function PetMotion.setBase(model: Model, cf: CFrame)
	local s = active[model]
	if not s and model.Parent and model:IsDescendantOf(game) then
		-- dropped while it was out of the game (a follower hidden over a respawn): pick it up again
		PetMotion.start(model)
		s = active[model]
	end
	if s then s.base = cf end
end

local function pop(model: Model, kind: string)
	PetMotion.start(model)
	local s = active[model]
	if s then PetPose.pop(s.pose, kind) end
end
-- Hatch: crouch, happy hop, land with a squash.
function PetMotion.hatch(model: Model) pop(model, "hatch") end
-- Celebrate: two hops with a spin (no roar).
function PetMotion.celebrate(model: Model) pop(model, "celebrate") end
-- Spin: one hop with a full turn (a pet levelling up).
function PetMotion.spin(model: Model) pop(model, "spin") end
-- Hop: one small hop on the spot (the owner jumped). Never cuts a hatch / celebrate / spin short.
function PetMotion.hop(model: Model) pop(model, "hop") end

-- One-shot clip (attack / hit / win) over whatever the pet is doing; it returns to the loop when done.
function PetMotion.play(model: Model, name: string): boolean
	PetMotion.start(model)
	local s = active[model]
	return s ~= nil and PetPose.play(s.pose, name)
end

-- Head yaw / pitch (pitch + = nose down) toward a world point, in the head's own frame; nil when unknown.
local function aimAt(j: any, f: number, at: Vector3): (number?, number?)
	if j == nil then return nil end
	local frame: BasePart? = nil
	local pos: Vector3? = nil
	if j:IsA("Bone") then
		frame = j:FindFirstAncestorWhichIsA("BasePart")
		pos = j.WorldPosition
	elseif j:IsA("Motor6D") and j.Part0 then
		frame = j.Part0
		pos = (j.Part0.CFrame * j.C0).Position
	end
	if not frame or not pos then return nil end
	local lp = frame.CFrame:VectorToObjectSpace(at - pos)
	local flat = math.sqrt(lp.X * lp.X + lp.Z * lp.Z)
	if flat < 0.3 then return nil end
	return math.atan2(f * lp.X, f * lp.Z), -math.atan2(lp.Y, flat)
end

local function set(j: { [string]: any }, name: string, cf: CFrame)
	local m = j[name]
	if not m then return end
	local r = restRot[m]
	if r then
		m.Transform = r:Inverse() * cf * r
	else
		m.Transform = cf
	end
end

-- a > 0 = nose / tip down, whichever way the pet faces (f = +1 faces +Z, -1 faces -Z)
local function pitchF(f: number, a: number, yaw: number?, roll: number?): CFrame
	return CFrame.Angles(a * f, (yaw or 0), (roll or 0) * f)
end

local input: { [string]: any } = {}

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 1 / 15)
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else nil
	for model, s in active do
		local inWorld = model:IsDescendantOf(Workspace)
		if not inWorld and not model:IsDescendantOf(game) then
			s.gone += dt
			if s.gone >= GONE then drop(model) end
			continue
		end
		s.gone = 0
		-- distance culling (world pets only; ViewportFrame pets have their own camera)
		if inWorld and camPos and (s.base.Position - camPos).Magnitude > CULL then continue end
		local f = s.fwd
		local j = s.joints

		-- ground speed from how far the base moved (feet keep pace with it in PetPose)
		local pos = s.base.Position
		local inst = 0
		if s.lastPos then
			local d = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude
			if d < TELEPORT then inst = d / math.max(dt, 1e-3) end
		end
		s.lastPos = pos
		s.speed += (inst - s.speed) * math.min(1, dt * 8)
		local sc = model:GetScale()
		if sc ~= s.scale then -- re-scaled after start (followers are fitted to one height)
			s.height = math.max(s.height * sc / s.scale, 0.3)
			s.scale = sc
		end

		local lookAt = model:GetAttribute("LookAt")
		local aimYaw, aimPitch = nil, nil
		if typeof(lookAt) == "Vector3" then
			aimYaw, aimPitch = aimAt(j.Head, f, lookAt)
		end
		local look = s.base.LookVector
		local anim = model:GetAttribute("Anim")
		local rate = model:GetAttribute("WalkRate")
		input.moving = model:GetAttribute("Moving") == true
		input.speed = if input.moving then s.speed else 0
		input.height = s.height
		input.gait = s.gait
		input.rigged = s.rigged
		input.anim = if type(anim) == "string" then anim else nil
		input.walkRate = if type(rate) == "number" then rate else nil
		input.sleepy = model:GetAttribute("Sleepy") == true
		input.aimYaw, input.aimPitch = aimYaw, aimPitch
		input.yaw = math.atan2(-look.X, -look.Z)
		local V = PetPose.step(s.pose, input, dt)

		set(j, "LegL", pitchF(f, V.legFL))
		set(j, "LegR", pitchF(f, V.legFR))
		set(j, "LegBL", pitchF(f, V.legBL))
		set(j, "LegBR", pitchF(f, V.legBR))
		set(j, "Tail", pitchF(f, V.tailP, V.tailY))
		set(j, "Arms", pitchF(f, V.arms))
		set(j, "WingL", CFrame.Angles(0, 0, V.wing))
		set(j, "WingR", CFrame.Angles(0, 0, -V.wing))
		set(j, "Head", pitchF(f, V.headP, V.headY, V.headR))
		set(j, "Jaw", CFrame.identity) -- owner rule (2026-10-12): the mouth / beak never opens
		-- the whole-body moves use the pivot, which always faces -Z (PetModel turns backwards meshes round), so a
		-- lunge goes forward and "nose down" is down even for a mesh modelled facing +Z
		local offset = CFrame.new(0, V.rootY, -V.rootZ)
			* CFrame.Angles(0, V.rootYaw, V.rootR)
			* CFrame.Angles(-V.rootP, 0, 0)
		model:PivotTo(s.base * offset)
	end
end)

return PetMotion
