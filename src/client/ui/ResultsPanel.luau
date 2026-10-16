--!strict
-- Geode reveal and RESULTS (board 10).
-- Reveal: RevealView plays the sequence and owns the screen (UI.block).
-- Results: the SAME specimen on the left; the real winner (avatar, crown), the local player's own hunt figures
-- (rubble earned, rocks cracked, rubble sold, storage now: HuntLedger numbers, never recomputed), and the specimen
-- line only for the recipient ("Geode added to collection" once the profile holds it). Others read who found it.
-- PLAY AGAIN follows the existing rematch rules (the leader starts once everyone tapped it; members mark ready),
-- LOBBY returns through the existing flow.
-- Polish: the pet stands on a gold winner's podium in the hero view, confetti falls once when the card opens, and a
-- bouncing "NEW!" sticker marks the recipient's first ever pet of that species and rarity (Pet Book count of 1).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local Net = require(Shared.Net)
local ResultsRules = require(Shared.ResultsRules)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)
local GeodeView = require(script.Parent.GeodeView)
local RevealView = require(script.Parent.Parent.RevealView)
local Effects = require(script.Parent.Parent.Effects)

local T = UI.T
local TC = Theme.Color
local K = Theme.Pet
local player = Players.LocalPlayer
local Results = {}

local resultsOpen = false
local body: Frame? = nil
local footer: Frame? = nil
local panelRef: Frame? = nil

Results.OnTutorialAction = nil :: ((string) -> ())? -- set by Main: "Train" (open the TRAIN card back in the lobby)
Results.OnOpenPet = nil :: ((string) -> ())? -- set by Main: opens the Pet Book on that pet

local function act(a: string)
	Net.event("MatchAction"):FireServer(a)
end

local function headline(res): string
	if res.Kind == "Tutorial" then
		return "PRACTICE HUNT DONE!"
	elseif res.Winner == player.UserId and res.Kind ~= "Solo" then
		return "YOU FOUND IT!"
	end
	return "PET HATCHED!"
end
Results.headline = headline

function Results.reveal(res)
	UI.closeModal()
	local text = if res.Kind == "Tutorial" then "YOU FOUND THE PET!" elseif res.Kind == "Solo" then "HATCHED A PET!" elseif res.Winner == player.UserId then "YOU HATCHED A PET!" else string.upper(res.WinnerName or "?") .. " HATCHED A PET!"
	RevealView.play(res, text, res.Winner == player.UserId) -- the practice pet is yours too: "You hatched ...!" + confetti
end

local stickerShown: { [any]: boolean } = {} -- spec ids whose NEW! sticker already bounced in (re-renders stay still)
local confettiFor: any = nil -- the results table the confetti already fell for

-- A gold two-step podium under the pet (inside the model, so a drag turns it too), then the camera re-fits both.
-- Pet palette gold on top, the deeper gold of the buttons' edge below.
local function podium(model: Model, cam: Camera)
	local cf, size = model:GetBoundingBox()
	local w = math.max(size.X, size.Z)
	local h = math.max(size.Y * 0.22, 0.3)
	local baseY = cf.Position.Y - size.Y / 2
	local function disc(name: string, d: number, hh: number, y: number, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(hh, d, d)
		p.CFrame = CFrame.new(cf.Position.X, y, cf.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Parent = model
	end
	disc("PodiumTop", w * 1.15, h, baseY - h / 2, K.Gold)
	disc("PodiumBase", w * 1.4, h * 0.6, baseY - h - h * 0.3, TC.GoldDeep)
	GeodeView.frame(cam, model)
end

-- First pet of this species and rarity in the player's Pet Book (the server counts it before the results arrive).
local function firstOfKind(prof: any, spec: any): boolean
	if type(prof) ~= "table" or type(prof.DiscoveryRarity) ~= "table" or type(spec) ~= "table" then
		return false
	end
	local row = prof.DiscoveryRarity[spec.Mineral]
	return type(row) == "table" and row[spec.Rarity] == 1
end

local function newSticker(parent: Instance, key: any)
	-- the pet-style ribbon tag (red pill, ink edge, white outlined words), tilted like the shop's "LIMITED!"
	local tag = PetStyle.ribbon(parent, "NEW!", K.Red, {
		Name = "NewSticker", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(42, 22), Size = UDim2.fromOffset(66, 28),
		Rotation = -12, ZIndex = 4,
	})
	PetStyle.vgrad(tag, K.RedTop, K.Red)
	local tagWords = tag:FindFirstChildOfClass("TextLabel")
	if tagWords then
		tagWords.TextSize = T.Small
	end
	if stickerShown[key] or UI.Reduced then
		return
	end
	stickerShown[key] = true
	local sc = Instance.new("UIScale")
	sc.Scale = 0
	sc.Parent = tag
	local pop = TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	pop.Completed:Connect(function()
		if sc.Parent then
			TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 3, true), { Scale = 1.15 }):Play()
		end
	end)
	pop:Play()
