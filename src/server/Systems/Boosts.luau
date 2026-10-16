--!strict
-- Who has what extra right now: Robux passes (from Robux) and the server-wide
-- mega boost (from Mega). Tables reads it for every flip. No requires, so any
-- system can use it without require loops.

local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Boosts = {}

local passes: { [Player]: { [string]: boolean } } = {}
local megaUntil = 0

function Boosts.setPass(player: Player, key: string, owned: boolean)
	local owns = passes[player]
	if not owns then
		owns = {}
		passes[player] = owns
	end
	owns[key] = if owned then true else nil
end

function Boosts.owns(player: Player, key: string): boolean
	local owns = passes[player]
	return owns ~= nil and owns[key] == true
end

function Boosts.passes(player: Player): { [string]: boolean }
	return passes[player] or {}
end

function Boosts.startMega(now: number)
	megaUntil = now + Config.MEGA_BOOST_SECONDS
end

function Boosts.megaLeft(now: number): number
	return math.max(0, megaUntil - now)
end

-- Extra cash multiplier for this player's heads (2x pass x mega boost).
function Boosts.cashMult(player: Player, now: number): number
	local mult = 1
	if Boosts.owns(player, "doubleCash") then
		mult *= Config.PASS_CASH_MULT
	end
	if now < megaUntil then
		mult *= Config.MEGA_BOOST_MULT
	end
	return mult
end

function Boosts.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		passes[player] = nil
	end)
end

return Boosts
