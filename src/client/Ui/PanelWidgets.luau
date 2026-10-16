--!strict
-- Small pieces the GIFTS / PETS / GOALS shop tabs share: fitted labels, progress bars, a tap
-- guard (a press only counts when the list did not move under the finger) and a white card row.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TapGuard = require(ReplicatedStorage.Shared.Util.TapGuard)
local Sounds = require(script.Parent.Parent.Controllers.Sounds)
local Kit = require(script.Parent.Kit)

local PanelWidgets = {}

export type Bar = { track: Frame, fill: Frame, text: TextLabel }

local TRACK = Color3.fromRGB(226, 220, 208)

function PanelWidgets.label(props: { [string]: any }, max: number, ink: boolean): TextLabel
	if ink then
		props.TextColor3 = Kit.INK
		props.TextStrokeTransparency = 1
	end
	props.ZIndex = props.ZIndex or 7
	local l = Kit.label(props)
	Kit.textLimit(l, max)
	return l
end

function PanelWidgets.makeBar(parent: Frame, position: UDim2, size: UDim2, color: Color3): Bar
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = TRACK
	track.ZIndex = 7
	Kit.corner(track, 0.5)
	Kit.stroke(track, 1.5)
	track.Parent = parent
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.ZIndex = 8
	Kit.corner(fill, 0.5)
	fill.Parent = track
	local text = PanelWidgets.label({ Name = "Count", Size = UDim2.fromScale(1, 1), ZIndex = 9 }, 16, false)
	Kit.outline(text, 2)
	text.Parent = track
	return { track = track, fill = fill, text = text }
end

function PanelWidgets.setBar(bar: Bar, frac: number, text: string)
	bar.fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	bar.text.Text = text
end

-- A press only counts when the list did not move under the finger (same rule as the shop).
function PanelWidgets.guard(list: ScrollingFrame, button: TextButton, fn: () -> ())
	local downCanvas: number? = nil
	local lastScroll = -10
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		lastScroll = os.clock()
	end)
	button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			downCanvas = list.CanvasPosition.Y
		end
	end)
	button.Activated:Connect(function()
		local at = downCanvas or list.CanvasPosition.Y
		downCanvas = nil
		if TapGuard.ok(at, list.CanvasPosition.Y, os.clock() - lastScroll) then
			Sounds.play("Tap", 0.4)
			fn()
		end
	end)
end

function PanelWidgets.card(parent: ScrollingFrame, name: string, height: number, order: number): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, -10, 0, height)
	frame.LayoutOrder = order
	frame.BackgroundColor3 = Kit.CARD
	frame.ZIndex = 6
	Kit.corner(frame, 0.18)
	local outline = Kit.stroke(frame, 2)
	frame.Parent = parent
	return frame, outline
end

return PanelWidgets
