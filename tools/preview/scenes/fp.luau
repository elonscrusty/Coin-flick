-- fp: first-person acceptance pictures (docs/m6/FIRST_PERSON.md). The camera sits at the avatar's eye and looks
-- where the player would look, through the real client: CameraMode, Reticle, PileView's camera-centre ray,
-- CarryGlimpse and the HUD. The mock has no PlayerModule, so the scene sets the camera CFrame itself (the
-- real game lets Roblox's LockFirstPerson camera do that). Nothing here is a Studio test.
--   --set view=lobby    the lobby spawn: THIRD PERSON (owner decision 2026-10-10, docs/m11/CAMERA_SPAWN_FIX.md): Classic
--                       camera behind the avatar at the lobby zoom, kept inside the lodge room by CameraGuard, no reticle
--   --set view=aim      at the pile, reticle on a pickable rock (eligible ring, one outlined rock)
--   --set view=glimpse  three rocks picked up through the reticle: the basket lip at the lower edge
--   --set tier=Volcanic (any view) multi-hit rocks so the crack stages show
--   --set view=table    at the own table after DEPOSIT: tray, plate and the hammer mid stroke (--set t=S)
--   --set view=sell     at a sell hopper with rubble in the bag
--   --set view=full     basket full, reticle on a rock: the "Basket full" reason
--   --set view=menu     a panel open (SHOP) in the lobby: input suspended, no reticle; closing gives the camera back
--   --set view=peek     in a hunt, the free-cursor key (Left Alt) held: cursor free, no reticle; released: locked again
--   --set view=explore  open ground, nothing aimed: neutral dot, no message
local C = lib("ctr")
local view = preview.args.view or "aim"
local lobbyOnly = view == "lobby" or view == "menu"
local s = C.boot({
	profile = function(data)
		data.Cash = 900
		data.TutorialStep = 1
		data.CapacityTier = 3
		if preview.args.tier then
			data.UnlockedTiers[preview.args.tier] = true
		end
		if view == "sell" then
			data.RubbleByTier = { Gravel = 14 }
		end
	end,
})
local Workspace = game:GetService("Workspace")
local me = s.me
local Config = s.Config
local cam = Workspace.CurrentCamera
local function eyeOf(): Vector3
	local head = me.Character and me.Character:FindFirstChild("Head")
	return (head :: BasePart).Position + Vector3.new(0, 0.15, 0)
end
local function look(at: Vector3)
	cam.CFrame = CFrame.lookAt(eyeOf(), at)
	cam.FieldOfView = Config.Camera.Fov
end
local function face(pos: Vector3, at: Vector3)
	C.place(me, CFrame.lookAt(Vector3.new(pos.X, pos.Y, pos.Z), Vector3.new(at.X, pos.Y, at.Z)))
end

if lobbyOnly then
	local spawn = C.lobbySpawn()
	C.place(me, spawn)
	C.settle(0.8)
	-- Roblox's Classic camera (the mock has no PlayerModule): behind and above the avatar at about the default
	-- start zoom; CameraGuard then pulls it in front of the lodge's front wall, like it does in the game
	C.followCamera(12, 5)
	preview.advance(0.05)
	do
		local CM = preview.client("CameraMode")
		local L = Config.Lodge
		local cp = cam.CFrame.Position
		print(("[fp] lobby camera mode %s zoom %s..%s fp=%s camera %s"):format(tostring(me.CameraMode), tostring(me.CameraMinZoomDistance), tostring(me.CameraMaxZoomDistance), tostring(CM.firstPerson()), tostring(cp)))
		if me.CameraMode ~= Enum.CameraMode.Classic or CM.firstPerson() then
			print("[FAIL] fp " .. view .. ": the lobby is not third person (" .. tostring(me.CameraMode) .. ")")
			return
		end
		if me.CameraMinZoomDistance ~= Config.Camera.Lobby.MinZoom or me.CameraMaxZoomDistance ~= Config.Camera.Lobby.MaxZoom then
			print("[FAIL] fp " .. view .. ": lobby zoom " .. tostring(me.CameraMinZoomDistance) .. ".." .. tostring(me.CameraMaxZoomDistance))
			return
		end
		if not (cp.X > L.MinX and cp.X < L.MaxX and cp.Z > L.MinZ and cp.Z < L.MaxZ and cp.Y > L.FloorY and cp.Y < L.CeilingY) then
			print("[FAIL] fp " .. view .. ": the third-person camera left the lodge room: " .. tostring(cp))
			return
		end
		local head = me.Character:FindFirstChild("Head") :: BasePart
		if head.LocalTransparencyModifier > 0.01 then
			print("[FAIL] fp " .. view .. ": the own head is hidden in third person")
			return
		end
	end
	if view == "menu" then
		C.tap("^SHOP$")
		C.settle(0.6)
	end
	C.settle(0.4)
	local st = preview.client("Reticle").Current.State
	print("[fp] reticle " .. tostring(st))
	local want = "hidden" -- third person: no reticle in the lobby (normal prompts and the cursor instead)
	if st ~= want then
		print("[FAIL] fp " .. view .. ": reticle " .. tostring(st) .. ", expected " .. want)
		return
	end
	if view == "menu" and preview.args.check ~= "off" then
		-- the modal owns the screen: move/look input suspended, rail + resources + tool chip quiet; both come back on close
		local CM = preview.client("CameraMode")
		local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		local left = pg:FindFirstChild("CrackTheRocks"):FindFirstChild("Left")
		if not CM.suspendedInput() or left.Visible then
			print("[FAIL] fp menu: suspended=" .. tostring(CM.suspendedInput()) .. " left visible=" .. tostring(left.Visible))
			return
		end
		local hits = preview.findGui(function(obj)
			return obj.Name == "Close" and obj:IsA("GuiButton")
		end)
		preview.click(hits[1])
		C.settle(0.6)
		if CM.suspendedInput() or not left.Visible or CM.cursorFree() then
			print("[FAIL] fp menu close: suspended=" .. tostring(CM.suspendedInput()) .. " left visible=" .. tostring(left.Visible))
			return
		end
	end
	print("FP PASS " .. view)
	return
end

local w = C.watchMatch()
if preview.args.tier then
	C.fireServer("PartyAction", "Create")
	preview.advance(0.3)
	C.fireServer("PartyAction", "Tier", preview.args.tier)
	preview.advance(0.3)
end
local init = C.startSolo(w)
C.waitPhase(w, "Searching", 6)
C.settle(0.4)
do
	-- the hunt switched the view to first person once
	local CM = preview.client("CameraMode")
	if me.CameraMode ~= Enum.CameraMode.LockFirstPerson or not CM.firstPerson() or me.CameraMaxZoomDistance > 0.5 then
		print("[FAIL] fp " .. view .. ": the hunt is not first person (" .. tostring(me.CameraMode) .. ")")
		return
	end
end
local PileView = preview.client("PileView")
local Reticle = preview.client("Reticle")
local center: Vector3 = init.Center
local tablePos
for _, t in ipairs(init.Tables or {}) do
	if t.Owner == me.UserId then
		tablePos = t.Position
	end
end
local function floorPos(p: Vector3)
	return Vector3.new(p.X, center.Y, p.Z)
end
local function standAtPile()
	local dir = (Vector3.new(tablePos.X - center.X, 0, tablePos.Z - center.Z)).Unit
	local tier = Config.Tiers[init.Tier]
	local wanted = math.max(1, math.ceil(init.Rocks / 2.2))
	local rEff = math.min(tier.Radius, tier.RockSize * math.sqrt(wanted / 3.4) + tier.RockSize * 0.5)
	local pos = center + dir * (rEff + 2.4)
	face(Vector3.new(pos.X, center.Y, pos.Z), center)
	C.settle(0.3)
end
-- Sweeps the view over the pile until the reticle is on a pickable rock (the client's own ray decides).
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
			print("[fp] no rock found under the reticle")
			return
		end
		hold(0.06)
		preview.advance(Config.Carry.PickupInterval + 0.15)
	end
end

if view == "peek" then
	standAtPile()
	look(eyeOf() + Vector3.new(0, -0.2, 0) + (eyeOf() - center).Unit * 30)
	C.settle(0.4)
	local CM = preview.client("CameraMode")
	local UIS = game:GetService("UserInputService")
	local modal = me:WaitForChild("PlayerGui"):FindFirstChild("CT_CameraMode")
	local btn = modal and modal:FindFirstChild("FreeCursor") :: TextButton?
	local held = {}
	preview.key(Enum.KeyCode.LeftAlt, 0.2, function()
		held.free = CM.cursorFree()
		held.reticle = Reticle.Current.State
		held.icon = UIS.MouseIconEnabled
		held.behavior = UIS.MouseBehavior
		held.modal = btn ~= nil and btn.Visible and btn.Modal and btn.AbsolutePosition.X >= 0 and btn.AbsolutePosition.Y >= 0
		held.act = CM.mayAct()
	end)
	C.settle(0.5)
	print(("[fp] peek held: free=%s reticle=%s icon=%s behavior=%s modal=%s act=%s; released: free=%s reticle=%s"):format(
		tostring(held.free), tostring(held.reticle), tostring(held.icon), tostring(held.behavior), tostring(held.modal), tostring(held.act),
		tostring(CM.cursorFree()), tostring(Reticle.Current.State)))
	if not held.free or held.reticle ~= "hidden" or not held.icon or held.behavior ~= Enum.MouseBehavior.Default or not held.modal or held.act then
		print("[FAIL] fp peek: holding Left Alt did not free the cursor on screen")
		return
	end
	if CM.cursorFree() or Reticle.Current.State == "hidden" or UIS.MouseIconEnabled or (btn and btn.Visible) then
		print("[FAIL] fp peek: releasing Left Alt did not lock the view again")
		return
	end
	print("FP PASS peek")
	return
elseif view == "explore" then
	standAtPile()
	look(eyeOf() + Vector3.new(0, -0.2, 0) + (eyeOf() - center).Unit * 30)
	C.settle(0.4)
elseif view == "aim" then
	standAtPile()
	print("[fp] aimed: " .. tostring(aimAtARock()))
	C.settle(0.3)
elseif view == "glimpse" then
	standAtPile()
	pickN(tonumber(preview.args.n) or (Config.Carry.Capacity - 1)) -- basket not full, so the context stays "pickup"
	C.settle(0.9)
	-- step back and aside from the 150-egg mound (eggs fill every view near its edge), then look over the pile: neutral
	local away = Vector3.new(eyeOf().X - center.X, 0, eyeOf().Z - center.Z).Unit
	local spot = Vector3.new(eyeOf().X, center.Y, eyeOf().Z) + away * 4 + Vector3.new(-away.Z, 0, away.X) * 8 -- sideways, clear of the nest
	face(spot, center)
	C.settle(0.3)
	look(eyeOf() + (center - eyeOf()).Unit * 20 + Vector3.new(0, 4, 0))
elseif view == "full" then
	standAtPile()
	pickN(Config.Carry.Capacity)
	C.settle(0.6)
	aimAtARock()
	-- the context only reports a target when the basket has room for it; look at the pile instead
	look(Vector3.new(center.X, center.Y + 1.4, center.Z))
	C.settle(0.4)
elseif view == "table" then
	standAtPile()
	pickN(Config.Carry.Capacity)
	C.settle(0.6)
	local p = floorPos(tablePos)
	local c = floorPos(center)
	-- the work spot is the table's own yellow Stand pad (not a guess): the model carries it as an attachment
	local standAt = 3.2
	local own = preview.client("StationView").ownModel()
	local sa = own and own:FindFirstChild("Stand", true)
	local att = sa and sa:FindFirstChildWhichIsA("Attachment")
	if att then
		standAt = (Vector3.new(att.WorldPosition.X, 0, att.WorldPosition.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
	end
	if preview.args.dist then
		standAt = tonumber(preview.args.dist) :: number
	end
	print("[fp] work spot distance " .. tostring(standAt))
	local stand = p + (c - p).Unit * standAt
	face(stand, p)
	C.settle(0.5)
	hold(0.1) -- DEPOSIT
	C.settle(0.9)
	if preview.args.t == "idle" then
		preview.advance(1.4) -- rock on the plate, no stroke yet
	else
		PileView.holdBegin() -- HOLD TO CRUSH
		preview.advance(tonumber(preview.args.t) or 0.55)
	end
	look(p + Vector3.new(0, 3.4, 0))
elseif view == "sell" then
	local hopper
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("Hopper") and d:FindFirstChild("Body") and (d.Body.Position - center).Magnitude < 120 then
			hopper = d.Body
			break
		end
	end
	if hopper then
		local from = Vector3.new(hopper.Position.X, center.Y, hopper.Position.Z)
		local dir = (Vector3.new(center.X, 0, center.Z) - Vector3.new(from.X, 0, from.Z)).Unit
		face(from + dir * 6, from)
		C.settle(0.6)
		look(hopper.Position)
		C.settle(0.4)
	else
		print("[fp] no hopper found")
	end
end
preview.advance(0.05) -- one more frame with the final camera
local ctx = PileView.context(true)
print("[fp] view=" .. view .. " ctx=" .. ctx.Id .. " reticle=" .. tostring(Reticle.Current.State) .. " reason=" .. tostring(Reticle.Current.Reason))
do
	local g = Workspace:FindFirstChild("CT_Rocks_Glimpse")
	print("[fp] glimpse model: " .. tostring(g) .. (g and (" at " .. tostring((g :: Model):GetPivot().Position) .. " cam " .. tostring(cam.CFrame.Position)) or ""))
end
do
	local ch = me.Character
	for _, n in ipairs({ "RightUpperArm", "RightLowerArm", "RightHand", "Head", "UpperTorso" }) do
		local p = ch and ch:FindFirstChild(n)
		print("[fp] " .. n .. " ltm " .. tostring(p and (p :: BasePart).LocalTransparencyModifier) .. " dist " .. tostring(p and ((p :: BasePart).Position - cam.CFrame.Position).Magnitude))
	end
end
do
	local want = ({ aim = { "pickup", "eligible" }, glimpse = { "pickup", "neutral" }, table = { "crush", "eligible" }, sell = { "sell", "eligible" }, explore = { "none", "neutral" } })[view]
	local g = Workspace:FindFirstChild("CT_Rocks_Glimpse")
	-- glimpse is about the basket lip; off the big mound the context may drop to "none", the reticle must stay neutral
	local ctxOk = ctx.Id == (want and want[1]) or (view == "glimpse" and ctx.Id == "none")
	if want and (not ctxOk or Reticle.Current.State ~= want[2]) then
		print("[FAIL] fp " .. view .. ": ctx " .. ctx.Id .. " reticle " .. tostring(Reticle.Current.State))
	elseif view == "glimpse" and not g then
		print("[FAIL] fp glimpse: no basket lip with eggs carried")
	elseif view == "aim" and g then
		print("[FAIL] fp aim: a basket lip with an empty basket")
	else
		print("FP PASS " .. view)
	end
end
