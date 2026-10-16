--!strict
-- Park stalls (dino-jungle pet park, owner picks 2026-10-10): the counters around the open spawn plaza, built from
-- the uploaded lodge kit (ReplicatedStorage.Assets.Kit via MeshService) where it fits and Parts elsewhere. The old
-- Prospector Lodge hall (building, hunt bays, wall pockets, chandelier) is gone; LobbyBuilder / ParkBuilder build the
-- park around these stalls. Each builder takes a WORLD frame `cf` whose kit front (-Z) faces the plaza.
--
-- What each destination keeps (contracts grepped before this change, docs/lodge/INTEGRATION.md):
--   UPGRADES    Part `Counter` + prompt (Panel "Shop"); model CT_Rocks_UpgradePedestal with PreviewAnchor /
--               PreviewLabel on the counter (src/client/UpgradePreview.luau draws the selected item, per player)
--   PET BOOK    Part `Counter` + prompt (Panel "Collection"); three decorative EXAMPLE pets (tagged Decorative, no Id,
--               in no profile) on the counter pedestals
--   SELL CANDY  Model attribute Hopper, part `Body` with ProximityPrompt `SellPrompt` (attribute Sell) = the one
--               EconomyService sell endpoint
--   EGG SHOP    Part `Counter` with a DISABLED prompt (attribute ShopHook "EggShop"): what it sells is still being
--               decided with the owner, so nothing is wired (no price, no purchase); an egg display shelf inside
--   BOARDS      BoardMounts/Mount_<id> (attribute Bare): LobbyBoards puts the live SurfaceGui rows of
--               LeaderboardService on them; the headings are fitted signs
-- Kit meshes never collide (MeshService); every solid thing has an invisible box collider. Every kit asset has a
-- Part stand-in (REPLACE marker) used when its mesh did not load.

local Workspace = game:GetService("Workspace")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local GeodeModel = require(Shared.GeodeModel)
local MeshCatalog = require(Shared.MeshCatalog)
local MapNames = require(Shared.MapNames)
local Kit = require(script.Parent.KitParts)
local KitPlace = require(script.Parent.KitPlace)

local part, deco, model = Kit.part, Kit.deco, Kit.model
local M = Enum.Material

local LodgeBuilder = {}

LodgeBuilder.FLOOR_Y = Config.Lodge.FloorY -- the park ground top (world y)
LodgeBuilder.Interior = Config.Lodge -- the walkable park box (lobby camera box, spawn check)

-- Palette: warm timber, stone, the park's teal and orange accents
local C = {
	Wood = Color3.fromRGB(176, 112, 64),
	WoodDark = Color3.fromRGB(116, 74, 44),
	WoodLight = Color3.fromRGB(214, 156, 98),
	Plaster = Color3.fromRGB(236, 220, 190),
	Stone = Color3.fromRGB(176, 164, 144),
	Charcoal = Color3.fromRGB(70, 60, 56),
	Gold = Color3.fromRGB(250, 204, 84),
	AwningCream = Color3.fromRGB(246, 230, 196),
	AwningOrange = Color3.fromRGB(236, 128, 44),
	AwningTeal = Color3.fromRGB(32, 150, 140),
	Ink = Color3.fromRGB(255, 240, 208),
	InkDark = Color3.fromRGB(44, 46, 52),
	LightWarm = Color3.fromRGB(255, 200, 140),
	LightDay = Color3.fromRGB(255, 246, 232),
	Leaf = Color3.fromRGB(70, 132, 48),
}

local function catalogAttach(name: string, point: string): Vector3?
	local e = (MeshCatalog :: any)[name]
	local p = e and e.Attach and e.Attach[point]
	if p then
		return Vector3.new(p[1], p[2], p[3])
	end
	return nil
end

-- Test hook: the `lodge-fallback` preview check sets this Workspace attribute before boot to build every Part stand-in.
local function kitAllowed(): boolean
	return Workspace:GetAttribute("LodgeFallbackTest") ~= true
end

-- One invisible collider box in an asset's frame (`cf` = the asset's placed frame, offset / size in its model space).
local function collider(parent: Instance, cf: CFrame, size: Vector3, offset: Vector3, name: string?): Part
	return KitPlace.blocker(parent, cf * CFrame.new(offset), size, name or "Collider")
