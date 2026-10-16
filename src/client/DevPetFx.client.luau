--!strict
-- Studio-only pet effects showcase (owner / screenshot tool; returns at once outside Studio, nothing is sent anywhere).
-- Chat commands:
--   /petfx    a row of nine pets, one per aura tier (Common, Uncommon, Rare, Epic, Legendary, a chase pet, the Void
--             Dragon) plus a Golden and a Rainbow pet. The camera frames the whole row for the auras, then moves in
--             on the Void Dragon for each effect: happy bounce, hit, crit, level up, KO.
--   /fightfx  two pets face each other and play every big fight moment (FightFx): hit, type advantage, crit,
--             special, level up, KO with the winner showcase.
-- The camera is held for the whole show (like the hatch show) and given back at the end. Each step holds about two
-- seconds and is printed to Output as "[DevPetFx] step N: name" and set on Workspace attribute DevFxStep, so a
-- screenshot helper knows what is on screen. The pets live in Workspace.DevPetFx (a Model with a PrimaryPart at the
-- middle of the row), removed when the show ends.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PetModel = require(Shared.PetModel)
local PetFxRules = require(Shared.PetFxRules)
local PetFx = require(script.Parent:WaitForChild("PetFx"))
local FightFx = require(script.Parent:WaitForChild("FightFx"))
local CameraMode = require(script.Parent:WaitForChild("CameraMode"))

local player = Players.LocalPlayer
local STEP = 2.2 -- seconds each step holds for screenshots

local function chasePet(): string
	for id, sp in Config.Minerals :: { [string]: any } do
		if sp.Chase == true and id ~= "CosmicDragon" then
			return id
		end
	end
	return "Raptor"
end

local ROW = {
	{ Rarity = "Common", Mineral = "Raptor" },
	{ Rarity = "Uncommon", Mineral = "Raptor" },
	{ Rarity = "Rare", Mineral = "Raptor" },
	{ Rarity = "Epic", Mineral = "Raptor" },
	{ Rarity = "Legendary", Mineral = "Raptor" },
	{ Rarity = "Legendary", Mineral = chasePet() },
	{ Rarity = "Legendary", Mineral = "CosmicDragon" },
	{ Rarity = "Rare", Mineral = "Raptor", Modifier = "Golden" },
	{ Rarity = "Epic", Mineral = "Raptor", Modifier = "Rainbow" },
}

type Pet = { Model: Model, Fx: any, Ground: Vector3, Spec: { [string]: any } }
local busy = false

local function step(n: number, name: string)
	print(string.format("[DevPetFx] step %d: %s", n, name))
	Workspace:SetAttribute("DevFxStep", name)
end

-- Builds the show: a Model in Workspace with an anchor PrimaryPart, pets placed along `places`, PetFx attached and
-- updated every frame. Returns the pets, the model and a cleanup function.
local function build(specs: { { [string]: any } }, places: { CFrame }): ({ Pet }, Model, () -> ())
	local model = Instance.new("Model")
	model.Name = "DevPetFx"
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	local mid = Vector3.zero
	for _, cf in places do
		mid += cf.Position
	end
	anchor.CFrame = CFrame.new(mid / #places)
	anchor.Parent = model
	model.PrimaryPart = anchor
	model.Parent = Workspace
	local pets: { Pet } = {}
	for i, spec in specs do
		local ok, m = pcall(PetModel.build, spec, { Scale = 1, Lod = true, NoLight = true })
		if ok and m then
			m:PivotTo(places[i])
			m.Parent = model
			local okF, fx = pcall(PetFx.attach, m, spec, 1, model)
			table.insert(pets, { Model = m, Fx = if okF then fx else nil, Ground = places[i].Position, Spec = spec })
		end
	end
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for _, p in pets do
			if p.Fx then
				PetFx.update(p.Fx, p.Ground, 0, 0, false, t, camPos, 0, math.floor(t / 3) % 2 == 0)
			end
		end
	end)
	return pets, model, function()
		conn:Disconnect()
		for _, p in pets do
			if p.Fx then
				PetFx.destroy(p.Fx)
			end
		end
		model:Destroy()
	end
end

local function centre(p: Pet): Vector3
	local h = p.Model:GetAttribute("Height")
	return p.Ground + Vector3.new(0, (if type(h) == "number" then h else 2) * 0.5, 0)
end

-- Holds the camera for the show; returns a function that moves it and one that gives it back.
local function holdCamera(): ((Vector3, Vector3, number?) -> (), () -> ())
	local cam = Workspace.CurrentCamera
	local from, fov = cam.CFrame, cam.FieldOfView
	CameraMode.cinematic("DevPetFx", true)
	cam:SetAttribute("CT_Cinematic", true)
	cam.CameraType = Enum.CameraType.Scriptable
	local function aim(eye: Vector3, focus: Vector3, f: number?)
		TweenService:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			CFrame = CFrame.lookAt(eye, focus), FieldOfView = f or 60,
		}):Play()
		task.wait(0.65)
	end
	local function release()
		cam.CFrame = from
		cam.FieldOfView = fov
		cam:SetAttribute("CT_Cinematic", nil)
		cam.CameraType = Enum.CameraType.Custom
		CameraMode.cinematic("DevPetFx", false)
		Workspace:SetAttribute("DevFxStep", nil)
	end
	return aim, release
