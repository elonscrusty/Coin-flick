-- party: the PARTY panel in the lobby, driven through the real PartyService.
--   --set view=none   (default) no party yet: SOLO HUNT / CREATE PARTY
--   --set view=solo   a party of one (created with PartyAction Create): tiers, READY, START
--   --set view=party  Ava and Ben invited and joined (real Invite / Accept), Ava ready
--   --set view=invite Ava invited you: the PARTY INVITE dialog with ACCEPT / DECLINE
--   --set view=invitetab  Ava joined, Ben is in the lobby: the leader's Invite tab (eligible players only)
--   --set view=expired    Ava's invite runs out (Config.Party.InviteSeconds): the dialog closes, "Party invitation expired."
--   --set view=starting   START on SOLO HUNT, captured before the hunt arrives: "Starting hunt..." (the request is
--                         held back through PartyPanel.Hold)
--   --set view=startcheck STARTING PASS: two taps + a reopen send one request, timeout notice, a real start clears it
local C = lib("ctr")
local view = preview.args.view or "none"
local others = if view == "party" or view == "invite" or view == "invitetab" or view == "expired" then { { "Ava", 2 }, { "Ben", 3 } } else {}
local s = C.boot({
	others = others,
	profile = function(data)
		data.Cash = 2400
		data.TutorialStep = 1
		data.UnlockedTiers.Quarry = true
	end,
})
C.settle(1)
local me = s.me
if view == "solo" then
	C.fireServer("PartyAction", "Create")
elseif view == "party" then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(me.UserId)
	for _, p in ipairs(s.others) do
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", party and party.Id)
		preview.advance(0.3)
	end
	preview.fireServerAs(s.others[1], "PartyAction", "Ready", true)
elseif view == "invitetab" then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(me.UserId)
	C.fireServer("PartyAction", "Invite", s.others[1].UserId)
	preview.advance(0.3)
	preview.fireServerAs(s.others[1], "PartyAction", "Accept", party and party.Id)
	preview.advance(0.5)
	C.tap("^INVITE$")
elseif view == "expired" then
	local ava = s.others[1]
	preview.fireServerAs(ava, "PartyAction", "Create")
	preview.advance(0.3)
	preview.fireServerAs(ava, "PartyAction", "Invite", me.UserId)
	preview.advance(1)
	local had = C.findText("^ACCEPT$", "GuiButton") ~= nil
	for _ = 1, preview.shared("Config").Party.InviteSeconds + 12 do
		preview.advance(1)
		if C.findText("^ACCEPT$", "GuiButton") == nil then
			break
		end
	end
	preview.advance(0.3)
	local gone = C.findText("^ACCEPT$", "GuiButton") == nil
	local said = C.findText("^PARTY INVITATION EXPIRED") ~= nil
	if had and gone and said then
		print("INVITE-EXPIRY PASS (dialog shown, closed on expiry, notice shown)")
	else
		print(("[FAIL] INVITE-EXPIRY had=%s gone=%s said=%s"):format(tostring(had), tostring(gone), tostring(said)))
	end
elseif view == "starting" or view == "startcheck" then
	-- the panel's preview seam holds the request back (the mock server would answer in the same step)
	local Panel = preview.require(preview.clientFolder():FindFirstChild("ui"):FindFirstChild("PartyPanel"))
	Panel.Hold = true
	C.tap("^PARTY$")
	preview.advance(0.3)
	C.tap("^START$")
	preview.advance(0.3)
	if view == "starting" then
		C.followCamera()
		return
	end
	-- STARTING PASS: one request for two taps and a reopen, the pending state visible, the start view kept,
	-- a timeout notice, and a real start ending the pending state.
	local shown = C.findText("^STARTING HUNT") ~= nil
	local again = C.tap("^START$") -- the button is gone while pending
	Panel.open()
	preview.advance(0.2)
	local still = C.findText("^STARTING HUNT") ~= nil
	local sent = #Panel.Held
	preview.advance(9) -- past START_WAIT
	local timedOut = not Panel.isStarting() and C.findText("^THE HUNT DID NOT START") ~= nil and C.findText("^START$", "GuiButton") ~= nil
	Panel.Held = {}
	Panel.Hold = true
	C.tap("^START$")
	preview.advance(0.1)
	local pendingAgain = Panel.isStarting()
	Panel.release()
	preview.advance(4)
	local ended = not Panel.isStarting()
	local inHunt = C.findText("^STARTING HUNT") == nil and C.findText("^START HUNT$") == nil
	if shown and not again and still and sent == 1 and timedOut and pendingAgain and ended and inHunt then
		print("STARTING PASS (shown, one request for two taps + reopen, timeout notice, cleared by the hunt)")
	else
		print(("[FAIL] STARTING shown=%s again=%s still=%s sent=%d timedOut=%s pendingAgain=%s ended=%s inHunt=%s"):format(
			tostring(shown), tostring(again), tostring(still), sent, tostring(timedOut), tostring(pendingAgain), tostring(ended), tostring(inHunt)))
	end
	return
elseif view == "invite" then
	local ava = s.others[1]
	preview.fireServerAs(ava, "PartyAction", "Create")
	preview.advance(0.3)
	preview.fireServerAs(ava, "PartyAction", "Invite", me.UserId)
end
preview.advance(0.5)
-- a party arriving opens the panel by itself; otherwise tap the HUD button
if view ~= "expired" and view ~= "invitetab" and not C.findText("^LEAVE$", "GuiButton") and not C.findText("^SOLO HUNT$") and not C.findText("^ACCEPT$", "GuiButton") then
	C.tap("^PARTY$")
end
-- setup notices ("Invite sent to ...") are transient: let them run out so the picture shows the panel
if view == "party" or view == "invitetab" then
	preview.advance(4.5)
end
C.settle(1)
C.followCamera()
