--!strict
-- Client audio: buses, one ambience per area, world sounds with distance attenuation, caps.
--
-- Buses (SoundGroups under SoundService.CTR_Audio):
--   SFX       <- Settings.Sfx     all one-shots and machine loops
--   Ambience  <- Settings.Music * 0.6   one looping bed, lobby or arena (crossfaded), plus the soft hum near a
--                                      working press (positioned, heard within 40 studs)
--   Music     <- Settings.Music   reserved (no music files yet)
-- Every sound id comes from shared/SoundIds (0 = not uploaded): a 0 id plays nothing, silently.
--
-- Rules that keep it from spamming:
--   * per-sound cooldown (COOLDOWN), so fast swings, machines and button mashing stay readable;
--   * at most MAX_WORLD live positioned sounds and MAX_FLAT live flat (UI / own strike) sounds;
--   * positioned sounds farther than MAX_DIST are never created; closer ones roll off
--     (LinearSquare, full volume inside MIN_DIST, silent at MAX_DIST);
--   * at most MAX_LOOPS machine loops at once (nearest win), each stops itself when its owner
--     stops calling Audio.machineActive for IDLE seconds.
-- Docs: docs/AUDIO.md.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SoundIds = require(Shared.SoundIds)
local PetSoundIds = require(Shared.PetSoundIds)
local SoundConfig = require(Shared.SoundConfig) -- hand-set ids (egg crunch / pop); 0 = silent
local EggConfig = require(Shared.EggConfig)
local SoundCues = require(Shared.SoundCues) -- moment -> key map, reveal cues, stand-ins while a made sound is 0
local State = require(script.Parent.State)

local Audio = {}

export type Opts = { Pos: Vector3?, Volume: number?, Pitch: number?, Key: string? }

local MIN_DIST = 14
local MAX_DIST = 95
local MAX_WORLD = 8
local MAX_FLAT = 6
local MAX_LOOPS = 4 -- three machines plus the own jackhammer
local IDLE = 0.35
local AMBIENCE_VOLUME = 0.45
local LOAD_WAIT = 10 -- seconds a one-shot may take to load before its slot is given up

-- seconds between two plays of the same sound name (per Key when one is given)
local COOLDOWN: { [string]: number } = {
	HammerHit = 0.06, StoneCrack = 0.09, GravelSpill = 0.2,
	JackhammerStart = 1.0, JackhammerStop = 0.5,
	PressDescend = 0.8, PressImpact = 0.8, PressRetract = 0.8,
	GeodeReveal = 1.0, RarityAccent = 1.0, Sale = 0.25, Pickup = 0.12, Deposit = 0.15, MaterialFound = 0.8, Purchase = 0.2,
	Button = 0.05, CountdownTick = 0.3, MatchWin = 1.0,
	EggCrunch = 0.05, EggPop = 0.15, HatchChoir = 2.0,
	CoinPickup = 0.08, SpeedBoots = 1.0, TowerHit = 0.07, TowerSpecial = 0.3, EggChirp = 0.5,
	HatchSparkle = 1.0, HatchDrum = 1.0, PetFound = 1.0, EggGrab = 0.12, EggDrop = 0.15, BattleMatched = 1.0,
	PetCrit = 0.1, PetKO = 0.25, BattleWin = 1.0, BattleLose = 1.0, TrainTap = 0.05, LevelUp = 2.0, Evolve = 1.0,
	FloorClear = 1.0, DailyClaim = 1.0, GiftOpen = 0.8, QuestDone = 0.4, LuckyMeter = 1.0, Denied = 0.35,
}

-- sounds with numbered variants (HammerHit1..3 etc.)
local VARIANTS: { [string]: number } = { HammerHit = 3, StoneCrack = 3, GravelSpill = 2 }

