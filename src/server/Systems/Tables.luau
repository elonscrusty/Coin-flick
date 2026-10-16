--!strict
-- Each player's table, its coins and helper guys, and every flip.
-- The client only says "I tapped coin N". This module checks it and decides
-- heads or skull with the server's own random numbers.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local CoinLook = require(ReplicatedStorage.Shared.Util.CoinLook)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local FlipArc = require(ReplicatedStorage.Shared.Util.FlipArc)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local TableLayout = require(ReplicatedStorage.Shared.Util.TableLayout)
local Boosts = require(script.Parent.Boosts)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)
local Plot = require(script.Parent.Parent.Builders.Plot)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Profile = Types.Profile
type FlipResult = Types.FlipResult

type TableState = {
	slot: number,
	model: Model,
	center: Vector3, -- middle of the table top surface
	coins: { BasePart },
	faces: { FlipResult },
	busyUntil: { number },
	helperNext: { [string]: number }, -- helper id -> when he flips next
	nextAutoFlip: number,
	combo: number, -- chain flips: taps in a row, each within COMBO_WINDOW
	lastTapAt: number,
	yaw: number, -- turns the coins so they spin toward the ZOOM camera (FlipArc.spinYaw)
	characterConn: RBXScriptConnection?,
}

local Tables = {}

local states: { [Player]: TableState } = {}
local rng = Random.new()
local tapLimiter = RateLimiter.new(Config.TAP_RATE, Config.TAP_BURST, os.clock)
local waitingForPlot: { Player } = {}
local forcedRarity: { [Player]: string } = {} -- Studio test button only
local SEE_FLIPS_DISTANCE = 220
local HEADS: FlipResult = "heads"

-- A coin lies flat: its round faces point up/down. Heads = Right face up.
local function restCFrame(state: TableState, index: number, face: FlipResult): CFrame
	local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
	local pos = state.center + Vector3.new(x, Config.COIN_THICKNESS / 2, z)
	local roll = FlipArc.restRoll(face)
	return CFrame.new(pos) * CFrame.Angles(0, state.yaw, 0) * CFrame.Angles(0, 0, roll)
end

-- One painted coin face: a thick rim, a thin inner ring and the mark in the
-- middle. Names (Rim, Ring, Mark) let the client recolor a rare coin in the air.
local function coinFace(parent: BasePart, face: Enum.NormalId, text: string, textColor: Color3, rimColor: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = `Face_{face.Name}`
	gui.Face = face
	gui.LightInfluence = 0.3
	gui.CanvasSize = Vector2.new(200, 200)
	gui.Parent = parent

	local function ring(name: string, scale: number, thickness: number)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(scale, scale)
		frame.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = thickness
		stroke.Color = rimColor
		stroke.Parent = frame
		frame.Parent = gui
	end
	ring("Rim", 0.94, 12)
	ring("Ring", 0.74, 4)

	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.56, 0.56)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor
	label.Parent = gui
end

