--!strict
-- Teleport mode UI (Config.Places.Mode = "Teleport"): a card at the top of the screen that shows
--   * in the lobby: the party heading to the quarry, with RETRY / CANCEL when a teleport failed
--   * in the Match place: WaitingForParty with arrival checkmarks, the 30 s countdown and, if
--     members are missing, START WITH ARRIVED / RETURN options
--   * returning to the lobby, and rejected arrivals
-- It only displays what the server sends and sends intents back (LaunchAction). Never shown in
-- the default single-place mode.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)

local C = UI.Colors
local PET = Theme.Pet
local T = UI.T
local LaunchPanel = {}

-- Pet style: a sky-blue PetStyle.card (drop shadow, pattern, tilt) with a floating title, white outlined words, light
-- member rows and lime / navy pills. `card` is the card's wrapper (position, size, destroy); `face` holds the content.
local CARD_W = 460
local CARD_PAD_X, CARD_PAD_Y, CARD_GAP = 14, 10, 6
local card: Frame? = nil
local face: Frame? = nil
local last: { Kind: string, Data: any }? = nil
-- The Waiting card arrives every second (countdown). Rebuilding it each time destroyed the buttons under the
-- player's finger and lost taps, so when only the countdown changed the message text is updated in place.
local waitSig: string? = nil
local msgLabel: TextLabel? = nil

local function act(action: string)
	Net.event("LaunchAction"):FireServer(action)
end

local function ensureCard(): Frame
	if card and card.Parent and face and face.Parent then
		return face :: Frame
	end
	local root = UI.overlay()
	-- the pattern is laid for the card's full width; the wrapper then takes the screen width up to CARD_W
	local f = PetStyle.card(root, "sky", { Name = "LaunchCard", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(CARD_W, 120), Active = true })
	local wrap = f.Parent :: Frame
	wrap.Size = UDim2.new(1, -32, 0, 120)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(CARD_W, 1000)
	limit.Parent = wrap
	-- the content lives in its own frame: a list layout on the face would stack the pattern host as a row
	local content = UI.frame(f, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 })
	UI.pad(content, CARD_PAD_X, CARD_PAD_Y)
	UI.list(content, Enum.FillDirection.Vertical, CARD_GAP)
	card = wrap
	face = content
	return content
end

-- The wrapper grows to its content (every child has a fixed height; a scale-sized face cannot size itself).
local function fitHeight(f: Frame)
	local h = 0
	local n = 0
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") and c.Visible and c.Name ~= "Pattern" and c.Name ~= "Drop" then
			h += c.Size.Y.Offset
			n += 1
		end
	end
	h += CARD_PAD_Y * 2 + CARD_GAP * math.max(n - 1, 0)
	local w = card
	if w then
		w.Size = UDim2.new(1, -32, 0, h)
	end
end

-- A round badge: green check (here / sent), red cross (failed), grey ring (still on the way).
local function badge(parent: Instance, kind: string, order: number): Frame
	local b = UI.frame(parent, {
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = if kind == "good" then PET.Lime elseif kind == "bad" then PET.Red else C.Disabled,
		LayoutOrder = order,
	})
	PetStyle.round(b, 12)
	PetStyle.edge(b, if kind == "good" then PET.LimeEdge elseif kind == "bad" then PET.RedEdge else C.GrayDeep, 2)
	local function bar(w: number, h: number, x: number, y: number, rot: number)
		local r = UI.frame(b, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rot,
			BackgroundColor3 = if kind == "bad" then PET.White else PET.Ink,
		})
		UI.corner(r, 2)
	end
	if kind == "good" then
		bar(3, 8, 9, 14, 45)
		bar(3, 14, 15, 12, -45)
	elseif kind == "bad" then
		bar(3, 14, 12, 12, 45)
		bar(3, 14, 12, 12, -45)
	else
		for i = 0, 2 do
			local d = UI.frame(b, { Position = UDim2.fromOffset(5 + i * 6, 10), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = C.Muted })
			UI.corner(d, 2)
		end
	end
	return b
end

