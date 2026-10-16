--!strict
-- Remote registry. The server creates every remote at boot; clients wait for them.
-- Clients only ever send intents; every outcome is decided on the server.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	-- client -> server
	"RockAction", -- (action, roundId, rockId?) action: Pickup | Deposit | Crush | ToggleMachine (V3 loop, docs/V3_LOOP.md)
	"PartyAction", -- (action, arg)
	"MatchAction", -- (action)
	"ShopAction", -- (action, id)
	"CollectionAction", -- (action, arg1, arg2)
	"SettingsAction", -- (settings table)
	"ClientReady", -- ()
	"TutorialAction", -- ("Skip" | "Goal")
	"LaunchAction", -- (action) Teleport mode: "Retry" | "Cancel" | "StartWithArrived" | "ReturnAll"
	"StoreAction", -- ("Buy" | "Equip" | "Unequip", cosmetic id or kind)
	"RobuxAction", -- ("Buy", egg id, count 1|3|10 | "LuckPotion" | pass key) Robux shop (RobuxService); the server prompts the purchase
	"RetentionAction", -- ("Ready" | "Starter" | "Gift") first five minutes + comeback hooks (RetentionService)
	-- server -> client
	"ProfileState", -- (public profile)
	"PartyState", -- (party view or nil, invites)
	"Inspect", -- (card) read-only view of a specimen on display in a lobby gallery
	"MatchEvent", -- (kind, payload)
	"Toast", -- (text, kind)
	"LaunchEvent", -- (kind, payload) Teleport mode: loading / waiting-for-party UI
	"Fx", -- (kind, data) cosmetic feedback, e.g. ("Sell", { Pos, Count, Total })
	"RareHatch", -- (kind "Local" | "Global", { Name, Pet, Rarity }) rare hatch banner (RareHatch); Local adds fireworks
	"EggEvent", -- (kind, payload) EggEvents: ("Wobble", { Round, Id }) | ("Boots", { Round, UserId, Until, Seconds })
	"Retention", -- (kind, payload) RetentionService: "Starter" | "Gift" | "GiftReady" | "Away" | "Friend" | "Group"
	"HangoutEvent", -- (kind, payload) lobby hangout (LobbyGames / LobbyEvents): Whack, WhackDone, Event
	"HatchShow", -- (show) a bought egg hatching at the public hatch stand: { Buyer, BuyerId, Egg, Count, Pet, Waiting } (RobuxService queue; Waiting = shows still queued)
}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder :: Folder
	end
	local found: Folder
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if f then
			found = f
		else
			found = Instance.new("Folder")
			found.Name = "Remotes"
			found.Parent = ReplicatedStorage
		end
	else
		found = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	folder = found
	return found
end

function Net.init()
	local f = getFolder()
	if RunService:IsServer() then
		for _, name in Net.Events do
			if not f:FindFirstChild(name) then
				local e = Instance.new("RemoteEvent")
				e.Name = name
				e.Parent = f
			end
		end
	end
end

function Net.event(name: string): RemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

return Net
