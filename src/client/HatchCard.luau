--!strict
-- The pet card above a hatch at the public hatch stand (client only, cosmetic; the server rolled the pet before the
-- HatchShow event arrived). A small BillboardGui card shows its back ("?") first, then flips over (the card narrows to
-- nothing and widens again) to show who hatched what: the rarity line and the pet's name land together (a name typing
-- in after the rarity read as "COMMON ... BUNNY") and the rarity stars (1 Common .. 5 Legendary) fill in one by one. Reduce Motion: the open card at once, full name, all stars lit.
-- Everything lives under the BillboardGui, so destroying the adornee (the show folder) cleans it all up.

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local UI = require(script.Parent.ui.UI)

local HatchCard = {}

local FLIP_AT, FLIP = 0.15, 0.32 -- seconds after the pop; the whole flip (half narrows, half widens)
local STAR_STEP = 0.16 -- seconds per star
local DIM = Color3.fromRGB(70, 66, 84)

local function stars(rarity: string): number
	for i, r in Config.Rarities do
		if r == rarity then
			return i
		end
	end
	return 1
end

-- Builds the card over `adornee`. `head` is the small line ("Kc hatched a RARE"), `name` the pet name that types in.
function HatchCard.show(adornee: BasePart, head: string, name: string, rarity: string, color: Color3): BillboardGui
	local reduced = UI.Reduced
	local bb = Instance.new("BillboardGui")
	bb.Name = "HatchTag"
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(260, 92)
	bb.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y * 0.5 + 2.8, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	-- the card face (only its background narrows during the flip; the text sits beside it so it never squashes)
	local card = UI.frame(bb, {
		Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(34, 30, 46), BackgroundTransparency = 0.15,
	})
	UI.corner(card, 12)
	local edge = UI.stroke(card, color, 3)
	local back = UI.text(card, "?", {
		Name = "Back", Font = UI.Head, TextSize = 40, TextColor3 = color, Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local front = UI.frame(bb, { Name = "Front", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	UI.text(front, head, {
		Name = "Head", Font = UI.Bold, TextSize = UI.T.Body, TextColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 0, 20), TextXAlignment = Enum.TextXAlignment.Center,
	})
	UI.text(front, name, {
		Name = "Name", Font = UI.Head, TextSize = 24, TextColor3 = color, Position = UDim2.fromOffset(8, 24),
		Size = UDim2.new(1, -16, 0, 34), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local row = UI.frame(front, {
		Name = "Stars", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(5 * 22, 20), BackgroundTransparency = 1,
	})
	local lit = stars(rarity)
	local slots: { Frame } = {}
	for i = 1, 5 do
		slots[i] = UI.frame(row, { Name = "Slot" .. i, Position = UDim2.fromOffset((i - 1) * 22, 0), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1 })
		UI.icon(slots[i], "star", 20, { Color = DIM, Flat = true })
	end
	bb.Parent = adornee

	local function light(i: number)
		local s = slots[i]
		if s and s.Parent then
			local star = UI.icon(s, "star", 20, { Name = "Lit" })
			UI.pop(star, 0.3)
		end
	end
	local function open()
		back.Visible = false
		front.Visible = true
	end
	if reduced then
		open()
		for i = 1, lit do
			light(i)
		end
		return bb
	end

	task.delay(FLIP_AT, function()
		if not bb.Parent then
			return
		end
		local half = TweenInfo.new(FLIP / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local shut = TweenService:Create(card, half, { Size = UDim2.fromScale(0, 1) })
		back.Visible = false -- the "?" would squash with the card; the bare card turns edge-on
		shut:Play()
		shut.Completed:Wait()
		if not bb.Parent then
			return
		end
		edge.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
		TweenService:Create(card, TweenInfo.new(FLIP / 2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
		task.wait(FLIP / 2)
		if not bb.Parent then
			return
		end
		open()
		-- rarity line and name show together, then the stars light one by one
		for i = 1, lit do
			light(i)
			task.wait(STAR_STEP)
			if not bb.Parent then
				return
			end
		end
	end)
	return bb
end

return HatchCard
