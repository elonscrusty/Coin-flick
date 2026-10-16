-- _icons: the whole icon family at 36 and 18 px on slate and on cream (design review sheet).
local C = lib("ctr")
C.boot({ profile = function(data) data.TutorialStep = 1 end })
C.settle(1)
local UI = require(preview.clientFolder().ui.UI)
local gui = UI.overlay()
local kinds = { "cash", "rubble", "basket", "rock", "tray", "hammer", "jackhammer", "machine", "press", "crusher", "geode", "gem", "gear", "party", "user", "shop", "home", "results", "lock", "sell", "arrow", "back", "close", "plus", "check", "star", "crown", "clock" }
local root = UI.frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Colors.Cream })
for half = 0, 1 do
	local panel = UI.frame(root, {
		Position = UDim2.new(0, 0, half * 0.5, 0), Size = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = if half == 0 then UI.Colors.Slate else UI.Colors.Cream,
	})
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(52, 64)
	grid.CellPadding = UDim2.fromOffset(2, 2)
	grid.Parent = panel
	for _, k in kinds do
		local cell = UI.frame(panel, { BackgroundTransparency = 1 })
		local ink = if half == 0 then UI.Colors.Text else UI.Colors.Ink
		local bg = if half == 0 then UI.Colors.Slate else UI.Colors.Cream
		UI.icon(cell, k, 36, { Color = ink, Bg = bg, Position = UDim2.fromOffset(8, 0) })
		UI.icon(cell, k, 18, { Color = ink, Bg = bg, Position = UDim2.fromOffset(17, 40) })
	end
end
