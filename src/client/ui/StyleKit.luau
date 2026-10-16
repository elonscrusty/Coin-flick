--!strict
-- Style test helpers (owner's UI style sheet, 2026-10-14). Used ONLY by ShopPanel (#1 POLYGON ADVENTURE) and QuestPanel
-- (#7 ISLAND SIGNPOST). Visual overrides on top of what UI.luau builds: nothing here changes sizes, layout or behaviour,
-- and UI.luau's shared defaults stay as they are. A restyled button keeps its colours through hover / press / disabled
-- repaints because the override follows UI.paint's own property writes.

local Theme = require(script.Parent.Theme)

local TC = Theme.Color
local StyleKit = {}

-- The pet style (Theme.PetStyle, 2026-10-15) draws both panels from the shared look: every override here steps aside.
local OFF = Theme.PetStyle == true

export type ButtonSkin = { Fill: Color3, Hover: Color3, Line: Color3, Text: Color3, OffFill: Color3?, OffText: Color3?, Outline: boolean? }

local function near(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.02
end
StyleKit.near = near

-- Recolours one UI.button and keeps it recoloured when UI.paint runs again.
function StyleKit.button(b: GuiButton, skin: ButtonSkin)
	if OFF then
		return
	end
	local label = b:FindFirstChild("Label") :: TextLabel?
	local line = b:FindFirstChild("Border") :: UIStroke?
	local outline = if label then label:FindFirstChild("Outline") else nil
	local function apply()
		local off = b:GetAttribute("Disabled") == true
		local want = if off then (skin.OffFill or skin.Fill) elseif b:GetAttribute("Hover") == true then skin.Hover else skin.Fill
		if b:GetAttribute("Pressed") == true and not off then
			want = want:Lerp(Color3.new(0, 0, 0), 0.18)
		end
		if b.BackgroundColor3 ~= want then
			b.BackgroundColor3 = want
		end
		if line then
			local lc = if b:GetAttribute("Selected") then skin.Text else skin.Line
			if line.Color ~= lc then
				line.Color = lc
			end
		end
		if label then
			local tc = if off then (skin.OffText or skin.Text) else skin.Text
			if label.TextColor3 ~= tc then
				label.TextColor3 = tc
			end
			if outline and outline:IsA("UIStroke") then
				local en = skin.Outline == true
				if outline.Enabled ~= en then
					outline.Enabled = en
				end
			end
		end
	end
	apply()
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(apply)
	if label then
		label:GetPropertyChangedSignal("TextColor3"):Connect(apply)
	end
	if outline and outline:IsA("UIStroke") then
		outline:GetPropertyChangedSignal("Enabled"):Connect(apply)
	end
end

-- Holds a frame/button background: any write of a colour in `from` becomes `to` (row hover repaints).
function StyleKit.holdBg(g: GuiObject, from: { Color3 }, to: Color3)
	if OFF then
		return
	end
	local function fix()
		for _, c in from do
			if near(g.BackgroundColor3, c) then
				g.BackgroundColor3 = to
				return
			end
		end
	end
	fix()
	g:GetPropertyChangedSignal("BackgroundColor3"):Connect(fix)
end

-- Text colour remap for words that were white / pale / gold / green for a blue panel; `fn` returns the new colour or nil.
function StyleKit.text(root: Instance, fn: (TextLabel) -> Color3?)
	if OFF then
		return
	end
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			local c = fn(d)
			if c then
				d.TextColor3 = c
				local o = d:FindFirstChild("Outline")
				if o and o:IsA("UIStroke") then
					o.Enabled = false
				end
			end
		end
	end
end

-- A faceted gem: a small square turned 45 degrees, flat fill and a darker edge.
function StyleKit.gem(parent: Instance, name: string, pos: UDim2, size: number, fill: Color3, edge: Color3): Frame
	local g = Instance.new("Frame")
	g.Name = name
	if OFF then
		g.Visible = false
		g.Parent = parent
		return g
	end
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = pos
	g.Size = UDim2.fromOffset(size, size)
	g.Rotation = 45
	g.BackgroundColor3 = fill
	g.BorderSizePixel = 0
	g.ZIndex = 40
	local s = Instance.new("UIStroke")
	s.Color = edge
	s.Thickness = 2
	s.Parent = g
	-- a lighter facet on the upper half
	local f = Instance.new("Frame")
	f.Name = "Facet"
	f.BackgroundColor3 = fill:Lerp(Color3.new(1, 1, 1), 0.5)
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(0.5, 0.5)
	f.ZIndex = g.ZIndex + 1
	f.Parent = g
	g.Parent = parent
	return g
end

-- Corner gems (four corners plus the middle of both sides when `sides`).
function StyleKit.cornerGems(panel: Instance, fill: Color3, edge: Color3, size: number, sides: boolean)
	if OFF then
		return
	end
	local pts = { UDim2.fromOffset(6, 6), UDim2.new(1, -6, 0, 6), UDim2.new(0, 6, 1, -6), UDim2.new(1, -6, 1, -6) }
	for i, p in pts do
		StyleKit.gem(panel, "Gem" .. i, p, size, fill, edge)
	end
	if sides then
		StyleKit.gem(panel, "GemL", UDim2.new(0, 2, 0.5, 0), size - 2, fill, edge)
		StyleKit.gem(panel, "GemR", UDim2.new(1, -2, 0.5, 0), size - 2, fill, edge)
	end
end

-- Recolours the stroke of the panel's own edge and its Rim frame, and the header's tab / coin pill.
function StyleKit.panel(panel: Frame, bg: Color3, edge: Color3, edgeThick: number, rim: Color3, tab: Color3, tabEdge: Color3, tabText: Color3?)
	if OFF then
		return
	end
	panel.BackgroundColor3 = bg
	local e = panel:FindFirstChildOfClass("UIStroke")
	if e then
		e.Color = edge
		e.Thickness = edgeThick
	end
	local r = panel:FindFirstChild("Rim")
	local rs = if r then r:FindFirstChildOfClass("UIStroke") else nil
	if rs then
		rs.Color = rim
	end
	local header = panel:FindFirstChild("Header")
	if not header then
		return
	end
	local t = header:FindFirstChild("Tab")
	if t and t:IsA("GuiObject") then
		t.BackgroundColor3 = tab
		local ts = t:FindFirstChildOfClass("UIStroke")
		if ts then
			ts.Color = tabEdge
		end
		if tabText then
			for _, d in t:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextColor3 = tabText
					local o = d:FindFirstChild("Outline")
					if o and o:IsA("UIStroke") then
						o.Enabled = false
					end
				end
			end
		end
	end
	local cash = header:FindFirstChild("Cash")
	local cs = if cash then cash:FindFirstChildOfClass("UIStroke") else nil
	if cs then
		cs.Color = tabEdge
	end
end

local _ = TC
return StyleKit
