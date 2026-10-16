--!strict
-- Always-on HUD, UI v2 (docs/ui_v2/BRIEF_UI_V2.md, boards 1-3).
--   Lobby: cash (and the rubble bag when it holds any) top left; a compact right column with Settings, Upgrades,
--     Collection and Party; the first-hunt cue pill and tutorial hints. Nothing hunt-only.
--   Hunt: objective card top centre, the real round timer top right (with the pile count), labelled counters top
--     left (CARRIED basket, QUEUE at the station, RUBBLE storage), a processing card that reflects the server's
--     plate state, tool slots (1 HAND / 2 tool) bottom centre, the contextual action bottom right (placed by
--     TouchLayout clear of the jump button), Settings and Lobby in the right column.
--   Notifications go through UI.notify (coalesced, above menus).
-- While a menu, dialog or the reveal owns the screen, gameplay pieces hide and holding stops.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)
local State = require(script.Parent.Parent.State)
local PileView = require(script.Parent.Parent.PileView)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local QuestPanel = require(script.Parent.QuestPanel)
local Audio = require(script.Parent.Parent.Audio)
local Effects = require(script.Parent.Parent.Effects)
local GuideArrow = require(script.Parent.Parent.GuideArrow)
local ActionRules = require(Shared.ActionRules)
local TouchLayout = require(Shared.TouchLayout)
local ColumnFit = require(Shared.ColumnFit)
local SafeZones = require(Shared.SafeZones)
local StarterEggView = require(script.Parent.Parent.StarterEggView)
local RaceRules = require(Shared.RaceRules)
local EggConfig = require(Shared.EggConfig)
local Juice = require(script.Parent.Juice)
local HudArt = require(script.Parent.HudArt)
local PetStyle = require(script.Parent.PetStyle)
local ItemView = require(script.Parent.ItemView)
local PanelSkin = require(script.Parent.PanelSkin)

local FEW_EGGS = 10 -- the "10 EGGS LEFT!" banner
local fewShownFor: number? = nil -- SearchStart of the hunt the banner was shown for
local fewArmedFor: number? = nil -- SearchStart of the hunt whose pile was seen above FEW_EGGS
local seenPets: number? = nil -- pets owned when the Pet Book was last open (red "!" on its tile)
local lastPets: number? = nil -- pets owned at the last HUD refresh
local pulseSecond = -1 -- last whole second the timer pulsed
local shookTimer = false -- the one-time shake at the start of the red countdown
local lastObjPhase: string? = nil -- phase the objective title last slid in for
local lastActPickup = false -- PICK UP was showing on the previous tick

local C = UI.Colors
local T = UI.T
local TC = Theme.Color
local Hud = {}

Hud.hintText = nil :: (() -> string?)?
Hud.hintDismissed = nil :: string?

local player = Players.LocalPlayer
local refs: { [string]: any } = {}
local openPanel: (string) -> () = function() end
local shownCash = -1
local cashTween: Tween? = nil
local cashValue = Instance.new("NumberValue")

