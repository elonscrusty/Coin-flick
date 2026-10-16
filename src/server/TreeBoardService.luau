--!strict
-- Leaderboard tree (owner pick 2026-10-14; rules in shared/TreeBoard). The top players by best pet POWER (Boards
-- "Power", read by LeaderboardService from its OrderedDataStore) stand on the branches of a giant tree in the lobby
-- centre, each shown by their strongest pet as a live model (PetDisplay animates server-built pets) with a glowing
-- "#1 Name / POWER 1,234" sign.
--
-- The tree: a "LeaderboardTree" model in the lobby map; else one in ServerStorage is cloned onto the part
-- "LeaderboardTreeSpot"; else, with only the spot, a simple chunky stand-in tree is built there (REPLACE with the
-- Blender tree). Branch points: Attachments (or parts) named Branch1..N anywhere in the tree, Branch1 = the top spot.
-- A part "BattlePad" in the tree (or a round pad made in front of it) gets the attribute PvpPad, so PvpService opens
-- the BATTLE card when someone steps on it. An Attachment (or part) "DragonPerch" in the tree is where the Void Dragon
-- statue stands (server/VoidStatue.perch; optional attribute Height = the dragon's height in studs).
--
-- Cards: each player's best pet look + power is saved (TreeBoard.card) in the DataStore TreeBoard.Config.Store when
-- it changes, at most once per CardWriteSeconds, so other servers can draw offline players' pets. Everything that
-- touches a DataStore is pcall'd: a failure draws the branch with its sign and no pet, never an error.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local TreeBoard = require(Shared.TreeBoard)
local GeodeModel = require(Shared.GeodeModel)
local PetModel = require(Shared.PetModel)
local Profiles = require(script.Parent.Profiles)
local Leaderboards = require(script.Parent.LeaderboardService)
local VoidStatue = require(script.Parent.VoidStatue)

local TreeBoardService = {}

local C = TreeBoard.Config
local SUFFIX = if RunService:IsStudio() then "_Studio" else ""

local tree: Instance? = nil
local branches: { CFrame } = {}
local display: Folder? = nil
local store: any = nil
local cards: { [number]: { Card: TreeBoard.Card?, At: number } } = {} -- userId -> card (nil = none) + read time
local written: { [number]: TreeBoard.Card } = {}
local lastWrite: { [number]: number } = {}
local lastDraw = -math.huge
local drawQueued = false
local loadCard = function(userId: number): any
	return store and store:GetAsync(tostring(userId))
end
local saveCard = function(userId: number, card: TreeBoard.Card)
	if store then
		store:SetAsync(tostring(userId), card)
	end
end

-- Tests only: replace the card store reads / writes.
function TreeBoardService.setStore(load: (number) -> any, save: (number, TreeBoard.Card) -> ())
	loadCard, saveCard = load, save
	table.clear(cards)
	table.clear(written)
	table.clear(lastWrite)
end

-- Tree ---------------------------------------------------------------------------------------------------------------

local function branchCFrames(t: Instance): { CFrame }
	local list: { { N: number, CF: CFrame } } = {}
	for _, d in t:GetDescendants() do
		local n = tonumber(string.match(d.Name, "^Branch(%d+)$"))
		if n then
			if d:IsA("Attachment") then
				table.insert(list, { N = n, CF = d.WorldCFrame })
			elseif d:IsA("BasePart") then
				table.insert(list, { N = n, CF = d.CFrame * CFrame.new(0, d.Size.Y / 2, 0) })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.N < b.N
	end)
	local out = {}
	for _, e in list do
		table.insert(out, e.CF)
	end
	return out
end

-- A chunky stand-in tree (REPLACE with the Blender LeaderboardTree): trunk, leaf blobs and Branch1..N attachments in
-- a rising spiral, the top one above the crown.
local function standInTree(spot: BasePart): Model
	local m = Instance.new("Model")
	m.Name = C.Model
	local base = spot.CFrame * CFrame.new(0, spot.Size.Y / 2, 0)
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Shape = shape or Enum.PartType.Block
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = m
		return p
	end
	local trunk = part("Trunk", Vector3.new(40, 9, 9), base * CFrame.new(0, 20, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 82, 52), Enum.PartType.Cylinder)
	m.PrimaryPart = trunk
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		part("Leaves", Vector3.new(16, 16, 16), base * CFrame.new(math.cos(a) * 9, 40 + (i % 2) * 4, math.sin(a) * 9), Color3.fromRGB(92, 176, 82), Enum.PartType.Ball)
	end
	part("Leaves", Vector3.new(20, 20, 20), base * CFrame.new(0, 48, 0), Color3.fromRGB(104, 190, 90), Enum.PartType.Ball)
	for k = 1, C.Branches do
		local at = Instance.new("Attachment")
		at.Name = "Branch" .. k
		at.Parent = trunk -- parent first: WorldCFrame on a loose Attachment is kept as a local offset
		if k == 1 then
			at.WorldCFrame = base * CFrame.new(0, 38, -23) -- out in front, under the crown (the Void Dragon stands on top)
		else
			local a = (k - 2) / (C.Branches - 1) * math.pi * 2
			local h = 46 - (k - 2) * 3.6
			at.WorldCFrame = base * CFrame.new(math.cos(a) * 21, h, math.sin(a) * 21) * CFrame.Angles(0, -a + math.pi / 2, 0)
		end
		local limb = part("Limb", Vector3.new(1.6, 1.6, 1.6), at.WorldCFrame * CFrame.new(0, -0.8, 0), Color3.fromRGB(110, 76, 48))
		limb.Size = Vector3.new(4, 1.4, 4)
	end
	local perch = Instance.new("Attachment")
	perch.Name = "DragonPerch"
	perch.Parent = trunk
	perch.WorldCFrame = base * CFrame.new(0, 57.5, 0)
	return m
