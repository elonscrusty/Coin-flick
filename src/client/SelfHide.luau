--!strict
-- The player's own avatar is hidden for the player (LocalTransparencyModifier; others still see it) while
-- PopupRules.hideSelf says so: a Pet Battle (InBattle) or a tower climb (InTower). Re-applied every frame after the
-- camera, because the default camera scripts reset the modifier. Restored when the fight view ends.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local PopupRules = require(Shared.PopupRules)

local SelfHide = {}

local player = Players.LocalPlayer
local hidden: { [Instance]: boolean } = {}

local function apply(on: boolean)
	local char = player.Character
	if on and char then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 1
				hidden[d] = true
			end
		end
	elseif not on and next(hidden) then
		for d in hidden do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		table.clear(hidden)
	end
end

function SelfHide.wanted(): boolean
	return PopupRules.hideSelf(player:GetAttribute("InBattle") == true, player:GetAttribute("InTower") == true)
end

function SelfHide.start()
	RunService:BindToRenderStep("SelfHide", Enum.RenderPriority.Camera.Value + 2, function()
		apply(SelfHide.wanted())
	end)
end

return SelfHide
