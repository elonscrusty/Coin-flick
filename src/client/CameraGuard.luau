--!strict
-- Camera guard (Master Prompt 4, sections 28 and 51): keeps the player's camera out of opaque world geometry.
--
-- Cause of the "wood-filled screen" in the workshop: Roblox's own camera script (Poppercam) only pulls the
-- camera in for parts that are CanCollide = true. The Blender kit models are placed as anchored,
-- NON-colliding MeshParts (KitModels.clone: "Parts stay anchored and non-colliding"), and the Kit.deco
-- parts are non-colliding and non-queryable, so the default camera happily flew through roofs, beams and
-- shelves. Making all of that collidable would trap avatars, so the camera is handled separately here
-- and no collision is changed.
--
-- Active whenever the view is third person: the whole lobby (owner decision 2026-10-10: the lobby is third person,
-- hunts are first person) and hunts when Config.Camera.FirstPerson = false. In first person (Player.CameraMode =
-- LockFirstPerson, set only by CameraMode) this guard does nothing. Zoom limits belong to CameraMode
-- (Config.Camera.Lobby).
--
-- The lobby is the outdoor pet park: its edge is an invisible boundary (CanQuery = false) in front of the jungle
-- wall and the cliffs, so no ray can see it. While the head is inside the park box (Config.Lodge: the boundary and a
-- sky ceiling well above the longest lobby zoom) the distance to the box face behind the camera counts as one more
-- hit (CameraSolve.boxExit), so the camera never swings out through the jungle wall. Outdoors there is no roof: the
-- ceiling never shortens a normal zoom. Hunt arenas are far outside the box (boxExit gives nothing there).
--
-- Every frame, after the default camera has run, five thin rays go from the head to the camera position the
-- default script chose. The nearest real occluder pulls the camera in (at once, never inside it) and it eases
-- back out at 9 studs per second (CameraSolve). Not occluders:
--   * the avatars, small parts (largest side under 3 studs: props, grit, foliage bits), see-through parts
--     (Transparency >= 0.5) and the client's own pile / guide folders
--   * anything marked for the camera: attribute `CameraIgnore = true` on the part or on ANY ancestor
--     (Model / Folder), or the CollectionService tag "CameraIgnore". Builders set this on decorative-only
--     trim, canopy fringe, hanging signs and foliage that should never push the camera.
-- Parts with CanQuery = false are never hit by rays, which is how Kit.deco parts are skipped already.
-- Floors, walls and boundaries stay occluders (they are big, opaque and queryable). Also sets sensible
-- zoom limits so the camera cannot sit inside the avatar or drift across the map.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CameraSolve = require(Shared.CameraSolve)
local Config = require(Shared.Config)

local CameraGuard = {}

local player = Players.LocalPlayer

CameraGuard.IgnoreAttribute = "CameraIgnore"
CameraGuard.IgnoreTag = "CameraIgnore"

local SMALL = 3 -- studs: parts smaller than this on every side never block the camera
local PROBE = 0.45 -- studs: offset of the four side rays from the centre ray
local MAX_STEPS = 6 -- ignorable parts skipped per ray
local GROUND_CLEAR = 1.2 -- studs: lowest the camera may sit above the avatar's feet while standing on something

local ignoreCache: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local cap: number? = nil
local started = false
local lastCharacter: Model? = nil

local function marked(inst: Instance): boolean
	local c = ignoreCache[inst]
	if c ~= nil then
		return c
	end
	local value = false
	local cur: Instance? = inst
	while cur and cur ~= Workspace do
		if cur:GetAttribute(CameraGuard.IgnoreAttribute) == true or CollectionService:HasTag(cur, CameraGuard.IgnoreTag) then
			value = true
			break
		end
		cur = cur.Parent
	end
	ignoreCache[inst] = value
	return value
end

-- True when a hit part should not push the camera.
function CameraGuard.ignorable(part: BasePart): boolean
	if part.Transparency >= 0.5 then
		return true
	end
	local s = part.Size
	if part.ClassName ~= "Terrain" and math.max(s.X, s.Y, s.Z) < SMALL then
		return true
	end
	return marked(part)
