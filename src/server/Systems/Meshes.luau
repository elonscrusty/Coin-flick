--!strict
-- Loads the uploaded Blender models (shared/MeshIds, ids made by tools/upload_meshes.py) and hands out clones.
-- A model whose id is 0, or that fails to load (Studio without asset access), is simply absent: every caller
-- keeps its Part stand-in, so the game always works. The FBX files carry no colours, so each MeshPart is
-- painted here from shared/MeshCatalog, matched by its slot name (the piece name is `<Model>_<slot>`).

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)
local MeshIds = require(ReplicatedStorage.Shared.MeshIds) :: { [string]: number }

local Meshes = {}

local RETRIES = 3
local BOOT_WAIT = 25 -- seconds the server waits for models before building the world

local templates: { [string]: Model } = {}
local pending = 0

-- The slot of a MeshPart: its name is `<Model>_<slot>` (the importer may add a suffix such as `.001`).
local function slotOf(modelName: string, partName: string): string?
	return string.match(partName, "^" .. modelName .. "_(%w+)")
end

local function paint(name: string, model: Model)
	local pieces = MeshCatalog[name]
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			local slot = slotOf(name, part.Name)
			local look = if slot then pieces[slot] else nil
			if look then
				part.Color = look.color
				part.Material = (Enum.Material :: any)[look.material]
			end
		end
	end
end

local function load(name: string, id: number)
	pending += 1
	task.spawn(function()
		for attempt = 1, RETRIES do
			local ok, result = pcall(InsertService.LoadAsset, InsertService, id)
			if ok and result then
				local model = result:FindFirstChildWhichIsA("Model") or result
				if model:IsA("Model") then
					model.Name = name
					paint(name, model)
					templates[name] = model
				end
				break
			end
			task.wait(attempt)
		end
		pending -= 1
	end)
end

function Meshes.has(name: string): boolean
	return (templates :: { [string]: Model? })[name] ~= nil
end

-- A painted copy placed at `cf`. `tints` recolours pieces by slot (e.g. { Top = tableColor }).
function Meshes.clone(name: string, cf: CFrame, tints: { [string]: Color3 }?): Model?
	local template = templates[name]
	if not template then
		return nil
	end
	local copy = template:Clone()
	if tints then
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") then
				local slot = slotOf(name, part.Name)
				local tint = if slot then tints[slot] else nil
				if tint then
					part.Color = tint
				end
			end
		end
	end
	copy:PivotTo(cf)
	return copy
end

function Meshes.init()
	for name, id in MeshIds do
		if id > 0 and MeshCatalog[name] then
			load(name, id)
		end
	end
	local deadline = os.clock() + BOOT_WAIT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return Meshes
