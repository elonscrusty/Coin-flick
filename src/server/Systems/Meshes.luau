--!strict
-- Loads the Blender models (docs/MODELING.md) once at boot and hands out painted copies.
-- A model with id 0 (not uploaded yet) or one that fails to load gives nil: every caller keeps its Part stand-in.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)
local MeshIds = require(ReplicatedStorage.Shared.MeshIds) :: { [string]: number }
local MeshPaint = require(ReplicatedStorage.Shared.Util.MeshPaint)

local LOAD_TIMEOUT = 15

local Meshes = {}

local templates: { [string]: Model } = {}

local function load(name: string, id: number)
	local ok, container = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok or typeof(container) ~= "Instance" then
		warn(`CoinFlick: model {name} ({id}) did not load, using the Part stand-in`)
		return
	end
	local parts = 0
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	if parts == 0 then
		warn(`CoinFlick: model {name} has no parts, using the Part stand-in`)
		container:Destroy()
		return
	end
	local model = Instance.new("Model")
	model.Name = name
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then
			d.Parent = model
		end
	end
	container:Destroy()
	templates[name] = model
end

function Meshes.init()
	local pending = 0
	for name, id in MeshIds do
		if id > 0 and MeshCatalog[name] then
			pending += 1
			task.spawn(function()
				load(name, id)
				pending -= 1
			end)
		end
	end
	local waited = 0
	while pending > 0 and waited < LOAD_TIMEOUT do
		waited += task.wait(0.1)
	end
end

function Meshes.has(name: string): boolean
	return templates[name] and true or false
end

-- A painted copy placed at `cf` (the pivot: floor centre, or the middle for coins), or nil while the model is
-- not available. `lift` raises the pivot above the floor (helpers hop around their body centre).
-- `anchored` keeps it fixed in the world (table, helpers); otherwise weld it to something (coins, hats).
function Meshes.clone(name: string, cf: CFrame, tints: MeshPaint.Tints?, lift: number?, anchored: boolean?): Model?
	local template = templates[name]
	if not template then
		return nil
	end
	local model = template:Clone()
	local box, size = model:GetBoundingBox()
	local pivot = box
	if not MeshPaint.isCentered(name) then
		pivot = box * CFrame.new(0, -size.Y / 2 + (lift or 0), 0)
	end
	model.WorldPivot = pivot
	local primary: BasePart? = nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true -- welded below, then freed
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			primary = primary or part
		end
	end
	if not primary then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = primary
	MeshPaint.paint(model, name, tints)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model:PivotTo(cf)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored == true
		end
	end
	return model
end

-- Weld a model to a part so it travels with it (parts moved by CFrame, like the coins).
function Meshes.attach(model: Model, to: BasePart)
	local primary = model.PrimaryPart
	if primary then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = to
		weld.Part1 = primary
		weld.Parent = primary
	end
	model.Parent = to
end

return Meshes
