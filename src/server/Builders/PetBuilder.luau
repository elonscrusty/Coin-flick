--!strict
-- A coin pet standing in the world. The real thing is the Blender model (Meshes.clone, docs/MODELING.md);
-- until that model is uploaded (id 0) a chunky Part pet with the same colours stands in for it.
-- The pet is only placed here: every client walks it around locally (Controllers/PetFollow).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.PetConfig)
local PetLook = require(ReplicatedStorage.Shared.Util.PetLook)
local Meshes = require(script.Parent.Parent.Systems.Meshes)

local PetBuilder = {}

PetBuilder.TAG = "CoinPet"

local function part(model: Model, name: string, shape: Enum.PartType, size: Vector3, offset: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

-- Part stand-in, about 2.5 studs tall, faces -Z (the model's look direction), pivot = floor centre.
local function standIn(def: PetConfig.PetDef, at: CFrame): Model
	local model = Instance.new("Model")
	local ball = Enum.PartType.Ball
	local dark = Color3.fromRGB(42, 26, 26)
	part(model, "Body", ball, Vector3.new(1.8, 1.7, 1.7), Vector3.new(0, 0.86, 0.05), def.body)
	part(model, "Head", ball, Vector3.new(1.7, 1.55, 1.55), Vector3.new(0, 1.8, -0.1), def.body)
	for _, side in { -1, 1 } do
		part(model, "Eye", ball, Vector3.new(0.34, 0.42, 0.3), Vector3.new(side * 0.34, 1.9, -0.82), dark)
		part(model, "Ear", ball, Vector3.new(0.4, 0.9, 0.6), Vector3.new(side * 0.62, 2.5, 0), def.accent)
	end
	part(model, "Nose", ball, Vector3.new(0.26, 0.2, 0.22), Vector3.new(0, 1.66, -0.9), dark)
	model.PrimaryPart = model:FindFirstChild("Body") :: BasePart
	model:PivotTo(at)
	return model
end

-- A pet of `def` at `level`, placed at `at` (a floor-level CFrame). Always returns a Model.
function PetBuilder.make(def: PetConfig.PetDef, level: number, ownerUserId: number, at: CFrame): Model
	local name = PetLook.modelName(def.id)
	local model = name and Meshes.clone(name, at, PetLook.tints(def), nil, true, PetLook.scale(level))
	local usingMesh = model ~= nil
	if not model then
		model = standIn(def, at)
		model:ScaleTo(PetLook.scale(level))
	end
	local pet = model :: Model
	pet.Name = `Pet_{ownerUserId}`
	pet:SetAttribute("OwnerUserId", ownerUserId)
	pet:SetAttribute("PetId", def.id)
	pet:SetAttribute("Level", level)
	pet:SetAttribute("Mesh", usingMesh)
	CollectionService:AddTag(pet, PetBuilder.TAG)
	return pet
end

return PetBuilder