local BASE_VOLUME: { [string]: number } = {
	HammerHit = 0.75, StoneCrack = 0.7, GravelSpill = 0.55, Button = 0.5, CountdownTick = 0.6,
	Sale = 0.7, Purchase = 0.7, Pickup = 0.65, Deposit = 0.75, MaterialFound = 0.8, GeodeReveal = 0.85, RarityAccent = 0.7, MatchWin = 0.8,
	JackhammerStart = 0.6, JackhammerStop = 0.5, PressDescend = 0.6, PressImpact = 0.8, PressRetract = 0.5,
	EggCrunch = 0.7, EggPop = 0.85, HatchChoir = 0.8,
	CoinPickup = 0.6, SpeedBoots = 0.75, TowerHit = 0.6, TowerSpecial = 0.8, EggChirp = 0.7,
	HatchSparkle = 0.8, HatchDrum = 0.85, PetFound = 0.75, EggGrab = 0.6, EggDrop = 0.7, BattleMatched = 0.75,
	PetCrit = 0.7, PetKO = 0.65, BattleWin = 0.8, BattleLose = 0.6, TrainTap = 0.45, LevelUp = 0.75, Evolve = 0.85,
	FloorClear = 0.75, DailyClaim = 0.75, GiftOpen = 0.75, QuestDone = 0.7, LuckyMeter = 0.8, Denied = 0.55,
	JackhammerLoop = 0.5, ConveyorHum = 0.3, CrusherLoop = 0.45, MachineHum = 0.32,
}

-- machine kinds for machineActive: start one-shot, loop, stop one-shot (any may be absent). Idle = seconds without
-- a call before the loop winds down (default IDLE); Ambient = the loop plays on the Ambience bus (music/ambient
-- volume) with a short reach, for the gentle hum near a running machine.
type MachineKind = { Start: string?, Loop: string, Stop: string?, Idle: number?, Ambient: boolean? }
local MACHINES: { [string]: MachineKind } = {
	Jackhammer = { Start = "JackhammerStart", Loop = "JackhammerLoop", Stop = "JackhammerStop" },
	Conveyor = { Loop = "ConveyorHum" },
	Crusher = { Loop = "CrusherLoop" },
	-- the hydraulic press only makes one-shots (descend / impact / retract); while those keep coming a soft
	-- motor hum runs under them (started from Audio.play, below) and fades 4.5 s after the last stroke
	Hum = { Loop = "MachineHum", Idle = 4.5, Ambient = true },
}
local HUM_MIN, HUM_MAX = 6, 40 -- the hum is only heard near the machine
local HUM_FROM = { PressDescend = true, PressImpact = true, PressRetract = true }

local AREA_AMBIENCE = { lobby = "LobbyMusic", arena = "RaceMusic" } -- Find The Pet: chill-pop lobby, hype race (PetSoundIds)

local rng = Random.new()
local last: { [string]: number } = {}
local live = { World = 0, Flat = 0 }
local groups: { Master: SoundGroup?, SFX: SoundGroup?, Ambience: SoundGroup?, Music: SoundGroup? } = {}
local ambience: { Sound: Sound?, Area: string? } = {}
local windBed: Sound? = nil -- the hunt wind loop (arena only)
local parkedLobby: Sound? = nil -- lobby ambience kept paused during a hunt so it resumes where it left off
-- Round-end rush (0..1): over the last RUSH_LEAD seconds before the overtime glow (EggConfig.Overtime) the race music
-- gets a little louder and faster, and stays there until the pet is found. Cosmetic: read from the server's clock.
local RUSH_LEAD = 30
local RUSH_VOLUME = 0.3 -- up to +30 % on the Ambience bus
local RUSH_SPEED = 0.08 -- up to +8 % playback speed
local rush = 0
local duck = 1 -- music/ambience duck multiplier during the hatch reveal
local duckToken = 0
local started = false
-- quick streaks of these climb in pitch (up to 8 steps of 6 %), a pause of 0.6 s resets them (only played sounds count)
local CLIMB: { [string]: boolean } = { CoinPickup = true, TrainTap = true }
local streak: { [string]: { N: number, At: number } } = {}
local menuOpen = false -- a menu panel is open: one-shot sounds a bit quieter
local MENU_QUIET = 0.75

