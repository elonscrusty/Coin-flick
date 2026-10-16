--!strict
-- The one list of remotes. The server creates them all at startup.
-- Clients only ever send "I tapped coin N" / "I want to buy X"; the server decides everything.

return table.freeze({
	Events = table.freeze({
		"TapCoin", -- client -> server: (coinIndex: number)
		"BuyUpgrade", -- client -> server: (upgradeId: string)
		"BuyHelper", -- client -> server: (helperId: string) unlock a helper
		"LevelHelper", -- client -> server: (helperId: string)
		"TeamHelper", -- client -> server: (helperId: string, on: boolean)
		"ResetTable", -- client -> server: ()
		"State", -- server -> client: (Snapshot)
		"Flipped", -- server -> all: (FlipEvent)
		"Notice", -- server -> client: (Notice)
		"TapMega", -- client -> server: ()
		"MegaState", -- server -> all: (MegaState)
		"MegaFlipped", -- server -> all: ()
		"BuyHat", -- client -> server: (hatId: string)
		"WearHat", -- client -> server: (hatId: string, "" = take off)
		"ChooseSkin", -- client -> server: (skinId: string, "" = classic)
		"BuyRobux", -- client -> server: (item: string) server opens the Roblox buy window
		"Leaderboards", -- server -> client: (Leaderboards)
		"DailyState", -- server -> client: (DailyView)
		"ClaimGift", -- client -> server: ()
		"ClaimJob", -- client -> server: (slot: number)
<<<<<<< HEAD
		"GoalsState", -- server -> client: (GoalsView) ladder + weekly challenges + coin book
		"ClaimChallenge", -- client -> server: (slot: number, 0 = the all-three bonus)
		"WearLadder", -- client -> server: (rungId: string, "" = take it off)
=======
		"PlayGiftState", -- server -> client: (PlayGiftView)
		"ClaimPlayGift", -- client -> server: (slot: number)
		"BadgeState", -- server -> client: (BadgeView)
		"EventState", -- server -> all: (EventView) weekend luck x2 / coin rain, sent on join and on change
>>>>>>> origin/claude/project-thread-exhqff
		"PetEquip", -- client -> server: (petId: string, "" = put pets away)
		"PetState", -- server -> client: (views: { PetRules.PetView }, activeId: string)
		"PetFlipped", -- server -> client: (petId, cash, level, leveledUp)
	}),
	-- Only created when running in Roblox Studio. Never exists in a live game.
	StudioOnly = table.freeze({
		"Cheat", -- client -> server: (command: string)
	}),
})
