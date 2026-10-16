# "Liked" UI style: reference spec

The owner liked the UI in a Roblox clip (`/mnt/project-files/Roblox 2026-10-14 17-36-46.mp4`, 1920 x 1012, 60 fps).
This file writes down what that clip does, so our game can copy the **look and motion** while keeping **its own
content** (pets, eggs, shells, our own menus). Frames: `reference/liked_ui/full/t_NN.png` (NN = second in the clip),
detail crops: `reference/liked_ui/crops/`, contact sheets: `reference/liked_ui/sheet_0..2.jpg`, comparisons:
`reference/liked_ui/side_by_side/`.

Source of truth for every number below: `src/shared/LikedStyle.luau` (pure, tested in
`tests/test_liked_style.luau`). The client kit that draws it: `src/client/ui/Liked.luau`. Switch: `Theme.Style =
"Liked"` in `src/client/ui/Theme.luau` (any other value gives the old look back). While Liked is on, no kit or HudArt
picture is drawn over a Liked piece (HudArt / UiKit / PanelSkin skip their skins), so the code-drawn layers show.

## 1. How things were measured

- Frames were pulled with ffmpeg at full size; colours are the median of a 5 x 5 box (PIL) on flat areas, away from
  outlines and glints.
- Sizes are measured on the 1012 px tall frame and stored as a fraction of screen height `H`, clamped to logical px
  so phones keep 44 px touch targets (`LikedStyle.size`).
- Logical px = the UI layer after our UIScale (design 800 x 400; about 2.5 frame px per logical px at 1012 tall).
- Motion was stepped frame by frame at 60 fps (16.7 ms per frame); times are rounded to the nearest frame pair.
  Easing was picked by matching the in-between frames against Quad / Quart / Back / Sine curves.

## 2. Global tokens

### Colours (hex)

| Token | Hex | Where in the clip |
| --- | --- | --- |
| CyanTop / Cyan / CyanLow | #4CF2FF / #27CCFE / #08BFFE | left HUD squares (Shop, Trade), top to body |
| CyanLip / CyanEdge | #006C8E / #003446 | the darker lip under each square, its outer edge |
| ActTop / Act / ActLip / ActEdge | #28C4FF / #1CB1FF / #205269 / #001F2C | the big bottom-centre action square |
| QuestBody / QuestEdge | #F0F9FE / #96D6FF | NEXT UP bar body and edge |
| QuestTitle / QuestTitleEdge | #1E96F0 / #08346E | NEXT UP words; also our section heads' outline |
| QuestTag / QuestTagEdge | #FFDA34 / #6E3C00 | the yellow "NEXT UP!" tag |
| BarFillTop / BarFill / BarTrack / BarEdge | #AAFF3C / #76F500 / #007FBF / #00345A | progress bars |
| CoinText / GemText / CountEdge | #FFD84A / #2FA8FF / #1C1628 | currency counts and their outline |
| Shade | #000000 at 0.45 | world shade behind an open menu |
| TabBar / TabBarEdge / TabText | #102E42 / #081620 / #CEDCE6 | menu tab strip |
| LimeTop / Lime / LimeEdge | #D2FE00 / #72FE00 / #2E6E00 | selected tab pill, green buttons |
| RedTop / Red / RedEdge | #FF5A5A / #F03131 / #7A0A12 | the X close button, red buttons |
| Panel / PanelPattern / PanelEdge | #FFFFFF / #E2EEF8 / #D6E8F8 | white menu sheets and their diamond pattern |
| TitleText / TitleEdge / TitleShadow | #FFFFFF / #00456B / #002842 | "Shop" / "Pets" titles outside the panel |
| PriceTop / Price / PriceEdge | #C8FF28 / #79FD00 / #246000 | green price pills |
| BlueTop / Blue / BlueEdge | #5AD6FF / #1EAAFF / #003C78 | blue "Open" pills |
| RibbonGold / RibbonRed | #FFC41E / #E81E3C | "Limited" / "Best value" ribbons |
| Holo / HoloTop / HoloLow / HoloEdge / HoloGlow | #2FC6FF / #78E6FF / #148CF5 / #0A5AC8 / #5FF4FF | pets holographic card |
| NewTag | #FFD84A | "NEW!" over a hatched pet |

