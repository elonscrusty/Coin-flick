--!strict
-- Pet level-up flourish (client only, cosmetic). Watches the local profile's pets (State.Profile.Inventory, level from
-- TowerXP via PetRules.level, the same number the Pet Book and tower show). When one of them goes up a level while it
-- is following the local player, PetFx draws a ring of light and "LEVEL UP!" over that follower and it spins once
-- (PetFollow.spin). The first profile only sets the baseline, so joining never plays it. Nothing is sent anywhere.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetRules = require(Shared.PetRules)
local State = require(script.Parent.State)
local PetFollow = require(script.Parent.PetFollow)
local PetFx = require(script.Parent.PetFx)
local Audio = require(script.Parent.Audio)

local PetLevelFx = {}

local levels: { [string]: number } = {}
local primed = false

local function scan()
	local prof = State.Profile
	local inv = prof and prof.Inventory
	if type(inv) ~= "table" then
		return
	end
	local ups: { { Id: any, Level: number } } = {}
	for _, g in inv :: { any } do
		if type(g) == "table" and g.Id ~= nil then
			local key = tostring(g.Id)
			local lv = PetRules.level(g)
			local before = levels[key]
			if primed and before and lv > before then
				table.insert(ups, { Id = g.Id, Level = lv })
			end
			levels[key] = lv
		end
	end
	primed = true
	local me = Players.LocalPlayer
	if #ups > 0 then
		-- any pet levelled (hunt XP, tower, training): one level-up chime; Audio's 2 s cooldown merges it with the
		-- Pet Battle panel's own training level-up sound
		Audio.play("LevelUp")
	end
	for i, up in ups do
		if i > 3 then
			break
		end
		local model = me and PetFollow.modelFor(me, up.Id)
		if model then
			pcall(PetFx.levelUp, model, up.Level)
			PetFollow.spin(me, up.Id) -- and the pet spins once
		end
	end
end

local started = false
function PetLevelFx.start()
	if started then
		return
	end
	started = true
	scan()
	State.Changed.Event:Connect(function(what)
		if what == "Profile" then
			scan()
		end
	end)
end

return PetLevelFx
