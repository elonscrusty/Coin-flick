--!strict
-- Lobby light fill. The old Prospector Lodge needed an interior fill (its roof shaded the hall); the lobby is now the
-- outdoor dino-jungle pet park, lit by the project Lighting like the hunts, so there is nothing to blend: the module
-- keeps its API (start, inside, blend) for Main.client and the preview scenes and never touches Lighting.

local LodgeLight = {}

-- No roofed interior in the park.
function LodgeLight.inside(_p: Vector3): boolean
	return false
end

function LodgeLight.start() end

-- Test / preview hook: current blend 0..1 (always 0 outdoors).
function LodgeLight.blend(): number
	return 0
end

return LodgeLight
