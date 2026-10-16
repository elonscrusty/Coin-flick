--!strict
-- Park plots (dino-jungle pet park, owner picks 2026-10-10/11): each connected player gets one of the 12 fenced plots
-- (ParkConfig.Plot.Count = the lobby's population) for the session; it frees on leave. The owner's name goes on the
-- sign over the gate. The pets they chose to display (saved DisplayAssignments, in their order, up to their capacity
-- Profiles.displaySlots) are shown on the plot (ParkConfig.arrange):
--   * display slots 1-3 go in the plot's 3 glass domes (slot 1 = the big middle dome); the player picks them with
--     the display slot chooser (CollectionAction, Collection panel); an empty dome says "+ ADD PET" and its prompt
--     opens the Collection panel;
--   * pets placed beyond the 3 domes stand still in the yard on fixed spots (ParkConfig.yardSpots), playing their idle
--     on each client (PetDisplay). No pet walks around loose (owner, 2026-10-14); old saved RoamPets are ignored.
-- Every shown pet carries an "Inspect" prompt (attributes InspectOwner / InspectId) that opens the read-only
-- InspectPanel through the "Inspect" event. Visitors can look; nothing here lets anyone change another display.
-- LIKE: every plot has a LIKE post (prompt attribute LikePlot). One like per visitor per plot owner per UTC day,
-- saved in both profiles (shared/Hangout.like); the plot with the most likes TODAY wears a big floating crown and a
-- gold glow (owner pick 2026-10-14, lobby hangout idea 1).
-- Public API unchanged: Gallery.start(lobbyInfo) (lobbyInfo.Alcoves = the plots), Gallery.render(player); the player
-- attribute `Alcove` (and `Plot`) = the plot index.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeGen = require(Shared.GeodeGen)
local GeodeModel = require(Shared.GeodeModel)
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)
local ParkConfig = require(Shared.ParkConfig)
local Hangout = require(Shared.Hangout)
local Profiles = require(script.Parent.Profiles)
local KitPlace = require(script.Parent.KitPlace)
local ParkBuilder = require(script.Parent.ParkBuilder)

local Gallery = {}


local plots: { any } = {}
local owner: { [number]: Player } = {} -- plot index -> player
local plotOf: { [Player]: number } = {}

local PLAQUE_BG = Color3.fromRGB(110, 74, 44) -- warm wood (the near-black plaque read as a black slab from the path)

-- Dome plaques are read from both sides of the dome: copy the text face onto the front too.
local function bothFaces(tag: BasePart)
	local g = tag:FindFirstChild("Label")
	if g and g:IsA("SurfaceGui") and not tag:FindFirstChild("LabelFront") then
		local c = g:Clone()
		c.Name = "LabelFront"
		c.Face = Enum.NormalId.Front
		c.Parent = tag
	end
end

local likes = ParkConfig.newLikes()
-- The crown's working table (ParkConfig.likeLeader): its counts are refreshed from today's saved likes on every
-- crown update; it is dropped once the server is empty, so it never grows for the whole life of a long server.
Players.PlayerRemoving:Connect(function(leaver)
	for _, p in Players:GetPlayers() do
		if p ~= leaver then
			return
		end
	end
	likes = ParkConfig.newLikes()
end)
local crownOwner: number? = nil -- UserId of the plot owner wearing the crown
local crown: Model? = nil
local glow: Highlight? = nil -- gold glow on the crowned plot

local function clear(idx: number)
	local a = plots[idx]
	local f = a.Root:FindFirstChild("Display")
	if f then
		f:Destroy()
	end
end

-- The plot's glow ring takes the owner's gallery theme light; with no theme it is the park teal.
local function applyTheme(root: Instance, data: any?)
	local theme = if data then Cosmetics.equipped(data.Cosmetics, "GalleryTheme") else nil
	if theme then
		Cosmetics.applyAlcoveTheme(root, theme)
	else
		for _, ring in root:GetChildren() do
			if ring.Name == "ShelfLight" and ring:IsA("BasePart") then
				ring.Color = ParkBuilder.Palette.Teal
			end
		end
	end
end

local function inspectPrompt(parent: Instance, player: Player, g: any, range: number)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "InspectPrompt"
	pp.ActionText = "Inspect"
	pp.ObjectText = GeodeGen.displayName(g)
	pp.HoldDuration = 0
	pp.MaxActivationDistance = range
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R
	pp:SetAttribute("InspectOwner", player.UserId)
	pp:SetAttribute("InspectId", g.Id)
	pp.Parent = parent
