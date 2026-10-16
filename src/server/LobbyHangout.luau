--!strict
-- Lobby hangout, shared server part (shared/Hangout has the rules and tuning; docs/HANGOUT.md the hooks):
--   * one prompt router: every hangout prompt carries the attribute `Hangout` (its kind); Triggered is re-checked for
--     range here and handed to the handler registered for that kind (LobbyGames, LobbyEvents register theirs);
--   * coin payouts (pay / payGame with the daily mini-game cap), counted in Stats.CashEarned (MOST COINS board);
--   * sit spots (idea 8): parts named SitSpot*, Bench*, Swing*, DockSeat*, CampfireLog* get a "Sit" prompt (a part
--     that is not a Seat gets an invisible Seat on its top); a Campfire gets a warm light (static, no flames);
--   * secret spots (idea 9): HiddenEgg1..N pay coins once each, the LookoutChest once per UTC day;
--   * the ONE group reward (idea 10 + the first-five-minutes daily group gift, merged): membership of
--     Retention.Group.Id is asked once per join (or on the GroupGift prompt); a member gets a free pet once
--     (RobuxService.giftEgg), the daily group coins (RetentionService.groupDaily) and the player attribute GroupMember
--     (MatchService adds Hangout.groupLuck to the finder's luck). Off while the id is 0.
-- Hooks are found by name under the lobby roots when the lobby starts (adopt), so the hand-built LobbyMeadow and
-- the fallback park work the same. A missing hook just means that feature is not in the map.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)
local Net = require(Shared.Net)
local Profiles = require(script.Parent.Profiles)

local LobbyHangout = {}

local handlers: { [string]: (Player, ProximityPrompt) -> () } = {}
local lastPrompt: { [Player]: number } = {}
local secretTotal = 0
local groupCheck = function(player: Player): any
	return GroupService:GetGroupsAsync(player.UserId)
end
local giftEgg: ((Player, string, string) -> any?)? = nil
local groupDaily: ((Player, boolean) -> number)? = nil

local function toast(player: Player, text: string, kind: string?)
	Net.event("Toast"):FireClient(player, text, kind or "info")
end
LobbyHangout.toast = toast

function LobbyHangout.toastAll(text: string, kind: string?)
	Net.event("Toast"):FireAllClients(text, kind or "info")
end

-- The player's saved hangout state (repaired in place), or nil before the profile loads / after it was released.
function LobbyHangout.state(player: Player): Hangout.State?
	local data = Profiles.get(player)
	if not data or Profiles.isReleased(player) then
		return nil
	end
	data.Hangout = Hangout.sanitize(data.Hangout)
	return data.Hangout
end

function LobbyHangout.today(): number
	return Hangout.day(os.time())
end

-- Pays coins now (counted as earned: MOST COINS board). Returns the coins paid.
function LobbyHangout.pay(player: Player, coins: number): number
	local data = Profiles.get(player)
	local n = math.floor(coins)
	if not data or Profiles.isReleased(player) or n <= 0 then
		return 0
	end
	data.Cash += n
	data.Stats.CashEarned += n
	Profiles.changed(player)
	return n
end

-- A mini-game prize: paid up to what is left of today's Hangout.Games.DailyCoinCap. Returns the coins paid.
function LobbyHangout.payGame(player: Player, want: number): number
	local h = LobbyHangout.state(player)
	if not h then
		return 0
	end
	local n = Hangout.payGame(h, LobbyHangout.today(), want)
	return LobbyHangout.pay(player, n)
end

