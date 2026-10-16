--!strict
-- Lobby map hooks (shared/MapNames, docs/MAP_HOOKS.md). The owner builds the lobby by hand in Studio
-- (Workspace.FTP_Lobby); this module finds the named pieces and makes sure each one carries what the game logic needs
-- (attributes, attachments, prompts, text labels), adding anything missing. Every lookup is guarded: a missing piece is
-- skipped with one warn, never an error. It runs on the procedural fallback park too (which already has everything),
-- so both maps go through the same checks.
--
--   MapHooks.root()                    -> the hand-built map Model (first of MapNames.Roots under Workspace) or nil
--   MapHooks.ensure(map, lobby, adopt) -> fixes up the hooks under `map`; `lobby` is the code's CT_Rocks_Lobby folder
--                                         (helper parts go there). With `adopt`, also adopts the hand-built plots,
--                                         boards and WHAT'S NEW board and returns { Plots }.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MapNames = require(Shared.MapNames)
local ParkConfig = require(Shared.ParkConfig)
local WhatsNew = require(Shared.WhatsNew)
local KitPlace = require(script.Parent.KitPlace)

local MapHooks = {}

local function warnMissing(what: string)
	warn("[MapHooks] lobby map has no " .. what .. "; that feature is skipped")
end

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function findAny(parent: Instance, names: { string }): Instance?
	for _, n in names do
		local d = parent:FindFirstChild(n, true)
		if d then
			return d
		end
	end
	return nil
end

