--!strict
-- Deterministic rock pile. Server and clients build the same layout from (rock count, rock
-- size, radius, seed), then apply the same removals, so only rock ids travel over the network.
-- The server picks a fresh seed every round (MatchService), so the mound turns, its peak shifts and the
-- ids land in different slots each round; the seed is public, the target id never is.
--
-- The mound is a set of columns on a hex grid. Each column is a stack of rocks (bottom first).
-- A rock is exposed when it is the top of its column, or when a neighbouring column is lower
-- than it (its side is open). Removing a rock lets the rocks above it settle down one slot.
-- Edge columns are open on the outside, so every rock is eventually reachable; nothing sits
-- under the floor.

local Pile = {}
Pile.__index = Pile

export type Rock = {
	Id: number,
	Column: number,
	Jitter: Vector3, -- small xz offset
	Rot: Vector3, -- euler degrees for the shell
	Scale: number, -- 0.85..1.15
	Shape: number, -- 1..4 shell variant
}

export type Column = {
	Pos: Vector2, -- xz relative to pile centre
	Neighbors: { number },
	OpenEdge: boolean,
	Stack: { number }, -- remaining rock ids, bottom first
}

export type Pile = typeof(setmetatable(
	{} :: {
		RockSize: number,
		Layer: number,
		Rocks: { Rock },
		Columns: { Column },
		Removed: { [number]: boolean },
		Remaining: number,
		Total: number,
	},
	Pile
))

local SQRT3 = math.sqrt(3)

