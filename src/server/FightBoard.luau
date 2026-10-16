--!strict
-- The lobby arena's fight board (carter 2026-10-14: fights in the middle, fun to watch, make players want stronger
-- pets): a big sign floating over the arena that everyone in the lobby reads, showing the LIVE fight (names and
-- team power, or how to join) and the day's BIGGEST WIN on this server (the biggest upset: PvpRules.biggerWin).
-- A two-faced sign 16 studs over the arena centre, or where a part with attribute FightBoard = true stands (Studio);
-- fitted sign text (KitPlace / SignLayout). PvpService feeds it (FightBoard.live / FightBoard.won).

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PvpRules = require(Shared.PvpRules)
local KitPlace = require(script.Parent.KitPlace)

local FightBoard = {}

local board: Model? = nil
type Row = { Labels: { TextLabel }, W: number, H: number, Preset: string }
local rows: { [string]: Row } = {}
local best: PvpRules.Win? = nil

local GOLD = Color3.fromRGB(255, 205, 70)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 96, 86)
local FACE = Color3.fromRGB(34, 30, 52)
local W, H = 28, 11

local function setRow(name: string, text: string, color: Color3?)
	local r = rows[name]
	if not r then
		return
	end
	for _, l in r.Labels do
		local gui = l.Parent
		if gui and gui:IsA("SurfaceGui") then
			KitPlace.applyFit(gui, l, text, r.W, r.H, r.Preset)
		end
		if color then
			l.TextColor3 = color
		end
	end
end

-- Builds the board over the arena at `origin` (PvpService's arena origin) once. Returns it (tests).
function FightBoard.ensure(origin: CFrame?): Model?
	if board and board.Parent then
		return board
	end
	local at: CFrame? = nil
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("FightBoard") == true then
			at = d.CFrame -- a spot the owner placed in Studio
			break
		end
	end
	if not at then
		if not origin then
			return nil
		end
		at = CFrame.new(origin.Position + Vector3.new(0, 16, 0)) * origin.Rotation
	end
	local cf = at :: CFrame
	local m = Instance.new("Model")
	m.Name = "FightBoard"
	local slab = Instance.new("Part")
	slab.Name = "Slab"
	slab.Size = Vector3.new(W, H, 0.8)
	slab.CFrame = cf
	slab.Color = FACE
	slab.Material = Enum.Material.SmoothPlastic
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.CanTouch = false
	slab:SetAttribute("CameraIgnore", true)
	slab.Parent = m
	local trim = Instance.new("SelectionBox")
	trim.Name = "Trim"
	trim.Adornee = slab
	trim.Color3 = GOLD
	trim.LineThickness = 0.25
	trim.SurfaceTransparency = 1
	trim.Parent = slab
	-- the same three rows on both faces (spectators stand on every side of the arena)
	local spec: { { Name: string, Y: number, H: number, Preset: string, Color: Color3 } } = {
		{ Name = "Title", Y = 3.6, H = 2.6, Preset = "Heading", Color = GOLD },
		{ Name = "Live", Y = 0.1, H = 2.8, Preset = "Row", Color = WHITE },
		{ Name = "Biggest", Y = -3.4, H = 2.2, Preset = "Row", Color = GOLD },
	}
	for _, r in spec do
		local name, y, h, preset, color = r.Name, r.Y, r.H, r.Preset, r.Color
		local row: Row = { Labels = {}, W = W - 2, H = h, Preset = preset }
		for _, turn in { 0, math.pi } do
			local face = cf * CFrame.Angles(0, turn, 0) * CFrame.new(0, y, 0.45)
			local _, label = KitPlace.signText(m, name, face, W - 2, h, " ", preset, color, nil, true)
			table.insert(row.Labels, label)
		end
		rows[name] = row
	end
	m.Parent = Workspace
	board = m
	FightBoard.live(nil)
	FightBoard.refreshWin()
	return m
end

local function side(s: { Name: string, Bot: boolean, Power: number }): string
	return string.format("%s%s \u{26A1}%d", s.Name, if s.Bot then " BOT" else "", s.Power)
end

-- The fight in the arena now (two side cards from PvpService), or nil when it is empty.
function FightBoard.live(a: any?, b: any?)
	if a and b then
		setRow("Title", "\u{1F534} LIVE BATTLE!", RED)
		setRow("Live", side(a) .. "  vs  " .. side(b), WHITE)
	else
		setRow("Title", "\u{2694} PET BATTLE ARENA \u{2694}", GOLD)
		setRow("Live", "Tap BATTLE to fight on Sky Island!", Color3.fromRGB(200, 230, 255))
	end
	local slab = board and board:FindFirstChild("Slab")
	local trim = slab and slab:FindFirstChild("Trim") :: SelectionBox?
	if trim then
		trim.Color3 = if a then RED else GOLD
	end
end

function FightBoard.refreshWin()
	local today = math.floor(os.time() / 86400)
	local w = best
	if w and w.Day == today then
		setRow("Biggest", string.format("\u{1F3C6} BIGGEST WIN TODAY: %s \u{26A1}%d beat %s \u{26A1}%d", w.Winner, w.WinnerPower, w.Loser, w.LoserPower))
	else
		setRow("Biggest", "\u{1F3C6} Biggest win today: nobody yet. Be first!")
	end
end

-- A finished fight with a player winner: maybe the day's new biggest win. Returns true when it is.
function FightBoard.won(winner: string, loser: string, winnerPower: number, loserPower: number): boolean
	local cand: PvpRules.Win = { Winner = winner, Loser = loser, WinnerPower = winnerPower, LoserPower = loserPower, Day = math.floor(os.time() / 86400) }
	local nextBest = PvpRules.biggerWin(best, cand)
	local isNew = nextBest == cand
	best = nextBest
	FightBoard.refreshWin()
	return isNew
end

-- Whether a board stands in the world (no board means no "biggest win" notice).
function FightBoard.shown(): boolean
	return board ~= nil and board.Parent ~= nil
end

function FightBoard.best(): PvpRules.Win?
	return best
end

return FightBoard
