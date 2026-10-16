-- hitfx: third-person pictures of ANOTHER player (Ava) carrying a basket and swinging / holding a jackhammer
-- at her table, driven only by the server events the real client already receives (docs/m10/HITFX.md).
-- First-person crack stages, contact dust and the split use the fp scene (--set view=table --set t=S).
--   --set view=carry            Ava walks with 3+ rocks in her basket (both arms under it)
--   --set view=swing            Ava at her plate once --set q=4 rocks are left in her tray (--set tool=SteelHammer|Jackhammer)
--   --set extra=S               extra seconds simulated before the shot (changes the stroke phase)
local C = lib("ctr")
local view = preview.args.view or "swing"
local tool = preview.args.tool or "Hammer"
local s = C.boot({
	others = { { "Ava", 2 } },
	profile = function(data)
		data.Cash = 900
		data.TutorialStep = 1
		data.CapacityTier = 3
	end,
})
local ava = s.others[1]
local ad = s.Profiles and s.Profiles.get(ava)
if ad then
	ad.CapacityTier = 3
	ad.TutorialStep = 1
	if tool ~= "Hammer" then
		ad.EquipmentOwned[tool] = true
		ad.EquippedHandheld = tool
	end
	s.Profiles.changed(ava)
end
local w = C.watchMatch()
C.fireServer("PartyAction", "Create")
preview.advance(0.3)
local pt = s.PartyService.of(s.me.UserId)
C.fireServer("PartyAction", "Invite", ava.UserId)
preview.advance(0.3)
preview.fireServerAs(ava, "PartyAction", "Accept", pt and pt.Id)
preview.advance(0.3)
preview.fireServerAs(ava, "PartyAction", "Ready", true)
preview.advance(0.3)
C.fireServer("PartyAction", "Ready", true)
preview.advance(0.3)
C.fireServer("PartyAction", "Start")
for _ = 1, 20 do
	if w.last.Init then
		break
	end
	preview.advance(0.1)
end
C.waitPhase(w, "Searching", 6)
C.settle(0.4)
local SV = preview.client("StationView")
local CarryView = preview.client("CarryView")
local function avaState()
	return SV.Latest and SV.Latest[ava.UserId]
end
C.crackUntilFound(w, { ava }, 200, {
	stopWhen = function()
		local st = avaState()
		if not st then
			return false
		end
		if view == "carry" then
			return #st.Basket >= 3 and CarryView.count(ava.UserId) >= 3
		end
		-- her scheduled strokes (Hit events) are playing once the first queued rock was taken
		return #st.Queue <= (tonumber(preview.args.q) or 4)
	end,
})
local ava = s.others[1]
local ad = s.Profiles and s.Profiles.get(ava)
if ad then
	ad.CapacityTier = 3
	ad.TutorialStep = 1
	if tool ~= "Hammer" then
		ad.EquipmentOwned[tool] = true
		ad.EquippedHandheld = tool
	end
	s.Profiles.changed(ava)
end
local w = C.watchMatch()
C.fireServer("PartyAction", "Create")
preview.advance(0.3)
local pt = s.PartyService.of(s.me.UserId)
C.fireServer("PartyAction", "Invite", ava.UserId)
preview.advance(0.3)
preview.fireServerAs(ava, "PartyAction", "Accept", pt and pt.Id)
preview.advance(0.3)
preview.fireServerAs(ava, "PartyAction", "Ready", true)
preview.advance(0.3)
C.fireServer("PartyAction", "Ready", true)
preview.advance(0.3)
C.fireServer("PartyAction", "Start")
for _ = 1, 20 do
	if w.last.Init then
		break
	end
	preview.advance(0.1)
end
C.waitPhase(w, "Searching", 6)
C.settle(0.4)
local SV = preview.client("StationView")
local CarryView = preview.client("CarryView")
local function avaState()
	return SV.Latest and SV.Latest[ava.UserId]
end
C.crackUntilFound(w, { ava }, 200, {
	stopWhen = function()
		local st = avaState()
		if not st then
			return false
		end
		if view == "carry" then
			return #st.Basket >= 3 and CarryView.count(ava.UserId) >= 3
		end
		if preview.args.dbg then
			print("[dbg]", #st.Queue, tostring(st.Current), tostring(st.Progress), st.State)
		end
		return st.Current ~= nil and (st.Progress or 0) >= (tonumber(preview.args.p) or 0.4)
	end,
})
preview.advance(tonumber(preview.args.extra) or 0.15)
local root = ava.Character and ava.Character:FindFirstChild("HumanoidRootPart")
if root then
	local cf = root.CFrame
	local plate = SV.platePosition(ava.UserId)
	local target = if view == "swing" and plate then cf.Position + Vector3.new(0, 0.8, 0) else cf.Position + Vector3.new(0, 0.5, 0)
	local off = if view == "swing" then (cf.LookVector * 9 + cf.RightVector * 6) + Vector3.new(0, 4.5, 0) else (cf.LookVector * 7 + cf.RightVector * 6) + Vector3.new(0, 3.5, 0)
	C.cameraAt(target, off, 55)
end
local st = avaState()
print("[hitfx] view=" .. view .. " basket=" .. tostring(st and #st.Basket) .. " progress=" .. tostring(st and st.Progress))
