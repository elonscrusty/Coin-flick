--!strict
-- The words for the HUD's event / gift / friend chip and the pop banners of the
-- play gifts, badges, goals and weekend events. Pure (the clock is passed in)
-- so Lune can check every string and that the chip text stays short.

local Types = require(script.Parent.Parent.Types)

type EventView = Types.EventView
type PlayGiftView = Types.PlayGiftView

local EventText = {}

EventText.NEAR_GIFT = 300 -- seconds: a gift this close to ready gets a countdown chip
EventText.CYCLE = 3 -- seconds each chip shows when several are active

export type Alert = { kind: string, text: string, tap: boolean }

-- "m:ss" under an hour, "Hh MMm" under a day, "Dd Hh" after that.
function EventText.span(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 3600 then
		return string.format("%d:%02d", s // 60, s % 60)
	elseif s < 86400 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	end
	return string.format("%dd %dh", s // 86400, (s % 86400) // 3600)
end

-- Rain beats weekend (it is the hotter news). Empty when no event.
function EventText.event(ev: EventView?, now: number): string
	if not ev then
		return ""
	end
	if ev.rain and ev.rainEndsAt > now then
		return `🌧 RAIN {ev.cashMult}x {EventText.span(ev.rainEndsAt - now)}`
	elseif ev.weekend and ev.endsAt > now then
		return `🍀 {ev.luckMult}x LUCK {EventText.span(ev.endsAt - now)}`
	end
	return ""
end

-- The one wording for "a gift is coming" (HUD chip, GIFTS tab buttons).
function EventText.giftWait(seconds: number): string
	return `Next gift {EventText.span(seconds)}`
end

-- Play gifts: how many can be taken now, else a countdown when one is close.
-- `age` is how many seconds old the view is (the countdown keeps running).
function EventText.gift(view: PlayGiftView?, age: number): (string, boolean)
	if not view then
		return "", false
	end
	if view.claimable > 0 then
		return `🎁 {view.claimable} READY!`, true
	end
	local nearest = math.huge
	for _, g in view.gifts do
		if g.state == "waiting" then
			nearest = math.min(nearest, g.left - age)
		end
	end
	if nearest <= 0 then
		return "🎁 READY!", true
	elseif nearest <= EventText.NEAR_GIFT then
		return EventText.giftWait(nearest), false
	end
	return "", false
end

-- Everything that wants the shared chip slot right now, most important first.
function EventText.alerts(ev: EventView?, gifts: PlayGiftView?, giftAge: number, friendMult: number?, now: number)
	local list: { Alert } = {}
	local giftText, giftTap = EventText.gift(gifts, giftAge)
	if giftText ~= "" and giftTap then
		table.insert(list, { kind = "gift", text = giftText, tap = true })
	end
	local eventText = EventText.event(ev, now)
	if eventText ~= "" then
		table.insert(list, { kind = "event", text = eventText, tap = false })
	end
	if friendMult then
		table.insert(list, { kind = "friend", text = `👫 {friendMult}x cash`, tap = false })
	end
	if giftText ~= "" and not giftTap then
		table.insert(list, { kind = "gift", text = giftText, tap = false })
	end
	return list
end

-- Which alert shows at second `tick` (they take turns when there are several).
function EventText.pick(list: { Alert }, tick: number): Alert?
	if #list == 0 then
		return nil
	end
	return list[(math.floor(tick / EventText.CYCLE) % #list) + 1]
end

-- The weekly board's reset timer for the THIS WEEK tab.
function EventText.weekReset(weekEndsAt: number, now: number): string
	if weekEndsAt <= now then
		return "Resets now!"
	end
	return `Resets in {EventText.span(weekEndsAt - now)}`
end

-- Pop banner for a Notice: title and one line. nil = not a banner kind.
function EventText.banner(kind: string, text: string): (string?, string?)
	if kind == "event" then
		local title = if string.find(text, "RAIN", 1, true) then "COIN RAIN!" else "WEEKEND!"
		local line = string.match(text, "^[%u ]+!%s*(.+)$") or text
		return title, line
	elseif kind == "playGift" then
		return "PLAY GIFT!", (string.gsub(text, "^Play gift!%s*", ""))
	elseif kind == "badge" then
		return "NEW BADGE!", (string.gsub(text, "^Badge:%s*", ""))
	end
	return nil, nil
end

return EventText
