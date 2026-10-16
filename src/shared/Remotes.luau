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
	}),
	-- Only created when running in Roblox Studio. Never exists in a live game.
	StudioOnly = table.freeze({
		"Cheat", -- client -> server: (command: string)
	}),
})
