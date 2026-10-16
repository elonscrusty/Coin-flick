--!strict
-- Owner mockup panel look (2026-10-12; reference/ui/daily, settings, start_hunt): cream panel with a navy edge and a
-- gold rim, a yellow title tab over the top edge (picture + word), the owner's red X and coin pill. Shared by the
-- DAILY, SETTINGS and START HUNT / PARTY panels on top of UI.modal (which keeps opening, closing and blocking).
-- Picture slots (HudArt.Buttons panel_bg / panel_tab, btn_close_x, coin_pill) replace the drawn parts once uploaded.

local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local HudArt = require(script.Parent.HudArt)

local T = UI.T
local TC = Theme.Color
local PanelSkin = {}

-- Pet style (Theme.PetStyle, 2026-10-15): the cream becomes the clip's white-blue card, the navy its deep title
-- blue; the gold title tab, rims and owner pictures step aside (the modal header draws the floating title and X).
local PET = Theme.Pet
PanelSkin.CREAM = if Theme.PetStyle then PET.QuestBody else Color3.fromRGB(255, 247, 224)
PanelSkin.SKY = if Theme.PetStyle then PET.BlueTop else Color3.fromRGB(128, 198, 255) -- boxes inside a panel (gift box, choice cards)
PanelSkin.SKY_EDGE = if Theme.PetStyle then PET.Blue else Color3.fromRGB(40, 122, 232)
PanelSkin.ROW = if Theme.PetStyle then TC.Inset else Color3.fromRGB(196, 228, 255) -- rows and tiles
PanelSkin.NAVY = if Theme.PetStyle then PET.TitleEdge else TC.PanelEdge
PanelSkin.BAR = if Theme.PetStyle then PET.Blue else Color3.fromRGB(46, 136, 245)

-- Rounded box with an outline.
function PanelSkin.box(parent: Instance, name: string, color: Color3, edge: Color3, thick: number, props: { [string]: any }): Frame
	local f = UI.frame(parent, props)
	f.Name = name
	f.BackgroundColor3 = color
	UI.corner(f, 12)
	UI.stroke(f, edge, thick)
	return f
end

-- Inner frame for a box's padding and layout: a skin picture sits on the box itself, outside the layout (a layout
-- would place the picture like any other child).
function PanelSkin.content(f: Frame): Frame
	return UI.frame(f, { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = f.ZIndex })
end

-- Fitted one-line text that fills its box (TextScaled inside a size cap), so it never spills out of a tile.
function PanelSkin.word(parent: Instance, text: string, size: number, props: { [string]: any }): TextLabel
	local l = UI.text(parent, text, props)
	l.TextWrapped = false
	UI.fit(l, size, math.min(size, 10))
	return l
end

export type DressOpts = { Center: boolean?, Tiles: boolean? }

