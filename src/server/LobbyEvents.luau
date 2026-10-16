--!strict
-- Hourly lobby events (owner pick 2026-10-14, lobby hangout idea 7). At the start of every UTC hour every server runs
-- the same event (Hangout.eventAt), with a toast one minute before:
--   CoinRain    coins fall around the event spot for CoinRain.Seconds; touch one to take it (PlayerCap per player)
--   GoldenRock  a big golden rock everyone cracks together ("Crack" prompt, one hit per HitGap per player); when it
--               breaks, everyone who hit it gets GoldenRock.Prize coins. If time runs out, nobody gets anything.
--   MysteryEgg  an egg drops at an event spot; the first player to open it gets a free pet (RobuxService.giftEgg,
--               Basic egg odds), or FallbackCoins when their Pet Book is full.
-- Event spots: parts named EventSpot or EventSpot1..N in the lobby; without one, the lobby spawn is used.
-- Every event part lives in Workspace.CT_HangoutEvents (outside the lobby folder and its decor policy).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)
local Net = require(Shared.Net)
local H = require(script.Parent.LobbyHangout)

local LobbyEvents = {}

local E = Hangout.Events
local spots: { Vector3 } = {}
local fallback = Vector3.new(0, 5, 0)
local gift: ((Player, string, string) -> any?)? = nil

type Current = { Kind: string, Ends: number, Id: number, Parts: { Instance } }
local current: Current? = nil
local serial = 0
local rainGot: { [Player]: number } = {}
local rockHits: { [Player]: number } = {}
local rockLast: { [Player]: number } = {}
local rockTotal, rockNeed = 0, 0
local eggOpened = false

local folder: Folder? = nil
local function partsFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "CT_HangoutEvents"
	made.Parent = Workspace
	folder = made
	return made
end

local function spot(): Vector3
	return if #spots > 0 then spots[math.random(1, #spots)] else fallback
end

local function broadcast(kind: string, payload: any)
	Net.event("HangoutEvent"):FireAllClients(kind, payload)
end

local function finish(c: Current, line: string?)
	if current ~= c then
		return
	end
	current = nil
	for _, p in c.Parts do
		p:Destroy()
	end
	table.clear(rainGot)
	table.clear(rockHits)
	table.clear(rockLast)
	broadcast("Event", { Kind = c.Kind, State = "End" })
	if line then
		H.toastAll(line, "ok")
	end
end

-- Coin rain -----------------------------------------------------------------------------------------------------------

-- A player touched (or the test took) a coin. Returns the coins paid.
function LobbyEvents.collect(player: Player, coin: Instance): number
	local c = current
	if not c or c.Kind ~= "CoinRain" or coin:GetAttribute("Taken") or not coin:IsDescendantOf(partsFolder()) then
		return 0
	end
	local room = Hangout.rainRoom(rainGot[player] or 0)
	if room <= 0 then
		return 0
	end
	coin:SetAttribute("Taken", true)
	local value = math.min(E.CoinRain.CoinValue, room)
	local at = if coin:IsA("BasePart") then coin.Position else nil
	coin:Destroy()
	local paid = H.pay(player, value)
	rainGot[player] = (rainGot[player] or 0) + paid
	Net.event("HangoutEvent"):FireClient(player, "Coin", { Pos = at, Coins = paid })
	return paid
end

local function dropCoin(c: Current)
	local cfg = E.CoinRain
	local centre = c.Parts[1] and (c.Parts[1] :: any).Position or spot()
	local a = math.random() * math.pi * 2
	local r = math.sqrt(math.random()) * cfg.Radius
	local coin = Instance.new("Part")
	coin.Name = "RainCoin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.4, 2, 2)
	coin.Color = Color3.fromRGB(255, 200, 40)
	coin.Material = Enum.Material.SmoothPlastic
	coin.Reflectance = 0.15
	coin.CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * r, cfg.DropHeight, math.sin(a) * r)) * CFrame.Angles(0, 0, math.rad(90))
	coin.CanCollide = true
	coin.Touched:Connect(function(hit: BasePart)
		local model = hit:FindFirstAncestorOfClass("Model")
		local p = if model then Players:GetPlayerFromCharacter(model) else nil
		if p then
			LobbyEvents.collect(p, coin)
		end
	end)
	coin.Parent = partsFolder()
	table.insert(c.Parts, coin)
	task.delay(cfg.Life, function()
		if coin.Parent then
			coin:Destroy()
		end
	end)
end

local function coinRain(c: Current)
	local cfg = E.CoinRain
	local marker = Instance.new("Part") -- an invisible centre (the first event part: dropCoin reads it)
	marker.Name = "RainCentre"
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = spot()
	marker.Parent = partsFolder()
	table.insert(c.Parts, marker)
	H.toastAll("COIN RAIN! Grab the falling coins!", "rare")
	for _ = 1, cfg.Coins do
		if current ~= c then
			return
		end
		dropCoin(c)
		task.wait(cfg.Seconds / cfg.Coins)
	end
	task.wait(2)
	finish(c, nil)
end

-- Golden rock ---------------------------------------------------------------------------------------------------------

local function rockLabel(c: Current)
	local gui = c.Parts[1] and c.Parts[1]:FindFirstChild("RockGui", true)
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = "GOLDEN EGG\n" .. math.max(0, rockNeed - rockTotal) .. " taps left"
	end
end

-- A "Crack" hit on the golden rock (prompt, range checked by LobbyHangout).
function LobbyEvents.hitRock(player: Player): boolean
	local c = current
	if not c or c.Kind ~= "GoldenRock" then
		return false
	end
	local t = os.clock()
	if rockLast[player] and t - rockLast[player] < E.GoldenRock.HitGap then
		return false
	end
	rockLast[player] = t
	rockHits[player] = (rockHits[player] or 0) + 1
	rockTotal += 1
	rockLabel(c)
	broadcast("RockHit", { Left = math.max(0, rockNeed - rockTotal), Pos = (c.Parts[1] :: any).Position })
	if rockTotal >= rockNeed then
		local helpers = 0
		for p in rockHits do
			if p.Parent then
				helpers += 1
				H.pay(p, E.GoldenRock.Prize)
			end
		end
		finish(c, "The GOLDEN EGG hatched! " .. helpers .. " helpers got " .. E.GoldenRock.Prize .. " coins each!")
	end
	return true
end

H.onPrompt("GoldRock", function(player, _prompt)
	LobbyEvents.hitRock(player)
end)

local function goldenRock(c: Current)
	local cfg = E.GoldenRock
	rockTotal = 0
	rockNeed = Hangout.rockHits(#Players:GetPlayers())
	local rock = Instance.new("Part")
	rock.Name = "GoldenRock"
	rock.Size = Vector3.new(7, 6, 7)
	rock.Color = Color3.fromRGB(255, 196, 46)
	rock.Material = Enum.Material.SmoothPlastic
	rock.Reflectance = 0.2
	rock.Anchored = true
	rock.CFrame = CFrame.new(spot() + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(20), math.rad(8))
	local light = Instance.new("PointLight")
	light.Color = rock.Color
	light.Range = 20
	light.Brightness = 2
	light.Parent = rock
	local gui = Instance.new("BillboardGui")
	gui.Name = "RockGui"
	gui.Size = UDim2.fromScale(10, 3)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 236, 160)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = rock
	H.prompt(rock, "GoldRock", "Tap", "Golden Egg", cfg.Range)
	rock.Parent = partsFolder()
	table.insert(c.Parts, rock)
	rockLabel(c)
	H.toastAll("A GOLDEN EGG appeared! Everyone tap it together!", "rare")
	task.wait(cfg.Seconds)
	finish(c, "The golden egg rolled away... next time!")
