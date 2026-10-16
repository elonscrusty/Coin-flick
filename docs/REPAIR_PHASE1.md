# Phase 1 repair (owner's V2 brief, recording 2026-10-09 10:43)

Offline only: type check, rule tests (21/21) and the offline preview renderer
(`tools/preview`, docs/PREVIEW.md), 42 screens (7 scenes x 6 devices) with the layout
checker at 0 problems. NOTHING here is verified in Studio or on a phone yet.

Each item: what the recording showed, the source cause found in the code, its kind
(BUG = code bug, MISSING = feature not built, ART = placeholder art), and the fix.

## 1. Mobile UI overflow (P0)
- **Cause (BUG):** every label was sized by `TextSize` inside a fixed pixel box. Roblox's
  "Text size" accessibility setting (GuiService.PreferredTextSize, measured ~1.6x on the owner's
  phone in the Swarm project) scales TextSize text but not boxes, so GEODES / SETTINGS, the tool
  slot, HOLD TO CRACK and the results lines spilled out. The objective's second line and the
  results rows were also long concatenated strings in one-line boxes.
- **Fix:** `src/client/ui/UI.luau` rebuilt as a small design system: tokens (`UI.T`: text 13-24,
  44 px touch, 108x42 menu cards, 112x76 primary action, modal max 560 wide), fitted text at the
  source (`UI.fit`: TextScaled with MaxTextSize = designed size, MinTextSize 11, so text is the
  designed size when it fits and shrinks instead of spilling), drawn icons, viewport scale
  0.8-1.3 from an 800x400 design canvas, modals sized min(available - 32, wanted) with a reserved
  footer and a scrolling body.
- HUD (`ui/Hud.luau`): icon + value rows for Cash and Rubble ("8 / 30"), objective "Find the
  hidden geode" / "75 rocks left" (no personal count in that line), one hint line, timer top right,
  menu cards on the left, tool dock 264x56 (name + "Equipped"; stats moved to the shop), machine
  cell "Unlock later". Portrait: the objective drops below Cash/Rubble at full width.
- Results (`ui/ResultsPanel.luau`): one fact per line (headline, mineral, rarity chip, mass and
  value, winner, "1 geode added to your collection", "+1 solo find (not a multiplayer win)",
  "You cracked N rocks", "Rubble you keep: N (sells for $X)", next step), buttons in the footer.
- Shop / collection tab rows scroll sideways on narrow screens; collection cards compacted so a
  whole row fits a 390 px tall landscape phone.

## 2. Input and modal state
- **Cause (BUG):** modals and the reveal shared the HUD layer and did not stop gameplay input; the
  tool dock showed through the reveal.
- **Fix:** modals and the reveal live on their own ScreenGui above the HUD and call `UI.block`,
  which hides Roblox's touch thumbstick/jump (`GuiService.TouchControlsEnabled`), stops holding,
  clears the target and hides the action button, dock and objective. Holding also stops on
  drag-off, focus loss, respawn, phase change and match end.
- Primary action states: HOLD TO CRACK (valid rock in range), MOVE CLOSER, STORAGE FULL / SELL
  RUBBLE (tap shows where to sell), GET READY (countdown), SECURING GEODE (reward saving). It is
  placed above Roblox's jump button using the jump button's real size rule (70 px under 500 px
  screens, 120 px otherwise).
- Keyboard: E / R2 hold to crack; world prompts moved to R so they no longer clash with E.
- **Also found by the preview (BUG):** the selection Highlight was parented to Workspace with no
  Adornee, which in Roblox outlines its parent, i.e. the whole world. Now it lives in a Folder and
  is enabled only while a rock is selected (thin warm-yellow outline, no fill).

## 3. Hammer visibility (P1)
- **Cause (BUG, likely):** the tool was jointed to the hand at CharacterAdded. Avatar bundles
  replace body parts after that, which destroyed the joint's Part0 and dropped the tool. Also the
  hammer was small and the swing only rotated the tool joint.
