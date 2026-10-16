--!strict
-- Pet Battle + Pet Training screens (carter 2026-10-14: find the pet -> train the pet -> fight other pets).
-- BATTLE button (HUD mode row) -> battle card (team, power, trophies, FIGHT / TRAIN); train card (tap TRAIN on a pet
-- to level it up, pick the team); queue strip while looking for a rival; fight HUD (names, timer, SPECIAL, LEAVE);
-- result card. The 3D fight is drawn by TowerView. Sends intents only (PvpNet.PvpAction); the server decides all.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PvpConfig = require(Shared.PvpConfig)
local PvpRules = require(Shared.PvpRules)
local TouchLayout = require(Shared.TouchLayout)
local UiMotion = require(Shared.UiMotion)
local UI = require(script.Parent.UI)
local State = require(script.Parent.Parent.State)
local PanelSkin = require(script.Parent.PanelSkin)
local Theme = require(script.Parent.Theme)
local HudArt = require(script.Parent.HudArt)
local Juice = require(script.Parent.Juice)
local GeodeView = require(script.Parent.GeodeView)
local TowerView = require(script.Parent.Parent.TowerView)
local Audio = require(script.Parent.Parent.Audio)
local PetShop = require(script.Parent.PetShop)
local PetFollow = require(script.Parent.Parent.PetFollow)
local TowerPanel = require(script.Parent.TowerPanel)
local PetFx = require(script.Parent.Parent.PetFx)
local FightFx = require(script.Parent.Parent.FightFx)
local FightCam = require(script.Parent.Parent.FightCam)
local PetMotionBridge = require(script.Parent.Parent.PetMotionBridge)
local TapFight = require(script.Parent.TapFight)

local TC = Theme.Color
local T = UI.T
local player = Players.LocalPlayer

local PvpPanel = {}

local send: (any) -> () = function() end
local roster: any = nil
-- when the roster arrived: a card opened later asks again (levels, names and power change outside the cards: hunt XP,
-- /maxpet, hatching; Studio 2026-10-16 the TRAIN card kept Lv 1 after the Pet Book showed 50/50). The server allows
-- one Open per second, so a roster under ROSTER_FRESH old is reused.
local rosterAt = -math.huge
local ROSTER_FRESH = 1.1
local function stale(): boolean
	return roster == nil or os.clock() - rosterAt > ROSTER_FRESH
end
local inFight = false
local queuedAt: number? = nil
local queueBot = PvpConfig.BotAfter
local fightEnds = 0
local fightStarts = 0
local hud: Frame? = nil
local queueStrip: Frame? = nil
local queueLabel: TextLabel? = nil
local timerLabel: TextLabel? = nil
local namesLabel: TextLabel? = nil
local specialBtn: TextButton? = nil
local meterFill: Frame? = nil
local trainRows: { [string]: Frame } = {}
local picked: { string } = {}
local lastTap = 0
local wantCard: string? = nil -- the card to open when the next roster arrives
local unitInfo: { [string]: any } = {} -- this fight's units: Foe, Info { Rarity, Level, Cap, Power }, Name
local beatBy: any = nil -- the rival pet the finisher showed (named on the loss card)

-- One FightFx moment (FightFx.play); false when it could not play, so callers can fall back.
local function moment(kind: string, opts: { [string]: any })
	local ok = pcall(FightFx.play, kind, opts)
	return ok
end

-- Pet line spacing for this fight (PvpConfig.Layouts), and back to the tower's after.
local function applyLayout(layout: any?)
	if layout then
		TowerView.petZ, TowerView.foeZ = layout.PetZ, layout.FoeZ
		TowerView.petGap, TowerView.foeGap = layout.PetGap, layout.FoeGap
		TowerView.showTarget = false
	else
		TowerView.petZ, TowerView.foeZ, TowerView.petGap, TowerView.foeGap = -14, -4, 5, 6
		TowerView.showTarget = true
	end
end

local RARITY_COLOR = {
	Common = Color3.fromRGB(200, 200, 206),
	Uncommon = Color3.fromRGB(110, 220, 90),
	Rare = Color3.fromRGB(80, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 40),
} :: { [string]: Color3 }

local RANK_COLOR: { [string]: Color3 } = {}
for _, r in PvpConfig.Ranks do
	RANK_COLOR[r.Name] = r.Color
end