end

-- A generic Part stand-in from the catalog bounds and first piece colour (REPLACE: the kit mesh goes here).
local function boundsBox(parent: Instance, name: string, cf: CFrame, color: Color3?): BasePart?
	local e = (MeshCatalog :: any)[name]
	if not e then
		return nil
	end
	local lo, hi = e.Bounds[1], e.Bounds[2]
	local size = Vector3.new(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
	local centre = Vector3.new((hi[1] + lo[1]) / 2, (hi[2] + lo[2]) / 2, (hi[3] + lo[3]) / 2)
	local p0 = e.Pieces[1]
	local mat = (Enum.Material :: any)[p0.Material] or M.SmoothPlastic
	return deco(part(parent, "StandIn", size, cf * CFrame.new(centre), color or p0.Color, mat))
end

-- Places kit asset `name` at `cf` in its own model (name `id`). The kit clone when loaded, else `fallback(m, cf)`
-- (or a bounds box). Returns the model and whether the kit mesh is used.
local function asset(parent: Instance, id: string, name: string, cf: CFrame, fallback: ((Model, CFrame) -> ())?): (Model, boolean)
	local m = if kitAllowed() then KitPlace.place(parent, name, cf, 1, "CT_Rocks_" .. id) else nil
	if m then
		return m, true
	end
	local s = model(parent, "CT_Rocks_" .. id)
	s:SetAttribute("StandIn", name) -- REPLACE: kit mesh `name` did not load
	if fallback then
		fallback(s, cf)
	else
		boundsBox(s, name, cf)
	end
	return s, false
end
LodgeBuilder.asset = asset

-- Items resting on an assembly share a MountGroup (the placement audit treats them as mounted, not clipping).
local function mountGroup(m: Instance, group: string)
	m:SetAttribute("MountGroup", group)
end

-- Fitted sign text on a kit face. `faceCF` = the asset frame, `attach` = the face's front centre in model space; kit
-- faces look toward model -Z. The text part stands 0.05 studs in front of the face and is turned half a turn so its
-- SurfaceGui (Face = Back = +Z) looks out of the face. Landmark and Heading signs: bold white with a black outline.
local function faceText(parent: Instance, name: string, faceCF: CFrame, attach: Vector3, W: number, H: number, text: string, preset: string, ink: Color3?, backing: Color3?): (Part, TextLabel)
	local cf = faceCF * CFrame.new(attach + Vector3.new(0, 0, -0.05)) * CFrame.Angles(0, math.pi, 0)
	local landmark = preset == "Landmark" or preset == "Heading"
	local p, t = KitPlace.signText(parent, name, cf, W, H, text, preset, ink or C.Ink, backing, landmark)
	return p, t
end

-- A small invisible light anchor (the kit lantern is the fixture).
local function lightAt(parent: Instance, pos: Vector3, brightness: number, range: number, color: Color3?): PointLight
	local a = deco(part(parent, "Light", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), C.Charcoal, M.SmoothPlastic))
	a.Transparency = 1
	a.CastShadow = false
	return Kit.light(a, "PointLight", color or C.LightWarm, brightness, range) :: PointLight
end

local function prompt(p: BasePart, action: string, object: string, panel: string, range: number): ProximityPrompt
	local pp = Kit.prompt(p, action, object, panel, range)
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	return pp
end

-- Stall stand-in (REPLACE): counter, back panel, striped awning slab, sign board.
local function stallStandIn(stripe: Color3): (Model, CFrame) -> ()
	return function(s: Model, f: CFrame)
		part(s, "CounterBody", Vector3.new(24, 3.8, 5.5), f * CFrame.new(0, 1.9, -1.25), C.Wood, M.WoodPlanks).CanCollide = false
		part(s, "Countertop", Vector3.new(24.4, 0.25, 5.9), f * CFrame.new(0, 3.9, -1.25), C.WoodLight, M.Wood).CanCollide = false
		part(s, "BackPanel", Vector3.new(24, 12.7, 0.6), f * CFrame.new(0, 6.35, 3.6), C.Plaster, M.SmoothPlastic).CanCollide = false
		for i = 0, 10 do
			local p = part(s, "Awning", Vector3.new(25 / 11, 0.3, 7.2), f * CFrame.new(-12.5 + (i + 0.5) * 25 / 11, 11.5, 0.4) * CFrame.Angles(math.rad(-16), 0, 0), if i % 2 == 0 then stripe else C.AwningCream, M.Fabric)
			deco(p)
		end
		part(s, "SignFrame", Vector3.new(12, 3, 0.3), f * CFrame.new(0, 11.25, -4.0), C.WoodDark, M.Wood).CanCollide = false
	end
