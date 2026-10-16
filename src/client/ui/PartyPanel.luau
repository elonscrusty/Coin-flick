--!strict
-- START HUNT and PARTY (boards 8 and 9, additional 6-8), all through the real PartyService (PartyAction):
--   no party:  START HUNT "One pile. One geode." with SOLO HUNT (START) and PARTY HUNT (CREATE PARTY); while the
--              request is on its way the cards give way to "Starting hunt..." (no double start). The pending state
--              stays on the start view even when the server's solo party arrives before the hunt does, ends when
--              the hunt arrives or the server refuses (a warning), and gives up after START_WAIT seconds with a
--              notice (the server still refuses a second start while one is running).
--   a party:   PARTY n/4 with Members (avatar, name, leader crown, the server's ready state or blocker, empty slots,
--              kick for the leader), the hunt tier, READY, START HUNT (leader only, enabled when the server says it
--              can start) and LEAVE; Invite (leader): eligible lobby players only, no invites once the party is full.
--   invitations: a dialog with the inviter, ACCEPT / DECLINE; an invite that expires or vanishes closes it with
--              "Party invitation expired."
-- The server validates every action; refusals arrive as notifications.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local Juice = require(script.Parent.Juice)
local HudArt = require(script.Parent.HudArt)
local PanelSkin = require(script.Parent.PanelSkin)

local T = UI.T
local TC = Theme.Color
local PartyPanel = {}

local player = Players.LocalPlayer
local open = false
local body: Frame? = nil
local panelRef: Frame? = nil
local view = "Members" -- party tabs: Members | Invite
local openedWithParty = false -- the shell (title / subtitle) was built for a party view
local starting = false -- a Solo / Start request is on its way
local startingFrom = "" -- "Solo" (start view) or "Start" (party view)
local startingSeq = 0
local START_WAIT = 8
local sentInvite: { [number]: number } = {} -- userId -> os.clock() of the last invite sent (button shows SENT)

-- Preview seam (tools/preview/scenes/party.luau): with Hold set, requests wait in Held instead of going to the
-- server, so the pending state can be seen and the double-start guard counted offline. Never set in the game.
PartyPanel.Hold = false
PartyPanel.Held = {} :: { { any } }

local function act(action: string, arg: any?)
	if PartyPanel.Hold then
		table.insert(PartyPanel.Held, { action, arg } :: { any })
		return
	end
	Net.event("PartyAction"):FireServer(action, arg)
end

-- Sends what the preview held back.
function PartyPanel.release()
	PartyPanel.Hold = false
	local held = PartyPanel.Held
	PartyPanel.Held = {}
	for _, h in held do
		act(h[1], h[2])
	end
end

function PartyPanel.isStarting(): boolean
	return starting
end

local render

local function setStarting(on: boolean, from: string?)
	starting = on
	startingSeq += 1
	if on then
		startingFrom = from or "Solo"
		local mine = startingSeq
		task.delay(START_WAIT, function()
			if starting and startingSeq == mine then
				starting = false
				render()
				UI.notify("The hunt did not start. Try again.", "info", { Tag = "start-timeout" })
			end
		end)
	end
	render()
end

-- Ends a pending start (the hunt arrived or the server refused); rebuilds the shell if the view changed.
local function endStarting()
	if not starting then
		return
	end
	starting = false
	startingSeq += 1
	render()
end

