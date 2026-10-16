--!strict
-- Round intro (client only, cosmetic; the server's Countdown phase still decides when the hunt starts):
--   * Whoosh: entering a hunt (State.Match appears) or going back to the lobby (it clears) covers the camera jump
--     with a short swirl that fades out. Reduce Motion: a plain quick fade, no swirl.
--   * Countdown: big 3 - 2 - 1 - GO! in the middle of the screen, read from the server's EndsAt (nothing local
--     decides the start). Own small ScreenGui (the HUD keeps its own "Starting in" line).
--   * Swoop: during the countdown the camera glides from high over the pile down into the player's eyes, ending
--     looking at the pile, so first person resumes from there. A CameraMode cinematic (released before the hunt
--     starts); skipped with Reduce Motion or when the countdown is already almost over.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ContentProvider = game:GetService("ContentProvider")

local State = require(script.Parent.State)
local CameraMode = require(script.Parent.CameraMode)
local UI = require(script.Parent.ui.UI)
local ZoneThemes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ZoneThemes"))
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local IntroRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("IntroRules"))

local RoundIntro = {}

local CINE = "RoundSwoop"
local SWOOP_MAX = 2.6 -- seconds
-- Swoop framing (polish: the pile read small and far at round start). The path starts lower and nearer the pile and
-- a tighter lens frames the egg pile larger; the lens eases back to Config.Camera.Fov before first person resumes.
local SWOOP_HIGH = Vector3.new(0, 26, 0) -- start: above the pile, a little past its centre (was 42 up, 18 past)
local SWOOP_PAST = 8
local SWOOP_MID_OUT, SWOOP_MID_UP = 9, 14 -- the bend of the glide, on the player's side (was 14 out, 26 up)
local SWOOP_FOV = 56 -- degrees at the start of the glide (first person uses Config.Camera.Fov)
local LOAD_MAX = 4 -- seconds the entry cover waits for the arena's meshes before it lifts anyway
local GROUND_MIN = 1.2 -- with solid ground under the player the cover may lift this soon, meshes or not
local REST = UDim2.fromScale(0.5, 0.52) -- the countdown number's resting spot: screen middle, under the objective banner
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local numLabel: TextLabel? = nil
local numScale: UIScale? = nil
local cover: Frame? = nil
local shown = "" -- the text on screen ("3", "2", "1", "GO!" or "")
local lastRound: any = nil
local swoopRound: any = nil
local goRound: any = nil
local hadMatch = false
local swooping = false
local arenaReady = true -- false while the entry cover waits for the arena to load (no swoop over a half-loaded map)

local function reduced(): boolean
	local p = State.Profile
	return UI.Reduced or (p ~= nil and p.Settings ~= nil and p.Settings.ReducedMotion == true)
end

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui :: ScreenGui
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "CT_RoundIntro"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 15 -- over the HUD (5), under menus (20)
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = player:WaitForChild("PlayerGui")
	gui = sg
	-- the countdown number
	local holder = Instance.new("Frame")
	holder.Name = "Count"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = REST
	holder.ZIndex = 20 -- the countdown number shows over the entry cover
	holder.Size = UDim2.fromOffset(260, 150)
	holder.Parent = sg
	local sc = Instance.new("UIScale")
	sc.Parent = holder
	numScale = sc
	local t = UI.text(holder, "", {
		Name = "Text", Font = UI.Head, TextSize = 120, Outline = "Strong", TextColor3 = UI.Colors.Gold,
		Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Visible = false,
	})
	numLabel = t
	-- the whoosh cover
	local c = Instance.new("Frame")
	c.Name = "Whoosh"
	c.Size = UDim2.fromScale(1, 1)
	c.BackgroundColor3 = Color3.fromRGB(255, 248, 228)
	c.BackgroundTransparency = 1
	c.BorderSizePixel = 0
	c.Visible = false
	c.ZIndex = 10
	c.Parent = sg
	cover = c
	return sg
end

-- Countdown number -----------------------------------------------------------------------------------------

-- GO!: one ring bursts out from behind the word and fades. It stays small (a second, wider ring read on phones as
-- a big faint circle round the whole screen). The ring ends itself.
local function ringWave(holder: Frame)
	local sg = gui
	if not sg then
		return
	end
	local ring = Instance.new("Frame")
	ring.Name = "GoRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = holder.Position
	ring.Size = UDim2.fromOffset(80, 80)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI.Colors.Green
	stroke.Thickness = 8
	stroke.Parent = ring
	ring.Parent = sg
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(240, 240) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1, Thickness = 2 }):Play()
	task.delay(0.47, function()
		ring:Destroy()
	end)
end

