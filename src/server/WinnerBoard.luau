--!strict
-- LAST WINNERS board in the lobby: the last few hunt winners in THIS server with the pet each one found. Memory
-- only (no DataStore, nothing saved, empty after a server restart); MatchService calls WinnerBoard.record when a
-- hunt's pet is awarded (never the practice round). Display only: it changes nothing about who wins.
--
-- Where it shows (no new props): when the map has a part named WinnersBoard (optional hook, anywhere in Workspace)
-- the rows are drawn on its front face. Otherwise a flat, see-through screen floats just above the WHAT'S NEW board
-- (MapNames.WhatsNewBoard in the hand-built lobby, or the fallback park's CT_Park_WhatsNew), facing the same way as
-- that board's text. Without either, nothing is drawn (the list is still kept).
-- With the owner's NoticeBoard mesh imported (ReplicatedStorage.WorldKit_LowPoly), that board stands beside the WHAT'S
-- NEW board instead of the floating screen and the rows go on its panel face (noticeBoard below).
-- Single-place mode only: in Teleport mode the hunts run in another server, so the lobby board stays empty.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapNames = require(Shared.MapNames)
local SignLayout = require(Shared.SignLayout)
local KitPlace = require(script.Parent.KitPlace)
local WorldKit = require(Shared.WorldKit)

local WinnerBoard = {}

local KEEP = 4
local HOOK = "WinnersBoard"
local FLOAT_W_MIN, FLOAT_W_MAX = 12, 16 -- the floating screen: as wide as the WHAT'S NEW board, within these
local FLOAT_ASPECT = 0.6 -- height / width
-- Layout on the face (fractions of its height): the title band, then KEEP rows. Text sizes are explicit and fitted
-- (shared/SignLayout, like every world sign): the old TextScaled rows were about half a stud tall on a 12-stud screen.
local TITLE_Y, TITLE_H = 0.03, 0.2
local ROWS_Y, ROW_H = 0.25, 0.18

type Row = { Name: string, Pet: string, Rarity: string }
local rows: { Row } = {}
local labels: { TextLabel } = {}
local face = { W = 0, H = 0, PPS = 40 }

local function clean(s: any, max: number): string
	local t = tostring(s or "?")
	t = string.gsub(t, "[%c<>]", "")
	if #t > max then
		t = string.sub(t, 1, max - 1) .. "\u{2026}"
	end
	return t
end

local function redraw()
	-- one text size for every row: the largest that lets the longest row fit the row box (SignLayout Placard)
	local em = math.huge
	local texts: { string } = {}
	for i = 1, #labels do
		local r = rows[i]
		local plain = if r then r.Name .. "  " .. r.Pet elseif i == 1 then "No winners yet: be the first!" else ""
		texts[i] = plain
		if plain ~= "" and face.W > 0 then
			em = math.min(em, SignLayout.fit(plain, face.W * 0.9, face.H * ROW_H, "Row").Em)
		end
	end
	local size = if em < math.huge then math.clamp(math.floor(em * face.PPS), 8, 100) else 24
	for i, l in labels do
		local r = rows[i]
		if r then
			local col: Color3 = (Config.RarityTextColors :: any)[r.Rarity] or Color3.new(1, 1, 1)
			l.Text = string.format('%s  <font color="#%s">%s</font>', r.Name, col:ToHex(), r.Pet)
		else
			l.Text = texts[i]
		end
		l.TextSize = size
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = SignLayout.outlinePx(size)
		end
	end
end

-- A hunt's pet was awarded: newest first, at most KEEP rows.
function WinnerBoard.record(winnerName: string, petName: string, rarity: string?)
	table.insert(rows, 1, { Name = clean(winnerName, 18), Pet = clean(petName, 22), Rarity = tostring(rarity or "Common") })
	while #rows > KEEP do
		table.remove(rows)
	end
	redraw()
end

-- The rows on a SurfaceGui (face of `part`): sky-blue panel, gold title, white rows with a black outline.
local function draw(part: BasePart, faceId: Enum.NormalId, see: boolean)
	local W, H = KitPlace.faceSize(part, faceId)
	local title = SignLayout.fit("LAST WINNERS", W * 0.92, H * TITLE_H, "Heading")
	face.W, face.H = W, H
	face.PPS = math.clamp(title.TextSize / title.Em, 8, 60) -- the title at its preset TextSize; rows share the density
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WinnersGui"
	gui.Face = faceId
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = face.PPS
	gui.LightInfluence = 0
	gui.Parent = part
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(46, 118, 206) -- sky blue like the lodge boards (the old near-black read as a slab)
	bg.BackgroundTransparency = if see then 0.15 else 0
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.06, 0)
	corner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 196, 36)
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, TITLE_Y)
	t.Size = UDim2.fromScale(0.92, TITLE_H)
	t.Font = Enum.Font.LuckiestGuy
	t.TextScaled = false
	t.TextSize = math.min(100, math.floor(title.Em * face.PPS))
	t.TextColor3 = Color3.fromRGB(255, 196, 36)
	t.Text = "LAST WINNERS"
	t.Parent = bg
	local ts = Instance.new("UIStroke")
	ts.Color = SignLayout.Outline.Stroke
	ts.Thickness = SignLayout.outlinePx(t.TextSize)
	ts.LineJoinMode = Enum.LineJoinMode.Round
	ts.Parent = t
	table.clear(labels)
	for i = 1, KEEP do
		local l = Instance.new("TextLabel")
		l.Name = "Row" .. i
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.05, ROWS_Y + (i - 1) * ROW_H)
		l.Size = UDim2.fromScale(0.9, ROW_H)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = false
		l.RichText = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(255, 255, 255)
		l.Parent = bg
		local s = Instance.new("UIStroke")
		s.Color = SignLayout.Outline.Stroke
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Parent = l
		table.insert(labels, l)
	end
	redraw()
