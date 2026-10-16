-- results: a real hunt played to the end through the Strike remote (the player walks to the
-- nearest exposed rock and cracks it at the hammer's rate until the server reports Found),
-- then the reveal and the results screen.
--   --set stage=results (default) the results screen, stage=reveal the geode reveal
--   --set mode=solo (default) a Gravel solo hunt, mode=tutorial the practice pile
--   (TutorialStep 0), mode=party Ava and Ben hunt with you (they crack too; whoever breaks
--   the geode rock wins it)
local C = lib("ctr")
local mode = preview.args.mode or "solo"
local others = if mode == "party" then { { "Ava", 2 }, { "Ben", 3 } } else {}
local s = C.boot({
	others = others,
	profile = function(data)
		data.Cash = 900
		data.TutorialStep = if mode == "tutorial" then 0 else 1
		data.CapacityTier = 3 -- 300 rubble: the whole Gravel pile fits (30 would fill up mid-hunt)
	end,
})
for _, p in ipairs(s.others) do
	local d = s.Profiles and s.Profiles.get(p)
	if d then
		d.CapacityTier = 3
		d.TutorialStep = 1
	end
end
local w = C.watchMatch()
local players = { s.me }
if mode == "party" then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local party = s.PartyService.of(s.me.UserId)
	for _, p in ipairs(s.others) do
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", party and party.Id)
		preview.advance(0.3)
		table.insert(players, p)
	end
	-- a member joining clears Ready, so everyone readies after the last one joined
	for _, p in ipairs(s.others) do
		preview.fireServerAs(p, "PartyAction", "Ready", true)
		preview.advance(0.3)
	end
	C.fireServer("PartyAction", "Ready", true)
	preview.advance(0.3)
	C.fireServer("PartyAction", "Start")
	for _ = 1, 20 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
else
	C.startSolo(w)
end
C.waitPhase(w, "Searching", 6)
local found = C.crackUntilFound(w, players)
preview.log("found: " .. tostring(found) .. (w.last.Found and (" by " .. tostring(w.last.Found.WinnerName)) or ""))
if preview.args.stage == "reveal" then
	-- --set at=<s> seconds into the reveal (default 1.6: shell open, labels in)
	C.waitPhase(w, "Reveal", 8)
	local at = tonumber(preview.args.at) or 1.6
	preview.advance(math.max(0.05, (w.at.Reveal or preview.now()) + at - preview.now()))
else
	C.waitPhase(w, "Results", 15)
	C.settle(6) -- the client plays the geode opening before the results panel (Main.client reveal delay)
end
C.followCamera(16, 8)
if preview.args.skip == "1" then
	-- --set skip=1 (with mode=tutorial): SKIP TUTORIAL on the practice results. The footer must switch to the
	-- ordinary PLAY AGAIN / LOBBY (no second SKIP TUTORIAL, no tutorial stage line).
	C.tap("^SKIP TUTORIAL$")
	C.settle(1)
	local ok = C.findText("^PLAY AGAIN$", "GuiButton") ~= nil and C.findText("^SKIP TUTORIAL$", "GuiButton") == nil
	print(if ok then "SKIP PASS (PLAY AGAIN shown, SKIP TUTORIAL gone)" else "[FAIL] SKIP: tutorial footer still shown")
end