type Loop = { Sound: Sound, Part: Attachment?, Pos: Vector3?, LastSeen: number, Kind: string }
local loops: { [string]: Loop } = {}
local loopCount = 0
local loopConn: RBXScriptConnection? = nil

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function idOf(name: string): number
	local v = SoundIds[name]
	if v == nil then
		v = SoundConfig.Ids[name]
	end
	if v == nil or v == 0 then
		v = PetSoundIds[name] -- Find The Pet picks (music, hatch, made sounds)
	end
	return if type(v) == "number" then v else 0
end

local function listenerPos(): Vector3?
	local cam = Workspace.CurrentCamera
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return if cam then cam.CFrame.Position else nil
end

local function applyVolumes()
	local s = settings()
	local music = if type(s.Music) == "number" then math.clamp(s.Music, 0, 1) else 0.6
	local sfx = if type(s.Sfx) == "number" then math.clamp(s.Sfx, 0, 1) else 0.8
	if groups.SFX then
		(groups.SFX :: SoundGroup).Volume = sfx
	end
	if groups.Music then
		(groups.Music :: SoundGroup).Volume = music * duck
	end
	if groups.Ambience then
		(groups.Ambience :: SoundGroup).Volume = music * 0.6 * (1 + RUSH_VOLUME * rush) * duck
	end
end

local function makeGroup(name: string, parent: Instance): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Parent = parent
	return g
end

local function resolve(name: string): string
	local n = VARIANTS[name]
	if n then
		return name .. rng:NextInteger(1, n)
	end
	return name
end

-- Plays `name` once. opts: Pos (Vector3: positioned, rolls off with distance), Volume (x),
-- Pitch (x), Key (cooldown key, default the name). Returns whether a sound started.
function Audio.play(name: string, opts: Opts?): boolean
	local o: Opts = opts or {}
	if HUM_FROM[name] and o.Pos then
		-- a working press: keep its soft hum running (one per machine position)
		local p = o.Pos :: Vector3
		Audio.machineActive(string.format("hum:%d:%d", math.floor(p.X + 0.5), math.floor(p.Z + 0.5)), "Hum", p)
	end
	local id = idOf(resolve(name))
	local fallback = SoundCues.Fallback[name]
	if id == 0 and fallback then
		id = idOf(resolve(fallback)) -- the old sound stands in until the made one is uploaded
	end
	if id == 0 or not started then
		return false
	end
	local now = os.clock()
	local key = o.Key or name
	local cd = COOLDOWN[name] or 0.04 -- default 40 ms: identical sounds in one frame never stack
	if cd > 0 and now - (last[key] or -1) < cd then
		return false
	end
	local climb = 0
	if CLIMB[name] then
		local st: { N: number, At: number } = streak[name] or { N = 0, At = -1 }
		st.N = if now - st.At < 0.6 then math.min(st.N + 1, 8) else 0
		st.At = now
		streak[name] = st
		climb = st.N
	end
	local pos = o.Pos
	local bucket = if pos then "World" else "Flat"
	if live[bucket] >= (if pos then MAX_WORLD else MAX_FLAT) then
		return false
	end
	local holder: Instance = Workspace.CurrentCamera or Workspace
	local att: Attachment? = nil
	if pos then
		local lp = listenerPos()
		if lp and (lp - pos).Magnitude > MAX_DIST then
			return false
		end
		local a = Instance.new("Attachment")
		a.WorldPosition = pos
		a.Parent = Workspace.Terrain
		att, holder = a, a
	end
	last[key] = now
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = (BASE_VOLUME[name] or 0.7) * (o.Volume or 1) * (if menuOpen then MENU_QUIET else 1)
	s.PlaybackSpeed = (o.Pitch or 1) * (0.96 + rng:NextNumber() * 0.08) * (1 + 0.06 * climb)
	s.SoundGroup = groups.SFX
	if pos then
		s.RollOffMode = Enum.RollOffMode.LinearSquare
		s.RollOffMinDistance = MIN_DIST
		s.RollOffMaxDistance = MAX_DIST
	end
	s.Parent = holder
	live[bucket] += 1
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		live[bucket] -= 1
		s:Destroy()
		if att then
			att:Destroy()
		end
	end
	s.Ended:Once(finish)
	s:Play()
	-- safety: never leak a slot. TimeLength is 0 until the asset has loaded, so a sound that loads late (the 4 s hatch
	-- build-up) arms the timer only once its real length is known; one that never loads gives up after LOAD_WAIT.
	local function arm()
		task.delay(math.max(s.TimeLength / math.max(s.PlaybackSpeed, 0.1), 1.5) + 1.5, finish)
	end
	if s.IsLoaded then
		arm()
	else
		local armed = false
		local function armOnce()
			if not armed then
				armed = true
				arm()
			end
		end
		s.Loaded:Once(armOnce)
		task.delay(LOAD_WAIT, armOnce)
	end
	return true
