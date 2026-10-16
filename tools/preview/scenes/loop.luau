-- loop: the whole hunt loop in first person through the real server and client (Master Prompt 7, Pass E).
-- One simulation per picture: --set step=<name> plays everything up to that step and stops there.
--   spawn      lobby spawn, Start Hunt ahead
--   countdown  Start Hunt pressed (solo), the countdown
--   aim        at the pile, reticle on a rock
--   glimpse    three rocks picked up, basket lip at the lower edge
--   full       basket 5/5
--   deposit    at the own table, rocks just deposited
--   crack      hammer on the rock (tool contact)
--   output     first rock resolved: ordinary output + material notice
--   machine    AutoCracker running on the deposited queue
--   reveal     the target geode opening
--   results    Results screen
--   rematch    StartRematch from Results: a fresh round, no results card, empty basket, first-person camera
--   lobby      back in the lobby after Return: no hunt HUD
--   collection Collection panel: the won specimen
--   cabinet    the specimen on the owner cabinet (GeodeModel.onStand)
--   hud        lobby view after the whole loop: clean HUD
local C = lib("ctr")
local step = preview.args.step or "spawn"
local needsMachine = step == "machine"
local s = C.boot({
	profile = function(data)
		data.Cash = 900
		data.TutorialStep = 1
		data.CapacityTier = 3
		data.DisplayCapacity = 4
		if needsMachine then
			data.EquipmentOwned.AutoCracker = true
			data.InstalledMachine = "AutoCracker"
		end
	end,
})
local Workspace = game:GetService("Workspace")
local me, Config = s.me, s.Config
local cam = Workspace.CurrentCamera
local function fail(msg: string)
	print("[FAIL] loop " .. step .. ": " .. msg)
end
local function eyeOf(): Vector3
	return (me.Character:FindFirstChild("Head") :: BasePart).Position + Vector3.new(0, 0.15, 0)
end
local function look(at: Vector3)
	cam.CFrame = CFrame.lookAt(eyeOf(), at)
	cam.FieldOfView = Config.Camera.Fov
end
local function face(pos: Vector3, at: Vector3)
	C.place(me, CFrame.lookAt(pos, Vector3.new(at.X, pos.Y, at.Z)))
end
local function hudText(pattern: string): boolean
	-- only text that is actually on screen counts (a hidden card is not a stale HUD)
	local hits = preview.findGui(function(obj)
		local ok, text = pcall(function()
			return obj.Text
		end)
		return ok and type(text) == "string" and string.find(string.upper(text), pattern) ~= nil
	end)
	for _, g in ipairs(hits) do
		if preview.isShown(g) then
			return true
		end
	end
	return false
end
local function done()
	preview.advance(0.05)
	print("LOOP PASS " .. step)
end

local spawn = C.lobbySpawn()
C.place(me, spawn)
C.settle(0.8)
if step == "spawn" then
	look(eyeOf() + spawn.LookVector * 30 + Vector3.new(0, -1.2, 0))
	C.settle(0.4)
	if hudText("TABLE") then
		fail("table card in the lobby")
	end
	return done()
end

local w = C.watchMatch()
local init = C.startSolo(w)
local PileView = preview.client("PileView")
local Reticle = preview.client("Reticle")
local center: Vector3 = init.Center
local tablePos
for _, t in ipairs(init.Tables or {}) do
	if t.Owner == me.UserId then
		tablePos = t.Position
	end
end
local function flat(p: Vector3)
	return Vector3.new(p.X, center.Y, p.Z)
end
if step == "countdown" then
	preview.advance(0.8)
	look(eyeOf() + Vector3.new(0, -0.3, 0) + (center - eyeOf()).Unit * 30)
	return done()
end
C.waitPhase(w, "Searching", 6)
C.settle(0.4)
local function standAtPile()
	local dir = (Vector3.new(tablePos.X - center.X, 0, tablePos.Z - center.Z)).Unit
	local tier = Config.Tiers[init.Tier]
	local wanted = math.max(1, math.ceil(init.Rocks / 2.2))
	local rEff = math.min(tier.Radius, tier.RockSize * math.sqrt(wanted / 3.4) + tier.RockSize * 0.5)
	face(center + dir * (rEff + 2.4), center)
	C.settle(0.3)
