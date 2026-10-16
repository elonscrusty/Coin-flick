--!strict
-- The coin yard (shared/CoinYard): builds the fenced yard east of the park, the two portal arches, the floor flip pads,
-- the egg stand and the battle ring in the clearing, and pays flips. The server rolls every flip and writes the cash;
-- the client only walks. Cash is the normal profile Cash, so it buys eggs at the Pet Shop like shell coins do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoinYard = require(Shared.CoinYard)
local Net = require(Shared.Net)
local RobuxConfig = require(Shared.RobuxConfig)
local Profiles = require(script.Parent.Profiles)
local Kit = require(script.Parent.KitParts)
local ArenaKit = require(script.Parent.ArenaKit)
local KitPlace = require(script.Parent.KitPlace)

local part, deco, folder = Kit.part, Kit.deco, Kit.folder
local M = Enum.Material

local CoinYardService = {}

local PANEL = "RobuxShop" -- the Pet Shop panel (same as the EGG SHOP hut prompt)
local GOLD = Color3.fromRGB(255, 205, 60)
local STONE = Color3.fromRGB(150, 140, 120)
local WOOD = Color3.fromRGB(112, 76, 46) -- darker than it looks: Studio paints props paler
local GRASS = Color3.fromRGB(110, 190, 80)
local COIN_COLOURS: { [string]: Color3 } = {
	Copper = Color3.fromRGB(205, 127, 80),
	Silver = Color3.fromRGB(210, 215, 225),
	Gold = Color3.fromRGB(255, 205, 60),
	Diamond = Color3.fromRGB(120, 230, 255),
}

local rng = Random.new()
local padAt: { [Player]: { [BasePart]: number } } = {}
type Chain = { n: number, at: number }
local chain: { [Player]: Chain } = {}
local portalAt: { [Player]: number } = {}

-- Slow sparkles that make a part read as magic (client-side particles, cheap).
local function sparkle(p: BasePart, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(2, 4)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(20, 20)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Parent = p
end

-- Loops a property between two values forever (one tween per part).
local function pulse(p: Instance, props: { [string]: any }, seconds: number)
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props):Play()
end

local function toast(player: Player, text: string, kind: string)
	Net.event("Toast"):FireClient(player, text, kind)
end

-- Sign with fitted text (SignLayout: explicit TextSize; a TextScaled label comes out 8 px tall).
local function sign(parent: Instance, name: string, cf: CFrame, size: Vector3, text: string, preset: string)
	local p = deco(part(parent, name, size, cf, Color3.fromRGB(96, 66, 42), M.SmoothPlastic))
	local label = ArenaKit.label(p, Enum.NormalId.Front, text, Color3.fromRGB(255, 240, 200), nil, preset)
	KitPlace.outline(label)
	return p
end

-- Pays one flip on a pad (server side only).
local function flipPad(player: Player, pad: BasePart)
	local data = Profiles.get(player)
	if not data or not Profiles.isLoaded(player) then
		return
	end
	local now = os.clock()
	local mine = padAt[player]
	if not mine then
		mine = {}
		padAt[player] = mine
	end
	if now - (mine[pad] or 0) < CoinYard.PadCooldown then
		return
	end
	mine[pad] = now
	local c: Chain = chain[player] or { n = 0, at = 0 }
	c.n = CoinYard.nextChain(c.n, c.at, now)
	c.at = now
	chain[player] = c
	local tier = RobuxConfig.eggTier(data.UnlockedTiers)
	local base = CoinYard.baseFor(RobuxConfig.roundCoins(tier))
	local boost = Profiles.petBoosts(data).Coins
	local r = CoinYard.flip(base, rng:NextNumber(), rng:NextNumber(), c.n, boost)
	data.Cash += r.cash
	Profiles.changed(player)

	-- everyone sees the coin spin and the amount
	local disc = pad:FindFirstChild("Coin") :: BasePart?
	if disc then
		disc.Color = COIN_COLOURS[r.coin] or GOLD
		TweenService:Create(disc, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = disc.CFrame * CFrame.Angles(0, 0, math.pi * 4) }):Play()
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 44)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = pad
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = if r.heads then (COIN_COLOURS[r.coin] or GOLD) else Color3.fromRGB(220, 220, 230)
	t.TextStrokeTransparency = 0
	t.Text = ("%s +%d%s"):format(if r.heads then "HEADS" else "tails", r.cash, if c.n > 1 then " x" .. c.n else "")
	t.Parent = gui
	gui.Parent = pad
	task.delay(0.9, function()
		gui:Destroy()
	end)
	if r.heads and r.coin ~= "Copper" then
		toast(player, ("%s coin! +%d coins"):format(r.coin, r.cash), "rare")
	end
