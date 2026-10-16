--!strict
-- Lobby HUD art (owner mockup 2026-10-12, docs: /mnt/project-files/reference/ui/lobby_hud_mockup.png).
-- One table of picture slots for the HUD buttons. Each slot starts with id 0 and draws a stand-in: the procedural
-- UI.icon when one exists, else an emoji. To use the owner's pictures, upload each PNG in Studio and paste its id
-- into Image below (REPLACE markers). Each slot names its picture in /mnt/project-files/reference/ui/icons/.
-- Nothing else needs to change.
-- Also: HudArt.bigButton, the chunky left-column button (picture, bubble title, small caption pill).

local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)

local T = UI.T
local TC = Theme.Color
local HudArt = {}

export type Slot = { Image: string, Icon: string?, Emoji: string, Badge: string? }

HudArt.Slots = {
	-- plain coin (owner upload 2026-10-13); the old icons/coin.png (74874264229011) had a paw on its face
	Coin = { Image = "rbxassetid://115219544717046", Icon = "cash", Emoji = "\u{1FA99}" },
	Egg = { Image = "rbxassetid://103668102240419", Icon = "egg", Emoji = "\u{1F95A}" }, -- icons/egg.png, spotted egg (PLAY)
	Tower = { Image = "rbxassetid://99375195419423", Icon = nil, Emoji = "\u{1F3F0}" }, -- icons/tower.png, castle tower (TOWER)
	Calendar = { Image = "rbxassetid://120813968101346", Icon = "calendar", Emoji = "\u{1F4C5}" }, -- icons/calendar.png (DAILY)
	Paw = { Image = "rbxassetid://95216121363258", Icon = nil, Emoji = "\u{1F43E}" }, -- icons/paw.png (My Pets)
	-- the UPGRADE tile: a pet collar (owner upload 2026-10-14, IMPORT_NOW/icon_upgrade.png) with a small green up-arrow
	-- badge so it reads as "upgrade"; the old icons/hammer.png (98508674379928) was a mining tool
	Hammer = { Image = "rbxassetid://102877925830559", Icon = "boostLuck", Emoji = "\u{2B06}\u{FE0F}", Badge = "up" },
	Party = { Image = "rbxassetid://119307883183320", Icon = "party", Emoji = "\u{1F465}" }, -- icons/party.png, party people (Party)
	Gear = { Image = "rbxassetid://120609709962908", Icon = "gear", Emoji = "\u{2699}\u{FE0F}" }, -- icons/gear.png (Settings)
	Camera = { Image = "rbxassetid://95284429074133", Icon = "camera", Emoji = "\u{1F4F7}" }, -- icons/camera.png (photo button)
	-- The logo picture should carry the "One egg hides a rare pet!" line itself; the text stand-in draws both.
	-- Low-poly button icons (polish #72, rendered from the game's own models): for buttons that only had words
	IconPlay = { Image = "rbxassetid://123009599855834", Icon = "egg", Emoji = "\u{1F95A}" }, -- Icon_Play
	IconDaily = { Image = "rbxassetid://115944751580313", Icon = "calendar", Emoji = "\u{1F381}" }, -- Icon_Daily (gift)
	IconTower = { Image = "rbxassetid://89508066417725", Icon = nil, Emoji = "\u{1F3F0}" }, -- Icon_Tower
	IconPets = { Image = "rbxassetid://71060132379263", Icon = nil, Emoji = "\u{1F43E}" }, -- Icon_Pets (paw)
	-- REPLACE: Icon_PetBook. The upload 86197129278145 showed as a plain blue square in Studio (Book tab and the
	-- PET BOOK header), so the drawn book stands in until a working id for icons/Icon_PetBook is pasted here
	IconPetBook = { Image = "rbxassetid://0", Icon = "book", Emoji = "\u{1F4D8}" },
	IconShop = { Image = "rbxassetid://104340058683648", Icon = "cash", Emoji = "\u{1FA99}" }, -- Icon_Shop (coin)
	IconSettings = { Image = "rbxassetid://83896590237238", Icon = "gear", Emoji = "\u{2699}\u{FE0F}" }, -- Icon_Settings
	IconLeaderboard = { Image = "rbxassetid://108477862918584", Icon = nil, Emoji = "\u{1F3C6}" }, -- Icon_Leaderboard
	-- Pet Book zone tabs (polish #66, low-poly renders); keyed by zone name. All = the Pets paw, Tower = the tower.
	TabAll = { Image = "rbxassetid://71060132379263", Icon = nil, Emoji = "\u{1F43E}" }, -- Tab_All
	TabMeadow = { Image = "rbxassetid://73889450063316", Icon = nil, Emoji = "\u{1F33C}" }, -- Tab_Meadow
	TabForest = { Image = "rbxassetid://77721269403352", Icon = nil, Emoji = "\u{1F332}" }, -- Tab_Forest
	TabSnow = { Image = "rbxassetid://105292673580149", Icon = nil, Emoji = "\u{2744}\u{FE0F}" }, -- Tab_Snow
	TabVolcano = { Image = "rbxassetid://95614141244341", Icon = nil, Emoji = "\u{1F30B}" }, -- Tab_Volcano
	TabSpace = { Image = "rbxassetid://70553344841939", Icon = nil, Emoji = "\u{1FA90}" }, -- Tab_Space
	TabTower = { Image = "rbxassetid://89508066417725", Icon = nil, Emoji = "\u{1F3F0}" }, -- Tab_Tower (no Tower section in the Book yet)
	TabFavorites = { Image = "rbxassetid://101374665155273", Icon = nil, Emoji = "\u{2B50}" }, -- Tab_Favorites (FAVS filter)
	-- SETTINGS row icons (reference/ui/settings/); Camera Sensitivity reuses Camera above
	Music = { Image = "rbxassetid://97371583022210", Icon = "music", Emoji = "\u{1F3B5}" }, -- settings/icon_music.png
	Sound = { Image = "rbxassetid://105745506130146", Icon = "speaker", Emoji = "\u{1F50A}" }, -- settings/icon_sound.png
	Motion = { Image = "rbxassetid://91756220886385", Icon = "motion", Emoji = "\u{1F6B6}" }, -- settings/icon_reduce_motion.png
	Sparkle = { Image = "rbxassetid://102842945119030", Icon = "sparkle", Emoji = "\u{2728}" }, -- settings/icon_low_effects.png
	Bulb = { Image = "rbxassetid://140183110000190", Icon = "hint", Emoji = "\u{1F4A1}" }, -- settings/icon_hints.png
	Info = { Image = "rbxassetid://100408466405157", Icon = "info", Emoji = "\u{2139}\u{FE0F}" }, -- settings/icon_info.png
	-- START HUNT pieces (reference/ui/start_hunt/)
	EggPink = { Image = "rbxassetid://96034035112982", Icon = "egg", Emoji = "\u{1F95A}" }, -- start_hunt/egg_pink.png (solo card, tab)
	CheckGreen = { Image = "rbxassetid://111089747987064", Icon = nil, Emoji = "\u{2705}" }, -- start_hunt/check_green.png (success toast)
	Logo = { Image = "rbxassetid://0", Icon = nil, Emoji = "" }, -- REPLACE: icons/logo.png, FIND THE PET logo (wide, about 3:1)
} :: { [string]: Slot }

-- Button backgrounds (owner pictures, 2026-10-12), drawn as 9-slice ImageLabels so they stretch to any width. Rect is
-- the picture's opaque area in UPLOADED pixels (Roblox shrinks uploads to 1024 on the long side: the 1983 px wide
-- PNGs are stored 1024 wide, the 1254 px square one 1024), Inset the corner size kept unstretched.
-- While Image is id 0 the button keeps its drawn look (UI.button fill, outline, gloss).
export type Skin = { Image: string, Rect: { number }, Inset: number }

HudArt.Buttons = {
	btn_yellow = { Image = "rbxassetid://85287297082386", Rect = { 25, 66, 973, 275 }, Inset = 103 }, -- icons/btn_yellow.png (PLAY)
	btn_green = { Image = "rbxassetid://138290207229363", Rect = { 25, 48, 973, 306 }, Inset = 114 }, -- icons/btn_green.png (TOWER)
	btn_blue = { Image = "rbxassetid://71058843862567", Rect = { 22, 49, 981, 303 }, Inset = 103 }, -- icons/btn_blue.png (DAILY)
	btn_square_blue = { Image = "rbxassetid://122888270350671", Rect = { 56, 82, 908, 870 }, Inset = 229 }, -- icons/btn_square_blue.png (right tiles)
	coin_pill = { Image = "rbxassetid://89951108537678", Rect = { 20, 48, 983, 262 }, Inset = 136 }, -- icons/coin_pill.png (coin counter)
	-- DAILY panel pieces (reference/ui/daily/, owner 2026-10-12; rects in stored pixels, 1024 on the long side)
	tile_blue = { Image = "rbxassetid://91872036085012", Rect = { 101, 85, 618, 859 }, Inset = 110 }, -- daily/tile_blue.png (day tile)
	tile_gold = { Image = "rbxassetid://81935709573093", Rect = { 88, 83, 644, 866 }, Inset = 110 }, -- daily/tile_gold.png (today)
	tile_cream = { Image = "rbxassetid://109847489698973", Rect = { 90, 93, 640, 843 }, Inset = 110 }, -- daily/tile_cream.png (day 7)
	btn_grey = { Image = "rbxassetid://125874583720932", Rect = { 48, 58, 928, 264 }, Inset = 110 }, -- daily/btn_grey.png (not ready)
	btn_close_x = { Image = "rbxassetid://140480545375801", Rect = { 105, 114, 814, 795 }, Inset = 397 }, -- daily/btn_close_x.png (square, X stays sharp)
	bar_track = { Image = "rbxassetid://89803827523657", Rect = { 36, 134, 952, 73 }, Inset = 36 }, -- daily/bar_track.png
	bar_fill = { Image = "rbxassetid://105957798330697", Rect = { 31, 129, 962, 83 }, Inset = 41 }, -- daily/bar_fill.png
	-- OPEN has its word baked in, so it is drawn whole (ScaleType Fit), not sliced; QuestPanel adds the amount beside it
	btn_open = { Image = "rbxassetid://101506495443942", Rect = { 45, 34, 933, 371 }, Inset = 185 }, -- daily/btn_open.png
	-- Panel / hunt pieces still to be drawn by the owner (2026-10-13); the code already asks for these names:
	-- panel_bg, panel_tab (PanelSkin), settings_row (SETTINGS rows), hunt_card (START HUNT cards),
	-- hud_card (hunt timer / CARRIED / SHELLS cards), slot_blue (hunt hotbar slot). Add each here with its stored-pixel
	-- Rect and Inset once uploaded; until then they are drawn.
} :: { [string]: Skin }

local function hasId(image: string): boolean
	return image ~= "" and (string.match(image, "%d+") or "0") ~= "0"
end

-- Puts a button picture behind `b` (a UI.button, or a plain frame) once its id is set; the drawn fill, outline and
-- gloss step aside. The corners scale with the height (`height`, else b's offset height) so they keep the picture's
-- shape; the middle stretches sideways. A pill's rounded ends take the whole height, so the inset stops at the middle.
function HudArt.skin(b: GuiObject, key: string, height: number?): boolean
	local k = HudArt.Buttons[key]
	if Theme.PetStyle or not k or not hasId(k.Image) then
		return false -- the pet style draws its own buttons and cards (the cream / gold pictures belong to the old look)
	end
	-- the owner's picture wins over the shared kit picture (UI.kitSkin): drop it and keep it from coming back
	local kit = b:FindFirstChild("KitSkin")
	if kit then
		kit:Destroy()
	end
	b:SetAttribute("OwnerSkin", true)
	local r = k.Rect
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = -1 -- under the shine sweep (ZIndex 0) and the captions
	img.Image = k.Image
	img.ImageRectOffset = Vector2.new(r[1], r[2])
	img.ImageRectSize = Vector2.new(r[3], r[4])
	img.ScaleType = Enum.ScaleType.Slice
	local iy = math.min(k.Inset, math.floor(r[4] / 2) - 4)
	img.SliceCenter = Rect.new(k.Inset, iy, r[3] - k.Inset, r[4] - iy)
	img.SliceScale = (height or b.Size.Y.Offset) / r[4]
	img.Parent = b
	b.BackgroundTransparency = 1
	local gloss = b:FindFirstChild("Gloss")
	if gloss then
		gloss:Destroy() -- the picture has its own shine; UI.shine's glint sweep stays on top of it
	end
	-- slow light band drifting across the picture (owner ask 2026-10-12): one looping tween, nothing per frame
	if not UI.Reduced then
		local g = Instance.new("UIGradient")
		g.Name = "Drift"
		g.Rotation = 25
		local dim, hi = Color3.fromRGB(215, 215, 215), Color3.fromRGB(255, 255, 255)
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, dim), ColorSequenceKeypoint.new(0.5, hi), ColorSequenceKeypoint.new(1, dim) })
		g.Offset = Vector2.new(-0.6, 0)
		g.Parent = img
		TweenService:Create(g, TweenInfo.new(2.6 + math.random() * 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.6, 0) }):Play()
	end
	for _, c in b:GetChildren() do
		if c:IsA("UIStroke") then
			c.Enabled = false
		end
	end
	-- hover a touch brighter, disabled grayed (the press squash comes from UI.button)
	local function tint()
		img.ImageColor3 = if b:GetAttribute("Disabled") then Color3.fromRGB(150, 150, 150) elseif b:GetAttribute("Hover") then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(235, 235, 235)
	end
	b:GetAttributeChangedSignal("Disabled"):Connect(tint)
	b:GetAttributeChangedSignal("Hover"):Connect(tint)
	tint()
	return true
