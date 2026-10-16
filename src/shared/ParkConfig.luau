--!strict
-- Dino-jungle pet park (the public lobby, owner picks 2026-10-10, latest layout picture): layout numbers and the pure
-- rules around them. The park sits on normal ground in a jungle valley (ground top y = Config.Lodge.FloorY = 0).
-- World frame: a 4 x 4 grid of cells; the middle 2 x 2 is an open grass CLEARING with the four queue nests (2 x 2)
-- and the crowned leaderboard; the 12 outer cells are square fenced PLOTS, stone paths between them. The main stone
-- path runs north-south through the middle: the spawn plaza with the stalls at its south end (+Z), the EGG SHOP hut at
-- its north end (-Z). Used by ParkBuilder (geometry), LobbyBuilder (spawn, zones), GalleryService (who shows where)
-- and the yard spots. Tested offline in tests/test_park.luau.

local ParkConfig = {}

-- Nameplate text (and like-prompt object) on a plot nobody holds right now. Plots are given out on join, so this
-- must not read like something to claim; it says the real rule (audit 2 #3: "FREE PLOT" gave no next step).
ParkConfig.EmptyPlot = "OPEN PLOT\nthe next player to join gets it"
-- Title text a hand-built sign may carry for an empty plot (MapHooks finds and reuses that label).
ParkConfig.SignMatch = { "FREE PLOT", "OPEN PLOT" }
-- Over the local player's own plot, only on their screen (client/YourPlotTag).
ParkConfig.YourPlot = "YOUR PLOT"

-- Walkable park bounds (world studs): the invisible boundary and the lobby camera box (Config.Lodge mirrors these).
ParkConfig.Bounds = { MinX = -100, MaxX = 100, MinZ = -164, MaxZ = 160 } -- Pet Garden yard 200 x 320 (walls x +-91, z -160..142)

-- Grid: cell centres on both axes (studs); the four middle cells form the clearing.
ParkConfig.Grid = { Centres = { -66, -22, 22, 66 }, Pitch = 44 }
ParkConfig.Clearing = { Half = 38 } -- grass square -38..38 (the stone ring path runs around it at 39..49)
ParkConfig.Path = { Width = 10, Ring = 44 } -- ring path centre line |x| / |z| = 44; main path x = 0

-- Spawn plaza (south end of the main path): stalls and two boards around it, the spawn facing the clearing (-Z).
ParkConfig.Plaza = { MinX = -56, MaxX = 56, MinZ = 92, MaxZ = 132 }
ParkConfig.Spawn = { X = 0, Z = 108 }

-- EGG SHOP hut at the north end of the main path, facing the clearing (+Z).
ParkConfig.Shop = { X = 0, Z = -108 }

-- PET TOWER entrance (the tower thread hooks its TowerPortal part) at the west end of the cross path, facing the park.
ParkConfig.Tower = { X = -95, Z = 0 }

-- Plots: 12 squares of Size studs in the outer cells. Plot order = allocation order (south row first: nearest the
-- spawn). Each plot's gate faces the ring path toward the clearing.
ParkConfig.Plot = { Count = 12, Size = 32 }
local CELLS: { { number } } = {
	{ -22, 66 }, { 22, 66 }, { -66, 66 }, { 66, 66 }, -- south row (nearest the spawn)
	{ -66, 22 }, { 66, 22 }, { -66, -22 }, { 66, -22 }, -- west and east columns
	{ -22, -66 }, { 22, -66 }, { -66, -66 }, { 66, -66 }, -- north row
}

-- Showcase layout inside a plot (plot frame: origin = yard centre on the ground, -Z (LookVector) = toward the gate).
-- Owner pick: every plot has exactly 3 glass domes on stone stands at the back, and the player chooses which pets go
-- in them (the display slot chooser, CollectionAction; display slot k = dome k, slot 1 = the big middle dome).
-- Pets placed beyond the 3 domes (a larger display capacity) stand still in the yard between the gate and the domes
-- on fixed spots (yardSpots), kept AvoidR clear of the middle dome. (Speed is unused since roaming was removed.)
ParkConfig.Showcase = {
	Domes = {
		{ X = 0, Z = 8, Height = 1.6, Plinth = 8.4, Dome = 7.4, PetScale = 3.4 },
		{ X = -10, Z = 6, Height = 1.3, Plinth = 6.6, Dome = 5.8, PetScale = 2.7 },
		{ X = 10, Z = 6, Height = 1.3, Plinth = 6.6, Dome = 5.8, PetScale = 2.7 },
	},
	Wander = { MinX = -7.5, MaxX = 7.5, MinZ = -12.5, MaxZ = 1.0, AvoidR = 6, Speed = 2.2, PetScale = 2.2 },
	MaxWander = 17, -- 3 domes + 17 standing in the yard = 20, the largest bought display level (Config.Display); see wanderCap
	FloorMargin = 5, -- hand-built plots: yard pets keep this far inside the pen's Floor edge (fence, posts)
}

-- Queue nests (the hunt pads) in a 2 x 2 in the clearing; each glows its own colour and has a small sign.
ParkConfig.QueuePads = {
	Size = 8, -- glowing disc diameter (the woven rim sits around it)
	Spots = { { -11, -12 }, { 11, -12 }, { -11, 12 }, { 11, 12 } },
	Colours = { "Yellow", "Blue", "Pink", "Green" },
}
-- The two lobby boards (owner: only these two) stand side by side east of the nests, facing them (-X):
-- RAREST PET (crowned) and HIGHEST FLOOR. Players read them from the open grass between the nests and the boards.
ParkConfig.Leaderboard = { X = 30, Z = -8 } -- RAREST PET, the tall crowned board
ParkConfig.TowerBoard = { X = 30, Z = 8 } -- HIGHEST FLOOR
-- WHAT'S NEW board in the plaza (shared/WhatsNew), beside the park arch, facing the spawn (+Z).
ParkConfig.NewsBoard = { X = 22, Z = 97, W = 16, H = 7 }

-- Public HATCH STAND beside the EGG SHOP (hook only: part HatchStand, attribute HatchStand = true, attachment
-- HatchPoint on top; the hatch itself is played there by the shop side).
ParkConfig.HatchStand = { X = 21, Z = -97, D = 11 }

-- Secret egg (hook only: part SecretEgg, attribute SecretEgg, prompt "Take"): far north-east corner of the jungle
-- edge, inside the boundary, tucked behind bushes.
ParkConfig.SecretEgg = { X = 99, Z = -131 }

-- Plot LIKEs (server-checked; GalleryService): one like per visitor per plot owner per server session, never your
-- own plot. The plot with the most likes (at least one) wears the crown; on a tie the current crown stays.
ParkConfig.Likes = { CrownHeight = 20 }

export type LikeState = { Count: { [number]: number }, By: { [number]: { [number]: boolean } } }

function ParkConfig.newLikes(): LikeState
	return { Count = {}, By = {} }
end

-- Records a like from `visitor` for the plot of `owner`; returns (ok, reason).
function ParkConfig.like(s: LikeState, visitor: number, owner: number): (boolean, string)
	if visitor == owner then
		return false, "own"
	end
	local by = s.By[owner]
	if not by then
		by = {}
		s.By[owner] = by
	end
	if by[visitor] then
		return false, "already"
	end
	by[visitor] = true
	s.Count[owner] = (s.Count[owner] or 0) + 1
	return true, "ok"
end

-- The owner whose plot wears the crown among `present` owners (or nil); `current` keeps it on a tie.
function ParkConfig.likeLeader(s: LikeState, present: { number }, current: number?): number?
	local best, bestN = nil, 0
	for _, o in present do
		local n = s.Count[o] or 0
		if n > bestN or (n == bestN and n > 0 and o == current) then
			best, bestN = o, n
		end
	end
	if current and best ~= current and table.find(present, current) and (s.Count[current] or 0) == bestN then
		return current
	end
	return best
end

local RANK: { [string]: number } = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
ParkConfig.Rank = RANK

-- Plot i: cell centre (x, z) and the unit direction (dx, dz) from the plot toward its gate (the ring path).
function ParkConfig.plotCentre(i: number): (number, number, number, number)
	local c = CELLS[i]
	local x, z = c[1], c[2]
	if math.abs(z) == 66 then
		return x, z, 0, -math.sign(z)
	end
	return x, z, -math.sign(x), 0
end

-- World frame of plot i on the ground (y = groundY): origin at the yard centre, LookVector toward the gate.
function ParkConfig.plotFrame(i: number, groundY: number?): CFrame
	local x, z, dx, dz = ParkConfig.plotCentre(i)
	local p = Vector3.new(x, groundY or 0, z)
	return CFrame.new(p) * CFrame.Angles(0, math.atan2(-dx, -dz), 0) -- look (-Z) toward the gate
end

-- Where the displayed pets go. `pets` = the displayed specimens in display order (each { Id, Rarity, Value }).
-- The first 3 go in the domes (slot k = dome k); the rest stand still in the yard (at most maxYard), each on its own
-- spot (yardSpots) doing its idle. Nothing walks around loose (owner, 2026-10-14: no roaming pets). Pure: no instances.
export type PetRef = { Id: string, Rarity: string, Value: number? }

function ParkConfig.arrange(pets: { PetRef }, maxYard: number?): { Domes: { PetRef }, Yard: { PetRef } }
	local nDomes = #ParkConfig.Showcase.Domes
	local nYard = maxYard or ParkConfig.Showcase.MaxWander
	local out = { Domes = {}, Yard = {} }
	for _, p in pets do
		if #out.Domes < nDomes then
			table.insert(out.Domes, p)
		elseif #out.Yard < nYard then
			table.insert(out.Yard, p)
		end
	end
	return out
end

-- Fixed standing spots (plot-local x, z) for `n` yard pets inside `box`, inset from the fence, clear of the big
-- dome (`avoid`, radius `avoidR`). The yard is cut into an even cols x rows table of cells over its WHOLE width and
-- depth (the cols x rows with the widest spacing) and each pet stands in a cell's middle: rows fill from the gate side (-Z, the front)
-- toward the domes, and a part-full last row is spread across the width. When cells would be closer than MIN_GAP
-- studs, a tight grid is reused in turn instead (huge displays on a small yard). Pure.
local MIN_GAP = 2.4
function ParkConfig.yardSpots(box: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }, avoid: Vector2, avoidR: number, n: number): { Vector2 }
	local inset = 1.2
	local x0, x1 = box.MinX + inset, box.MaxX - inset
	local z0, z1 = box.MinZ + inset, box.MaxZ - inset
	if x0 > x1 then
		x0, x1 = (box.MinX + box.MaxX) / 2, (box.MinX + box.MaxX) / 2
	end
	if z0 > z1 then
		z0, z1 = (box.MinZ + box.MaxZ) / 2, (box.MinZ + box.MaxZ) / 2
	end
	local out: { Vector2 } = {}
	if n <= 0 then
		return out
	end
	local w, d = math.max(x1 - x0, 0.01), math.max(z1 - z0, 0.01)
	-- the table whose cells are farthest apart (ties: more columns, so the yard's width is used)
	local function cells(cols: number, rows: number): ({ { Vector2 } }, number)
		local byRow: { { Vector2 } } = {}
		local count = 0
		for r = 1, rows do
			local row = {}
			for c = 1, cols do
				local v = Vector2.new(x0 + (c - 0.5) * w / cols, z0 + (r - 0.5) * d / rows)
				if (v - avoid).Magnitude >= avoidR then
					table.insert(row, v)
				end
			end
			count += #row
			table.insert(byRow, row)
		end
		return byRow, count
	end
	local bestRows: { { Vector2 } }? = nil
	local bestGap = MIN_GAP - 1e-6
	for cols = n, 1, -1 do
		for rows = math.ceil(n / cols), math.ceil(n / cols) + 4 do
			local gap = math.min(w / cols, d / rows)
			if gap <= bestGap then
				break
			end
			local byRow, count = cells(cols, rows)
			if count >= n then
				bestRows, bestGap = byRow, gap
				break
			end
		end
	end
	if bestRows then
		for _, row in bestRows do
			local left = n - #out
			if left <= 0 then
				break
			end
			if left >= #row then
				for _, v in row do
					table.insert(out, v)
				end
			else
				for k = 1, left do
					table.insert(out, row[math.floor((k - 0.5) * #row / left) + 1])
				end
			end
		end
		return out
	end
	-- fallback: a MIN_GAP grid over the yard, reused in turn
	local spots: { Vector2 } = {}
	local nx, nz = math.floor(w / MIN_GAP) + 1, math.floor(d / MIN_GAP) + 1
	local sx, sz = if nx > 1 then w / (nx - 1) else 0, if nz > 1 then d / (nz - 1) else 0
	for r = 0, nz - 1 do
		for c = 0, nx - 1 do
			local v = Vector2.new(x0 + c * sx, z0 + r * sz)
			if (v - avoid).Magnitude >= avoidR then
				table.insert(spots, v)
			end
		end
	end
	for k = 1, n do
		out[k] = if #spots > 0 then spots[(k - 1) % #spots + 1] else Vector2.new((x0 + x1) / 2, (z0 + z1) / 2)
	end
	return out
end

-- The yard box (plot-local) yard pets stand in, from the pen's Floor half sizes seen from the plot frame (`hx` across,
-- `hz` gate to back) less `margin`, pulled in to the inner face of each outer fence run (`fences`: plot-local centre
-- X/Z and half extents TX/TZ of every part named "...Fence...", less `pad`). Only real outer runs count: long and thin
-- (along a side), standing in the outer band of that side (past 70% of the half size), and pulling the side in by at
-- most 40% of the half size. A "fence" inside the pen (a garden-bed fence, a rail by the domes) would otherwise shrink
-- the yard to a strip and line every pet up along one fence (owner report 2026-10-15). Smaller than `fallback` (the
-- code default box) on either axis -> `fallback`. Pure.
export type YardFence = { X: number, Z: number, TX: number, TZ: number }
function ParkConfig.yardBox(hx: number, hz: number, margin: number, fences: { YardFence }, pad: number, fallback: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }): { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
	local ax, az = hx - margin, hz - margin
	if not (ax > fallback.MaxX and az > fallback.MaxZ) then
		return { MinX = fallback.MinX, MaxX = fallback.MaxX, MinZ = fallback.MinZ, MaxZ = fallback.MaxZ }
	end
	local box = { MinX = -ax, MaxX = ax, MinZ = -az, MaxZ = az }
	local maxPullX, maxPullZ = hx * 0.4, hz * 0.4
	for _, f in fences do
		local ox, oz = math.abs(f.X) / math.max(hx, 1), math.abs(f.Z) / math.max(hz, 1)
		if ox >= oz then
			-- an X side: a run along z, thin across x, in the outer band
			if f.TX * 3 <= f.TZ and ox >= 0.7 then
				local inner = math.abs(f.X) - f.TX - pad
				if inner >= hx - maxPullX then
					if f.X > 0 then
						box.MaxX = math.min(box.MaxX, inner)
					else
						box.MinX = math.max(box.MinX, -inner)
					end
				end
			end
		elseif f.TZ * 3 <= f.TX and oz >= 0.7 then
			local inner = math.abs(f.Z) - f.TZ - pad
			if inner >= hz - maxPullZ then
				if f.Z > 0 then
					box.MaxZ = math.min(box.MaxZ, inner)
				else
					box.MinZ = math.max(box.MinZ, -inner)
				end
			end
		end
	end
	if box.MinX > box.MaxX then
		local c = (box.MinX + box.MaxX) / 2
		box.MinX, box.MaxX = c, c
	end
	if box.MinZ > box.MaxZ then
		local c = (box.MinZ + box.MaxZ) / 2
		box.MinZ, box.MaxZ = c, c
	end
	return box
end

-- How far above the plot floor a yard pet stands so it is on the ground players actually see (Studio 2026-10-15: a
-- moved hand-built plot kept its old Floor height while the new lawn there is higher, so pets placed on the Floor
-- were buried). `hitY` = the first surface a ray straight down at the spot meets (nil = none); surfaces below the
-- floor, or more than YardMaxLift above it (a roof, a tree, a sign), are ignored. Pure.
ParkConfig.YardMaxLift = 14
function ParkConfig.yardLift(hitY: number?, floorTop: number): number
	if hitY == nil or hitY ~= hitY then
		return 0
	end
	local lift = hitY - floorTop
	if lift <= 0 or lift > ParkConfig.YardMaxLift then
		return 0
	end
	return lift
end

-- How many pets may stand in the yard on a plot with `slots` display slots: at least Showcase.MaxWander, and enough for every
-- slot past the domes (the ExtraPlots pass adds RobuxConfig.ExtraDisplaySlots on top of the biggest bought level).
function ParkConfig.wanderCap(slots: number): number
	return math.max(ParkConfig.Showcase.MaxWander, slots - #ParkConfig.Showcase.Domes)
end

-- Inside the walkable park (world x / z)?
function ParkConfig.inside(x: number, z: number): boolean
	local B = ParkConfig.Bounds
	return x > B.MinX and x < B.MaxX and z > B.MinZ and z < B.MaxZ
end

return ParkConfig
