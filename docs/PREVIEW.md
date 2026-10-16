# Offline preview renderer (no Studio needed)

`tools/preview/` runs the **real game code** (src/server Main + src/client Main) headlessly
against a mock Roblox API in Lune and draws what it builds: the 3D world with three.js and
the GUI as Roblox would lay it out, in headless Chromium. Use it for screenshots of the UI
and world on several devices. It is an approximation of Roblox, not a Studio playtest:
nothing it shows counts as Studio-verified.

Ported from the SWARM preview tool (same owner); the runtime and renderer are generic.

## Setup

```
bash tools/preview/setup.sh      # once per machine, idempotent
```

Needs Lune 0.10.4 (`/tmp/ctr-tools/lune/lune` from `tools/setup_tools.sh`; falls back to
`/tmp/sh-tools`; override with `CTR_TOOLS=...`), Node, three.js (`npm install` into
`tools/preview/node_modules`) and Google Fonts with measured widths in
`tools/preview/.cache/fonts`. Chromium comes from the global Playwright install
(`/opt/pw-browsers`; `CTR_CHROMIUM=<path>` overrides). Never run `playwright install`.
`node_modules/`, `.cache/` and `out/` are gitignored.

## Commands

```
bash tools/preview/render.sh lobby --device phone-1108            # -> tools/preview/out/lobby-phone-1108.png
bash tools/preview/render.sh hunt --device phone --out /tmp/hunt.png
bash tools/preview/render.sh lobby,party,hunt,results,shop,collection,settings \
     --devices phone-1108,phone,phone-portrait,pc --outdir tools/preview/out/matrix
bash tools/preview/render.sh party --set view=party               # scene arguments
bash tools/preview/render.sh --all                                # every scene x pc/phone/phone-portrait/phone-1108
python3 tools/preview/check_layout.py tools/preview/out/matrix    # text overlap / off-screen / cut checks
bash tools/preview/render_list.sh tools/preview/ui_v2.list docs/ui_v2/renders [pc,phone-1108,phone-portrait] [--only text] [-- --set textsize=Largest]
                                                                   # a named shot list (UI v2 screens) on several devices
```

