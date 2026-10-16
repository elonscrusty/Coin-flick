--!strict
-- Tap to fight (carter 2026-10-16: "Fight part is thin"): the player's hands in a Pet Battle.
-- TAP anywhere on the fight = a quick extra hit (a POW pop under the finger at once, the server's hit on the rival pet
-- when it lands) and a COMBO counter. A gold ring on one of our pets = a rival's big move is coming: BLOCK in time
-- for PERFECT! BLOCK with no ring misses and locks for a moment. Intents only (PvpAction Tap / Block); the server
-- decides every hit (PvpRules.tap / block). PvpPanel builds it into the fight HUD and feeds it the fight events.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PvpConfig = require(Shared.PvpConfig)
local UI = require(script.Parent.UI)
local Juice = require(script.Parent.Juice)
local TowerView = require(script.Parent.Parent.TowerView)
local Audio = require(script.Parent.Parent.Audio)
local PetFx = require(script.Parent.Parent.PetFx)

local T = UI.T
local player = Players.LocalPlayer

local TapFight = {}

local GOLD = Color3.fromRGB(255, 205, 70)
local SHIELD = Color3.fromRGB(105, 218, 232)
local BLOCK_W = 132
local RING_LIFE = 2.2 -- a ring the server never answered (the pet fainted first) fades after this

local send: (any) -> () = function() end
local blockBtn: TextButton? = nil
local comboLabel: TextLabel? = nil
local on = false -- taps count (fighting, not counting in)
local mySide = 1
local lastSend = -math.huge
local combo, lastTapAt = 0, -math.huge
local lockedUntil = 0
local rings: { [string]: { Gui: BillboardGui, At: number } } = {} -- [attacker id] = ring on our pet
local hinted = false

local function partOf(m: Model?): BasePart?
	if m == nil then
		return nil
	end
	return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
end

local function clearRing(from: string)
	local r = rings[from]
	if r then
		rings[from] = nil
		r.Gui:Destroy()
	end
end

local function anyRing(): boolean
	return next(rings) ~= nil
end

-- BLOCK glows gold while a ring is up, dims while locked after a miss.
local function styleBlock()
	local b = blockBtn
	if b == nil then
		return
	end
	local label = b:FindFirstChild("Label") :: TextLabel?
	local locked = os.clock() < lockedUntil
	UI.setEnabled(b, not locked, if anyRing() then "gold" else "blue")
	if label then
		label.Text = if locked then "MISSED" elseif anyRing() then "BLOCK!" else "BLOCK"
	end
end

-- A pulsing gold ring around our pet that a rival's big move is aimed at.
local function ring(from: string, to: string)
	clearRing(from)
	local part = partOf(TowerView.model(to))
	if part == nil then
		return
	end
	local g = Instance.new("BillboardGui")
	g.Name = "BlockRing"
	g.Adornee = part
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Size = UDim2.fromScale(7, 7)
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 6
	stroke.Parent = circle
	circle.Parent = g
	local word = Instance.new("TextLabel")
	word.BackgroundTransparency = 1
	-- under the ring: the pet's name and health bar sit above it
	word.AnchorPoint = Vector2.new(0.5, 0)
	word.Position = UDim2.fromScale(0.5, 1)
	word.Size = UDim2.fromScale(0.9, 0.16)
	word.Font = UI.Head
	word.Text = "BLOCK!"
	word.TextScaled = true
	word.TextColor3 = GOLD
	word.TextStrokeTransparency = 0
	word.Parent = g
	g.Parent = player:FindFirstChildOfClass("PlayerGui")
	-- shrinks in toward the pet: the hit lands as the ring closes
	TweenService:Create(circle, TweenInfo.new(PvpConfig.Block.WarnTime, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0.45, 0.45) }):Play()
	rings[from] = { Gui = g, At = os.clock() }
	Audio.play("CountdownTick", { Volume = 0.5, Key = "pvp:ring" })
	styleBlock()
end

local function comboText()
	local l = comboLabel
	if l == nil then
		return
	end
	if combo >= 2 then
		l.Visible = true
		l.Text = "COMBO x" .. combo
		l.TextColor3 = if combo > PvpConfig.Tap.ComboMax then GOLD else Color3.new(1, 1, 1)
		l.Rotation = if combo % 2 == 0 then -4 else 4
	else
		l.Visible = false
	end
end

