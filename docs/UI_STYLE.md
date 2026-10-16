# UI style guide: "toy box" look (2026-10-12)

Owner ask: the UI "looks very AI", flat and still. Copy the style of the biggest Roblox games.

## What the top games share
Looked at: Pet Simulator 99, Adopt Me!, Grow a Garden, Blox Fruits, Bee Swarm Simulator, Brookhaven, Murder
Mystery 2, Tower of Hell, Doors, Blade Ball, Arsenal, Toilet Tower Defense, Anime Defenders, Fisch, Dress to
Impress, Natural Disaster Survival, Bedwars, Royale High, Jailbreak, Piggy (public screenshots and dev forum
UI threads).

1. **Bright, saturated panels, never charcoal.** Sky blue (Pet Sim 99, Bee Swarm), cream + teal (Adopt Me),
   green + wood (Grow a Garden). Dark UI only in horror / shooter games.
2. **Thick dark outlines on everything.** 3-4 px navy or black strokes on panels and buttons, and a thick black
   outline on every word.
3. **Chunky cartoon fonts.** Luckiest Guy / Fredoka One style, all caps on buttons and titles.
4. **Glossy 3D buttons.** Vertical gradient (light top, darker bottom lip), a soft white highlight on the top
   half, colour by meaning: green = go / buy, gold = main action / premium, red = close, blue = normal.
5. **Everything moves.** Hover grows a button ~6%, press squashes it, release bounces past full size.
   Menus spring in from small with an overshoot. The main button idles with a little wiggle so the eye finds it.
6. **Shine sweeps.** A white diagonal glint slides across main and buy buttons every few seconds.
7. **Reward moments are loud.** Spinning sun rays behind the prize, "+50" numbers that pop up and float away,
   coins flying to the counter, confetti, a big tilted banner, a count-up.
8. **Rarity colours** with a shimmering border on rare items (rainbow / gold sweep).

## Our rules (implemented in `src/client/ui/Theme.luau` + `UI.luau` + `Juice.luau`)
- Panels: sky-blue gradient (`Theme.Color.Panel` + `Theme.Panel`), navy 4 px border, deeper blue wells.
- Buttons: `UI.button` adds gloss, 3 px navy border, hover grow, squash and bounce; styles gold, green, red,
  blue ("gray" is the blue secondary). Gold and green buttons get a shine sweep (`UI.shine`).
- Attention: `UI.wiggle(obj)` (a tilt every few seconds) for the one button the player should tap next (PLAY).
- Rewards: `Juice.floatText(src, "+50", color)` number pop-ups, `Juice.rays(target)` spinning rays.
- Reduce Motion turns every loop off and every spring into an instant change.
- Icons stay procedural (no uploaded images needed). Optional uploads that would look even better are listed in
  `docs/OWNER_STEPS.md` "UI images (optional)".
