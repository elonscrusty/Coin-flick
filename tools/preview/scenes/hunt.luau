-- hunt: a solo hunt started through the real PartyAction("Solo") handler (MatchService builds
-- the arena and the pile), past the 3 s countdown into Searching; camera behind the player at
-- the pile. --set phase=countdown stops during the countdown, --set cracked=N cracks N rocks
-- first (the V3 loop through the real RockAction remote), --set tutorial=on runs the practice pile (TutorialStep 0),
-- --set tier=Quarry picks the party tier (must be unlocked; the scene unlocks it),
-- --set view=wide a high view over the arena, --set near=on stands the player at the mound
-- edge facing it, --set swing=T (with near) holds the action button for T seconds (picks up rocks).
-- --set machine=AutoCracker|HydraulicPress|IndustrialCrusher installs that machine for the player
-- (owned, installed), --set mtime=S runs the machine S seconds into the hunt before the capture,
-- --set mstate=paused|full pauses it / fills the bag, --set view=bay frames the player's bay
-- (--set bayview=front|side|top), --set view=wide shows the whole arena,
-- --set race=on: a three-player party hunt (you, Ava, Ben) through the real party handlers; everyone cracks eggs
-- until --set cracked=N (default 4) are done and your nest has an egg, then you stand at your nest (CRACK button,
-- race bar).
-- --set view=corner|top|gate|hopper|nook|drop|station|low|overview|frompile are the arena art views (ARENA_VIEWS).
local C = lib("ctr")
-- Extra arena views: corner (high, from the south-west), top (plan view), gate (from inside
-- the entrance), hopper (approach to the sell hopper), nook (equipment shelter), drop (east
-- railing and the lower bench), gate (the gate from inside), station (behind table 3 looking at the mound), low (eye level).
local ARENA_VIEWS = {
	corner = { Vector3.new(0, 0, 0), Vector3.new(-48, 46, 52), 60 },
	top = { Vector3.new(0, 0, 0), Vector3.new(0, 120, 1), 60 },
	gate = { Vector3.new(0, 4, -44), Vector3.new(6, 9, 26), 70 },
	hopper = { Vector3.new(0, 3, 32), Vector3.new(8, 8, -16), 60 },
	nook = { Vector3.new(-36, 3, 0), Vector3.new(18, 9, 6), 60 },
	drop = { Vector3.new(58, -8, 4), Vector3.new(-24, 22, 16), 70 },
	station = { Vector3.new(0, 2, 0), Vector3.new(-22, 7, -22), 70 },
	low = { Vector3.new(0, 4, 0), Vector3.new(-6, 4, 30), 70 },
	-- pass four (docs/m5/quarry): high three-quarter overview like the owner's placement target, and a
	-- player-height view from the pile edge toward table 3 and the north-west edge
	overview = { Vector3.new(0, 0, -4), Vector3.new(0, 50, 54), 60 },
	frompile = { Vector3.new(-14, 3, -16), Vector3.new(14, 2.5, 14), 70 },
}
local tier = preview.args.tier
local race = preview.args.race == "on"
local s = C.boot({
	others = if race then { { "Ava", 2 }, { "Ben", 3 } } else nil,
	profile = function(data)
		data.Cash = 640
		data.TutorialStep = if preview.args.tutorial == "on" then 0 else 1
		local machine = preview.args.machine
		if machine then
			data.EquipmentOwned[machine] = true
			data.InstalledMachine = machine
		end
		if preview.args.bag == "full" then
			data.RubbleByTier = { Gravel = 30 } -- bag full: the calm notice and the SELL guidance
		end
		if preview.args.mstate == "full" then
			data.RubbleByTier = { Gravel = 29 } -- one slot left; the first claim fills the bag
		end
		if tier then
			data.UnlockedTiers[tier] = true
		end
	end,
})
local w = C.watchMatch()
if tier then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	C.fireServer("PartyAction", "Tier", tier)
	preview.advance(0.3)