end

-- Machine sounds ---------------------------------------------------------------------------

local function stopLoop(key: string, withStop: boolean)
	local l = loops[key]
	if not l then
		return
	end
	loops[key] = nil
	loopCount -= 1
	l.Sound:Stop()
	l.Sound:Destroy()
	if l.Part then
		l.Part:Destroy()
	end
	local m = MACHINES[l.Kind]
	if withStop and m and m.Stop then
		Audio.play(m.Stop, { Pos = l.Pos, Key = key .. ":stop" })
	end
end

local function loopWatch()
	local now = os.clock()
	for key, l in loops do
		local m = MACHINES[l.Kind]
		if now - l.LastSeen > ((m and m.Idle) or IDLE) then
			stopLoop(key, true)
		end
	end
	if loopCount <= 0 and loopConn then
		loopConn:Disconnect()
		loopConn = nil
	end
end

-- Call while a machine (or the held jackhammer) is working; stop calling and it winds down
-- after IDLE seconds. `key` identifies the machine; `pos` is its world position (nil = own,
-- flat). Repeated calls are cheap. The nearest MAX_LOOPS machines are audible.
function Audio.machineActive(key: string, kind: string, pos: Vector3?)
	local m = MACHINES[kind]
	if not m or not started then
		return
	end
	local l = loops[key]
	if l then
		l.LastSeen = os.clock()
		return
	end
	local id = idOf(m.Loop)
	if id == 0 then
		return
	end
	local lp = listenerPos()
	local dist = if pos and lp then (lp - pos).Magnitude else 0
	if dist > MAX_DIST then
		return
	end
	if loopCount >= MAX_LOOPS then
		-- replace the farthest loop only if this one is nearer
		local farKey, farDist = nil, -1
		for k, other in loops do
			local d = if other.Pos and lp then (lp - other.Pos).Magnitude else 0
			if d > farDist then
				farKey, farDist = k, d
			end
		end
		if not farKey or farDist <= dist then
			return
		end
		stopLoop(farKey, false)
	end
	local att: Attachment? = nil
	local holder: Instance = Workspace.CurrentCamera or Workspace
	if pos then
		local a = Instance.new("Attachment")
		a.WorldPosition = pos
		a.Parent = Workspace.Terrain
		att, holder = a, a
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	s.Volume = BASE_VOLUME[m.Loop] or 0.4
	s.SoundGroup = if m.Ambient then groups.Ambience else groups.SFX
	if pos then
		s.RollOffMode = Enum.RollOffMode.LinearSquare
		s.RollOffMinDistance = if m.Ambient then HUM_MIN else MIN_DIST
		s.RollOffMaxDistance = if m.Ambient then HUM_MAX else MAX_DIST
	end
	s.Parent = holder
	s:Play()
	loops[key] = { Sound = s, Part = att, Pos = pos, LastSeen = os.clock(), Kind = kind }
	loopCount += 1
	if m.Start then
		Audio.play(m.Start, { Pos = pos, Key = key .. ":start" })
	end
	if not loopConn then
		local acc = 0
		loopConn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc >= 0.1 then
				acc = 0
				loopWatch()
			end
		end)
	end
end

function Audio.machineStop(key: string)
	stopLoop(key, true)
end

