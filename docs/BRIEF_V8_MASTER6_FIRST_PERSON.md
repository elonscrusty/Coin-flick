# CRACK THE ROCKS — MASTER PROMPT 6
## First-person play, ordinary-material discoveries, and a more satisfying hunt

Implement this as an additive update to the CURRENT project. Preserve Master Prompt 5's compact lobby, single expandable Upgrades counter, Collection corner, catalog, progress and existing working carry-and-crush systems. This prompt supersedes earlier third-person gameplay camera requirements. Do not rebuild the lobby into the reference game's farm. Inspect current source and changes from any phases already in progress before editing. Integrate with current files rather than reverting a newer implementation to an old script.

The goal is to make finding, carrying and cracking individual rocks feel close, responsive and satisfying. First-person gameplay is explicitly requested. Ordinary-material variety, discovery tracking and clear feedback are proposed additions based on the supplied reference. Their scope is specified below so implementation does not accidentally change the single-geode competition.

## 1. Reference evidence and adaptation boundaries

Reference: Roblox 2026-10-09 18-11-48.mp4, approximately 71 seconds, desktop recording. Times below are approximate.

The first portion shows a third-person public lobby with labeled attractions, a shop, inventory categories, pet cosmetics, rewards and party pads. Around 35–42 seconds a solo pad counts down and transitions into a farm hunt. From roughly 43 seconds onward, gameplay is first person. The player approaches one large haystack and collects individual visible pieces. The HUD includes a collection capacity of 25 and an elapsed timer. A New Index Discovery notice identifies a Normal find with +10 Gems, followed by a Rainbow find with +150 Gems. The video later shows a labeled sell location: after selling nine hay, carried count becomes zero and the confirmation states $0.45 received. The player returns to the haystack afterward.

These are visual observations, not verified source behavior. This short clip does not show the needle being found, a multiplayer winner, full index contents, a pet operating, a completed progression system or save/rejoin. Do not infer those implementations from the footage. Do not copy the exact interface, assets, names, economy, farm theme, monetization panels or artwork.

Adapt these useful principles:
- Close first-person interaction makes the pile and item transfers tangible.
- Short collection feedback explains what just happened without a long modal.
- Ordinary finds can create discovery moments even before the main target appears.
- Inventory capacity and a timer communicate short-term progress.
- A sell location visibly explains material-to-currency conversion.
- The lobby and hunt have different presentation priorities.

Do not import pets, clans, daily gifts, class systems, premium multipliers, additional currencies, infinite carry or chapter systems for this update. Keep the existing solo/party entry. The pad countdown is evidence of a clear transition, not a request to replace our Start Hunt kiosk or party policy.

## 2. Nonnegotiable game loop

Public shared lobby; private solo or party hunt with up to four members. Exactly one shared central pile and one hidden target geode per round. Rocks are individual authoritative records, even if the visual pile uses bounded decorative filler. Party members compete over the same source pool. Each player collects neutral-looking rocks, carries them to their own assigned table, deposits into their own input queue and processes there.

Picking up the target does not win. First valid target-processing completion wins; the server commits the winner once. Solo records a Find according to current policy; competitive play records a Win according to current policy. Winner receives exactly one persistent specimen. Every player retains their own valid ordinary earnings. Auto machines process deposited queue input only. No cracking at the pile, remote extraction, stealing queue items or second target.

Initial basket capacity remains five and station queue ten unless real existing upgrades change them. Rubble storage is separate. Preserve purchased storage, including the recorded 100-unit capacity, current prices, tool/machine ownership, gallery capacities, collected specimens and placement records. Do not change inventory limits to the reference's 25 merely because its HUD shows that number.

## 3. First-person camera ownership and lifecycle

Use first person for ordinary player-controlled exploration in BOTH the compact public lobby and the private hunt. Menus, results and specimen inspection may use clearly bounded presentation cameras or ViewportFrames; they must restore first-person exploration on close. Other players still see the normal world avatar and equipment. This is a camera/input presentation change, not removal of avatars from multiplayer.

Prefer Roblox's supported built-in first-person camera path using CameraMode.LockFirstPerson, with existing movement/camera controls retained. Inspect current custom camera scripts, zoom restrictions, camera offsets and menu controllers before changing properties. Avoid creating a second camera-follow loop that fights PlayerModule every frame. One coordinator owns mode changes and restoration; no unrelated script repeatedly forces its own CameraType or MouseBehavior.

