--!strict
-- Lobby HUD v2 idle personality (carter 2026-10-15): now and then ONE button does its own short move, then the HUD
-- rests for a few quiet seconds. Pure numbers and picks; client/ui/LobbyHudV2 plays them.
--   * Moves[name]: the button's steps. Each step tweens the whole painted button (one piece) to a pose:
--     x / y = offset as a share of the button's own size, sx / sy = size share, rot = degrees. Every move ends at rest.
--   * Moves[name].Fx: the separate light decoration that goes with it (Stars, Burst, Glow, Flash); Low Effects drops it.
--   * pick(now, lastAt, last, claimable, r): which button goes next (nil = nobody is ready). DAILY only goes while a
--     reward is claimable; never the same button twice in a row; each button rests between its own turns.

local LobbyHudIdle = {}

export type Step = { d: number, x: number?, y: number?, sx: number?, sy: number?, rot: number?, style: string?, dir: string? }
export type Move = { Steps: { Step }, Fx: string?, FxAt: number?, Stretch: boolean? }

LobbyHudIdle.Gap = { Min = 3.5, Max = 5.5 } -- quiet seconds after a move ends, before the next one starts
LobbyHudIdle.FirstWait = 2.5 -- after arriving in the lobby (the entrance pop plays first)
LobbyHudIdle.Rest = { Play = 8, Default = 14, Daily = 9 } -- a button's own rest between its turns
LobbyHudIdle.Weight = { Play = 3, Daily = 2, Default = 1 } -- PLAY is the liveliest
LobbyHudIdle.Limit = { Move = 0.12, Size = 0.1, Rot = 9, Time = 1.6 } -- keep every pose close to rest (tested)

LobbyHudIdle.Order = { "Play", "MyPets", "PetBook", "Daily", "Spin", "Train", "Fight", "Shop" }

LobbyHudIdle.Moves = {
	-- squash, spring up, settle with a little bounce; three tiny stars pop round the edges on the spring
	Play = {
		Steps = {
			{ d = 0.12, y = 0.03, sx = 1.05, sy = 0.92, style = "Quad" },
			{ d = 0.16, y = -0.08, sx = 0.97, sy = 1.05, style = "Quad" },
			{ d = 0.4, style = "Back" },
		},
		Fx = "Stars",
		FxAt = 0.12,
		Stretch = true,
	},
	-- an excited hop with a gentle tilt, then settle
	MyPets = {
		Steps = {
			{ d = 0.14, y = -0.09, rot = -5, style = "Quad" },
			{ d = 0.14, y = 0.01, rot = 3, style = "Quad", dir = "In" },
			{ d = 0.3, style = "Back" },
		},
	},
	-- a quick side-to-side wiggle, like a book asking to be opened
	PetBook = {
		Steps = {
			{ d = 0.09, x = 0.015, rot = 4, style = "Sine" },
			{ d = 0.12, x = -0.015, rot = -4, style = "Sine" },
			{ d = 0.11, x = 0.01, rot = 3, style = "Sine" },
			{ d = 0.1, x = -0.005, rot = -2, style = "Sine" },
			{ d = 0.15, style = "Sine" },
		},
	},
	-- the gift shakes with a small sparkle burst (only while a reward is claimable)
	Daily = {
		Steps = {
			{ d = 0.07, rot = -7, sx = 1.04, sy = 1.04, style = "Quad" },
			{ d = 0.09, rot = 7, sx = 1.04, sy = 1.04, style = "Quad" },
			{ d = 0.09, rot = -5, sx = 1.02, sy = 1.02, style = "Quad" },
			{ d = 0.08, rot = 4, style = "Quad" },
			{ d = 0.2, style = "Back" },
		},
		Fx = "Burst",
		FxAt = 0.05,
	},
	-- a playful rock of the whole button (the wheel is part of the picture, so the picture rocks, never spins)
	Spin = {
		Steps = {
			{ d = 0.25, rot = 6, style = "Sine" },
			{ d = 0.4, rot = -6, style = "Sine" },
			{ d = 0.3, rot = 3, style = "Sine" },
			{ d = 0.3, style = "Sine" },
		},
	},
	-- a small hop up with a soft glow underneath
	Train = {
		Steps = {
			{ d = 0.16, y = -0.08, style = "Quad" },
			{ d = 0.14, y = 0.01, style = "Quad", dir = "In" },
			{ d = 0.2, style = "Back" },
		},
		Fx = "Glow",
		FxAt = 0,
	},
	-- a short punchy tilt and a quick flash round the edge
	Fight = {
		Steps = {
			{ d = 0.07, rot = -8, sx = 1.05, sy = 1.05, style = "Quad" },
			{ d = 0.1, rot = 3, sx = 1.01, sy = 1.01, style = "Quad" },
			{ d = 0.22, style = "Back" },
		},
		Fx = "Flash",
		FxAt = 0.03,
	},
	-- a gentle sway, like a bag hanging from a hand
	Shop = {
		Steps = {
			{ d = 0.3, x = 0.01, rot = 4, style = "Sine" },
			{ d = 0.45, x = -0.01, rot = -4, style = "Sine" },
			{ d = 0.35, x = 0.005, rot = 2, style = "Sine" },
			{ d = 0.3, style = "Sine" },
		},
	},
} :: { [string]: Move }

-- where the separate sparkles sit, as shares of the button's box (round the edges, never over the words)
LobbyHudIdle.StarSpots = {
	Play = { { x = 0.03, y = 0.12 }, { x = 0.97, y = 0.18 }, { x = 0.9, y = 0.92 } },
	Daily = { { x = 0.08, y = 0.08 }, { x = 0.92, y = 0.1 }, { x = 0.04, y = 0.6 }, { x = 0.96, y = 0.55 } },
}

function LobbyHudIdle.duration(name: string): number
	local m = LobbyHudIdle.Moves[name]
	local t = 0
	if m then
		for _, s in m.Steps do
			t += s.d
		end
	end
	return t
end

local function rest(name: string): number
	return (LobbyHudIdle.Rest :: any)[name] or LobbyHudIdle.Rest.Default
end

local function weight(name: string): number
	return (LobbyHudIdle.Weight :: any)[name] or LobbyHudIdle.Weight.Default
end

-- quiet seconds before the next move (r in 0..1)
function LobbyHudIdle.gap(r: number): number
	local g = LobbyHudIdle.Gap
	return g.Min + (g.Max - g.Min) * math.clamp(r, 0, 1)
end

-- the next button to move, or nil when none is ready. `lastAt[name]` = when it last moved (nil = never).
-- `skip[name]` = true for a button that is busy (held down or hovered) and must not move now.
function LobbyHudIdle.pick(now: number, lastAt: { [string]: number }, last: string?, claimable: boolean, r: number, skip: { [string]: boolean? }?): string?
	local ready: { string } = {}
	local total = 0
	for _, name in LobbyHudIdle.Order do
		local at = lastAt[name]
		local ok = name ~= last and (at == nil or now - at >= rest(name)) and not (skip and skip[name])
		if name == "Daily" and not claimable then
			ok = false
		end
		if ok then
			table.insert(ready, name)
			total += weight(name)
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.clamp(r, 0, 0.999999) * total
	for _, name in ready do
		roll -= weight(name)
		if roll < 0 then
			return name
		end
	end
	return ready[#ready]
end

return LobbyHudIdle
