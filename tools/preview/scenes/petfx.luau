-- petfx: the pet effects row (client PetFx, docs: src/client/DevPetFx.client.luau is the Studio version).
-- Nine pets, one per aura tier plus Golden and Rainbow: Common, Uncommon, Rare, Epic, Legendary, a chase pet, the
-- Void Dragon, Golden Rare, Rainbow Epic. --set fx=aura (default, auras only) | hit (each pet takes a hit, the 5th a
-- crit, the last a KO) | bounce (every pet mid happy bounce) | level (level-up blast on the Legendary).
-- Particles draw as a few static sprites in the preview (docs/PREVIEW.md); rings, orbs, pillars, flashes, the squash
-- and pop text are real parts and show as in the game.
local C = lib("ctr")
local s = C.boot({ profile = function(data)
	data.TutorialStep = 1
end })
local PetModel = C.shared("PetModel")
local Config = C.shared("Config")
local PetFx = preview.client("PetFx")
local mode = preview.args.fx or "aura"

local chase = "Raptor"
for id, sp in Config.Minerals do
	if sp.Chase and id ~= "CosmicDragon" then
		chase = id
		break
	end
end
local ROW = {
	{ Rarity = "Common", Mineral = "Raptor" },
	{ Rarity = "Uncommon", Mineral = "Raptor" },
	{ Rarity = "Rare", Mineral = "Raptor" },
	{ Rarity = "Epic", Mineral = "Raptor" },
	{ Rarity = "Legendary", Mineral = "Raptor" },
	{ Rarity = "Legendary", Mineral = chase },
	{ Rarity = "Legendary", Mineral = "CosmicDragon" },
	{ Rarity = "Rare", Mineral = "Raptor", Modifier = "Golden" },
	{ Rarity = "Epic", Mineral = "Raptor", Modifier = "Rainbow" },
}
local root = s.me.Character.HumanoidRootPart
local base = root.CFrame * CFrame.new(0, -2.8, -16)
local folder = Instance.new("Folder")
folder.Name = "PetFxRow"
folder.Parent = workspace
local pets = {}
for i, spec in ROW do
	local m = PetModel.build(spec, { Scale = 1, Lod = true, NoLight = true })
	local ground = (base * CFrame.new((i - 5) * 5, 0, 0)).Position
	m:PivotTo(CFrame.lookAt(ground, ground - base.LookVector))
	m.Parent = folder
	local fx = PetFx.attach(m, spec, 1, folder)
	table.insert(pets, { M = m, Fx = fx, G = ground })
	print(string.format("PETFX %d %s %s %s tier=%d orbs=%d pillar=%s", i, spec.Rarity, spec.Mineral, tostring(spec.Modifier),
		fx.Look.Tier, #fx.Orbs, tostring(fx.Pillar ~= nil)))
end
local cam = workspace.CurrentCamera
local function tickAll(t)
	for _, p in pets do
		PetFx.update(p.Fx, p.G, 0, 0, false, t, cam.CFrame.Position, 0, true)
	end
end
for k = 1, 20 do
	tickAll(k * 0.05)
	preview.advance(0.05)
end
-- (the follow camera is not simulated: place ours before the bursts, PetFx skips bursts far from the camera)
C.cameraAt(base.Position + Vector3.new(0, 1.2, 0), -base.LookVector * 15 + Vector3.new(0, 4.5, 0), 80)
if mode == "hit" then
	for i, p in pets do
		if i == #pets then
			PetFx.ko(p.M)
		else
			PetFx.hit(p.M, { Element = ({ "Fire", "Ice", "Nature", "Storm", "Earth", "Cosmic" })[(i - 1) % 6 + 1], Crit = i == 5, Damage = 12 })
		end
	end
	preview.advance(0.12)
elseif mode == "bounce" then
	for _, p in pets do
		PetFx.squash(p.M)
	end
	preview.advance(0.12) -- landing squash of the first hop is near 0.3 s; 0.12 s = stretching up
elseif mode == "level" then
	PetFx.levelUp(pets[5].M, 7)
	preview.advance(0.15)
end
tickAll(1.2)
-- the follow camera moves during advance(): place ours last
for _, d in s.me.Character:GetDescendants() do -- keep the player out of the shot
	if d:IsA("BasePart") then
		d.Transparency = 1
	end
end
C.cameraAt(base.Position + Vector3.new(0, 1.2, 0), -base.LookVector * 15 + Vector3.new(0, 4.5, 0), 80)
