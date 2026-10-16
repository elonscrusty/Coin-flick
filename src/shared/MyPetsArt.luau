--!strict
-- MY PETS low-poly frame pictures (carter's art pack, 2026-10-16). Files: art/ui/my_pets_lowpoly/<File>.png, cropped to
-- their visible pixels (W x H = the uploaded size). Inset = the clear opening inside each frame as shares of the
-- picture (left, top, right, bottom), measured from the alpha along the middle lines. Id 0 = not uploaded yet: the
-- panel keeps its drawn low-poly look. Preview: --set art=1 uses preview-only ids 1016000001..15 (art/artmap.json).
-- Frames are drawn as nine-slice pictures cut at the measured opening (slice), scaled so the border keeps the source
-- proportions (scaleFor); buttons are cut a little inside their bevelled ends (Cap). Tested in tests/test_my_pets.luau.

local MyPetsArt = {}

export type Piece = { Id: number, File: string, W: number, H: number, Inset: { number }? }

MyPetsArt.Pieces = {
	Main = { Id = 102450592636035, File = "main-panel-frame", W = 1024, H = 534, Inset = { 0.0781, 0.1067, 0.0791, 0.1348 } },
	Detail = { Id = 90800160593928, File = "detail-panel-frame", W = 659, H = 1024, Inset = { 0.1381, 0.0918, 0.1411, 0.0986 } },
	CardCommon = { Id = 127375042254219, File = "card-common", W = 512, H = 498, Inset = { 0.1348, 0.1727, 0.1367, 0.1566 } },
	CardUncommon = { Id = 108087286214024, File = "card-uncommon", W = 512, H = 504, Inset = { 0.1445, 0.1409, 0.1465, 0.1587 } },
	CardRare = { Id = 139298743910020, File = "card-rare", W = 512, H = 505, Inset = { 0.1562, 0.1505, 0.1582, 0.1564 } },
	CardEpic = { Id = 129474966464429, File = "card-epic", W = 512, H = 489, Inset = { 0.1426, 0.1329, 0.1445, 0.1472 } },
	CardLegendary = { Id = 124773211826038, File = "card-legendary", W = 512, H = 508, Inset = { 0.1445, 0.1417, 0.1484, 0.1634 } },
	CardVoid = { Id = 109768012411313, File = "card-void", W = 507, H = 512, Inset = { 0.1321, 0.1699, 0.1361, 0.1523 } },
	Selected = { Id = 134979085238480, File = "selected-card-overlay", W = 512, H = 492, Inset = { 0.1289, 0.1199, 0.1309, 0.124 } },
	Slot = { Id = 115512055450279, File = "team-slot-frame", W = 512, H = 493, Inset = { 0.1367, 0.1359, 0.1387, 0.1643 } },
	Lime = { Id = 79103791647785, File = "action-lime", W = 1024, H = 317 },
	Orange = { Id = 111821095370774, File = "action-orange", W = 1024, H = 283 },
	Blue = { Id = 82932321259022, File = "action-blue", W = 1024, H = 293 },
	Close = { Id = 88518206824559, File = "close-red", W = 512, H = 492 },
	Fav = { Id = 71518618550192, File = "favorite-gold", W = 512, H = 481 },
} :: { [string]: Piece }

-- the order the preview ids follow (1016000000 + index)
MyPetsArt.Order = { "Main", "Detail", "CardCommon", "CardUncommon", "CardRare", "CardEpic", "CardLegendary", "CardVoid", "Selected", "Slot", "Lime", "Orange", "Blue", "Close", "Fav" }

-- a button's bevelled ends: kept whole (shares of the picture height)
MyPetsArt.Cap = { X = 0.45, Y = 0.34 }

local CARD = { Common = "CardCommon", Uncommon = "CardUncommon", Rare = "CardRare", Epic = "CardEpic", Legendary = "CardLegendary" }

-- the card frame for a rarity (VOID species use the void frame); unknown rarities fall back to Common
function MyPetsArt.cardKey(rarity: string?, void: boolean?): string
	if void then
		return "CardVoid"
	end
	return CARD[rarity or ""] or "CardCommon"
end

-- the piece when its picture is uploaded, else nil (draw the fallback)
function MyPetsArt.get(name: string): Piece?
	local p = MyPetsArt.Pieces[name]
	if p and p.Id > 0 then
		return p
	end
	return nil
end

function MyPetsArt.ready(): boolean
	for _, n in MyPetsArt.Order do
		if MyPetsArt.Pieces[n].Id <= 0 then
			return false
		end
	end
	return true
end

-- nine-slice centre (picture pixels): a frame is cut at its opening, a button just inside its bevelled ends
function MyPetsArt.slice(p: Piece): (number, number, number, number)
	local i = p.Inset
	if i then
		return math.floor(i[1] * p.W), math.floor(i[2] * p.H), math.ceil(p.W - i[3] * p.W), math.ceil(p.H - i[4] * p.H)
	end
	local cx, cy = math.floor(MyPetsArt.Cap.X * p.H), math.floor(MyPetsArt.Cap.Y * p.H)
	return cx, cy, p.W - cx, p.H - cy
end

-- SliceScale that draws the piece's left border `border` px wide (frames) or its whole height `border` px (buttons)
function MyPetsArt.scaleFor(p: Piece, border: number): number
	local i = p.Inset
	local src = if i then i[1] * p.W else p.H
	return border / math.max(src, 1)
end

-- the clear opening of a piece drawn in a w x h box with slice scale k: (left, top, right, bottom) in px
function MyPetsArt.opening(p: Piece, k: number): (number, number, number, number)
	local x0, y0, x1, y1 = MyPetsArt.slice(p)
	return x0 * k, y0 * k, (p.W - x1) * k, (p.H - y1) * k
end

return MyPetsArt
