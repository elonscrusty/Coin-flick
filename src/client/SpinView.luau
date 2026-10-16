--!strict
-- Spin wheel HUD hook (idea 3, client only; the server rolls and pays: RetentionService.spin, LaunchPerks.Spin).
-- A SPIN card in the HUD's lobby row, sharing the GIFT card's slot (SpinView.wanted): "in 3:59:12" counts down to the next free spin; when
-- it is ready it turns green "SPIN!" and wiggles. Tap = ask the server to spin; the answer ("Spin", { Slice, Text })
-- shows as a banner with confetti. A drawn wheel that lands on the slice is the UI thread's job (Fable): it can read
-- LaunchPerks.Spin.Slices for the slice order and listen to the same Retention "Spin" notice.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)
local Theme = require(script.Parent.ui.Theme)
local HudArt = require(script.Parent.ui.HudArt)
local Juice = require(script.Parent.ui.Juice)
local Effects = require(script.Parent.Effects)
local SpinPanel = require(script.Parent.ui.SpinPanel)

local T = UI.T
local TC = Theme.Color
local SpinView = {}

local player = Players.LocalPlayer
local btn: TextButton? = nil
local sub: TextLabel? = nil
local readyAt = math.huge -- os.clock when the next spin is ready (from the last profile view)
local style = ""
local stopWiggle: (() -> ())? = nil
local asked = 0

local function clock(sec: number): string
	sec = math.max(0, math.ceil(sec))
	local h, m = sec // 3600, sec % 3600 // 60
	return if h > 0 then string.format("%d:%02d:%02d", h, m, sec % 60) else string.format("%d:%02d", m, sec % 60)
end

local function setStyle(s: string)
	local b = btn
	if not b or style == s then
		return
	end
	style = s
	UI.setStyle(b, s)
	if s == "green" and not stopWiggle then
		stopWiggle = UI.wiggle(b)
	elseif s ~= "green" and stopWiggle then
		(stopWiggle :: () -> ())()
		stopWiggle = nil
	end
end

local function refresh()
	local b, l = btn, sub
	if not b or not l then
		return
	end
	local lobby = State.Match == nil and player:GetAttribute("MatchKey") == nil and player:GetAttribute("InTower") ~= true and player:GetAttribute("InBattle") ~= true
	local left = readyAt - os.clock()
	b.Visible = lobby and State.Profile ~= nil and readyAt < math.huge and SpinView.wanted(left <= 0)
	if not b.Visible then
		return
	end
	if left <= 0 then
		l.Text = "SPIN!"
		setStyle("green")
	else
		l.Text = "in " .. clock(left)
		setStyle("blue")
	end
end

-- The HUD row has room for one of GIFT / SPIN (the phone row is full): SPIN shows once today's play gifts are all
-- opened, or while a spin is ready and no gift is. RetentionView hides GIFT while this is true.
function SpinView.wanted(spinReady: boolean?): boolean
	local p = State.Profile
	local g = p and (p :: any).Gifts
	if readyAt == math.huge then
		return false
	end
	if spinReady == nil then
		spinReady = readyAt - os.clock() <= 0
	end
	if type(g) ~= "table" or g.NextGift == nil then
		return true
	end
	return spinReady == true and (tonumber(g.Ready) or 0) <= 0
end

local function onProfile()
	local p = State.Profile
	local perks = p and (p :: any).Perks
	if type(perks) == "table" and type(perks.SpinIn) == "number" then
		readyAt = os.clock() + perks.SpinIn
	end
	refresh()
end

local function onClick()
	local b = btn
	if not b then
		return
	end
	-- the wheel panel (ui/SpinPanel) holds the SPIN button and the countdown; it asks the server itself
	if os.clock() - asked < 0.5 then
		return
	end
	asked = os.clock()
	SpinPanel.open()
end

-- the wheel panel (the HUD card's tap; the preview scene `spin` calls these too)
function SpinView.openPanel()
	SpinPanel.open()
end

function SpinView.landPanel(sliceId: string, text: string)
	SpinPanel.land(sliceId, text)
end

function SpinView.start()
	local screen = UI.screen()
	local left = screen:FindFirstChild("Left", true)
	local b = HudArt.bigButton(left or screen, {
		Name = "SpinWheel", Style = "blue", Art = "IconDaily", Title = "SPIN", Sub = "in 4:00:00", Width = 172, Height = 60, LayoutOrder = 56,
		OnClick = onClick,
	})
	if not left then
		b.Position = UDim2.fromOffset(T.Edge, T.Edge + 224)
	end
	b.Visible = false
	btn = b
	sub = b:FindFirstChild("Sub", true) :: TextLabel?
	style = "blue"
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			onProfile()
		elseif what == "Match" then
			refresh()
		end
	end)
	Net.event("Retention").OnClientEvent:Connect(function(kind, data)
		if kind == "Spin" and type(data) == "table" then
			asked = 0
			if SpinPanel.isOpen() then
				-- the wheel spins onto the slice, then celebrates
				SpinPanel.land(tostring(data.Slice or ""), tostring(data.Text or ""))
			else
				Juice.banner("SPIN: " .. string.upper(tostring(data.Text or "")) .. "!", TC.Gold, 2)
				Effects.confetti()
			end
		elseif kind == "SpinNo" and type(data) == "table" then
			asked = 0
			local why = if type(data.In) == "number" then "Next spin in " .. clock(data.In) else tostring(data.Text or "Try again!")
			local b = btn
			if SpinPanel.isOpen() then
				SpinPanel.refuse(why)
			elseif b then
				Juice.nope(b)
				Juice.floatText(b, why, TC.Gold)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	onProfile()
end

return SpinView