end
local function aimAtARock(): boolean
	local base = Vector3.new(center.X, center.Y + 1.2, center.Z)
	for dy = 0, 6 do
		for _, dx in ipairs({ 0, -1.5, 1.5, -3, 3, -4.5, 4.5, -6, 6 }) do
			local perp = (base - eyeOf()):Cross(Vector3.yAxis).Unit
			look(base + perp * dx + Vector3.new(0, -dy * 0.6, 0))
			preview.advance(0.12)
			local ctx = PileView.context(true)
			if ctx.Id == "pickup" and PileView.selectedId() ~= nil then
				return true
			end
		end
	end
	return false
end
local function hold(seconds: number)
	PileView.holdBegin()
	preview.advance(seconds)
	PileView.holdEnd()
end
local function pickN(n: number)
	for _ = 1, n do
		if not aimAtARock() then
			fail("no rock under the reticle")
			return
		end
		hold(0.06)
		preview.advance(Config.Carry.PickupInterval + 0.15)
	end
end
standAtPile()
if step == "aim" then
	if not aimAtARock() or Reticle.Current.State ~= "eligible" then
		fail("reticle " .. tostring(Reticle.Current.State))
	end
	C.settle(0.3)
	return done()
end
local cap = Config.Carry.Capacity
if step == "glimpse" then
	pickN(3)
	C.settle(0.9)
	look(eyeOf() + (center - eyeOf()).Unit * 20 + Vector3.new(0, -2.5, 0))
	if not Workspace:FindFirstChild("CT_Rocks_Glimpse") then
		fail("no basket lip with rocks carried")
	end
	return done()
end
pickN(cap)
C.settle(0.6)
if step == "full" then
	aimAtARock()
	look(Vector3.new(center.X, center.Y + 1.4, center.Z))
	C.settle(0.4)
	if PileView.context(true).Id == "pickup" then
		fail("basket full but a rock is still pickable")
	end
	return done()
end
local p = flat(tablePos)
local stand = p + (flat(center) - p).Unit * 3.2
face(stand, p)
C.settle(0.5)
hold(0.1) -- DEPOSIT
if step == "deposit" then
	C.settle(0.5)
	look(p + Vector3.new(0, 3.4, 0))
	if PileView.context(true).Id ~= "crush" then
		fail("ctx " .. PileView.context(true).Id)
	end
	return done()
end
if step == "machine" then
	-- the deposited queue runs on the machine while the player walks back to the pile
	C.settle(tonumber(preview.args.t) or 1.2)
	look(p + Vector3.new(0, 3.2, 0))
	return done()
end
C.settle(0.9)
PileView.holdBegin() -- HOLD TO CRUSH
if step == "crack" then
	preview.advance(tonumber(preview.args.t) or 0.3)
	look(p + Vector3.new(0, 3.4, 0))
	return done()
end
if step == "output" then
	local t = 0
	while t < 12 and not hudText("MATERIAL DISCOVERED") do
		preview.advance(0.1)
		t += 0.1
	end
	look(p + Vector3.new(0, 3.4, 0))
	if not hudText("MATERIAL DISCOVERED") then
		fail("no material notice after the first rocks")
	end
	return done()
end
PileView.holdEnd()
local found = C.crackUntilFound(w, { me })
if not found then
	fail("target not found")
end
if step == "reveal" then
	C.waitPhase(w, "Reveal", 8)
	preview.advance(math.max(0.05, (w.at.Reveal or preview.now()) + (tonumber(preview.args.at) or 1.8) - preview.now()))
	-- the player stands at the own table where the geode opens on the plate
	face(stand, p)
	look(p + Vector3.new(0, 3.4, 0))
	preview.advance(0.05)
	return done()
end
C.waitPhase(w, "Results", 15)
C.settle(6)
if step == "results" then
	C.followCamera(16, 8)
	return done()
