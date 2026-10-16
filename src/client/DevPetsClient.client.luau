--!strict
-- Dev pet spawner button (owner / Studio only; the server decides via the IsDev attribute and re-checks every request).
-- Drawn in the pet style (ui/PetStyle, Theme.Pet): a red DEV tile on the HUD menu column, a white patterned sheet
-- with the title floating over its edge, rarity pills and white pet rows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if player:GetAttribute("DevPets") ~= true then
	player:GetAttributeChangedSignal("DevPets"):Wait()
end

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local uiFolder = script.Parent:WaitForChild("ui")
local UI = require(uiFolder:WaitForChild("UI"))
local PetStyle = require(uiFolder:WaitForChild("PetStyle"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local remote = ReplicatedStorage:WaitForChild("DevSpawnPet") :: RemoteFunction

local K = PetStyle.K
local TC = Theme.Color
local RARITY_COLOR = {
	Common = Color3.fromRGB(170, 170, 170), Uncommon = Color3.fromRGB(90, 200, 90), Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 80, 230), Legendary = Color3.fromRGB(255, 180, 40),
}
local PANEL_W, PANEL_H = 560, 520

local gui = Instance.new("ScreenGui")
gui.Name = "DevPets"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
-- Sibling: children draw over their parent. (Instance.new defaults to Global, where the panel's ZIndex 2 hid all of
-- its ZIndex-1 contents behind its own background: the menu opened blank.)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- The DEV button is a small tile at the bottom of the HUD's right menu column (so it never covers the left column or
-- the thumbstick); it falls back to the right edge when the HUD is not there. Hidden in hunts and the tower.
local hudGui = player:WaitForChild("PlayerGui"):WaitForChild("CrackTheRocks", 10)
local menu = if hudGui then hudGui:WaitForChild("Menu", 10) else nil
-- same size as the menu tiles (Hud TILE) so it sits on their two-column grid; the red pet-style button
local open = UI.button(menu or gui, "DEV", "red", nil, { Name = "DevTile", LayoutOrder = 99, Size = UDim2.fromOffset(60, 60), TextSize = 20 })
if not menu then
	open.AnchorPoint = Vector2.new(1, 0.5)
	open.Position = UDim2.new(1, -8, 0.62, 0)
end
local function refreshOpen()
	open.Visible = player:GetAttribute("MatchKey") == nil and (player:GetAttribute("InTower") == nil and player:GetAttribute("InBattle") == nil)
end
player:GetAttributeChangedSignal("MatchKey"):Connect(refreshOpen)
player:GetAttributeChangedSignal("InTower"):Connect(refreshOpen)
player:GetAttributeChangedSignal("InBattle"):Connect(refreshOpen)
refreshOpen()

-- dark backdrop: dims the HUD behind the menu and takes its taps (tap outside the menu closes it)
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = TC.Shade
backdrop.BackgroundTransparency = 0.45
backdrop.Visible = false
backdrop.Parent = gui
gui.IgnoreGuiInset = true

-- the sheet: a white patterned card with a drop copy under it (PetStyle.shadowed), the title floating over its top edge
local panel, face = PetStyle.shadowed(gui, 16, 5, nil, {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.9, 0, 0.8, 0), Visible = false,
})
panel.Active = true
local cap = Instance.new("UISizeConstraint")
cap.MaxSize = Vector2.new(PANEL_W, PANEL_H)
cap.Parent = panel
PetStyle.edge(face, K.PanelEdge, 3)
PetStyle.pattern(face, K.PanelPattern, 0.3, 46, PANEL_W, PANEL_H, 160)

PetStyle.title(face, "Spawn a pet (dev)", 26, { Position = UDim2.fromOffset(16, -12), Size = UDim2.new(1, -80, 0, 40), ZIndex = 6 })

local close = PetStyle.closeX(face, 40, function() end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, -10) })

