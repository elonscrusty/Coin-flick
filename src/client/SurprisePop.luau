--!strict
-- Surprise eggs (owner pick 2026-10-15, shared/HuntFun.Surprise): the server pays a small prize for every ordinary egg
-- a player finishes and tells only that player (MatchEvent "Surprise" { Round, List = { { Kind, Amount } }, Meter,
-- MeterNeed }). This draws it: a short screen pop right of centre ("+4 coins", "+3 pet XP", "Lucky Meter 12/30") at
-- HuntFun.PopSpots, and a JACKPOT banner with a coin flight for the rare jackpot. Purely visual; the prize is already
-- paid when the event arrives.

local Audio = require(script.Parent.Audio)
local Juice = require(script.Parent.ui.Juice)
local UI = require(script.Parent.ui.UI)
local HuntFun = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HuntFun"))

local SurprisePop = {}

local GOLD = Color3.fromRGB(255, 212, 80)
local XP = Color3.fromRGB(120, 220, 255)
local METER = Color3.fromRGB(190, 140, 255)

local count = 0 -- pops shown so far (picks the next row, so pops in one batch never sit on each other)
local anchors: { Frame } = {}

-- An invisible spot on the notice layer for Juice.floatText to rise from (one per row, made once).
local function anchorFor(i: number): Frame?
	local a = anchors[i]
	if a and a.Parent then
		return a
	end
	local spot = HuntFun.PopSpots[i]
	local layer = UI.noticeLayer()
	local f = Instance.new("Frame")
	f.Name = "SurprisePopSpot" .. i
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(spot.X, spot.Y)
	f.Size = UDim2.fromOffset(2, 2)
	f.Parent = layer
	anchors[i] = f
	return f
end

local function pop(text: string, color: Color3)
	local spot = HuntFun.popScreen(count)
	local i = table.find(HuntFun.PopSpots, spot) or 1
	count += 1
	local a = anchorFor(i)
	if a then
		Juice.floatText(a, text, color)
	end
end

-- MatchEvent "Surprise": one batch of prizes (a fast auto nest can finish several eggs in one step). Coins and XP in a
-- batch are added up, so the screen never fills with pops.
function SurprisePop.show(data: any)
	if type(data) ~= "table" or type(data.List) ~= "table" then
		return
	end
	local coins, xp, meter, jackpot = 0, 0, 0, 0
	for _, s in data.List do
		if type(s) == "table" and type(s.Amount) == "number" then
			if s.Kind == "Coins" then
				coins += s.Amount
			elseif s.Kind == "Xp" then
				xp += s.Amount
			elseif s.Kind == "Meter" then
				meter += s.Amount
			elseif s.Kind == "Jackpot" then
				jackpot += s.Amount
			end
		end
	end
	if jackpot > 0 then
		Juice.banner("JACKPOT EGG! +" .. jackpot .. " coins", GOLD, 1.6)
		Audio.play("MatchWin")
		local a = anchorFor(1)
		local target = Juice.coinTarget()
		if a and target then
			Juice.coinFlyFrom(a.AbsolutePosition, target, jackpot)
		end
	end
	if coins > 0 then
		pop("+" .. coins .. " coins", GOLD)
		Audio.play("CoinPickup")
	end
	if xp > 0 then
		pop("+" .. xp .. " pet XP", XP)
	end
	if meter > 0 then
		local need = tonumber(data.MeterNeed)
		local now = tonumber(data.Meter)
		pop(if now and need then string.format("Lucky Meter %d/%d", now, need) else "Lucky Meter +1", METER)
		Audio.play("LuckyMeter")
	end
end

return SurprisePop