Set consistent defaults and reapply only when lifecycle requires it: fresh join, character spawn, session transition and restoration from a deliberate cinematic. Handle CurrentCamera replacement. Capture/restore any intentionally modified subject, type, field of view and mouse state. Do not keep a reference to a destroyed humanoid after respawn. A result reveal cannot leave the player stuck with a Scriptable camera. Lobby return cannot restore an obsolete arena camera position.

Begin with the existing default field of view unless it is already problematic. Do not add speed-FOV changes, head bob, view roll, strong recoil or camera shake by default. Tool contact should be communicated through the model, sound and localized effects. If existing settings support reduced motion, honor them. Keep first person usable for players sensitive to movement without adding an unrelated settings overhaul.

The player's face, hats, hair, torso and basket must not obscure the camera. Use local presentation/transparency behavior coordinated with the built-in camera. Do not make world character parts globally transparent to solve a local visibility issue. Test the actual supported rigs and common avatar accessories. If custom arms are required, they are cosmetic local viewmodels; they must never carry physical authority or collide with the map.

## 4. Mouse, touch, gamepad and menu behavior

Desktop: during exploration, normal first-person mouse look is active. When a real interactive modal opens, the cursor is usable, camera/action input is suspended appropriately, and the player can operate tabs, scrolling, close controls and item selection. Restore first-person mouse look only after the last blocking modal closes. Track modal ownership rather than toggling camera state independently for every panel.

Opening Shop over another supported overlay must not restore gameplay when only one layer closes. Closing a menu must not perform a pickup or tool strike with the same input. Switching focus away, cancelling a request, receiving Results or ending a session clears held processing intent. Keep Roblox's menu/chat and reserved input behavior intact. Respect processed input and focused text entry.

Touch: dragging in the normal look region rotates the camera; joystick movement stays separate; a dedicated contextual action button performs the selected action. A look swipe is not an automatic pickup or strike. Keep action controls clear of movement, jump, Roblox controls and safe insets. Avoid a touch action zone covering the whole screen. Adapt prompts when preferred input changes on a hybrid device.

Gamepad: right stick looks, normal movement remains, one contextual interaction mapping acts on the selected target, and supported menus have usable focus navigation/back. Do not invent a new complicated control scheme. Reuse current compatible bindings and present the actual binding in the prompt. Input changes must not create duplicate requests through both old and new handlers.

## 5. First-person targeting and contextual action

Use one small centered reticle and one context resolver. A camera-center ray is a reasonable presentation query. It identifies eligible targets within configured reach and line of sight. Ignore local viewmodels and noninteractive decorative trim. Source rocks, owned station deposit zone, valid processing position, existing sell point and lobby counter triggers have explicit interaction tags/owners. Do not make every mesh a potential target.

The server validates any request independently: session, distance, eligible rock/queue record, ownership, capacity, line of sight where required, current processing state and rate limits. Client aim/highlight is a convenience, not proof. Never send target geode identity or let a client select an arbitrary record outside reach. Preserve atomic pickup contention when two players aim at the same rock.

Reticle states are simple: neutral, eligible and unavailable with a concise reason only when useful. Use a subtle outline on one targeted rock, not the whole pile. A disabled distant object should not produce a constant Move Closer message during scenery exploration. Avoid overlapping ProximityPrompt labels and a second custom action button describing the same interaction. Choose one visual presentation with one authoritative action path.

Context examples:
- Eligible source rock and available basket space: Pick up rock.
- Basket full while targeting source: Basket full — deposit at your table.
- Owned table deposit zone with carried rocks and queue space: Deposit rocks.
- Deposit with insufficient queue space: use current accepted partial/all-or-nothing policy and show accurate counts; do not silently discard overflow.
- Owned processing position with queued manual input: Crack rock with the real hold/tap behavior of the equipped tool.
- Auto machine active: show queue/status; do not expose a duplicate manual completion path.
- Valid existing sell location with ordinary rubble: Sell rubble with an accurate amount/value preview.
- Counter in lobby: Open Upgrades or Open Collection.

Picking up remains a deliberate per-rock action. Optional held-repeat may be retained only if already configured and capped by the actual tool/input rules; this update does not authorize vacuum-style collection or faster purchased pickup. Preserve intended processing timings. A convenient prompt cannot change throughput or fairness.

## 6. Visible carrying and table work

