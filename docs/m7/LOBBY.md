# Master Prompt 7, Pass B: lobby world

> Superseded 2026-10-10: this courtyard is no longer built; the lobby is the Prospector Lodge
> (docs/lodge/INTEGRATION.md). Kept for history.

Offline only (Lune preview + Rojo build). Nothing here is Studio-tested. SurfaceGui text (signs, screens, records rows,
plaques) is not drawn by the preview, so text was checked numerically by the `signs` scene, not by eye.

Pictures: `docs/m7/lobby/<view>-<device>.png` (pc, phone-1108), first-person player-eye views
(`bash tools/preview/render.sh lobby --set eye=<view> --set display=4`): `spawn`, `start`, `upgrades`, `collection`,
`pocket` (unclaimed display pockets), `owned` (the player's 20-slot cabinet with 4 real specimens), `seller`, `records`.
`before/` holds the same eye views of the rejected version.

## What changed (brief sections 3-6, 12)

| Area | Before | Now |
|---|---|---|
| Palette / materials | Cobblestone + pavement + joint grids, cream/brass trims, navy steel, neon lantern glass | one palette in `LobbyBuilder.P`: warm wood, slate stone, charcoal metal, pale labels, sage green, ONE muted amber; calm Concrete plaza + one lighter route, no tile joints, no pad borders |
| Lights | ~9 PointLights, neon lanterns on every post, 6 lamp piers | 5 soft PointLights (gantry, cabinet, records, seller lamp, one spawn lantern), matte glass, no repeated yellow strips |
| Foliage | Kit.planter round balls, cube trees, Court_Tree, flower planters | one faceted family: Court_Tree + new `Lobby7_ShrubBed`, retoned sage, no flowers |
| START HUNT (ahead) | gabled pavilion booth, counter, back screen | waist-high `Lobby7_StartTerminal` (Blender) on a slate pad with a stand-spot ring, one slim timber/charcoal sign gantry with START HUNT, one small emblem, one sloped readiness screen ("SOLO OR PARTY / UP TO 4 PLAYERS") |
| UPGRADES (left) | canopy booth, tool wall of catalog tools, crates | short `Lobby7_ToolCounter` (Blender): steel worktop, vice, pegboard backdrop with generic tool silhouettes, small awning + UPGRADES sign, order screen; ONE preview pedestal beside it (`CT_Rocks_UpgradePedestal` / `PreviewAnchor` / `PreviewLabel` kept, `UpgradePreview` unchanged and working) |
| COLLECTION (right) | canopy booth + display bank + two front example crates | open corner: the 4x3 cabinet module full of decorative examples is the silhouette (COLLECTION on its crown, DISPLAY EXAMPLES plaque), short `Lobby7_InfoLectern` with the prompt, ONE hero pedestal toward the wall with an EXAMPLE GEODE plaque; front blocks removed |
| Perimeter | 16 full-height dark "Open alcove" cabinets with shutters | unclaimed = small two-step stone pedestal with one "Open display" label; claimed = cabinet built to the owner's real capacity (`SetCapacity`: 3 = 3x1 waist stand, 6 = 3x2, 12 = 4x3, 20 = 5x4), eye-level rows filled first; low (2.2 stud) boundary wall, broken near row of rock masses, planting pockets |
| Crates | three corners | one service corner (south-west, behind the seller) |
| Seller | big yellow hopper + chute + placard beside Upgrades | compact `Lobby7_SellChute` (Blender) at the west utility edge (-32.4, 24), off the Start Hunt axis, one SELL RUBBLE sign, one status lamp |
| Records | 24 x 11 dark wall, dark boards | open timber frame on a stone sill, pale boards with charcoal text, thin accent bar, one RECORDS header |

Specimens: cabinets, owner pockets and the hero pedestal use `GeodeModel.onStand` (merged from main), the same
presentation as real owner specimens. Examples are tagged `Decorative`, have no Id and live in no profile.

## Contracts kept (grepped before changing)

- Start: Part `Cabinet` with the "Start Hunt" prompt, Panel `Party`, range 16.
- Upgrades / Collection: Part `Counter`, Panel `Shop` / `Collection`, OnePerButton.
- Seller: Model attribute `Hopper`, child `Body` with ProximityPrompt `SellPrompt` (attribute `Sell`, ActionText "Sell Rubble");
  EconomyService / PileView / HUD marker unchanged. Same endpoint, no second sell system.
- Gallery: `CT_Rocks_Alcove_<i>` models, `Floor` part (client "YOUR GALLERY" marker), `SideL`/`SideR`/`ShelfLight` direct children
  (Cosmetics theme), `InspectPrompt`/`PlacePrompt`, Alcove fields `Index, Root, Plate, Slots, SetLabel, Shutters` (now empty) plus new
  `SetCapacity`, `LabelDepth`. 16 pockets = `Config.Gallery.Alcoves` = `Config.Places.LobbyMaxPlayers`; capacities 3/6/12/20 from
  `Profiles.displaySlots` (unchanged). Frames unchanged, so no allocation moves.
- `BoardMounts` / `Mount_<id>` / `Mount_Header` read by LobbyBoards. Kit meshes are non-colliding; every solid piece has an invisible
  blocker; decorative pieces carry `CameraIgnore`. Each Blender piece has a Part stand-in (REPLACE) when the kit is not loaded.

## Records in Studio (section 12)

Cause (from source, not from the recording): in a Studio test whose DataStores are unreachable, `GetOrderedDataStore` or the read can
fail with a message that does not contain "403"/"API"/"Studio", so `LeaderboardService` set status `error` and the boards showed
"Could not load this board / Trying again soon" every refresh. Now, in Studio only: if any profile in the server is session-only
(SAVES OFF) or any store open / read fails, status becomes `unavailable`, the board shows one note "Records unavailable in this Studio
test", it fires once and stops reading for that session. No rows are invented; writes stay off (offline profiles are never ranked).
Production keeps `error` with the last good rows and retries. The old "local" (this-server-only) state is removed.

## Checks (offline)

- `bash tools/check.sh`: zero diagnostics, 117 rule tests, both builds.
- `bash tools/run_regressions.sh`: all checks pass (see STATUS).
- `check_lobby.py`: SpawnAisle, NorthAisle, UpgradesFront, CollectionFront and new SellerFront CLEAR.
- `signs`: 27 signs in range; START HUNT / UPGRADES / COLLECTION / RECORDS present once; long owner name truncates inside its plate.

## Not done / limits

- Branding: no world sign carried the game name, so nothing to rename in the world. The kick text in `Profiles.luau` ("Crack the
  Rocks could not load your save...") is player-facing but outside this pass.
- UI text still says "walk to an orange SELL hopper" (`Main.client.luau`, `ResultsPanel.luau`): true in hunts (arena hoppers are still
  amber), not for the lobby bin. Owner of the UI files should reword ("SELL RUBBLE bin").
- Readiness screen text is static and truthful; it does not show live party state.
- In the preview the boards and sign faces look blank (SurfaceGui not drawn); pale board faces read as cream panels there.
- Not verified in Studio: collisions, camera near the gantry, prompt choice between nearby destinations, real lighting / textures,
  lower graphics levels, a real saved specimen placed / removed / restored after rejoin.