-- A POW under the finger at once (the server's hit follows on the rival pet).
local function pow(at: Vector2)
	local screen = UI.screen()
	local inset = screen.AbsolutePosition
	local scale = math.max(UI.Scale, 0.1)
	local l = UI.text(screen, if combo > PvpConfig.Tap.ComboMax then "POW!!" else "POW!", {
		Font = UI.Head, TextSize = T.Body, Outline = "Strong", TextColor3 = if combo > 5 then GOLD else Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(90, 36), TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset((at.X - inset.X) / scale, (at.Y - inset.Y) / scale), ZIndex = 40,
	})
	l.Rotation = math.random(-12, 12)
	TweenService:Create(l, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		Position = l.Position - UDim2.fromOffset(0, 40), TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.4, function()
		l:Destroy()
	end)
end

local function tap(at: Vector2)
	if not on then
		return
	end
	local now = os.clock()
	if now - lastSend < 1 / PvpConfig.Tap.PerSecond then
		return -- the server would drop it anyway
	end
	lastSend = now
	combo = if now - lastTapAt <= PvpConfig.Tap.ComboGap then combo + 1 else 1
	lastTapAt = now
	send({ Op = "Tap" })
	pow(at)
	comboText()
	Audio.play("TrainTap", { Volume = 0.45, Pitch = 1 + math.min(combo, PvpConfig.Tap.ComboMax) * 0.03, Key = "pvp:tap" })
end

-- The fight HUD's BLOCK button (left of SPECIAL) and combo counter. `special` = the SPECIAL button to sit beside.
function TapFight.build(hud: Frame, special: TextButton, sendFn: (any) -> ())
	send = sendFn
	local b = UI.button(hud, "BLOCK", "blue", function()
		if not on or os.clock() < lockedUntil then
			return
		end
		send({ Op = "Block" })
	end, { Name = "Block", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(BLOCK_W, T.Primary.Y + 6) })
	b:SetAttribute("DisabledFill", Color3.fromRGB(40, 48, 66))
	b:SetAttribute("DisabledText", Color3.new(1, 1, 1))
	blockBtn = b
	local function place()
		b.Size = UDim2.fromOffset(BLOCK_W, special.Size.Y.Offset)
		b.Position = special.Position - UDim2.fromOffset(special.Size.X.Offset + 10, 0)
	end
	place()
	special:GetPropertyChangedSignal("Position"):Connect(place)
	special:GetPropertyChangedSignal("Size"):Connect(place)
	local cl = UI.text(hud, "COMBO x2", {
		Name = "Combo", Font = UI.Head, TextSize = T.Title, Outline = "Strong", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.78, 0), Size = UDim2.fromOffset(260, 48), TextXAlignment = Enum.TextXAlignment.Center,
	})
	cl.Visible = false
	comboLabel = cl
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not on or not hud.Visible then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			tap(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	-- rings the server never answered, the combo running out, the BLOCK lock wearing off
	task.spawn(function()
		while true do
			task.wait(0.15)
			local now = os.clock()
			for from, r in rings do
				if now - r.At > RING_LIFE then
					clearRing(from)
				end
			end
			if combo > 0 and now - lastTapAt > PvpConfig.Tap.ComboGap then
				combo = 0
				comboText()
			end
			if on then
				styleBlock()
			end
		end
	end)
end

-- A fight starts (`side` = ours) or counts in; taps count from `live` on.
function TapFight.start(side: number)
	mySide = side
	combo, lockedUntil = 0, 0
	on = false
	for from in rings do
		clearRing(from)
	end
	comboText()
	styleBlock()
end

function TapFight.live()
	on = true
	if not hinted then
		hinted = true
		UI.notify("TAP the screen to hit! Gold ring on your pet? Tap BLOCK!", "info", { Tag = "pvptap" })
	end
	styleBlock()
end

function TapFight.stop()
	on = false
	combo = 0
	for from in rings do
		clearRing(from)
	end
	comboText()
	if blockBtn then
		UI.setEnabled(blockBtn, false, "blue")
	end
end

-- Fight events from the server (after TowerView drew the plain hits).
function TapFight.events(list: { any })
	for _, e in list do
		local k = e.Kind
		if k == "Tap" then
			local m = TowerView.model(e.To or "")
			if m then
				local mine = e.Side == mySide
				pcall(PetFx.hit, m, { Damage = if mine then e.Amount else nil, Quiet = not mine })
			end
		elseif k == "Warn" then
			if e.Side == mySide and on then
				ring(e.From, e.To)
			end
		elseif k == "Blocked" then
			if e.Side == mySide then
				local r = rings[e.From or ""]
				local circle = r and r.Gui:FindFirstChildOfClass("Frame")
				local stroke = circle and circle:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = SHIELD -- guarded: waits for the move to bounce off
				end
			end
		elseif k == "Perfect" then
			clearRing(e.From or "")
			local m = TowerView.model(e.To or "")
			if e.Side == mySide then
				if m then
					pcall(PetFx.pop, m:GetPivot().Position + Vector3.new(0, 4, 0), "PERFECT!", GOLD, true)
				end
				Juice.banner("PERFECT BLOCK!", SHIELD, 0.7)
				Audio.play("PetCrit", { Volume = 0.7, Key = "pvp:perfect" })
			elseif m then
				pcall(PetFx.pop, m:GetPivot().Position + Vector3.new(0, 4, 0), "BLOCKED", SHIELD, false)
			end
			styleBlock()
		elseif k == "BlockMiss" then
			if e.Side == mySide then
				lockedUntil = os.clock() + (e.Amount or PvpConfig.Block.MissLock)
				Audio.play("Denied", { Volume = 0.5, Key = "pvp:miss" })
				styleBlock()
			end
		elseif k == "Hit" then
			-- the move landed without a block: its ring goes
			if rings[e.From or ""] then
				clearRing(e.From)
				styleBlock()
			end
		end
	end
end

return TapFight