end

-- Where the Void Dragon stands on the tree, and its height (attribute Height), or nil when the tree has no perch.
local function perchOf(t: Instance): (CFrame?, number?)
	local p = t:FindFirstChild("DragonPerch", true)
	local h = p and p:GetAttribute("Height")
	local height = if type(h) == "number" then h else nil
	if p and p:IsA("Attachment") then
		return p.WorldCFrame, height
	elseif p and p:IsA("BasePart") then
		p.Transparency = 1
		p.CanCollide = false
		return p.CFrame * CFrame.new(0, p.Size.Y / 2, 0), height
	end
	return nil, nil
end

local function findTree(roots: { Instance }): Instance?
	for _, r in roots do
		local t = r:FindFirstChild(C.Model, true)
		if t then
			return t
		end
	end
	local spot: BasePart? = nil
	for _, r in roots do
		local s = r:FindFirstChild(C.Spot, true)
		if s and s:IsA("BasePart") then
			spot = s
			break
		end
	end
	if not spot then
		return nil
	end
	local stored = ServerStorage:FindFirstChild(C.Model, true)
	local t: Model
	if stored and stored:IsA("Model") then
		t = stored:Clone()
		local _, size = t:GetBoundingBox()
		t:PivotTo(spot.CFrame * CFrame.new(0, spot.Size.Y / 2 + size.Y / 2, 0))
	else
		t = standInTree(spot)
	end
	t.Parent = spot.Parent
	return t
end

local function ensurePad(t: Instance)
	local pad = t:FindFirstChild(C.Pad, true)
	if not (pad and pad:IsA("BasePart")) then
		local cf: CFrame, size: Vector3
		if t:IsA("Model") then
			cf, size = t:GetBoundingBox()
		elseif t:IsA("BasePart") then
			cf, size = t.CFrame, t.Size
		else
			return
		end
		local p = Instance.new("Part")
		p.Name = C.Pad
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.6, 10, 10)
		p.Color = Color3.fromRGB(230, 70, 60)
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		local bottom = cf.Position - Vector3.new(0, size.Y / 2, 0)
		local front = cf.LookVector * (math.max(size.X, size.Z) / 2 + 8)
		p.CFrame = CFrame.new(bottom + front + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 44)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		gui.MaxDistance = 80
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = "BATTLE"
		l.TextColor3 = Color3.fromRGB(255, 236, 200)
		l.TextStrokeTransparency = 0
		l.Parent = gui
		gui.Parent = p
		p.Parent = t
		pad = p
	end
	(pad :: BasePart):SetAttribute("PvpPad", true)
end

-- Cards ---------------------------------------------------------------------------------------------------------------

-- Saves the player's best-pet card when it changed (and not more often than CardWriteSeconds). Returns true if saved.
function TreeBoardService.noteChange(player: Player): boolean
	local data = Profiles.get(player)
	if not data then
		return false
	end
	local pet, power = TreeBoard.bestPet(data)
	local card = TreeBoard.card(pet, power)
	local uid = player.UserId
	if card then
		cards[uid] = { Card = card, At = os.clock() } -- live players draw from their own profile
	end
	if not TreeBoard.cardChanged(written[uid], card) then
		return false
	end
	local now = os.clock()
	if lastWrite[uid] and now - lastWrite[uid] < C.CardWriteSeconds then
		return false
	end
	lastWrite[uid] = now
	local ok: boolean, err: any = pcall(function()
		saveCard(uid, card :: TreeBoard.Card)
	end)
	if ok then
		written[uid] = card :: TreeBoard.Card
	else
		warn("[TreeBoard] card not saved:", err)
	end
	return ok
end

local function cardFor(uid: number): TreeBoard.Card?
	local c = cards[uid]
	if c and (os.clock() - c.At < C.CardCacheSeconds or Players:GetPlayerByUserId(uid)) then
		return c.Card
	end
	local ok, raw = pcall(loadCard, uid)
	local card = if ok and type(raw) == "table" then TreeBoard.card(raw, raw.Power) else nil
	if ok then
		cards[uid] = { Card = card, At = os.clock() }
	elseif c then
		return c.Card -- keep the last good one
	end
	return card