end

-- True once a HudArt.Buttons picture has its id.
function HudArt.hasSkin(key: string): boolean
	local k = HudArt.Buttons[key]
	return k ~= nil and hasId(k.Image)
end

-- True once the slot has a real uploaded picture.
function HudArt.has(slot: string): boolean
	local s = HudArt.Slots[slot]
	return s ~= nil and hasId(s.Image)
end

-- What a UI.tabs entry draws for a slot: the uploaded picture's id, else the drawn icon kind, else nothing.
function HudArt.tabPicture(slot: string): string?
	local s = HudArt.Slots[slot]
	if not s then
		return nil
	end
	return if HudArt.has(slot) then s.Image else s.Icon
end

-- Square picture for a slot: the uploaded image, else the procedural icon, else the emoji. Returns the holder.
function HudArt.image(parent: Instance, slot: string, size: number, props: { [string]: any }?): GuiObject
	local s = HudArt.Slots[slot]
	if HudArt.has(slot) then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(size, size)
		img.Image = s.Image
		img.ScaleType = Enum.ScaleType.Fit
		for k, v in (props or {}) :: { [string]: any } do
			(img :: any)[k] = v
		end
		img.Parent = parent
		if s.Badge == "up" then
			-- a green circle with a white "+" on the picture's lower right corner (the thin up-arrow glyph read as a
			-- stray mark on a phone)
			local d = math.max(16, math.floor(size * 0.46))
			local badge = Instance.new("Frame")
			badge.Name = "UpBadge"
			badge.AnchorPoint = Vector2.new(1, 1)
			badge.Position = UDim2.new(1, 2, 1, 2)
			badge.Size = UDim2.fromOffset(d, d)
			badge.BackgroundColor3 = Color3.fromRGB(64, 186, 84)
			badge.ZIndex = img.ZIndex + 1
			UI.corner(badge, d // 2)
			UI.stroke(badge, Color3.fromRGB(255, 255, 255), 2)
			local arrow = UI.text(badge, "+", { Name = "Arrow", Font = UI.Head, Size = UDim2.fromScale(1, 1), TextSize = math.floor(d * 0.9), TextXAlignment = Enum.TextXAlignment.Center, Outline = false })
			arrow.TextWrapped = false
			arrow.ZIndex = badge.ZIndex + 1
			badge.Parent = img
		end
		return img
	end
	if s and s.Icon then
		return UI.icon(parent, s.Icon, size, props)
	end
	local g = UI.text(parent, if s then s.Emoji else "?", { Name = "Icon", Size = UDim2.fromOffset(size, size), TextSize = size * 0.8, TextXAlignment = Enum.TextXAlignment.Center, Outline = false })
	g.TextWrapped = false
	for k, v in (props or {}) :: { [string]: any } do
		(g :: any)[k] = v
	end
	return g
end

-- Word pictures (owner's bubble-letter captions): slot "text_<word>", e.g. text_play, text_egg_hunt_race. While a slot
-- is missing or id 0 the normal fitted text shows. Rect = the letters' area in STORED pixels (Roblox keeps uploads at
-- most 1024 px on the long side), so the see-through margin is cropped; leave it out to use the whole picture.
export type Word = { Image: string, Rect: { number }? }

HudArt.Words = {
	text_play = { Image = "rbxassetid://89875527302311", Rect = { 46, 26, 932, 290 } }, -- icons/text_play.png
	text_egg_hunt_race = { Image = "rbxassetid://120944707801640", Rect = { 19, 93, 992, 171 } }, -- icons/text_egg_hunt_race.png
	text_tower = { Image = "rbxassetid://84214979694639", Rect = { 18, 55, 985, 233 } }, -- icons/text_tower.png
	text_pet_battles = { Image = "rbxassetid://134681102183895", Rect = { 19, 68, 997, 186 } }, -- icons/text_pet_battles.png
	text_daily = { Image = "rbxassetid://107024905458130", Rect = { 31, 50, 965, 279 } }, -- icons/text_daily.png
	text_upgrade = { Image = "rbxassetid://112790280058453", Rect = { 19, 43, 989, 265 } }, -- icons/text_upgrade.png
	text_party = { Image = "rbxassetid://117976168232642", Rect = { 28, 47, 979, 338 } }, -- icons/text_party.png
	text_settings = { Image = "rbxassetid://91132635339082", Rect = { 31, 72, 963, 193 } }, -- settings/text_settings.png (owner swap 2026-10-13)
	text_my_pets = { Image = "rbxassetid://0" }, -- REPLACE: icons/text_my_pets.png (picture not made yet; add its Rect)
	-- the lobby Settings tile caption, in the same lettering as text_upgrade / text_party (text_settings above is the
	-- all-caps SETTINGS panel title and looked small and out of place on the tile); plain text until it exists
	text_settings_tile = { Image = "rbxassetid://132909300773968", Rect = { 3, 3, 1020, 155 } }, -- "Settings" like Upgrade
	-- DAILY panel words (reference/ui/daily/); slot names follow the caption text, so two differ from the file names
	text_daily_gift = { Image = "rbxassetid://130529219531710", Rect = { 24, 92, 988, 175 } }, -- daily/text_daily_gift.png
	text_day_7_is_the_big_one = { Image = "rbxassetid://106652209321014", Rect = { 18, 87, 993, 162 } }, -- daily/text_day7_big_one.png
	text_today_s_quests = { Image = "rbxassetid://110000450222400", Rect = { 23, 95, 978, 148 } }, -- daily/text_todays_quests.png
	-- SETTINGS row words (reference/ui/settings/, file = slot name + .png). settings/text_settings.png is a newer copy
	-- of the SETTINGS word above; the uploaded icons/ one stays until the owner swaps it.
	text_music = { Image = "rbxassetid://72628283899221", Rect = { 119, 52, 793, 240 } }, -- settings/text_music.png
	text_sounds = { Image = "rbxassetid://82395505445227", Rect = { 37, 49, 951, 244 } }, -- settings/text_sounds.png
	text_camera_sensitivity = { Image = "rbxassetid://132418772668568", Rect = { 22, 96, 982, 144 } }, -- settings/text_camera_sensitivity.png
	text_reduce_motion = { Image = "rbxassetid://104818690518475", Rect = { 23, 82, 984, 151 } }, -- settings/text_reduce_motion.png
	text_low_effects = { Image = "rbxassetid://108851463070888", Rect = { 20, 86, 989, 181 } }, -- settings/text_low_effects.png
	text_hints = { Image = "rbxassetid://134098200846150", Rect = { 99, 48, 853, 286 } }, -- settings/text_hints.png
	text_skip = { Image = "rbxassetid://115555347320224", Rect = { 55, 61, 918, 294 } }, -- settings/text_skip.png (SETTINGS and hint SKIP buttons)
	text_first_hunt_guide = { Image = "rbxassetid://97113691309913", Rect = { 18, 87, 989, 170 } }, -- settings/text_first_hunt_guide.png
	-- Panel titles and common buttons (ui-50 #50)
	text_upgrades = { Image = "rbxassetid://86763512409354", Rect = { 3, 3, 1020, 143 } }, -- UPGRADES (Upgrades panel tab)
	text_pet_book = { Image = "rbxassetid://134985513090430", Rect = { 3, 3, 1020, 153 } }, -- PET BOOK (Pet Book panel tab)
	text_egg_shop = { Image = "rbxassetid://140406046399302", Rect = { 3, 3, 1020, 152 } }, -- EGG SHOP (Egg Shop panel tab)
	text_pet_tower = { Image = "rbxassetid://89720726468934", Rect = { 2, 2, 1021, 135 } }, -- PET TOWER (Tower panel tab)
	text_buy = { Image = "rbxassetid://71487225037993", Rect = { 7, 7, 1016, 364 } }, -- BUY (list row buttons)
	text_equip = { Image = "rbxassetid://132606053786336", Rect = { 6, 5, 1018, 263 } }, -- EQUIP (list row and detail buttons)
	text_play_again = { Image = "rbxassetid://128295643129855", Rect = { 2, 2, 1021, 129 } }, -- PLAY AGAIN (results)
	text_lobby = { Image = "rbxassetid://84037549662887", Rect = { 5, 5, 1018, 230 } }, -- LOBBY (results)
	-- START HUNT words (reference/ui/start_hunt/, file = slot name + .png); "up to 4" follows Config.Party.MaxSize
	text_start_hunt = { Image = "rbxassetid://113207439376464", Rect = { 24, 105, 981, 143 } }, -- start_hunt/text_start_hunt.png
	text_one_pile_one_pet = { Image = "rbxassetid://84728739832356", Rect = { 13, 93, 1002, 154 } }, -- start_hunt/text_one_pile_one_pet.png
	text_practice_hunt = { Image = "rbxassetid://112929180082685", Rect = { 18, 106, 989, 127 } }, -- start_hunt/text_practice_hunt.png
	text_a_small_pile_to_learn_the_ropes = { Image = "rbxassetid://115723738140463", Rect = { 8, 113, 1009, 107 } }, -- start_hunt/text_a_small_pile_to_learn_the_ropes.png
	text_party_hunt = { Image = "rbxassetid://115143501322966", Rect = { 31, 94, 968, 147 } }, -- start_hunt/text_party_hunt.png
	text_up_to_4_players_one_pet = { Image = "rbxassetid://89221769499641", Rect = { 18, 116, 992, 114 } }, -- start_hunt/text_up_to_4_players_one_pet.png
	text_start = { Image = "rbxassetid://80189452461987", Rect = { 54, 57, 931, 250 } }, -- start_hunt/text_start.png
	text_create_party = { Image = "rbxassetid://84981341306787", Rect = { 11, 99, 1004, 144 } }, -- start_hunt/text_create_party.png
} :: { [string]: Word }

-- success toasts show the owner's green tick once its picture is uploaded; it is fetched now, so the first toast
-- shows it straight away instead of the drawn tick swapping to the picture a moment later
if hasId(HudArt.Slots.CheckGreen.Image) then
	local tick = HudArt.Slots.CheckGreen.Image
	UI.OkPicture = tick
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ tick }, function(_, status)
				if status == Enum.AssetFetchStatus.Success then
					UI.OkPictureReady = true
				end
			end)
		end)
	end)
