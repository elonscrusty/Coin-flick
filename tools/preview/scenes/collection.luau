-- collection: the GEODES panel with made-up specimens in the real profile (GeodeGen.roll
-- shapes, sent through the real ProfileState): --set count=N specimens (default 9),
-- --set tab=Geodes|Index|Stats, --set detail=1 opens the first geode's detail page,
-- --set count=0 the empty state, --set nick=1 names the first pet, --set sort=Rarity|Level|Type, --set rename=1,
-- --set shiny=1 marks the first three pets SHINY (LaunchPerks.Shiny: gold tag on the card and the detail, 2x value).
local C = lib("ctr")
local count = tonumber(preview.args.count) or 9
C.boot({
	profile = function(data)
		data.Cash = 5300
		data.TutorialStep = 1
		local specs = C.fakeSpecimens(count)
		data.InventoryGeodes = specs
		if preview.args.shiny then
			-- the first three cards as the Pet Book shows them (sorted by rarity), so --set detail=1 opens a shiny one
			local LaunchPerks = C.shared("LaunchPerks")
			local PetRules = C.shared("PetRules")
			local order = table.clone(specs)
			if PetRules then
				PetRules.sort(order, "Rarity")
			end
			for i = 1, math.min(3, #order) do
				order[i].Shiny = true
				order[i].Value = order[i].Value * (if LaunchPerks then LaunchPerks.Shiny.ValueMult else 2)
			end
		end
		for i, g in ipairs(specs) do
			data.DiscoveryIndex[g.Mineral] = (data.DiscoveryIndex[g.Mineral] or 0) + 1
			data.DiscoveryRarity[g.Mineral] = data.DiscoveryRarity[g.Mineral] or {}
			data.DiscoveryRarity[g.Mineral][g.Rarity] = (data.DiscoveryRarity[g.Mineral][g.Rarity] or 0) + 1
			data.Stats.SoloFinds += 1
			data.Stats.BestGeodeValue = math.max(data.Stats.BestGeodeValue, g.Value)
			if i == 2 then
				g.Favorite = true
			end
		end
		if specs[1] then
			data.DisplayAssignments = { specs[1].Id }
			if preview.args.nick then
				specs[1].Nickname = "Sir Chomps" -- --set nick=1: a named pet (card caption, detail title)
			end
			if preview.args.follow and specs[2] then
				-- --set follow=1: the second pet follows you, so the POWER badges show better / worse arrows
				data.EquippedPets = { specs[2].Id }
			end
			if preview.args.follow == "display" then
				-- --set follow=display: the followed pet is also on display and a favourite (every card tag at once)
				data.EquippedPets = { specs[1].Id }
				specs[1].Favorite = true
			end
		end
		data.Stats.MatchesPlayed = count + 3
		data.Stats.RocksCracked = 412
	end,
})
C.settle(1)
C.tap("^COLLECTION$")
preview.advance(0.3)
local tab = preview.args.tab
if tab then
	C.tap("^" .. string.upper(tab) .. "$")
end
if preview.args.detail then
	-- geode cards are buttons inside the panel's scroller; tap the first card
	local cards = preview.findGui(function(obj, st)
		return obj:IsA("GuiButton") and obj:FindFirstChildOfClass("ViewportFrame") ~= nil
	end)
	if cards[1] then
		preview.click(cards[1])
	else
		preview.warn("no geode card to open")
	end
	if preview.args.more then
		-- --set more=1: the detail's MORE button shows every stat in plain words
		preview.advance(0.3)
		C.tap("^MORE$")
	end
end
if preview.args.sort then
	-- --set sort=Rarity|Level|Type: the Pet Book sort buttons
	C.tap("^" .. string.upper(preview.args.sort) .. "$")
	preview.advance(0.3)
end
if preview.args.rename then
	-- --set rename=1: the detail view's NAME button opens the rename dialog (text box + SAVE)
	preview.advance(0.3)
	C.tap("^NAME$")
	preview.advance(0.3)
end
local function cardButtons()
	return preview.findGui(function(obj, st)
		return obj:IsA("GuiButton") and obj.Parent and obj.Parent:IsA("ScrollingFrame")
	end)
end
if preview.args.confirm == "all" then
	-- --set confirm=all: sell mode, pick three geodes, press SELL N: the confirm dialog
	C.tap("^SELL$")
	preview.advance(0.3)
	for i = 1, 4 do
		-- the panel re-renders after each pick: look the cards up again
		local card = cardButtons()[i]
		if card then
			preview.click(card)
			preview.advance(0.2)
		end
	end
	C.tap("^SELL %d")
	preview.advance(0.3)
elseif preview.args.confirm then
	-- --set confirm=1: open the first geode and press SELL $: the confirm dialog
	preview.advance(0.3)
	C.tap("^SELL %$")
	preview.advance(0.3)
end
if preview.args.place then
	-- --set place=1: PLACE ON DISPLAY on the Display tab opens the specimen picker for the selected slot
	C.tap("^DISPLAY$")
	preview.advance(0.3)
	local slots = preview.findGui(function(obj)
		return obj:IsA("GuiButton") and obj.Name == "Slot2"
	end)
	if slots[1] then
		preview.click(slots[1])
		preview.advance(0.2)
	end
	C.tap("^PLACE ON DISPLAY$")
	preview.advance(0.3)
end
if preview.args.records == "fail" then
	-- --set records=fail (PREVIEW ONLY): the client's copy of the profile loses its Stats, as if the records never
	-- arrived, so the Records tab shows its unavailable state (RETRY / CLOSE). Prints RECORDS PASS / [FAIL].
	local State = preview.require(preview.clientFolder():FindFirstChild("State"))
	State.Profile.Stats = nil
	State.update("Profile")
	preview.advance(0.3)
	local retry = C.findText("^RETRY$", "GuiButton")
	local close = C.findText("^CLOSE$", "GuiButton")
	local zero = C.findText("^SOLO FINDS$")
	if retry and close and not zero then
		print("RECORDS PASS (unavailable state with RETRY and CLOSE, no made-up rows)")
	else
		print("[FAIL] RECORDS unavailable state missing")
	end
end
C.settle(1)
if preview.args.glint then
	-- --set glint=S (with shiny=1): S seconds after the panel settled, mid-sweep frame of the card glint (SHINY cards
	-- every 2.5 s, Legendary every 4 s): glint=2.7 catches a shiny card's band half-way across
	preview.advance(tonumber(preview.args.glint) or 2.7)
end
C.followCamera()

if preview.args.follow then
	-- CARDTAGS: no card tag (Following, Display / In pen, favourite star) overlaps a card's POWER badge
	local bad, checked = 0, 0
	local cards = preview.findGui(function(obj)
		return obj:IsA("GuiObject") and string.sub(obj.Name, 1, 5) == "Spec_"
	end)
	local function overlap(a: GuiObject, b: GuiObject): boolean
		local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
		return ap.X < bp.X + bs.X and bp.X < ap.X + as.X and ap.Y < bp.Y + bs.Y and bp.Y < ap.Y + as.Y
	end
	for _, card in cards do
		local power = card:FindFirstChild("Power", true) :: GuiObject?
		if power then
			for _, tag in { "FollowBadge", "DisplayBadge", "FavStar" } do
				local t = card:FindFirstChild(tag) :: GuiObject?
				if t then
					checked += 1
					local label = if t:IsA("TextLabel") then t.TextBounds else t.AbsoluteSize
					-- text labels: only the drawn words count, centred in the label
					local probe = t
					if t:IsA("TextLabel") then
						local w = math.min(label.X, t.AbsoluteSize.X)
						local f = Instance.new("Frame")
						f.Size = UDim2.fromOffset(w, t.AbsoluteSize.Y)
						f.Position = UDim2.fromOffset(t.AbsolutePosition.X + (t.AbsoluteSize.X - w) / 2, t.AbsolutePosition.Y)
						probe = f
						if t.AbsolutePosition.Y < power.AbsolutePosition.Y + power.AbsoluteSize.Y and power.AbsolutePosition.Y < t.AbsolutePosition.Y + t.AbsoluteSize.Y
							and (t.AbsolutePosition.X + (t.AbsoluteSize.X - w) / 2) < power.AbsolutePosition.X + power.AbsoluteSize.X
							and power.AbsolutePosition.X < t.AbsolutePosition.X + (t.AbsoluteSize.X + w) / 2 then
							bad += 1
							print("[FAIL] CARDTAGS " .. card.Name .. " " .. tag .. " covers the POWER badge")
						end
						f:Destroy()
					elseif overlap(probe, power) then
						bad += 1
						print("[FAIL] CARDTAGS " .. card.Name .. " " .. tag .. " covers the POWER badge")
					end
				end
			end
		end
	end
	print(if bad == 0 and checked > 0 then "CARDTAGS PASS (" .. checked .. " tags checked)" else "CARDTAGS FAIL (" .. bad .. " overlaps, " .. checked .. " tags)")
end
