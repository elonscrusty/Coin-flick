--!strict
-- Real 3D models made in Blender (art/meshes, ids in MeshIds, colours in MeshCatalog).
-- Meshes.clone(name, cframe, tints) gives a ready Model, or nil while a model has no id (0) or failed to load:
-- every caller keeps its old Part code as the fallback, so nothing breaks before the owner uploads the models.
-- Each imported MeshPart is repainted from the catalog by its slot (the last word of its name); `tints`
-- overrides single slots, e.g. { Leaf = theme.foliage }. `scale` resizes the whole model about its origin.
-- Assumes the imported model's pivot is the Blender origin (floor centre). UNVERIFIED until a Studio check.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)
local MeshIds = require(ReplicatedStorage.Shared.MeshIds) :: { [string]: number }

local Meshes = {}

local LOAD_WAIT = 12 -- seconds the world waits for all models at boot

local templates: { [string]: Model } = {}

local function slotOf(name: string): string
	return string.match(name, "(%w+)$") or name
end

local function load(name: string, id: number)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or not result then
		warn(`Meshes: could not load {name} ({id})`)
		return
	end
	local model = Instance.new("Model")
	model.Name = name
	for _, part in result:GetDescendants() do
		if part:IsA("MeshPart") then
			local copy = part:Clone()
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.Parent = model
		end
	end
	result:Destroy()
	if #model:GetChildren() == 0 then
		warn(`Meshes: {name} has no mesh parts`)
		model:Destroy()
		return
	end
	templates[name] = model
end

function Meshes.init()
	local pending = 0
	for name, id in MeshIds do
		if id ~= 0 and MeshCatalog[name] then
			pending += 1
			task.spawn(function()
				load(name, id)
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < LOAD_WAIT do
		task.wait(0.1)
	end
end

function Meshes.has(name: string): boolean
	local template: Model? = templates[name]
	return template ~= nil
end

function Meshes.clone(name: string, cf: CFrame, tints: { [string]: Color3 }?, scale: number?): Model?
	local template = templates[name]
	local catalog = MeshCatalog[name]
	if not template or not catalog then
		return nil
	end
	local model = template:Clone()
	for _, part in model:GetChildren() do
		if part:IsA("MeshPart") then
			local slot = slotOf(part.Name)
			local look = catalog[slot]
			if look then
				part.Color = (tints and tints[slot]) or look.color
				local material = (Enum.Material :: any)[look.material]
				if material then
					part.Material = material
				end
			end
		end
	end
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(cf)
	return model
end

return Meshes
