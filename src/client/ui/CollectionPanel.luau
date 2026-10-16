--!strict
-- COLLECTION (boards 6 and 7, additional 4 and 5). Tabs:
--   Collection  owned specimens as cards (real 3D thumbnails) and the selected specimen's view: name, rarity,
--               mass, value, display slot usage, PLACE ON DISPLAY / REMOVE FROM DISPLAY, favourite and the separate,
--               confirmed SELL. Empty: "No geodes yet." with START HUNT (the real Start Hunt panel).
--   Display     the real lobby display slots (Profiles.displaySlots): pick a slot, place an owned specimen, replace
--               or remove; the server keeps the list dense and updates the world display.
--   Index       (Book) every pet species by zone with its hatch chance in that zone (species are equally likely
--               within a zone), and the rarity odds from Config.RarityWeights (plus your Luck pet's odds);
--               unfound species are plain silhouettes.
--   Records     Solo finds, Competitive wins and Matches played from the server's profile; an unavailable profile
--               shows "Records unavailable" with RETRY / CLOSE (never made-up zeros).
--   Stats       the other stats (eggs cracked, coins earned, best pet, pets owned, your pet's boost) and badges.
-- Collection storage ("Owned n / max") and display capacity ("Display slots n / N") are always shown apart.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local EggPerks = require(Shared.EggPerks)
local SpeciesPool = require(Shared.SpeciesPool)
local GeodeGen = require(Shared.GeodeGen)
local UiMotion = require(Shared.UiMotion)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local HudArt = require(script.Parent.HudArt)
local Theme = require(script.Parent.Theme)
local GeodeView = require(script.Parent.GeodeView)
local Materials = require(Shared.Materials)
local MaterialThumb = require(script.Parent.MaterialThumb)
local PartyPanel = require(script.Parent.PartyPanel)
local ProgressConfig = require(Shared.ProgressConfig)
local PetRules = require(Shared.PetRules)
local Juice = require(script.Parent.Juice)
local PetStatView = require(Shared.PetStatView)
local PetStatsStrip = require(script.Parent.PetStatsStrip)
local PetStyle = require(script.Parent.PetStyle)
local UiJuice = require(script.Parent.UiJuice)
local LaunchPerks = require(Shared.LaunchPerks)

local T = UI.T
local TC = Theme.Color
local PET = Theme.Pet

-- The profile view the server syncs (Profiles.publicView) and one pet in it (GeodeGen.public), read loosely.
type Prof = { [string]: any }
type Pet = { [string]: any }
local Collection = {}
Collection.onTeamFull = nil :: ((string) -> ())? -- Main: MY PETS asks which team slot to swap

local PAGE = 30
local tab = "Collection"
local sortBy = "Rarity" -- "Newest" | "Rarity" | "Level" | "Type" (PetRules.sort)
local favOnly = false
local bookZone = "All" -- Pet Book zone filter: "All" or a zone name (Config.Tiers[..].Name)
local page = 1
local sellMode = false
local picked: { [string]: boolean } = {}
local detail: string? = nil
local moreOpen: string? = nil -- the pet whose detail shows the MORE stats page instead of its picture
local slotSel = 1 -- Display tab: the selected slot
local placing: string? = nil -- Display tab: a specimen waiting for a slot (from PLACE ON DISPLAY on a full display)
local picker = false -- Display tab: choosing a specimen for the selected slot
local body: Frame? = nil
local open = false
local panelRef: Frame? = nil
local closeRef: (() -> ())? = nil
local recordsWaitUntil = 0
local animateIn = false -- the next render pops its cards / rows in (set when the panel opens or the tab changes)
-- Pets that arrived since the player last looked (UiMotion.freshIds): their cards wear a red "!" and a soft glow
-- until tapped or until the Pet Book closes. nil before the first profile (nothing is new then).
local knownPets: { [string]: boolean }? = nil
local freshPets: { [string]: boolean } = {}
local function trackFresh(prof: any)
	if type(prof) ~= "table" or type(prof.Inventory) ~= "table" then
		return
	end
	local ids = {}
	for _, x in prof.Inventory do
		table.insert(ids, tostring(x.Id))
	end
	local known, fresh = UiMotion.freshIds(knownPets, ids)
	knownPets = known
	for _, id in fresh do
		freshPets[id] = true
	end
end
local equipFlip: string? = nil -- the pet whose EQUIP was just tapped: its tick flips in once the server agrees

local RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- `px` real pixels in logical units at the current layer scale (a 44 logical chip drew 36 real px on the Studio
-- phone window, so chip heights are set from the real size they must reach)
local function realPx(px: number): number
	return math.ceil(px / math.max(UI.Scale, 0.5))
end

-- Chip / tab-like buttons (sort, filter, zone): at least 40 real px tall, never under the touch size
local function chipH(): number
	return math.max(T.Touch, realPx(40))
end

-- A button caption on one line: TextScaled text wraps whatever TextWrapped says, so the label box is made one line
-- tall (centred in the button); the word then shrinks to the text floor instead of breaking mid-word ("NAM / E",
-- "UNEQ / UIP"). Callers that move the label (tick, icon) keep its Y scale and offset.
local function oneLine(b: GuiButton, size: number?)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		local sz = size or T.Body + 1
		local lineH = math.ceil(sz * 1.3)
		l.TextWrapped = false
		l.AnchorPoint = Vector2.new(0, 0)
		l.Position = UDim2.new(0, 6, 0.5, -math.floor(lineH / 2))
		l.Size = UDim2.new(1, -12, 0, lineH)
		UI.fit(l, sz, T.MinText)
		l.TextWrapped = false
	end
end

local function act(action: string, a: any?, b: any?)
	Net.event("CollectionAction"):FireServer(action, a, b)
end

local function slotOf(prof: Prof, id: string): number?
	return table.find(prof.DisplayAssignments, id)
end

local function findGeode(prof: Prof, id: string?): Pet?
	if not id then
		return nil
	end
	for _, g in prof.Inventory do
		if g.Id == id then
			return g
		end
	end
	return nil
end

local function sortedList(prof: Prof): { Pet }
	local list: { Pet } = {}
	for _, g in prof.Inventory do
		if favOnly and not g.Favorite then
			continue
		end
		table.insert(list, g)
	end
	PetRules.sort(list, sortBy)
	return list
end

-- Pet type (BoostKind): icon name and glow colour on cards, follower tags and the detail line.
local TYPE_ICON = { Coins = "boostCoins", Speed = "boostSpeed", Luck = "boostLuck" }

local function typeIcon(g: Pet): string
	return TYPE_ICON[PetRules.kindOf(g)] or "boostCoins"
end

local function sellable(prof: Prof, g: Pet): boolean
	return not g.Favorite and not slotOf(prof, g.Id)
end

local render

local function geodePicture(g: Pet)
	return function(c: Instance)
		local vp, model, cam = GeodeView.make(c, g, { Size = UDim2.fromScale(1, 1), Backing = true })
		GeodeView.frame(cam, model, 0.75) -- a closer frame: the pet fills its card instead of floating small in it
		Juice.turntable(vp, model) -- slow sway (capped, on-screen cards only)
	end
end

-- Rarity glow for a pet card: border in the rarity colour, shimmering from Epic up (UI.rarityGlow).
local function rarityOpts(g: Pet): (Color3?, boolean, Color3?)
	return Config.RarityColors[g.Rarity], (RANK[g.Rarity] or 0) >= 4, Config.RarityTextColors[g.Rarity]
end

local function confirmSell(prof: Prof, ids: { string }, from: GuiObject?)
	local total, count, rare = 0, 0, 0
	for _, g in prof.Inventory do
		if table.find(ids, g.Id) then
			total += g.Value
			count += 1
			if RANK[g.Rarity] >= 4 then
				rare += 1
			end
		end
	end
	UI.confirm({
		Name = "ConfirmSell",
		Title = "Sell " .. count .. " pet" .. (if count == 1 then "" else "s") .. "?",
		Message = (if rare > 0 then rare .. " Epic or Legendary! " else "") .. "They leave your Pet Book for good.",
		Icon = "egg",
		Price = total,
		Confirm = "SELL",
		Style = "red",
		OnConfirm = function()
			if from then
				Juice.coinSource(from) -- the sale's coins fly from the SELL button once the server pays
			end
			act("Sell", ids, total)
			table.clear(picked)
			sellMode = false
			detail = nil
			render()
		end,
	})
end

local KIND_WORD = PetStatView.KindWord

-- Free renaming: the server filters the name and saves it (PetService "RenamePet"); empty clears it.
local function askRename(g: Pet)
	UI.confirm({
		Name = "RenamePet",
		Title = "Name your pet",
		Picture = function(c: Instance)
			GeodeView.make(c, g, { Size = UDim2.fromScale(1, 1) })
		end,
		Input = { Text = g.Nickname or "", Placeholder = GeodeGen.displayName(g), MaxLength = Config.Pets.NameMax },
		Confirm = "SAVE",
		OnConfirm = function(text: string?)
			act("RenamePet", g.Id, text or "")
		end,
	})
end

local function isFollowing(prof: Prof, id: string): boolean
	return table.find(prof.EquippedPets or {}, id) ~= nil
end

local function petSlots(prof: Prof): number
	return prof.PetSlots or Config.Pets.Slots
end

local function countsLine(prof: Prof): string
	return "Owned " .. #prof.Inventory .. "/" .. prof.InventoryMax .. "   Following " .. #(prof.EquippedPets or {}) .. "/" .. petSlots(prof)
end

-- Selected specimen view (board 6, right): name, facts, picture, display usage, actions.
-- SHINY (LaunchPerks.Shiny, 1 in 100 pets): a small gold star tag. The pet's name already starts with "Shiny "
-- (GeodeGen.displayName), so the tag is the only other place the word shows: on the card, and beside the detail name.
local function isShiny(g: Pet): boolean
	return g.Shiny == true
end

-- A card's caption (or, `long`, the detail's name): the name minus the "Shiny " a shiny pet's name starts with (the
-- gold SHINY tag beside it says it, and "Shiny Unicorn" wrapped to two lines on a phone card). A nickname shows as it is.
local function cardLabel(g: Pet, long: boolean?): string
	local s = PetRules.label(g, not long)
	if isShiny(g) and not (type(g.Nickname) == "string" and g.Nickname ~= "") and string.sub(s, 1, 6) == "Shiny " then
		return string.sub(s, 7)
	end
	return s