end

-- Kit awnings come in the lodge's red / purple; the park tones them to its orange / teal.
local function toneAwning(m: Model, stripe: Color3)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and (string.find(d.Name, "Awning", 1, true) or string.find(d.Name, "Canopy", 1, true)) then
			local h, sat, v = d.Color:ToHSV()
			if sat > 0.25 and v > 0.4 and (h < 0.08 or h > 0.7) then
				d.Color = stripe
			end
		end
	end
end

-- UPGRADES: counter -> Shop panel; the preview pedestal on the counter; cashbox, basket, lantern, runner.
function LodgeBuilder.buildUpgrades(root: Instance, lights: Instance, cf: CFrame)
	local g = Kit.folder(root, "CT_Rocks_Upgrades")
	local stall = asset(g, "Upgrades_Stall", "Lodge_UpgradesStall", cf, stallStandIn(C.AwningOrange))
	toneAwning(stall, C.AwningOrange)
	mountGroup(stall, "Upgrades")
	KitPlace.cameraIgnore(stall)
	local counter = collider(g, cf, Vector3.new(24, 4, 5.5), Vector3.new(0, 2, -1.25), "Counter")
	counter.CanQuery = true
	prompt(counter, "Browse equipment", "Upgrades", "Shop", 12)
	collider(g, cf, Vector3.new(24, 12.7, 1.2), Vector3.new(0, 6.35, 3.6), "StallBack")
	faceText(stall, "Title", cf, catalogAttach("Lodge_UpgradesStall", "SignFace") or Vector3.new(0, 11.25, -4.16), 11.5, 2.5, "UPGRADES", "Landmark")
	for _, d in { { "Upgrades_Cashbox", "Lodge_Cashbox", "Cashbox" }, { "Upgrades_Basket", "Lodge_RockBasket", "Basket" }, { "Upgrades_Lantern", "Lodge_Lantern", "Lantern" }, { "Upgrade_Runner", "Lodge_RunnerRug", "Runner" } } do
		local p = catalogAttach("Lodge_UpgradesStall", d[3])
		if p then
			local m = asset(g, d[1], d[2], cf * CFrame.new(p) + (if d[3] == "Runner" then Vector3.new(0, 0.03, 0) else Vector3.zero))
			mountGroup(m, "Upgrades")
			KitPlace.cameraIgnore(m)
			if d[3] == "Lantern" then
				lightAt(lights, (cf * CFrame.new(p + Vector3.new(0, 0.66, 0))).Position, 0.8, 12)
			end
		end
	end
	-- The ONE preview pedestal on the counter (UpgradePreview shows the selected tool on PreviewAnchor, client-only).
	local pm = model(g, "CT_Rocks_UpgradePedestal")
	pm:SetAttribute("UpgradePedestal", true)
	mountGroup(pm, "Upgrades")
	local pcf = cf * CFrame.new(5.2, 4, -1.7)
	local ped = asset(pm, "UpgradePreviewStand", "Lodge_SpecimenPedestal", pcf)
	mountGroup(ped, "Upgrades")
	local top = catalogAttach("Lodge_SpecimenPedestal", "Specimen") or Vector3.new(0, 1.2, 0)
	local anchor = deco(part(pm, "PreviewAnchor", Vector3.new(0.4, 0.1, 0.4), pcf * CFrame.new(top + Vector3.new(0, 0.05, 0)), C.Gold, M.SmoothPlastic))
	anchor.Transparency = 1
	anchor:SetAttribute("PreviewAnchor", true)
	anchor:SetAttribute("PreviewHeight", 2.6) -- normalised model height the client scales to (studs)
	local label = KitPlace.signText(pm, "PreviewLabel", pcf * CFrame.new(0, 0.6, -1.4) * CFrame.Angles(0, math.pi, 0), 2.3, 0.45, "PREVIEW", "Plaque", C.InkDark, C.AwningCream)
	label.Name = "PreviewLabel"
	KitPlace.cameraIgnore(pm)
