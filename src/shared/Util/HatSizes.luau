--!strict
-- How wide each hat is (its widest part, in hat units where a head is ~1.2),
-- and how much to shrink the wide ones so no hat swallows your avatar.
-- Keep WIDTH in step with the brims in HatBuilder; Hats scales each hat by `fit`.

local HatSizes = {}

HatSizes.WIDTH = table.freeze({
	party = 1.0,
	cone = 1.3,
	cowboy = 2.1,
	chef = 1.4,
	propeller = 1.6,
	duck = 1.1,
	tophat = 1.6,
	crown = 1.2,
} :: { [string]: number })

-- Widest a hat may be on the head, in hat units (before the shared 1.6x chunky scale).
HatSizes.MAX_WIDTH = 1.45

-- Shrink factor for one hat (1 = normal size).
function HatSizes.fit(id: string): number
	local width = HatSizes.WIDTH[id]
	if not width or width <= HatSizes.MAX_WIDTH then
		return 1
	end
	return HatSizes.MAX_WIDTH / width
end

return HatSizes