local function setNumber(text: string)
	if text == shown then
		return
	end
	shown = text
	ensureGui()
	local t, sc = numLabel, numScale
	if not t or not sc then
		return
	end
	if text == "" then
		t.Visible = false
		return
	end
	t.Text = text
	t.Visible = true
	t.TextTransparency = 0
	t.TextColor3 = if text == "GO!" then UI.Colors.Green else UI.Colors.Gold
	local stroke = t:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 0
	end
	local holder = t.Parent :: Frame
	if reduced() then
		sc.Scale = 1
		holder.Position = REST
	else
		-- a gentle pop (1.6 reached up into the objective banner on short phones)
		sc.Scale = 1.25
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- each number drops in from a little above and bounces to rest
		holder.Position = REST - UDim2.fromScale(0, 0.04)
		TweenService:Create(holder, TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = REST }):Play()
		if text == "GO!" then
			ringWave(holder)
		end
	end
	if text == "GO!" then
		task.delay(0.55, function()
			if shown ~= "GO!" then
				return
			end
			TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			if stroke and stroke:IsA("UIStroke") then
				TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
			task.delay(0.32, function()
				if shown == "GO!" then
					setNumber("")
				end
			end)
		end)
	end
end

-- Whoosh ---------------------------------------------------------------------------------------------------

-- The hunt arena's meshes near `centre` (the zone set the server clones in at round start). The first hunt on a
-- phone downloads them while the countdown runs: without waiting, the camera showed nests floating over sky.
local function arenaMeshes(centre: Vector3): { Instance }
	local list: { Instance } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("MeshPart") and (d.Position - centre).Magnitude < 140 then
			table.insert(list, d)
		end
	end
	return list
end

local whooshId = 0
-- Solid ground under the player's feet (the arena floor near them has streamed in).
local function groundUnderPlayer(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char :: Instance }
	return Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params) ~= nil
end

-- `centre` (entering a hunt): the cover stays up until the arena there has loaded (at most LOAD_MAX, or GROUND_MIN
-- once the ground under the player is in), then fades. While it waits it is not blank: it takes the zone's ground
-- colour and says which map is loading (`tier` = the hunt's tier id).
local function whoosh(centre: Vector3?, tier: string?)
	ensureGui()
	local c = cover
	if not c then
		return
	end
	whooshId += 1
	local my = whooshId
	for _, ch in c:GetChildren() do
		ch:Destroy()
	end
	c.Visible = true
	c.BackgroundTransparency = 0
	local plain = reduced()
	local theme = if centre then ZoneThemes.get(tier) else nil
	c.BackgroundColor3 = Color3.fromRGB(255, 248, 228)
	if not plain then
		-- a soft turning colour swirl over the cover while it fades (no spiral arms: as they thinned out they read as
		-- white lines across the screen); entering a hunt it runs from the zone's ground colour to its sky
		local grad = Instance.new("UIGradient")
		grad.Color = if theme
			then ColorSequence.new(theme.Floor:Lerp(Color3.new(1, 1, 1), 0.25), Color3.fromRGB(150, 210, 255))
			else ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(150, 210, 255))
		grad.Parent = c
	elseif theme then
		c.BackgroundColor3 = theme.Floor:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	local loadingLabel: TextLabel? = nil
	if theme then
		-- under the countdown number (which sits in the middle), so "3" and "2" never land on an empty screen
		loadingLabel = UI.text(c, "Loading " .. (if theme.Zone == "Space" then "Space" else "the " .. theme.Zone) .. "\u{2026}", {
			Name = "Loading", Font = UI.Head, TextSize = 30, Outline = "Strong", TextColor3 = UI.Colors.Text,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.76), Size = UDim2.new(0.8, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 11,
		})
		local ll = loadingLabel :: TextLabel
		ll.TextWrapped = false
		UI.fit(ll, 30, 18)
	end
	local dur = if plain then 0.35 else 0.7
	local t0 = os.clock()
	local loaded = true
	if centre then
		loaded = false
		arenaReady = false
		task.spawn(function()
			local parts = arenaMeshes(centre)
			pcall(function()
				ContentProvider:PreloadAsync(parts)
			end)
			if my == whooshId then
				loaded = true
				arenaReady = true
			end
		end)
		task.delay(LOAD_MAX, function()
			if my == whooshId and not loaded then
				loaded = true
				arenaReady = true
			end
		end)
	end
	local waitFrom = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not loaded and os.clock() - waitFrom >= GROUND_MIN and groundUnderPlayer() then
			loaded = true -- the floor around the player is in: show the map now, the rest streams in behind
			arenaReady = true
		end
		if not loaded then
			t0 = os.clock() -- hold the cover (spinning) until the arena is there
			local grad = c:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Rotation = (os.clock() * 200) % 360
			end
			return
		end
		local k = (os.clock() - t0) / dur
		if my ~= whooshId or k >= 1 then
			if conn then
				conn:Disconnect()
			end
			if my == whooshId then
				c.Visible = false
				for _, ch in c:GetChildren() do
					ch:Destroy()
				end
			end
			return
		end
		local e = k * k
		c.BackgroundTransparency = e
		if loadingLabel then
			loadingLabel.TextTransparency = e
			local o = loadingLabel:FindFirstChildOfClass("UIStroke")
			if o then
				o.Transparency = e
			end
		end
		local grad = c:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Rotation = k * 540
		end
	end)
end

-- Swoop ----------------------------------------------------------------------------------------------------

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

