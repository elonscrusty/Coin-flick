-- ftplobby: a tiny stand-in shaped like the owner's hand-built Workspace.FTP_Lobby (plain parts, no attributes or
-- prompts; ground top y = 3, street layout: spawn and pads at +Z, shop / hatch / tower at -Z), placed BEFORE the server starts. Checks that neither the
-- procedural park nor the old lodge / code spawn is built and that every hook is adopted: queue pads + countdown
-- signs (front and back), both leaderboards as text, plots (floor, 3 dome bases, sign, LIKE), egg shop prompt (enabled
-- by RobuxService), hatch stand + HatchPoint, tower portal, secret egg, spawn. One FTPLOBBY PASS / FAIL line per check.
local C = lib("ctr")
local MapNames = preview.shared("MapNames")

local Y = 3 -- ground top
local map = Instance.new("Model")
map.Name = "FTP_Lobby"
local function group(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or map
	return m
end
local function block(name: string, size: Vector3, cf: CFrame, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Parent = parent or map
	return p
end
local function textGui(part: BasePart, face: Enum.NormalId, text: string): TextLabel
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.Parent = part
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Text = text
	t.Parent = g
	return t
end
block("Ground", Vector3.new(400, 2, 400), CFrame.new(0, Y - 1, 0))
group("Jungle")
local sp = Instance.new("SpawnLocation")
sp.Name = "LobbySpawn"
sp.Size = Vector3.new(6, 1, 6)
sp.CFrame = CFrame.new(0, Y - 0.15, 72)
sp.Anchored = true
sp.Parent = map

local pads = group("QueuePads")
for n = 1, 4 do
	local m = group(MapNames.queuePad(n), pads)
	local pos = Vector3.new(({ -27, -9, 9, 27 })[n], Y, 48)
	local pad = block("Pad", Vector3.new(8, 0.4, 8), CFrame.new(pos + Vector3.new(0, 0.2, 0)), m)
	m.PrimaryPart = pad
	local cd = block("Countdown", Vector3.new(4, 2, 0.3), CFrame.new(pos + Vector3.new(0, 5, -5)), m)
	textGui(cd, Enum.NormalId.Front, "")
	textGui(cd, Enum.NormalId.Back, "")
end

local boards = group("Leaderboards")
for i, name in { "RarestPetBoard", "TowerFloorBoard" } do
	local m = group(name, boards)
	local b = block("Board", Vector3.new(10, 12, 1), CFrame.new(if i == 1 then -44 else 44, Y + 7, 58), m)
	textGui(b, Enum.NormalId.Back, "")
end

local plots = group("Plots")
for i = 1, 12 do
	local m = group(MapNames.plot(i), plots)
	local side = if i <= 6 then -1 else 1
	local x = side * 49
	local z = ({ 22, -6, -34, -62, -90, -118 })[(i - 1) % 6 + 1]
	local floor = block("Floor", Vector3.new(30, 1, 30), CFrame.new(x, Y - 0.5, z), m)
	m.PrimaryPart = floor
	block("Hut", Vector3.new(8, 8, 8), CFrame.new(x + side * 9, Y + 4, z + 8), m)
	block("Dome1Base", Vector3.new(6, 1, 6), CFrame.new(x + side * 4, Y + 0.5, z - 4), m)
	local d = block("Dome1", Vector3.new(8, 8, 8), CFrame.new(x + side * 4, Y + 1, z - 4), m)
	d.Transparency = 0.6
	d.CanCollide = false
	block("Stand1", Vector3.new(3, 2, 3), CFrame.new(x - side * 4, Y + 1, z - 9), m)
	block("Stand2", Vector3.new(3, 2, 3), CFrame.new(x - side * 4, Y + 1, z + 1), m)
	-- the sign at the gate, on the street side (x = 0)
	local sign = block("PlotSign", Vector3.new(0.4, 2, 8), CFrame.new(x - side * 15, Y + 6, z), m)
	textGui(sign, Enum.NormalId.Front, "")
end

local buildings = group("Buildings")
local shop = group("EggShop", buildings)
block("Hut", Vector3.new(16, 8, 10), CFrame.new(0, Y + 4, -172), shop)
local eggs = group("DisplayEggs", shop)
block("Egg1_Common", Vector3.new(1, 1.4, 1), CFrame.new(-3, Y + 9, -166), eggs)
block("Sign", Vector3.new(8, 2, 0.4), CFrame.new(0, Y + 9, -166), shop)
local hatch = group("HatchStand", buildings)
block("Base", Vector3.new(10, 1, 10), CFrame.new(-24, Y + 0.5, -154), hatch)
block("Top", Vector3.new(5, 1, 5), CFrame.new(-24, Y + 1.5, -154), hatch)
block("Sign", Vector3.new(6, 2, 0.4), CFrame.new(-24, Y + 6, -160), hatch)
local tower = group("TowerEntrance", buildings)
block("Arch", Vector3.new(12, 14, 2), CFrame.new(37, Y + 7, -168), tower)
block("Sign", Vector3.new(8, 2, 0.4), CFrame.new(37, Y + 12, -166), tower)
-- an owner-lettered shop sign (TextScaled, as Studio leaves it) and a WHAT'S NEW board with its own label
local book = group("BookShop", buildings)
local bookLabel = textGui(block("Sign", Vector3.new(10, 2.4, 0.4), CFrame.new(-60, Y + 9, -166), book), Enum.NormalId.Front, "PET BOOK")
bookLabel.TextScaled = true
local newsLabel = textGui(block("WhatsNewBoard", Vector3.new(10, 7, 0.5), CFrame.new(20, Y + 5, 66)), Enum.NormalId.Back, "")
block("SecretEgg", Vector3.new(1, 1.5, 1), CFrame.new(98, Y + 0.75, -196))
local wf = group("Waterfall")
local flow = block("Flow", Vector3.new(6, 20, 1), CFrame.new(-90, Y + 10, -60), wf)
local lanterns = group("Lanterns")
block("Lantern", Vector3.new(1, 1, 1), CFrame.new(10, Y + 6, 60), lanterns)
map.Parent = workspace

local s = C.boot({ profile = function(data)
	data.TutorialStep = 1
	data.Onboard.Skipped = true
end })
C.settle(2)

local function check(name: string, ok: boolean)
	print((if ok then "FTPLOBBY PASS " else "FTPLOBBY FAIL ") .. name)
end
check("no CT_Rocks_Lobby (no procedural park, no old lodge)", workspace:FindFirstChild("CT_Rocks_Lobby") == nil and workspace:FindFirstChild("CT_Park_Jungle", true) == nil)
check("owner's parts not moved (Flow, Egg1_Common)", flow.Position == Vector3.new(-90, Y + 10, -60) and eggs.Egg1_Common.Position == Vector3.new(-3, Y + 9, -166) and flow:GetAttribute("CameraIgnore") == nil)
check("no code spawn pad", workspace:FindFirstChild("CT_Rocks_LobbySpawn", true) == nil)
local hrp = s.me.Character and s.me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
check("player spawned at LobbySpawn (" .. tostring(hrp and hrp.Position) .. ")", hrp ~= nil and (hrp.Position - Vector3.new(0, Y, 72)).Magnitude < 8)
local alc = s.me:GetAttribute("Alcove")
check("player got a hand-built plot (Alcove = " .. tostring(alc) .. ")", type(alc) == "number")
local plot = plots:FindFirstChild(MapNames.plot(tonumber(alc) or 1))
local disp = plot and plot:FindFirstChild("Display")
local adds = 0
if disp then
	for _, d in disp:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "PlacePrompt" then
			adds += 1
		end
	end
end
check("Dome1Base + Stand1 + Stand2 offer + ADD PET (" .. adds .. ")", adds == 3)
local signText = plot and plot:FindFirstChild("PlotSign") and plot.PlotSign:FindFirstChild("Text", true)
check("owner name on PlotSign (" .. tostring(signText and signText.Text) .. ")", signText ~= nil and string.find(signText.Text, "Park") ~= nil)
-- plot 1 is on the left (x -49): its dome plaque sits on the street side (+X) of Dome1Base, i.e. the plot faces the street
local base1 = plot and plot:FindFirstChild("Dome1Base")
local nearest, nd = nil, math.huge
for _, d in (if disp then disp:GetChildren() else {}) do
	if d:IsA("BasePart") and d.Name == "Label" and base1 and (d.Position - base1.Position).Magnitude < nd then
		nearest, nd = d, (d.Position - base1.Position).Magnitude
	end
end
check("plot faces the street (dome plaque toward x = 0)", nearest ~= nil and base1 ~= nil and nearest.Position.X > base1.Position.X + 1)
local likePrompt = plot and plot:FindFirstChild("LikePrompt", true)
check("LIKE prompt with LikePlot", likePrompt ~= nil and likePrompt:GetAttribute("LikePlot") == alc)
local pad3 = pads:FindFirstChild("QueuePad3") and pads.QueuePad3:FindFirstChild("Pad")
check("queue pad touch part HuntPortal + PadIndex", pad3 ~= nil and pad3:GetAttribute("HuntPortal") == true and pad3:GetAttribute("PadIndex") == 3)
local front, back = 0, 0
for _, d in pads:GetDescendants() do
	if d:IsA("TextLabel") and d.Name == "Text" and d.Text ~= "" then
		if (d.Parent :: SurfaceGui).Face == Enum.NormalId.Front then
			front += 1
		else
			back += 1
		end
	end
end
check("queue text on every countdown sign, front and back (" .. front .. "/" .. back .. ")", front == 4 and back == 4)
local rb = boards:FindFirstChild("RarestPetBoard") and boards.RarestPetBoard:FindFirstChild("Text", true)
local tb = boards:FindFirstChild("TowerFloorBoard") and boards.TowerFloorBoard:FindFirstChild("Text", true)
check("RAREST PET board text (" .. tostring(rb and rb.Text) .. ")", rb ~= nil and string.find(rb.Text, "RAREST PET") ~= nil)
check("HIGHEST FLOOR board text", tb ~= nil and string.find(tb.Text, "HIGHEST FLOOR") ~= nil)
local function fitted(l: TextLabel?): boolean
	local st = l and l:FindFirstChildOfClass("UIStroke")
	return l ~= nil and not l.TextScaled and l.TextSize >= 8 and l.TextColor3.R > 0.97 and st ~= nil
end
check("leaderboard text fitted, white, outlined (" .. tostring(rb and rb.TextSize) .. " px)", fitted(rb) and fitted(tb))
check("WHAT'S NEW text fitted, white, outlined (" .. newsLabel.TextSize .. " px)", fitted(newsLabel) and string.find(newsLabel.Text, "WHAT'S NEW", 1, true) ~= nil)
check("book shop sign refitted, words kept (" .. bookLabel.TextSize .. " px)", fitted(bookLabel) and bookLabel.Text == "PET BOOK")
C.settle(2) -- WinnerBoard waits 3 s for the lobby
local winners = workspace:FindFirstChild("CT_WinnersScreen", true)
local row1 = winners and winners:FindFirstChild("Row1", true)
check("LAST WINNERS screen with fitted rows (" .. tostring(row1 and (row1 :: TextLabel).TextSize) .. " px)", row1 ~= nil and not (row1 :: TextLabel).TextScaled)
local shopPrompt = shop:FindFirstChildWhichIsA("ProximityPrompt", true)
-- (Enabled is not checked: in the preview the client prompt arbiter shares these instances and turns out-of-range prompts off)
check("egg shop prompt hooked by the Robux shop", shopPrompt ~= nil and shop:GetAttribute("RobuxShopHooked") == true and shopPrompt:GetAttribute("Panel") == "RobuxShop")
local top = hatch:FindFirstChild("Top")
check("hatch stand top: HatchStand + HatchPoint", top ~= nil and top:GetAttribute("HatchStand") == true and top:FindFirstChild("HatchPoint") ~= nil)
local portal = tower:FindFirstChild("TowerPortal", true)
check("tower portal part", portal ~= nil and portal:GetAttribute("TowerPortal") == true)
local egg = map:FindFirstChild("SecretEgg")
local take = egg and egg:FindFirstChildWhichIsA("ProximityPrompt")
check("secret egg attribute + Take prompt", egg ~= nil and egg:GetAttribute("SecretEgg") == true and take ~= nil and take.ActionText == "Take")
C.followCamera()
