--!strict
-- "Polygon Adventure" UI kit (Blender-rendered PNGs, owner uploads 2026-10-14): one entry per picture,
-- name -> { Id, SliceCenter, Size }. The ids came from the owner's Studio uploads; an entry set back to
-- rbxassetid://0 makes that piece fall back to its drawn look. The shared UI helpers draw these as ImageLabels
-- (client/ui/UI.kitSkin, called from UI.button's paint, UI.modal, UI.tabs, UI.specimenCard, UI.catalogRow,
-- UI.cash, UI.bar, UI.closeButton, UI.newDot and UI.icon "cash"). Pure data and decisions, tested offline
-- (tests/test_ui_kit.luau).
--
-- The PNGs are 2x: Pixels is the uploaded picture's size, Size the 1x size (half). SliceCenter is in the picture's
-- own (2x) pixels from the kit's slices.json margins: Rect(L, T, W - R, H - B). SliceScale 0.5 draws the corners at 1x;
-- a piece smaller than its corners scales them down further (UiKit.sliceScale).

local UiKit = {}

-- Lip: extra bottom margin (2x px) a panel picture has under its rim (the 3D lip). Panels crop it off (ImageRect) so the
-- visible border is the same on all four sides (Studio check 2026-10-14: the Pet Book rim read thicker at the bottom).
-- MaxStretch: how far the element's aspect may stray from the picture's before the picture no longer fits (a portrait
-- card stretched into a wide bar drew a thick stretched stripe on the Upgrades rows); nil = any shape.
export type Entry = { Id: string, Pixels: Vector2, Size: Vector2, SliceCenter: Rect, Slice: boolean, Lip: number?, MaxStretch: number? }

-- A 9-slice piece: `w` x `h` (2x px), margins left / right / top / bottom in those pixels.
local function sliced(id: string, w: number, h: number, l: number, r: number, t: number, b: number): Entry
	return { Id = "rbxassetid://" .. id, Pixels = Vector2.new(w, h), Size = Vector2.new(w / 2, h / 2), SliceCenter = Rect.new(l, t, w - r, h - b), Slice = true }
end

-- A plain picture drawn whole (ScaleType Fit): icons, the badge dot, the close X.
local function plain(id: string, s: number): Entry
	return { Id = "rbxassetid://" .. id, Pixels = Vector2.new(s, s), Size = Vector2.new(s / 2, s / 2), SliceCenter = Rect.new(0, 0, s, s), Slice = false }
end

local function button(id: string): Entry
	return sliced(id, 271, 120, 47, 47, 35, 50)
end

local function rarity(id: string): Entry
	local e = sliced(id, 182, 188, 49, 49, 49, 56)
	e.MaxStretch = 3
	return e
end

-- A card picture (portrait): fits tiles, not wide bars.
local function card(id: string): Entry
	local e = sliced(id, 207, 266, 54, 54, 54, 61)
	e.MaxStretch = 3
	return e
end

-- A panel picture: its bottom lip is cropped so the rim is even (UiKit.crop).
local function panel(id: string, w: number, h: number): Entry
	local e = sliced(id, w, h, 84, 84, 84, 95)
	e.Lip = 95 - 84
	return e
end

local function icon(id: string): Entry
	return plain(id, 143)
end

