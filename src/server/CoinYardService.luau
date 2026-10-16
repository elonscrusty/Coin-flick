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

local part, deco, folder = Kit.part, Kit.deco, Kit.folder
local M = Enum.Material

local CoinYardService = {}

local PANEL = "RobuxShop" -- the Pet Shop panel (same as the EGG SHOP hut prompt)
local GOLD = Color3.fromRGB(255, 205, 60)
local STONE = Color3.fromRGB(150, 140, 120)
local WOOD = Color3.fromRGB(150, 100, 60)
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

local function toast(player: Player, text: string, kind: string)
	Net.event("Toast"):FireClient(player, text, kind)
end

local function sign(parent: Instance, name: string, cf: CFrame, size: Vector3, text: string, px: number?)
	local p = deco(part(parent, name, size, cf, Color3.fromRGB(40, 32, 28), M.SmoothPlastic))
	local label = Kit.label(p, Enum.NormalId.Front, text, Color3.fromRGB(255, 240, 200), nil, nil, px)
	label.TextWrapped = true
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
		TweenService:Create(disc, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = disc.CFrame * CFrame.Angles(math.pi * 4, 0, 0) }):Play()
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
	sign(m, "Sign", CFrame.new(x - face * 1.8, 16.5, z) * CFrame.Angles(0, face > 0 and math.pi / 2 or -math.pi / 2, 0), Vector3.new(14, 2.4, 0.2), text, 40)
	local door = part(m, "Door", Vector3.new(1, 13, 11), CFrame.new(x, 6.5, z), GOLD, M.Neon)
	door.Transparency = 0.45
	door.CanCollide = false
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

	-- flip pads: a flat pad with a coin disc standing on it
	local P = Y.Pads
	for col = 1, P.Cols do
		for row = 1, P.Rows do
			local x, z = Y.padCentre(col, row)
			local pad = part(f, "FlipPad", Vector3.new(P.Size, 0.6, P.Size), CFrame.new(x, 0.3, z), if (col + row) % 2 == 0 then Color3.fromRGB(255, 230, 140) else Color3.fromRGB(255, 190, 90), M.SmoothPlastic)
			pad:SetAttribute("CoinPad", true)
			local disc = deco(part(pad, "Coin", Vector3.new(0.5, 4, 4), CFrame.new(x, 2.6, z) * CFrame.Angles(0, 0, 0), GOLD, M.Metal, Enum.PartType.Cylinder))
			disc.CFrame = CFrame.new(x, 2.6, z) * CFrame.Angles(0, 0, math.pi / 2)
			hookTouch(pad, function(player)
				flipPad(player, pad)
			end)
		end
	end

	-- odds sign (rule: odds always shown), facing the arrival side
	local lines = CoinYard.oddsLines()
	sign(f, "OddsSign", CFrame.new(cx - 40, 9, cz - hz + 3) * CFrame.Angles(0, math.rad(0), 0), Vector3.new(34, 11, 0.4), "COIN ODDS\n" .. table.concat(lines, "\n"), 18)
	sign(f, "HowSign", CFrame.new(cx - 8, 9, cz - hz + 3), Vector3.new(30, 8, 0.4), "WALK ON A PAD TO FLIP IT!\nCoins buy eggs at the egg stand.\nFlip fast to build a chain: +10% each!", 22)

	-- egg stand: opens the Pet Shop (odds shown there before any buy)
	local stand = part(f, Y.StandName, Vector3.new(12, 6, 6), CFrame.new(Y.Stand.X, 3, Y.Stand.Z) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(80, 170, 190), M.SmoothPlastic)
	deco(part(f, "StandRoof", Vector3.new(15, 1, 9), CFrame.new(Y.Stand.X, 11, Y.Stand.Z) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(230, 90, 90), M.SmoothPlastic))
	for _, s in { -1, 1 } do
		part(f, "StandPost", Vector3.new(1, 11, 1), CFrame.new(Y.Stand.X - 3.5, 5.5, Y.Stand.Z + s * 6), WOOD, M.Wood)
	end
	local egg = deco(part(f, "StandEgg", Vector3.new(4, 5, 4), CFrame.new(Y.Stand.X, 8.5, Y.Stand.Z), Color3.fromRGB(255, 245, 210), M.SmoothPlastic, Enum.PartType.Ball))
	egg.Size = Vector3.new(4, 5, 4)
	sign(f, "StandSign", CFrame.new(Y.Stand.X - 3.2, 8.5, Y.Stand.Z) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(10, 2.2, 0.2), "EGG STAND", 40)
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
	local inner = deco(part(f, "BattleRingInner", Vector3.new(0.7, R.Diameter - 4, R.Diameter - 4), CFrame.new(R.X, 0.32, R.Z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 240, 200), M.SmoothPlastic, Enum.PartType.Cylinder))
	inner.Name = "BattleRingInner"
	sign(f, "BattleRingSign", CFrame.new(R.X, 6, R.Z - R.Diameter / 2 - 1) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 3, 0.3), "BATTLE RING\nstep in to fight!", 40)
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
