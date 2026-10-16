--!strict
-- "Table view": the camera looks down at your own table so coins are big,
-- easy tap targets on a phone. The VIEW button switches back to normal.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraView = {}

local player = Players.LocalPlayer
local enabled = true
local shakeUntil = 0
local shakePower = 0
local rng = Random.new()

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
			-- Tall/narrow screens need the camera further back to fit the table.
			local back = math.max(1, 1.45 / aspect)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.FieldOfView = 55
			local eye = center + outward * (15 * back) + Vector3.new(0, 20 * back, 0)
			camera.CFrame = CFrame.lookAt(eye, center + outward * 1.5)
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

function CameraView.toggle(): boolean
	enabled = not enabled
	if not enabled then
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	return enabled
end

-- Little screen shake for big moments (reset now, big rare flips later).
function CameraView.shake(power: number, seconds: number)
	shakePower = power
	shakeUntil = os.clock() + seconds
end

function CameraView.init()
	RunService:BindToRenderStep("CoinFlickCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraView
