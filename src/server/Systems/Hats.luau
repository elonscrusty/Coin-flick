--!strict
-- Silly hats: bought with hat points (🎩 from skull flips), worn on your head.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Net = require(script.Parent.Net)
local PlayerData = require(script.Parent.PlayerData)
local World = require(script.Parent.World)
local HatBuilder = require(script.Parent.Parent.Builders.HatBuilder)
local GameLogic = require(script.Parent.Parent.Util.GameLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Hats = {}

local limiter = RateLimiter.new(Config.BUY_RATE, Config.BUY_BURST, os.clock)

-- Put the player's current hat on their character (or take it off).
local function dress(player: Player)
	local character = player.Character
	local profile = PlayerData.get(player)
	if not character or not profile then
		return
	end
	local old = character:FindFirstChild("CoinFlickHat")
	if old then
		old:Destroy()
	end
	-- Hide the avatar's own hats while a COIN FLICK hat is on (and bring them back after).
	local wearing = profile.hat ~= ""
	for _, item in character:GetChildren() do
		if not item:IsA("Accessory") then
			continue
		end
		if (item :: Accessory).AccessoryType ~= Enum.AccessoryType.Hat then
			continue
		end
		local handle = item:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			if handle:GetAttribute("CoinFlickWas") == nil then
				handle:SetAttribute("CoinFlickWas", handle.Transparency)
			end
			local was = handle:GetAttribute("CoinFlickWas")
			handle.Transparency = if wearing then 1 elseif typeof(was) == "number" then was else 0
		end
	end
	local head = character:FindFirstChild("Head")
	if not wearing or not head or not head:IsA("BasePart") then
		return
	end
	local hat = HatBuilder.build(profile.hat, World.makePart)
	if not hat then
		return
	end
	hat:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 - 0.1, 0))
	for _, part in hat:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
		end
	end
	hat.Parent = character
end

local function notify(player: Player, text: string)
	local notice: Types.Notice = { kind = "bought", text = text }
	Net.event("Notice"):FireClient(player, notice)
end

local function onBuy(player: Player, rawId: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if GameLogic.buyHat(profile, rawId) then
		local def = Economy.hatDef(rawId)
		PlayerData.changed(player)
		dress(player)
		notify(player, `{if def then def.name else "Hat"} is on your head!`)
	end
end

local function onWear(player: Player, rawId: unknown)
	if not limiter:allow(player) then
		return
	end
	local profile = PlayerData.get(player)
	if profile and GameLogic.wearHat(profile, rawId) then
		PlayerData.changed(player)
		dress(player)
	end
end

function Hats.init()
	Net.event("BuyHat").OnServerEvent:Connect(onBuy)
	Net.event("WearHat").OnServerEvent:Connect(onWear)
	PlayerData.onLoaded(function(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			dress(player)
		end)
		dress(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		limiter:remove(player)
	end)
end

return Hats
