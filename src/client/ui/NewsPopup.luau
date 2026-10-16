--!strict
-- WHAT'S NEW pop-up (shared/WhatsNew): shown once per new version, in the lobby, when no other menu is open and the
-- tutorial is done. Showing it tells the server (SettingsAction { LastSeenNews = version }), which stores the
-- version in the profile, so it does not come back on the next visit. The same lines are on the park's board.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local WhatsNew = require(Shared.WhatsNew)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local PopupGate = require(script.Parent.Parent.PopupGate)
local Theme = require(script.Parent.Theme)

local T = UI.T
local TC = Theme.Color
local NewsPopup = {}

local shown = false -- once per session at most (the server keeps it across visits)
local queued = false -- waiting its turn behind another big card (NEXT GOAL, away nest) or a menu

function NewsPopup.open()
	local lines = WhatsNew.Lines
	local newsPanel, body, close, footer = UI.modal("WhatsNew", WhatsNew.Title, Vector2.new(440, 120 + #lines * 40 + 70), { Footer = 64, Center = true }) -- body scrolls: many lines never clip on short or portrait screens
	PanelSkin.dress(newsPanel, "Info", WhatsNew.Title, { Center = true })
	UI.list(body, Enum.FillDirection.Vertical, 6)
	for i, line in lines do
		local row = UI.frame(body, { Name = "Line" .. i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i })
		UI.text(row, "\u{2022}", { Name = "Dot", Font = UI.Head, TextSize = T.Body, TextColor3 = TC.Gold, Size = UDim2.fromOffset(20, 34), TextXAlignment = Enum.TextXAlignment.Center })
		UI.text(row, line, { Name = "Text", Font = UI.Bold, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), TextXAlignment = Enum.TextXAlignment.Left })
	end
	if footer then
		UI.button(footer, "GOT IT", "gold", close, { Name = "GotIt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.6, 0, 0, 46), TextSize = T.Head })
	end
end

local function wanted(): boolean
	local prof = State.Profile
	return not shown and prof ~= nil and WhatsNew.shouldShow(prof.LastSeenNews, prof.OnboardDone == true)
end

-- a big card like the others: one at a time (shared/PopupRules), never over a hunt, a menu or the NEXT GOAL card
local function check()
	if queued or not wanted() then
		return
	end
	queued = true
	PopupGate.later("Card", function()
		queued = false
		if not wanted() or UI.blocked() or not PopupGate.free("Card") then
			if wanted() then
				task.delay(1, check)
			end
			return
		end
		shown = true
		Net.event("SettingsAction"):FireServer({ LastSeenNews = WhatsNew.Version })
		NewsPopup.open()
	end)
end

function NewsPopup.start()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" or what == "Match" then
			task.delay(2, check) -- let the lobby settle first
		end
	end)
	UI.ModalChanged.Event:Connect(function(name)
		if name == nil then
			task.delay(1, check)
		end
	end)
end

return NewsPopup