end

local function hookTouch(pad: BasePart, fn: (Player) -> ())
	pad.Touched:Connect(function(hit)
		local char = hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			fn(player)
		end
	end)
end

local function teleport(player: Player, x: number, z: number, faceX: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		(char :: Model):PivotTo(CFrame.lookAt(Vector3.new(x, 4, z), Vector3.new(x + faceX, 4, z)))
	end
end

-- A glowing doorway part: stepping in sends the player across.
local function arch(parent: Instance, name: string, x: number, z: number, text: string, toX: number, toZ: number, face: number)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	for _, s in { -1, 1 } do
		part(m, "Pillar", Vector3.new(3, 16, 3), CFrame.new(x, 8, z + s * 7), STONE, M.Cobblestone)
	end
	part(m, "Beam", Vector3.new(3.4, 3, 17), CFrame.new(x, 16.5, z), WOOD, M.Wood)
	sign(m, "Sign", CFrame.new(x - face * 1.8, 16.5, z) * CFrame.Angles(0, face > 0 and math.pi / 2 or -math.pi / 2, 0), Vector3.new(14, 2.4, 0.2), text, "Landmark")
	local door = part(m, "Door", Vector3.new(1, 13, 11), CFrame.new(x, 6.5, z), GOLD, M.Neon)
	door.Transparency = 0.45
	door.CanCollide = false
	sparkle(door, Color3.fromRGB(255, 240, 150), 18, 0.7)
	pulse(door, { Transparency = 0.7, Color = Color3.fromRGB(120, 230, 255) }, 1.4)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 225, 150)
	glow.Range = 24
	glow.Parent = door
	deco(part(m, "Coin", Vector3.new(0.5, 3, 3), CFrame.new(x - face * 1.8, 19.5, z) * CFrame.Angles(0, face > 0 and math.pi / 2 or -math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Neon, Enum.PartType.Cylinder))
	door:SetAttribute("CoinYardPortal", true)
	hookTouch(door, function(player)
		local now = os.clock()
		if now - (portalAt[player] or 0) < 3 then
			return
		end
		portalAt[player] = now
		teleport(player, toX, toZ, face)
	end)
	return m
end

-- Trees, bushes and lamp posts round the inside of the fence (chunky low-poly, bright). Kept clear of the pad grid,
-- the arch lane (z within 10 of 0 at the west fence) and the signs on the north wall.
local function scenery(f: Folder)
	local Y = CoinYard
	local cx, cz = Y.Centre.X, Y.Centre.Z
	local hx, hz = Y.Size.X / 2, Y.Size.Z / 2
	local leaf = { Color3.fromRGB(70, 175, 70), Color3.fromRGB(110, 200, 60), Color3.fromRGB(50, 150, 90) }
	local function tree(x: number, z: number, k: number)
		deco(part(f, "TreeTrunk", Vector3.new(2, 5 * k, 2), CFrame.new(x, 2.5 * k, z), WOOD, M.Wood))
		deco(part(f, "TreeTop", Vector3.new(9 * k, 8 * k, 9 * k), CFrame.new(x, 8 * k, z), leaf[(math.floor(x + z) % 3) + 1], M.Grass, Enum.PartType.Ball))
	end
	local function bush(x: number, z: number, hue: Color3)
		deco(part(f, "Bush", Vector3.new(5, 3.6, 5), CFrame.new(x, 1.6, z), Color3.fromRGB(80, 185, 80), M.Grass, Enum.PartType.Ball))
		for i = 1, 3 do
			deco(part(f, "Bloom", Vector3.new(1, 1, 1), CFrame.new(x + (i - 2) * 1.5, 3.2, z + (i % 2) * 1.6 - 0.8), hue, M.SmoothPlastic, Enum.PartType.Ball))
		end
	end
	local function lamp(x: number, z: number)
		part(f, "LampPost", Vector3.new(1, 9, 1), CFrame.new(x, 4.5, z), WOOD, M.Wood)
		local bulb = deco(part(f, "LampBulb", Vector3.new(2.4, 2.4, 2.4), CFrame.new(x, 9.6, z), Color3.fromRGB(255, 230, 130), M.Neon, Enum.PartType.Ball))
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 225, 150)
		l.Range = 22
		l.Brightness = 1.5
		l.Parent = bulb
	end
	local blooms = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 230, 90), Color3.fromRGB(150, 130, 255), Color3.fromRGB(255, 255, 255) }
	for i = 0, 5 do
		local x = cx - hx + 12 + i * 15.5
		tree(x, cz + hz - 7, if i % 2 == 0 then 1 else 0.8)
		bush(x + 7, cz + hz - 4, blooms[(i % 4) + 1])
		lamp(x + 3.5, cz + hz - 4)
	end
	for i = 0, 3 do
		local z = cz - hz + 14 + i * 18
		if math.abs(z - cz) > 10 then
			tree(cx + hx - 6, z, 1)
			tree(cx - hx + 6, z, 0.9)
		end
		bush(cx - hx + 4, z + 8, blooms[(i % 4) + 1])
	end
	for i = 0, 2 do
		bush(cx + 20 + i * 18, cz - hz + 4, blooms[((i + 1) % 4) + 1])
		lamp(cx + 11 + i * 18, cz - hz + 4)
	end
