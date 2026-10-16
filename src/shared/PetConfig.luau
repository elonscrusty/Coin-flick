--!strict
-- Coin pets: all tuning in one place. Pets are won by goals, never by random
-- eggs or boxes. The first pet (the puppy) is free; the other four unlock by
-- doing something. An active pet flips its own coin for extra cash and levels up.

export type GoalKind = "free" | "flips" | "headsInRow" | "megaBeats" | "resets"

export type PetDef = {
	id: string,
	name: string,
	icon: string,
	goal: GoalKind,
	target: number, -- how many of `goal` it takes (0 for the free puppy)
	goalText: string, -- kid-friendly goal, shown on the pet card
	interval: number, -- seconds between this pet's coin flips at level 1
	mult: number, -- cash of a pet flip = cash per heads x mult (at level 1)
	body: Color3,
	accent: Color3,
}

-- In unlock order. All cute, nothing scary.
local Pets: { PetDef } = {
	{
		id = "puppy",
		name = "Puppy",
		icon = "🐶",
		goal = "free",
		target = 0,
		goalText = "Free gift!",
		interval = 4,
		mult = 0.5,
		body = Color3.fromRGB(222, 170, 110),
		accent = Color3.fromRGB(120, 76, 42),
	},
	{
		id = "pig",
		name = "Piggy",
		icon = "🐷",
		goal = "flips",
		target = 1000,
		goalText = "Flip 1,000 coins",
		interval = 3.5,
		mult = 0.7,
		body = Color3.fromRGB(255, 160, 200),
		accent = Color3.fromRGB(235, 100, 150),
	},
	{
		id = "bunny",
		name = "Bunny",
		icon = "🐰",
		goal = "headsInRow",
		target = 10, -- same number as Config.STREAK_GOAL
		goalText = "Get 10 heads in a row",
		interval = 3,
		mult = 0.9,
		body = Color3.fromRGB(245, 245, 250),
		accent = Color3.fromRGB(255, 170, 190),
	},
	{
		id = "dragon",
		name = "Dragon",
		icon = "🐲",
		goal = "megaBeats",
		target = 10,
		goalText = "Beat the MEGA coin 10 times",
		interval = 3,
		mult = 1.4,
		body = Color3.fromRGB(110, 210, 110),
		accent = Color3.fromRGB(255, 200, 60),
	},
	{
		id = "cat",
		name = "Space Cat",
		icon = "🐱",
		goal = "resets",
		target = 4, -- keep equal to SPACE_PLOT_RESETS: the 4th table look is the space plot
		goalText = "Reach the space plot",
		interval = 2.5,
		mult = 1.6,
		body = Color3.fromRGB(150, 130, 255),
		accent = Color3.fromRGB(90, 220, 255),
	},
}

return table.freeze({
	MAX_LEVEL = 10,
	XP_PER_FLIP = 1,
	XP_BASE = 15, -- xp to go from level 1 to 2...
	XP_GROWTH = 1.5, -- ...and each level after needs 1.5x more
	LEVEL_CASH = 0.15, -- each level: +15% cash per pet flip
	LEVEL_SPEED = 0.96, -- each level: flips 4% sooner
	SPACE_PLOT_RESETS = 4,
	EQUIP_RATE = 3, -- pet swaps per second per player (token bucket)
	EQUIP_BURST = 5,
	FREE_PET = "puppy",
	Pets = table.freeze(Pets),
})