-- A part for `inst`: itself, a Model's PrimaryPart, else its first part.
local function asPart(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function findPart(parent: Instance, name: string): BasePart?
	return asPart(find(parent, name))
end

-- The highest part (by top face) inside `inst`, skipping signs.
local function topPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	local best: BasePart? = nil
	local bestTop = -math.huge
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= MapNames.BuildingSign and d.Transparency < 1 then
			local top = d.Position.Y + d.Size.Y / 2
			if top > bestTop then
				best, bestTop = d, top
			end
		end
	end
	return best or asPart(inst)
end

-- A TextLabel on the Front face (LookVector side) of `part`, made once.
local function faceLabel(part: BasePart, labelName: string, text: string): TextLabel
	local existing = part:FindFirstChild(labelName, true)
	if existing and existing:IsA("TextLabel") then
		return existing
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = labelName .. "Gui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local t = Instance.new("TextLabel")
	t.Name = labelName
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.fromRGB(255, 244, 220)
	t.TextStrokeTransparency = 0.4
	t.TextScaled = true
	t.Text = text
	t.Parent = gui
	return t
end

-- The first TextLabel inside `inst` with one of `names` (any name when `names` is empty).
local function findLabel(inst: Instance, names: { string }): TextLabel?
	for _, d in inst:GetDescendants() do
		if d:IsA("TextLabel") and (#names == 0 or table.find(names, d.Name)) then
			return d
		end
	end
	return nil
end

local function hasPrompt(inst: Instance): boolean
	return inst:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
end

local function prompt(part: BasePart, name: string, action: string, object: string, dist: number): ProximityPrompt
	local existing = part:FindFirstChildWhichIsA("ProximityPrompt")
	if existing then
		return existing
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = dist
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R
	pp.Parent = part
	return pp
end

function MapHooks.root(): Instance?
	return MapNames.findRoot(Workspace:GetChildren())
end

-- Hunt queue ------------------------------------------------------------------------------------------------------

-- QueuePad1..4: the touch part ("Pad" in a pad Model, or the pad Part itself) gets HuntPortal and PadIndex.
-- PartyService writes the queue text into the first QueueBoard/QueueText it finds; when the map has no QueueBoard an
-- invisible one is made in the code's lobby folder, and its text is copied onto every pad's "Countdown" sign.
local function ensureQueue(map: Instance, lobby: Instance)
	local countdowns: { TextLabel } = {}
	local any = false
	for n = 1, MapNames.QueuePadCount do
		local padInst = find(map, MapNames.queuePad(n))
		local touch = if padInst then (findPart(padInst, MapNames.QueuePadTouch) or asPart(padInst)) else nil
		if touch then
			any = true
			touch:SetAttribute("HuntPortal", true)
			touch:SetAttribute("PadIndex", n)
			touch.CanTouch = true
			-- a flat disc lying in the ground may never overlap a walking avatar: add an invisible touch volume
			-- (a short cylinder over the disc, named HuntPortal so PartyService does not light it as a pad)
			local thin = math.min(touch.Size.X, touch.Size.Y, touch.Size.Z)
			if thin < 2 and not touch:FindFirstChild("HuntPortal") then
				local wide = math.max(touch.Size.X, touch.Size.Y, touch.Size.Z)
				local vol = Instance.new("Part")
				vol.Name = "HuntPortal"
				vol.Shape = Enum.PartType.Cylinder
				vol.Size = Vector3.new(4, wide * 0.9, wide * 0.9)
				vol.CFrame = CFrame.new(touch.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				vol.Transparency = 1
				vol.Anchored = true
				vol.CanCollide = false
				vol.CanQuery = false
				vol.CanTouch = true
				vol.CastShadow = false
				vol:SetAttribute("PadIndex", n)
				vol:SetAttribute("HuntPortal", true)
				vol.Parent = touch
			end
		end
		local cd = if padInst then find(padInst, MapNames.QueueCountdown) else nil
		if cd then
			for _, d in cd:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == MapNames.CountdownText then
					table.insert(countdowns, d) -- front and back
				end
			end
		end
	end
	if not any then
		warnMissing(MapNames.QueuePad .. "1-" .. MapNames.QueuePadCount)
	end
	local board = findPart(map, MapNames.QueueBoard)
	if not board and #countdowns > 0 then
		local hidden = Instance.new("Part")
		hidden.Name = MapNames.QueueBoard
		hidden.Size = Vector3.new(1, 1, 0.1)
		hidden.CFrame = CFrame.new(0, -50, 0)
		hidden.Transparency = 1
		hidden.Anchored = true
		hidden.CanCollide = false
		hidden.CanQuery = false
		hidden.CanTouch = false
		hidden.Parent = lobby
		board = hidden
		local gui = faceLabel(hidden, MapNames.QueueText, "STEP ON TO PLAY").Parent :: SurfaceGui
		gui.Enabled = false
	end
	if not board then
		warnMissing(MapNames.QueueBoard .. " / " .. MapNames.QueueCountdown .. " signs")
		return
	end
	local text = faceLabel(board :: BasePart, MapNames.QueueText, "STEP ON TO PLAY")
	if #countdowns > 0 then
		local last = ""
		local function copy()
			if text.Text ~= last then
				last = text.Text
				for _, l in countdowns do
					l.Text = last
				end
			end
		end
		copy()
		task.spawn(function()
			while text.Parent do
				task.wait(0.25)
				copy()
			end
		end)
	end
end

-- Buildings ------------------------------------------------------------------------------------------------------

-- The hatch stand is only the stage for the public hatch show now (HatchStandView). Coin eggs are sold in the Pet
-- Shop's Eggs tab at the EGG SHOP hut (2026-10-15), so the stand has no "Buy Eggs" prompt; an old one is removed.
local function ensureHatch(map: Instance)
	local inst = find(map, MapNames.HatchStand)
	if not inst then
		warnMissing(MapNames.HatchStand)
		return
	end
	-- already hooked (the fallback park, or a map that set it by hand)
	local stand: BasePart? = if inst:IsA("BasePart") and inst:GetAttribute("HatchStand") == true then inst else nil
	if not stand then
		for _, d in (inst :: Instance):GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
				stand = d
				break
			end
		end
	end
	if not stand then
		stand = topPart(inst)
		if not stand then
			warnMissing(MapNames.HatchStand .. " part")
			return
		end
		stand:SetAttribute("HatchStand", true)
		if not stand:FindFirstChild(MapNames.HatchPoint) then
			local at = Instance.new("Attachment")
			at.Name = MapNames.HatchPoint
			at.Position = Vector3.new(0, stand.Size.Y / 2, 0) -- the top face
			at.Parent = stand
		end
	end
	local old = (stand :: BasePart):FindFirstChild("ShrinePrompt")
	if old then
		old:Destroy()
	end
end

local function ensureTower(map: Instance)
	local entrance = find(map, MapNames.TowerEntrance)
	local door = if entrance and entrance.Name ~= MapNames.TowerPortal then entrance:FindFirstChild(MapNames.TowerPortal, true) else entrance
	door = door or find(map, MapNames.TowerPortal)
	if not door and entrance and entrance:IsA("BasePart") then
		door = entrance -- a single part entrance is its own doorway
	end
	if not door and entrance and entrance:IsA("Model") then
		-- no doorway part: an invisible touch box in the middle of the entrance, standing on its lowest point
		local cf, size = entrance:GetBoundingBox()
		local box = Instance.new("Part")
		box.Name = MapNames.TowerPortal
		box.Size = Vector3.new(math.clamp(size.X * 0.5, 3, 12), 8, math.clamp(size.Z * 0.5, 3, 12))
		box.CFrame = cf * CFrame.new(0, -size.Y / 2 + 4, 0)
		box.Transparency = 1
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box:SetAttribute("CameraIgnore", true)
		box.Parent = entrance
		door = box
	end
	if door and door:IsA("BasePart") then
		door:SetAttribute("TowerPortal", true)
		door.CanTouch = true
	else
		warnMissing(MapNames.TowerEntrance .. " / " .. MapNames.TowerPortal)
	end
end

local function ensureSecretEgg(map: Instance)
	local egg = findPart(map, MapNames.SecretEgg)
	if not egg then
		warnMissing(MapNames.SecretEgg)
		return
	end
	egg:SetAttribute("SecretEgg", true)
	local holder = find(map, MapNames.SecretEgg)
	if holder and holder ~= egg then
		holder:SetAttribute("SecretEgg", true)
	end
	if not (holder and hasPrompt(holder)) then
		local pp = prompt(egg, MapNames.SecretEggPrompt, "Take", "???", 6)
		pp.Name = MapNames.SecretEggPrompt
	end
end

-- EGG SHOP: a (disabled) prompt on its counter / sign; RobuxService enables the first prompt in the hut as the shop.
local function ensureEggShop(map: Instance)
	local shop = find(map, MapNames.EggShop)
	if not shop then
		warnMissing(MapNames.EggShop)
		return
	end
	if hasPrompt(shop) then
		return -- the fallback park's counter prompt, or RobuxService already hooked it
	end
	local anchor = findPart(shop, MapNames.ShopCounter) or findPart(shop, MapNames.BuildingSign) or asPart(shop)
	if anchor then
		local pp = prompt(anchor, "ShopPrompt", "Egg Shop", "EGG SHOP", 12)
		pp.Enabled = false -- RobuxService turns it on (it is the shop's only door)
		pp:SetAttribute("ShopHook", "EggShop")
	end
end

-- WHAT'S NEW: the title and the lines of shared/WhatsNew on the board's front face (or its own TextLabel "Text").
local function ensureWhatsNew(map: Instance)
	local inst = find(map, MapNames.WhatsNewBoard)
	local board = asPart(inst)
	if not inst or not board then
		warnMissing(MapNames.WhatsNewBoard)
		return
	end
	local t = findLabel(inst, { MapNames.BoardText, "WhatsNewText" }) or faceLabel(board, "WhatsNewText", "")
	-- fitted, white with a black outline (the owner's frame and face colour stay as built). Only the first 3 lines
	-- go on the board so the letters stay big enough to read from the path; the pop-up still shows them all.
	local lines = table.move(WhatsNew.Lines, 1, math.min(3, #WhatsNew.Lines), 1, {})
	KitPlace.fitMapLabel(t, WhatsNew.Title .. "\n" .. table.concat(lines, "\n"), "Placard")
	-- audit F26: the fitted 48 px text came out half a stud tall on the board (96 px per stud), unreadable on a phone
	-- walk-up; let it fill the board face instead
	if t:IsA("TextLabel") then
		t.TextWrapped = true
		t.TextScaled = true
	end
end

-- Building signs the owner lettered in Studio (EGG SHOP, the book shop, PET TOWER, ...): every SurfaceGui with one
-- TextLabel on a part under Buildings, or on any part whose name ends in "Sign", gets its own words refitted
-- (KitPlace.fitMapLabel, Landmark preset: big, white, black outline). Plot signs (owner names, written by the plot
-- code) and the code's own fitted signs (attribute SignText) are left alone.
local function ensureSigns(map: Instance)
	local buildings = map:FindFirstChild("Buildings", true)
	-- signs whose text other code writes (plots, queue pads and board, WHAT'S NEW, leaderboards)
	local skip = { MapNames.QueueBoard, MapNames.QueueCountdown, MapNames.WhatsNewBoard }
	for _, b in MapNames.Boards do
		table.move(b.Parts, 1, #b.Parts, #skip + 1, skip)
	end
	local function plotSign(inst: Instance): boolean
		local a: Instance? = inst
		while a and a ~= map do
			local n = a.Name
			if table.find(MapNames.PlotSign, n) or table.find(skip, n) or string.match(n, "^" .. MapNames.Plot .. "%d+$") or string.match(n, "^" .. MapNames.QueuePad .. "%d+$") then
				return true
			end
			a = a.Parent
		end
		return false
	end
	for _, gui in map:GetDescendants() do
		if not gui:IsA("SurfaceGui") then
			continue
		end
		local part = gui.Adornee or gui.Parent
		if not (part and part:IsA("BasePart")) or part:GetAttribute("SignText") ~= nil then
			continue
		end
		local signLike = string.sub(part.Name, -4) == "Sign" or (buildings ~= nil and part:IsDescendantOf(buildings))
		if not signLike or plotSign(part) then
			continue
		end
		local labels = {}
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") then
				table.insert(labels, d)
			end
		end
		local label = labels[1]
		if #labels == 1 and label and string.match(label.Text, "%S") and not string.find(label.Text, "<", 1, true) then
			KitPlace.fitMapLabel(label, label.Text, "Landmark")
		end
	end
end

-- Book shop sign (Studio check 2026-10-13): the BOOK lettering on the owner's ShopBook building is part of its mesh
-- texture, so it can't be refitted. A code-made framed board named BookSign carries big white outlined PET BOOK
-- lettering like the other shop signs. Placed on a part named BookSignSpot when the map has one (its LookVector = the
-- way the sign faces, its centre = the sign centre); otherwise above the front of ShopBook, facing the way the
-- PetBookSpot stall spot faces (else ShopBook's own front).
-- True when `inst` shows nothing: attribute Hidden, a see-through part, or a model / folder with no visible part.
function MapHooks.isHidden(inst: Instance): boolean
	if inst:GetAttribute("Hidden") == true then
		return true
	end
	if inst:IsA("BasePart") then
		return inst.Transparency >= 0.99
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			return false
		end
	end
	return true
end

-- The PET BOOK sign over the ShopBook stall. Skipped while the ShopBook is hidden (2026-10-14: the stall was hidden
-- and its sign floated in front of the Void Dragon statue's wing).
local function ensureBookSign(map: Instance, lobby: Instance)
	local shop = find(map, "ShopBook")
	if not shop or MapHooks.isHidden(shop) or lobby:FindFirstChild("BookSign", true) then
		return
	end
	local spot = findPart(map, "BookSignSpot")
	local cf: CFrame
	local W = 10
	if spot then
		-- level: a tilted spot part only gives the facing, never a lean
		local lv = spot.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		cf = CFrame.lookAt(spot.Position, spot.Position - flat)
		W = math.clamp(spot.Size.X, 6, 16)
	else
		local box: CFrame, size: Vector3
		if shop:IsA("Model") then
			box, size = shop:GetBoundingBox()
		elseif shop:IsA("BasePart") then
			box, size = shop.CFrame, shop.Size
		else
			return
		end
		local stall = findPart(map, MapNames.StallSpots.PetBook)
		local look = if stall then stall.CFrame.LookVector else box.LookVector
		local front = Vector3.new(look.X, 0, look.Z)
		front = if front.Magnitude > 0.01 then front.Unit else Vector3.zAxis
		-- half the footprint along the front direction, so the board sits just in front of the top edge
		local depth = math.abs(box.RightVector:Dot(front)) * size.X + math.abs(box.LookVector:Dot(front)) * size.Z
		local pos = box.Position + Vector3.new(0, size.Y / 2 + 1.6, 0) + front * (depth / 2 + 0.3)
		W = math.clamp(size.X * 0.6, 6, 14)
		cf = CFrame.lookAt(pos, pos - front) -- +Z (the sign front) toward the viewer
	end
	local face = KitPlace.signBoard(lobby, "BookSign", cf, W, W * 0.25, "PET BOOK", "Landmark", { Outline = true, Depth = 0.3 })
	local board = face.Parent
	if board then
		for _, d in board:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
	end
end

-- Leaderboards: a board with its own TextLabel ("Board" part > SurfaceGui > "Text") is marked BoardId and LobbyBoards
-- writes the rows there as text. A plain part gets an invisible mount over its front face in the code's BoardMounts
-- folder, marked Bare, and LobbyBoards draws the rows onto it.
local function ensureBoards(map: Instance, lobby: Instance)
	for _, b in MapNames.Boards do
		local inst = findAny(map, b.Parts)
		if not inst then
			warnMissing(b.Parts[1])
			continue
		end
		local face = findPart(inst, MapNames.BoardFace) or asPart(inst)
		local label = findLabel(inst, { MapNames.BoardText })
		if label then
			label:SetAttribute("BoardId", b.Id)
		elseif face then
			local mounts = lobby:FindFirstChild("BoardMounts")
			if not mounts then
				local folder = Instance.new("Folder")
				folder.Name = "BoardMounts"
				folder.Parent = lobby
				mounts = folder
			end
			local name = "Mount_" .. b.Id
			if not (mounts :: Instance):FindFirstChild(name) then
				local m = Instance.new("Part")
				m.Name = name
				m.Size = Vector3.new(face.Size.X, face.Size.Y, 0.05)
				m.CFrame = face.CFrame * CFrame.new(0, 0, -(face.Size.Z / 2 + 0.03)) * CFrame.Angles(0, math.pi, 0)
				m.Transparency = 1
				m.Anchored = true
				m.CanCollide = false
				m.CanQuery = false
				m.CanTouch = false
				m.CastShadow = false
				m:SetAttribute("Bare", true)
				m.Parent = mounts
			end
		end
	end
end

-- Plots ----------------------------------------------------------------------------------------------------------

-- Yaw-only frame at `pos` whose -Z (look) points along the flat direction (dx, dz).
local function facing(pos: Vector3, dx: number, dz: number): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, math.atan2(-dx, -dz), 0)
end

-- One hand-built plot -> the plot interface GalleryService uses (ParkBuilder.Plot). The plot looks toward its sign
-- (the gate / street side); the pets on Dome1Base, Stand1 and Stand2 (display slots 1-3) face that way.
local function adoptPlot(m: Instance, i: number, centre: Vector3): any?
	local floor = (if m:IsA("Model") and m.PrimaryPart and m.PrimaryPart.Name == MapNames.PlotFloor then m.PrimaryPart else nil)
		or findPart(m, MapNames.PlotFloor)
	if not floor then
		warnMissing(MapNames.plot(i) .. "." .. MapNames.PlotFloor)
		return nil
	end
	m:SetAttribute("Plot", i)
	local top = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
	-- the plot looks toward its sign (it stands at the gate, on the street side); without a sign, toward the map
	-- centre along the plot's main axis
	local signAt = asPart(findAny(m, MapNames.PlotSign))
	local to = if signAt then signAt.Position - top else centre - top
	local dx, dz = to.X, to.Z
	if not signAt then
		if math.abs(dx) >= math.abs(dz) then
			dz = 0
		else
			dx = 0
		end
	end
	if dx * dx + dz * dz < 1 then
		dx, dz = centre.X - top.X, centre.Z - top.Z
	end
	if dx * dx + dz * dz < 1e-4 then
		dz = -1
	end
	local F = facing(top, dx, dz)
	local domes = {}
	for k = 1, MapNames.DomeCount do
		local slot = findAny(m, MapNames.slotParts(k))
		local cf: CFrame? = nil
		local r = 2
		if slot and slot:IsA("BasePart") then
			cf = facing(slot.Position + Vector3.new(0, slot.Size.Y / 2, 0), dx, dz)
			r = math.max(slot.Size.X, slot.Size.Z) / 2
		elseif slot and slot:IsA("Attachment") then
			local p = slot.WorldPosition
			cf = facing(p, dx, dz)
		end
		if cf then
			local scale = slot and slot:GetAttribute("PetScale")
			table.insert(domes, {
				Slot = cf,
				Label = cf * CFrame.new(0, 0.35, -(r * 0.75)) * CFrame.Angles(0, math.pi, 0),
				Scale = if type(scale) == "number" and scale > 0 then scale else math.clamp(r / 2.2, 0.6, 1.3),
			})
		else
			warnMissing(MapNames.plot(i) .. "." .. (MapNames.slotParts(k)[1] or ("slot " .. k)))
		end
	end
	local signInst = findAny(m, MapNames.PlotSign)
	local signPart = asPart(signInst)
	local label: TextLabel? = (if signInst then findLabel(signInst, MapNames.SignText) else nil) or (function()
		local own = find(m, MapNames.OwnerText)
		return if own and own:IsA("TextLabel") then own else nil
	end)()
	-- bug 248: a hand-built sign can carry a big static "FREE PLOT" title next to a small owner line. The big title
	-- becomes the owner line ("<Name>'s Park", fitted), and the other small sign labels hide while the plot is owned.
	local extras: { TextLabel } = {}
	if signInst then
		local title: TextLabel? = nil
		for _, d in signInst:GetDescendants() do
			local up = if d:IsA("TextLabel") then string.upper(d.Text) else ""
			local hit = false
			for _, w in ParkConfig.SignMatch do
				hit = hit or string.find(up, w, 1, true) ~= nil
			end
			if d:IsA("TextLabel") and hit then
				title = d
				break
			end
		end
		if title then
			for _, d in signInst:GetDescendants() do
				if d:IsA("TextLabel") and d ~= title and table.find(MapNames.SignText, d.Name) then
					table.insert(extras, d)
				end
			end
			label = title
			title.TextScaled = true
		end
	end
	if not label and signPart then
		label = faceLabel(signPart, MapNames.OwnerText, ParkConfig.EmptyPlot)
	end
	local likeText = find(m, MapNames.LikeText)
	local likeBase = findPart(m, MapNames.LikePost) or signPart or floor
	local pp = prompt(likeBase, "LikePrompt", "Like", ParkConfig.EmptyPlot, 10)
	pp:SetAttribute("LikePlot", i)
	pp:SetAttribute("Off", true) -- GalleryService turns it on when someone owns the plot
	-- the sign shows the owner's name and, when there is no separate like counter, the likes under it
	local name, likes = ParkConfig.EmptyPlot, 0
	local function draw()
		if label then
			label.Text = if likes > 0 and not likeText then name .. "\n" .. likes .. (if likes == 1 then " LIKE" else " LIKES") else name
		end
		for _, x in extras do
			x.Visible = name == ParkConfig.EmptyPlot
		end
		if likeText and likeText:IsA("TextLabel") then
			likeText.Text = if likes == 1 then "1 LIKE" else tostring(likes) .. " LIKES"
		end
	end
	draw()
	-- Wandering pets roam the whole pen: the Floor's extent seen from the plot frame (the floor may be turned 90
	-- degrees against the frame), less a margin for the fence, posts and stands. The code default box is only the
	-- fallback when the floor is smaller than that default.
	local W = ParkConfig.Showcase.Wander
	local fr, fl = F.RightVector, F.LookVector
	local fx, fz = floor.CFrame.RightVector, floor.CFrame.LookVector
	local hx = math.abs(fr:Dot(fx)) * floor.Size.X / 2 + math.abs(fr:Dot(fz)) * floor.Size.Z / 2
	local hz = math.abs(fl:Dot(fx)) * floor.Size.X / 2 + math.abs(fl:Dot(fz)) * floor.Size.Z / 2
	-- bug 247: a hand-built fence can stand well inside the Floor's edge, so the box is also pulled in to the inner
	-- face of every outer fence run (parts named "...Fence..."); pieces inside the pen are ignored (ParkConfig.yardBox)
	local fences: { ParkConfig.YardFence } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "fence", 1, true) then
			local lp = F:PointToObjectSpace(d.Position)
			local tx = math.abs(F:VectorToObjectSpace(d.CFrame.RightVector).X) * d.Size.X / 2
				+ math.abs(F:VectorToObjectSpace(d.CFrame.UpVector).X) * d.Size.Y / 2
				+ math.abs(F:VectorToObjectSpace(d.CFrame.LookVector).X) * d.Size.Z / 2
			local tz = math.abs(F:VectorToObjectSpace(d.CFrame.RightVector).Z) * d.Size.X / 2
				+ math.abs(F:VectorToObjectSpace(d.CFrame.UpVector).Z) * d.Size.Y / 2
				+ math.abs(F:VectorToObjectSpace(d.CFrame.LookVector).Z) * d.Size.Z / 2
			table.insert(fences, { X = lp.X, Z = lp.Z, TX = tx, TZ = tz })
		end
	end
	local wander = ParkConfig.yardBox(hx, hz, ParkConfig.Showcase.FloorMargin, fences, 1.5, W)
	return {
		Index = i,
		Root = m,
		Frame = F,
		Plate = label,
		SetLabel = function(text: string)
			name = text
			draw()
		end,
		Domes = domes,
		SetLikes = function(n: number)
			likes = n
			draw()
		end,
		CrownAt = F * CFrame.new(0, ParkConfig.Likes.CrownHeight, 0),
		Wander = wander,
		Shutters = {},
		SetCapacity = function(_n: number) end,
		LabelDepth = 1,
	}
end

-- (exposed for tests)
MapHooks.ensureBookSign = function(map: Instance, lobby: Instance)
	ensureBookSign(map, lobby)
end

function MapHooks.ensure(map: Instance, lobby: Instance, adopt: boolean): { Plots: { any } }
	for _, fn in { ensureHatch, ensureTower, ensureSecretEgg, ensureEggShop } do
		local ok: boolean, err: any = pcall(fn, map)
		if not ok then
			warn("[MapHooks] hook check failed:", err)
		end
	end
	local okQ: boolean, errQ: any = pcall(ensureQueue, map, lobby)
	if not okQ then
		warn("[MapHooks] queue hooks failed:", errQ)
	end
	local plots = {}
	if adopt then
		pcall(ensureWhatsNew, map)
		local okB: boolean, errB: any = pcall(ensureBookSign, map, lobby)
		if not okB then
			warn("[MapHooks] book sign not added:", errB)
		end
		local okS: boolean, errS: any = pcall(ensureSigns, map)
		if not okS then
			warn("[MapHooks] building signs not refitted:", errS)
		end
		pcall(ensureBoards, map, lobby)
		-- the map centre (the plots' gates face it): the middle of the map's bounding box
		local centre = Vector3.zero
		if map:IsA("Model") then
			local ok, cf = pcall(function(): CFrame
				return ((map :: Model):GetBoundingBox()) -- the frame only
			end)
			if ok and cf then
				centre = Vector3.new(cf.Position.X, 0, cf.Position.Z)
			end
		end
		-- Plot1..PlotCount are expected; extra plots the owner adds (Plot7, Plot8, ...) are picked up too
		local i = 0
		while true do
			i += 1
			local m = find(map, MapNames.plot(i))
			if not m and i > MapNames.PlotCount then
				break
			end
			if m then
				local okP, p = pcall(adoptPlot, m, i, centre)
				if okP and p then
					table.insert(plots, p)
				elseif not okP then
					warn("[MapHooks] plot", i, "not adopted:", p)
				end
			else
				warnMissing(MapNames.plot(i))
			end
		end
	end
	return { Plots = plots }
end

return MapHooks