### Card gradients (left to right, UIGradient rotation 0)

| Tone | Stops |
| --- | --- |
| purple | #466EFF -> #963CFF -> #F050DC (Magic Eggs card) |
| gold | #FFD678 -> #FF9628 -> #DC4628 (Chronos Egg, Godly Hatches) |
| blue | #2878FF -> #1EBEFF -> #5A5AFF (Pets bundle row) |
| pink | #FF6EBE -> #DC5AFF -> #AA5AFF (Tokens row) |
| green | #3CC85A -> #78E63C -> #1EA078 |

Shop cards cycle purple, gold, blue, pink, green (`LikedStyle.tone(i)`); a card you cannot afford or that is locked
turns blue.

### Shape

| Thing | Radius | Stroke | Notes |
| --- | --- | --- | --- |
| Menu panel | 14 (36 frame px) | 2 | white, faint diamond pattern drifting |
| Gradient card | 10 | 2.5 dark edge | drop copy 4 px down (ShadowDrop), glow 6 px when selected |
| HUD square | 10 (24 frame px) | 2.5 (6 frame px) | lighter top, lip from 84 % down |
| Pills | full | 2.5 | price, Open, Settings |
| Titles | - | 3 (+1 on the menu title) | dark copy 3 px lower as the shadow |
| Button words | - | 1.6 | counts and prices 2.4 |

### Type

- Display and body: **Fredoka One** (rounded heavy). Titles white with a thick dark outline and a dark drop copy.
- HUD counts, "NEXT UP!", section heads: **Gotham SSm Heavy Italic**, heavy outline (CountEdge or QuestTitleEdge).
- Sizes (logical px): menu title 40, section 24, card title 26, tab 17, button 20, price 18, body 15, HUD count 22,
  caption 15, ribbon 14. Nothing under the shared text floor (UiKit.MinText 14; 12 real px on screen).
- Text in fixed boxes goes through `UI.text` / `UI.button` / `Liked.text` (fitted), never a raw TextSize.

### Icons

The clip uses glossy 3D-rendered pictures (a cursor, a padlock, a clover, egg art) with a dark outline and a soft
drop shadow, about 60 % of the button. Ours use the HudArt slots (Paw, Calendar, Party, Coin, Egg, Gear, ...). Many
slots are still id 0, which the preview draws as a hatched placeholder; see "Art still needed" below. No hammer, rock
or mining pictures: the theme is pets and eggs.

## 3. Screens: theirs and ours

Layout numbers are fractions of the screen (`W`, `H`), from `LikedStyle.lobby` and the panels.

### 3.1 Lobby HUD (clip t_01, t_09, t_13; crops lobby_*)

| Piece | Theirs | Ours (`client/ui/LikedHud.luau`) |
| --- | --- | --- |
| Left squares | 2 cyan squares (Shop, Trade), 95 px = 0.094 H, gap 0.008 H, centred near 0.48 H, x 15 px | 4 squares: Pets, Shop, Daily, Party; same size and centre; on very short screens they go into 2 columns |
| Currency | bottom left: Rebirths / coins / gems, icon 0.054 H, rows 0.075 H, heavy italic counts | coins (CoinText) and shells ("14/30 Shells"); counts tick up (UiMotion count) |
| NEXT UP bar | top centre, 0.474 H wide, 0.087 H tall, white body, yellow tilted "NEXT UP!" tag, egg picture, green bar | same; text = the server's next daily quest (`LikedStyle.nextUp`), or the lobby objective; "CLAIM!" tag when one is done |
| Action square | bottom centre, 150 x 160 frame px, "+1" bubble bobbing | Play (start a hunt) with a bobbing "Hunt!" bubble; the queue card sits over it |
| Right icons | small padlocked icons from 0.35 H down | Tower, Battle, Free Gift (timer as the caption pill); kept above the jump button |
| Settings | dark pill top right | same (Gear picture); DEV tile goes under it |

