# FIND THE GEODE! — UI redesign v2 (owner brief, pasted in chat 2026-10-10)

Reference boards in this folder:
- `ui_reference.png` — "UI REFERENCE" (12 panels: lobby HUD, hunt collect, hunt station, upgrades tools, machines, collection, display, start hunt, party, results, settings, feedback/confirmations). This is the corrected board: lobby signs read UPGRADES / START HUNT / COLLECTION.
- `ui_reference_uncorrected_draft.png` — same board but the lobby shows extra worlds (THE QUARRY / FROZEN PEAKS / LAVA CAVES). Do NOT add those worlds.
- `additional_screens.png` — "ADDITIONAL SCREENS" (storage upgrades, tier upgrades, gallery capacity, records, empty collection, invite players, party invitation, loading and retry, rubble sale).

---

Completely redesign the existing Find the Geode user interface to match the two attached reference boards.

Implement this in the actual Roblox project. Inspect the current code first, then make the changes. Do not stop after describing a plan.

The images establish the visual direction and screen layouts. The existing game code remains authoritative for prices, upgrade effects, unlock requirements, capacities, tiers, owned items, save data, and gameplay rules.

Treat sample numbers, placeholder names, silhouettes, and incidental text in the images as illustrative. Do not add features or change the economy just because an image contains them.

## 1. INSPECT AND PRESERVE THE EXISTING GAME
Find every existing UI entry point, screen controller, HUD component, notification system, shop catalog, collection controller, party controller, settings controller, and results controller.
Identify which scripts create UI dynamically and which interfaces already exist in StarterGui. Replace or consolidate the old interface so duplicate screens and conflicting controllers cannot remain active.
Preserve: existing player progress and save formats; existing server validation and purchase handling; existing upgrade catalogs and their real values; existing party and hunt systems; existing tool and machine functionality; existing collection ownership and display behavior.
Do not reset data, rename persistence keys unnecessarily, or replace working systems with mock implementations.

## 2. LOCKED GAMEPLAY REQUIREMENTS
The game has a shared public lobby and private solo or party hunts. A party hunt supports up to four players.
Each hunt has: one shared pile of individual rocks; exactly one target geode; players collecting rocks, carrying them to their own station, depositing them, and processing them there.
Players cannot crack rocks directly at the shared pile. Automatic machines process deposited rocks only. They do not collect rocks remotely.
Picking up the target rock does not win the round. The first server-validated completion of processing the target rock determines the winner.
Uncracked rocks must not expose the geode through different outlines, colors, glowing cracks, icons, hover text, sounds, or UI markers.
Players retain their own ordinary earnings. Only the winner receives the round's target specimen. Keep Solo Finds separate from Competitive Wins.
Do not add pets, eggs, combat, extra currencies, rebirths, prestige, new maps, or new progression systems as part of this redesign.

## 3. VISUAL STYLE
Match the attached boards closely: bold, chunky, readable lettering; white text with a controlled black outline; orange or gold for important counts and selected states; green cash text with a cash-stack icon; flat charcoal panels; dark borders; modest corner rounding; gold primary buttons; gray secondary buttons; red close buttons with a clear white X; illustrated icons with consistent outlines and visual weight.
Keep the interface compact and energetic.
Avoid oversized empty panels, cream backgrounds, decorative wood frames, navy-and-cyan dashboard styling, excessive gradients, bloom, glowing borders, and giant permanent navigation rails.
Use an available Roblox font that best matches the references. Do not assume an arbitrary external font can be loaded. If a suitable pixel font is unavailable, prioritize clear bold typography and consistent outlines.
Use stronger outlines for headings and floating HUD text, and lighter outlines for supporting text. Small text must remain readable.
Do not bake entire menus into image backgrounds. Build the interface from real Roblox UI elements so it remains responsive and interactive.