end

local function shinyTag(parent: Instance, h: number, props: { [string]: any }): Frame
	local tg = PetStyle.ribbon(parent, "SHINY", PET.Gold, props)
	tg.Name = "ShinyBadge"
	PetStyle.vgrad(tg, PET.Gold:Lerp(PET.White, 0.35), PET.RibbonGold)
	local l = tg:FindFirstChildOfClass("TextLabel")
	if l then
		l.ZIndex = tg.ZIndex + 2
		l.TextColor3 = PET.TitleEdge
		local o = l:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			o.Enabled = false
		end
		l.Position = UDim2.fromOffset(h - 2, 0)
		l.Size = UDim2.new(1, -(h + 2), 1, 0)
		l.TextWrapped = false
		UI.fit(l, T.Tiny, T.MinText)
	end
	UI.icon(tg, "star", h - 6, { Name = "Star", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), ZIndex = tg.ZIndex + 2 })
	return tg
end

-- Repeating glint on the Pet Book cards (carter asked for motion): SHINY cards get UiJuice.sweep every ~2.5 s,
-- Legendary cards the same band every ~4 s. One loop per render (the generation stops an older loop), one sweep
-- instance per card at a time (sweep itself refuses a second), nothing per frame; off under Reduce Motion.
local GLINT_SHINY = 2.5
local GLINT_LEGEND = 4
local glintGen = 0

local function startGlints(cards: { { card: GuiObject, every: number } })
	glintGen += 1
	local gen = glintGen
	if #cards == 0 or UiJuice.still() then
		return
	end
	task.spawn(function()
		local t = 0
		local STEP = 0.5
		while gen == glintGen do
			task.wait(STEP)
			t += STEP
			if gen ~= glintGen or UiJuice.still() then
				return
			end
			local alive = 0
			for _, g in cards do
				if g.card.Parent then
					alive += 1
					if math.floor(t / g.every) ~= math.floor((t - STEP) / g.every) then
						UiJuice.sweep(g.card, T.Radius)
					end
				end
			end
			if alive == 0 then
				return
			end
		end
	end)
end

local FACTS_H = 38 -- the facts line: two lines of 14 px words
local NOTE_H = 0 -- no bonus note any more: POWER and MORE on the picture say it (pet stats rework)
local DETAIL_MIN_H = 224 + (FACTS_H - 21) + NOTE_H -- name + facts, a small 3D pet, the bonus note and two button rows
-- The clip's pet card (pet style): a holo blue gradient with a cyan glow edge and a faint white pattern, resting a
-- little tilted and leaning toward the pointer (desktop only; touch leaves it still). Reduce Motion keeps it flat.
local function holoCard(f: Frame)
	local PET = Theme.Pet
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Name = "Holo"
	g.Rotation = 70
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PET.Holo[1]),
		ColorSequenceKeypoint.new(0.5, PET.Holo[2]),
		ColorSequenceKeypoint.new(1, PET.Holo[3]),
	})
	g.Parent = f
	local border = f:FindFirstChild("Border")
	if border and border:IsA("UIStroke") then
		border.Color = PET.HoloEdge
		border.Thickness = 2.5
	end
	-- the glow: a soft cyan ring just outside the edge (a sibling-free stroke on the card itself, drawn wide and faint)
	local glow = Instance.new("UIStroke")
	glow.Name = "Glow"
	glow.Color = PET.HoloGlow
	glow.Thickness = 7
	glow.Transparency = 0.55
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Parent = f
	UI.pattern(f, Color3.new(1, 1, 1), 0.82, 30, 260, DETAIL_MIN_H)
	if UI.Reduced or not UserInputService.MouseEnabled then
		return
	end
	local rest = -2.5
	f.Rotation = rest
	f.MouseLeave:Connect(function()
		UI.spring(f, Theme.Spring.Release, { Rotation = rest })
	end)
	f.MouseMoved:Connect(function(x: number)
		local w = f.AbsoluteSize.X
		if w < 1 then
			return
		end
		local dx = math.clamp(((x - f.AbsolutePosition.X) / w - 0.5) * 2, -1, 1)
		UI.spring(f, { 0.55, 5 }, { Rotation = rest + dx * 2 })
	end)
end