UiKit.Entries = {
	button_blue = button("72697145353714"),
	button_blue_pressed = button("88459868316412"),
	button_coral = button("108639924673709"),
	button_coral_pressed = button("88633559143079"),
	button_green = button("85239779404293"),
	button_green_pressed = button("133919821267056"),
	button_yellow = button("131017167474107"),
	button_yellow_pressed = button("94666526187739"),
	panel_large = panel("123952033373409", 527, 410),
	panel_small = panel("76810626105109", 335, 256),
	card = card("123706165003345"),
	card_selected = card("98615042784008"),
	tab = sliced("75926104892358", 207, 99, 40, 40, 40, 14),
	tab_active = sliced("118884930792992", 207, 99, 40, 40, 40, 14),
	close_x = plain("102591340029020", 99),
	coin_pill = sliced("76218890033810", 246, 86, 84, 46, 36, 40),
	badge_dot = plain("135033080755062", 79),
	progress_bg = sliced("137735681037240", 399, 67, 36, 36, 33, 33),
	progress_fill = sliced("123400596244425", 399, 67, 36, 36, 33, 33),
	rarity_common = rarity("100541606021995"),
	rarity_uncommon = rarity("77702245224588"),
	rarity_rare = rarity("127616220113092"),
	rarity_epic = rarity("86734803035763"),
	rarity_legendary = rarity("136045809594401"),
	rarity_void = rarity("130434968960886"),
	icon_bolt = icon("123065655189615"),
	icon_coin = icon("78474630929064"),
	icon_egg = icon("138774715991522"),
	icon_gem = icon("140222387178177"),
	icon_heart = icon("79588751757651"),
	icon_paw = icon("108005474157839"),
	icon_star = icon("107664581924134"),
	icon_sword = icon("99463779099896"),
} :: { [string]: Entry }

-- UI.button styles -> kit button: gold (primary) yellow, green green, red (destructive) coral, blue (HUD tiles) blue.
-- gray (secondary: filters, sort, FAV, locked rewards) has no kit picture on purpose: it is drawn flat and
-- desaturated so it never reads like a primary button (Studio check 2026-10-14). A disabled button keeps its
-- picture, tinted grey (UI.kitSkin).
UiKit.ButtonFor = { gold = "button_yellow", green = "button_green", red = "button_coral", blue = "button_blue" } :: { [string]: string }

-- Pet rarity -> card frame (the rarest tiers share the void frame).
UiKit.RarityFor = {
	Common = "rarity_common", Uncommon = "rarity_uncommon", Rare = "rarity_rare", Epic = "rarity_epic",
	Legendary = "rarity_legendary", Mythic = "rarity_void", Secret = "rarity_void", Void = "rarity_void",
} :: { [string]: string }

-- True once the picture has a real (non-zero) asset id.
function UiKit.hasId(id: string?): boolean
	if type(id) ~= "string" or id == "" then
		return false
	end
	local n = string.match(id, "%d+")
	return n ~= nil and tonumber(n) ~= 0
end

export type Skin = { Image: string, SliceCenter: Rect, Pixels: Vector2, Size: Vector2, ScaleType: string, Pressed: string?, Lip: number?, MaxStretch: number? }

-- What `name` should draw: nil while its id is 0 (the caller keeps its drawn look), else the image, the slice
-- centre, the picture sizes, "Slice" (or "Fit" for plain pictures) and the pressed picture when that one has an id.
function UiKit.skinFor(name: string?, entries: { [string]: Entry }?): Skin?
	if type(name) ~= "string" then
		return nil
	end
	local t = entries or UiKit.Entries
	local e = t[name]
	if not e or not UiKit.hasId(e.Id) then
		return nil
	end
	local p = t[name .. "_pressed"]
	return {
		Image = e.Id,
		SliceCenter = e.SliceCenter,
		Pixels = e.Pixels,
		Size = e.Size,
		ScaleType = if e.Slice then "Slice" else "Fit",
		Pressed = if p and UiKit.hasId(p.Id) then p.Id else nil,
		Lip = e.Lip,
		MaxStretch = e.MaxStretch,
	}
end

-- The kit key for a UI.button style (nil: keep the drawn button).
function UiKit.buttonKey(style: string?): string?
	return UiKit.ButtonFor[style or ""]
end

-- The card key for a pet card: the selected frame wins, then the rarity frame, else the plain card.
function UiKit.cardKey(selected: boolean?, rarityName: string?): string
	if selected then
		return "card_selected"
	end
	return UiKit.RarityFor[rarityName or ""] or "card"
end

-- Corner margins (L, T, R, B) of a sliced picture, in its own pixels.
function UiKit.margins(skin: Skin): (number, number, number, number)
	local c = skin.SliceCenter
	return c.Min.X, c.Min.Y, skin.Pixels.X - c.Max.X, skin.Pixels.Y - c.Max.Y
end

