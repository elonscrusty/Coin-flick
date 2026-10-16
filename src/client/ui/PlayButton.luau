--!strict
-- Lobby PLAY button and hunt-queue card (left HUD column, under the cash). Lobby only.
--   not queued: a big PLAY button (shows "2/4" when an open queue is already counting down)
--   queued:     "HUNT IN 12s" with the player count and LEAVE
-- It only shows what the server sends (LaunchEvent "Queue") and sends intents (PartyAction "Queue" / "Unqueue").
-- Walking onto the lobby portal pads joins the same queue on the server.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local HudArt = require(script.Parent.HudArt)

local T = UI.T
local TC = Theme.Color
local PlayButton = {}

local WIDTH = 172 -- same width as the TOWER row (Hud LOBBY_W)
local HEIGHT = 70 -- PLAY and the queue card share it, so the column never jumps when one replaces the other
local LEAVE_W = 64
type QView = { Count: number, Max: number, StartsAt: number, Remaining: number }

local root: Frame? = nil
local playBtn: TextButton? = nil
local card: Frame? = nil
local countText: TextLabel? = nil
local subText: TextLabel? = nil
local mine: QView? = nil
local open: QView? = nil
local pendingUntil = 0 -- a join / leave request is on its way (no double taps)
local pulse: Tween? = nil -- "STARTING" breathes while the server builds the hunt (it reads as working, not stuck)

local function act(action: string)
	if os.clock() < pendingUntil then
		return
	end
	pendingUntil = os.clock() + 0.6
	Net.event("PartyAction"):FireServer(action)
end

local function secondsLeft(v: QView): number
	return math.max(0, math.ceil(v.StartsAt - Workspace:GetServerTimeNow()))
end

local function setPulse(on: boolean)
	local ct = countText :: TextLabel
	if on and not pulse and not UI.Reduced then
		local tw = TweenService:Create(ct, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.45 })
		pulse = tw
		tw:Play()
	elseif not on and pulse then
		(pulse :: Tween):Cancel()
		pulse = nil
		ct.TextTransparency = 0
	end
end

local function refresh()
	local r = root
	if not r then
		return
	end
	-- gone the moment the server puts us in a hunt (MatchKey), before the hunt state arrives
	local lobby = State.Match == nil and Players.LocalPlayer:GetAttribute("MatchKey") == nil
	r.Visible = lobby
	if not lobby then
		setPulse(false)
		return
	end
	local m = mine
	;(card :: Frame).Visible = m ~= nil
	;(playBtn :: TextButton).Visible = m == nil
	if m then
		local left = secondsLeft(m)
		-- while starting, the dots step every quarter second (the refresh loop) and the word breathes
		local dots = string.rep(".", 1 + math.floor(os.clock() * 4) % 3)
		;(countText :: TextLabel).Text = if left > 0 then "HUNT IN " .. left .. "s" else "STARTING" .. dots
		setPulse(left <= 0)
		;(subText :: TextLabel).Text = "(" .. m.Count .. "/" .. m.Max .. ") players"
	else
		setPulse(false)
		local label = (playBtn :: TextButton):FindFirstChild("Label") :: TextLabel?
		local o = open
		if label then
			label.Text = if o then "PLAY  " .. o.Count .. "/" .. o.Max else "PLAY"
		end
	end
end

local function build()
	local screen = UI.screen()
	-- Sit in the HUD's left column list when it exists (so nothing overlaps); else a fixed spot under the cash.
	local left = screen:FindFirstChild("Left", true)
	local r = UI.frame(left or screen, {
		Name = "PlayQueue",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 50,
	})
	if not left then
		r.Position = UDim2.fromOffset(T.Edge, T.Edge + 80)
	end
	root = r
	-- big gold PLAY (lobby mockup): egg picture, title, and what PLAY is (the main game) so it never reads like TOWER
	playBtn = HudArt.bigButton(r, {
		Name = "Play", Style = "gold", Art = "Egg", Skin = "btn_yellow", Title = "PLAY", Sub = "Egg hunt race", Width = WIDTH, Height = HEIGHT,
		OnClick = function()
			act("Queue")
		end,
	})
	UI.wiggle(playBtn :: TextButton)
	-- queue card: count and players on the left, LEAVE on the right, PLAY's height
	local c = UI.card(r, "hud", { Name = "QueueCard", Size = UDim2.fromOffset(WIDTH, HEIGHT), Visible = false })
	card = c
	local textW = -(LEAVE_W + 18)
	countText = UI.text(c, "", { Name = "Count", Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Gold, Outline = "Normal", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, textW, 0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	;(countText :: TextLabel).TextWrapped = false
	UI.fit(countText :: TextLabel, T.Body, T.MinText) -- short words, and they shrink before they clip on small phones
	subText = UI.text(c, "", { Name = "Players", Font = UI.Bold, TextSize = T.Small, Outline = "Normal", Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, textW, 0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	;(subText :: TextLabel).TextWrapped = false
	UI.fit(subText :: TextLabel, T.Small, T.MinText)
	UI.button(c, "LEAVE", "gray", function()
		act("Unqueue")
	end, { Name = "Leave", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(LEAVE_W, HEIGHT - 16), TextSize = T.Small })
	refresh()
end

function PlayButton.onQueue(data: any)
	if type(data) ~= "table" then
		return
	end
	mine = data.Mine
	open = data.Open
	pendingUntil = 0
	refresh()
end

function PlayButton.start()
	build()
	Net.event("LaunchEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "Queue" then
			PlayButton.onQueue(data)
		end
	end)
	State.Changed.Event:Connect(function(what)
		if what == "Match" then
			refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("MatchKey"):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if mine then
				refresh()
			end
		end
	end)
	Net.event("PartyAction"):FireServer("Sync") -- the server answers with the queue state too
end

-- Lobby HUD v2 PLAY (ui/LobbyHudV2): one tap joins the queue, a tap while queued leaves it.
function PlayButton.tap()
	act(if mine then "Unqueue" else "Queue")
end

-- The queue line over the v2 PLAY button, or nil when there is nothing to say.
function PlayButton.status(): string?
	local m, o = mine, open
	if m then
		local left = secondsLeft(m)
		return (if left > 0 then "HUNT IN " .. left .. "s" else "STARTING...") .. "  \u{b7}  " .. m.Count .. "/" .. m.Max .. " players  \u{b7}  tap PLAY to leave"
	elseif o then
		return o.Count .. "/" .. o.Max .. " players waiting \u{b7} tap PLAY to join"
	end
	return nil
end

return PlayButton