local function renderDetail(side: GuiObject, prof: Prof, g: Pet)
	-- Short landscape phones (678 x 310: the side column is ~130 logical tall once the menu clears Roblox's top-left
	-- buttons) cannot fit the detail, so it sits in a scroller at its smallest height and scrolls; taller screens see
	-- the scroller's canvas match its window (nothing to scroll).
	local host = UI.scroller(side, { Name = "DetailScroll", AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollBarThickness = 6 })
	-- a narrow column (a short landscape window, or under ~220 logical px wide): the action buttons stack in
	-- full-width rows, so no caption ever breaks mid-word (Studio phone window 844 x 390)
	-- (the column's width from the layout numbers, not AbsoluteSize: that read small before the first layout pass)
	local modalW = if UI.Logical.Y >= 600 then 780 else 700
	local sideW = (math.min(UI.Logical.X - 24, modalW) - 2 * T.Pad) * 0.4 - 4
	local stack = not UI.isPortrait() and (UI.isShort() or sideW < 220)
	local btnH = T.Touch -- every row keeps the full tap height; the compact header pays for the third row
	local twoRows = not stack
	local actH = if twoRows then 2 * T.Touch + 6 else 3 * btnH + 12
	local minH = DETAIL_MIN_H + (actH - (2 * T.Touch + 6))
	-- the stacked rows would push the card past a short column (it would scroll, cutting FAV / SELL under the
	-- fold): then the compact header takes over (the stats row in place of the facts line, see `short` below),
	-- which frees enough for the three rows to show whole
	local hostH = host.AbsoluteSize.Y / math.max(UI.Scale, 0.01)
	local forceShort = stack and hostH > 0 and hostH < minH
	if forceShort then
		minH = math.max(hostH, minH - 55) -- 55: the facts line and the full stats row against the compact row
	end
	local f = UI.card(host, "inset", { Name = "Detail", Size = UDim2.new(1, 0, 0, minH) })
	if Theme.PetStyle then
		holoCard(f)
	end
	local function fitDetail()
		local h = math.max(host.AbsoluteSize.Y / math.max(UI.Scale, 0.01), minH)
		local scrolls = h > host.AbsoluteSize.Y / math.max(UI.Scale, 0.01) + 0.5
		f.Size = UDim2.new(1, if scrolls then -8 else 0, 0, math.floor(h))
		host.CanvasSize = UDim2.fromOffset(0, math.floor(h))
	end
	host:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitDetail)
	fitDetail()
	UI.pad(f, 8, 6)
	local isDisp = slotOf(prof, g.Id)
	local smallW = 66 -- NAME / MORE: wide enough for the word on one line at the text floor
	local shiny = isShiny(g)
	local SHINY_W = if shiny then 86 else 0 -- the gold SHINY tag right of the name (the name box gives it room)
	local name = UI.text(f, cardLabel(g, true), { Name = "Name", Font = UI.Head, TextSize = T.Head, TextColor3 = Config.RarityTextColors[g.Rarity] or TC.Text, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -(smallW + 4) - 28 - SHINY_W, 0, 26), TextXAlignment = Enum.TextXAlignment.Center })
	name.TextWrapped = false
	UI.fit(name, T.Head, T.MinText) -- long names ("Rainbow Infernal Hydra") shrink to fit instead of cutting off
	UI.oneLine(name) -- below the text floor too: "Rainbow Sunpetal Drake" lost "Drake" at the floor (Studio 2026-10-16)
	UI.icon(f, typeIcon(g), 22, { Name = "TypeIcon", Position = UDim2.fromOffset(0, 2) })
	if shiny then
		local badge = shinyTag(f, 20, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(smallW + 6), 0, 13), Size = UDim2.fromOffset(SHINY_W - 6, 20), Rotation = -3 })
		UI.pop(badge, 0.6) -- the badge pops in with the detail
	end
	local rename = UI.button(f, "NAME", "gray", function()
		askRename(g)
	end, { Name = "Rename", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(smallW, btnH), TextSize = T.Small + 1 })
	oneLine(rename, T.Small + 1)
	-- One facts line (rarity, variant multiplier, hunt bonus, display state); POWER and "Lv 7/20" sit on the picture.
	local following = isFollowing(prof, g.Id)
	local nickLine = if type(g.Nickname) == "string" and g.Nickname ~= "" then GeodeGen.displayName(g, true) .. " \u{b7} " else ""
	local variant = PetStatView.variantTag(g)
	local facts = UI.text(f, nickLine .. g.Rarity .. (if variant then " \u{b7} " .. variant else "") .. " \u{b7} " .. PetStatView.bonusText(g) .. (if following then " \u{b7} following" elseif isDisp then " \u{b7} on display" else ""), {
		Name = "Facts", Font = UI.Bold, TextSize = T.Body, TextColor3 = Config.RarityTextColors[g.Rarity] or (if Theme.PetStyle then TC.Text else TC.Muted), Outline = "Normal", RichText = true,
		Position = UDim2.fromOffset(0, 25), Size = UDim2.new(1, -(smallW + 4), 0, FACTS_H), TextXAlignment = Enum.TextXAlignment.Center,
	})
	-- two lines at most: at the 14 px text floor a long facts line no longer fits one line of a phone's side column
	facts.TextWrapped = true
	UI.fit(facts, T.Body)
	-- two 44 px rows (on small phones UI.button pads the hit areas to 44 real px as well): EQUIP and PLACE share a
	-- row so the 3D pet keeps most of the height; a narrow column stacks them (three rows, see `stack`)
	local placePos = if twoRows then UDim2.new(0.42, 3, 0, 0) else UDim2.fromOffset(0, btnH + 6)
	local placeSize = if twoRows then UDim2.new(0.58, -3, 0, T.Touch) else UDim2.new(1, 0, 0, btnH)
	local view, viewModel, viewCam = GeodeView.make(f, g, { Name = "Specimen", Position = UDim2.fromOffset(0, 27 + FACTS_H), Size = UDim2.new(1, 0, 1, -(27 + FACTS_H + actH + 6 + NOTE_H)), Backing = not Theme.PetStyle }, true)
	if Theme.PetStyle then
		-- the clip's card: a soft white burst behind the pet instead of a boxed backing
		local burst = UI.frame(f, { Name = "Burst", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5), Position = view.Position + UDim2.new(0.5, 0, 0, 0) + UDim2.new(0, 0, 0.5, -((27 + FACTS_H + actH + 6 + NOTE_H) / 2)), Size = UDim2.new(0.8, 0, 0.8, 0), ZIndex = 0 })
		burst.Position = UDim2.new(0.5, 0, 0, view.Position.Y.Offset)
		burst.Size = view.Size
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = burst
		burst.AnchorPoint = Vector2.new(0.5, 0)
		UI.corner(burst, 999)
		local bg = Instance.new("UIGradient")
		bg.Rotation = 90
		bg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 0.9) })
		bg.Parent = burst
	end
	GeodeView.frame(viewCam, viewModel, 0.7) -- closer: the pet fills its box
	Juice.turntable(view, viewModel) -- sways until touched (a drag pauses it)
	-- one small line under the facts: a shiny pet's doubled sell value (LaunchPerks.Shiny.ValueMult), and / or why a
	-- Robux pet sells low (the server pays a small share of its value)
	local tagBits = {}
	if shiny then
		table.insert(tagBits, "Shiny \u{b7} " .. LaunchPerks.Shiny.ValueMult .. "x sell value")
	end
	if g.Bought == true then
		table.insert(tagBits, "Robux pet \u{b7} low sell price")
	end
	local tagLine = #tagBits > 0
	local tagLabel: TextLabel? = nil
	if tagLine then
		local tl = UI.text(f, table.concat(tagBits, "  \u{b7}  "), {
			Name = if shiny then "ShinyTag" else "RobuxTag", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = if shiny then PET.RibbonGold else TC.Muted, Outline = "Normal",
			Position = UDim2.fromOffset(0, 29 + FACTS_H), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
		})
		tl.TextWrapped = false
		tl.TextTruncate = Enum.TextTruncate.AtEnd
		tagLabel = tl
	end
	local actions = UI.frame(f, { Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, actH) })
	-- carter's pick: ONE "bigger = better" POWER number on the picture, with a green up / red down arrow against the
	-- pet that follows you; MORE (top right) shows every stat in plain words (PetStatsStrip / PetStatView)
	local other: Pet? = nil
	local firstId = (prof.EquippedPets or {})[1]
	if firstId and firstId ~= g.Id then
		for _, o in prof.Inventory do
			if o.Id == firstId then
				other = o
			end
		end
	end
	-- Short landscape phones leave no picture between the header and the buttons, so there the row replaces the
	-- facts line (rarity shows as the name's colour) and the whole row opens MORE (NAME holds the top right).
	-- (measured: the picture's own height in layout units; under ~44 there is no room for a row on top of it)
	local viewH = view.AbsoluteSize.Y / math.max(UI.Scale, 0.01)
	local short = forceShort or (if viewH > 0 then viewH < 44 else UI.isShort())
	local statH = if short then 22 else 36
	local stats: GuiObject
	if short then
		local hit = Instance.new("TextButton")
		hit.Name = "Stats"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Position = UDim2.fromOffset(0, 24)
		hit.Size = UDim2.new(1, -(smallW + 4), 0, statH)
		hit.ZIndex = view.ZIndex + 2
		hit.Parent = f
		stats = hit
		facts.Visible = false
		if tagLabel and forceShort then
			-- a short column (stacked buttons right under the row) has no room for it: it sat behind EQUIP; the SELL
			-- button shows the doubled price anyway
			tagLabel.Visible = false
		end
	else
		stats = UI.frame(f, { Name = "Stats", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 48 + (FACTS_H - 21) + (if tagLine then 16 else 0)), Size = UDim2.new(1, 0, 0, statH), ZIndex = view.ZIndex + 2 })
	end
	local moreW = smallW
	local badge = PetStatsStrip.badge(stats, PetStatView.power(g), PetStatView.compare(g, other), statH, { Position = UDim2.fromOffset(2, 0) })
	-- level next to POWER: how far it has grown and how far its rarity lets it grow (carter, 2026-10-14)
	local lv, cap = PetStatView.levelOf(g)
	local lvW = (if badge then badge.Size.X.Offset else 0) + 6
	local lvChip = PetStatsStrip.level(stats, lv, cap, if short then statH - 2 else statH - 8, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, lvW, 0.5, 0) })
	if short then
		-- the hunt bonus (and variant) after the level, then an info dot that says "tap for more"
		local x0 = lvW + lvChip.Size.X.Offset + 6
		local bits = UI.text(stats, (if variant then variant .. " \u{b7} " else "") .. PetStatView.bonusText(g), {
			Name = "Facts", Font = UI.Bold, TextSize = T.Small, TextColor3 = Config.RarityTextColors[g.Rarity] or TC.Muted, Outline = "Normal",
			Position = UDim2.fromOffset(x0, 0), Size = UDim2.new(1, -(x0 + 22), 1, 0),
		})
		-- one line, cut with "..." when the row is narrow (the 14 px floor can't shrink it, and wrapping stacked it
		-- into a column over the name on desk)
		bits.TextScaled = false
		bits.TextSize = math.max(T.Small, 14)
		bits.TextWrapped = false
		bits.TextTruncate = Enum.TextTruncate.AtEnd
		-- too narrow for the whole line: hide it (the row still opens MORE, which says the same in full)
		local function fitsBits()
			bits.Visible = bits.TextFits
		end
		bits:GetPropertyChangedSignal("TextFits"):Connect(fitsBits)
		bits:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitsBits)
		fitsBits()
		local hint = UI.icon(stats, "info", 18, { Name = "MoreHint", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
		-- the info dot is only a hint (the whole row opens MORE): it steps aside when the level pill reaches it, so the
		-- pill is never covered (Studio 2026-10-16: "Lv 50 MAX" read "Lv 50 MA")
		local function clearHint()
			hint.Visible = UiMotion.clearOf(lvChip.AbsolutePosition.X + lvChip.AbsoluteSize.X, hint.AbsolutePosition.X, 2)
		end
		lvChip:GetPropertyChangedSignal("AbsoluteSize"):Connect(clearHint)
		lvChip:GetPropertyChangedSignal("AbsolutePosition"):Connect(clearHint)
		hint:GetPropertyChangedSignal("AbsolutePosition"):Connect(clearHint)
		clearHint()
	end
	-- MORE covers the picture and the buttons (portrait phones left the picture only a few lines tall) with every
	-- stat in plain words, and a BACK button under them
	local moreHost = UI.frame(f, { Name = "MoreHost", BackgroundColor3 = TC.Panel, Position = UDim2.fromOffset(0, 46 + (FACTS_H - 21)), Size = UDim2.new(1, 0, 1, -(46 + (FACTS_H - 21))), Visible = false, ZIndex = view.ZIndex + 5 })
	UI.corner(moreHost, T.RadiusSm)
	local function showMore(on: boolean)
		moreOpen = if on then g.Id else nil
		if on and moreHost:FindFirstChild("MoreStats") == nil then
			PetStatsStrip.more(moreHost, g, other ~= nil, function()
				showMore(false)
			end)
		end
		moreHost.Visible = on
	end
	if short then
		(stats :: TextButton).Activated:Connect(function()
			showMore(true)
		end)
	else
		local moreBtn = UI.button(stats, "MORE", "gray", function()
			showMore(true)
		end, { Name = "More", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 0), Size = UDim2.new(0, moreW, 1, 0), TextSize = T.Small })
		oneLine(moreBtn, T.Small)
	end
	if moreOpen == g.Id then
		showMore(true)
	end
	local eq: TextButton
	eq = UI.button(actions, if following then "UNEQUIP" else "EQUIP", if following then "gray" else "green", function()
		if not following and #(prof.EquippedPets or {}) >= (prof.PetSlots or Config.Pets.Slots) then
			-- the team is full: MY PETS asks which slot to swap (never a silent replace)
			local f = Collection.onTeamFull
			if f then
				f(g.Id)
				return
			end
		end
		UI.pending(eq, "\u{2026}", 4)
		equipFlip = if following then nil else g.Id
		act(if following then "UnequipPet" else "EquipPet", g.Id)
	end, { Name = "Equip", Size = if twoRows then UDim2.new(0.42, -3, 0, T.Touch) else UDim2.new(1, 0, 0, btnH), TextSize = T.Body + 1 })
	oneLine(eq)
	if following then
		-- a following pet's button carries a tick; right after EQUIP it flips in (turns over and pops)
		local tick = UI.icon(eq, "check", 22, { Name = "Tick", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = eq.ZIndex + 2 })
		-- the word starts right of the tick (the tick sat on the U of UNEQUIP, Studio #178)
		local el = eq:FindFirstChild("Label") :: TextLabel?
		if el then
			el.Position = UDim2.new(0, 34, el.Position.Y.Scale, el.Position.Y.Offset)
			el.Size = UDim2.new(1, -40, el.Size.Y.Scale, el.Size.Y.Offset)
		end
		if equipFlip == g.Id then
			equipFlip = nil
			if not UI.Reduced then
				UI.pop(eq, 0.8)
				UI.pop(tick, 0.2, 0.05)
				tick.Rotation = -180
				TweenService:Create(tick, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
			end
		end
	end
	local main
	if isDisp then
		main = UI.button(actions, if twoRows then "TAKE OFF DISPLAY" else "REMOVE FROM DISPLAY", "gold", function()
			UI.pending(main, "REMOVING\u{2026}", 4)
			act("Display", g.Id, false)
		end, { Name = "Place", Position = placePos, Size = placeSize, TextSize = T.Body + 1 })
		oneLine(main)
	else
		main = UI.button(actions, "PLACE ON DISPLAY", "gold", function()
			if #prof.DisplayAssignments < prof.DisplaySlots then
				UI.pending(main, "PLACING\u{2026}", 4)
				act("Display", g.Id, true)
			else
				-- display full: choose which slot to replace on the Display tab
				placing = g.Id
				picker = false
				tab = "Display"
				render()
			end
		end, { Name = "Place", Position = placePos, Size = placeSize, TextSize = T.Body + 1 })
		oneLine(main)
	end
	local row = UI.frame(actions, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, if twoRows then T.Touch + 6 else 2 * (btnH + 6)), Size = UDim2.new(1, 0, 0, if twoRows then T.Touch else btnH) })
	UI.list(row, Enum.FillDirection.Horizontal, 6)
	-- one short word per button so each reads on one line at body size: FAV (star) and SELL share the row (the ROAM
	-- button is gone: no pet walks around loose, owner 2026-10-14)
	-- the favourite button says FAV beside its star (a bare star read as an unlabelled diamond, Studio); the star
	-- steps aside when the word would not fit beside it
	local fav = UI.button(row, "FAV", "gray", function()
		act("Favorite", g.Id, not g.Favorite)
	end, { Name = "Favourite", Size = UDim2.new(0.4, -4, 1, 0), TextSize = T.Body + 1, LayoutOrder = 1 })
	local star = UI.icon(fav, "star", 22, { Name = "Star", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = fav.ZIndex + 2 })
	oneLine(fav)
	local fl = fav:FindFirstChild("Label") :: TextLabel?
	if fl then
		UI.iconWord(fav, fl, star, 22, T.Small)
	end
	if g.Favorite then
		UI.setSelected(fav, true)
	end
	local canSell = sellable(prof, g)
	-- a protected pet says why it can't be sold (the server refuses it too)
	local sellText = if canSell then "SELL " .. UI.num(g.Value) elseif g.Favorite then "LOCKED" else "ON DISPLAY"
	local sell: TextButton
	sell = UI.button(row, sellText, "gray", function()
		confirmSell(prof, { g.Id }, sell)
	end,{ Name = "Sell", Size = UDim2.new(0.6, -4, 1, 0), TextSize = T.Body + 1, LayoutOrder = 3 })
	oneLine(sell)
	if canSell then
		-- the coin picture says "coins" so the word fits on one line
		local sl = sell:FindFirstChild("Label") :: TextLabel?
		local coin = UI.icon(sell, "cash", 20, { Name = "Coin", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = sell.ZIndex + 2 })
		if sl then
			UI.iconWord(sell, sl, coin, 20, T.Small)
		end
	end
	UI.setEnabled(sell, canSell)
end

-- Zero specimens (additional board 5): one rock silhouette, two short lines, START HUNT.
local function renderEmpty(b: Frame, prof: Prof, top: number)
	if panelRef then
		UI.fitModal(panelRef, Vector2.new(520, if UI.isPortrait() then 420 else 330))
	end
	local _, btn = UI.emptyState(b, "Your Pet Book is empty!", "Go hatch your first pet!", nil, {
		Name = "EmptyState", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, top / 2 - 8),
	}, if not State.Match then {
		Text = "START HUNT",
		OnClick = function()
			PartyPanel.open()
		end,
	} else nil)
	if btn then
		btn.Name = "StartHunt"
	end
	UI.text(b, countsLine(prof) .. "   Display slots " .. #prof.DisplayAssignments .. "/" .. prof.DisplaySlots, {
		Name = "Counts", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light",
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center,
	})
