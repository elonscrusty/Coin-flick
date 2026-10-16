--!strict
-- Rainbow path (idea 34, client only, cosmetic). Anyone walking on a lobby path leaves a rainbow trail and a few
-- sparkles at their feet. A path is any part inside a folder or model named "Paths" (the lobby build's path layer) or a
-- part with attribute RainbowPath = true. Drawn by each viewer for every player, so everyone sees everyone's trail.
-- Off in a hunt (MatchKey), the tower and Pet Battles, and with Low Effects.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)
local PathGrid = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").PathGrid)

local RainbowPath = {}

local TICK = 0.2
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 235, 80)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 230, 120)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 180, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
})

type Fx = { Root: BasePart, Trail: Trail, Spark: ParticleEmitter, Parts: { Instance } }
local fx: { [Player]: Fx } = {}

local function low(): boolean
	local p = State.Profile
	return p ~= nil and p.Settings ~= nil and p.Settings.LowEffects == true
end

-- The lobby's path parts have CanQuery = false, so a raycast never hits them: the paths are read once into a flat grid
-- (shared/PathGrid) and a player is "on a path" when their feet are over one (top 0.5 stud above to 7 studs below the
-- root part).
local paths = PathGrid.new(16)
local lastScan = -math.huge
local function onPath(root: BasePart): boolean
	if paths.Count == 0 and os.clock() - lastScan > 10 then
		lastScan = os.clock()
		paths = PathGrid.lobbyPaths(Workspace)
	end
	local p = root.Position
	return PathGrid.under(paths, p.X, p.Y, p.Z, 0.5, 0.5, 7) ~= nil
end

local function clear(player: Player)
	local f = fx[player]
	if f then
		for _, inst in f.Parts do
			inst:Destroy()
		end
		fx[player] = nil
	end
end

local function build(player: Player, root: BasePart): Fx
	local a0 = Instance.new("Attachment")
	a0.Name = "RainbowA0"
	a0.Position = Vector3.new(0, -2.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "RainbowA1"
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "RainbowTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = RAINBOW
	trail.Lifetime = 0.7
	trail.MinLength = 0.2
	trail.LightEmission = 0.4
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = root
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "RainbowSparkle"
	spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spark.Color = RAINBOW
	spark.LightEmission = 1
	spark.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	spark.Lifetime = NumberRange.new(0.5, 0.9)
	spark.Rate = 10
	spark.Speed = NumberRange.new(1, 2.5)
	spark.SpreadAngle = Vector2.new(60, 60)
	spark.EmissionDirection = Enum.NormalId.Top
	spark.Enabled = false
	spark.Parent = a0
	local f: Fx = { Root = root, Trail = trail, Spark = spark, Parts = { a0, a1, trail } }
	fx[player] = f
	return f
end

local function update(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and root and root:IsA("BasePart") and hum) then
		clear(player)
		return
	end
	local away = player:GetAttribute("MatchKey") ~= nil or player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true
	local on = false
	if not away and not low() and hum.MoveDirection.Magnitude > 0.1 then
		on = onPath(root)
	end
	local cur: Fx? = fx[player]
	if cur and cur.Root ~= root then
		clear(player)
		cur = nil
	end
	if not cur and not on then
		return
	end
	local f: Fx = cur or build(player, root)
	f.Trail.Enabled = on
	f.Spark.Enabled = on
end

function RainbowPath.start()
	Players.PlayerRemoving:Connect(function(p)
		clear(p)
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(function()
					update(p)
				end)
				if not ok then
					warn("[RainbowPath]", err)
				end
			end
		end
	end)
end

return RainbowPath
