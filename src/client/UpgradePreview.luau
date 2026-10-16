--!strict
-- The ONE preview pedestal beside the lobby's Upgrades counter (Master Prompt 5 sections 2 and 6).
--
-- Entirely client-local: the pedestal the server builds (model CT_Rocks_UpgradePedestal, part PreviewAnchor)
-- is empty geometry. This module clones the selected item's preview model (ReplicatedStorage.Assets.Previews,
-- the same real tool / machine models the shop pictures use) onto the anchor in a client-only folder, so
--   * it is per player: another player's selection or equipment never changes what you see;
--   * it grants nothing and owns nothing: it reads State.Profile only to pick the default and the label;
--   * it has no per-tool stand and no price table: items come from Config.HandheldOrder / MachineOrder, so
--     any number of future tools or machines appear with no lobby geometry (add the Config entry and its
--     preview model; the pedestal normalises every model to the same height by its bounding box).
-- Default item: the player's equipped hand tool. `UpgradePreview.select(id)` (or the Selected event) shows any
-- catalog item, `select(nil)` returns to the default. Nothing here is interactive (no collision, no query).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SignLayout = require(Shared.SignLayout)
local State = require(script.Parent.State)

local UpgradePreview = {}

UpgradePreview.Selected = Instance.new("BindableEvent") -- (itemId: string?) fired after the shown item changes

local MAX_WIDTH = 3.4 -- studs: the largest footprint a preview may take on the pedestal
local SPIN = 0.5 -- radians per second
local SHOW_RANGE = 70

local selected: string? = nil
local anchor: BasePart? = nil
local labelPart: BasePart? = nil
local localFolder: Folder? = nil
local shown: Model? = nil
local shownId: string? = nil
local shownRel: CFrame = CFrame.new()
local shownSize: Vector3 = Vector3.one
local angle = 0
local started = false

-- Every catalog item in display order: hand tools, then machines. Data comes from Config only.
function UpgradePreview.items(): { { Id: string, Name: string } }
	local out = {}
	for _, id in Config.HandheldOrder do
		local h = Config.Handhelds[id]
		if h then
			table.insert(out, { Id = id, Name = h.Name })
		end
	end
	for _, id in Config.MachineOrder do
		local mc = Config.Machines[id]
		if mc then
			table.insert(out, { Id = id, Name = mc.Name })
		end
	end
	return out
end

local function nameOf(id: string): string
	local h = Config.Handhelds[id]
	if h then
		return h.Name
	end
	local mc = Config.Machines[id]
	return if mc then mc.Name else id
end

local function isItem(id: string): boolean
	return Config.Handhelds[id] ~= nil or Config.Machines[id] ~= nil
end

-- What the pedestal shows: the explicit selection, else the equipped hand tool, else the first catalog item.
function UpgradePreview.currentId(): string?
	if selected and isItem(selected) then
		return selected
	end
	local prof = State.Profile
	local eq = prof and prof.EquippedHandheld
	if type(eq) == "string" and isItem(eq) then
		return eq
	end
	return Config.HandheldOrder[1]
end

local function setLabel(text: string)
	local p = labelPart
	if not p then
		return
	end
	local gui = p:FindFirstChildOfClass("SurfaceGui")
	local t = gui and gui:FindFirstChildWhichIsA("TextLabel")
	local w, h = p:GetAttribute("SignW"), p:GetAttribute("SignH")
	if gui and t and type(w) == "number" and type(h) == "number" then
		local f = SignLayout.fit(string.upper(text), w, h, "Plaque")
		gui.PixelsPerStud = f.PPS
		t.TextSize = f.TextSize
		t.Text = f.Text
		p:SetAttribute("SignText", f.Text)
		p:SetAttribute("SignFill", f.Fill)
	end
end

local function place()
	local m, a = shown, anchor
	if m and a then
		local target = CFrame.new(a.Position + Vector3.new(0, shownSize.Y / 2, 0)) * CFrame.Angles(0, angle, 0)
		m:PivotTo(target * shownRel)
	end