end

-- every uploaded word picture is fetched at start-up, so the lobby buttons show their words as
-- soon as the HUD appears
task.spawn(function()
	local ids = {}
	for _, w in HudArt.Words do
		if hasId(w.Image) then
			table.insert(ids, w.Image)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(ids)
	end)
end)

function HudArt.wordKey(text: string): string
	local k = string.gsub(string.gsub(string.lower(text), "[^%w]+", "_"), "^_*(.-)_*$", "%1")
	return "text_" .. k
end

-- Shows the word picture for whatever `label` says (when that word has one) in place of the label: same box, kept
-- in proportion, left-aligned or centred like the text. Follows later text changes (PLAY -> "PLAY 2/4" shows text).
-- `fill` (0..1, default 1) shrinks the picture inside that box so it keeps a margin from the button's rim.
function HudArt.word(label: TextLabel, fill: number?)
	local parent = label.Parent
	if not parent or Theme.PetStyle then
		return -- the pet style keeps every word as text (the bubble word pictures belong to the old look)
	end
	-- one picture per label: UI.button may already have added it, so a later call only changes the fill
	label:SetAttribute("WordFill", fill or 1)
	if label:GetAttribute("HasWord") then
		return
	end
	label:SetAttribute("HasWord", true)
	local img = Instance.new("ImageLabel")
	img.Name = "WordImage"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = label.ZIndex
	img.LayoutOrder = label.LayoutOrder -- takes the label's place when it sits in a list layout
	img.Visible = false
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectType = Enum.AspectType.FitWithinMaxSize
	ar.Parent = img
	img.Parent = parent
	local function update()
		-- a label can name its own slot (WordKey attribute) when the plain word's picture has the wrong style there
		local key = label:GetAttribute("WordKey")
		local w = HudArt.Words[if type(key) == "string" then key else HudArt.wordKey(label.Text)]
		local on = w ~= nil and hasId(w.Image)
		if w and on then
			img.Image = w.Image
			local r = w.Rect
			if r then
				img.ImageRectOffset = Vector2.new(r[1], r[2])
				img.ImageRectSize = Vector2.new(r[3], r[4])
				ar.AspectRatio = r[3] / r[4]
			else
				img.ImageRectOffset = Vector2.zero
				img.ImageRectSize = Vector2.zero
				ar.AspectRatio = 3
			end
			-- anchor on the text's alignment side so the shrunk box stays where the words were
			local ax = if label.TextXAlignment == Enum.TextXAlignment.Left then 0 elseif label.TextXAlignment == Enum.TextXAlignment.Right then 1 else 0.5
			img.AnchorPoint = Vector2.new(ax, 0.5)
			local p, z = label.Position, label.Size
			-- measured from the label's own anchor (a bottom-anchored caption must not drop half a box lower)
			local la = label.AnchorPoint
			local kx, ky = ax - la.X, 0.5 - la.Y
			img.Position = UDim2.new(p.X.Scale + z.X.Scale * kx, p.X.Offset + z.X.Offset * kx, p.Y.Scale + z.Y.Scale * ky, p.Y.Offset + z.Y.Offset * ky)
			local f = (label:GetAttribute("WordFill") :: number?) or 1
			img.Size = UDim2.new(z.X.Scale * f, z.X.Offset * f, z.Y.Scale * f, z.Y.Offset * f)
		end
		-- (gating on IsLoaded kept the plain word up for good in Studio; the word pictures are preloaded instead,
		-- at start-up, so a slow phone does not show an empty tile for long)
		img.Visible = on
		label.Visible = not on
	end
	-- follow the label when its owner moves it after the picture was added (bigButton shifts the title right of
	-- its icon after UI.button made it; without this the word stayed centred under the icon)
	for _, prop in { "Text", "Position", "Size", "AnchorPoint", "TextXAlignment" } do
		label:GetPropertyChangedSignal(prop):Connect(update)
	end
	label:GetAttributeChangedSignal("WordFill"):Connect(update)
	update()
