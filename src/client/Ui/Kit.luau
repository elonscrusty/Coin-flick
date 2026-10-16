--!strict
-- Panel look on top of UiStyle (the one shared style module): the extra
-- colors, the button "looks" (buy / poor / max / locked / owned / equipped /
-- soon) and padding. Everything else is UiStyle's, re-exported here so panel
-- code reads the same as before.
--
-- Text rule: on a colored or busy background, text is bold WHITE with a dark
-- outline (UiStyle.label does this). Dark INK text only sits on cream cards.

local UiStyle = require(script.Parent.Parent.Controllers.UiStyle)

local Kit = {}

Kit.FONT = UiStyle.FONT
Kit.INK = UiStyle.INK
Kit.WHITE = UiStyle.WHITE
Kit.GREEN = UiStyle.GREEN
Kit.PURPLE = UiStyle.PURPLE
Kit.ORANGE = UiStyle.ORANGE
Kit.BLUE = UiStyle.BLUE
Kit.RED = UiStyle.RED
Kit.GREY = UiStyle.GREY
Kit.PANEL = UiStyle.PANEL
Kit.GOLD = UiStyle.GOLD
Kit.FAST = UiStyle.FAST
Kit.BOUNCY = UiStyle.BOUNCY
Kit.COUNT = UiStyle.COUNT
Kit.TEAL = Color3.fromRGB(30, 200, 180)
Kit.SLATE = Color3.fromRGB(80, 84, 104)
Kit.MUTED = Color3.fromRGB(120, 105, 90) -- second line text on cream
Kit.CARD = Color3.fromRGB(255, 255, 255)
Kit.SILVER = Color3.fromRGB(200, 205, 215)
Kit.BRONZE = Color3.fromRGB(215, 140, 80)

-- Only "buy" is bright green; things you can't press are flat and dark so
-- they never look buyable.
Kit.LOOKS = {
	buy = { bg = Color3.fromRGB(70, 210, 110), text = Color3.fromRGB(255, 255, 255) },
	poor = { bg = Color3.fromRGB(110, 150, 125), text = Color3.fromRGB(255, 255, 255) },
	max = { bg = UiStyle.GOLD, text = Color3.fromRGB(255, 255, 255) },
	locked = { bg = Color3.fromRGB(150, 105, 215), text = Color3.fromRGB(255, 255, 255) },
	owned = { bg = Color3.fromRGB(60, 170, 255), text = Color3.fromRGB(255, 255, 255) },
	equipped = { bg = Color3.fromRGB(30, 200, 180), text = Color3.fromRGB(255, 255, 255) },
	soon = { bg = Color3.fromRGB(80, 84, 104), text = Color3.fromRGB(255, 255, 255) },
} :: { [string]: { bg: Color3, text: Color3 } }

Kit.corner = UiStyle.corner
-- Border outline; an optional color replaces the default dark one.
function Kit.stroke(parent: GuiObject, thickness: number?, color: Color3?): UIStroke
	local s = UiStyle.stroke(parent, thickness)
	if color then
		s.Color = color
	end
	return s
end
Kit.label = UiStyle.label
Kit.button = UiStyle.button
Kit.popScale = UiStyle.popScale

-- The thick letter outline (made once; UiStyle.label already adds one).
function Kit.outline(text: TextLabel | TextButton, thickness: number?): UIStroke
	local existing = text:FindFirstChild("TextOutline")
	if existing and existing:IsA("UIStroke") then
		if thickness then
			existing.Thickness = thickness
		end
		return existing
	end
	return UiStyle.textOutline(text, thickness)
end

function Kit.textLimit(text: TextLabel | TextButton, max: number, _min: number?)
	UiStyle.textLimit(text, max)
end

function Kit.padding(parent: GuiObject, x: UDim, y: UDim)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = x
	pad.PaddingRight = x
	pad.PaddingTop = y
	pad.PaddingBottom = y
	pad.Parent = parent
end

-- Paints a button in one of the Kit.LOOKS styles.
function Kit.applyLook(b: TextButton, look: string)
	local style = Kit.LOOKS[look] or Kit.LOOKS.poor
	b.BackgroundColor3 = style.bg
	b.TextColor3 = style.text
end

return Kit
