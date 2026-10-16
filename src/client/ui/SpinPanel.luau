--!strict
-- LUCKY SPIN: the free spin wheel (LaunchPerks.Spin, one spin every 4 hours). A drawn pie wheel of the eight slices
-- in LaunchPerks.Spin.Slices order; SPIN asks the server (RetentionAction "Spin"), the server rolls and pays, and its
-- answer ("Spin", { Slice, Text }: SpinView passes it to SpinPanel.land) spins the wheel onto that slice. The client
-- never picks the prize; the wheel only shows what the server already paid.

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local LaunchPerks = require(Shared.LaunchPerks)
local RobuxConfig = require(Shared.RobuxConfig)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local Effects = require(script.Parent.Parent.Effects)
local Audio = require(script.Parent.Parent.Audio)
local PopupGate = require(script.Parent.Parent.PopupGate)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)
local Juice = require(script.Parent.Juice)

local T = UI.T
local K = Theme.Pet
local SpinPanel = {}

local SLICES = LaunchPerks.Spin.Slices
local N = #SLICES
local STEP = 360 / N
local TURNS = 5 -- whole turns before the wheel settles on the slice
local SPIN_SECONDS = 4.2

-- slice colours: coins gold, luck potions pink, eggs blue / cyan / purple (the slice order alternates them)
local function sliceColor(sl: LaunchPerks.Slice): (Color3, Color3)
	if sl.Kind == "Coins" then
		return Color3.fromRGB(255, 226, 92), Color3.fromRGB(255, 190, 30)
	elseif sl.Kind == "Potion" then
		return Color3.fromRGB(255, 120, 190), Color3.fromRGB(240, 60, 140)
	elseif sl.Egg == "MythicEgg" then
		return Color3.fromRGB(190, 110, 255), Color3.fromRGB(130, 50, 230)
	elseif sl.Egg == "RareEgg" then
		return Color3.fromRGB(90, 180, 255), Color3.fromRGB(30, 120, 240)
	end
	return K.CyanTop, K.Cyan
end

-- short words for a slice on the wheel ("+500", "5 MIN LUCK", "RARE EGG")
local function sliceWord(sl: LaunchPerks.Slice, tierId: string): string
	if sl.Kind == "Coins" then
		return "+" .. UI.num(LaunchPerks.sliceCoins(sl, tierId))
	elseif sl.Kind == "Potion" then
		return (sl.Minutes or 0) .. " MIN LUCK"
	end
	local e = RobuxConfig.egg(sl.Egg)
	return string.upper(if e then e.Name else "EGG")
end

local function tierId(): string
	local p: any = State.Profile
	return RobuxConfig.eggTier(if p then p.UnlockedTiers else nil)
end

local function clock(sec: number): string
	sec = math.max(0, math.ceil(sec))
	local h, m = sec // 3600, sec % 3600 // 60
	return if h > 0 then string.format("%d:%02d:%02d", h, m, sec % 60) else string.format("%d:%02d", m, sec % 60)
end

-- open panel state
local disc: Frame? = nil
local spinBtn: TextButton? = nil
local resultL: TextLabel? = nil
local hintL: TextLabel? = nil
local spinning = false
local pendingDone: (() -> ())? = nil -- ends the SPINNING... state on the button
local closePanel: (() -> ())? = nil
local open = false

-- the prize pill: shown with its line once the wheel lands, hidden (not an empty bar) before and while spinning
local function showResult(line: string?): TextLabel?
	local l = resultL
	if not l then
		return nil
	end
	l.Text = line or ""
	local pill = l.Parent
	if pill and pill:IsA("GuiObject") then
		pill.Visible = line ~= nil
	end
	return l
end

local function readyIn(): number
	local p: any = State.Profile
	local perks = p and p.Perks
	local left = if type(perks) == "table" and type(perks.SpinIn) == "number" then perks.SpinIn else math.huge
	local seen = p and p.__spinSeen
	-- the profile view's SpinIn was true when the view arrived; count down from then
	if type(seen) == "number" then
		left -= os.clock() - seen
	end
	return left
end

