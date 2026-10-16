--!strict
-- Pet Battle (1v1, 3 pets each) and Pet Training (carter 2026-10-14: find the pet -> train the pet -> fight).
-- Server authority: matchmaking, the fight (shared/PvpRules), rewards, trophies, streaks and training XP are all
-- decided here; clients send intents only (ReplicatedStorage.PvpNet.PvpAction) and draw what PvpEvent tells them.
-- Fights reuse the tower: same team (TowerService.team), same XP book and levels, and the client draws them with
-- TowerView. Every fight gets its own floating island (SkyIsland, carter 2026-10-14): both fighters are moved onto
-- it and back to the lobby after the result; nobody spectates. Nobody waits more than PvpConfig.BotAfter seconds: a bot (shown with a BOT
-- tag) steps in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetRules = require(Shared.PetRules)
local PvpConfig = require(Shared.PvpConfig)
local PvpRules = require(Shared.PvpRules)
local PetStats = require(Shared.PetStats)
local TowerConfig = require(Shared.TowerConfig)
local Profiles = require(script.Parent.Profiles)
local TowerService = require(script.Parent.TowerService)
local SkyIsland = require(script.Parent.SkyIsland)
local IslandRules = require(Shared.IslandRules)
local RockService = require(script.Parent.RockService)
local Gallery = require(script.Parent.GalleryService)
local FightBoard = require(script.Parent.FightBoard)
local GeodeGen = require(Shared.GeodeGen)
local EggPerks = require(Shared.EggPerks)
local Net = require(Shared.Net)

local PvpService = {}
PvpService.onSend = nil :: ((Player, any) -> ())? -- offline tests (tests/server/pvp.luau) watch every message

type Fight = {
	Key: string,
	Slot: number,
	Arena: Model,
	Origin: CFrame,
	Radius: number, -- the island's fight floor radius (the fall catcher puts anyone past it back on their mark)
	Layout: any, -- PvpConfig.Layouts entry
	Views: { CFrame }, -- [side] origin each side's client draws from (side 2 is mirrored, so both see their pets in front)
	Players: { [number]: Player? }, -- [side]; nil = bot
	Names: { string },
	BotSide: number?,
	Rules: PvpRules.Fight,
	Specs: { [string]: any },
	ForfeitAt: { Phase: string, Time: number }?, -- set when a side left before the result (settle pays the stayer)
	Info: { [string]: any }, -- unit id -> { Rarity, Level, Cap, Power } (the loser's finisher card shows the winner's)
	PetIds: { [string]: any }, -- unit id -> saved pet id (players only)
	Phase: string, -- "CountIn" | "Fighting" | "Cheer" | "Closed"
	Timer: number,
	Pending: { PvpRules.Event },
	SendIn: number,
	BotReadyAt: number?,
	BotTaps: number, -- bot taps owed (PvpConfig.Tap.BotTaps a second)
	Left: { [number]: boolean }, -- [side] forfeited (left mid-fight)
}

type Ticket = { Player: Player, Since: number, Power: number }

local queue: { Ticket } = {}
local boardLive: () -> ()
local boardSpot: () -> CFrame?
local catchFalls: () -> ()
local fightOf: { [Player]: Fight } = {}
local fights: { [string]: Fight } = {}
local returnCF: { [Player]: CFrame } = {}
local lastOp: { [Player]: { [string]: number } } = {}
local taps: { [Player]: { Tokens: number, At: number } } = {}
local syncAt: { [Player]: number } = {}
local serial = 0
local event: RemoteEvent

local SEND_EVERY = 0.2
-- Where a player stands: behind their own pets (z -14), closer than the tower's rug so the camera behind them stays
-- inside the arena walls.
local function standAt(view: CFrame, layout: any): CFrame
	local pos = view * Vector3.new(layout.StandX or 0, 3.5, layout.StandZ)
	local fight = view * Vector3.new(0, 3.5, (layout.PetZ + layout.FoeZ) / 2)
	return CFrame.lookAt(pos, fight) -- watching the middle of the fight
end

-- Side 2 sees the arena turned round about the middle of the two pet lines, so both see their own pets in front.
local function mirror(layout: any): CFrame
	return CFrame.new(0, 0, layout.PetZ + layout.FoeZ) * CFrame.Angles(0, math.pi, 0)
end

local function send(p: Player?, msg: any)
	if p and p.Parent then
		event:FireClient(p, msg)
		local hook = PvpService.onSend
		if hook then
			hook(p, msg)
		end
	end
end

-- Rate limit: true when `op` may run now for this player (at most one per `gap` seconds).
local function allow(p: Player, op: string, gap: number): boolean
	local book = lastOp[p]
	if not book then
		book = {}
		lastOp[p] = book
	end
	local now = os.clock()
	if now - (book[op] or -math.huge) < gap then
		return false
	end
	book[op] = now
	return true
end

local function stats(data: any): any
	local s = data and data.Pvp
	return if type(s) == "table" then s else { Trophies = 0, Streak = 0, BestStreak = 0, Wins = 0, Losses = 0 }
end

local function teamPets(p: Player, side: number): { PvpRules.TeamPet }
	local out = {}
	for i, g in TowerService.team(p) do
		if i > PvpConfig.TeamSize then
			break
		end
		table.insert(out, {
			Id = side .. ":" .. i,
			Name = PetRules.label(g),
			Xp = TowerService.xpOf(p, g.Id),
			Pet = g,
		})
	end
	return out
end

-- Pets that may not be used up by an evolve: following, shown on the plot or roaming it.
local function lockedPets(data: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, key in { "EquippedPets", "DisplayAssignments", "RoamPets" } do
		local list = data[key]
		if type(list) == "table" then
			for _, id in list do
				if type(id) == "string" then
					out[id] = true
				end
			end
		end
	end
	return out
end

local function evolveCheck(p: Player, data: any, g: any): (boolean, string?, { string }, number)
	return PvpRules.evolveCheck(g, function(id: string): number
		return TowerService.xpOf(p, id)
	end, data.InventoryGeodes, lockedPets(data))
end

local function petCard(p: Player, g: any, data: any?)
	local xp = TowerService.xpOf(p, g.Id)
	local v: any = TowerService.petView(g, xp)
	local cap = PetStats.cap(g)
	local level, into, need = PetStats.level(xp, cap)
	v.Cap = cap
	v.Power2 = PvpRules.power(g, xp) -- THE power number (PvpRules.petPower)
	v.Level = level
	v.XpInto = into
	v.XpNeed = need
	v.Name = PetRules.label(g)
	v.Evolve = PetStats.stage(g)
	if data and TowerConfig.Evolve.Enabled then
		local ok, why, _, free = evolveCheck(p, data, g)
		v.CanEvolve = ok
		v.EvolveWhy = why
		v.Copies = math.min(free + 1, TowerConfig.Evolve.Copies) -- this pet + the free copies, out of Copies
	end
	return v
end

local function inQueue(p: Player): number?
	for i, t in queue do
		if t.Player == p then
			return i
		end
	end
	return nil
end

-- Lobby name tag numbers (NameTag via PetFlair.battleLine): team power, trophies, win streak. Everyone sees them,
-- so a strong team is something to show off and to want.
local function publish(p: Player)
	local data = Profiles.get(p)
	if not data or not p.Parent then
		return
	end
	local s = stats(data)
	local power = PvpRules.teamPower(teamPets(p, 1))
	if p:GetAttribute("TeamPower") ~= power then
		p:SetAttribute("TeamPower", power)
	end
	if p:GetAttribute("Trophies") ~= s.Trophies then
		p:SetAttribute("Trophies", s.Trophies)
	end
	if p:GetAttribute("PvpStreak") ~= s.Streak then
		p:SetAttribute("PvpStreak", s.Streak)
	end
end

-- Battle / training card data: every pet with its power and level, the team, trophies and rank.
local function roster(p: Player)
	local data = Profiles.get(p)
	if not data then
		return
	end
	local pets = {}
	for _, g in data.InventoryGeodes do
		table.insert(pets, petCard(p, g, data))
	end
	local team = {}
	local teamPower = 0
	for _, tp in teamPets(p, 1) do
		table.insert(team, (tp.Pet :: any).Id)
		teamPower += PvpRules.power(tp.Pet, tp.Xp)
	end
	local s = stats(data)
	local rank, nxt = PvpRules.rank(s.Trophies)
	send(p, {
		Kind = "Roster",
		Pets = pets,
		Team = team,
		Power = teamPower,
		Trophies = s.Trophies,
		Streak = s.Streak,
		BestStreak = s.BestStreak,
		Wins = s.Wins,
		Losses = s.Losses,
		Rank = rank.Name,
		NextRank = if nxt then nxt.Name else nil,
		NextAt = if nxt then nxt.Min else nil,
		Queued = inQueue(p) ~= nil,
	})
end

local function unqueue(p: Player, why: string?)
	local i = inQueue(p)
	if i then
		table.remove(queue, i)
		send(p, { Kind = "Unqueued", Why = why })
	end
end

local function moveTo(p: Player, cf: CFrame)
	local char = p.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		char:PivotTo(cf)
	end
end

-- Units as one side's client sees them: its own pets carry its UserId, the foes Owner 0 (TowerView draws Owner 0
-- across the arena). Foe pets carry their look (Spec), so they are drawn as real pets, not mobs.
local function unitsFor(f: Fight, side: number, ownerId: number)
	local out = {}
	for _, u in f.Rules.Units do
		table.insert(out, {
			Id = u.Id,
			Owner = if u.Side == side then ownerId else 0,
			Kind = u.Kind,
			Name = u.Name,
			Max = u.Max,
			Hp = u.Hp,
			Element = u.Element,
			Boss = false,
			Foe = u.Side ~= side,
			Spec = f.Specs[u.Id],
			Info = f.Info[u.Id],
		})
	end
	return out
end

local function hpView(f: Fight)
	local hp = {}
	for _, u in f.Rules.Units do
		hp[u.Id] = { u.Hp, u.Shield }
	end
	return hp
end

local function each(f: Fight, fn: (side: number, p: Player) -> ())
	for side = 1, 2 do
		local p = f.Players[side]
		if p and not f.Left[side] and fightOf[p] == f then
			fn(side, p)
		end
	end
end

local function flush(f: Fight)
	if #f.Pending == 0 then
		return
	end
	local list = f.Pending
	f.Pending = {}
	local hp = hpView(f)
	each(f, function(side, p)
		send(p, { Kind = "Events", List = list, Hp = hp, Meter = f.Rules.Meters[side] / PvpConfig.SpecialCharge })
	end)
end

local function sideCard(f: Fight, side: number)
	local p = f.Players[side]
	local data = p and Profiles.get(p)
	local s = stats(data)
	local power = 0
	for _, u in f.Rules.Units do
		if u.Side == side then
			-- the same POWER the BATTLE card and matchmaking show (unit Max HP also carries speed growth, so rebuilding
			-- power from the unit overstated it)
			local info = f.Info[u.Id]
			power += if info and type(info.Power) == "number" then info.Power else 0
		end
	end
	return {
		Name = f.Names[side],
		Bot = p == nil,
		Trophies = if p then s.Trophies else nil,
		Rank = if p then PvpRules.rank(s.Trophies).Name else nil,
		Power = power,
	}
end

local function release(p: Player)
	fightOf[p] = nil
	p:SetAttribute("InBattle", nil)
	local back = returnCF[p]
	returnCF[p] = nil
	if back and p.Parent then
		moveTo(p, back)
	end
end

-- The lobby board's LIVE row: the newest fight going on (on its island), or how to join.
boardLive = function()
	local newest: Fight? = nil
	for _, f in fights do
		local n = tonumber(string.sub(f.Key, 4)) or 0
		if f.Phase ~= "Closed" and (newest == nil or n > (tonumber(string.sub((newest :: Fight).Key, 4)) or 0)) then
			newest = f
		end
	end
	if newest then
		FightBoard.live(sideCard(newest, 1), sideCard(newest, 2))
	else
		FightBoard.live(nil)
	end
end

-- Where the lobby's fight board floats: a part marked FightBoard = true placed in Studio (FightBoard looks for it),
-- or over an old lobby arena (ArenaCenter part outside the islands). No spot: no board.
boardSpot = function(): CFrame?
	local islands = Workspace:FindFirstChild("PetBattleIslands")
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ArenaCenter") == true and not (islands and d:IsDescendantOf(islands)) then
			return CFrame.new(d.Position + Vector3.new(0, d.Size.Y / 2, 0)) * d.CFrame.Rotation
		end
	end
	return nil
end

-- A fighter who falls or walks off their island is put back on their mark.
catchFalls = function()
	for p, f in fightOf do
		local char = p.Character
		local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart and f.Phase ~= "Closed" and not IslandRules.onIsland(f.Origin, f.Radius, rootPart.Position) then
			local side = if f.Players[1] == p then 1 else 2
			moveTo(p, standAt(f.Views[side], f.Layout))
		end
	end
end

local function closeFight(f: Fight)
	if f.Phase == "Closed" then
		return
	end
	f.Phase = "Closed"
	fights[f.Key] = nil
	for side = 1, 2 do
		local p = f.Players[side]
		if p and fightOf[p] == f then
			release(p)
		end
	end
	SkyIsland.free(f.Slot, f.Arena)
	boardLive()
end

-- Pays one side and sends its result card. `result` = "Win" | "Loss" | "Draw".
local function pay(f: Fight, side: number, result: string)
	local p = f.Players[side]
	local data = p and Profiles.get(p)
	if not p or not data or Profiles.isReleased(p) or f.Left[side] then
		return -- a side that left mid-fight was paid its loss when it left
	end
	local s = stats(data)
	data.Pvp = s
	local vsBot = f.BotSide ~= nil
	local o = PvpRules.outcome(result, s.Trophies, s.Streak, vsBot)
	data.Cash = (tonumber(data.Cash) or 0) + o.Coins
	s.Trophies = math.max(s.Trophies + o.Trophies, 0)
	s.Streak = o.Streak
	s.BestStreak = math.max(s.BestStreak, s.Streak)
	if result == "Win" then
		s.Wins += 1
		-- every 3rd win banks a free egg; RobuxService hatches banked eggs as soon as the Pet Book has room
		local perks = EggPerks.sanitize(data.EggPerks)
		data.EggPerks = perks
		local egg = EggPerks.fightWin(perks)
		if egg then
			Net.event("Toast"):FireClient(p, EggPerks.Free.FightWinsPerEgg .. " wins! You earned a FREE " .. EggPerks.eggName(egg) .. "!", "rare")
		end
	elseif result == "Loss" then
		s.Losses += 1
	end
	local ups = {}
	for unitId, petId in f.PetIds do
		if string.sub(unitId, 1, 2) == side .. ":" then
			local before = TowerService.xpOf(p, petId)
			TowerService.addXp(p, petId, o.Xp)
			local got = TowerService.xpOf(p, petId) - before -- with the Pet Book page bonus (EggPerks.xpMult)
			local g = TowerService.petById(p, tostring(petId))
			local lb, la = PvpRules.train(before, got, if g then PetStats.cap(g) else nil)
			if g and la > lb then
				table.insert(ups, { Name = PetRules.label(g), Level = la, Power = PvpRules.power(g, before + got) })
			end
		end
	end
	Profiles.changed(p)
	publish(p)
	local rank, nxt = PvpRules.rank(s.Trophies)
	send(p, {
		Kind = "Result",
		Result = result,
		Coins = o.Coins,
		TrophyChange = o.Trophies,
		Trophies = s.Trophies,
		Streak = s.Streak,
		Xp = o.Xp,
		Rank = rank.Name,
		NextRank = if nxt then nxt.Name else nil,
		NextAt = if nxt then nxt.Min else nil,
		LevelUps = ups,
		Foe = f.Names[3 - side],
		Bot = vsBot,
	})
