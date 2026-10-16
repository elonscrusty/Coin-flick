-- lobby: the real server + client booted, the lobby world and HUD, camera behind the
-- player at the spawn. --set cash=N sets the profile cash, --set view=wide a high view
-- over the lobby. --set kit=off builds every kit stall / board as its Part stand-in (LodgeBuilder fallback).
local C = lib("ctr")
if preview.args.kit == "off" then
	game:GetService("Workspace"):SetAttribute("LodgeFallbackTest", true)
end
local s = C.boot({
	profile = function(data)
		data.Cash = tonumber(preview.args.cash) or 1250
		data.RubbleByTier = { Gravel = tonumber(preview.args.rubble) or 14 } -- --set rubble=N
		data.TutorialStep = tonumber(preview.args.tut) or 1
		-- --set display=N puts N made-up pets on the player's own plot (plot 1)
		local n = tonumber(preview.args.display)
		if n and n > 0 then
			local specs = C.fakeSpecimens(n)
			data.InventoryGeodes = specs
			data.DisplayCapacity = 4
			data.DisplayAssignments = {}
			for _, g in ipairs(specs) do
				table.insert(data.DisplayAssignments, g.Id)
			end
		end
	end,
})
-- --set boards=seed: PREVIEW TEST DATA ONLY. Seeds the in-memory OrderedDataStores with made-up players (user ids
-- 1001..) and re-reads them through the real LeaderboardService, so the lodge boards can be judged with five rows.
-- Never shipped: the game reads the real stores (an empty board shows its honest empty state).
if preview.args.boards == "seed" then
	local DataStoreService = game:GetService("DataStoreService")
	local Boards = C.shared("Boards")
	local Config = C.shared("Config")
	for _, id in ipairs(Boards.Order) do
		local store = DataStoreService:GetOrderedDataStore(Config.Leaderboards.StorePrefix .. id)
		for i = 1, 7 do
			local base = ({ Wins = 40, Biggest = 90000, Collection = 120, Solo = 60, Tower = 40 })[id] or 1000
			store:SetAsync(tostring(1000 + i), math.max(1, math.floor(base * (1 - (i - 1) * 0.11))))
		end
	end
	local LB = C.server("LeaderboardService")
	if LB then
		C.try("refresh", LB.refreshAll)
	end
end
-- --set signtest=flip|cover|off: check_signs.py --selftest breaks the PET PARK arch sign on purpose (its SurfaceGui turned to
-- the back of the text part / a plank in front of it / the SurfaceGui disabled) to prove the rendered check catches it
local signtest = preview.args.signtest
if signtest then
	local title = workspace:FindFirstChild("CT_Rocks_Lobby"):FindFirstChild("CT_Park_Plaza"):FindFirstChild("ParkSign")
		:FindFirstChild("Face") :: BasePart
	local gui = title:FindFirstChild("Label") :: SurfaceGui
	if signtest == "flip" then
		gui.Face = Enum.NormalId.Front
	elseif signtest == "off" then
		gui.Enabled = false
	elseif signtest == "cover" then
		local plank = Instance.new("Part")
		plank.Anchored = true
		plank.Size = Vector3.new(title.Size.X, title.Size.Y, 0.2)
		plank.CFrame = title.CFrame * CFrame.new(0, 0, 0.4)
		plank.Parent = workspace
	end
end
C.settle(2)
-- --set newpets=N: PREVIEW ONLY. N made-up pets land in the Pet Book after the first profile, so the red "!" badge
-- on the My Pets tile shows (it counts pets hatched since the book was last opened).
local newPets = tonumber(preview.args.newpets)
if newPets and newPets > 0 then
	local State = preview.client("State")
	local prof = State.Profile
	if prof then
		local list = if type(prof.Inventory) == "table" then prof.Inventory else prof.InventoryGeodes
		if type(list) == "table" then
			for _, g in ipairs(C.fakeSpecimens(newPets)) do
				table.insert(list, g)
			end
			State.Changed:Fire("Profile")
			C.settle(0.5)
		else
			print("[FAIL] lobby: no pet list on the profile for newpets")
		end
	end
end
if tonumber(preview.args.display) then
	-- the profile edit above ran after the alcove was first drawn; draw it again
	local gallery = C.server("GalleryService")
	if gallery then
		gallery.render(s.me)
	end
end
-- --set hud=off hides every ScreenGui so the world can be judged on its own
if preview.args.hud == "off" then
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") then
			g.Enabled = false
		end
	end