function Pile.new(count: number, rockSize: number, radius: number, seed: number): Pile
	local rng = Random.new(seed)
	local s = rockSize
	-- Per-round variety (all from `seed`, so server and clients agree): the whole grid turns by a random
	-- angle, the dome's peak sits off centre, and egg ids are dealt to slots in a shuffled order.
	local turn = rng:NextNumber(0, math.pi * 2)
	local cosT, sinT = math.cos(turn), math.sin(turn)
	-- Shrink the footprint for small piles so short columns stay together.
	local wanted = math.max(1, math.ceil(count / 2.2))
	local rEff = math.min(radius, s * math.sqrt(wanted / 3.4) + s * 0.5)

	-- Hex grid points inside the circle.
	local cols: { Column } = {}
	local index: { [string]: number } = {}
	local n = math.ceil(rEff / s) + 1
	for q = -n * 2, n * 2 do
		for r = -n * 2, n * 2 do
			local x = s * (q + r / 2)
			local z = s * (SQRT3 / 2) * r
			if x * x + z * z <= rEff * rEff then
				local pos = Vector2.new(x * cosT - z * sinT, x * sinT + z * cosT)
				table.insert(cols, { Pos = pos, Neighbors = {}, OpenEdge = false, Stack = {} })
				index[q .. ":" .. r] = #cols
			end
		end
	end
	if #cols == 0 then
		table.insert(cols, { Pos = Vector2.zero, Neighbors = {}, OpenEdge = true, Stack = {} })
		index["0:0"] = 1
	end
	-- Neighbours (6 hex directions); a missing neighbour means the side faces open ground.
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, -1 }, { -1, 1 } }
	for key, ci in index do
		local q, r = string.match(key, "^(-?%d+):(-?%d+)$")
		local qi, ri = tonumber(q) :: number, tonumber(r) :: number
		local col = cols[ci]
		for _, d in dirs do
			local nb = index[(qi + d[1]) .. ":" .. (ri + d[2])]
			if nb then
				table.insert(col.Neighbors, nb)
			else
				col.OpenEdge = true
			end
		end
		table.sort(col.Neighbors)
	end

	-- Dome heights: weight by distance from centre, then hand out exactly `count` rocks.
	local peakAngle = rng:NextNumber(0, math.pi * 2)
	local peakDist = rng:NextNumber(0, 0.25) * rEff
	local peak = Vector2.new(math.cos(peakAngle), math.sin(peakAngle)) * peakDist
	local weights = {}
	local sum = 0
	for i, c in cols do
		local d = (c.Pos - peak).Magnitude / math.max(rEff, 1)
		local w = 0.1 + math.max(0, 1 - d * d) ^ 1.4 -- wide base, tapered peak
		weights[i] = w
		sum += w
	end
	local heights = {}
	local given = 0
	for i in cols do
		heights[i] = math.floor(count * weights[i] / sum)
		given += heights[i]
	end
	-- Remainder to the most central columns, deterministic order.
	local order = {}
	for i in cols do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if weights[a] ~= weights[b] then
			return weights[a] > weights[b]
		end
		return a < b
	end)
	local k = 1
	while given < count do
		local ci = order[((k - 1) % #order) + 1]
		heights[ci] += 1
		given += 1
		k += 1
	end

	-- Shuffled id deal (Fisher-Yates): slot j (column order, bottom to top) gets id perm[j].
	local perm = table.create(count)
	for i = 1, count do
		perm[i] = i
	end
	for i = count, 2, -1 do
		local j = rng:NextInteger(1, i)
		perm[i], perm[j] = perm[j], perm[i]
	end
	local rocks: { Rock } = table.create(count)
	local slot = 0
	for ci, c in cols do
		for _ = 1, heights[ci] do
			slot += 1
			local id = perm[slot]
			rocks[id] = {
				Id = id,
				Column = ci,
				Jitter = Vector3.new(rng:NextNumber(-0.12, 0.12) * s, 0, rng:NextNumber(-0.12, 0.12) * s),
				Rot = Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(0, 360), rng:NextNumber(-25, 25)),
				Scale = rng:NextNumber(0.85, 1.15),
				Shape = rng:NextInteger(1, 4),
			}
			table.insert(c.Stack, id)
		end
	end

	return setmetatable({
		RockSize = s,
		Layer = s * 0.62,
		Rocks = rocks,
		Columns = cols,
		Removed = {},
		Remaining = count,
		Total = count,
	}, Pile)
end

function Pile.levelOf(self: Pile, id: number): number?
	local rock = self.Rocks[id]
	if not rock or self.Removed[id] then
		return nil
	end
	local stack = self.Columns[rock.Column].Stack
	for i, rid in stack do
		if rid == id then
			return i
		end
	end
	return nil
end

function Pile.isExposed(self: Pile, id: number): boolean
	local level = self:levelOf(id)
	if not level then
		return false
	end
	local col = self.Columns[self.Rocks[id].Column]
	if level == #col.Stack or col.OpenEdge then
		return true
	end
	for _, nb in col.Neighbors do
		if #self.Columns[nb].Stack < level then
			return true
		end
	end
	return false
end

-- Local position of a rock's centre relative to the pile centre on the floor.
function Pile.localPosition(self: Pile, id: number): Vector3?
	local level = self:levelOf(id)
	if not level then
		return nil
	end
	local rock = self.Rocks[id]
	local col = self.Columns[rock.Column]
	return Vector3.new(col.Pos.X, (level - 0.5) * self.Layer, col.Pos.Y) + rock.Jitter
end

-- Removes a rock. Returns the column index so callers can refresh it and its neighbours.
function Pile.remove(self: Pile, id: number): number?
	local level = self:levelOf(id)
	if not level then
		return nil
	end
	local rock = self.Rocks[id]
	table.remove(self.Columns[rock.Column].Stack, level)
	self.Removed[id] = true
	self.Remaining -= 1
	return rock.Column
end

-- V3 loop: a rock can be picked up when it is exposed AND low enough to reach from the mound
-- perimeter without climbing (its layer is at most maxLevel). The bottom rock of any column that
-- touches empty ground is always exposed, so the pile can never get stuck.
function Pile.isPickable(self: Pile, id: number, maxLevel: number): boolean
	local level = self:levelOf(id)
	return level ~= nil and level <= maxLevel and self:isExposed(id)
end

function Pile.pickableIds(self: Pile, maxLevel: number): { number }
	local out = {}
	for _, col in self.Columns do
		for level, id in col.Stack do
			if level <= maxLevel and self:isExposed(id) then
				table.insert(out, id)
			end
		end
	end
	return out
end

-- Puts a removed rock back on the mound (a leaver's basket or queue). It goes on top of a
-- low column at the edge (fewer than maxLevel rocks, so it stays reachable), the one nearest
-- `near` (xz relative to the pile centre) when given. Deterministic; returns the column index.
function Pile.restore(self: Pile, id: number, near: Vector2?, maxLevel: number?): number?
	if not self.Removed[id] then
		return nil
	end
	local cap = maxLevel or 3
	local best, bestKey, bestIdx = nil, math.huge, math.huge
	for ci, col in self.Columns do
		local h = #col.Stack
		-- prefer edge columns that still have room, then the lowest column anywhere
		local key = h + (if col.OpenEdge and h < cap then 0 else 1000)
		if near then
			key += (col.Pos - near).Magnitude * 0.01
		end
		if key < bestKey or (key == bestKey and ci < bestIdx) then
			best, bestKey, bestIdx = ci, key, ci
		end
	end
	if not best then
		return nil
	end
	self.Removed[id] = nil
	table.insert(self.Columns[best].Stack, id)
	self.Rocks[id].Column = best
	self.Remaining += 1
	return best
end

-- Same as restore but into a column the server already chose (clients replay the server's choice).
function Pile.restoreTo(self: Pile, id: number, column: number): boolean
	if not self.Removed[id] or not self.Columns[column] then
		return false
	end
	self.Removed[id] = nil
	table.insert(self.Columns[column].Stack, id)
	self.Rocks[id].Column = column
	self.Remaining += 1
	return true
end

-- Full column contents (bottom first), for reconnects: clients replace their layout with this.
function Pile.stacks(self: Pile): { { number } }
	local out = {}
	for ci, col in self.Columns do
		out[ci] = table.clone(col.Stack)
	end
	return out
end

function Pile.setStacks(self: Pile, stacks: { { number } })
	local removed: { [number]: boolean } = {}
	for id in self.Rocks do
		removed[id] = true
	end
	local remaining = 0
	for ci, col in self.Columns do
		col.Stack = table.clone(stacks[ci] or {})
		for _, id in col.Stack do
			removed[id] = nil
			remaining += 1
			if self.Rocks[id] then
				self.Rocks[id].Column = ci
			end
		end
	end
	self.Removed = removed
	self.Remaining = remaining
end

function Pile.exposedIds(self: Pile): { number }
	local out = {}
	for _, col in self.Columns do
		for _, id in col.Stack do
			if self:isExposed(id) then
				table.insert(out, id)
			end
		end
	end
	return out
end

return Pile