## 4. CREATE SHARED UI COMPONENTS
Implement reusable components or builders for: modal shell; header and close button; primary, secondary, and destructive buttons; tabs; catalog rows; specimen cards; icon-and-value counters; empty states; loading states; error states; confirmation dialogs; notifications; sliders and toggles.
Centralize colors, typography, spacing, border thickness, corner radii, and interaction styles. Keep visual values easy to adjust from one shared theme configuration.
Use consistent spacing and alignment across every screen. Avoid separate hard-coded styling for each menu.
Buttons need clear normal, hovered, pressed, selected, disabled, and pending states. Disabled actions must look disabled and must not accept input.

## 5. SCREEN AND INPUT MANAGEMENT
Use a consistent screen manager. Opening a primary menu should close the previous primary menu. Confirmation dialogs may appear above the current menu without destroying its state. Closing a confirmation should return to the underlying menu. Closing the primary menu should restore gameplay input correctly.
While menus are open: release the mouse from first-person camera control; show the cursor on desktop; prevent menu clicks and touches from swinging tools or collecting rocks; prevent unwanted camera rotation behind menus; stop gameplay movement when the existing flow requires it; preserve scrolling and touch interaction inside the menu.
When menus close: restore the previous camera and input state; restore the existing first-person behavior; avoid leaving the cursor unlocked or the camera frozen.
Do not globally disable all input in a way that also breaks UI navigation. Handle keyboard, mouse, touch, and existing gamepad support. Use button activation behavior that works across input types. Avoid mouse-only handlers.

## 6. LOBBY HUD
Rebuild the lobby HUD using the first reference panel. Show: cash; compact Upgrades access; compact Collection access; compact Party access; small Settings access.
Preserve any other genuinely necessary existing entry points, but integrate them into the same visual system.
Do not show hunt-only information in the lobby: station queue; hunt timer; rock carry progress; hunt objectives.
Keep world destinations consistent with the existing compact lobby: Upgrades, Start Hunt, Collection. Do not add the extra worlds shown in the uncorrected draft image.
Keep the world visible. Navigation should not consume a large strip of screen space.

## 7. HUNT HUD: COLLECTING
Use the collecting reference as the primary direction. Show: compact hunt objective at the top; the actual round timer in a separate readable position; carry count and capacity; rubble count and capacity; relevant tool slots; contextual interaction prompt.
Use real state, not sample values from the image. Label the counters so players understand the distinction between carried rocks and stored rubble.
The hand should be selected while collecting rocks. The interaction button should say PICK UP only when a valid rock is within range and can be collected.
When the basket is full, prevent collection and show a brief actionable message: "Basket full. Deposit your rocks at the station."
Do not repeatedly stack the same notification while the player holds an input. Maintain a clear center crosshair in first person.

## 8. HUNT HUD: STATION
At the player's station, show relevant station information: current carried rocks; deposited queue and capacity; processing state when applicable.
The contextual action should follow the existing interaction rules: DEPOSIT ROCKS when depositing is valid; the existing processing action when cracking is valid; a clear disabled or unavailable state when the action cannot run.
Do not display conflicting actions over the same button.
Show a short processing indicator near the station or in a compact HUD element. It must reflect actual server-confirmed processing state.
A processing bar must not continue after the player leaves, changes tools, the round ends, or the operation is canceled.
Keep the target rock visually neutral until the legitimate reveal.

## 9. UPGRADES: SHARED SHOP SHELL
Use the reference's compact two-column layout: catalog on the left; selected item preview and details on the right.
Preserve the existing tabs: Tools, Machines, Storage, Tiers, Gallery. Only show tabs that correspond to existing implemented systems.
Use real catalog data for: names, prices, requirements, effects, ownership, equipped state, upgrade availability.
Show clear action states: Buy, Upgrade, Equip, Equipped, Owned, Locked, Not enough cash, Purchasing. Use the correct state for the actual item. Do not label every action SELECT simply because the reference uses that word.
Purchases and equipment changes must remain server-validated. Disable repeat activation while a request is pending. Update the interface from authoritative results.

## 10. TOOLS AND MACHINES
Use consistent illustrated thumbnails or clean ViewportFrame previews. The selected preview should be large enough to identify the item without leaving excessive empty space.
Where appropriate, show: tool name; actual useful stat or effect; actual price or requirement; ownership or equipped state; one clear primary action.
For automatic machines, explain their existing behavior: "Processes deposited rocks automatically." Do not imply that automatic machines collect from the shared pile.
Use actual models from the game when possible. If rendering them in a ViewportFrame, frame each model properly and isolate its preview lighting. Avoid cropped tools, tiny previews, inconsistent camera angles, and clipping through the preview frame.

