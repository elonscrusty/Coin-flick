--!strict
-- What the GIFTS and PETS shop tabs draw, as plain data (no Roblox objects), so
-- tests/specs/GiftPetView.spec.luau can check the words, bars and buttons offline.
-- The server decides every reward; these views only describe it.

local EventText = require(script.Parent.EventText)
local Format = require(script.Parent.Format)
local PanelView = require(script.Parent.PanelView)
local PetConfig = require(script.Parent.Parent.PetConfig)
local PetRules = require(script.Parent.PetRules)
local Types = require(script.Parent.Parent.Types)

type DailyView = Types.DailyView
type PetView = PetRules.PetView
type Look = PanelView.Look

local GiftPetView = {}

export type Button = { text: string, look: Look }
export type GiftCell = { day: number, text: string, hats: number, state: "claimed" | "ready" | "later" }
export type JobRow = {
	text: string,
	frac: number, -- 0..1 bar fill
	count: string, -- "3/10"
	reward: string,
	button: Button,
	slot: number,
	canClaim: boolean,
}
export type DailyRows = { cells: { GiftCell }, gift: Button, giftReady: boolean, timer: string, jobs: { JobRow } }
export type PetRow = {
	id: string,
	icon: string,
	name: string,
	line: string,
	frac: number,
	bar: string,
	button: Button,
	action: "equip" | "away" | "none",
	owned: boolean,
	active: boolean,
}

GiftPetView.GIFT_TAB = "GIFTS"
GiftPetView.PETS_TAB = "PETS"
GiftPetView.NO_DAILY = "Loading your gifts..."

-- One clock format everywhere ("3:51", "3h 20m"), the same as the HUD chip.
function GiftPetView.timeLeft(seconds: number): string
	return EventText.span(seconds)
end

local function rewardText(cash: number, hats: number): string
	local text = PanelView.money(cash)
	if hats > 0 then
		text ..= ` +🎩{hats}`
	end
	return text
end

-- The one "next gift" number the HUD chip also shows: the soonest waiting play gift, else the
-- wait for tomorrow's daily gift. Returns seconds, or 0 when a play gift is ready to take.
function GiftPetView.nextGiftSeconds(view: DailyView, now: number, play: Types.PlayGiftView?, playAge: number): number
	local nearest = math.max(0, view.nextReset - now)
	if play then
		for _, g in play.gifts do
			if g.state == "ready" then
				return 0
			elseif g.state == "waiting" then
				nearest = math.min(nearest, math.max(0, g.left - playAge))
			end
		end
	end
	return nearest
end

function GiftPetView.dailyRows(view: DailyView, now: number, play: Types.PlayGiftView?, playAge: number?): DailyRows
	local gift = view.gift
	local perHeads = gift.cash / math.max(1, gift.flips)
	local cells: { GiftCell } = {}
	for i, reward in gift.cycle do
		local state: "claimed" | "ready" | "later" = "later"
		if i < gift.dayIndex or (i == gift.dayIndex and not gift.ready) then
			state = "claimed"
		elseif i == gift.dayIndex then
			state = "ready"
		end
		table.insert(cells, {
			day = i,
			text = PanelView.money(reward.flips * math.max(1, perHeads)),
			hats = reward.hats,
			state = state,
		})
	end
	local timer = `Daily gifts reset in {GiftPetView.timeLeft(view.nextReset - now)}`
	local giftButton: Button = if gift.ready
		then { text = `GET DAY {gift.dayIndex} GIFT!`, look = "buy" }
		else {
			text = EventText.giftWait(GiftPetView.nextGiftSeconds(view, now, play, playAge or 0)),
			look = "done",
		}
	local jobs: { JobRow } = {}
	for i, job in view.jobs do
		local button: Button = if job.claimed
			then { text = "DONE", look = "done" }
			elseif job.done then { text = "CLAIM!", look = "buy" }
			else { text = "NOT YET", look = "poor" }
		table.insert(jobs, {
			text = PanelView.fixCount(job.text),
			frac = math.clamp(job.progress / math.max(1, job.goal), 0, 1),
			count = `{Format.short(job.progress)}/{Format.short(job.goal)}`,
			reward = rewardText(job.cash, job.hats),
			button = button,
			slot = i,
			canClaim = job.done and not job.claimed,
		})
	end
	return { cells = cells, gift = giftButton, giftReady = gift.ready, timer = timer, jobs = jobs }
end

function GiftPetView.petRows(views: { PetView }): { PetRow }
	local rows: { PetRow } = {}
	for _, view in views do
		local def = PetRules.def(view.id)
		if not def then
			continue
		end
		local row: PetRow
		if view.owned then
			local maxed = view.xpNeeded <= 0
			row = {
				id = view.id,
				icon = def.icon,
				name = def.name,
				line = `Level {view.level} • {PanelView.money(view.cashPerFlip)} every {string.format(
					"%.1f",
					view.seconds
				)}s`,
				frac = if maxed then 1 else math.clamp(view.xp / view.xpNeeded, 0, 1),
				bar = if maxed then "MAX LEVEL ★" else `XP {Format.short(view.xp)}/{Format.short(view.xpNeeded)}`,
				button = if view.active
					then { text = "PUT AWAY", look = "equipped" }
					else { text = "EQUIP", look = "buy" },
				action = if view.active then "away" else "equip",
				owned = true,
				active = view.active,
			}
		else
			row = {
				id = view.id,
				icon = def.icon,
				name = def.name,
				line = view.goalText,
				frac = math.clamp(view.have / math.max(1, view.need), 0, 1),
				bar = `{Format.short(view.have)}/{Format.short(view.need)}`,
				button = { text = "LOCKED 🔒", look = "poor" },
				action = "none",
				owned = false,
				active = false,
			}
		end
		table.insert(rows, row)
	end
	return rows
end

export type PlayGiftRow = { slot: number, text: string, reward: string, button: Button, canClaim: boolean }
GiftPetView.PLAY_HEADER = "PLAY GIFTS"

-- Gifts for time played today. `age` = seconds since the view arrived (countdowns keep running).
function GiftPetView.playGiftRows(view: Types.PlayGiftView, age: number): { PlayGiftRow }
	local rows: { PlayGiftRow } = {}
	for _, g in view.gifts do
		local button: Button = if g.state == "claimed"
			then { text = "DONE", look = "done" }
			elseif g.state == "ready" or g.left - age <= 0 then { text = "CLAIM!", look = "buy" }
			else { text = EventText.giftWait(g.left - age), look = "poor" }
		table.insert(rows, {
			slot = g.slot,
			text = `Play {g.minutes} min`,
			reward = rewardText(g.cash, g.hats),
			button = button,
			canClaim = g.state ~= "claimed" and (g.state == "ready" or g.left - age <= 0),
		})
	end
	return rows
end

-- True when the tab's red dot should show.
function GiftPetView.dailyDot(view: DailyView?, play: Types.PlayGiftView?): boolean
	return (view ~= nil and view.claimable > 0) or (play ~= nil and play.claimable > 0)
end

-- Pet count, for sizing (kept here so Config changes need no client edit).
function GiftPetView.petCount(): number
	return #PetConfig.Pets
end

return GiftPetView
