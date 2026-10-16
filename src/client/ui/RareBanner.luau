--!strict
-- Rare hatch banner (owner pick). The server (RareHatch) sends ("Local" | "Global", { Name, Pet, Rarity }):
--   Local  - someone in THIS server hatched a Rare+ pet: screen fireworks and a gold banner.
--   Global - a Rare+ hatch in another server (MessagingService): the same gold banner, no fireworks.
-- Banners queue (at most Config.RareHatch.QueueMax waiting, extras are dropped) and each shows for BannerSeconds.
-- Low Effects: two small bursts instead of five; Reduce Motion: no fireworks, the banner just appears. Cosmetic only.
-- A Legendary Local hatch also washes the world gold for 3 s for everyone here (HatchFx.goldSky; Lighting untouched).

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetFlair = require(Shared.PetFlair)
local SafeZones = require(Shared.SafeZones)
local UserInputService = game:GetService("UserInputService")
local UI = require(script.Parent.UI)
local Theme = require(script.Parent.Theme)
local PetStyle = require(script.Parent.PetStyle)
local State = require(script.Parent.Parent.State)
local Audio = require(script.Parent.Parent.Audio)
local HatchFx = require(script.Parent.Parent.HatchFx)
local Juice = require(script.Parent.Juice)

local RareBanner = {}

local T = UI.T
local K = Theme.Pet
local cfg = Config.RareHatch

type Item = { Kind: string, P: PetFlair.Payload }
local queue: { Item } = {}
local showing = false
local rng = Random.new()

local function settings(): { [string]: any }
	return (State.Profile and State.Profile.Settings) or {}
end

local function holder(): Frame
	local layer = UI.noticeLayer()
	local f = layer:FindFirstChild("RareBannerLayer") :: Frame?
	if f then
		return f
	end
	local nf = Instance.new("Frame")
	nf.Name = "RareBannerLayer"
	nf.BackgroundTransparency = 1
	nf.Size = UDim2.fromScale(1, 1)
	nf.ZIndex = 40
	nf.Parent = layer
	return nf
end

-- One firework: a ring of small squares flying out from a point and fading.
local function burst(parent: Frame, at: UDim2, color: Color3, count: number)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local d = rng:NextNumber(50, 90)
		local s = rng:NextInteger(6, 10)
		local dot = Instance.new("Frame")
		dot.Name = "Spark"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = at
		dot.Size = UDim2.fromOffset(s, s)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if i % 3 == 0 then K.White else color
		dot.Rotation = 45
		dot.ZIndex = 41
		dot.Parent = parent
		local goal = at + UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d + 18)
		local tw = TweenService:Create(dot, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = goal, BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
		})
		tw:Play()
		task.delay(1, function()
			dot:Destroy()
		end)
	end
end

