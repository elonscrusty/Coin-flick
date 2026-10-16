--!strict
-- Statues of the top 3 players (idea 38, owner pick 2026-10-15). Lobby only. Each pedestal is a BasePart with
-- attribute TopStatue = 1, 2 or 3 (placed in Studio; with none in the map nothing is built). On it stands that rank's
-- real Roblox avatar from the STRONGEST PET board (LeaderboardService "Power"), frozen in place and scaled up
-- (1st biggest), with a "#1 Name / power" sign. Rebuilt when the board's top 3 changes. Nothing is invented: an empty
-- or unreadable board leaves the pedestal empty.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Leaderboards = require(script.Parent.LeaderboardService)
local StandRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").StandRules)

local TopStatues = {}

local BOARD = "Power"
local SCALE = { 1.7, 1.5, 1.35 }
local COLOR = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(215, 225, 240), Color3.fromRGB(230, 150, 90) }

local shown: { [number]: number } = {} -- rank -> user id on the pedestal now

local function pedestals(): { [number]: BasePart }
	local out = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local r = d:GetAttribute("TopStatue")
			if type(r) == "number" and r >= 1 and r <= 3 and not out[r] then
				out[math.floor(r)] = d
			end
		end
	end
	return out
end

local function sign(model: Model, rank: number, name: string, text: string)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "StatueSign"
	bb.Size = UDim2.fromOffset(220, 56)
	bb.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y + 1.6, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	local function line(t: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, h)
		l.Position = UDim2.fromOffset(0, y)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = t
		l.TextColor3 = color
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = Color3.fromRGB(40, 30, 20)
		l.Parent = bb
	end
	line("#" .. rank .. " " .. name, 0, 30, COLOR[rank])
	line(text, 30, 24, Color3.new(1, 1, 1))
	bb.Parent = head
end

local function place(rank: number, pad: BasePart, row: Leaderboards.Row)
	local old = pad:FindFirstChild("TopStatueModel")
	if old then
		old:Destroy()
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(row.UserId)
	end)
	if not (ok and model) then
		warn("[TopStatues] avatar failed for rank", rank, model)
		return
	end
	model.Name = "TopStatueModel"
	-- Studio 2026-10-15: anchoring every part before the model was in the world left the avatar without joints (the
	-- rig is built when it is parented), so PivotTo moved only the root and head and the limbs stayed behind 40 studs
	-- away. Now: only the root anchored, parented first so the joints build, then scaled, stood up, and frozen.
	local root = model:FindFirstChild("HumanoidRootPart")
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	model:PivotTo(CFrame.new(pad.Position + Vector3.new(0, 10, 0)))
	model.Parent = pad
	task.wait(0.3)
	pcall(function()
		model:ScaleTo(SCALE[rank])
	end)
	-- stand it upright first (a fresh avatar can come in tilted)
	local p0 = model:GetPivot()
	model:PivotTo(CFrame.lookAt(p0.Position, p0.Position + StandRules.facing(p0)))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- feet on the pedestal top, measured on the VISIBLE parts (an invisible part sat 2.6 studs under the feet)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local c, s = d.CFrame, d.Size / 2
			local e = Vector3.new(
				math.abs(c.RightVector.X) * s.X + math.abs(c.UpVector.X) * s.Y + math.abs(c.LookVector.X) * s.Z,
				math.abs(c.RightVector.Y) * s.X + math.abs(c.UpVector.Y) * s.Y + math.abs(c.LookVector.Y) * s.Z,
				math.abs(c.RightVector.Z) * s.X + math.abs(c.UpVector.Z) * s.Y + math.abs(c.LookVector.Z) * s.Z
			)
			lo = lo:Min(c.Position - e)
			hi = hi:Max(c.Position + e)
		end
	end
	if lo.Y < math.huge then
		model:PivotTo(StandRules.onTop(pad.CFrame, pad.Size, model:GetPivot(), CFrame.new((lo + hi) / 2), hi - lo))
	end
	sign(model, rank, row.Name, row.Text)
end

local function refresh()
	local state = Leaderboards.get(BOARD)
	if state.Status ~= "ok" then
		return
	end
	local pads = pedestals()
	for rank = 1, 3 do
		local pad = pads[rank]
		local row = state.Rows[rank]
		if pad and row and shown[rank] ~= row.UserId then
			shown[rank] = row.UserId
			task.spawn(place, rank, pad, row)
		end
	end
end

function TopStatues.start()
	Leaderboards.onUpdated(function(board)
		if board == BOARD then
			refresh()
		end
	end)
	task.delay(5, refresh)
end

return TopStatues
