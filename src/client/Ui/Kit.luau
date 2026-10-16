--!strict
-- Shared UI style for every COIN FLICK screen (HUD, shop, popups): colors,
-- font, motion and the chunky building blocks. One place, so all screens look
-- like one game.
--
-- Text rule: on a colored or busy background, text is bold WHITE with a dark
-- outline (Kit.outline). Dark INK text only sits on the cream panel color.

local TweenService = game:GetService("TweenService")

local Kit = {}

Kit.FONT = Enum.Font.FredokaOne

Kit.INK = Color3.fromRGB(45, 30, 20)
Kit.WHITE = Color3.fromRGB(255, 255, 255)
Kit.GREEN = Color3.fromRGB(70, 210, 110)
Kit.PURPLE = Color3.fromRGB(170, 110, 255)
Kit.ORANGE = Color3.fromRGB(255, 160, 40)
Kit.BLUE = Color3.fromRGB(60, 170, 255)
Kit.RED = Color3.fromRGB(255, 90, 90)
Kit.GREY = Color3.fromRGB(170, 170, 175)
Kit.PANEL = Color3.fromRGB(255, 248, 230)
Kit.GOLD = Color3.fromRGB(255, 196, 40)
Kit.TEAL = Color3.fromRGB(30, 200, 180)
Kit.SLATE = Color3.fromRGB(80, 84, 104)
Kit.MUTED = Color3.fromRGB(120, 105, 90) -- second line text on cream
Kit.CARD = Color3.fromRGB(255, 255, 255)
Kit.SILVER = Color3.fromRGB(200, 205, 215)
Kit.BRONZE = Color3.fromRGB(215, 140, 80)

Kit.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Kit.BOUNCY = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
Kit.COUNT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Button looks (see shared/Util/PanelView Look). Only "buy" is bright green;
-- things you can't press are flat and dark so they never look buyable.
Kit.LOOKS = {
	buy = { bg = Color3.fromRGB(70, 210, 110), text = Color3.fromRGB(255, 255, 255) },
	poor = { bg = Color3.fromRGB(150, 150, 158), text = Color3.fromRGB(255, 255, 255) },
	max = { bg = Color3.fromRGB(255, 196, 40), text = Color3.fromRGB(255, 255, 255) },
	locked = { bg = Color3.fromRGB(80, 84, 104), text = Color3.fromRGB(255, 255, 255) },
	owned = { bg = Color3.fromRGB(60, 170, 255), text = Color3.fromRGB(255, 255, 255) },
	equipped = { bg = Color3.fromRGB(30, 200, 180), text = Color3.fromRGB(255, 255, 255) },
	soon = { bg = Color3.fromRGB(80, 84, 104), text = Color3.fromRGB(255, 255, 255) },
} :: { [string]: { bg: Color3, text: Color3 } }

function Kit.corner(parent: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.25, 0)
	c.Parent = parent
end

-- Border outline around a box.
function Kit.stroke(parent: GuiObject, thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Kit.INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Thick dark outline around the letters themselves (reads on any background).
function Kit.outline(text: TextLabel | TextButton, thickness: number?): UIStroke
	(text :: any).TextStrokeTransparency = 1
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = Kit.INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = text
	return s
end

function Kit.textLimit(text: TextLabel | TextButton, max: number, min: number?)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = max
	c.MinTextSize = min or 10
	c.Parent = text
end

function Kit.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Kit.FONT
	l.TextScaled = true
	l.TextColor3 = Kit.WHITE
	l.TextStrokeColor3 = Kit.INK
	l.TextStrokeTransparency = 0.2
	for k, v in props do
		(l :: any)[k] = v
	end
	return l
end

function Kit.padding(parent: GuiObject, x: UDim, y: UDim)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = x
	pad.PaddingRight = x
	pad.PaddingTop = y
	pad.PaddingBottom = y
	pad.Parent = parent
end

-- A chunky cartoon button that squishes when pressed and bounces back.
function Kit.button(text: string, color: Color3, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = Kit.FONT
	b.TextScaled = true
	b.Text = text
	b.TextColor3 = Kit.WHITE
	Kit.outline(b, 2)
	Kit.corner(b)
	Kit.stroke(b)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	Kit.padding(b, UDim.new(0.08, 0), UDim.new(0.12, 0))
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, Kit.FAST, { Scale = 0.9 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Kit.BOUNCY, { Scale = 1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, Kit.BOUNCY, { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onPress)
	return b
end

-- Paints a button in one of the Kit.LOOKS styles.
function Kit.applyLook(b: TextButton, look: string)
	local style = Kit.LOOKS[look] or Kit.LOOKS.poor
	b.BackgroundColor3 = style.bg
	b.TextColor3 = style.text
end

function Kit.popScale(scale: UIScale, amount: number)
	scale.Scale = amount
	TweenService:Create(scale, Kit.BOUNCY, { Scale = 1 }):Play()
end

return Kit
