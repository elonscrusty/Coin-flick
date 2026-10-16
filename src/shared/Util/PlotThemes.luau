--!strict
-- Plot looks: every reset gives your yard a new theme (Meadow, Beach, Candy, Castle, Space).
-- After the fifth look you can pick any look you have unlocked. Pure data and rules, so the
-- tests can check it offline. The server's Builders/PlotDecor turns a theme into parts.
-- Themes only change how the yard LOOKS. No theme changes cash, odds or anything else.

export type Sky = { atmosphere: Color3, decay: Color3, tint: Color3 }

export type Theme = {
	id: string,
	name: string,
	resets: number, -- resets needed before you can pick it
	pad: Color3, -- floor of the yard
	tile: Color3, -- checker tiles on the floor: clearly not white (the fence is white)
	ground: Color3, -- ring of ground outside the fence, so each yard reads as its own place
	border: Color3, -- trim around the floor
	fence: Color3, -- posts and rails
	post: Color3, -- fence cap / arch pillars
	sign: Color3, -- name sign board
	signText: Color3,
	accent: { Color3 }, -- small props (flowers, shells, sweets, lamps, crystals)
	foliage: { Color3 }, -- big tree-ish props
	trunk: Color3,
	stone: { Color3 }, -- rocks
	props: { string }, -- which small pieces fill the corners, in order
	sky: Sky, -- how the sky feels while you stand in this yard (client tints the haze)
	tableLook: string, -- name of the Config.TableLooks entry the table wears in this yard
	tree: string, -- big corner piece: "oak" | "palm" | "lolly" | "tower" | "crystal"
}

local THEMES: { Theme } = {
	{
		id = "meadow",
		name = "Sunny Meadow",
		resets = 0,
		pad = Color3.fromRGB(176, 226, 150),
		tile = Color3.fromRGB(130, 200, 110),
		ground = Color3.fromRGB(150, 222, 120),
		border = Color3.fromRGB(150, 100, 60),
		fence = Color3.fromRGB(255, 250, 240),
		post = Color3.fromRGB(150, 100, 60),
		sign = Color3.fromRGB(150, 100, 60),
		signText = Color3.fromRGB(255, 255, 255),
		accent = {
			Color3.fromRGB(255, 90, 120),
			Color3.fromRGB(255, 220, 60),
			Color3.fromRGB(150, 120, 255),
			Color3.fromRGB(255, 150, 60),
		},
		foliage = { Color3.fromRGB(80, 200, 80), Color3.fromRGB(60, 180, 100), Color3.fromRGB(120, 220, 70) },
		trunk = Color3.fromRGB(120, 80, 45),
		stone = { Color3.fromRGB(170, 176, 184), Color3.fromRGB(196, 190, 176) },
		props = { "bench", "boulder", "crate", "bush" },
		sky = {
			atmosphere = Color3.fromRGB(150, 210, 255),
			decay = Color3.fromRGB(95, 175, 255),
			tint = Color3.fromRGB(255, 255, 255),
		},
		tableLook = "Picnic Wood",
		tree = "oak",
	},
	{
		id = "beach",
		name = "Sandy Beach",
		resets = 1,
		pad = Color3.fromRGB(250, 228, 160),
		tile = Color3.fromRGB(232, 194, 118),
		ground = Color3.fromRGB(246, 224, 150),
		border = Color3.fromRGB(70, 190, 255),
		fence = Color3.fromRGB(255, 255, 255),
		post = Color3.fromRGB(255, 120, 90),
		sign = Color3.fromRGB(30, 150, 230),
		signText = Color3.fromRGB(255, 255, 255),
		accent = {
			Color3.fromRGB(255, 130, 150),
			Color3.fromRGB(255, 220, 90),
			Color3.fromRGB(90, 220, 230),
			Color3.fromRGB(255, 255, 255),
		},
		foliage = { Color3.fromRGB(60, 190, 90), Color3.fromRGB(90, 210, 110) },
		trunk = Color3.fromRGB(190, 140, 80),
		stone = { Color3.fromRGB(226, 208, 170), Color3.fromRGB(240, 220, 190) },
		props = { "umbrella", "shell", "bucket", "boulder" },
		sky = {
			atmosphere = Color3.fromRGB(140, 228, 255),
			decay = Color3.fromRGB(60, 205, 255),
			tint = Color3.fromRGB(255, 250, 235),
		},
		tableLook = "Ocean Splash",
		tree = "palm",
	},
	{
		id = "candy",
		name = "Candy Land",
		resets = 2,
		pad = Color3.fromRGB(255, 205, 230),
		tile = Color3.fromRGB(255, 160, 205),
		ground = Color3.fromRGB(255, 196, 224),
		border = Color3.fromRGB(255, 120, 190),
		fence = Color3.fromRGB(255, 255, 255),
		post = Color3.fromRGB(255, 90, 160),
		sign = Color3.fromRGB(190, 110, 255),
		signText = Color3.fromRGB(255, 255, 255),
		accent = {
			Color3.fromRGB(255, 90, 160),
			Color3.fromRGB(120, 230, 200),
			Color3.fromRGB(255, 230, 90),
			Color3.fromRGB(170, 130, 255),
		},
		foliage = { Color3.fromRGB(255, 130, 190), Color3.fromRGB(150, 230, 210), Color3.fromRGB(255, 220, 110) },
		trunk = Color3.fromRGB(255, 255, 255),
		stone = { Color3.fromRGB(255, 170, 210), Color3.fromRGB(190, 160, 255) },
		props = { "cupcake", "gumdrop", "candycane", "boulder" },
		sky = {
			atmosphere = Color3.fromRGB(255, 192, 232),
			decay = Color3.fromRGB(255, 140, 212),
			tint = Color3.fromRGB(255, 238, 250),
		},
		tableLook = "Bubblegum",
		tree = "lolly",
	},
	{
		id = "castle",
		name = "Toy Castle",
		resets = 3,
		pad = Color3.fromRGB(214, 214, 226),
		tile = Color3.fromRGB(168, 174, 206),
		ground = Color3.fromRGB(190, 194, 208),
		border = Color3.fromRGB(120, 130, 180),
		fence = Color3.fromRGB(230, 232, 245),
		post = Color3.fromRGB(110, 120, 170),
		sign = Color3.fromRGB(90, 100, 170),
		signText = Color3.fromRGB(255, 226, 120),
		accent = {
			Color3.fromRGB(255, 200, 60),
			Color3.fromRGB(255, 120, 120),
			Color3.fromRGB(110, 190, 255),
			Color3.fromRGB(255, 255, 255),
		},
		foliage = { Color3.fromRGB(110, 120, 190), Color3.fromRGB(130, 140, 210) },
		trunk = Color3.fromRGB(190, 192, 210),
		stone = { Color3.fromRGB(190, 194, 212), Color3.fromRGB(214, 216, 232) },
		props = { "barrel", "crate", "torch", "boulder" },
		sky = {
			atmosphere = Color3.fromRGB(190, 200, 255),
			decay = Color3.fromRGB(140, 150, 238),
			tint = Color3.fromRGB(244, 244, 255),
		},
		tableLook = "Royal Purple",
		tree = "tower",
	},
	{
		id = "space",
		name = "Star Station",
		resets = 4,
		pad = Color3.fromRGB(150, 130, 230),
		tile = Color3.fromRGB(116, 96, 205),
		ground = Color3.fromRGB(150, 152, 182),
		border = Color3.fromRGB(90, 255, 230),
		fence = Color3.fromRGB(235, 240, 255),
		post = Color3.fromRGB(90, 255, 230),
		sign = Color3.fromRGB(70, 60, 160),
		signText = Color3.fromRGB(120, 255, 235),
		accent = {
			Color3.fromRGB(90, 255, 230),
			Color3.fromRGB(255, 120, 230),
			Color3.fromRGB(255, 230, 100),
			Color3.fromRGB(140, 200, 255),
		},
		foliage = { Color3.fromRGB(90, 255, 230), Color3.fromRGB(255, 120, 230), Color3.fromRGB(140, 200, 255) },
		trunk = Color3.fromRGB(220, 224, 245),
		stone = { Color3.fromRGB(180, 160, 240), Color3.fromRGB(210, 190, 255) },
		props = { "orb", "boulder", "antenna", "crate" },
		sky = {
			atmosphere = Color3.fromRGB(172, 150, 255),
			decay = Color3.fromRGB(120, 100, 238),
			tint = Color3.fromRGB(240, 234, 255),
		},
		tableLook = "Star Station",
		tree = "crystal",
	},
}

