# Lobby map hooks (hand-built lobby)

The owner builds the lobby by hand in Studio as **`Workspace.FTP_Lobby`** (ground top y = 3; a street layout with
the spawn and queue pads at the +Z end and the EGG SHOP, HATCH STAND and PET TOWER at the -Z end). The game code finds the pieces it needs **by name** and adds missing attributes, attachments and prompts
itself. All names live in one place, `src/shared/MapNames.luau`; change a name there and the code follows. Where a
hook lists several names, the first one is the FTP_Lobby name and the others are also accepted.

## How the code decides which lobby to use

- A Model directly under Workspace named **`FTP_Lobby`** (or `Lobby` / `PetPark`) is the hand-built lobby. When it
  exists, the code builds **no** `CT_Rocks_Lobby` at all (no procedural park, no old lodge, no code spawn pad, and
  the client's park camera box stays off). It only adopts the hooks below (`src/server/MapHooks.luau`, called from
  `LobbyBuilder.build` and `LobbyBuilder.ensureSpawn`). Its few helper pieces go in `Workspace.CT_Rocks_LobbyHooks`.
- The code never moves or deletes the owner's parts. It only adds attributes, prompts, attachments and labels.
  Decor (`Lanterns`, `Cliffs`, `Waterfall` with its own script, `EggShop.DisplayEggs`) is left alone.
- Without one, the procedural park (`ParkBuilder`) is built as a simple fallback with the same names.
- A missing piece never breaks the game. The server prints one `[MapHooks] lobby map has no ...` warning and skips
  that feature.
- Names are searched anywhere inside the map, so folders and models can group things (FTP_Lobby uses `QueuePads`,
  `Leaderboards`, `Plots`, `Buildings`, `Jungle`, `Ground`).

"Front" means the part's front face (LookVector). *auto* = the code adds it when it is missing.

## The hooks

| Name (FTP_Lobby path) | What it is | What it needs |
|---|---|---|
| `LobbySpawn` | Where players appear, and where they are sent back after a hunt | A SpawnLocation (any SpawnLocation in the map also works). |
| `QueuePads/QueuePad1..4` | Hunt queue pads | A Model whose touch part is named `Pad` (or a single Part). *auto* on the touch part: `HuntPortal = true`, `PadIndex = n`, CanTouch. Pads light up one per queued player. |
| `QueuePadN/Countdown` | Each pad's countdown sign | SurfaceGuis (front and back) with a TextLabel `Text`. The queue text ("STEP ON TO PLAY", then "HUNT IN 12s (2/4)", 20 s countdown) is copied into every one. |
| `QueueBoard` (optional) | One extra queue sign | A Part (*auto* TextLabel `QueueText`). If the map has none, the code makes a hidden one for the queue service and mirrors it onto the Countdown signs. |
| `Leaderboards/RarestPetBoard`, `Leaderboards/TowerFloorBoard` | RAREST PET and HIGHEST FLOOR boards | A `Board` part with a SurfaceGui and a TextLabel `Text`. The title and the top 5 rows ("1. Name   12,345") or the status line are written there as text. A plain part without a label gets drawn rows over its front face instead. |
| `Plots/Plot1..12` | Player plots, one per player for the session (1-6 left of the street, 7-12 right) | A Model with PrimaryPart `Floor` (also `Hut`, decor). The plot faces its `PlotSign` (the street side), and pets face that way. |
| ↳ `Dome1Base`, `Stand1`, `Stand2` | Where display slots 1, 2 and 3 stand (slot 1 under the big glass `Dome1`) | Parts; the pet stands on the top face. Optional attribute `PetScale`. A small plaque shows the pet name; an empty spot shows "+ ADD PET" (opens the Pet Book). Display slots 4 and up wander on the Floor. |
| ↳ `PlotSign` | Owner's name ("Name's Park" / "FREE PLOT") and the like count | A part with a TextLabel `Text`. *auto*: the LIKE ProximityPrompt (attribute `LikePlot = n`) goes on this sign, or on an optional `LikePost` part. One like per visitor per plot per server, never your own (server-checked). The most-liked plot gets a gold crown 20 studs over its Floor. |
| `Buildings/EggShop` | Egg shop hut | Any parts plus a `Sign` (`DisplayEggs` is decor). *auto*: a ProximityPrompt on its `Counter` part, else on the `Sign`. RobuxService turns the first prompt in the hut into the shop door. |
| `Buildings/HatchStand` | Public hatch stand | *auto* on its highest part (signs skipped): `HatchStand = true` and an Attachment `HatchPoint` on the top face. The hatch show plays there. |
| `Buildings/TowerEntrance` | PET TOWER door | Best: a Part named `TowerPortal` inside (the doorway). *auto*: `TowerPortal = true`, CanTouch. Without one, an invisible 8-stud-tall touch box `TowerPortal` is added in the middle of the entrance. |
| `SecretEgg` | Hidden badge egg | A small part. *auto*: `SecretEgg = true` and a ProximityPrompt "Take". BadgeService does the rest. |
| `WhatsNewBoard` (optional) | WHAT'S NEW board | A part (or one with a TextLabel `Text`); the lines of `src/shared/WhatsNew.luau` are written there. The pop-up works without it. |
| `VoidStatueSpot` (optional) | The giant Void Dragon statue ("1 in 1000") | A Part; the statue stands on it, facing the Part's front. Without it the statue stands near the spawn. |
| `StarterEggSpot` (optional) | A new player's free starter egg | A Part; without it the egg sits 16 studs in front of the spawn. |
| `UpgradesSpot`, `PetBookSpot`, `SellerSpot` (optional) | Where the code builds its UPGRADES, PET BOOK and SELL CANDY stalls | A Part each; the stall stands on its bottom and faces its front. FTP_Lobby has none yet, so those stalls are not built there. |
| `Jungle`, `Ground`, `Lanterns`, `Cliffs`, `Waterfall` | Scenery | No hooks; never touched. |

## Notes

- Lighting: the lobby is always daytime (project Lighting, no day/night cycle).
- Nothing here is verified in Studio. The offline preview scene `tools/preview/scenes/ftplobby.luau` builds a tiny
  FTP_Lobby-shaped stand-in with plain parts and checks every hook (`bash tools/preview/run_scene.sh ftplobby`).
