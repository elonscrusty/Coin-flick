--!strict
-- The owner's hand-made low-poly world meshes, imported in Studio into ReplicatedStorage.WorldKit_LowPoly
-- (docs/OWNER_STEPS.md "Low-poly world kit"). Shared: the client (pile eggs) and the server (nest tables, hunt pads,
-- LAST WINNERS board) both read it. Without the folder, or without a piece, has() is false and every caller builds
-- its old look (the place file in the repo has none of these, so the fallback is what tests and the preview run).
--
-- Expected pieces (each one MeshPart, or a Model holding one; "Name.001" counts as Name):
--   HuntEgg_Pink, HuntEgg_Blue, HuntEgg_Green, HuntEgg_Yellow   pile eggs (GeodeModel.rockShell)
--   NestTable                                                     the hatch nest table body (StationModels)
--   StonePad                                                      one hunt pad under each nest table (HuntLowPoly)
--   NoticeBoard                                                   the lobby LAST WINNERS board (WinnerBoard)
-- Assumed import (confirmed by Studio): sized in studs, textured (the TextureID is kept), front faces -Z. The pivot
-- may be at the base; this module never relies on it: a MeshPart's CFrame is its bounding-box centre, so callers
-- place pieces with fitBox / onFloor (bottom of the box on the floor).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldKit = {}

WorldKit.Folder = "WorldKit_LowPoly"
WorldKit.Eggs = { "HuntEgg_Pink", "HuntEgg_Blue", "HuntEgg_Green", "HuntEgg_Yellow" }
WorldKit.Names = { "HuntEgg_Pink", "HuntEgg_Blue", "HuntEgg_Green", "HuntEgg_Yellow", "NestTable", "StonePad", "NoticeBoard" }

local cache: { [string]: MeshPart }? = nil
-- an incomplete set is rescanned at most every RESCAN seconds (a pile builds hundreds of eggs in one go)
local RESCAN = 2
local partial: { [string]: MeshPart }? = nil
local partialAt = -math.huge
local function sources(): { [string]: MeshPart }
	if cache then
		return cache
	end
	if partial and os.clock() - partialAt < RESCAN then
		return partial
	end
	local found: { [string]: MeshPart } = {}
	local root = ReplicatedStorage:FindFirstChild(WorldKit.Folder)
	if not root then
		partial, partialAt = found, os.clock()
		return found
	end
	for _, d in root:GetDescendants() do
		if d:IsA("MeshPart") then
			local base = string.gsub(d.Name, "%.%d+$", "")
			-- a piece imported as a Model: the Model carries the name, its MeshPart may not
			local parent = d.Parent
			if not table.find(WorldKit.Names, base) and parent and parent:IsA("Model") then
				base = string.gsub(parent.Name, "%.%d+$", "")
			end
			found[base] = found[base] or d
		end
	end
	-- only cache a complete set (the client may see the folder before every mesh replicated)
	for _, name in WorldKit.Names do
		if not found[name] then
			partial, partialAt = found, os.clock()
			return found
		end
	end
	cache = found
	return found
end

-- True when every named piece is present.
function WorldKit.has(...: string): boolean
	local s = sources()
	for _, n in { ... } do
		if not s[n] then
			return false
		end
	end
	return true
end

-- The piece's natural size in studs (nil when missing).
function WorldKit.size(name: string): Vector3?
	local src = sources()[name]
	return if src then src.Size else nil
end

-- A visual-only copy of `name` (anchored, no collision, no queries, no touch, texture kept), unparented and unplaced.
function WorldKit.clone(name: string, partName: string?): MeshPart?
	local src = sources()[name]
	if not src then
		return nil
	end
	local p = src:Clone()
	for _, ch in p:GetChildren() do
		if not ch:IsA("SurfaceAppearance") then
			ch:Destroy()
		end
	end
	p.Name = partName or name
	p.Transparency = 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.PivotOffset = CFrame.identity
	return p
end

-- Stretches `p` per axis to `size` and centres it on `centre` (a box CFrame: the old part's CFrame and Size).
function WorldKit.fitBox(p: BasePart, centre: CFrame, size: Vector3)
	p.Size = size
	p.CFrame = centre
end

-- Stands `p` on `floor` (a floor-level frame): the bottom of its box on the floor, centred in X and Z.
function WorldKit.onFloor(p: BasePart, floor: CFrame)
	p.CFrame = floor * CFrame.new(0, p.Size.Y / 2, 0)
end

return WorldKit