end
if step == "rematch" then
	local round0 = w.last.Init.Round
	w.last.Init = nil
	C.fireServer("MatchAction", "StartRematch")
	for _ = 1, 40 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
	local init2 = w.last.Init
	C.waitPhase(w, "Searching", 8)
	C.settle(0.6)
	local CM = preview.client("CameraMode")
	if not init2 or init2.Round == round0 then
		fail("no new round after StartRematch")
	elseif hudText("RESULTS") or hudText("PLAY AGAIN") or Workspace:FindFirstChild("CT_Rocks_Glimpse") then
		fail("results card or basket model left over: results=" .. tostring(hudText("RESULTS")) .. " again=" .. tostring(hudText("PLAY AGAIN")) .. " glimpse=" .. tostring(Workspace:FindFirstChild("CT_Rocks_Glimpse")))
	elseif not CM.firstPerson() or CM.cursorFree() or cam.CameraType == Enum.CameraType.Scriptable then
		fail("camera or cursor not back in first person")
	end
	local c2 = {}
	for _, t in ipairs(init2 and init2.Tables or {}) do
		if t.Owner == me.UserId then
			c2 = t
		end
	end
	if c2.Position then
		face(flat(c2.Position) + (flat(center) - flat(c2.Position)).Unit * 3.2, flat(c2.Position))
		C.settle(0.4)
		look(flat(c2.Position) + Vector3.new(0, 3.4, 0))
	end
	return done()
end
C.fireServer("MatchAction", "Return")
C.settle(3)
local inv = s.Profiles.get(me).InventoryGeodes
local won = inv[#inv]
if step == "lobby" or step == "hud" then
	C.place(me, spawn)
	C.settle(0.6)
	C.followCamera(12, 5) -- third person in the lobby (docs/m11/CAMERA_SPAWN_FIX.md)
	C.settle(0.4)
	local CM = preview.client("CameraMode")
	if hudText("TABLE") or hudText("FIND THE GEODE") or hudText("BASKET") or CM.cursorFree() then
		fail("stale hunt HUD or cursor after return: table=" .. tostring(hudText("TABLE")) .. " find=" .. tostring(hudText("FIND THE GEODE")) .. " basket=" .. tostring(hudText("BASKET")) .. " cursor=" .. tostring(CM.cursorFree()))
	elseif CM.firstPerson() or me.CameraMode ~= Enum.CameraMode.Classic or cam.CameraType == Enum.CameraType.Scriptable or Workspace:FindFirstChild("CT_Rocks_Glimpse") then -- the lobby is third person (docs/m11)
		fail("lobby not back in third person, cinematic camera or basket model left after the reveal and return: mode=" .. tostring(me.CameraMode))
	elseif (me.Character:FindFirstChild("Head") :: BasePart).LocalTransparencyModifier > 0.01 then
		fail("the own head stayed hidden after the hunt (first-person hiding not undone)")
	end
	return done()
end
if not won then
	fail("no specimen in the inventory")
	return
end
if step == "collection" then
	C.tap("^COLLECTION$")
	C.settle(0.5)
	local cards = preview.findGui(function(obj)
		return obj:IsA("GuiButton") and obj:FindFirstChildOfClass("ViewportFrame") ~= nil
	end)
	if cards[1] then
		preview.click(cards[1])
		C.settle(0.4)
	end
	return done()
end
-- cabinet: place through the real CollectionAction, then stand at the owner cabinet
C.fireServer("CollectionAction", "Display", won.Id, true)
C.settle(1.0)
local gallery = C.server("GalleryService")
if gallery then
	gallery.render(me)
end
C.settle(0.8)
-- stand 6.5 studs in front of the player's own pocket (wherever the lobby put it), looking at its shelves
local idx = me:GetAttribute("Alcove") or 1
local floorPart = Workspace.CT_Rocks_Lobby.CT_Rocks_Gallery:FindFirstChild("CT_Rocks_Alcove_" .. tostring(idx)).Floor
local fcf = floorPart.CFrame
local feet = (fcf * CFrame.new(0, 0, 6.5)).Position
C.place(me, CFrame.lookAt(feet, Vector3.new(fcf.Position.X, feet.Y, fcf.Position.Z)))
C.settle(0.4)
look(fcf.Position + Vector3.new(0, 4.2, 0))
if #s.Profiles.get(me).DisplayAssignments ~= 1 then
	fail("not placed")
end
return done()
