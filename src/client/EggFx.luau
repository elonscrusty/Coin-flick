--!strict
-- Client side of the egg events (src/server/EggEvents.luau, tuning in src/shared/EggConfig.luau). Cosmetic only:
--   ("Wobble", { Round, Ids })                  a small patch of pile eggs rocks on their bases for a moment
--   ("Overtime", { Round, Id })                 time is up: the pet egg glows gold (Highlight) so the race ends
--   ("Chirp", { Round, Pos })                  a nearby pile egg chirps (sometimes the pet egg): a 3D sound (EggConfig.Chirp.SoundId,
--                                               silent while it is 0) and a small floating note at Pos
--   ("Boots", { Round, UserId, Until, Seconds }) sparkles on that player's avatar; for the local player also a
--                                               small boot badge with a countdown (own ScreenGui, lower left)
-- The server decides every pick and the speed itself; nothing here changes gameplay.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local EggConfig = require(Shared.EggConfig)
local State = require(script.Parent.State)
local PileView = require(script.Parent.PileView)
local UI = require(script.Parent.ui.UI)
local Audio = require(script.Parent.Audio)
local HitFx = require(script.Parent.HitFx)

local EggFx = {}

local player = Players.LocalPlayer
local wobbling: { [Model]: boolean } = {}

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

-- Rocks the egg on its base: a few damped side-to-side tilts, then back to exactly where it was. Stops at once
-- if anything else moves the model meanwhile (a pile settle), so the pile view always wins.
local function wobble(model: Model)
	if wobbling[model] then
		return
	end
	wobbling[model] = true
	local cfg = EggConfig.Wobble
	local base = model:GetPivot()
	local half = model:GetExtentsSize().Y * 0.5
	local deg = cfg.Degrees * (if settings().ReducedMotion == true then 0.5 else 1)
	local last = base
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function stop(restore: boolean)
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if restore and model.Parent then
			model:PivotTo(base)
		end
		wobbling[model] = nil
	end
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			stop(false)
			return
		end
		if (model:GetPivot().Position - last.Position).Magnitude > 0.01 then
			stop(false) -- moved by the pile view: leave it where it was put
			return
		end
		local k = (os.clock() - t0) / cfg.Seconds
		if k >= 1 then
			stop(true)
			return
		end
		local a = math.rad(deg) * math.sin(k * cfg.Shakes * 2 * math.pi) * (1 - k)
		local cf = base * CFrame.new(0, -half, 0) * CFrame.Angles(a * 0.4, 0, a) * CFrame.new(0, half, 0)
		last = cf
		model:PivotTo(cf)
	end)
end

-- Boots: sparkles on an avatar ---------------------------------------------------------------

local function sparkle(uid: number, seconds: number)
	if settings().LowEffects == true and uid ~= player.UserId then
		return
	end
	local p = Players:GetPlayerByUserId(uid)
	local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local old = root:FindFirstChild("EggBootsSparkles")
	if old then
		old:Destroy()
	end
	local s = Instance.new("Sparkles")
	s.Name = "EggBootsSparkles"
	s.SparkleColor = UI.Colors.Gold
	s.Parent = root
	task.delay(seconds, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Boots: a dust trail at the feet while that avatar runs on the ground (one loop per player, ends itself).
local trailUntil: { [number]: number } = {}

local function dustTrail(uid: number, seconds: number)
	if settings().LowEffects == true and uid ~= player.UserId then
		return
	end
	local had = trailUntil[uid] ~= nil
	trailUntil[uid] = os.clock() + seconds
	if had then
		return
	end
	local conn: RBXScriptConnection? = nil
	local nextPuff = 0
	conn = RunService.Heartbeat:Connect(function()
		local p = Players:GetPlayerByUserId(uid)
		local char = p and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if os.clock() > (trailUntil[uid] or 0) or not root or not hum or State.Match == nil then
			trailUntil[uid] = nil
			if conn then
				conn:Disconnect()
			end
			return
		end
		local v = root.AssemblyLinearVelocity
		local now = os.clock()
		if now >= nextPuff and hum.FloorMaterial ~= Enum.Material.Air and Vector3.new(v.X, 0, v.Z).Magnitude > 6 then
			nextPuff = now + 0.12
			local foot = root.Position - Vector3.new(0, root.Size.Y * 0.5 + hum.HipHeight - 0.2, 0)
			HitFx.trail(foot - Vector3.new(v.X, 0, v.Z).Unit * 0.6)
		end
	end)
end

-- Boots: the local badge ---------------------------------------------------------------------

local gui: ScreenGui? = nil
local timerLabel: TextLabel? = nil
local bootsUntil = 0
local ticking = false

local function badge(): (ScreenGui, TextLabel)
	if gui and timerLabel and gui.Parent then
		return gui :: ScreenGui, timerLabel :: TextLabel
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "EggFxBoots"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = false
	sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 12
	sg.Enabled = false
	sg.Parent = player:WaitForChild("PlayerGui")
	-- lower left, above the bottom edge: below the HUD's left tiles and left of the tool dock in every layout
	local box = UI.frame(sg, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, UI.T.Edge, 1, -80),
		Size = UDim2.fromOffset(112, 36),
		BackgroundColor3 = UI.Colors.Hud,
		BackgroundTransparency = 0.15,
	})
	UI.corner(box, UI.T.Radius)
	UI.stroke(box, UI.Colors.Gold, 2)
	-- REPLACE: real boot icon image; a drawn stand-in (shaft + foot) until then
	local icon = UI.frame(box, { Name = "Boot", Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1 })
	local shaft = UI.frame(icon, { Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(11, 20), BackgroundColor3 = UI.Colors.Gold })
	UI.corner(shaft, 3)
	local foot = UI.frame(icon, { Position = UDim2.fromOffset(6, 16), Size = UDim2.fromOffset(20, 10), BackgroundColor3 = UI.Colors.Gold })
	UI.corner(foot, 4)
	local label = UI.text(box, "FAST 8s", {
		Name = "Timer",
		Font = UI.Head,
		TextSize = UI.T.Small,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -44, 1, 0),
	})
	gui, timerLabel = sg, label
	return sg, label