end

local function renderCollection(b: Frame, prof: Prof, top: number)
	if #prof.Inventory == 0 then
		renderEmpty(b, prof, top)
		return
	end
	local portrait = UI.isPortrait()
	local list = sortedList(prof)
	local g = findGeode(prof, detail)
	if not g and #list > 0 then
		local first = list[1]
		g = first
		detail = first.Id
	end
	local left = UI.frame(b, { Name = "Grid", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top), Size = if portrait then UDim2.new(1, 0, 0.45, -top / 2) else UDim2.new(0.6, -4, 1, -top) })
	-- toolbar: sort by rarity / level / type (tap again for newest first), favourites filter, sell mode
	local barH = chipH()
	local bar = UI.frame(left, { Name = "Toolbar", Size = UDim2.new(1, 0, 0, barH), BackgroundTransparency = 1 })
	UI.list(bar, Enum.FillDirection.Horizontal, 5)
	for i, key in { "Rarity", "Level", "Type" } do
		local sbtn = UI.button(bar, string.upper(key), "gray", function()
			sortBy = if sortBy == key then "Newest" else key
			page = 1
			render()
		end, { Name = "Sort" .. key, Size = UDim2.new(0.2, -4, 1, 0), TextSize = T.Body, LayoutOrder = i })
		oneLine(sbtn, T.Body)
		UI.setSelected(sbtn, sortBy == key)
	end
	local fb = UI.button(bar, "FAVS", "gray", function()
		favOnly = not favOnly
		page = 1
		render()
	end, { Name = "Favs", Size = UDim2.new(0.2, -4, 1, 0), TextSize = T.Body, LayoutOrder = 4 })
	oneLine(fb, T.Body)
	UI.setSelected(fb, favOnly)
	-- low-poly star left of FAVS (the word moves right to make room)
	local fl = fb:FindFirstChild("Label") :: TextLabel?
	if fl then
		HudArt.image(fb, "TabFavorites", 20, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0) })
		fl.Position = UDim2.new(0, 24, fl.Position.Y.Scale, fl.Position.Y.Offset)
		fl.Size = UDim2.new(1, -28, fl.Size.Y.Scale, fl.Size.Y.Offset)
	end
	local sb = UI.button(bar, if sellMode then "CANCEL" else "SELL", if sellMode then "red" else "gray", function()
		sellMode = not sellMode
		table.clear(picked)
		render()
	end, { Name = "SellMode", Size = UDim2.new(0.2, -4, 1, 0), TextSize = T.Body, LayoutOrder = 5 })
	oneLine(sb, T.Body)
	local footH = T.Touch
	local pages = math.max(1, math.ceil(#list / PAGE))
	page = math.clamp(page, 1, pages)
	local grid = UI.scroller(left, { Name = "Cards", Position = UDim2.fromOffset(0, barH + 6), Size = UDim2.new(1, 0, 1, -(barH + 6 + footH + 4)) })
	-- room under the last row as tall as the footer, so the bottom cards scroll fully clear of Owned / EQUIP BEST
	UI.pad(grid, 2, 2).PaddingBottom = UDim.new(0, footH)
	local gl = Instance.new("UIGridLayout")
	local w = (math.min(UI.Logical.X - 24, 760) - 2 * T.Pad) * (if portrait then 1 else 0.6) - 12
	local cols = math.max(3, math.floor((w + 6) / 92))
	gl.CellSize = UDim2.new(1 / cols, -6, 0, if UI.isShort() then 84 else 96)
	gl.CellPadding = UDim2.fromOffset(6, 6)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	if #list == 0 then
		UI.text(grid, "No favourites yet. Tap Favs to show all.", { Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, Size = UDim2.new(1, 0, 0, 40) })
	end
	-- the pet that follows you: every card's POWER gets a green up / red down arrow against it
	local followed: Pet? = nil
	local followId = (prof.EquippedPets or {})[1]
	for _, o in prof.Inventory do
		if o.Id == followId then
			followed = o
		end
	end
	local glints: { { card: GuiObject, every: number } } = {}
	for i = (page - 1) * PAGE + 1, math.min(#list, page * PAGE) do
		local x = list[i]
		local isSel = if sellMode then picked[x.Id] == true else detail == x.Id
		local rc, shimmer, rtext = rarityOpts(x)
		local card = UI.specimenCard(grid, i, {
			-- boost shows in the detail view (cards are too narrow for name and boost)
				Name = "Spec_" .. x.Id, Caption = cardLabel(x), Selected = isSel, Picture = geodePicture(x), Rarity = x.Rarity,
			Glow = PetRules.kindColor(PetRules.kindOf(x)), TypeIcon = typeIcon(x),
			RarityColor = rc, Shimmer = shimmer, Thick = x.Rarity == "Legendary", CaptionColor = rtext,
			OnSelect = function()
				if sellMode then
					if sellable(prof, x) then
						picked[x.Id] = if picked[x.Id] then nil else true :: any
						render()
					end
				else
					freshPets[tostring(x.Id)] = nil -- seen now: the "!" and glow go
					detail = x.Id
					render()
				end
			end,
		})
		if freshPets[tostring(x.Id)] and not sellMode then
			-- new since the last look: a red "!" (wiggles in) and a soft breathing glow. The dot sits in a zero-size
			-- holder just outside the card's top-right corner, so it rides over the corner instead of covering the
			-- POWER badge / star inside it (the shared dot's home is 4 px inside its parent)
			local dotHost = UI.frame(card, { Name = "NewDotHost", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 2, 0, -2), Size = UDim2.fromOffset(8, 8), ZIndex = card.ZIndex + 5 })
			UI.newDot(dotHost, true)
			Juice.pulse(card, nil, T.Radius)
		end
		-- a bigger caption than the shared card's (names were tiny on a phone): taller line, picture a bit shorter;
		-- every name stays on one line and shrinks to fit (UI.oneLine lowers the floor): two lines cut words
		-- ("Golder / Puffquill") and crowded the Following / Display tags (Studio 2026-10-16)
		local cap = card:FindFirstChild("Caption") :: TextLabel?
		local cpic = card:FindFirstChild("Picture") :: Frame?
		if cap and cpic then
			cap.Size = UDim2.new(1, -6, 0, 24)
			cap.Position = UDim2.new(0, 3, 1, -2)
			UI.fit(cap, T.Body + 1, T.MinText)
			UI.oneLine(cap)
			cpic.Size = UDim2.new(1, -8, 1, -30)
		end
		-- POWER on the picture's top left (the type icon keeps the bottom right)
		PetStatsStrip.badge(cpic or card, PetStatView.power(x), PetStatView.compare(x, followed), 20, { Position = UDim2.fromOffset(2, 2), ZIndex = 6 })
		local nth = i - (page - 1) * PAGE
		if animateIn and nth <= 12 then
			UI.pop(card, 0.4, nth * 0.035) -- the first cards pop in one after another
		end
		if sellMode and picked[x.Id] then
			local e = card:FindFirstChild("Border") :: UIStroke?
			if e then
				e.Color = TC.Red
			end
		end
		-- card tags never cover the POWER badge (top left): the favourite star sits top right, the Following and
		-- Display words stack under the badge (Studio: "Following" hid the following pet's number)
		if x.Favorite then
			UI.icon(card, "star", 16, { Name = "FavStar", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), ZIndex = 7 })
		end
		local tagY = 28
		if isShiny(x) then
			-- the gold SHINY tag under the POWER badge (never over it), ahead of the Following / Display words
			shinyTag(card, 16, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, tagY), Size = UDim2.fromOffset(74, 16), Rotation = -3, ZIndex = 7 })
			tagY += 17
			table.insert(glints, { card = card :: GuiObject, every = GLINT_SHINY })
		elseif x.Rarity == "Legendary" then
			table.insert(glints, { card = card :: GuiObject, every = GLINT_LEGEND })
		end
		if isFollowing(prof, x.Id) then
			UI.text(card, "Following", { Name = "FollowBadge", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Green, Outline = "Normal", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, tagY), Size = UDim2.new(1, -8, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
			tagY += 14
		end
		if slotOf(prof, x.Id) then
			UI.text(card, "Display", { Name = "DisplayBadge", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Gold, Outline = "Normal", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, tagY), Size = UDim2.new(1, -8, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
		end
	end
	startGlints(glints)
	local foot = UI.frame(left, { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, footH) })
	if sellMode then
		local ids, total = {}, 0
		for _, x in prof.Inventory do
			if picked[x.Id] then
				table.insert(ids, x.Id)
				total += x.Value
			end
		end
		local s: TextButton
		s = UI.button(foot, "SELL " .. #ids .. " \u{b7} " .. UI.money(total), "red", function()
			confirmSell(prof, ids, s)
		end,{ Name = "SellPicked", Size = UDim2.new(1, 0, 1, 0), TextSize = T.Body })
		UI.setEnabled(s, #ids > 0)
	else
		local pagesW = if pages > 1 then 2 * T.Touch + 8 else 0
		-- two readable lines, inset from the panel's rim (one tiny line touched the frame edge)
		-- one label per line (a single wrapped two-line label scaled its words down to specks, Studio #179)
		local counts = UI.frame(foot, { Name = "Counts", BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -(pagesW + 112 + 12), 1, 0) })
		local lines = {
			"Owned " .. #prof.Inventory .. "/" .. prof.InventoryMax .. (if pages > 1 then " \u{b7} Page " .. page .. "/" .. pages else ""),
			"Following " .. #(prof.EquippedPets or {}) .. "/" .. petSlots(prof),
		}
		for li, line in lines do
			local c = UI.text(counts, line, { Name = "Line" .. li, Font = UI.Bold, TextSize = T.Body + 2, Outline = "Normal", Position = UDim2.new(0, 0, (li - 1) / 2, 0), Size = UDim2.fromScale(1, 0.5) })
			c.TextWrapped = false
			UI.fit(c, T.Body + 2, T.Small)
			c.TextWrapped = false
			c.TextTruncate = Enum.TextTruncate.AtEnd
		end
		-- Equip Best: the server picks the owned pet with the highest POWER (lobby only, PetService)
		local best = UI.button(foot, "EQUIP BEST", "green", function()
			act("EquipBest")
		end, { Name = "EquipBest", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -pagesW, 0, 0), Size = UDim2.new(0, 106, 1, 0), TextSize = T.Body + 1 })
		-- greyed out: the label says why (same checks as PetService)
		local reason: string? = nil
		if State.Match ~= nil then
			reason = "IN A HUNT"
		elseif #prof.Inventory == 0 then
			reason = "NO PETS"
		else
			local bestIds = PetRules.best(prof.Inventory, Config.Pets.Slots)
			local equipped = prof.EquippedPets or {}
			local same = #bestIds == #equipped
			for i, bid in bestIds do
				if equipped[i] ~= bid then
					same = false
				end
			end
			if same then
				reason = "ALREADY BEST"
			end
		end
		-- a greyed button on the pale sheet read grey-on-grey: the off state is the navy tab-bar fill with white words
		best:SetAttribute("DisabledFill", Theme.Pet.TabBar)
		best:SetAttribute("DisabledText", Color3.new(1, 1, 1))
		UI.setEnabled(best, reason == nil)
		if reason then
			UI.setText(best, reason)
		end
		if pages > 1 then
			UI.button(foot, "<", "gray", function()
				page = math.max(1, page - 1)
				render()
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(T.Touch + 4), 0, 0), Size = UDim2.new(0, T.Touch, 1, 0), TextSize = T.Small })
			UI.button(foot, ">", "gray", function()
				page = math.min(pages, page + 1)
				render()
			end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, T.Touch, 1, 0), TextSize = T.Small })
		end
	end
	local right = UI.frame(b, {
		Name = "Side", BackgroundTransparency = 1,
		Position = if portrait then UDim2.new(0, 0, 0.45, top / 2 + 6) else UDim2.new(0.6, 4, 0, top),
		Size = if portrait then UDim2.new(1, 0, 0.55, -(top / 2 + 6)) else UDim2.new(0.4, -4, 1, -top),
	})
	if sellMode then
		UI.text(right, "Tap pets to pick them. Favourites and displayed pets are protected.", { Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, Size = UDim2.new(1, 0, 0, 60), TextYAlignment = Enum.TextYAlignment.Top })
	elseif g then
		renderDetail(right, prof, g)
	end
