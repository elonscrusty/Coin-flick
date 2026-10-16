-- fightfx: two pets mid-fight, one big moment (client FightFx). --set m=hit|advantage|crit|special|levelup|ko
-- (default crit), --set at=S seconds after the moment starts (default 0.12; special charges 0.7 s first, ko shows the
-- winner after the slow motion, try at=1.6). Screen effects play as for the local player's own pet (Mine).
local C = lib("ctr")
local s = C.boot({ profile = function(data)
	data.TutorialStep = 1
end })
local PetModel = C.shared("PetModel")
local PetFx = preview.client("PetFx")
local FightFx = preview.client("FightFx")
local kind = preview.args.m or "crit"
local at = tonumber(preview.args.at) or 0.12

local root = s.me.Character.HumanoidRootPart
local base = root.CFrame * CFrame.new(0, -2.8, -14)
local side = base.RightVector
local aPos, bPos = base.Position - side * 4, base.Position + side * 4
local folder = Instance.new("Folder")
folder.Name = "FightFxRow"
folder.Parent = workspace
local function pet(spec, pos, face)
	local m = PetModel.build(spec, { Scale = 1, Lod = true, NoLight = true })
	m:PivotTo(CFrame.lookAt(pos, face))
	m.Parent = folder
	local fx = PetFx.attach(m, spec, 1, folder)
	return m, fx
end
local a, afx = pet({ Rarity = "Legendary", Mineral = "CosmicDragon" }, aPos, bPos)
local b, bfx = pet({ Rarity = "Epic", Mineral = "Raptor" }, bPos, aPos)
for _, d in s.me.Character:GetDescendants() do
	if d:IsA("BasePart") then
		d.Transparency = 1
	end
end
local cam = workspace.CurrentCamera
local mid = base.Position + Vector3.new(0, 1.5, 0)
local function aimCam()
	C.cameraAt(mid, -base.LookVector * 15 + Vector3.new(0, 4, 0), 62)
end
aimCam()
PetFx.update(afx, aPos, 0, 0, false, 1, cam.CFrame.Position, 0, false)
PetFx.update(bfx, bPos, 0, 0, false, 1, cam.CFrame.Position, 0, false)
local opts = { Target = b, Attacker = a, Element = if kind == "advantage" then "Fire" else "Cosmic", Damage = 31, Mine = true }
if kind == "levelup" then
	opts = { Target = a, Color = Color3.fromRGB(150, 70, 255), Level = 9, Mine = true }
elseif kind == "ko" then
	opts.Winner = a
	opts.WinnerColor = Color3.fromRGB(150, 70, 255)
end
FightFx.play(kind, opts)
preview.advance(at, 60)
PetFx.update(afx, aPos, 0, 0, false, 2, cam.CFrame.Position, 0, false)
PetFx.update(bfx, bPos, 0, 0, false, 2, cam.CFrame.Position, 0, false)
aimCam()
print("FIGHTFX", kind, "at", at, "speed", FightFx.speed())