-- A light pill row on the blue card: badge, name in the deep title blue, the state word on the right.
local function memberRow(parent: Instance, name: string, kind: string, word: string, isLeader: boolean, order: number)
	local row = UI.frame(parent, { Name = "Member", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = PET.QuestBody, LayoutOrder = order, ZIndex = 3 })
	PetStyle.round(row, 999)
	PetStyle.edge(row, PET.QuestEdge, 2)
	local b = badge(row, kind, 0)
	b.Position = UDim2.fromOffset(6, 3)
	b.ZIndex = 4
	UI.text(row, if isLeader then "\u{2605} " .. name else name, { Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -176, 1, 0), TextSize = T.Small, Font = UI.Bold, TextColor3 = PET.TitleEdge, Outline = false, ZIndex = 4 })
	local state = UI.text(row, word, {
		Position = UDim2.new(1, -132, 0, 0),
		Size = UDim2.fromOffset(120, 30),
		TextSize = T.Tiny,
		Font = UI.Head,
		Outline = false,
		ZIndex = 4,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if kind == "good" then PET.PriceEdge elseif kind == "bad" then PET.RedEdge else C.Muted,
	})
	state.TextWrapped = false -- one line: the fitted words shrink instead of wrapping
end

local function clear(f: Frame)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") and c.Name ~= "Pattern" then
			c:Destroy()
		end
	end
end

local function head(f: Frame, title: string, message: string?)
	-- the title and its drop copy sit in one box (two labels in the list would take two rows)
	local box = UI.frame(f, { Name = "Head", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 3 })
	PetStyle.title(box, UI.titleCase(title), T.Head + 2, { Size = UDim2.new(1, 0, 1, 0), ZIndex = 4 })
	if message and message ~= "" then
		msgLabel = PetStyle.words(f, message, T.Small, { Name = "Message", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, OutlineColor = PET.TitleEdge, OutlineThick = 1.8, ZIndex = 3 })
	end
end

