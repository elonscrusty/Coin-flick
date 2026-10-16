--!strict
-- Turns a tap (phone) or click (PC) on one of YOUR coins into
-- "I tapped coin N" for the server. That's all the client ever says.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ClientNet = require(script.Parent.Parent.ClientNet)
local FlipFx = require(script.Parent.FlipFx)
local Sounds = require(script.Parent.Sounds)

local CoinTap = {}

local player = Players.LocalPlayer
local tapRemote: RemoteEvent
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function coinFromHit(hit: Instance): (number?, BasePart?)
	local index = hit:GetAttribute("CoinIndex")
	local tableModel = hit:FindFirstAncestorOfClass("Model")
	if typeof(index) ~= "number" or not tableModel then
		return nil, nil
	end
	if tableModel:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil, nil -- not your table
	end
	local coins = tableModel:FindFirstChild("Coins")
	local coin = coins and coins:FindFirstChild(`Coin_{index}`)
	if coin and coin:IsA("BasePart") then
		return index, coin
	end
	return nil, nil
end

local function tapRay(ray: Ray)
	local tables = workspace:FindFirstChild("Tables")
	if not tables then
		return
	end
	params.FilterDescendantsInstances = { tables }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	if not result then
		return
	end
	local index, coin = coinFromHit(result.Instance)
	if not index or not coin or FlipFx.isFlying(coin) then
		return
	end
	Sounds.play("Tap", 0.35)
	tapRemote:FireServer(index)
end

function CoinTap.init()
	tapRemote = ClientNet.event("TapCoin")

	-- Phones/tablets. TouchTapInWorld gives viewport coordinates.
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		if processedByUI then
			return
		end
		local camera = workspace.CurrentCamera
		tapRay(camera:ViewportPointToRay(position.X, position.Y))
	end)

	-- Mouse. InputObject positions are screen coordinates (no top bar inset).
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local camera = workspace.CurrentCamera
		tapRay(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	end)
end

return CoinTap
