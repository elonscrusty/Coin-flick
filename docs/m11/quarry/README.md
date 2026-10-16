# Hunt quarry polish (offline preview only, NOT Studio-tested)

Pictures (phone-1108, some pc): `fp-aim/` at the pile, `fp-table/` at the own table, `fp-sell/` at a sell bin,
`table-approach/` walking from the pile to the own table, `hopper-front/` a sell bin from the route, `overview/` the
worksite. `before/` = the same first-person views before this pass. The preview does not draw SurfaceGui text, so
the sign text itself is not visible in these pictures; it was checked numerically (below).

## Kit language (lodge)
Lodge palette from `blender/models/lodge_building.py` / `_lodgeparts.py` (`ArenaKit.L`): timber #A9693F, light timber
#BC7E4E, dark timber #70452D, iron #343639, sign wood #8A5532 with cream letters and a muted gold trim, stone #A79F90,
slate-brown roof #634437, plaster #E7D6B8.
- Tables (`StationModels.warm`): timber bodies with dark timber grooves, every frame / post / strap / rim dark iron
  (clean dark outline on the pale pad), lighter iron bolts. Plate, glass, beacon lens and accents unchanged.
- Sell bins (`ArenaKit` hopper): timber bin, dark timber skid and seams, iron straps and rim, framed sign-wood board.
- Shelters: the Storage_Nook and Quarry_ToolShelter kit meshes are recoloured by slot (`Kit.lodgeSkin`); the Part
  fallback uses stone slab, timber posts, plaster walls and a slate-brown roof.
- Crane: lodge timber, iron straps and plates, stone footings; the kit grab bucket recoloured the same way.

## Signs: causes found and fixed
| Sign | Cause | Fix |
|---|---|---|
| Table sign ("CRUSHING TABLE n") | The kit sign face is 1.34 x 0.98 studs: 16 characters with TextScaled made letters about 0.13 studs tall; the kit's cream rock icon stood 0.015 studs in front of the text plate (covering its lower half) | Lodge timber board 3.2 x 0.95 on two posts behind the table, above the shield (top 4.5) and clear of the beacon; text "TABLE n", fitted (SignLayout Plaque, cap 0.40 studs), cream on sign wood (5.3:1), owner colour on the trim |
| Nameplate (owner name) | 1.5 x 0.42 plate: below SignLayout's minimum readable size, any name would be cut to "P..."; names were upper-cased (wider) | 3.4 x 0.74 charcoal plate over the front plaque, between the iron posts and straps, 0.05 in front of them; Nameplate preset; names in their own case; owner accent 5:1+ on charcoal, idle "TABLE n" 8:1 |
| Idle table text | Grey (120,124,128) on dark: 2.3:1 | cream sign, light grey plaque (above) |
| SELL RUBBLE | TextScaled, no fit check | Framed lodge board (KitPlace.signBoard, Landmark preset, 65 % fill, cap 0.35), face 0.6 in front of its posts |
| Machine owner plate | "Owner · Machine" on one line overran the plate (machine name cut) | Two lines on a 4.4 x 1.3 plate, Placard preset |
| Pad number disc | One digit on a 1.5 stud disc filled a third of it (TextScaled) | Digit removed (the table number is on the table sign); the disc stays as the owner colour mark |
| All quarry text | `Kit.label` / station labels used TextScaled | `Kit.label` and the station labels use KitPlace.applyFit (explicit TextSize) and carry SignText / SignPreset / SignW / SignH |

Audit (a scratch scene over a running hunt with a machine, not committed): every SurfaceGui TextLabel in the arena is
enabled, faces its viewer (work spot eye for table signs, 9 studs in front for the others; dot 0.53-1.0), has at least
4.5:1 contrast against its background, fills its preset range, and an oriented-box ray test from the viewer to the
face hits no opaque part: 12 of 12 OK.

## Silhouettes
- Pile: the mound stands on a pale crushed-stone bed (192,178,154) instead of a dark dirt patch, so the grey rocks'
  lower edges and gaps read against something lighter. Same size and place. Rock meshes and colours are unchanged
  (the rock tint is chosen by the client, not edited here).
- Tables: dark iron outline + timber body + the board above; nothing added in the work lane.

Unchanged: pile, table, bay and hopper positions, routes, all named parts / attachments / prompts / attributes
(`Surface`, `Plate`, `InputTray` + `Slot1..10`, `OutputTray`, `DockPad`, `Stand`, `Feed`, `Nameplate` with label
`Name`, `Sign` with label `Title`, `Light`, `CT_Rocks_SellHopper` + `Body` + `SellPrompt` + `ReceiptLight`). No meshes
were rebuilt or uploaded (recolours only), so no new asset ids.

Not verified: Studio lighting and real SurfaceGui rendering, text legibility on a real phone, collisions.

Checks (offline): `bash tools/check.sh` zero diagnostics, 154 rule tests, build; `bash tools/run_regressions.sh` 45/45 PASS
(the placement audit first caught the new table board's side rails sharing a top plane with its face on the 45-degree
tables; the rails are now 0.04 taller).
