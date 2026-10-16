# Theme sweep (pet game, no rock or mining wording)

Player-visible text only. Ids, keys, code names, comments and save data are unchanged. Banned words live in `src/shared/ThemeWords.luau`; `tests/test_theme_words.luau` enforces them.

## Coin upgrades (display only; ids Hammer / SteelHammer / Jackhammer / AutoCracker / HydraulicPress / IndustrialCrusher stay)

| Id | Old | New | Icon (drawn fallback in ItemView, shop thumb) |
|---|---|---|---|
| Hammer | Wooden Mallet | Lucky Collar | boostLuck |
| SteelHammer | Golden Mallet | Treat Bag | boostCoins |
| Jackhammer | Rainbow Tapper | Pet Whistle | boostSpeed |
| AutoCracker | Auto Hatcher | Auto Nest | queue |
| HydraulicPress | Egg Press | Warm Incubator | egg |
| IndustrialCrusher | Mega Hatcher | Mega Incubator | sparkle |

Shop tabs: Tools -> Gear, Machines -> Nests. Stat wording: Power -> Find power, hits/s -> taps/s.

## Every string changed (file:line, old -> new)

- `src/shared/Config.luau:48`: `Recommended = "Wooden Mallet"` -> `Recommended = "Lucky Collar"`
- `src/shared/Config.luau:54`: `Recommended = "Golden Mallet"` -> `Recommended = "Treat Bag"`
- `src/shared/Config.luau:66`: `Recommended = "Rainbow Tapper + hatcher"` -> `Recommended = "Pet Whistle + Auto Nest"`
- `src/shared/Config.luau:60`: `Recommended = "Rainbow Tapper"` -> `Recommended = "Pet Whistle"`
- `src/shared/Config.luau:72`: `Recommended = "Best hatcher"` -> `Recommended = "Best incubator"`
- `src/shared/Config.luau:90`: `Name = "Wooden Mallet"` -> `Name = "Lucky Collar"`
- `src/shared/Config.luau:91`: `Name = "Golden Mallet"` -> `Name = "Treat Bag"`
- `src/shared/Config.luau:92`: `Name = "Rainbow Tapper"` -> `Name = "Pet Whistle"`
- `src/shared/Config.luau:102`: `Name = "Auto Hatcher"` -> `Name = "Auto Nest"`
- `src/shared/Config.luau:103`: `Name = "Egg Press"` -> `Name = "Warm Incubator"`
- `src/shared/Config.luau:104`: `Name = "Mega Hatcher"` -> `Name = "Mega Incubator"`
- `src/shared/Config.luau:400`: `Every egg you crack leaves some.` -> `Every egg you hatch leaves some.`
- `src/shared/Config.luau:483`: `Name = "Copper Heads"` -> `Name = "Copper Shine"`
- `src/shared/Config.luau:484`: `Warm copper tool heads. Looks only: same power.` -> `Warm copper shine for your gear. Looks only: same power.`
- `src/shared/Config.luau:488`: `Name = "Night Steel"` -> `Name = "Night Shine"`
- `src/shared/Config.luau:489`: `Dark blue steel with bright edges. Looks only: same power.` -> `Dark blue shine with bright edges. Looks only: same power.`
- `src/shared/Config.luau:503`: `ToolSkin = "Tool skin"` -> `ToolSkin = "Gear skin"`
- `src/shared/ProgressConfig.luau:77`: `Text = "Crack %d eggs"` -> `Text = "Hatch %d eggs"`
- `src/shared/ProgressConfig.luau:34`: `Name = "Stone Nest"` -> `Name = "Clay Nest"`
- `src/shared/TowerConfig.luau:166`: `Name = "Rock Toss"` -> `Name = "Mud Toss"`
- `src/shared/TowerConfig.luau:166`: `Name = "Boulder Smash"` -> `Name = "Mega Stomp"`
- `src/shared/TowerConfig.luau:199`: `Name = "Rock Crab"` -> `Name = "Shell Crab"`
- `src/shared/Hangout.luau:205`: `GoldenRock = "GOLDEN ROCK"` -> `GoldenRock = "GOLDEN EGG"`
- `src/first/LoadingScreen.luau:45`: `Tap fast to crack eggs quicker!` -> `Tap fast to hatch eggs quicker!`
- `src/first/LoadingScreen.luau:47`: `Better tables hatch rarer pets.` -> `Better nests hatch rarer pets.`
- `src/server/LobbyEvents.luau:157`: `"GOLDEN ROCK\n" .. math.max(0, rockNeed - rockTotal) .. " hits left"` -> `"GOLDEN EGG\n" .. math.max(0, rockNeed - rockTotal) .. " taps left"`
- `src/server/LobbyEvents.luau:184`: `"The GOLDEN ROCK cracked! "` -> `"The GOLDEN EGG hatched! "`
- `src/server/LobbyEvents.luau:226`: `"GoldRock", "Crack", "Golden Rock"` -> `"GoldRock", "Tap", "Golden Egg"`
- `src/server/LobbyEvents.luau:230`: `"A GOLDEN ROCK appeared! Everyone crack it together!"` -> `"A GOLDEN EGG appeared! Everyone tap it together!"`
- `src/server/LobbyEvents.luau:232`: `"The golden rock got away... next time!"` -> `"The golden egg rolled away... next time!"`
- `src/server/LobbyGames.luau:154`: `"Whack-a-Rock: " .. hits .. " hits! +"` -> `"Egg Pop: " .. hits .. " taps! +"`
- `src/server/LobbyGames.luau:169`: `"Tap the rocks!"` -> `"Tap the eggs!"`
- `src/server/LobbyGames.luau:442`: `"Whack", "Play", "Whack-a-Rock"` -> `"Whack", "Play", "Egg Pop"`
- `src/client/HangoutView.luau:432`: `"WHACK-A-ROCK: " .. tostring(data.Hits) .. " hits, "` -> `"EGG POP: " .. tostring(data.Hits) .. " taps, "`
- `src/client/HangoutView.luau:443`: `"GOLDEN ROCK: " .. tostring(data.Left) .. " hits left"` -> `"GOLDEN EGG: " .. tostring(data.Left) .. " taps left"`
- `src/client/Main.client.luau:157`: `"Hold CRACK! to crack your egg!"` -> `"Hold HATCH! to hatch your egg!"`
- `src/client/Main.client.luau:159`: `"Stand at your nest, hold CRACK!"` -> `"Stand at your nest, hold HATCH!"`
- `src/client/Main.client.luau:712`: `"Nest is full! Crack some eggs first."` -> `"Nest is full! Hatch some eggs first."`
- `src/client/Main.client.luau:717`: `"Your machine cracks for you! Bring it eggs."` -> `"Your Auto Nest hatches for you! Bring it eggs."`
- `src/client/ui/Hud.luau:261`: `["Tray full: crack some eggs first"] = "Nest is full. Crack some eggs first."` -> `["Tray full: hatch some eggs first"] = "Nest is full. Hatch some eggs first."`
- `src/client/ui/Hud.luau:271`: `"^Your machine cracks"` -> `"^Your Auto Nest hatches"`
- `src/client/ui/Hud.luau:1390`: `"MACHINE CRACKING"` -> `"AUTO NEST HATCHING"`
- `src/client/ui/Hud.luau:452`: `"CRACKING"` -> `"HATCHING"`
- `src/client/ui/Hud.luau:537`: `"CRACKING"` -> `"HATCHING"`
- `src/client/ui/Hud.luau:543`: `"CRACKING"` -> `"HATCHING"`
- `src/client/ui/Hud.luau:1392`: `"CRACKING"` -> `"HATCHING"`
- `src/client/ui/Hud.luau:1428`: `"CRACKING"` -> `"HATCHING"`
- `src/client/ui/Hud.luau:870`: `"Sell shells to keep cracking"` -> `"Sell shells to keep hatching"`
- `src/client/ui/Hud.luau:1128`: `Text = "CRACK!"` -> `Text = "HATCH!"`
- `src/client/ui/Hud.luau:1455`: `"Tap to crack!"` -> `"Tap to hatch!"`
- `src/client/ui/Hud.luau:1464`: `"Crack eggs at your nest!"` -> `"Hatch eggs at your nest!"`
- `src/client/ui/Hud.luau:1595`: `" to crack"` -> `" to hatch"`
- `src/client/ui/Hud.luau:78`: `Jackhammer = "RAINBOW" }` -> `Jackhammer = "WHISTLE" }`
- `src/client/ui/Hud.luau:78`: `Hammer = "MALLET", SteelHammer = "GOLDEN"` -> `Hammer = "COLLAR", SteelHammer = "TREATS"`
- `src/client/ui/Hud.luau:948`: `"2", "hammer", "MALLET", 2)` -> `"2", "hammer", "COLLAR", 2)`
- `src/client/ui/CollectionPanel.luau:972`: `"Crack more eggs to find out what is inside."` -> `"Hatch more eggs to find out what is inside."`
- `src/client/ui/CollectionPanel.luau:1060`: `big(1, "pickaxe", "Solo finds"` -> `big(1, "star", "Solo finds"`
- `src/client/ui/CollectionPanel.luau:1065`: `stat(4, "Eggs cracked"` -> `stat(4, "Eggs hatched"`
- `src/client/ui/CollectionPanel.luau:165`: `Icon = "geode",` -> `Icon = "egg",`
- `src/client/ui/CollectionPanel.luau:926`: `UI.icon(dot, "geode", 34` -> `UI.icon(dot, "egg", 34`
- `src/client/ui/ResultsPanel.luau:275`: `"Eggs cracked:"` -> `"Eggs hatched:"`
- `src/client/ui/ShopPanel.luau:229`: `local unit = if h.Hold then "pulses/s" else "hits/s"` -> `local unit = if h.Hold then "pulses/s" else "taps/s"`
- `src/client/ui/ShopPanel.luau:245`: `local nowUnit = if now.Hold then "pulses/s" else "hits/s"` -> `local nowUnit = if now.Hold then "pulses/s" else "taps/s"`
- `src/client/ui/ShopPanel.luau:232`: `Effect = "Power " .. h.Damage` -> `Effect = "Find power " .. h.Damage`
- `src/client/ui/ShopPanel.luau:243`: `"  (yours: Power "` -> `"  (yours: Find power "`
- `src/client/ui/ShopPanel.luau:246`: `spec.Consequence = "Power " .. now.Damage` -> `spec.Consequence = "Find power " .. now.Damage`
- `src/client/ui/ShopPanel.luau:233`: `Note = if h.Hold then "Hold to crack eggs at your nest." else "Crack eggs at your nest."` -> `Note = if h.Hold then "Hold to hatch eggs faster at your nest." else "Helps you hatch eggs at your nest."`
- `src/client/ui/ShopPanel.luau:235`: `Confirm = "Buy this tool?"` -> `Confirm = "Buy this gear?"`
- `src/client/ui/ShopPanel.luau:278`: `Effect = "Cracks eggs for you automatically."` -> `Effect = "Hatches eggs for you automatically."`
- `src/client/ui/ShopPanel.luau:281`: `Confirm = "Buy this machine?", Consequence = "It is installed at your station right away."` -> `Confirm = "Buy this nest upgrade?", Consequence = "It is set up at your nest right away."`
- `src/client/ui/ShopPanel.luau:372`: `"Eggs take " .. tier.HP .. " hit" .. (if tier.HP == 1 then "" else "s") .. ". Pets from "` -> `"Eggs need " .. tier.HP .. " tap" .. (if tier.HP == 1 then "" else "s") .. " to hatch. Pets from "`
- `src/client/ui/ShopPanel.luau:44`: `"Tools"` -> `"Gear"`
- `src/client/ui/ShopPanel.luau:53`: `"Tools"` -> `"Gear"`
- `src/client/ui/ShopPanel.luau:464`: `"Tools"` -> `"Gear"`
- `src/client/ui/ShopPanel.luau:682`: `"Tools"` -> `"Gear"`
- `src/client/ui/ShopPanel.luau:53`: `"Machines"` -> `"Nests"`
- `src/client/ui/ShopPanel.luau:466`: `"Machines"` -> `"Nests"`
- `src/client/ui/ShopPanel.luau:483`: `"Machines"` -> `"Nests"`
- `src/client/ui/ShopPanel.luau:589`: `"Machines"` -> `"Nests"`
- `src/client/ui/ShopPanel.luau:670`: `"Machines"` -> `"Nests"`
- `src/client/ui/ShopPanel.luau:261`: `Thumb = iconThumb("hammer"),` -> `Thumb = iconThumb("boostLuck"),`
- `src/client/ui/ItemView.luau:22`: `Hammer = "hammer", SteelHammer = "hammer", Jackhammer = "jackhammer",` -> `Hammer = "boostLuck", SteelHammer = "boostCoins", Jackhammer = "boostSpeed",`
- `src/client/ui/ItemView.luau:23`: `AutoCracker = "machine", HydraulicPress = "press", IndustrialCrusher = "crusher",
}

local TOOLS` -> `AutoCracker = "queue", HydraulicPress = "egg", IndustrialCrusher = "sparkle",
}

local TOOLS`
- `src/client/ui/ItemView.luau:94`: `FALLBACK_ICON[id] or "hammer"` -> `FALLBACK_ICON[id] or "star"`

## Not changed (needs owner or another helper)
- `src/client/ui/UI.luau` KIND_ICON (toast kinds `geode`/`material` draw geode/rock icons) and the default icon `rock` in UI.luau; the drawn `hammer`/`rock`/`geode`/`pickaxe` icon art itself.
- `src/client/ui/HudArt.luau` Hammer slot is an uploaded hammer.png (UPGRADE tile); needs a new pet-gear picture.
- 3D shop/lobby models for the upgrades still look like hammers and machines (`Tool_Hammer`, `Machine_*` kit models); the shop now draws pet icons instead, the lobby pedestal preview is unchanged.
- `src/server/DevCommands.server.luau` `/event rock` (developer command, not shown to players).

