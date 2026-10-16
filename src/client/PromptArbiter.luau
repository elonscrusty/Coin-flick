--!strict
-- World prompt arbitration (Master Prompt 4, sections 27 and 51).
--
-- Cause of the overlapping "Inspect / Buy" panels in the lobby: every workshop stand carries its own
-- ProximityPrompt and Roblox draws EVERY enabled prompt in range with its default (large, world-anchored)
-- billboard, so neighbouring stands overlap each other and the tool chip. Nothing coordinated them.
--
-- Fix, entirely on the client (the server's prompts are untouched):
--   * every ProximityPrompt in the world is tracked (one connection set, entries dropped when removed)
--   * each prompt's Style is switched to Custom LOCALLY, so Roblox draws no billboard for it
--   * every 0.1 s ONE winner is chosen (PromptPick: nearest, camera-facing helps, hysteresis, a prompt behind
--     a big solid is penalised, never removed) and only that prompt stays Enabled (locally); the rest are
--     disabled locally, so they cannot be triggered either
--   * the winner is drawn as ONE compact pill in the lower middle of the screen, above the tool chip and the
--     tip, clear of the joystick, action and jump areas; tapping it triggers that same prompt
--   * nothing shows while a modal / reveal owns the screen or while a button is held; after the hunt only the
--     arena's sell bin is offered (the action button is gone by then);
--     in a hunt the hopper prompt is hidden (the action button already sells) and only the player's OWN
--     machine panel is offered
-- Keyboard / gamepad activation stays with Roblox (the prompt keeps its KeyboardKeyCode); the pill's chip names the
-- key, the controller button or TAP for the input in use.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PromptPick = require(Shared.PromptPick)
local State = require(script.Parent.State)
local PileView = require(script.Parent.PileView)
local Config = require(Shared.Config)
local CameraMode = require(script.Parent.CameraMode)
local UI = require(script.Parent.ui.UI)

local PromptArbiter = {}

local player = Players.LocalPlayer
local C = UI.Colors
local T = UI.T

local tracked: { [ProximityPrompt]: boolean } = {} -- prompt -> last Enabled value we wrote
local winner: ProximityPrompt? = nil
local started = false
local pill: TextButton? = nil
local actionLabel: TextLabel? = nil
local objectLabel: TextLabel? = nil
local keyChip: TextLabel? = nil
local clock = 0
local PILL_W, PILL_H = 270, 58
local occludedCache: { [ProximityPrompt]: { At: number, Value: boolean } } = {}
-- The server's own Enabled for each prompt (audit 29: the arbiter used to switch a server-disabled prompt, such as
-- a closed shop door, back on when it won). Taken when the prompt is first seen, then updated whenever Enabled
-- changes to a value the arbiter did not write. Limit: a server switch-off that lands while the arbiter already
-- holds the prompt off locally fires no change, so it is only seen once the server switches it on again.
local serverOn: { [ProximityPrompt]: boolean } = {}
local enabledConn: { [ProximityPrompt]: RBXScriptConnection } = {}

local function anchorOf(pp: ProximityPrompt): Vector3?
	local parent = pp.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function track(pp: ProximityPrompt)
	if tracked[pp] ~= nil then
		return
	end
	tracked[pp] = pp.Enabled
	serverOn[pp] = pp.Enabled
	enabledConn[pp] = pp:GetPropertyChangedSignal("Enabled"):Connect(function()
		if tracked[pp] ~= nil and pp.Enabled ~= tracked[pp] then
			serverOn[pp] = pp.Enabled
			tracked[pp] = pp.Enabled
		end
	end)
	pp.Style = Enum.ProximityPromptStyle.Custom -- local only: no default billboard for any prompt
end

local function untrack(pp: ProximityPrompt)
	tracked[pp] = nil
	serverOn[pp] = nil
	local conn = enabledConn[pp]
	if conn then
		conn:Disconnect()
		enabledConn[pp] = nil
	end
	occludedCache[pp] = nil
	if winner == pp then
		winner = nil
	end
end

