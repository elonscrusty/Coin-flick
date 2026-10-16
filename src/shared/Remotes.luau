--!strict
-- The one list of remotes. The server creates them all at startup.
-- Clients only ever send "I tapped coin N" / "I want to buy X"; the server decides everything.

return table.freeze({
	Events = table.freeze({
		"TapCoin", -- client -> server: (coinIndex: number)
		"BuyUpgrade", -- client -> server: (upgradeId: string)
		"BuyHelper", -- client -> server: ()
		"ResetTable", -- client -> server: ()
		"State", -- server -> client: (Snapshot)
		"Flipped", -- server -> all: (FlipEvent)
		"Notice", -- server -> client: (Notice)
	}),
	-- Only created when running in Roblox Studio. Never exists in a live game.
	StudioOnly = table.freeze({
		"Cheat", -- client -> server: (command: string)
	}),
})
