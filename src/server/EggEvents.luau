--!strict
-- Egg events (tuning in src/shared/EggConfig.luau):
--   * Wobble hint: every few seconds (server-decided gap) a small patch of eggs still in the pile wobbles for everyone in the
--     match. Each anchor is decided at fire time by EggHints.pickForTier (small chance of the pet egg while it is in
--     the pile, otherwise a uniformly random other pile egg); the pile eggs near a jittered point around it wobble
--     together (EggHints.patch), and the jitter usually leaves the anchor outside its own patch. Nothing is
--     precomputed or sent ahead; eggs in baskets, trays or on plates never wobble. The payload is a list of pile
--     ids, never the anchor alone. Every zone mixes in decoys; the Meadow (EggConfig.Wobble.SlowTiers) is slower.
--   * Speed boots: finishing an ordinary egg has a small server-rolled chance to give that player a short walk
--     speed boost. The server sets WalkSpeed and restores it afterwards (only if nothing else changed it).
--   * Overtime: after EggConfig.Overtime.RoundSeconds of searching the pet egg glows gold for the match, as soon as
--     it is in the pile (if it is carried or on a nest at that moment, the glow waits; wobbles keep going until the
--     glow is sent). Sync re-sends it (EggEvents.resend).
--   * Chirp: a pile egg near a player chirps for that player (EggConfig.Chirp) at a jittered point (no id); it is
--     the pet egg only with a small chance, otherwise a nearby decoy egg.
-- MatchService calls EggEvents.step(m, t) for every Searching match; RockService calls EggEvents.cracked(m, uid)
-- for every ordinary egg a player finishes.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local EggConfig = require(Shared.EggConfig)
local EggHints = require(Shared.EggHints)

local EggEvents = {}

type WobbleState = { Round: number, NextAt: number, Start: number, Overtime: boolean }

local rng = Random.new()
local wobble: { [any]: WobbleState } = setmetatable({}, { __mode = "k" }) :: any -- per match table, dies with it
-- Active boosts per user: the speed we set and when it ends (server clock).
local boosts: { [number]: { Speed: number, Base: number, Until: number, Token: number } } = {}
local token = 0

local function fireMatch(m: any, kind: string, payload: any)
	local ev = Net.event("EggEvent")
	for uid in m.Present do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			ev:FireClient(p, kind, payload)
		end
	end
end

local function gap(tier: string?): number
	local lo, hi = EggHints.gapRange(tier)
	return rng:NextNumber(lo, hi)
end

-- The pile eggs of a match as { Id, Pos } in world space.
local function pileEggs(m: any, core: any): { { Id: number, Pos: Vector3 } }
	local eggs = {}
	local center = m.Arena and m.Arena.Center
	if not center then
		return eggs
	end
	for _, eid in EggHints.pileIds(core.Rocks) do
		local lp = core.Pile:localPosition(eid)
		if lp then
			table.insert(eggs, { Id = eid, Pos = center + lp })
		end
	end
	return eggs
end

local chirpStep: (any, any, number) -> () -- defined below

-- The pet egg's id while it is in the pile, else nil (the overtime glow can only show on a pile egg).
local function overtimeId(core: any): number?
	local rock = core.TargetId and core.Rocks[core.TargetId]
	return if rock and rock.State == "InPile" then core.TargetId else nil
end

-- One scheduler step for a Searching match (t = os.clock()).
function EggEvents.step(m: any, t: number)
	if m.Phase ~= "Searching" then
		return
	end
	local core = m.Core
	if not core or core.Phase ~= "Searching" then
		return
	end
	chirpStep(m, core, t)
	local st = wobble[m]
	if st == nil or st.Round ~= m.Round then
		-- first wobble one gap after Searching starts; the overtime clock starts here too
		wobble[m] = { Round = m.Round, NextAt = t + gap(core.Tier), Start = t, Overtime = false }
		return
	end
	local ot = EggConfig.Overtime
	if ot.Enabled and not st.Overtime and not m.Tutorial and t - st.Start >= ot.RoundSeconds then
		local id = overtimeId(core)
		if id then
			-- Only set once it is really sent: an egg carried or on a nest at 3:00 glows once it is back in the pile.
			st.Overtime = true
			-- a glowing egg buried in the mound could not be picked up (Studio 2026-10-15): lift it to a reachable
			-- spot first (RoundRocks.surface; the Move event goes out with the next rock flush)
			core:surface(id)
			fireMatch(m, "Overtime", { Round = m.Round, Id = id }) -- the one time the pet egg is named
		end
	end
	if not EggConfig.Wobble.Enabled or st.Overtime then
		return
	end
	if t < st.NextAt then
		return
	end
	st.NextAt = t + gap(core.Tier)
	-- Decided now, from the live pile: only eggs still in the pile can be picked; decoys in every zone.
	local id = EggHints.pickForTier(rng, EggHints.pileIds(core.Rocks), core.TargetId, core.Tier)
	local center = m.Arena and m.Arena.Center
	local anchorLocal = id and center and core.Pile:localPosition(id)
	if anchorLocal then
		-- Patch hint: never one id. Every pile egg near a jittered point around the anchor wobbles together.
		local w = EggConfig.Wobble
		local ids = EggHints.patch(rng, center + anchorLocal, pileEggs(m, core), w.PatchRadius, w.PatchJitterMin, w.PatchJitterMax, w.PatchMax)
		if #ids > 0 then
			fireMatch(m, "Wobble", { Round = m.Round, Ids = ids })
		end
	end