-- rarity picker: the rarity the NEXT spawned pet gets (it is not a list filter: every pet is always listed)
local rarity = "Legendary"
local pickLabel = UI.text(face, "", { Name = "Pick", TextSize = 14, TextColor3 = TC.Muted, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 20), ZIndex = 3 })
local row = UI.frame(face, { Name = "Rarities", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 36), ZIndex = 3 })
local rl = Instance.new("UIListLayout")
rl.FillDirection = Enum.FillDirection.Horizontal
rl.Padding = UDim.new(0, 6)
rl.Parent = row
local rarityButtons: { [string]: TextButton } = {}
-- recolours a pill (its gradient, edge and words): selected = the rarity's glossy colour, others = flat navy
local function paintPill(b: TextButton, top: Color3, bottom: Color3, edgeColor: Color3, textColor: Color3)
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(top, bottom)
	end
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = edgeColor
	end
	local l = b:FindFirstChild("Label")
	if l and l:IsA("TextLabel") then
		l.TextColor3 = textColor
		local o = l:FindFirstChild("Outline")
		if o and o:IsA("UIStroke") then
			o.Color = edgeColor
		end
	end
end
local function paintRarity()
	for r, b in rarityButtons do
		local on = r == rarity
		local col = RARITY_COLOR[r] or K.White
		if on then
			paintPill(b, col:Lerp(K.White, 0.4), col, col:Lerp(K.Ink, 0.55), K.White)
		else
			paintPill(b, K.TabBar:Lerp(K.White, 0.1), K.TabBar, K.TabBarEdge, K.TabText)
		end
		local l = b:FindFirstChild("Label")
		if l and l:IsA("TextLabel") then
			l.Text = if on then "\u{2713} " .. r else r
		end
	end
	pickLabel.Text = "New pet rarity: " .. rarity .. "   (tap a pet to spawn it)"
