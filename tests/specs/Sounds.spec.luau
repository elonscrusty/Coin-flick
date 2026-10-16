local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local SoundPick = require(ReplicatedStorage.Shared.Util.SoundPick)

-- carter's uploaded ids, copied from Find The Pet's SoundIds.luau (b578be3).
local UPLOADED: { [string]: number } = {
	Tap = 137600997709297, -- Button
	Heads = 73948288584672, -- CoinPickup
	Skull = 112800468947570, -- Pickup
	Buy = 120358225055021, -- Purchase
	Reset = 74062661586425, -- LevelUp
	Rare = 109340819460170, -- RarityAccent
	Combo = 74274333382741, -- LuckyMeter
	Mega = 109965175431278, -- MatchWin
	Daily = 119151410036137, -- DailyClaim
	Gift = 94176845962719, -- GiftOpen
	JobDone = 123258283238472, -- QuestDone
	Denied = 109439887902047, -- Denied
}

describe("Sounds", function()
	it("every sound the game plays exists", function()
		for _, name in
			{ "Tap", "Flip", "Land", "Heads", "Skull", "Buy", "Reset", "Rare", "Combo", "Mega", "Gift", "Denied" }
		do
			expect(Config.Sounds[name] ~= nil).toBeTruthy()
		end
	end)

	it("uses carter's uploaded ids, never made-up ones", function()
		for name, def in Config.Sounds do
			if def.id ~= 0 then
				expect(UPLOADED[name]).toBe(def.id)
			end
		end
		for name, id in UPLOADED do
			expect(Config.Sounds[name].id).toBe(id)
		end
	end)

	it("every sound has a built-in fallback", function()
		for _, def in Config.Sounds do
			expect(string.sub(def.fallback, 1, 18)).toBe("rbxasset://sounds/")
		end
	end)

	it("plays the uploaded id, and the fallback if it fails or is missing", function()
		local def = Config.Sounds.Heads
		expect(SoundPick.source(def, false)).toBe("rbxassetid://73948288584672")
		expect(SoundPick.source(def, true)).toBe(def.fallback)
		expect(SoundPick.source(Config.Sounds.Flip, false)).toBe(Config.Sounds.Flip.fallback)
	end)
end)
