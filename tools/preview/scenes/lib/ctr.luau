--[[
	scenes/lib/ctr.luau - helpers shared by the Crack the Rocks preview scenes.

	Scenes drive the game only through its real entry points: the server boots from
	ServerScriptService.Server.Main (preview.startServer), the client from
	StarterPlayerScripts.Client.Main (preview.startClient), and both talk through the real
	RemoteEvents in ReplicatedStorage.Remotes. Profile data is changed on the server
	(Profiles.get + Profiles.changed), so the client receives the real publicView.
	Every step is protected: a failing game module is reported with its stack and the
	scene still renders whatever exists.

	The mock has no default Roblox avatar, so C.boot builds a plain R15-shaped character
	(HumanoidRootPart, Head, torso, arms, legs, RightHand, Humanoid) for each player.
]]

local C = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Runs fn; on error reports it and returns nil (the scene keeps going).
function C.try(label: string, fn, ...)
	local results = table.pack(xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end, ...))
	if not results[1] then
		preview.warn(label .. " failed:\n" .. tostring(results[2]))
		return nil
	end
	return table.unpack(results, 2, results.n)
end

function C.shared(name: string)
	return C.try("require Shared." .. name, preview.shared, name)
end

function C.server(name: string)
	return C.try("require Server." .. name, preview.server, name)
end

local SKIN = Color3.fromRGB(234, 184, 146)
local SHIRT = Color3.fromRGB(52, 120, 196)
local PANTS = Color3.fromRGB(46, 52, 70)