local function holder(name: string): Frame
	return UI.frame(UI.screen(), { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
end

local function reduced(): boolean
	return UI.Reduced == true
end

-- One pet picture (the same 3D view the Pet Book uses).
local function picture(parent: Instance, spec: any, size: number, pos: UDim2?)
	local pic = UI.frame(parent, { Name = "Picture", Position = pos or UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	if type(spec) == "table" then
		pcall(GeodeView.make, pic, spec, { Size = UDim2.fromScale(1, 1), Backing = true })
	end
	return pic
end

local function petById(id: string): any?
	if roster == nil then
		return nil
	end
	for _, p in roster.Pets do
		if p.Id == id then
			return p
		end
	end
	return nil
end

-- BATTLE card ------------------------------------------------------------------------------------------------------

local openTrain: () -> ()

local function openBattle()
	if stale() then
		wantCard = "Battle"
		send({ Op = "Open" })
		return
	end
	local panel, body, close, footer = UI.modal("Battle", "PET BATTLE", Vector2.new(600, 450), {
		Subtitle = string.format("%s rank · %d trophies · win streak %d", roster.Rank, roster.Trophies, roster.Streak),
		Footer = T.Primary.Y + 16,
	})
	PanelSkin.dress(panel, "IconLeaderboard", "PET BATTLE")
	-- a short landscape screen (the Studio 844 x 390 window, landscape phones: under 420 logical px tall) sees the
	-- card through a ~200 px window: smaller team cards and heading there, so the record and the free-egg lines
	-- show without scrolling (they hid under the TRAIN / FIGHT footer, Studio check 2026-10-15)
	local short = not UI.isPortrait() and UI.Logical.Y < 420
	local twoLines = false
	for _, id in roster.Team do
		local p = petById(id)
		twoLines = twoLines or (p ~= nil and UiMotion.twoLineName(p.Name))
	end
	-- room for a two-line name ("Skeleton Thunderstrut") only when a team pet has one
	local cardH = (if short then 100 else 132) + (if twoLines then (if short then 16 else 18) else 0)
	local pic = if short then 56 else 72
	UI.list(body, Enum.FillDirection.Vertical, if short then 4 else 8)
	if #roster.Pets == 0 then
		UI.emptyState(body, "No pets yet", "Hatch a pet in the egg race first. Then it can battle!")
	else
		-- the clip's quest-title blue, no outline, like the other headings on the white sheet (gold read weak there)
		UI.text(body, string.format("YOUR TEAM · POWER %s", UI.num(roster.Power)), {
			Name = "TeamPower", Font = UI.Head, TextSize = T.Head, Size = UDim2.new(1, 0, 0, if short then 28 else 34), TextColor3 = Theme.Pet.QuestTitle, Outline = "Normal", LayoutOrder = 1,
		})
		local row = UI.frame(body, { Name = "Team", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, cardH), LayoutOrder = 2 })
		UI.list(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
		for i, id in roster.Team do
			local p = petById(id)
			if p then
				local c = UI.card(row, "inset", { Name = "Pet" .. i, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i })
				picture(c, p.Spec, pic, UDim2.new(0.5, -pic / 2, 0, 4))
				-- up to two lines ("Skeleton Thunderstrut" wrapped and hid the level, then ended in "..." on one line, on a
				-- 844x390 phone); the level sits on the power line below
				local nameH = if twoLines then (if short then 34 else 40) else (if short then 18 else 22) -- same row height on every card
				UI.text(c, p.Name, {
					Name = "PetName", Font = UI.Bold, TextSize = T.Small, Position = UDim2.fromOffset(4, pic + 4), Size = UDim2.new(1, -8, 0, nameH),
					TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = TowerView.TypeColor[p.Element] or TC.Text,
				})
				UI.text(c, "\u{26A1} " .. UI.num(p.Power2) .. "  Lv " .. p.Level, {
					Font = UI.Head, TextSize = T.Body, Position = UDim2.fromOffset(4, pic + 4 + nameH), Size = UDim2.new(1, -8, 0, if short then 20 else 26),
					TextXAlignment = Enum.TextXAlignment.Center,
				})
			end
		end
		UI.text(body, string.format("Wins %d · Losses %d · Best streak %d", roster.Wins, roster.Losses, roster.BestStreak), {
			Name = "Record", TextSize = T.Small, TextColor3 = TC.Muted, Size = UDim2.new(1, 0, 0, if short then 22 else 24), LayoutOrder = 3,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		-- free eggs (shared/EggPerks): every 3rd battle win banks a free Basic Egg
		local prof: any = State.Profile
		local perks: any = if prof then prof.EggPerks else nil
		local toEgg = if type(perks) == "table" then tonumber(perks.WinsToEgg) else nil
		if toEgg and toEgg > 0 then
			UI.text(body, string.format("Win %d more = FREE EGG!", toEgg), {
				Name = "FreeEgg", Font = UI.Head, TextSize = T.Body, TextColor3 = Theme.Pet.Lime, Outline = "Normal", Size = UDim2.new(1, 0, 0, if short then 24 else 26), LayoutOrder = 4,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		local nextText = if roster.NextRank then string.format("%d more trophies to %s!", roster.NextAt - roster.Trophies, roster.NextRank) else "Top rank! You are a Champion!"
		UI.text(body, "Win = coins + trophies. Train pets to make them stronger! " .. nextText, {
			Name = "Tip", TextSize = T.Small, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 5, TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	if footer then
		UI.list(footer, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		UI.button(footer, "TRAIN", "blue", function()
			openTrain()
		end, { Name = "Train", Size = UDim2.new(0.42, -5, 1, 0), LayoutOrder = 1 })
		UI.button(footer, if queuedAt then "CANCEL" else "FIGHT!", if queuedAt then "gray" else "green", function()
			close()
			send({ Op = if queuedAt then "Cancel" else "Queue" })
		end, { Name = "Fight", Size = UDim2.new(0.42, -5, 1, 0), LayoutOrder = 2 })
	end
end

-- TRAIN card -------------------------------------------------------------------------------------------------------

local function setRow(row: Frame, p: any)
	local lv = row:FindFirstChild("Level") :: TextLabel?
	if lv then
		lv.Text = string.format("%s%s  Lv %d/%d", p.Name, string.rep("\u{2605}", p.Evolve or 0), p.Level, p.Cap or p.Level)
	end
	local pw = row:FindFirstChild("Power") :: TextLabel?
	if pw then
		-- at the cap the copies count shows how close an EVOLVE is (3 copies of the same pet)
		local maxedNow = p.Cap ~= nil and p.Level >= p.Cap
		local copies = if maxedNow and p.EvolveWhy ~= "Stage" and p.Copies then string.format("   \u{1F9EC} %d/3", p.Copies) else ""
		pw.Text = "\u{26A1} " .. UI.num(p.Power2) .. copies
	end
	local fill = row:FindFirstChild("Fill", true) :: Frame?
	if fill then
		local f = if (p.XpNeed or 0) > 0 then math.clamp(p.XpInto / p.XpNeed, 0, 1) else 1
		fill.Size = UDim2.fromScale(f, 1)
	end
	local train = row:FindFirstChild("TrainBtn") :: TextButton?
	if train then
		local maxed = p.Cap ~= nil and p.Level >= p.Cap
		local label = train:FindFirstChild("Label") :: TextLabel?
		local evolve = maxed and p.CanEvolve == true
		if label then
			label.Text = if evolve then "EVOLVE!" elseif maxed then "MAX" else "TRAIN!"
		end
		UI.setEnabled(train, evolve or not maxed, if evolve then "blue" else "gold")
	end
	local team = row:FindFirstChild("TeamBtn") :: TextButton?
	if team then
		local on = table.find(picked, p.Id) ~= nil
		local label = team:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if on then "IN TEAM" else "ADD"
		end
		UI.setEnabled(team, true, if on then "green" else "gray")
	end
end

function openTrain()
	if stale() then
		wantCard = "Train"
		send({ Op = "Open" })
		return
	end
	picked = table.clone(roster.Team)
	local panel, body, _close, footer = UI.modal("Train", "TRAIN PETS", Vector2.new(620, 440), {
		Subtitle = "Tap TRAIN, climb the TOWER or hunt eggs to level up your pets!",
		Footer = T.Primary.Y + 16,
	})
	PanelSkin.dress(panel, "IconPets", "TRAIN PETS")
	UI.list(body, Enum.FillDirection.Vertical, 6)
	table.clear(trainRows)
	if #roster.Pets == 0 then
		UI.emptyState(body, "No pets yet", "Hatch a pet in the egg race first!")
	end
	local sorted = table.clone(roster.Pets)
	table.sort(sorted, function(a: any, b: any)
		return a.Power2 > b.Power2
	end)
	for i, p in sorted do
		local row = UI.card(body, "inset", { Name = "Pet_" .. tostring(p.Id), Size = UDim2.new(1, 0, 0, 74), LayoutOrder = i })
		picture(row, p.Spec, 62)
		-- one line shrunk to fit, so a long variant name never pushes "Lv 4/10" out of the box
		UI.oneLine(UI.text(row, "", { Name = "Level", Font = UI.Bold, TextSize = T.Body, Position = UDim2.fromOffset(74, 4), Size = UDim2.new(0.5, -78, 0, 24), TextColor3 = TowerView.TypeColor[p.Element] or TC.Text }))
		UI.text(row, "", { Name = "Power", Font = UI.Head, TextSize = T.Body, Position = UDim2.fromOffset(74, 28), Size = UDim2.new(0.5, -78, 0, 22) })
		UI.bar(row, { Name = "Xp", Position = UDim2.fromOffset(74, 54), Size = UDim2.new(0.5, -78, 0, 10) }, TC.Gold)
		UI.button(row, "ADD", "gray", function()
			local at = table.find(picked, p.Id)
			if at then
				table.remove(picked, at)
			elseif #picked < PvpConfig.TeamSize then
				table.insert(picked, p.Id)
			else
				UI.notify("Your team is full. Tap IN TEAM on a pet to take it out.", "info")
				return
			end
			send({ Op = "SetTeam", Pets = picked })
			for _, q in roster.Pets do
				local r = trainRows[q.Id]
				if r then
					setRow(r, q)
				end
			end
		end, { Name = "TeamBtn", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -132, 0.5, 0), Size = UDim2.fromOffset(104, 44), TextSize = T.Small })
		UI.button(row, "TRAIN!", "gold", function()
			local cur = petById(p.Id) or p
			if cur.CanEvolve and cur.Cap and cur.Level >= cur.Cap then
				UI.confirm({
					Name = "Evolve", Title = "Evolve " .. tostring(cur.Name) .. "?",
					Message = "Uses 2 other copies of this pet. It grows bigger, stronger and can level higher!",
					Confirm = "EVOLVE!", Cancel = "NOT NOW", Style = "blue",
					OnConfirm = function()
						send({ Op = "Evolve", Pet = cur.Id })
					end,
				})
				return
			end
			local now = os.clock()
			if now - lastTap < 1 / PvpConfig.Train.TapsPerSecond then
				return -- the server counts at most TapsPerSecond taps; faster taps would just be dropped
			end
			lastTap = now
			send({ Op = "Train", Pet = p.Id })
			if not reduced() then
				Juice.wobble(row)
			end
		end, { Name = "TrainBtn", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(116, 54) })
		trainRows[p.Id] = row
		setRow(row, p)
	end
	if footer then
		UI.list(footer, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		UI.button(footer, "BEST", "gray", function()
			send({ Op = "EquipBest" })
		end, { Name = "Best", Size = UDim2.new(0.24, -6, 1, 0), LayoutOrder = 1 })
		-- the Training Tower (carter 2026-10-14): every floor climbed gives the team XP
		UI.button(footer, "TOWER", "blue", function()
			TowerPanel.openPicker()
		end, { Name = "Tower", Size = UDim2.new(0.24, -6, 1, 0), LayoutOrder = 2 })
		-- rarer pets grow higher (level caps): the egg shrine is the other way to get stronger
		UI.button(footer, "HATCH", "gold", function()
			PetShop.setPayCoins(true)
			PetShop.open("Eggs")
		end, { Name = "Hatch", Size = UDim2.new(0.24, -6, 1, 0), LayoutOrder = 3 })
		UI.button(footer, "BATTLE", "green", function()
			wantCard = "Battle"
			send({ Op = "Open" })
		end, { Name = "ToBattle", Size = UDim2.new(0.24, -6, 1, 0), LayoutOrder = 4 })
	end
end

-- The trained pet, when it follows the player, does its "train" clip (PetMotion) while the taps keep coming and a
-- squash hop each tap; a level up gets PetFx's level-up burst.
local trainUntil: { [string]: number } = {}
local function trainMotion(msg: any)
	local m = PetFollow.modelFor(player, msg.Pet)
	if not m then
		return
	end
	PetMotionBridge.setAnim(m, "train")
	local id = tostring(msg.Pet)
	trainUntil[id] = os.clock() + 1.5
	task.delay(1.6, function()
		if os.clock() >= (trainUntil[id] or 0) and m.Parent and m:GetAttribute("Anim") == "train" then
			trainUntil[id] = nil
			PetMotionBridge.setAnim(m, nil)
		end
	end)
	if msg.LevelUp then
		if not moment("levelup", { Target = m, Level = msg.Level, Mine = true }) then
			pcall(PetFx.levelUp, m, msg.Level)
		end
	elseif (msg.Gain or 0) > 0 and not reduced() then
		pcall(PetFx.squash, m)
	end
end

local function onTrained(msg: any)
	local p = petById(msg.Pet)
	if not p then
		return
	end
	trainMotion(msg)
	p.Level, p.XpInto, p.XpNeed, p.Power2 = msg.Level, msg.XpInto, msg.XpNeed, msg.Power
	if msg.Maxed and not msg.LevelUp then
		UI.notify(string.format("%s is at max level! Rarer pets can grow higher.", p.Name), "info", { Tag = "trainmax" })
	end
	local row = trainRows[p.Id]
	if row and row.Parent then
		setRow(row, p)
		local btn = row:FindFirstChild("TrainBtn") :: GuiObject?
		if btn then
			Juice.floatText(btn, "+" .. tostring(msg.Gain) .. " XP", TC.Gold)
		end
	end
	if msg.LevelUp then
		Juice.banner(string.format("LEVEL UP! %s Lv %d", p.Name, msg.Level), TC.Gold, 1.4)
		UI.notify(string.format("%s power %s \u{2192} %s!", p.Name, UI.num(msg.PowerBefore or msg.Power), UI.num(msg.Power)), "success", { Tag = "trainlv" })
		Audio.play("LevelUp") -- PetSoundIds.LevelUp (stand-in RarityAccent until uploaded)
		if row and row.Parent then
			Juice.confetti(row, 18)
		end
	end
end

-- HUD: entry button, queue strip, fight bar --------------------------------------------------------------------------

local function buildEntry()
	local screen = UI.screen()
	local box = screen:WaitForChild("LeftBox", 10) -- the HUD wraps its left column in this box
	local left = if box then box:WaitForChild("Left", 10) else nil
	local row = if left then left:WaitForChild("ModeRow", 5) or left else nil
	local b: TextButton = HudArt.bigButton(row or screen, {
		Name = "BattleButton", Style = "red", Art = "IconLeaderboard", Title = "BATTLE", Sub = "Pet vs pet", Width = 172, Height = 60, LayoutOrder = 2,
		OnClick = openBattle,
	})
	b:SetAttribute("Short", "FIGHT") -- the word on the square phone tile (HudArt.compact)
	if not left then
		b.Position = UDim2.fromOffset(T.Edge, T.Edge + 220)
	end
	local function refresh()
		b.Visible = player:GetAttribute("MatchKey") == nil and player:GetAttribute("InTower") == nil and player:GetAttribute("InBattle") == nil
	end
	for _, a in { "MatchKey", "InTower", "InBattle" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	refresh()
end

local function buildQueueStrip()
	local g = holder("BattleQueue")
	local strip = UI.card(g, "hud", { Name = "Strip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, T.Edge + 48), Size = UDim2.fromOffset(340, 48) })
	queueLabel = UI.text(strip, "Finding a rival...", { Font = UI.Bold, TextSize = T.Body, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -120, 1, 0) })
	UI.button(strip, "CANCEL", "gray", function()
		send({ Op = "Cancel" })
	end, { Name = "Cancel", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(100, 38), TextSize = T.Small })
	g.Visible = false
	queueStrip = g
end

local function setQueued(on: boolean)
	queuedAt = if on then os.clock() else nil
	if queueStrip then
		queueStrip.Visible = on
	end
end

local SPECIAL_W = 160
local function buildHud()
	local g = holder("BattleHud")
	g.Visible = false
	hud = g
	local top = UI.card(g, "hud", { Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, T.Edge), Size = UDim2.fromOffset(380, 66) })
	namesLabel = UI.text(top, "YOU vs RIVAL", {
		Font = UI.Head, TextSize = T.Body, Outline = "Strong", Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 2), TextXAlignment = Enum.TextXAlignment.Center,
	})
	timerLabel = UI.text(top, "1:00", {
		Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Gold, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 34), TextXAlignment = Enum.TextXAlignment.Center,
	})
	TowerView.topClear = function(): number
		if g.Visible then
			local inset = (GuiService:GetGuiInset())
			return inset.Y + top.AbsolutePosition.Y + top.AbsoluteSize.Y
		end
		return 0
	end
	UI.button(g, "LEAVE", "red", function()
		UI.confirm({
			Name = "BattleLeave", Title = "Leave the battle?", Message = "Leaving counts as a loss.", Confirm = "LEAVE", Cancel = "STAY", Style = "red",
			OnConfirm = function()
				send({ Op = "Leave" })
			end,
		})
	end, { Name = "Leave", Position = UDim2.new(0, T.Edge, 0.14, 0), Size = UDim2.fromOffset(100, T.Touch), TextSize = T.Small })
	local sp = UI.button(g, "SPECIAL", "gold", function()
		send({ Op = "Special" })
	end, { Name = "Special", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(SPECIAL_W, T.Primary.Y + 6) })
	sp:SetAttribute("DisabledFill", Color3.fromRGB(40, 48, 66))
	sp:SetAttribute("DisabledText", Color3.new(1, 1, 1))
	specialBtn = sp
	local _, fill = UI.bar(sp, { Name = "Meter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.new(1, 0, 0, 10) }, TC.Gold)
	meterFill = fill
	-- same spot as the tower's SPECIAL: above or beside Roblox's jump button, never on the thumbstick side
	local function place()
		local px = UI.screen().AbsoluteSize
		if px.X < 2 or px.Y < 2 then
			return
		end
		local cam = Workspace.CurrentCamera
		local full = if cam then cam.ViewportSize else px
		local scale = math.max(UI.Scale, 0.1)
		local h = T.Primary.Y + 6 + 16
		local topLimit = px.Y - (T.Edge + 250) * scale
		local r, bottom, mode = TouchLayout.place(full.X, full.Y, h * scale, topLimit, UserInputService.TouchEnabled)
		local w = SPECIAL_W
		if mode == "left" then
			w = math.max(96, math.min(w, (px.X * 0.6 - r) / scale))
		end
		sp.Size = UDim2.fromOffset(w, T.Primary.Y + 6)
		sp.Position = UDim2.new(1, -r / scale, 1, -bottom / scale)
	end
	place()
	UI.screen():GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(place)
	end)
	TapFight.build(g, sp, function(msg)
		send(msg)
	end)
end

local wasFull = false
local hasSpecial = true -- only Epic+ pets bring a SPECIAL (carter 2026-10-14)
local function setMeter(f: number)
	if not hasSpecial then
		f = 0
	end
	f = math.clamp(f, 0, 1)
	if meterFill then
		meterFill.Size = UDim2.fromScale(f, 1)
		meterFill.BackgroundColor3 = if f >= 1 then TC.Gold else Color3.fromRGB(105, 218, 232)
	end
	local sp = specialBtn
	if sp then
		UI.setEnabled(sp, f >= 1, "gold")
		local label = sp:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if not hasSpecial then "EPIC+ ONLY" elseif f >= 1 then "SPECIAL!" else "CHARGING " .. math.floor(f * 100) .. "%"
		end
		if f >= 1 and not wasFull then
			Audio.play("RarityAccent", { Volume = 0.6, Key = "pvp:special-ready" })
			if not reduced() then
				task.spawn(function()
					for _, rot in { -6, 6, -4, 4, 0 } do
						TweenService:Create(sp, TweenInfo.new(0.06, Enum.EasingStyle.Sine), { Rotation = rot }):Play()
						task.wait(0.06)
					end
				end)
			end
		end
	end
	wasFull = f >= 1
end

-- The VS splash while the fight camera sweeps in: the two sides slide in from the edges, a big VS pops between them.
local function vsSplash(left: string, right: string, hold: number)
	local root = UI.noticeLayer()
	local old = root:FindFirstChild("PvpVs")
	if old then
		old:Destroy()
	end
	local f = UI.frame(root, {
		Name = "PvpVs", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.new(0.94, 0, 0, 74), BackgroundTransparency = 1, ZIndex = 38,
	})
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(720, 74)
	lim.Parent = f
	local function plate(name: string, text: string, color: Color3, x: number, from: number)
		local card = UI.frame(f, {
			Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(from, 0.5), Size = UDim2.new(0.4, 0, 0, 52),
			BackgroundColor3 = color, BackgroundTransparency = 0.12, ZIndex = 38,
		})
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 14)
		c.Parent = card
		local st = Instance.new("UIStroke")
		st.Color = Color3.new(1, 1, 1)
		st.Thickness = 3
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = card
		UI.text(card, text, { Name = "Text", Font = UI.Head, TextSize = T.Head, TextColor3 = Color3.new(1, 1, 1), Outline = "Strong", Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 39 })
		if UI.Reduced then
			card.Position = UDim2.fromScale(x, 0.5)
		else
			TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(x, 0.5) }):Play()
		end
	end
	plate("Me", left, Color3.fromRGB(60, 140, 255), 0.22, -0.3)
	plate("Foe", right, Color3.fromRGB(235, 70, 70), 0.78, 1.3)
	local vs = UI.text(f, "VS", { Name = "Vs", Font = UI.Head, TextSize = 56, TextColor3 = TC.Gold, Outline = "Strong", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.18, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 40 })
	vs.TextWrapped = false
	task.delay(if UI.Reduced then 0 else 0.3, function()
		if vs.Parent then
			UI.pop(vs, 0.3)
		end
	end)
	task.delay(hold, function()
		if not f.Parent then
			return
		end
		local info = TweenInfo.new(0.35)
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1 }):Play()
			elseif d:IsA("Frame") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
	end)
	Debris:AddItem(f, hold + 0.5)
end

local function countIn(n: number)
	task.spawn(function()
		for i = math.floor(n), 1, -1 do
			if not inFight then
				return
			end
			Juice.banner(tostring(i), TC.Gold, 0.6)
			task.wait(1)
		end
		if inFight then
			Juice.banner("FIGHT!", Color3.fromRGB(255, 110, 80), 0.9)
		end
	end)
end

-- The loser's finisher: the camera eases in on the rival's strongest standing pet, which glows in its rarity colour
-- under a big card (power, rarity, level). It is what beat you, and what you could have.
local function finisher()
	local best, bestPower = nil, -1
	for id, u in unitInfo do
		local m = TowerView.model(id)
		local standing = m ~= nil and u.Hp > 0
		local p = (u.Info and u.Info.Power or 0) + (if standing then 1e6 else 0)
		if u.Foe and m and p > bestPower then
			best, bestPower = id, p
		end
	end
	if not best then
		return
	end
	local u = unitInfo[best]
	local info = u.Info or {}
	beatBy = { Name = u.Name, Power = info.Power or 0, Rarity = info.Rarity or "Common", Level = info.Level or 1, Cap = info.Cap or 1, Modifier = info.Modifier }
	local variant = if info.Modifier and info.Modifier ~= "Natural" then string.upper(info.Modifier) .. " " else ""
	TowerView.showcase(best, "\u{26A1}" .. UI.num(beatBy.Power), string.format("%s%s · Lv %d/%d", variant, string.upper(beatBy.Rarity), beatBy.Level, beatBy.Cap), RARITY_COLOR[beatBy.Rarity] or TC.Gold)
	local model = TowerView.model(best)
	if model then
		FightCam.hero(model) -- a low push-in on what beat you, held until the fight closes
	end
end

local function endFightView()
	inFight = false
	TapFight.stop()
	FightCam.stop()
	table.clear(unitInfo)
	applyLayout(nil)
	if hud then
		hud.Visible = false
	end
	TowerView.clear()
	task.delay(0.3, function()
		local cam = Workspace.CurrentCamera
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if cam and root and root:IsA("BasePart") and cam.CameraType == Enum.CameraType.Custom and not inFight then
			local p = root.Position
			cam.CFrame = CFrame.lookAt(p - root.CFrame.LookVector * 10 + Vector3.new(0, 5, 0), p + Vector3.new(0, 1.5, 0))
		end
	end)
end

local function showResult(msg: any)
	local title = if msg.Result == "Win" then "VICTORY!" elseif msg.Result == "Loss" then "DEFEAT" else "DRAW"
	local lines = {}
	table.insert(lines, string.format("+%s coins", UI.num(msg.Coins)))
	if msg.TrophyChange ~= 0 then
		table.insert(lines, string.format("%s%d trophies", if msg.TrophyChange > 0 then "+" else "", msg.TrophyChange))
	end
	if msg.Streak >= 2 then
		table.insert(lines, string.format("%d win streak!", msg.Streak))
	end
	local text = table.concat(lines, " · ") .. string.format("\n+%d pet XP · %s rank (%d trophies)", msg.Xp, msg.Rank, msg.Trophies)
	for _, up in msg.LevelUps or {} do
		text ..= string.format("\n%s reached Lv %d (power %s)!", up.Name, up.Level, UI.num(up.Power))
	end
	local lost = msg.Result == "Loss" and beatBy ~= nil
	if lost then
		-- what beat you, and how to get there: train, hatch rarer pets
		text ..= string.format("\nBeaten by %s: \u{26A1}%s, %s Lv %d/%d. Get stronger!", beatBy.Name, UI.num(beatBy.Power), beatBy.Rarity, beatBy.Level, beatBy.Cap)
	end
	beatBy = nil
	UI.confirm({
		Name = "BattleResult", Title = title, Message = text, Confirm = if lost then "GET STRONGER" else "FIGHT AGAIN", Cancel = "OK",
		Style = if msg.Result == "Win" then "green" else "gold",
		OnConfirm = function()
			if lost then
				openTrain()
			else
				send({ Op = "Queue" })
			end
		end,
	})
	if msg.Result == "Win" then
		Audio.play("BattleWin") -- PetSoundIds.BattleWin (stand-in MatchWin until uploaded)
		local shade = UI.dialogLayer():FindFirstChild("Dialog_BattleResult")
		local panel = shade and shade:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			Juice.confetti(panel, 30)
		end
	end
	roster = nil -- stale (trophies, levels): the next card asks again
end

-- Fight moments on top of TowerView's hit drawing: FightFx (crit / special / K.O. with the
-- winner's showcase; screen effects only when one of the player's own pets is in it) and the owner's PetMotion attack
-- and hit clips (no-op without them). Fighters and watchers both see them.
local function units(list: { any }?)
	table.clear(unitInfo)
	local all: { any } = list or {}
	for _, u in all do
		unitInfo[u.Id] = { Foe = u.Foe == true, Info = u.Info, Name = u.Name, Hp = u.Hp, Element = u.Element }
	end
end

local function syncHp(hp: any)
	for id, pair in hp or {} do
		local u = unitInfo[id]
		if u and type(pair) == "table" then
			u.Hp = pair[1] or 0
		end
	end
end

-- The K.O.: the last pet that fainted, and the strongest pet still standing on the other side gets the showcase.
local function knockout(fainted: string?)
	local lost = fainted and unitInfo[fainted]
	local winner: Model? = nil
	local bestPower = -1
	for id, u in unitInfo do
		local m = TowerView.model(id)
		if m and u.Hp > 0 and (lost == nil or u.Foe ~= lost.Foe) then
			local p = u.Info and u.Info.Power or 0
			if p > bestPower then
				winner, bestPower = m, p
			end
		end
	end
	local target = fainted and TowerView.model(fainted)
	local winnerMine = false
	if lost then
		winnerMine = lost.Foe -- the foe fainted: my side won
	end
	local played = target ~= nil and moment("ko", {
		Target = target,
		Winner = winner,
		Mine = inFight,
		Cinematic = false, -- FightCam directs the K.O. (orbit, then the winner's hero shot)
		WinnerMine = winnerMine,
	})
	if inFight and target then
		FightCam.ko(target, winner)
	end
	if not played then
		TowerView.knockout(fainted)
	end
end

local function fightMotion(list: { any })
	for _, e in list do
		if e.Kind == "Hit" then
			local from, to = TowerView.model(e.From or ""), TowerView.model(e.To or "")
			PetMotionBridge.play(from, "attack")
			PetMotionBridge.play(to, "hit")
			-- plain and type-advantage hits are TowerView's numbers and "Strong!" pops; FightFx adds the crits (a second
			-- pop on every hit buried the fight in text on a phone)
			if inFight and to then
				-- no lean on every hit (Studio 2026-10-15 camera log: the leans and a close-up on every type-advantage
				-- hit kept the wide shot off both teams most of the fight); crits only get a close-up, spaced out by
				-- FightCamRules.CUT_GAP
				if e.Crit then
					FightCam.cut("crit", to, from)
				end
			end
			if to and e.Crit then
				local att = unitInfo[e.From or ""]
				local def = unitInfo[e.To or ""]
				moment("crit", {
					Target = to,
					Attacker = from,
					Element = att and att.Element,
					Quiet = true, -- TowerView already pops "CRIT! 72" (two words stacked on a phone)
					Mine = inFight and def ~= nil and (not def.Foe or (att ~= nil and not att.Foe)),
				})
			end
		elseif e.Kind == "Special" then
			local from = TowerView.model(e.From or "")
			local att = unitInfo[e.From or ""]
			if from then
				local target: Model? = nil
				for id, u in unitInfo do
					if att and u.Foe ~= att.Foe and u.Hp > 0 then
						target = TowerView.model(id)
						break
					end
				end
				moment("special", { Attacker = from, Target = target or from, Element = att and att.Element, Mine = inFight })
				if inFight and att then
					if att.Foe then
						FightCam.cut("special", target or from, from) -- the rival's SPECIAL lands on our pets
					else
						FightCam.cut("charge", from) -- ours: over the caster's shoulder
					end
				end
			end
		end
	end
end

local function onEvent(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local k = msg.Kind
	if k == "Roster" then
		roster = msg
		rosterAt = os.clock()
		local want = wantCard
		wantCard = nil
		if want == "Train" then
			openTrain()
		elseif want == "Battle" or (want == nil and UI.modalOpen() == "Battle") then
			openBattle()
		elseif UI.modalOpen() == "Train" then
			-- a team change: restyle the open train card in place (keeps its scroll position)
			picked = table.clone(msg.Team)
			for _, q in msg.Pets do
				local r = trainRows[q.Id]
				if r and r.Parent then
					setRow(r, q)
				end
			end
		end
	elseif k == "OpenCard" then
		wantCard = msg.Card
	elseif k == "Trained" then
		onTrained(msg)
	elseif k == "Evolved" then
		if msg.Ok then
			Juice.banner(string.format("EVOLVED! %s", string.rep("\u{2605}", msg.Stage or 1)), TC.Gold, 2)
			UI.notify(string.format("Power %s \u{2192} %s! New max level %d.", UI.num(msg.PowerBefore or 0), UI.num(msg.Power or 0), msg.Cap or 0), "success", { Tag = "evolve" })
			Audio.play("Evolve") -- PetSoundIds.Evolve (stand-in RarityAccent until uploaded)
			-- the evolved pet, if it follows the player, celebrates (PetFx level-up burst + a happy bounce)
			task.delay(0.6, function()
				local m = PetFollow.modelFor(player, msg.Pet)
				if m then
					pcall(PetFx.happy, m)
					pcall(PetFx.pop, m:GetPivot().Position + Vector3.new(0, 4, 0), "EVOLVED!", TC.Gold, true)
				end
				pcall(PetFollow.bounce, player, msg.Pet)
			end)
		elseif msg.Why == "Copies" then
			UI.notify("You need 3 copies of this pet to evolve. Pets that follow you or sit on your plot are kept safe.", "info", { Tag = "evolve" })
		end
	elseif k == "Queued" then
		queueBot = msg.BotAfter or PvpConfig.BotAfter
		setQueued(true)
		UI.notify("Looking for a rival! You can walk around while you wait.", "info", { Tag = "pvpqueue" })
	elseif k == "Unqueued" then
		local was = queuedAt ~= nil
		setQueued(false)
		local why = PvpRules.unqueueText(msg.Why)
		if was and why then
			UI.notify(why, "info", { Tag = "pvpqueue" })
		end
	elseif k == "Start" then
		setQueued(false)
		UI.closeModal()
		UI.closeDialog()
		for _, name in { "NextGoal", "AwayNest" } do
			local card = UI.dialogLayer():FindFirstChild(name)
			if card then
				card:Destroy() -- a welcome card never covers the fight (it waits for the lobby: RetentionView)
			end
		end
		inFight = true
		TowerView.clear()
		applyLayout(msg.Layout or PvpConfig.Layouts.Private)
		TowerView.floor({ Origin = msg.Origin, Units = msg.Units })
		units(msg.Units)
		beatBy = nil
		fightStarts = os.clock() + (msg.CountIn or 0)
		fightEnds = fightStarts + (msg.FightTime or PvpConfig.FightTime)
		if namesLabel then
			local foe = msg.Foe or {}
			namesLabel.Text = string.format("YOU (%s)  vs  %s%s (%s)", UI.num(msg.Me and msg.Me.Power or 0), string.upper(tostring(foe.Name)), if foe.Bot then " BOT" else "", UI.num(foe.Power or 0))
		end
		if hud then
			hud.Visible = true
		end
		hasSpecial = msg.HasSpecial ~= false
		setMeter(0)
		TapFight.start(msg.MySide or 1)
		task.delay(msg.CountIn or 0, function()
			if inFight then
				TapFight.live()
			end
		end)
		if not hasSpecial then
			UI.notify("Epic and Legendary pets bring a SPECIAL to battles!", "info", { Tag = "pvpspecial" })
		end
		local n = msg.CountIn or 0
		FightCam.start(msg.Origin, msg.Layout or PvpConfig.Layouts.Private, n > 0, n, msg.Units)
		local foe = msg.Foe or {}
		vsSplash(string.format("YOU \u{26A1}%s", UI.num(msg.Me and msg.Me.Power or 0)), string.format("%s%s \u{26A1}%s", string.upper(tostring(foe.Name)), if foe.Bot then " BOT" else "", UI.num(foe.Power or 0)), math.max(n - 0.4, 1.8))
		countIn(n)
	elseif k == "Events" then
		if not inFight then
			return
		end
		TowerView.events(msg.List, msg.Hp)
		syncHp(msg.Hp)
		fightMotion(msg.List)
		TapFight.events(msg.List)
		setMeter(msg.Meter or 0)
		local lastFaint: string? = nil
		for _, e in msg.List do
			if e.Kind == "Faint" then
				lastFaint = e.To
			elseif e.Kind == "KO" then
				knockout(lastFaint)
			elseif e.Kind == "TimeUp" then
				Juice.banner("TIME UP!", TC.Gold, 0.9)
			end
		end
	elseif k == "Over" then
		local won = msg.Winner == msg.MySide
		if msg.Winner == 0 then
			Juice.banner("DRAW!", TC.Gold, 1.6)
		else
			TowerView.cheer(won)
			Juice.banner(if won then "YOU WIN!" else "K.O.! YOU LOSE", if won then TC.Gold else Color3.fromRGB(230, 90, 80), 1.8)
			if not won then
				if hud then
					hud.Visible = false -- the finisher card takes the top of the screen
				end
				finisher()
			end
		end
		if specialBtn then
			UI.setEnabled(specialBtn, false, "gold")
		end
		TapFight.stop()
	elseif k == "Result" then
		if inFight then
			endFightView()
		end
		showResult(msg)
	elseif k == "Closed" then
		if inFight then
			endFightView()
		end
	elseif k == "Notice" then
		UI.notify(tostring(msg.Text), "info")
	end
end

function PvpPanel.start()
	local net = game:GetService("ReplicatedStorage"):WaitForChild("PvpNet")
	local action = net:WaitForChild("PvpAction") :: RemoteEvent
	local event = net:WaitForChild("PvpEvent") :: RemoteEvent
	send = function(msg)
		action:FireServer(msg)
	end
	task.spawn(buildEntry)
	buildQueueStrip()
	buildHud()
	event.OnClientEvent:Connect(onEvent)
	-- queue strip countdown and fight timer
	task.spawn(function()
		while true do
			task.wait(0.25)
			if queuedAt and queueLabel then
				local waited = os.clock() - queuedAt
				local left = math.max(math.ceil(queueBot - waited), 0)
				queueLabel.Text = if left > 0 then string.format("Finding a rival... %d", left) else "Bringing a bot rival!"
			end
			if inFight and timerLabel then
				local left = math.max(math.ceil(fightEnds - os.clock()), 0)
				timerLabel.Text = if os.clock() < fightStarts then "GET READY" else string.format("%d:%02d", left // 60, left % 60)
			end
		end
	end)
end

PvpPanel.openBattle = openBattle
PvpPanel.openTrain = function()
	openTrain()
end

return PvpPanel
