--!strict
-- Pet hatch reveal (2 to 6 s by rarity, see below), shown in a hero ViewportFrame over the arena:
--   0.0-0.4  the screen dims in, the closed egg (two shell halves around the pet) drops in
--   0.4-1.0  the egg wobbles harder and glowing zigzag cracks run up the seam
--   1.0-1.5  the shell halves fly apart and fade; the pet pops up out of it with a springy bounce
--   1.2-2.6  rarity-coloured rays turn behind the pet, a soft camera ease, name + rarity fade in
--            ("You hatched a Rare Fox!", the whole line at once so the rarity never shows before the name)
-- Owner pick: the whole sequence follows the rarity (Config.Hatch via PetFlair.hatchTiming): Common / Uncommon about
-- 2 s; Rare, Epic and Legendary about 6 s with the wobble, cracks and pop in slow motion, a pulsing rarity glow, a
-- choir build-up from the start and the species' roar at the pop (SoundConfig; silent while the ids are 0). Only the
-- local animation clock is warped (PetFlair.hatchWarp). Then it holds the final
-- frame (the same GeodeView framing the results card uses) until the results arrive or the player taps. A tap
-- after 0.5 s jumps to the final frame; a tap on the final frame closes it. Purely cosmetic: the server saved the
-- pet before the Reveal event was sent. Reduced motion shows the final frame at once.
-- Party hunts: players who did NOT win watch the winner's hatch in a small picture-in-picture box at the right
-- edge (no full-screen dim, controls stay usable); the winner, solo and practice hunts get the full screen.
-- Polish: the shell halves tumble down, bounce once and fade; the rarity line slams in (big -> squash -> settle)
-- with a short shake, stronger for higher rarities.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PetFlair = require(Shared.PetFlair)
local GeodeGen = require(Shared.GeodeGen)
local GeodeModel = require(Shared.GeodeModel)
local UI = require(script.Parent.ui.UI)
local GeodeView = require(script.Parent.ui.GeodeView)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)
local PetMotionBridge = require(script.Parent.PetMotionBridge)
local SpeciesPool = require(Shared.SpeciesPool)
local LuckEvents = require(Shared.LuckEvents)
local PetStatView = require(Shared.PetStatView)

local C = UI.Colors
local T = UI.T

local RevealView = {}

local ANIM_END = PetFlair.HatchAnim.End

-- 0..1 from the configured rarity multipliers (Common small, Legendary full); no invented odds
local function rarityStrength(rarity: string): number
	local m = (Config.RarityMult :: any)[rarity] or 1
	local top = 1
	for _, v in Config.RarityMult :: any do
		top = math.max(top, v)
	end
	return math.clamp(math.log(math.max(m, 1)) / math.log(math.max(top, 2)), 0, 1)
end
local SKIP_AFTER = 0.5
local HINT_AT = 2 -- seconds before the "Tap to continue" hint fades in
local SPIN_RATE = 0.5 -- radians per second the finished pet turns

-- backdrop tint per zone (tier ids: Gravel = Meadow, Quarry = Forest, Cavern = Snow, Volcanic = Volcano, Meteor = Space)
local ZONE_SHADE: { [string]: Color3 } = {
	Gravel = Color3.fromRGB(34, 62, 36),
	Quarry = Color3.fromRGB(22, 50, 34),
	Cavern = Color3.fromRGB(36, 56, 92),
	Volcanic = Color3.fromRGB(88, 36, 18),
	Meteor = Color3.fromRGB(56, 32, 92),
}

-- "1 in N" for this pet: its rarity chance times its species share, from the same public odds the Pet Book shows
local function oddsText(spec: any): string?
	local ok, text = pcall(function(): string?
		local wsum = 0
		for _, r in Config.Rarities do
			wsum += Config.RarityWeights[r]
		end
		local rp = {}
		for _, r in Config.Rarities do
			rp[r] = Config.RarityWeights[r] / wsum
		end
		local share = SpeciesPool.chance(spec.Tier, spec.Mineral, os.time(), rp)
		local p = (rp[spec.Rarity] or 0) * share
		-- the one odds-line rule (shared LuckEvents.oneIn): whole numbers, no line for a common result
		local n = LuckEvents.oneIn(p, spec.Rarity)
		return if n then "1 in " .. UI.num(n) .. " chance!" else nil
	end)
	return if ok then text else nil
end

local gui: Frame? = nil
local conn: RBXScriptConnection? = nil
local playing = false
local skippedBefore = false -- the player skipped a hatch this session: quiet hatches then open on the final frame