### 3.2 Shop (clip t_03 - t_16; crops shop_*)

| | Theirs | Ours (`client/ui/ShopPanel.luau`, `likedGrid`) |
| --- | --- | --- |
| Frame | no panel behind the cards: cards float over the dark blurred world; "Shop" title top left, tab strip, coins, red X | same: the sheet is hidden in Liked, title outside, navy cash pill, red X |
| Tabs | navy strip, lime selected pill slides 150 ms | same pill and slide (UiJuice tab slide with Motion.TabSlide) |
| Cards | wide gradient cards with a picture, a white heavy-outlined name, small effect words, price pills, ribbons | 2-column grid of gradient cards (1 column portrait): picture on a light disc, name, effect line, state ribbon (Owned / Equipped / Max! / Locked), price pill (coin + number, "Need N" in red) |
| Motion | hover lift, shine sweep, slow pattern drift | tilt toward the pointer (CardTilt), hover 1.03, shine every 3.5 s, press bounce on touch |

Our content stays: upgrades (gear, pets slots, luck), Robux eggs behind the Robux tab with full odds, no fake ids.

### 3.3 Pets (clip t_25, t_27; crops pets_*)

| | Theirs | Ours (`client/ui/CollectionPanel.luau`, `likedHolo`) |
| --- | --- | --- |
| Card | big holographic card, cyan gradient, white starburst behind the pet, thick blue edge, outer glow, tilted -3 deg, follows the cursor | same: holo gradient, burst disc with 4 rays, edge 4, glow 6, idle -3 deg, HoloTilt follow (max 4 deg, 0.0085 H offset, ease 8/s) |
| Title | "Pets" in a blue gradient | "Pets" white with the blue edge |
| Footer | Equip / Delete pills | Equip (green) / Unequip (red) |

### 3.4 Daily (no Daily screen in the clip; built from the shared menu rules)

`client/ui/QuestPanel.luau`: white sheet, title "Daily" outside the panel, cyan gift box, light cyan day tiles,
section heads ("DAILY GIFT", "TODAY'S QUESTS") in white heavy italic with a navy outline (`PanelSkin.word`, Name
"Title"), lime CLAIM, the green bar colours.

### 3.5 Settings (no Settings screen in the clip; built from the shared menu rules)

`client/ui/SettingsPanel.luau`: cyan rows with a dark lip, white outlined labels, yellow slider fill, lime ON / white
OFF toggles, the menu title outside the panel, the red X.

### 3.6 Egg hatch (clip t_27 - t_31, 26.9 - 31.7 s)

| | Theirs | Ours (`client/HatchShow.luau`, `likedCaption`) |
| --- | --- | --- |
| Egg | big egg mid-screen, HUD hidden, world blurred, cracks spread per tap | our 3D hatch show (demo egg v2 port: wobble, cracks, rays, burst), HUD hidden |
| Burst | white flash, fades about 0.5 s | white then rarity-colour flash, fades in Egg.Flash (0.5 s) |
| Caption | under the pet: small yellow italic "NEW!" (3 % H), name in big white Fredoka with a dark outline (6.8 % H), "1 in 2" odds (4.5 % H) | same three lines at 0.58 H; NEW! only on the first of that species and rarity; the third line shows the rarity word in its colour (we do not show odds there) |
| Exit | pet shrinks into the HUD | caption shrinks to 0 in Egg.FlyOut (Back In) with the pet |

## 4. Animations

All in `LikedStyle.Motion` (tested), driven by `client/ui/Liked.luau`, `UiJuice` and `UiMotion`.

