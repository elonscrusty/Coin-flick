# Lobby hangout (owner picks 2026-10-14)

Ideas 1, 2, 4, 6, 7, 8, 9, 10 from the lobby hangout list (no trading, no pet tricks). Rules and tuning:
`src/shared/Hangout.luau`. Server: `LobbyHangout` (prompt router, coins, sit spots, secrets, group),
`LobbyGames` (mini-games), `LobbyEvents` (hourly events), plus small changes in `GalleryService` (daily likes,
crown glow), `RobuxService` (`giftEgg`, rare alert for shrine hatches), `MatchService` (group luck), `Boards`
(MOST COINS). Client: `HangoutView` (sky beam, status card, Emote button).
Tests: `tests/test_hangout.luau` (rules), `tests/server/hangout.luau` (real modules on the mock).
Preview: `bash tools/preview/render.sh hangout` (`--set race=off` for the emote grid).

## What each idea does
1. Show-off plots: one like per visitor per owner per UTC day, saved in both profiles. Most likes today = crown +
   gold glow (Highlight) + crown light.
2. Rare-hatch alert: Epic / Legendary hatch in this server = sky beam over the egg shrine for 8 s. Shrine and Robux
   egg hatches now also send the gold banner (before: hunt finds only).
4. Mini-games, coin prizes, 600 coins per player per day across all games: Whack-a-Rock (20 s, 2 coins a hit,
   max 40). The Pet Race and Egg Toss were removed (owner picks 2026-10-14); leftover `RaceTrack` / `EggToss` models are deleted at server start.
6. Boards: MOST COINS (coins earned ever) joins RAREST PET and HIGHEST FLOOR.
7. Hourly events at :00 UTC, same in every server: Coin Rain -> Golden Rock -> Mystery Egg. Studio: `/event rain`,
   `/event rock`, `/event egg`.
8. Sit spots: any part named SitSpot*, Bench*, Swing*, DockSeat*, CampfireLog* gets a Sit prompt (an invisible seat
   on top when the part is not a Seat). Campfire gets a warm light (no flames: static props rule). Emote button:
   Wave, Cheer, Dance, Dance 2, Laugh, Point from the avatar's own Animate script.
9. Secret spots: HiddenEgg1..N pay 75 coins once each; LookoutChest pays 150 coins once a day.
10. Group (ONE merged reward with the first-five-minutes daily group gift): free pet once (Basic egg odds) +
    daily group coins (RetentionService.groupDaily) + 5% hunt luck, all from one membership check in LobbyHangout. OFF until `Retention.Group.Id` is set
    (REPLACE marker; the same id turns on the daily group coin gift from the first-five-minutes work). Optional GroupGift part = "Claim" prompt.
    Friends luck (+10% per Roblox friend in the server) was already in the game.

## Animation (owner ask 2026-10-14: "animate what you can, glowing aura etc")
`client/HangoutAnim`: golden rock bobs, turns, gold aura pulses, sparkles, shakes on hits; mystery egg bobs,
wobbles, colour-shifting aura, sparkles; whack rocks pop up with a bounce; rain coins glint; hidden eggs twinkle
softly; lookout chest glow breathes; campfire light flickers with embers; top plot glow breathes, crown sparkles;
sky beam shimmers; the stump has a pulsing "play here" light. 
the status card and emote grid pop in. Only within 140 studs of the camera (70 with Low Effects,
sparkles off with Low Effects), nothing in a hunt.

## Hooks the Studio helper places in the lobby (names matter, anywhere under the lobby map)
| Name | What | Notes |
|---|---|---|
| `WhackStump` (Model) | tree stump | top part gets the Play prompt; optional parts `Hole1..5` on top, else a ring |
| `CoinsBoard` | MOST COINS board | copy `RarestPetBoard`, rename, change the heading |
| `EventSpot` / `EventSpot1..N` | flat open spots on the plaza | coin rain centre, golden rock, mystery egg drops (36-stud rain radius) |
| `Bench*`, `Swing*`, `DockSeat*`, `CampfireLog*`, `SitSpot*` | seats | a Seat part or any part (seat made on top) |
| `Campfire` | campfire prop | gets a warm light |
| `HiddenEgg1..N` | small hidden eggs | tucked away, reachable on foot |
| `LookoutChest` | chest at the mountain lookout | reachable by parkour only |
| `GroupGift` (optional) | small sign/chest | "Claim" for group members |

## Leaderboard tree (2026-10-14)

A tree in the lobby centre shows the top 10 players by best pet POWER (Boards "Power", `PetStats.powerOfPet`), each
best pet as a live model on a branch with a glowing name / power sign (gold for #1, blue for #2-3).

- Rules: `src/shared/TreeBoard.luau` (tested in `tests/test_tree_board.luau`). Server: `src/server/TreeBoardService.luau`.
- Tree: a `LeaderboardTree` model in the lobby, else one from ServerStorage placed on a `LeaderboardTreeSpot` part,
  else a procedural stand-in (REPLACE). Branch points: attachments or parts `Branch1..Branch10` (Branch1 = top).
- Best-pet looks are saved as small cards in the `CTR_TreePets` DataStore (`_Studio` in Studio), at most one write per
  player every 2 minutes and only on change, so offline players' pets still show. Failed reads keep the last good tree.
- BATTLE pad: a `BattlePad` part in the tree model (or a made red pad) gets attribute `PvpPad = true`, which
  PvpService already turns into the Battle card.
- Signs are sized in studs, so far-away signs shrink instead of piling up.
- Void Dragon on top: an Attachment (or part) `DragonPerch` in the tree is where the Void Dragon statue stands, with
  no plinth (`VoidStatue.perch`; optional attribute `Height`). The stand-in tree has one on its crown. The client
  statue effects re-attach to the moved statue.
