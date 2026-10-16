--!strict
-- Rare hatch announcements (owner pick). A Rare, Epic or Legendary hatch (Config.Pets.AnnounceRarities) is shown:
--   * in this server: fireworks and a gold banner for every player (RareHatch remote, kind "Local");
--   * in every other server: the same gold banner, no fireworks (MessagingService topic Config.RareHatch.Topic,
--     kind "Global").
-- The message carries only the player's display name, the pet's display name and the rarity (PetFlair.payload),
-- never a user id, egg id or anything about a running round. Publishing is rate limited per server and per player
-- (PetFlair.allow); messages from other servers are checked again and limited to one banner per ReceiveGap.
-- Every MessagingService call is wrapped in pcall: if it fails (Studio without API access, an outage) the local
-- banner still plays and the error is only warned.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GeodeGen = require(Shared.GeodeGen)
local PetFlair = require(Shared.PetFlair)

local RareHatch = {}

local cfg = Config.RareHatch
local messaging: any = nil
do
	local ok, svc = pcall(function()
		return game:GetService("MessagingService")
	end)
	if ok then
		messaging = svc
	end
end

local publishLimit = PetFlair.newLimiter(cfg.PublishGap, cfg.PlayerGap)
local receiveLimit = PetFlair.newLimiter(cfg.ReceiveGap)
local sent: { [string]: number } = {} -- echo key -> os.clock() of our own publish

local function fire(kind: string, p: PetFlair.Payload)
	Net.event("RareHatch"):FireAllClients(kind, p)
end

-- Called by MatchService once the finder's own reveal has played. The server decided the hatch; nothing here comes
-- from a client.
function RareHatch.announce(player: Player, specimen: { [string]: any })
	if type(specimen) ~= "table" or not (PetFlair.shouldAnnounce(specimen.Rarity) or specimen.Shiny == true) then
		return
	end
	local p = PetFlair.payload(player.DisplayName, GeodeGen.displayName(specimen :: any), specimen.Rarity)
	if not p then
		return
	end
	fire("Local", p)
	if not messaging then
		return
	end
	local now = os.clock()
	if not PetFlair.allow(publishLimit, tostring(player.UserId), now) then
		return -- this server just announced: the other servers skip this one (the local banner still played)
	end
	for k, t in sent do
		if now - t > cfg.EchoSeconds then
			sent[k] = nil
		end
	end
	sent[PetFlair.echoKey(p)] = now
	task.spawn(function()
		local ok, err = pcall(function()
			messaging:PublishAsync(cfg.Topic, { Name = p.Name, Pet = p.Pet, Rarity = p.Rarity })
		end)
		if not ok then
			warn("[RareHatch] publish failed:", err)
		end
	end)
end

local function onMessage(message: any)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" then
		return
	end
	local p = PetFlair.payload(data.Name, data.Pet, data.Rarity)
	if not p then
		return
	end
	local now = os.clock()
	local key = PetFlair.echoKey(p)
	local mine = sent[key]
	if mine and now - mine <= cfg.EchoSeconds then
		sent[key] = nil -- our own message coming back: the local banner already played here
		return
	end
	if not PetFlair.allow(receiveLimit, "all", now) then
		return
	end
	fire("Global", p)
end

local started = false
function RareHatch.start()
	if started then
		return
	end
	started = true
	if not messaging then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			messaging:SubscribeAsync(cfg.Topic, onMessage)
		end)
		if not ok then
			warn("[RareHatch] subscribe failed (other servers will not show rare hatches here):", err)
		end
	end)
end

return RareHatch