-- Pills: "yellow" = lime (go), "dark" = navy (back / cancel); a disabled one is flat grey and takes no taps.
local function buttons(f: Frame, specs: { { Text: string, Style: string, Enabled: boolean?, Action: (() -> ())? } })
	if #specs == 0 then
		return
	end
	local row = UI.frame(f, { Name = "Buttons", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 100, ZIndex = 3 })
	UI.list(row, Enum.FillDirection.Horizontal, 8)
	for i, s in specs do
		local props = { Size = UDim2.new(1 / #specs, -8 * (#specs - 1) / #specs, 1, 0), LayoutOrder = i }
		local b: TextButton
		if s.Enabled == false then
			b = PetStyle.pill(row, s.Text, C.Disabled, C.Disabled, C.GrayDeep, props, T.Body)
			b.Active = false
			b:SetAttribute("Disabled", true)
		elseif s.Style == "yellow" then
			b = PetStyle.pill(row, s.Text, PET.LimeTop, PET.Lime, PET.LimeEdge, props, T.Body)
		else
			b = PetStyle.pill(row, s.Text, PET.TabBar, PET.TabBar, PET.TabBarEdge, props, T.Body)
		end
		local action = s.Action
		if action and s.Enabled ~= false then
			b.Activated:Connect(action)
		end
	end
end

-- Everything on the Waiting card except the countdown seconds; equal signatures mean only the text changed.
local function waitingSignature(data: any): string
	local parts = { tostring(data.Status), tostring(data.CanStart), tostring(data.CanReturnAll) }
	for _, m in data.Members or {} do
		table.insert(parts, tostring(m.Name) .. ":" .. tostring(m.Arrived) .. ":" .. tostring(m.Leader))
	end
	return table.concat(parts, "|")
end

local function render(kind: string, data: any)
	if kind == "Waiting" then
		local sig = waitingSignature(data)
		local label = msgLabel
		if last and last.Kind == "Waiting" and sig == waitSig and card and card.Parent and label and label.Parent then
			if data.Status ~= "Loading" and data.Status ~= "TimedOut" then
				label.Text = "Everyone is on the way. The hunt starts when the whole party is here.  " .. tostring(data.Remaining) .. " s"
			end
			last = { Kind = "Waiting" :: string, Data = data }
			return
		end
		waitSig = sig
	else
		waitSig = nil
	end
	local f = ensureCard()
	clear(f)
	msgLabel = nil
	last = { Kind = kind, Data = data }
	if kind == "Launch" then
		local phase = data.Phase
		local title = "HEADING TO THE PET HUNT"
		if phase == "Failed" then
			title = "COULD NOT GET THERE"
		elseif phase == "Partial" then
			title = "PART OF THE PARTY IS MISSING"
		elseif phase == "Preparing" then
			title = "GETTING READY"
		end
		head(f, title, data.Message)
		for i, m in data.Members do
			local k, word = "wait", "ON THE WAY"
			if m.State == "Away" then
				k, word = "good", "IN THE HUNT"
			elseif m.State == "Sent" then
				k, word = "good", "SENT"
			elseif m.State == "Failed" then
				k, word = "bad", "FAILED"
			end
			memberRow(f, m.Name, k, word, m.UserId == data.Leader, 10 + i)
		end
		if phase == "Failed" or phase == "Partial" then
			buttons(f, {
				{ Text = "RETRY", Style = "yellow", Enabled = data.CanRetry == true, Action = function()
					act("Retry")
				end },
				{ Text = "CANCEL", Style = "dark", Action = function()
					act("Cancel")
				end },
			})
		end
	elseif kind == "Waiting" then
		local status = data.Status
		local title = "WAITING FOR YOUR PARTY"
		local msg = "Everyone is on the way. The hunt starts when the whole party is here."
		if status == "Loading" then
			title = "EVERYONE IS HERE"
			msg = "Loading your gear..."
		elseif status == "TimedOut" then
			title = "SOME PLAYERS ARE MISSING"
			msg = if data.CanStart then "Start with the players who are here, or go back to the lobby." else "Waiting for the party leader to decide."
		else
			msg = msg .. "  " .. tostring(data.Remaining) .. " s"
		end
		head(f, title, msg)
		for i, m in data.Members do
			memberRow(f, m.Name, if m.Arrived then "good" else "wait", if m.Arrived then "HERE" else "ON THE WAY", m.Leader, 10 + i)
		end
		local specs = {}
		if data.CanStart then
			table.insert(specs, { Text = "START WITH ARRIVED", Style = "yellow", Action = function()
				act("StartWithArrived")
			end })
		end
		table.insert(specs, { Text = if data.CanReturnAll then "RETURN ALL" else "RETURN", Style = "dark", Action = function()
			act(if data.CanReturnAll then "ReturnAll" else "Return")
		end })
		buttons(f, specs)
	elseif kind == "ReturnFailed" then
		head(f, "COULD NOT GO BACK YET", "Nothing was lost. Try again in a moment.")
		buttons(f, { { Text = "TRY AGAIN", Style = "yellow", Action = function()
			act("Return")
		end } })
	elseif kind == "Rejected" then
		head(f, "NOT AVAILABLE", data.Message)
	elseif kind == "Returning" then
		head(f, "BACK TO THE LOBBY", data.Message)
	end
	fitHeight(f)
end

function LaunchPanel.hide()
	last = nil
	waitSig = nil
	msgLabel = nil
	if card then
		(card :: Frame):Destroy()
		card = nil
		face = nil
	end
end

function LaunchPanel.onEvent(kind: string, data: any)
	if kind == "Hide" then
		LaunchPanel.hide()
	elseif kind == "Mode" then
		State.Teleport = data.Teleport == true
		State.update("Match")
	elseif kind == "Launch" or kind == "Waiting" or kind == "ReturnFailed" or kind == "Rejected" or kind == "Returning" then
		render(kind, data)
	end
end

function LaunchPanel.start()
	Net.event("LaunchEvent").OnClientEvent:Connect(LaunchPanel.onEvent)
	-- A hunt starting or ending replaces the waiting card.
	State.Changed.Event:Connect(function(what)
		if what == "Match" and State.Match and last and last.Kind == "Waiting" then
			LaunchPanel.hide()
		end
	end)
end

return LaunchPanel