First person removes the third-person basket from the normal view. Give the player a small readable glimpse of their carried load without filling the screen: a basket lip and limited stones in the lower peripheral view, or a restrained held-load representation compatible with the real animation. Keep the center, horizon, targeted rock and table plate clear. The ordinary carry count remains visible so the player is never dependent on looking down.

A pickup has a short local transfer cue, quiet stone sound, count increment after accepted state and a bounded visual load update. On server rejection, remove predicted feedback cleanly. Do not spawn a physically simulated rock that falls through the avatar or can be collected again. Keep the third-person basket/pose coherent for other players.

Deposit visibly empties accepted carried records into the input tray. Show remaining carried count if only part transferred. One rock feeds onto the plate. Hammer or jackhammer is visible at the correct contact point. Manual animations have anticipation/contact/recovery and stop safely on invalid state. Do not attach an oversized jackhammer across the entire center of the screen. Auto machines have a clear feed/crack/output sequence tied to real queue resolution.

Adjust table plate height, tray placement, tool size and approach clearance for actual eye-level viewing. The player should be able to stand naturally and see the active rock without climbing onto the table or pitching the camera straight down. Any small work-position assistance must remain cancellable and must not lock locomotion unexpectedly. Avoid moving the camera into a shield or tool. Preserve routes and equal station access for four players.

## 7. Ordinary material discoveries: worthwhile finds without extra geodes

Add a lightweight Material Discoveries feature over ORDINARY processing. This is the adaptation of the reference's Normal/Rainbow notices. It is not a second collectible-geode system and not a second currency. Ordinary rocks may reveal a small material category on valid cracking, but all ordinary outputs remain sellable rubble under the current inventory/capacity rules.

Suggested initial category set: Common Stone, Quartz Fragment and Metallic Specks. Names describe material appearance, not guaranteed geological authenticity. Reuse existing categories if they already serve this purpose. Keep the set small and data-driven. Each category gets a readable icon/thumbnail, restrained output color/detail, display name and description. Quartz fragments are small solid chips, never a hollow geode shell. Metallic specks are visual inclusions, never a whole gold collectible. Reserve the hollow crystal-cavity reward for the round target.

Default economic policy for this update: category identity changes discovery presentation, NOT sell value, capacity usage or processing speed. Every ordinary result contributes the same current configured unit/amount as before. Do not add bonus Gems or copy the reference's reward amounts. If the existing economy already differentiates ordinary outputs, retain its data and account for it accurately; do not overwrite real configured values with the equal-value default.

For new category assignment, start with explicit server-side configurable weights, for example 80 percent Common Stone, 15 percent Quartz Fragment and 5 percent Metallic Specks. These are proposed presentation weights, independent of target selection and tool power. Validate distribution before final tuning. They are not exposed target odds. Determine ordinary category server-side consistently for each rock/round so retries and equipment changes cannot reroll it. Do not make higher tools increase category odds in this pass.

All uncracked source stones must remain neutral with no category-specific visible color, sparkle, glow, mesh, crack pattern, UI name, audio or client-readable hidden metadata. Discovery occurs only after that player's valid ordinary completion. Visible colorful hay in the reference does not authorize visible rich rocks in our competitive pile. Neither ordinary material nor target identity should influence pickup selection through leaked presentation.

For persistence, store a compact discovered-category set and optional count of valid ordinary completions per category in the current player profile. Use stable IDs and safe defaults for old profiles. Unknown future IDs cannot crash the selector. Count only actual completed outputs owned by that player; viewing decoration, picking up, depositing, cancelled cracking and previewing Shop cannot unlock discoveries. Duplicate completion events do not increment twice.

Update discovery state in the existing authoritative completion/reward pipeline. Avoid a second remote that trusts the client to report discoveries. Use existing retry/idempotency conventions. Do not add a standalone datastore per UI category. Display confirmed data; on save failure use current recovery policy and avoid falsely promising that a discovery was saved.

## 8. Discovery book in Collection

Add a Materials subsection to the existing Collection interface alongside earned geode specimens, clearly labeled so players understand the difference. Preserve existing specimen selector, owner slots, placement/removal and gallery upgrades. Ordinary material entries are a discovery checklist, not displayable trophy specimens and not free inventory awards.

