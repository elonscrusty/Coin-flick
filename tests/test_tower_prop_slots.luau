-- Tower theme props (shared/TowerPropSlots, used by server/TowerBuilder): the slot at +-TILE/2 along each side wall
-- stays clear of the side doors (at 0 and +-TILE, about 6.2 studs half-wide), and widths are capped.
return function(t)
	local test, shared = t.test, t.shared
	local S = shared("TowerPropSlots")

	test("tower prop slots: width caps (7 studs, trees 14) hold for any mesh shape", function()
		for _, tree in { false, true } do
			local cap = if tree then S.TreeWidth else S.MaxWidth
			for _, m in { { 20, 5, 3 }, { 3, 9, 20 }, { 2, 4, 2 }, { 40, 40, 40 } } do
				local k = S.scale(m[1], m[2], m[3], 6, tree)
				assert(math.max(m[1], m[3]) * k <= cap + 1e-9, "cap " .. cap)
				assert(m[2] * k <= 6 + 1e-9, "never taller than asked")
			end
		end
		assert(math.abs(S.scale(2, 4, 2, 6, false) - 1.5) < 1e-9, "a small mesh scales up to its height")
	end)

	test("tower prop slots: every slot clears both neighbouring side doors, props stay inside the wall", function()
		for _, tree in { false, true } do
			local widest = if tree then S.TreeWidth else S.MaxWidth
			local half = widest / 2 -- axis-aligned footprint of the widest allowed prop
			for _, along in S.Alongs do
				local gap = S.doorGap(along, half)
				assert(gap > 0, string.format("tree=%s slot %.1f gap %.2f", tostring(tree), along, gap))
				for _, sx in { -1, 1 } do
					local x, z = S.position(sx, along, half)
					assert(math.abs(x) + half <= S.Room - 2 + 1e-9, "inside the wall")
					assert(z == along * S.Tile)
				end
			end
		end
		-- a non-tree prop stays clear of the doors even turned any way (diagonal of its square footprint)
		assert(S.doorGap(0.5, S.MaxWidth / 2 * math.sqrt(2)) > 0)
	end)
end