end

-- Drawing ----------------------------------------------------------------------------------------------------------------

local function sign(parent: Instance, rank: number, name: string, power: number)
	local top, bottom = TreeBoard.signLines(rank, name, power)
	local gui = Instance.new("BillboardGui")
	gui.Name = "TreeSign"
	-- Sized in studs (scale), so far signs shrink and do not pile into one block of text.
	gui.Size = if rank == 1 then UDim2.fromScale(11, 3.2) else UDim2.fromScale(8, 2.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, TreeBoard.petHeight(rank) + 1.5, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local col = TreeBoard.signColor(rank)
	local function line(text: string, y: number, h: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, y)
		l.Size = UDim2.fromScale(1, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = col
		l.TextStrokeTransparency = 0
		l.TextStrokeColor3 = Color3.fromRGB(30, 24, 18)
		l.Parent = gui
	end
	line(top, 0, 0.56)
	line(bottom, 0.56, 0.44)
	gui.Parent = parent
end

-- Redraws the tree from the "Power" board rows. Returns the plan drawn (tests).
function TreeBoardService.draw(): { any }
	local t = tree
	local f = display
	if not t or not f then
		return {}
	end
	local state = Leaderboards.get("Power")
	local plan = TreeBoard.plan(state.Rows, #branches)
	if #plan > 0 then
		lastDraw = os.clock() -- an empty board (still loading) does not hold back the first real draw
	end
	local fresh = Instance.new("Folder")
	fresh.Name = "TreePets"
	for _, e in plan do
		local at = branches[e.Branch]
		local holder = Instance.new("Part")
		holder.Name = "Branch" .. e.Branch .. "Spot"
		holder.Size = Vector3.new(1, 1, 1)
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide, holder.CanQuery, holder.CanTouch = false, false, false
		holder.CFrame = at
		holder:SetAttribute("UserId", e.UserId)
		holder:SetAttribute("Rank", e.Rank)
		holder.Parent = fresh
		sign(holder, e.Rank, e.Name, e.Power)
		local card = cardFor(e.UserId)
		if card then
			local ok, m = pcall(function()
				local model = GeodeModel.build(card :: any, { Lod = true, NoLight = true })
				PetModel.fitHeight(model, TreeBoard.petHeight(e.Rank))
				return model
			end)
			if ok and m then
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
					end
				end
				local _, size = m:GetBoundingBox()
				m:PivotTo(at * CFrame.new(0, size.Y / 2, 0))
				m.Name = "TreePet"
				local glow = Instance.new("PointLight")
				glow.Color = TreeBoard.signColor(e.Rank)
				glow.Range = if e.Rank == 1 then 16 else 10
				glow.Brightness = if e.Rank == 1 then 2 else 1.2
				glow.Parent = holder
				CollectionService:AddTag(m, "PetSpin") -- turns slowly on the spot (PetDisplay; cosmetic)
				m.Parent = holder
			end
		end
	end
	local old = f:FindFirstChild("TreePets")
	fresh.Parent = f
	if old then
		old:Destroy()
	end
	return plan
end

local function queueDraw()
	if drawQueued then
		return
	end
	drawQueued = true
	task.delay(math.max(0, C.RefreshSeconds - (os.clock() - lastDraw)), function()
		drawQueued = false
		pcall(TreeBoardService.draw)
	end)
end

-- Test hooks: the tree and its branch points.
function TreeBoardService.tree(): (Instance?, { CFrame })
	return tree, branches
end

-- `roots`: the lobby map(s) (never the arenas). No tree and no spot: nothing is built (one warn).
function TreeBoardService.start(roots: { Instance })
	if not C.Enabled then
		return -- no tree in the lobby by design (TreeBoard.Config.Enabled), so no warning either
	end
	pcall(function()
		store = DataStoreService:GetDataStore(C.Store .. SUFFIX)
	end)
	tree = findTree(roots)
	local t = tree
	if not t then
		warn("[TreeBoard] no LeaderboardTree or LeaderboardTreeSpot in the lobby; the leaderboard tree is skipped")
		return
	end
	branches = branchCFrames(t)
	ensurePad(t)
	local perch, perchHeight = perchOf(t)
	if perch then
		local ok, err = pcall(VoidStatue.perch, roots[1], perch, perchHeight)
		if not ok then
			warn("[TreeBoard] Void Dragon perch failed: " .. tostring(err))
		end
	end
	local f = Instance.new("Folder")
	f.Name = "TreeBoardDisplay"
	f.Parent = t
	display = f
	Profiles.onChanged(function(player)
		task.defer(TreeBoardService.noteChange, player)
	end)
	Profiles.onLoaded(function(player)
		task.defer(TreeBoardService.noteChange, player)
	end)
	Leaderboards.onUpdated(function(board: string)
		if board == "Power" then
			queueDraw()
		end
	end)
	task.defer(function()
		pcall(TreeBoardService.draw)
	end)
end

return TreeBoardService