-- The avatar's root part, or nil.
function LobbyHangout.root(player: Player): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function promptAt(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- Is the player's avatar within `range` studs of `pos`?
function LobbyHangout.near(player: Player, pos: Vector3, range: number): boolean
	local r = LobbyHangout.root(player)
	return r ~= nil and (r.Position - pos).Magnitude <= range
end

-- A hangout prompt on `part` (made once; kind in the attribute `Hangout`).
function LobbyHangout.prompt(part: Instance, kind: string, action: string, object: string, range: number?, hold: number?): ProximityPrompt
	local pp = part:FindFirstChild("HangoutPrompt") :: ProximityPrompt?
	if not pp then
		local made = Instance.new("ProximityPrompt")
		made.Name = "HangoutPrompt"
		made.RequiresLineOfSight = false
		made.Parent = part
		pp = made
	end
	local p = pp :: ProximityPrompt
	p.ActionText = action
	p.ObjectText = object
	p.MaxActivationDistance = range or 10
	p.HoldDuration = hold or 0
	p:SetAttribute("Hangout", kind)
	return p
end

function LobbyHangout.onPrompt(kind: string, fn: (Player, ProximityPrompt) -> ())
	handlers[kind] = fn
end

-- Routes one Triggered prompt (also called by tests). Out of range or too fast = ignored.
function LobbyHangout.trigger(prompt: ProximityPrompt, player: Player)
	local kind = prompt:GetAttribute("Hangout")
	local fn = if type(kind) == "string" then handlers[kind] else nil
	if not fn then
		return
	end
	local at = promptAt(prompt)
	if not at or not LobbyHangout.near(player, at, prompt.MaxActivationDistance + 6) then
		return
	end
	local t = os.clock()
	if lastPrompt[player] and t - lastPrompt[player] < 0.2 then
		return
	end
	lastPrompt[player] = t
	fn(player, prompt)
end

-- Sit spots (idea 8) --------------------------------------------------------------------------------------------------

local function seatFor(part: BasePart): Seat
	if part:IsA("Seat") then
		return part
	end
	local existing = part:FindFirstChild("HangoutSeat")
	if existing and existing:IsA("Seat") then
		return existing
	end
	local seat = Instance.new("Seat")
	seat.Name = "HangoutSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.2, 0)
	seat.Parent = part
	return seat
end

local function hookSit(part: BasePart)
	local seat = seatFor(part)
	LobbyHangout.prompt(seat, "Sit", "Sit", "", 8)
end

LobbyHangout.onPrompt("Sit", function(player, prompt)
	local seat = prompt.Parent
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if seat and seat:IsA("Seat") and hum and hum.Health > 0 and seat.Occupant == nil then
		seat:Sit(hum)
	end
end)

local function hookCampfire(inst: Instance)
	local part = if inst:IsA("BasePart") then inst else inst:FindFirstChildWhichIsA("BasePart", true)
	if part and not part:FindFirstChild("CampfireLight") then
		local light = Instance.new("PointLight")
		light.Name = "CampfireLight"
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Brightness = 1.6
		light.Range = 16
		light.Parent = part
	end
end

-- Secret spots (idea 9) ------------------------------------------------------------------------------------------------

-- Tells this player's client which hidden eggs to hide (Hangout.foundList).
function LobbyHangout.publishSecrets(player: Player)
	local h = LobbyHangout.state(player)
	if h then
		player:SetAttribute(Hangout.Secrets.FoundAttr, Hangout.foundList(h))
	end
end

LobbyHangout.onPrompt("Secret", function(player, prompt)
	local h = LobbyHangout.state(player)
	local name = prompt:GetAttribute("Secret")
	if not h or type(name) ~= "string" then
		return
	end
	if not Hangout.claimSecret(h, name) then
		toast(player, "You already found this hidden egg!", "info")
		LobbyHangout.publishSecrets(player)
		return
	end
	LobbyHangout.publishSecrets(player)
	local paid = LobbyHangout.pay(player, Hangout.Secrets.Coins)
	toast(player, "Hidden egg " .. Hangout.secretsFound(h) .. "/" .. math.max(secretTotal, Hangout.secretsFound(h)) .. " found! +" .. paid .. " coins", "rare")
	Net.event("Fx"):FireClient(player, "HiddenEgg", { Pos = promptAt(prompt) })
end)

LobbyHangout.onPrompt("Lookout", function(player, prompt)
	local h = LobbyHangout.state(player)
	if not h then
		return
	end
	if not Hangout.claimLookout(h, LobbyHangout.today()) then
		toast(player, "Come back tomorrow for more lookout coins!", "info")
		return
	end
	local paid = LobbyHangout.pay(player, Hangout.Secrets.LookoutCoins)
	toast(player, "You climbed to the lookout! +" .. paid .. " coins", "rare")
	Net.event("Fx"):FireClient(player, "HiddenEgg", { Pos = promptAt(prompt) })
end)

-- Group bonus (idea 10) ------------------------------------------------------------------------------------------------

local checking: { [Player]: boolean } = {}
local lastGroup: { [Player]: number } = {}

-- Asks Roblox whether the player is in the group, sets GroupMember and gives the free pet once. `loud` = the player
-- asked (the GroupGift prompt), so a "join first" line is shown.
function LobbyHangout.checkGroup(player: Player, loud: boolean?)
	if not Hangout.groupOn() or checking[player] then
		return
	end
	checking[player] = true
	local ok, rows = pcall(groupCheck, player)
	checking[player] = nil
	if not ok then
		warn("[LobbyHangout] group check failed:", rows)
		return
	end
	local member = Hangout.inGroup(rows)
	if player.Parent then
		player:SetAttribute("GroupMember", member)
	end
	local h = LobbyHangout.state(player)
	if not h then
		return
	end
	if not member then
		if loud then
			toast(player, "Join our Roblox group, then tap here for a free pet!", "info")
		end
		return
	end
	local daily = groupDaily
	local coins = if daily then daily(player, true) else 0
	if h.GroupGift then
		if loud and coins == 0 then
			toast(player, "You already got your group gifts today. Thanks for joining!", "info")
		end
		return
	end
	local gift = giftEgg
	local pet = if gift then gift(player, Hangout.Group.GiftEgg, "group:" .. player.UserId) else nil
	if pet then
		h.GroupGift = true
		Profiles.changed(player)
		toast(player, "Thanks for joining the group! Here is a free pet!", "rare")
	else
		toast(player, "Make room in your Pet Book to get your free group pet!", "warn")
	end
end

LobbyHangout.onPrompt("GroupGift", function(player, _prompt)
	local t = os.clock()
	if lastGroup[player] and t - lastGroup[player] < 10 then
		return
	end
	lastGroup[player] = t
	if not Hangout.groupOn() then
		toast(player, "The group gift is coming soon!", "info")
		return
	end
	task.spawn(LobbyHangout.checkGroup, player, true)
end)

-- Tests only: replace the group lookup (player -> GetGroupsAsync rows) and the pet gift.
function LobbyHangout.setGroupCheck(fn: (Player) -> any)
	groupCheck = fn
end
function LobbyHangout.setGift(fn: (Player, string, string) -> any?)
	giftEgg = fn
end
function LobbyHangout.setGroupDaily(fn: (Player, boolean) -> number)
	groupDaily = fn
end

-- Hooks ---------------------------------------------------------------------------------------------------------------

-- Finds the hangout hooks under `root` (sit spots, campfire, hidden eggs, lookout chest, group gift). Safe to call
-- again: every prompt is made once.
function LobbyHangout.adopt(root: Instance)
	local n = 0
	for _, d in root:GetDescendants() do
		local name = d.Name
		if d:IsA("BasePart") and d.Name ~= "HangoutSeat" and Hangout.isSitName(name) then
			hookSit(d)
		elseif name == Hangout.Sit.Campfire then
			hookCampfire(d)
		elseif Hangout.secretIndex(name) then
			local part = if d:IsA("BasePart") then d elseif d:IsA("Model") then d:FindFirstChildWhichIsA("BasePart", true) else nil
			if part then
				n += 1
				local pp = LobbyHangout.prompt(part, "Secret", "Take", "Hidden Egg", Hangout.Secrets.Range)
				pp:SetAttribute("Secret", name)
			end
		elseif name == Hangout.Secrets.Lookout or name == Hangout.Group.GiftPrompt then
			local part = if d:IsA("BasePart") then d elseif d:IsA("Model") then d:FindFirstChildWhichIsA("BasePart", true) else nil
			if part then
				if name == Hangout.Secrets.Lookout then
					LobbyHangout.prompt(part, "Lookout", "Open", "Lookout Chest", Hangout.Secrets.Range)
				else
					LobbyHangout.prompt(part, "GroupGift", "Claim", "Group Gift", Hangout.Secrets.Range)
				end
			end
		end
	end
	secretTotal = math.max(secretTotal, n)
end

-- `roots`: the lobby map(s) to search for hooks (the hand-built map, the code's lobby folder); never the arenas.
function LobbyHangout.start(roots: { Instance }, gift: ((Player, string, string) -> any?)?)
	if gift and not giftEgg then
		giftEgg = gift
	end
	if not groupDaily then
		groupDaily = require(script.Parent.RetentionService).groupDaily
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt:GetAttribute("Hangout") ~= nil then
			LobbyHangout.trigger(prompt, player)
		end
	end)
	for _, r in roots do
		LobbyHangout.adopt(r)
	end
	Profiles.onLoaded(function(player)
		LobbyHangout.publishSecrets(player)
		task.spawn(LobbyHangout.checkGroup, player, false)
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastPrompt[p] = nil
		lastGroup[p] = nil
		checking[p] = nil
	end)
end

return LobbyHangout
