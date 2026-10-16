--!strict
-- Picks which sound file to load: carter's uploaded id, or the built-in
-- fallback when there is no id or the id failed to load.

local Config = require(script.Parent.Parent.Config)

local SoundPick = {}

function SoundPick.source(def: Config.SoundDef, failed: boolean): string
	if failed or def.id <= 0 then
		return def.fallback
	end
	return "rbxassetid://" .. tostring(def.id)
end

return SoundPick