end

export type BigOpts = {
	Name: string,
	Style: string,
	Art: string,
	Skin: string?,
	Title: string,
	Sub: string?,
	Width: number,
	Height: number,
	LayoutOrder: number?,
	OnClick: () -> (),
}

-- Caption pill height of a big button `h` tall, and the gap kept between the title and that pill.
local SUB_GAP = 4
local SUB_BOTTOM = 5 -- gap under the caption pill
local function subPillH(h: number): number
	return math.max(22, math.floor(h * 0.36)) -- tall enough for body-size words (bug #220: "Best floor 4" read tiny)
end

-- Chunky lobby button (mockup): picture on the left, bubble title, caption in a darker pill under it. Uses UI.button,
-- so it keeps the press squash and spring-back bounce, hover, and the touch pad. The title stays the "Label" child.
function HudArt.bigButton(parent: Instance, o: BigOpts): TextButton
	local h = o.Height
	local b = UI.button(parent, o.Title, o.Style, o.OnClick, { Name = o.Name, Size = UDim2.fromOffset(o.Width, h), LayoutOrder = o.LayoutOrder or 0, TextSize = if o.Sub then T.Head + 2 else T.Head })
	UI.corner(b, 14)
	if o.Skin then
		HudArt.skin(b, o.Skin)
	end
	local art = math.floor(h - (if o.Sub then 20 else 12))
	HudArt.image(b, o.Art, art, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = b.ZIndex + 1 })
	local x = art + 10
	local label = b:FindFirstChild("Label") :: TextLabel?
	if label then
		-- title centred in the space right of the picture, clear of the rim (the skin's lip covers the top few pixels)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = false
		if o.Sub then
			-- the title ends a clear gap above the caption pill (bubble letters touched the pill and read as overlapping)
			local top = math.floor(h * 0.08)
			label.Position = UDim2.fromOffset(x, top)
			label.Size = UDim2.new(1, -(x + 10), 0, h - subPillH(h) - SUB_BOTTOM - SUB_GAP - top)
		else
			label.Position = UDim2.fromOffset(x, math.floor(h * 0.14))
			label.Size = UDim2.new(1, -(x + 10), 1, -math.floor(h * 0.28))
		end
		HudArt.word(label, if o.Sub then 0.9 else 0.94)
	end
	if o.Sub then
		local ph = subPillH(h)
		local pill = UI.frame(b, { Name = "SubPill", Position = UDim2.new(0, x - 4, 1, -(ph + SUB_BOTTOM)), Size = UDim2.new(1, -(x + 6), 0, ph), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.78 })
		UI.corner(pill, ph // 2)
		local st = UI.styleOf(o.Style)
		local sub = UI.text(pill, o.Sub, { Name = "Sub", Font = UI.Bold, TextSize = T.Body, TextColor3 = if st == "gold" then TC.DarkText else TC.Text, Outline = if st == "gold" then false else "Normal", Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Center })
		sub.TextWrapped = false
		UI.fit(sub, T.Body, T.MinText)
		sub.TextWrapped = false
		HudArt.word(sub, 0.84)
		HudArt.fitSub(b)
		UI.Resized.Event:Connect(function()
			if b.Parent then
				HudArt.fitSub(b)
			end
		end)
	end
	return b
end

-- The caption pill shows only where it can hold its words at the text floor (12 real px: UI.fit's minimum at the
-- current scale). On a short screen (under 420 logical px tall) a pill too thin for that is hidden rather than its
-- words shrunk under the floor. The pill remembers the verdict (TooShort) so HudArt.compact never shows it again.
function HudArt.fitSub(b: GuiObject)
	local pill = b:FindFirstChild("SubPill") :: GuiObject?
	local sub = if pill then pill:FindFirstChild("Sub") :: TextLabel? else nil
	if not pill or not sub then
		return
	end
	local fit = sub:FindFirstChild("Fit") :: UITextSizeConstraint?
	local lo = if fit then fit.MinTextSize else T.MinText
	local tooShort = UI.Logical.Y < 420 and pill.Size.Y.Offset < lo * 1.2 + 2
	pill:SetAttribute("TooShort", tooShort)
	if tooShort then
		pill.Visible = false
	elseif pill:GetAttribute("Compact") ~= true then
		pill.Visible = true
	end
end

-- puts the full title back after the square tile's short word (HudArt.compact)
function HudArt.restoreText(label: TextLabel?)
	local home = if label then label:GetAttribute("HomeText") else nil
	if label and type(home) == "string" then
		label.Text = home
	end
end

-- Compact form of a big button for the touch rows (narrow cells, SafeZones.lobbyLayout): the caption pill is hidden,
-- the picture shrinks (and goes when the cell is under 100 px), and the title alone fills the rest. `on = false`
-- restores the layout bigButton made. Works on the button itself; PlayButton's wrapper passes its children.
function HudArt.compact(b: GuiObject, on: boolean, w: number, h: number)
	local label = b:FindFirstChild("Label") :: TextLabel?
	local icon = b:FindFirstChild("Icon") :: GuiObject?
	local pill = b:FindFirstChild("SubPill") :: GuiObject?
	if label and label:GetAttribute("HomePos") == nil then
		label:SetAttribute("HomePos", label.Position)
		label:SetAttribute("HomeSize", label.Size)
		label:SetAttribute("HomeAlign", label.TextXAlignment)
	end
	if icon and icon:GetAttribute("HomeSize") == nil then
		icon:SetAttribute("HomeSize", icon.Size)
		icon:SetAttribute("HomePos", icon.Position)
		icon:SetAttribute("HomeAnchor", icon.AnchorPoint)
	end
	if pill then
		pill:SetAttribute("Compact", on)
		pill.Visible = not on and pill:GetAttribute("TooShort") ~= true
	end
	if on and w <= h + 8 then
		-- square tile (landscape phone row, 2026-10-15): the picture centred in the top part, the one word along the
		-- bottom edge, full width, never wrapped (the fitted text goes down to the 12 px floor, not under it)
		local a = math.max(16, h - 32)
		if icon then
			icon.Visible = true
			icon.Size = UDim2.fromOffset(a, a)
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, 3)
		end
		if label then
			-- a 24 px word box: about 20 real px at the phone scale (12 read tiny in the Studio phone window)
			label.Position = UDim2.new(0, 1, 1, -26)
			label.Size = UDim2.new(1, -2, 0, 24)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextWrapped = false
			-- a tile is too narrow for TOWER / BATTLE at the text floor (fitted text wraps mid-word), so the button's
			-- short word (Short attribute: TRAIN, FIGHT) takes over while it is square
			local short = b:GetAttribute("Short")
			if type(short) == "string" then
				if label:GetAttribute("HomeText") == nil then
					label:SetAttribute("HomeText", label.Text)
				end
				label.Text = short
			end
		end
	elseif on then
		HudArt.restoreText(label)
		local showIcon = w >= 100
		local a = if showIcon then math.max(16, h - 16) else 0
		if icon then
			icon.Visible = showIcon
			icon.Size = UDim2.fromOffset(a, a)
			icon.AnchorPoint = icon:GetAttribute("HomeAnchor") :: Vector2
			icon.Position = icon:GetAttribute("HomePos") :: UDim2
		end
		if label then
			local x = if showIcon then a + 10 else 8
			label.Position = UDim2.fromOffset(x, math.floor(h * 0.14))
			label.Size = UDim2.new(1, -(x + 8), 1, -math.floor(h * 0.28))
			label.TextXAlignment = label:GetAttribute("HomeAlign") :: Enum.TextXAlignment
			label.TextWrapped = false
		end
	else
		HudArt.restoreText(label)
		if icon then
			icon.Visible = true
			icon.Size = icon:GetAttribute("HomeSize") :: UDim2
			icon.AnchorPoint = icon:GetAttribute("HomeAnchor") :: Vector2
			icon.Position = icon:GetAttribute("HomePos") :: UDim2
		end
		if label then
			label.Position = label:GetAttribute("HomePos") :: UDim2
			label.Size = label:GetAttribute("HomeSize") :: UDim2
			label.TextXAlignment = label:GetAttribute("HomeAlign") :: Enum.TextXAlignment
		end
	end
end

-- any UI.button whose word has an uploaded picture (BUY, EQUIP, PLAY AGAIN...) shows it; others stay text
UI.ButtonWord = function(label: TextLabel)
	local w = HudArt.Words[HudArt.wordKey(label.Text)]
	if w and hasId(w.Image) then
		HudArt.word(label, 0.8)
	end
end

return HudArt
