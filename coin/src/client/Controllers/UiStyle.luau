--!strict
-- One look for every screen piece: colors, font, motion, and the small
-- builders (label, button, outline) the HUD and panels share. Text gets a
-- real thick outline (UIStroke) so it reads on bright sky and busy 3D.

local TweenService = game:GetService("TweenService")

local UiStyle = {}

UiStyle.FONT = Enum.Font.FredokaOne
UiStyle.INK = Color3.fromRGB(45, 30, 20)
UiStyle.WHITE = Color3.fromRGB(255, 255, 255)
UiStyle.GREEN = Color3.fromRGB(70, 210, 110)
UiStyle.PURPLE = Color3.fromRGB(170, 110, 255)
UiStyle.ORANGE = Color3.fromRGB(255, 160, 40)
UiStyle.BLUE = Color3.fromRGB(60, 170, 255)
UiStyle.RED = Color3.fromRGB(255, 90, 90)
UiStyle.GREY = Color3.fromRGB(170, 170, 175)
UiStyle.PANEL = Color3.fromRGB(255, 248, 230)
UiStyle.GOLD = Color3.fromRGB(255, 220, 60)

UiStyle.FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UiStyle.BOUNCY = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
UiStyle.COUNT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Smallest text a phone player can still read.
UiStyle.MIN_TEXT = 14

function UiStyle.corner(parent: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.25, 0)
	c.Parent = parent
end

-- Border outline for frames and buttons.
function UiStyle.stroke(parent: GuiObject, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = UiStyle.INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Thick dark outline around the letters themselves (much bolder than
-- TextStroke). Named so code can find it to fade it with the text.
function UiStyle.textOutline(parent: TextLabel | TextButton, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = "TextOutline"
	s.Thickness = thickness or 2.5
	s.Color = UiStyle.INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	local anyParent: any = parent
	anyParent.TextStrokeTransparency = 1
	return s
end

-- Fade a label's text and its outline together.
function UiStyle.fadeText(l: TextLabel, transparency: number, info: TweenInfo?): Tween
	local outline = l:FindFirstChild("TextOutline")
	if outline and outline:IsA("UIStroke") then
		TweenService:Create(outline, info or UiStyle.COUNT, { Transparency = transparency }):Play()
	end
	local t = TweenService:Create(l, info or UiStyle.COUNT, { TextTransparency = transparency })
	t:Play()
	return t
end

-- Show a faded label again (text and outline).
function UiStyle.showText(l: TextLabel)
	l.TextTransparency = 0
	local outline = l:FindFirstChild("TextOutline")
	if outline and outline:IsA("UIStroke") then
		outline.Transparency = 0
	end
end

function UiStyle.textLimit(l: TextLabel | TextButton, max: number, min: number?)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = max
	c.MinTextSize = math.min(max, min or UiStyle.MIN_TEXT)
	c.Parent = l
end

-- Chunky cartoon shading for a card or panel: a soft light-to-shade gradient and a thin
-- glossy highlight strip along the top. (The gradient only paints this frame, not its children.)
function UiStyle.chunky(frame: GuiObject, shade: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Shade"
	local low = math.floor(255 * (shade or 0.9))
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(low, low, low))
	gradient.Rotation = 90
	gradient.Parent = frame
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.new(0.5, 0, 0, 3)
	gloss.Size = UDim2.new(0.9, 0, 0, 4)
	gloss.BackgroundColor3 = UiStyle.WHITE
	gloss.BackgroundTransparency = 0.45
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 1
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = gloss
	gloss.Parent = frame
end

-- White text with a thick outline. Dark text (TextColor3 = INK) gets no
-- outline: it sits on light cards.
function UiStyle.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UiStyle.FONT
	l.TextScaled = true
	l.TextColor3 = UiStyle.WHITE
	l.TextStrokeColor3 = UiStyle.INK
	l.TextStrokeTransparency = 0.2
	for k, v in props do
		(l :: any)[k] = v
	end
	if l.TextStrokeTransparency < 1 then
		UiStyle.textOutline(l)
	end
	return l
end

function UiStyle.popScale(scale: UIScale, amount: number)
	scale.Scale = amount
	TweenService:Create(scale, UiStyle.BOUNCY, { Scale = 1 }):Play()
end

-- A glossy highlight across the top of a chunky piece (pills, chips, buttons):
-- a soft white band under the labels, so the piece looks like shiny plastic.
function UiStyle.gloss(parent: GuiObject, transparency: number?): Frame
	local band = Instance.new("Frame")
	band.Name = "Gloss"
	band.AnchorPoint = Vector2.new(0.5, 0)
	band.Position = UDim2.fromScale(0.5, 0.07)
	band.Size = UDim2.fromScale(0.86, 0.34)
	band.BackgroundColor3 = UiStyle.WHITE
	band.BackgroundTransparency = transparency or 0.72
	band.BorderSizePixel = 0
	band.Active = false
	band.ZIndex = 2
	UiStyle.corner(band, 0.5)
	band.Parent = parent
	return band
end

-- A chunky cartoon button that squishes when pressed.
function UiStyle.button(text: string, color: Color3, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = UiStyle.FONT
	b.TextScaled = true
	b.Text = text
	b.TextColor3 = UiStyle.WHITE
	b.TextStrokeColor3 = UiStyle.INK
	UiStyle.corner(b)
	UiStyle.stroke(b, 3.5)
	UiStyle.textOutline(b, 2.5)
	UiStyle.chunky(b, 0.84)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, UiStyle.FAST, { Scale = 0.9 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, UiStyle.BOUNCY, { Scale = 1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, UiStyle.BOUNCY, { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onPress)
	return b
end

return UiStyle
