-- rocks-views: acceptance pictures for the V3 client (pile, basket, tray, plate, HUD, tutorial).
-- Everything runs through the real client: the HUD button logic (PileView.holdBegin) sends the real
-- RockAction remote, the real server answers, the real StationView / CarryView draw it.
--   --set view=A   pickup: the exact rock arcs from the pile into the basket (mid flight)
--   --set view=B   basket 5/5: TAKE TO TABLE with the arrow to the own table
--   --set view=C   at the own table: rocks deposited and queued, hammer swinging at the plate
--   --set view=D   at the own table, nothing yet: COLLECT ROCKS (arrow to the pile)
--   --set view=G   machine running at the table while the player is back at the pile
--   --set view=H   the geode rock finished: shell opening on the plate (mid opening)
--   --set view=L --set step=pickup|carry|deposit|crush|rubble   tutorial hint in order (practice pile)
--   --set view=W   four stations, everyone busy, wide view
--   --set view=pile   the pile only (silhouette check), --set cam=close for a closer shot
--   --set cam=machine   view G: camera on the machine bay behind the own table
--   --set machine=AutoCracker|HydraulicPress|IndustrialCrusher   machine for view G
--   --set tool=Hammer|SteelHammer|Jackhammer   handheld for view C
local C = lib("ctr")
local view = preview.args.view or "A"
local machine = preview.args.machine or "AutoCracker"
local tool = preview.args.tool or "Hammer"
local party = view == "W"
local others = if party then { { "Ava", 2 }, { "Ben", 3 }, { "Cleo", 4 } } else {}
local s = C.boot({
	others = others,
	profile = function(data)
		data.Cash = 900
		data.TutorialStep = if view == "L" then 0 else 1
		data.CapacityTier = 3
		if view == "G" or view == "M" then
			data.EquipmentOwned[machine] = true
			data.InstalledMachine = machine
		end
		if view == "C" and tool ~= "Hammer" then
			data.EquipmentOwned[tool] = true
			data.EquippedHandheld = tool
		end
		if view == "L" then
			local ob = data.Onboard
			local step = preview.args.step or "pickup"
			if step == "rubble" then
				ob.Started, ob.PickedUp, ob.Deposited, ob.Cracked = true, true, true, true
			end
		end
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
if party then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	local pt = s.PartyService.of(s.me.UserId)
	for _, p in ipairs(s.others) do
		C.fireServer("PartyAction", "Invite", p.UserId)
		preview.advance(0.3)
		preview.fireServerAs(p, "PartyAction", "Accept", pt and pt.Id)
		preview.advance(0.3)
		table.insert(players, p)
	end
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
local init = w.last.Init
C.waitPhase(w, "Searching", 6)
C.settle(0.4)
local PileView = preview.client("PileView")
local Config = s.Config
local center: Vector3 = init.Center
local me = s.me

local tablePos
for _, t in ipairs(init.Tables or {}) do
	if t.Owner == me.UserId then
		tablePos = t.Position
	end
end
-- Portrait phones are narrow: pull every camera back so the same picture fits.
local function portraitScale(): number
	local cam = game:GetService("Workspace").CurrentCamera
	local vs = cam.ViewportSize
	return if vs.Y > vs.X then 1.7 else 1
end
local function camAt(target: Vector3, offset: Vector3, fov: number?)
	C.cameraAt(target, offset * portraitScale(), fov)
end
local function floorPos(p: Vector3)
	return Vector3.new(p.X, center.Y, p.Z)
end
local function standAtPile()
	-- at the mound edge on the side facing the own table's opposite, looking at the pile
	local dir = if tablePos then (Vector3.new(tablePos.X - center.X, 0, tablePos.Z - center.Z)).Unit else Vector3.new(0, 0, 1)
	-- the mound's footprint shrinks for small piles (Pile.new): stand just outside its edge
	local tier = Config.Tiers[init.Tier]
	local wanted = math.max(1, math.ceil(init.Rocks / 2.2))
	local rEff = math.min(tier.Radius, tier.RockSize * math.sqrt(wanted / 3.4) + tier.RockSize * 0.5)
	local pos = center + dir * (rEff + 2.6)
	C.place(me, CFrame.lookAt(Vector3.new(pos.X, center.Y, pos.Z), Vector3.new(center.X, center.Y, center.Z)))
	return pos
end
local function standAtTable()
	local p = floorPos(tablePos)
	local c = floorPos(center)
	local pos = p + (c - p).Unit * 3.4
	C.place(me, CFrame.lookAt(pos, p))
end
local function hold(seconds: number)
	PileView.holdBegin()
	preview.advance(seconds)
	PileView.holdEnd()
end
local function pickN(n: number)
	for _ = 1, n do
		hold(0.06)
		preview.advance(Config.Carry.PickupInterval + 0.1)
	end
end
local function camBehind(dist: number, height: number)
	C.followCamera(dist * portraitScale(), height * portraitScale())
end
-- Camera off the avatar's right shoulder, looking at its chest (shows the basket and the rocks).
local function camSide(dist: number, height: number, back: number?)
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local cf = root.CFrame
	local target = cf.Position + Vector3.new(0, 1.2, 0)
	camAt(target, cf.RightVector * dist - cf.LookVector * (back or 3) + Vector3.new(0, height, 0), 55)
end

if view == "pile" then
	local dir = Vector3.new(0, 0, 1)
	local pos = center + dir * 20
	C.place(me, CFrame.lookAt(Vector3.new(pos.X, center.Y, pos.Z), Vector3.new(center.X, center.Y, center.Z)))
	C.settle(0.6)
	if preview.args.cam == "close" then
		camAt(center + Vector3.new(0, 3, 0), Vector3.new(0, 7, 15), 55)
	else
		camAt(center + Vector3.new(0, 1, 0), Vector3.new(0, 11, 20), 60)
	end
elseif view == "A" then
	standAtPile()
	C.settle(0.4)
	pickN(1)
	hold(0.06) -- second pickup: the first one has landed, the second is in the air
	preview.advance(0.22)
	camSide(9, 3.5, 4)
elseif view == "B" then
	standAtPile()
	C.settle(0.4)
	pickN(5)
	C.settle(0.8)
	camBehind(14, 7)
elseif view == "C" then
	standAtPile()
	C.settle(0.3)
	pickN(5)
	C.settle(0.8)
	standAtTable()
	C.settle(0.5)
	hold(0.1) -- DEPOSIT ROCKS
	C.settle(0.9)
	PileView.holdBegin() -- HOLD TO CRUSH
	preview.advance(tonumber(preview.args.t) or 0.72)
	local dir = (floorPos(center) - floorPos(tablePos)).Unit
	local perp = dir:Cross(Vector3.new(0, 1, 0))
	local camMode = preview.args.cam or "over"
	if camMode == "side" then
		camAt(floorPos(tablePos) + Vector3.new(0, 3.6, 0), dir * 5.5 + perp * 6.5 + Vector3.new(0, 5.2, 0), 55)
	else
		-- over the avatar's left shoulder, looking down at the plate
		camAt(floorPos(tablePos) + Vector3.new(0, 3.2, 0), dir * 12.5 - perp * 3.2 + Vector3.new(0, 8, 0), 55)
	end
elseif view == "D" then
	standAtTable()
	C.settle(0.6)
	camBehind(13, 6)
elseif view == "G" then
	standAtPile()
	C.settle(0.3)
	pickN(5)
	C.settle(0.8)
	standAtTable()
	C.settle(0.4)
	hold(0.1)
	C.settle(0.6)
	standAtPile()
	C.settle(tonumber(preview.args.t) or 0.9)
	if preview.args.cam == "table" then
		local dir = (floorPos(center) - floorPos(tablePos)).Unit
		local perp = dir:Cross(Vector3.new(0, 1, 0))
		camAt(floorPos(tablePos) + Vector3.new(0, 3.6, 2), dir * 4 - perp * 8 + Vector3.new(0, 6, 0), 62)
	elseif preview.args.cam == "machine" then
		-- the machine bay behind the own table (kit machine check)
		local dir = (floorPos(center) - floorPos(tablePos)).Unit
		local perp = dir:Cross(Vector3.new(0, 1, 0))
		camAt(floorPos(tablePos) - dir * 9 + Vector3.new(0, 2.5, 0), dir * 11 + perp * 9 + Vector3.new(0, 9, 0), 55)
	else
		camBehind(15, 8)
	end
elseif view == "M" then
	-- machine close-up at a chosen moment: the machine is paused while 10 rocks are loaded into the tray, then
	-- started; `t` = seconds it has been running (every machine cycle is short, so pick t to catch a stroke).
	--   --set machine=...  --set t=S  --set cam=front|side|table|wide  --set loads=N (default 2 x 5 rocks)
	C.fireServer("ShopAction", "ToggleMachine")
	C.settle(0.3)
	for _ = 1, tonumber(preview.args.loads) or 2 do
		standAtPile()
		C.settle(0.2)
		pickN(5)
		C.settle(0.4)
		standAtTable()
		C.settle(0.3)
		hold(0.1)
		C.settle(0.4)
	end
	C.fireServer("ShopAction", "ToggleMachine")
	preview.advance(tonumber(preview.args.t) or 0.3, 30)
	local dir = (floorPos(center) - floorPos(tablePos)).Unit
	local perp = dir:Cross(Vector3.new(0, 1, 0))
	local base = floorPos(tablePos) - dir * 7.4 -- the machine bay behind the table
	local cam = preview.args.cam or "front"
	if preview.args.flip == "1" then
		perp = -perp
	end
	if cam == "front" then
		camAt(base + Vector3.new(0, 2.2, 0), dir * 9 + perp * 6 + Vector3.new(0, 8, 0), 52)
	elseif cam == "side" then
		camAt(base + Vector3.new(0, 2.2, 0), perp * 14 + Vector3.new(0, 4, 0), 48)
	elseif cam == "wide" then
		camAt(floorPos(tablePos) - dir * 3 + Vector3.new(0, 2, 0), dir * 14 + perp * 10 + Vector3.new(0, 9, 0), 55)
	else
		camAt(floorPos(tablePos) + Vector3.new(0, 3.6, 2), dir * 4 - perp * 8 + Vector3.new(0, 6, 0), 62)
	end
elseif view == "H" then
	-- everything through the loop until the geode rock is crushed, then stop in the middle of the opening
	local found = false
	local stampT = nil
	C.crackUntilFound(w, players, 400, {
		onStep = function()
			if w.last.Found and not stampT then
				stampT = preview.now()
			end
		end,
	})
	local at = tonumber(preview.args.t) or 1.9
	if stampT then
		preview.advance(math.max(0.05, stampT + at - preview.now()))
	end
	found = w.last.Found ~= nil
	preview.log("geode found: " .. tostring(found))
	local sp = preview.client("StationView")
	local pp = sp.platePosition(me.UserId)
	local tp = sp.tablePosition(me.UserId)
	if pp and tp then
		local dir = (floorPos(center) - floorPos(tp)).Unit
		local perp = dir:Cross(Vector3.new(0, 1, 0))
		if preview.args.cam == "front" then
			-- the player's own view: from the operating side (pile side of the table), slightly above
			camAt(pp + Vector3.new(0, 0.9, 0), dir * (if preview.args.flip == "1" then -5.2 else 5.2) + Vector3.new(0, 3.4, 0), 50)
		elseif preview.args.cam == "close" then
			camAt(pp + Vector3.new(0, 1.0, 0), dir * 3.2 + Vector3.new(0, 1.9, 0), 46)
		else
			camAt(pp + Vector3.new(0, 0.7, 0), dir * 3.4 + perp * 5.2 + Vector3.new(0, 3.2, 0), 52)
		end
	end
elseif view == "L" then
	local step = preview.args.step or "pickup"
	if step == "pickup" then
		standAtPile()
		C.settle(0.3)
	elseif step == "carry" then
		standAtPile()
		C.settle(0.3)
		pickN(3)
		C.settle(0.8)
	elseif step == "deposit" then
		standAtPile()
		pickN(3)
		C.settle(0.6)
		standAtTable()
		C.settle(0.6)
	elseif step == "crush" then
		standAtPile()
		pickN(3)
		C.settle(0.6)
		standAtTable()
		C.settle(0.4)
		hold(0.1)
		C.settle(1.0)
	else -- rubble: first rubble already earned earlier in the practice round
		standAtPile()
		pickN(2)
		C.settle(0.6)
		standAtTable()
		C.settle(0.4)
		hold(0.1)
		C.settle(0.6)
		PileView.holdBegin()
		preview.advance(1.4)
		PileView.holdEnd()
		C.settle(0.8)
	end
	camBehind(14, 7)
elseif view == "W" then
	-- all four hunt for a while, then a high view of the four tables and the shared pile
	C.crackUntilFound(w, players, 400, { stopAfterDone = 6 })
	C.settle(0.6)
	camAt(center, Vector3.new(0, 38, 46), 62)
else
	camBehind(14, 7)
end
do
	local tl = me.Character and me.Character:FindFirstChild("CT_Rocks_HeldTool")
	preview.log("held tool: " .. tostring(tl) .. (tl and (" part0 transparency " .. tostring((tl:FindFirstChildWhichIsA("BasePart") :: any).Transparency)) or ""))
end