end

-- When the results opened: how long the specimen has been "securing" without showing in the collection.
local openedAt = 0
local SECURE_WAIT = 8

local function tileStat(parent: Instance, order: number, name: string, icon: string, label: string, value: string, color: Color3?): TextLabel
	local f = UI.card(parent, "inset", { Name = name, LayoutOrder = order, Size = UDim2.new(0.5, -3, 0, 58) })
	UI.text(f, label, { Name = "Label", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 21) })
	UI.icon(f, icon, 26, { Position = UDim2.fromOffset(8, 26) })
	local v = UI.text(f, value, { Name = "Value", Font = UI.Head, TextSize = T.Head + 2, TextColor3 = color or TC.Text, Position = UDim2.fromOffset(40, 23), Size = UDim2.new(1, -46, 0, 30) })
	v.TextWrapped = false
	return v
end

-- The two score tiles count up from 0 once per results table (re-renders show the final number at once).
local countedFor: any = nil
local function countTile(label: TextLabel, n: number, delay: number)
	if UI.Reduced or n <= 0 then
		return
	end
	label.Text = "0"
	task.delay(delay, function()
		if label.Parent then
			UI.countUp(label, 0, n, 0.7)
		end
	end)
end

local glow: (GuiButton) -> () -- defined below render (PLAY AGAIN glow)
local function render()
	if not resultsOpen or not body or not footer then
		return
	end
	local b = body :: Frame
	local foot = footer :: Frame
	for _, c in b:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	for _, c in foot:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	local res = State.Results
	local m = State.Match
	local prof = State.Profile
	if not res or not m then
		UI.loadingState(b, "Loading results", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		return
	end
	local spec = res.Specimen
	local won = res.Winner == player.UserId
	local mine
	for _, mem in res.Members do
		if mem.UserId == player.UserId then
			mine = mem
		end
	end
	local portrait = UI.isPortrait()

	-- left: the specimen (opening faces the camera), its name and rarity
	local hero = UI.card(b, "inset", { Name = "Hero", Size = if portrait then UDim2.new(1, 0, 0, 170) else UDim2.new(0.42, -4, 1, 0) })
	local _, model, heroCam = GeodeView.make(hero, spec, { Name = "Specimen", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -30) }, true)
	model:PivotTo(CFrame.new())
	podium(model, heroCam)
	local nm = UI.text(hero, GeodeGen.displayName(spec) .. " \u{b7} " .. spec.Rarity, { Name = "SpecimenName", Font = UI.Bold, TextSize = T.Body, TextColor3 = Config.RarityTextColors[spec.Rarity] or TC.Text, Outline = "Normal", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -4), Size = UDim2.new(1, -12, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	nm.TextWrapped = false

	-- right: winner, recipient line, own figures
	-- scrolls when the facts (tutorial stage, payout, others, rematch note) outgrow a short phone
	local col = UI.scroller(b, { Name = "Facts", VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Position = if portrait then UDim2.fromOffset(0, 178) else UDim2.new(0.42, 4, 0, 0), Size = if portrait then UDim2.new(1, 0, 1, -178) else UDim2.new(0.58, -4, 1, 0) })
	UI.list(col, Enum.FillDirection.Vertical, 6)
	local who = UI.card(col, "inset", { Name = "Winner", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 58) })
	UI.text(who, if res.Kind == "Solo" or res.Kind == "Tutorial" then "Solo find:" else "Winner:", { Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 0, 21) })
	UI.icon(who, "crown", 24, { Position = UDim2.fromOffset(10, 26) })
	if type(res.Winner) == "number" and res.Winner > 0 then
		local av = UI.frame(who, { Name = "Avatar", Position = UDim2.fromOffset(40, 23), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = TC.Panel })
		UI.corner(av, 6)
		UI.stroke(av, K.CardEdge, 1.5)
		UI.icon(av, "user", 24, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. res.Winner .. "&w=48&h=48"
		img.Parent = av
	end
	local wn = UI.text(who, (res.WinnerName or "?") .. (if won then " (You)" else ""), { Name = "WinnerName", Font = UI.Head, TextSize = T.Head, Position = UDim2.fromOffset(78, 22), Size = UDim2.new(1, -86, 0, 32) })
	wn.TextWrapped = false
	wn.TextTruncate = Enum.TextTruncate.AtEnd

	-- the specimen line: only the recipient hears about the collection
	local line, lineColor, lineIcon = "", TC.Muted, "info"
	if won and res.Kind ~= "Tutorial" then
		local have = false
		if prof then
			for _, g in prof.Inventory do
				if g.Id == spec.Id then
					have = true
					break
				end
			end
		end
		local waited = os.clock() - openedAt
		if have then
			line, lineColor, lineIcon = "Pet added to your Pet Book!", TC.Green, "check"
			if firstOfKind(prof, spec) then
				newSticker(hero, spec.Id)
			end
			if prof and prof.SavesOff then
				line = "Added (saves are off: not kept after you leave)"
			end
		elseif waited < SECURE_WAIT then
			line, lineColor, lineIcon = "Hatching your pet\u{2026}", TC.Muted, "clock"
			task.delay(SECURE_WAIT - waited + 0.1, render)
		else
			line, lineColor, lineIcon = "Recorded: added the next time you join.", TC.Warn, "clock"
		end
	elseif res.Kind == "Tutorial" then
		-- the practice ends when the geode is found, not when the pile is empty
		line, lineColor, lineIcon = "Practice complete: pet hatched!", TC.Green, "check"
	elseif not won then
		local sp = spec
		local petName = if type(sp) == "table" and sp.Rarity and sp.Mineral then sp.Rarity .. " " .. (Config.Minerals[sp.Mineral] and Config.Minerals[sp.Mineral].Name or "Pet") else "Pet"
		local shells = if mine then " +" .. tostring(mine.RubbleEarned) .. " candy" else ""
		line, lineIcon = (res.WinnerName or "?") .. " hatched a " .. petName .. "! Better luck next egg!" .. shells, "info"
		local prize = mine and mine.Prize
		if type(prize) == "table" and type(prize.Medal) == "string" then
			-- prizes for everyone (shared/HuntFun.Prizes): the medal by eggs finished, already paid by the server
			line, lineColor, lineIcon = string.format("%s medal! +%d coins +%d pet XP", prize.Medal, tonumber(prize.Coins) or 0, tonumber(prize.Xp) or 0), TC.Gold, "crown"
		end
	end
	local rl = UI.frame(col, { Name = "Reward", BackgroundTransparency = 1, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 28) })
	if lineIcon == "check" and UI.OkPicture then
		-- "Pet added to your Pet Book!": the owner's green tick picture
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = UI.OkPicture
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = UDim2.fromOffset(24, 24)
		img.Parent = rl
	else
		UI.icon(rl, lineIcon, 20, { Position = UDim2.fromOffset(2, 2) })
	end
	local seeW = if lineIcon == "check" and won and Results.OnOpenPet and spec and spec.Id then 64 else 0
	UI.text(rl, line, { Name = "RewardText", Font = UI.Bold, TextSize = T.Body, TextColor3 = lineColor, Outline = "Normal", Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -(28 + seeW), 1, 0) })
	if seeW > 0 then
		-- SEE opens the Pet Book on the new pet (the Results tile brings this screen back)
		local id = spec.Id
		UI.button(rl, "SEE", "blue", function()
			if Results.OnOpenPet then
				Results.OnOpenPet(id)
			end
		end, { Name = "SeePet", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(seeW - 12, 28), TextSize = T.Small + 1 }) -- inset: its rim poked past the row
	end
	if mine then
		-- HuntLedger numbers, never recomputed here: earned, sold and stored overlap, so they are never added up
		local tiles = UI.frame(col, { Name = "Tiles", BackgroundTransparency = 1, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 58) })
		UI.list(tiles, Enum.FillDirection.Horizontal, 6)
		local earned = tileStat(tiles, 1, "Earned", "rubble", "Candy earned:", tostring(mine.RubbleEarned), TC.Count)
		local cracked = tileStat(tiles, 2, "Cracked", "egg", "Eggs hatched:", tostring(mine.Processed), TC.Count)
		if countedFor ~= res then
			countedFor = res
			countTile(earned, tonumber(mine.RubbleEarned) or 0, 0.15)
			countTile(cracked, tonumber(mine.Processed) or 0, 0.3)
		end
	end
	-- at most ResultsRules.MaxLines rows (bug #227): Reward, one Stats row, Racers for party hunts; the bag strip and
	-- the pile-left caption were the tiny lines and are gone
	local rows = ResultsRules.lines({ Tutorial = not (prof == nil or prof.OnboardDone), Leader = false, Ready = false, Racers = #res.Members })
	if table.find(rows, "Racers") then
		local present: { [number]: boolean } = {}
		for _, mm in m.Members or {} do
			present[mm.UserId] = mm.Present == true
		end
		-- one line per racer in two columns (name | eggs cracked); your own line in gold
		local board = UI.frame(col, { Name = "Others", BackgroundTransparency = 1, LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
		UI.list(board, Enum.FillDirection.Vertical, 1)
		for i, mem in res.Members do
			local me = mem.UserId == player.UserId
			local r = UI.frame(board, { Name = "Racer_" .. i, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = TC.Gold, BackgroundTransparency = if me then 0.7 else 1 })
			UI.corner(r, 6)
			local col3 = if me then TC.Gold else TC.Muted
			local racerName = UI.text(r, mem.Name .. (if present[mem.UserId] == false then " (left)" else "") .. (if me then " (you)" else ""), { Font = UI.Bold, TextSize = T.Small, TextColor3 = col3, Outline = "Light", Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0.65, -6, 1, 0) })
			racerName.TextWrapped = false
			racerName.TextTruncate = Enum.TextTruncate.AtEnd
			UI.text(r, tostring(mem.Processed) .. " eggs", { Font = UI.Bold, TextSize = T.Small, TextColor3 = col3, Outline = "Light", Position = UDim2.fromScale(0.65, 0), Size = UDim2.new(0.35, -6, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
		end
	end

	-- footer buttons
	local buttons = UI.frame(foot, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	UI.list(buttons, Enum.FillDirection.Horizontal, T.Gap, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	-- plainWords: every caption as fitted text (no word pictures), so a row of mixed buttons shares one font
	local plainWords = false
	local function fb(text: string, style: string, fn: () -> (), w: number, name: string?)
		local btn
		btn = UI.button(buttons, text, style, function()
			UI.pending(btn, "WAIT\u{2026}", 4)
			fn()
		end, { Name = name or text, Size = UDim2.new(w, -T.Gap, 0, 46), TextSize = T.Head, Word = not plainWords })
		return btn
	end
	-- Tutorial footer only while the tutorial is still running: once it is finished or skipped, the ordinary
	-- PLAY AGAIN / LOBBY footer shows (a skipped practice result must not keep offering SKIP TUTORIAL).
	local onboardDone = prof == nil or prof.OnboardDone
	if not onboardDone and prof then
		local ob = prof.Onboard or {}
		-- the core loop as three step chips, so finishing the practice hunt reads as step one of the game, not the end:
		-- FIND (done: the practice pet hatched) -> TRAIN -> FIGHT. Done = green tick, current = gold, later = gray.
		-- (listed first in the column, so a short phone never scrolls them out of sight)
		local tick = "\u{2713} "
		local steps = {
			{ Done = ob.Geode == true, Text = "FIND", Num = "1 " },
			{ Done = false, Text = "TRAIN", Num = "2 " },
			{ Done = false, Text = "FIGHT", Num = "3 " },
		}
		local row = UI.frame(col, { Name = "Stages", BackgroundTransparency = 1, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 32) })
		UI.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		local current = false
		for i, stp in steps do
			local isNow = not stp.Done and not current
			current = current or isNow
			local color = if stp.Done then TC.Green elseif isNow then TC.Gold else TC.Gray
			local chip = UI.chip(row, (if stp.Done then tick else stp.Num) .. stp.Text, color, { LayoutOrder = i, Size = UDim2.new(0.31, -6, 0, 28) })
			local label = chip:FindFirstChild("Text") :: TextLabel?
			if label then
				UI.fit(label, T.Body, T.Tiny) -- the shared chip is caption-sized; these steps are key labels
			end
			if label and isNow then
				-- the current step is a dark pill with gold text and a gold rim (dark-on-gold read as gold-on-gold)
				chip.BackgroundColor3 = TC.PanelEdge
				local rim = chip:FindFirstChildOfClass("UIStroke")
				if rim then
					rim.Color = TC.Gold
					rim.Thickness = 2
				end
				label.TextColor3 = TC.Gold
			end
		end
		plainWords = true
		-- the primary button pushes the loop: back to the lobby with the TRAIN card open for the new pet
		fb(ResultsRules.Label[ResultsRules.primary({ Tutorial = true, Leader = true, Ready = false, Racers = #res.Members })], "gold", function()
			if Results.OnTutorialAction then
				Results.OnTutorialAction("Train")
			end
			act("Return")
		end, 0.4)
		fb("LOBBY", "gray", function()
			act("Return")
		end, 0.3)
		fb("SKIP TUTORIAL", "gray", function()
			Net.event("TutorialAction"):FireServer("Skip")
		end, 0.3)
		UI.sameTextSize(buttons, T.Head)
		return
	end
	-- rematch: the leader starts once everyone tapped PLAY AGAIN; members mark themselves ready
	local present, leader = 0, nil
	for _, mem in m.Members or {} do
		if mem.Present then
			present += 1
			if mem.Leader then
				leader = mem.UserId
			end
		end
	end
	if not leader then
		for _, mem in m.Members or {} do
			if mem.Present then
				leader = mem.UserId
				break
			end
		end
	end
	local amLeader = leader == player.UserId
	local myReady, allReady = false, true
	for _, mem in m.Members or {} do
		if mem.Present and mem.UserId ~= leader and not mem.Rematch then
			allReady = false
		end
		if mem.UserId == player.UserId then
			myReady = mem.Rematch
		end
	end
	local together = State.Teleport and amLeader and present > 1
	if amLeader then
		local rb = fb(ResultsRules.Label.PlayAgain, "gold", function()
			act("StartRematch")
		end, if together then 0.4 else 0.55, "PlayAgain")
		UI.setEnabled(rb, allReady and m.Phase == "Results")
		glow(rb)
	else
		local rb = fb(ResultsRules.Label[ResultsRules.primary({ Tutorial = false, Leader = false, Ready = myReady == true, Racers = present })], if myReady then "green" else "gold", function()
			act("Rematch")
		end, 0.55, "PlayAgain")
		if not myReady then
			glow(rb)
		end
	end
	fb("LOBBY", "gray", function()
		act("Return")
	end, if together then 0.3 else 0.45, "Lobby")
	if together then
		fb("ALL TO LOBBY", "gray", function()
			Net.event("LaunchAction"):FireServer("ReturnAll")
		end, 0.3)
	end
	-- who the rematch is waiting for (party hunts)
	if present > 1 then
		local note = if amLeader and not allReady then "Waiting for everyone to tap PLAY AGAIN." elseif not amLeader and myReady then "Ready. The leader starts the next hunt." elseif not amLeader then "Tap PLAY AGAIN; the leader starts the next hunt." else ""
		if note ~= "" then
			UI.text(col, note, { Name = "Rematch", Font = UI.Bold, TextSize = T.Small, TextColor3 = TC.Count, Outline = "Normal", LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 22) })
		end
	end
end

-- PLAY AGAIN breathes a soft gold glow (the main way forward from this screen)
glow = function(b: GuiButton)
	if UI.Reduced then
		return
	end
	local st = Instance.new("UIStroke")
	st.Name = "Glow"
	st.Color = TC.Gold
	st.Thickness = 0
	st.Transparency = 0.2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	TweenService:Create(st, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4 }):Play()
end

function Results.open()
	RevealView.close()
	local res = State.Results
	-- short landscape screens (a phone): the card takes the whole height it can get, so the stat tiles stay in view
	local size = if UI.isPortrait() then Vector2.new(480, 620) elseif UI.Logical.Y >= 600 then Vector2.new(620, 400) else Vector2.new(580, math.max(360, UI.Logical.Y - 24))
	-- toasts ("New in your Pet Book") wait until the card closes: they covered the FIND / TRAIN / FIGHT chips on a phone
	UI.holdNotices(true)
	local panel, b, _, f = UI.modal("Results", if res then headline(res) else "HUNT COMPLETE!", size, { Dismissable = false, Footer = 62, Fixed = true })
	PanelSkin.dress(panel, "Egg", if res then headline(res) else "HUNT COMPLETE!", { Center = true })
	panelRef = panel
	body = b
	footer = f
	resultsOpen = true
	openedAt = os.clock()
	local conn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "Results" then
			resultsOpen = false
			UI.holdNotices(false)
			body = nil
			footer = nil
			panelRef = nil
			conn:Disconnect()
			State.update("Match") -- the HUD shows the Results tile again
		end
	end)
	render()
	-- confetti over the podium once per round (the winner also had it in the reveal; everyone cheers here)
	if res and confettiFor ~= res and res.Kind ~= "Tutorial" then
		confettiFor = res
		Effects.confetti()
	end
end

function Results.hide()
	RevealView.close()
	if UI.modalOpen() == "Results" then
		UI.closeModal()
	end
end

function Results.start()
	State.Changed.Event:Connect(function(what)
		if what == "Match" or what == "Profile" or what == "Results" then
			render()
		end
	end)
end

local _ = panelRef
return Results
