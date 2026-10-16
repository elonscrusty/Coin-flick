# Lodge visual correction and integration pass (owner brief, 2026-10-10)

(The owner refers to "actual Roblox screenshots"; none were attached to the session, so the comparison uses the latest preview renders, e.g. docs/m10/acceptance/01-spawn-pc.png and docs/lodge/renders/game/*, against docs/lodge/00_Approved_Lobby.png. If the owner's screenshots were from Studio, the blank signs are a real in-game problem, not only a preview limitation.)

Perform a visual correction and integration pass on the existing Find the Geode lodge. Keep the current building and layout. Compare the actual Roblox screenshots directly with the approved lobby reference. The architecture is recognizable, but the result is too dark, too orange, and missing essential visible information. Do not generate another lobby design or rebuild unrelated gameplay systems.

## 1. Investigate the missing text and leaderboards first
The screenshots show: blank Upgrades sign; blank Collection sign; blank Start Hunt sign; blank exterior title plaque; two empty black leaderboard faces.
Inspect the actual project to determine why each surface is blank. Check whether the required UI was created, whether it targets the correct face, whether it is enabled, whether its text has contrast, whether geometry covers it, and whether its controller initializes successfully.
For leaderboards, separately verify presentation and data loading. Inspect errors and trace the existing data source. Do not assume every blank board is a data problem.
Our modeling specification deliberately requested blank mesh faces for dynamic text. Those faces now require their actual Roblox presentation layer.
Complete the integration: UPGRADES on the red-awning counter; COLLECTION on the purple-awning counter; START HUNT above the three bays; FIND THE GEODE on the exterior plaque; SOLO FINDS on the left leaderboard; COMPETITIVE WINS on the right leaderboard.
Use bold white lettering with a controlled black outline, matching the approved reference.
Each leaderboard should permanently display five prominent ranking rows with rank, avatar, player name, and actual score. Keep solo and competitive records separate.
Use real data. If data is unavailable, retain the heading and show an honest loading, empty, or unavailable state. Never leave an unexplained black rectangle or fabricate rankings. Do not bake example usernames and scores into the models.

## 2. Correct the lighting
The current room appears substantially darker and more orange than the approved reference. Inspect the existing Lighting configuration, color correction, window transparency, roof geometry, and local lights before changing anything.
Establish neutral daylight first. Cream plaster should read as cream, gray stone should read as gray, and red/purple awnings should remain distinct. Then add modest warm lantern illumination.
Avoid fixing the darkness by adding many bright lights or increasing bloom. Preserve shadows and depth without leaving the counters, boards, and specimens difficult to see. Compare before and after screenshots from the same camera position.

## 3. Reduce floor contrast
The large dark outlines between floor stones dominate the current view. Keep the existing floor geometry if it is usable. Reduce the contrast of the grout and stone boundaries, soften the color variation, and use a more neutral base tone. Preserve a flat, comfortable collision surface. The floor should support the room visually, while signs, boards, awnings, and specimens attract attention.

## 4. Refine the collection counter
Preserve the violet, blue, and amber specimens. Inspect the bright outlines around their shells. If they come from selection effects or highlights, keep those effects limited to intentional interaction states rather than permanently outlining every specimen. Retain real faceted rock thickness and recessed crystals. Do not replace the specimens with flat images. Reduce the visual bulk of the mounts where needed. Use short, simple stands that support the specimens without competing with them. Keep crystals colorful and readable without relying on excessive glow. Make the lower display cabinet visible through restrained lighting and clear materials.

## 5. Finish the exterior
Complete the title plaque. Keep the existing building silhouette, roof, entrance, and foundation. Add restrained depth where broad plaster sections feel unfinished, using existing timber trim, wall-mounted lanterns, and deliberate planting placement.
Make the entrance approach feel connected to the lodge: clear path; finished step edges; consistent porch rails; a few grouped rocks and plants around the perimeter. Do not scatter props across the path, add outdoor shops, or build a new gameplay area.

## 6. Preserve the game
Keep all current progress, economy, tools, collection ownership, party rules, and hunt systems. The three bays access the existing solo/party hunt flow. Do not turn them into automatic public matchmaking. Keep the main floor open. Do not fill the room with additional assets to disguise lighting or signage problems.

## 7. Verify the actual result
Capture new Roblox screenshots of: entrance looking toward Start Hunt; each leaderboard close enough to read; Upgrades counter; Collection counter; exterior entrance. Use comparable camera positions to the supplied screenshots.
Verify the main signs are visible in game, boards display meaningful states, text is not covered by geometry, and the room remains readable on mobile.
Report the root cause of the blank signs and boards, changes made, and checks actually performed. Do not call this complete based only on Blender renders or mesh exports. Show the corrected result inside Roblox.