local PlotThemes = {}

PlotThemes.list = table.freeze(THEMES)

-- Plain list of every theme id, in unlock order.
function PlotThemes.ids(): { string }
	local out = {}
	for _, t in THEMES do
		table.insert(out, t.id)
	end
	return out
end

function PlotThemes.index(id: unknown): number?
	for i, t in THEMES do
		if t.id == id then
			return i
		end
	end
	return nil
end

function PlotThemes.get(id: string): Theme?
	local i = PlotThemes.index(id)
	return if i then THEMES[i] else nil
end

-- The look a player gets on their own: reset 0 Meadow, 1 Beach, 2 Candy, 3 Castle, 4 Space,
-- then it loops (reset 5 is Meadow again, until they pick one).
function PlotThemes.cycle(resets: number): Theme
	local n = math.max(0, math.floor(resets))
	return THEMES[(n % #THEMES) + 1]
end

function PlotThemes.isUnlocked(id: unknown, resets: number): boolean
	local i = PlotThemes.index(id)
	if not i then
		return false
	end
	return resets >= THEMES[i].resets
end

-- Looks a player may pick right now.
function PlotThemes.unlocked(resets: number): { string }
	local out = {}
	for _, t in THEMES do
		if resets >= t.resets then
			table.insert(out, t.id)
		end
	end
	return out
end

-- Which look to build. Before the last look is unlocked the newest look shows (no picking
-- yet). After that, a valid pick wins; no pick (or a pick that is not unlocked) follows the
-- cycle, so a bad saved value can never crash or unlock anything.
function PlotThemes.resolve(resets: number, picked: unknown): Theme
	if resets < THEMES[#THEMES].resets then
		return PlotThemes.cycle(resets)
	end
	if typeof(picked) == "string" and PlotThemes.isUnlocked(picked, resets) then
		return THEMES[PlotThemes.index(picked) :: number]
	end
	return PlotThemes.cycle(resets)
end

-- Picking is allowed only once every look has been seen once (reset 4 and up).
function PlotThemes.canPick(resets: number): boolean
	return resets >= THEMES[#THEMES].resets
end

return PlotThemes