end
local init
if race then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local pt = s.PartyService.of(s.me.UserId)
	for _, p in ipairs(s.others) do
		local d = s.Profiles.get(p)
		if d then
			d.TutorialStep = 1
			s.Profiles.changed(p)
		end
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", pt and pt.Id)
		preview.advance(0.3)
	end
	for _, p in ipairs(s.others) do
		preview.fireServerAs(p, "PartyAction", "Ready", true)
		preview.advance(0.3)
	end
	C.fireServer("PartyAction", "Ready", true)
	preview.advance(0.3)
	C.fireServer("PartyAction", "Start")
	for _ = 1, 30 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
	init = w.last.Init
else
	init = C.startSolo(w)
end
if race and init then
	C.waitPhase(w, "Searching", 6)
	local want = tonumber(preview.args.cracked) or 4
	local done = 0
	local mine = nil
	local me = s.me
	local ev = game:GetService("ReplicatedStorage").Remotes.MatchEvent
	local conn = ev.OnClientEvent:Connect(function(kind, data)
		if kind == "Rocks" then
			for _, e in ipairs(data.Ev or {}) do
				if e.Kind == "Done" then
					done += 1
				end
			end
			for _, v in ipairs(data.Stations or {}) do
				if v.UserId == me.UserId then
					mine = v
				end
			end
		end
	end)
	local players = { me }
	for _, p in ipairs(s.others) do
		table.insert(players, p)
	end
	C.crackUntilFound(w, players, 240, {
		stopWhen = function()
			return done >= want and mine ~= nil and (mine.Current ~= nil or #mine.Queue > 0)
		end,
	})
	conn:Disconnect()
	-- stand at your own nest, facing it
	local tp
	for _, t in ipairs(init.Tables or {}) do
		if mine and t.Index == mine.Index then
			tp = t.Position
		end
	end
	if tp then
		local standPos = tp + (init.Center - tp).Unit * 3.4
		C.place(me, CFrame.lookAt(Vector3.new(standPos.X, 3, standPos.Z), Vector3.new(tp.X, 3, tp.Z)))
	end
	preview.log("race: " .. done .. " eggs done")
	C.settle(1)
elseif preview.args.phase == "countdown" then
	preview.advance(1.2)
else
	C.waitPhase(w, "Searching", 6)
	local n = tonumber(preview.args.cracked) or 0
	if n > 0 and init then
		-- crack n rocks: reuse the strike loop with a removal limit
		local cracked = 0
		local ev = game:GetService("ReplicatedStorage").Remotes.MatchEvent
		ev.OnClientEvent:Connect(function(kind, data)
			if kind == "Rocks" then
				for _, e in ipairs(data.Ev or {}) do
					if e.Kind == "Done" then
						cracked += 1
					end
				end
			end
		end)
		local Config = C.shared("Config")
		-- V3 loop: pick up, deposit and crush at the table until n rocks are done
		C.crackUntilFound(w, nil, n * 4 * (Config.Tiers[init.Tier].HP or 1) + 30, { stopAfterDone = n })
		preview.log("cracked " .. cracked .. " rocks")
	end
	C.settle(1)
end
local mtime = tonumber(preview.args.mtime)
if mtime and preview.args.machine then
	if preview.args.mstate == "paused" then
		C.fireServer("ShopAction", "ToggleMachine")
	end
	preview.advance(mtime, 30)
end
if preview.args.near == "on" and init then
	local me = game:GetService("Players").LocalPlayer
	local pos = init.Center + Vector3.new(0, 0, 13)
	C.place(me, CFrame.lookAt(pos, Vector3.new(init.Center.X, pos.Y, init.Center.Z)))
	C.settle(0.3)
	local t = tonumber(preview.args.swing)
	if t then
		local PileView = preview.client("PileView")
		PileView.holdBegin()
		preview.advance(0.05 + t)
	end
end
-- --set qcam=x,y,z --set qlook=x,y,z [--set qfov=N]: camera relative to the mound centre.
-- --set tcam=own|idle with --set toff=x,y,z --set tlook=x,y,z: offsets in the frame of the player's table
-- (own) or the first inactive table (idle); table frame: -Z toward the pile (the operating side), +Y up.
local function vec3(s: string?): Vector3?
	if not s then
		return nil
	end
	local a = string.split(s, ",")
	return Vector3.new(tonumber(a[1]) or 0, tonumber(a[2]) or 0, tonumber(a[3]) or 0)
end
local customDone = false
if init and preview.args.qcam then
	local look = vec3(preview.args.qlook) or Vector3.zero
	C.cameraAt(init.Center + look, (vec3(preview.args.qcam) :: Vector3) - look, tonumber(preview.args.qfov) or 60)
	customDone = true
elseif init and preview.args.tcam then
	local me = game:GetService("Players").LocalPlayer
	local pick
	for _, d in game:GetService("Workspace"):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("StationIndex") then
			local mine = d:GetAttribute("OwnerId") == me.UserId
			if (preview.args.tcam == "own") == mine and (mine or not pick) then
				pick = d
			end
		end
	end
	if pick then
		local f = pick:GetPivot() * CFrame.new(0, -2.75, 0)
		local off = vec3(preview.args.toff) or Vector3.new(0, 5, -9)
		local look = vec3(preview.args.tlook) or Vector3.new(0, 3, 0)
		local cam = game:GetService("Workspace").CurrentCamera
		cam.CFrame = CFrame.lookAt(f:PointToWorldSpace(off), f:PointToWorldSpace(look))
		cam.FieldOfView = tonumber(preview.args.qfov) or 60
		customDone = true
	end
end
if customDone then
	-- camera already placed
elseif preview.args.view == "bay" then
	local found
	for _, d in game:GetService("Workspace"):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("MachineId") then
			found = d
		end
	end
	if found then
		local frame = found:GetAttribute("Frame")
		local v = preview.args.bayview or "front"
		local off = if v == "side" then Vector3.new(24, 7, -4) elseif v == "top" then Vector3.new(2, 28, -14) elseif v == "back" then Vector3.new(9, 9, 22) else Vector3.new(10, 9, -22)
		C.cameraAt(frame.Position + Vector3.new(0, 4, 0), frame:VectorToWorldSpace(off), 60)
	end
elseif preview.args.view == "wide" and init then
	C.cameraAt(init.Center, Vector3.new(0, 55, 60))
elseif preview.args.view and ARENA_VIEWS[preview.args.view] and init then
	-- arena art views (V4 arena): {target offset from the mound centre, camera offset, fov}
	local v = ARENA_VIEWS[preview.args.view]
	C.cameraAt(init.Center + v[1], v[2], v[3])
else
	C.followCamera(16, 8)
end
if preview.args.cam == "side" and init then
	local me = game:GetService("Players").LocalPlayer
	local r = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	if r then
		C.cameraAt(r.Position, Vector3.new(16, 3, -2), 50)
	end
end
if preview.args.toast == "feedback" then
	-- --set toast=feedback (board 12): the same refusal three times must stay ONE notification (coalesced),
	-- plus a purchase confirmation from the server. Prints NOTICES PASS / [FAIL].
	for _ = 1, 3 do
		preview.fireClient("Toast", "Basket full: take rocks to your table", "info")
		preview.advance(0.15)
	end
	preview.fireClient("Toast", "Bought and equipped the Steel Hammer!", "ok")
	preview.advance(0.3)
	local UIm = preview.require(preview.clientFolder():FindFirstChild("ui"):FindFirstChild("UI"))
	local texts = UIm.noticeTexts()
	local basket = 0
	for _, t in ipairs(texts) do
		if string.find(t, "^Basket full") then
			basket += 1
		end
	end
	if basket == 1 and #texts == 2 then
		print("NOTICES PASS (3 identical refusals coalesced into one card, 2 cards total)")
	else
		print(("[FAIL] NOTICES basket cards=%d total=%d"):format(basket, #texts))
	end
elseif preview.args.toast then
	-- --set toast=1: a sale toast and an info toast (bounded stack)
	preview.fireClient("Toast", "+$48  •  Sold 24 rubble", "cash")
	preview.advance(0.2)
	preview.fireClient("Toast", "Invite sent to Ben.", "info")
	preview.advance(0.3)
end