-- Avatar headshot from Roblox's own thumbnail service (rbxthumb), with the drawn user glyph behind it.
local function avatar(parent: Instance, userId: number, size: number, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Name = "Avatar", Size = UDim2.fromOffset(size, size), BackgroundColor3 = TC.Inset })
	UI.apply(f, props)
	UI.corner(f, T.RadiusSm)
	UI.stroke(f, TC.Outline, 1.5)
	UI.icon(f, "user", math.floor(size * 0.8), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	if userId > 0 then
		local img = Instance.new("ImageLabel")
		img.Name = "Headshot"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=48&h=48"
		img.Parent = f
		UI.corner(img, T.RadiusSm)
	end
	return f
end

local function clear(b: Instance)
	for _, c in b:GetChildren() do
		if not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

-- Pending invitations shown at the top of the panel too (the dialog is the main path).
local function inviteRows(b: Frame, y: number): number
	for _, inv in State.Invites do
		local row = UI.card(b, "inset", { Name = "Invite", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 52) })
		UI.text(row, inv.From .. " invited you", { Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0) })
		local ab
		ab = UI.button(row, "ACCEPT", "gold", function()
			UI.pending(ab, "JOINING\u{2026}", 4)
			act("Accept", inv.PartyId)
		end, { Size = UDim2.fromOffset(100, T.Touch), Position = UDim2.new(1, -212, 0, 4), TextSize = T.Body })
		UI.button(row, "DECLINE", "gray", function()
			act("Decline", inv.PartyId)
		end, { Size = UDim2.fromOffset(100, T.Touch), Position = UDim2.new(1, -106, 0, 4), TextSize = T.Body })
		y += 58
	end
	return y
end

-- A card picture (HudArt slot) as big as its box allows, kept square and centred.
local function picture(p: Instance, slot: string)
	local img = HudArt.image(p, slot, 64, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9) })
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = img
end

-- Board 8: the two ways to hunt.
local function renderStart(b: Frame)
	if starting then
		-- additional board 8: a compact pending card instead of an empty menu
		if panelRef then
			UI.fitModal(panelRef, Vector2.new(420, 200 + 54 * #State.Invites))
		end
		local y0 = inviteRows(b, 0)
		UI.loadingState(b, "Starting hunt\u{2026}", { Name = "Starting", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, y0 / 2) })
		return
	end
	if panelRef then
		UI.fitModal(panelRef, Vector2.new(560, if UI.isPortrait() then 520 else 360))
	end
	local y = inviteRows(b, 0)
	local prof = State.Profile
	local practice = prof ~= nil and prof.TutorialStep == 0
	local portrait = UI.isPortrait()
	local cards = UI.frame(b, { Name = "Choices", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -y) })
	UI.list(cards, if portrait then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal, T.Gap)
	local function card(order: number, name: string, title: string, sub: string, btnText: string, pic: (Instance) -> (), onClick: () -> ())
		-- sky card (owner mockup reference/ui/start_hunt/mockup.png): picture, title, one line, gold button
		local box = PanelSkin.box(cards, name, PanelSkin.SKY, PanelSkin.SKY_EDGE, 3, { LayoutOrder = order, Size = if portrait then UDim2.new(1, 0, 0.5, -4) else UDim2.new(0.5, -4, 1, 0) })
		-- the owner's blue card picture (DAILY tile_blue) until a dedicated hunt_card exists
		local _ = HudArt.skin(box, "hunt_card", 220) or HudArt.skin(box, "tile_blue", 220)
		local c = PanelSkin.content(box)
		UI.pad(c, 8, 8)
		-- the caption line is 26 px tall: its word picture is about 9:1, so an 18 px box drew it as a thin strip
		local SUB_H = 26
		-- a clear gap between the caption line and the button (they touched, Studio #186)
		local GAP = 10
		local p = UI.frame(c, { Name = "Picture", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -(28 + SUB_H + 46 + GAP)) })
		pic(p)
		local tl = UI.text(c, title, { Name = "Title", Font = UI.Head, TextSize = T.Head + 2, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(46 + GAP + SUB_H)), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
		local sl = UI.text(c, sub, { Name = "Sub", Font = UI.Bold, TextSize = T.Body + 1, Outline = "Normal", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(46 + GAP)), Size = UDim2.new(1, 0, 0, SUB_H), TextXAlignment = Enum.TextXAlignment.Center })
		sl.TextWrapped = false
		local bt = UI.button(c, btnText, "gold", function()
			if starting then
				return
			end
			onClick()
		end, { Name = if order == 1 then "StartSolo" else "CreateParty", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 46), TextSize = T.Head + 2 })
		HudArt.skin(bt, "btn_yellow", 46)
		-- owner's word pictures (reference/ui/start_hunt/) where one matches; other lines keep the text
		HudArt.word(tl)
		HudArt.word(sl, 0.9)
		local bl = bt:FindFirstChild("Label") :: TextLabel?
		if bl then
			HudArt.word(bl, 0.8)
		end
		return bt
	end
	card(1, "Solo", if practice then "PRACTICE HUNT" else "SOLO HUNT", if practice then "A small pile to learn the ropes" else "Find the pet yourself", "START", function(p)
		picture(p, if HudArt.has("EggPink") then "EggPink" else "Egg")
	end, function()
		if starting then
			return
		end
		setStarting(true, "Solo")
		act("Solo")
	end)
	card(2, "Party", "PARTY HUNT", "Up to " .. Config.Party.MaxSize .. " players, one pet", "CREATE PARTY", function(p)
		picture(p, "Party")
	end, function()
		act("Create")
	end)