-- Event helpers (one call each from the hook points) ---------------------------------------

-- Own strike contact. Jackhammer-type tools (hold) run the machine loop instead of a hit per swing.
function Audio.strike(isHold: boolean, pos: Vector3?)
	if isHold then
		Audio.machineActive("self:jack", "Jackhammer", nil)
		Audio.play("HammerHit", { Volume = 0.35, Pitch = 0.85, Key = "self:hit" })
	else
		Audio.play("HammerHit", { Key = "self:hit" })
	end
	if pos then
		Audio.play("StoneCrack", { Pos = pos, Volume = 0.4, Key = "self:chip" })
	end
	Audio.play("EggCrunch", { Key = "self:crunch" }) -- SoundConfig id; silent while it is 0
end

-- Another player's strike, positioned.
function Audio.strikeAt(pos: Vector3)
	Audio.play("HammerHit", { Pos = pos, Volume = 0.3, Key = "other:hit" })
	Audio.play("EggCrunch", { Pos = pos, Volume = 0.3, Key = "other:crunch" })
end

function Audio.rockCracked(pos: Vector3?)
	Audio.play("StoneCrack", { Pos = pos })
	Audio.play("EggPop", { Pos = pos }) -- an egg breaks open (SoundConfig id; silent while it is 0)
	if rng:NextNumber() < 0.5 then
		Audio.play("GravelSpill", { Pos = pos, Volume = 0.8 })
	end
end

-- Rare+ hatch: the choir build-up at the start of the slow-motion reveal (SoundConfig.Ids.HatchChoir; silent while 0).
-- Pets never roar (owner rule).
-- Dips music and ambience for a few seconds so the reveal sounds stand out.
function Audio.duck(seconds: number)
	duckToken += 1
	local mine = duckToken
	duck = 0.35
	applyVolumes()
	task.delay(seconds, function()
		if duckToken ~= mine then
			return
		end
		for i = 1, 6 do
			if duckToken ~= mine then
				return
			end
			duck = 0.35 + 0.65 * (i / 6)
			applyVolumes()
			task.wait(0.1)
		end
	end)
end

function Audio.hatchChoir()
	Audio.duck(4)
	Audio.play("HatchChoir")
end

-- A rock taken off the shared pile into the basket (own pickup, flat).
function Audio.pickup()
	Audio.play("EggGrab", { Key = "self:pick" }) -- stand-in Pickup until EggGrab is uploaded
end

-- Rocks set down at the player's crushing table (own deposit, flat).
function Audio.deposit()
	Audio.play("EggDrop", { Key = "self:deposit" }) -- stand-in Deposit until EggDrop is uploaded
end

-- A first-time material for this player.
function Audio.materialFound()
	Audio.play("MaterialFound")
end

function Audio.button()
	Audio.play("ButtonClickSoft")
end

local lastCount = -1
function Audio.countdown(n: number)
	if n ~= lastCount then
		lastCount = n
		Audio.play("CountdownTick", { Pitch = if n <= 1 then 1.35 else 1 })
	end
end

function Audio.resetCountdown()
	lastCount = -1
end

-- Hatch reveal: the cues per rarity live in shared/SoundCues (sting pitch / loudness climb with rarity; Epic+ add the
-- sparkle swell, Legendary and the Void Dragon add the drum hit). Pets never roar (owner rule).
function Audio.reveal(rarity: string?, isVoid: boolean?)
	Audio.duck(if isVoid or rarity == "Legendary" then 4 else 3)
	for _, c in SoundCues.reveal(rarity, isVoid) do
		local function go()
			Audio.play(c.Key, { Pitch = c.Pitch, Volume = c.Volume, Key = c.Tag })
		end
		if c.Delay > 0 then
			task.delay(c.Delay, go)
		else
			go()
		end
	end
end

-- Ambience --------------------------------------------------------------------------------

