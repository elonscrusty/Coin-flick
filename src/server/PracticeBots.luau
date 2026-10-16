--!strict
-- Practice buddies on the first hunt (rules: shared/BotRules). The bots are plain R15 characters owned by the server
-- that act out the loop next to the new player: walk to the pile, grab, walk to their nest, tap it. They are scenery
-- only: no RockAction, no eggs taken or cracked, never a finder (the practice pet is always the player's).
-- If a character cannot be made (Roblox avatar service down) the round simply has no bots.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local BotRules = require(Shared.BotRules)
local Config = require(Shared.Config)
local StationModels = require(script.Parent.StationModels)
local RacerCollision = require(script.Parent.RacerCollision)

local PracticeBots = {}

type Live = { Bot: BotRules.Bot, Model: Model, Humanoid: Humanoid, Root: BasePart, Nest: Vector3, NestAt: Vector3, Pile: Vector3, Egg: BasePart?, Arrived: boolean, Table: Model, Target: Vector3?, LastPos: Vector3, LastMoveAt: number, LastOrderAt: number, Cycles: number }
type Group = { Live: { Live }, Running: boolean }

local groups: { [string]: Group } = {}
local rng = Random.new()
local loops = 0 -- step loops still running (tests: 0 once every practice round is over)

local factory: ((string, Color3) -> Model?)? = nil

-- Tests only: build bot characters with `fn` instead of the Roblox avatar service (the offline mock has none).
function PracticeBots.setFactory(fn: ((string, Color3) -> Model?)?)
	factory = fn
end

-- (Tests) the live bots of match `key`: name, step, carrying.
function PracticeBots.peek(key: string): { { [string]: any } }
	local out = {}
	local group = groups[key]
	local list: { Live } = if group then group.Live else {}
	for _, live in list do
		table.insert(out, { Name = live.Bot.Name, Step = live.Bot.Step, Carry = live.Bot.Carry, Cycles = live.Cycles, Pos = live.Root.Position, Pile = live.Pile, Nest = live.Nest })
	end
	return out
end

local SHAPES = { Ball = Enum.PartType.Ball, Block = Enum.PartType.Block, Wedge = Enum.PartType.Wedge }

-- Welds the outfit's chunky parts (ears, spikes, tail) onto the character, in a folder named "Outfit".
local function dress(m: Model, outfit: BotRules.Outfit)
	local folder = Instance.new("Folder")
	folder.Name = "Outfit"
	for _, op in outfit.Parts do
		local attach = (m:FindFirstChild(op.Attach) or m:FindFirstChild("Head") or m:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if attach then
			local p = Instance.new("Part")
			p.Name = op.Name
			p.Shape = SHAPES[op.Shape] or Enum.PartType.Block
			p.Size = Vector3.new(op.Size[1], op.Size[2], op.Size[3])
			p.Color = op.Color
			p.Material = Enum.Material.SmoothPlastic
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			local r = op.Rot or { 0, 0, 0 }
			p.CFrame = attach.CFrame * CFrame.new(op.Offset[1], op.Offset[2], op.Offset[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = attach, p
			weld.Parent = p
			p.Parent = folder
		end
	end
	folder.Parent = m
	m:SetAttribute("Outfit", outfit.Name)
end

local function makeCharacter(name: string, index: number): Model?
	local f = factory
	local outfit = BotRules.outfit(index)
	local ok, model = pcall(function()
		if f then
			return f(name, outfit.Body)
		end
		local d = Instance.new("HumanoidDescription")
		d.HeadColor = outfit.Skin
		d.LeftArmColor, d.RightArmColor = outfit.Body, outfit.Body
		d.TorsoColor = outfit.Body
		d.LeftLegColor, d.RightLegColor = outfit.Legs, outfit.Legs
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[PracticeBots] no bot character: " .. tostring(model))
		return nil
	end
	local m = model :: Model
	m.Name = "PracticeBot_" .. name
	-- the default avatar's grey shirt / blue pants clothing would hide the onesie colours
	for _, c in m:GetDescendants() do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then
			c:Destroy()
		end
	end
	pcall(dress, m, outfit)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = name
		hum.NameDisplayDistance = 60
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.WalkSpeed = BotRules.WalkSpeed
		hum.BreakJointsOnDeath = false
	end
	m:SetAttribute("PracticeBot", true)
	return m
end

local function carryEgg(live: Live, on: boolean)
	if on and not live.Egg then
		local egg = Instance.new("Part")
		egg.Name = "BotEgg"
		egg.Shape = Enum.PartType.Ball
		egg.Size = Vector3.new(1.4, 1.8, 1.4)
		egg.Color = Color3.fromRGB(250, 244, 226)
		egg.Material = Enum.Material.SmoothPlastic
		egg.CanCollide, egg.CanQuery, egg.CanTouch, egg.Massless = false, false, false, true
		local head = live.Model:FindFirstChild("Head") :: BasePart?
		local anchor = head or live.Root
		egg.CFrame = anchor.CFrame * CFrame.new(0, 2, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = anchor, egg
		weld.Parent = egg
		egg.Parent = live.Model
		live.Egg = egg
	elseif not on and live.Egg then
		live.Egg:Destroy()
		live.Egg = nil
	end
end

local ARRIVE = 2.5 -- studs (flat) from the target counts as arrived
local REORDER = 2 -- seconds: MoveTo is given again (Roblox drops a MoveTo after 8 s or when it is pushed off)
local STUCK = 1 -- seconds without moving STUCK_STUDS: the bot is nudged along (a nest edge or the pile holds it)
local STUCK_STUDS = 0.4
local NUDGE = 2.5 -- studs per nudge
local logSteps = game:GetService("RunService"):IsStudio() -- Studio output: one line per bot when its first loop is done

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function walk(live: Live, to: Vector3, now: number)
	live.Arrived = false
	live.Target = to
	live.LastOrderAt = now
	live.LastMoveAt = now
	live.LastPos = live.Root.Position
	live.Humanoid:MoveTo(to)
end

-- One movement check for a walking bot: arrival by distance, MoveTo given again, a nudge when it is stuck.
local function steer(live: Live, now: number)
	local to = live.Target
	if not to or live.Arrived then
		return
	end
	local pos = live.Root.Position
	if flat(pos, to) <= ARRIVE then
		live.Arrived = true
		return
	end
	if (pos - live.LastPos).Magnitude >= STUCK_STUDS then
		live.LastPos = pos
		live.LastMoveAt = now
	elseif now - live.LastMoveAt >= STUCK then
		-- held by something: step it along the ground toward the target and walk on from there
		local d = Vector3.new(to.X - pos.X, 0, to.Z - pos.Z)
		local stepLen = math.min(NUDGE, d.Magnitude)
		local nextPos = pos + d.Unit * stepLen
		live.Model:PivotTo(CFrame.lookAt(nextPos, nextPos + d.Unit))
		live.LastPos = nextPos
		live.LastMoveAt = now
		live.Humanoid:MoveTo(to)
		live.LastOrderAt = now
		return
	end
	if now - live.LastOrderAt >= REORDER then
		live.Humanoid:MoveTo(to)
		live.LastOrderAt = now
	end
end

-- Bots for practice match `key`: one per free nest (tables whose index is not in `used`), up to BotRules.Count.
function PracticeBots.spawn(key: string, arena: { [string]: any }, used: { [number]: boolean })
	PracticeBots.clear(key)
	local center = arena.Center
	local tables = arena.Tables
	if typeof(center) ~= "Vector3" or type(tables) ~= "table" or typeof(arena.Root) ~= "Instance" then
		return
	end
	local free = {}
	for i, tbl in tables do
		if not used[i] and typeof(tbl) == "Instance" and tbl:IsA("Model") then
			table.insert(free, { Index = i, Model = tbl })
		end
	end
	local group: Group = { Live = {}, Running = true }
	groups[key] = group
	local spawns = arena.Spawns
	local radius = 10
	local okTier, tier = pcall(function()
		return Config.Tiers[Config.Tutorial.Tier]
	end)
	if okTier and tier and type(tier.Radius) == "number" then
		radius = tier.Radius
	end
	-- the step loop runs from the start; bots join it as their characters are made (making one can take a second)
	-- The loop also ends on its own when this group is no longer the match's current one, or once every bot model is
	-- gone (arena cleared under it): a practice crew can never outlive its round (walkthrough 10-14: bots kept
	-- looping ToPile/Grab/ToNest/Crack in the Output after the player was back in the lobby).
	local born = os.clock()
	local function alive(): boolean
		if not group.Running or groups[key] ~= group then
			return false
		end
		for _, live in group.Live do
			if live.Model.Parent then
				return true
			end
		end
		return #group.Live == 0 and os.clock() - born < 30 -- characters still being made
	end
	task.spawn(function()
		loops += 1
		while alive() do
			local now = os.clock()
			for _, live in group.Live do
				local before = live.Bot.Step
				steer(live, now)
				if BotRules.advance(live.Bot, now, live.Arrived, rng) then
					local step = live.Bot.Step
					if step == "ToPile" then
						walk(live, live.Pile, now)
					elseif step == "ToNest" then
						walk(live, live.Nest, now)
					else
						live.Target = nil
						live.Humanoid:Move(Vector3.zero)
						if step == "Crack" then
							live.Cycles += 1
							live.Root.CFrame = CFrame.lookAt(live.Root.Position, Vector3.new(live.NestAt.X, live.Root.Position.Y, live.NestAt.Z))
						end
					end
					if logSteps and step == "Crack" and live.Cycles == 1 then
						print(("[PracticeBots] %s finished its first pile -> nest loop"):format(live.Bot.Name)) -- once, not every step
					end
					if before ~= step then
						carryEgg(live, live.Bot.Carry)
					end
					if step == "Crack" then
						-- a little hop on each tap so the crack reads from across the arena
						task.spawn(function()
							for _ = 1, 3 do
								if not group.Running or not live.Model.Parent then
									return
								end
								live.Humanoid.Jump = true
								task.wait(0.6)
							end
						end)
					end
				end
			end
			task.wait(0.2)
		end
		group.Running = false
		loops -= 1
	end)
	for i, bot in BotRules.make(#free, rng, os.clock()) do
		task.spawn(function()
			local slot = free[i]
			local model = makeCharacter(bot.Name, i)
			if not model then
				return
			end
			if not group.Running then
				model:Destroy()
				return
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hum or not root then
				model:Destroy()
				return
			end
			local nest = slot.Model:GetPivot().Position
			local away = Vector3.new(nest.X - center.X, 0, nest.Z - center.Z)
			local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
			-- stand where a player of that nest spawns (always clear ground), else a little in front of the nest
			local spot = if type(spawns) == "table" and typeof(spawns[slot.Index]) == "CFrame" then (spawns[slot.Index] :: CFrame).Position else nest - dir * 4
			local nestStand = Vector3.new(spot.X, center.Y, spot.Z)
			local pileEdge = center + dir * (radius + 2) -- just outside the pile, facing this bot's nest
			model:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 1, 0), Vector3.new(center.X, spot.Y + 1, center.Z)))
			model.Parent = arena.Root
			RacerCollision.apply(model, true) -- bots pass through players like racers do
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			StationModels.setOwner(slot.Model, -i, bot.Name)
			local t = os.clock()
			local live: Live = {
				Bot = bot, Model = model, Humanoid = hum, Root = root, Nest = nestStand, NestAt = nest, Pile = pileEdge, Egg = nil,
				Arrived = false, Table = slot.Model, Target = nil, LastPos = root.Position, LastMoveAt = t, LastOrderAt = t, Cycles = 0,
			}
			table.insert(group.Live, live)
		end)
	end
end

-- Removes match `key`'s bots (round over, player left). Safe to call when there are none.
function PracticeBots.clear(key: string)
	local group = groups[key]
	if not group then
		return
	end
	group.Running = false
	groups[key] = nil
	for _, live in group.Live do
		if live.Model.Parent then
			live.Model:Destroy()
		end
		if live.Table.Parent then
			StationModels.setOwner(live.Table, nil, nil)
		end
	end
end

-- (Tests) how many bot step loops are still running across all matches.
function PracticeBots.loops(): number
	return loops
end

-- How many bots match `key` has (tests and the dev tools).
function PracticeBots.count(key: string): number
	local group = groups[key]
	return if group then #group.Live else 0
end

return PracticeBots