local function makeCoin(state: TableState, index: number, profile: Profile, skin: Config.SkinDef?): BasePart
	local diameter = Economy.coinDiameter(profile.upgrades.bigCoins)
	local face: FlipResult = state.faces[index] or HEADS
	local look = CoinLook.NORMAL
	local coinColor = if skin then skin.coin else look.color
	local textColor = if skin then skin.text else look.text
	local rimColor = if skin then CoinLook.darker(skin.coin, 0.7) else look.rim

	local coin = World.makePart({
		Name = `Coin_{index}`,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(Config.COIN_THICKNESS, diameter, diameter),
		Color = coinColor,
		Material = Enum.Material:FromName(look.material) or Enum.Material.SmoothPlastic,
		Reflectance = look.reflectance,
		CanCollide = false,
		CanQuery = false, -- taps hit the bigger hitbox instead
		CanTouch = false,
		CastShadow = true,
	})
	coin.CFrame = restCFrame(state, index, face)
	coin:SetAttribute("CoinIndex", index)
	coin:SetAttribute("Face", face)
	-- What the coin looks like at rest. The client dresses rare coins in the air and always restores
	-- THIS (never whatever it finds on the part), so a coin can never stay big or colored.
	coin:SetAttribute("RestSize", coin.Size)
	coin:SetAttribute("RestColor", coin.Color)
	coin:SetAttribute("RestMaterial", coin.Material.Name)
	coin:SetAttribute("RestReflectance", coin.Reflectance)
	coinFace(coin, Enum.NormalId.Right, "$", textColor, rimColor)
	coinFace(coin, Enum.NormalId.Left, "🎩", textColor, rimColor) -- tails gives hat points

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Enabled = false
	sparkle.Rate = 0
	sparkle.Lifetime = NumberRange.new(0.4, 0.8)
	sparkle.Speed = NumberRange.new(6, 12)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, look.sparkleSize), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(look.sparkle[1], look.sparkle[#look.sparkle])
	sparkle.LightEmission = CoinLook.SPARKLE_LIGHT
	sparkle.Parent = coin

	local hitbox = World.makePart({
		Name = `Hitbox_{index}`,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, diameter + Config.HITBOX_EXTRA, diameter + Config.HITBOX_EXTRA),
		CFrame = restCFrame(state, index, HEADS),
		Transparency = 1,
		CanCollide = false,
		CanQuery = true,
		CanTouch = false,
		CastShadow = false,
	})
	hitbox:SetAttribute("CoinIndex", index)
	hitbox.Parent = state.model:FindFirstChild("Hitboxes")

	coin.Parent = state.model:FindFirstChild("Coins")
	return coin
end

local function makeHelper(state: TableState, index: number, def: Config.HelperDef, level: number): Model
	local helper = Instance.new("Model")
	helper.Name = `Helper_{def.id}`
	local body = World.makePart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (2 + level * 0.06), -- grows a little with each level
		Color = def.body,
		CanCollide = false,
		CanQuery = false,
	})
	local head = World.makePart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Color = Color3.fromRGB(255, 220, 180),
		CanCollide = false,
		CanQuery = false,
	})
	local leftEye = World.makePart({
		Name = "LeftEye",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.35, 0.35, 0.35),
		Color = Color3.fromRGB(20, 20, 30),
		CanCollide = false,
		CanQuery = false,
	})
	local rightEye = leftEye:Clone()
	rightEye.Name = "RightEye"
	local cap = World.makePart({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 1.5, 1.5),
		Color = def.cap,
		CanCollide = false,
		CanQuery = false,
	})

	local base = CFrame.new(state.center + Vector3.new(Config.TABLE_RADIUS + 2, -Config.TABLE_HEIGHT + 1, 0))
	body.CFrame = base
	head.CFrame = base * CFrame.new(0, 1.5, 0)
	leftEye.CFrame = base * CFrame.new(-0.35, 1.6, -0.7)
	rightEye.CFrame = base * CFrame.new(0.35, 1.6, -0.7)
	cap.CFrame = base * CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.pi / 2)
	for _, part in { body, head, leftEye, rightEye, cap } do
		part.Parent = helper
	end
	helper.PrimaryPart = body
	-- The client walks it around the table (smooth, and no network traffic).
	helper:SetAttribute("OrbitCenter", state.center - Vector3.new(0, Config.TABLE_HEIGHT - 1, 0))
	helper:SetAttribute("OrbitRadius", Config.TABLE_RADIUS + 2)
	helper:SetAttribute("Phase", index * 2.1)
	helper:SetAttribute("HelperId", def.id)
	helper.Parent = state.model:FindFirstChild("Helpers")
	CollectionService:AddTag(helper, "Helper")
	return helper
end