| Animation | Measured on the clip | Ours |
| --- | --- | --- |
| Menu open | world darkens + blurs in 1-2 frames (30 ms); the panel scales 1.06 -> 1 and drops 20 px in 230 ms, Quad Out | MenuOpen: 0.23 s Quad Out, from 1.06 and -20 px, shade 0.45 in 0.03 s, blur 18 |
| Menu close | X squashes, panel swells 3 % in 50 ms, then shrinks to 0.7 in 80 ms, Back In, gone | MenuClose: swell 1.03 / 0.05 s, then 0.08 s Back In to 0.7 |
| Press / release | squash to about 0.92 in 4 frames; springs back past 1 in about 180 ms | Press 0.92 / 0.07 s Quad Out; Release 0.18 s Back Out |
| Hover | lift to about 1.05 in 120 ms | Hover 1.05 / 0.12 s (computer only) |
| Tab pill | slides 210 frame px in 133-167 ms, fast start | TabSlide 0.15 s Quart Out (`LikedStyle.tabX`) |
| Pattern drift | diamonds drift down-right 13 frame px/s | PatternDrift 0.0068 H per second (`patternOffset`) |
| Shine | one white glint across a card about every 3.5 s, 0.6 s, Sine InOut | Shine 0.6 s every 3.5 s (`shineOffset`) |
| Counts | numbers run up | Count 0.45 s (UiMotion.countValue) |
| Idle bob | "+1" bubble and icons bob about 3 px, 1.6 s | Bob 3 px / 1.6 s |
| Toast | slides 40 px in from the right with a pop | Toast 0.22 s Back Out from 40 px |
| Holo tilt | edges tilt -7..+8 deg in perspective, centre moves +-17 px, 90 % in about 0.3 s | HoloTilt: flat rotation +-4 deg, +-0.0085 H, ease 8/s (`tilt`, `lerpAlpha`) |
| Card tilt | under 1 px while the cursor rested; owner asked for the follow anyway | CardTilt: 2 deg, 0.004 H, 10/s, hover 1.03 |
| Egg | fly-in 0.3 s Back Out; each tap 0.2 s (shake +-15 deg, squash 0.62, ring 1 -> 1.6); swell to 1.25 in 0.7 s; white 0.15 s; flash 0.5 s; hold 1.6 s; fly-out 0.15 s | Motion.Egg with the same numbers (`eggPhase` gives the phase at any time); the 3D show keeps the demo egg's own timing, the caption and flash use these |

Touch devices: no pointer, so cards and the holo card do not follow; they get the press bounce instead. Reduce
Motion (Settings) turns off the drift, shine, bob and tilt.

## 5. Layout rules (Liked)

- Nothing sits on Roblox's jump button, top bar or the player list (`check_layout.py`, 0 problems is the bar).
- No panel fill or backing shows above or around a header plate: the title sits outside the white sheet, and the
  shop hides its sheet entirely.
- **One announcement lane.** Banners that pop over the HUD (RARE HATCH, the big Juice words) never cover another HUD
  card. Cards register with `client/ui/AnnounceLane` (hangout status card, race TAP button, EMOTE, the NEXT UP bar,
  the lobby objective, the toast column, the lobby squares, side icons, PLAY and its bubble, currency rows, the
  Settings pill). A banner asks `shared/BannerLane.place` (pure, tested in `tests/test_banner_lane.luau`) for the
  nearest free spot: its own spot if free, else above / below / beside the cards, then narrower (down to 60 %), then
  one line tall; always inside the screen and clear of the jump button. A banner on screen registers itself, so two
  banners stack.

## 6. Honest notes

- The preview renderer does not blur, does not draw images (hatched placeholders), and draws UIGradient on text
  only roughly; glow and drop copies are drawn as frames and show as they will in Roblox. Final colours and blur
  must be checked in Studio.
- The 3D hatch show is the owner's demo egg port; only its caption and flash follow this spec.
- Shop card tilt could not be measured from the clip (the cursor rested); the values are a smaller copy of the
  holo card's.
- Nothing here was checked in Studio.

## 7. Art still needed (owner uploads; ids stay 0 until then)

- Lobby square pictures: paw (Pets), shop bag or collar (Shop), calendar (Daily), party, tower, battle, gift.
- Coin, shell, egg (NEXT UP) and gear (Settings) pictures in the glossy outlined style.
- Shop item thumbnails: some gear rows still use the old tool pictures (`ItemView` / kit thumbnails); they need pet
  and egg themed art.
- An optional starburst picture for the holo card (the drawn disc and rays stand in).
