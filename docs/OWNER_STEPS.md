# Owner steps

## Try it in Roblox Studio (computer needed)
1. Download `build/CrackTheRocks.rbxlx` from the repo (or the file sent in chat).
2. Open it in Roblox Studio (File > Open from File).
3. Press **Play**. You spawn in the lobby.
4. Tap **PARTY** (left side) and then **SOLO HUNT**. Your first hunt is a 12-rock practice pile.
5. In the quarry, tap a rock to pick it (or just stand close), then hold **HOLD TO CRACK**
   (PC: hold **E**, gamepad: hold **R2**).
6. When the button says "STORAGE FULL", walk to an orange **SELL RUBBLE** hopper and press its
   prompt (PC: **R**).
7. The first hunt is a practice pile with hints: sell your rubble, then put your geode on show in
   your lobby gallery (or tap SKIP TUTORIAL). After that, results offer **HUNT AGAIN** / **LOBBY**.

To test a party with friends inside Studio: Test tab > Clients and Servers > 2 players > Start.
One player taps PARTY > CREATE PARTY and invites the other from the list.

## Saves in Studio
Studio can only save if API access is on. Without it, the game still runs but shows
"SAVES OFF (Studio)" under your Cash and nothing is written.
To turn saving on in Studio (your choice, Claude won't do this):
Home > Game Settings > Security > "Enable Studio Access to API Services" > Save.
Studio uses separate test saves (`_Studio` stores), so it never touches real player saves.

## Studio dev shortcuts
For screenshots. They only work in a Studio playtest; in the live game they do nothing (the server checks
`RunService:IsStudio()`; code in `src/server/DevCommands.server.luau`). Type them in the chat box:
- `/endround`: during a hunt search, ends the round at once as if you found the pet egg, so you go straight to the
  results. You get the round's pet like a normal find (saved only to the `_Studio` test saves).
- `/boss` or `/boss 10`: while you are inside the Pet Tower, jumps your climb to a boss floor. A number is rounded up to
  the next boss floor (every 5th floor); no number = the next boss floor above where you are.
- `/zone forest` (or `meadow`, `snow`, `volcano`, `space`; any capitals): shows that hunt zone's look (ground colours,
  border tint, landmarks). Inside a hunt it re-skins your own arena (only the look; the round's eggs stay the same).
  Outside a hunt it skins a free arena and moves you onto it, so you can walk around and take pictures. A wrong name
  lists the valid ones. The next real round puts its own zone back.
- `/coins 50000`: sets your coins to that number (0 to 10,000,000), for testing the egg shrine's 1x / 3x / 10x buys.
  Only the `_Studio` test saves change.
A small "[DEV]" message says whether it worked (for example "enter the tower first").

## Robux shop (EGG SHOP): create the products and passes
The shop is built but sells nothing until you create the items on the Creator Hub and paste their ids. Every id in
`src/shared/RobuxConfig.luau` is 0 with a `-- REPLACE` note; an item with id 0 shows "NOT FOR SALE YET" / "SOON". Pasted 2026-10-15: Starter Pack, Spooky Egg x1/x3/x10 (on sale until 2026-11-02 00:00 UTC), VIP, Auto Hatch and Open 3 Eggs passes.
You choose every price on Roblox; the game reads the price from Roblox and shows it ("R$ ?" until it loads).
1. Creator Hub > your experience > Monetization > Developer Products > Create. Make 10 products:
   Basic Egg x1, x3, x10; Rare Egg x1, x3, x10; Mythic Egg x1, x3, x10; Luck Potion. Copy each Product ID.
2. Monetization > Passes > Create a Pass, three times: 2x Coins, Pet Storage+, Extra Plots. Put each on sale and
   copy its Pass ID. (Extra Plots does nothing until plots are added; the shop says so.)
3. Send the ids to Claude (or paste them yourself): eggs go in `RobuxConfig.Eggs[...].Products = { [1] = id, [3] = id,
   [10] = id }`, the potion in `RobuxConfig.Potion.ProductId`, the passes in `RobuxConfig.Passes.<Name>.PassId`.
4. Check the odds tables for the Rare and Mythic eggs in `RobuxConfig.Eggs` (each adds up to 100) and the luck numbers
   (`MaxLuck`, `Events`). Change them only through Claude so the shop card stays right.
5. Test in Studio (Play): buy each item with Studio's test purchase (no real Robux), check the pet arrives, the potion
   timer shows in the EGG SHOP, a 10x egg gives 10 pets, and the hatch stand by the shop plays the show.
   Real purchases must be checked once in the live game too.

## Weekly pets (new pet every week)
10 of the new pets unlock one per week (list: `Config.WeeklyPets.Order` in `src/shared/Config.luau`). They stay hidden
until you set the first drop day: put the UTC time in seconds into `Config.WeeklyPets.Start` (for example the day you
publish). Week 1 unlocks at that time, week 2 seven days later, and so on. Each one needs its model `Pet_<id>` in
`ReplicatedStorage.PetModels` before its week; until then it uses a stand-in body.

## Low-poly world kit (your hand-made meshes)
Put these in a folder named exactly `WorldKit_LowPoly` directly in `ReplicatedStorage` (each one a MeshPart, or a
Model holding one MeshPart, named exactly like this; a `.001` ending is fine):
- `HuntEgg_Pink`, `HuntEgg_Blue`, `HuntEgg_Green`, `HuntEgg_Yellow`: the hunt pile eggs (all four, or none is used).
- `NestTable`: the hatch nest table body (stretched to 7 x 3 x 4 studs; top = the work surface).
- `StonePad`: the pad under each nest table in the hunt (stretched to the old pad, 11.6 x 0.3 x 8.8 studs).
- `NoticeBoard`: the LAST WINNERS board, placed on the ground beside the WHAT'S NEW board. The text goes on a
  7.4 x 3.3 stud panel assumed centred on the mesh's front; if it misses, change `PANEL_OFFSET` / `PANEL_DEPTH` in
  `src/server/WinnerBoard.luau`.
Each mesh: sized in studs, front facing -Z, textured (the texture is kept). Any piece that is missing keeps the old
look. Code: `src/shared/WorldKit.luau`.

## Group gift (optional)
Members of your Roblox group get 100 free coins a day. Make a group on roblox.com, copy the number in its web
address, and paste it as `Retention.Group = { Id = <number>, ... }` in `src/shared/Retention.luau`. 0 = off.

## Game sounds: upload the made sounds (PC helper, 2 minutes)
26 short sounds are made and saved in `art/sfx` (hatch sparkle, drum hit, pet found, battle, training, level up,
evolve, gifts, quests, Lucky Meter, "not allowed" bonk...). Until they are uploaded the game plays nothing (or the old
sound) at those moments; nothing breaks. No roars anywhere. Whoever has your PC runs, in the repo folder:

```
ROBLOX_USER_ID=20194281 python3 tools/upload_audio.py --key-file <path to the Roblox key file on Carter's PC>
```

- The key file holds only the Open Cloud API key (Assets read + write for your account). The script reads it and
  never prints it. Do not paste the key into chat or a commit.
- It uploads only files without an id yet, writes `art/sfx/uploaded_ids.json`, and rewrites `src/shared/SoundIds.luau`.
  Commit both files and push; the new sounds then play by themselves (`PetSoundIds` reads the ids from there).
- A file Roblox refuses keeps id 0 (silent). Run the same line again later to retry.
- Then play once in Studio and listen: hatch a pet, do a Pet Battle, train, claim the daily gift.

## Not needed yet
- No assets to upload yet. Rocks, geodes, tools and buildings are built from plain parts for now.

## Separate Lobby and Match places (Teleport mode, optional)
The game works as one place by default (`Config.Places.Mode = "SinglePlace"`), also in Studio. Teleport
mode sends each party to its own private Match server. It is switched off until you do these steps.
Claude cannot do them (no publishing) and cannot test teleports: they do not run in Studio.

1. Open the game on the Roblox site (Creator Hub > your experience > Places). Click **Create place**
   and name it e.g. "Crack the Rocks - Match". It must be in the SAME experience as the lobby.
2. Copy both place ids (the number in each place's URL, or the "..." menu > Copy Place ID).
3. In `src/shared/Config.luau`, section `Config.Places`, set `LobbyPlaceId` and `MatchPlaceId` to those
   numbers and `Mode = "Teleport"` (or ask Claude to). Rebuild: `bash tools/check.sh`.
4. Publish the lobby from `build/CrackTheRocks.rbxlx` (File > Publish to Roblox As... > the lobby place).
5. Open `build/CrackTheRocksMatch.rbxlx` and publish it to the Match place the same way
   (File > Publish to Roblox As... > the Match place). Both files contain the same scripts; the server
   picks its job from the place id.
6. Game Settings > Security: leave "Enable Studio Access to API Services" as it is for live play.
   Teleports need the experience to be public or at least playable by your test accounts.
7. Test live with two accounts on two devices: invite, ready, START. Check the loading card, that both
   arrive, the hunt runs, LOBBY / ALL TO LOBBY bring you back, and your cash and geodes are still there.
   Also try: one account quits during the 30 s wait (leader gets START WITH ARRIVED / RETURN ALL).
To go back to one place at any time, set `Mode = "SinglePlace"` again; nothing else changes.