end

-- One member row (board 9).
local function memberRow(parent: Instance, order: number, mem: any?, isLeader: boolean, solo: boolean)
	local row = UI.card(parent, "inset", { Name = if mem then "Member_" .. order else "Empty_" .. order, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 40) })
	if not mem then
		avatar(row, 0, 30, { Position = UDim2.fromOffset(38, 5), BackgroundTransparency = 1 })
		UI.text(row, "Empty Slot", { Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Faint, Outline = "Light", Position = UDim2.fromOffset(78, 0), Size = UDim2.new(1, -160, 1, 0) })
		UI.text(row, "---", { Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Faint, Outline = "Light", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(60, 40), TextXAlignment = Enum.TextXAlignment.Right })
		return
	end
	if mem.Leader then
		UI.icon(row, "crown", 24, { Position = UDim2.fromOffset(8, 8) })
	else
		UI.text(row, tostring(order), { Font = UI.Head, TextSize = T.Head, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(24, 40), TextXAlignment = Enum.TextXAlignment.Center })
	end
	avatar(row, mem.UserId, 30, { Position = UDim2.fromOffset(38, 5) })
	local you = mem.UserId == player.UserId
	local name = UI.text(row, mem.Name .. (if mem.Leader then "  (Leader)" elseif you then "  (You)" else ""), { Name = "Name", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(78, 0), Size = UDim2.new(1, -(78 + 120), 1, 0) })
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local blockers = mem.Blockers or {}
	local status = if solo then "Solo" elseif #blockers > 0 then blockers[1] elseif mem.Ready then "Ready" else "Not ready"
	local col = if solo then TC.Muted elseif #blockers > 0 then TC.Warn elseif mem.Ready then TC.Green else TC.Count
	local kick = isLeader and not you
	local st = UI.text(row, status, { Name = "State", Font = UI.Bold, TextSize = T.Body, TextColor3 = col, Outline = "Normal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, if kick then -54 else -12, 0, 0), Size = UDim2.fromOffset(110, 40), TextXAlignment = Enum.TextXAlignment.Right })
	st.TextWrapped = false
	if kick then
		UI.closeButton(row, function()
			-- a mis-tap must not remove a friend: ask first
			UI.confirm({
				Name = "PartyKick",
				Title = "Remove " .. mem.Name .. "?",
				Message = mem.Name .. " leaves your party.",
				Icon = "party",
				Confirm = "REMOVE",
				Cancel = "KEEP",
				Style = "red",
				OnConfirm = function()
					act("Kick", mem.UserId)
				end,
			})
		end, { Name = "Kick", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(T.Touch, T.Touch) })
	end
end

-- Eligible players to invite: in this server, not in the party, not in a hunt.
local function eligible(party): { Player }
	local inParty = {}
	for _, mem in party.Members do
		inParty[mem.UserId] = true
	end
	local out = {}
	for _, p in Players:GetPlayers() do
		if not inParty[p.UserId] and p ~= player and not p:GetAttribute("MatchKey") then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	return out
end

local function renderParty(b: Frame, party: { [string]: any })
	local prof = State.Profile
	local isLeader = party.Leader == player.UserId
	local me
	for _, mem in party.Members do
		if mem.UserId == player.UserId then
			me = mem
		end
	end
	if panelRef then
		UI.fitModal(panelRef, Vector2.new(560, if UI.isPortrait() then 620 else 400))
		local title = panelRef:FindFirstChild("Header") and (panelRef :: any).Header:FindFirstChild("Title")
		if title then
			title.Text = "PARTY " .. #party.Members .. "/" .. party.Max
		end
	end
	if not isLeader then
		view = "Members"
	end
	local y = inviteRows(b, 0)
	if isLeader then
		UI.tabs(b, { { "Members", "Members" }, { "Invite", "Invite" } }, view, function(id)
			view = id
			render()
		end, { Position = UDim2.fromOffset(0, y) })
		y += T.Tab + 6
	end
	local footH = 50
	if view == "Invite" and isLeader then
		local full = #party.Members >= party.Max
		local list = UI.scroller(b, { Name = "InviteList", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -(y + 26)) })
		UI.pad(list, 2, 2)
		UI.list(list, Enum.FillDirection.Vertical, 6)
		local people = eligible(party)
		if full then
			UI.text(list, "The party is full.", { Name = "Full", Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Muted, Outline = "Normal", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
		elseif #people == 0 then
			UI.text(list, "Nobody else in the lobby can join right now.", { Name = "Nobody", Font = UI.Bold, TextSize = T.Body, TextColor3 = TC.Muted, Outline = "Normal", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
		else
			for i, p in people do
				local row = UI.card(list, "inset", { Name = "Player_" .. p.UserId, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 50) })
				avatar(row, p.UserId, 38, { Position = UDim2.fromOffset(8, 6) })
				local nm = UI.text(row, p.DisplayName, { Font = UI.Bold, TextSize = T.Head - 2, Outline = "Normal", Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -(56 + 130), 1, 0) })
				nm.TextWrapped = false
				nm.TextTruncate = Enum.TextTruncate.AtEnd
				local recent = sentInvite[p.UserId] and os.clock() - sentInvite[p.UserId] < 8
				local ib = UI.button(row, if recent then "SENT" else "INVITE", "gold", function()
					sentInvite[p.UserId] = os.clock()
					act("Invite", p.UserId)
					render()
					task.delay(8.1, render)
				end, { Name = "Invite", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(112, T.Touch), TextSize = T.Body + 1 })
				if recent then
					UI.setEnabled(ib, false)
				end
			end
		end
		UI.text(b, "Party size: " .. #party.Members .. "/" .. party.Max, { Name = "Size", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
		return
	end
	-- Members
	local solo = false
	local tierH = 36
	local reasonH = 24
	local list = UI.scroller(b, { Name = "Members", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -(y + tierH + reasonH + footH + 12)) })
	UI.pad(list, 2, 2)
	UI.list(list, Enum.FillDirection.Vertical, 5)
	for i = 1, party.Max do
		memberRow(list, i, party.Members[i], isLeader, solo)
	end
	-- hunt tier (the leader picks; locked tiers are visible but not pickable)
	local tiers = UI.scroller(b, { Name = "Tiers", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(footH + reasonH + 8)), Size = UDim2.new(1, 0, 0, tierH), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0 })
	UI.list(tiers, Enum.FillDirection.Horizontal, 6)
	if party.Tutorial then
		UI.text(tiers, "Practice pile \u{b7} " .. party.TierRocks .. " eggs", { Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Size = UDim2.fromOffset(260, tierH) })
	else
		for i, tid in Config.TierOrder do
			local tier = Config.Tiers[tid]
			local unlocked = prof and prof.UnlockedTiers[tid]
			local sel = party.Tier == tid
			local tb = UI.button(tiers, tier.Name, if sel then "gold" else "gray", function()
				if isLeader and not sel then
					act("Tier", tid)
				end
			end, { Name = "Tier_" .. tid, Size = UDim2.fromOffset(104, tierH), TextSize = T.Body, LayoutOrder = i })
			if not sel and (not isLeader or not unlocked) then
				UI.setEnabled(tb, false)
			end
			if not unlocked and not sel then
				tb.Activated:Connect(function()
					Juice.nope(tb) -- a locked zone shakes "no" when tapped
				end)
			end
		end
	end
	local reason = if starting then "Starting hunt\u{2026}" elseif not isLeader then "The leader picks the tier and starts the hunt." else (party.Reason or "Everyone is ready. Start when you like!")
	if isLeader and not starting and me and not me.Ready then
		reason = "Tap READY, then START HUNT." -- "Waiting for <you> to ready" read as someone else holding things up
	end
	UI.text(b, reason, { Name = "Reason", Font = UI.Bold, TextSize = T.Body + 1, TextColor3 = if starting then TC.Gold elseif party.CanStart then TC.Green else TC.Muted, Outline = "Normal", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(footH + 4)), Size = UDim2.new(1, 0, 0, reasonH), TextXAlignment = Enum.TextXAlignment.Center })
	-- footer: READY, START HUNT (leader), LEAVE
	local foot = UI.frame(b, { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, footH - 4) })
	UI.list(foot, Enum.FillDirection.Horizontal, 8)
	-- one main button that changes with the state (READY and a grey WAITING FOR READY side by side read as two
	-- choices, #235): READY until you are ready; then the leader's turns into START HUNT once the server says the
	-- party can start, or CANCEL READY while it waits on someone (the reason line above says who)
	local ready = me and me.Ready
	if isLeader and ready then
		local waiting = not party.CanStart and string.find(party.Reason or "", "^Waiting for") ~= nil
		local start
		if waiting and not starting then
			start = UI.button(foot, "CANCEL READY", "gray", function()
				act("Ready", false)
			end, { Name = "Ready", Size = UDim2.new(0.68, -6, 1, 0), TextSize = T.Head, LayoutOrder = 1 })
		else
			start = UI.button(foot, if starting then "STARTING\u{2026}" else "START HUNT", "gold", function()
				if starting then
					return
				end
				setStarting(true, "Start")
				act("Start")
			end, { Name = "Start", Size = UDim2.new(0.68, -6, 1, 0), TextSize = T.Head, LayoutOrder = 1 })
			UI.setEnabled(start, party.CanStart and not starting)
		end
	else
		UI.button(foot, if ready then "NOT READY" else "READY", if ready then "gray" else "gold", function()
			act("Ready", not ready)
		end, { Name = "Ready", Size = UDim2.new(if isLeader then 0.68 else 0.6, -6, 1, 0), TextSize = T.Head, LayoutOrder = 1 })
	end
	UI.button(foot, "LEAVE", "gray", function()
		act("Leave")
	end, { Name = "Leave", Size = UDim2.new(if isLeader then 0.32 else 0.4, -6, 1, 0), TextSize = T.Head, LayoutOrder = 3 })
end

function render()
	if not open or not body then
		return
	end
	local b = body :: Frame
	clear(b)
	local party = State.Party
	if party and not (starting and startingFrom == "Solo") then
		renderParty(b, party)
	else
		if panelRef then
			local h = panelRef:FindFirstChild("Header")
			local t = h and h:FindFirstChild("Title")
			if t and t:IsA("TextLabel") then
				t.Text = "START HUNT"
			end
		end
		renderStart(b)
	end
end

function PartyPanel.open()
	view = "Members"
	local party = State.Party
	openedWithParty = party ~= nil
	local panel, b = UI.modal("Party", if party then "PARTY" else "START HUNT", Vector2.new(560, 360), { Fixed = true, Subtitle = if party then nil else "One pile. One pet." })
	local egg = if HudArt.has("EggPink") then "EggPink" else "Egg"
	PanelSkin.dress(panel, if party then "Party" else egg, if party then "PARTY" else "START HUNT", { Center = true, Tiles = not party })
	-- "One pile. One pet." in a taller box (its 6.5:1 word picture drew tiny in the modal's 24 px line); it still ends
	-- where the body starts (header 54 + 22)
	local subtitle = panel:FindFirstChild("Subtitle") :: TextLabel?
	if subtitle then
		subtitle.Position = UDim2.fromOffset(16, 42)
		subtitle.Size = UDim2.new(1, -32, 0, 34)
		subtitle.TextWrapped = false
		UI.fit(subtitle, T.Head, T.MinText)
	end
	body = b
	panelRef = panel
	open = true
	local conn
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "Party" then
			open = false
			body = nil
			panelRef = nil
			conn:Disconnect()
		end
	end)
	render()
	return function()
		if open then
			UI.closeModal()
		end
	end
end

-- Invitation dialogs ------------------------------------------------------------------------------
local dialogFor: string? = nil -- PartyId the dialog is about
local dialogClose: (() -> ())? = nil
local answered = false
local seen: { [string]: boolean } = {}

local function inviteDialog(inv: { [string]: any })
	dialogFor = inv.PartyId
	answered = false
	dialogClose = UI.confirm({
		Name = "PartyInvite",
		Title = "PARTY INVITE",
		Message = inv.From .. " invited you.",
		Icon = "party",
		Confirm = "ACCEPT",
		Cancel = "DECLINE",
		OnConfirm = function()
			answered = true
			dialogFor = nil
			act("Accept", inv.PartyId)
		end,
		OnCancel = function()
			answered = true
			dialogFor = nil
			act("Decline", inv.PartyId)
		end,
	})
end

local function checkInvites()
	local present: { [string]: boolean } = {}
	for _, inv in (State.Invites or {}) :: { any } do
		present[inv.PartyId] = true
	end
	-- the invite on screen expired or vanished
	if dialogFor and not present[dialogFor] then
		local was = dialogFor
		dialogFor = nil
		if dialogClose and UI.dialogOpen() == "PartyInvite" then
			dialogClose()
		end
		if not answered and not (State.Party and State.Party.Id == was) then
			UI.notify("Party invitation expired.", "info")
		end
	end
	for pid in seen do
		if not present[pid] then
			seen[pid] = nil
		end
	end
	if State.Match or State.Party then
		return
	end
	for _, inv in (State.Invites or {}) :: { any } do
		if not seen[inv.PartyId] then
			seen[inv.PartyId] = true
			if dialogFor == nil and UI.dialogOpen() == nil then
				inviteDialog(inv)
			end
		end
	end
end

function PartyPanel.start()
	State.Changed.Event:Connect(function(what)
		if what == "Party" then
			checkInvites()
		end
		if what == "Match" and State.Match and starting then
			endStarting() -- the hunt began
		end
		local soloPending = starting and startingFrom == "Solo"
		if what == "Party" and open and not soloPending and (State.Party ~= nil) ~= openedWithParty and not State.Match then
			PartyPanel.open() -- start view <-> party view: rebuild the shell (title, subtitle)
			return
		end
		if what == "Party" or what == "Profile" then
			render()
		end
	end)
	-- a refusal ends a pending start at once
	UI.Notice.Event:Connect(function(_, kind)
		if kind == "warn" and starting then
			endStarting()
			-- a refused solo start leaves a party of one behind: show it in its own shell
			if open and (State.Party ~= nil) ~= openedWithParty and not State.Match then
				PartyPanel.open()
			end
		end
	end)
	Players.PlayerAdded:Connect(function()
		task.defer(render)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(render)
	end)
end

return PartyPanel
