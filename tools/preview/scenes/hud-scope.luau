-- hud-scope: HUD scope across a hunt and the return to the lobby (brief V7 section 10). Starts a solo hunt,
-- shows an arena guidance toast ("Basket full..."), returns to the lobby through the real MatchAction and
-- checks that nothing arena-only survives: no Table x / 10 card (full or mini), no Carry Basket card, no
-- guidance toast, no guide arrow chip, no action button. Then starts a second hunt and checks the HUD binds
-- again. Prints HUD-SCOPE PASS or [FAIL] lines.
local C = lib("ctr")
C.boot({
	profile = function(data)
		data.Cash = 640
		data.TutorialStep = 1
		data.Onboard.Skipped = true
	end,
})
local w = C.watchMatch()

local function shown(obj): boolean
	local o = obj
	while o do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		if o:IsA("ScreenGui") and not o.Enabled then
			return false
		end
		o = o.Parent
	end
	return true
end

local function visibleNamed(name: string)
	local hits = preview.findGui(function(obj)
		return obj.Name == name and shown(obj)
	end)
	return hits[1]
end

local function toastTexts(pattern: string)
	local n = 0
	for _, g in ipairs(preview.findGui(function(obj)
		local ok, text = pcall(function()
			return obj.Text
		end)
		return ok and type(text) == "string" and string.find(text, pattern) ~= nil and shown(obj)
	end)) do
		n += 1
		local _ = g
	end
	return n
end

local fails = 0
local function check(label: string, ok: boolean)
	if ok then
		print("[ok] " .. label)
	else
		fails += 1
		print("[FAIL] " .. label)
	end
end

C.startSolo(w)
C.waitPhase(w, "Searching", 6)
preview.advance(1)
check("hunt: carry card shown", visibleNamed("CarryCard") ~= nil)

-- an arena guidance toast, then a normal notice that must survive
preview.fireClient("Toast", "Basket full: take rocks to your table", "info")
preview.fireClient("Toast", "Saved your settings", "ok")
preview.advance(0.2)
check("toast shown during hunt", toastTexts("Basket full") > 0)

C.fireServer("MatchAction", "Return")
preview.advance(2)
check("lobby: Table card hidden", visibleNamed("TableQueue") == nil)
check("lobby: mini table summary hidden", C.findText("^TABLE  %d") == nil or not shown(C.findText("^TABLE  %d")))
check("lobby: carry basket card hidden", visibleNamed("CarryCard") == nil)
check("lobby: arena toast dismissed", toastTexts("Basket full") == 0)
check("lobby: no guide arrow chip", toastTexts("^TABLE$") == 0 and toastTexts("^PILE$") == 0)
check("lobby: action button hidden", visibleNamed("PrimaryAction") == nil)

-- second hunt binds again
local w2 = C.watchMatch()
C.startSolo(w2)
C.waitPhase(w2, "Searching", 6)
preview.advance(1)
check("second hunt: carry card back", visibleNamed("CarryCard") ~= nil)
C.fireServer("MatchAction", "Return")
preview.advance(2)
check("second return: Table card hidden", visibleNamed("TableQueue") == nil)

if fails == 0 then
	print("HUD-SCOPE PASS")
else
	print("[FAIL] HUD-SCOPE " .. fails .. " check(s) failed")
end
