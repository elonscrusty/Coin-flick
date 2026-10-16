# Master Prompt 8, Pass 5: UI states (offline preview only, NOT Studio-tested)

Rendered with `tools/preview/render.sh` on pc, phone-1108 and phone-portrait; `largest/` = Roblox Text size Largest
(`--set textsize=Largest`). `check_layout.py` over all 45 renders: 0 problems (9 "clipped" infos are rows inside the
scrolling results body).

| Picture | Scene |
|---|---|
| `loading-*` | `loading` (step 2 of 3). `--set step=run` runs the real boot and prints `loading PASS` when the screen showed first and removed itself after the HUD existed |
| `results-*`, `results-party/` | `results`, `results --set mode=party` |
| `settings-*` | `settings` |
| `party-*`, `party-party/` | `party` (no party), `party --set view=party` |
| `shop-*`, `collection-*`, `collection-empty/` | `shop`, `collection`, `collection --set count=0` |

## What changed
- Title / loading screen: `src/first/LoadingScreen.luau` + `Boot.client.luau`, mapped to `ReplicatedFirst.Loading` in
  `default.project.json` and `match.project.json`. FIND THE GEODE! logo, three real steps (place loaded, character exists,
  HUD ScreenGui exists), bar shows finished steps only, no percentages; removes itself after a 0.25 s fade, or after 25 s
  if a step never finishes, so it can never trap the player.
- Results: title leads with FOUND THE GEODE! (solo), YOU FOUND THE GEODE! or "<NAME> FOUND THE GEODE!" (party); the
  reveal headline uses the same text. "YOUR ROUND" block at 16 px with earned / sold / in bag as separate rows plus the line
  "Separate counts, not a total". Other hunters show "left the hunt" when not present. A status line shows refused rematch
  requests (server toasts); buttons still use the 4 s pending state, so a refusal restores them. Leader / non-leader
  actions unchanged (non-leaders can always return to the lobby).
- Settings: grouped SOUND / MOTION & EFFECTS / HELP; sliders and switches have 44-48 px touch areas; sliders go full width
  on narrow screens; moving a slider sets the real SoundGroups (`SoundService.CTR_Audio` SFX, Music, Ambience at 0.6x)
  immediately, then the server saves it. Only existing settings (Music, Sfx, ReducedMotion, LowEffects, Hints, Skip guide).
- Start Hunt: fairness line "One shared pile. Bring rocks to your own table. First to crack the geode wins." in both the
  no-party and party views; SOLO / CREATE PARTY / START share one in-flight guard (no double start); invite, tier, kick
  and accept targets 44 px; body text 16 px.
- Collection subtitle shortened (no two-line wrap in portrait). Shop: no gaps found against section 17.

## Not verified
Studio play test, real devices, real SoundGroup volume change by ear, real Roblox text-size scaling, gamepad focus.
The mock ghosts the touch JUMP button behind modals; in Roblox the touch controls hide while a modal is open.