## 11. STORAGE, TIERS, AND GALLERY CAPACITY
Storage should clearly distinguish: carry basket capacity; station input queue capacity; rubble storage capacity. Show current and next values from the real configuration where an upgrade exists.
Tier screens must use the actual tier system and its existing benefits. Do not show the reference's development placeholder "Use existing tier progression." Replace it with actual player-facing information.
Gallery capacity must use the existing capacity progression. Do not implement a nine-slot upgrade just because the generated image shows one. Preserve the configured capacities and costs.

## 12. COLLECTION
Use the reference's specimen grid and selected-item preview. The collection should: show owned specimens clearly; support the existing selection behavior; present meaningful information for the selected specimen; provide the existing display action; show display slot usage separately from collection storage usage.
Do not confuse collection inventory capacity with world display capacity. For unknown entries, preserve the existing discovery rules. Do not expose undiscovered specimen identities if the current system conceals them. Do not fabricate rarity labels, collection entries, or specimen properties.
When no specimens are owned, show: "No geodes yet." "Find one in a hunt." Provide a Start Hunt action that opens the real hunt flow.

## 13. DISPLAY MANAGEMENT
Use the same collection shell with the Display tab selected. Show actual display slots and their contents.
Allow players to: select a slot; place an owned specimen through the existing system; replace a displayed specimen where supported; remove a displayed specimen.
Show which specimen is currently selected and which slot will be affected. Prevent invalid actions and duplicate placement according to the existing rules. Changes must update the real world display and persist through the existing save system.

## 14. RECORDS
Keep Solo Finds, Competitive Wins, and Matches Played distinct where those records exist. Show real server-provided data.
If records are unavailable, show a compact error state with Retry and Close. Do not fabricate zero values as though they were successfully loaded. A failed leaderboard request should not block the rest of the collection or lobby interface.

## 15. START HUNT
Build the compact Solo Hunt / Party Hunt screen. Explain the premise briefly: "One pile. One geode."
Solo starts the existing solo flow. Party Hunt opens or creates the existing party flow. Do not add public matchmaking if the current design uses private parties.
Show loading and pending states during the real start operation. Prevent double-start requests.

## 16. PARTY MEMBERS, INVITES, AND INVITATIONS
Use the reference's compact member list. Show: real player names and avatars where available; party leader; actual party size; existing readiness state, if implemented; empty slots; Start Hunt for the leader; Leave for members.
Do not invent a ready system if the game does not use one. Invite lists must show eligible players only.
Invitation dialogs need: inviter identity; Accept; Decline; expired or unavailable handling.
Update the interface when a player leaves, disconnects, accepts, declines, or when the leader changes. If the party is full, do not continue showing valid Invite actions. Preserve existing server validation and party permissions.

## 17. RESULTS
Build the compact results panel from the reference. Show: actual winner; the discovered target geode; the local player's actual ordinary earnings; the local player's actual processing statistics, if tracked; whether the local player received the specimen.
Do not show "Geode added to collection" to every participant. That message is for the actual recipient. Solo results should use appropriate solo wording. Party results should explain who found the geode without implying every player won.
Play Again must use the existing rematch behavior and permissions. Do not let a non-leader independently start a conflicting party round. Lobby returns through the existing flow.

## 18. SETTINGS
Restyle the existing settings in the new visual language. Include Music, Sounds, Camera Sensitivity, and Reduce Motion only where the game supports them. Implement appropriate local behavior for these presentation settings if they are missing and fit the current architecture.
Settings must actually affect the game. Use readable slider values or clear feedback. Support touch dragging without moving the camera underneath. Reduce Motion should reduce decorative UI movement and unnecessary camera effects without removing important gameplay feedback. Persist preferences using the existing settings system where available.

