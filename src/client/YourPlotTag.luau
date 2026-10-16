--!strict
-- "YOUR PLOT" over the local player's own plot, only on their screen (audit 2 #3: similar yards made players check
-- every sign to find theirs). The server gives plots out on join (GalleryService, player attribute Alcove); other
-- players keep seeing the owner's name on the sign. Hidden in hunts, the tower and battles.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MapNames = require(Shared.MapNames)
local ParkConfig = require(Shared.ParkConfig)

local YourPlotTag = {}

local player = Players.LocalPlayer
local tag: BillboardGui? = nil

-- the plot's gate sign part, else its floor
local function anchor(idx: number): BasePart?
	local m = Workspace:FindFirstChild(MapNames.plot(idx), true)
	if not m then
		return nil
	end
	for _, n in MapNames.PlotSign do
		local s = m:FindFirstChild(n, true)
		local p = if s and s:IsA("BasePart") then s elseif s and s:IsA("Model") then s.PrimaryPart or s:FindFirstChildWhichIsA("BasePart", true) else nil
		if p then
			return p
		end
	end
	local f = m:FindFirstChild(MapNames.PlotFloor, true)
	return if f and f:IsA("BasePart") then f else nil
end

local function build(at: BasePart): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "YourPlotTag"
	bb.Size = UDim2.fromOffset(170, 44)
	bb.StudsOffsetWorldSpace = Vector3.new(0, at.Size.Y / 2 + 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.BackgroundColor3 = Color3.fromRGB(110, 200, 90)
	l.BorderSizePixel = 0
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Text = ParkConfig.YourPlot
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.fromRGB(40, 90, 30)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = l
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = l
	l.Parent = bb
	bb.Adornee = at
	bb.Parent = player:WaitForChild("PlayerGui")
	return bb
end

local function away(): boolean
	return player:GetAttribute("MatchKey") ~= nil or player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true
end

local function refresh()
	local idx = player:GetAttribute("Alcove")
	local at = if type(idx) == "number" then anchor(idx) else nil
	local t = tag
	if t and (not at or t.Adornee ~= at) then
		t:Destroy()
		tag, t = nil, nil
	end
	if at and not t then
		t = build(at)
		tag = t
	end
	if t then
		t.Enabled = not away()
	end
end

function YourPlotTag.start()
	for _, a in { "Alcove", "MatchKey", "InTower", "InBattle" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	task.spawn(function()
		-- the hand-built map can stream in after join: look again for a while
		for _ = 1, 30 do
			refresh()
			task.wait(2)
		end
	end)
end

return YourPlotTag
