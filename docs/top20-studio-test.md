# Top-20 fixes: Studio test sheet (main @ latest, 2026-10-15)

All items below PASS offline (568 tests). These steps prove them in Studio. Sync main first (Edit mode).

## 4. New kid test (fresh _Studio save, phone emulator)
Play the first 5 minutes as a new player: join, starter egg, practice hunt, results, Pet Book, Daily, train, battle a bot.
Note every bump (screenshot + one line). Check the items below along the way.

## Checks
1. Save safe: hatch starter pet, note coins, leave, rejoin: pet + coins there. Shutdown with 2 players: rejoin, coins there.
2. Friend fight: Test > Local Server, 2 players. P1 BATTLE > FIGHT!, ~3 s later P2. Both on the SAME island, no BOT tag, within 15 s. Repeat P2 first, and with ~12 s gap.
3. First pet: fresh save, DevAutoPet set: NO "New in your Pet Book" toast on join; starter egg shows "YOUR FIRST PET!".
6. Hunt hint (phone emulator): one line "Find the pet egg! Grab eggs (hold PICK UP)...", no "E". Gone after ~15 s or first pickup.
7. Hatch: Common shows no "1 in" line; rarer reads "1 in 250 chance!"; name + rarity appear together.
10. Hints: "Tap PET BOOK!" gone after ~10 s; "FREE PET!" tag gone after ~30 s at spawn.
11. Fight view: own avatar + hats never visible in a battle. No toast / NEXT GOAL card during the fight; they show ~1.5 s after.
12. Tower: floor 1 title pill gone before pets hit. "Floor cleared" card: no red X, only CONTINUE / LEAVE, text readable.
16. Leave mid-fight: P2 leaves during a battle: P1 gets the win, back in lobby, island gone.
18. Yard: 6 pets in the yard spread over the lawn (about 2 x 3), not on the back fence. tools/studio/yard_pet_check.luau.
5. Phone speed: Dev Console FPS + memory in full lobby, in a hunt, in a fight. Two hunts at once, finish, wait 2 min: only CT_Rocks_Arena_1 left.
20. Sounds (after upload, see below): hatch Epic (sparkle) + Legendary (drum), battle (matched, hit, crit, SPECIAL, K.O., win/lose), training taps (pitch climbs), level up, evolve, floor clear, daily, quest, gift, grey button tap, sale (one ding).

## Sound upload: DONE (72b3aba)
ROBLOX_USER_ID=20194281 python3 tools/upload_audio.py --key-file "C:\Users\myson\OneDrive\Desktop\crack butt holes\roblox_key.txt"
(Never prints the key.) Then commit + push art/sfx/uploaded_ids.json and src/shared/SoundIds.luau.
