--!strict
-- Pet Tower screens: the TOWER entry button (lobby only), the team picker (pick up to 3 pets, see each pet's
-- type, grade, stats and moves), the fight HUD (floor, wave, SPECIAL button with its meter, LEAVE) and the
-- floor-end card. Sends intents only; the server decides everything.

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local TowerConfig = require(Shared.TowerConfig)
local PetStatView = require(Shared.PetStatView)
local PetStats = require(Shared.PetStats)
local TouchLayout = require(Shared.TouchLayout)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local Theme = require(script.Parent.Theme)
local HudArt = require(script.Parent.HudArt)
local TowerView = require(script.Parent.Parent.TowerView)
local TowerFx = require(script.Parent.Parent.TowerFx)
local State = require(script.Parent.Parent.State)
local Audio = require(script.Parent.Parent.Audio)
local Juice = require(script.Parent.Juice)
local GeodeView = require(script.Parent.GeodeView)
local PetStatsStrip = require(script.Parent.PetStatsStrip)
local TweenService = game:GetService("TweenService")

local TC = Theme.Color
local K = Theme.Pet
local T = UI.T
local player = Players.LocalPlayer

local TowerPanel = {}

local send: (any) -> () = function() end
-- The server takes one intent per 0.15 s per player and drops the rest, so fast team taps were lost (audit 20).
-- `send` goes through a small outbox spaced just over that gap: a queued SetTeam is replaced by the newest picks
-- (the last choice always reaches the server), and a second copy of any other queued op is dropped.
local SEND_GAP = 0.2
local teamQueued = false -- a SetTeam waits in the outbox
local teamHoldUntil = 0 -- a Roster reply before this may predate the last SetTeam: keep the local picks
-- The revive price is read from Roblox in the background, never inside a handler (GetProductInfo yields; audit 26).
-- A failed read is remembered and retried after REVIVE_RETRY seconds; until then the card shows "R$ ?".
local REVIVE_RETRY = 30
local revivePrice: string? = nil -- "R$ 99", read from Roblox once (never written in the game)
local reviveFetching = false
local reviveFailedAt = -math.huge
local function fetchRevivePrice()
	if TowerConfig.Revive.ProductId == 0 or revivePrice or reviveFetching or os.clock() - reviveFailedAt < REVIVE_RETRY then
		return
	end
	reviveFetching = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(TowerConfig.Revive.ProductId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			revivePrice = "R$ " .. info.PriceInRobux
		else
			reviveFailedAt = os.clock()
		end
		reviveFetching = false
	end)
end
local function reviveCost(): string
	fetchRevivePrice()
	return revivePrice or "R$ ?"
end
local roster: any = nil
local picked: { string } = {}
local hud: Frame? = nil
local floorLabel: TextLabel? = nil
local coinsLabel: TextLabel? = nil -- running coin total of this climb (server RunCoins, sent with each FloorEnd)
local meterFill: Frame? = nil
local specialBtn: TextButton? = nil
local chargeRing: UIStroke? = nil
local ringPulse: Tween? = nil
local specialGlow: Frame? = nil
local glowScale: UIScale? = nil
local glowTweens: { Tween } = {}
local wasFull = false
local inRun = false
local hudFloor = 0 -- floor of the last Floor message (0 = none); early floors leave without a confirm
local pickerRows: { [any]: TextButton } = {} -- pet id -> row of the open picker
local entryButton: TextButton? = nil

local LOSE_TIPS = {
	"Level up your pets: win floors and they gain XP.",
	"Use type advantage: hits marked Strong! do extra damage.",
	"Bring pets of different types so one is always strong.",
	"Hit EQUIP BEST to send in your strongest pets.",
}

-- Shows the best floor on the TOWER button's small label.
local function setBest(n: number?)
	local b = entryButton
	local sub = if b then b:FindFirstChild("Sub", true) else nil
	if sub and sub:IsA("TextLabel") and n and n > 0 then
		sub.Text = "Best floor " .. tostring(n)
	end
end

-- The shared rarity text tints (Config): light words that take the dark outline, like the Pet Book and results.
local RARITY_COLOR = Config.RarityTextColors :: { [string]: Color3 }

