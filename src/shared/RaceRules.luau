--!strict
-- Race bar standings (pure, tests/test_race.luau). Input: the station views the server sends with every pile
-- update ({ UserId, Index, Cracked }) and the member list ({ UserId, Name, Present }). Output: one row per
-- member, most eggs cracked first (ties keep station order), with a 0..1 bar share of the leader's count.
-- Uses only per-player crack counts: nothing here says which egg hides the pet.

local RaceRules = {}

export type Row = { UserId: number, Name: string, Cracked: number, Share: number, Present: boolean, Leader: boolean }

function RaceRules.standings(stations: { any }?, members: { any }?): { Row }
	local counts: { [number]: number } = {}
	local order: { [number]: number } = {}
	local stList: { any } = stations or {}
	for _, st in stList do
		if type(st) == "table" and type(st.UserId) == "number" then
			counts[st.UserId] = math.max(0, math.floor(tonumber(st.Cracked) or 0))
			order[st.UserId] = tonumber(st.Index) or 99
		end
	end
	local rows: { Row } = {}
	local memList: { any } = members or {}
	for i, mem in memList do
		local uid = mem.UserId
		if type(uid) == "number" then
			table.insert(rows, {
				UserId = uid,
				Name = tostring(mem.Name or "?"),
				Cracked = counts[uid] or math.max(0, math.floor(tonumber(mem.Cracked) or 0)),
				Share = 0,
				Present = mem.Present ~= false,
				Leader = false,
			})
			if order[uid] == nil then
				order[uid] = 100 + i
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.Cracked ~= b.Cracked then
			return a.Cracked > b.Cracked
		end
		return order[a.UserId] < order[b.UserId]
	end)
	local top = if rows[1] then rows[1].Cracked else 0
	for i, r in rows do
		r.Share = if top > 0 then r.Cracked / top else 0
		r.Leader = i == 1 and top > 0 and (rows[2] == nil or rows[2].Cracked < top)
	end
	return rows
end

return RaceRules