end

-- Reused every frame (no per-frame tables or RaycastParams).
local EXCLUDE_FOLDERS = { "CT_Rocks_LocalPile", "CT_Rocks_Grit", "CT_Rocks_Guide", "CT_Rocks_Selection" }
local excludeBuf: { Instance } = {}
local skipBuf: { Instance } = {}
local hitsBuf: { number? } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function baseExclude(): { Instance }
	local list = excludeBuf
	table.clear(list)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in EXCLUDE_FOLDERS do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	local cam = Workspace.CurrentCamera
	if cam then
		table.insert(list, cam)
	end
	return list
end

-- Distance from `origin` along `dir` to the first real occluder within `maxDist`, or nil.
local function firstHit(origin: Vector3, dir: Vector3, maxDist: number, exclude: { Instance }): number?
	local params = rayParams
	local skip = skipBuf
	table.clear(skip)
	table.move(exclude, 1, #exclude, 1, skip)
	for _ = 1, MAX_STEPS do
		params.FilterDescendantsInstances = skip
		local hit = Workspace:Raycast(origin, dir * maxDist, params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		if not CameraGuard.ignorable(inst) then
			return (hit.Position - origin).Magnitude
		end
		table.insert(skip, inst)
	end
	return nil
end

local function step(dt: number)
	local cam = Workspace.CurrentCamera
	local char = player.Character
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		cap = nil -- first person: the camera is in the head, CameraMode owns it
		return
	end
	if not cam or not char or cam.CameraType == Enum.CameraType.Scriptable then
		cap = nil
		return
	end
	if char ~= lastCharacter then
		lastCharacter = char
		cap = nil
	end
	local head = (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not head then
		return
	end
	local origin = head.Position + Vector3.new(0, 0.4, 0)
	local camCf = cam.CFrame
	local vec = camCf.Position - origin
	local wanted = vec.Magnitude
	if wanted < CameraSolve.MinDistance then
		cap = nil
		return
	end
	local dir = vec / wanted
	local right = dir:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(dir).Unit
	local exclude = baseExclude()
	local hits = hitsBuf
	table.clear(hits)
	local r, u = right * PROBE, up * PROBE
	table.insert(hits, firstHit(origin, dir, wanted, exclude))
	table.insert(hits, firstHit(origin + r, dir, wanted, exclude))
	table.insert(hits, firstHit(origin - r, dir, wanted, exclude))
	table.insert(hits, firstHit(origin + u, dir, wanted, exclude))
	table.insert(hits, firstHit(origin - u, dir, wanted, exclude))
	local L = Config.Lodge
	if Workspace:FindFirstChild("CT_Rocks_Lobby") then
		table.insert(hits, CameraSolve.boxExit(origin, dir, Vector3.new(L.MinX, L.FloorY, L.MinZ), Vector3.new(L.MaxX, L.CeilingY, L.MaxZ)))
	end
	local allowed = CameraSolve.allowed(wanted, hits)
	local nextCap = CameraSolve.smooth(cap, allowed, dt)
	cap = nextCap
	local final = math.min(wanted, nextCap)
	local pos = if wanted - final > 0.01 then origin + dir * final else camCf.Position
	-- ground floor: looking up from a low angle, the camera could dip under the ground (the view filled with
	-- grass). Keep it a little above the avatar's feet; it still looks up, just from above the ground.
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.FloorMaterial ~= Enum.Material.Air then
		local floorY = root.Position.Y - root.Size.Y * 0.5 - hum.HipHeight + GROUND_CLEAR
		if pos.Y < floorY then
			pos = Vector3.new(pos.X, floorY, pos.Z)
		end
	end
	if pos ~= camCf.Position then
		cam.CFrame = CFrame.new(pos) * camCf.Rotation
	end
end

function CameraGuard.start()
	if started then
		return
	end
	started = true
	-- runs every frame but steps aside in first person (see step); CameraMode sets the zoom limits
	RunService:BindToRenderStep("CTR_CameraGuard", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraGuard
