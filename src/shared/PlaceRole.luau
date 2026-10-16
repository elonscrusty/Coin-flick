--!strict
-- Which job this server does. Pure so it can be tested offline.
--   "Single": lobby and private arenas in one server (default, Studio, unpublished places).
--   "Lobby" : public lobby that teleports parties to the Match place.
--   "Match" : private reserved server that runs one party's hunts.
-- Anything that is not clearly configured falls back to "Single" so Studio always works.

local PlaceRole = {}

function PlaceRole.resolve(mode: string, placeId: number, lobbyPlaceId: number, matchPlaceId: number): string
	if mode ~= "Teleport" then
		return "Single"
	end
	if lobbyPlaceId == 0 or matchPlaceId == 0 or lobbyPlaceId == matchPlaceId then
		return "Single" -- ids not pasted in yet (or both the same): do not half-enable teleports
	end
	if placeId == matchPlaceId then
		return "Match"
	elseif placeId == lobbyPlaceId then
		return "Lobby"
	end
	return "Single" -- Studio / a place that is neither of the two
end

return PlaceRole