local function ease(k: number): number -- smooth in-out
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

local function easeOutBack(k: number): number
	k = math.clamp(k, 0, 1)
	local c1, c3 = 1.3, 2.3
	return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

local function span(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

function RevealView.close()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	Effects.clear()
	playing = false
	if gui then
		gui:Destroy()
		gui = nil
		UI.block("reveal", false) -- harmless when the compact box never blocked
	end
end

function RevealView.isOpen(): boolean
	return gui ~= nil
end

-- True while the sequence is still running (not yet on its final frame). The results card waits for
-- this to turn false, so the opening is never cut short by the server's Results event.
function RevealView.isPlaying(): boolean
	return gui ~= nil and playing
end

local function article(word: string): string
	return if string.find(string.lower(string.sub(word, 1, 1)), "[aeiou]") then "an" else "a"
end

-- res: the server's Reveal payload (Specimen, Kind, Winner...). headline: the discovery line.
-- iWon: the local player won it (confetti; versus fanfare when res.Kind is not Solo).
function RevealView.play(res: { [string]: any }, headline: string, iWon: boolean)
	RevealView.close()
	-- someone else's find in a party hunt: picture-in-picture instead of the full screen
	local compact = not iWon and res.Kind ~= "Tutorial" and res.Kind ~= "Solo"
	if not compact then
		UI.block("reveal", true)
	end
	local spec = res.Specimen
	local reduced = UI.Reduced
	local root = UI.overlay()
	local shade: Frame
	if compact then
		local side = math.floor(math.clamp(math.min(UI.Logical.X, UI.Logical.Y) * 0.42, 140, 210))
		shade = UI.frame(root, {
			Name = "Reveal", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.46, 0), Size = UDim2.fromOffset(side, side + 18),
			BackgroundColor3 = ZONE_SHADE[spec.Tier] or Color3.fromRGB(34, 26, 52), BackgroundTransparency = 1, Active = true, ZIndex = 5, ClipsDescendants = true,
		})
		UI.corner(shade, T.RadiusLg)
	else
		shade = UI.frame(root, { Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = ZONE_SHADE[spec.Tier] or Color3.fromRGB(34, 26, 52), BackgroundTransparency = 1, Active = true, ZIndex = 5 })
	end
	gui = shade
	local rarity: string = spec.Rarity or "Common"
	local tint: Color3 = (Config.RarityColors :: any)[rarity] or Color3.new(1, 1, 1)
	local strength = rarityStrength(rarity)
	if compact then
		UI.stroke(shade, tint, 2)
	end
	-- layout: full screen, or the small box (headline on top, the name under the pet, no facts / hint)
	local stageSize = if compact then UDim2.new(1, -8, 1, -48) else UDim2.new(1, 0, 1, -170)
	local stagePos = if compact then UDim2.new(0.5, 0, 0.5, -2) else UDim2.new(0.5, 0, 0.5, -16)
	-- real seconds -> animation time for this rarity (about 2 s, or about 6 s of slow motion for Rare+)
	local timing = PetFlair.hatchTiming(rarity)
	local END = timing.Total
	local function warp(rt: number): number
		return PetFlair.hatchWarp(timing, rt)
	end
	-- rarity rays: thin bars turning behind the pet, plus a soft disc
	local glow = UI.frame(shade, { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = stagePos, Size = stageSize, BackgroundTransparency = 1, ClipsDescendants = true })
	local rays: { Frame } = {}
	local rayCount = 6 + math.floor(6 * strength)
	for i = 1, rayCount do
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.5)
		r.SizeConstraint = Enum.SizeConstraint.RelativeYY
		r.Size = UDim2.fromScale(0.07, 2.2)
		r.BackgroundColor3 = tint
		r.BackgroundTransparency = 1
		r.BorderSizePixel = 0
		r.Rotation = i / rayCount * 180
		r.Parent = glow
		rays[i] = r
	end
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.SizeConstraint = Enum.SizeConstraint.RelativeYY
	disc.Size = UDim2.fromScale(0.8, 0.8)
	disc.BackgroundColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.3)
	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0.5, 0)
	dc.Parent = disc
	disc.Parent = glow
	local head = UI.text(shade, headline, {
		Font = UI.Head, TextSize = if compact then T.Small else 30, TextColor3 = C.Yellow, AnchorPoint = Vector2.new(0.5, 0),
		Position = if compact then UDim2.new(0.5, 0, 0, 3) else UDim2.new(0.5, 0, 0, 10), Size = if compact then UDim2.new(1, -10, 0, 20) else UDim2.new(0.9, 0, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1,
	})
	local vp, model, cam = GeodeView.make(shade, spec, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = stagePos, Size = stageSize,
	})
	local petName = GeodeGen.displayName(spec)
	local title = if iWon then string.format("You hatched %s %s %s!", article(rarity), rarity, petName) else string.format("%s %s", rarity, petName)
	local labelsPos = if compact then UDim2.new(0.5, 0, 1, -3) else UDim2.new(0.5, 0, 1, -30)
	local labels = UI.frame(shade, { AnchorPoint = Vector2.new(0.5, 1), Position = labelsPos, Size = if compact then UDim2.new(1, -8, 0, 22) else UDim2.new(0.9, 0, 0, 100), BackgroundTransparency = 1 })
	UI.list(labels, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center)
	local name = UI.text(labels, title, { Font = UI.Head, TextSize = if compact then T.Small else 24, Size = UDim2.new(1, 0, 0, if compact then 20 else 30), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Config.RarityTextColors[rarity], LayoutOrder = 1, TextTransparency = 1 })
	-- the rarity slam: the line lands big, squashes past its size and settles (UIScale, so the fitted text keeps its fit)
	local slam = Instance.new("UIScale")
	slam.Parent = name
	-- the rarity colour gets a light-to-deep gradient across the line
	local nameGrad = Instance.new("UIGradient")
	local nameCol = Config.RarityTextColors[rarity] or tint
	nameGrad.Color = ColorSequence.new(nameCol:Lerp(Color3.new(1, 1, 1), 0.45), nameCol, nameCol:Lerp(tint, 0.6):Lerp(Color3.new(0, 0, 0), 0.15))
	nameGrad.Parent = name
	name.TextColor3 = Color3.new(1, 1, 1) -- the gradient multiplies the text colour: white keeps its colours true
	local pose = (Config.FormationNames :: any)[spec.Formation] or ""
	-- the new pet's POWER and "Lv 1/cap" (carter's one "bigger = better" number, PetStatView); old line without a Seed
	local power = PetStatView.power(spec)
	local lv, cap = PetStatView.levelOf(spec)
	local factsText = if power then rarity .. "  ·  POWER " .. UI.num(power) .. "  ·  " .. PetStatView.levelText(lv, cap) else rarity .. "  ·  " .. pose .. "  ·  " .. string.format("%.2f kg", spec.Mass or 0)
	local facts = UI.text(labels, factsText, {
		Font = UI.Bold, TextSize = T.Head, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Muted, LayoutOrder = 2, TextTransparency = 1,
	})
	facts.Visible = not compact
	-- odds ("1 in 250!")
	local extraText = oddsText(spec) or ""
	-- (no "you have N" count here: the profile sync can land before or after the reveal starts, so it could be off by one)
	local extra = UI.text(labels, extraText, {
		Font = UI.Bold, TextSize = T.Head, Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Yellow, LayoutOrder = 3, TextTransparency = 1,
	})
	extra.Visible = not compact and extraText ~= ""
	-- screen edges glow in the rarity colour (four gradient strips; fades in at the pop, not in the small box)
	local edges: { Frame } = {}
	if not compact then
		for i = 1, 4 do
			local e = Instance.new("Frame")
			e.Name = "EdgeGlow"
			e.BorderSizePixel = 0
			e.BackgroundColor3 = tint
			e.BackgroundTransparency = 1
			e.Active = false
			e.ZIndex = 6
			local horiz = i <= 2
			e.Size = if horiz then UDim2.new(1, 0, 0.16, 0) else UDim2.new(0.12, 0, 1, 0)
			e.AnchorPoint = Vector2.new(if i == 4 then 1 else 0, if i == 2 then 1 else 0)
			e.Position = UDim2.fromScale(if i == 4 then 1 else 0, if i == 2 then 1 else 0)
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new(0, 1)
			g.Rotation = if i == 1 then 90 elseif i == 2 then 270 elseif i == 3 then 0 else 180
			g.Parent = e
			e.Parent = shade
			edges[i] = e
		end
	end
	-- Epic / Legendary: one short white flash as the pet pops (never with reduced motion)
	local flash: Frame? = nil
	if not compact and not reduced and (rarity == "Epic" or rarity == "Legendary") then
		flash = UI.frame(shade, { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 7 })
	end
	-- gold / rainbow pets: the variant word pops on its own under the headline
	local variantWord = ({ Golden = "GOLD!", Rainbow = "RAINBOW!", SilverCosmic = "COSMIC!" } :: { [string]: string })[spec.Modifier]
	local vword: TextLabel? = nil
	local vscale = Instance.new("UIScale")
	if variantWord and not compact then
		vword = UI.text(shade, variantWord, {
			Font = UI.Head, TextSize = 40, TextColor3 = C.Yellow, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52),
			Size = UDim2.new(0.8, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, ZIndex = 8,
		})
		vscale.Parent = vword
	end
	-- gold / rainbow pets get a quick shimmer sweep across the stage
	local special = spec.Modifier == "Golden" or spec.Modifier == "Rainbow" or spec.Modifier == "SilverCosmic"
	local sweepClip = UI.frame(shade, { Name = "Sweep", AnchorPoint = Vector2.new(0.5, 0.5), Position = stagePos, Size = stageSize, BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 6 })
	local sweep = Instance.new("Frame")
	sweep.AnchorPoint = Vector2.new(0.5, 0.5)
	sweep.Size = UDim2.fromScale(0.22, 1.6)
	sweep.Rotation = 20
	sweep.BackgroundColor3 = if spec.Modifier == "Rainbow" then Color3.fromRGB(255, 220, 255) else Color3.fromRGB(255, 244, 190)
	sweep.BackgroundTransparency = 1
	sweep.BorderSizePixel = 0
	sweep.Visible = special and not compact
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	sg.Parent = sweep
	sweep.Parent = sweepClip
	local live = 0 -- real seconds since the reveal started (keeps running while the final frame holds)
	local hint = UI.text(shade, "Tap to skip", { Font = UI.Bold, TextSize = T.Body, TextColor3 = C.Text, Outline = "Normal", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(240, 24), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	-- the closed egg: two shell halves around the pet (pet starts tiny so nothing pokes through the shell)
	local world = vp:FindFirstChildOfClass("WorldModel") :: WorldModel
	local base = model:GetPivot()
	local halves = GeodeModel.frontHalves(spec, 1)
	local closed: { CFrame } = {}
	local cracks: { BasePart } = {}
	local shells: { BasePart } = {}
	for i, h in halves do
		h:PivotTo(base * h:GetPivot())
		closed[i] = h:GetPivot()
		h.Parent = world
		for _, d in h:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "Crack" then
					table.insert(cracks, d)
				else
					table.insert(shells, d)
				end
			end
		end
	end
	table.sort(cracks, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	local glints: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Glint" then
			table.insert(glints, d)
		end
	end
	local fit = GeodeModel.shellFit(spec, 1)
	local eggY = if fit then fit.CentreY else 1.5
	local R = if fit then fit.Width / 2 else 1.25
	local endCam = cam.CFrame
	local dist = (endCam.Position - model:GetBoundingBox().Position).Magnitude
	local dimAmbient = Color3.fromRGB(96, 88, 110)
	local dimLight = Color3.fromRGB(190, 180, 170)
	local petScale = -1

	local fired: { [string]: boolean } = {}
	local function once(key: string, fn: () -> ())
		if not fired[key] then
			fired[key] = true
			fn()
		end
	end

	local function setPetScale(k: number)
		k = math.max(k, 0.05)
		if math.abs(k - petScale) > 1e-3 then
			petScale = k
			model:ScaleTo(k)
		end
	end

	-- the pet's place for animation time t: pops out, lands with a tiny bounce, then turns slowly
	local spinFrom: number? = nil -- live time when the slow turn began (so it starts at 0, not mid-turn)
	local function placePet(t: number)
		if t >= 1.5 and spinFrom == nil then
			spinFrom = live
		end
		local spin = if reduced or t < 1.5 then 0 else (live - (spinFrom or live)) * SPIN_RATE
		local turn = CFrame.Angles(0, spin, 0)
		if t < 1.0 then
			model:PivotTo(base * CFrame.new(0, eggY * 0.6 + (1 - easeOutBack(span(t, 0, 0.4))) * R * 1.2, 0))
		else
			local pk = span(t, 1.0, 1.55)
			local hop = math.sin(math.min(pk, 1) * math.pi) * R * 0.5
			local landed = math.max(t - 1.55, 0)
			local bounce = if reduced then 0 else R * 0.09 * math.abs(math.sin(landed * 13)) * math.exp(-landed * 5)
			model:PivotTo(base * CFrame.new(0, eggY * 0.6 * (1 - ease(pk)) + hop + bounce, 0) * turn)
		end
	end

	local function animate(t: number)
		shade.BackgroundTransparency = 1 - (if compact then 0.8 else 0.86) * ease(span(t, 0, 0.4))
		-- rays fade in and turn
		local rp = ease(span(t, 1.15, 1.7))
		for i, r in rays do
			r.Rotation = i / #rays * 180 + t * 18
			r.BackgroundTransparency = 1 - rp * (0.12 + 0.18 * strength)
		end
		disc.BackgroundTransparency = 1 - rp * (0.1 + 0.12 * strength)
		if timing.Glow then
			-- Rare+: a pulsing rarity glow builds behind the egg through the slow motion, peaking at the pop
			local g = ease(span(t, 0.3, 1.0)) * (1 - 0.5 * ease(span(t, 1.2, 1.8)))
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 7)
			disc.BackgroundTransparency = math.min(disc.BackgroundTransparency, 1 - g * (0.3 + 0.2 * pulse))
		end
		-- camera: a little wide, then the ease onto the pet
		local f = 1.45 - 0.1 * ease(span(t, 0, 1.0)) - 0.35 * ease(span(t, 1.5, 2.4))
		cam.CFrame = endCam * CFrame.new(0, -0.04 * dist * (f - 1), dist * (f - 1))
		-- egg: drop in, then wobble harder and harder until it cracks
		local drop = (1 - easeOutBack(span(t, 0, 0.4))) * R * 1.2
		local wob = if t < 1.0 then math.sin(t * (14 + 22 * span(t, 0.4, 1.0))) * (0.05 + 0.2 * span(t, 0.4, 1.0)) else 0
		local rock = CFrame.new(0, eggY, 0) * CFrame.Angles(0, 0, wob) * CFrame.new(0, -eggY, 0)
		-- shell halves: tumble out and down to the floor, bounce once, then fade
		local k = span(t, 1.0, 1.9)
		local out = 1 - (1 - k) ^ 2
		local floorY = -R * 0.6
		local y
		if k < 0.6 then
			local u = k / 0.6
			y = floorY * u * u + R * 1.8 * u * (1 - u)
		else
			local v = (k - 0.6) / 0.4
			y = floorY + R * 0.5 * v * (1 - v)
		end
		for i, h in halves do
			local side = (h:GetAttribute("Side") :: number?) or (if i == 1 then -1 else 1)
			local fly = CFrame.new(side * out * R * 2.4, y, -out * R * 0.5) * CFrame.Angles(0, 0, -side * out * math.rad(150))
			h:PivotTo(base * rock * CFrame.new(0, drop, 0) * base:Inverse() * closed[i] * fly)
		end
		local fade = span(t, 1.6, 1.95)
		for _, p in shells do
			p.Transparency = fade
		end
		-- cracks run up the seam
		local n = #cracks
		for i, c in cracks do
			local at = 0.45 + 0.5 * ((i - 1) / math.max(n - 1, 1))
			c.Transparency = math.max(1 - span(t, at, at + 0.06), fade)
		end
		-- pet pops out with a bounce
		if t < 1.0 then
			setPetScale(0.2)
		else
			setPetScale(0.2 + 0.8 * easeOutBack(span(t, 1.0, 1.55)))
		end
		placePet(t)
		-- lighting brightens as it hatches
		local l = ease(span(t, 0.95, 1.5))
		vp.Ambient = dimAmbient:Lerp(GeodeView.Ambient, l)
		vp.LightColor = dimLight:Lerp(GeodeView.LightColor, l):Lerp(tint, 0.15 * strength * l)
		if timing.Glow then
			vp.LightColor = vp.LightColor:Lerp(tint, 0.35 * ease(span(t, 0.3, 1.0)) * (1 - l * 0.6))
		end
		for i, g in glints do
			local on = span(t, 1.65 + i * 0.07, 1.85 + i * 0.07)
			local tw = 0.5 + 0.5 * math.sin(t * 9 + i * 1.7)
			g.Transparency = 1 - on * (0.45 + 0.5 * tw)
		end
		head.TextTransparency = 1 - span(t, 0.95, 1.3)
		local lab = 1 - span(t, 1.6, 2.0)
		local sk = span(t, 1.6, 1.82)
		name.TextTransparency = 1 - math.min(sk * 3, 1)
		-- the whole line lands at once with the slam, so the rarity and the pet's name always show together
		extra.TextTransparency = 1 - span(t, 1.8, 2.2)
		local eg = ease(span(t, 1.0, 1.5)) * (0.35 + 0.3 * strength)
		for _, e in edges do
			e.BackgroundTransparency = 1 - eg
		end
		if flash then
			local fp = span(t, 1.0, 1.3)
			flash.BackgroundTransparency = if fp <= 0 or fp >= 1 then 1 else 1 - 0.55 * (1 - fp)
		end
		if vword then
			local vp2 = span(t, 1.85, 2.15)
			vword.TextTransparency = 1 - math.min(vp2 * 3, 1)
			vscale.Scale = if vp2 <= 0 then 2 else 1 + 1.0 * (1 - easeOutBack(vp2))
		end
		if sweep.Visible then
			local sp = span(t, 1.95, 2.45)
			sweep.BackgroundTransparency = if sp <= 0 or sp >= 1 then 1 else 0.35
			sweep.Position = UDim2.fromScale(-0.2 + 1.4 * sp, 0.5)
		end
		slam.Scale = if sk <= 0 then 2.4 else 1 + 1.4 * (1 - easeOutBack(sk))
		facts.TextTransparency = lab
		-- the shake right after it lands (stronger for rarer pets; none in the small box)
		local shake = if compact then 0 else span(t, 1.82, 1.83) * (1 - span(t, 1.83, 2.1))
		if shake > 0 and not reduced then
			local amp = (3 + 7 * strength) * shake
			labels.Position = labelsPos + UDim2.fromOffset(math.sin(t * 173) * amp, math.cos(t * 131) * amp * 0.6)
		else
			labels.Position = labelsPos
		end
		hint.Visible = t >= SKIP_AFTER and not compact
		hint.TextTransparency = if t >= ANIM_END then 1 - span(live, HINT_AT, HINT_AT + 0.6) else 0
		if t >= 1.0 then
			once("sound", function()
				-- pets never roar (owner rule): sting + sparkle swell / drum hit by rarity (shared/SoundCues.reveal)
				Audio.reveal(rarity, spec.Mineral == "CosmicDragon")
				-- the real mesh pet (PetModels template) plays its hatch animation as it pops out (optional)
				PetMotionBridge.hatch(model)
			end)
		end
		if t >= 1.1 then
			once("burst", function()
				if not reduced then
					pcall(Effects.revealBurst, vp.AbsolutePosition, vp.AbsoluteSize, tint, (0.15 + 0.85 * strength) * (if compact then 0.4 else 1))
				end
			end)
		end
		if t >= 1.75 then
			once("shimmer", function()
				if not reduced then
					pcall(Effects.shimmer, vp.AbsolutePosition, vp.AbsoluteSize)
				end
			end)
		end
		if t >= 1.9 and iWon then
			once("win", function()
				Effects.confetti()
				if res.Kind ~= "Solo" then
					Audio.play("MatchWin")
				end
			end)
		end
		if t >= ANIM_END then
			hint.Text = "Tap to continue"
		end
	end

	local t = 0 -- real seconds; animate() takes the warped animation time
	if reduced then
		t = END
	elseif timing.SlowMo then
		Audio.hatchChoir()
	end
	local pre = if reduced then 0 else 0.3 -- a short beat of dim before the egg drops in
	if skippedBefore and not reduced and not timing.Glow and not compact then
		t = END -- this player skipped before: quiet hatches open on the final frame (Rare and up still play)
		pre = 0
	end
	playing = t < END
	animate(warp(t))
	if reduced then
		shade.BackgroundTransparency = 0.12
	end
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.fromScale(1, 1)
	btn.ZIndex = 10
	btn.Parent = shade
	btn.Activated:Connect(function()
		if t >= END then
			RevealView.close()
		elseif t >= SKIP_AFTER then
			t = END
			playing = false
			skippedBefore = true
			animate(warp(t))
		end
	end)
	if reduced then
		return
	end
	conn = RunService.RenderStepped:Connect(function(dt)
		if not shade.Parent then
			RevealView.close()
			return
		end
		live += dt
		if t >= END then
			placePet(ANIM_END) -- the finished pet keeps turning while the card holds
			hint.TextTransparency = 1 - span(live, HINT_AT, HINT_AT + 0.6)
			return
		end
		if pre > 0 then
			pre -= dt
			return
		end
		t = math.min(t + dt, END)
		if t >= END then
			playing = false
		end
		animate(warp(t))
	end)
end

return RevealView
