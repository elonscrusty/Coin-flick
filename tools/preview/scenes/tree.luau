-- tree: the leaderboard tree (server/TreeBoardService) on a LeaderboardTreeSpot in front of the spawn, the stand-in
-- tree, ten ranked players with made-up pets (PREVIEW TEST DATA ONLY: in-memory stores), the BATTLE pad.
local C = lib("ctr")
local s = C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Onboard.Skipped = true
		data.LastSeenNews = C.shared("WhatsNew").Version
	end,
})
local me = s.me
local root = me.Character:FindFirstChild("HumanoidRootPart") :: BasePart
local spotCF = root.CFrame * CFrame.new(0, -3, -60)
local folder = Instance.new("Folder")
folder.Name = "TreePreview"
local spot = Instance.new("Part")
spot.Name = "LeaderboardTreeSpot"
spot.Anchored = true
spot.Transparency = 1
spot.Size = Vector3.new(20, 1, 20)
spot.CFrame = CFrame.new(spotCF.Position) * CFrame.Angles(0, math.pi, 0)
spot.Parent = folder
folder.Parent = workspace
local TB = C.shared("TreeBoard")
local specs = C.fakeSpecimens(10)
local cards = {}
local ods = game:GetService("DataStoreService"):GetOrderedDataStore(s.Config.Leaderboards.StorePrefix .. "Power")
for i = 1, 10 do
	local power = 5000 - i * 350
	cards[2000 + i] = TB.card(specs[i], power)
	ods:SetAsync(tostring(2000 + i), power)
end
local Tree = C.server("TreeBoardService")
Tree.setStore(function(uid)
	return cards[uid]
end, function() end)
Tree.start({ folder })
C.server("LeaderboardService").refreshAll()
preview.advance(2)
Tree.draw()
local cam = workspace.CurrentCamera
local at = spotCF.Position + Vector3.new(0, 30, 0)
cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 18, 0) + (root.Position - at).Unit * 10, at)
preview.advance(1)