local basketWasFull = false
local queueWasFull = false
local pileWarned = false
local LEFT_W = 132
local FIT_MIN_CARD = 40 -- smallest left-column card height (logical px) when the column is squeezed on a short phone
local BOX_PAD = 12 -- room left of the column inside that box
local LEFT_GAP = 14 -- minimum screen px between the left HUD cards and the safe-area edge
local TILE = 68 -- menu tile (bug #218: the 60 px tiles read cramped with tiny captions on a phone)
local RIGHT_W = 72
local LOBBY_W = 172 -- lobby buttons in the left column (PLAY, the TOWER + photo row, DAILY) share one width
local BOX_W = 2 * LOBBY_W + 6 + 24 -- clipped box around the left column: TOWER + BATTLE side by side, plus rims and dots
local SLOT = 76-- one hunt hotbar slot (HAND / tool)
local DOCK_W = 2 * SLOT + 8 -- hunt tool dock (bottom centre)
local RACE_H = 24 -- one race bar row (name, eggs cracked, share bar)

-- Lobby HUD v2 (ui/LobbyHudV2) takes over the lobby: the old left column and tile menu hide in the lobby while it
-- is on (they come back in hunts, and whenever it is off).
local lobbyHidden = false
function Hud.setLobbyHidden(on: boolean)
	if lobbyHidden ~= on then
		lobbyHidden = on
		Hud.refresh()
	end
end

function Hud.setPanelOpener(fn: (string) -> ())
	openPanel = fn
end

local TOOL_SHORT = { Hammer = "COLLAR", SteelHammer = "TREATS", Jackhammer = "WHISTLE" }
local MACHINE_ICON = { AutoCracker = "machine", HydraulicPress = "press", IndustrialCrusher = "crusher" }

local function myMachine(m: any): any?
	for _, e in (m and m.Machines) or {} do
		if e.UserId == player.UserId then
			return e
		end
	end
	return nil
end

local function ownStation(m: any): any?
	for _, st in (m and m.Stations) or {} do
		if st.UserId == player.UserId then
			return st
		end
	end
	return nil
end

-- Daily rewards ready to claim (the red number on DAILY): quests done and not claimed, plus the gift when it is
-- ready, read from the rows the server sent (the same rule as shared/Quests.view's Claimable, which is the fallback).
local function dailyReady(prof: any): number
	local d = prof and prof.Daily
	if type(d) ~= "table" then
		return 0
	end
	if type(d.Quests) ~= "table" or type(d.Gift) ~= "table" then
		return tonumber(d.Claimable) or 0
	end
	local n = if d.Gift.Ready == true then 1 else 0
	for _, q in d.Quests do
		if q.Done == true and q.Claimed ~= true then
			n += 1
		end
	end
	return n
end
Hud.dailyReady = dailyReady -- LobbyHudV2's DAILY reminder wiggle

-- Compact menu tile (lobby mockup): blue rounded square, picture, one-word caption. `icon` is a HudArt slot (owner
-- picture with a stand-in) or a plain UI.icon kind.
local BAG_FOLD_W = 150 -- the candy bag pill, folded for the landscape phone row (Hud.arrangeLobby)
local TILE_CAP = T.Body + 2 -- tile caption size (fitted down to T.Small when "Settings" needs it; the body size read tiny on a phone)
-- The red count badge (UI.newDot) on a 12 px anchor: made now, 34 px across (UI.newDot draws 20; 28 real px or
-- more at the phone scale), its number at body size, so it reads on a phone. UI.newDot keeps the frame on later
-- calls (it only flips Visible and the number).
local function badge(anchor: Frame): Frame
	local d = UI.newDot(anchor, false)
	d.Size = UDim2.fromOffset(34, 34)
	local mark = d:FindFirstChild("Mark") :: TextLabel?
	if mark then
		UI.fit(mark, T.Body + 4, T.MinText)
	end
	return d
end

local function tile(parent: Instance, name: string, caption: string?, icon: string, order: number, onClick: () -> (), small: boolean?): TextButton
	local s = if small then 44 else TILE
	local b = UI.button(parent, "", "blue", onClick, { Name = name, Size = UDim2.fromOffset(s, s), LayoutOrder = order })
	UI.corner(b, 14)
	if not small then
		if Theme.PetStyle then
			PetStyle.iconTile(b, s) -- the video's square: light top, dark lip, drifting streaks, white rim
		else
			HudArt.skin(b, "btn_square_blue")
		end
	end
	local l = b:FindFirstChild("Label")
	if l then
		l:Destroy()
	end
	local hasCap = caption ~= nil and not small
	local isz = if small then 28 else (if hasCap then 38 else 42)
	local iprops = { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if small then 8 elseif hasCap then 3 else 11), ZIndex = 3 }
	if HudArt.Slots[icon] then
		HudArt.image(b, icon, isz, iprops)
	else
		UI.icon(b, icon, isz, iprops)
	end
	if hasCap then
		-- plain words on all four tiles, one size: the word pictures (only Upgrade and Party have one) shrank into a
		-- thin strip at this width and made those two captions smaller than the others;
		-- the box runs 3 px past each side of the tile so "Settings" keeps the full size
		local cap = UI.text(b, caption :: string, { Name = "Caption", Font = UI.Bold, TextSize = TILE_CAP, Outline = "Normal", Size = UDim2.new(1, 8, 0, 24), Position = UDim2.new(0, -4, 1, -25), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		cap.TextWrapped = false
		UI.fit(cap, TILE_CAP, T.Small)
	end
	return b
end

-- Tool slot (board 2/3): number, icon, caption; gold ring when it is the tool in use. Display only: tools follow
-- the context (hand at the pile, hammer at the plate), there is no manual switching in this game.
local SLOT_ICON = 40 -- hotbar picture size
local function toolSlot(parent: Instance, name: string, num: string, icon: string, caption: string, order: number): Frame
	local f = UI.card(parent, "hud", { Name = name, Size = UDim2.fromOffset(SLOT, SLOT + 2), LayoutOrder = order })
	UI.text(f, num, { Name = "Num", Font = UI.Head, TextSize = T.Body, Outline = "Strong", Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(18, 20) })
	refs[name .. "Icon"] = UI.icon(f, icon, SLOT_ICON, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8) })
	local cap = UI.text(f, caption, { Name = "Caption", Font = UI.Head, TextSize = T.Body, Outline = "Normal", Position = UDim2.new(0, 2, 1, -23), Size = UDim2.new(1, -4, 0, 21), TextXAlignment = Enum.TextXAlignment.Center })
	cap.TextWrapped = false
	UI.fit(cap, T.Body, T.MinText) -- RAINBOW is the longest tool word; it shrinks rather than clipping to "RAINBO"
	return f
end

-- Hunt hotbar (owner mockup reference/ui/hunt_hud): the tool in use is a gold slot, the other blue. The blue slot can
-- carry the owner's picture (HudArt slot_blue, added once); the gold one is drawn over it.
local function setSlot(f: Frame, on: boolean)
	if not f:GetAttribute("Skinned") then
		f:SetAttribute("Skinned", true)
		HudArt.skin(f, "slot_blue", SLOT + 2)
	end
	local skin = f:FindFirstChild("Skin") :: ImageLabel?
	local edge = f:FindFirstChild("Border") :: UIStroke?
	if edge then
		edge.Enabled = on or skin == nil
		edge.Color = if on then TC.GoldDeep else TC.PanelEdge
		edge.Thickness = 3
	end
	if skin then
		skin.Visible = not on
	end
	f.BackgroundTransparency = if skin and not on then 1 else 0
	f.BackgroundColor3 = if on then TC.Gold else TC.Hud
	-- gold arrow over the slot in use (not only the colour says it; the dock sits on the bottom edge), big enough to
	-- read at a glance on a phone
	local arrow = f:FindFirstChild("InUse") :: TextLabel?
	if not arrow then
		local a = UI.text(f, "\u{25BC}", { Name = "InUse", Font = UI.Bold, TextSize = 24, TextColor3 = TC.Gold, Outline = "Strong", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.fromOffset(32, 24), TextXAlignment = Enum.TextXAlignment.Center })
		a.TextWrapped = false
		arrow = a
	end
	(arrow :: TextLabel).Visible = on
end

-- Hunt cards (timer, CARRIED, SHELLS): cream with a navy edge and a gold rim, navy captions (owner mockup).
-- Pet style: the clip's white-blue card with a sky edge and no rim, navy words.
local PET = Theme.Pet
local CREAM = PanelSkin.CREAM
local CARD_EDGE = if Theme.PetStyle then PET.QuestEdge else TC.PanelEdge
local function creamCard(f: Frame)
	f.BackgroundColor3 = CREAM
	f.BackgroundTransparency = 0
	local edge = f:FindFirstChild("Border") :: UIStroke?
	if edge then
		edge.Color = CARD_EDGE
		edge.Thickness = 3
	end
	if not Theme.PetStyle then
		local rim = UI.frame(f, { Name = "Rim", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1 })
		UI.corner(rim, T.Radius - 2)
		UI.stroke(rim, TC.Gold, 3)
	end
	HudArt.skin(f, "hud_card", f.Size.Y.Offset)
	for _, name in { "Caption", "Pile" } do
		local l = f:FindFirstChild(name) :: TextLabel?
		if l then
			l.TextColor3 = PanelSkin.NAVY
			local o = l:FindFirstChildOfClass("UIStroke")
			if o then
				o.Enabled = false
			end
		end
	end
end

-- Hunt counters (CARRIED / NEST / CANDY): the caption reads as a label in its own right (display font, body size)
-- and the number keeps its weight under it, inside a slightly taller card.
local COUNTER_H = 56
local function huntCounter(f: Frame)
	f.Size = UDim2.fromOffset(f.Size.X.Offset, COUNTER_H)
	local icon = f:FindFirstChild("Icon") :: GuiObject?
	if icon then
		icon.Position = UDim2.fromOffset(7, (COUNTER_H - 30) // 2)
	end
	local cap = f:FindFirstChild("Caption") :: TextLabel?
	if cap then
		cap.Font = UI.Head
		cap.Position = UDim2.fromOffset(44, 5)
		cap.Size = UDim2.new(1, -50, 0, 20)
		cap.TextWrapped = false
		UI.fit(cap, T.Body, T.MinText)
	end
	local v = f:FindFirstChild("Value") :: TextLabel?
	if v then
		v.Position = UDim2.fromOffset(44, 25)
		v.Size = UDim2.new(1, -50, 0, 26)
		UI.fit(v, T.Count, T.Body)
	end
end

-- One "full" look for CARRIED and QUEUE: a red number and a red card edge (the colour change alone was easy to miss).
local function markFull(card: Frame, full: boolean)
	local edge = card:FindFirstChild("Border") :: UIStroke?
	if edge then
		edge.Color = if full then TC.Red else TC.PanelEdge
	end
	local v = card:FindFirstChild("Value") :: TextLabel?
	if v and full then
		v.TextColor3 = TC.Red
	end
end

-- Notifications ---------------------------------------------------------------------------------
-- Gameplay messages from PileView and the server, reworded to short actionable text and coalesced by UI.notify.
local REWORD = {
	["Basket full: take eggs to your nest"] = "Basket full. Take your eggs to your nest.",
	["Tray full: hatch some eggs first"] = "Nest is full. Hatch some eggs first.",
	["Candy bag full: sell at a candy stand"] = "Candy bag full. Sell at a candy stand.",
	["Your candy bag is empty. Nothing to sell."] = "No candy to sell.",
}

local function tagOf(text: string): string?
	if string.find(text, "^Basket full") then
		return "arena:basket"
	elseif string.find(text, "^Candy bag full") then
		return "arena:bag"
	elseif string.find(text, "^Collect more eggs") or string.find(text, "^Walk closer") or string.find(text, "^Move closer") or string.find(text, "^Nest is full") or string.find(text, "^Your Auto Nest hatches") then
		return "arena:" .. string.lower(string.sub(text, 1, 12))
	end
	return nil
end

-- Quick left-right wiggle of a counter card's icon (basket full feedback).
local function shakeIcon(card: Instance?)
	local icon = card and card:FindFirstChild("Icon") :: GuiObject?
	if not icon or UI.Reduced then
		return
	end
	task.spawn(function()
		for _, r in { -14, 12, -8, 5, 0 } do
			icon.Rotation = r
			task.wait(0.05)
		end
	end)
end

-- Shells counter: rolls up to a higher number instead of jumping (0.4 s), drops show at once.
local rubbleShown = -1
local rubbleToken = 0
local rubbleRoll: { N: number, Cap: number }? = nil -- the roll-up in progress (refreshes with the same count let it finish)
local function setRubbleRolling(n: number, cap: number)
	if rubbleRoll and rubbleRoll.N == n and rubbleRoll.Cap == cap then
		return
	end
	rubbleToken += 1
	local token = rubbleToken
	local from = rubbleShown
	rubbleShown = n
	rubbleRoll = nil
	if UI.Reduced or from < 0 or n <= from then
		refs.SetRubble(n, cap)
		return
	end
	rubbleRoll = { N = n, Cap = cap }
	task.spawn(function()
		local t0 = os.clock()
		while token == rubbleToken do
			local k = math.min(1, (os.clock() - t0) / 0.4)
			refs.SetRubble(math.floor(from + (n - from) * k + 0.5), cap)
			if k >= 1 then
				rubbleRoll = nil
				break
			end
			task.wait()
		end
	end)
end

function Hud.toast(text: string, kind: string?)
	if type(text) ~= "string" then
		return
	end
	if string.find(text, "^Basket full") and refs.CarryCard and refs.CarryCard.Visible then
		shakeIcon(refs.CarryCard) -- the basket icon and the BASKET FULL button already say it
		return
	end
	local t = REWORD[text] or text
	local k = kind or "info"
	if string.find(t, "invited you to a hunt party") and not State.Match and not State.Party then
		return -- the PARTY INVITE dialog (PartyPanel) already says it, with ACCEPT / DECLINE
	end
	if string.find(t, "^Basket full") then
		k = "basket"
	end
	UI.notify(t, k, { Tag = tagOf(t) })
end

-- Removes guidance notifications: "basket" | "bag" | "arena" (all arena guidance) | "all".
function Hud.dismissToasts(tag: string)
	if tag == "all" or tag == "arena" then
		UI.dismissNotices("arena:")
	else
		UI.dismissNotices("arena:" .. tag)
	end
end

-- Material discoveries: quiet, merged (Config.MaterialNoticeSeconds). The full record is in Collection > Materials.
local matPending: { string } = {}
local matScheduled = false
local matShownAt = -math.huge
function Hud.materialNotice(ids: { string })
	for _, id in ids do
		if type(id) == "string" and Config.Materials[id] and not table.find(matPending, id) then
			table.insert(matPending, id)
		end
	end
	if matScheduled or #matPending == 0 then
		return
	end
	matScheduled = true
	local wait = math.max(0.35, matShownAt + Config.MaterialNoticeSeconds - os.clock())
	task.delay(wait, function()
		matScheduled = false
		local names = {}
		for _, id in matPending do
			table.insert(names, Config.Materials[id].Name)
		end
		table.clear(matPending)
		local m = State.Match
		if #names == 0 or not m or m.Phase ~= "Searching" then
			return -- the geode was found meanwhile: the reveal is not covered (the record is in Collection)
		end
		matShownAt = os.clock()
		UI.notify("Material discovered: " .. table.concat(names, ", "), "material")
	end)
end

-- Entering the reveal: every gameplay notice (and a pending discovery) leaves the screen at once.
function Hud.clearMessages()
	table.clear(matPending)
	UI.dismissNotices("")
end

-- Cash counter rolls to the new value (display only).
local function setCash(n: number)
	if n == shownCash then
		return
	end
	if cashTween then
		cashTween:Cancel()
	end
	-- (not in the pet tower: the coin pill is hidden there and the floor-end card already says the coins)
	-- (not in a hunt either: the surprise egg pops there already say the coins, and the pill is hidden, so the text
	-- landed on the hunt clock card; never on a pill that is not drawn: Juice.onScreen)
	if shownCash >= 0 and n > shownCash and refs.Cash and (player:GetAttribute("InTower") ~= true and player:GetAttribute("InBattle") ~= true)
		and State.Match == nil and Juice.onScreen(refs.Cash) then
		Juice.payout(n - shownCash) -- coins fly from the CLAIM / OPEN / SELL button that earned them (if one did)
		Juice.floatText(refs.Cash, "+" .. UI.money(n - shownCash), TC.Cash)
		if refs.CoinIcon then
			Juice.spin(refs.CoinIcon) -- the coin picture turns once as the coins land
		end
	end
	if UI.Reduced or shownCash < 0 then
		cashValue.Value = n
	else
		cashValue.Value = shownCash
		local tw = TweenService:Create(cashValue, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = n })
		cashTween = tw
		tw:Play()
	end
	shownCash = n
	UI.modalCash(n)
end

-- "Start your first hunt" is a brief cue, not a banner: CUE_SECONDS after the lobby appears, gone once any panel opens.
local CUE_SECONDS = 14
local clockTick = 1 -- timer clock tick direction (flips each second)
local cueStart: number? = nil
local cueBrowsed = false
-- True while the top-centre objective card (START YOUR FIRST HUNT, PARTY 2/4, FIND THE PET...) is on screen.
function Hud.objectiveShown(): boolean
	local obj, top = refs.Objective, refs.Top
	return obj ~= nil and top ~= nil and obj.Visible and top.Visible
end

function Hud.cueActive(): boolean
	if cueBrowsed then
		return false
	end
	if cueStart == nil then
		cueStart = os.clock()
	end
	return os.clock() - (cueStart :: number) < CUE_SECONDS
end

-- Processing: the plate bar is shown only while the server's progress for the current rock is actually moving
-- (an update within PROGRESS_LIVE seconds) or the station's machine is running. Leaving the table, a new round
-- or the end of the hunt hides it; nothing animates it on the client.
local PROGRESS_LIVE = 1.6
local PROC_HOLD = 0.8 -- seconds the card stays after its reason ends (no flicker between hits or context ticks)
local lastProgress: number? = nil
local lastProgressAt = -math.huge
local lastProgressKey: any = nil
local procUntil = -math.huge -- the card stays on screen until this os.clock()
-- The bar eases between server values (over about the time between the last two hits) instead of jumping, and the
-- percent follows the eased value. It only ever moves toward a value the server sent (nothing is predicted).
local procShown = Instance.new("NumberValue")
local procTween: Tween? = nil
local procGoal = -1
local procGap = 0.4
local procBase = "HATCHING"

function Hud.build()
	local root = UI.screen()
	UI.ModalChanged.Event:Connect(function(name)
		if name ~= nil then
			cueBrowsed = true
		end
	end)

	-- Left column: cash (lobby) / counters (hunt), processing, machine, roster. One list: nothing overlaps.
	local left = UI.frame(root, { Name = "Left", Position = UDim2.fromOffset(T.Edge + 4, T.Edge), Size = UDim2.fromOffset(LEFT_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
	UI.list(left, Enum.FillDirection.Vertical, 6)
	-- The column sits in a clipped box that only scrolls when a very short screen still cannot hold it at the smallest
	-- card size (fitLeft); the box has room for the cards' rims and the red dots, which hang past the column.
	local leftBox = Instance.new("ScrollingFrame")
	leftBox.Name = "LeftBox"
	leftBox.BackgroundTransparency = 1
	leftBox.BorderSizePixel = 0
	leftBox.ScrollBarThickness = 0
	leftBox.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Left -- the bar hugs the column, not the far side of the box
	leftBox.ScrollingDirection = Enum.ScrollingDirection.Y
	leftBox.ScrollingEnabled = false
	leftBox.Active = false
	leftBox.CanvasSize = UDim2.new()
	leftBox.Size = UDim2.fromOffset(BOX_W, 1000)
	leftBox.Parent = root
	left.Position = UDim2.fromOffset(BOX_PAD, 0)
	left.Parent = leftBox
	refs.Stats = left
	refs.LeftList = left:FindFirstChildOfClass("UIListLayout")
	-- coin counter (mockup): a cream pill with the amount, the coin picture overlapping its left end
	local cashRow = UI.frame(left, { Name = "Resources", LayoutOrder = 1, Size = UDim2.fromOffset(LEFT_W + 24, 40), BackgroundTransparency = 1 })
	-- (pet style: the clip's navy pill with white digits, the coin picture over its left end)
	local pill = UI.frame(cashRow, { Name = "Pill", Position = UDim2.fromOffset(20, 5), Size = UDim2.new(1, -20, 1, -10), BackgroundColor3 = if Theme.PetStyle then PET.TabBar else Color3.fromRGB(255, 246, 214) })
	UI.corner(pill, 15)
	-- a light blue edge on the navy pill (the dark edge sank into the world behind it on a phone)
	UI.stroke(pill, if Theme.PetStyle then PET.QuestEdge else TC.PanelEdge, 3)
	HudArt.skin(pill, "coin_pill", 30)
	-- no drifting light band on the coin pill: on the flat cream it read as a half-filled progress bar
	local drift = pill:FindFirstChild("Drift", true)
	if drift then
		drift:Destroy()
	end
	refs.CoinIcon = HudArt.image(cashRow, "Coin", 40, { Position = UDim2.fromOffset(0, 0), ZIndex = 3 })
	-- a clear gap between the coin picture (40 px, over the pill's first 20) and the first digit
	local amount = UI.text(pill, "0", { Name = "Amount", Font = UI.Head, TextSize = 26, TextColor3 = if Theme.PetStyle then TC.Text else TC.DarkText, Outline = if Theme.PetStyle then "Normal" else false, Position = UDim2.fromOffset(31, 1), Size = UDim2.new(1, -37, 1, -2) })
	amount.TextWrapped = false
	UI.fit(amount, 26, T.MinText)
	refs.Resources = cashRow
	local function showCash(v: number)
		-- short from 10,000 up (12.5K) so the pill keeps its big digits
		local n = math.floor(v + 0.5)
		amount.Text = if n >= 10000 and n < 100000 then (string.gsub(string.format("%.1f", math.floor(n / 100) / 10), "%.0$", "")) .. "K" else UI.num(n)
	end
	cashValue.Changed:Connect(showCash)
	showCash(0)
	refs.Cash = amount
	Effects.setCashTarget(refs.Cash)
	Juice.setCoinTarget(refs.Cash) -- coins earned on a menu button fly here (Juice.payout)
	-- lobby: the candy bag (only when it holds shells to sell): how full it is, and what to do with it
	-- a cream card like the coin pill above it (navy words, no outline)
	-- (as wide as PLAY, so the "sell" line keeps a readable size; the shell icon matches the hunt counter)
	local bag = UI.frame(left, { Name = "BagLine", BackgroundColor3 = PanelSkin.CREAM, Size = UDim2.fromOffset(LOBBY_W, 54), LayoutOrder = 2, Visible = false })
	UI.corner(bag, 12)
	UI.stroke(bag, PanelSkin.NAVY, 2.5)
	UI.icon(bag, "rubble", 30, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0) })
	refs.Rubble = UI.text(bag, "", { Name = "Bag", Font = UI.Bold, TextSize = T.Body, TextColor3 = PanelSkin.NAVY, Outline = false, Position = UDim2.fromOffset(40, 3), Size = UDim2.new(1, -44, 0, 22) })
	refs.Rubble.TextXAlignment = Enum.TextXAlignment.Left
	refs.Rubble.TextWrapped = false
	UI.fit(refs.Rubble, T.Body, T.MinText)
	-- the call to action as big as the count and in a strong green on the cream (it was small navy and read faint)
	refs.RubbleSub = UI.text(bag, "Sell for coins!", { Name = "BagSub", Font = UI.Bold, TextSize = T.Body + 2, TextColor3 = Color3.fromRGB(14, 112, 40), Outline = false, Position = UDim2.fromOffset(40, 27), Size = UDim2.new(1, -44, 0, 23) })
	refs.RubbleSub.TextWrapped = false
	UI.fit(refs.RubbleSub, T.Body + 2, T.Small) -- short words so the line keeps a big size (bug #220)
	refs.BagLine = bag
	-- Daily gift + quests (lobby only), under the cash: the right column is full on short phones (JUMP sits under
	-- it). A small red dot shows how many rewards are ready to claim.
	-- (under PLAY and the TOWER row, as in the lobby mockup)
	local daily = HudArt.bigButton(left, {
		Name = "Quests", Style = "blue", Art = "Calendar", Skin = "btn_blue", Title = "DAILY", Width = LOBBY_W - 20, Height = 52, LayoutOrder = 70,
		OnClick = function()
			if UI.modalOpen() == "Quests" then
				UI.closeModal()
			else
				QuestPanel.open()
			end
		end,
	})
	-- red "!" dot (UI.newDot) with the number of rewards ready to claim. It hangs on a small anchor at the button's
	-- right end, level with its top, so it sits beside DAILY (narrower than TOWER) instead of over the TOWER button;
	-- just outside the rounded corner (it covered the corner), in the room the narrower DAILY leaves
	-- (2026-10-15 phone review: the dot was tiny and inside the picture) now a 34 px badge on the button's top-right
	-- corner, half outside it sideways (DAILY is 20 px narrower than the column, so it stays clear of the screen
	-- edge) and up to the gap above (the TOWER row is drawn later, so the badge never goes under it)
	-- (runner review: the badge sat on the tile's words) centred on the corner itself, half outside both ways
	local dotAt = UI.frame(daily, { Name = "DotAt", BackgroundTransparency = 1, Position = UDim2.new(1, -8, 0, -6), Size = UDim2.fromOffset(12, 12), ZIndex = 6 })
	badge(dotAt)
	refs.QuestsDot = dotAt
	refs.BtnQuests = daily
	-- hunt counters (labelled: what you carry vs what waits at your station vs what you stored)
	refs.CarryCard, refs.SetCarry = UI.counter(left, "basket", "CARRIED", { Name = "CarryCard", LayoutOrder = 3, Size = UDim2.fromOffset(LEFT_W, 52) })
	refs.QueueCard, refs.SetQueue = UI.counter(left, "queue", "NEST", { Name = "TableQueue", LayoutOrder = 4, Size = UDim2.fromOffset(LEFT_W, 52) })
	refs.RubbleCard, refs.SetRubble = UI.counter(left, "rubble", "CANDY", { Name = "RubbleCard", LayoutOrder = 5, Size = UDim2.fromOffset(LEFT_W, 52) })
	for _, c in { refs.CarryCard, refs.QueueCard, refs.RubbleCard } do
		huntCounter(c)
		creamCard(c)
	end
	-- processing (server plate progress)
	local proc = UI.card(left, "hud", { Name = "Processing", Size = UDim2.fromOffset(LEFT_W, 40), LayoutOrder = 6, Visible = false })
	refs.ProcText = UI.text(proc, "HATCHING", { Font = UI.Bold, TextSize = T.Tiny, Outline = "Normal", Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 18) })
	local _, pfill = UI.bar(proc, { Position = UDim2.new(0, 8, 1, -14), Size = UDim2.new(1, -16, 0, 8) })
	refs.ProcFill = pfill
	refs.Proc = proc
	procShown.Changed:Connect(function(v)
		pfill.Size = UDim2.fromScale(math.clamp(v, 0, 1), 1)
		refs.ProcText.Text = if procBase == "HATCHING" then procBase .. " " .. math.floor(v * 100 + 0.5) .. "%" else procBase
	end)
	-- machine chip: state of the installed machine; tapping starts / stops it (server ToggleMachine)
	local mach = UI.button(left, "", "gray", function()
		local prof = State.Profile
		if prof and prof.InstalledMachine and myMachine(State.Match) then
			Net.event("ShopAction"):FireServer("ToggleMachine")
		end
	end, { Name = "Machine", Size = UDim2.fromOffset(LEFT_W, 44), LayoutOrder = 7, Visible = false })
	local ml = mach:FindFirstChild("Label") :: TextLabel
	ml.Position = UDim2.fromOffset(38, 2)
	ml.Size = UDim2.new(1, -42, 1, -4)
	ml.TextXAlignment = Enum.TextXAlignment.Left
	ml.Font = UI.Bold
	UI.fit(ml, T.Tiny + 1, T.MinText)
	refs.MachLabel = ml
	refs.MachIconKind = ""
	refs.Mach = mach
	-- party roster (hunt)
	local roster = UI.frame(left, { Name = "Roster", Size = UDim2.fromOffset(LEFT_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 8, Visible = false })
	UI.list(roster, Enum.FillDirection.Vertical, 3)
	refs.Roster = roster
	-- lobby mode row under PLAY: the TOWER button (TowerPanel fills it)
	local modeRow = UI.frame(left, { Name = "ModeRow", BackgroundTransparency = 1, Size = UDim2.fromOffset(LOBBY_W, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 60 })
	local modeList = UI.list(modeRow, Enum.FillDirection.Horizontal, 6)
	refs.ModeList = modeList
	-- Touch screens: the lobby buttons (PLAY, GIFT, TOWER, BATTLE, DAILY) leave the column and go into this grid, a
	-- row along the top on a landscape phone or two columns on an upright one, so none sits in Roblox's thumbstick
	-- zone (the lower left; a button there takes the touch and the player cannot walk: carter, phone, 2026-10-15).
	-- SafeZones.lobbyLayout decides; arrangeLobby (below) moves the buttons whenever the screen or the set changes.
	local actions = UI.frame(left, { Name = "Actions", BackgroundTransparency = 1, Size = UDim2.fromOffset(LOBBY_W, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 45, Visible = false })
	local actionGrid = Instance.new("UIGridLayout")
	actionGrid.Name = "Grid"
	actionGrid.CellPadding = UDim2.fromOffset(6, 6)
	actionGrid.SortOrder = Enum.SortOrder.LayoutOrder
	actionGrid.FillDirection = Enum.FillDirection.Horizontal
	actionGrid.Parent = actions
	-- landscape phones: one row, the PLAY pill wider than the square tiles after it (a grid cannot do that), so
	-- the row swaps the grid for this list; grid and list never sit in the frame at the same time
	local actionRow = Instance.new("UIListLayout")
	actionRow.Name = "Row"
	actionRow.FillDirection = Enum.FillDirection.Horizontal
	actionRow.Padding = UDim.new(0, 6)
	actionRow.SortOrder = Enum.SortOrder.LayoutOrder
	actionRow.VerticalAlignment = Enum.VerticalAlignment.Center
	-- PlayQueue is PlayButton's wrapper (the PLAY button and the queue card inside it share its size)
	local LOBBY_BUTTONS = { "PlayQueue", "FreeGift", "SpinWheel", "TowerButton", "BattleButton", "Quests" }
	local boxW = BOX_W -- width of the clipped box; wider than the column when the touch row needs it (fitLeft keeps it)
	local function shapeOne(b: GuiObject, w: number?, h: number?)
		if b:GetAttribute("HomeW") == nil then
			b:SetAttribute("HomeW", b.Size.X.Offset)
			b:SetAttribute("HomeH", b.Size.Y.Offset)
		end
		local cw = w or b:GetAttribute("HomeW") :: number
		local ch = h or b:GetAttribute("HomeH") :: number
		b.Size = UDim2.fromOffset(cw, ch)
		if b:IsA("GuiButton") then
			HudArt.compact(b, w ~= nil, cw, ch)
		end
	end
	local function shape(b: GuiObject, w: number?, h: number?)
		shapeOne(b, w, h)
		if b.Name == "PlayQueue" then
			for _, c in b:GetChildren() do
				if c:IsA("GuiObject") then
					shapeOne(c, w, h)
				end
			end
		end
	end
	-- The candy bag card folded to one line (icon + "Candy bag 84/100", no "Sell for coins!" line) for the landscape
	-- phone row, and back to the full card elsewhere.
	local function foldBag(on: boolean)
		local bag = refs.BagLine
		local icon = bag:FindFirstChild("Icon") :: GuiObject?
		if bag:GetAttribute("Folded") == on then
			return
		end
		bag:SetAttribute("Folded", on)
		local prof = State.Profile
		if prof then
			refs.Rubble.Text = (if on then (if prof.Rubble >= prof.Capacity then "FULL " else "Candy ") elseif prof.Rubble >= prof.Capacity then "Candy bag FULL " else "Candy bag ") .. prof.Rubble .. "/" .. prof.Capacity
		end
		-- the drawn icon's parts are offsets, so it shrinks through a UIScale (around its anchor) and not its Size
		local iconScale: UIScale? = if icon then icon:FindFirstChild("Fold") :: UIScale? else nil
		if icon and not iconScale then
			local sc = Instance.new("UIScale")
			sc.Name = "Fold"
			sc.Parent = icon
			iconScale = sc
		end
		if on then
			bag.Size = UDim2.fromOffset(BAG_FOLD_W, 30)
			if iconScale then
				iconScale.Scale = 22 / 30
			end
			refs.Rubble.Position = UDim2.fromOffset(32, 0)
			refs.Rubble.Size = UDim2.new(1, -36, 1, 0)
			refs.RubbleSub.Visible = false
		else
			bag.Size = UDim2.fromOffset(LOBBY_W, 54)
			if iconScale then
				iconScale.Scale = 1
			end
			refs.Rubble.Position = UDim2.fromOffset(40, 3)
			refs.Rubble.Size = UDim2.new(1, -44, 0, 22)
			refs.RubbleSub.Visible = true
		end
	end
	local function arrangeLobby()
		local touch = UserInputService.TouchEnabled
		local L = SafeZones.lobbyLayout(UI.Logical.X, UI.Logical.Y, touch, LOBBY_W)
		local found: { [string]: GuiObject } = {}
		for _, holder in { left, modeRow, actions } do
			for _, c in holder:GetChildren() do
				if c:IsA("GuiObject") and table.find(LOBBY_BUTTONS, c.Name) then
					found[c.Name] = c
				end
			end
		end
		for i, name in LOBBY_BUTTONS do
			local b = found[name]
			if b then
				if b:GetAttribute("HomeOrder") == nil then
					b:SetAttribute("HomeOrder", b.LayoutOrder)
				end
				if L.Mode == "column" then
					shape(b)
					b.LayoutOrder = b:GetAttribute("HomeOrder") :: number
					local home: Instance = if name == "TowerButton" or name == "BattleButton" then modeRow else left
					if b.Parent ~= home then
						b.Parent = home
					end
				else
					-- row mode: PLAY keeps a wide pill, the four others are squares (SafeZones.lobbyLayout)
					shape(b, if name == "PlayQueue" and L.PlayW then L.PlayW else L.CellW, L.CellH)
					b.LayoutOrder = i
					if b.Parent ~= actions then
						b.Parent = actions
					end
				end
			end
		end
		local bagLine = left:FindFirstChild("BagLine")
		if L.Mode == "column" then
			actions.Visible = false
			actions.LayoutOrder = 45
			modeRow.Visible = true
			if bagLine and bagLine:IsA("GuiObject") then
				bagLine.LayoutOrder = 2
			end
			foldBag(false)
			refs.ObjPillW = nil
			boxW = BOX_W
		else
			local w
			if L.Mode == "row" then
				actionGrid.Parent = nil
				actionRow.Parent = actions
				w = SafeZones.rowWidth(L, 6)
			else
				actionRow.Parent = nil
				actionGrid.Parent = actions
				actionGrid.CellSize = UDim2.fromOffset(L.CellW, L.CellH)
				actionGrid.FillDirectionMaxCells = L.Cols
				w = L.Cols * L.CellW + (L.Cols - 1) * 6
			end
			actions.Size = UDim2.fromOffset(w, 0)
			actions.Visible = true
			actions.LayoutOrder = 2 -- right under the coins: anything else in the column (objective, candy line) goes below
			modeRow.Visible = false
			-- the candy line (a plain card, it takes no touches) goes under the buttons so the row stays high; on a
			-- landscape phone it folds to one small pill so the HUD covers less of the view (carter, phone, 2026-10-15)
			if bagLine and bagLine:IsA("GuiObject") then
				bagLine.LayoutOrder = 46
			end
			foldBag(L.Mode == "row")
			-- the NEXT UP pill (ObjLayout) spans the row, so its sub line keeps one line
			refs.ObjPillW = math.max(LEFT_W + 24, w)
			boxW = math.max(BOX_W, w + 2 * BOX_PAD + 12)
		end
		leftBox.Size = UDim2.fromOffset(boxW, leftBox.Size.Y.Offset)
		-- the objective follows the same verdict (pill under the row, card at the top centre in column mode)
		if refs.ObjLayout and refs.ObjInMatch ~= nil then
			refs.ObjLayout(refs.ObjInMatch, L.Mode ~= "column")
		end
		local obj = refs.Objective
		if obj and refs.ObjPill == true then
			obj.Size = UDim2.fromOffset(refs.ObjPillW or (LEFT_W + 24), obj.Size.Y.Offset)
		end
	end
	refs.ArrangeLobby = arrangeLobby
	for _, holder in { left, modeRow } do
		holder.ChildAdded:Connect(function(c)
			if table.find(LOBBY_BUTTONS, c.Name) then
				task.defer(arrangeLobby)
			end
		end)
	end
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		task.defer(arrangeLobby)
	end)

	-- Studio test status only (never shown to players)
	local so = UI.card(root, "hud", { Name = "TestStatus", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, T.Edge, 1, -T.Edge), Size = UDim2.fromOffset(160, 24), Visible = false })
	local sot = UI.text(so, "Studio test: saves off", { TextSize = T.Tiny, TextColor3 = TC.Count, Outline = "Normal", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center })
	sot.TextWrapped = false
	refs.SavesOff = so

	-- Right column: timer (hunt), then Settings and the menu tiles.
	local right = UI.frame(root, { Name = "Menu", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -T.Edge, 0, T.Edge), Size = UDim2.fromOffset(RIGHT_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
	UI.list(right, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	refs.Menu = right
	-- The hunt timer and pile count sit at the top of the LEFT column: Roblox's player list opens over the top right
	-- corner (it has no "is open" signal), so essential round numbers never go there.
	local timer = UI.card(left, "hud", { Name = "Timer", Size = UDim2.fromOffset(LEFT_W, 52), LayoutOrder = 0, Visible = false })
	local clock = UI.icon(timer, "clock", 30, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 22, 0.5, 0) }) -- mockup: clock left of the time
	refs.Clock = clock
	refs.TimerText = UI.text(timer, "0:00", { Name = "Time", Font = UI.Head, TextSize = Theme.Text.Timer, TextColor3 = TC.Gold, Position = UDim2.fromOffset(42, 5), Size = UDim2.new(1, -46, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	refs.TimerText.TextWrapped = false
	-- clear of the card's rim (the digits' tops were cut off at the old 1 px top) and fitted to the box
	UI.fit(refs.TimerText, Theme.Text.Timer, 18)
	refs.PileText = UI.text(timer, "", { Name = "Pile", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Normal", Position = UDim2.new(0, 42, 1, -19), Size = UDim2.new(1, -46, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	refs.PileText.TextWrapped = false
	UI.fit(refs.PileText, T.Tiny, 11)
	refs.Timer = timer
	creamCard(timer)
	-- lobby mockup order: My Pets, Upgrade, Party, Settings (the owner's DEV tile stays last, LayoutOrder 99)
	refs.BtnCollection = tile(right, "Collection", "My Pets", "Paw", 2, function()
		openPanel("Collection")
	end)
	-- the red "!" hangs on an anchor inside the tile's top-right corner (above every tile layer), so the whole dot
	-- shows; on the tile's own corner its top half was cut off at the top of the menu column
	-- (2026-10-15 phone review: the "!" was tiny and over the picture's corner) now a 34 px badge on the tile's
	-- top-right corner, half outside it (the menu column's gap to the screen edge keeps it on screen)
	refs.PetsDot = UI.frame(refs.BtnCollection, { Name = "DotAt", BackgroundTransparency = 1, Position = UDim2.new(1, -8, 0, -4), Size = UDim2.fromOffset(12, 12), ZIndex = 8 })
	badge(refs.PetsDot)
	refs.BtnShop = tile(right, "Shop", "Upgrade", "Hammer", 3, function()
		openPanel("Shop")
	end)
	refs.BtnParty = tile(right, "Party", "Party", "Party", 4, function()
		openPanel("Party")
	end)
	refs.BtnSettings = tile(right, "Settings", "Settings", "Gear", 5, function()
		openPanel("Settings")
	end)
	refs.BtnLobby = tile(right, "Lobby", "Lobby", "exit", 6, function()
		openPanel("ConfirmReturn")
	end)
	-- the tile you last opened keeps a soft gold ring until another menu opens (where you were, at a glance)
	local lastRing: UIStroke? = nil
	local TILE_OF = { Collection = refs.BtnCollection, Shop = refs.BtnShop, Party = refs.BtnParty, Settings = refs.BtnSettings }
	UI.ModalChanged.Event:Connect(function(name)
		if name == "Collection" and lastPets ~= nil then
			-- opening the Pet Book is seeing the new pets: the "!" goes now, not at the next profile change
			seenPets = lastPets
			UI.newDot(refs.PetsDot, false)
		end
		local t = if name then TILE_OF[name] else nil
		if not t then
			return
		end
		if lastRing then
			lastRing:Destroy()
		end
		local ring = Instance.new("UIStroke")
		ring.Name = "LastOpened"
		ring.Color = TC.Gold
		ring.Thickness = 3
		ring.Transparency = 0.25
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = t
		lastRing = ring
	end)
	refs.BtnResults = tile(right, "Results", "Results", "results", 7, function()
		openPanel("Results")
	end)
	-- Right column vs Roblox's jump button (TouchLayout, screen px). On short wide phones (phone-1108x512) one column
	-- of four tiles reaches into the jump area, so the tiles fold into two columns while that would happen.
	local menuList = right:FindFirstChildOfClass("UIListLayout")
	local menuGrid = Instance.new("UIGridLayout")
	menuGrid.Name = "Fold"
	menuGrid.CellSize = UDim2.fromOffset(TILE, TILE)
	menuGrid.CellPadding = UDim2.fromOffset(6, 6)
	menuGrid.FillDirection = Enum.FillDirection.Horizontal
	menuGrid.FillDirectionMaxCells = 2
	menuGrid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	menuGrid.SortOrder = Enum.SortOrder.LayoutOrder
	-- Lobby on a phone: the tiles go into the top right corner of the whole screen (owner video, polish #105). The HUD
	-- layer keeps Roblox's safe area (top bar + notch insets), which on a notched phone left the grid low and well in
	-- from the edge, though that corner is empty (Roblox's own buttons sit top left). An empty full-screen ScreenGui
	-- measures the insets in the same pixels as the HUD layer, so nothing is guessed per device.
	local insetProbe = Instance.new("ScreenGui")
	insetProbe.Name = "HudInsetProbe"
	insetProbe.ResetOnSpawn = false
	insetProbe.IgnoreGuiInset = true
	insetProbe.ScreenInsets = Enum.ScreenInsets.None
	insetProbe.Enabled = false -- draws nothing; its absolute rectangle is all we read
	insetProbe.Parent = player:WaitForChild("PlayerGui")
	local CLEAR_JUMP = 36 -- screen px kept free between the lowest tile and the reserved jump area (polish #106)
	local function fitMenu()
		if not right.Parent then
			return
		end
		local gui = UI.screen()
		local px = gui.AbsoluteSize
		local cam = Workspace.CurrentCamera
		local full = if cam then cam.ViewportSize else px
		local scale = math.max(UI.Scale, 0.1)
		-- insets of the HUD layer inside the full screen (screen px; 0 when the probe has no size yet)
		local topIn, rightIn, bottomIn = 0, 0, 0
		local pa, ps = insetProbe.AbsolutePosition, insetProbe.AbsoluteSize
		if ps.X > 1 and ps.Y > 1 then
			local ga = gui.AbsolutePosition
			topIn = math.clamp(ga.Y - pa.Y, 0, ps.Y * 0.25)
			rightIn = math.clamp((pa.X + ps.X) - (ga.X + px.X), 0, ps.X * 0.2)
			bottomIn = math.clamp((pa.Y + ps.Y) - (ga.Y + px.Y), 0, ps.Y * 0.25)
		end
		local h, n = 0, 0
		for _, c in right:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				h += c.Size.Y.Offset
				n += 1
			end
		end
		h += math.max(0, n - 1) * 6
		local fold = false
		-- hunts: the few tiles left (Settings, Lobby, Results) sit in one row in the top right corner, so they no
		-- longer hang down the side of the view (they covered the nest sign) and the action button has room there
		local hunt = State.Match ~= nil and n > 0
		if hunt then
			-- portrait: placeTop already put the row under the full-width top stack (objective, hint); keep that
			-- height, or the hint card covers the tiles
			right.Position = UDim2.new(1, -T.Edge, 0, if UI.isPortrait() then right.Position.Y.Offset else T.Edge)
			menuGrid.FillDirectionMaxCells = n
			if menuList then
				menuList.Parent = nil
			end
			menuGrid.Parent = right
			right.Size = UDim2.fromOffset(n * TILE + (n - 1) * 6, 0)
			return
		end
		local touch = UserInputService.TouchEnabled and px.Y > 1
		-- touch only: on a computer Roblox's player list opens in that corner (it is closed by default on phones)
		-- up into the empty right end of Roblox's top bar in landscape only: in portrait that strip is the phone's
		-- status bar / notch
		local up = if touch and px.X > px.Y then topIn / scale else 0
		local out = if touch then rightIn / scale else 0
		-- portrait: placeTop put the menu under the full-width top stack (objective, hint); keep that height, or the
		-- objective card covers the first tile's caption ("My Pets", phone-portrait check 2026-10-14)
		local y = if UI.isPortrait() then math.max(T.Edge, right.Position.Y.Offset) else T.Edge - up
		right.Position = UDim2.new(1, -T.Edge + out, 0, y)
		local cols = 1
		if touch then
			-- the lowest tile stays CLEAR_JUMP px above the reserved jump area (screen px from the real bottom):
			-- one column if that fits, else two, else three columns
			-- (and never inside Roblox's jump-button corner, SafeZones.jumpZone)
			local limit = math.max(TouchLayout.reserved(full.X, full.Y).Top + CLEAR_JUMP, (px.Y / scale - SafeZones.columnLimit(px.X / scale, px.Y / scale, scale)) * scale)
			local topPx = y * scale -- the menu's top in HUD-layer px
			local screenBottom = px.Y + bottomIn
			local function fits(c: number): boolean
				local rows = math.ceil(n / c)
				local hh = if c == 1 then h else rows * TILE + math.max(0, rows - 1) * 6
				return screenBottom - (topPx + hh * scale) >= limit
			end
			cols = if fits(1) then 1 elseif fits(2) or n <= 2 then 2 else 3
		end
		fold = cols > 1
		menuGrid.FillDirectionMaxCells = cols
		if menuList then
			menuList.Parent = if fold then nil else right
		end
		menuGrid.Parent = if fold then right else nil
		right.Size = UDim2.fromOffset(if fold then cols * TILE + (cols - 1) * 6 else RIGHT_W, 0)
	end
	refs.FitMenu = fitMenu
	for _, c in right:GetChildren() do
		if c:IsA("GuiObject") then
			c:GetPropertyChangedSignal("Visible"):Connect(function()
				task.defer(fitMenu)
			end)
		end
	end
	-- tiles added later (the owner's DEV tile) count too
	right.ChildAdded:Connect(function(c)
		if c:IsA("GuiObject") then
			c:GetPropertyChangedSignal("Visible"):Connect(function()
				task.defer(fitMenu)
			end)
			task.defer(fitMenu)
		end
	end)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fitMenu)
	-- rotation, resizes and safe-area changes move the insets
	for _, g in { UI.screen() :: GuiBase2d, insetProbe :: GuiBase2d } do
		g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			task.defer(fitMenu)
		end)
		g:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			task.defer(fitMenu)
		end)
	end
	task.defer(fitMenu)

	-- Top centre: objective, then the tutorial hint and the rubble-full notice.
	local top = UI.frame(root, { Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, T.Edge), Size = UDim2.new(1, -2 * (LEFT_W + 2 * T.Edge + 8), 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 })
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(360, 1000)
	lim.Parent = top
	UI.list(top, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	-- an opaque cream card with a navy edge and gold rim like the hunt cards (the see-through one let world signs and
	-- billboards show through the words); the title keeps its outlined bubble letters, the line under it is navy
	-- (pet style: the clip's NEXT UP bar: white-blue body, sky edge, a tilted yellow "NEXT UP!" tag on its top left
	-- corner in the lobby, the line under the title in quest blue)
	local obj = UI.frame(top, { Name = "Objective", Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1, BackgroundColor3 = CREAM, BackgroundTransparency = 0 })
	UI.corner(obj, T.Radius)
	UI.stroke(obj, CARD_EDGE, 3)
	if not Theme.PetStyle then
		local objRim = UI.frame(obj, { Name = "Rim", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1 })
		UI.corner(objRim, T.Radius - 2)
		UI.stroke(objRim, TC.Gold, 3)
	end
	local objTag: TextLabel? = nil
	if Theme.PetStyle then
		local tag = UI.text(obj, "NEXT UP!", { Name = "Tag", Font = UI.Head, TextSize = T.Small, TextColor3 = PET.Tag, Outline = "Normal", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(10, -2), Size = UDim2.fromOffset(84, 22), Rotation = -4, ZIndex = 3, TextXAlignment = Enum.TextXAlignment.Left })
		tag.TextWrapped = false
		local to = tag:FindFirstChild("Outline")
		if to and to:IsA("UIStroke") then
			to.Color = PET.TagEdge
			to.Thickness = 2.6
		end
		objTag = tag
	end
	refs.ObjTitle = UI.text(obj, "", { Name = "Title", Font = UI.Head, TextSize = T.Head + 4, RichText = true, Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	refs.ObjTitle.TextWrapped = false
	-- (the title's box ends a pixel above the sub line: on a phone the big letters' tails sat on the sub words)
	refs.ObjSub = UI.text(obj, "", { Name = "Sub", Font = UI.Bold, TextSize = T.Body, TextColor3 = if Theme.PetStyle then PET.QuestTitle else TC.PanelEdge, Outline = false, Position = UDim2.fromOffset(8, 32), Size = UDim2.new(1, -16, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Objective = obj
	-- In a hunt the line under the title is what to do next, so it gets the big letters and the title (FIND THE PET,
	-- GET READY...) becomes a smaller header; the lobby keeps the title-first card.
	local objHunt: boolean? = nil
	local objPill: boolean? = nil
	refs.ObjLayout = function(hunt: boolean, pill: boolean?)
		local isPill = pill == true and not hunt
		if objHunt == hunt and objPill == isPill then
			return
		end
		objHunt = hunt
		objPill = isPill
		-- Phones in the lobby: a small pill in the left column, right under the coin bar (the top centre of the view
		-- holds the world's arch sign). The title and the line under it stay, in small fitted letters.
		obj.Parent = if isPill then left else top
		obj.LayoutOrder = if isPill then 2 else 1
		refs.ObjPill = isPill
		if objTag then
			objTag.Visible = not hunt and not isPill
		end
		if isPill then
			refs.ObjFullH = 38
			obj.Size = UDim2.fromOffset(refs.ObjPillW or (LEFT_W + 24), 38)
			local title, sub = refs.ObjTitle, refs.ObjSub
			-- (the two lines keep a 4 px gap: with the title box running into the sub's, the big letters' tails
			-- sat on the sub words on a phone)
			title.Position = UDim2.fromOffset(6, 1)
			title.Size = UDim2.new(1, -12, 0, 16)
			UI.fit(title, T.Small + 2, T.MinText)
			sub.Font = UI.Bold
			sub.Position = UDim2.fromOffset(6, 21)
			sub.Size = UDim2.new(1, -12, 0, 16)
			sub.TextWrapped = false
			UI.fit(sub, T.Small, T.MinText)
			return
		end
		refs.ObjFullH = if hunt then 62 else 56 -- the hunt card is a little taller for its bigger title
		local title, sub = refs.ObjTitle, refs.ObjSub
		if hunt then
			title.Position = UDim2.fromOffset(8, 3)
			title.Size = UDim2.new(1, -16, 0, 26)
			UI.fit(title, T.Head, T.Body)
			sub.Font = UI.Head
			sub.Position = UDim2.fromOffset(8, 29)
			sub.Size = UDim2.new(1, -16, 0, 27)
			sub.TextWrapped = false
			UI.fit(sub, T.Head + 2, T.Small)
		else
			title.Position = UDim2.fromOffset(8, 2)
			title.Size = UDim2.new(1, -16, 0, 30)
			UI.fit(title, T.Head + 4, T.Head)
			sub.Font = UI.Bold
			sub.Position = UDim2.fromOffset(8, 31)
			sub.Size = UDim2.new(1, -16, 0, 22)
			sub.TextWrapped = true
			UI.fit(sub, T.Body, T.MinText)
		end
	end
	-- Lobby logo (mockup): the owner's FIND THE PET picture, or a bubble-text stand-in with the tagline pill.
	local logo = UI.frame(top, { Name = "Logo", Size = UDim2.new(1, 0, 0, 92), LayoutOrder = 0, BackgroundTransparency = 1, Visible = false })
	if HudArt.has("Logo") then
		local img = Instance.new("ImageLabel")
		img.Name = "LogoImage"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = HudArt.Slots.Logo.Image
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = logo
	else
		local lt = UI.text(logo, "FIND THE <font color=\"#FFC424\">PET</font>", { Name = "LogoText", Font = UI.Head, TextSize = 46, RichText = true, Outline = "Strong", Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center })
		lt.TextWrapped = false
		UI.fit(lt, 46, T.Head)
		local tag = UI.frame(logo, { Name = "Tagline", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.new(0.86, 0, 0, 28), BackgroundColor3 = TC.PanelEdge, BackgroundTransparency = 0.05 })
		UI.corner(tag, 14)
		UI.stroke(tag, TC.Hud, 2)
		local tt = UI.text(tag, "One egg hides a <font color=\"#FFC424\">rare pet!</font>", { Font = UI.Bold, TextSize = T.Body, RichText = true, Outline = "Normal", Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(6, 0), TextXAlignment = Enum.TextXAlignment.Center })
		tt.TextWrapped = false
		UI.fit(tt, T.Body, T.MinText)
	end
	refs.Logo = logo
	local hint = UI.card(top, "hud", { Name = "Hint", Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2, Visible = false })
	UI.icon(hint, "hint", 22, { Position = UDim2.fromOffset(8, 16) })
	refs.HintText = UI.text(hint, "", { Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Size = UDim2.new(1, -160, 1, -4), Position = UDim2.fromOffset(36, 2) })
	-- SKIP ends the whole tutorial (server: TutorialAction "Skip"); the free starter pet is kept / still given
	local hintSkip = UI.button(hint, "SKIP", "blue", function()
		UI.confirm({
			Name = "SkipTutorial",
			Title = "Skip the tutorial?",
			Message = "No more tips. You keep your free starter pet.",
			Icon = "hint",
			Confirm = "SKIP",
			OnConfirm = function()
				Net.event("TutorialAction"):FireServer("Skip")
			end,
		})
	end, { Name = "SkipTutorial", Size = UDim2.fromOffset(56, T.Touch), Position = UDim2.new(1, -120, 0, 5), TextSize = T.Small })
	local hsl = hintSkip:FindFirstChild("Label") :: TextLabel?
	if hsl then
		HudArt.word(hsl, 0.8) -- owner's SKIP word picture (reference/ui/settings/text_skip.png) once uploaded
	end
	UI.button(hint, "OK", "blue", function()
		Hud.hintDismissed = refs.HintText.Text
		Hud.refresh()
	end, { Size = UDim2.fromOffset(52, T.Touch), Position = UDim2.new(1, -58, 0, 5), TextSize = T.Small })
	refs.Hint = hint
	local lowHint = UI.frame(root, { Name = "HintLow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(T.Edge + 54)), Size = UDim2.new(1, -2 * (LEFT_W + 2 * T.Edge), 0, 54), BackgroundTransparency = 1 })
	local lowLim = Instance.new("UISizeConstraint")
	lowLim.MaxSize = Vector2.new(400, 60)
	lowLim.Parent = lowHint
	refs.HintLow = lowHint
	local full = UI.card(top, "hud", { Name = "BagNotice", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3, Visible = false })
	UI.icon(full, "rubble", 26, { Position = UDim2.fromOffset(8, 9) })
	UI.text(full, "Candy bag full", { Font = UI.Head, TextSize = T.Body, Size = UDim2.new(1, -48, 0, 22), Position = UDim2.fromOffset(42, 2) })
	UI.text(full, "Sell candy to keep hatching", { Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Normal", Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(42, 23) })
	refs.BagNotice = full
	refs.Top = top
	refs.HintTopHolder = top

	-- Portrait phones: the objective spans the top and the two columns start under it.
	-- Short screens: the left column must end above the bottom edge. A UIScale on the column shrinks every card by
	-- the ColumnFit size rule (cards never below FIT_MIN_CARD logical px tall); tall screens stay at scale 1.
	local fitScale = Instance.new("UIScale")
	fitScale.Name = "FitScale"
	fitScale.Parent = left
	local function fitLeft()
		local list = refs.LeftList :: UIListLayout?
		if not list then
			return
		end
		arrangeLobby()
		-- all heights in the units the layout reports (screen px); k = px per logical px
		local cur = math.max(fitScale.Scale, 0.1)
		local k = left.AbsoluteSize.X / (math.max(left.Size.X.Offset, 1) * cur)
		if k <= 0.01 then
			return
		end
		local n, sum = 0, 0
		for _, c in left:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				n += 1
				sum += c.AbsoluteSize.Y / cur
			end
		end
		if n == 0 then
			return
		end
		local gapPx = list.Padding.Offset * k
		local content = sum + gapPx * (n - 1)
		local avail = root.AbsoluteSize.Y - (leftBox.AbsolutePosition.Y - root.AbsolutePosition.Y) - T.Edge * k
		local mean = sum / n
		local f = ColumnFit.fit(avail, n, gapPx, FIT_MIN_CARD * k, mean)
		-- cols > 1: even the smallest card size does not fit one column, so the column scrolls instead
		local size = if f.cols > 1 then FIT_MIN_CARD * k else f.size
		local sc = if content <= avail then 1 else math.min(1, size / mean)
		if math.abs(fitScale.Scale - sc) > 0.005 then
			fitScale.Scale = sc
		end
		local shownH = (sum * sc + gapPx * (n - 1) * sc) -- height of the column after scaling, px
		leftBox.ScrollingEnabled = shownH > avail + 0.5
		leftBox.ScrollBarThickness = if leftBox.ScrollingEnabled then 4 else 0
		leftBox.Size = UDim2.fromOffset(boxW, math.max(1, math.floor(avail / k)))
		leftBox.CanvasSize = UDim2.fromOffset(0, math.ceil(shownH / k))
	end
	local function placeTop()
		local topH = if refs.Objective.Visible and top.Visible and refs.Objective.Parent == top then refs.Objective.Size.Y.Offset + 8 else 0
		if refs.Logo.Visible and top.Visible then
			topH += refs.Logo.Size.Y.Offset + 6
		end
		-- portrait: the columns start under everything in the top stack (objective, hint, rubble notice)
		local stackH = topH
		if top.Visible then
			if refs.Hint.Visible and refs.Hint.Parent == top then
				stackH += refs.Hint.Size.Y.Offset + 6
			end
			if refs.BagNotice.Visible then
				stackH += refs.BagNotice.Size.Y.Offset + 6
			end
		end
		-- the left cards keep a safe gap from the screen edge: the HUD layer already sits inside Roblox's safe insets
		-- (notch, top bar), and the gap is at least LEFT_GAP screen px whatever the UI scale (on a small phone T.Edge
		-- alone shrank to a few px and the card rims touched the edge)
		local leftX = math.max(T.Edge + 4, math.ceil(LEFT_GAP / math.max(UI.Scale, 0.1)))
		-- portrait: TOWER and BATTLE stack in the mode row (side by side they ran under the right menu tiles)
		if refs.ModeList then
			(refs.ModeList :: UIListLayout).FillDirection = if UI.isPortrait() then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		end
		if UI.isPortrait() then
			top.AnchorPoint = Vector2.new(0.5, 0)
			top.Position = UDim2.new(0.5, 0, 0, T.Edge)
			top.Size = UDim2.new(1, -2 * T.Edge, 0, 0)
			lim.MaxSize = Vector2.new(420, 1000)
			leftBox.Position = UDim2.fromOffset(leftX - BOX_PAD, T.Edge + stackH)
			right.Position = UDim2.new(1, -T.Edge, 0, T.Edge + stackH)
			refs.HintLow.Size = UDim2.new(1, -2 * T.Edge, 0, 54)
		else
			top.AnchorPoint = Vector2.new(0.5, 0)
			top.Position = UDim2.new(0.5, 0, 0, T.Edge)
			-- the lobby column holds the wider PLAY / TOWER / DAILY buttons (LOBBY_W): sized for the hunt's LEFT_W, the
			-- objective card overlapped PLAY (the gold tab seen under the banner was the world marker, see Main)
			local colW = if State.Match then LEFT_W else LOBBY_W
			top.Size = UDim2.new(1, -2 * (colW + leftX + T.Edge + 8), 0, 0)
			lim.MaxSize = Vector2.new(360, 1000)
			leftBox.Position = UDim2.fromOffset(leftX - BOX_PAD, T.Edge)
			right.Position = UDim2.new(1, -T.Edge, 0, T.Edge)
			refs.HintLow.Size = UDim2.new(1, -2 * (LEFT_W + 2 * T.Edge), 0, 54)
		end
		-- notifications sit under the top bar
		if UI.isPortrait() and State.Match ~= nil then
			-- full width under the counter and menu columns (the gap between them is too narrow for a card)
			local cols = 0
			for _, c in left:GetChildren() do
				if c:IsA("GuiObject") and c.Visible then
					if c == refs.Roster then
						cols += refs.RosterH or 0 -- auto-sized: the race bar's own height (chips + gaps)
					else
						cols += c.Size.Y.Offset + 6
					end
				end
			end
			UI.placeNotices(T.Edge + stackH + math.max(cols, 170) + 4)
		else
			UI.placeNotices(T.Edge + topH + (if refs.Hint.Visible or refs.BagNotice.Visible then 62 else 4))
		end
		fitLeft()
		fitMenu()
	end
	placeTop()
	refs.PlaceTop = placeTop
	-- the column grows and shrinks as cards show and hide: refit when its content height changes
	if refs.LeftList then
		refs.LeftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			task.defer(placeTop)
		end)
	end
	UI.screen():GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(placeTop)
	end)

	-- Bottom centre: tool slots (hunt only).
	local dock = UI.frame(root, { Name = "Dock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -T.Edge), Size = UDim2.fromOffset(DOCK_W, SLOT + 2), BackgroundTransparency = 1, Visible = false })
	UI.list(dock, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	refs.SlotHand = toolSlot(dock, "SlotHand", "1", "hand", "HAND", 1)
	refs.SlotTool = toolSlot(dock, "SlotTool", "2", "boostLuck", "COLLAR", 2)
	refs.SlotToolKind = ""
	refs.Dock = dock

	-- Primary action: gold, one short verb; neutral states are flat gray and say why nothing can be done.
	local act = Instance.new("TextButton")
	act.Name = "PrimaryAction"
	act.AnchorPoint = Vector2.new(1, 1)
	act.Position = UDim2.new(1, -T.Edge - 8, 1, -150)
	act.Size = UDim2.fromOffset(T.Primary.X, T.Primary.Y)
	act.BackgroundColor3 = TC.Gold
	act.AutoButtonColor = false
	act.Text = ""
	act.Visible = false
	act.Parent = root
	UI.corner(act, 12)
	refs.ActStroke = UI.stroke(act, TC.GoldDeep, 3)
	-- the key sits on a small dark badge in the corner, above the label (it was drawn under the words)
	local keyBadge = UI.frame(act, { Name = "KeyBadge", BackgroundColor3 = TC.Hud, AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(-4, -6), Size = UDim2.fromOffset(26, 22), ZIndex = 4, Visible = false })
	UI.corner(keyBadge, 7)
	UI.stroke(keyBadge, TC.PanelEdge, 2)
	refs.ActKey = UI.text(keyBadge, "E", { Name = "KeyHint", Font = UI.Head, TextSize = T.Tiny, TextColor3 = TC.Text, Outline = false, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	refs.ActKey:GetPropertyChangedSignal("Visible"):Connect(function()
		keyBadge.Visible = refs.ActKey.Visible
	end)
	refs.ActText = UI.text(act, "PICK UP", { Name = "Label", Font = UI.Head, TextSize = T.Head + 2, TextColor3 = TC.DarkText, Outline = false, Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12), TextXAlignment = Enum.TextXAlignment.Center, LineHeight = 0.9 })
	UI.squashScale(act)
	UI.bevel(act)
	-- One press at a time; the finger-lift watcher is dropped when the button hides or a menu opens.
	local pressConn: RBXScriptConnection? = nil
	local function releaseAct()
		if pressConn then
			pressConn:Disconnect()
			pressConn = nil
		end
		UI.squash(act, false)
		PileView.stopAll()
	end
	act.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if pressConn then
			return -- a second finger must not start a second loop
		end
		PileView.holdBegin()
		UI.squash(act, true)
		pressConn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
				if pressConn then
					pressConn:Disconnect()
					pressConn = nil
				end
				PileView.holdEnd()
				UI.squash(act, false)
			end
		end)
	end)
	act:GetPropertyChangedSignal("Visible"):Connect(function()
		if not act.Visible then
			releaseAct()
		end
	end)
	refs.Act = act
	-- Sell card (board "Rubble sale"): rides above the action while it says SELL RUBBLE. Numbers are the server's view
	-- of the bag (profile Rubble / Capacity / RubbleValue); the receipt after the sale is the server's notification.
	local sellCard = UI.card(act, "panel", { Name = "SellPreview", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -8), Size = UDim2.fromOffset(T.Primary.X + 40, 58), Visible = false })
	UI.icon(sellCard, "basket", 34, { Position = UDim2.fromOffset(6, 12) })
	refs.SellQty = UI.text(sellCard, "", { Font = UI.Bold, TextSize = T.Body, Outline = "Normal", RichText = true, Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -52, 0, 24) })
	refs.SellCash = UI.text(sellCard, "", { Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Cash, Position = UDim2.fromOffset(46, 28), Size = UDim2.new(1, -52, 0, 24) })
	refs.SellCard = sellCard

	-- Where the action sits (TouchLayout: clear of Roblox's jump button, screen pixels).
	local function placeAction()
		local gui = UI.screen()
		local px = gui.AbsoluteSize
		local cam = Workspace.CurrentCamera
		local fullSize = if cam then cam.ViewportSize else px
		local scale = if UI.Logical.X > 0 then px.X / UI.Logical.X else 1
		-- CRACK (refs.ActBig) is the big thumb button; everything else keeps the normal size
		local big = refs.ActBig == true
		local w = if big then T.Primary.X + 26 else T.Primary.X
		local h = if big then T.Primary.Y + 30 else T.Primary.Y
		local topLimit = px.Y - (T.Edge + 190) * scale -- keep the right column (timer, menu) free
		local menu = refs.Menu :: Frame
		if State.Match ~= nil and menu.Visible and menu.AbsoluteSize.Y > 1 then
			-- hunt: the menu is one short row, so the action may rise to just under it (above the jump button, at the
			-- screen edge) instead of moving in toward the middle of the view, where it covered the nest's name board
			topLimit = px.Y - (menu.AbsolutePosition.Y - gui.AbsolutePosition.Y + menu.AbsoluteSize.Y + 12 * scale)
		end
		local r, bottom, mode = TouchLayout.place(fullSize.X, fullSize.Y, h * scale, topLimit, UserInputService.TouchEnabled)
		if mode == "left" then
			-- on the bottom row the button must stay right of the tool dock (bottom centre, DOCK_W wide)
			local room = (px.X / 2 - (DOCK_W / 2 + 10) * scale - r) / scale
			w = math.max(math.min(w, room), math.min(T.Primary.X, room), 96)
		end
		act.Size = UDim2.fromOffset(w, h)
		act.Position = UDim2.new(1, -r / scale, 1, -bottom / scale)
		refs.ActMode = mode
		refs.ActRightPx = r
	end
	refs.PlaceAction = placeAction
	placeAction()
	UI.screen():GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAction)
	for _, prop in { "AbsoluteSize", "Visible" } do
		refs.Menu:GetPropertyChangedSignal(prop):Connect(function()
			task.defer(placeAction)
		end)
	end
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(placeAction)

	-- The rectangle (HUD pixels) the route-hint chip may use: between the two columns, below the top bar, above the dock.
	GuideArrow.setBounds(function()
		local gui = UI.screen()
		local origin, size = gui.AbsolutePosition, gui.AbsoluteSize
		local scale = if UI.Logical.X > 0 then size.X / UI.Logical.X else 1
		local l = refs.Stats.AbsolutePosition.X - origin.X + refs.Stats.AbsoluteSize.X + 12 * scale
		local r = refs.Menu.AbsolutePosition.X - origin.X - 12 * scale
		if refs.Act.Visible then
			r = math.min(r, refs.Act.AbsolutePosition.X - origin.X - 12 * scale)
		end
		local t = 40 * scale
		if refs.Top.Visible then
			t = refs.Top.AbsolutePosition.Y - origin.Y + refs.Top.AbsoluteSize.Y + 12 * scale
		end
		local bt = size.Y - 20 * scale
		if refs.Dock.Visible then
			bt = refs.Dock.AbsolutePosition.Y - origin.Y - 8 * scale
		end
		if r - l < 100 then
			t = math.max(t, refs.Stats.AbsolutePosition.Y - origin.Y + refs.Stats.AbsoluteSize.Y + 8 * scale)
			l = 12 * scale
		end
		if r - l < 100 or bt - t < 60 then
			return 60, 60, size.X - 60, size.Y - 60
		end
		return l, t, r, bt
	end)

	Hud.refresh()
	State.Changed.Event:Connect(function()
		Hud.refresh()
	end)
	player:GetAttributeChangedSignal("MatchKey"):Connect(Hud.refresh)
	player:GetAttributeChangedSignal("InTower"):Connect(Hud.refresh)
	player:GetAttributeChangedSignal("InBattle"):Connect(Hud.refresh)
	UI.BlockChanged.Event:Connect(function(blocked)
		if blocked then
			PileView.stopAll()
			PileView.clearSelection()
		end
		Hud.refresh()
	end)
	task.spawn(function()
		local warned = false
		while true do
			task.wait(0.2)
			-- one failing tick must not end the loop (audit 16): log the first error, keep ticking
			local ok, err = pcall(Hud.tick)
			if not ok and not warned then
				warned = true
				warn("[Hud] tick failed (further errors silenced): " .. tostring(err))
			end
		end
	end)
end

-- Eggs not cracked yet this hunt (server counters: Total - Broken), for the line under the clock.
local function uncracked(m: any): number
	local c = m.Counts
	if c and type(c.Unopened) == "number" then
		return c.Unopened
	end
	return if c and type(c.Pile) == "number" then c.Pile else (m.Remaining or m.Rocks or 0)
end

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Contextual primary action (V3 loop). The id comes from PileView.context(), the same rules the server applies,
-- so the button never promises what it cannot do. Neutral = a status (flat gray), never a second primary.
local ACTION = {
	pickup = { Text = "PICK UP" },
	take = { Text = "BASKET FULL", Neutral = true },
	deposit = { Text = "DEPOSIT\nEGGS" },
	crush = { Text = "HATCH!", Big = true }, -- the big thumb button; tapping the nest egg also cracks
	machine = { Text = "MACHINE\nRUNNING", Neutral = true },
	collect = { Text = "COLLECT\nEGGS", Go = true }, -- the next step (empty basket at the nest): bright green, never gray
	sell = { Text = "SELL\nCANDY" },
	bagfull = { Text = "STORAGE\nFULL", Neutral = true },
	closer = { Text = "MOVE\nCLOSER", Neutral = true, Hint = true }, -- blue with a white edge: "walk closer", not broken
	wait = { Text = "GET\nREADY", Neutral = true },
	securing = { Text = "SECURING\u{2026}", Neutral = true },
}
local lastCtxId: string? = nil -- the contextual action shown last tick (stale "Move closer" cards are dropped on change)

-- Key hint for keyboard and gamepad players (touch shows none).
local function keyHint(): string?
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return nil
	elseif string.sub(last.Name, 1, 7) == "Gamepad" then
		return "RT"
	elseif last == Enum.UserInputType.Keyboard or last == Enum.UserInputType.MouseButton1 or last == Enum.UserInputType.MouseMovement then
		return "E"
	end
	return nil
end

-- Sell hoppers of the current arena (found once per match key; the arena does not move during a match).
local hopperKey: any = nil
local hoppers: { BasePart } = {}
local function nearestHopper(m: any): BasePart?
	if hopperKey ~= m.Key then
		hopperKey = m.Key
		table.clear(hoppers)
		for _, d in Workspace:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Hopper") then
				local body = d:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					table.insert(hoppers, body)
				end
			end
		end
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local best, bestD = nil, 400
	for _, b in hoppers do
		if b.Parent then
			local d = (b.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

-- Contexts that mean "standing at the own table".
local AT_TABLE = { deposit = true, crush = true, machine = true, collect = true, bagfull = true }

-- the equipped pet gear's own picture (its Gear_<Id> model, or ItemView's gear icon), never the old hammer
local function setToolSlotIcon(gearId: string)
	if refs.SlotToolKind == gearId then
		return
	end
	refs.SlotToolKind = gearId
	if refs.SlotToolIcon then
		refs.SlotToolIcon:Destroy()
	end
	refs.SlotToolIcon = ItemView.make(refs.SlotTool, gearId, { Name = "SlotToolIcon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(SLOT_ICON, SLOT_ICON) }, SLOT_ICON)
end

function Hud.tick()
	local m = State.Match
	if m == nil and refs.CueShown and not Hud.cueActive() then
		refs.CueShown = false
		Hud.refresh()
		return
	end
	if not m or not refs.Act then
		if m == nil and refs.Act and GuideArrow.label() ~= "" and GuideArrow.label() ~= "EGG" then
			GuideArrow.clear() -- the post-hunt SELL chip never follows the player into the lobby (the starter EGG arrow stays)
		end
		Hud.updateHint()
		return
	end
	Hud.updateHint()
	local now = Workspace:GetServerTimeNow()
	if m.Phase == "Countdown" then
		local leftS = math.max(1, math.ceil(m.EndsAt - now))
		refs.ObjSub.Text = "Starting in " .. leftS
		Audio.countdown(leftS)
		-- the timer card is up from the countdown: the full round time waits to run down from GO
		local ot0 = EggConfig.Overtime
		refs.TimerText.Text = if ot0.Enabled and not m.Tutorial then fmtTime(ot0.RoundSeconds) else "0:00"
	elseif m.Phase == "Searching" then
		local elapsed = now - (m.SearchStart or now)
		-- 3-minute rounds (EggConfig.Overtime): the clock runs DOWN to the moment the pet egg glows gold for everyone,
		-- then stays at 0:00 while the race finishes; the practice round (no glow) counts up as before
		local ot1 = EggConfig.Overtime
		local tt = if ot1.Enabled and not m.Tutorial then fmtTime(math.max(0, math.ceil(ot1.RoundSeconds - elapsed))) else fmtTime(elapsed)
		if tt ~= refs.TimerText.Text and refs.Clock and not UI.Reduced then
			-- the clock gives a small tick each second (left, right, left...)
			clockTick = -clockTick
			refs.Clock.Rotation = 8 * clockTick
			TweenService:Create(refs.Clock, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		end
		refs.TimerText.Text = tt
		-- last 10 seconds before the overtime glow (EggConfig.Overtime): the clock turns red and pulses each second
		local ot = EggConfig.Overtime
		local toGlow = ot.RoundSeconds - elapsed
		if ot.Enabled and not m.Tutorial and toGlow > 0 and toGlow <= 10 then
			refs.TimerText.TextColor3 = Theme.Fx.Danger
			refs.PileText.TextColor3 = Theme.Fx.Danger
			pileWarned = true
			if not shookTimer then
				shookTimer = true
				if not UI.Reduced then
					task.spawn(function()
						for _, r in { 6, -5, 4, -2, 0 } do
							if not refs.Timer.Parent then
								return
							end
							refs.Timer.Rotation = r
							task.wait(0.045)
						end
					end)
				end
			end
			local sec = math.floor(elapsed)
			if sec ~= pulseSecond then
				pulseSecond = sec
				UI.pop(refs.Timer, 1.15)
			end
		elseif refs.TimerText.TextColor3 == Theme.Fx.Danger then
			refs.TimerText.TextColor3 = TC.Gold
		end
		if toGlow > 10 then
			shookTimer = false
		end
		-- eggs-left line: orange for the last 30 s before the overtime glow, red for the last 10 s (above)
		if ot.Enabled and not m.Tutorial and toGlow > 10 and toGlow <= 30 then
			refs.PileText.TextColor3 = TC.Warn
			pileWarned = true
		elseif pileWarned and not (ot.Enabled and not m.Tutorial and toGlow > 0 and toGlow <= 10) then
			refs.PileText.TextColor3 = TC.Muted
			pileWarned = false
		end
	elseif m.SearchStart and m.SearchEnd then
		refs.TimerText.Text = fmtTime(m.SearchEnd - m.SearchStart) -- stopped at the authoritative end
	end
	local blocked = UI.blocked()
	local phase = m.Phase
	local actionPhase = phase == "Countdown" or phase == "Searching" or phase == "RewardPending"
	local ctx = PileView.context()
	-- a "Move closer" card is stale the moment a real action is offered (PICK UP, DEPOSIT, CRACK...): drop it
	if ctx.Id ~= "closer" and ctx.Id ~= lastCtxId and ACTION[ctx.Id] and ACTION[ctx.Id].Neutral ~= true then
		UI.dismissNotices("arena:move closer")
	end
	lastCtxId = ctx.Id
	local show = actionPhase and not blocked and ActionRules.visible(ctx.Id)
	if refs.Act.Visible ~= show then
		refs.Act.Visible = show
	end
	-- PICK UP bounces once when it becomes available
	local pickupNow = show and ctx.Id == "pickup"
	if pickupNow and not lastActPickup then
		UI.pop(refs.Act, 0.82)
	end
	lastActPickup = pickupNow
	if show then
		local a = ACTION[ctx.Id] or ACTION.closer
		local neutral = a.Neutral == true
		local hintLook = a.Hint == true
		local go = a.Go == true -- active "go there" step: green with white outlined letters
		refs.Act.BackgroundColor3 = if hintLook then TC.Gray elseif neutral then TC.Disabled elseif go then TC.Green else TC.Gold
		refs.ActStroke.Color = if hintLook then TC.Text elseif neutral then TC.PanelEdge elseif go then TC.GreenDeep else TC.GoldDeep
		refs.ActText.TextColor3 = if neutral or go then TC.Text else TC.DarkText
		local o = refs.ActText:FindFirstChild("Outline")
		if (neutral or go) and not o then
			UI.outline(refs.ActText, "Normal")
		elseif not (neutral or go) and o then
			o:Destroy()
		end
		refs.ActText.Text = a.Text
		-- CRACK is the big thumb button (an egg is on the own nest plate); every other action keeps the normal size
		local big = a.Big == true
		if refs.ActBig ~= big then
			refs.ActBig = big
			UI.fit(refs.ActText, if big then T.Head + 10 else T.Head + 2)
			refs.PlaceAction()
		end
		local key = keyHint()
		refs.ActKey.Visible = key ~= nil and not neutral
		if key then
			refs.ActKey.Text = key
		end
		refs.Act:SetAttribute("Disabled", neutral)
	end
	refs.CtxId = ctx.Id
	if phase == "Searching" then
		refs.ObjSub.Text = Hud.searchLine(m, ctx.Id)
	end
	local prof = State.Profile
	local sellOn = show and ctx.Id == "sell" and prof ~= nil
	if refs.SellCard.Visible ~= sellOn then
		refs.SellCard.Visible = sellOn
	end
	if sellOn and prof then
		if prof.Rubble > 0 then
			refs.SellQty.Text = "Candy: <font color=\"#FFB020\">" .. prof.Rubble .. "</font>/" .. prof.Capacity
			refs.SellCash.Text = "+" .. UI.money(prof.RubbleValue or 0)
		else
			refs.SellQty.Text = "No candy to sell."
			refs.SellCash.Text = ""
		end
	end
	-- after the hunt, while the tutorial's next step is selling: the route hint points at the nearest bin
	local hop = if phase == "Results" and not blocked and prof and not prof.OnboardDone and prof.Onboard and not prof.Onboard.Sold and prof.Rubble > 0 then nearestHopper(m) else nil
	if hop then
		GuideArrow.set(hop.Position, "SELL", hop.Position.Y)
	else
		PileView.updateGuide(ctx, phase == "Searching" and not blocked, prof ~= nil and not prof.OnboardDone)
	end

	-- Own station: queue, processing, machine, tool slots.
	local st = ownStation(m)
	local searching = st ~= nil and phase == "Searching" and not blocked
	local atTable = searching and AT_TABLE[ctx.Id] == true
	local cap = if st and st.QueueCap then st.QueueCap else Config.Station.QueueCapacity
	local queued = if st then #st.Queue else 0
	-- the QUEUE card keeps its slot for the whole hunt (from the countdown on): popping in and out at the nest made
	-- the left column jump
	refs.QueueCard.Visible = st ~= nil and actionPhase
	if st then
		refs.SetQueue(queued, cap)
		local qFull = queued >= cap and cap > 0
		markFull(refs.QueueCard, qFull)
		if qFull and not queueWasFull then
			shakeIcon(refs.QueueCard) -- same wiggle as the basket the moment the nest tray fills
		end
		queueWasFull = qFull
	end
	-- processing indicator from the server's plate state only
	local procOn, procText, procV = false, "", 0
	if searching and st then
		local running = st.Machine ~= nil and st.State == "Running"
		local key = st.Current
		local p = st.Progress or 0
		local newRock = key ~= lastProgressKey
		if newRock then
			lastProgressKey = key
			lastProgress = p
			lastProgressAt = if p > 0 then os.clock() else -math.huge
		elseif lastProgress ~= p then
			procGap = math.clamp(os.clock() - lastProgressAt, 0.15, 0.8) -- time between the last two server values
			lastProgress = p
			lastProgressAt = os.clock()
		end
		-- a rock on the own plate that has started cracking keeps the card up while the player is at the nest (it no
		-- longer drops out between two hits)
		local live = key ~= nil and (p > 0 or os.clock() - lastProgressAt < PROGRESS_LIVE)
		if running and (key ~= nil or queued > 0) then
			procOn, procText, procV = true, "AUTO NEST HATCHING", if key then p else 0
		elseif live and atTable then
			procOn, procText, procV = true, "HATCHING", p
		end
		if newRock then
			procGoal = -1 -- a new rock starts its bar from its own value, not eased down from the last one
		end
	else
		lastProgressKey = nil
	end
	local nowC = os.clock()
	if procOn then
		procUntil = nowC + PROC_HOLD
	elseif refs.Proc.Visible and searching and nowC < procUntil and lastProgressKey ~= nil then
		procOn, procText, procV = true, procBase, procGoal -- short hold: a context flicker does not blink the card
	end
	if refs.Proc.Visible ~= procOn then
		refs.Proc.Visible = procOn
	end
	if procOn then
		procBase = procText
		local goal = math.clamp(procV, 0, 1)
		if goal ~= procGoal then
			local first = procGoal < 0 or goal < procGoal
			procGoal = goal
			if procTween then
				procTween:Cancel()
				procTween = nil
			end
			if first or UI.Reduced then
				procShown.Value = goal
			else
				local tw = TweenService:Create(procShown, TweenInfo.new(procGap, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Value = goal })
				procTween = tw
				tw:Play()
			end
		end
		-- the label follows the eased value (the Changed handler); a new label word shows at once
		refs.ProcText.Text = if procBase == "HATCHING" then procBase .. " " .. math.floor(procShown.Value * 100 + 0.5) .. "%" else procBase
	else
		procGoal = -1
	end
	-- tool slots: the hand while collecting / depositing, the tool while cracking
	local dockOn = searching
	if refs.Dock.Visible ~= dockOn then
		refs.Dock.Visible = dockOn
	end
	if dockOn then
		local toolInUse = ctx.Id == "crush"
		setSlot(refs.SlotHand, not toolInUse)
		setSlot(refs.SlotTool, toolInUse)
	end
end

-- The objective line while searching. It follows the contextual action (re-read every tick, not only on server
-- updates), so it never says "Grab eggs" while the DEPOSIT button is up at the nest.
function Hud.searchLine(m: any, ctxId: string): string
	local mine = ownStation(m)
	local n = if mine then #mine.Basket else 0
	local cap = if mine and mine.CarryCap then mine.CarryCap else Config.Carry.Capacity
	if m and m.Tutorial then
		-- the first (practice) hunt: one tip at a time, three words at most (the route arrow shows where)
		if ctxId == "deposit" then
			return "Drop eggs in!"
		elseif ctxId == "crush" or ctxId == "machine" or ctxId == "bagfull" then
			return "Tap to hatch!"
		elseif n > 0 and (n >= cap or ctxId ~= "pickup") then
			return "Go to nest!"
		end
		return "Grab eggs!"
	end
	if ctxId == "deposit" then
		return "Put your eggs in your nest!"
	elseif ctxId == "crush" or ctxId == "machine" or ctxId == "bagfull" then
		return "Hatch eggs at your nest!"
	elseif n >= cap then
		return "Take your eggs to your nest!"
	elseif n > 0 and ctxId ~= "pickup" then
		return "Grab more eggs or take them to your nest!"
	end
	return "Grab eggs from the pile!"
end

-- The one next step after a hunt (HUD objective while the results card is closed). Tutorial players get the
-- tutorial's next stage; everyone else is told how to hunt again.
function Hud.nextStep(): string
	local prof = State.Profile
	if prof and not prof.OnboardDone and prof.Onboard then
		local ob = prof.Onboard
		if not ob.Sold and prof.Rubble > 0 then
			return "Next: sell candy at the candy stand"
		elseif ob.Geode and not ob.Displayed and #prof.Inventory > 0 then
			return "Next: tap LOBBY, then show your pet"
		end
	end
	return "Tap RESULTS to hunt again"
end

function Hud.refresh()
	if not refs.Act then
		return
	end
	local prof = State.Profile
	local m = State.Match
	local blocked = UI.blocked()
	local full = false
	local inMatch = m ~= nil
	-- lobby-only pieces go the moment the server puts us in a hunt (MatchKey), not when the hunt state lands later
	local lobbyUi = not inMatch and player:GetAttribute("MatchKey") == nil
	local phase = if m then m.Phase else nil
	if prof then
		setCash(prof.Cash)
		full = prof.Rubble >= prof.Capacity
		local folded = refs.BagLine:GetAttribute("Folded") == true -- the short pill of the phone row (foldBag)
		refs.Rubble.Text = (if folded then (if full then "FULL " else "Candy ") elseif full then "Candy bag FULL " else "Candy bag ") .. prof.Rubble .. "/" .. prof.Capacity
		local near = not full and prof.Capacity > 0 and prof.Rubble >= prof.Capacity * 0.8
		refs.Rubble.TextColor3 = if full then TC.Red elseif near then Color3.fromRGB(230, 120, 20) else PanelSkin.NAVY
		local bagEdge = refs.BagLine:FindFirstChildOfClass("UIStroke")
		if bagEdge then
			bagEdge.Color = if full then TC.Red elseif near then Color3.fromRGB(230, 120, 20) else PanelSkin.NAVY
		end
		refs.RubbleSub.Text = if full then "Sell, then hunt!" else "Sell for coins!"
		refs.BagLine.Visible = lobbyUi and prof.Rubble > 0
		setRubbleRolling(prof.Rubble, prof.Capacity)
		refs.SavesOff.Visible = prof.SavesOff == true and RunService:IsStudio() and not blocked
		local h = Config.Handhelds[prof.EquippedHandheld]
		local slotCap = refs.SlotTool:FindFirstChild("Caption") :: TextLabel?
		if slotCap then
			slotCap.Text = TOOL_SHORT[prof.EquippedHandheld] or (if h then string.upper(h.Name) else "COLLAR")
		end
		setToolSlotIcon(prof.EquippedHandheld or "Hammer")
	end
	local mine = ownStation(m)
	do
		local n = if mine then #mine.Basket else 0
		local carryCap = if mine and mine.CarryCap then mine.CarryCap else Config.Carry.Capacity -- basket upgrades
		refs.SetCarry(n, carryCap)
		local nowFull = n >= carryCap and carryCap > 0
		markFull(refs.CarryCard, nowFull)
		if nowFull and not basketWasFull then
			shakeIcon(refs.CarryCard) -- the meter wiggles the moment the basket fills
		end
		basketWasFull = nowFull
		refs.CarryCard.Visible = inMatch and mine ~= nil
		refs.RubbleCard.Visible = inMatch and mine ~= nil
		if refs.LeftList then
			refs.LeftList.Padding = UDim.new(0, if inMatch then 9 else 6) -- hunt cards get a clear gap between them
		end
		if n < carryCap then
			Hud.dismissToasts("basket")
		end
	end
	-- machine chip (hunt, own machine installed)
	if prof then
		local id = prof.InstalledMachine
		local entry = myMachine(m)
		local want = if id then (MACHINE_ICON[id] or "machine") else "machine"
		if want ~= refs.MachIconKind then
			refs.MachIconKind = want
			if refs.MachIcon then
				refs.MachIcon:Destroy()
			end
			refs.MachIcon = UI.icon(refs.Mach, want, 26, { Position = UDim2.fromOffset(7, 9) })
		end
		local label = "Off in practice"
		if id and entry then
			label = if entry.State == "Running" then "Running \u{b7} tap to pause" elseif entry.State == "Paused" then "Paused \u{b7} tap to run" elseif entry.State == "Full" then "Storage full" else "Installed"
		end
		refs.MachLabel.Text = label
		refs.Mach.Visible = inMatch and id ~= nil and mine ~= nil and phase == "Searching" and not blocked
		UI.setEnabled(refs.Mach, entry ~= nil)
	end
	if not inMatch then
		Hud.dismissToasts("all") -- arena directions do not follow the player into the lobby
	elseif not full then
		Hud.dismissToasts("bag")
	end
	-- lobby menu vs hunt menu
	refs.Resources.Visible = lobbyUi
	refs.BtnShop.Visible = lobbyUi
	refs.BtnParty.Visible = lobbyUi
	refs.BtnCollection.Visible = lobbyUi
	refs.BtnQuests.Visible = lobbyUi
	do
		-- (bug #249) counted again from the quest rows and the gift on every refresh (each profile change and the
		-- MatchKey change on the way back to the lobby), so a claim clears the dot as soon as its profile lands
		UI.newDot(refs.QuestsDot, dailyReady(prof) > 0, dailyReady(prof))
		-- red "!" on the Pet Book tile for pets hatched since it was last opened (this session only, client side)
		-- (counted from the first loaded profile: counting from "no profile yet" = 0 lit the "!" for every pet you own
		-- and it never cleared unless the profile changed while the book was open)
		local have = if prof and prof.Inventory then #prof.Inventory else nil
		if have then
			if seenPets == nil or UI.modalOpen() == "Collection" or have < (seenPets :: number) then
				seenPets = have
			end
			lastPets = have
		end
		UI.newDot(refs.PetsDot, have ~= nil and seenPets ~= nil and have > (seenPets :: number))
	end
	refs.BtnLobby.Visible = inMatch
	refs.BtnResults.Visible = inMatch and phase == "Results" and State.Results ~= nil and UI.modalOpen() ~= "Results"
	refs.Timer.Visible = inMatch and (phase == "Searching" or phase == "Countdown" or ((phase == "RewardPending" or phase == "Reveal" or phase == "Results") and m.SearchEnd ~= nil))
	-- after the find the clock is stopped: say so, so the card never reads as a live hunt
	local final = inMatch and phase ~= "Searching" and phase ~= "Countdown"
	-- the count under the clock is every egg not cracked yet (pile + baskets + nests: the pet can be in any of them),
	-- so it goes down with each crack; the pile alone did not move while eggs were cracked at the nests
	local pileText = if final then "FINAL TIME" elseif m then (uncracked(m) .. " to hatch") else ""
	if pileText ~= refs.PileText.Text then
		local flip = not final and refs.PileText.Text ~= "" and refs.PileText.Text ~= "FINAL TIME" and refs.Timer.Visible
		refs.PileText.Text = pileText
		if flip then
			Juice.flip(refs.PileText) -- the eggs-left number turns over like a counter
		end
	end
	refs.TimerText.TextColor3 = if final then TC.Muted else TC.Gold
	-- "10 EGGS LEFT!" banner: once per hunt, when the uncracked count first drops to FEW_EGGS or fewer
	if m and phase == "Searching" and m.SearchStart then
		local pile = uncracked(m)
		-- only when the count really drops past the line (a small pile that starts under it shows no banner)
		if type(pile) == "number" then
			if pile > FEW_EGGS then
				fewArmedFor = m.SearchStart
			elseif pile > 0 and fewArmedFor == m.SearchStart and fewShownFor ~= m.SearchStart then
				fewShownFor = m.SearchStart
				Juice.banner(pile .. (if pile == 1 then " EGG LEFT!" else " EGGS LEFT!"), TC.Gold)
			end
		end
	end
	-- race bar (party hunts): eggs each hunter has cracked this round, from the server's station views only
	for _, c in refs.Roster:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local members = if m then (m.Members or {}) else {}
	refs.Roster.Visible = inMatch and #members > 1
	refs.RosterH = if inMatch and #members > 1 then #members * (RACE_H + 3) + 6 else 0
	if inMatch and #members > 1 then
		local rows = RaceRules.standings(m.Stations, members)
		for i, row in rows do
			local me = row.UserId == player.UserId
			local chip = UI.frame(refs.Roster, { Name = "Racer" .. i, Size = UDim2.fromOffset(LEFT_W, RACE_H), BackgroundColor3 = TC.Hud, BackgroundTransparency = 0.2, LayoutOrder = i })
			UI.corner(chip, 6)
			if me then
				UI.stroke(chip, TC.Gold, 2)
			end
			if row.Leader then
				UI.icon(chip, "crown", 15, { Position = UDim2.fromOffset(4, 1) })
			end
			local nm = UI.text(chip, (if me then "You" else row.Name) .. (if row.Present then "" else " (left)"), {
				Font = UI.Bold, TextSize = T.Tiny, Outline = "Normal", Size = UDim2.new(1, -60, 0, 17), Position = UDim2.fromOffset(22, 0),
				TextColor3 = if row.Present then TC.Text else TC.Faint,
			})
			nm.TextWrapped = false
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			local cnt = UI.text(chip, tostring(row.Cracked), {
				Name = "Count", Font = UI.Head, TextSize = T.Tiny, TextColor3 = TC.Gold, Outline = "Normal",
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 0), Size = UDim2.fromOffset(34, 17), TextXAlignment = Enum.TextXAlignment.Right,
			})
			cnt.TextWrapped = false
			local _, fill = UI.bar(chip, { Position = UDim2.new(0, 6, 1, -6), Size = UDim2.new(1, -12, 0, 4) }, if me then TC.Gold else TC.Muted)
			fill.Size = UDim2.fromScale(row.Share, 1)
		end
	end
	if not inMatch then
		refs.Act.Visible = false
		refs.Proc.Visible = false
		refs.QueueCard.Visible = false
		refs.Dock.Visible = false
		refs.Mach.Visible = false
	end
	UI.MaxNotices = if inMatch and phase == "Searching" then 2 else 3 -- keep the nest and the egg in view
	refs.Top.Visible = not blocked
	-- in the pet tower only the tower HUD shows: the lobby columns (coins, bag, PLAY, DAILY, tiles) step aside
	local inTower = (player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true)
	local v2 = lobbyHidden and lobbyUi
	refs.Stats.Visible = not blocked and not inTower and not v2
	refs.Menu.Visible = not blocked and not inTower and not v2
	refs.BagNotice.Visible = inMatch and phase == "Searching" and full and not blocked
	if not inMatch or phase ~= "Searching" or blocked then
		PileView.stopAll()
	end

	local showObjective = true
	if not inMatch then
		local party = State.Party
		if not lobbyUi then
			showObjective = false -- on the way into a hunt: nothing from the lobby
		elseif prof and prof.StarterEgg == true and not party and Hud.cueActive() then
			refs.ObjTitle.Text = "FREE PET!"
			refs.ObjSub.Text = "Tap the glowing egg!" -- the starter egg comes first (StarterEggView)
		elseif prof and prof.TutorialStep == 0 and not party and Hud.cueActive() then
			refs.ObjTitle.Text = "START YOUR FIRST HUNT"
			refs.ObjSub.Text = "Tap PLAY. One egg hides a rare pet!"
			refs.CueShown = true
		elseif party and #party.Members > 1 then
			refs.ObjTitle.Text = "PARTY " .. #party.Members .. "/" .. party.Max
			refs.ObjSub.Text = party.Reason or "Everyone is ready"
		else
			showObjective = false -- the logo says what the game is (lobby mockup)
		end
	else
		if phase == "Countdown" then
			refs.ObjTitle.Text = "GET READY"
		elseif phase == "Searching" then
			refs.ObjTitle.Text = "FIND THE <font color=\"#FFC424\">PET</font>"
			refs.ObjSub.Text = Hud.searchLine(m, PileView.context().Id)
		elseif phase == "RewardPending" then
			refs.ObjTitle.Text = string.upper(m.WinnerName or "Someone") .. " FOUND IT!"
			local mine3 = m.WinnerName == player.DisplayName or m.WinnerName == player.Name
			refs.ObjSub.Text = if mine3 then "Hatching the pet\u{2026}" else "Next time! Hatching their pet\u{2026}"
			if lastObjPhase ~= "RewardPending" and not UI.Reduced then
				-- the winner line slides in from the side instead of popping
				refs.ObjTitle.Position = UDim2.fromOffset(120, 2)
				refs.ObjTitle.TextTransparency = 1
				TweenService:Create(refs.ObjTitle, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(8, 4), TextTransparency = 0 }):Play()
			end
		elseif phase == "Reveal" then
			refs.ObjTitle.Text = string.upper(m.WinnerName or "Someone") .. " FOUND IT!"
			refs.ObjSub.Text = "Pet hatched!"
		elseif phase == "Results" then
			refs.ObjTitle.Text = "HUNT OVER"
			refs.ObjSub.Text = Hud.nextStep()
		end
	end
	lastObjPhase = if inMatch then phase else nil
	refs.ObjInMatch = inMatch
	refs.ObjLayout(inMatch, SafeZones.compactLobby(UI.Logical.X, UI.Logical.Y, UserInputService.TouchEnabled))
	refs.ShowObjective = showObjective
	refs.Objective.Visible = showObjective
	refs.Logo.Visible = false -- owner: no FIND THE PET title in the lobby for now
	refs.PlaceTop()
	Hud.updateHint()
	Hud.tick()
end

-- Hint lifetime (done / timeout, bugs #216, #221) is one rule, shared/HintRules, applied by Main's Hud.hintText before
-- the text gets here; the HUD only decides where the card sits and whether the screen is free for it.

-- One tutorial hint at a time, re-evaluated every tick (it follows what the avatar is doing).
function Hud.updateHint()
	if not refs.Hint then
		return
	end
	local fn = Hud.hintText
	local hint = if fn then fn() else nil
	if hint and State.Match and string.find(hint, "^Basket full") and refs.CarryCard and refs.CarryCard.Visible then
		-- the red CARRIED count and the BASKET FULL button already say it (and the arrow shows the way): no third copy
		hint = nil
	end
	local want = if State.Match then refs.HintTopHolder else refs.HintLow
	if refs.Hint.Parent ~= want and want then
		refs.Hint.Parent = want
	end
	-- in the pet tower the tower HUD owns the top of the screen: no lobby objective or tutorial hint behind it
	local inTower = (player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true)
	-- (hidden during the 3-2-1 so the countdown numbers stay clear)
	local counting = State.Match ~= nil and State.Match.Phase == "Countdown"
	local vis = hint ~= nil and hint ~= Hud.hintDismissed and not UI.blocked() and not inTower and not counting
	-- One guidance card at a time: while a tutorial hint shows in the lobby or a hunt search, the objective steps
	-- aside (the hint says what to do); after a hunt it keeps only its title (HUNT OVER), so the stack never covers
	-- the view and two cards never ask for different things.
	local m = State.Match
	local objVis = refs.ShowObjective ~= false and not inTower and not (vis and (m == nil or m.Phase == "Searching"))
	-- the starter-egg line steps aside while the egg and its route arrow are on screen (they say the same thing, and the
	-- top-centre card covered the arch sign over spawn on PC too)
	if objVis and StarterEggView.visible() then
		objVis = false
	end
	local pillMode = refs.ObjPill == true
	local subVis = pillMode or not (vis and m ~= nil)
	local objH = if pillMode then 38 elseif subVis then (refs.ObjFullH or 56) else 34
	if refs.Hint.Visible ~= vis or refs.Objective.Visible ~= objVis or refs.ObjSub.Visible ~= subVis or refs.Objective.Size.Y.Offset ~= objH then
		if vis and not refs.Hint.Visible then
			UI.pop(refs.Hint, 0.85) -- the hint bar pops in instead of just appearing
		end
		refs.Hint.Visible = vis
		refs.Objective.Visible = objVis
		refs.ObjSub.Visible = subVis
		refs.Objective.Size = if pillMode then UDim2.fromOffset(refs.ObjPillW or (LEFT_W + 24), objH) else UDim2.new(1, 0, 0, objH)
		refs.PlaceTop()
	end
	if hint and refs.HintText.Text ~= hint then
		refs.HintText.Text = hint
	end
end

local _ = C
return Hud
