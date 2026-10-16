--!strict
-- What a coin pet looks like in the world, as plain data: which Blender model it uses (docs/MODELING.md),
-- how it is tinted and how big it is. Pure, so tests/specs/PetLook.spec.luau can check it offline.
-- A pet whose model is not uploaded yet (id 0) gets the Part stand-in from Builders/PetBuilder.

local PetConfig = require(script.Parent.Parent.PetConfig)
local MeshPaint = require(script.Parent.MeshPaint)

local PetLook = {}

-- Pet id -> Blender model name (blender/models_pets.py).
PetLook.MODELS = table.freeze({
	puppy = "CF_PetPuppy",
	pig = "CF_PetPiggy",
	bunny = "CF_PetBunny",
	dragon = "CF_PetDragon",
	cat = "CF_PetSpaceCat",
})

PetLook.BASE_SCALE = 0.9 -- the models are about 2.5 studs tall before scaling
PetLook.SCALE_PER_LEVEL = 0.04 -- a levelled-up pet grows a little (level 10 = +36%)

function PetLook.modelName(id: unknown): string?
	return if typeof(id) == "string" then PetLook.MODELS[id] else nil
end

-- Paint a pet's body in its own colour; every other piece keeps the model's catalog colour.
function PetLook.tints(def: PetConfig.PetDef): MeshPaint.Tints
	return { Body = def.body }
end

function PetLook.scale(level: number): number
	local lv = math.clamp(math.floor(level), 1, PetConfig.MAX_LEVEL)
	return PetLook.BASE_SCALE + PetLook.SCALE_PER_LEVEL * (lv - 1)
end

return PetLook
