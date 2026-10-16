--!strict
-- Procedural tool strokes (no animation assets exist yet, so nothing here uses an animation id).
--
-- Arms move through their shoulder Motor6Ds: each frame, after the Animator has posed the rig, an
-- extra rotation is layered onto the shoulder's Transform (RunService.Stepped), so idle and walk
-- animations still play underneath. Poses are written in the torso's frame (x right, y up, -z
-- forward) and converted into each joint's own frame from its C0, so the same numbers work on
-- R15 (RightUpperArm.RightShoulder), R6 (Torso["Right Shoulder"], turned 90 degrees) and rigs
-- with other shoulder names. A rig without a recognisable shoulder gets the whole stroke on the
-- tool grip instead (tool-only fallback). Joints we touched are restored exactly when a stroke
-- ends or stop() is called: if the Animator did not rewrite a Transform this frame, our previous
-- layer is removed before the next is added, so nothing accumulates on rigs without animations.
--
-- Hammer / steel hammer (0.65 s / 0.55 s): wind-up overhead with the head cocked back, an
-- accelerating swing that brings the head down onto the work in front at the contact moment
-- (onContact fires there), a short recoil, then back to the carry pose.
-- Jackhammer: start (0.15 s ease in), loop while pulses keep arriving, stop (0.18 s ease out).
-- Both hands go to the two grips, the tool is held upright with the silver bit down; its height
-- follows the work surface found by a ray below the bit (the rock on the table plate). Vibration
-- is a small local shake of the tool (at most 0.05 stud), none with reduced motion. Moving away,
-- unequipping or stop() (round end, reveal) ends it. Purely cosmetic: the server decides hits.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ToolAnim = {}

type Swing = {
	Start: number,
	Total: number,
	Contact: (() -> ())?,
	ContactDone: boolean,
	Reduced: boolean,
}

type Jack = {
	Start: number,
	Until: number,
	Reduced: boolean,
	Origin: Vector3,
	Raise: number,
	Work: Vector3?,
	RayAt: number,
	StopAt: number?,
}

type Rig = {
	Right: Motor6D?,
	Left: Motor6D?,
	RightHand: BasePart?,
	LeftHand: BasePart?,
	Root: BasePart?,
}

local swings: { [Model]: Swing } = {}
local jacks: { [Model]: Jack } = {}
local layers: { [Motor6D]: { Base: CFrame, Wrote: CFrame } } = {}
local restGrip: { [Motor6D]: CFrame } = {}

local HAMMER_CONTACT = 0.49 -- fraction of the stroke at which the head meets the work
local JACK_IN, JACK_OUT = 0.15, 0.18
local MAX_LEAN = math.rad(32) -- the bit leans toward the stone by at most this much

local function findMotor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

local function rigOf(character: Model): Rig
	local r: Rig = {}
	r.Right = findMotor(character:FindFirstChild("RightUpperArm"), "RightShoulder") or findMotor(character:FindFirstChild("Torso"), "Right Shoulder")
	r.Left = findMotor(character:FindFirstChild("LeftUpperArm"), "LeftShoulder") or findMotor(character:FindFirstChild("Torso"), "Left Shoulder")
	if not r.Right then
		-- other rigs: any Motor6D whose name says right + shoulder/arm
		for _, d in character:GetDescendants() do
			if d:IsA("Motor6D") then
				local n = string.lower(d.Name)
				if string.find(n, "right") and (string.find(n, "shoulder") or string.find(n, "arm")) then
					r.Right = d
				elseif string.find(n, "left") and (string.find(n, "shoulder") or string.find(n, "arm")) then
					r.Left = r.Left or d
				end
			end
		end
	end
	local function part(name: string, alt: string): BasePart?
		local p = character:FindFirstChild(name) or character:FindFirstChild(alt)
		return if p and p:IsA("BasePart") then p else nil
	end
	r.RightHand = part("RightHand", "Right Arm")
	r.LeftHand = part("LeftHand", "Left Arm")
	r.Root = part("HumanoidRootPart", "Torso")
	return r
end

