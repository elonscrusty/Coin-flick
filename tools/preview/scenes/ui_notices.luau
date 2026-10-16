-- ui_notices: notifications never cover an open menu header (UI v2 leftover, docs/ui_v2/REPORT.md section 4).
-- Opens every primary menu from the HUD, fires three notifications (one wraps to two lines) and measures the
-- notification column against the menu's Header (title, cash, X) and, with --set dialog=1, against a purchase
-- confirmation over the Upgrades menu. Prints NOTICE-HEADER PASS / [FAIL] lines. Run it with --set uiscale=real
-- (scenes/lib/ctr.luau) so the rectangles read back are the ones a device draws at the game's UIScale.
--   --set menu=Shop|Collection|Party|Settings  only that menu, left open for the picture
--   --set count=1|2|3  notifications fired per menu (default 3)
local C = lib("ctr")
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 2600
	end,
})
C.settle(1)
local UI = preview.require(preview.clientFolder():FindFirstChild("ui"):FindFirstChild("UI"))

local function rect(g: GuiObject)
	local p, s = g.AbsolutePosition, g.AbsoluteSize
	return p.X, p.Y, p.X + s.X, p.Y + s.Y
end

local function overlaps(a: GuiObject, b: GuiObject): boolean
	local ax0, ay0, ax1, ay1 = rect(a)
	local bx0, by0, bx1, by1 = rect(b)
	return ax0 < bx1 - 1 and bx0 < ax1 - 1 and ay0 < by1 - 1 and by0 < ay1 - 1
end

local function notices(): { GuiObject }
	local out = {}
	for _, g in ipairs(preview.findGui(function(o)
		return o.Name == "Notice" and o.Parent ~= nil and o.Parent.Name == "Notices"
	end)) do
		table.insert(out, g)
	end
	return out
end

local count = tonumber(preview.args.count) or 3
local function fire()
	UI.notify("Basket full. Deposit your rocks at the station.", "warn")
	if count >= 2 then
		UI.notify("Bought and equipped the Steel Hammer!", "ok")
	end
	if count >= 3 then
		UI.notify("Invite sent to Ben. They have a little while to accept it before it runs out.", "info")
	end
	preview.advance(0.4)
end

local function panelOf(prefix: string): GuiObject?
	local hits = preview.findGui(function(o)
		return o.Name == "Panel" and o.Parent ~= nil and string.sub(o.Parent.Name, 1, #prefix) == prefix
	end)
	return hits[1]
end

local fails = 0
local checked = 0
local function check(label: string, protect: GuiObject?)
	local ns = notices()
	if not protect or #ns == 0 then
		fails += 1
		print(("[FAIL] NOTICE-HEADER %s: %s"):format(label, if protect then "no notices" else "nothing to protect"))
		return
	end
	checked += 1
	for _, n in ipairs(ns) do
		if overlaps(n, protect) then
			fails += 1
			local _, ny0, _, ny1 = rect(n)
			local _, hy0, _, hy1 = rect(protect)
			print(("[FAIL] NOTICE-HEADER %s: notice y %d..%d over %s y %d..%d"):format(label, ny0, ny1, protect.Name, hy0, hy1))
		end
	end
end

local menus = { { "^UPGRADES$", "Shop" }, { "^COLLECTION$", "Collection" }, { "^PARTY$", "Party" }, { "^SETTINGS$", "Settings" } }
local only = preview.args.menu
for _, m in ipairs(menus) do
	if only == nil or only == m[2] then
		C.tap(m[1])
		preview.advance(0.5)
		local panel = panelOf("Modal_")
		fire()
		check(m[2], panel and panel:FindFirstChild("Header") :: GuiObject?)
		if only == nil then
			UI.closeModal()
			UI.dismissNotices("")
			preview.advance(0.5)
		end
	end
end
if preview.args.dialog == "1" then
	C.tap("^UPGRADES$")
	preview.advance(0.5)
	local modal = panelOf("Modal_")
	UI.confirm({ Name = "Probe", Title = "Purchase this upgrade?", Message = "Steel Hammer. Cracks rocks faster.", Price = 600, Icon = "hammer" })
	preview.advance(0.3)
	fire()
	check("Shop header under dialog", modal and modal:FindFirstChild("Header") :: GuiObject?)
	check("Dialog", panelOf("Dialog_"))
end
-- SCALE: landscape phones keep the old formula (0.8..1.3); portrait phones scale by width (390 -> 1.0); big screens keep growing with the height (Roblox viewport
-- sizes below the 58 px top bar). Menu sizes on screen are the logical size times the scale.
local old = function(v: Vector2)
	return math.clamp(math.min(v.X / 800, v.Y / 400), 0.8, 1.3)
end
local cases = {
	{ "phone-small", Vector2.new(667, 317), nil },
	{ "phone", Vector2.new(750, 332), nil },
	{ "phone-1108", Vector2.new(1108, 454), nil },
	{ "phone-portrait", Vector2.new(390, 786), 1.0 },
	{ "portrait 430", Vector2.new(430, 874), 430 / 390 },
	{ "tablet", Vector2.new(1024, 690), nil },
	{ "laptop 1366x768", Vector2.new(1366, 710), 1.3 },
	{ "1080p", Vector2.new(1920, 1022), 1022 / 600 },
	{ "1440p", Vector2.new(2560, 1382), 1382 / 600 },
}
for _, c in ipairs(cases) do
	local got = UI.scaleFor(c[2])
	local want = c[3] or old(c[2])
	local logical = c[2] / got
	print(("SCALE %-16s %4dx%-4d scale %.2f (was %.2f) logical %dx%d"):format(c[1], c[2].X, c[2].Y, got, old(c[2]), logical.X, logical.Y))
	if math.abs(got - want) > 0.01 then
		fails += 1
		print(("[FAIL] SCALE %s %.3f, want %.3f"):format(c[1], got, want))
	end
end
if fails == 0 and checked > 0 then
	print(("NOTICE-HEADER PASS (%d menus / dialogs, notices clear of every header)"):format(checked))
else
	print(("NOTICE-HEADER FAIL: %d"):format(fails))
end
C.followCamera()