local function speciesName(id: string): string
	-- Owner's display names; anything unnamed: "DireWolf" -> "Dire Wolf"
	return TowerConfig.PetNames[id] or (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

-- Tower HUD pieces live on the shared HUD layer (UI.screen: safe-area insets and the same UIScale as every screen).
local function holder(name: string): Frame
	return UI.frame(UI.screen(), { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
end

-- order: the pet's place in the team (1..TeamSize) when picked, else nil. A picked row gets a gold number badge,
-- so the choice reads without colour alone.
local function styleRow(b: TextButton, order: number?)
	local on = order ~= nil
	b.BackgroundColor3 = if on then TC.InsetHover else TC.Inset
	local s = b:FindFirstChild("Border") :: UIStroke?
	if s then
		s.Color = if on then TC.Gold else TC.InsetEdge
		s.Thickness = if on then 3 else 1.5
	end
	local badge = b:FindFirstChild("PickBadge") :: Frame?
	if on and not badge then
		local f = UI.frame(b, { Name = "PickBadge", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(32, 32), BackgroundColor3 = TC.Gold, ZIndex = 6 })
		UI.corner(f, 16)
		UI.stroke(f, TC.GoldDeep, 2)
		UI.text(f, "", { Name = "Num", Font = UI.Head, TextSize = T.Body, TextColor3 = TC.DarkText, Outline = false, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		badge = f
	end
	if badge then
		badge.Visible = on
		local num = badge:FindFirstChild("Num") :: TextLabel?
		if num and order then
			num.Text = tostring(order)
		end
	end
end

local function restyleRows()
	for id, b in pickerRows do
		if b.Parent then
			styleRow(b, table.find(picked, id))
		end
	end
end

-- True when the open picker shows exactly these pets (then a roster update only restyles the rows).
local function samePets(pets: any): boolean
	if type(pets) ~= "table" then
		return false
	end
	local n = 0
	for _, p in pets do
		local b = pickerRows[p.Id]
		if not b or not b.Parent then
			return false
		end
		n += 1
	end
	local have = 0
	for _ in pickerRows do
		have += 1
	end
	return n == have
end

-- Row sizes (Studio check 2026-10-15: the row's words, chip and badge came out tiny at phone size): the row, its
-- type chip and the pick badge stay big enough to read and tap, and every fitted word keeps the shared text floor.
local ROW_H = 76
local ROW_GAP = 6
local CHIP_H = 32

local function petRow(parent: Instance, order: number, p: any, onTap: () -> ()): TextButton
	local pickOrder = table.find(picked, p.Id)
	local b = Instance.new("TextButton")
	b.Name = "Pet_" .. tostring(p.Id)
	b.Text = ""
	b.AutoButtonColor = false
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, ROW_H)
	b.BorderSizePixel = 0
	UI.corner(b, T.Radius)
	UI.stroke(b, TC.InsetEdge, 1.5)
	styleRow(b, pickOrder)
	UI.bouncy(b) -- press squash like every other row and card
	-- the pet's picture on the left (the same 3D view the collection cards use)
	local pic = UI.frame(b, { Name = "Picture", Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(62, 62), BackgroundTransparency = 1 })
	if type(p.Spec) == "table" then
		pcall(GeodeView.make, pic, p.Spec, { Size = UDim2.fromScale(1, 1), Backing = true })
	end
	local nameLabel = UI.text(b, (if type(p.Name) == "string" and p.Name ~= "" then p.Name else speciesName(p.Spec.Mineral or "Pet")) .. "  " .. PetStatView.levelText(tonumber(p.Level) or 1, PetStats.cap(p.Spec)), {
		Name = "Name", Font = UI.Bold, TextSize = T.Body + 1, Position = UDim2.fromOffset(76, 5), Size = UDim2.new(0.5, -80, 0, 26),
		TextColor3 = RARITY_COLOR[p.Rarity] or TC.Text,
	})
	UI.fit(nameLabel, T.Body + 1, T.MinText)
	UI.oneLine(nameLabel) -- long names shrink on one line instead of dropping "Lv" to a second line
	-- type and grade pills read at the name's size (UI.chip's caption size was too small beside it)
	local chips = UI.frame(b, { BackgroundTransparency = 1, Position = UDim2.fromOffset(76, 36), Size = UDim2.new(0.5, -80, 0, CHIP_H) })
	UI.list(chips, Enum.FillDirection.Horizontal, 6)
	local function pill(text: string, color: Color3, order: number)
		local c = UI.chip(chips, text, color, { Size = UDim2.new(1, 0, 1, 0), LayoutOrder = order })
		local lim = Instance.new("UISizeConstraint")
		lim.MaxSize = Vector2.new(124, CHIP_H)
		lim.Parent = c
		local label = c:FindFirstChild("Text") :: TextLabel?
		if label then
			label.Font = UI.Head
			UI.fit(label, T.Body, T.MinText)
			label.TextWrapped = false -- "COSMI / C" broke in two on portrait phones
		end
	end
	pill(string.upper(p.Element), TowerView.TypeColor[p.Element] or TC.Gray, 1)
	-- (the grade pill is gone: it is part of POWER now, and the Pet Book MORE page still names it)
	-- carter's pick: one "bigger = better" POWER number (the same number as the Pet Book, PetStatView.powerOf)
	PetStatsStrip.badge(b, PetStatView.powerOf(p), 0, 28, { Name = "Stats", Position = UDim2.new(0.5, 0, 0, 5) }) -- room on the right for the pick badge
	UI.text(b, p.Basic .. " · " .. p.Move .. " · " .. p.Special .. "!", {
		Name = "Moves", TextSize = T.Small, TextColor3 = TC.Muted, Position = UDim2.new(0.5, 0, 0, 36), Size = UDim2.new(0.5, -46, 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	b.Activated:Connect(onTap)
	b.Parent = parent
	return b
end

function TowerPanel.openPicker()
	if roster == nil or inRun then
		send({ Op = "Open" })
		return
	end
	local towerPanel, body, close, footer = UI.modal("Tower", "TRAINING TOWER", Vector2.new(620, 420), {
		Subtitle = string.format("Every floor trains your pets! Best floor %d · start at %d", roster.Best, roster.Checkpoint),
		Footer = T.Primary.Y + 16, -- the buttons' full height plus the footer padding (64 cut them off at the border)
	})
	PanelSkin.dress(towerPanel, "Tower", "TRAINING TOWER")
	UI.list(body, Enum.FillDirection.Vertical, ROW_GAP)
	if #roster.Pets == 0 then
		UI.emptyState(body, "No pets yet", "Hatch a pet in the egg race first. Then it can fight here!")
	end
	local sorted = table.clone(roster.Pets)
	table.sort(sorted, function(a: any, b: any)
		return PetStatView.powerOf(a) > PetStatView.powerOf(b) -- strongest first, so the numbers read top-down
	end)
	table.clear(pickerRows)
	for i, p in sorted do
		pickerRows[p.Id] = petRow(body, i, p, function()
			local at = table.find(picked, p.Id)
			if at then
				table.remove(picked, at)
			elseif #picked < TowerConfig.TeamSize then
				table.insert(picked, p.Id)
			else
				UI.notify("Your team is full. Tap a pet to take it out.", "info")
				return
			end
			-- the picker stays open: pick the whole team, then CLIMB (the server's roster reply restyles in place)
			restyleRows()
			send({ Op = "SetTeam", Pets = picked })
			UI.notify(string.format("Team %d/%d", #picked, TowerConfig.TeamSize), "info", { Tag = "towerteam" })
		end)
	end
	-- more pets below the buttons: a gold MORE tab between EQUIP BEST and CLIMB! until the last pet is in view
	-- (tapping it scrolls one row down). It lives in the footer, in its own slot: on the list's bottom edge it
	-- covered the last visible row's words (check_layout COVERED, 2026-10-15)
	local moreSlot: Frame? = nil
	if footer then
		UI.list(footer, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		-- both footer buttons fill the footer's padded height: T.Primary.Y (64) px, well over the 44 px touch floor
		UI.button(footer, "EQUIP BEST", "gray", function()
			close()
			send({ Op = "EquipBest" })
		end, { Name = "EquipBest", Size = UDim2.new(0.38, -6, 1, 0), LayoutOrder = 1 })
		moreSlot = UI.frame(footer, { Name = "MoreSlot", BackgroundTransparency = 1, Size = UDim2.new(0.24, -4, 1, 0), LayoutOrder = 2 })
		UI.button(footer, "CLIMB!", "green", function()
			close()
			send({ Op = "Start" })
		end, { Name = "Start", Size = UDim2.new(0.38, -6, 1, 0), LayoutOrder = 3 })
	end
	local lastRow = if #sorted > 0 then pickerRows[sorted[#sorted].Id] else nil
	if lastRow and moreSlot then
		local more = UI.button(moreSlot, "MORE \u{25BC}", "gold", function()
			body.CanvasPosition += Vector2.new(0, ROW_H + ROW_GAP)
		end, { Name = "MorePets", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, math.max(44, UI.minTouch())), TextSize = T.Small, Visible = false })
		local function update()
			local bottom = body.AbsolutePosition.Y + body.AbsoluteSize.Y
			more.Visible = lastRow.AbsolutePosition.Y + lastRow.AbsoluteSize.Y > bottom + 4
		end
		body:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
		body:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
		lastRow:GetPropertyChangedSignal("AbsolutePosition"):Connect(update)
		task.defer(update)
	end
end

-- TOWER entry: a row of the HUD's left column (under PLAY, like the queue card), so it never sits on the thumbstick.
-- Falls back to a fixed spot under the cash if the HUD column is not there.
local function buildEntry()
	local screen = UI.screen()
	local box = screen:WaitForChild("LeftBox", 10) -- the HUD wraps its left column in this box
	local left = if box then box:WaitForChild("Left", 10) else nil
	-- the HUD's mode row (TOWER beside the photo button); green, so it never reads like the gold PLAY button
	local row = if left then left:WaitForChild("ModeRow", 5) or left else nil
	local b: TextButton = HudArt.bigButton(row or screen, {
		Name = "TowerButton", Style = "green", Art = "Tower", Skin = "btn_green", Title = "TOWER", Sub = "Train pets", Width = 172, Height = 60, LayoutOrder = 1,
		OnClick = TowerPanel.openPicker,
	})
	b:SetAttribute("Short", "TRAIN") -- the word on the square phone tile (HudArt.compact)
	entryButton = b
	setBest(if roster then roster.Best else nil)
	if not left then
		b.Position = UDim2.fromOffset(T.Edge, T.Edge + 150)
	end
	local function refresh()
		b.Visible = player:GetAttribute("MatchKey") == nil and player:GetAttribute("InTower") == nil and player:GetAttribute("InBattle") == nil
	end
	player:GetAttributeChangedSignal("InBattle"):Connect(refresh)
	player:GetAttributeChangedSignal("MatchKey"):Connect(refresh)
	player:GetAttributeChangedSignal("InTower"):Connect(refresh)
	refresh()
end

local SPECIAL_W = 160

local function buildHud()
	local g = holder("TowerHud")
	g.Visible = false
	hud = g
	local top = UI.card(g, "hud", { Name = "Floor", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, T.Edge), Size = UDim2.fromOffset(300, 40) })
	-- centred vertically so the floor flip (see flipFloor) squashes toward the middle like a counter card
	floorLabel = UI.text(top, "FLOOR 1", {
		Font = UI.Head, TextSize = T.Head, Outline = "Strong", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	coinsLabel = UI.text(g, "+0 coins", {
		-- beside the floor card (under it, it sat over the boss's name in the 3D view)
		Name = "RunCoins", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Cash, Position = UDim2.new(0.5, 158, 0, T.Edge), Size = UDim2.fromOffset(130, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UI.button(g, "LEAVE", "red", function()
		-- before the first boss floor little is at stake (the coins are kept), so no confirm
		if hudFloor < TowerConfig.BossEvery then
			send({ Op = "Leave" })
			return
		end
		UI.confirm({
			Name = "TowerLeave", Title = "Leave the tower?", Message = "You keep the coins you won.", Confirm = "LEAVE", Cancel = "STAY", Style = "red",
			OnConfirm = function()
				send({ Op = "Leave" })
			end,
		})
	end, { Name = "Leave", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, T.Edge, 0.14, 0), Size = UDim2.fromOffset(100, T.Touch), TextSize = T.Small })
	-- (top-left, under Roblox's menu buttons: under the floor card it covered the boss's bar, bottom-left is the thumbstick)
	-- hit numbers in the 3D view stay below the floor card (viewport px: this layer sits under the top bar)
	TowerView.topClear = function(): number
		if not g.Visible then
			return 0
		end
		local inset = (GuiService:GetGuiInset())
		return inset.Y + top.AbsolutePosition.Y + top.AbsoluteSize.Y
	end
	local sp = UI.button(g, "SPECIAL", "gold", function()
		send({ Op = "Special" })
	end, { Name = "Special", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(SPECIAL_W, T.Primary.Y + 6) })
	specialBtn = sp
	-- charging: the navy of the tab strips with a white, strongly outlined label (grey on grey did not read); paint()
	-- uses these while the button is disabled
	sp:SetAttribute("DisabledFill", K.TabBar)
	sp:SetAttribute("DisabledText", K.White)
	local spl = sp:FindFirstChild("Label")
	if spl then
		UI.outline(spl, "Strong")
	end
	-- ready glow: a soft gold halo behind the button (a sibling, so it shows around it), lit and pulsing only
	-- while SPECIAL is ready (setMeter); place() keeps it centred on the button
	local halo = UI.frame(g, {
		Name = "SpecialGlow", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = K.Gold, BackgroundTransparency = 1,
		ZIndex = math.max(sp.ZIndex - 1, 0),
	})
	UI.corner(halo, T.Radius + 10)
	local haloScale = Instance.new("UIScale")
	haloScale.Parent = halo
	specialGlow = halo
	glowScale = haloScale
	-- charge ring: a gold glow around the button that brightens as the meter fills and pulses when ready
	local glow = UI.frame(sp, {
		Name = "ChargeRing", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 8, 1, 8),
		BackgroundTransparency = 1, ZIndex = 0,
	})
	UI.corner(glow, T.Radius + 4)
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = TC.Gold
	ring.Thickness = 3
	ring.Transparency = 1
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = glow
	chargeRing = ring
	local track, fill = UI.bar(sp, { Name = "Meter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.new(1, 0, 0, 10) }, TC.Gold)
	local _ = track
	meterFill = fill
	-- SPECIAL goes where the hunt's action button goes (TouchLayout, screen px): above Roblox's jump button, or left
	-- of it on the bottom row, never in the thumbstick half of the screen.
	local function place()
		local px = UI.screen().AbsoluteSize
		if px.X < 2 or px.Y < 2 then
			return
		end
		local cam = Workspace.CurrentCamera
		local full = if cam then cam.ViewportSize else px
		local scale = math.max(UI.Scale, 0.1)
		local h = T.Primary.Y + 6 + 16 -- button plus the meter above it
		-- keep the lobby menu column (top right, about 250 tall) free
		local topLimit = px.Y - (T.Edge + 250) * scale
		local r, bottom, mode = TouchLayout.place(full.X, full.Y, h * scale, topLimit, UserInputService.TouchEnabled)
		local w = SPECIAL_W
		if mode == "left" then
			-- stay in the right 60% of the screen (the thumbstick owns the left side)
			w = math.max(96, math.min(w, (px.X * 0.6 - r) / scale))
		end
		sp.Size = UDim2.fromOffset(w, T.Primary.Y + 6)
		sp.Position = UDim2.new(1, -r / scale, 1, -bottom / scale)
		halo.Size = UDim2.fromOffset(w + 22, T.Primary.Y + 6 + 22)
		halo.Position = sp.Position - UDim2.fromOffset(w / 2, (T.Primary.Y + 6) / 2)
	end
	place()
	UI.screen():GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(place)
	end)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
end

local function reducedMotion(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.ReducedMotion == true
end

-- Floor number change: the label flips like a counter card (squashes shut, new text, opens again).
-- Reduce Motion or a wave-only change just swaps the text.
local shownFloor = 0
local flipId = 0
local floorText = "FLOOR 1"
local mobsLeft = -1 -- standing mobs of this wave (-1 = not known yet)
local function labelText(): string
	return if mobsLeft >= 0 then string.format("%s · %d LEFT", floorText, mobsLeft) else floorText
end
local function flipFloor(label: TextLabel, text: string, floor: number, height: number)
	floorText = text
	flipId += 1
	local id = flipId
	local changed = shownFloor ~= 0 and floor ~= shownFloor
	shownFloor = floor
	if not changed or reducedMotion() then
		label.Text = labelText()
		label.Size = UDim2.fromScale(1, height)
		return
	end
	local shut = TweenService:Create(label, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(1, 0) })
	shut.Completed:Connect(function()
		if flipId ~= id then
			return
		end
		label.Text = labelText()
		TweenService:Create(label, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, height) }):Play()
	end)
	shut:Play()
end

-- SPECIAL's ready halo: lit and breathing (bigger and brighter, then back) while ready; steady with Reduce Motion.
local function setGlow(on: boolean)
	for _, tw in glowTweens do
		tw:Cancel()
	end
	table.clear(glowTweens)
	local halo, sc = specialGlow, glowScale
	if not (halo and sc) then
		return
	end
	sc.Scale = 1
	halo.BackgroundTransparency = if on then 0.45 else 1
	if on and not reducedMotion() then
		local info = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		table.insert(glowTweens, TweenService:Create(halo, info, { BackgroundTransparency = 0.8 }))
		table.insert(glowTweens, TweenService:Create(sc, info, { Scale = 1.12 }))
		for _, tw in glowTweens do
			tw:Play()
		end
	end
end

-- the ready ring: pale gold (the pet gold lifted toward white), brighter than the charging ring
local READY_RING = K.Gold:Lerp(K.White, 0.5)

local function setMeter(v: number)
	local f = math.clamp(v / TowerConfig.SpecialCharge, 0, 1)
	if meterFill then
		meterFill.Size = UDim2.fromScale(f, 1)
		meterFill.BackgroundColor3 = if f >= 1 then TC.Gold else K.Cyan -- charging cyan (the HUD squares), ready gold
	end
	local ring = chargeRing
	if ring then
		local full = f >= 1
		if full ~= wasFull then
			wasFull = full
			if ringPulse then
				ringPulse:Cancel()
				ringPulse = nil
			end
			setGlow(full)
			if full then
				Audio.play("RarityAccent", { Volume = 0.6, Key = "tower:special-ready" }) -- the "something good" chime
			end
			if full and not reducedMotion() then
				local btn = specialBtn
				if btn then
					-- ready: the button wiggles once
					task.spawn(function()
						for _, rot in { -6, 6, -4, 4, 0 } do
							if btn.Parent == nil then
								return
							end
							TweenService:Create(btn, TweenInfo.new(0.06, Enum.EasingStyle.Sine), { Rotation = rot }):Play()
							task.wait(0.06)
						end
					end)
				end
				ring.Thickness = 3
				ring.Transparency = 0
				local tw = TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6, Transparency = 0.45 })
				ringPulse = tw
				tw:Play()
			end
		end
		if not full or reducedMotion() then
			ring.Thickness = if full then 5 else 3
			ring.Color = if full then READY_RING else TC.Gold
			-- charging: the ring fades in with the meter (faint at the start, bright just before ready)
			ring.Transparency = if full then 0 else 1 - f * 0.75
		else
			ring.Color = READY_RING
		end
	end
	if specialBtn then
		UI.setEnabled(specialBtn, f >= 1, "gold")
		local label = specialBtn:FindFirstChild("Label") :: TextLabel?
		if label then
			-- charging vs ready, in words (the meter above turns from cool blue to gold)
			label.Text = if f >= 1 then "SPECIAL READY!" else "CHARGING " .. math.floor(f * 100) .. "%"
		end
	end
end

-- Runs `fn` once the avatar stands in the tower (InTower set and near the floor's origin), checking for up to 4 s.
-- A floor end, a newer floor or leaving cancels it (cardToken).
local cardToken = 0
local shownWave = 0 -- floor * 100 + wave of the last Floor message (a repeat, e.g. after a revive, calls nothing out)
local function whenInTower(origin: any, fn: () -> ())
	cardToken += 1
	local id = cardToken
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 4 do
			if id ~= cardToken or not inRun then
				return
			end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if player:GetAttribute("InTower") == true and typeof(origin) == "CFrame" and root and root:IsA("BasePart") and (root.Position - origin.Position).Magnitude < 80 then
				task.wait(0.15) -- one beat for the camera to catch up with the move
				if id == cardToken and inRun then
					fn()
				end
				return
			end
			task.wait(0.1)
		end
	end)
end

-- On entry: puts the camera behind the avatar, looking over the pets at the mobs (it kept the lobby's angle, which
-- often faced the back wall). Once only; the player turns it freely afterwards.
local function faceFight(origin: any)
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and typeof(origin) == "CFrame" and root and root:IsA("BasePart")) or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local fight = origin * Vector3.new(0, 2, 2) -- between the pet line and the mobs
	local back = (root.Position - fight) * Vector3.new(1, 0, 1)
	back = if back.Magnitude > 0.1 then back.Unit else origin.LookVector -- the players' side (-Z)
	cam.CFrame = CFrame.lookAt(root.Position + back * 10 + Vector3.new(0, 6, 0), fight)
end

-- Floor-end card clean-up: one clear choice (its two buttons; the red X corner button goes) and a message that
-- reads at heading size (bug 239). `grow` adds height for the bigger reward row under the message.
local function tidyCard(dialogName: string, grow: number)
	local shade = UI.dialogLayer():FindFirstChild("Dialog_" .. dialogName)
	local panel = shade and shade:FindFirstChild("Panel")
	if not (panel and panel:IsA("Frame")) then
		return
	end
	local x = panel:FindFirstChild("Close")
	if x then
		x:Destroy()
	end
	local title = panel:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Size = UDim2.new(1, -(title.Position.X.Offset + 14), 0, title.Size.Y.Offset)
	end
	local message = panel:FindFirstChild("Message")
	if message and message:IsA("TextLabel") then
		-- keeps the dialog's own message colour (dark ink on the cream card); white here was unreadable
		UI.fit(message, T.Head)
	end
	if grow > 0 then
		panel.Size += UDim2.fromOffset(0, grow)
		local lim = panel:FindFirstChildOfClass("UISizeConstraint")
		if lim then
			lim.MaxSize += Vector2.new(0, grow)
		end
	end
end

-- Floor-end reward line: turns the dialog's price line (UI.confirm Price) into "[coin] +30   [star] +120 PET XP"
-- with the drawn coin and star icons. XP is what the pets earned this climb.
local function rewardRow(dialogName: string, coins: number, xp: number)
	local shade = UI.dialogLayer():FindFirstChild("Dialog_" .. dialogName)
	local panel = shade and shade:FindFirstChild("Panel")
	local slot = panel and panel:FindFirstChild("Price")
	if not (slot and slot:IsA("Frame")) then
		return
	end
	slot:ClearAllChildren()
	slot.Size = UDim2.new(1, -(slot.Position.X.Offset + 14), 0, 34)
	UI.list(slot, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	-- fixed text boxes (UI.text fits the words inside them on narrow phones)
	local function item(icon: string, text: string, color: Color3, width: number, order: number)
		UI.icon(slot, icon, 32, { LayoutOrder = order })
		local l = UI.text(slot, text, { Name = "Reward", Font = UI.Head, TextSize = T.Head + 4, TextColor3 = color, Size = UDim2.fromOffset(width, 34), LayoutOrder = order + 1 })
		l.TextWrapped = false
		UI.pop(l, 0.7, 0.1 * order)
	end
	item("cash", "+" .. UI.num(coins), TC.Cash, 96, 1)
	item("star", string.format("+%s PET XP", UI.num(xp)), TC.Gold, 180, 3)
end

local function onEvent(msg: any)
	if type(msg) ~= "table" then
		return
	end
	if msg.Kind == "Roster" then
		roster = msg
		setBest(msg.Best)
		-- an answer to an older pick must not undo taps still on the way to the server
		if not teamQueued and os.clock() >= teamHoldUntil then
			picked = table.clone(msg.Team or {})
		end
		if not inRun and UI.modalOpen() == "Tower" and samePets(msg.Pets) then
			restyleRows() -- answer to a pick: the open picker stays put (keeps its scroll position)
		elseif not inRun then
			TowerPanel.openPicker()
		end
	elseif msg.Kind == "Floor" then
		local entering = not inRun
		if entering and coinsLabel then
			coinsLabel.Text = "+0 coins"
		end
		hudFloor = msg.Floor or 0
		inRun = true
		UI.closeModal()
		-- a new floor or wave has begun (CONTINUE, a revive, or the Studio /boss jump): the last floor's end card
		-- and its dim backdrop must not hang over the fight. Closing it this way fires no button callback, and it
		-- also closes Sticky cards (the revive offer).
		if UI.dialogOpen() == "TowerFloor" then
			UI.closeDialog()
		end
		if hud then
			hud.Visible = true
		end
		if floorLabel then
			-- every 10 floors the number gets bigger and goldener (the label is centred, so it grows both ways)
			local tier = math.min(math.floor(msg.Floor / 10), 3)
			-- the pet gold (TC.Gold read dark on the navy card) or white, both under the strong dark outline
			floorLabel.TextColor3 = if tier >= 1 then K.Gold else K.White
			-- "BOSS" only on the boss's own wave (the normal mobs before it read as the boss)
			local bossWave = msg.Boss and msg.Wave == msg.Waves
			flipFloor(floorLabel, string.format("%sFLOOR %d · WAVE %d/%d", if bossWave then "BOSS " else "", msg.Floor, msg.Wave, msg.Waves), msg.Floor, 1 + 0.12 * tier)
		end
		local waveKey = (msg.Floor or 0) * 100 + (msg.Wave or 1)
		local newWave = waveKey ~= shownWave
		shownWave = waveKey
		if newWave and (msg.Wave or 1) > 1 then
			-- a new wave on the same floor: a short call-out (text only, no backdrop, so the fight stays in view)
			local last = msg.Wave == msg.Waves
			Juice.banner(string.format("%s %d/%d!", if last and msg.Boss then "BOSS WAVE" else "WAVE", msg.Wave, msg.Waves), if last then K.RedTop else TC.Gold, 1.1)
		end
		-- only a new theme gets a title card ("JUNGLE FLOORS!"); the HUD's floor label already names every floor (a
		-- "FLOOR 3 / Jungle" card on each floor hung over the middle of the room)
		local themeCard = msg.Wave == 1 and msg.Theme ~= nil and (msg.Floor - 1) % TowerConfig.ThemeEvery == 0
		if themeCard or entering then
			local glow = TC.Gold
			for _, th in TowerConfig.Themes do
				if th.Name == msg.Theme then
					glow = th.Glow
				end
			end
			local title = string.upper(tostring(msg.Theme))
			local sub = string.format("FLOORS %d-%d", msg.Floor, msg.Floor + TowerConfig.ThemeEvery - 1)
			-- only once we are really standing in the tower (the first floor's message lands while the lobby is
			-- still on screen); on entry the camera turns to the fight first
			whenInTower(msg.Origin, function()
				if entering then
					faceFight(msg.Origin)
					UI.notify("Your pets fight for you. Tap SPECIAL when it glows!", "info", { Tag = "towertip" })
				end
				if themeCard then
					TowerFx.titleCard(title, sub, glow)
				end
			end)
		end
		setMeter(0)
		TowerView.floor(msg)
	elseif msg.Kind == "Events" then
		TowerView.events(msg.List, msg.Hp)
		setMeter((msg.Meters or {})[tostring(player.UserId)] or (msg.Meters or {})[player.UserId] or 0)
	elseif msg.Kind == "FloorEnd" then
		-- the floor's title card goes first so it never covers the floor-end card's words
		cardToken += 1
		TowerFx.hideTitle()
		TowerView.hush() -- no hit number or SPECIAL! word behind the card
		setMeter(0)
		setBest(msg.Best)
		if coinsLabel then
			coinsLabel.Text = "+" .. UI.money(msg.RunCoins or 0)
		end
		if msg.Drop then
			UI.notify(string.format("TOWER PET! You found %s!", msg.Drop), "ok")
		end
		if msg.Result == "Cleared" then
			TowerView.cleared()
			UI.confirm({
				Name = "TowerFloor", Title = string.format("FLOOR %d CLEARED!", msg.Floor),
				Message = string.format("Ready for floor %d?", msg.Floor + 1),
				Price = msg.Coins, -- reserves the reward line under the message (filled by rewardRow)
				-- Sticky: a stray tap outside or Escape must not leave the climb (audit 17); only its buttons act
				Confirm = "CONTINUE", Cancel = "LEAVE", Style = "green", Sticky = true,
				OnConfirm = function()
					send({ Op = "Next" })
				end,
				OnCancel = function()
					send({ Op = "Leave" })
				end,
			})
			tidyCard("TowerFloor", 10)
			rewardRow("TowerFloor", msg.Coins or 0, msg.Xp or 0)
		elseif (msg.Paid or 0) > 0 then
			UI.confirm({
				Name = "TowerFloor", Title = "Your pets fainted!",
				Message = string.format("Revive for %s and keep going (%d left this climb), or leave with %d coins and %d XP.", reviveCost(), msg.Paid, msg.RunCoins, msg.Xp),
				Confirm = "REVIVE (" .. reviveCost() .. ")", Cancel = "LEAVE", Style = "green", Sticky = true,
				OnConfirm = function()
					send({ Op = "BuyRevive" })
				end,
				OnCancel = function()
					send({ Op = "Leave" })
				end,
			})
			tidyCard("TowerFloor", 0)
		elseif (msg.Revives or 0) > 0 then
			UI.confirm({
				Name = "TowerFloor", Title = "Your pets fainted!",
				Message = string.format("Revive once for free and keep going, or leave with %d coins and %d XP.", msg.RunCoins, msg.Xp),
				Confirm = "REVIVE", Cancel = "LEAVE", Style = "green", Sticky = true,
				OnConfirm = function()
					send({ Op = "Revive" })
				end,
				OnCancel = function()
					send({ Op = "Leave" })
				end,
			})
			tidyCard("TowerFloor", 0)
		else
			UI.confirm({
				Name = "TowerFloor", Title = "Your pets fainted!",
				Message = string.format("You keep %d coins and %d XP. Best floor: %d. Try again!\n%s %s", msg.RunCoins, msg.Xp, msg.Best, LOSE_TIPS[(msg.Floor or 1) % #LOSE_TIPS + 1], LOSE_TIPS[((msg.Floor or 1) + 1) % #LOSE_TIPS + 1]),
				Confirm = "BACK TO LOBBY", NoCancel = true, Style = "gold",
				OnConfirm = function()
					send({ Op = "Leave" })
				end,
				OnCancel = function()
					send({ Op = "Leave" })
				end,
			})
			tidyCard("TowerFloor", 0)
		end
	elseif msg.Kind == "Closed" then
		inRun = false
		wasFull = false
		hudFloor = 0
		shownFloor = 0
		shownWave = 0
		mobsLeft = -1
		if ringPulse then
			ringPulse:Cancel()
			ringPulse = nil
		end
		setGlow(false)
		roster = nil
		cardToken += 1
		TowerFx.hideTitle()
		UI.closeDialog()
		if hud then
			hud.Visible = false
		end
		TowerView.clear()
		-- back in the lobby: once the server has moved the avatar, put the camera behind it looking ahead
		-- (otherwise it keeps the tower's angle and can end up inside the portal glow)
		task.delay(0.3, function()
			local cam = Workspace.CurrentCamera
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if cam and root and root:IsA("BasePart") and cam.CameraType == Enum.CameraType.Custom and not inRun then
				local p = root.Position
				cam.CFrame = CFrame.lookAt(p - root.CFrame.LookVector * 10 + Vector3.new(0, 5, 0), p + Vector3.new(0, 1.5, 0))
			end
		end)
	elseif msg.Kind == "Notice" then
		UI.notify(tostring(msg.Text), "info")
	end
end

function TowerPanel.start()
	if TowerConfig.Revive.ProductId ~= 0 then
		fetchRevivePrice() -- read the price early so the fainted card already has it
	end
	local net = game:GetService("ReplicatedStorage"):WaitForChild("TowerNet")
	local action = net:WaitForChild("TowerAction") :: RemoteEvent
	local event = net:WaitForChild("TowerEvent") :: RemoteEvent
	local outbox: { any } = {}
	local lastSent = -math.huge
	local pumping = false
	local function pump()
		while #outbox > 0 do
			local left = lastSent + SEND_GAP - os.clock()
			if left > 0 then
				task.wait(left)
			end
			local msg = table.remove(outbox, 1)
			if msg.Op == "SetTeam" then
				teamQueued = false
				teamHoldUntil = os.clock() + 0.6
			end
			lastSent = os.clock()
			action:FireServer(msg)
		end
		pumping = false
	end
	send = function(msg)
		if type(msg) ~= "table" then
			return
		end
		local queued = false
		for i, m in outbox do
			if m.Op == msg.Op then
				if msg.Op == "SetTeam" then
					outbox[i] = { Op = "SetTeam", Pets = table.clone(msg.Pets) } -- newest picks win
				end
				queued = true
				break
			end
		end
		if not queued then
			if msg.Op == "SetTeam" then
				msg = { Op = "SetTeam", Pets = table.clone(msg.Pets) } -- a snapshot: later taps edit `picked` in place
				teamQueued = true
			end
			table.insert(outbox, msg)
		end
		if not pumping then
			pumping = true
			task.spawn(pump)
		end
	end
	task.spawn(buildEntry) -- waits for the HUD column
	buildHud()
	-- enemies left on this wave, shown on the floor card (bug 242)
	TowerView.onMobsLeft = function(left: number, _total: number)
		mobsLeft = left
		if floorLabel then
			floorLabel.Text = labelText()
		end
	end
	event.OnClientEvent:Connect(onEvent)
end

return TowerPanel