-- Restyles a UI.modal panel: `icon` is a HudArt slot for the tab picture, `title` the tab word (HudArt.word picks
-- the owner's word picture when one matches). Center puts the tab in the middle (SETTINGS, START HUNT).
function PanelSkin.dress(panel: Frame, icon: string, title: string, opts: DressOpts?)
	local o: DressOpts = opts or {}
	local NAVY, CREAM = PanelSkin.NAVY, PanelSkin.CREAM
	if Theme.PetStyle then
		-- the sheet, floating title and X come from UI.modal; a centred title moves to the middle, a subtitle goes navy
		local header = panel:FindFirstChild("Header")
		for _, name in { "Title", "TitleShadow" } do
			local t = if header then header:FindFirstChild(name) else nil
			if t and t:IsA("TextLabel") then
				t.Text = UI.titleCase(title)
				if o.Center then
					t.TextXAlignment = Enum.TextXAlignment.Center
					t.Position = UDim2.fromOffset(0, t.Position.Y.Offset)
					t.Size = UDim2.new(1, 0, 0, t.Size.Y.Offset)
				end
			end
		end
		local sub = panel:FindFirstChild("Subtitle") :: TextLabel?
		if sub then
			sub.TextColor3 = NAVY
			local ol = sub:FindFirstChildOfClass("UIStroke")
			if ol then
				ol.Enabled = false
			end
			sub.TextXAlignment = Enum.TextXAlignment.Center
		end
		return
	end
	panel.BackgroundColor3 = CREAM
	local shade = panel:FindFirstChild("PanelShade")
	if shade then
		shade:Destroy()
	end
	local edge = panel:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = NAVY
		edge.Thickness = 3
	end
	local rim = UI.frame(panel, { Name = "Rim", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1 })
	UI.corner(rim, T.RadiusLg - 2)
	UI.stroke(rim, TC.Gold, 4)
	-- Tiles (START HUNT, owner 2026-10-13): no dedicated panel art yet, so reuse the DAILY cream and gold tiles
	local skinned = HudArt.skin(panel, "panel_bg", 470) or (o.Tiles == true and HudArt.skin(panel, "tile_cream", 470))
	if skinned or panel:GetAttribute("KitOn") then
		rim:Destroy() -- the picture has its own rim: the drawn gold one inside it made a double border (Studio #186)
	end
	local header = panel:FindFirstChild("Header")
	if not header then
		return
	end
	-- the header (tab, X, coins) draws over the panel picture and rim: their top edge must not cut through the tab
	local top = 0
	for _, c in panel:GetChildren() do
		if c ~= header and c:IsA("GuiObject") then
			top = math.max(top, c.ZIndex)
		end
	end
	if header:IsA("GuiObject") and header.ZIndex <= top then
		header.ZIndex = top + 1
	end
	local t = header:FindFirstChild("Title") :: TextLabel?
	if t then
		t.Visible = false
	end
	-- the tab sits half above the panel's top edge
	-- wider on an upright phone so a two-word title (PET BOOK) stays on one line (not when the coins sit there)
	local TAB_H = UI.headerTab() -- 56, compact 46 on the shortest phones
	local tabSize = UDim2.new(if o.Center then 0.56 elseif UI.isPortrait() and not header:FindFirstChild("Cash") then 0.6 else 0.42, 0, 0, TAB_H)
	local tab = PanelSkin.box(header, "Tab", TC.Gold, NAVY, 3, {
		AnchorPoint = Vector2.new(if o.Center then 0.5 else 0, 0.5),
		Position = if o.Center then UDim2.new(0.5, 0, 0, 4) else UDim2.new(0, 14, 0, 4),
		Size = tabSize,
		ZIndex = 5,
	})
	local back = header:FindFirstChild("Back")
	if o.Center and back and back:IsA("GuiObject") and header:IsA("GuiObject") then
		-- a BACK button holds the header's left side (EGG SHOP from UPGRADES): the centred tab keeps clear of it on
		-- both sides (the X sits on the right) on any panel width
		local reserve = back.Position.X.Offset + back.Size.X.Offset + 10
		local function fitTab()
			local w = header.AbsoluteSize.X / math.max(UI.Scale, 0.01) -- logical px, like the offsets
			if w > 0 then
				tab.Size = UDim2.new(0, math.floor(math.max(120, math.min(w * 0.56, w - 2 * reserve))), 0, TAB_H)
			end
		end
		fitTab()
		header:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitTab)
	end
	UI.corner(tab, TAB_H // 2)
	local _ = HudArt.skin(tab, "panel_tab", TAB_H) or (o.Tiles and HudArt.skin(tab, "tile_gold", TAB_H))
	local tin = PanelSkin.content(tab)
	UI.pad(tin, 10, 5)
	-- always laid out from the left (a centred list let the picture and word drift out of the tab on the owner's
	-- phone, onto the BACK button); a centred tab centres its word in the room right of the picture instead
	UI.list(tin, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local pic = HudArt.image(tin, icon, 40, { Size = UDim2.fromScale(1, 1), LayoutOrder = 1, ZIndex = 6 })
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = pic
	local w = PanelSkin.word(tin, title, T.Title, {
		Name = "Word", Font = UI.Head, Outline = "Strong", Size = UDim2.new(1, -52, 1, 0), LayoutOrder = 2, ZIndex = 6,
		TextXAlignment = if o.Center then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
	})
	HudArt.word(w)
	if t then
		-- panels that retitle themselves (PARTY 2/4) keep the tab in step
		t:GetPropertyChangedSignal("Text"):Connect(function()
			w.Text = t.Text
		end)
	end
	-- red X picture (square, drawn whole); its drawn X steps aside
	local x = header:FindFirstChild("Close") :: GuiButton?
	if x and HudArt.skin(x, "btn_close_x") then
		for _, c in x:GetChildren() do
			if c:IsA("GuiObject") and c.Name ~= "Skin" then
				c.Visible = false
			end
		end
	end
	-- coin readout as a cream pill
	local cash = header:FindFirstChild("Cash") :: Frame?
	if cash then
		cash.BackgroundTransparency = 0
		cash.BackgroundColor3 = CREAM
		UI.corner(cash, 14)
		UI.stroke(cash, TC.GoldDeep, 3)
		HudArt.skin(cash, "coin_pill", cash.Size.Y.Offset)
		-- the owner's coin picture (as on the HUD) in place of the drawn coin, whose parts read as an "I" on the
		-- cream pill (Studio #187)
		local drawn = cash:FindFirstChild("Icon")
		if drawn and drawn:IsA("GuiObject") and HudArt.has("Coin") then
			local h = cash.Size.Y.Offset
			drawn:Destroy()
			HudArt.image(cash, "Coin", h + 6, { Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -4, 0.5, 0), ZIndex = cash.ZIndex + 1 })
		end
		local amt = cash:FindFirstChild("Amount") :: TextLabel?
		if amt then
			amt.TextColor3 = NAVY
			local ol = amt:FindFirstChildOfClass("UIStroke")
			if ol then
				ol.Enabled = false
			end
		end
	end
	-- a subtitle line (START HUNT "One pile. One pet.") sits on cream: navy, no outline
	local sub = panel:FindFirstChild("Subtitle") :: TextLabel?
	if sub then
		sub.TextColor3 = NAVY
		local ol = sub:FindFirstChildOfClass("UIStroke")
		if ol then
			ol.Enabled = false
		end
		sub.TextXAlignment = Enum.TextXAlignment.Center
		HudArt.word(sub)
	end
end

-- Picture skins for the buttons of a cream card, by UI.button style (red stays drawn: no red picture yet).
local STYLE_SKIN = { gold = "btn_yellow", gray = "btn_grey", blue = "btn_blue", green = "btn_green" }

-- Cream look for small cards (yes/no dialogs, party invite, toasts): cream fill, navy edge, gold rim, navy body
-- text, picture buttons and the red X picture. `edgeColor` keeps a toast's green / red edge meaning.
function PanelSkin.card(f: Frame, edgeColor: Color3?)
	f.BackgroundColor3 = PanelSkin.CREAM
	f.BackgroundTransparency = 0
	local shade = f:FindFirstChild("PanelShade")
	if shade then
		shade:Destroy()
	end
	local edge = f:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = edgeColor or (if Theme.PetStyle then PET.QuestEdge else PanelSkin.NAVY)
		edge.Thickness = 3
	end
	if not Theme.PetStyle then
		local rim = UI.frame(f, { Name = "Rim", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, ZIndex = 0 })
		local c = f:FindFirstChildOfClass("UICorner")
		UI.corner(rim, if c then math.max(0, c.CornerRadius.Offset - 3) else T.Radius)
		UI.stroke(rim, TC.Gold, 2)
	end
	for _, d in f:GetDescendants() do
		if d:IsA("TextLabel") and (d.Name == "Message" or d.Name == "Text") then
			d.TextColor3 = PanelSkin.NAVY
			local ol = d:FindFirstChildOfClass("UIStroke")
			if ol then
				ol.Enabled = false
			end
		elseif d:IsA("GuiButton") and d.Name == "Close" then
			if HudArt.skin(d, "btn_close_x") then
				for _, k in d:GetChildren() do
					if k:IsA("GuiObject") and k.Name ~= "Skin" then
						k.Visible = false
					end
				end
			end
		elseif d:IsA("GuiButton") and d.Parent and d.Parent.Name == "Buttons" then
			local key = STYLE_SKIN[tostring(d:GetAttribute("Style"))]
			if key then
				HudArt.skin(d, key, d.AbsoluteSize.Y > 0 and d.AbsoluteSize.Y or 46)
			end
		end
	end
end

UI.DialogDress = function(panel: Frame)
	PanelSkin.card(panel)
end
UI.NoticeDress = function(card: Frame, kind: string)
	PanelSkin.card(card, if kind == "ok" or kind == "geode" then TC.Green elseif kind == "warn" then TC.Red else nil)
end

return PanelSkin
