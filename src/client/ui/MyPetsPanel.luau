--!strict
-- MY PETS (carter's low-poly reference, 2026-10-15): the one team and the pet collection.
--   YOUR TEAM   three slots: the ONE team (profile EquippedPets, Config.Pets.Slots = 3) that follows you in the lobby
--               and fights in the Training Tower and Pet Battles. Tap a slot = select that pet.
--   toolbar     pets owned / storage, search by name, sort (Power, Rarity, Level, Newest)
--   grid        every pet as a card (real 3D pet, full name, POWER); a green tick = on the team, a white outline =
--               selected (two different marks)
--   EQUIP BEST  the server fills the team with the highest POWER pets (PetService, PetRules.best)
--   pet panel   the selected pet: full name, rarity, big 3D picture (drag to turn), ON TEAM / ON DISPLAY roles, POWER,
--               level and XP to the next level, EQUIP / UNEQUIP, DISPLAY (plot dome, its own thing), favourite star
-- A full team never swaps a pet silently: EQUIP asks which slot (the team slots light up) and the server swaps only
-- the slot picked (PetRules.swapSlot). The client sends intents only; the server decides.
-- Look: carter's low-poly frame pictures (shared/MyPetsArt, 2026-10-16): the main frame, the pet panel frame, a frame
-- per rarity on every card (the cyan selected frame on the picked card), team slot frames, blank lime / orange / blue
-- buttons with live white lettering, the red X and the gold star. Every frame is a nine-sliced border drawn ABOVE a
-- native backing, with the live content inside its opening; decorations never take taps. Until the pictures are
-- uploaded (id 0) the same pieces are drawn natively (faceted gradients, thick navy outline). The paw on the title is
-- carter's MY PETS button picture.
-- Layout: shared/MyPetsLayout (tested on PC, landscape and upright phones).

local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Net = require(Shared.Net)
local PetRules = require(Shared.PetRules)
local PetStats = require(Shared.PetStats)
local PetStatView = require(Shared.PetStatView)
local TowerConfig = require(Shared.TowerConfig)
local MyPetsLayout = require(Shared.MyPetsLayout)
local LobbyHudArt = require(Shared.LobbyHudArt)
local MyPetsArt = require(Shared.MyPetsArt)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local GeodeView = require(script.Parent.GeodeView)

type Pet = { [string]: any }
type Rect = MyPetsLayout.Rect

local MyPets = {}
MyPets.Debug = false
MyPets.onDisplayFull = nil :: ((string) -> ())? -- Main: the Pet Book's display tab, placing this pet

local NAVY = Color3.fromHex("071747")
local NAVY_SOFT = Color3.fromHex("10245E")
local CYAN = Color3.fromHex("25E8FF")
local SKY = Color3.fromHex("009DFF")
local SKY_LIGHT = Color3.fromHex("4FC3FF")
local LIME = Color3.fromHex("80FF32")
local LIME_DARK = Color3.fromHex("3FBF1A")
local ORANGE = Color3.fromHex("FFA008")
local RED = Color3.fromHex("FF3B3B")
local GOLD = Color3.fromHex("FFD72D")
local WHITE = Color3.new(1, 1, 1)
local VOID = Color3.fromRGB(112, 52, 210)
local TICK = Color3.fromHex("7CFF3A")

local SORTS = { "Power", "Rarity", "Level", "Newest" }
local PAGE = 30

local open = false
local panelRef: Frame? = nil
local canvas: Frame? = nil
local closeFn: (() -> ())? = nil
local selected: string? = nil
local search = ""
local sortBy = "Power"
local shownCount = PAGE
local swapFor: string? = nil -- a pet waiting to join a full team: the player picks the slot
local refs: { [string]: any } = {}
local lay: MyPetsLayout.Layout = {}

local function act(action: string, a: any?, b: any?)
	Net.event("CollectionAction"):FireServer(action, a, b)
end

local function prof(): { [string]: any }?
	return State.Profile :: any
end

local function motion(): boolean
	return not UI.Reduced
end

-- Low-poly kit ---------------------------------------------------------------------------------------------------

local function place(obj: GuiObject, r: Rect)
	obj.Position = UDim2.fromOffset(math.floor(r.x), math.floor(r.y))
	obj.Size = UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
end

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(WHITE, k)
end

-- flat triangular planes: a hard-stepped gradient across the face (no gloss), two tones of `base`
local function facets(obj: GuiObject, base: Color3, angle: number?)
	local a, b, c = lighter(base, 0.18), base, darker(base, 0.88)
	local g = Instance.new("UIGradient")
	g.Name = "Facets"
	g.Rotation = angle or 32
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.3, a),
		ColorSequenceKeypoint.new(0.3001, b),
		ColorSequenceKeypoint.new(0.55, b),
		ColorSequenceKeypoint.new(0.5501, lighter(base, 0.08)),
		ColorSequenceKeypoint.new(0.78, lighter(base, 0.08)),
		ColorSequenceKeypoint.new(0.7801, c),
		ColorSequenceKeypoint.new(1, c),
	})
	g.Parent = obj