local function toolOf(character: Model): (Model?, Motor6D?)
	local tool = character:FindFirstChild("CT_Rocks_HeldTool")
	if not tool or not tool:IsA("Model") then
		return nil, nil
	end
	local grip = tool.PrimaryPart
	local m = grip and grip:FindFirstChild("ToolGrip")
	return tool, if m and m:IsA("Motor6D") then m else nil
end

local function rest(tool: Model?, g: Motor6D): CFrame
	local saved = restGrip[g]
	if saved then
		return saved
	end
	local attr = tool and tool:GetAttribute("RestC0")
	local base = if typeof(attr) == "CFrame" then attr else g.C0
	restGrip[g] = base
	g.Destroying:Connect(function()
		restGrip[g] = nil
	end)
	return base
end

-- Layer `torsoRot` (a rotation about the joint, in the torso's frame) onto a shoulder.
local function layer(m: Motor6D, torsoRot: CFrame)
	local c0 = m.C0.Rotation
	local extra = c0:Inverse() * torsoRot * c0
	local cur = m.Transform
	local rec = layers[m]
	local base = if rec and cur == rec.Wrote then rec.Base else cur
	local out = base * extra
	m.Transform = out
	layers[m] = { Base = base, Wrote = out }
end

local function unlayer(m: Motor6D?)
	if not m then
		return
	end
	local rec = layers[m]
	if rec then
		if m.Transform == rec.Wrote then
			m.Transform = rec.Base
		end
		layers[m] = nil
	end
end

-- Hammer head squash on contact: the head pieces (Part tools: Head / FaceL / FaceR; kit tools: Steel /
-- SteelLight) shrink along their longest axis (the striking axis) and bulge a little on the other two,
-- about their own centres, so welds and the grip are untouched. Rest sizes are kept per part (weak keys).
local HEAD_PARTS = { Head = true, FaceL = true, FaceR = true, Steel = true, SteelLight = true }
local headCache: { [Model]: { [BasePart]: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
local squashed: { [Model]: boolean? } = setmetatable({}, { __mode = "k" }) :: any

-- amount 0 = rest size; about 0.12 reads as a firm hit.
function ToolAnim.squash(tool: Model, amount: number)
	if amount <= 0 and not squashed[tool] then
		return
	end
	local heads = headCache[tool]
	if not heads then
		local found: { [BasePart]: Vector3 } = {}
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") and HEAD_PARTS[d.Name] then
				found[d] = d.Size
			end
		end
		headCache[tool] = found
		heads = found
	end
	squashed[tool] = if amount > 0 then true else nil
	for part, size in heads do
		if part.Parent then
			if amount <= 0 then
				part.Size = size
			else
				local long = math.max(size.X, size.Y, size.Z)
				local function f(v: number): number
					return v * (if v == long then 1 - amount else 1 + amount * 0.5)
				end
				part.Size = Vector3.new(f(size.X), f(size.Y), f(size.Z))
			end
		end
	end
end

local function restore(character: Model)
	local r = rigOf(character)
	unlayer(r.Right)
	unlayer(r.Left)
	local tool, g = toolOf(character)
	if g then
		g.C0 = rest(tool, g)
	end
	if tool then
		ToolAnim.squash(tool, 0)
	end
end

-- Torso-frame arm rotation: raise forward by `raise` (0 = hanging, pi/2 = straight ahead), then
-- bring the hand toward the body's centre line by `inward` (side = +1 right arm, -1 left arm).
local function armRot(raise: number, inward: number, side: number): CFrame
	return CFrame.Angles(raise, 0, 0) * CFrame.Angles(0, 0, -side * inward)
end

local function fistOf(hand: BasePart): CFrame
	return hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 + 0.15, 0)
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function smooth(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Hammer keyframes: arm raise and the tool's angle in the hand's frame (about the hand's X axis;
-- the carry pose is -28 degrees, head up and a little forward).
local KEYS = {
	{ u = 0.0, raise = 0, tool = -28 },
	{ u = 0.3, raise = 165, tool = -135 }, -- wound up overhead, head cocked back
	{ u = HAMMER_CONTACT, raise = 128, tool = -278 }, -- head comes down on the work in front
	{ u = 0.6, raise = 136, tool = -262 }, -- recoil
	{ u = 1.0, raise = 0, tool = -28 },
}

local function hammerPose(u: number): (number, number)
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if u <= b.u then
			local k = (u - a.u) / (b.u - a.u)
			-- ease out on the wind-up, accelerate into contact, ease out of the recoil
			local e = if i == 1 then 1 - (1 - k) ^ 2 elseif i == 2 then k * k else smooth(k)
			return math.rad(lerp(a.raise, b.raise, e)), math.rad(lerp(a.tool, b.tool, e))
		end
	end
	return 0, math.rad(-28)
end

-- Start one stroke on a character. toolId nil = read it from the held tool.
-- Pet gear is passive: nothing is swung. A work tap is only the contact callback (hit effects) after a short beat.
function ToolAnim.strike(_character: Model, _toolId: string?, _reduced: boolean?, onContact: (() -> ())?)
	if onContact then
		task.delay(0.15, onContact)
	end
end

function ToolAnim.stop(character: Model)
	swings[character] = nil
	jacks[character] = nil
	restore(character)
end

-- The point the bit works on, cached briefly: a ray down in front of the avatar finds the rock on
-- the table plate (or the plate); without a hit, the nearest table "Plate" attachment (the rock
-- sits on it); else a spot at knee-to-hip height in front.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local plates: { Attachment } = {}
local platesAt = -math.huge
local function workPoint(character: Model, root: BasePart, j: Jack, now: number): Vector3
	if j.Work and now - j.RayAt < 0.15 then
		return j.Work :: Vector3
	end
	j.RayAt = now
	rayParams.FilterDescendantsInstances = { character }
	local probe = root.CFrame * CFrame.new(0, 2.5, -2.2)
	local hit = Workspace:Raycast(probe.Position, Vector3.new(0, -9, 0), rayParams)
	local work = (root.CFrame * CFrame.new(0, -1.1, -2)).Position
	if hit and hit.Position.Y > root.Position.Y - 3.5 and hit.Position.Y < root.Position.Y + 3 then
		work = hit.Position
	else
		if now - platesAt > 5 then
			platesAt = now
			table.clear(plates)
			for _, d in Workspace:GetDescendants() do
				if d:IsA("Attachment") and d.Name == "Plate" then
					table.insert(plates, d)
				end
			end
		end
		local best = 6
		for _, a in plates do
			local d = (a.WorldPosition - root.Position) * Vector3.new(1, 0, 1)
			if a.Parent and d.Magnitude < best then
				best = d.Magnitude
				work = a.WorldPosition + Vector3.new(0, 0.8, 0) -- top of a rock on the plate
			end
		end
	end
	j.Work = work
	return work
end

local function stepSwing(character: Model, sw: Swing, now: number): boolean
	local u = (now - sw.Start) / sw.Total
	if u >= 1 then
		restore(character)
		return false
	end
	if not sw.ContactDone and u >= HAMMER_CONTACT then
		sw.ContactDone = true
		if sw.Contact then
			task.spawn(sw.Contact)
		end
	end
	local raise, toolAng = hammerPose(u)
	local hit = (u - HAMMER_CONTACT) / 0.14 -- head squash just after contact (none with reduced motion)
	local held = toolOf(character)
	if held then
		ToolAnim.squash(held, if sw.Reduced or hit < 0 or hit > 1 then 0 else 0.13 * math.sin(hit * math.pi))
	end
	if sw.Reduced then
		-- a small tap instead of the full overhead swing
		raise *= 0.4
		toolAng = math.rad(-28) + (toolAng - math.rad(-28)) * 0.4
	end
	local r = rigOf(character)
	local tool, g = toolOf(character)
	if r.Right then
		layer(r.Right, armRot(raise, 0, 1))
	end
	if g then
		local base = rest(tool, g)
		local fist = base * CFrame.Angles(math.rad(28), 0, 0) -- the fist frame (rest without its tilt)
		if r.Right then
			g.C0 = fist * CFrame.Angles(toolAng, 0, 0)
		else
			-- no shoulder: the whole stroke happens at the grip
			g.C0 = fist * CFrame.Angles(toolAng - raise, 0, 0)
		end
	end
	return true
end

local function stepJack(character: Model, j: Jack, now: number): boolean
	local r = rigOf(character)
	local tool, g = toolOf(character)
	local root = r.Root
	if not tool or tool:GetAttribute("ToolId") ~= "Jackhammer" or not g or not root then
		restore(character)
		return false
	end
	-- moving away from where it started ends the loop
	local flat = root.Position - j.Origin
	if not j.StopAt and (now > j.Until or Vector3.new(flat.X, 0, flat.Z).Magnitude > 3) then
		j.StopAt = now
	end
	local w = smooth((now - j.Start) / JACK_IN)
	if j.StopAt then
		w = math.min(w, 1 - smooth((now - j.StopAt) / JACK_OUT))
		if w <= 0 then
			restore(character)
			return false
		end
	end
	local len = -((tool:GetAttribute("TipY") :: number?) or -2.4) -- handlebar to bit tip
	local gripX = (tool:GetAttribute("GripX") :: number?) or 0.6
	local work = workPoint(character, root, j, now)
	local hand = r.RightHand
	if r.Right and hand then
		-- raise the arms until the bit (leaning at most MAX_LEAN toward the work) reaches it
		local m = r.Right :: Motor6D
		local joint = ((m.Part0 :: BasePart).CFrame * m.C0).Position
		local armLen = math.max((fistOf(hand).Position - joint).Magnitude, 0.5)
		local handY = work.Y + len * math.cos(MAX_LEAN * 0.7)
		local want = math.acos(math.clamp((joint.Y - handY) / armLen, -1, 1))
		want = math.clamp(want, math.rad(40), math.rad(150))
		j.Raise = if j.Raise == 0 then want else lerp(j.Raise, want, 0.25)
		local half = math.abs((root.CFrame:PointToObjectSpace(joint)).X)
		local inward = math.asin(math.clamp((half - gripX) / armLen, 0, 0.9))
		layer(m, armRot(j.Raise * w, inward * w, 1))
		if r.Left then
			layer(r.Left, armRot(j.Raise * w, inward * w, -1))
		end
	end
	-- the tool: handlebar centred between the two fists, body hanging with the bit aimed at the
	-- work (upright, leaning toward the stone by at most MAX_LEAN), facing the avatar's way
	local centre: Vector3
	if hand then
		local rf = fistOf(hand).Position
		local lf = if r.LeftHand and r.Left then fistOf(r.LeftHand :: BasePart).Position else rf - root.CFrame.RightVector * gripX * 2
		centre = (rf + lf) / 2
	else
		centre = work + Vector3.new(0, len, 0)
	end
	local down = work - centre
	if down.Magnitude < 0.1 or down.Y > -0.1 then
		down = Vector3.new(0, -1, 0)
	end
	down = down.Unit
	local lean = math.acos(math.clamp(-down.Y, -1, 1))
	if lean > MAX_LEAN then
		local horiz = Vector3.new(down.X, 0, down.Z)
		horiz = if horiz.Magnitude > 1e-3 then horiz.Unit else Vector3.zero
		down = (Vector3.new(0, -math.cos(MAX_LEAN), 0) + horiz * math.sin(MAX_LEAN)).Unit
	end
	local fwd = root.CFrame.LookVector
	local up = -down
	local right = fwd:Cross(up)
	right = if right.Magnitude > 1e-3 then right.Unit else root.CFrame.RightVector
	local back = right:Cross(up).Unit
	local orient = CFrame.fromMatrix(Vector3.zero, right, up, back)
	local shake = Vector3.zero
	if not j.Reduced then
		local t = now - j.Start
		shake = Vector3.new(math.sin(t * 97) * 0.012, (if (t * 26) % 1 < 0.5 then 0.05 else -0.03) * w, math.sin(t * 83 + 1) * 0.012)
	end
	local goal = CFrame.new(centre) * orient * CFrame.new(shake)
	local partner = g.Part0 :: BasePart
	local target = partner.CFrame:Inverse() * goal
	local base = rest(tool, g)
	g.C0 = base:Lerp(target, w)
	return true
end

RunService.Stepped:Connect(function()
	local now = os.clock()
	for character, sw in swings do
		if not character.Parent or not stepSwing(character, sw, now) then
			swings[character] = nil
		end
	end
	for character, j in jacks do
		if not character.Parent or not stepJack(character, j, now) then
			jacks[character] = nil
		end
	end
end)

-- Pickup reach: the right arm reaches forward and comes back (0.4 s). Tools are stowed while
-- collecting, so only the shoulder moves (applied after the Animator, like the strike).

local scoops: { [Model]: number } = {}

function ToolAnim.scoop(character: Model)
	local t = scoops[character]
	if t and os.clock() - t < 0.36 then
		return
	end
	scoops[character] = os.clock()
end

-- Carry pose (other players, third person): both arms come forward and in, under the basket, while it holds
-- rocks; eased in and out (0.2 s). Layered on the shoulders after the Animator like the strike; skipped
-- while the same avatar strikes, runs a jackhammer or scoops. Cosmetic only. on=false eases out and restores.
local carrying: { [Model]: { On: boolean, W: number } } = {}
local CARRY_RAISE, CARRY_INWARD = math.rad(40), 0.1

function ToolAnim.carry(character: Model, on: boolean, reduced: boolean?)
	local c = carrying[character]
	if c then
		c.On = on
	elseif on then
		carrying[character] = { On = true, W = if reduced then 1 else 0 }
	end
end

function ToolAnim.isCarrying(character: Model): boolean
	local c = carrying[character]
	return c ~= nil and c.On
end

local lastCarry = os.clock()
RunService.Stepped:Connect(function()
	local now = os.clock()
	local dt = math.min(now - lastCarry, 0.1)
	lastCarry = now
	for character, c in carrying do
		if not character.Parent then
			carrying[character] = nil
			continue
		end
		c.W = math.clamp(c.W + (if c.On then dt else -dt) / 0.2, 0, 1)
		local r = rigOf(character)
		if swings[character] or jacks[character] or scoops[character] then
			continue -- another stroke owns the arms this frame
		end
		if c.W <= 0 then
			unlayer(r.Right)
			unlayer(r.Left)
			carrying[character] = nil
			continue
		end
		local w = smooth(c.W)
		if r.Right then
			layer(r.Right, armRot(CARRY_RAISE * w, CARRY_INWARD * w, 1))
		end
		if r.Left then
			layer(r.Left, armRot(CARRY_RAISE * w, CARRY_INWARD * w, -1))
		end
	end
end)

-- Turns the character's root toward a point (yaw only) so a swing lands on the plate in front of
-- it. Only call for the local player's own character (its owner moves it).
function ToolAnim.face(character: Model, target: Vector3)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local p = root.Position
		local flat = Vector3.new(target.X, p.Y, target.Z)
		if (flat - p).Magnitude > 0.2 then
			root.CFrame = CFrame.lookAt(p, flat)
		end
	end
end

RunService.Stepped:Connect(function()
	local now = os.clock()
	for character, t0 in scoops do
		local u = (now - t0) / 0.4
		if u >= 1 or not character.Parent then
			scoops[character] = nil
			continue
		end
		local angle = math.rad(62) * math.sin(math.pi * u)
		local upper = character:FindFirstChild("RightUpperArm")
		local m = upper and upper:FindFirstChild("RightShoulder")
		if m and m:IsA("Motor6D") then
			m.Transform = m.Transform * CFrame.Angles(angle, 0, 0)
		else
			local torso = character:FindFirstChild("Torso")
			local m6 = torso and torso:FindFirstChild("Right Shoulder")
			if m6 and m6:IsA("Motor6D") then
				m6.Transform = m6.Transform * CFrame.Angles(0, 0, angle)
			end
		end
	end
end)

return ToolAnim