end

-- Sync / late join: the overtime glow is an event, so a client that rebuilt its pile gets it again.
function EggEvents.resend(m: any, player: Player)
	local st = wobble[m]
	local core = m.Core
	if not st or not core or st.Round ~= m.Round or not st.Overtime or m.Phase ~= "Searching" then
		return
	end
	local id = overtimeId(core)
	if id then
		Net.event("EggEvent"):FireClient(player, "Overtime", { Round = m.Round, Id = id })
	end
end

-- Chirps: per match, per player, the next check time. Only pile eggs chirp, only to a player close to them, never
-- in the practice round. The pet egg is only sometimes the source; the payload is a jittered point, not an id.
local chirpAt: { [any]: { Round: number, Next: { [number]: number } } } = setmetatable({}, { __mode = "k" }) :: any

function chirpStep(m: any, core: any, t: number)
	local cfg = EggConfig.Chirp
	if not cfg.Enabled or m.Tutorial or not m.Arena or not m.Arena.Center then
		return
	end
	local st = chirpAt[m]
	if st == nil or st.Round ~= m.Round then
		st = { Round = m.Round, Next = {} }
		chirpAt[m] = st
	end
	local ev = Net.event("EggEvent")
	local eggs: { { Id: number, Pos: Vector3 } }? = nil -- built once per step, only when someone is due
	for uid in m.Present do
		local due = st.Next[uid]
		if due == nil then
			st.Next[uid] = t + rng:NextNumber(cfg.MinGap, cfg.MaxGap)
		elseif t >= due then
			st.Next[uid] = t + rng:NextNumber(cfg.MinGap, cfg.MaxGap)
			local p = Players:GetPlayerByUserId(uid)
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if p and root and root:IsA("BasePart") and rng:NextNumber() < cfg.Chance then
				eggs = eggs or pileEggs(m, core)
				local src = EggHints.chirpSource(rng, eggs :: any, root.Position, cfg.Radius, core.TargetId, cfg.TargetChance)
				local at = EggHints.chirpPoint(rng, src, root.Position, math.huge, cfg.JitterMin, cfg.JitterMax)
				if at then
					ev:FireClient(p, "Chirp", { Round = m.Round, Pos = at })
				end
			end
		end
	end
end

-- Walk speed allowance multiplier for a movement check: >1 while the player wears speed boots.
function EggEvents.speedAllowance(uid: number): number
	local b = boosts[uid]
	if b and Workspace:GetServerTimeNow() < b.Until then
		return 1 + EggConfig.Boots.Bonus
	end
	return 1
end

local function endBoost(player: Player, my: number)
	local b = boosts[player.UserId]
	if not b or b.Token ~= my then
		return -- a newer boost took over
	end
	boosts[player.UserId] = nil
	player:SetAttribute("SpeedBoost", nil)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	-- Restore only our own speed: a freeze (countdown) or a respawn already set its own value.
	if hum and math.abs(hum.WalkSpeed - b.Speed) < 0.01 then
		hum.WalkSpeed = b.Base -- the speed before the boots (pet speed bonus included)
	end
end

-- An ordinary egg finished by `uid` in match `m`: maybe drop speed boots.
function EggEvents.cracked(m: any, uid: number)
	local cfg = EggConfig.Boots
	if not cfg.Enabled or m.Phase ~= "Searching" then
		return
	end
	local player = Players:GetPlayerByUserId(uid)
	if not player or boosts[uid] then
		return -- one pair at a time: no roll while boosted
	end
	if rng:NextNumber() >= cfg.Chance then
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.WalkSpeed <= 0 then
		return
	end
	token += 1
	local my = token
	-- The boots multiply the hunter's current speed, so a speed pet's bonus (MatchService.setFrozen) is kept and
	-- comes back unchanged when they run out.
	local base = hum.WalkSpeed
	local speed = base * (1 + cfg.Bonus)
	local untilT = Workspace:GetServerTimeNow() + cfg.Seconds
	boosts[uid] = { Speed = speed, Base = base, Until = untilT, Token = my }
	-- Movement checks can read this to widen their allowance while boosted.
	player:SetAttribute("SpeedBoost", 1 + cfg.Bonus)
	hum.WalkSpeed = speed
	fireMatch(m, "Boots", { Round = m.Round, UserId = uid, Until = untilT, Seconds = cfg.Seconds })
	task.delay(cfg.Seconds, function()
		if player.Parent then
			endBoost(player, my)
		elseif boosts[uid] and boosts[uid].Token == my then
			boosts[uid] = nil -- only our own boost: a rejoined player's newer boost is keyed by the same UserId
		end
	end)
end

function EggEvents.start()
	Players.PlayerRemoving:Connect(function(p)
		boosts[p.UserId] = nil
	end)
end

return EggEvents