end

-- Mystery egg ---------------------------------------------------------------------------------------------------------

function LobbyEvents.openEgg(player: Player): boolean
	local c = current
	if not c or c.Kind ~= "MysteryEgg" or eggOpened then
		return false
	end
	eggOpened = true
	local g = gift
	local pet = if g then g(player, E.MysteryEgg.Egg, "mystery:" .. c.Id .. ":" .. player.UserId) else nil
	if not pet then
		local paid = H.pay(player, E.MysteryEgg.FallbackCoins)
		H.toast(player, "Your Pet Book is full, so the mystery egg gave you " .. paid .. " coins!", "ok")
	end
	finish(c, player.DisplayName .. " opened the MYSTERY EGG!")
	return true
end

H.onPrompt("MysteryEgg", function(player, _prompt)
	LobbyEvents.openEgg(player)
end)

local function mysteryEgg(c: Current)
	local cfg = E.MysteryEgg
	eggOpened = false
	local egg = Instance.new("Part")
	egg.Name = "MysteryEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(3.4, 3.4, 3.4)
	egg.Color = Color3.fromRGB(170, 110, 255)
	egg.Material = Enum.Material.SmoothPlastic
	egg.Anchored = true
	egg.Position = spot() + Vector3.new(0, 1.7, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = egg.Color
	light.Range = 14
	light.Parent = egg
	H.prompt(egg, "MysteryEgg", "Open", "Mystery Egg", cfg.Range, 1)
	egg.Parent = partsFolder()
	table.insert(c.Parts, egg)
	H.toastAll("A MYSTERY EGG dropped in the lobby! First to open it wins a pet!", "rare")
	task.wait(cfg.Seconds)
	finish(c, "Nobody found the mystery egg in time!")
end

-- Runner --------------------------------------------------------------------------------------------------------------

local RUN = { CoinRain = coinRain, GoldenRock = goldenRock, MysteryEgg = mysteryEgg }

-- Starts event `kind` now (the hourly schedule, /event in Studio, tests). False when one is already running.
function LobbyEvents.run(kind: string): boolean
	local fn = (RUN :: any)[kind]
	if not fn or current then
		return false
	end
	serial += 1
	local c: Current = { Kind = kind, Ends = 0, Id = os.time() * 10 + serial % 10, Parts = {} }
	current = c
	broadcast("Event", { Kind = kind, State = "Start", Name = E.Names[kind] })
	task.spawn(fn, c)
	return true
end

-- The running event (tests): { Kind, Parts } or nil.
function LobbyEvents.current(): any
	return current
end

-- Tests only: the pet gift used by the mystery egg.
function LobbyEvents.setGift(fn: (Player, string, string) -> any?)
	gift = fn
end

local function schedule()
	while true do
		local now = os.time()
		local at = Hangout.nextEventTime(now)
		local kind = Hangout.eventAt(at)
		local warnAt = at - E.WarnSeconds
		if warnAt > now then
			task.wait(warnAt - now)
			H.toastAll(E.Names[kind] .. " starts in 1 minute! Come to the plaza!", "info")
		end
		task.wait(math.max(0, at - os.time()))
		LobbyEvents.run(kind)
		task.wait(5)
	end
end

function LobbyEvents.start(roots: { Instance }, spawnAt: Vector3?, giftFn: ((Player, string, string) -> any?)?)
	if giftFn and not gift then
		gift = giftFn
	end
	if spawnAt then
		fallback = spawnAt
	end
	for _, r in roots do
		for _, d in r:GetDescendants() do
			if d:IsA("BasePart") and string.match(d.Name, "^EventSpot%d*$") then
				table.insert(spots, d.Position + Vector3.new(0, d.Size.Y / 2, 0))
			end
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		rainGot[p] = nil
		rockHits[p] = nil
		rockLast[p] = nil
	end)
	task.spawn(schedule)
end

return LobbyEvents
