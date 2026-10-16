-- battle: Pet Battle + training (ui/PvpPanel, server/PvpService). --set view=card (default) | train | tower |
-- queue | fight | result | finisher | loss | live (the lobby arena). tower = TOWER from the train card. inspect = tapping
-- another player's following pet (the card the server sends). The player has three pets; card/train open from the HUD BATTLE button, fight queues and lets the bot step
-- in (PvpConfig.BotAfter), then stops mid-fight; result plays the fight to the end. intro = the fight camera's opening
-- sweep (mid count-in). --set ring=1 (with view=fight) stops when a BLOCK ring is up. --set big=1 puts the fight on a stand-in of the Studio stadium (64-stud floor, FightRadius 30).
local C = lib("ctr")
local PvpConfig = preview.shared("PvpConfig")
local view = preview.args.view or "card"
if preview.args.log then
	workspace:SetAttribute("FightCamLog", true) -- FightCam prints FCLOG lines (the Studio check log)
end
local booted = C.boot({
	others = if view == "inspect" then { { "Ava", 2 } } else nil,
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
		data.Onboard.Skipped = true
		local pets = C.fakeSpecimens(5)
		for i, g in pets do
			g.Id = "pet" .. i
		end
		-- two spare copies of pet1, which sits at its level cap: its row offers EVOLVE
		for k = 1, 2 do
			local c = table.clone(pets[1])
			c.Id = "copy" .. k
			c.Seed = pets[1].Seed + k
			table.insert(pets, c)
		end
		-- a variant with a long name (Studio 2026-10-16: "Skeleton Thunderstrut" hid its level on a phone card)
		pets[2].Modifier = "Skeleton"
		data.InventoryGeodes = pets
		data.EquippedPets = {}
		data.TowerXP = { pet1 = 1e7, pet2 = 300 }
		data.Pvp = { Trophies = 172, Streak = 2, BestStreak = 4, Wins = 9, Losses = 5 }
	end,
})
C.settle(1)
if preview.args.big then
	local spawn = C.lobbySpawn()
	local floor = Instance.new("Part")
	floor.Name = "StadiumFloorStandIn"
	floor.Anchored = true
	floor.Size = Vector3.new(64, 1, 64)
	floor.Color = Color3.fromRGB(196, 170, 120)
	floor.CFrame = CFrame.new((spawn * CFrame.new(0, -2.5, -50)).Position)
	floor:SetAttribute("ArenaCenter", true)
	floor:SetAttribute("FightRadius", 30)
	floor.Parent = workspace
elseif view == "live" or view == "board" then
	-- a stand-in for the Studio-built lobby arena: an 18.5-stud floor 30 studs in front of spawn
	local spawn = C.lobbySpawn()
	local floor = Instance.new("Part")
	floor.Name = "ArenaFloorStandIn"
	floor.Anchored = true
	floor.Size = Vector3.new(18.5, 1, 18.5)
	floor.Color = Color3.fromRGB(196, 170, 120)
	floor.CFrame = CFrame.new((spawn * CFrame.new(0, -2.5, -30)).Position)
	floor:SetAttribute("ArenaCenter", true)
	floor.Parent = workspace
end
local function tap(name: string)
	local hits = preview.findGui(function(obj)
		return obj:IsA("GuiButton") and obj.Name == name and obj.Parent ~= nil
	end)
	if hits[1] then
		preview.click(hits[1])
		print(name .. " found")
	else
		print("[FAIL] " .. name .. " missing")
	end
	C.settle(1)
end
if view ~= "inspect" then
	tap("BattleButton")
end
if view == "inspect" then
	local ava = booted.others[1]
	local Profiles = C.server("Profiles")
	local hers = Profiles.get(ava)
	if hers then
		local g = C.fakeSpecimens(1)[1]
		g.Id = "avapet"
		g.Rarity = "Legendary"
		g.Evolve = 1
		hers.InventoryGeodes = { g }
		hers.EquippedPets = { "avapet" }
		hers.TowerXP = { avapet = 30000 }
		hers.Pvp.Trophies = 640
		C.server("PvpService").action(game:GetService("Players").LocalPlayer, { Op = "Inspect", UserId = ava.UserId, Pet = "avapet" })
		print("inspect sent")
	else
		print("[FAIL] no second profile")
	end
	C.settle(1)
elseif view == "train" then
	tap("Train")
	tap("TrainBtn")
elseif view == "tower" then
	tap("Train")
	tap("Tower")
elseif view == "queue" then
	tap("Fight")
	C.settle(4)
elseif view == "finisher" or view == "loss" then
	-- the player's pets drop to 1 HP mid-fight, so the rival wins: finisher camera, then (loss) the result card
	tap("Fight")
	C.settle(PvpConfig.BotAfter + PvpConfig.CountIn + 2)
	local me = game:GetService("Players").LocalPlayer
	local f = C.server("PvpService").fightOf(me)
	if f then
		for _, u in f.Rules.Units do
			if u.Side == 1 then
				u.Hp = 1
			end
		end
	end
	C.settle(if view == "loss" then 8 else 3)
elseif view == "live" or view == "board" then
	tap("Fight")
	C.settle(PvpConfig.BotAfter + PvpConfig.CountIn + 7)
	if view == "board" then
		-- what a spectator sees: the arena and the fight board over it, from the path
		local slab = workspace:FindFirstChild("FightBoard") and workspace.FightBoard:FindFirstChild("Slab") :: BasePart?
		if slab then
			local cam = workspace.CurrentCamera
			cam.CFrame = CFrame.lookAt((slab.CFrame * CFrame.new(0, -2, -30)).Position, (slab.CFrame * CFrame.new(0, -4, 0)).Position)
			cam.FieldOfView = 60
			print("board found")
		else
			print("[FAIL] board missing")
		end
	end
elseif view == "intro" then
	tap("Fight")
	C.settle(PvpConfig.BotAfter + 1.4)
elseif view == "fight" or view == "result" then
	tap("Fight")
	C.settle(PvpConfig.BotAfter + PvpConfig.CountIn + 1.5)
	if view == "result" then
		C.settle(70)
	elseif preview.args.ring then
		-- --set ring=1: stop the moment a BLOCK ring is up on one of our pets (tap to fight, TapFight)
		local gui = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		for _ = 1, 120 do
			C.settle(0.1)
			if gui and gui:FindFirstChild("BlockRing") then
				C.settle(0.3)
				break
			end
		end
	else
		C.settle(6)
	end
end
if view ~= "fight" and view ~= "finisher" and view ~= "live" and view ~= "board" and view ~= "intro" then -- fights keep the camera PvpPanel set
	C.followCamera()
end
C.settle(0.3)