-- SliceScale for a piece drawn `w` x `h` (logical px): 0.5 draws the 2x corners at 1x; a piece smaller than its
-- corners scales them down so opposite corners never overlap.
function UiKit.sliceScale(skin: Skin, w: number, h: number): number
	local l, t, r, b = UiKit.margins(skin)
	local s = 0.5
	if w > 0 and l + r > 0 then
		s = math.min(s, w / (l + r))
	end
	if h > 0 and t + b > 0 then
		s = math.min(s, h / (t + b))
	end
	return math.max(s, 0.01)
end

-- The part of a picture to draw (ImageRectSize) and its slice centre inside that part: a panel's bottom lip is cropped
-- off, so its four rim margins come out equal (L, T, R and B = T). Other pictures are drawn whole.
function UiKit.crop(skin: Skin): (Vector2, Rect)
	local lip = skin.Lip or 0
	if lip <= 0 or skin.ScaleType ~= "Slice" then
		return skin.Pixels, skin.SliceCenter
	end
	local l, t, r, _ = UiKit.margins(skin)
	local size = Vector2.new(skin.Pixels.X, skin.Pixels.Y - lip)
	return size, Rect.new(l, t, size.X - r, size.Y - t)
end

-- Rim margins (L, T, R, B) as drawn, after the crop.
function UiKit.drawnMargins(skin: Skin): (number, number, number, number)
	local size, c = UiKit.crop(skin)
	return c.Min.X, c.Min.Y, size.X - c.Max.X, size.Y - c.Max.Y
end

-- SliceScale for a piece drawn `w` x `h` (logical px, measured after layout), with the cropped margins:
-- min(cap, h / (T + B), w / (L + R)), so opposite corners never overlap and a corner is never stretched.
-- `cap` defaults to 0.5 (the 2x corners at 1x).
function UiKit.fitScale(skin: Skin, w: number, h: number, cap: number?): number
	local l, t, r, b = UiKit.drawnMargins(skin)
	local s = cap or 0.5
	if w > 0 and l + r > 0 then
		s = math.min(s, w / (l + r))
	end
	if h > 0 and t + b > 0 then
		s = math.min(s, h / (t + b))
	end
	return math.max(s, 0.01)
end

-- Whether a sliced picture suits an element `w` x `h`: a piece with MaxStretch only when the element's aspect is
-- within that factor of the picture's (a portrait card is not drawn as a wide bar); unknown sizes fit.
function UiKit.fits(skin: Skin, w: number, h: number): boolean
	local m = skin.MaxStretch
	if not m or w <= 0 or h <= 0 or skin.ScaleType ~= "Slice" then
		return true
	end
	local want = (w / h) / (skin.Pixels.X / skin.Pixels.Y)
	return want <= m and want >= 1 / m
end

-- Corner cap for a menu panel on a screen `logicalH` tall: 1x corners (0.5) from 450 logical px up, down to 0.35 at
-- 390 and below (landscape phones are 315-400 logical tall), so the rim does not eat the content.
function UiKit.panelCap(logicalH: number): number
	return math.clamp(0.35 + (logicalH - 390) / (450 - 390) * 0.15, 0.35, 0.5)
end

-- Share of a rim margin that is the visible frame; the rest is the soft inner edge the content may sit on.
UiKit.RIM_SHARE = 0.6

-- Inner content rect of a panel picture drawn at SliceScale `scale`: insets (L, T, R, B) in logical px. Header, tabs,
-- body and footer all sit inside it, so they line up with the picture and with each other.
-- Top offset (inside the KitPad padding) of a kit panel's solid fill: the content pad `padTop` and the rim's own
-- inset `rimTop` differ only when the header sits on the rim (padTop 0); the fill then still starts under the rim.
function UiKit.backingTop(padTop: number, rimTop: number): number
	return math.max(rimTop - padTop, 0)
end

function UiKit.contentInset(skin: Skin, scale: number): (number, number, number, number)
	local l, t, r, b = UiKit.drawnMargins(skin)
	local k = scale * UiKit.RIM_SHARE
	return math.floor(l * k), math.floor(t * k), math.floor(r * k), math.floor(b * k)
end

