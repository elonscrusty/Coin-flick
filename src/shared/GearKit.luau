--!strict
-- Pure decisions for the owner's pet gear models (ReplicatedStorage.Assets.Kit.Gear_<Id>).
-- Pet gear is passive: nothing is ever held in the hand, so `heldToolName` is always nil.
local GearKit = {}

GearKit.Ids = { "Hammer", "SteelHammer", "Jackhammer", "AutoCracker", "HydraulicPress", "IndustrialCrusher" }

local LEGACY: { [string]: { string } } = {
	Hammer = { "Tool_Hammer", "Hammer" },
	SteelHammer = { "Tool_SteelHammer", "SteelHammer" },
	Jackhammer = { "Tool_Jackhammer", "Jackhammer" },
	AutoCracker = { "Machine_AutoCracker", "AutoCracker" },
	HydraulicPress = { "Machine_HydraulicPress", "HydraulicPress" },
	IndustrialCrusher = { "Machine_IndustrialCrusher", "IndustrialCrusher" },
}

-- Kit lookup order for a gear id: the new Gear_<Id> model first, the older names as fallbacks.
function GearKit.kitNames(id: string): { string }
	local out = { "Gear_" .. id }
	local legacy: { string } = LEGACY[id] or { id }
	for _, n in legacy do
		table.insert(out, n)
	end
	return out
end

-- Which build a machine uses: "Gear" when the Gear_<Id> model exists and is Ready, else the "Parts" build.
function GearKit.source(exists: boolean, ready: boolean): string
	if exists and ready then
		return "Gear"
	end
	return "Parts"
end

-- Which parts of the Parts build hide once the Gear_<Id> model stands over it: every body part, including the
-- StateLight bulb and the Beacon (they floated as grey dots beside the mesh); only the Base keeps its look.
function GearKit.hideUnderGear(name: string, _role: any): boolean
	return name ~= "Base"
end

-- Scale factor for the hip accessory: its longest side about 1.8 studs on a normal (~5 stud) avatar, in proportion on
-- bigger or smaller ones (0.7 studs was too small to see on R15).
GearKit.AccessoryLongest = 1.8
function GearKit.accessoryScale(longest: number, avatarHeight: number): number
	local want = GearKit.AccessoryLongest * math.clamp(avatarHeight / 5, 1, 2)
	return math.clamp(want / math.max(longest, 0.05), 0.05, 40)
end

-- Uniform scale that fits a model of size `gear` inside the footprint `box` (width/depth, and height when box.Y > 0).
function GearKit.fitScale(gear: Vector3, box: Vector3): number
	local s = math.min(box.X / math.max(gear.X, 1e-3), box.Z / math.max(gear.Z, 1e-3))
	if box.Y > 0 then
		s = math.min(s, box.Y / math.max(gear.Y, 1e-3))
	end
	return s
end

-- The held Tool name for a gear id: none (passive gear never sits in the hand).
function GearKit.heldToolName(_id: string): string?
	return nil
end

-- The kit model that may show as a small hip accessory (hand-tier gear only), else nil.
function GearKit.accessoryModel(id: string): string?
	if id == "Hammer" or id == "SteelHammer" or id == "Jackhammer" then
		return "Gear_" .. id
	end
	return nil
end

return GearKit