end
for _, r in Config.Rarities do
	local col = RARITY_COLOR[r] or K.White
	local b = PetStyle.pill(row, r, col:Lerp(K.White, 0.4), col, col:Lerp(K.Ink, 0.55), { Name = "Rarity_" .. r, Size = UDim2.new(1 / #Config.Rarities, -6, 1, 0) }, 14)
	rarityButtons[r] = b
	b.Activated:Connect(function()
		rarity = r
		paintRarity()
	end)
end
paintRarity()

local status = UI.text(face, "Tap a rarity, then a pet.", { Name = "Status", TextSize = 15, TextColor3 = TC.Muted, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -8), Size = UDim2.new(1, -32, 0, 24), ZIndex = 3 })

-- search box: type part of a name to find a pet fast (a pale inset with the sheet's edge colour)
local search = Instance.new("TextBox")
search.Name = "Search"
search.Position = UDim2.fromOffset(12, 102)
search.Size = UDim2.new(1, -24, 0, 34)
search.BackgroundColor3 = K.PanelPattern
search.BorderSizePixel = 0
search.TextColor3 = K.Ink
search.PlaceholderText = "Search pets..."
search.PlaceholderColor3 = TC.Faint
search.Font = UI.Bold
search.TextSize = 16
search.Text = ""
search.ClearTextOnFocus = false
search.TextXAlignment = Enum.TextXAlignment.Left
search.ZIndex = 3
search.Parent = face
PetStyle.round(search, 10)
PetStyle.edge(search, TC.InsetEdge, 2)
local spad = Instance.new("UIPadding")
spad.PaddingLeft = UDim.new(0, 10)
spad.Parent = search

-- the list sits in its own pale inset with padding, so rows never butt against the pills or the footer
local inset = UI.frame(face, { Name = "ListInset", BackgroundColor3 = K.PanelPattern, Position = UDim2.fromOffset(12, 144), Size = UDim2.new(1, -24, 1, -184), ClipsDescendants = true, ZIndex = 3 })
PetStyle.round(inset, 12)
PetStyle.edge(inset, TC.InsetEdge, 2)
local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(0, 6)
list.Size = UDim2.new(1, 0, 1, -12)
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = K.TitleEdge
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ZIndex = 4
list.Parent = inset
local lpad = Instance.new("UIPadding")
lpad.PaddingLeft = UDim.new(0, 6)
lpad.PaddingRight = UDim.new(0, 12)
lpad.PaddingTop = UDim.new(0, 2)
lpad.PaddingBottom = UDim.new(0, 6)
lpad.Parent = list
local grid = Instance.new("UIGridLayout")
-- two wide columns: long names ("Astral Kitsune") get the same text size as short ones
grid.CellSize = UDim2.new(0.5, -4, 0, 46)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.Name
grid.Parent = list

local busy = false
-- only pets that have a real (Meshy) model in ReplicatedStorage.PetModels (attribute Mesh = true)
local petModels = ReplicatedStorage:WaitForChild("PetModels", 10)
local function hasModel(id: string): boolean
	local m = petModels and petModels:FindFirstChild("Pet_" .. id)
	return m ~= nil and m:GetAttribute("Mesh") == true
end
for id, sp in Config.Minerals :: any do
	if not hasModel(id) then
		continue
	end
	-- one row: a colour swatch of the pet (body colour, accent ring), its name, and its body type underneath
	local b = Instance.new("TextButton")
	b.Name = tostring(sp.Name or id)
	b.BackgroundColor3 = K.White
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 4
	b.Parent = list
	PetStyle.round(b, 10)
	PetStyle.edge(b, K.PanelEdge, 2)
	UI.squashScale(b)
	b.MouseButton1Down:Connect(function()
		UI.squash(b, true)
	end)
	b.MouseButton1Up:Connect(function()
		UI.squash(b, false)
	end)
	b.MouseLeave:Connect(function()
		UI.squash(b, false)
	end)
	local sw = PetStyle.dot(b, (sp.Crystal :: Color3?) or K.White, 30, { Name = "Swatch", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0) })
	local rim = sw:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = (sp.Rim :: Color3?) or K.Ink
		rim.Thickness = 3
	end
	local nm = UI.text(b, tostring(sp.Name or id), { Name = "Name", TextSize = 16, Font = UI.Bold, TextColor3 = K.Ink, Position = UDim2.fromOffset(44, 3), Size = UDim2.new(1, -48, 0, 22), ZIndex = 5 })
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	nm.TextWrapped = false
	local kd = UI.text(b, tostring(sp.Kind or "?") .. " \u{00B7} " .. tostring(sp.BoostKind or "") .. (if sp.Chase then " \u{00B7} chase" else ""), {
		Name = "Kind", TextSize = 14, TextColor3 = TC.Muted, Position = UDim2.fromOffset(44, 25), Size = UDim2.new(1, -48, 0, 17), ZIndex = 5,
	})
	kd.TextTruncate = Enum.TextTruncate.AtEnd
	kd.TextWrapped = false
	local key = string.lower(tostring(sp.Name or id) .. " " .. tostring(id))
	search:GetPropertyChangedSignal("Text"):Connect(function()
		local q = string.lower(search.Text)
		b.Visible = q == "" or string.find(key, q, 1, true) ~= nil
	end)
	b.Activated:Connect(function()
		if busy then return end
		busy = true
		status.Text = "Spawning..."
		local ok, a, msg = pcall(function()
			return remote:InvokeServer(id, rarity)
		end)
		status.Text = if ok and a then "Got: " .. tostring(msg) else "Failed: " .. tostring(if ok then msg else a)
		busy = false
	end)
end

local function show(on: boolean)
	panel.Visible = on
	backdrop.Visible = on
end
open.Activated:Connect(function()
	show(not panel.Visible)
end)
close.Activated:Connect(function()
	show(false)
end)
backdrop.Activated:Connect(function()
	show(false)
end)