end

local function placePrompt(parent: Instance)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "PlacePrompt"
	pp.ActionText = "Place pet"
	pp.ObjectText = "Showcase"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 8
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R
	pp:SetAttribute("Panel", "Collection") -- opens the Collection panel locally
	pp.Parent = parent
end

local function speciesName(g: any): string
	-- the pet's nickname when its owner named it (filtered by PetService), else the species name
	if type(g.Nickname) == "string" and g.Nickname ~= "" then
		return g.Nickname
	end
	local mineral = Config.Minerals[g.Mineral]
	return if mineral then mineral.Name else tostring(g.Mineral)
end

local function petModel(g: any, scale: number, tiny: boolean): Model
	local m = GeodeModel.build(GeodeGen.public(g), { Scale = scale, Lod = true, Tiny = tiny, NoLight = true })
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return m
end

-- The plot's LIKE prompt reads as one action: "Like / <Name>'s Park". Off on an empty plot; the owner never gets it
-- on their own plot (the client arbiter reads OwnerId; the server still refuses self-likes).
local function setLikePrompt(root: Instance, player: Player?)
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("LikePlot") ~= nil then
			d.ActionText = "Like"
			d.ObjectText = if player then player.DisplayName .. "'s Park" else ParkConfig.EmptyPlot
			d:SetAttribute("Off", player == nil)
			d:SetAttribute("OwnerId", if player then player.UserId else nil)
		end
	end
end