end

-- PET BOOK: counter -> Collection panel; three EXAMPLE pets on the pedestals.
local EXAMPLES: { { any } } = { { "Raptor", 11 }, { "Griffin", 35 }, { "Phoenix", 23 } }

local function examplePet(parent: Instance, cf: CFrame, i: number): Model?
	local ex = EXAMPLES[i]
	local ok, g = pcall(GeodeModel.example, ex[1], ex[2], { Scale = 0.7, Lod = true, NoLight = true })
	if not ok or not g then
		return nil
	end
	g.Name = "CT_Rocks_DisplayExample"
	g:SetAttribute("Decorative", true) -- made up: no Id, in no profile, never a reward
	g:PivotTo(cf) -- pets face -Z, the kit front: toward the plaza
	g.Parent = parent
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	KitPlace.cameraIgnore(g)
	return g
end

function LodgeBuilder.buildCollection(root: Instance, lights: Instance, cf: CFrame)
	local g = Kit.folder(root, "CT_Rocks_Collection")
	local stall = asset(g, "Collection_Stall", "Lodge_CollectionStall", cf, stallStandIn(C.AwningTeal))
	toneAwning(stall, C.AwningTeal)
	mountGroup(stall, "Collection")
	KitPlace.cameraIgnore(stall)
	local counter = collider(g, cf, Vector3.new(24, 4, 5.5), Vector3.new(0, 2, -1.25), "Counter")
	counter.CanQuery = true
	prompt(counter, "Open Pet Book", "Pet Book", "Collection", 12)
	collider(g, cf, Vector3.new(24, 12.7, 1.2), Vector3.new(0, 6.35, 3.6), "StallBack")
	faceText(stall, "Title", cf, catalogAttach("Lodge_CollectionStall", "SignFace") or Vector3.new(0, 11.25, -4.16), 11.5, 2.5, "PET BOOK", "Landmark")
	faceText(g, "ExamplesPlaque", cf, Vector3.new(0, 8.55, 2.95), 7.0, 0.8, "EXAMPLE PETS", "Plaque", C.Ink, C.WoodDark)
	for _, d in stall:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Glass" then
			d.Transparency = 0.86
			d.Color = Color3.fromRGB(232, 240, 242)
		end
	end
	for i = 1, 3 do
		local p = catalogAttach("Lodge_CollectionStall", "Specimen" .. i)
		if p then
			local pedCF = cf * CFrame.new(p)
			local ped = asset(g, "Collection_Pedestal" .. i, "Lodge_SpecimenPedestal", pedCF)
			mountGroup(ped, "Collection")
			KitPlace.cameraIgnore(ped)
			local top = catalogAttach("Lodge_SpecimenPedestal", "Specimen") or Vector3.new(0, 1.2, 0)
			local pet = examplePet(g, pedCF * CFrame.new(top), i)
			if pet then
				mountGroup(pet, "Collection")
			end
		end
	end
	local lp = catalogAttach("Lodge_CollectionStall", "Lantern")
	if lp then
		local m = asset(g, "Collection_Lantern", "Lodge_Lantern", cf * CFrame.new(lp))
		mountGroup(m, "Collection")
		KitPlace.cameraIgnore(m)
		lightAt(lights, (cf * CFrame.new(lp + Vector3.new(0, 0.66, 0))).Position, 0.8, 12)
	end
end

