--!strict
-- Animates server-built mesh pets on the client (plots, domes, hatch stands, gallery shelves). Bone.Transform does
-- not replicate, so the server's copies stand still unless each client starts PetMotion on them. Server-built
-- template pets are tagged "PetDisplay" (PetModel.fromTemplate on the server; other builders may tag their own).
-- Followers are built on the client and started by PetFollow, so they are not tagged. Nothing happens when
-- PetModels / PetMotion are missing (PetMotionBridge). Display pets turn their heads toward the nearest player walking
-- by (within LOOK_RANGE studs; the "LookAt" model attribute PetMotion eases toward), five times a second.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Bridge = require(script.Parent.PetMotionBridge)

local PetDisplay = {}

local TAG = "PetDisplay"
local started: { [Instance]: boolean } = setmetatable({} :: any, { __mode = "k" })

local function try(inst: Instance)
	if started[inst] or not inst:IsA("Model") or not inst:IsDescendantOf(Workspace) then
		return
	end
	if Bridge.start(inst) then
		started[inst] = true
	end
end

-- Dome pets (tag "PetSpin", set by GalleryService) turn slowly on the spot. Local only; nearby ones only.
local SPIN_TAG = "PetSpin"
local SPIN_RATE = 0.35 -- radians per second
local SPIN_RANGE = 90
local spinning: { [Model]: CFrame } = setmetatable({} :: any, { __mode = "k" })

local function stepSpin(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	for m, base in spinning do
		if not m.Parent then
			spinning[m] = nil
			continue
		end
		local pos = base.Position
		if (pos - camPos).Magnitude < SPIN_RANGE then
			local base2 = base * CFrame.Angles(0, os.clock() * SPIN_RATE, 0)
			if not Bridge.setBase(m, base2) then -- PetMotion re-pivots mesh pets from its base every frame
				m:PivotTo(base2)
			end
		end
	end
end

local function trySpin(inst: Instance)
	if inst:IsA("Model") and inst:IsDescendantOf(Workspace) and not spinning[inst] then
		spinning[inst] = inst:GetPivot()
	end
end

-- Passer-by look: the nearest character head within LOOK_RANGE of each animated display pet near the camera.
local LOOK_RANGE = 20
local LOOK_EVERY = 0.2
local lookSet: { [Instance]: Vector3? } = setmetatable({} :: any, { __mode = "k" })
local lookClock = 0
local heads: { Vector3 } = {}

local function stepLook(dt: number)
	lookClock += dt
	if lookClock < LOOK_EVERY then
		return
	end
	lookClock = 0
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	table.clear(heads)
	for _, pl in Players:GetPlayers() do
		local head = pl.Character and pl.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			table.insert(heads, head.Position)
		end
	end
	for inst in started do
		if not inst:IsA("Model") or not inst.Parent then
			continue
		end
		local pos = inst:GetPivot().Position
		local want: Vector3? = nil
		if (pos - camPos).Magnitude < SPIN_RANGE and not spinning[inst] then
			local best = LOOK_RANGE * LOOK_RANGE
			for _, h in heads do
				local d = h - pos
				local d2 = d:Dot(d)
				if d2 < best then
					best = d2
					want = h
				end
			end
		end
		local had: Vector3? = lookSet[inst]
		if want ~= had and (want == nil or had == nil or ((want :: Vector3) - (had :: Vector3)).Magnitude > 0.25) then
			lookSet[inst] = want
			inst:SetAttribute("LookAt", want)
		end
	end
end

local running = false
function PetDisplay.start()
	if running then
		return
	end
	running = true
	for _, inst in CollectionService:GetTagged(SPIN_TAG) do
		trySpin(inst)
	end
	CollectionService:GetInstanceAddedSignal(SPIN_TAG):Connect(function(inst)
		task.defer(trySpin, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(SPIN_TAG):Connect(function(inst)
		if inst:IsA("Model") then
			spinning[inst] = nil
		end
	end)
	game:GetService("RunService").Heartbeat:Connect(stepSpin)
	game:GetService("RunService").Heartbeat:Connect(stepLook)
	for _, inst in CollectionService:GetTagged(TAG) do
		try(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
		task.defer(try, inst) -- after the model's parts have streamed in with it
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		started[inst] = nil
	end)
end

return PetDisplay
