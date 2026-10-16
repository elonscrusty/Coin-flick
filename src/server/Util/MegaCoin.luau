--!strict
-- The shared mega coin's counter. Pure: no Roblox objects, so it is tested.
-- Everyone taps the same coin; when the taps reach the goal it flips and
-- everyone who helped gets a reward.

export type MegaCoin = {
	taps: number,
	contributors: { [number]: number }, -- userId -> taps
	tap: (self: MegaCoin, userId: number, goal: number) -> boolean,
	finish: (self: MegaCoin) -> { number },
	forget: (self: MegaCoin, userId: number) -> (),
}

local MegaCoin = {}

-- One tap. Returns true when this tap filled the coin.
local function tap(self: MegaCoin, userId: number, goal: number): boolean
	self.taps += 1
	self.contributors[userId] = (self.contributors[userId] or 0) + 1
	return self.taps >= goal
end

-- The coin flipped: hand back who helped and start over.
local function finish(self: MegaCoin): { number }
	local ids: { number } = {}
	for userId in self.contributors do
		table.insert(ids, userId)
	end
	table.sort(ids)
	self.taps = 0
	self.contributors = {}
	return ids
end

-- A player left: their taps stay in the count, but they get no reward.
local function forget(self: MegaCoin, userId: number)
	self.contributors[userId] = nil
end

function MegaCoin.new(): MegaCoin
	return {
		taps = 0,
		contributors = {},
		tap = tap,
		finish = finish,
		forget = forget,
	}
end

return MegaCoin