- **Fix:** re-attach on CharacterAppearanceLoaded and whenever the hand part is replaced; works
  for R15, R6, other "right hand/arm" parts, or the root as a last resort. Chunkier hammers
  (2.2-2.5 stud heads with pale striking faces, 3 stud handle), held as an extension of the arm.
  Procedural swing (`ToolAnim.luau`): the right shoulder Motor6D's Transform is rotated each
  frame after the Animator (RunService.Stepped), raise 0-0.15, swing 0.15-0.32, contact at 0.32
  (chips spawn then), recover to 0.65 s (steel 0.55 s); jackhammer arm forward + 0.1 stud
  vibration. Reduced motion shrinks the swing. No animation ids are used.
- Preview: renders show the raise and the head landing on the rock (`hunt --set near=on
  --set swing=T --set cam=side`). Studio must confirm that Stepped runs after the Animator on
  the owner's avatar; if not, the tool still swings via its own joint (fallback branch).

## 4. Rock mound (P1, ART)
- Same logical pile and server positions; new look: Gravel ~17 studs wide, ~5-6 tall (tested),
  wide base / tapered peak, smaller rocks, faceted shells (core block + skewed block + slanted
  wedge in three greys), 16 loose edge stones (no collision, not hittable), crack seams per hit
  (multi-HP tiers), 4-8 pooled fragments on break fading in 0.4-0.7 s, gentle settle tween.
  Mesh replacement points: `GeodeModel.rockShell` (CT_Rocks_RockShell_A..D).

## 5. Geode model (P1, ART)
- **Cause (ART):** the old model was a sphere + flat disc + spikes, so from the front it read as
  a coin.
- **Fix:** `GeodeModel.build` makes a hollow bowl from rings of faceted shell slabs, a pale
  broken rim, a crystal bed, small crystal nubs and faceted spikes (prism + diamond tip) per
  formation; palette from the mineral, modifiers from the stored data, seeded so the same
  specimen looks the same in reveal, results, collection and gallery (gallery uses a lighter LOD).
  Viewports frame the model from its bounding box at a three-quarter angle. The reveal splits
  two front shell halves away (lift 0-0.3, split 0.3-0.9, frame, shimmer, labels).

## 6. Tutorial teaches sell and display
- **Was (MISSING):** practice ended at the find.
- Now: profile `Onboard` steps Started / Cracked / Geode / Sold / Displayed / Goal / Skipped,
  any order, never repeated. Practice geode is rock 2-6 broken, so one ordinary rock (and its
  rubble) always comes first (tested). One hint at a time with OK, a marker over the nearest
  hopper ("SELL HERE") or the player's alcove ("YOUR GALLERY"). Practice results show SELL RUBBLE
  or DISPLAY GEODE (returns to the lobby and opens that geode with SHOW IN GALLERY), LOBBY and
  SKIP TUTORIAL; HUNT AGAIN appears once onboarding is done or skipped. Settings has a SKIP row.
  Old saves: steps inferred (practice done, cash earned, something displayed).

## 7. Solo results / rarity audit
- "+1..." in the recording was "+1 rubble ($2)" in the cracked/rubble row. It was not a win.
  Inspected: practice never touched MultiplayerWins; it did not count as a Solo Find either.
  Now practice and solo finds both add SoloFinds; MultiplayerWins only from multiplayer hunts.
  Existing saves are not changed retroactively.
- Rarity: weights 60/25/10/4/1 in Config, one roll per win, no forcing or test flags; the
  50,000-roll test keeps Legendary at 1% (+/-0.3). The recorded Legendary was a 1-in-100 roll.

## 8. Sale feedback
- Same server math. Toast "+$16 • Sold 8 rubble", gravel bits dropping into the hopper grate,
  Cash counter rolls to the new value. Rubble still carries over between rematches.

## 9. Environment
- Lobby: giant yellow ring removed; terminal plaza, walkways with edge lines to the shop,
  collection, gallery and hopper; signposts; bigger tool displays; collection hall's unrelated
  neon blocks removed; empty alcoves show a ghost pedestal "Your first geode goes here"; plates
  read "<name>'s gallery"; labels show name, rarity, mass. Hopper has a grate and hazard band.
- Arena: wall supports, machine bays signed "MACHINE BAY · UNLOCK LATER".

## Not done / blocked
- Studio and phone verification of everything above (BLOCKED: owner).
- 2-4 player races, disconnect/reward retry, rejoin, real DataStores (BLOCKED: Studio).
- Sound (stone hits etc.): no audio assets; nothing invented (BLOCKED: assets).
- Real meshes for rocks/geodes/tools (ART, Phase 4); performance measurement on a device.
