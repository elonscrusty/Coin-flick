--!strict
-- Shop preview models: one clone of every hand tool and machine in ReplicatedStorage.Assets.Previews,
-- built from the SAME factories the world uses (WorldBuilder.toolModel, MachineModels.build), so the
-- shop shows the real model: uploaded mesh when present, the Part model otherwise. The client
-- (ui/ItemView) prefers ReplicatedStorage.Assets.Kit.<name> when a kit model of that name is Ready.
-- Cheap: a handful of models built once at boot, never per UI open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local World = require(script.Parent.WorldBuilder)
local MachineModels = require(script.Parent.MachineModels)

local PreviewKit = {}

local function anchorAll(m: Instance)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("SurfaceGui") then
			d:Destroy() -- the owner plate text is not part of a shop picture
		end
	end
end

function PreviewKit.build()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	local old = (assets :: Instance):FindFirstChild("Previews")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Previews"
	for _, id in Config.HandheldOrder do
		local ok, m = pcall(World.toolModel, id, 1)
		if ok and m then
			m.Name = id
			anchorAll(m)
			m.Parent = folder
		end
	end
	for _, id in Config.MachineOrder do
		local holder = Instance.new("Folder")
		local ok, m = pcall(MachineModels.build, id, CFrame.new(), holder, 0, "")
		if ok and m then
			m.Name = id
			anchorAll(m)
			m.Parent = folder
		end
		holder:Destroy()
	end
	folder.Parent = assets
end

return PreviewKit
