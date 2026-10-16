-- disc: Material Discovery pictures (docs/m6/DISCOVERIES.md), all through the real server and client.
--   --set view=notice   hunt where a real crack reveals a first-time material (Common Stone already known, so the
--                       first Quartz / Metal crack shows "Material discovered"); the picture is taken while the toast is up
--   --set view=hud      hunt a few seconds in, objective "Find the geode", "Rocks left in pile", timer
--   --set view=sell     9 rubble in the bag, the avatar at the arena hopper: SELL RUBBLE with the preview card
--   --set view=receipt  the same, then the real action button is pressed: the receipt toast
--   --set view=empty    empty bag at the hopper: no sell action
--   --set view=collection --set mats=none|some|all   Collection > Materials (profile data written by the server)
local C = lib("ctr")
local view = preview.args.view or "notice"
local mats = preview.args.mats or "some"
local s = C.boot({
	profile = function(data, Config)
		data.Cash = 640
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.CapacityTier = 2
		if view == "notice" or view == "hud" then
			data.Materials = { Found = { CommonStone = true }, Counts = { CommonStone = 14 } }
		elseif view == "sell" or view == "receipt" then
			data.RubbleByTier = { Gravel = 9 }
			data.Materials = { Found = { CommonStone = true, QuartzFragment = true }, Counts = { CommonStone = 6, QuartzFragment = 3 } }
		elseif view == "collection" then
			if mats == "some" then
				data.Materials = { Found = { CommonStone = true, QuartzFragment = true }, Counts = { CommonStone = 31, QuartzFragment = 6 } }
			elseif mats == "all" then
				data.Materials = { Found = { CommonStone = true, QuartzFragment = true, MetallicSpecks = true }, Counts = { CommonStone = 118, QuartzFragment = 19, MetallicSpecks = 7 } }
			end
			data.InventoryGeodes = C.fakeSpecimens(3)
			data.DisplayAssignments = { data.InventoryGeodes[1].Id }
		end
	end,
})

if view == "collection" then
	C.settle(1)
	C.tap("^COLLECTION$")
	preview.advance(0.3)
	C.tap("^MATERIALS$")
	C.settle(1)
	C.followCamera()
	return
end

local w = C.watchMatch()
local announced = 0
local ev = game:GetService("ReplicatedStorage").Remotes.MatchEvent
ev.OnClientEvent:Connect(function(kind)
	if kind == "MaterialFound" then
		announced += 1
	end
end)
C.startSolo(w)
C.waitPhase(w, "Searching", 6)
preview.advance(0.5)

local function nearestHopper()
	local best, bestD
	local root = s.me.Character and s.me.Character:FindFirstChild("HumanoidRootPart")
	for _, d in game:GetService("Workspace"):GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Hopper") then
			local body = d:FindFirstChild("Body")
			if body and root then
				local dist = (body.Position - root.Position).Magnitude
				if not bestD or dist < bestD then
					best, bestD = body, dist
				end
			end
		end
	end
	return best
end

if view == "notice" then
	C.crackUntilFound(w, { s.me }, 600, { stopWhen = function()
		return announced > 0
	end })
	preview.advance(0.7)
	C.followCamera(16, 8)
elseif view == "hud" then
	C.crackUntilFound(w, { s.me }, 600, { stopAfterDone = 4 })
	preview.advance(0.5)
	C.followCamera(16, 8)
else
	local hopper = nearestHopper()
	if hopper then
		-- stand in front of the hopper (its front faces the arena centre)
		local center = w.last.Init.Center
		local dir = (center - hopper.Position)
		dir = Vector3.new(dir.X, 0, dir.Z).Unit
		C.place(s.me, CFrame.lookAt(hopper.Position + dir * 6 - Vector3.new(0, hopper.Size.Y / 2 - 0.1, 0), hopper.Position))
	else
		preview.warn("no hopper found")
	end
	if view == "empty" then
		local d = s.Profiles.get(s.me)
		d.RubbleByTier = {}
		s.Profiles.changed(s.me)
	end
	C.settle(1.5)
	if view == "receipt" then
		-- the action button sends exactly this remote (PileView: ShopAction SellAtHopper); the server sells and replies
		C.fireServer("ShopAction", "SellAtHopper")
		preview.advance(0.4)
	end
	C.followCamera(9, 5)
end
