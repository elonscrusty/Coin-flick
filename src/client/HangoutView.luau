--!strict
-- Lobby hangout, client side (shared/Hangout). Draws only; the server decides everything.
--   * sky beam over the egg shrine when an Epic / Legendary hatches in this server (RareHatch "Local")
--   * whack-a-rock: a small score card while you play
--   * lobby events: the status card names the running event
--   * emote button: Roblox's own emotes, read from the avatar's Animate script (no asset ids in the game)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)
local SafeZones = require(Shared.SafeZones)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)
local Theme = require(script.Parent.ui.Theme)
local PetStyle = require(script.Parent.ui.PetStyle)
local PET = Theme.Pet

local HangoutView = {}

local player = Players.LocalPlayer
local fx: Folder? = nil

local function fxFolder(): Folder
	local f = fx
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "CT_HangoutFx"
	made.Parent = Workspace
	fx = made
	return made
end

local function lowEffects(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.LowEffects == true
end

local function deco(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- Sky beam -------------------------------------------------------------------------------------------------------------

local function hatchStand(): BasePart?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("HatchStand") == true then
			return d
		end
	end
	return nil
end

function HangoutView.beam(rarity: string)
	if not Hangout.beamFor(rarity) then
		return
	end
	local stand = hatchStand()
	if not stand then
		return
	end
	local B = Hangout.Beam
	local w = (B.Width :: any)[rarity] or 5
	local h = if lowEffects() then B.Height / 2 else B.Height
	local beam = Instance.new("Part")
	beam.Name = "SkyBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Color = (B.Color :: any)[rarity] or Color3.new(1, 1, 1)
	beam.Size = Vector3.new(h, w, w)
	beam.CFrame = CFrame.new(stand.Position + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Transparency = 1
	deco(beam)
	local light = Instance.new("PointLight")
	light.Color = beam.Color
	light.Range = 40
	light.Brightness = 3
	light.Parent = beam
	beam.Parent = fxFolder()
	TweenService:Create(beam, TweenInfo.new(0.6), { Transparency = 0.25 }):Play()
	task.delay(B.Seconds, function()
		TweenService:Create(beam, TweenInfo.new(1.2), { Transparency = 1 }):Play()
		task.wait(1.3)
		beam:Destroy()
	end)
end

-- Screen bits: status card, emotes -----------------------------------------------------------------------------------

local card: TextLabel? = nil
local cardBox: Frame? = nil -- the card's light pet-style box (shown and popped with the words)
local emoteBtn: TextButton? = nil
local emoteRow: Frame? = nil
local cardText = { Whack = nil :: string?, Event = nil :: string? }

-- A quick "pop" (scale up and settle) on a screen element (owner ask: animate everything).
local function pop(g: GuiObject, from: number)
	local found = g:FindFirstChildOfClass("UIScale")
	local s: UIScale = if found then found else Instance.new("UIScale")
	s.Parent = g
	s.Scale = from
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function refreshCard()
	local c = card
	if not c then
		return
	end
	local line = cardText.Whack or cardText.Event
	local box: GuiObject = if cardBox then cardBox else c
	local was = box.Visible
	box.Visible = line ~= nil and State.Match == nil
	-- a new message pops; a ticking count only pops when the first word changes
	if box.Visible and (not was or string.match(c.Text, "^%S+") ~= string.match(line or "", "^%S+")) then
		pop(box, 1.18)
	end
	c.Text = line or ""
end

local function playEmote(key: string)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animate = char and char:FindFirstChild("Animate")
	local folder = animate and animate:FindFirstChild(key)
	local anim = folder and folder:FindFirstChildWhichIsA("Animation")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not (anim and animator and hum) then
		return
	end
	local track = (animator :: Animator):LoadAnimation(anim :: Animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	-- walking away stops the emote
	local conn: RBXScriptConnection? = nil
	conn = (hum :: Humanoid).Running:Connect(function(speed: number)
		if speed > 1 then
			track:Stop(0.2)
			if conn then
				conn:Disconnect()
			end
		end
	end)
	track.Stopped:Connect(function()
		if conn then
			conn:Disconnect()
		end
	end)
end

local function buildGui()
	local sg = Instance.new("ScreenGui")
	sg.Name = "CT_Hangout"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = false
	sg.DisplayOrder = 6
	sg.Parent = player:WaitForChild("PlayerGui")


	-- pet style: a light rounded HUD card (the clip's "NEXT UP" bar) with the words in the deep title blue
	local box = UI.frame(sg, { Name = "HangoutCard", BackgroundColor3 = PET.QuestBody })
	-- a bit below the middle (the top middle belongs to the objective / gift notes)
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 0.62, -58)
	box.Size = UDim2.fromOffset(300, 40)
	box.Visible = false
	PetStyle.round(box, 999)
	PetStyle.edge(box, PET.QuestEdge, 2.5)
	local c = UI.text(box, "", { Name = "Text", TextSize = UI.T.Head, Font = UI.Head, TextColor3 = PET.TitleEdge, Outline = false, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0) })
	c.TextXAlignment = Enum.TextXAlignment.Center
	card = c
	cardBox = box

	local row = Instance.new("Frame")
	row.Name = "EmoteRow"
	row.BackgroundTransparency = 1
	-- a 2-wide grid right above the Emote button (left of the jump button, clear of the joystick)
	row.AnchorPoint = Vector2.new(1, 1)
	row.Position = UDim2.new(1, -184, 1, -96) -- placeEmote() moves it with the button
	row.Size = UDim2.fromOffset(2 * 82, math.ceil(#Hangout.Emotes / 2) * 50)
	row.Visible = false
	local list = Instance.new("UIGridLayout")
	list.CellSize = UDim2.fromOffset(76, 44)
	list.CellPadding = UDim2.fromOffset(6, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	for i, e in Hangout.Emotes do
		local b = UI.button(row, e.Name, "gray", function()
			row.Visible = false
			playEmote(e.Key)
		end, { TextSize = UI.T.Small })
		b.Size = UDim2.fromOffset(76, 44)
		b.LayoutOrder = i
	end
	row.Parent = sg
	emoteRow = row

	local eb = UI.button(sg, "Emote", "gray", function()
		row.Visible = not row.Visible
		if row.Visible then
			pop(row, 0.6)
		end
	end, { TextSize = UI.T.Small })
	eb.Name = "EmoteButton"
	eb.AnchorPoint = Vector2.new(1, 1)
	eb.Position = UDim2.new(1, -184, 1, -40)
	eb.Size = UDim2.fromOffset(62, 48)
	emoteBtn = eb

	-- Structural spot (shared/SafeZones): on touch the button stays out of the jump-button zone (bottom right) and
	-- out of the bottom-centre band where a ProximityPrompt card (egg "Hatch!") appears. This gui has no UIScale, so
	-- the geometry runs in logical px (screen px / UI.Scale) and the result is converted back; PC keeps its old spot.
	local function placeEmote()
		local px = sg.AbsoluteSize
		if px.X < 2 or px.Y < 2 then
			return
		end
		local k = math.max(UI.Scale, 0.1)
		local touch = UserInputService.TouchEnabled
		local r = SafeZones.bottomButton(px.X / k, px.Y / k, 62 / k, 48 / k, touch, k)
		local rightPx = px.X - (r.x + r.w) * k
		local bottomPx = px.Y - (r.y + r.h) * k
		eb.Position = UDim2.new(1, -rightPx, 1, -bottomPx)
		row.Position = UDim2.new(1, -rightPx, 1, -(bottomPx + 48 + 8))
	end
	placeEmote()
	sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeEmote)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(placeEmote)
end

local function refreshVisibility()
	-- hunts, the pet tower and pet battles have their own buttons where EMOTE sits (it covered SPECIAL)
	local inHunt = State.Match ~= nil or player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true
	-- a menu on screen (UI.modal) hides the floating EMOTE button and its grid; closing the menu brings them back
	local menuOpen = UI.modalOpen() ~= nil
	if emoteBtn then
		emoteBtn.Visible = not inHunt and not menuOpen
	end
	if (inHunt or menuOpen) and emoteRow then
		emoteRow.Visible = false
	end
	refreshCard()
end

-- Events from the server -------------------------------------------------------------------------------------------------

local function onEvent(kind: string, data: any)
	if kind == "Whack" and type(data) == "table" then
		local left = math.max(0, math.ceil((data.Ends or 0) - Workspace:GetServerTimeNow()))
		cardText.Whack = "EGG POP: " .. tostring(data.Hits) .. " taps, " .. left .. "s"
		refreshCard()
	elseif kind == "WhackDone" then
		cardText.Whack = nil
		refreshCard()
	elseif kind == "Event" and type(data) == "table" then
		cardText.Event = if data.State == "Start" and type(data.Name) == "string" then data.Name .. " is on!" else nil
		refreshCard()
	elseif kind == "RockHit" and type(data) == "table" then
		cardText.Event = "GOLDEN EGG: " .. tostring(data.Left) .. " taps left"
		refreshCard()
	end
end

function HangoutView.start()
	buildGui()
	Net.event("HangoutEvent").OnClientEvent:Connect(onEvent)
	Net.event("RareHatch").OnClientEvent:Connect(function(kind: any, p: any)
		if kind == "Local" and type(p) == "table" then
			HangoutView.beam(p.Rarity)
		end
	end)
	State.Changed.Event:Connect(function(what: string)
		if what == "Match" then
			refreshVisibility()
		end
	end)
	player:GetAttributeChangedSignal("InTower"):Connect(refreshVisibility)
	player:GetAttributeChangedSignal("InBattle"):Connect(refreshVisibility)
	UI.ModalChanged.Event:Connect(refreshVisibility) -- the shared "a menu is open" signal: EMOTE hides under a menu
	refreshVisibility()
end

return HangoutView
