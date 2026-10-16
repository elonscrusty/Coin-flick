--!strict
-- What the GIFTS and PETS shop tabs draw, as plain data (no Roblox objects), so
-- tests/specs/GiftPetView.spec.luau can check the words, bars and buttons offline.
-- The server decides every reward; these views only describe it.

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

-- "3h 20m", "20m 05s", "45s".
function GiftPetView.timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return `{s}s`
end

local function rewardText(cash: number, hats: number): string
	local text = PanelView.money(cash)
	if hats > 0 then
		text ..= ` +🎩{hats}`
	end
	return text
end

function GiftPetView.dailyRows(view: DailyView, now: number): DailyRows
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
	local timer = `New gifts in {GiftPetView.timeLeft(view.nextReset - now)}`
	local giftButton: Button = if gift.ready
		then { text = `GET DAY {gift.dayIndex} GIFT!`, look = "buy" }
		else { text = "GIFT TAKEN ✔", look = "owned" }
	local jobs: { JobRow } = {}
	for i, job in view.jobs do
		local button: Button = if job.claimed
			then { text = "DONE ✔", look = "owned" }
			elseif job.done then { text = "CLAIM!", look = "buy" }
			else { text = "NOT YET", look = "poor" }
		table.insert(jobs, {
			text = job.text,
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
				button = { text = "LOCKED 🔒", look = "locked" },
				action = "none",
				owned = false,
				active = false,
			}
		end
		table.insert(rows, row)
	end
	return rows
end

-- True when the tab's red dot should show.
function GiftPetView.dailyDot(view: DailyView?): boolean
	return view ~= nil and view.claimable > 0
end

-- Pet count, for sizing (kept here so Config changes need no client edit).
function GiftPetView.petCount(): number
	return #PetConfig.Pets
end

return GiftPetView
