# Lodge visual pass (owner brief 2026-10-10, VISUAL_PASS_BRIEF.md)

**Status: offline preview only. Nothing here is Studio-tested.** Every picture below is the Lune + three.js preview
(docs/PREVIEW.md), an approximation of Roblox. The brief asks for screenshots inside Roblox; those still have to be
taken by the owner (steps at the end). No owner Studio screenshots were attached, so "blank" was judged from the
preview renders the owner had seen (docs/m10/acceptance/01-spawn-pc.png, docs/lodge/renders/game/*).

Renders: `docs/lodge/renders/visual_pass/before/` (commit 17dc7ea, drawn with the new renderer so text shows) and
`after/`, same cameras, `pc` and `phone-1108`: `spawn` (entrance toward START HUNT), `boards` / `boardswins` (each board
close enough to read), `upgrades` (old close camera) and `upgradessign` (a step back, sign in view), `collection`,
`exterior`. `after/*-seeded-*` = the boards with PREVIEW TEST DATA (made-up players 1001.., `--set boards=seed`, only in
the preview scene) to judge five full rows; the plain `after/boards*` show the real empty state.

## 1. Blank signs and boards: root cause per surface

| Surface | What the code did | Why it looked blank | Fix |
|---|---|---|---|
| All six (UPGRADES, COLLECTION, START HUNT, FIND THE GEODE, SOLO FINDS, COMPETITIVE WINS) in the owner's pictures | SurfaceGuis existed, `Enabled`, on the correct face | **The preview renderer never drew SurfaceGuis** (`exporter.luau`: `R.note("SurfaceGuis are not drawn")`), and it skips fully transparent parts, which is what every sign text part is. Every screenshot showed the bare kit sign wood and the charcoal kit board face. | Renderer now draws SurfaceGuis (below). |
| Face / orientation (all) | `faceText` puts a part 0.05 in front of the kit face, turned half a turn, SurfaceGui `Face = Back` (+Z) | Not a cause. The pipeline map Blender (x,y,z) -> Roblox (-x,z,y) has determinant +1 (a rotation, no mirror), so catalog "front = -Z" holds. Verified in the render: SurfaceGuis are drawn one-sided, so a flipped face would draw nothing; all seven face their readers (also numerically in the `signs` audit). | Comment in `faceText`; regression. |
| Covered by geometry | text 0.05-0.06 in front of the kit faces | Not a cause for the six titles (100% of their text pixels visible). It **was** the cause for the small DISPLAY EXAMPLES plaque: the middle example geode covered "DISPLAY". | Plaque raised to y 8.55. |
| Contrast (all titles) | cream ink (255,240,208), no outline, on brown sign wood; RECORDS-era Landmark fill 55-75% | Real weakness in game too: low-contrast cream on mid-brown, small for the board | White ink, black UIStroke outline (6 px at TextSize 80, `SignLayout.Outline`), Landmark fill 60-88%. |
| SOLO FINDS / COMPETITIVE WINS headings | a 1.5-stud band, cap 0.6 studs | Real weakness: tiny on an 11.5-stud board | New `Heading` preset, 10.8 x 2.0 band, cap 0.73-0.90 studs. |
| Board faces | `createLodgeContent`: rows hidden until data; with no rows only a small note in the middle; `LightInfluence 0.2` | Data path is correct (LeaderboardService -> `Leaderboards.get`, Solo = Stats.SoloFinds, Wins = Stats.MultiplayerWins, OrderedDataStores `CTR_LB_*`, Studio `_Studio`). In an empty / loading / Studio state the face was a black rectangle with one small line: "unexplained black rectangle". Init: `LobbyBoards.build` runs from Main after the lobby is built; no errors in any preview boot. | Five permanent rank slots (open slot = rank + dash, never an example name), avatar, name, real score, a status line that is never empty (loading / empty / Studio unavailable / error + retry), `LightInfluence 0`, `pcall` around drawing so one board cannot blank the other. |

Not checked (needs Studio): real font metrics, avatar thumbnails (`rbxthumb://`), SurfaceGui sharpness at distance,
real lighting on `LightInfluence 0` faces, import axes of the big building mesh.

## 2. Changes

**Signs** (`SignLayout.luau`, `KitPlace.luau`, `LodgeBuilder.luau`): `SignLayout.Outline` + `outlinePx`, `Heading` preset,
Landmark range 60-88%; `KitPlace.outline` / `signText(..., outline)`; every lodge Landmark / Heading is white with a black
outline.

**Boards** (`LobbyBoards.luau`, state only from `LeaderboardService`, unchanged): see table; `LobbyBoards.lodgeStatus`.

**Lighting** (`LodgeLight.luau`, `LodgeBuilder.luau`): inspected project Lighting (Ambient 0.42 grey, sun ColorShift warm,
Bloom 0.06 / threshold 2.4, ColorCorrection near neutral, Atmosphere), glass transparency 0.7, the roof shading the hall,
14 local warm PointLights and the client fill. The orange came from the amber client fill (176,150,118), all-orange hall
fills and the cream floor wash. Now: neutral fill (156,153,147) + exposure 0.3; the four big hall fills near-neutral
daylight (255,246,232) at the same or lower brightness, chandelier 1.0 -> 0.8; lanterns stay warm. Lights added: 2 small
ones at the collection counter (net +2, 16 total). Bloom and colour correction untouched. Global Lighting untouched
(hunts share it).

**Floor**: paint only (`KitPlace.tone` on the building mesh pieces): grout slab (130,123,113) -> (162,154,143), stones
(167/180) -> (180/186) warm grey; `FloorWarmWash` overlay removed. Geometry and colliders unchanged.

**Collection counter**: no Highlight / SelectionBox exists in the lobby (grepped). The bright outlines were each example
geode's chalk rim lit from a hand's width away by its own fill PointLight (GeodeModel FillLight). Examples now built with
`NoLight` and the rim toned toward the rind (geometry, thickness and recessed crystals unchanged); the extra cradle
stand (`onStand`) is gone, specimens sit on the kit pedestal; cabinet glass 0.7 -> 0.86 transparency + one soft light
inside; one soft wash from the front lights the crystals.

**Exterior**: plaque lettering (above), two kit wall lanterns on the broad plaster bays, dark timber nosing on the three
step edges, a stone landing as wide as the steps joining the path, four grouped rock + plant clusters at the corners and
sides (off the path, one collider each). Porch rails are the kit's own and already match.

**Preserved**: all contracts in INTEGRATION.md (Counter / Cabinet / SellPrompt / BoardMounts / pedestal names), prompts,
economy, party/hunt flow, ClearZones (open floor), no new gameplay areas.

**Renderer** (`tools/preview`): SurfaceGuis drawn on their faces (`renderer/page/surfaces.js`), unlit GUI at nominal
colours, `ExposureCompensation` applied, `<png>.surfaces.json` with visible / unoccluded text pixels.

## 3. Checks actually run (offline)

- `bash tools/check.sh`: zero diagnostics, 155 rule tests (new sign tests), build OK.
- `bash tools/run_regressions.sh`: ALL 46 CHECKS PASS (45 before + the new `sign-faces`).
- `python3 tools/preview/check_signs.py --selftest` (new regression `sign-faces`): breaks START HUNT three ways (face
  flipped, plank in front, disabled) and catches all three; then all 8 lodge surfaces PASS with 100% of their text
  visible from the player views.
- `signs` scene: fills in range, every lodge landmark white + outlined, enabled, unlit, facing its readers; both boards
  show 5 slots and a non-empty status for loading / ok / unavailable / error.
- Looked at every before/after PNG on pc and phone-1108.

## 4. Owner steps (Studio)

1. Open the built place, Play solo. From the spawn: START HUNT, SOLO FINDS, COMPETITIVE WINS readable, white with black
   outline. Walk to UPGRADES, COLLECTION, outside the door (FIND THE GEODE).
2. Boards: in Studio with saves off they must say "Records unavailable in this Studio test" with five numbered empty
   slots; in a published server "Loading records..." then rows or "No ... yet - be the first!".
3. Judge the hall brightness and colour against 00_Approved_Lobby.png; tune `FILL_*` in `src/client/LodgeLight.luau` or
   the fill brightness in `LodgeBuilder.buildDecor` if needed. Check on the phone.