-- Is this prompt offered in the current situation at all (before distance)?
local function offered(pp: ProximityPrompt, inMatch: boolean, phase: string?): boolean
	if serverOn[pp] == false then
		return false -- switched off by the server: never offered, never re-enabled here
	end
	if inMatch then
		if phase == "Results" then
			-- after the hunt the action button is gone, so the arena's own SELL RUBBLE bin takes the sale
			-- (the results card and the tutorial send the player there)
			return pp.Name == "SellPrompt" or pp:GetAttribute("Sell") == true
		elseif phase ~= "Searching" then
			return false
		end
		if pp.Name == "MachineToggle" then
			local model = if pp.Parent then pp.Parent.Parent else nil
			return model ~= nil and model:GetAttribute("OwnerId") == player.UserId
		end
		return false -- the hopper is the action button's job in a hunt; gallery and workshop prompts are lobby-only
	end
	-- switched off by the server (a LIKE post on an empty plot), or a LIKE post on your own plot
	if pp:GetAttribute("Off") == true then
		return false
	end
	if pp:GetAttribute("LikePlot") ~= nil and pp:GetAttribute("OwnerId") == player.UserId then
		return false
	end
	return true
end

-- A big opaque solid between the camera and the prompt (a roof or wall of another building) makes it a
-- poor choice. Soft: it only costs distance, so a lone prompt is never lost. Cached for 0.5 s.
local function occluded(pp: ProximityPrompt, anchor: Vector3): boolean
	local c = occludedCache[pp]
	local now = os.clock()
	if c and now - c.At < 0.5 then
		return c.Value
	end
	local cam = Workspace.CurrentCamera
	local value = false
	if cam then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local skip: { Instance } = {}
		if player.Character then
			table.insert(skip, player.Character)
		end
		local own = pp.Parent and pp.Parent:FindFirstAncestorOfClass("Model")
		if own then
			table.insert(skip, own)
		end
		params.FilterDescendantsInstances = skip
		local from = cam.CFrame.Position
		local hit = Workspace:Raycast(from, anchor - from, params)
		if hit and hit.Instance:IsA("BasePart") then
			local s = hit.Instance.Size
			value = hit.Instance.Transparency < 0.5 and math.max(s.X, s.Y, s.Z) >= 6 and (hit.Position - anchor).Magnitude > 1.5
		end
	end
	occludedCache[pp] = { At = now, Value = value }
	return value
end

-- The rubble seller (board "Rubble sale"): its prompt is drawn as a sell card with the real bag count.
local function isSell(pp: ProximityPrompt): boolean
	return pp.Name == "SellPrompt" or pp:GetAttribute("Sell") == true
end

local sellIcon: GuiObject? = nil
local sellButton: TextButton? = nil

local function trigger()
	local pp = winner
	if not pp or not pp.Parent then
		return
	end
	if isSell(pp) then
		local prof = State.Profile
		if not prof or prof.Rubble <= 0 then
			UI.notify("No candy to sell.", "info", { Tag = "norubble" })
			return
		end
	end
	pp:InputHoldBegin()
	task.delay(0.06, function()
		pp:InputHoldEnd()
	end)
end

