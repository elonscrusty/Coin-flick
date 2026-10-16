--!strict
-- Practice buddies (pure rules; tests/test_retention.luau drives them). The first hunt a new player plays (the
-- practice pile, Config.Tutorial) has a few friendly bots racing next to them, so the very first round feels like a
-- race with no queue wait. The bots only act it out: they walk to the pile, grab, walk to their own nest and tap
-- it. They never take a real egg, never crack one and can never find the pet (the practice pet is always the new
-- player's: RoundRocks TutorialBreak). The server (src/server/PracticeBots.luau) moves their characters.

local BotRules = {}

BotRules.Names = { "Pip", "Bolt", "Mo" }
BotRules.Count = 3 -- at most this many bots (one per free nest)

-- Fun outfits so the practice crew never reads as default avatars (walkthrough 10-14): a pet onesie each, body
-- colours plus a few chunky parts welded on (ears, spikes, tail). Procedural only (no catalog ids). Part offsets are
-- studs from the attach part's centre, R15 facing -Z (so +Z is the back); Rot is degrees.
export type OutfitPart = { Name: string, Attach: string, Shape: string, Size: { number }, Offset: { number }, Rot: { number }?, Color: Color3 }
export type Outfit = { Name: string, Skin: Color3, Body: Color3, Legs: Color3, Parts: { OutfitPart } }
local PINK, WHITE, ORANGE, CREAM, GREEN, LIME = Color3.fromRGB(255, 150, 200), Color3.fromRGB(255, 250, 245), Color3.fromRGB(255, 140, 50), Color3.fromRGB(255, 236, 205), Color3.fromRGB(90, 200, 100), Color3.fromRGB(200, 240, 90)
BotRules.Outfits = {
	{
		Name = "Bunny", Skin = Color3.fromRGB(255, 214, 170), Body = PINK, Legs = PINK,
		Parts = {
			{ Name = "EarL", Attach = "Head", Shape = "Block", Size = { 0.32, 1.1, 0.16 }, Offset = { -0.28, 1.05, 0 }, Rot = { 0, 0, 10 }, Color = PINK },
			{ Name = "EarR", Attach = "Head", Shape = "Block", Size = { 0.32, 1.1, 0.16 }, Offset = { 0.28, 1.05, 0 }, Rot = { 0, 0, -10 }, Color = PINK },
			{ Name = "EarInL", Attach = "Head", Shape = "Block", Size = { 0.16, 0.8, 0.05 }, Offset = { -0.29, 1.02, -0.09 }, Rot = { 0, 0, 10 }, Color = WHITE },
			{ Name = "EarInR", Attach = "Head", Shape = "Block", Size = { 0.16, 0.8, 0.05 }, Offset = { 0.29, 1.02, -0.09 }, Rot = { 0, 0, -10 }, Color = WHITE },
			{ Name = "Tail", Attach = "LowerTorso", Shape = "Ball", Size = { 0.6, 0.6, 0.6 }, Offset = { 0, 0, 0.55 }, Color = WHITE },
		},
	},
	{
		Name = "Fox", Skin = Color3.fromRGB(240, 190, 150), Body = ORANGE, Legs = Color3.fromRGB(60, 50, 50),
		Parts = {
			{ Name = "EarL", Attach = "Head", Shape = "Wedge", Size = { 0.2, 0.6, 0.5 }, Offset = { -0.38, 0.8, 0 }, Rot = { 0, 90, 0 }, Color = ORANGE },
			{ Name = "EarR", Attach = "Head", Shape = "Wedge", Size = { 0.2, 0.6, 0.5 }, Offset = { 0.38, 0.8, 0 }, Rot = { 0, 90, 0 }, Color = ORANGE },
			{ Name = "Tail", Attach = "LowerTorso", Shape = "Ball", Size = { 0.7, 0.7, 1.6 }, Offset = { 0, 0.2, 1.0 }, Rot = { -30, 0, 0 }, Color = ORANGE },
			{ Name = "TailTip", Attach = "LowerTorso", Shape = "Ball", Size = { 0.5, 0.5, 0.6 }, Offset = { 0, 0.62, 1.68 }, Rot = { -30, 0, 0 }, Color = CREAM },
		},
	},
	{
		Name = "Dino", Skin = Color3.fromRGB(200, 150, 110), Body = GREEN, Legs = GREEN,
		Parts = {
			{ Name = "Spike1", Attach = "Head", Shape = "Wedge", Size = { 0.2, 0.45, 0.45 }, Offset = { 0, 0.7, 0.15 }, Color = LIME },
			{ Name = "Spike2", Attach = "UpperTorso", Shape = "Wedge", Size = { 0.2, 0.5, 0.5 }, Offset = { 0, 0.5, 0.55 }, Rot = { 0, 0, 0 }, Color = LIME },
			{ Name = "Spike3", Attach = "UpperTorso", Shape = "Wedge", Size = { 0.2, 0.5, 0.5 }, Offset = { 0, -0.1, 0.55 }, Color = LIME },
			{ Name = "Tail", Attach = "LowerTorso", Shape = "Wedge", Size = { 0.6, 0.6, 1.6 }, Offset = { 0, -0.2, 1.05 }, Rot = { 0, 180, 0 }, Color = GREEN },
		},
	},
} :: { Outfit }

-- The outfit for bot number `i` (wraps around).
function BotRules.outfit(i: number): Outfit
	local n = #BotRules.Outfits
	return BotRules.Outfits[((math.max(1, i) - 1) % n) + 1]
end

-- Seconds each step lasts (walking steps end early when the bot arrives; WalkMax is the give-up time).
BotRules.Timing = {
	Grab = { 0.8, 1.6 },
	Crack = { 1.6, 3.2 },
	WalkMax = 7,
	FirstDelay = { 0.3, 1.5 }, -- a small random start so the bots do not move in lockstep
}
BotRules.WalkSpeed = 13 -- a little slower than a player (Roblox default 16), so the new player can keep up

export type Step = string -- "Wait" | "ToPile" | "Grab" | "ToNest" | "Crack"
BotRules.Order = { "ToPile", "Grab", "ToNest", "Crack" } :: { Step }

export type Bot = { Index: number, Name: string, Step: Step, Until: number, Carry: boolean }

local function range(rng: Random, r: { number }): number
	return r[1] + rng:NextNumber() * (r[2] - r[1])
end

-- The bots for a practice round with `freeNests` nests nobody uses (0..Count bots).
function BotRules.make(freeNests: number, rng: Random, now: number): { Bot }
	local out = {}
	for i = 1, math.clamp(freeNests, 0, BotRules.Count) do
		table.insert(out, {
			Index = i,
			Name = BotRules.Names[i],
			Step = "Wait" :: Step,
			Until = now + range(rng, BotRules.Timing.FirstDelay),
			Carry = false,
		})
	end
	return out
end

-- The step after `step` (Wait goes to ToPile, Crack goes round to ToPile again).
function BotRules.next(step: Step): Step
	local i = table.find(BotRules.Order, step)
	if not i then
		return "ToPile"
	end
	return BotRules.Order[(i % #BotRules.Order) + 1]
end

-- Moves `bot` on when its step is over: `arrived` = the walk reached its target. Returns true when the step changed.
-- Carry is true from the grab until the crack is done (the bot shows an egg over its head).
function BotRules.advance(bot: Bot, now: number, arrived: boolean, rng: Random): boolean
	local walking = bot.Step == "ToPile" or bot.Step == "ToNest"
	if not (now >= bot.Until or (walking and arrived)) then
		return false
	end
	local nextStep = BotRules.next(bot.Step)
	bot.Step = nextStep
	if nextStep == "Grab" then
		bot.Until = now + range(rng, BotRules.Timing.Grab)
	elseif nextStep == "Crack" then
		bot.Until = now + range(rng, BotRules.Timing.Crack)
	else
		bot.Until = now + BotRules.Timing.WalkMax
	end
	if nextStep == "ToNest" then
		bot.Carry = true
	elseif nextStep == "ToPile" then
		bot.Carry = false
	end
	return true
end

return BotRules
