--!strict
-- The one popup gate on the client (rule: shared/PopupRules). Fight views hold it (`PopupGate.hold("Fight", true)`
-- from FightCam's start to its stop); the player's InBattle / InTower / MatchKey attributes and State.Match count too.
-- Anything that pops a non-fight card or toast asks `PopupGate.free(kind)` or hands it to `PopupGate.later(kind, fn)`,
-- which runs it now when free, else in order once the fight is over (after PopupRules.Breath seconds).
-- `PopupGate.Changed` fires whenever the answer may have changed (a toast queue can flush on it).

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PopupRules = require(Shared.PopupRules)
local State = require(script.Parent.State)

local PopupGate = {}

PopupGate.Changed = Instance.new("BindableEvent")

-- set by ui/UI (which needs this module, so not the other way round): a menu or a big card is on screen
PopupGate.onScreen = nil :: (() -> boolean)?

local holds: { [string]: boolean? } = {}
local waiting: { { Kind: string, Fn: () -> () } } = {}
local draining = false

local function busy(): PopupRules.Busy
	local p = Players.LocalPlayer
	return {
		MatchKey = p and p:GetAttribute("MatchKey"),
		InTower = p and p:GetAttribute("InTower"),
		InBattle = p and p:GetAttribute("InBattle"),
		Match = State.Match,
		Held = next(holds) ~= nil,
		Shown = PopupGate.onScreen ~= nil and PopupGate.onScreen() or nil,
	}
end

function PopupGate.free(kind: string): boolean
	return PopupRules.free(kind, busy())
end

function PopupGate.cardStays(shownFor: number): boolean
	return PopupRules.cardStays(shownFor, busy())
end

function PopupGate.fighting(): boolean
	return PopupRules.fighting(busy())
end

local function drain()
	if draining or #waiting == 0 then
		return
	end
	draining = true
	task.delay(PopupRules.Breath, function()
		draining = false
		local i = 1
		while i <= #waiting do
			local w = waiting[i]
			if PopupRules.free(w.Kind, busy()) then
				table.remove(waiting, i)
				task.spawn(w.Fn)
			else
				i += 1
			end
		end
		-- a card still waits for a menu or another card to close (no single signal for that): look again soon
		if #waiting > 0 and not PopupGate.fighting() then
			drain()
		end
	end)
end

local function changed()
	PopupGate.Changed:Fire(PopupGate.fighting())
	if #waiting > 0 and not PopupGate.fighting() then
		drain()
	end
end

-- Holds (on) or releases (off) every non-fight popup under `key` (e.g. "Fight").
function PopupGate.hold(key: string, on: boolean)
	if (holds[key] == true) == on then
		return
	end
	holds[key] = if on then true else nil
	changed()
end

-- Runs `fn` now if a `kind` popup may show, else once it may (in the order asked).
function PopupGate.later(kind: string, fn: () -> ())
	if PopupGate.free(kind) and #waiting == 0 then
		fn()
		return
	end
	table.insert(waiting, { Kind = kind, Fn = fn })
	drain()
end

do
	local p = Players.LocalPlayer
	if p then
		for _, a in { "MatchKey", "InTower", "InBattle" } do
			p:GetAttributeChangedSignal(a):Connect(changed)
		end
	end
	State.Changed.Event:Connect(function(what)
		if what == "Match" then
			changed()
		end
	end)
end

return PopupGate