-- The wheel: a round CanvasGroup (it clips to its UICorner) holding the spinning disc of eight wedges. Each wedge is
-- the bottom-right quarter of a full-size square masked to the triangle under its diagonal (a UIGradient step), so
-- the quarter reads as a 45 degree pie slice; the square is rotated about the wheel's centre by the slice's angle.
local function buildWheel(parent: Instance, d: number, props: { [string]: any }): CanvasGroup
	local tier = tierId()
	local group = Instance.new("CanvasGroup")
	group.Name = "Wheel"
	group.BackgroundColor3 = K.Ink
	group.BorderSizePixel = 0
	group.Size = UDim2.fromOffset(d, d)
	for k, v in props do
		(group :: any)[k] = v
	end
	UI.corner(group, d // 2)
	group.Parent = parent
	local spin = UI.frame(group, { Name = "Disc", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	for i, sl in SLICES do
		local holder = UI.frame(spin, { Name = "Slice" .. i, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (i - 1) * STEP })
		local top, bottom = sliceColor(sl)
		local wedge = UI.frame(holder, { Name = "Wedge", Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = if i % 2 == 1 then top else bottom })
		UI.corner(wedge, 1) -- (a 1 px round keeps the layout checker's square-corner rule; unseen under the rim)
		local mask = Instance.new("UIGradient")
		mask.Name = "Mask"
		mask.Rotation = -45 -- across the diagonal: the half nearer the top edge stays, the rest goes
		mask.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.499, 1),
			NumberSequenceKeypoint.new(0.501, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
		mask.Parent = wedge
		-- the word along the slice's middle line, read from the centre outwards
		local a = math.rad(STEP / 2)
		local r = 0.33
		local word = PetStyle.words(holder, sliceWord(sl, tier), T.Body, {
			Name = "Word", Font = UI.Head, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + r * math.cos(a), 0.5 + r * math.sin(a)),
			Size = UDim2.fromScale(0.36, 0.11), Rotation = STEP / 2, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3,
			OutlineThick = 2.4,
		})
		word.TextWrapped = false
		UI.fit(word, T.Body, T.MinText)
	end
	-- spoke lines between the slices: a line as wide as the wheel, centred on it, covers two opposite spokes
	for i = 1, N // 2 do
		local line = UI.frame(spin, { Name = "Spoke" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = K.Ink, Rotation = (i - 1) * STEP, ZIndex = 2 })
		line.BorderSizePixel = 0
	end
	-- hub
	local hub = UI.frame(group, { Name = "Hub", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.24, 0.24), BackgroundColor3 = K.White, ZIndex = 4 })
	UI.corner(hub, d) -- round
	PetStyle.edge(hub, K.Ink, 3)
	local star = PetStyle.words(hub, "\u{2605}", T.Title, { Name = "Star", Font = UI.Head, Size = UDim2.fromScale(1, 1), TextColor3 = K.Gold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, OutlineThick = 2 })
	star.TextWrapped = false
	UI.fit(star, T.Title, T.Body)
	-- rim
	local rim = UI.frame(group, { Name = "Rim", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 })
	UI.corner(rim, d // 2)
	PetStyle.edge(rim, K.Ink, 5)
	disc = spin
	return group
end

local function setButton()
	local b = spinBtn
	if not b then
		return
	end
	local label = b:FindFirstChild("Label") :: TextLabel?
	if spinning or b:GetAttribute("Pending") == true then
		return
	end
	local left = readyIn()
	if left <= 0 then
		UI.setEnabled(b, true, "gold")
		if label then
			label.Text = "SPIN!"
		end
	else
		UI.setEnabled(b, false)
		if label then
			label.Text = "NEXT SPIN IN " .. clock(left)
		end
	end
end

-- Spins the disc onto slice `sliceId` (the server's roll) and then shows `text` as the prize.
function SpinPanel.land(sliceId: string, text: string)
	local d = disc
	if not d or not open then
		return
	end
	local index = 1
	for i, sl in SLICES do
		if sl.Id == sliceId then
			index = i
		end
	end
	spinning = true
	if pendingDone then
		pendingDone()
		pendingDone = nil
	end
	showResult(nil)
	if hintL then
		hintL.Text = "Spinning..."
	end
	-- the pointer sits at the top (-90 degrees): the slice's middle line must end up there
	local middle = (index - 1) * STEP + STEP / 2
	local target = -90 - middle
	local from = d.Rotation % 360
	target = target - 360 * math.floor((target - from) / 360) -- the first target angle past `from`
	target += 360 * TURNS
	Audio.play("UIWhooshSoft", { Key = "ui:spin" })
	if UI.Reduced then
		d.Rotation = target
	else
		local tw = TweenService:Create(d, TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Rotation = target })
		tw:Play()
		tw.Completed:Wait()
	end
	spinning = false
	if not open then
		return
	end
	-- the pointer bounces as the wheel stops
	local box = d.Parent and d.Parent.Parent
	local pointer = if box then box:FindFirstChild("Pointer") else nil
	if pointer then
		UI.pop(pointer, 1.6)
	end
	local l = showResult(LaunchPerks.spinWon(text))
	if l then
		UI.pop(l, 0.6)
	end
	if hintL then
		hintL.Text = "Come back in 4 hours for another free spin!"
	end
	Effects.confetti() -- (no banner: the prize pill says it, and a banner covered the wheel)
	setButton()
end

function SpinPanel.isOpen(): boolean
	return open
end

local asked = 0
-- The server said no ("SpinNo": too early, or no spin to give): the button comes back and the words say why.
function SpinPanel.refuse(why: string)
	if pendingDone then
		pendingDone()
		pendingDone = nil
	end
	asked = 0
	local b = spinBtn
	if b then
		Juice.nope(b)
	end
	if hintL then
		hintL.Text = why
	end
	setButton()
end

local function onSpin()
	if spinning or readyIn() > 0 or os.clock() - asked < 1.5 then
		return
	end
	asked = os.clock()
	local b = spinBtn
	if b then
		pendingDone = UI.pending(b, "SPINNING...", 6)
	end
	Net.event("RetentionAction"):FireServer("Spin")
end

function SpinPanel.open()
	local short = UI.Logical.Y < 420
	local portrait = UI.isPortrait()
	-- (upright: a shorter panel so the footer stays above Roblox's JUMP button)
	local w, h = 580, if portrait then math.min(600, UI.Logical.Y - 200) elseif short then math.max(300, UI.Logical.Y - 24) else 400
	local panel, body, close, footer = UI.modal("Spin", "LUCKY SPIN", Vector2.new(w, h), { Fixed = true, Footer = 64 })
	open = true
	closePanel = close
	-- toasts wait while the wheel is up (Studio 2026-10-15: a free-egg "You hatched..." toast spoiled the prize mid-spin
	-- and toasts covered the panel's title); they show as soon as the panel closes
	PopupGate.hold("SpinPanel", true)
	local bodyH = h - 64 - 70
	-- landscape: the wheel on the left with its pointer, the words on the right; upright phone: wheel above words
	local d = if portrait then math.clamp(math.floor(bodyH * 0.5), 150, 230) else math.clamp(math.floor(bodyH - 8), 150, 250)
	local wheelBox = UI.frame(body, { Name = "WheelBox", Size = if portrait then UDim2.new(1, 0, 0, d + 20) else UDim2.fromOffset(d + 16, bodyH), BackgroundTransparency = 1 })
	buildWheel(wheelBox, d, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6) })
	local pointer = PetStyle.words(wheelBox, "\u{25BC}", 34, { Name = "Pointer", Font = UI.Head, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -d / 2 - 14), Size = UDim2.fromOffset(44, 34), TextColor3 = K.Gold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8, OutlineThick = 2.6 })
	pointer.TextWrapped = false
	local info = UI.frame(body, { Name = "Info", Position = if portrait then UDim2.fromOffset(0, d + 28) else UDim2.fromOffset(d + 28, 0), Size = if portrait then UDim2.new(1, 0, 1, -(d + 28)) else UDim2.new(1, -(d + 28), 1, 0), BackgroundTransparency = 1 })
	UI.list(info, Enum.FillDirection.Vertical, 8)
	local title = PetStyle.words(info, "FREE SPIN EVERY 4 HOURS!", T.Head, { Name = "Line", Font = UI.Head, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, TextColor3 = K.QuestTitle, OutlineColor = K.TitleEdge, OutlineThick = 2.4 })
	title.TextWrapped = true
	UI.fit(title, T.Head, T.MinText)
	local blurb = UI.text(info, "Win coins, luck potions or a free egg. Coins grow with your best zone.", { Name = "Blurb", Font = UI.Bold, TextSize = T.Body, TextColor3 = K.TitleEdge, Outline = false, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 2 })
	blurb.TextWrapped = true
	UI.fit(blurb, T.Body, T.MinText)
	-- the prize line: a glossy lime pill, only once the wheel lands (Studio 2026-10-15: an empty green bar before)
	local pill = UI.frame(info, { Name = "Result", Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = K.Lime, LayoutOrder = 3, Visible = false })
	PetStyle.round(pill, 999)
	PetStyle.vgrad(pill, K.LimeTop, K.Lime)
	PetStyle.edge(pill, K.LimeEdge, 2.5)
	local won = PetStyle.words(pill, "", T.Head, { Name = "Won", Font = UI.Head, Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), TextXAlignment = Enum.TextXAlignment.Center, OutlineColor = K.LimeEdge, OutlineThick = 2.4 })
	won.TextWrapped = false
	UI.fit(won, T.Head, T.MinText)
	resultL = won
	local hint = UI.text(info, "Tap SPIN!", { Name = "Hint", Font = UI.Bold, TextSize = T.Body, TextColor3 = K.TitleEdge, Outline = false, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4 })
	hint.TextWrapped = false
	UI.fit(hint, T.Body, T.MinText)
	hintL = hint
	if footer then
		spinBtn = UI.button(footer, "SPIN!", "gold", onSpin, { Name = "SpinButton", Size = UDim2.new(1, 0, 1, 0), TextSize = T.Head + 2 })
	end
	setButton()
	-- the countdown ticks while the panel is open
	task.spawn(function()
		while open and panel.Parent do
			task.wait(1)
			if open then
				setButton()
			end
		end
	end)
	local conn: RBXScriptConnection
	conn = UI.ModalChanged.Event:Connect(function(name)
		if name ~= "Spin" then
			PopupGate.hold("SpinPanel", false)
			open = false
			disc, spinBtn, resultL, hintL, closePanel = nil, nil, nil, nil, nil
			conn:Disconnect()
		end
	end)
	-- a new profile view (the clock restarted) refreshes the button
	State.Changed.Event:Connect(function(what)
		if what == "Profile" and open then
			local p: any = State.Profile
			if p then
				p.__spinSeen = os.clock()
			end
			setButton()
		end
	end)
	local p: any = State.Profile
	if p and p.__spinSeen == nil then
		p.__spinSeen = os.clock()
	end
end

function SpinPanel.close()
	if closePanel then
		closePanel()
	end
end

return SpinPanel
