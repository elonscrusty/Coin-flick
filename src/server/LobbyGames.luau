--!strict
-- Lobby mini-games (owner pick 2026-10-14, lobby hangout idea 4). Small coin prizes, all paid through one daily cap
-- (Hangout.Games.DailyCoinCap, LobbyHangout.payGame). The server decides every hit, tap and place; clients only draw
-- (client/HangoutView). The pet race and the egg toss were removed (owner picks 2026-10-14); leftover RaceTrack /
-- EggToss models are cleared.
--
--   WhackStump   "Play": rocks pop out of the stump's holes for Whack.Seconds; tap a rock (ClickDetector) before it
--                drops back. One player at a time. Holes: parts / attachments named Hole1..N, else a ring on the top.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)
local Net = require(Shared.Net)
local H = require(script.Parent.LobbyHangout)

local LobbyGames = {}

local G = Hangout.Games
local clock = function(): number
	return Workspace:GetServerTimeNow()
end
-- Tests only: replace the server clock.
function LobbyGames.setClock(fn: () -> number)
	clock = fn
end

local folder: Folder? = nil
local function partsFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "CT_HangoutGames" -- outside the lobby folder: the lobby's decor policy turns clicks off
	made.Parent = Workspace
	folder = made
	return made
end

local function event(player: Player?, kind: string, payload: any)
	if player then
		Net.event("HangoutEvent"):FireClient(player, kind, payload)
	else
		Net.event("HangoutEvent"):FireAllClients(kind, payload)
	end
end

local function partOf(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- Whack-a-rock --------------------------------------------------------------------------------------------------------

type Whack = { Stump: BasePart, Holes: { Vector3 }, Player: Player?, Hits: number, Rock: BasePart?, Ends: number }
local whacks: { Whack } = {}
local whackCool: { [Player]: number } = {}

local function holesOf(stump: Instance, top: BasePart): { Vector3 }
	local out: { Vector3 } = {}
	for _, d in stump:GetDescendants() do
		if string.match(d.Name, "^Hole%d+$") then
			if d:IsA("BasePart") then
				table.insert(out, d.Position + Vector3.new(0, d.Size.Y / 2, 0))
			elseif d:IsA("Attachment") then
				table.insert(out, d.WorldPosition)
			end
		end
	end
	if #out == 0 then
		local w = G.Whack
		local c = top.CFrame * CFrame.new(0, top.Size.Y / 2, 0)
		for i = 1, w.Holes do
			local a = (i - 1) / w.Holes * math.pi * 2
			table.insert(out, (c * CFrame.new(math.cos(a) * w.HoleRadius, 0, math.sin(a) * w.HoleRadius)).Position)
		end
	end
	return out
end

local function popRock(w: Whack, at: Vector3): BasePart
	local rock = Instance.new("Part")
	rock.Name = "WhackRock"
	rock.Size = Vector3.new(1.8, 1.6, 1.8)
	rock.Color = Color3.fromRGB(150, 140, 128)
	rock.Material = Enum.Material.Slate
	rock.Anchored = true
	rock.CanCollide = false
	rock.CFrame = CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 40
	cd.Parent = rock
	cd.MouseClick:Connect(function(clicker: Player)
		if clicker == w.Player and w.Rock == rock then
			w.Hits += 1
			w.Rock = nil
			rock:Destroy()
			event(clicker, "Whack", { Hits = w.Hits, Ends = w.Ends, Pos = at })
		end
	end)
	rock.Parent = partsFolder()
	return rock
end

local function runWhack(w: Whack, player: Player)
	local cfg = G.Whack
	w.Player, w.Hits = player, 0
	w.Ends = clock() + cfg.Seconds
	event(player, "Whack", { Hits = 0, Ends = w.Ends })
	local last = 0
	while clock() < w.Ends and player.Parent and H.near(player, w.Stump.Position, cfg.LeaveDistance) do
		local i = math.random(1, #w.Holes)
		if i == last and #w.Holes > 1 then
			i = i % #w.Holes + 1
		end
		last = i
		local rock = popRock(w, w.Holes[i])
		w.Rock = rock
		local t0 = clock()
		while w.Rock == rock and clock() - t0 < cfg.PopSeconds do
			task.wait(0.05)
		end
		if w.Rock == rock then
			w.Rock = nil
			rock:Destroy()
		end
		task.wait(cfg.Gap)
	end
	local hits = w.Hits
	w.Player = nil
	whackCool[player] = os.clock() + cfg.Cooldown
	if player.Parent then
		local paid = H.payGame(player, Hangout.whackPrize(hits))
		event(player, "WhackDone", { Hits = hits, Coins = paid })
		H.toast(player, "Egg Pop: " .. hits .. " taps! +" .. paid .. " coins" .. (if paid == 0 and hits > 0 then " (daily game coins all won!)" else ""), "ok")
	end
end

H.onPrompt("Whack", function(player, prompt)
	local w: Whack? = nil
	for _, x in whacks do
		if prompt:IsDescendantOf(x.Stump) or prompt.Parent == x.Stump then
			w = x
		end
	end
	if not w then
		return
	end
	if w.Player then
		H.toast(player, if w.Player == player then "Tap the eggs!" else w.Player.DisplayName .. " is playing. Wait your turn!", "info")
		return
	end
	if (whackCool[player] or 0) > os.clock() then
		return
	end
	task.spawn(runWhack, w, player)
end)

-- Test hook: the rock up right now on stump `i` (nil = none).
function LobbyGames.whackRock(i: number?): BasePart?
	local w = whacks[i or 1]
	return if w then w.Rock else nil
end

-- Hooks -----------------------------------------------------------------------------------------------------------------

function LobbyGames.adopt(root: Instance)
	for _, d in root:GetDescendants() do
		if d.Name == "WhackStump" then
			local top = partOf(d)
			if top then
				local known = false
				for _, w in whacks do
					known = known or w.Stump == top
				end
				if not known then
					table.insert(whacks, { Stump = top, Holes = holesOf(d, top), Player = nil, Hits = 0, Rock = nil, Ends = 0 })
					H.prompt(top, "Whack", "Play", "Egg Pop", G.Range)
				end
			end
		elseif d.Name == "RaceTrack" or d.Name == "EggToss" then
			d:Destroy() -- the pet race and the egg toss were removed (owner picks 2026-10-14)
		end
	end
end

function LobbyGames.start(roots: { Instance })
	for _, r in roots do
		LobbyGames.adopt(r)
	end
	Players.PlayerRemoving:Connect(function(p)
		whackCool[p] = nil
	end)
end

return LobbyGames
