--!strict
-- Pure rules for the Blender models (see docs/MODELING.md): which model a game thing uses, how a part's
-- name maps to a colour slot, and how tints win over catalog colours. Works on the server and the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshCatalog = require(ReplicatedStorage.Shared.MeshCatalog)

export type Tints = { [string]: Color3 }

local MeshPaint = {}

-- Game id -> model name.
MeshPaint.HELPERS = table.freeze({
	buddy = "CF_Buddy",
	zippy = "CF_Zippy",
	chompy = "CF_Chompy",
	twinkle = "CF_Twinkle",
	king = "CF_King",
})

MeshPaint.HATS = table.freeze({
	party = "CF_HatParty",
	cone = "CF_HatCone",
	cowboy = "CF_HatCowboy",
	chef = "CF_HatChef",
	propeller = "CF_HatPropeller",
	duck = "CF_HatDuck",
	tophat = "CF_HatTop",
	crown = "CF_HatCrown",
})

MeshPaint.COIN = "CF_Coin"
MeshPaint.TABLE = "CF_Table"
-- The coin model is 3 studs across before scaling (the game's base coin diameter).
MeshPaint.COIN_DIAMETER = 3

-- Models whose origin is their centre (coins, gifts). Everything else has its origin at the floor centre.
local CENTERED: { [string]: boolean } = { CF_Coin = true, CF_MegaCoin = true }

function MeshPaint.isCentered(name: string): boolean
	return CENTERED[name] == true
end

-- The colour slot of an imported part: FBX parts are named "<Model>_<Slot>" (letters and digits only).
function MeshPaint.slotOf(partName: string): string?
	return string.match(partName, "(%w+)$")
end

-- Colour and material for a slot: a tint wins over the catalog colour. nil = this model has no such slot.
function MeshPaint.look(name: string, slot: string, tints: Tints?): (Color3?, string?)
	local model = MeshCatalog[name]
	local piece = model and model[slot]
	if not piece then
		return nil, nil
	end
	return (tints and tints[slot]) or piece.color, piece.material
end

-- Uniform scale that makes the model's coin as wide as `diameter` studs.
function MeshPaint.coinScale(diameter: number): number
	return diameter / MeshPaint.COIN_DIAMETER
end

-- Paint every part of an imported model (also used to recolour rare coins in the air).
function MeshPaint.paint(model: Instance, name: string, tints: Tints?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local slot = MeshPaint.slotOf(part.Name)
			local color, material = nil, nil
			if slot then
				color, material = MeshPaint.look(name, slot, tints)
			end
			if color then
				part.Color = color
				part.Material = Enum.Material:FromName(material :: string) or Enum.Material.SmoothPlastic
			end
		end
	end
end

return MeshPaint