end

local function buildYard(root: Instance)
	local Y = CoinYard
	local f = folder(root, Y.FolderName)
	local cx, cz = Y.Centre.X, Y.Centre.Z
	local hx, hz = Y.Size.X / 2, Y.Size.Z / 2
	part(f, "Floor", Vector3.new(Y.Size.X, 2, Y.Size.Z), CFrame.new(cx, -1, cz), GRASS, M.Grass)
	-- low stone fence + invisible tall walls so nobody leaves the yard sideways
	local function wall(x: number, z: number, sx: number, sz: number)
		part(f, "Fence", Vector3.new(sx, 3, sz), CFrame.new(x, 1.5, z), STONE, M.Cobblestone)
		local inv = part(f, "Bounds", Vector3.new(sx, 80, sz), CFrame.new(x, 40, z), Color3.new(), M.SmoothPlastic)
		inv.Transparency = 1
		inv.CanQuery = false
	end
	wall(cx, cz - hz, Y.Size.X, 2)
	wall(cx, cz + hz, Y.Size.X, 2)
	wall(cx - hx, cz, 2, Y.Size.Z)
	wall(cx + hx, cz, 2, Y.Size.Z)

	scenery(f)

	-- flip pads: a flat pad with a coin disc standing on it
	local P = Y.Pads
	for col = 1, P.Cols do
		for row = 1, P.Rows do
			local x, z = Y.padCentre(col, row)
			local pad = part(f, "FlipPad", Vector3.new(P.Size, 0.6, P.Size), CFrame.new(x, 0.3, z), if (col + row) % 2 == 0 then Color3.fromRGB(255, 230, 140) else Color3.fromRGB(255, 190, 90), M.SmoothPlastic)
			pad:SetAttribute("CoinPad", true)
			-- the coin stands on its edge (cylinder axis along X) so a flip turns it about Z like a real coin
			deco(part(pad, "Coin", Vector3.new(0.6, 4, 4), CFrame.new(x, 3.2, z), GOLD, M.Metal, Enum.PartType.Cylinder))
			sparkle(pad, GOLD, 3, 0.5)
			deco(part(pad, "Rim", Vector3.new(P.Size - 3, 0.2, P.Size - 3), CFrame.new(x, 0.65, z), Color3.fromRGB(255, 250, 200), M.Neon))
			hookTouch(pad, function(player)
				flipPad(player, pad)
			end)
		end
	end

	-- odds sign (rule: odds always shown), facing the arrival side
	local lines = CoinYard.oddsLines()
	sign(f, "OddsSign", CFrame.new(cx - 26, 10.5, cz - hz + 3) * CFrame.Angles(0, math.pi, 0), Vector3.new(34, 16, 0.4), "COIN ODDS\n" .. table.concat(lines, "\n"), "Placard")
	sign(f, "HowSign", CFrame.new(cx + 22, 10, cz - hz + 3) * CFrame.Angles(0, math.pi, 0), Vector3.new(28, 10, 0.4), "FLIP THE PADS!\nCoins buy eggs here\nChain flips: +10% each", "Placard")

	-- egg stand: opens the Pet Shop (odds shown there before any buy)
	local stand = part(f, Y.StandName, Vector3.new(12, 6, 6), CFrame.new(Y.Stand.X, 3, Y.Stand.Z) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(80, 170, 190), M.SmoothPlastic)
	deco(part(f, "StandRoof", Vector3.new(15, 1, 9), CFrame.new(Y.Stand.X, 11, Y.Stand.Z) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(230, 90, 90), M.SmoothPlastic))
	for _, s in { -1, 1 } do
		part(f, "StandPost", Vector3.new(1, 11, 1), CFrame.new(Y.Stand.X - 3.5, 5.5, Y.Stand.Z + s * 6), WOOD, M.Wood)
	end
	local egg = deco(part(f, "StandEgg", Vector3.new(4, 5, 4), CFrame.new(Y.Stand.X, 14, Y.Stand.Z), Color3.fromRGB(170, 235, 200), M.SmoothPlastic, Enum.PartType.Ball))
	egg.Size = Vector3.new(4, 5, 4)
	for i, c in { Color3.fromRGB(255, 130, 170), Color3.fromRGB(255, 220, 90), Color3.fromRGB(140, 160, 255) } do
		local a = i * 2.1
		deco(part(egg, "EggSpot", Vector3.new(1.1, 1.1, 1.1), CFrame.new(Y.Stand.X - 1.9 * math.cos(a), 14 + (i - 2) * 1.1, Y.Stand.Z + 1.9 * math.sin(a)), c, M.SmoothPlastic, Enum.PartType.Ball))
	end
	sparkle(egg, Color3.fromRGB(255, 255, 200), 8, 0.6)
	pulse(egg, { Color = Color3.fromRGB(255, 200, 225) }, 1.5)
	sign(f, "StandSign", CFrame.new(Y.Stand.X - 3.2, 8.5, Y.Stand.Z) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(10, 2.2, 0.2), "EGG STAND", "Landmark")
	local pp = Kit.prompt(stand, "Open", "Egg Stand", PANEL, 14)
	pp.Enabled = true

	arch(f, Y.ArchName, Y.YardArch.X, Y.YardArch.Z, "BACK TO PARK", Y.ParkArrive.X, Y.ParkArrive.Z, -1)
