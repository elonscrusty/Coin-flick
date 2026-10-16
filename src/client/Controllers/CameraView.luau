--!strict
-- Normal Roblox 3D camera by default (behind your avatar). The ZOOM button
-- swoops to a close "table view" of your own coins, great for fast tapping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraMath = require(ReplicatedStorage.Shared.Util.CameraMath)

local CameraView = {}

local player = Players.LocalPlayer
local enabled = false
local spawnHold = false -- the spawn view is showing; ends when you move
local shakeUntil = 0
local shakePower = 0
local rng = Random.new()
local ZOOM_FOV = 55
local WALK_FOV = 70

local tableName = `Table_{player.UserId}`
local cachedTable: Model? = nil

local function myTable(): Model?
	if cachedTable and cachedTable.Parent then
		return cachedTable
	end
	cachedTable = nil
	local folder = workspace:FindFirstChild("Tables")
	local model = folder and folder:FindFirstChild(tableName)
	if model and model:IsA("Model") then
		cachedTable = model
		return model
	end
	return nil
end

local function update()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if enabled then
		local model = myTable()
		local center = model and model:GetAttribute("Center")
		local outward = model and model:GetAttribute("Outward")
		if typeof(center) == "Vector3" and typeof(outward) == "Vector3" then
			local viewport = camera.ViewportSize
			local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 1.6
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = ZOOM_FOV
			-- The closest spot where all 10 coins and their flips fit between
			-- the HUD bars on this screen shape (CameraMath, tested in Lune).
			local view = CameraMath.tableView(aspect, ZOOM_FOV)
			local eye = center - outward * view.back + Vector3.new(0, view.up, 0)
			camera.CFrame = CFrame.lookAt(eye, center + outward * view.aim)
		end
	end
	if spawnHold and not enabled then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.MoveDirection.Magnitude > 0.1 then
			CameraView.releaseSpawn()
		end
	end
	if os.clock() < shakeUntil then
		local left = (shakeUntil - os.clock())
		local p = shakePower * math.min(1, left * 4)
		camera.CFrame *= CFrame.new(rng:NextNumber(-p, p), rng:NextNumber(-p, p), 0)
	end
end

function CameraView.isTableView(): boolean
	return enabled
end

-- Back to the normal camera: behind your avatar, looking a little down at it.
-- (Just switching to Custom kept the steep ZOOM angle, so the camera sat right
-- on top of your head looking straight down.)
local function behindAvatar(camera: Camera)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		local focus = root.Position + Vector3.new(0, 1.5, 0)
		local walk = CameraMath.WALK
		camera.CFrame = CFrame.lookAt(focus - look.Unit * walk.back + Vector3.new(0, walk.up, 0), focus)
	end
end

-- Hand the camera back to Roblox (behind your avatar). Called when you start walking.
function CameraView.releaseSpawn()
	if not spawnHold then
		return
	end
	spawnHold = false
	local camera = workspace.CurrentCamera
	if camera and not enabled then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = WALK_FOV
		behindAvatar(camera)
		task.defer(behindAvatar, camera)
	end
end

function CameraView.toggle(): boolean
	enabled = not enabled
	if enabled then
		spawnHold = false
	end
	if not enabled then
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = WALK_FOV
		behindAvatar(camera)
		-- The Roblox camera script reads the camera on its next frame; set it again then.
		task.defer(behindAvatar, camera)
	end
	return enabled
end

-- Little screen shake for big moments (reset now, big rare flips later).
function CameraView.shake(power: number, seconds: number)
	shakePower = power
	shakeUntil = os.clock() + seconds
end

-- Normal view: when you spawn, look over your shoulder at your table.
local function faceTable()
	task.wait(0.3) -- the server moves you into your yard first
	local camera = workspace.CurrentCamera
	local model = myTable()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local center = model and model:GetAttribute("Center")
	local outward = model and model:GetAttribute("Outward")
	if enabled or not camera or not root or not root:IsA("BasePart") then
		return
	end
	if typeof(center) ~= "Vector3" or typeof(outward) ~= "Vector3" then
		return
	end
	-- High over the gate, looking down at the table: your avatar is below the picture and the
	-- arch behind the lens. It lasts until you move (or press ZOOM).
	local spawnView = CameraMath.SPAWN
	local eye = root.Position - outward * spawnView.back + Vector3.new(0, spawnView.up, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = WALK_FOV
	camera.CFrame = CFrame.lookAt(eye, center)
	spawnHold = true
end

function CameraView.init()
	player.CharacterAdded:Connect(function()
		task.spawn(faceTable)
	end)
	task.spawn(function()
		-- First spawn: wait for our table to exist.
		local folder = workspace:WaitForChild("Tables", 30)
		if folder then
			folder:WaitForChild(tableName, 30)
		end
		faceTable()
	end)
	RunService:BindToRenderStep("CoinFlickCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraView
