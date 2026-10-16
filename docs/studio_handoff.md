# Studio handoff (2026-10-15, Studio thread)

## Current Studio state (place 136287661337145, Edit mode, camera Fixed)
- Code synced to main **21a454f** (PetSkins with the new DireWolf skins). Lobby built to **round 24** (c515541).
  glitch_scan: GLITCHES 61, z-fight pairs 34 (was 119 / 1054). What's left: cliffs and trees inside OuterHills (by design), Plazas and YardGates same-folder pairs.
- **Not published.** Publishing is blocked for Claude (the auto-mode classifier treats Alt+P as a production deploy). carter has to press Alt+P in Studio.
- PetModels: **Pet_DireWolf = new 1015d wolf** (carter said yes). The old one is `ServerStorage.LobbyBackups.Pet_DireWolf_old1015`.
- Candidates (not swapped):
  - `ReplicatedStorage.PetCandidates_1015d` is now empty (the wolf moved into PetModels).
  - `ReplicatedStorage.PetCandidates_1015f`: Bunny, Griffin.
  - `ReplicatedStorage.PetCandidates_1015g`: Cinderpup, Clovercrest, Pebblehorn, Bramblebat, Ashwing, Duskwing, Embergeist, Flarestrut.
  - `PetCandidates_1015c` (big eyes, rejected) is in LobbyBackups.
- `Workspace.PetCompareSpawn`: 20 old/new display pets beside the spawn path, with OLD/NEW labels.
  - Bunny and Griffin row at z=90; the four 1015g rows at z=82, 75, 68 and 61.
  - Animated by the TEMP `StarterPlayerScripts.PetCompareIdle`.
  - Move both to LobbyBackups when carter is done comparing.
- Backups: `ServerStorage.LobbyBackups` (WolfTest, PetCompare stage, WalkPoses module, old wolf) and `ServerStorage.ImportLeftovers` (import shells). Never destroy; move here.
- Skin ids for 1015d/f/g were sent to the coordinator. DireWolf skins are on main; Bunny, Griffin and 1015g skins are not on main yet.

## How things are done
- **Code sync:**
  1. `git pull` in C:\Users\myson\Crack-the-rocks.
  2. Build: `rojo build /tmp/code.project.json -o /tmp/all.rbxm`. The project maps src/shared, src/server, src/client, src/first and tools/owner/PetMotion.luau.
  3. Copy all.rbxm into every `%LOCALAPPDATA%\Roblox\Versions\*\content\ctr_all.rbxm`.
  4. In Edit, `game:GetObjects("rbxasset://ctr_all.rbxm")[1]`, then recursively copy `.Source` into these targets:
     - Client → StarterPlayerScripts.Client
     - Shared → ReplicatedStorage.Shared
     - Server → ServerScriptService.Server
     - Loading → ReplicatedFirst.Loading
     - PetMotion → ReplicatedStorage.PetMotion
  5. Clone in any modules that are missing. Skip HuntZoneKit and HuntLowPoly (hunt zones are paused).
- **build_lobby / glitch_scan:** copy tools/studio/lobby_redesign/{build_lobby,glitch_scan}.luau, append `return true`, and rojo-build (/tmp/bl, /tmp/gs) to ctr_bl.rbxm / ctr_gs.rbxm. In Edit, parent the module to ServerStorage, `pcall(require)`, then destroy it. Capture LogService.MessageOut lines (`GLITCHES`, `CLIP`, `ZFIGHT`, ...).
- **Shots:**
  - `scratchpad\shot.ps1` uses PrintWindow on maximised Studio and crops the viewport to 1432x444.
  - In Play, bind the camera with `BindToRenderStep(name, Camera.Value+1)` and set it Scriptable every frame. A plain CameraType set gets overridden.
  - Disable the ScreenGuis and the Camera.MenuBlur.
  - After Edit-mode shots: `CameraType=Fixed`, and destroy CT_Cinematic.
- **Walkthrough:**
  1. Turn walkthrough.json into poses, a shot every 8 studs plus 4 directions at each waypoint (543 poses).
  2. Put them in a ModuleScript `ReplicatedStorage.WalkPoses` (via rbxm).
  3. In Play, run a client loop at 0.8 s per pose with a small index label at the top right.
  4. Capture with `walkcap.ps1 -First 0 -Count 543 -Start 4.4 -Step 0.8`. The last run had file i = pose i-2.
  5. Make 5x12 labelled sheets and send them to the runner with the strict glitch prompt.
- **Runner:** `C:\Users\myson\agent-runner\run.bat "prompt" --image work/... --out work/...`. Output goes in agent-runner\work\out\.
- **Image upload:** run a local node server over the skins folder (scratchpad srv.js pattern, 127.0.0.1:8765), then the Studio MCP `upload_image` with http URLs, 16 per call. **Audio:** scratchpad\ul\upload_audio.js. It reads roblox_key.txt; never print the key.
- **Pet candidate setup:**
  1. Take the MeshPart out of the imported Pet_X and put it in a new Model with Mesh=true and SizeBoost copied from live.
  2. Set it anchored, no collide/query/touch, with `CFrame=(0,h/2,0)*FLIP`, `PivotOffset=FLIP` and PrimaryPart.
  3. Move the shell to ImportLeftovers.
- **Rules:**
  - Stay in Edit while carter imports.
  - Never publish unless carter says so, and even then carter presses Alt+P.
  - Pets never open their mouths.
  - Report to @parent with `sent_to_shared_agent`.
  - Use the thread `attached_outputs` (24 max, now full), so link `/mnt/project-files/...` from SendUserFile instead.

## Open queue (in order)
1. **Round-24 walkthrough + strict score.** The round-23 frames in agent-runner\work\out\walk are stale; re-run them.
2. **UI round 3:**
   - PC shots done: Pet Book x2, Upgrades, Robux, Party, Settings, dev panel, Tower (agent-runner\work\out\ui3).
   - Still to do: Loading screen, Tower fight HUD mid-fight (needs a pet: DevSpawnPet, equip, Climb), and phone-size shots (viewport about 844x390) with the thumb-zone check.
   - Then a runner sheet, and report.
   - Found so far: every Robux strip button says "SOON".
3. **Top-20 sheet:** docs/top20-studio-test.md (main 0902d34 or later, includes item 8). Run the new-kid walkthrough plus the listed checks; report PASS/FAIL per number.
4. **Bunny head glitch:** carter reported it. My camera orbit with LookAt did not reproduce it, so we need to know where carter saw it.