local function fireworks(parent: Frame, rarity: string)
	local s = settings()
	if s.ReducedMotion == true then
		return
	end
	local low = s.LowEffects == true
	local bursts = if low then 2 else 5
	local per = if low then 8 else 14
	-- the rarity's colour, then the pet palette: gold, ribbon pink, the HUD cyan
	local colors = { (Config.RarityColors :: any)[rarity] or K.Gold, K.Gold, K.RibbonPink, K.CyanTop }
	for b = 1, bursts do
		task.delay((b - 1) * 0.28, function()
			if parent.Parent then
				local at = UDim2.new(rng:NextNumber(0.15, 0.85), 0, rng:NextNumber(0.12, 0.45), 0)
				burst(parent, at, colors[(b - 1) % #colors + 1], per)
			end
		end)
	end
end

local function build(parent: Frame, item: Item): Frame
	local p = item.P
	local portrait = UI.isPortrait()
	-- landscape: in the gap between the left HUD column (cash, DAILY, PLAY) and the right tiles, so no button is covered
	local w = if portrait then math.min(360, UI.Logical.X - 24) else math.min(440, UI.Logical.X * 0.5)
	local pos = if portrait then UDim2.new(0.5, 0, 0.43, 0) else UDim2.new(0.56, 0, 0, 58)
	if not portrait and SafeZones.compactLobby(UI.Logical.X, UI.Logical.Y, UserInputService.TouchEnabled) then
		-- landscape phone: the lobby buttons sit in one row at the top left (SafeZones.lobbyLayout), so the banner
		-- goes in the gap between that row and the right tiles, or under the row when the gap is too thin
		local L = SafeZones.lobbyLayout(UI.Logical.X, UI.Logical.Y, UserInputService.TouchEnabled, 172)
		local rowRight = 14 + SafeZones.rowWidth(L, 6) + 20
		local tilesLeft = UI.Logical.X - 150
		if tilesLeft - rowRight >= 240 then
			w = math.min(440, tilesLeft - rowRight)
			pos = UDim2.fromOffset(math.floor((rowRight + tilesLeft) / 2), 58)
		else
			w = math.min(440, UI.Logical.X * 0.5)
			pos = UDim2.new(0.5, 0, 0, 14 + 40 + 6 + L.CellH + 16)
		end
	end
	local banner = Instance.new("Frame")
	banner.Name = "RareBanner"
	-- portrait: below the notice stack (top) and the HUD counters; landscape: just under the top buttons
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = pos
	banner.Size = UDim2.fromOffset(w, if portrait then 78 else 66)
	-- the pet-style gold tag: glossy gold (lighter top), the tag's dark gold edge, white outlined Fredoka words
	banner.BackgroundColor3 = K.Tag
	banner.BorderSizePixel = 0
	banner.ZIndex = 42
	banner.Parent = parent
	PetStyle.round(banner, T.RadiusLg)
	PetStyle.edge(banner, K.TagEdge, 3)
	PetStyle.vgrad(banner, K.Gold:Lerp(K.White, 0.3), K.Tag)
	banner:SetAttribute("Style", "gold") -- the glint sweeps across it like a gold button
	UI.shine(banner)
	task.defer(Juice.rays, banner, K.Gold, 2.2)
	local what = if p.Rarity == "Legendary" then "LEGENDARY" elseif PetFlair.isShinyName(p.Pet) then "SHINY" else "RARE"
	local head = if item.Kind == "Local" then what .. " HATCH!" else what .. " HATCH IN ANOTHER SERVER"
	PetStyle.words(banner, head, T.Small, {
		Name = "Head", OutlineColor = K.TagEdge, OutlineThick = 2,
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), ZIndex = 43,
	})
	PetStyle.words(banner, PetFlair.bannerLine(p), T.Head, {
		Name = "Line", OutlineColor = K.TagEdge, OutlineThick = 2.6,
		TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 1, -26), ZIndex = 43,
	})
	return banner
end

-- Legendary hatch here (idea 10): one big full-screen flash for everyone in the server, white then the rainbow, and
-- the sparkle sound. Never with Reduced Motion (the gold sky and banner still show).
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 120)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 70)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 230, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 180, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
})
local function megaFlash(parent: Instance)
	Audio.play("HatchSparkle")
	if settings().ReducedMotion == true then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "LegendaryFlash"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0.15
	f.ZIndex = 40
	f.Parent = parent
	local g = Instance.new("UIGradient")
	g.Color = RAINBOW
	g.Rotation = 35
	g.Enabled = false
	g.Parent = f
	task.delay(0.12, function()
		g.Enabled = true
		f.BackgroundTransparency = 0.35
		TweenService:Create(g, TweenInfo.new(0.9), { Rotation = 215 }):Play()
		TweenService:Create(f, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end)
	task.delay(1.2, function()
		f:Destroy()
	end)
end

local function pump()
	if showing then
		return
	end
	local item = table.remove(queue, 1)
	if not item then
		return
	end
	showing = true
	local parent = holder()
	if item.Kind == "Local" then
		fireworks(parent, item.P.Rarity)
		if item.P.Rarity == "Legendary" then
			megaFlash(parent)
			HatchFx.goldSky(3) -- everyone in this server sees the world wash gold for a moment
		end
	end
	Audio.play("RarityAccent")
	local banner = build(parent, item)
	if settings().ReducedMotion ~= true then
		local goal = banner.Position
		banner.Position = goal - UDim2.fromOffset(0, 40)
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = goal }):Play()
	end
	task.delay(cfg.BannerSeconds, function()
		banner:Destroy()
		showing = false
		pump()
	end)
end

function RareBanner.show(kind: string, data: any)
	if kind ~= "Local" and kind ~= "Global" or type(data) ~= "table" then
		return
	end
	local p = PetFlair.payload(data.Name, data.Pet, data.Rarity)
	if not p then
		return
	end
	if #queue >= cfg.QueueMax then
		return
	end
	local item: Item = { Kind = kind :: string, P = p }
	table.insert(queue, item)
	pump()
end

local started = false
function RareBanner.start()
	if started then
		return
	end
	started = true
	Net.event("RareHatch").OnClientEvent:Connect(RareBanner.show)
end

return RareBanner
