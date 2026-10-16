-- boards: the lobby leaderboards. The board FACE is built by the real LobbyBoards.createContent into a ScreenGui
-- (the lobby scene now draws the real SurfaceGui boards too) (same layout code the 3D boards use,
-- fed by the real LeaderboardService reading seeded in-memory OrderedDataStores). The 3D stands
-- (posts, frame, header) are in the world: --set view=world looks at them from the plaza.
--   --set board=Wins|Biggest|Collection|Solo|all   (default Wins; all = four in a row)
--   --set style=lodge                              the Prospector Lodge face (five dark rows, avatar heads; Solo / Wins)
--   --set state=ok|loading|error|empty|unavailable       (ok = real service rows; others set the face directly)
--   --set rows=N                                    (seeded players, default 12)
local C = lib("ctr")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local s = C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Stats.MultiplayerWins = 4
	end,
})
C.settle(1)

local Boards = C.shared("Boards")
local Leaderboards = C.server("LeaderboardService")
local LobbyBoards = C.server("LobbyBoards")
local state = preview.args.state or "ok"
local rows = tonumber(preview.args.rows) or 12

-- seed the in-memory stores with made-up players (preview only)
local fakeNames = { "Ava", "Ben", "Cleo", "Dax", "Eli", "Fay", "Gus", "Hana", "Ivo", "Jade", "Kit", "Lia" }
local ok, err = pcall(function()
	for _, id in ipairs(Boards.Order) do
		local store = DataStoreService:GetOrderedDataStore("CTR_LB_" .. id)
		for i = 1, rows do
			local base = ({ Wins = 40, Biggest = 90000, Collection = 120, Solo = 60 })[id]
			store:SetAsync(tostring(1000 + i), math.max(1, math.floor(base * (1 - (i - 1) * 0.07))))
		end
	end
end)
if not ok then
	preview.warn("seeding ordered stores failed: " .. tostring(err))
end
if Leaderboards then
	C.try("refresh", Leaderboards.refreshAll)
end

if preview.args.view == "world" then
	local p = C.lobbySpawn().Position
	C.cameraAt(Vector3.new(50, 8, 14), Vector3.new(-6, 4, 30), 62)
	C.settle(0.5)
	return
end

-- ScreenGui with the board face(s)
local gui = Instance.new("ScreenGui")
gui.Name = "BoardsPreview"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local holder = Instance.new("Frame")
holder.Size = UDim2.fromScale(1, 1)
holder.BackgroundColor3 = Color3.fromRGB(30, 34, 40)
holder.Parent = gui
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, 8)
list.Parent = holder

local which = preview.args.board or "Wins"
local ids = which == "all" and Boards.Order or { which }
for _, id in ipairs(ids) do
	local cell = Instance.new("Frame")
	cell.Size = UDim2.new(1 / #ids, -8, 1, -16)
	cell.BackgroundTransparency = 1
	cell.Parent = holder
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = if preview.args.style == "lodge" then 11.0 / 8.65 else 580 / 710
	ar.Parent = cell
	local h = if preview.args.style == "lodge" then LobbyBoards.createLodgeContent(cell, id) else LobbyBoards.createContent(cell, id)
	if state == "ok" then
		h.Set(Leaderboards.get(id))
	elseif state == "unavailable" then
		h.Set({ Status = "unavailable", Rows = {}, Updated = 0 })
	elseif state == "error" then
		h.Set({ Status = "error", Rows = {}, Updated = 0 })
	elseif state == "empty" then
		h.Set({ Status = "ok", Rows = {}, Updated = 0 })
	else
		h.Set({ Status = "loading", Rows = {}, Updated = 0 })
	end
end
C.settle(0.5)