Options: `--set key=value` (scene arguments), `--seed N`, `--studio`
(RunService:IsStudio() = true, so Profiles uses the `_Studio` store name in the in-memory
mock), `--no-coreui` (hide the ghost of Roblox's top-left buttons), `--max-time S`
(simulated seconds, default 300), `--ref GIT_REF` (render a committed version from a clean
snapshot), `--repo PATH`. With `--outdir` / `--json` the scene JSON lands next to each PNG;
`check_layout.py` reads those.

Devices: `pc` 1920x1080, `laptop` 1366x768, `phone` 844x390 (notch insets 47 px),
`phone-portrait` 390x844, `phone-1108` 1108x512 (the owner's Android-style phone),
`phone-small` 667x375, `iphone` 852x393 (real-device quirks, Text size Largest),
`tablet` 1024x768. `--set textsize=Medium|Large|Larger|Largest` sets the Roblox Text size
accessibility setting.

## Scenes (`tools/preview/scenes/*.luau`)

Every scene boots the real server (`Main.server`: remotes, lobby world, Profiles on an
in-memory DataStore, PartyService, MatchService, Economy, Gallery) and then the real client
(`Main.client`: HUD, panels, PileView). Profile changes are made on the server
(`Profiles.get` + `Profiles.changed`), so the client gets the real `publicView`. Actions go
through the real RemoteEvents (`PartyAction`, `Strike`, ...).

| Scene | Shows |
|---|---|
| `lobby` | lobby world, HUD, camera behind the player at the spawn. `--set cash=N`, `--set view=wide` |
| `party` | PARTY panel. `--set view=none` (default, no party), `solo` (party of one), `party` (Ava + Ben invited and joined, Ava ready), `invite` (Ava invited you) |
| `hunt` | solo hunt started with `PartyAction("Solo")`, past the 3 s countdown into Searching, camera at the pile. `--set phase=countdown`, `--set cracked=N` (cracks rocks first through `Strike`), `--set tutorial=on` (practice pile), `--set tier=Quarry`, `--set view=wide` |
| `results` | a real hunt cracked to the end through `Strike` (the player walks to the nearest exposed rock and strikes at the hammer's rate), then the results screen. `--set stage=reveal [--set at=1.6]` the geode reveal, `--set mode=tutorial` practice pile, `--set mode=party` Ava and Ben crack too |
| `rocks-views` | V3 acceptance pictures driven through the real HUD button and RockAction. `--set view=A` pickup arc, `B` 5/5 and TAKE TO TABLE, `C` deposit, queue and hammer at the plate (`t=` seconds into the hold, `cam=side`), `D` COLLECT ROCKS, `G` machine running while at the pile (`machine=`, `t=`, `cam=table`), `H` geode opening on the plate (`t=`), `L` + `step=pickup\|carry\|deposit\|crush\|rubble` tutorial hints, `W` four stations, `pile` the mound (`cam=close`); `tool=` handheld for C |
| `shop` | SHOP panel. `--set tab=Tools\|Storage\|Tiers\|Gallery`, `--set cash=N` |
| `collection` | GEODES panel with made-up specimens (`GeodeGen.roll` shapes) in the real profile. `--set count=N` (0 = empty state), `--set tab=Geodes\|Index\|Stats`, `--set detail=1` opens the first geode |
| `settings` | SETTINGS panel |
| `petflair` | rare hatch banner + fireworks (`--set banner=local\|global\|none`, `at=S`), lobby name tags (title + tower floor; `view=follow` or side view), hatch reveal by rarity (`reveal=Common\|Rare\|Epic\|Legendary`, `rt=S`); prints the first-find coin check (PETINDEX) |
| `_tools` | the held tool on the stand-in avatar at a table-height work surface (open ground). `--set tool=Hammer\|SteelHammer\|Jackhammer`, `--set t=S` (seconds into a stroke; omit = carry pose), `--set cam=side\|front\|back`, `--set rig=R6` |
| `_specimens` | GeodeModel specimens at full, Lod (gallery shelf) and Tiny detail side by side. `--set n=N` |

UI v2 options (docs/ui_v2/REPORT.md): `collection --set tab=Display|Records`, `--set records=fail` (RECORDS PASS: the
unavailable state), `--set place=1` (Display picker); `shop --set confirm=1` (CONFIRM PASS: purchase confirmation);
`party --set view=invitetab|expired` (INVITE-EXPIRY PASS); `hunt --set toast=feedback` (NOTICES PASS: coalescing);
`lobby --set eye=seller --set prompt=on [--set rubble=0]` (the sell card). HUD menu tiles are found by name
(`C.tap("^SHOP$")` falls back to the tile named Shop).

`--set uiscale=real` (any scene booted with `C.boot`): the renderer ignores a `UIScale` parented to a `ScreenGui`, so
by default every UI layer is drawn at scale 1; this option moves each layer's contents into a scaled full-screen
Frame so the picture shows the real device size (docs/ui_v2/REPORT.md section 5). `ui_notices` (NOTICE-HEADER /
SCALE checks, `--set menu=`, `--set count=`, `--set dialog=1`); `party --set view=starting|startcheck` (STARTING).

Helpers for new scenes: `scenes/lib/ctr.luau` (`C.boot{profile=fn, others={{"Ava",2}}}`,
`C.makeCharacter`, `C.watchMatch`, `C.startSolo`, `C.waitPhase`, `C.crackUntilFound`,
`C.fakeSpecimens`, `C.fireServer`, `C.tap("^SHOP$")`, `C.findText`, `C.followCamera`,
`C.cameraAt`, `C.settle`). Scenes also get `preview` (`advance(s)`, `addPlayer(name, id)`,
`fireServerAs(player, remote, ...)`, `fireClient`, `click`, `findGui`, `shared(name)`,
`server(name)`, `client(name)`, `camera`, `args`). Files starting with `_` are skipped by `--all`.

## Limits (what is approximated)

* **Avatar**: the mock has no default Roblox avatar, so `C.boot` builds a blocky R15-shaped
  stand-in (HumanoidRootPart, Head, torso, arms, legs, RightHand, Humanoid). No animations.
* **Camera**: the default Roblox follow camera is not simulated; scenes place the camera
  (`C.followCamera`, `C.cameraAt`).
* **Physics / input**: no physics (parts stay where code puts them), raycasts hit nothing,
  remotes and signals are delivered immediately, sounds are silent. One local client;
  other players (`addPlayer`) have characters and server-side profiles but run no client.
* **Rendering**: textured materials (Concrete, Slate, Wood, Grass ...) are flat colours,
  Decals are not drawn, Terrain is not drawn, ParticleEmitters are a few
  static sprites, images (rbxassetid) are striped placeholders, Highlights are fill +
  outline. Text metrics can differ from Roblox by a pixel or two.
* **Fonts**: FredokaOne and LuckiestGuy (UI v2 titles) are the real fonts; GothamBold is drawn with Montserrat (substitute).
* **DataStores** are in memory (empty on every run); no MarketplaceService purchases.
* **Highlight in Workspace**: a Highlight with no Adornee applies to its parent in Roblox,
  and Workspace is a Model, so the renderer outlines the whole world while PileView's
  highlight sits in Workspace without an Adornee (it warns about it). `--set wshighlight=off`
  leaves that case out of the picture.

* **SurfaceGuis** (since 2026-10-10, `renderer/page/surfaces.js`): laid out like ScreenGuis on a canvas of face studs x
  PixelsPerStud (or CanvasSize), painted into a texture (Frame / TextLabel / ImageLabel backgrounds, UICorner, UIStroke,
  text with TextStroke / contextual UIStroke outlines; images and `rbxthumb` avatars are neutral placeholders) and put on a
  one-sided plane on the adorned face, depth tested. LightInfluence < 0.5 is drawn at its own colours (inverse of the page
  tone mapping), >= 0.5 is lit. Each render also writes `<png>.surfaces.json`: per SurfaceGui the visible and unoccluded
  text pixels. `python3 tools/preview/check_signs.py [--selftest]` uses it to fail a lodge sign or board whose text is
  missing, facing away or covered (regression `sign-faces`). Lighting.ExposureCompensation is applied (2^EV).

How it works in more detail (GUI layout rules, lighting, export format): the runtime is in
`tools/preview/runtime/` (`main.luau`, `mock/*`), the renderer in `tools/preview/renderer/`.
