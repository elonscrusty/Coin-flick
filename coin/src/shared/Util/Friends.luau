--!strict
-- Friend bonus: a player with at least one friend in the same server gets 2x cash (so does the friend).
-- Pure; the server asks Roblox who is friends with whom and passes the answer in.

local Config = require(script.Parent.Parent.Config)

local Friends = {}

-- userIds in this server -> { [userId] = true } for everyone who has a friend here.
-- `areFriends` must be symmetric in practice; only pairs a < b are asked, so each pair is checked once.
function Friends.flags(userIds: { number }, areFriends: (number, number) -> boolean): { [number]: boolean }
	local flags: { [number]: boolean } = {}
	for i = 1, #userIds do
		for j = i + 1, #userIds do
			local a, b = userIds[i], userIds[j]
			if a ~= b and areFriends(a, b) then
				flags[a] = true
				flags[b] = true
			end
		end
	end
	return flags
end

function Friends.multiplier(hasFriendHere: boolean): number
	return if hasFriendHere then Config.FRIEND_CASH_MULT else 1
end

return Friends