## 19. NOTIFICATIONS AND CONFIRMATIONS
Implement a consistent compact notification system. Examples: Basket full; Station queue full; Not enough cash; Purchase successful; Purchase failed; Geode added to collection; No rubble to sell; Party invitation expired.
Use short actionable text. Coalesce repeated messages rather than piling them up. Important messages should remain readable for an appropriate duration.
Purchase confirmations must show the actual item, price, currency, and consequence before confirmation. Do not show a generic confirmation with no transaction details. Confirmations must not perform the purchase until Confirm is activated.

## 20. RUBBLE SALE
Use a compact interaction prompt at the existing seller. Show the actual rubble amount. Selling must use the existing server-side calculation. Show the authoritative sale result.
If the player has no rubble, show a short "No rubble to sell" message. Do not display fake earnings. The selling interaction must not overlap movement controls or cause an accidental tool action.

## 21. MOBILE, DESKTOP, AND RESPONSIVE LAYOUT
The reference boards establish appearance, not fixed pixel coordinates. Use responsive layout constraints, padding, lists, grids, and scrolling. Respect device safe areas and Roblox interface insets.
Ensure: no important controls hide beneath the native joystick; no action buttons overlap the native jump button; text remains readable on small phones; close buttons remain easy to tap; long item names wrap or truncate intentionally; catalog lists scroll properly; modals fit the available viewport; selection previews remain useful at narrow sizes.
On smaller screens, adapt the two-column shop into an appropriate compact layout without squeezing every element until it becomes unreadable. Do not uniformly scale a desktop canvas down to a tiny phone UI.

## 22. ANIMATION AND SOUND
Use restrained UI transitions: brief modal entrance; small button press feedback; clear tab selection; short notification entrance and exit.
Avoid elastic bouncing, excessive shaking, large zooms, and repeated glowing effects. Cancel old tweens before conflicting transitions. Honor Reduce Motion.
Use the game's existing suitable UI sounds where possible. Do not invent audio asset IDs or depend on inaccessible assets.

## 23. ASSETS AND TECHNICAL QUALITY
Use existing usable assets first. For illustrated icons, use available approved textures or create consistent simple assets through the project's actual supported workflow. Do not invent Roblox image IDs.
Use ViewportFrames for real tools and specimens where appropriate. Keep previews efficient: no unnecessary live world models; no physics simulation; no accumulating connections; no continuously rotating every catalog thumbnail; clean up previews when the screen closes.
Avoid rebuilding entire screens every frame. Update values only when their underlying state changes. Disconnect event listeners and cancel outstanding UI work when controllers are destroyed.
Maintain clear client/server boundaries. The client presents state; the server validates purchases, inventories, processing, round wins, and party operations.

## 24. REMOVE THE OLD INTERFACE CLEANLY
After replacing the screens: remove obsolete UI instances; remove duplicate screen creators; remove unused controllers and conflicting bindings where safe; ensure only one active interface responds to each entry point; ensure old styles do not appear during loading or transitions. Do not delete unrelated gameplay systems.

## 25. VERIFY BEFORE CALLING IT COMPLETE
Check the implemented interface in the actual game. Verify: lobby entry points open the correct screen; hunt-only counters disappear outside hunts; collecting and station interactions show correct actions; menus do not allow clicks to swing tools underneath; closing menus restores first-person input; shop values match the real catalog; purchase failures and successful purchases update correctly; owned and equipped states are accurate; collection and world displays remain synchronized; empty collection states work; party leader and member permissions remain correct; invitation expiration and party-full states work; results distinguish winner rewards from ordinary earnings; Solo Finds and Competitive Wins remain separate; loading, retry, and unavailable states work; mobile layouts avoid joystick and jump overlap; reopening menus repeatedly does not create duplicate handlers; player progress remains intact.
Do not claim multiplayer, mobile, purchase, or persistence tests passed unless they were actually performed.

## DELIVERABLE
Implement the redesign, then provide: 1) a concise list of changed scripts and UI systems; 2) screenshots of the implemented lobby HUD, hunt HUD, upgrades, collection, party, and results screens; 3) a summary of verification performed; 4) any remaining asset or testing limitations.
Prioritize a cohesive, working interface that closely matches the attached boards. Preserve the actual game beneath it.