-- A blocky R15-shaped stand-in for the default avatar, feet on the floor at cf.
function C.makeCharacter(player: Player, cf: CFrame, shirt: Color3?)
	local m = Instance.new("Model")
	m.Name = player.Name
	local function p(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Shape = shape or Enum.PartType.Block
		part.Anchored = false
		part.CFrame = cf * CFrame.new(offset)
		part.Parent = m
		return part
	end
	local root = p("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), SHIRT)
	root.Transparency = 1
	root.Anchored = true
	p("LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0, 2.3, 0), PANTS)
	p("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.4, 0), shirt or SHIRT)
	p("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.85, 0), SKIN)
	p("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3.6, 0), shirt or SHIRT)
	p("LeftLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(-1.5, 2.6, 0), SKIN)
	p("LeftHand", Vector3.new(1, 0.4, 1), Vector3.new(-1.5, 1.95, 0), SKIN)
	p("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3.6, 0), shirt or SHIRT)
	p("RightLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(1.5, 2.6, 0), SKIN)
	p("RightHand", Vector3.new(1, 0.4, 1), Vector3.new(1.5, 1.95, 0), SKIN)
	p("LeftUpperLeg", Vector3.new(1, 1, 1), Vector3.new(-0.5, 1.5, 0), PANTS)
	p("LeftLowerLeg", Vector3.new(1, 0.8, 1), Vector3.new(-0.5, 0.6, 0), PANTS)
	p("RightUpperLeg", Vector3.new(1, 1, 1), Vector3.new(0.5, 1.5, 0), PANTS)
	p("RightLowerLeg", Vector3.new(1, 0.8, 1), Vector3.new(0.5, 0.6, 0), PANTS)
	-- R15-style Motor6D joints (named as in Roblox) so held tools and arm swings move
	-- with the body in the preview: joint pivot at the top centre of the child part.
	local function joint(name: string, p0n: string, p1n: string)
		local p0 = m:FindFirstChild(p0n) :: BasePart
		local p1 = m:FindFirstChild(p1n) :: BasePart
		local at = p1.CFrame * CFrame.new(0, p1.Size.Y / 2, 0)
		local j = Instance.new("Motor6D")
		j.Name = name
		j.C0 = p0.CFrame:ToObjectSpace(at)
		j.C1 = p1.CFrame:ToObjectSpace(at)
		j.Part0 = p0
		j.Part1 = p1
		j.Parent = p1
	end
	joint("Root", "HumanoidRootPart", "LowerTorso")
	joint("Waist", "LowerTorso", "UpperTorso")
	joint("Neck", "UpperTorso", "Head")
	joint("LeftShoulder", "UpperTorso", "LeftUpperArm")
	joint("LeftElbow", "LeftUpperArm", "LeftLowerArm")
	joint("LeftWrist", "LeftLowerArm", "LeftHand")
	joint("RightShoulder", "UpperTorso", "RightUpperArm")
	joint("RightElbow", "RightUpperArm", "RightLowerArm")
	joint("RightWrist", "RightLowerArm", "RightHand")
	joint("LeftHip", "LowerTorso", "LeftUpperLeg")
	joint("LeftKnee", "LeftUpperLeg", "LeftLowerLeg")
	joint("RightHip", "LowerTorso", "RightUpperLeg")
	joint("RightKnee", "RightUpperLeg", "RightLowerLeg")
	local hum = Instance.new("Humanoid")
	hum.Parent = m
	m.PrimaryPart = root
	m.Parent = Workspace
	player.Character = m
	return m
end

function C.lobbySpawn(): CFrame
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			return d.CFrame * CFrame.new(0, d.Size.Y / 2, 0)
		end
	end
	return CFrame.new(0, 0, 0)
end

-- Places a character's feet at cf (keeps the model's look direction from cf).
function C.place(player: Player, cf: CFrame)
	local char = player.Character
	if char then
		char:PivotTo(cf * CFrame.new(0, 3, 0))
		-- the mock's PivotTo does not run joints: re-seat the body (and held tool) from the root
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local cf = root.CFrame
			root.CFrame = cf + Vector3.new(0, 0.001, 0)
			root.CFrame = cf
		end
	end
end

-- --set uiscale=real: the renderer lays a ScreenGui out at scale 1 and ignores a UIScale parented to the
-- ScreenGui itself (Roblox applies it to everything inside). The game's UI layers carry one (UI.luau "Scale"),
-- so this moves each layer's contents into a full-screen Frame that carries the same scale, which the renderer
-- does draw: the picture then shows the menus at the size a real device would. Preview only.
function C.realUIScale()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function wrap(sg: Instance)
		if not sg:IsA("ScreenGui") then
			return
		end
		local sc = sg:FindFirstChild("Scale")
		if not sc or not sc:IsA("UIScale") or sg:FindFirstChild("PreviewScaleRoot") then
			return
		end
		local root = Instance.new("Frame")
		root.Name = "PreviewScaleRoot"
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		local mirror = Instance.new("UIScale")
		local function fit()
			local k = math.max(sc.Scale, 0.01)
			mirror.Scale = k
			root.Size = UDim2.fromScale(1 / k, 1 / k)
		end
		fit()
		sc:GetPropertyChangedSignal("Scale"):Connect(fit)
		mirror.Parent = root
		root.Parent = sg
		local function move(c: Instance)
			if c ~= root and c:IsA("GuiObject") then
				c.Parent = root
			end
		end
		for _, c in sg:GetChildren() do
			move(c)
		end
		sg.ChildAdded:Connect(move)
	end
	local function watch(sg: Instance)
		task.defer(wrap, sg)
		sg.ChildAdded:Connect(function(c)
			if c.Name == "Scale" then
				task.defer(wrap, sg)
			end
		end)
	end
	for _, sg in pg:GetChildren() do
		watch(sg)
	end
	pg.ChildAdded:Connect(watch)
end

-- Boots the real server (Main.server) with the local player (and opts.others: list of
-- {name, userId}) present, waits for the profiles to load, then edits the local profile
-- with opts.profile(data) and boots the real client (Main.client).
-- Returns { me, others, Profiles, MatchService, PartyService, Config }.
function C.boot(opts)
	opts = opts or {}
	local me = Players.LocalPlayer
	local others = {}
	for _, o in ipairs(opts.others or {}) do
		table.insert(others, preview.addPlayer(o[1], o[2]))
	end
	-- characters first (the server's tool attach and hunts need them)
	C.makeCharacter(me, CFrame.new(0, 0, 0))
	local colors = { Color3.fromRGB(196, 72, 60), Color3.fromRGB(80, 160, 90), Color3.fromRGB(200, 150, 50) }
	for i, p in ipairs(others) do
		C.makeCharacter(p, CFrame.new(4 * i, 0, 0), colors[(i - 1) % #colors + 1])
	end
	C.try("start server", preview.startServer)
	preview.advance(1)
	local spawn = C.lobbySpawn()
	C.place(me, spawn)
	for i, p in ipairs(others) do
		C.place(p, spawn * CFrame.new(4 * i, 0, 2))
	end
	local s = {
		me = me,
		others = others,
		Profiles = C.server("Profiles"),
		MatchService = C.server("MatchService"),
		PartyService = C.server("PartyService"),
		Config = C.shared("Config"),
	}
	-- Scenes move avatars by instant PivotTo (pile to table in one frame), which is exactly what the
	-- server's teleport check refuses. Off for scenes; a scene that tests the check turns it back on.
	if s.Config and s.Config.Motion and opts.motionCheck ~= true then
		s.Config.Motion.Enabled = false
	end
	-- profiles load in the background (in-memory DataStore)
	for _ = 1, 50 do
		if s.Profiles and s.Profiles.isLoaded(me) then
			break
		end
		preview.advance(0.1)
	end
	if opts.profile and s.Profiles then
		local data = s.Profiles.get(me)
		if data then
			C.try("profile edit", opts.profile, data, s.Config)
			s.Profiles.changed(me)
		else
			preview.warn("local profile not loaded")
		end
	end
	if preview.args.uiscale == "real" then
		C.realUIScale()
	end
	if preview.args.headless == "on" then
		preview.startClient(false)
	else
		C.try("start client", preview.startClient)
	end
	preview.advance(0.5)
	return s
end

-- A few made-up specimens shaped like GeodeGen.roll output (for collection / display scenes).
function C.fakeSpecimens(n: number)
	local GeodeGen = C.shared("GeodeGen")
	local Config = C.shared("Config")
	local out = {}
	if not GeodeGen or not Config then
		return out
	end
	local tiers = {}
	for id in pairs(Config.Tiers) do
		table.insert(tiers, id)
	end
	table.sort(tiers, function(a, b)
		return (Config.Tiers[a].Order or 0) < (Config.Tiers[b].Order or 0)
	end)
	local rng = Random.new(preview.seed * 31 + 7)
	for i = 1, n do
		local tier = tiers[(i - 1) % #tiers + 1]
		local ok, spec = pcall(GeodeGen.roll, Random.new(rng:NextInteger(1, 2 ^ 30)), tier, string.format("preview-%04d", i), "preview:" .. i, 1760000000 + i * 3600, i % 3 ~= 0)
		if ok and spec then
			table.insert(out, spec)
		else
			preview.warn("GeodeGen.roll failed: " .. tostring(spec))
		end
	end
	return out
end

-- Records every MatchEvent the local client gets (kind -> last payload, plus a list).
function C.watchMatch()
	local w = { last = {}, kinds = {}, at = {} } -- at[phase] = simulated time it began
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local ev = folder and folder:FindFirstChild("MatchEvent")
	if ev then
		ev.OnClientEvent:Connect(function(kind, data)
			w.last[kind] = data
			table.insert(w.kinds, kind)
			if kind == "Phase" and type(data) == "table" and data.Phase then
				w.at[data.Phase] = preview.now()
			end
		end)
	end
	return w
end

-- Starts a solo hunt through the real PartyAction("Solo") handler and waits for the Init.
function C.startSolo(w)
	C.fireServer("PartyAction", "Solo")
	for _ = 1, 20 do
		if w.last.Init then
			break
		end
		preview.advance(0.1)
	end
	if not w.last.Init then
		preview.warn("no MatchEvent Init after PartyAction Solo")
	end
	return w.last.Init
end

-- Advances until the hunt's phase is `phase` (MatchEvent Phase), at most `limit` seconds.
function C.waitPhase(w, phase: string, limit: number?)
	local t = 0
	while t < (limit or 10) do
		local ph = w.last.Phase
		if ph and ph.Phase == phase then
			return true
		end
		preview.advance(0.1)
		t += 0.1
	end
	preview.warn("hunt did not reach phase " .. phase)
	return false
end

-- Plays the V3 loop through the real RockAction remote until the geode is found: each listed
-- player walks to the pile and picks rocks up (Pickup, 0.45 s apart), carries a full basket to
-- their own crushing table (Deposit), then crushes the tray at the tool's rate (Crush). A player
-- whose station has a running machine only collects and deposits. A local Pile replica built from
-- the Init payload is kept in sync with the Rocks events. opts: stopAfterDone = N ends the loop
-- once N rocks were crushed in total; stopWhen = function() -> true ends it; onStep = function() called every 0.1 s step.
-- Returns true when a Found event arrived.
function C.crackUntilFound(w, players: { Player }?, limit: number?, opts: { [string]: any }?)
	local init = w.last.Init
	local Config = C.shared("Config")
	local Pile = C.shared("Pile")
	if not init or not Config or not Pile then
		return false
	end
	opts = opts or {}
	players = players or { Players.LocalPlayer }
	local tier = Config.Tiers[init.Tier]
	local pile = Pile.new(init.Rocks, tier.RockSize, tier.Radius, init.Seed)
	if init.Stacks then
		pile:setStacks(init.Stacks)
	else
		for _, id in ipairs(init.Removed or {}) do
			pile:remove(id)
		end
	end
	local center: Vector3 = init.Center
	local stations = {}
	for _, v in ipairs(init.Stations or {}) do
		stations[v.UserId] = v
	end
	local tablePos = {}
	for _, t in ipairs(init.Tables or {}) do
		tablePos[t.Index] = t.Position
	end
	local done = 0
	local ev = game:GetService("ReplicatedStorage").Remotes.MatchEvent
	local conn = ev.OnClientEvent:Connect(function(kind, data)
		if kind == "Rocks" and data.Round == init.Round then
			for _, e in ipairs(data.Ev or {}) do
				if e.Kind == "Pick" then
					pile:remove(e.Id)
				elseif e.Kind == "Return" then
					pile:restoreTo(e.Id, e.Col)
				elseif e.Kind == "Done" then
					done += 1
				end
			end
			stations = {}
			for _, v in ipairs(data.Stations or {}) do
				stations[v.UserId] = v
			end
		end
	end)
	local mode: { [number]: string } = {}
	local nextAct: { [number]: number } = {}
	local reach = Config.Carry.ReachLevels
	local cap = Config.Carry.Capacity
	local t0 = preview.now()
	local function stand(p: Player, pos: Vector3, look: Vector3)
		local char = p.Character
		if char then
			char:PivotTo(CFrame.lookAt(Vector3.new(pos.X, 3, pos.Z), Vector3.new(look.X, 3, look.Z)))
		end
	end
	while preview.now() - t0 < (limit or 400) and not w.last.Found do
		if opts.stopAfterDone and done >= opts.stopAfterDone then
			break
		end
		if opts.stopWhen and opts.stopWhen() then
			break
		end
		local taken: { [number]: boolean } = {}
		for _, p in ipairs(players) do
			local uid = p.UserId
			local st = stations[uid]
			local now = preview.now()
			if st and now >= (nextAct[uid] or 0) then
				local auto = st.Machine ~= nil and st.State ~= "Paused"
				local basket = #st.Basket
				local queued = #st.Queue + (if st.Current then 1 else 0)
				local m = mode[uid] or "collect"
				local tp = tablePos[st.Index]
				local standPos = if tp then tp + (center - tp).Unit * 3.4 else center
				if m == "collect" then
					local pick = nil
					if basket < cap then
						for _, id in ipairs(pile:pickableIds(reach)) do
							if not taken[id] then
								pick = id
								break
							end
						end
					end
					if pick then
						taken[pick] = true
						local lp = pile:localPosition(pick)
						local flat = Vector3.new(lp.X, 0, lp.Z)
						local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
						stand(p, center + flat + dir * (tier.RockSize + 3), center + flat)
						preview.fireServerAs(p, "RockAction", "Pickup", init.Round, pick)
						nextAct[uid] = now + Config.Carry.PickupInterval + 0.05
					elseif basket > 0 then
						mode[uid] = "deposit"
					elseif queued > 0 and not auto then
						mode[uid] = "crush"
					else
						nextAct[uid] = now + 0.3 -- nothing to do (pile empty, machine busy)
					end
				elseif m == "deposit" then
					if basket == 0 then
						mode[uid] = if (queued > 0 and not auto) then "crush" else "collect"
					else
						stand(p, standPos, if tp then tp else center)
						preview.fireServerAs(p, "RockAction", "Deposit", init.Round)
						nextAct[uid] = now + Config.Station.DepositInterval + 0.1
						if queued >= Config.Station.QueueCapacity and not auto then
							mode[uid] = "crush"
						end
					end
				else
					if queued == 0 then
						mode[uid] = "collect"
					elseif auto then
						mode[uid] = "collect"
					else
						stand(p, standPos, if tp then tp else center)
						preview.fireServerAs(p, "RockAction", "Crush", init.Round)
						local tool = Config.Handhelds[st.Tool or "Hammer"] or Config.Handhelds.Hammer
						nextAct[uid] = now + 1 / tool.Rate + 0.05
					end
				end
			end
		end
		if opts.onStep then
			opts.onStep()
		end
		preview.advance(0.1)
	end
	conn:Disconnect()
	return w.last.Found ~= nil
end

-- Fires a client->server remote as the local player (the real handler runs).
function C.fireServer(name: string, ...)
	C.try("FireServer " .. name, preview.fireServerAs, Players.LocalPlayer, name, ...)
end

-- Lets pop-in / slide animations finish.
function C.settle(seconds: number?)
	preview.advance(seconds or 1.5, 30)
end

-- Camera looking at `target` from `offset` (world studs), like the default follow camera.
function C.cameraAt(target: Vector3, offset: Vector3, fov: number?)
	local cam = Workspace.CurrentCamera
	cam.CFrame = CFrame.lookAt(target + offset, target)
	if fov then
		cam.FieldOfView = fov
	end
end

-- Default follow camera behind the local character (Roblox's Classic camera at ~16 studs).
function C.followCamera(distance: number?, height: number?)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local cf = root.CFrame
	local target = cf.Position + Vector3.new(0, 1.5, 0)
	local back = -cf.LookVector * (distance or 14)
	C.cameraAt(target, back + Vector3.new(0, height or 7, 0))
end

-- First GuiObject whose Text matches the Lua pattern (upper-cased compare), or nil. With
-- class "GuiButton" a matching label inside a button (UI.button puts its text on a child
-- TextLabel) returns that button.
function C.findText(pattern: string, class: string?)
	local hits = preview.findGui(function(obj, st)
		local ok, text = pcall(function()
			return obj.Text
		end)
		return ok and type(text) == "string" and string.find(string.upper(text), pattern) ~= nil
	end)
	for _, g in ipairs(hits) do
		if not class or g:IsA(class) then
			return g
		end
		if class == "GuiButton" then
			local b = g:FindFirstAncestorWhichIsA("GuiButton")
			if b then
				return b
			end
		end
	end
	return nil
end

-- Opens a panel exactly as the HUD buttons do (taps the HUD button with that label).
function C.tap(pattern: string)
	local b = C.findText(pattern, "GuiButton")
	if not b then
		-- icon tiles (UI v2 HUD menu) carry their panel in the Name, not always in a caption
		local alias = { ["^SHOP$"] = "Shop", ["^UPGRADES$"] = "Shop", ["^COLLECTION$"] = "Collection", ["^SETTINGS$"] = "Settings", ["^PARTY$"] = "Party", ["^LOBBY$"] = "Lobby", ["^RESULTS$"] = "Results" }
		local want = alias[pattern]
		if want then
			local hits = preview.findGui(function(obj)
				return obj:IsA("GuiButton") and obj.Name == want and obj.Parent ~= nil and obj.Parent.Name == "Menu"
			end)
			b = hits[1]
		end
	end
	if not b then
		preview.warn("no button matching " .. pattern)
		return false
	end
	preview.click(b)
	return true
end

return C