end

-- a chunky low-poly plate: faceted face, thick navy outline, and a navy lower edge drawn as a sibling just under it
-- (a child would draw on top of the face), kept in step with the face's place
local function plate(parent: Instance, name: string, color: Color3, props: { [string]: any }?, edge: number?): Frame
	local drop = UI.frame(parent, { Name = name .. "Drop", BackgroundColor3 = NAVY, BackgroundTransparency = 0 })
	UI.corner(drop, 7)
	local f = UI.frame(parent, { Name = name, BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	drop.ZIndex = math.max(f.ZIndex - 1, 1)
	UI.corner(f, 7)
	local s = Instance.new("UIStroke")
	s.Name = "Edge"
	s.Color = NAVY
	s.Thickness = edge or 3
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	facets(f, color)
	local function sync()
		drop.Position = f.Position + UDim2.fromOffset(0, 4)
		drop.Size = f.Size
		drop.AnchorPoint = f.AnchorPoint
	end
	f:GetPropertyChangedSignal("Position"):Connect(sync)
	f:GetPropertyChangedSignal("Size"):Connect(sync)
	f.Destroying:Connect(function()
		drop:Destroy()
	end)
	sync()
	return f
end

local function words(parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = { Font = UI.Head, TextSize = size, TextColor3 = WHITE, Outline = "Strong", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	local l = UI.text(parent, text, p)
	return l
end

-- a frame / button picture from carter's art pack, or nil while it is not uploaded. `border` (logical px) = nine-slice
-- the picture so its left border is that wide; nil = the whole picture fitted (the X and the star). A button's
-- slice follows its height (`follow`), so it keeps its bevelled ends at any width.
local function art(parent: Instance, key: string, name: string, z: number, border: number?, follow: boolean?): ImageLabel?
	local piece = MyPetsArt.get(key)
	if not piece then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = "rbxassetid://" .. piece.Id
	img.Active = false
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = z
	if follow and parent:IsA("GuiObject") then
		local x0, y0, x1, y1 = MyPetsArt.slice(piece)
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = Rect.new(x0, y0, x1, y1)
		local host = parent :: GuiObject
		local function fit()
			img.SliceScale = math.max(host.Size.Y.Offset, 8) / piece.H
		end
		host:GetPropertyChangedSignal("Size"):Connect(fit)
		fit()
	elseif border then
		local x0, y0, x1, y1 = MyPetsArt.slice(piece)
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = Rect.new(x0, y0, x1, y1)
		img.SliceScale = MyPetsArt.scaleFor(piece, border)
	else
		img.ScaleType = Enum.ScaleType.Fit
	end
	img.Parent = parent
	return img
end

-- the native backing under a frame picture: a faceted face tucked under the frame's border
local function backing(parent: Instance, color: Color3, inset: number, z: number): Frame
	local f = UI.frame(parent, { Name = "Backing", BackgroundColor3 = WHITE, BackgroundTransparency = 0, Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(1, -2 * inset, 1, -2 * inset), ZIndex = z })
	UI.corner(f, 8)
	facets(f, color)
	return f
end

-- a press-squash button (one piece; the hit box never moves)
local function pressy(b: GuiButton)
	local sc = Instance.new("UIScale")
	sc.Name = "Press"
	sc.Parent = b
	local function go(s: number, t: number, style: Enum.EasingStyle?)
		if motion() then
			TweenService:Create(sc, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = s }):Play()
		else
			sc.Scale = 1
		end
	end
	b.MouseButton1Down:Connect(function()
		go(0.94, 0.06)
	end)
	b.MouseButton1Up:Connect(function()
		go(1, 0.16, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		go(1, 0.12)
	end)
end

-- `skin` = the art pack button behind the label (Lime / Orange / Blue; Close and Fav carry their own symbol, so they
-- get no label at all); without the picture the button is drawn in `color`
local function button(parent: Instance, name: string, text: string, color: Color3, onTap: () -> (), size: number?, skin: string?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = WHITE
	b.Parent = parent
	local symbol = skin == "Close" or skin == "Fav"
	local pic = if skin then art(b, skin, "Art", 1, nil, not symbol) else nil
	if pic then
		b.BackgroundTransparency = 1
		b:SetAttribute("Art", skin)
	else
		UI.corner(b, 7)
		local s = Instance.new("UIStroke")
		s.Name = "Edge"
		s.Color = NAVY
		s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = b
		facets(b, color)
	end
	if pic and symbol then
		pressy(b)
		b.Activated:Connect(onTap)
		return b
	end
	local l = words(b, text, size or 20, { Name = "Label", Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 1, -8), ZIndex = 2 })
	l.TextWrapped = false
	pressy(b)
	b.Activated:Connect(onTap)
	return b
end

local function rarityColor(g: Pet): Color3
	if TowerConfig.CapSpecies[g.Mineral] then
		return VOID
	end
	return (Config.RarityColors :: any)[g.Rarity] or SKY
end

local function rarityWord(g: Pet): string
	if TowerConfig.CapSpecies[g.Mineral] then
		return "VOID"
	end
	return string.upper(tostring(g.Rarity or "?"))
end

-- the full name (nickname first when the pet has one), never cut short
local function fullName(g: Pet): string
	local species = GeodeGen.displayName(g :: any)
	if type(g.Nickname) == "string" and g.Nickname ~= "" then
		return g.Nickname .. " (" .. species .. ")"
	end
	return species
end

-- Data -------------------------------------------------------------------------------------------------------------

local function pets(): { Pet }
	local p = prof()
	return (p and type(p.Inventory) == "table" and p.Inventory) or {}
end

local function team(): { string }
	local p = prof()
	return (p and type(p.EquippedPets) == "table" and p.EquippedPets) or {}
end

local function slots(): number
	local p = prof()
	return (p and tonumber(p.PetSlots)) or Config.Pets.Slots
end

local function find(id: string?): Pet?
	if not id then
		return nil
	end
	for _, g in pets() do
		if g.Id == id then
			return g
		end
	end
	return nil
end

local function onTeam(id: string): boolean
	return table.find(team(), id) ~= nil
end

local function onDisplay(id: string): boolean
	local p = prof()
	return p ~= nil and type(p.DisplayAssignments) == "table" and table.find(p.DisplayAssignments, id) ~= nil
end

local function power(g: Pet): number
	return PetStatView.power(g) or 0
end

-- matching pets, sorted (Power: biggest first; ties newest, as PetRules.sort)
local function list(): { Pet }
	local out = {}
	local q = string.lower(search)
	for _, g in pets() do
		if q == "" or string.find(string.lower(fullName(g)), q, 1, true) then
			table.insert(out, g)
		end
	end
	if sortBy == "Power" then
		PetRules.sort(out, "Newest")
		local pw: { [any]: number } = {}
		for _, g in out do
			pw[g] = power(g)
		end
		local order: { [any]: number } = {}
		for i, g in out do
			order[g] = i
		end
		table.sort(out, function(a, b)
			if pw[a] ~= pw[b] then
				return pw[a] > pw[b]
			end
			return order[a] < order[b]
		end)
	else
		PetRules.sort(out, sortBy)
	end
	return out
end

-- level, cap and the share of the way to the next level (full at the cap), from the real tower XP
local function levelInfo(g: Pet): (number, number, number)
	local cap = PetStats.cap(g :: any)
	local xp = if type(g.TowerXP) == "number" then g.TowerXP else 0
	local lv, into, need = PetStats.level(xp, cap)
	local frac = if need > 0 then math.clamp(into / need, 0, 1) else 1
	return lv, cap, frac
end

-- Pieces -----------------------------------------------------------------------------------------------------------

-- the real 3D pet fitted by its own bounds (GeodeView.frame), so big and small species both fill the picture
local function petPicture(parent: Instance, g: Pet, name: string, drag: boolean?, margin: number?): ViewportFrame
	local vp, model, cam = GeodeView.make(parent, g, { Name = name, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, drag)
	GeodeView.frame(cam, model, margin or 0.66)
	return vp
end

local function tick(parent: Instance, size: number): TextLabel
	local t = words(parent, "\u{2714}", size, { Name = "OnTeam", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(size + 6, size + 6), TextColor3 = TICK, ZIndex = 8 })
	t.TextWrapped = false
	return t
end

local refresh: () -> ()

local function select(id: string?)
	if selected ~= id then
		selected = id
		refresh()
	end
end

local function slotTapped(i: number)
	local id = team()[i]
	if swapFor then
		act("EquipPet", swapFor, i) -- the server swaps exactly this slot
		selected = swapFor
		swapFor = nil
		refresh()
		return
	end
	if id then
		select(id)
	end
end

local function drawTeam()
	local holder = refs.Slots :: Frame
	holder:ClearAllChildren()
	local ids = team()
	for i = 1, 3 do
		local r = lay["Slot" .. i]
		if not r then
			continue
		end
		local t = lay.Team
		local local_ = { x = r.x - t.x, y = r.y - t.y, w = r.w, h = r.h }
		local g = find(ids[i])
		local usable = i <= slots()
		local hit = Instance.new("TextButton")
		hit.Name = "Slot" .. i
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.BackgroundTransparency = 1
		hit.ZIndex = 10
		hit.Parent = holder
		place(hit, local_)
		local face: Frame
		local slotArt = MyPetsArt.get("Slot")
		if slotArt then
			-- the slot frame picture over a rarity-coloured face; the pet, number and tick sit on top
			face = UI.frame(holder, { Name = "SlotFace" .. i, BackgroundTransparency = 1, ZIndex = 2 })
			place(face, local_)
			local bw = math.max(local_.w * 0.1, 6)
			backing(face, if g then rarityColor(g) else NAVY_SOFT, bw * 0.6, 1)
			art(face, "Slot", "Frame", 5, bw)
		else
			face = plate(holder, "SlotFace" .. i, if g then rarityColor(g) else NAVY_SOFT, { ZIndex = 2 })
			place(face, local_)
		end
		if g then
			petPicture(face, g, "Pet")
			tick(face, 18)
		elseif usable then
			words(face, "+", 30, { Name = "Empty", TextTransparency = 0.4, ZIndex = 4 })
		end
		local num = UI.frame(face, { Name = "Num", BackgroundColor3 = NAVY, BackgroundTransparency = 0, Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(22, 22), ZIndex = 6 })
		UI.corner(num, 11)
		words(num, tostring(i), 14, { Name = "N", ZIndex = 7 })
		if swapFor then
			local glow = Instance.new("UIStroke")
			glow.Name = "SwapGlow"
			glow.Color = GOLD
			glow.Thickness = 4
			glow.Parent = hit
			words(face, "SWAP", 16, { Name = "Swap", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -4, 0, 20), TextColor3 = GOLD, ZIndex = 8 })
		end
		hit.Activated:Connect(function()
			slotTapped(i)
		end)
	end
	local note = refs.TeamNote :: TextLabel
	note.Text = if swapFor then "Tap a slot to swap!" else "Follows you \u{2022} Battles with you"
	note.TextColor3 = if swapFor then GOLD else WHITE
end

local cardSize = Vector2.new(120, 100)

local function card(parent: Instance, g: Pet, i: number)
	local c = Instance.new("TextButton")
	c.Name = "Card"
	c.LayoutOrder = i
	c.Text = ""
	c.AutoButtonColor = false
	c.BackgroundColor3 = WHITE
	c.Parent = parent
	local sel = g.Id == selected
	if sel then
		c:SetAttribute("Selected", true)
	end
	local key = MyPetsArt.cardKey(g.Rarity, TowerConfig.CapSpecies[g.Mineral] ~= nil)
	local piece = MyPetsArt.get(if sel then "Selected" else key)
	local content: Frame
	local contentH = cardSize.Y - 6
	if piece then
		-- art: a rarity-coloured backing, the live pet / name / POWER clipped to the frame's opening, the frame on top
		-- (the selected card swaps its rarity frame for the cyan selected frame, never two thick borders)
		c.BackgroundTransparency = 1
		local bw = MyPetsLayout.cardBorder(cardSize.X)
		local k = MyPetsArt.scaleFor(piece, bw)
		local l, t, r, b = MyPetsArt.opening(piece, k)
		backing(c, rarityColor(g), bw * 0.55, 1)
		contentH = cardSize.Y - math.floor(t + b)
		content = UI.frame(c, { Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(math.floor(l), math.floor(t)), Size = UDim2.new(1, -math.floor(l + r), 1, -math.floor(t + b)), ZIndex = 2 })
		local frame = art(c, if sel then "Selected" else key, "Frame", 6, bw)
		if frame then
			frame:SetAttribute("Rarity", key)
		end
	else
		UI.corner(c, 7)
		facets(c, rarityColor(g))
		local edge = Instance.new("UIStroke")
		edge.Name = "Edge"
		edge.Color = if sel then WHITE else NAVY
		edge.Thickness = if sel then 5 else 3
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = c
		if sel then
			local ring = Instance.new("Frame")
			ring.Name = "SelectedRing"
			ring.BackgroundTransparency = 1
			ring.Size = UDim2.new(1, 8, 1, 8)
			ring.Position = UDim2.fromOffset(-4, -4)
			ring.Parent = c
			UI.corner(ring, 10)
			local rs = Instance.new("UIStroke")
			rs.Color = CYAN
			rs.Thickness = 3
			rs.Parent = ring
		end
		content = UI.frame(c, { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 2 })
	end
	-- name over POWER in a navy band along the bottom: tall enough for a readable name on the flattest phone card
	local bandH = math.clamp(math.floor(contentH * 0.5), 34, 50)
	local pic = UI.frame(content, { Name = "Picture", Size = UDim2.new(1, 0, 1, -bandH + 6), BackgroundTransparency = 1, ZIndex = 2 })
	petPicture(pic, g, "Pet")
	local band = UI.frame(content, { Name = "Band", BackgroundColor3 = NAVY, BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, bandH), ZIndex = 4 })
	UI.corner(band, 5)
	local nameH = math.floor(bandH * 0.46)
	local nm = words(band, fullName(g), 16, { Name = "Name", Position = UDim2.fromOffset(3, 1), Size = UDim2.new(1, -6, 0, nameH), ZIndex = 5 })
	UI.fit(nm, 16, 9)
	UI.oneLine(nm, 8) -- "Skeleton Thunderstrut" wrapped and showed only "Skeleton"
	words(band, UI.num(power(g)), 22, { Name = "Power", Position = UDim2.fromOffset(0, nameH + 1), Size = UDim2.new(1, 0, 1, -nameH - 2), TextColor3 = WHITE, ZIndex = 5 })
	if onTeam(g.Id) then
		tick(c, 20)
	end
	if g.Favorite == true then
		local st = words(c, "\u{2605}", 18, { Name = "Fav", Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(22, 22), TextColor3 = GOLD, ZIndex = 8 })
		st.TextWrapped = false
	end
	pressy(c)
	c.Activated:Connect(function()
		select(g.Id)
	end)
end

local function drawGrid()
	local grid = refs.Grid :: ScrollingFrame
	for _, ch in grid:GetChildren() do
		if not ch:IsA("UIGridLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	local all = list()
	local count = refs.Count :: TextLabel
	local p = prof()
	count.Text = tostring(#pets()) .. " / " .. tostring((p and p.InventoryMax) or Config.Inventory.Max)
	if #all == 0 then
		words(grid, if #pets() == 0 then "No pets yet! Tap PLAY to find one." else "No pet called that.", 18, { Name = "Empty", Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1 })
		return
	end
	for i, g in all do
		if i > shownCount then
			local more = button(grid, "More", "MORE (" .. (#all - shownCount) .. ")", SKY, function()
				shownCount += PAGE
				drawGrid()
			end, 18)
			more.LayoutOrder = i
			break
		end
		card(grid, g, i)
	end
end

local function role(parent: Instance, text: string, color: Color3, order: number, width: number?)
	local chip = UI.frame(parent, { Name = "Role", BackgroundColor3 = color, BackgroundTransparency = 0, Size = UDim2.fromOffset(width or 104, 22), LayoutOrder = order, ZIndex = 6 })
	UI.corner(chip, 6)
	local s = Instance.new("UIStroke")
	s.Color = NAVY
	s.Thickness = 2
	s.Parent = chip
	local l = words(chip, text, 12, { Name = "Text", Position = UDim2.fromOffset(4, 1), Size = UDim2.new(1, -8, 1, -2), ZIndex = 7 })
	UI.oneLine(l, 8)
end

local function drawDetail()
	local d = refs.Detail :: Frame
	for _, ch in d:GetChildren() do
		if ch.Name ~= "Edge" and ch.Name ~= "Facets" and ch.Name ~= "Drop" and ch.Name ~= "Backing" and ch.Name ~= "Frame" and not ch:IsA("UICorner") then
			ch:Destroy()
		end
	end
	local g = find(selected)
	local dr = lay.Detail
	local function at(n: string): (UDim2, UDim2)
		local r = lay[n]
		return UDim2.fromOffset(math.floor(r.x - dr.x), math.floor(r.y - dr.y)), UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
	end
	if not g then
		words(d, if #pets() == 0 then "Find your first pet in a hunt!" else "Tap a pet to see it here.", 20, { Name = "None", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) })
		return
	end
	local pos, size = at("Name")
	-- the whole name on one line, shrunk to fit ("SHINY GOLDEN RAZORCLAW" wrapped and lost its last word on a phone)
	local nm = words(d, string.upper(fullName(g)), 38, { Name = "Name", Position = pos, Size = size })
	UI.fit(nm, 38, 12)
	UI.oneLine(nm, 10)
	pos, size = at("Badge")
	local badge = UI.frame(d, { Name = "Badge", Position = pos, Size = size, BackgroundColor3 = rarityColor(g), BackgroundTransparency = 0 })
	UI.corner(badge, 6)
	local bs = Instance.new("UIStroke")
	bs.Color = NAVY
	bs.Thickness = 2.5
	bs.Parent = badge
	local rw = words(badge, rarityWord(g), 16, { Name = "Rarity", Position = UDim2.fromOffset(4, 1), Size = UDim2.new(1, -8, 1, -2) })
	rw.TextWrapped = false
	UI.fit(rw, 16, 8)
	pos, size = at("Preview")
	local box = UI.frame(d, { Name = "Preview", Position = pos, Size = size, BackgroundTransparency = 1, ClipsDescendants = false })
	local shadow = UI.frame(box, { Name = "Floor", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.9), Size = UDim2.fromScale(0.7, 0.12), BackgroundColor3 = NAVY, BackgroundTransparency = 0.7 })
	UI.corner(shadow, 999)
	local vp = petPicture(box, g, "Pet", true, 0.6)
	if motion() then -- a slow gentle bob
		vp.Position = UDim2.fromOffset(0, 0)
		TweenService:Create(vp, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, -6) }):Play()
	end
	-- ON TEAM / ON DISPLAY: their own row on short screens (lay.Roles), else stacked in the picture's top corner,
	-- a step in from its edge so the frame never cuts a chip
	local chips: { { text: string, color: Color3 } } = {}
	if onTeam(g.Id) then
		table.insert(chips, { text = "ON TEAM", color = LIME_DARK })
	end
	if onDisplay(g.Id) then
		table.insert(chips, { text = "ON DISPLAY", color = SKY })
	end
	local rr = lay.Roles
	local roles: Frame
	local chipW = 104
	if rr then
		roles = UI.frame(d, { Name = "Roles", BackgroundTransparency = 1, Position = UDim2.fromOffset(math.floor(rr.x - dr.x), math.floor(rr.y - dr.y)), Size = UDim2.fromOffset(math.floor(rr.w), math.floor(rr.h)), ZIndex = 6 })
		UI.list(roles, Enum.FillDirection.Horizontal, 4)
		chipW = math.floor(math.min(104, (rr.w - 4 * (#chips - 1)) / math.max(#chips, 1)))
	else
		roles = UI.frame(box, { Name = "Roles", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 2), Size = UDim2.new(0, 108, 0, 50), ZIndex = 6 })
		UI.list(roles, Enum.FillDirection.Vertical, 4)
	end
	for i, c in chips do
		role(roles, c.text, c.color, i, chipW)
	end
	pos, size = at("PowerLabel")
	local pl = words(d, "POWER", 18, { Name = "PowerLabel", Position = pos, Size = size })
	pl.TextWrapped = false
	pos, size = at("Power")
	local pill = UI.frame(d, { Name = "Power", Position = pos, Size = size, BackgroundColor3 = NAVY, BackgroundTransparency = 0 })
	UI.corner(pill, 8)
	words(pill, UI.num(power(g)), 48, { Name = "Value", Position = UDim2.fromOffset(6, 1), Size = UDim2.new(1, -12, 1, -2), TextColor3 = GOLD })
	local lv, cap, frac = levelInfo(g)
	pos, size = at("Level")
	words(d, "Level " .. lv .. " / " .. cap, 18, { Name = "Level", Position = pos, Size = size })
	pos, size = at("Bar")
	local bar = UI.frame(d, { Name = "Bar", Position = pos, Size = size, BackgroundColor3 = NAVY, BackgroundTransparency = 0 })
	UI.corner(bar, 7)
	local fill = UI.frame(bar, { Name = "Fill", BackgroundColor3 = LIME, BackgroundTransparency = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(math.max(frac, 0.04), -4, 1, -4) })
	UI.corner(fill, 5)
	-- EQUIP / UNEQUIP / SWAP IN (full team: pick a slot)
	local mine = onTeam(g.Id)
	local full = #team() >= slots()
	local label = if mine then "UNEQUIP" elseif full then "SWAP IN" else "EQUIP"
	local actB = button(d, "Action", label, if mine or full then ORANGE else LIME_DARK, function()
		if mine then
			act("UnequipPet", g.Id)
		elseif full then
			swapFor = if swapFor == g.Id then nil else g.Id
			refresh()
		else
			act("EquipPet", g.Id)
		end
	end, 24, if mine or full then "Orange" else "Lime")
	pos, size = at("Action")
	actB.Position, actB.Size = pos, size
	local shown = onDisplay(g.Id)
	local disp = button(d, "Display", if shown then "TAKE OFF" else "DISPLAY", SKY, function()
		local p = prof()
		if shown then
			act("Display", g.Id, false)
		elseif p and type(p.DisplayAssignments) == "table" and #p.DisplayAssignments < (tonumber(p.DisplaySlots) or 0) then
			act("Display", g.Id, true)
		else
			-- the domes are full: the Pet Book's display tab asks which one to swap
			local f = MyPets.onDisplayFull
			if f then
				f(g.Id)
			end
		end
	end, 20, "Blue")
	pos, size = at("Display")
	disp.Position, disp.Size = pos, size
	local fav = button(d, "Fav", "\u{2605}", GOLD, function()
		act("Favorite", g.Id, not (g.Favorite == true))
	end, 26, "Fav")
	pos, size = at("Fav")
	fav.Position, fav.Size = pos, size
	local star = fav:FindFirstChild("Label") :: TextLabel?
	if star then
		star.TextColor3 = if g.Favorite == true then WHITE else NAVY_SOFT
	end
	local starArt = fav:FindFirstChild("Art") :: ImageLabel?
	if starArt then -- not a favourite yet: the gold star waits dimmed
		starArt.ImageTransparency = if g.Favorite == true then 0 else 0.45
	end
	fav:SetAttribute("On", g.Favorite == true)
end

refresh = function()
	if not open or not canvas then
		return
	end
	-- the selection follows the data: a sold or missing pet falls back to the first on the team, then the first pet
	if not find(selected) then
		selected = team()[1] or (pets()[1] and pets()[1].Id) or nil
	end
	if swapFor and (not find(swapFor) or onTeam(swapFor) or #team() < slots()) then
		swapFor = nil
	end
	drawTeam()
	drawGrid()
	drawDetail()
end

-- Build ----------------------------------------------------------------------------------------------------------

local function build(w: number, h: number)
	local c = canvas
	if not c then
		return
	end
	c:ClearAllChildren()
	lay = MyPetsLayout.layout(w, h)
	-- the backdrop: the main frame picture over a blue face (the frame sits above the content, the title and X above
	-- the frame, as in carter's art); without the picture, one big drawn cyan plate
	local border = MyPetsLayout.Border(w, h)
	if MyPetsArt.get("Main") then
		backing(c, SKY, border * 0.5, 1).Name = "Back"
		art(c, "Main", "Frame", 9, border)
	else
		plate(c, "Back", SKY, { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, 4)
	end
	-- title: carter's paw picture + MY (white) PETS (gold)
	local title = UI.frame(c, { Name = "Title", BackgroundTransparency = 1, ZIndex = 11 })
	place(title, lay.Title)
	local th = math.min(lay.Title.h, lay.Title.w / 4.9) -- paw + MY + PETS always fit their box
	local paw = LobbyHudArt.image("MyPets")
	if paw then
		local img = Instance.new("ImageLabel")
		img.Name = "Paw"
		img.BackgroundTransparency = 1
		img.Image = paw
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(th, th)
		img.ZIndex = 11
		img.Parent = title
	end
	local my = words(title, "MY", 46, { Name = "My", Position = UDim2.fromOffset(th + 6, 0), Size = UDim2.fromOffset(math.floor(th * 1.25), th), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
	my.TextWrapped = false
	local pt = words(title, "PETS", 46, { Name = "Pets", Position = UDim2.fromOffset(th + 10 + math.floor(th * 1.25), 0), Size = UDim2.fromOffset(math.floor(th * 2.4), th), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, ZIndex = 11 })
	pt.TextWrapped = false
	local x = button(c, "Close", "X", RED, function()
		local f = closeFn
		if f then
			f()
		end
	end, 26, "Close")
	place(x, lay.Close)
	x.ZIndex = 11
	-- team strip
	local teamF = plate(c, "Team", SKY_LIGHT, { ZIndex = 2 })
	place(teamF, lay.Team)
	local tl = lay.TeamLabel
	local labelBox = UI.frame(teamF, { Name = "TeamLabel", BackgroundTransparency = 1, Position = UDim2.fromOffset(tl.x - lay.Team.x, tl.y - lay.Team.y), Size = UDim2.fromOffset(tl.w, tl.h), ZIndex = 3 })
	local slim = tl.h < 40 or tl.w < 170 -- short phones: just the words, EQUIP BEST sits beside or under them
	words(labelBox, "YOUR TEAM", 32, { Name = "Head", Size = UDim2.fromScale(1, if slim then 1 else 0.6), ZIndex = 3 })
	local note = words(labelBox, "Follows you \u{2022} Battles with you", 16, { Name = "Note", Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4), ZIndex = 3 })
	note.TextWrapped = false
	note.Visible = not slim -- the gold SWAP marks on the slots still show a swap
	UI.fit(note, 16, 9)
	refs.TeamNote = note
	local slotsF = UI.frame(teamF, { Name = "Slots", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	refs.Slots = slotsF
	-- toolbar
	local countF = plate(c, "Count", NAVY_SOFT, { ZIndex = 2 })
	place(countF, lay.Count)
	refs.Count = words(countF, "0 / 0", 22, { Name = "Text", Position = UDim2.fromOffset(6, 1), Size = UDim2.new(1, -12, 1, -4) })
	local searchF = plate(c, "Search", Color3.fromHex("E8F6FF"), { ZIndex = 2 })
	place(searchF, lay.Search)
	local box = Instance.new("TextBox")
	box.Name = "Box"
	box.BackgroundTransparency = 1
	box.Font = UI.Bold
	box.PlaceholderText = "\u{1F50D} Search pets"
	box.PlaceholderColor3 = Color3.fromHex("6A7FA8")
	box.Text = search
	box.TextColor3 = NAVY
	box.TextScaled = true
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(10, 4)
	box.Size = UDim2.new(1, -20, 1, -10)
	box.Parent = searchF
	local lim = Instance.new("UITextSizeConstraint")
	lim.MaxTextSize = 20
	lim.MinTextSize = 12
	lim.Parent = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		search = string.sub(box.Text, 1, 30)
		shownCount = PAGE
		drawGrid()
	end)
	local sortB = button(c, "Sort", sortBy .. " \u{25BE}", Color3.fromHex("E8F6FF"), function() end, 18)
	place(sortB, lay.Sort)
	local sl = sortB:FindFirstChild("Label") :: TextLabel?
	if sl then
		sl.TextColor3 = NAVY
		local o = sl:FindFirstChild("Outline")
		if o then
			o:Destroy()
		end
	end
	sortB.Activated:Connect(function()
		local i = table.find(SORTS, sortBy) or 1
		sortBy = SORTS[i % #SORTS + 1]
		if sl then
			sl.Text = sortBy .. " \u{25BE}"
		end
		shownCount = PAGE
		drawGrid()
	end)
	-- grid
	local grid = UI.scroller(c, { Name = "Grid", ZIndex = 2 })
	place(grid, lay.Grid)
	local cols, cw, chh = MyPetsLayout.cards(lay.Grid.w, UI.ScrollBar, lay.Grid.h)
	cardSize = Vector2.new(cw, chh)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(cw, chh)
	gl.CellPadding = UDim2.fromOffset(MyPetsLayout.Gap, MyPetsLayout.Gap)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.FillDirectionMaxCells = cols
	gl.Parent = grid
	local gp = Instance.new("UIPadding")
	gp.PaddingTop = UDim.new(0, MyPetsLayout.GridPad.Top)
	gp.PaddingLeft = UDim.new(0, MyPetsLayout.GridPad.Side)
	gp.PaddingBottom = UDim.new(0, MyPetsLayout.GridPad.Bottom)
	gp.Parent = grid
	refs.Grid = grid
	-- equip best
	local best = button(c, "EquipBest", "EQUIP BEST", LIME_DARK, function()
		act("EquipBest")
	end, 30, "Lime")
	place(best, lay.EquipBest)
	best.ZIndex = 4 -- above the team strip when a short upright phone puts it there
	-- pet panel
	local det: Frame
	if MyPetsArt.get("Detail") then
		det = UI.frame(c, { Name = "Detail", BackgroundTransparency = 1, ZIndex = 2 })
		place(det, lay.Detail)
		local db = MyPetsLayout.detailBorder(lay.Detail)
		backing(det, SKY_LIGHT, db * 0.5, 0)
		art(det, "Detail", "Frame", 20, db)
	else
		det = plate(c, "Detail", SKY_LIGHT, { ZIndex = 2 })
		place(det, lay.Detail)
	end
	refs.Detail = det
	refresh()
end

-- the panel's own size in the units its children are drawn in: a 100 x 100 probe inside it says how many screen
-- pixels one unit is (UI scale and the pop-in spring alike), so the layout always fills the panel exactly
local function measure(): (number, number)
	local p = panelRef
	local probe = p and p:FindFirstChild("Probe") :: Frame?
	if p and probe and probe.AbsoluteSize.X > 1 and p.AbsoluteSize.X > 10 then
		local k = probe.AbsoluteSize.X / 100
		return p.AbsoluteSize.X / k, p.AbsoluteSize.Y / k
	end
	return math.min(UI.Logical.X - 24, 900), math.min(UI.Logical.Y - 24, 500)
end

local lastSize = Vector2.zero
local function rebuildIfResized()
	local w, h = measure()
	local v = Vector2.new(math.floor(w), math.floor(h))
	if MyPets.Debug then
		local p = panelRef
		print("MYPETS measure", w, h, p and p.AbsoluteSize, p and p.Parent and (p.Parent :: any).AbsoluteSize, UI.Logical, UI.Scale)
	end
	if (v - lastSize).Magnitude >= 2 then
		lastSize = v
		build(v.X, v.Y)
	end
end

function MyPets.open(focus: string?)
	local panel, body, close = UI.modal("MyPets", "MY PETS", Vector2.new(900, 500), { Fixed = true, NoClose = true })
	-- the shell's own skin steps aside: this screen draws its own low-poly frame
	for _, ch in panel:GetChildren() do
		if ch ~= body and not ch:IsA("UISizeConstraint") and not (ch:IsA("UIScale") and ch.Name == "Enter") then
			ch:Destroy()
		end
	end
	panel.BackgroundTransparency = 1
	UI.frame(panel, { Name = "Probe", BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 100), Visible = false })
	for _, ch in body:GetChildren() do
		ch:Destroy()
	end
	body.Position = UDim2.fromOffset(0, 0)
	body.Size = UDim2.fromScale(1, 1)
	panelRef = panel
	canvas = body
	closeFn = close
	open = true
	swapFor = nil
	shownCount = PAGE
	if focus then
		selected = focus
	end
	lastSize = Vector2.zero
	rebuildIfResized()
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(rebuildIfResized)
	local conn: RBXScriptConnection
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "MyPets" then
			open = false
			canvas, panelRef, closeFn = nil, nil, nil
			refs = {}
			conn:Disconnect()
		end
	end)
end

-- the Pet Book (or anything else) asks to put a pet on a full team: MY PETS opens with the slots lit up
function MyPets.openSwap(id: string)
	MyPets.open(id)
	if #team() >= slots() and not onTeam(id) then
		swapFor = id
		refresh()
	end
end

function MyPets.isOpen(): boolean
	return open
end

-- profile updates come in bursts: one redraw a moment later
local queued = false
function MyPets.start()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" and open and not queued then
			queued = true
			task.delay(0.1, function()
				queued = false
				refresh()
			end)
		end
	end)
end

return MyPets