end

-- Display tab (board 7): the real slots, a selected slot and its one action.
local function renderDisplay(b: Frame, prof: Prof, top: number)
	local n = prof.DisplaySlots
	slotSel = math.clamp(slotSel, 1, math.max(n, 1))
	local used = #prof.DisplayAssignments
	local placingG = findGeode(prof, placing)
	if placing and not placingG then
		placing = nil
	end
	local info = UI.text(b, "", {
		Name = "DisplaySlots", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", RichText = true,
		Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 22),
	})
	info.Text = if placingG
		then "Display full: pick a slot for <font color=\"#FFC424\">" .. GeodeGen.displayName(placingG) .. "</font>"
		else "Display slots: <font color=\"#FFB020\">" .. used .. "/" .. n .. "</font>   (upgrade in Upgrades > Gallery)"
	local y = top + 26
	local actH = 50
	local gridH = if picker then 0.5 else 1
	local grid = UI.scroller(b, { Name = "Slots", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, gridH, -(y * gridH + actH + 4)) })
	UI.pad(grid, 2, 2)
	local gl = Instance.new("UIGridLayout")
	local cols = math.clamp(math.floor((math.min(UI.Logical.X - 24, 760) - 2 * T.Pad) / 104), 3, 6)
	-- the slots the next Gallery upgrade adds show as locked frames (Config.Display levels); one short row of cards is
	-- drawn taller so it fills the tab instead of leaving a big empty area
	local capLvl = if type(prof.DisplayCapacity) == "number" then prof.DisplayCapacity else nil
	local nextLvl = if capLvl then Config.Display[capLvl + 1] else nil
	local here = if capLvl then Config.Display[capLvl] else nil
	local cards = n + (if nextLvl and here and not placingG then nextLvl.Slots - here.Slots else 0)
	local cellH = if UI.isShort() then 86 else 100
	if cards <= cols and not picker then
		cellH = if UI.isShort() then 150 else 180
	end
	gl.CellSize = UDim2.new(1 / cols, -8, 0, cellH)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i = 1, n do
		local occ = findGeode(prof, prof.DisplayAssignments[i])
		UI.specimenCard(grid, i, {
			Name = "Slot" .. i,
			Caption = if occ then PetRules.label(occ, true) else "Empty",
			Empty = occ == nil,
			Selected = i == slotSel,
			Picture = if occ then geodePicture(occ) else nil,
			OnSelect = function()
				if placingG then
					-- a full display: replace the specimen in this slot with the one waiting
					act("DisplayAt", placingG.Id, i)
					placing = nil
					slotSel = i
					render()
					return
				end
				slotSel = i
				picker = false
				render()
			end,
		})
	end
	-- the slots the next Gallery upgrade adds, as locked frames (Config.Display levels; nothing to tap)
	if nextLvl and here and not placingG then
		local upTo = n + (nextLvl.Slots - here.Slots)
		for i = n + 1, upTo do
			local c = UI.specimenCard(grid, i, { Name = "Locked" .. i, Caption = UI.money(nextLvl.Price), Empty = true })
			c.Active = false
			c.AutoButtonColor = false
			c.BackgroundTransparency = 0.45
			local pic = c:FindFirstChild("Picture")
			if pic then
				pic:ClearAllChildren()
				UI.icon(pic, "lock", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			end
		end
	end
	-- the one action for the selected slot
	local actions = UI.frame(b, { Name = "Actions", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, actH) })
	local selId = prof.DisplayAssignments[slotSel]
	local candidates = {}
	for _, x in sortedList(prof) do
		if not slotOf(prof, x.Id) then
			table.insert(candidates, x)
		end
	end
	if placingG then
		UI.button(actions, "CANCEL", "gray", function()
			placing = nil
			render()
		end, { Name = "Cancel", Size = UDim2.fromScale(1, 1), TextSize = T.Head })
		return
	end
	if picker then
		-- choose a specimen for the selected slot (empty: the next free slot, the list stays dense; occupied: replace)
		local target = if selId then slotSel else used + 1
		local ph = UI.frame(b, { Name = "Picker", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.5, -(y * 0.5) + 4), Size = UDim2.new(1, 0, 0.5, -(actH + 8) + y * 0.5 - 4) })
		UI.text(ph, (if selId then "Replace slot " else "Place in slot ") .. target .. ": pick a pet", { Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Size = UDim2.new(1, 0, 0, 20) })
		local strip = UI.scroller(ph, { Name = "Choices", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X })
		UI.list(strip, Enum.FillDirection.Horizontal, 6)
		if #candidates == 0 then
			UI.text(strip, "Every pet you own is already on display.", { Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Muted, Size = UDim2.fromOffset(320, 40) })
		end
		for i, x in candidates do
			local c = UI.specimenCard(strip, i, {
				Name = "Pick_" .. x.Id, Caption = PetRules.label(x, true), Picture = geodePicture(x),
				OnSelect = function()
					act("DisplayAt", x.Id, target)
					picker = false
					render()
				end,
			})
			c.Size = UDim2.new(0, 92, 1, -6)
		end
		UI.button(actions, "CANCEL", "gray", function()
			picker = false
			render()
		end, { Name = "Cancel", Size = UDim2.fromScale(1, 1), TextSize = T.Head })
		return
	end
	if selId then
		local row = UI.frame(actions, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		UI.list(row, Enum.FillDirection.Horizontal, 8)
		local rm
		rm = UI.button(row, "REMOVE FROM DISPLAY", "gold", function()
			UI.pending(rm, "REMOVING\u{2026}", 4)
			act("Display", selId, false)
		end, { Name = "Remove", Size = UDim2.new(0.62, -4, 1, 0), TextSize = T.Body + 1, LayoutOrder = 1 })
		local rp = UI.button(row, "REPLACE", "gray", function()
			picker = true
			render()
		end, { Name = "Replace", Size = UDim2.new(0.38, -4, 1, 0), TextSize = T.Body + 1, LayoutOrder = 2 })
		UI.setEnabled(rp, #candidates > 0)
	else
		local pb = UI.button(actions, if #prof.Inventory == 0 then "NO PETS YET" else "PLACE ON DISPLAY", "gold", function()
			picker = true
			render()
		end, { Name = "Place", Size = UDim2.fromScale(1, 1), TextSize = T.Head })
		UI.setEnabled(pb, #candidates > 0)
	end
end

-- Pet Book: every species per zone; unfound ones stay a silhouette ("Not found yet"). % = species found.
-- "50%", "3.9%", "0.1% (1 in 1000)": a chance written so a young player can read it.
local function chanceText(p: number): string
	local pct = p * 100
	local s = if pct >= 10 or math.abs(pct - math.floor(pct + 0.5)) < 0.05 then tostring(math.floor(pct + 0.5)) .. "%" else string.format("%.1f%%", pct)
	if p > 0 and p < 0.01 then
		s ..= " (1 in " .. math.floor(1 / p + 0.5) .. ")"
	end
	return s
end

local function shortChance(p: number): string
	return (string.gsub(chanceText(p), " %(.*%)", ""))
end

local function rarityChances(luck: number?): { [string]: number }
	local w = GeodeGen.rarityWeights(luck)
	local total = 0
	for _, r in Config.Rarities do
		total += w[r] or 0
	end
	local out = {}
	for _, r in Config.Rarities do
		out[r] = if total > 0 then (w[r] or 0) / total else 0
	end
	return out
end

-- The rarity odds card at the top of the Book: one chip per rarity (colour, word, chance).
local function oddsCard(parent: Instance, order: number, prof: Prof)
	local luck = if prof.PetBoosts then prof.PetBoosts.Luck or 0 else 0
	local h = 92 -- compact: shown once, at the top of All
	local card = UI.card(parent, "inset", { Name = "RarityOdds", LayoutOrder = order, Size = UDim2.new(1, -6, 0, h) })
	UI.text(card, "Rarity odds for every pet you hatch", { Name = "Title", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 20) })
	local row = UI.frame(card, { Name = "Chips", Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 44), BackgroundTransparency = 1 })
	UI.list(row, Enum.FillDirection.Horizontal, 4)
	local base = rarityChances(0)
	local mine = rarityChances(luck)
	local n = #Config.Rarities
	for i, r in Config.Rarities do
		local chip = UI.frame(row, { Name = "Odds_" .. r, LayoutOrder = i, Size = UDim2.new(1 / n, -math.ceil(4 * (n - 1) / n), 1, 0), BackgroundColor3 = TC.Panel })
		UI.corner(chip, T.RadiusSm)
		UI.stroke(chip, Config.RarityColors[r], 2)
		-- the rarity word sits on a dark pill so every rarity colour reads (light-blue Rare vanished on the blue chip)
		local pill = UI.frame(chip, { Name = "RarityPill", Position = UDim2.fromOffset(3, 2), Size = UDim2.new(1, -6, 0, 18), BackgroundColor3 = PanelSkin.NAVY, BackgroundTransparency = 0.1 })
		UI.corner(pill, 9)
		local name = UI.text(pill, r, { Name = "Rarity", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = Config.RarityTextColors[r], Outline = "Light", Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
		name.TextWrapped = false
		UI.fit(name, T.Tiny, T.MinText)
		local pctLabel = UI.text(chip, shortChance(base[r]), { Name = "Chance", Font = UI.Head, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(2, 20), Size = UDim2.new(1, -4, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
		pctLabel.TextWrapped = false
		UI.fit(pctLabel, T.Body, T.MinText)
	end
	local legendary = base.Legendary or 0
	local foot = if legendary > 0 then "Legendary: 1 in " .. math.floor(1 / legendary + 0.5) .. " hatches." else ""
	if luck > 0 then
		foot = "With your Luck pet: Rare " .. shortChance(mine.Rare) .. ", Epic " .. shortChance(mine.Epic) .. ", Legendary " .. shortChance(mine.Legendary) .. "."
	end
	local f = UI.text(card, foot, { Name = "Foot", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light", Position = UDim2.fromOffset(10, h - 22), Size = UDim2.new(1, -20, 0, 18) })
	UI.fit(f, T.Tiny, T.MinText)
end

local MAX_SILHOUETTES = 32 -- 3D pet pictures per Book page (found in colour, unfound as a black shape); the rest keep a plain dot / "?"

local function renderIndex(b: Frame, prof: Prof, top: number)
	local byRarity = prof.DiscoveryRarity or {}
	local entries: { { [string]: any } }, foundN, totalN = {}, 0, 0
	for _, tid in Config.TierOrder do
		local tier = Config.Tiers[tid]
		local shown = bookZone == "All" or bookZone == tier.Name -- the % below still counts every zone
		if shown then
			table.insert(entries, { Header = tier.Name })
		end
		local now = os.time()
		local rp = {}
		local wsum = 0
		for _, r in Config.Rarities do
			wsum += Config.RarityWeights[r]
		end
		for _, r in Config.Rarities do
			rp[r] = Config.RarityWeights[r] / wsum
		end
		for _, id in SpeciesPool.list(tid, now) do -- hidden weekly pets are not listed until they are out
			local share = SpeciesPool.chance(tid, id, now, rp) -- the race egg odds GeodeGen.roll uses
			local m = Config.Minerals[id]
			local row = byRarity[id] or {}
			local n = 0
			for _, r in Config.Rarities do
				if (row[r] or 0) > 0 then
					n += 1
				end
			end
			local seen = n > 0 or (prof.DiscoveryIndex[id] or 0) > 0
			totalN += 1
			if seen then
				foundN += 1
			end
			if shown then
				table.insert(entries, { Id = id, Mineral = m, Row = row, Count = n, Seen = seen, Chance = share, Zone = tier.Name })
			end
		end
	end
	local pct = if totalN > 0 then math.floor(foundN / totalN * 100 + 0.5) else 0
	-- zone filter right under the tabs: All + one chip per zone, each with its low-poly icon (HudArt Tab<Zone>)
	local zones = { "All" }
	for _, tid in Config.TierOrder do
		table.insert(zones, Config.Tiers[tid].Name)
	end
	local zoneH = chipH()
	local zr = UI.frame(b, { Name = "ZoneTabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, zoneH) })
	UI.list(zr, Enum.FillDirection.Horizontal, 4)
	local nz = #zones
	for i, z in zones do
		local chip = UI.button(zr, z, "gray", function()
			if bookZone ~= z then
				bookZone = z
				render()
			end
		end, { Name = "Zone_" .. z, LayoutOrder = i, TextSize = T.Small + 1, Size = UDim2.new(1 / nz, -math.ceil(4 * (nz - 1) / nz), 1, 0) })
		UI.setSelected(chip, bookZone == z)
		local cl = chip:FindFirstChild("Label") :: TextLabel?
		if UI.isPortrait() then
			-- six chips on a phone held upright: picture only (the zone name heads its list below)
			HudArt.image(chip, "Tab" .. z, 32, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			if cl then
				cl.Visible = false
			end
		elseif cl then
			-- the picture steps aside when the zone name would not fit beside it at a readable size (Studio #177)
			local zpic = HudArt.image(chip, "Tab" .. z, 30, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0) })
			cl.Font = UI.Bold
			cl.Text = z
			cl.TextWrapped = false
			cl.Position = UDim2.new(0, 3, 0.5, -11)
			cl.Size = UDim2.new(1, -6, 0, 22)
			UI.fit(cl, T.Small, T.Small)
			cl.TextWrapped = false
			UI.tabIconWord(chip, cl, zpic, 30, T.Small) -- picture and name centred as one group
		end
	end
	local sc = UI.scroller(b, { Position = UDim2.fromOffset(0, top + zoneH + 6), Size = UDim2.new(1, 0, 1, -(top + zoneH + 6)) })
	UI.pad(sc, 2, 2)
	UI.list(sc, Enum.FillDirection.Vertical, 6)
	-- how much of the Book is filled: a readable line with a bar, at the head of the list (scrolls away with it)
	local sum = UI.card(sc, "inset", { Name = "IndexSummary", LayoutOrder = -2, Size = UDim2.new(1, -6, 0, 50) })
	local sl = UI.text(sum, "Pet Book " .. pct .. "% complete \u{b7} " .. foundN .. "/" .. totalN .. " pets", { Name = "Text", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -24, 0, 24) })
	sl.TextWrapped = false
	UI.fit(sl, T.Body, T.MinText)
	local _, fill = UI.bar(sum, { Name = "Progress", Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 12) }, TC.Gold)
	fill.Size = UDim2.fromScale(if totalN > 0 then foundN / totalN else 0, 1)
	-- Pet Book pages by zone name (the synced view when the server sent it, else the same rules run here)
	local pages: { [string]: EggPerks.Page } = {}
	local perks: any = prof.EggPerks
	local pageList: { EggPerks.Page } = if type(perks) == "table" and type(perks.Pages) == "table" then perks.Pages else EggPerks.pages(prof.DiscoveryIndex)
	for _, pg in pageList do
		pages[pg.Name] = pg
	end
	local silhouettes = 0
	for i, c in entries do
		if c.Header then
			-- zone name on the left; the page's progress and its lasting bonus (shared/EggPerks) on the right
			local hr = UI.frame(sc, { Name = "Zone_" .. c.Header, BackgroundTransparency = 1, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 22) })
			UI.text(hr, string.upper(c.Header), { Name = "Name", Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Gold, Outline = "Normal", Size = UDim2.new(0.42, 0, 1, 0) })
			local page = pages[c.Header]
			if page then
				local bonus = math.floor(EggPerks.Pages.CoinsPerPage * 100 + 0.5)
				local txt = if page.Done then string.format("FULL PAGE  +%d%% coins & XP", bonus) else string.format("%d/%d  \u{b7}  full page = +%d%% coins & XP", page.Found, page.Need, bonus)
				local pl = UI.text(hr, txt, { Name = "Page", Font = UI.Bold, TextSize = T.Small, TextColor3 = if page.Done then Theme.Pet.Lime else TC.Muted, Outline = "Normal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.58, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
				pl.TextWrapped = false
				UI.fit(pl, T.Small, T.MinText)
			end
			continue
		end
		local f = UI.card(sc, "inset", { LayoutOrder = i, Name = "Mineral_" .. c.Id, Size = UDim2.new(1, -6, 0, 70) })
		if animateIn and i <= 14 then
			UI.pop(f, 0.5, i * 0.03) -- rows pop in one after another when the Book opens
		end
		local dot = UI.frame(f, { Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = if c.Seen then c.Mineral.Crystal else TC.GrayDeep })
		UI.corner(dot, 24)
		UI.stroke(dot, if c.Seen then c.Mineral.Rim else TC.Outline, 2)
		local petSpec = { Mineral = c.Id, Formation = "Cluster", Modifier = "Natural", Rarity = "Common", Mass = 1.2, Seed = 1 }
		if c.Seen then
			if silhouettes < MAX_SILHOUETTES then
				-- the pet itself on a cream plate (a plain colour dot read as a green circle, Studio #180)
				silhouettes += 1
				dot.BackgroundTransparency = 1
				local edge = dot:FindFirstChildOfClass("UIStroke")
				if edge then
					edge.Enabled = false
				end
				GeodeView.make(dot, petSpec, { Name = "Picture", Size = UDim2.fromScale(1, 1), Backing = true })
			end
		else
			dot.BackgroundTransparency = 1
			if silhouettes < MAX_SILHOUETTES then
				-- the pet's own shape drawn pure black (the viewport tint), so each unfound row hints at a different pet
				silhouettes += 1
				local vp = GeodeView.make(dot, petSpec, { Name = "Silhouette", Size = UDim2.fromScale(1, 1) })
				vp.ImageColor3 = Color3.new(0, 0, 0)
				vp.Ambient = Color3.new(0, 0, 0)
				vp.LightColor = Color3.new(0, 0, 0)
			else
				-- past the cap (each picture is a 3D view): the plain shape with a question mark
				UI.icon(dot, "egg", 34, { Name = "Silhouette", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = TC.PanelEdge, Flat = true })
				UI.text(dot, "?", { Name = "Unknown", Font = UI.Head, TextSize = T.Head, TextColor3 = TC.Faint, Outline = "Light", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
			end
		end
		UI.text(f, if c.Seen then c.Mineral.Name else "Not found yet", { Name = "Name", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", TextColor3 = if c.Seen then TC.Text else TC.Faint, Position = UDim2.fromOffset(62, 4), Size = UDim2.new(1, -186, 0, 24) })
		-- hatch chance in its zone (shown for unfound pets too: it is a fact of the game, not a spoiler)
		local ch = UI.text(f, chanceText(c.Chance), { Name = "Chance", Font = UI.Head, TextSize = T.Head, TextColor3 = TC.Count, Outline = "Normal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(112, 26), TextXAlignment = Enum.TextXAlignment.Right })
		ch.TextWrapped = false
		-- one line that shrinks to the floor ("of Volcano pets" wrapped into three lines in its 18 px box)
		local cz = UI.text(f, "of " .. c.Zone .. " pets", { Name = "ChanceZone", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 38), Size = UDim2.fromOffset(112, 18), TextXAlignment = Enum.TextXAlignment.Right })
		cz.TextWrapped = false
		UI.fit(cz, T.Tiny, T.MinText)
		cz.TextWrapped = false
		if c.Seen then
			local kind = (c.Mineral :: any).BoostKind or "Coins"
			-- one line that shrinks a little to stay whole (it wrapped into a box one line tall and was cut, Studio #180)
			local l2 = UI.text(f, c.Count .. " of 5 rarities \u{b7} gives " .. (KIND_WORD[kind] or "coins"), { Name = "Line2", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light", Position = UDim2.fromOffset(62, 27), Size = UDim2.new(1, -190, 0, 20) })
			l2.TextWrapped = false
			UI.fit(l2, T.Tiny, 10)
			l2.TextWrapped = false
			l2.TextTruncate = Enum.TextTruncate.AtEnd
			for k, r in Config.Rarities do
				local has = (c.Row[r] or 0) > 0
				local gem = UI.frame(f, { Name = "Gem_" .. r, Position = UDim2.fromOffset(62 + (k - 1) * 22, 48), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = if has then Config.RarityColors[r] else TC.GrayDeep })
				UI.corner(gem, T.RadiusSm)
			end
		else
			local l2 = UI.text(f, "Hatch eggs in the " .. c.Zone .. " zone", { Name = "Line2", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Faint, Outline = "Light", Position = UDim2.fromOffset(62, 30), Size = UDim2.new(1, -190, 0, 20) })
			l2.TextWrapped = false
			UI.fit(l2, T.Tiny, 10)
			l2.TextWrapped = false
			l2.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
	-- the rarity odds are the same in every zone: shown once, on All, after the last page (first they hid the
	-- pages below the fold on a 390 px tall window)
	if bookZone == "All" then
		oddsCard(sc, #entries + 1, prof)
	end
end

-- Materials: a checklist of ordinary stone types cracked (presentation only: nothing here changes a price).
local function renderMaterials(b: Frame, prof: Prof, top: number)
	local mats = prof.Materials or { Found = {}, Counts = {} }
	local have, total = Materials.progress(mats)
	UI.text(b, "Materials discovered: " .. have .. "/" .. total, { Name = "MaterialsProgress", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 22) })
	local sc = UI.scroller(b, { Position = UDim2.fromOffset(0, top + 26), Size = UDim2.new(1, 0, 1, -(top + 26)) })
	UI.pad(sc, 2, 2)
	UI.list(sc, Enum.FillDirection.Vertical, 6)
	for i, id in Materials.order() do
		local mat = Config.Materials[id]
		local found = mats.Found[id] == true
		local row = UI.card(sc, "inset", { Name = "Material_" .. id, Size = UDim2.new(1, -6, 0, 70), LayoutOrder = i })
		MaterialThumb.make(row, id, found, 48, { Position = UDim2.fromOffset(10, 11) })
		UI.text(row, if found then mat.Name else "Unknown material", { Name = "Name", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", TextColor3 = if found then TC.Text else TC.Faint, Position = UDim2.fromOffset(70, 4), Size = UDim2.new(1, -180, 0, 22) })
		UI.text(row, if found then mat.Desc else "Hatch more eggs to find out what is inside.", { Name = "Desc", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light", TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(70, 28), Size = UDim2.new(1, -80, 0, 38) })
		if found then
			UI.text(row, "Found " .. (mats.Counts[id] or 0), { Name = "Count", Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Count, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -110, 0, 4), Size = UDim2.fromOffset(100, 22) })
		end
	end
end

-- Record rows slide in from the right one after another. Unlike Juice.slideIn this eases without overshoot (the Back
-- overshoot pushed rows past the left edge and cut their first letters) and snaps every row to its resting spot once
-- the slide should be over, so an interrupted tween (re-render, app backgrounded on a phone) never leaves rows
-- staggered sideways.
local function slideIn(row: GuiObject, order: number)
	if UI.Reduced or not row.Parent then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = row.Name
	holder.BackgroundTransparency = 1
	holder.Size = row.Size
	holder.LayoutOrder = row.LayoutOrder
	holder.Parent = row.Parent
	row.Size = UDim2.fromScale(1, 1)
	row.Position = UDim2.fromScale(0.6, 0)
	row.Parent = holder
	local delay = math.max(0, order - 1) * 0.04
	TweenService:Create(row, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), { Position = UDim2.new() }):Play()
	task.delay(delay + 0.35, function()
		if row.Parent then
			row.Position = UDim2.new()
		end
	end)
end

-- Records (additional board 4): the server's own numbers, or an honest unavailable state.
local function renderRecords(b: Frame, prof: Prof?, top: number, which: string?)
	local st = prof and prof.Stats
	if not prof or type(st) ~= "table" then -- (st is nil whenever prof is)
		if os.clock() < recordsWaitUntil then
			UI.loadingState(b, "Loading records", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, top / 2) })
			return
		end
		UI.errorState(b, "Records unavailable", "Your records could not be loaded right now.", function()
			recordsWaitUntil = os.clock() + 6
			Net.event("ClientReady"):FireServer() -- asks the server to send the profile again (rate limited there)
			render()
			task.delay(6.1, render)
		end, function()
			if closeRef then
				closeRef()
			end
		end, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, top / 2) })
		return
	end
	-- Records: three big rows that share the tab's height (no empty panel under them); Stats: a scrolling list
	local sc: GuiObject = if which ~= "Stats"
		then UI.frame(b, { Name = "Records", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top) })
		else UI.scroller(b, { Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top) })
	UI.pad(sc, 2, 2)
	UI.list(sc, Enum.FillDirection.Vertical, 8)
	local function big(order: number, icon: string, label: string, value: any)
		local row = UI.card(sc, "inset", { Name = "Record_" .. label, Size = UDim2.new(1, -6, 1 / 3, -6), LayoutOrder = order })
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = Vector2.new(math.huge, 110)
		cap.MinSize = Vector2.new(0, 50)
		cap.Parent = row
		UI.icon(row, icon, 48, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
		local l = UI.text(row, label, { Name = "Label", Font = UI.Bold, TextSize = T.Head + 2, Outline = "Normal", Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -(76 + 112 + 24), 1, 0) })
		l.TextWrapped = false
		-- the number sits in a flat squared chip (a big gold number under a heavy outline read as a coin, Studio #181)
		local chip = UI.frame(row, { Name = "ValueChip", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0, 112, 0.62, 0), BackgroundColor3 = TC.Panel })
		local cc = Instance.new("UISizeConstraint")
		cc.MaxSize = Vector2.new(112, 50)
		cc.Parent = chip
		UI.corner(chip, T.RadiusSm)
		UI.stroke(chip, TC.InsetEdge, 1.5)
		local v = UI.text(chip, tostring(value), { Name = "Value", Font = UI.Head, TextSize = T.Title, TextColor3 = TC.Text, Outline = "Normal", Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
		v.TextWrapped = false
		if animateIn then
			slideIn(row, order) -- the record rows slide in one after another when the tab opens
		end
	end
	local function stat(order: number, label: string, value: string)
		local row = UI.statRow(sc, order, label, value)
		if animateIn and order <= 14 then
			slideIn(row, order - 3)
		end
	end
	if which ~= "Stats" then
		big(1, "star", "Solo finds", st.SoloFinds or 0)
		big(2, "trophy", "Competitive wins", st.MultiplayerWins or 0)
		big(3, "calendar", "Matches played", st.MatchesPlayed or 0)
		return
	end
	stat(4, "Eggs hatched", tostring(st.RocksCracked or 0))
	stat(5, "Coins earned", UI.money(st.CashEarned or 0))
	-- best pet value in the same coins the SELL button shows (each pet's Value is Profiles.priceValue); the saved
	-- record only counts hunt finds, so a tower or Robux egg pet would otherwise sell for more than the "best"
	local best = if type(st.BestGeodeValue) == "number" then st.BestGeodeValue else 0
	for _, g in prof.Inventory do
		if type(g.Value) == "number" and g.Value > best then
			best = g.Value
		end
	end
	stat(6, "Best pet value", UI.money(best))
	stat(7, "Pets owned", tostring(#prof.Inventory))
	local pb = prof.PetBoost
	local boostLine = if pb and pb.Kind and pb.Amount > 0 then PetStatView.pct(pb.Amount) .. " " .. (KIND_WORD[pb.Kind] or "coins") else "none yet"
	stat(8, "Your pet gives", boostLine)
	-- launch badges (the server awards the Roblox badge once the owner has set its id)
	local progress = ProgressConfig.badgeProgress({
		Stats = st, DiscoveryIndex = prof.DiscoveryIndex, DiscoveryRarity = prof.DiscoveryRarity, Inventory = prof.Inventory,
		TowerBest = prof.TowerBest, UnlockedTiers = prof.UnlockedTiers, SecretEggFound = prof.SecretEggFound,
	})
	for i, key in ProgressConfig.BadgeOrder do
		local bd = ProgressConfig.Badges[key]
		local p = progress[key]
		stat(8 + i, bd.Name, if p.Done then "earned" elseif key == "SecretEgg" then "???" elseif p.Need > 1 then (p.Have .. "/" .. p.Need) else "not yet")
	end
	-- room under the last row so it scrolls fully clear of the panel's bottom edge (it was cut off, Studio #182)
	UI.frame(sc, { Name = "EndSpacer", BackgroundTransparency = 1, LayoutOrder = 10000, Size = UDim2.new(1, 0, 0, 24) })
end

-- third entry: the low-poly tab icon (HudArt Icon* slots)
local TABS = {
	{ "Collection", "Pets", HudArt.Slots.IconPets.Image },
	{ "Index", "Book", HudArt.tabPicture("IconPetBook") or "" },
	{ "Records", "Records", HudArt.Slots.IconLeaderboard.Image },
	{ "Stats", "Stats" },
	{ "Display", "Display" },
}

local function modalSize(): Vector2
	if UI.isPortrait() then
		return Vector2.new(480, 720)
	elseif UI.Logical.Y >= 600 then
		return Vector2.new(780, 480)
	end
	return Vector2.new(700, 380)
end

function render()
	if not open or not body then
		return
	end
	local b = body :: Frame
	for _, c in b:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	if panelRef then
		UI.fitModal(panelRef, modalSize())
	end
	UI.tabBar(b, TABS, tab, function(name)
		tab = name
		animateIn = true
		picker = false
		placing = nil
		sellMode = false
		render()
	end)
	local top = T.Tab + T.Gap
	local prof = State.Profile
	if not prof then
		if tab == "Records" or tab == "Stats" then
			renderRecords(b, nil, top, tab)
		else
			UI.loadingState(b, "Loading Pet Book", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, top / 2) })
		end
		return
	end
	if tab == "Collection" then
		renderCollection(b, prof, top)
	elseif tab == "Display" then
		renderDisplay(b, prof, top)
	elseif tab == "Index" then
		renderIndex(b, prof, top)
	elseif tab == "Materials" then
		renderMaterials(b, prof, top)
	else
		renderRecords(b, prof, top, tab)
	end
	animateIn = false
end

function Collection.open(openTab: string?)
	if type(openTab) == "string" then
		for _, t in TABS do
			if t[1] == openTab then
				tab = openTab
			end
		end
	end
	local panel, b, close = UI.modal("Collection", "PET BOOK", modalSize(), { Fixed = true })
	PanelSkin.dress(panel, "IconPetBook", "PET BOOK")
	panelRef = panel
	body = b
	closeRef = close
	open = true
	animateIn = true
	picker = false
	placing = nil
	sellMode = false
	local conn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "Collection" then
			table.clear(freshPets) -- the player has looked: nothing is new next time
			open = false
			body = nil
			panelRef = nil
			closeRef = nil
			glintGen += 1 -- the card glint loop ends with the panel
			conn:Disconnect()
		end
	end)
	render()
end

-- Opens straight on one specimen (used by the tutorial's display step).
-- MY PETS' DISPLAY with every dome full: the Display tab, already placing this pet (tap a dome to swap it in)
function Collection.openPlacing(id: string)
	tab = "Display"
	Collection.open()
	placing = id
	render()
end

function Collection.openOn(id: string?)
	tab = "Collection"
	detail = id
	Collection.open()
end

-- Profile updates come in bursts (sell, place, reward); each one used to rebuild the whole Pet Book (audit 31).
-- Closed panel: nothing to do (render returns at once). Open: a burst is coalesced into one rebuild 0.1 s later.
local renderQueued = false
function Collection.start()
	trackFresh(State.Profile)
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			trackFresh(State.Profile)
		end
		if what == "Profile" and open and not renderQueued then
			renderQueued = true
			task.delay(0.1, function()
				renderQueued = false
				render()
			end)
		end
	end)
end

return Collection