end

local function showBadge(untilT: number)
	bootsUntil = untilT
	local sg, label = badge()
	sg.Enabled = true
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		while true do
			local left = bootsUntil - Workspace:GetServerTimeNow()
			if left <= 0 or State.Match == nil then
				break
			end
			label.Text = string.format("FAST %ds", math.ceil(left))
			task.wait(0.2)
		end
		sg.Enabled = false
		ticking = false
	end)
end

-- Chirp: a sound and a small note at a point near (never on) the pet egg ---------------------------

local function chirp(pos: Vector3)
	local cfg = EggConfig.Chirp
	local anchor = Instance.new("Part")
	anchor.Name = "EggChirp"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0))
	anchor.Parent = Workspace
	if cfg.SoundId ~= 0 then
		local snd = Instance.new("Sound")
		snd.SoundId = "rbxassetid://" .. tostring(cfg.SoundId)
		snd.Volume = cfg.Volume
		snd.RollOffMaxDistance = cfg.RollOff
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.Parent = anchor
		snd:Play()
	else
		-- the shared sound list (PetSoundIds.EggChirp via Audio): silent while that id is 0 too
		Audio.play("EggChirp", { Pos = pos + Vector3.new(0, 1.5, 0) })
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(34, 34)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = cfg.RollOff * 2
	bb.Parent = anchor
	local note = UI.text(bb, "\u{266A}", { Font = UI.Head, TextSize = 28, TextColor3 = UI.Colors.Gold, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	note.TextWrapped = false
	local reduced = settings().ReducedMotion == true
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local k = (os.clock() - t0) / 1.2
		if k >= 1 or not anchor.Parent then
			if conn then
				conn:Disconnect()
			end
			anchor:Destroy()
			return
		end
		bb.StudsOffset = Vector3.new(if reduced then 0 else math.sin(k * 8) * 0.3, k * 2, 0)
		note.TextTransparency = k * k
	end)
end

-- The overtime glow on one pile egg (Highlight + breathing pulse). Returns true when it was added now.
local function glow(id: number): boolean
	local model = PileView.eggModel(id)
	if not model or model:FindFirstChild("OvertimeGlow") then
		return false
	end
	local h = Instance.new("Highlight")
	h.Name = "OvertimeGlow"
	h.FillColor = EggConfig.Overtime.GlowColor
	-- white rim: the low-poly nest bed is gold too, so a gold-on-gold glow got lost (QA 2026-10-13)
	h.OutlineColor = Color3.new(1, 1, 1)
	h.OutlineTransparency = 0
	h.FillTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = model
	if not UI.Reduced then
		-- slow breathing pulse (client visual only), ends with the glow
		task.spawn(function()
			local t0 = os.clock()
			while h.Parent do
				h.FillTransparency = 0.3 + 0.2 * math.sin((os.clock() - t0) * math.pi) -- ~2 s per breath
				task.wait()
			end
		end)
	end
	return true
end

-- The glowing egg of this round. The pile swaps an egg's model when it becomes exposed (filler -> full egg) or moves,
-- which dropped the Highlight (Studio 2026-10-15: the clock reached 0:00 and no gold egg could be found), so the
-- glow is put back on whatever model the egg has now, until the egg leaves the pile or the round changes.
local glowRound: any, glowId: number? = nil, nil
task.spawn(function()
	while true do
		task.wait(0.25)
		if glowId ~= nil then
			if glowRound ~= PileView.roundId() then
				glowRound, glowId = nil, nil
				PileView.setPriority(nil)
			else
				glow(glowId)
			end
		end
	end
end)

function EggFx.start()
	Net.event("EggEvent").OnClientEvent:Connect(function(kind: any, data: any)
		if type(data) ~= "table" then
			return
		end
		if kind == "Wobble" then
			if type(data.Ids) ~= "table" or data.Round ~= PileView.roundId() then
				return
			end
			for i, id in data.Ids do
				if i > EggConfig.Wobble.PatchMax then
					break
				end
				local model = if type(id) == "number" then PileView.eggModel(id) else nil
				if model then
					wobble(model)
				end
			end
		elseif kind == "Overtime" then
			if type(data.Id) ~= "number" or data.Round ~= PileView.roundId() then
				return
			end
			glowRound, glowId = data.Round, data.Id
			PileView.setPriority(data.Id) -- the pickup action takes it first once it is in reach
			if glow(data.Id) then
				local model = PileView.eggModel(data.Id)
				if model then
					wobble(model)
				end
			end
		elseif kind == "Chirp" then
			if typeof(data.Pos) ~= "Vector3" or data.Round ~= PileView.roundId() then
				return
			end
			chirp(data.Pos)
		elseif kind == "Boots" then
			if type(data.UserId) ~= "number" or type(data.Until) ~= "number" then
				return
			end
			local seconds = math.max(0, data.Until - Workspace:GetServerTimeNow())
			sparkle(data.UserId, seconds)
			dustTrail(data.UserId, seconds)
			if data.UserId == player.UserId then
				showBadge(data.Until)
				Audio.play("SpeedBoots") -- PetSoundIds.SpeedBoots (0 = silent)
			end
		end
	end)
end

return EggFx