-- The player's eyes looking at the egg pile (a little down, so the eggs fill the view).
local function eyeOn(head: BasePart, centre: Vector3): CFrame
	local eye = head.Position + Vector3.new(0, 0.3, 0)
	local look = Vector3.new(centre.X, eye.Y - 2.5, centre.Z)
	if (look - eye).Magnitude < 1 then
		look = eye + Vector3.new(0, -0.5, -4)
	end
	return CFrame.lookAt(eye, look)
end

-- No swoop this round (Reduce Motion, a late join, the arena still loading): the camera still starts on the pile,
-- never on whatever the spawn pad faced (walkthrough 10-14: the hunt opened on an empty lawn).
local aimRound: any = nil
local function aimAtPile(round: any, centre: any)
	if aimRound == round or swoopRound == round or swooping or typeof(centre) ~= "Vector3" then
		return
	end
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not cam or not head or not head:IsA("BasePart") then
		return
	end
	aimRound = round
	cam.CFrame = eyeOn(head, centre)
end

local function swoop(centre: Vector3, seconds: number)
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not cam or not head or not head:IsA("BasePart") then
		return
	end
	swooping = true
	CameraMode.cinematic(CINE, true)
	cam.CameraType = Enum.CameraType.Scriptable
	local function eyeFrame(): CFrame
		return eyeOn(head :: BasePart, centre)
	end
	local first = eyeFrame()
	local away = first.Position - centre
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 1 then away.Unit else Vector3.zAxis
	local high = centre + SWOOP_HIGH - away * SWOOP_PAST -- over the far side of the pile, looking down at it
	local mid = centre + away * SWOOP_MID_OUT + Vector3.new(0, SWOOP_MID_UP, 0)
	local baseFov = Config.Camera.Fov
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		if not CameraMode.inHunt() or State.Match == nil or State.Match.Phase ~= "Countdown" or not head.Parent then
			break
		end
		local k = smooth(math.clamp((os.clock() - t0) / seconds, 0, 1))
		local fin = eyeFrame()
		local p = high:Lerp(mid, k):Lerp(mid:Lerp(fin.Position, k), k)
		local target = centre:Lerp(fin.Position + fin.LookVector * 10, k)
		local cf = CFrame.lookAt(p, target)
		if k > 0.85 then
			cf = cf:Lerp(fin, (k - 0.85) / 0.15)
		end
		cam.CFrame = cf
		-- tight lens over the pile, back to the first-person lens by the end of the glide
		cam.FieldOfView = SWOOP_FOV + (baseFov - SWOOP_FOV) * smooth(math.clamp((k - 0.55) / 0.4, 0, 1))
		RunService.RenderStepped:Wait()
	end
	if cam.Parent then
		cam.CFrame = eyeFrame()
		cam.FieldOfView = baseFov
	end
	swooping = false
	CameraMode.cinematic(CINE, false)
end

-- Driver ---------------------------------------------------------------------------------------------------

local function onMatch()
	local m = State.Match
	local inMatch = m ~= nil
	if inMatch ~= hadMatch then
		hadMatch = inMatch
		whoosh(if m and typeof(m.Center) == "Vector3" then m.Center else nil, if m and type(m.Tier) == "string" then m.Tier else nil)
	end
	if not m then
		-- a new match starts its rounds at 1 again: forget this match's rounds (a stale "GO shown" kept a "1" up)
		lastRound, goRound, swoopRound, aimRound = nil, nil, nil, nil
		setNumber("")
		return
	end
	local key = IntroRules.roundKey(m.Key, m.Round)
	if key ~= lastRound then
		lastRound = key
		setNumber("")
	end
	if m.Phase == "Countdown" then
		local left = (tonumber(m.EndsAt) or 0) - Workspace:GetServerTimeNow()
		local centre = m.Center
		if arenaReady and swoopRound ~= key and not swooping and left > 1.2 and typeof(centre) == "Vector3" and not reduced() then
			swoopRound = key
			task.spawn(swoop, centre :: Vector3, math.min(SWOOP_MAX, left - 0.25))
		elseif arenaReady and reduced() then
			aimAtPile(key, centre)
		end
	elseif m.Phase == "Searching" then
		aimAtPile(key, m.Center) -- once, only when no swoop ran this round
		local next = IntroRules.onSearching(shown, goRound, key)
		if next == "GO!" then
			goRound = key
		end
		if next then
			setNumber(next)
		end
	elseif shown ~= "" and shown ~= "GO!" then
		setNumber("")
	end
end

local started = false
function RoundIntro.start()
	if started then
		return
	end
	started = true
	ensureGui()
	State.Changed.Event:Connect(function(what)
		if what == "Match" then
			onMatch()
		end
	end)
	-- the number follows the server clock between phase messages
	task.spawn(function()
		while true do
			task.wait(0.1)
			local m = State.Match
			if m and m.Phase == "Countdown" and not UI.blocked() then
				local left = math.ceil((tonumber(m.EndsAt) or 0) - Workspace:GetServerTimeNow())
				if left >= 1 and left <= 3 then
					setNumber(tostring(left))
				end
			end
		end
	end)
	onMatch()
end

return RoundIntro