end

local function clearShown()
	if shown then
		shown:Destroy()
	end
	shown = nil
	shownId = nil
end

local function refresh()
	local a = anchor
	if not a or not a.Parent then
		return
	end
	local id = UpgradePreview.currentId()
	if id == shownId then
		return
	end
	clearShown()
	if not id then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local previews = assets and assets:FindFirstChild("Previews")
	local template = previews and previews:FindFirstChild(id)
	if not template or not template:IsA("Model") then
		setLabel(nameOf(id))
		return
	end
	local m = template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	-- normalise by the model's bounds: one pedestal height for a hammer or a crusher, then clamp the footprint
	local height = (a:GetAttribute("PreviewHeight") :: number?) or 3.2
	local _, size0 = m:GetBoundingBox()
	local k = height / math.max(size0.Y, 0.1)
	local widest = math.max(size0.X, size0.Z) * k
	if widest > MAX_WIDTH then
		k *= MAX_WIDTH / widest
	end
	m:ScaleTo(k * m:GetScale())
	local bb, size = m:GetBoundingBox()
	shownSize = size
	shownRel = bb:ToObjectSpace(m:GetPivot())
	m.Name = "Preview_" .. id
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("CameraIgnore", true)
		end
	end
	if not localFolder then
		local f = Instance.new("Folder")
		f.Name = "UpgradePreviewLocal"
		f.Parent = Workspace
		localFolder = f
	end
	m.Parent = localFolder
	shown = m
	shownId = id
	place()
	setLabel(nameOf(id))
	UpgradePreview.Selected:Fire(id)
end

-- Show catalog item `id` on the pedestal (this player only); nil goes back to the equipped tool.
function UpgradePreview.select(id: string?)
	if id ~= nil and not isItem(id) then
		return
	end
	selected = id
	refresh()
end

function UpgradePreview.start()
	if started then
		return
	end
	started = true
	-- The pedestal may arrive late (StreamingEnabled streams the lobby in by distance) or come back as a new part after
	-- streaming out: listen for it instead of looking once.
	local function adopt(found: Instance)
		if found.Name == "PreviewLabel" and found:IsA("BasePart") and anchor and found.Parent == anchor.Parent then
			labelPart = found
			if shownId then
				setLabel(nameOf(shownId))
			end
			return
		end
		if found.Name ~= "PreviewAnchor" or not found:IsA("BasePart") or found == anchor then
			return
		end
		anchor = found
		labelPart = (found.Parent and found.Parent:FindFirstChild("PreviewLabel")) :: BasePart?
		refresh()
	end
	local function watchLobby(lobby: Instance)
		local found = lobby:FindFirstChild("PreviewAnchor", true)
		if found then
			adopt(found)
		end
		lobby.DescendantAdded:Connect(adopt)
	end
	task.spawn(function()
		local lobby = Workspace:WaitForChild("CT_Rocks_Lobby", 30)
		if lobby then
			watchLobby(lobby)
		else
			-- the match place has no lobby (nothing to do); a lobby that turns up later is still picked up
			local conn: RBXScriptConnection? = nil
			conn = Workspace.ChildAdded:Connect(function(c)
				if c.Name == "CT_Rocks_Lobby" then
					if conn then
						conn:Disconnect()
					end
					watchLobby(c)
				end
			end)
		end
		State.Changed.Event:Connect(function(what)
			if what == "Profile" then
				refresh()
			end
		end)
		RunService.Heartbeat:Connect(function(dt: number)
			local m, a = shown, anchor
			if not m or not a then
				return
			end
			if State.Profile and State.Profile.Settings and State.Profile.Settings.ReducedMotion == true then
				return
			end
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - a.Position).Magnitude < SHOW_RANGE then
				angle = (angle + dt * SPIN) % (math.pi * 2)
				place()
			end
		end)
	end)
end

return UpgradePreview