end

-- The row stands on the ground in front of the player, facing them.
local function frontOf(root: BasePart, dist: number): (CFrame, Vector3)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local ray = Workspace:Raycast(root.Position + look * dist + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0))
	local groundY = if ray then ray.Position.Y else root.Position.Y - 3
	local c = Vector3.new(root.Position.X, groundY, root.Position.Z) + look * dist
	return CFrame.lookAt(c, c - look), look
end

local function petShow(root: BasePart)
	local base, look = frontOf(root, 16)
	local places: { CFrame } = {}
	for i = 1, #ROW do
		places[i] = base * CFrame.new((i - (#ROW + 1) / 2) * 5, 0, 0)
	end
	local pets, _, cleanup = build(ROW, places)
	local aim, release = holdCamera()
	local ok, err = pcall(function()
		local mid = base.Position + Vector3.new(0, 1.5, 0)
		aim(mid - look * 24 + Vector3.new(0, 7, 0), mid, 70)
		step(1, "auras: all tiers")
		task.wait(STEP + 1)
		local star = pets[7] or pets[#pets] -- the Void Dragon
		local c = centre(star)
		aim(c - look * 11 + Vector3.new(2, 3, 0), c, 60)
		step(2, "aura close-up: Void Dragon")
		task.wait(STEP)
		step(3, "happy bounce")
		PetFx.happy(star.Model)
		task.wait(0.25)
		task.wait(STEP)
		step(4, "hit")
		PetFx.hit(star.Model, { Element = "Fire", Damage = 12 })
		task.wait(STEP)
		step(5, "crit")
		PetFx.hit(star.Model, { Element = "Storm", Crit = true, Damage = 30 })
		task.wait(STEP)
		step(6, "level up")
		PetFx.levelUp(star.Model, 8)
		task.wait(STEP)
		step(7, "KO poof")
		PetFx.ko(star.Model)
		task.wait(STEP)
	end)
	release()
	cleanup()
	if not ok then
		warn("[DevPetFx] " .. tostring(err))
	end
end

local function fightShow(root: BasePart)
	local base, look = frontOf(root, 14)
	local side = base.RightVector
	local aPos = base.Position - side * 4
	local bPos = base.Position + side * 4
	local specs = {
		{ Rarity = "Legendary", Mineral = "CosmicDragon" },
		{ Rarity = "Epic", Mineral = "Raptor" },
	}
	local pets, _, cleanup = build(specs, { CFrame.lookAt(aPos, bPos), CFrame.lookAt(bPos, aPos) })
	local aim, release = holdCamera()
	local ok, err = pcall(function()
		local a, b = pets[1], pets[2]
		assert(a and b, "pets did not build")
		local mid = base.Position + Vector3.new(0, 1.5, 0)
		aim(mid - look * 15 + Vector3.new(0, 4, 0), mid, 62)
		local winColor = PetFxRules.look(a.Spec.Rarity, a.Spec.Mineral, a.Spec.Modifier).Color
		step(1, "fight: hit")
		FightFx.play("hit", { Target = b.Model, Attacker = a.Model, Element = "Cosmic", Damage = 9, Mine = true })
		task.wait(STEP)
		step(2, "fight: type advantage")
		FightFx.play("advantage", { Target = a.Model, Attacker = b.Model, Element = "Fire", Damage = 18, Mine = true })
		task.wait(STEP)
		step(3, "fight: crit")
		FightFx.play("crit", { Target = b.Model, Attacker = a.Model, Element = "Storm", Damage = 31, Mine = true })
		task.wait(STEP)
		step(4, "fight: special")
		FightFx.play("special", { Target = b.Model, Attacker = a.Model, Element = "Cosmic", Damage = 45, Mine = true })
		task.wait(STEP + FightFx.SPECIAL_CHARGE)
		step(5, "fight: level up")
		FightFx.play("levelup", { Target = a.Model, Color = winColor, Level = 9, Mine = true })
		task.wait(STEP)
		step(6, "fight: KO + winner")
		FightFx.play("ko", { Target = b.Model, Attacker = a.Model, Element = "Cosmic", Mine = true, Winner = a.Model, WinnerColor = winColor })
		task.wait(STEP * 2)
	end)
	release()
	cleanup()
	if not ok then
		warn("[DevPetFx] " .. tostring(err))
	end
end

local function run(show: (BasePart) -> ())
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if busy or not root or not root:IsA("BasePart") then
		return
	end
	busy = true
	show(root)
	busy = false
end

local function onText(text: string)
	local cmd = string.lower((string.gsub(text, "%s", "")))
	if cmd == "/petfx" then
		task.spawn(run, petShow)
	elseif cmd == "/fightfx" then
		task.spawn(run, fightShow)
	end
end

TextChatService.SendingMessage:Connect(function(msg: TextChatMessage)
	onText(msg.Text)
end)
player.Chatted:Connect(onText)