end
-- --set eye=<name>: FIRST-PERSON player views (camera at the avatar's eye, Config.Camera.Fov, the local body
-- hidden like CameraMode does). { feet x, feet z, look x, look y, look z }. Positions are ordinary walking
-- spots, never overhead.
local EYE = {
	-- the dino-jungle pet park (ground y 0, spawn plaza at +Z, clearing with the nests at the centre, EGG SHOP at -Z;
	-- src/shared/ParkConfig.luau)
	spawn = { 0, 112, 0, 8, 60 },
	news = { 22, 110, 22, 6, 97 },
	boards = { 16, 0, 30, 8, 0 },
	nests = { 0, 2, 0, 8, -21 },
	upgradessign = { -34, 112, -48, 9, 112 },
	collectionsign = { 34, 112, 48, 9, 112 },
	seller = { -26, 116, -26, 6.5, 129 },
	eggshop = { 0, -88, 0, 7, -108 },
	hatch = { 21, -82, 21, 5, -100 },
	plot = { -22, 38, -22, 6, 50 },
	plotin = { -22, 56, -22, 2, 72 },
	likepost = { -16, 42, -12.6, 4, 52 },
	tower = { -78, 0, -95, 12, 0 },
}
local eye = preview.args.eye
if eye and EYE[eye] then
	local e = EYE[eye]
	local LB = C.server("LobbyBuilder")
	local fy = if LB and LB.groundAt then LB.groundAt(Vector3.new(e[1], 0, e[2])) else 0.5
	local feet = Vector3.new(e[1], fy, e[2])
	local at = Vector3.new(e[3], e[4], e[5])
	C.place(s.me, CFrame.lookAt(feet, Vector3.new(at.X, 0.5, at.Z)))
	C.settle(0.3)
	local head = s.me.Character:FindFirstChild("Head") :: BasePart
	for _, d in s.me.Character:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			d.Transparency = 1
		end
	end
	local cam = game:GetService("Workspace").CurrentCamera
	cam.CFrame = CFrame.lookAt(head.Position + Vector3.new(0, 0.15, 0), at)
	cam.FieldOfView = s.Config.Camera.Fov
	preview.advance(0.05)
	if preview.args.prompt == "on" then
		-- --set prompt=on: let the prompt arbiter (0.1 s heartbeat) pick the prompt in view, camera kept
		for _ = 1, 4 do
			preview.advance(0.1)
			cam.CFrame = CFrame.lookAt(head.Position + Vector3.new(0, 0.15, 0), at)
		end
	end
	return
end
-- --set view=spawn (default) | wide | overview | clearing | plot | plaza | tower | shop | plotclose | plotabove | towerclose | hatchclose
C.place(s.me, C.lobbySpawn())
local v = preview.args.view or "spawn"
print("PLAYER", game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position, C.lobbySpawn().Position)
-- views: { avatar x, avatar z, camera x, camera y, camera z, fov? } player-height views put the avatar
-- on the paving and the camera behind and above it like the default follow camera; "wide"/"overview"
-- are high views. --set hud=off hides the GUI.
local views = {
	wide = { 0, 100, 0, 70, 150 },
	overview = { 0, 0, 0, 180, 190, 60 },
	-- player-height follow views in the park
	clearing = { 0, 30, 0, 12, 52 },
	plot = { -22, 44, -22, 10, 32 },
	plaza = { 0, 104, 0, 12, 124 },
	tower = { -80, 0, -64, 10, 0 },
	shop = { 0, -88, 0, 10, -74 },
	spawn = nil,
}
-- free-camera close-ups (avatar stays at the spawn): { look x, look y, look z, cam x, cam y, cam z, fov }
local free = {
	plotclose = { -22, 2, 74, -22, 14, 52, 55 },
	plotabove = { -22, 0, 66, -8, 40, 66, 60 },
	towerclose = { -95, 8, 0, -70, 12, 0, 55 },
	hatchclose = { 21, 2, -97, 21, 12, -78, 55 },
}
local fv = free[v]
local vv = if fv then nil else views[v]
if fv then
	C.cameraAt(Vector3.new(fv[1], fv[2], fv[3]), Vector3.new(fv[4] - fv[1], fv[5] - fv[2], fv[6] - fv[3]), fv[7])
elseif vv then
	if v ~= "wide" and v ~= "overview" then
		local p0 = Vector3.new(vv[1], 0.5, vv[2])
		local away = Vector3.new(vv[1] - vv[3], 0, vv[2] - vv[5])
		C.place(s.me, CFrame.lookAt(p0, p0 + away))
	end
	local head = Vector3.new(vv[1], 3.5, vv[2])
	local cam = Vector3.new(vv[3], vv[4], vv[5])
	if v == "wide" or v == "overview" then
		head = Vector3.new(vv[1], 0, vv[2])
	end
	C.cameraAt(head, cam - head, vv[6])
else
	C.followCamera()
end
