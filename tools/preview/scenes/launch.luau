-- launch: the teleport LaunchPanel card, driven by firing the real LaunchEvent payloads the
-- server would send (the preview runs a single place, so the Teleport services are not live).
--   --set kind=launching (default) heading to the quarry, members sent / on the way
--   --set kind=failed        a member failed, RETRY / CANCEL     (also: partial, preparing)
--   --set kind=waiting       WaitingForParty with arrival checks + countdown
--   --set kind=timedout      members missing, START WITH ARRIVED / RETURN ALL (--set leader=off: RETURN only)
--   --set kind=loading       everyone here, loading gear
--   --set kind=returnfailed | rejected | returning
--   --set members=N          party size 2-4 (default 4)
local C = lib("ctr")
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
C.settle(1)
local kind = preview.args.kind or "launching"
local n = math.clamp(tonumber(preview.args.members) or 4, 2, 4)
local names = { "KestrelRockhound", "Ava", "Ben_the_Breaker", "Cleo" }
local members = {}
for i = 1, n do
	table.insert(members, { Name = names[i], UserId = 100 + i, Leader = i == 1 })
end
local function launch(phase, message, states)
	local list = {}
	for i, m in ipairs(members) do
		table.insert(list, { Name = m.Name, UserId = m.UserId, State = states[i] or "Pending" })
	end
	preview.fireClient("LaunchEvent", "Launch", { Phase = phase, Message = message, Leader = 101, Members = list, CanRetry = phase ~= "Preparing" })
end
local function waiting(status, arrived, canStart, canReturnAll, remaining)
	local list = {}
	for i, m in ipairs(members) do
		table.insert(list, { Name = m.Name, UserId = m.UserId, Arrived = arrived[i] == true, Leader = m.Leader })
	end
	preview.fireClient("LaunchEvent", "Waiting", { Status = status, Remaining = remaining, Members = list, CanStart = canStart, CanReturnAll = canReturnAll })
end
local leader = preview.args.leader ~= "off"
if kind == "launching" then
	launch("Sending", "Hold on, the party is travelling to the quarry.", { "Away", "Sent", "Pending", "Pending" })
elseif kind == "preparing" then
	launch("Preparing", "Reserving a private quarry for your party.", {})
elseif kind == "failed" then
	launch("Failed", "Ben_the_Breaker could not be teleported. Check your connection and try again.", { "Away", "Away", "Failed", "Away" })
elseif kind == "partial" then
	launch("Partial", "Some players are still in the lobby. Retry sends only the missing players.", { "Away", "Away", "Failed", "Pending" })
elseif kind == "waiting" then
	waiting("Waiting", { true, true }, false, false, 24)
elseif kind == "loading" then
	waiting("Loading", { true, true, true, true }, false, false, 0)
elseif kind == "timedout" then
	waiting("TimedOut", { true, true }, leader, leader, 0)
elseif kind == "returnfailed" then
	preview.fireClient("LaunchEvent", "ReturnFailed", {})
elseif kind == "rejected" then
	preview.fireClient("LaunchEvent", "Rejected", { Message = "This quarry is full. Ask your leader to start a new hunt." })
elseif kind == "returning" then
	preview.fireClient("LaunchEvent", "Returning", { Message = "Taking everyone back to the lobby..." })
end
C.settle(1)
C.followCamera()