-- Text floor (Studio check 2026-10-14: small white words on pale kit buttons were unreadable). Every fitted label is
-- designed at MinText or more and never shrinks below it; light words over colour carry an outline of at least
-- LightOutline px.
UiKit.MinText = 14
UiKit.LightOutline = 2

-- The floor is also kept in REAL pixels: every layer has a UIScale, so a 14 logical px label is 8 real px at scale 0.6
-- (Studio check 1434 x 658). RealMinText is the smallest text, in screen px, that is allowed to show.
UiKit.RealMinText = 12
UiKit.MaxFloorText = 28 -- the real-pixel floor never asks for more than this many logical px (very small scales)

-- Smallest logical text size that draws at least RealMinText real px at UIScale `scale` (never below MinText).
function UiKit.floorFor(scale: number?): number
	local k = math.max(scale or 1, 0.1)
	return math.min(math.max(UiKit.MinText, math.ceil(UiKit.RealMinText / k - 1e-6)), UiKit.MaxFloorText)
end

-- (MaxTextSize, MinTextSize) for a label designed at `size` that may shrink to `minSize`, with the floor applied.
-- With `scale` (the current UIScale) the floor is the real-pixel one: the minimum is max(MinText, ceil(12 / scale)),
-- and the maximum is lifted to meet it so the label can always reach the floor.
function UiKit.textRange(size: number, minSize: number?, scale: number?): (number, number)
	local hi = math.max(math.floor(size), UiKit.MinText)
	local lo = math.clamp(math.floor(minSize or UiKit.MinText), UiKit.MinText, hi)
	if scale then
		lo = math.max(lo, UiKit.floorFor(scale))
		hi = math.max(hi, lo)
	end
	return hi, lo
end

-- True for light text (white, cream, pale yellow / green / blue): relative luminance above 0.5.
function UiKit.isLight(c: Color3): boolean
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B > 0.5
end

-- Outline thickness for a label in colour `c` designed with `thick` (nil or 0: none): light text gets at least
-- LightOutline px of dark outline; dark text keeps what it was designed with.
function UiKit.outlineFor(c: Color3, thick: number?): number
	local t = thick or 0
	if UiKit.isLight(c) then
		return math.max(t, UiKit.LightOutline)
	end
	return t
end

-- Top offset (logical px) that keeps a modal's header inside the safe area. `insetY` is GuiService:GetGuiInset().Y in
-- real px, counted only when the layer ignores the inset (else the layer already starts below the top bar);
-- `overhang` is how far the header (the title tab) sticks out above the panel's top edge; `margin` a clear gap.
UiKit.SafeTopMargin = 8 -- the clear gap modals pass as `margin` (was 2; Studio 1434 x 658 cleared the top bar only barely)

function UiKit.safeTop(insetY: number, ignoresInset: boolean, scale: number, overhang: number, margin: number): number
	local top = if ignoresInset then insetY / math.max(scale, 0.01) else 0
	return math.ceil(top + math.max(overhang, 0) + margin)
end

-- How much to shorten a scroll window `window` px tall so it ends on a whole row: `bottoms` are the rows' bottom
-- edges (px from the window's top at scroll 0, any order). Returns 0 when everything fits, when no row ends inside
-- the window, or when the cut would take more than `maxShare` (default 0.35) of the window.
-- `heights` (optional, same order as `bottoms`): a row that crosses the window edge with half or more of it in view
-- is kept, not cut away (a tall quest card cut to nothing left a void under the heading, Studio check 2026-10-15).
function UiKit.snapCut(bottoms: { number }, window: number, maxShare: number?, heights: { number }?): number
	local last, best = 0, -1
	for i, b in bottoms do
		last = math.max(last, b)
		if b <= window and b > best then
			best = b
		end
		if heights and b > window then
			local h = heights[i] or 0
			if h > 0 and (window - (b - h)) / h >= 0.5 then
				return 0
			end
		end
	end
	if last <= window or best <= 0 then
		return 0
	end
	local cut = window - best
	if cut > window * (maxShare or 0.35) then
		return 0
	end
	return math.floor(cut)
end

return UiKit