local function ensurePill()
	if pill and pill.Parent then
		return
	end
	local b = Instance.new("TextButton")
	b.Name = "WorldPrompt"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(0.5, 1)
	-- the lower middle, above the hint lane: away from joystick, action and jump
	b.Position = UDim2.new(0.5, 0, 1, -(T.Edge + 54 + 54))
	b.Size = UDim2.fromOffset(PILL_W, PILL_H)
	-- the chunky HUD button look (lobby tiles, DAILY): HUD blue, thick navy outline, bottom lip and a gloss
	-- (it was a flat light-blue box)
	b.BackgroundColor3 = C.Hud
	b.BackgroundTransparency = 0
	b.BorderSizePixel = 0
	b.Visible = false
	b.ZIndex = 6
	b.Parent = UI.screen()
	UI.corner(b, 14)
	UI.stroke(b, C.PanelEdge, 3)
	UI.bevel(b)
	UI.gloss(b)
	local kc = UI.text(b, "R", { Font = UI.Head, TextSize = T.Small, TextColor3 = C.DarkText, Outline = false, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(30, 30), TextXAlignment = Enum.TextXAlignment.Center })
	kc.BackgroundTransparency = 0
	kc.BackgroundColor3 = C.Gold
	kc.ZIndex = 2
	UI.corner(kc, 8)
	UI.stroke(kc, C.GoldDeep, 2)
	keyChip = kc
	-- top line: WHAT it is (the pet's name, EGG SHOP), big; under it the action (Inspect, Coming soon), smaller but
	-- in gold and well readable (it was a tiny grey line, and a shop showed "COMING SOON" big over its own name)
	local title = UI.text(b, "", { Name = "Title", Font = UI.Head, TextSize = T.Head, ZIndex = 2, Position = UDim2.fromOffset(46, 5), Size = UDim2.new(1, -54, 0, 26) })
	title.TextWrapped = false
	actionLabel = title
	local sub = UI.text(b, "", { Name = "Sub", Font = UI.Bold, TextSize = T.Body, TextColor3 = C.Gold, Outline = "Normal", RichText = true, ZIndex = 2, Position = UDim2.fromOffset(46, 32), Size = UDim2.new(1, -54, 0, 20) })
	sub.TextWrapped = false
	objectLabel = sub
	local icon = UI.icon(b, "basket", 40, { Position = UDim2.fromOffset(8, 12), Visible = false })
	sellIcon = icon
	local sb = UI.button(b, "SELL", "gold", trigger, { Name = "Sell", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(84, 42), Visible = false, TextSize = T.Head + 2 })
	sellButton = sb
	b.Activated:Connect(trigger)
	UI.bouncy(b) -- the pill squashes on press and bounces back like every button
	pill = b
end

-- The input that activates a prompt, for the chip on the pill: the prompt's own key on keyboard and mouse, its
-- gamepad button on a controller, TAP on touch (tapping the pill triggers it). Shown for every input type, so no
-- lobby card is left without a way to use it.
local function keyFor(pp: ProximityPrompt): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "TAP"
	elseif string.sub(last.Name, 1, 7) == "Gamepad" then
		return (string.gsub(pp.GamepadKeyCode.Name, "^Button", ""))
	end
	return pp.KeyboardKeyCode.Name
end

local function choose(): ProximityPrompt?
	local m = State.Match
	local inMatch = m ~= nil
	local phase = if m then m.Phase else nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cam = Workspace.CurrentCamera
	local suppressed = not CameraMode.mayAct() or root == nil or PileView.isHolding()
	local cands: { PromptPick.Candidate } = {}
	local look = if cam then cam.CFrame.LookVector else Vector3.new(0, 0, -1)
	local fpLook = CameraMode.firstPerson()
	for pp in tracked do
		if suppressed or not root or not pp.Parent or not offered(pp, inMatch, phase) then
			continue
		end
		local a = anchorOf(pp)
		if not a then
			continue
		end
		local d = (a - root.Position).Magnitude
		if d <= pp.MaxActivationDistance then
			local to = a - (if cam then cam.CFrame.Position else root.Position)
			-- first person: only what the reticle points at (a cone around the camera-centre ray) is offered, so no
			-- label follows the player around while exploring and a press never acts on something behind them
			if fpLook and (to.Magnitude < 0.01 or look:Dot(to.Unit) < Config.Camera.PromptCone) and d > 3 then
				continue
			end
			local facing = if to.Magnitude > 0.01 then math.clamp((look:Dot(to.Unit) - 0.3) / 0.7, 0, 1) else 0
			local penalty = 0
			if occluded(pp, a) then
				penalty = 6 -- behind a big solid: a worse choice, still reachable when it is the only one
				facing = 0
			end
			table.insert(cands, { Key = pp, Distance = d + penalty, Range = pp.MaxActivationDistance + penalty, Facing = facing })
		end
	end
	local won = PromptPick.pick(cands, winner)
	return won :: ProximityPrompt?
end

local function apply(won: ProximityPrompt?)
	winner = won
	for pp, was in tracked do
		local want = pp == won and serverOn[pp] ~= false
		if was ~= want then
			tracked[pp] = want
			pp.Enabled = want
		end
	end
	if won then
		ensurePill()
		local b = pill :: TextButton
		local al, ol = actionLabel :: TextLabel, objectLabel :: TextLabel
		local key = keyFor(won)
		local sell = isSell(won)
		;(sellIcon :: GuiObject).Visible = sell
		;(sellButton :: TextButton).Visible = sell
		if sell then
			-- sell card: basket, "Sell rubble", the bag the server reports, SELL (or why not)
			local prof = State.Profile
			local n = if prof then prof.Rubble else 0
			local cap = if prof then prof.Capacity else 0
			b.Size = UDim2.fromOffset(300, 64)
			;(keyChip :: TextLabel).Visible = false
			al.Text = "Sell candy"
			ol.Text = if n > 0 then "Candy: <font color=\"#FFFFFF\">" .. n .. "</font>/" .. cap .. " for coins" else "No candy to sell."
			al.Position = UDim2.fromOffset(56, 8)
			al.Size = UDim2.new(1, -150, 0, 24)
			ol.Position = UDim2.fromOffset(56, 34)
			ol.Size = UDim2.new(1, -150, 0, 20)
			UI.setEnabled(sellButton :: TextButton, n > 0)
		else
			b.Size = UDim2.fromOffset(PILL_W, PILL_H)
			-- the name of the thing (ObjectText) is the big line and the action the small one; a prompt without an
			-- ObjectText shows its action big. A hold prompt says so (every lobby prompt is a press today).
			local hold = if won.HoldDuration > 0 then "Hold: " else ""
			local object = won.ObjectText
			if object ~= "" then
				al.Text = object
				ol.Text = hold .. won.ActionText
			else
				al.Text = hold .. won.ActionText
				ol.Text = ""
			end
			local kc = keyChip :: TextLabel
			kc.Visible = true
			kc.Text = key
			kc.Size = UDim2.fromOffset(if #key > 1 then 44 else 32, 32)
			local kx = if #key > 1 then 60 else 48
			local one = ol.Text == ""
			al.Position = UDim2.fromOffset(kx, if one then 14 else 5)
			al.Size = UDim2.new(1, -(kx + 8), 0, if one then 30 else 26)
			ol.Position = UDim2.fromOffset(kx, 32)
			ol.Size = UDim2.new(1, -(kx + 8), 0, 20)
		end
		-- clear of the thumbstick and Roblox's bottom-edge controls: raised off the bottom edge in landscape (it sat
		-- low beside the joystick), and above the tutorial hint lane whenever a hint shows there; portrait phones
		-- keep it higher, clear of the thumbstick and jump button
		local gui = UI.screen()
		local px = gui.AbsoluteSize
		local lane = gui:FindFirstChild("HintLow", true)
		local hintUp = false
		if lane then
			for _, c in lane:GetChildren() do
				if c:IsA("GuiObject") and c.Visible then
					hintUp = true
					break
				end
			end
		end
		local lift = if hintUp or px.X <= px.Y then T.Edge + 54 + 60 else T.Edge + 34
		b.Position = UDim2.new(0.5, 0, 1, -lift)
		b.Visible = true
	elseif pill then
		pill.Visible = false
	end
end

function PromptArbiter.start()
	if started then
		return
	end
	started = true
	for _, d in Workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			track(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			track(d)
		end
	end)
	Workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			untrack(d)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock < 0.1 then
			return
		end
		clock = 0
		apply(choose())
	end)
	UI.BlockChanged.Event:Connect(function()
		apply(choose())
	end)
end

-- For checks: how many prompts are tracked, which one is shown, how many are enabled right now.
function PromptArbiter.stats(): { Tracked: number, Enabled: number, Winner: ProximityPrompt?, PillVisible: boolean }
	local enabled = 0
	local n = 0
	for pp in tracked do
		n += 1
		if pp.Enabled then
			enabled += 1
		end
	end
	return { Tracked = n, Enabled = enabled, Winner = winner, PillVisible = pill ~= nil and pill.Visible }
end

return PromptArbiter
