--!strict
-- Photo mode (client only, lobby only, desktop P key; the HUD camera button was removed 2026-10-12, owner) hides every screen UI (the
-- game's ScreenGuis and Roblox's core UI) and gives a free orbit camera around the own avatar for screenshots of
-- pets. Drag to turn (mouse or one finger), wheel / pinch to zoom. A small X (or Esc / P / gamepad B) leaves; a
-- hunt starting or the character respawning leaves too. Nothing is sent to the server.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)
local CameraMode = require(script.Parent.CameraMode)
local UI = require(script.Parent.ui.UI)

local PhotoMode = {}

local CINE = "PhotoMode"
local MIN_DIST, MAX_DIST = 4, 40
local player = Players.LocalPlayer

local active = false
local exitGui: ScreenGui? = nil
local hidden: { ScreenGui } = {}
local coreWas: boolean? = nil
local conns: { RBXScriptConnection } = {}
local yaw, pitch, dist = 0, math.rad(-12), 12
local dragging = false
local hiddenTags: { BillboardGui } = {} -- follower name tags live in the world, so they are hidden by hand

local function setTags(on: boolean)
	if on then
		for _, b in hiddenTags do
			if b.Parent then
				b.Enabled = true
			end
		end
		table.clear(hiddenTags)
		return
	end
	local f = Workspace:FindFirstChild("CTR_Pets")
	if not f then
		return
	end
	for _, d in f:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "PetTag" and d.Enabled then
			d.Enabled = false
			table.insert(hiddenTags, d)
		end
	end
end

local function headOf(): BasePart?
	local char = player.Character
	local h = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
	return if h and h:IsA("BasePart") then h else nil
end

local function exit()
	if not active then
		return
	end
	active = false
	dragging = false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	ContextActionService:UnbindAction("CTR_PhotoExit")
	RunService:UnbindFromRenderStep("CTR_PhotoMode")
	for _, g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
	setTags(true)
	if coreWas ~= false then
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
	end
	coreWas = nil
	if exitGui then
		exitGui.Enabled = false
	end
	UI.block(CINE, false)
	CameraMode.cinematic(CINE, false)
end

local function ensureExit(): ScreenGui
	if exitGui and exitGui.Parent then
		return exitGui :: ScreenGui
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "CT_PhotoMode"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 40
	sg.Enabled = false
	sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	sg.Parent = player:WaitForChild("PlayerGui")
	local x = UI.closeButton(sg, exit, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -UI.T.Edge, 0, UI.T.Edge) })
	x.BackgroundTransparency = 0.45
	exitGui = sg
	return sg
end

local function step()
	local cam = Workspace.CurrentCamera
	local head = headOf()
	if not cam or not head or State.Match ~= nil then
		task.defer(exit)
		return
	end
	local focus = head.Position + Vector3.new(0, 0.5, 0)
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	cam.CFrame = CFrame.new(focus) * rot * CFrame.new(0, 0, dist)
end

local function enter()
	if active or State.Match ~= nil or CameraMode.inHunt() or UI.blocked() then
		return
	end
	local cam = Workspace.CurrentCamera
	local head = headOf()
	if not cam or not head then
		return
	end
	active = true
	-- start from the current view
	local look = cam.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), math.rad(-80), math.rad(60))
	dist = math.clamp((cam.CFrame.Position - head.Position).Magnitude, MIN_DIST, MAX_DIST)
	-- hide the screen UI (ours and Roblox's)
	local mine = ensureExit()
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("ScreenGui") and g ~= mine and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local okCore, was = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.All)
	end)
	coreWas = if okCore then was else nil
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	mine.Enabled = true
	setTags(false)
	UI.block(CINE, true) -- touch controls off, gameplay input suspended (CameraMode)
	CameraMode.cinematic(CINE, true)
	cam.CameraType = Enum.CameraType.Scriptable
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch then
			dragging = true
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			dist = math.clamp(dist - input.Position.Z * 2, MIN_DIST, MAX_DIST)
		elseif dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			local d: Vector3 = input.Delta
			yaw -= d.X * 0.008
			pitch = math.clamp(pitch - d.Y * 0.008, math.rad(-80), math.rad(60))
		elseif t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p: Vector3 = input.Position
			if p.Magnitude > 0.2 then
				yaw -= p.X * 0.05
				pitch = math.clamp(pitch + p.Y * 0.04, math.rad(-80), math.rad(60))
			end
		end
	end))
	local lastScale = 1
	table.insert(conns, UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if state == Enum.UserInputState.Begin then
			lastScale = 1
		end
		dist = math.clamp(dist * lastScale / math.max(scale, 0.05), MIN_DIST, MAX_DIST)
		lastScale = scale
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function()
		task.defer(exit)
	end))
	ContextActionService:BindActionAtPriority("CTR_PhotoExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			task.defer(exit)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Escape, Enum.KeyCode.P, Enum.KeyCode.ButtonB)
	RunService:BindToRenderStep("CTR_PhotoMode", Enum.RenderPriority.Camera.Value + 5, step)
end

function PhotoMode.isActive(): boolean
	return active
end

function PhotoMode.start()
	State.Changed.Event:Connect(function(what)
		if what == "Match" and State.Match ~= nil then
			exit()
		end
	end)
	-- desktop: P enters
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and not active and input.KeyCode == Enum.KeyCode.P then
			enter()
		end
	end)
end

return PhotoMode