end

local function settle(f: Fight)
	local w = f.Rules.Winner
	local wp = if w ~= 0 then f.Players[w] else nil
	if wp and not f.Left[3 - w] then
		-- the arena board keeps the day's biggest win (the biggest upset) for everyone to see
		local a, b = sideCard(f, w), sideCard(f, 3 - w)
		if FightBoard.won(a.Name, b.Name .. (if b.Bot then " BOT" else ""), a.Power, b.Power) and FightBoard.shown() then
			send(wp, { Kind = "Notice", Text = "Your win is today's BIGGEST WIN on the arena board!" })
		end
	end
	for side = 1, 2 do
		local result = if w == 0 then "Draw" elseif w == side then "Win" else "Loss"
		-- a rival who quit before the fight really started is no win (stops a second account feeding wins, trophies
		-- and free-egg progress): the side that stayed gets the draw reward (PvpRules.forfeitResult)
		if result == "Win" and f.ForfeitAt then
			result = PvpRules.forfeitResult(f.ForfeitAt.Phase, f.ForfeitAt.Time)
		end
		pay(f, side, result)
	end
	closeFight(f)
end

local function over(f: Fight)
	flush(f)
	f.Phase = "Cheer"
	f.Timer = PvpConfig.ResultHold
	each(f, function(side, p)
		send(p, { Kind = "Over", Winner = f.Rules.Winner, MySide = side })
	end)
end

-- A side leaves mid-fight: it loses, the other side wins at once (its reward is paid as normal).
local function forfeit(p: Player)
	local f = fightOf[p]
	if not f then
		return
	end
	local side = if f.Players[1] == p then 1 else 2
	if f.Phase == "CountIn" or f.Phase == "Fighting" then
		f.ForfeitAt = { Phase = f.Phase :: string, Time = f.Rules.Time }
		f.Rules.State = "Done"
		f.Rules.Winner = 3 - side
		table.insert(f.Pending, { Kind = "KO", Side = 3 - side, Id = "Forfeit" })
		pay(f, side, "Loss")
		f.Left[side] = true
		release(p)
		over(f)
	else
		if f.Phase == "Cheer" and not f.Left[side] then
			-- the fight is decided; a side that leaves during the cheer still gets its result now (its save is next)
			local w = f.Rules.Winner
			pay(f, side, if w == 0 then "Draw" elseif w == side then "Win" else "Loss")
			f.Left[side] = true
		end
		release(p)
	end
	send(p, { Kind = "Closed" })
	-- Nobody left to see the result (a bot fight, or the other side already left): free the island now. over() above
	-- has set the Cheer phase, so this must not wait on it (the old check did, and the island idled for ResultHold).
	local other = f.Players[3 - side]
	if other == nil or f.Left[3 - side] or not other.Parent then
		closeFight(f)
	end
end