function Audio.setArea(area: string)
	if not started or ambience.Area == area then
		return
	end
	ambience.Area = area
	-- hunt wind bed: a soft 12 s wind loop under the race music while in the arena
	if area == "arena" then
		local wid = idOf("HuntWindBed")
		if wid ~= 0 and not windBed then
			local w = Instance.new("Sound")
			w.Name = "HuntWindBed"
			w.SoundId = "rbxassetid://" .. wid
			w.Looped = true
			w.Volume = 0.25
			w.SoundGroup = groups.Ambience
			w.Parent = SoundService
			w:Play()
			windBed = w
		end
	elseif windBed then
		windBed:Destroy()
		windBed = nil
	end
	-- leaving the arena: machine hums stop at once (no hum carried into the lobby)
	for key, l in loops do
		local m = MACHINES[l.Kind]
		if m and m.Ambient then
			stopLoop(key, false)
		end
	end
	local old = ambience.Sound
	ambience.Sound = nil
	if old then
		local o = old :: Sound
		local keep = o.Name == "Ambience_lobby"
		if keep then
			parkedLobby = o
		end
		task.spawn(function()
			for i = 1, 12 do
				if ambience.Sound == o then
					return -- back in the lobby before the fade ended: the parked sound is playing again
				end
				o.Volume = AMBIENCE_VOLUME * (1 - i / 12)
				task.wait(0.1)
			end
			if ambience.Sound == o then
				return
			end
			if keep then
				o:Pause()
			else
				o:Destroy()
			end
		end)
	end
	local id = idOf(AREA_AMBIENCE[area] or "")
	if id == 0 then
		return
	end
	local s: Sound
	if area == "lobby" and parkedLobby and parkedLobby.Parent then
		s = parkedLobby :: Sound
		parkedLobby = nil
		s.Volume = 0
		s:Resume()
	else
		s = Instance.new("Sound")
		s.Name = "Ambience_" .. area
		s.SoundId = "rbxassetid://" .. id
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = groups.Ambience
		s.Parent = SoundService
		s:Play()
	end
	ambience.Sound = s
	task.spawn(function()
		for i = 1, 12 do
			if s.Parent == nil then
				return
			end
			s.Volume = AMBIENCE_VOLUME * (i / 12)
			task.wait(0.1)
		end
	end)
end

local function rushGoal(): number
	local m = State.Match
	local ot = EggConfig.Overtime
	if not m or m.Tutorial or not ot.Enabled or m.Phase ~= "Searching" or type(m.SearchStart) ~= "number" then
		return 0
	end
	local elapsed = Workspace:GetServerTimeNow() - m.SearchStart
	return math.clamp((elapsed - (ot.RoundSeconds - RUSH_LEAD)) / RUSH_LEAD, 0, 1)
end

local function rushStep()
	local goal = rushGoal()
	if math.abs(goal - rush) < 0.005 then
		return
	end
	rush = if goal > rush then math.min(goal, rush + 0.05) else math.max(goal, rush - 0.1)
	applyVolumes()
	local s = ambience.Sound
	if s and ambience.Area == "arena" then
		s.PlaybackSpeed = 1 + RUSH_SPEED * rush
	end
end

local function currentArea(): string
	return if State.Match or Players.LocalPlayer:GetAttribute("MatchKey") then "arena" else "lobby"
end

-- A menu panel opened or closed (Main.client forwards UI.ModalChanged; UI requires Audio, so not required here).
function Audio.setMenuOpen(open: boolean)
	menuOpen = open
end

function Audio.init()
	if started then
		return
	end
	started = true
	local master = Instance.new("SoundGroup")
	master.Name = "CTR_Audio"
	master.Parent = SoundService
	groups.Master = master
	groups.SFX = makeGroup("SFX", master)
	groups.Ambience = makeGroup("Ambience", master)
	groups.Music = makeGroup("Music", master)
	applyVolumes()
	Audio.setArea(currentArea())
	task.spawn(function()
		while true do
			task.wait(0.25)
			rushStep()
		end
	end)
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			applyVolumes()
		elseif what == "Match" then
			Audio.setArea(currentArea())
			local m = State.Match
			if not m or m.Phase ~= "Countdown" then
				Audio.resetCountdown()
			end
		end
	end)
end

return Audio