end

local function asPart(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

-- The part whose SurfaceGui shows the WHAT'S NEW text (its face tells which way the board looks).
local function newsFace(anchor: Instance): (BasePart?, Enum.NormalId)
	for _, d in anchor:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Parent and d.Parent:IsA("BasePart") and d:FindFirstChildWhichIsA("TextLabel", true) then
			return d.Parent :: BasePart, d.Face
		end
	end
	if anchor:IsA("SurfaceGui") then
		local p = anchor.Parent
		if p and p:IsA("BasePart") then
			return p, anchor.Face
		end
	end
	return asPart(anchor), Enum.NormalId.Front
end

local FACE_DIR: { [Enum.NormalId]: Vector3 } = {
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
}

-- The owner's NoticeBoard mesh (Shared.WorldKit, ReplicatedStorage.WorldKit_LowPoly), when imported: it stands on
-- the ground beside the WHAT'S NEW board (to its right as you face the news text, SIDE_GAP studs clear of it), facing
-- the same way, at its own size in studs. The rows go on an invisible panel part laid on the board's panel face.
-- ASSUMPTION (not checked in Studio): the panel is PANEL_W x PANEL_H studs and centred on the mesh's front (-Z) face,
-- i.e. its centre is the bounding-box centre moved PANEL_OFFSET (x right, y up, studs) and it sits PANEL_DEPTH studs
-- behind the box's front plane (0 = flush with the frontmost point). Adjust these constants if the text misses.
local PANEL_W, PANEL_H = 7.4, 3.3
local PANEL_OFFSET = Vector2.new(0, 0)
local PANEL_DEPTH = 0
local SIDE_GAP = 2
local function noticeBoard(box: Instance, facePart: BasePart, face: Enum.NormalId, out: Vector3, lobbyRoot: Instance?): BasePart?
	local mesh = if WorldKit.has("NoticeBoard") then WorldKit.clone("NoticeBoard", "CT_WinnersNoticeBoard") else nil
	if not mesh then
		return nil
	end
	-- the news board's footprint: its centre, floor (bottom of the whole board) and half width along its face
	local centre, size = facePart.CFrame, facePart.Size
	if box:IsA("Model") then
		centre, size = box:GetBoundingBox()
	elseif box.Parent and box.Parent:IsA("Model") and box.Parent ~= Workspace then
		centre, size = (box.Parent :: Model):GetBoundingBox()
	end
	local floorY = centre.Position.Y - size.Y / 2
	local right = out:Cross(Vector3.yAxis) -- the viewer's right when facing the news text (looking along -out)
	local halfNews = 0.5 * math.max(KitPlace.faceSize(facePart, face), 0)
	if box:IsA("Model") or (box.Parent and box.Parent:IsA("Model") and box.Parent ~= Workspace) then
		-- the bounding box is axis-aligned to the model pivot: its extent along `right`
		local r = centre:VectorToObjectSpace(right)
		halfNews = math.max(halfNews, 0.5 * (math.abs(r.X) * size.X + math.abs(r.Z) * size.Z))
	end
	local at = Vector3.new(facePart.Position.X, floorY, facePart.Position.Z) + right * (halfNews + SIDE_GAP + mesh.Size.X / 2)
	WorldKit.onFloor(mesh, CFrame.lookAt(at, at + out)) -- front (-Z) looks the same way as the news text
	mesh.CanCollide = false -- like the floating screen it replaces
	if mesh:IsA("MeshPart") and mesh.TextureID == "" then
		mesh.Color = Color3.fromRGB(176, 124, 78) -- untextured import: warm wood, never a black slab
	end
	mesh.CastShadow = true
	mesh:SetAttribute("CameraIgnore", true)
	mesh.Parent = lobbyRoot or Workspace
	local panel = Instance.new("Part")
	panel.Name = "CT_WinnersPanel"
	panel.Size = Vector3.new(PANEL_W, PANEL_H, 0.05)
	panel.CFrame = mesh.CFrame * CFrame.new(PANEL_OFFSET.X, PANEL_OFFSET.Y, -mesh.Size.Z / 2 + PANEL_DEPTH - 0.04)
	panel.Transparency = 1
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanQuery = false
	panel.CanTouch = false
	panel.CastShadow = false
	panel:SetAttribute("CameraIgnore", true)
	panel.Parent = mesh
	return panel
end

function WinnerBoard.start(lobbyRoot: Instance?)
	task.spawn(function()
		task.wait(3) -- the lobby (procedural park or the owner's map hooks) is built first
		local hook = Workspace:FindFirstChild(HOOK, true)
		local hookPart = asPart(hook)
		if hookPart then
			draw(hookPart, Enum.NormalId.Front, false)
			return
		end
		local anchor: Instance? = Workspace:FindFirstChild(MapNames.WhatsNewBoard, true)
		if not anchor then
			anchor = Workspace:FindFirstChild("CT_Park_WhatsNew", true)
		end
		if not anchor and lobbyRoot then
			anchor = lobbyRoot:FindFirstChild("CT_Park_WhatsNew", true)
		end
		if not anchor then
			warn("[WinnerBoard] no WinnersBoard part and no WHAT'S NEW board: the winners board is not drawn")
			return
		end
		local facePart, face = newsFace(anchor :: Instance)
		if not facePart then
			return
		end
		-- top of the whole board (posts and heading sign included)
		local top = facePart.Position.Y + facePart.Size.Y / 2
		local box = anchor :: Instance
		if box:IsA("Model") then
			local cf, size = box:GetBoundingBox()
			top = cf.Position.Y + size.Y / 2
		elseif box.Parent and box.Parent:IsA("Model") and box.Parent ~= Workspace then
			local cf, size = (box.Parent :: Model):GetBoundingBox()
			top = math.max(top, cf.Position.Y + size.Y / 2)
		end
		local dirLocal = FACE_DIR[face] or Vector3.new(0, 0, -1)
		local out = facePart.CFrame:VectorToWorldSpace(dirLocal)
		out = Vector3.new(out.X, 0, out.Z)
		out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, -1)
		local panel = noticeBoard(box, facePart, face, out, lobbyRoot)
		if panel then
			draw(panel, Enum.NormalId.Front, false)
			return
		end
		local floatW = math.clamp(KitPlace.faceSize(facePart, face), FLOAT_W_MIN, FLOAT_W_MAX)
		local floatH = floatW * FLOAT_ASPECT
		local centre = Vector3.new(facePart.Position.X, top + 1 + floatH / 2, facePart.Position.Z)
		local screen = Instance.new("Part")
		screen.Name = "CT_WinnersScreen"
		screen.Size = Vector3.new(floatW, floatH, 0.05)
		-- Front (-Z) of the screen looks the same way as the news text
		screen.CFrame = CFrame.lookAt(centre, centre + out)
		screen.Transparency = 1
		screen.Anchored = true
		screen.CanCollide = false
		screen.CanQuery = false
		screen.CanTouch = false
		screen.CastShadow = false
		screen:SetAttribute("CameraIgnore", true)
		screen.Parent = lobbyRoot or Workspace
		draw(screen, Enum.NormalId.Front, true)
	end)
end

-- Test / preview hook: the rows as plain text.
function WinnerBoard.rows(): { Row }
	return table.clone(rows)
end

return WinnerBoard
