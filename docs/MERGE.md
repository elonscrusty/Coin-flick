# Merge: Find The Pet + COIN FLICK

Base game = Find The Pet (map, plots, pets, eggs, saves). Built from elonscrusty/Crack-the-rocks main b578be3.
COIN FLICK's earlier code (build 2, branch claude/project-thread-2ldrkw) is parked unchanged in `coin/` and is not built.

## Step 1 (done): FTP builds here
`bash tools/check.sh` passes (typecheck, compile, 648 rule tests, Rojo build).
Left out to keep the repo small: generated preview json under docs/, big reference PNGs, art/compare, art/previews.

## Step 2 (next): a separate coin section on the map
Players walk over coins/floor pads to flip them for cash. Cash buys eggs and pets. Pets stay at the plots.
Port from `coin/`: flip logic (`coin/src/server/Util/GameLogic.luau`), floor pads, rarity.
Rules: server decides every flip; every egg shows its odds before buying; Robux ids/prices only from the owner.