end

local function buildParkSide(root: Instance)
	local Y = CoinYard
	local f = folder(root, Y.FolderName .. "_Gate")
	arch(f, Y.ArchName .. "_Park", Y.ParkArch.X, Y.ParkArch.Z, "COIN YARD", Y.Arrive.X, Y.Arrive.Z, 1)
	-- battle ring in the middle clearing: stepping on it opens the battle card (PvpService hooks parts with PvpPad)
	local R = Y.Ring
	local ring = part(f, "BattleRing", Vector3.new(0.6, R.Diameter, R.Diameter), CFrame.new(R.X, 0.3, R.Z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(230, 70, 70), M.SmoothPlastic, Enum.PartType.Cylinder)
	ring:SetAttribute("PvpPad", true)
	deco(part(f, "BattleRingGlow", Vector3.new(0.5, R.Diameter + 3, R.Diameter + 3), CFrame.new(R.X, 0.15, R.Z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 150, 60), M.SmoothPlastic, Enum.PartType.Cylinder))
	local inner = deco(part(f, "BattleRingInner", Vector3.new(0.7, R.Diameter - 4, R.Diameter - 4), CFrame.new(R.X, 0.32, R.Z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 240, 200), M.SmoothPlastic, Enum.PartType.Cylinder))
	inner.Name = "BattleRingInner"
	sparkle(ring, Color3.fromRGB(255, 200, 120), 14, 0.8)
	pulse(inner, { Color = Color3.fromRGB(255, 200, 200) }, 1.2)
	sign(f, "BattleRingSign", CFrame.new(R.X, 6, R.Z - R.Diameter / 2 - 1) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 3, 0.3), "BATTLE RING\nstep in to fight!", "Landmark")
end

function CoinYardService.start()
	local root = Workspace
	buildYard(root)
	buildParkSide(root)
	Players.PlayerRemoving:Connect(function(p)
		padAt[p] = nil
		chain[p] = nil
		portalAt[p] = nil
	end)
end

return CoinYardService
