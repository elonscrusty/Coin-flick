--!strict
-- Lobby name tags (owner pick, client only, cosmetic). Over every player's head in the lobby: the display name, the
-- title (gold, e.g. "Pet Master") and the best pet tower floor. The server decides both and puts them on the Player
-- as attributes "Title" and "TowerBest" (server PetIndex); this only draws them. Hidden while that player is in a
-- hunt (attribute MatchKey set) or the pet tower (InTower) so the view stays clear; while our tag shows, Roblox's own name over that
-- character is hidden locally so the name is not drawn twice.
-- The tag is middle-sized (the big one covered the pet and props in front of the player, the small one read faint on a
-- phone: bug #219) and fades out only while the camera is really close to that head (FADE_FAR -> FADE_NEAR studs), so
-- a zoomed-in view of your own pet is never hidden behind your name while the default zoom shows it fully.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PetFlair = require(Shared.PetFlair)
local UI = require(script.Parent.ui.UI)

local NameTag = {}

local C = UI.Colors
local LINE = 18
local NAME_H = 23
local WIDTH = 180
local FADE_FAR = 10 -- studs from the camera: fully shown beyond this (Roblox's default zoom is 12.5: no fade)
local FADE_NEAR = 5 -- studs: fully hidden at or inside this

type Entry = { Gui: BillboardGui?, Conns: { RBXScriptConnection } }
local entries: { [Player]: Entry } = {}

local function clear(e: Entry)
	if e.Gui then
		e.Gui:Destroy()
		e.Gui = nil
	end
end

local function setDefaultName(char: Model?, hide: boolean)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = if hide then Enum.HumanoidDisplayDistanceType.None else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function rebuild(player: Player, e: Entry)
	clear(e)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not char or not head or not head:IsA("BasePart") then
		return
	end
	if player:GetAttribute("MatchKey") ~= nil then
		setDefaultName(char, false)
		return -- lobby only
	end
	if player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true then
		setDefaultName(char, true)
		return -- in the pet tower no name floats over the fight (it sat behind LEAVE and the pets' bars)
	end
	local battle = PetFlair.battleLine(player:GetAttribute("TeamPower"), player:GetAttribute("Trophies"), player:GetAttribute("PvpStreak"))
	local lines = PetFlair.tagLines(player:GetAttribute("TowerBest"), player:GetAttribute("Title"), battle)
	local bb = Instance.new("BillboardGui")
	bb.Name = "LobbyNameTag"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(WIDTH, NAME_H + #lines * LINE)
	bb.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 1.4, 0)
	bb.MaxDistance = 60
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	-- every line keeps the full dark outline (UI.text thins it on small text): pale words vanished on the snow
	-- VIP pass (server attribute VIP): the name in gold with a VIP badge
	local vip = player:GetAttribute("VIP") == true
	local nameLabel = UI.text(bb, if vip then "[VIP] " .. player.DisplayName else player.DisplayName, {
		Name = "PlayerName", Font = UI.Bold, TextSize = 16, Outline = "Strong", TextColor3 = if vip then C.Gold else Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, NAME_H),
	})
	UI.outline(nameLabel, "Strong")
	for i, line in lines do
		local isTitle = i == 1 and line == player:GetAttribute("Title")
		local isBattle = line == battle
		local lineLabel = UI.text(bb, line, {
			Name = if isTitle then "Title" elseif isBattle then "Battle" else "Floor", Font = UI.Bold, TextSize = 14, Outline = "Strong",
			TextColor3 = if isTitle then C.Gold elseif isBattle then Color3.fromRGB(255, 196, 120) else Color3.fromRGB(200, 236, 255),
			TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, NAME_H + (i - 1) * LINE), Size = UDim2.new(1, 0, 0, LINE),
		})
		UI.outline(lineLabel, "Strong")
	end
	bb.Parent = head
	e.Gui = bb
	setDefaultName(char, true)
end

local function track(player: Player)
	if entries[player] then
		return
	end
	local e: Entry = { Gui = nil, Conns = {} }
	entries[player] = e
	local function again()
		rebuild(player, e)
	end
	for _, attr in { "Title", "TowerBest", "MatchKey", "InTower", "InBattle", "TeamPower", "Trophies", "PvpStreak", "VIP" } do
		table.insert(e.Conns, player:GetAttributeChangedSignal(attr):Connect(again))
	end
	table.insert(e.Conns, player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		again()
	end))
	table.insert(e.Conns, player.CharacterRemoving:Connect(function()
		clear(e)
	end))
	again()
end

local function untrack(player: Player)
	local e = entries[player]
	if not e then
		return
	end
	for _, c in e.Conns do
		c:Disconnect()
	end
	clear(e)
	entries[player] = nil
end

-- info boards players walk up to read (audit F26); positions refreshed now and then (the winners board is built late)
local INFO_BOARDS = { "WhatsNewBoard", "CT_WinnersNoticeBoard" }
local INFO_NEAR = 18
local boardPos: { Vector3 } = {}
local boardsAt = -math.huge
local function nearInfoBoard(at: Vector3): boolean
	if os.clock() - boardsAt > 3 then
		boardsAt = os.clock()
		table.clear(boardPos)
		for _, name in INFO_BOARDS do
			local b = Workspace:FindFirstChild(name, true)
			if b and b:IsA("Model") then
				table.insert(boardPos, b:GetPivot().Position)
			elseif b and b:IsA("BasePart") then
				table.insert(boardPos, b.Position)
			end
		end
	end
	for _, q in boardPos do
		if (Vector3.new(q.X, at.Y, q.Z) - at).Magnitude < INFO_NEAR then
			return true
		end
	end
	return false
end

local started = false
function NameTag.start()
	if started then
		return
	end
	started = true
	-- fade each tag by its distance to the camera (a few times a second is enough; writes only on change)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock < 0.08 then
			return
		end
		clock = 0
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		for p, e in entries do
			local bb = e.Gui
			local head = bb and bb.Adornee
			if not bb or not head or not head:IsA("BasePart") then
				continue
			end
			local d = (head.Position - camPos).Magnitude
			local k = math.clamp((FADE_FAR - d) / (FADE_FAR - FADE_NEAR), 0, 1)
			if p == Players.LocalPlayer and nearInfoBoard(head.Position) then
				k = 1 -- audit F26: your own tag sat right over the board text on a walk-up; others still see it
			end
			local tr = math.floor(k * 10 + 0.5) / 10 -- tenths, so small camera moves write nothing
			bb.Enabled = tr < 1
			for _, l in bb:GetChildren() do
				if l:IsA("TextLabel") and l.TextTransparency ~= tr then
					l.TextTransparency = tr -- UI.outline keeps the outline in step
				end
			end
		end
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(track, p)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
end

return NameTag