-- SELL CANDY: the kit counter is the seller (same Hopper / Body / SellPrompt contract as before).
function LodgeBuilder.buildSeller(root: Instance, lights: Instance, cf: CFrame)
	local m = asset(root, "SellHopper", "Lodge_RubbleSell", cf, function(s, f)
		part(s, "Counter", Vector3.new(7, 3.6, 3), f * CFrame.new(0, 1.8, -0.55), C.Wood, M.WoodPlanks).CanCollide = false
		part(s, "Back", Vector3.new(7, 10, 0.8), f * CFrame.new(0, 5, 1.6), C.WoodDark, M.Wood).CanCollide = false
		part(s, "SignBoard", Vector3.new(5.6, 2.6, 0.3), f * CFrame.new(0, 8.2, 1.2), C.WoodDark, M.Wood).CanCollide = false
	end)
	m:SetAttribute("Hopper", true)
	mountGroup(m, "Seller")
	KitPlace.cameraIgnore(m)
	local body = collider(m, cf, Vector3.new(7, 3.6, 3), Vector3.new(0, 1.8, -0.55), "Body")
	collider(m, cf, Vector3.new(7, 10, 0.8), Vector3.new(0, 5, 1.6), "SellerBack")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "SellPrompt"
	pp.ActionText = "Sell Candy"
	pp.ObjectText = "Candy stand"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	pp.UIOffset = Vector2.new(0, 30)
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pp:SetAttribute("Sell", true)
	pp.Parent = body
	faceText(m, "SellSign", cf, catalogAttach("Lodge_RubbleSell", "SignFace") or Vector3.new(0, 8.2, 1.16), 5.3, 2.3, "SELL CANDY", "Landmark")
	for _, d in { { "Rubble_Basket", "Lodge_RockBasket", "Basket" }, { "Rubble_Lantern", "Lodge_Lantern", "Lantern" } } do
		local p = catalogAttach("Lodge_RubbleSell", d[3])
		if p then
			local k = asset(root, d[1], d[2], cf * CFrame.new(p))
			mountGroup(k, "Seller")
			KitPlace.cameraIgnore(k)
			if d[3] == "Lantern" then
				lightAt(lights, (cf * CFrame.new(p + Vector3.new(0, 0.66, 0))).Position, 0.7, 11)
			end
		end
	end
	-- a striped jungle awning on two poles over the small counter, so it reads as a stall from the plaza
	local aw = model(root, "CT_Rocks_SellAwning")
	mountGroup(aw, "Seller")
	for _, x in { -4.4, 4.4 } do
		part(aw, "Pole", Vector3.new(0.5, 9, 0.5), cf * CFrame.new(x, 4.5, -3.4), C.WoodDark, M.Wood)
	end
	for i = 0, 5 do
		deco(part(aw, "Awning", Vector3.new(9.6 / 6, 0.25, 5), cf * CFrame.new(-4.8 + (i + 0.5) * 1.6, 9.1, -1.2) * CFrame.Angles(math.rad(-14), 0, 0), if i % 2 == 0 then C.AwningOrange else C.AwningCream, M.Fabric))
	end
	KitPlace.cameraIgnore(aw)
end

-- EGG SHOP: a timber jungle hut at the north end of the main path (Parts, REPLACE: real mesh) with an egg display
-- shelf behind the counter (procedural eggs, REPLACE: real egg meshes). What it sells is still being decided with the
-- owner, so NOTHING is wired: the counter carries a DISABLED ProximityPrompt (attribute ShopHook = "EggShop") for the
-- shop code to enable later, no price, no purchase, and a COMING SOON plaque says so.
local EGG_TINTS = {
	Color3.fromRGB(255, 214, 64), Color3.fromRGB(80, 190, 255), Color3.fromRGB(255, 110, 206), Color3.fromRGB(110, 232, 110),
	Color3.fromRGB(255, 140, 50), Color3.fromRGB(170, 120, 255),
}
local function egg(parent: Instance, cf: CFrame, h: number, tint: Color3)
	local body = Instance.new("Part")
	body.Name = "Egg" -- REPLACE: real egg mesh
	body.Size = Vector3.new(h * 0.76, h, h * 0.76)
	body.CFrame = cf * CFrame.new(0, h / 2, 0)
	body.Color = tint
	body.Material = M.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.Sphere
	sm.Parent = body
	body.Parent = parent
	local spot = deco(part(parent, "EggSpot", Vector3.new(h * 0.3, h * 0.24, 0.1), cf * CFrame.new(0, h * 0.62, -h * 0.37), tint:Lerp(Color3.new(1, 1, 1), 0.55), M.SmoothPlastic))
	spot.CastShadow = false
end

