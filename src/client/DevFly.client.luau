--!strict
-- Dev fly (owner tool): F toggles flying for players the server marked IsDev (DevPets.server: Studio or the place
-- owner). WASD moves along the camera, Space up, Ctrl down. The character is client-owned, so the moves replicate.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local SPEED = 60
local flying = false
local conn: RBXScriptConnection? = nil

local function root(): (BasePart?, Humanoid?)
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	local h = char and char:FindFirstChildOfClass("Humanoid")
	return (if r and r:IsA("BasePart") then r else nil), h
end

local function stop()
	flying = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local r, h = root()
	if r then
		r.Anchored = false
		r.AssemblyLinearVelocity = Vector3.zero
	end
	if h then
		h.PlatformStand = false
	end
end

local function start()
	local r, h = root()
	if not (r and h) then
		return
	end
	flying = true
	h.PlatformStand = true
	conn = RunService.RenderStepped:Connect(function(dt)
		local rp, hp = root()
		if not (rp and hp) or hp.Health <= 0 then
			stop()
			return
		end
		local cam = Workspace.CurrentCamera
		local look = cam.CFrame.LookVector
		local right = cam.CFrame.RightVector
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += look end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
		if move.Magnitude > 0 then
			move = move.Unit * SPEED * dt
		end
		local pos = rp.Position + move
		rp.AssemblyLinearVelocity = Vector3.zero
		rp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.F or player:GetAttribute("IsDev") ~= true then
		return
	end
	if flying then
		stop()
	else
		start()
	end
end)

player.CharacterAdded:Connect(stop)