Show a small progress line such as Materials discovered: 2/3, with numerator/denominator from real configured eligible categories. Undiscovered entries use restrained silhouettes and Unknown material text. Discovered entries show name, thumbnail, brief description and real found count if tracked. Do not display hidden target odds, imply extra targets, add a percent-complete reward, or gate equipment behind the checklist in this pass.

First discovery feedback is brief: Material discovered — Quartz Fragment. Repeat discoveries use a smaller ordinary-output acknowledgment or no separate notice if current feedback already explains the result. Never place a full-screen popup between each rock. Group or bound notifications from fast automatic processing so a thirty-item queue does not create thirty stacked cards. Keep a visible readable record in Materials when a notification is skipped by batching.

Use a distinct, quieter treatment than target reveal. A rare ordinary chip must not play a winner fanfare, end the round or increment Finds/Wins. New-discovery state appears once per category per player across rejoin. Mock developer unlocks are removed and cannot populate production data.

## 9. Hunt timer, pile progress and state-driven HUD

Keep one compact top objective: Find the geode. Under it, show a small elapsed hunt timer and an accurate shared-pile count. Timer starts at the authoritative hunt start after readiness/countdown, not public lobby join. It displays server-derived elapsed time without a remote every frame. Stop it at authoritative round end. It is informational; this update adds no deadline or timeout loss.

If an Unopened count already exists, inspect its semantics. Rocks still in source, carried rocks, queued rocks and unresolved active rocks are different sets. Label the desired visible metric accurately, such as Rocks left in pile for source records only. Do not label source depletion as Geode nearly found; the target may be in a basket or table. A remaining-to-process metric can include every unresolved record, but its title must make that scope clear. Source empty while unresolved records exist is a valid state, not permission to spawn another target.

Carry and rubble storage are separately labeled. While approaching the pile, emphasize Carry 3/5. At the table, emphasize own queue/current processing. Persistent currency remains legible but secondary to the current action. No more than one contextual primary action and one short guidance line dominate the center/lower action region. Keep reticle, active rock, movement and jump regions unobstructed.

Show only small relevant arena UI during a hunt. No clan, shop advertisement, permanent reward, codes, daily gift or multipliers panel fills the hunt edges. Lobby shows Start Hunt/party, progression access and actual account resources; it has no table queue, pile count or arena directions. Ensure Master Prompt 5's HUD leak fix remains intact after camera changes.

After five confirmed ordinary completions in a development test, source/carry/queue/active/output counters must reconcile according to their real definitions. Do not approve visually pleasing HUD counters without validating their record ownership and transitions.

## 10. Clear rubble selling

Improve the current Sell rubble location/flow rather than adding a second economy endpoint. If an actual sell location is already at the station or arena edge, retain it and make its approach/label clear in first person. Use a compact material bin/chute and an original stone-to-coin symbol consistent with our art kit. Do not copy the farm's cow, barn or exact wooden sign.

A valid sell action previews true ordinary quantity and expected currency from current server configuration. After confirmation, show a brief exact receipt, for example Sold 9 rubble for 45 Coins ONLY if those are the actual returned values. Example text is not a new price. Sell the correct owned ordinary bag records, never raw carry, queued rocks or earned geode specimens. Keep current manual/automatic sale policy and any storage-full behavior; do not silently turn it into auto-sell.

Capacity and sale feedback should clear obsolete guidance immediately when state changes. With empty storage, no active Sell action promises income. Rapid duplicate requests cannot grant repeated currency. A failed request must leave materials and currency consistent. Selling remains available according to current match policy; this pass must not block a full-bag player indefinitely or let sales resolve unrelated queued rocks.

## 11. First-person tutorial and session transitions

Use a short contextual first-session sequence: look at an eligible rock, collect it, carry it to your table, deposit, crack, observe ordinary output, then continue searching for the geode. Progress only on authoritative confirmed events. Existing returning players do not have to replay a tutorial because the camera changed. A brief first-person controls tip is enough. Keep guidance dismissible where appropriate.

Show a short truthful pre-hunt objective during the existing loading/readiness transition. Avoid a mandatory new long countdown or fly-through. Public party formation remains in the compact Start Hunt system. Use current minimum/maximum and readiness policy; solo must still work. Do not add multiple queues because the reference has multiple pads.

On target resolution, stop further competitive completions according to current end policy, show the real winner/solo result, and present the actual cavity-facing specimen. Keep a simple elapsed-time summary. Do not add fastest-hunt leaderboards or Best Time persistence yet: comparing different pile sizes, equipment and party sizes requires a separate design. Timer information alone is enough.

Menu/reveal restoration handles Return to lobby, Rematch, character reset, cancellation, disconnect recovery and session rejection. Other players' tool sounds and effects do not shake the local camera or obscure the reticle. Retain public world avatars so the shared lobby still feels social even though the local view is first person.

## 12. Asset and implementation scope

Required additions/adjustments: subtle reticle; one coherent context action; first-person-compatible basket/tool presentation; correctly visible work plate and input tray; three small ordinary-material output/thumbnail variants if absent; small discovery notification; Materials subsection; compact hunt timer; refined existing sell sign/bin. Reuse current counter, paving, cabinet, geode and tool kits. No new large buildings, pets or giant production props.

Inspect and extend current camera/input coordinator, interaction resolver, session UI, processing pipeline, profile schema, Collection renderer and sell flow. Keep modules focused and avoid an unrelated architecture rewrite. Data drives material categories and tool previews. Do not hardcode card positions, add fictional asset IDs, or claim PNG reference images are actual meshes.

Use supported Roblox APIs and current official documentation. Starting references:
https://create.roblox.com/docs/reference/engine/enums/CameraMode
https://create.roblox.com/docs/workspace/camera
https://create.roblox.com/docs/reference/engine/classes/Camera
https://create.roblox.com/docs/input
https://create.roblox.com/docs/reference/engine/classes/UserInputService

First-person support does not require a combat-style custom FPS framework. Prefer the smallest coherent solution that keeps native controls reliable. If a viewmodel is necessary, use one bounded local model and owned cleanup, with no per-frame model cloning, no remote stream of camera transforms and no duplicated effect loops. Batch discovery UI and bound preview rendering.

Implement in this order: audit and preserve current branch changes; camera/menu/input lifecycle; reticle/context interaction; basket/table visibility; authoritative ordinary category and profile migration; Materials UI and notifications; timer/count semantics; sell presentation; integrated device/session tests. Commit or package complete reconciled file replacements as appropriate to the project, rather than isolated snippets that leave old conflicting camera scripts running.

## 13. Acceptance demonstrations

1. Fresh join: first-person lobby, readable landmarks, unobstructed avatar accessories, menus work with a free cursor/focus and restore mouse look after close.
2. Solo start: correct private session, one pile, own station, timer starts once; no forced fly-through or duplicate camera owner.
3. Neutral pickup: target one individual rock, accepted transfer increments carry, maximum capacity enforced; uncracked rocks reveal no material or target information.
4. Deposit: five collected records transfer correctly to the owned queue, basket empties, full-basket guidance clears, no duplication or lost overflow.
5. Manual work: actual rock and tool contact visible at ordinary eye height, release/cancel works, output granted once; no pile cracking.
6. Automation: actual deposited queue processed, category notices bounded, no simultaneous manual duplicate resolution and no active effects after end/empty.
7. Discoveries: first category notice appears once; repeat count correct if supported; Materials shows confirmed data; rejoin restores state; no specimen/coin bonus invented.
8. Target: single geode awarded once, no ordinary fragment ends round, solo/competitive stats correct; cavity shown clearly in result and Collection.
9. Selling: correct bag quantity removed and actual currency added once; raw rocks and trophy geodes untouched; empty-state feedback truthful.
10. Multiplayer: two players contest one rock safely; two concurrent target completions cannot produce two winners; each player's local preview/reticle/camera independent; all routes remain fair.
11. Input: desktop, touch and gamepad flows tested; mobile look swipe does not collect; action avoids jump/joystick/safe areas; text entry and UI clicks do not trigger tools.
12. Lifecycle: open/close multiple supported overlays, rapid close/reopen, respawn, camera replacement, rematch and lobby return do not leave cursor lock, stale HUD, Scriptable camera, held action, listener or viewmodel leaks.
13. Conservation: every active rock belongs to exactly one valid unresolved state or has one resolution; UI labels match actual counts; ordinary category selection cannot be rerolled or exploited.
14. Migration: existing profiles retain money, capacity, equipment, specimens and displays; absent discovery fields get safe defaults; save failures use existing recovery conventions.

Provide actual in-game player-view footage of pickup → carry → deposit → cracking → ordinary discovery → sell and a separate genuine target result. Report changed files, confirmed checks and unresolved limitations. Do not claim the change is complete from a static mockup, thumbnails or a camera property alone.
