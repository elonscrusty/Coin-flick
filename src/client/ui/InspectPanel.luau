--!strict
-- Read-only inspect card for a specimen in someone's lobby gallery. Opened by the server's
-- "Inspect" event (a visitor pressed Inspect on a displayed geode). It only looks: the one
-- button closes it. Selling, moving or displaying belongs to the owner's own Collection.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PetRules = require(Shared.PetRules)
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local PanelSkin = require(script.Parent.PanelSkin)
local PetStyle = require(script.Parent.PetStyle)
local GeodeView = require(script.Parent.GeodeView)

local C = UI.Colors
local PET = Theme.Pet
local Inspect = {}

-- card = { Owner = display name, IsYou = boolean, Specimen = public specimen }
function Inspect.show(card)
	if type(card) ~= "table" or type(card.Specimen) ~= "table" or State.Match then
		return -- never over a hunt
	end
	local g = card.Specimen
	local owner = tostring(card.Owner or "Someone")
	local inspectPanel, b, close, footer = UI.modal("Inspect", "INSPECT", Vector2.new(560, 330), { Fixed = true, Footer = 58 })
	PanelSkin.dress(inspectPanel, "Paw", "INSPECT")
	-- the pet in a rounded pet-style frame: white into the clip's light card blue, a soft blue edge and a thin
	-- rarity-coloured ring just inside it (the rarity still shows at a glance)
	local rarityColor: Color3 = Config.RarityColors[g.Rarity] or C.Rock
	local frame = UI.frame(b, { Name = "PetFrame", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0.44, 0, 1, 0), BackgroundColor3 = PET.White, BackgroundTransparency = 0 })
	PetStyle.round(frame, 18)
	PetStyle.edge(frame, PET.QuestEdge, 3)
	PetStyle.vgrad(frame, PET.White, PET.QuestBody)
	PetStyle.pattern(frame, PET.QuestEdge, 0.8, 30, 240, 240, 60)
	local ring = UI.frame(frame, { Name = "RarityRing", Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1 })
	PetStyle.round(ring, 14)
	PetStyle.edge(ring, rarityColor, 2)
	local view = GeodeView.make(frame, g, { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1 }, true)
	view.Name = "Specimen"
	local info = UI.frame(b, { Position = UDim2.new(0.44, 12, 0, 0), Size = UDim2.new(0.56, -12, 1, 0), BackgroundTransparency = 1 })
	UI.list(info, Enum.FillDirection.Vertical, 6)
	UI.text(info, PetRules.label(g), { Font = UI.Head, TextSize = UI.T.Title, LayoutOrder = 1 })
	local chip = UI.chip(info, g.Rarity, Config.RarityColors[g.Rarity] or C.Rock, { Size = UDim2.fromOffset(110, 26), LayoutOrder = 2 })
	chip.Name = "Rarity"
	UI.text(info, string.format("%s · %.2f kg", Config.FormationNames[g.Formation] or g.Formation, g.Mass), { TextSize = UI.T.Body, TextColor3 = C.Muted, LayoutOrder = 3 })
	if type(card.Power) == "number" then
		-- a pet following its owner (tap-to-inspect): its battle power and level, the reason to want one like it
		local stars = string.rep("\u{2605}", tonumber(card.Evolve) or 0)
		-- a glossy lime pill with white outlined words (the clip's price / claim pill)
		local pill = UI.frame(info, { Name = "PowerPill", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = PET.Lime, LayoutOrder = 4 })
		PetStyle.round(pill, 999)
		PetStyle.vgrad(pill, PET.LimeTop, PET.Lime)
		PetStyle.edge(pill, PET.LimeEdge, 2.5)
		PetStyle.words(pill, string.format("\u{26A1} %s  ·  Lv %d/%d %s", UI.num(card.Power), card.Level or 1, card.Cap or 1, stars), UI.T.Head, {
			Name = "Power", Font = UI.Head, Size = UDim2.new(1, -20, 1, -6), Position = UDim2.fromOffset(10, 3),
			TextXAlignment = Enum.TextXAlignment.Center, OutlineColor = PET.LimeEdge, OutlineThick = 2.4,
		})
	else
		UI.text(info, "Value " .. UI.money(g.Value) .. (if g.Solo then " · solo find" else ""), { TextSize = UI.T.Body, TextColor3 = C.Muted, LayoutOrder = 4 })
	end
	local who = if type(card.Where) == "string" then card.Where
		elseif card.IsYou then "On display in your gallery" else "On display in " .. owner .. "'s gallery"
	UI.text(info, who, { TextSize = UI.T.Body, Font = UI.Head, TextColor3 = PET.TitleEdge, Outline = false, LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 44) }) -- two lines on an upright phone
	UI.text(info, "Look only. Drag to turn it.", {
		TextSize = UI.T.Small, TextColor3 = C.Muted, LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 22),
	})
	if footer then
		UI.button(footer, "CLOSE", "gray", close, { Size = UDim2.new(1, 0, 1, 0), TextSize = UI.T.Head })
	end
end

function Inspect.start()
	Net.event("Inspect").OnClientEvent:Connect(function(card)
		Inspect.show(card)
	end)
end

return Inspect
