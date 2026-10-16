--!strict
-- Pure bookkeeping of the teleport flow (server/LobbyLaunch, server/MatchPlace), kept apart so it is tested offline
-- (tests/test_teleport_book.luau): which launch entries a dissolved launch clears, who is still here after a save
-- yielded, and which players a Return request takes (one already on its way back is skipped).
local TeleportBook = {}

-- Removes every `launchOf` entry (uid -> party id) that points at `partyId`, whoever is on the roster now. Returns how
-- many were removed.
function TeleportBook.dissolve(launchOf: { [number]: string }, partyId: string): number
	local n = 0
	for uid, pid in table.clone(launchOf) do
		if pid == partyId then
			launchOf[uid] = nil
			n += 1
		end
	end
	return n
end

-- True when every uid is still in the party and on the server; otherwise false and the refusal text.
function TeleportBook.stillHere(members: { number }, uids: { number }, onServer: (number) -> boolean): (boolean, string?)
	for _, uid in uids do
		if not onServer(uid) or not table.find(members, uid) then
			return false, "A party member left."
		end
	end
	return true, nil
end

-- A Return request: the uids that start a return now. A uid already returning is skipped unless this is a retry
-- (`retry` true: the caller's own earlier attempt failed). Each taken uid is stamped with `token`.
function TeleportBook.takeReturns(returning: { [number]: number }, uids: { number }, token: number, retry: boolean): { number }
	local taken = {}
	for _, uid in uids do
		if retry or returning[uid] == nil then
			table.insert(taken, uid)
			returning[uid] = token
		end
	end
	return taken
end

-- True when the watchdog of return `token` still owns `uid` (a newer return replaced it, or it cleared on arrival: no).
function TeleportBook.stillOwns(returning: { [number]: number }, uid: number, token: number): boolean
	return returning[uid] == token
end

return TeleportBook