local function startFight(a: Player, b: Player?)
	local teamA = teamPets(a, 1)
	local teamB: { PvpRules.TeamPet } = if b then teamPets(b, 2) else {}
	local botName: string? = nil
	if not b then
		teamB = PvpRules.botTeam(teamA, math.random)
		for i, tp in teamB do
			tp.Id = "2:" .. i
		end
		botName = PvpConfig.BotNames[math.random(1, #PvpConfig.BotNames)]
	end
	if #teamA == 0 or #teamB == 0 then
		send(a, { Kind = "Notice", Text = "Hatch a pet first! Pets fight in battles." })
		if b then
			send(b, { Kind = "Notice", Text = "Your rival left. Tap FIGHT to find a new one." })
		end
		return
	end
	-- this fight's own floating island
	local island = SkyIsland.claim()
	local slot, arena, origin, layout = island.Slot, island.Model, island.Origin, island.Layout
	serial += 1
	local specs, petIds, info = {}, {}, {}
	for side, team in { teamA, teamB } do
		for _, tp in team do
			local g: any = tp.Pet
			local cap = PetStats.cap(g)
			info[tp.Id] = { Rarity = g.Rarity, Modifier = g.Modifier, Level = (PetStats.level(tp.Xp, cap)), Cap = cap, Power = PvpRules.power(g, tp.Xp) }
			specs[tp.Id] = { Mineral = g.Mineral, Rarity = g.Rarity, Modifier = g.Modifier, Formation = g.Formation, Mass = g.Mass, Seed = g.Seed, Evolve = g.Evolve }
			if side == 1 or b then
				petIds[tp.Id] = g.Id
			end
		end
	end
	local f: Fight = {
		Key = "pvp" .. serial,
		Slot = slot,
		Arena = arena :: any,
		Origin = origin,
		Radius = island.Radius,
		Layout = layout,
		Views = { origin, origin * mirror(layout) },
		Players = { [1] = a, [2] = b },
		Names = { a.DisplayName, if b then b.DisplayName else (botName or "Rival") },
		BotSide = if b then nil else 2,
		Rules = PvpRules.newFight(teamA, teamB),
		Specs = specs,
		Info = info,
		PetIds = petIds,
		Phase = "CountIn",
		Timer = PvpConfig.CountIn,
		Pending = {},
		SendIn = 0,
		BotReadyAt = nil,
		BotTaps = 0,
		Left = {},
	}
	fights[f.Key] = f
	boardLive()
	for side = 1, 2 do
		local p = f.Players[side]
		if p then
			fightOf[p] = f
			p:SetAttribute("InBattle", true)
			local char = p.Character
			if char then
				returnCF[p] = char:GetPivot()
			end
			moveTo(p, standAt(f.Views[side], f.Layout))
		end
	end
	each(f, function(side, p)
		send(p, {
			Kind = "Start",
			Units = unitsFor(f, side, p.UserId),
			Origin = f.Views[side],
			Layout = f.Layout,
			Island = true,
			MySide = side,
			Me = sideCard(f, side),
			Foe = sideCard(f, 3 - side),
			CountIn = PvpConfig.CountIn,
			HasSpecial = PvpRules.hasSpecial(f.Rules, side),
			FightTime = PvpConfig.FightTime,
		})
	end)
end

local function canQueue(p: Player): (boolean, string?)
	if not Profiles.isLoaded(p) then
		return false, nil
	end
	if fightOf[p] or p:GetAttribute("MatchKey") ~= nil or TowerService.inTower(p) then
		return false, "Finish what you are doing first!"
	end
	if #teamPets(p, 1) == 0 then
		return false, "Hatch a pet first! Pets fight in battles."
	end
	return true, nil
end

local function enqueue(p: Player)
	if inQueue(p) then
		return
	end
	local ok, why = canQueue(p)
	if not ok then
		if why then
			send(p, { Kind = "Notice", Text = why })
		end
		return
	end
	local team = teamPets(p, 1)
	table.insert(queue, { Player = p, Since = os.clock(), Power = PvpRules.teamPower(team) })
	send(p, { Kind = "Queued", Power = PvpRules.teamPower(team), BotAfter = PvpConfig.BotAfter })
end

-- Pairs waiting players by power; anyone waiting BotAfter seconds gets a bot.
local function matchmake()
	local now = os.clock()
	local i = 1
	while i <= #queue do
		local t = queue[i]
		local paired = false
		if not t.Player.Parent then
			table.remove(queue, i)
			continue
		end
		if not (canQueue(t.Player)) then
			-- never a silent drop: the search strip would keep counting (audit F24)
			table.remove(queue, i)
			send(t.Player, { Kind = "Unqueued", Why = if #teamPets(t.Player, 1) == 0 then "NoTeam" else "Busy" })
			continue
		end
		for j = i + 1, #queue do
			local o = queue[j]
			if o.Player.Parent and canQueue(o.Player) and PvpRules.canMatch(t.Power, now - t.Since, o.Power, now - o.Since) then
				table.remove(queue, j)
				table.remove(queue, i)
				startFight(t.Player, o.Player)
				paired = true
				break
			end
		end
		if not paired then
			if now - t.Since >= PvpConfig.BotAfter then
				table.remove(queue, i)
				startFight(t.Player, nil)
			else
				i += 1
			end
		end
	end
end

local function train(p: Player, petId: any)
	if type(petId) ~= "string" or #petId > 64 then
		return
	end
	-- token bucket: TapsPerSecond taps a second, short bursts allowed up to the same number
	local rate = PvpConfig.Train.TapsPerSecond
	local now = os.clock()
	local b: { Tokens: number, At: number } = taps[p] or { Tokens = rate, At = now }
	taps[p] = b
	b.Tokens = math.min(rate, b.Tokens + (now - b.At) * rate)
	b.At = now
	if b.Tokens < 1 then
		return
	end
	b.Tokens -= 1
	local g = TowerService.petById(p, petId)
	if not g or fightOf[p] then
		return
	end
	local before = TowerService.xpOf(p, g.Id)
	local cap = PetStats.cap(g)
	if PvpRules.maxed(g, before) then
		-- rarity cap reached (carter 2026-10-14): no more training; rarer pets grow higher
		send(p, { Kind = "Trained", Pet = g.Id, Gain = 0, Level = cap, XpInto = 0, XpNeed = 0, Power = PvpRules.power(g, before), Maxed = true })
		return
	end
	TowerService.addXp(p, g.Id, PvpConfig.Train.TapXp)
	local gain = TowerService.xpOf(p, g.Id) - before -- with the Pet Book page bonus (EggPerks.xpMult)
	local lb, la, xp = PvpRules.train(before, gain, cap)
	-- the profile (Pet Book levels) syncs at most every 2 s while tapping; the save picks it up as usual
	if now - (syncAt[p] or -math.huge) >= 2 or la > lb then
		syncAt[p] = now
		Profiles.changed(p)
	end
	if la > lb then
		publish(p)
	end
	local level, into, need = PetStats.level(xp, cap)
	send(p, {
		Kind = "Trained",
		Pet = g.Id,
		Gain = gain,
		Level = level,
		XpInto = into,
		XpNeed = need,
		Power = PvpRules.power(g, xp),
		LevelUp = la > lb,
		Maxed = level >= cap,
		PowerBefore = if la > lb then PvpRules.power(g, before) else nil,
	})
end

-- EVOLVE: a pet at its cap uses up Copies - 1 free copies of itself (same species, rarity and stage) and steps up
-- one stage: higher cap, stronger stats, bigger glowing look. The used copies and their XP are gone for good.
local function evolve(p: Player, petId: string)
	local data = Profiles.get(p)
	if not data or Profiles.isReleased(p) or p:GetAttribute("MatchKey") ~= nil or TowerService.inTower(p) then
		return
	end
	local _, g = Profiles.findGeode(data, petId)
	if not g then
		return
	end
	local ok, why, use = evolveCheck(p, data, g)
	if not ok then
		send(p, { Kind = "Evolved", Ok = false, Pet = petId, Why = why })
		return
	end
	local powerBefore = PvpRules.power(g, TowerService.xpOf(p, g.Id))
	local gone: { [string]: boolean } = {}
	for _, id in use do
		gone[id] = true
	end
	for i = #data.InventoryGeodes, 1, -1 do
		local c = data.InventoryGeodes[i]
		if type(c) == "table" and gone[c.Id] then
			table.remove(data.InventoryGeodes, i)
			if type(data.TowerXP) == "table" then
				data.TowerXP[c.Id] = nil
			end
		end
	end
	g.Evolve = PetStats.stage(g) + 1
	Profiles.changed(p) -- full: the inventory changed (followers, Pet Book and plot refresh from it)
	send(p, {
		Kind = "Evolved",
		Ok = true,
		Pet = g.Id,
		Stage = g.Evolve,
		Cap = PetStats.cap(g),
		PowerBefore = powerBefore,
		Power = PvpRules.power(g, TowerService.xpOf(p, g.Id)),
		Used = #use,
	})
	roster(p)
	publish(p)
	pcall(Gallery.render, p) -- a displayed pet shows its new look on the plot
end

-- Hunt XP (RockService.onCracked): every egg a player finishes gives each following pet a little XP.
local function huntXp(p: Player, found: boolean)
	local data = Profiles.get(p)
	if not data or type(data.EquippedPets) ~= "table" then
		return
	end
	local gain = if found then PvpConfig.Hunt.FoundXp else PvpConfig.Hunt.CrackXp
	for _, id in data.EquippedPets do
		TowerService.addXp(p, id, gain)
	end
end

-- Pet XP from the hunt fun prizes (surprise eggs, places; shared/HuntFun): `amount` to each following pet.
local function petXp(p: Player, amount: number)
	local data = Profiles.get(p)
	if not data or type(data.EquippedPets) ~= "table" or amount <= 0 then
		return
	end
	for _, id in data.EquippedPets do
		TowerService.addXp(p, id, amount)
	end
end

-- Tap-to-inspect another player's pet (client PetInspectTap): only pets that player has following them, so nothing
-- private is read. The card shows the pet with its battle power and level, and the owner's trophies.
local function inspectPet(p: Player, userId: any, petId: any)
	if type(userId) ~= "number" or type(petId) ~= "string" or #petId > 64 then
		return
	end
	local owner = Players:GetPlayerByUserId(userId)
	local data = owner and Profiles.get(owner)
	if not owner or not data or type(data.EquippedPets) ~= "table" or not table.find(data.EquippedPets, petId) then
		return
	end
	local _, g = Profiles.findGeode(data, petId)
	if not g then
		return
	end
	local xp = TowerService.xpOf(owner, g.Id)
	local cap = PetStats.cap(g)
	local s = stats(data)
	Net.event("Inspect"):FireClient(p, {
		Owner = owner.DisplayName,
		IsYou = owner == p,
		Specimen = GeodeGen.public(g),
		Power = PvpRules.power(g, xp),
		Level = (PetStats.level(xp, cap)),
		Cap = cap,
		Evolve = PetStats.stage(g),
		Where = string.format("%s's pet  \u{1F3C6} %s", owner.DisplayName, tostring(s.Trophies)),
	})
end

local function onAction(p: Player, msg: any)
	if type(msg) ~= "table" or type(msg.Op) ~= "string" then
		return
	end
	local op = msg.Op
	local f = fightOf[p]
	if op == "Train" then
		train(p, msg.Pet)
	elseif op == "Tap" or op == "Block" then
		-- tap to fight: at most Tap.PerSecond taps count (a few ms of slack for network jitter); BLOCK as SPECIAL
		local gap = if op == "Tap" then 1 / PvpConfig.Tap.PerSecond - 0.02 else PvpConfig.ActionGap
		if f and f.Phase == "Fighting" and allow(p, op, gap) then
			local side = if f.Players[1] == p then 1 else 2
			local _ok: boolean, ev: { PvpRules.Event }
			if op == "Tap" then
				_ok, ev = PvpRules.tap(f.Rules, side)
			else
				_ok, ev = PvpRules.block(f.Rules, side)
			end
			for _, e in ev do
				table.insert(f.Pending, e)
			end
			if op == "Block" then
				flush(f) -- the ring answer goes out at once
			end
			if f.Rules.State == "Done" then
				flush(f)
				over(f)
			end
		end
	elseif op == "Special" then
		if f and f.Phase == "Fighting" and allow(p, "Special", PvpConfig.ActionGap) then
			local side = if f.Players[1] == p then 1 else 2
			local ok, ev = PvpRules.useSpecial(f.Rules, side, math.random())
			if ok then
				for _, e in ev do
					table.insert(f.Pending, e)
				end
				flush(f)
				if f.Rules.State == "Done" then
					over(f)
				end
			end
		end
	elseif op == "Open" then
		if allow(p, "Open", 1) then
			roster(p)
		end
	elseif op == "Queue" then
		if allow(p, "Queue", PvpConfig.QueueGap) then
			enqueue(p)
		end
	elseif op == "Cancel" then
		if allow(p, "Cancel", 0.3) then
			unqueue(p, "Cancel")
		end
	elseif op == "Leave" then
		if f and allow(p, "Leave", PvpConfig.QueueGap) then
			forfeit(p)
		end
	elseif op == "SetTeam" then
		if f or inQueue(p) or type(msg.Pets) ~= "table" or #msg.Pets > PvpConfig.TeamSize * 2 or not allow(p, "Team", PvpConfig.ActionGap) then
			return
		end
		local ids, seen = {}, {}
		for i = 1, #msg.Pets do
			local id = msg.Pets[i]
			if #ids >= PvpConfig.TeamSize then
				break
			end
			if type(id) == "string" and not seen[id] and TowerService.petById(p, id) then
				seen[id] = true
				table.insert(ids, id)
			end
		end
		TowerService.setTeam(p, if #ids > 0 then ids else nil)
		roster(p)
		publish(p)
	elseif op == "Inspect" then
		if allow(p, "Inspect", 0.5) then
			inspectPet(p, msg.UserId, msg.Pet)
		end
	elseif op == "Evolve" then
		if TowerConfig.Evolve.Enabled and not f and not inQueue(p) and type(msg.Pet) == "string" and #msg.Pet <= 64 and allow(p, "Evolve", 1) then
			evolve(p, msg.Pet)
		end
	elseif op == "EquipBest" then
		if not f and not inQueue(p) and allow(p, "Team", PvpConfig.ActionGap) then
			TowerService.setTeam(p, nil)
			roster(p)
			publish(p)
		end
	end
end

-- Idle training: pets following the player gain a little XP every IdleEvery seconds.
local function idleTrain()
	for _, p in Players:GetPlayers() do
		local data = Profiles.get(p)
		if data and not Profiles.isReleased(p) and type(data.EquippedPets) == "table" and #data.EquippedPets > 0 then
			local gain = PvpConfig.Train.IdleXp
			for _, id in data.EquippedPets do
				TowerService.addXp(p, id, gain)
			end
			Profiles.changed(p, true)
		end
	end
end

function PvpService.start()
	local folder = Instance.new("Folder")
	folder.Name = "PvpNet"
	local action = Instance.new("RemoteEvent")
	action.Name = "PvpAction"
	action.Parent = folder
	event = Instance.new("RemoteEvent")
	event.Name = "PvpEvent"
	event.Parent = folder
	folder.Parent = ReplicatedStorage
	action.OnServerEvent:Connect(onAction)
	-- the arena board (built once the lobby arena exists; the map may load a little after the server starts)
	FightBoard.ensure(boardSpot())
	task.delay(10, function()
		FightBoard.ensure(boardSpot())
	end)
	RockService.onCracked = huntXp
	RockService.onPetXp = petXp

	-- Lobby pads (parts with attribute PvpPad / TrainPad, placed in Studio): stepping on one opens its card.
	local touchedAt: { [Player]: number } = {}
	local function hookPad(d: Instance)
		if not d:IsA("BasePart") or d:GetAttribute("PvpHooked") then
			return
		end
		local kind = if d:GetAttribute("PvpPad") == true then "Battle" elseif d:GetAttribute("TrainPad") == true then "Train" else nil
		if not kind then
			return
		end
		d:SetAttribute("PvpHooked", true)
		d.Touched:Connect(function(hit)
			local char = hit.Parent
			local p = char and Players:GetPlayerFromCharacter(char)
			if not p or fightOf[p] or p:GetAttribute("MatchKey") ~= nil then
				return
			end
			local now = os.clock()
			if now - (touchedAt[p] or 0) < 4 then
				return
			end
			touchedAt[p] = now
			send(p, { Kind = "OpenCard", Card = kind })
			roster(p)
		end)
	end
	for _, d in Workspace:GetDescendants() do
		hookPad(d)
	end
	Workspace.DescendantAdded:Connect(hookPad)
	task.delay(10, function()
		for _, d in Workspace:GetDescendants() do
			hookPad(d)
		end
	end)

	local function watch(p: Player)
		p:GetAttributeChangedSignal("MatchKey"):Connect(function()
			if p:GetAttribute("MatchKey") ~= nil then
				unqueue(p, "Hunt")
				forfeit(p)
			end
		end)
		p.CharacterAdded:Connect(function()
			local f = fightOf[p]
			if f then
				task.defer(function()
					local side = if f.Players[1] == p then 1 else 2
					if fightOf[p] == f then
						moveTo(p, standAt(f.Views[side], f.Layout))
					end
				end)
			end
		end)

	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		unqueue(p)
		forfeit(p)
		lastOp[p] = nil
		taps[p] = nil
		syncAt[p] = nil
		touchedAt[p] = nil
		returnCF[p] = nil
	end)

	local acc, matchAcc, idleAcc, tagAcc = 0, 0, 0, 14
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		matchAcc += dt
		idleAcc += dt
		if matchAcc >= 0.5 then
			matchAcc = 0
			matchmake()
			catchFalls()
		end
		tagAcc += dt
		if tagAcc >= 15 then -- name tag numbers follow new pets, sales and levels
			tagAcc = 0
			for _, p in Players:GetPlayers() do
				publish(p)
			end
		end
		if idleAcc >= PvpConfig.Train.IdleEvery then
			idleAcc = 0
			idleTrain()
		end
		if acc < TowerConfig.Tick then
			return
		end
		local step = math.min(acc, 0.5)
		acc = 0
		for _, f in fights do
			if f.Phase == "CountIn" then
				f.Timer -= step
				if f.Timer <= 0 then
					f.Phase = "Fighting"
				end
			elseif f.Phase == "Fighting" then
				local bot = f.BotSide
				for _, e in PvpRules.step(f.Rules, step, math.random) do
					table.insert(f.Pending, e)
					-- the bot catches some rings (PvpConfig.Block.BotBlock)
					if bot and e.Kind == "Warn" and e.Side == bot and math.random() < PvpConfig.Block.BotBlock then
						PvpRules.block(f.Rules, bot)
					end
				end
				if bot and f.Rules.State == "Fighting" then
					f.BotTaps += step * PvpConfig.Tap.BotTaps
					while f.BotTaps >= 1 and f.Rules.State == "Fighting" do
						f.BotTaps -= 1
						local _, ev = PvpRules.tap(f.Rules, bot)
						for _, e in ev do
							table.insert(f.Pending, e)
						end
					end
				end
				if bot and f.Rules.State == "Fighting" and PvpRules.meterFull(f.Rules, bot) then
					f.BotReadyAt = f.BotReadyAt or (os.clock() + PvpConfig.BotSpecialDelay)
					if os.clock() >= (f.BotReadyAt :: number) then
						f.BotReadyAt = nil
						local _, ev = PvpRules.useSpecial(f.Rules, bot, math.random())
						for _, e in ev do
							table.insert(f.Pending, e)
						end
					end
				end
				f.SendIn -= step
				if #f.Pending > 0 and (f.SendIn <= 0 or f.Rules.State ~= "Fighting") then
					flush(f)
					f.SendIn = SEND_EVERY
				end
				if f.Rules.State ~= "Fighting" then
					over(f)
				end
			elseif f.Phase == "Cheer" then
				f.Timer -= step
				if f.Timer <= 0 then
					settle(f)
				end
			end
		end
	end)
end

-- Offline tests: the intent handler (as if PvpAction fired) and the live fight table.
PvpService.action = onAction
function PvpService.fightOf(p: Player): any
	return fightOf[p]
end

return PvpService