function LodgeBuilder.buildEggShop(root: Instance, lights: Instance, cf: CFrame)
	local g = model(root, MapNames.EggShop)
	mountGroup(g, "EggShop")
	local W, D, H = 18, 10, 8.5
	-- the owner's Meshy hut (ServerStorage.MeshyAssets.MeshyEggShop) when present: it replaces the deck, walls, posts
	-- and roof (invisible blockers keep the walls solid); the shelf, counter, eggs and sign below stay either way
	local hut = KitPlace.meshy("MeshyEggShop", cf * CFrame.new(0, (H + 5.5) / 2, 0.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(W + 1, H + 5.5, D + 3.6))
	if hut then
		hut.Name = "HutMesh"
		hut.Parent = g
		KitPlace.blocker(g, cf * CFrame.new(0, 0.6 + H / 2, D / 2 + 0.7), Vector3.new(W, H, 0.6), "WallBackBlock")
		for _, sx in { -1, 1 } do
			KitPlace.blocker(g, cf * CFrame.new(sx * (W / 2 - 0.3), 0.6 + H / 2, 0.7), Vector3.new(0.6, H, D), "WallSideBlock")
		end
	else
	-- floor deck, back and side walls (solid), corner posts, a pitched roof with an orange ridge
	part(g, "Deck", Vector3.new(W + 1, 0.6, D + 1), cf * CFrame.new(0, 0.3, 0.5), C.WoodDark, M.WoodPlanks)
	part(g, "WallBack", Vector3.new(W, H, 0.6), cf * CFrame.new(0, 0.6 + H / 2, D / 2 + 0.7), C.Wood, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		part(g, "WallSide", Vector3.new(0.6, H, D), cf * CFrame.new(sx * (W / 2 - 0.3), 0.6 + H / 2, 0.7), C.Wood, M.WoodPlanks)
		for _, z in { -D / 2 + 0.7, D / 2 + 0.7 } do
			part(g, "Post", Vector3.new(1.1, H + 1.4, 1.1), cf * CFrame.new(sx * (W / 2), 0.6 + (H + 1.4) / 2, z), C.WoodDark, M.Wood)
		end
		deco(part(g, "Roof", Vector3.new(W / 2 + 1.8, 0.7, D + 3.6), cf * CFrame.new(sx * (W / 4 + 0.2), H + 2.9, 0.5) * CFrame.Angles(0, 0, -sx * math.rad(24)), C.AwningTeal, M.WoodPlanks))
	end
	deco(part(g, "Ridge", Vector3.new(1.3, 0.9, D + 3.8), cf * CFrame.new(0, H + 4.9, 0.5), C.AwningOrange, M.Wood))
	end
	-- the egg display shelf on the back wall: three tiers of procedural eggs (REPLACE: real egg meshes)
	for tier = 0, 2 do
		local y = 0.6 + 1.6 + tier * 2.0
		part(g, "Shelf", Vector3.new(W - 3, 0.3, 1.6), cf * CFrame.new(0, y, D / 2 - 0.4), C.WoodLight, M.Wood).CanCollide = false
		for k = 0, 5 do
			local x = -6.25 + k * 2.5
			egg(g, cf * CFrame.new(x, y + 0.15, D / 2 - 0.4), 1.25 + ((k + tier) % 2) * 0.2, EGG_TINTS[(k + tier * 2) % #EGG_TINTS + 1])
		end
	end
	-- the counter across the open front (the hook part for the future shop) and a big nest of eggs on it
	part(g, "CounterBody", Vector3.new(W - 4, 3.4, 1.8), cf * CFrame.new(0, 0.6 + 1.7, -D / 2 + 1.4), C.WoodLight, M.WoodPlanks).CanCollide = false
	local counter = collider(g, cf, Vector3.new(W - 4, 3.9, 2), Vector3.new(0, 0.6 + 1.95, -D / 2 + 1.4), "Counter")
	counter.CanQuery = true
	local pp = Kit.prompt(counter, "Egg Shop", "Coming soon", "", 12)
	pp.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	pp.Enabled = false -- nothing is for sale yet: the shop code enables this once the owner decides what it sells
	pp:SetAttribute("ShopHook", "EggShop")
	deco(part(g, "Countertop", Vector3.new(W - 3.6, 0.3, 2.3), cf * CFrame.new(0, 0.6 + 3.55, -D / 2 + 1.4), C.WoodDark, M.Wood))
	for k = 0, 2 do
		egg(g, cf * CFrame.new(-2.2 + k * 2.2, 0.6 + 3.7, -D / 2 + 1.4), 1.5, EGG_TINTS[k * 2 + 1])
	end
	-- the sign over the front and a COMING SOON plaque on the counter front
	local signCF = cf * CFrame.new(0, H + 2.4, -D / 2 - 1.3) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	KitPlace.signBoard(g, "ShopSign", signCF, 10, 2.4, "EGG SHOP", "Landmark", { Face = C.WoodDark, Frame = C.Wood, Trim = Color3.fromRGB(250, 204, 84), Outline = true })
	KitPlace.signText(g, "SoonPlaque", cf * CFrame.new(0, 0.6 + 1.9, -D / 2 + 0.45) * CFrame.Angles(0, math.pi, 0), 6, 1, "COMING SOON", "Plaque", C.Ink, C.WoodDark)
	lightAt(lights, (cf * CFrame.new(0, H - 1, 0.5)).Position, 0.9, 18)
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Roof" or d.Name == "Ridge") then
			d:SetAttribute("CameraIgnore", true)
		end
	end
end

-- BOARDS: kit frames; the live rows are LobbyBoards' SurfaceGui on Mount_<id>, the heading a fitted sign.
local function boardStandIn(s: Model, f: CFrame)
	part(s, "Frame", Vector3.new(13.4, 13.2, 1.2), f * CFrame.new(0, 8.9, 0.4), C.Wood, M.Wood).CanCollide = false
	part(s, "BoardFace", Vector3.new(11.5, 11.1, 0.2), f * CFrame.new(0, 9.05, -0.2), C.Charcoal, M.SmoothPlastic).CanCollide = false
	for _, x in { -6, 6 } do
		part(s, "Foot", Vector3.new(0.8, 3.4, 2.4), f * CFrame.new(x, 1.7, 0.2), C.WoodDark, M.Wood).CanCollide = false
	end
end

local HEAD_H = 2.0 -- heading band height (studs) at the top of each board face

-- boards = { { Id, Heading, CFrame (kit front -Z toward the viewer) } }; BoardMounts goes straight under `root`.
function LodgeBuilder.buildBoards(root: Instance, lights: Instance, boards: { { any } })
	local g = Kit.folder(root, "CT_Rocks_Boards")
	local mounts = Kit.folder(root, "BoardMounts")
	for _, b in boards do
		local id, heading, cf = b[1] :: string, b[2] :: string, b[3] :: CFrame
		local m = asset(g, "Leaderboard_" .. id, "Lodge_Leaderboard", cf, boardStandIn)
		mountGroup(m, "Board" .. id)
		KitPlace.cameraIgnore(m)
		collider(g, cf, Vector3.new(13.2, 15, 2.5), Vector3.new(0, 7.5, 0.15), "BoardBody")
		local face = catalogAttach("Lodge_Leaderboard", "BoardFace") or Vector3.new(0, 9.05, -0.1)
		local headTop = face.Y + 11.1 / 2 - 0.15
		local headY = headTop - HEAD_H / 2
		faceText(m, "Heading", cf, Vector3.new(0, headY, face.Z), 10.8, HEAD_H, heading, "Heading")
		local rowsTop = headTop - HEAD_H - 0.1
		local rowsBottom = face.Y - 11.1 / 2 + 0.25
		local mount = part(mounts, "Mount_" .. id, Vector3.new(11.0, rowsTop - rowsBottom, 0.05), cf * CFrame.new(0, (rowsTop + rowsBottom) / 2, face.Z - 0.06) * CFrame.Angles(0, math.pi, 0), C.Charcoal, M.SmoothPlastic)
		mount.Transparency = 1
		mount.CanCollide = false
		mount.CanQuery = false
		mount.CanTouch = false
		mount.CastShadow = false
		mount:SetAttribute("Bare", true) -- LobbyBoards: draw the rows straight onto this mount (dark theme, five rows)
		local tp = catalogAttach("Lodge_Leaderboard", "Trophy")
		if tp then
			local t = asset(g, id .. "_Trophy", "Lodge_TrophyEmblem", cf * CFrame.new(tp))
			mountGroup(t, "Board" .. id)
			KitPlace.cameraIgnore(t)
		end
	end
end

return LodgeBuilder