local function buildTable(player: Player, state: TableState, profile: Profile)
	local look = Config.TableLooks[Economy.tableLook(profile.resets)]
	local model = state.model
	model:ClearAllChildren()
	for _, name in { "Coins", "Hitboxes", "Helpers" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = model
	end

	local groundCenter = state.center - Vector3.new(0, Config.TABLE_HEIGHT, 0)
	local radius = Config.TABLE_RADIUS
	local topThickness = 1.2

	local top = World.makePart({
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(topThickness, radius * 2, radius * 2),
		CFrame = CFrame.new(state.center - Vector3.new(0, topThickness / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = look.top,
	})
	top.Parent = model

	local rim = World.makePart({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, radius * 2 + 1.2, radius * 2 + 1.2),
		CFrame = CFrame.new(state.center - Vector3.new(0, topThickness + 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = look.rim,
	})
	rim.Parent = model

	local legHeight = Config.TABLE_HEIGHT - topThickness - 0.6
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (radius * 0.6)
		local leg = World.makePart({
			Name = "Leg",
			Size = Vector3.new(1.4, legHeight, 1.4),
			Position = groundCenter + offset + Vector3.new(0, legHeight / 2, 0),
			Color = look.legs,
		})
		leg.Parent = model
	end

	-- The yard around the table (fence, name arch, trees).
	local center, outward = World.plotCenter(state.slot)
	local plotCFrame = CFrame.lookAt(center, center - outward)
	Plot.build(World.makePart, model, plotCFrame, look, player.DisplayName, profile.resets)

	state.coins = {}
	-- A skin only shows while the player still owns its pass.
	local skin = if profile.skin ~= "" and Boosts.owns(player, profile.skin) then Economy.skinDef(profile.skin) else nil
	local count = Economy.coinCount(profile)
	for i = 1, count do
		state.faces[i] = state.faces[i] or HEADS
		state.busyUntil[i] = state.busyUntil[i] or 0 -- coins in the air stay in the air
		state.coins[i] = makeCoin(state, i, profile, skin)
	end
	-- Empty spots for the coins you can still buy, so a fresh table after a
	-- reset looks like a goal ("fill me!") instead of a big empty circle.
	for i = 1, Economy.emptySlots(profile) do
		local index = count + i
		local x, z = TableLayout.coinOffset(index, Config.MAX_COINS)
		local d = Config.COIN_BASE_DIAMETER
		local slot = World.makePart({
			Name = `Slot_{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, d, d),
			CFrame = CFrame.new(state.center + Vector3.new(x, 0.03, z)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(120, 235, 165), -- bright mint, so it reads as "free spot" (not locked) on any table color
			Transparency = 0.3,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		local mark = Instance.new("SurfaceGui")
		mark.Face = Enum.NormalId.Right
		mark.LightInfluence = 0.3
		mark.CanvasSize = Vector2.new(200, 200)
		mark.Parent = slot
		local plus = Instance.new("TextLabel")
		plus.Size = UDim2.fromScale(1, 1)
		plus.BackgroundTransparency = 1
		plus.Text = "+"
		plus.TextScaled = true
		plus.Font = Enum.Font.FredokaOne
		plus.TextColor3 = Color3.fromRGB(255, 255, 255)
		plus.TextTransparency = 0.1
		plus.TextStrokeTransparency = 0
		plus.TextStrokeColor3 = Color3.fromRGB(20, 110, 70)
		plus.Parent = mark
		slot.Parent = model
	end
	for i = count + 1, #state.busyUntil do
		state.busyUntil[i] = nil
		state.faces[i] = nil
	end
	for i, id in profile.team do
		local def = Economy.helperDef(id)
		local level = profile.crew[id]
		if def and level then
			makeHelper(state, i, def, level)
		end
	end
	model:SetAttribute("Look", look.name)
end

local flipRemote: RemoteEvent

-- Super rare coins get shouted to the whole server the moment they are flipped,
-- while everyone can still see the big coin in the air. Silver and gold only
-- label the flipper's own coin.
local function shoutIfRare(player: Player, outcome: GameLogic.FlipOutcome)
	local notice = GameLogic.shoutNotice(player.DisplayName, player.UserId, outcome)
	if notice then
		if notice.everyone then
			Net.event("Notice"):FireAllClients(notice)
		else
			Net.event("Notice"):FireClient(player, notice)
		end
	end
end

local function flip(
	player: Player,
	state: TableState,
	profile: Profile,
	index: number,
	byHelper: boolean,
	combo: number,
	helperId: string?,
	helperMult: number?
)
	local now = os.clock()
	local duration = Economy.flipTime(profile.upgrades.speed)
	state.busyUntil[index] = now + duration
	local forced = forcedRarity[player]
	forcedRarity[player] = nil
	local rarityRoll = if forced then Economy.rarityRollFor(forced) else rng:NextNumber()
	local outcome = GameLogic.applyFlip(
		profile,
		rng:NextNumber(),
		rarityRoll,
		Boosts.cashMult(player, now) * (helperMult or 1),
		combo
	)

	local event: Types.FlipEvent = {
		ownerId = player.UserId,
		coin = index,
		result = outcome.result,
		cash = outcome.cash,
		hats = outcome.hats,
		duration = duration,
		byHelper = byHelper,
		helper = helperId,
		rarity = outcome.rarity,
		combo = combo,
	}
	-- Only players who can actually see this table get the event.
	local tablePos = state.center
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character.PrimaryPart
		if other == player or (root and (root.Position - tablePos).Magnitude <= SEE_FLIPS_DISTANCE) then
			flipRemote:FireClient(other, event)
		end
	end
	shoutIfRare(player, outcome)

	task.delay(duration, function()
		if states[player] ~= state then
			return -- player left
		end
		state.faces[index] = outcome.result
		-- The table may have been rebuilt (buy/reset) while this coin was in the air.
		local current = state.coins[index]
		if current and current.Parent then
			current.CFrame = restCFrame(state, index, outcome.result)
			current:SetAttribute("Face", outcome.result)
		end
		PlayerData.changed(player)
	end)
end

local function onTap(player: Player, rawIndex: unknown)
	if not tapLimiter:allow(player) then
		return
	end
	local state = states[player]
	local profile = PlayerData.get(player)
	if not state or not profile then
		return
	end
	local index = GameLogic.validateCoinIndex(rawIndex, #state.coins)
	if not index then
		return
	end
	local now = os.clock()
	if now < state.busyUntil[index] then
		return -- still in the air
	end
	state.combo = GameLogic.nextCombo(state.combo, state.lastTapAt, now)
	state.lastTapAt = now
	flip(player, state, profile, index, false, state.combo)
end

local function placeCharacter(player: Player)
	local state = states[player]
	local character = player.Character
	if not state or not character then
		return
	end
	local _, outward = World.plotCenter(state.slot)
	local ground = state.center - Vector3.new(0, Config.TABLE_HEIGHT, 0)
	-- Inside the yard, between the entrance and the table, facing the table.
	local standAt = ground - outward * (Config.TABLE_RADIUS + 6) + Vector3.new(0, 3, 0)
	character:PivotTo(CFrame.lookAt(standAt, Vector3.new(ground.X, standAt.Y, ground.Z)))
end

local function onLoaded(player: Player, profile: Profile, offlineCash: number)
	local slot = World.claimPlot(player)
	if not slot then
		-- Wait for a free table (set Max Players to 8 so this never happens).
		table.insert(waitingForPlot, player)
		local notice: Types.Notice = {
			kind = "full",
			text = "All tables are taken. You'll get one when someone leaves!",
		}
		Net.event("Notice"):FireClient(player, notice)
		return
	end
	local center, outward = World.plotCenter(slot)
	local model = Instance.new("Model")
	model.Name = `Table_{player.UserId}`
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Center", center + Vector3.new(0, Config.TABLE_HEIGHT, 0))
	model:SetAttribute("Outward", outward)
	local state: TableState = {
		slot = slot,
		model = model,
		center = center + Vector3.new(0, Config.TABLE_HEIGHT, 0),
		coins = {},
		faces = {},
		busyUntil = {},
		helperNext = {},
		nextAutoFlip = os.clock() + Config.AUTO_FLIP_INTERVAL,
		combo = 0,
		lastTapAt = 0,
		yaw = FlipArc.spinYaw(outward.X, outward.Z),
	}
	model:SetAttribute("SpinYaw", state.yaw)
	states[player] = state
	buildTable(player, state, profile)
	model.Parent = World.tablesFolder()

	state.characterConn = player.CharacterAdded:Connect(function()
		task.defer(placeCharacter, player)
	end)
	placeCharacter(player)

	if offlineCash > 0 then
		Tables.offlineNotice(player, offlineCash)
	end
	PlayerData.changed(player)
end

-- "Welcome back" money from helpers who worked while you were away.
function Tables.offlineNotice(player: Player, cash: number)
	local notice: Types.Notice = {
		kind = "offline",
		text = `Your helpers earned ${Format.short(cash)} while you were away!`,
	}
	Net.event("Notice"):FireClient(player, notice)
end

-- Studio QA: make this player's next flip a given rare coin.
function Tables.forceNextRarity(player: Player, rarity: string)
	forcedRarity[player] = rarity
end

-- Rebuild a player's table after buying coins/bigger coins/a helper, or a reset.
function Tables.refresh(player: Player)
	local state = states[player]
	local profile = PlayerData.get(player)
	if state and profile then
		buildTable(player, state, profile)
	end
end

function Tables.init()
	flipRemote = Net.event("Flipped")
	Net.event("TapCoin").OnServerEvent:Connect(onTap)
	PlayerData.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = states[player]
		states[player] = nil
		forcedRarity[player] = nil
		tapLimiter:remove(player)
		local waitIndex = table.find(waitingForPlot, player)
		if waitIndex then
			table.remove(waitingForPlot, waitIndex)
		end
		if state then
			if state.characterConn then
				state.characterConn:Disconnect()
			end
			state.model:Destroy()
			World.releasePlot(player)
			-- Hand the free table to whoever is waiting.
			local nextPlayer = table.remove(waitingForPlot, 1)
			local nextProfile = nextPlayer and PlayerData.get(nextPlayer)
			if nextPlayer and nextProfile then
				task.spawn(onLoaded, nextPlayer, nextProfile, 0)
			end
		end
	end)
end

local function randomReadyCoin(state: TableState, now: number): number?
	local ready: { number } = {}
	for i = 1, #state.coins do
		if now >= state.busyUntil[i] then
			table.insert(ready, i)
		end
	end
	return if #ready > 0 then ready[rng:NextInteger(1, #ready)] else nil
end

function Tables.start()
	-- Helper guys (and the auto-flip pass) flip a random coin that's on the table.
	while true do
		task.wait(0.1)
		local now = os.clock()
		for player, state in states do
			local profile = PlayerData.get(player)
			if not profile then
				continue
			end
			for _, id in profile.team do
				local def = Economy.helperDef(id)
				local level = profile.crew[id]
				if not def or not level then
					continue
				end
				local due = state.helperNext[id]
				if not due then
					-- New on the team: first flip after one full wait.
					state.helperNext[id] = now + Economy.helperInterval(def, level)
				elseif now >= due then
					state.helperNext[id] = now + Economy.helperInterval(def, level)
					local index = randomReadyCoin(state, now)
					if index then
						flip(player, state, profile, index, true, 0, id, Economy.helperCashMult(def, level))
					end
				end
			end
			if Boosts.owns(player, "autoFlip") and now >= state.nextAutoFlip then
				state.nextAutoFlip = now + Config.AUTO_FLIP_INTERVAL
				local index = randomReadyCoin(state, now)
				if index then
					flip(player, state, profile, index, false, 0)
				end
			end
		end
	end
end

return Tables