function Gallery.render(player: Player)
	local idx = plotOf[player]
	local data = Profiles.get(player)
	if not idx or not data then
		return
	end
	local a = plots[idx]
	clear(idx)
	a.SetLabel(player.DisplayName .. "'s Park") -- fitted Nameplate sign: shrinks, then truncates long names
	setLikePrompt(a.Root, player)
	applyTheme(a.Root, data)
	local f = Instance.new("Folder")
	f.Name = "Display"
	f.Parent = a.Root
	local slots = Profiles.displaySlots(data)
	local byId: { [string]: any } = {}
	local refs: { ParkConfig.PetRef } = {}
	for _, id in data.DisplayAssignments do
		if #refs >= slots then
			break
		end
		local _, g = Profiles.findGeode(data, id)
		if g and not byId[g.Id] then
			byId[g.Id] = g
			table.insert(refs, { Id = g.Id, Rarity = g.Rarity, Value = g.Value })
		end
	end
	local S = ParkConfig.Showcase
	local arr = ParkConfig.arrange(refs, ParkConfig.wanderCap(slots))
	local textCol = Config.RarityTextColors

	-- display slots 1-3: the glass domes (an empty dome invites the owner to place a pet)
	for k, dome in a.Domes do
		local ref = arr.Domes[k]
		local g = if ref then byId[ref.Id] else nil
		if g then
			local m = petModel(g, dome.Scale, false)
			m:PivotTo(dome.Slot)
			m.Parent = f
			CollectionService:AddTag(m, "PetSpin") -- clients turn dome pets slowly (PetDisplay; cosmetic)
			local tag = KitPlace.signText(f, "Label", dome.Label, 3.0, 0.6, speciesName(g), "Plaque", textCol[g.Rarity] or Color3.new(1, 1, 1), PLAQUE_BG)
			tag.CanQuery = true
			bothFaces(tag)
			inspectPrompt(tag, player, g, 9)
		else
			local tag = KitPlace.signText(f, "Label", dome.Label, 3.0, 0.6, "\u{1F43E} ADD PET", "Plaque", Color3.fromRGB(200, 190, 165), PLAQUE_BG)
			tag.CanQuery = true
			bothFaces(tag)
			placePrompt(tag)
		end
	end

	-- pets beyond the 3 domes stand still in the yard, each on its own spot, facing the gate (PetDisplay plays their
	-- idle and turns their heads to passers-by). Nothing roams (owner, 2026-10-14).
	local W = S.Wander
	local box = a.Wander
	local big = if a.Domes[1] then a.Frame:PointToObjectSpace(a.Domes[1].Slot.Position) else Vector3.new(S.Domes[1].X, 0, S.Domes[1].Z)
	local spots = ParkConfig.yardSpots(box, Vector2.new(big.X, big.Z), W.AvoidR, #arr.Yard)
	-- stand each pet on the ground players see at its spot (ParkConfig.yardLift): the plot frame sits on the plot's
	-- Floor, which a re-laid lawn can cover; players, the display itself and the plot's dome stands are not ground
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { f }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(skip, pl.Character)
		end
	end
	ray.FilterDescendantsInstances = skip
	local function liftAt(local2: Vector2): number
		local top = a.Frame * CFrame.new(local2.X, ParkConfig.YardMaxLift + 1, local2.Y)
		local res = workspace:Raycast(top.Position, Vector3.new(0, -(ParkConfig.YardMaxLift + 3), 0), ray)
		return ParkConfig.yardLift(if res then res.Position.Y else nil, a.Frame.Position.Y)
	end
	for k, ref in arr.Yard do
		local g = byId[ref.Id]
		if g then
			local m = petModel(g, W.PetScale, true)
			local at = spots[k]
			m:PivotTo(a.Frame * CFrame.new(at.X, liftAt(at), at.Y))
			local cy = m:GetAttribute("CentreY")
			local hit = Instance.new("Part")
			hit.Name = "Stand"
			hit.Size = Vector3.new(1.4, 1.4, 1.4)
			hit.CFrame = m:GetPivot() * CFrame.new(0, if type(cy) == "number" then cy else 0.8, 0)
			hit.Transparency = 1
			hit.Anchored = true
			hit.CanCollide = false
			hit.CanTouch = false
			hit.CanQuery = true
			hit.CastShadow = false
			hit.Parent = m
			inspectPrompt(hit, player, g, 8)
			m.Parent = f
		end
	end
end

-- LIKE ---------------------------------------------------------------------------------------------------------

-- The saved hangout state of a player (repaired in place), or nil before their profile loads.
local function hangoutOf(player: Player): Hangout.State?
	local data = Profiles.get(player)
	if not data then
		return nil
	end
	data.Hangout = Hangout.sanitize(data.Hangout)
	return data.Hangout
end

local function likeCount(idx: number): number
	local p = owner[idx]
	local h = if p then hangoutOf(p) else nil
	return if h then Hangout.likesToday(h, Hangout.day(os.time())) else 0
end

-- Moves the floating crown over the most-liked plot (or hides it when nobody has a like).
local function updateCrown()
	local present: { number } = {}
	local plotByUser: { [number]: number } = {}
	for i = 1, #plots do
		local p = owner[i]
		if p then
			table.insert(present, p.UserId)
			plotByUser[p.UserId] = i
		end
	end
	-- today's saved likes are the counts the leader is picked from (a new UTC day starts everyone at zero)
	for uid, i in plotByUser do
		likes.Count[uid] = likeCount(i)
	end
	crownOwner = ParkConfig.likeLeader(likes, present, crownOwner)
	local idx = if crownOwner then plotByUser[crownOwner] else nil
	local g = glow
	if g then
		g.Adornee = if idx then plots[idx].Root else nil
		g.Parent = if idx then plots[idx].Root else nil
	end
	local c = crown
	if not c then
		return
	end
	if idx then
		c:PivotTo(plots[idx].CrownAt)
		c.Parent = plots[idx].Root
	else
		c.Parent = nil
	end
end

-- Test hook: the UserId wearing the crown (nil = nobody).
function Gallery.crownOwner(): number?
	return crownOwner
end

local lastLike: { [Player]: number } = {}

local function like(visitor: Player, prompt: ProximityPrompt)
	local want = prompt:GetAttribute("LikePlot") -- the plot number (MapNames Plot<n>), not the list position
	local idx: number? = nil
	for p, plot in plots do
		if plot.Index == want then
			idx = p
		end
	end
	if not idx then
		return
	end
	local t = os.clock()
	if lastLike[visitor] and t - lastLike[visitor] < 0.5 then
		return
	end
	lastLike[visitor] = t
	local plotOwner = owner[idx]
	if not plotOwner then
		Net.event("Toast"):FireClient(visitor, "Nobody lives here yet", "info")
		return
	end
	local vh, oh = hangoutOf(visitor), hangoutOf(plotOwner)
	if not vh or not oh then
		return
	end
	local ok, why = Hangout.like(vh, visitor.UserId, oh, plotOwner.UserId, Hangout.day(os.time()))
	if not ok then
		Net.event("Toast"):FireClient(visitor, if why == "own" then "That's your own park!" elseif why == "max" then "You liked lots of parks today!" else "You already liked this park today", "info")
		return
	end
	Profiles.changed(visitor, true)
	Profiles.changed(plotOwner, true)
	plots[idx].SetLikes(likeCount(idx))
	Net.event("Toast"):FireClient(visitor, "You liked " .. plotOwner.DisplayName .. "'s park!", "ok")
	if plotOwner.Parent then
		Net.event("Toast"):FireClient(plotOwner, visitor.DisplayName .. " liked your park!", "ok")
	end
	updateCrown()
end


local function assign(player: Player)
	if plotOf[player] then
		return
	end
	for i = 1, #plots do
		if not owner[i] then
			owner[i] = player
			plotOf[player] = i
			player:SetAttribute("Alcove", plots[i].Index or i) -- the plot number (MapNames Plot<n>): Main.client's marker
			player:SetAttribute("Plot", plots[i].Index or i)
			Gallery.render(player)
			plots[i].SetLikes(likeCount(i))
			updateCrown()
			return
		end
	end
end

local function release(player: Player)
	local idx = plotOf[player]
	if not idx then
		return
	end
	clear(idx)
	plots[idx].SetLabel(ParkConfig.EmptyPlot)
	setLikePrompt(plots[idx].Root, nil)
	applyTheme(plots[idx].Root, nil)
	owner[idx] = nil
	plotOf[player] = nil
	plots[idx].SetLikes(0)
	updateCrown()
end

-- A visitor pressed Inspect on a displayed pet: send them a read-only card. The server re-checks that the owner is
-- still here and the pet is still on display.
local lastInspect: { [Player]: number } = {}

local function inspect(visitor: Player, prompt: ProximityPrompt)
	local ownerId = prompt:GetAttribute("InspectOwner")
	local id = prompt:GetAttribute("InspectId")
	if type(ownerId) ~= "number" or type(id) ~= "string" then
		return
	end
	local t = os.clock()
	if lastInspect[visitor] and t - lastInspect[visitor] < 0.5 then
		return
	end
	lastInspect[visitor] = t
	local plotOwner = Players:GetPlayerByUserId(ownerId)
	local data = if plotOwner then Profiles.get(plotOwner) else nil
	if not plotOwner or not data or not table.find(data.DisplayAssignments, id) then
		return
	end
	local _, g = Profiles.findGeode(data, id)
	if not g then
		return
	end
	Net.event("Inspect"):FireClient(visitor, {
		Owner = plotOwner.DisplayName,
		IsYou = plotOwner == visitor,
		Specimen = GeodeGen.public(g),
	})
end

function Gallery.start(lobbyInfo)
	plots = lobbyInfo.Alcoves
	if plots[1] then
		local c = ParkBuilder.crown(plots[1].Root, "CT_Park_PlotCrown", plots[1].CrownAt, 2.4)
		c.Parent = nil -- shown over the most-liked plot only
		local top = c:FindFirstChildWhichIsA("BasePart", true)
		if top then
			local light = Instance.new("PointLight")
			light.Color = Hangout.Likes.Glow
			light.Brightness = 2
			light.Range = 18
			light.Parent = top
		end
		crown = c
	end
	local h = Instance.new("Highlight")
	h.Name = "CT_TopPlotGlow"
	h.FillColor = Hangout.Likes.Glow
	h.FillTransparency = 0.85
	h.OutlineColor = Hangout.Likes.Glow
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	glow = h
	-- a new UTC day resets everyone's likes: re-read the counts once a minute
	task.spawn(function()
		while true do
			task.wait(60)
			for i = 1, #plots do
				if owner[i] then
					plots[i].SetLikes(likeCount(i))
				end
			end
			updateCrown()
		end
	end)
	-- Triggered is not proof of range (an exploit client can fire it): re-check the distance on the server.
	local function inRange(prompt: ProximityPrompt, player: Player): boolean
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local parent = prompt.Parent
		local at: Vector3? = if parent and parent:IsA("BasePart") then parent.Position
			elseif parent and parent:IsA("Attachment") then parent.WorldPosition
			elseif parent and parent:IsA("Model") then parent:GetPivot().Position
			else nil
		return root ~= nil and root:IsA("BasePart") and at ~= nil and (root.Position - at).Magnitude <= prompt.MaxActivationDistance + 6
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if (prompt:GetAttribute("InspectId") or prompt:GetAttribute("LikePlot")) and not inRange(prompt, player) then
			return
		end
		if prompt:GetAttribute("InspectId") then
			inspect(player, prompt)
		elseif prompt:GetAttribute("LikePlot") then
			like(player, prompt)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastInspect[p] = nil
		lastLike[p] = nil
	end)
	Profiles.onLoaded(function(player)
		assign(player)
	end)
	Players.PlayerRemoving:Connect(release)
end

-- Test / preview hook: the plot index a player holds.
function Gallery.plotOf(player: Player): number?
	return plotOf[player]
end

return Gallery
