--!strict
-- Pet stats drawn for young players (data from shared/PetStatView): the POWER badge (one "bigger = better" number
-- with a green up / red down arrow against the pet that follows you) and the MORE page (every stat in one plain
-- sentence). Used by the Pet Book cards and detail (CollectionPanel) and the Pet Tower picker (TowerPanel).

local TextService = game:GetService("TextService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetStatView = require(Shared.PetStatView)
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)

local T = UI.T
local TC = Theme.Color
local K = Theme.Pet

local Strip = {}

local UP = K.Lime
local DOWN = K.Red

-- A glossy pet-style pill (lighter top, dark edge) behind a badge: blue for the readouts, gold once a pet is maxed.
local function pillSkin(f: Frame, h: number, top: Color3, bottom: Color3, edge: Color3)
	PetStyle.round(f, math.floor(h / 2))
	PetStyle.vgrad(f, top, bottom)
	PetStyle.edge(f, edge, if h >= 30 then 2 else 1.5)
end

-- The POWER badge: bolt icon, the number, and a green up / red down arrow against the pet that follows you
-- (cmp from PetStatView.compare). `h` is its height; the width follows the number (AutomaticSize).
-- Attributes Power / Cmp let preview checks read it.
function Strip.badge(parent: Instance, power: number?, cmp: number, h: number, props: { [string]: any }?): Frame?
	if power == nil then
		return nil
	end
	-- sized from the measured number (nested AutomaticSize left pills narrower than their words, see UI.lua SubPill)
	local text = UI.num(power)
	local size = math.floor(h * 0.72)
	local tw = math.ceil(TextService:GetTextSize(text, size, UI.Head, Vector2.new(1000, 1000)).X) + 2
	local ih = h - 4
	local aw = if cmp ~= 0 then math.floor(h * 0.62) else 0
	local w = 2 + ih + 3 + tw + (if aw > 0 then aw + 2 else 0) + math.floor(h * 0.3)
	local f = UI.frame(parent, { Name = "Power", BackgroundColor3 = K.Blue, Size = UDim2.fromOffset(w, h) })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	pillSkin(f, h, K.BlueTop, K.Blue, K.BlueEdge)
	f:SetAttribute("Power", power)
	f:SetAttribute("Cmp", cmp)
	UI.icon(f, "statPower", ih, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0) })
	local num = UI.text(f, text, {
		Name = "Value", Font = UI.Head, TextSize = size, TextColor3 = K.Gold, Outline = "Normal",
		Position = UDim2.fromOffset(2 + ih + 3, 0), Size = UDim2.fromOffset(tw, h),
	})
	num.TextWrapped = false
	local numEdge = num:FindFirstChild("Outline")
	if numEdge and numEdge:IsA("UIStroke") then
		numEdge.Color = K.BlueEdge
	end
	if cmp ~= 0 then
		UI.icon(f, "arrow", aw, {
			Name = if cmp > 0 then "Better" else "Worse",
			Color = if cmp > 0 then UP else DOWN,
			Rotation = if cmp > 0 then 0 else 180,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2 + ih + 3 + tw + 2, 0.5, 0),
		})
	end
	return f
end

-- "Lv 7/20" chip next to the POWER badge; gold "MAX" style once the pet reached its rarity's cap.
function Strip.level(parent: Instance, level: number, cap: number, h: number, props: { [string]: any }?): Frame
	local maxed = level >= cap
	local text = PetStatView.levelText(level, cap)
	local size = math.floor(h * 0.7)
	local tw = math.ceil(TextService:GetTextSize(text, size, UI.Head, Vector2.new(1000, 1000)).X) + 2
	local f = UI.frame(parent, { Name = "Level", BackgroundColor3 = if maxed then K.Gold else K.Blue, Size = UDim2.fromOffset(tw + 14, h) })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	if maxed then
		pillSkin(f, h, K.Gold:Lerp(K.White, 0.3), K.Gold, K.TagEdge)
	else
		pillSkin(f, h, K.BlueTop, K.Blue, K.BlueEdge)
	end
	f:SetAttribute("Level", level)
	f:SetAttribute("Cap", cap)
	local l = UI.text(f, text, { Name = "Value", Font = UI.Head, TextSize = size, TextColor3 = if maxed then TC.DarkText else K.White, Outline = if maxed then false else "Normal", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	l.TextWrapped = false
	local lEdge = l:FindFirstChild("Outline")
	if lEdge and lEdge:IsA("UIStroke") then
		lEdge.Color = K.BlueEdge
	end
	return f
end

-- The MORE page: every stat as icon, bold head and one or two lines of words, in a scroll list filling `parent`
-- above a BACK button (`onBack`).
function Strip.more(parent: Instance, g: { [string]: any }, comparing: boolean, onBack: () -> ()): ScrollingFrame
	local sc = UI.scroller(parent, { Name = "MoreStats", Size = UDim2.new(1, 0, 1, -(T.Touch + 4)) })
	UI.list(sc, Enum.FillDirection.Vertical, 4)
	local order = 0
	local function line(icon: string?, head: string, text: string)
		order += 1
		local r = UI.frame(sc, { Name = "Line" .. order, LayoutOrder = order, BackgroundColor3 = TC.Inset, Size = UDim2.new(1, -4, 0, 54) })
		UI.corner(r, T.RadiusSm)
		if icon then
			UI.icon(r, icon, 24, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0) })
		end
		local h = UI.text(r, head, { Name = "Head", Font = UI.Head, TextSize = T.Body, Outline = "Normal", Position = UDim2.fromOffset(32, 2), Size = UDim2.new(1, -36, 0, 20) })
		UI.fit(h, T.Body, 10)
		h.TextWrapped = false
		local b = UI.text(r, text, { Name = "Text", Font = UI.Bold, TextSize = T.Tiny, TextColor3 = TC.Muted, Outline = "Light", Position = UDim2.fromOffset(32, 22), Size = UDim2.new(1, -36, 0, 30), TextYAlignment = Enum.TextYAlignment.Top })
		UI.fit(b, T.Tiny, 8)
		b.TextWrapped = true
	end
	for _, l in PetStatView.more(g) do
		line(l.Icon, l.Head, l.Text)
	end
	if comparing then
		line("arrow", "Arrows", "Green up = more POWER than the pet following you. Red down = less.")
	end
	UI.button(parent, "BACK", "gray", onBack, { Name = "Back", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.6, 0, 0, T.Touch), TextSize = T.Body })
	return sc
end

return Strip
