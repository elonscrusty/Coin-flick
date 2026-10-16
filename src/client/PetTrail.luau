--!strict
-- Golden and Rainbow follower pets leave a short sparkle trail as they move (client only, cosmetic). PetFollow calls
-- attach() on each follower it builds; the Trail lives inside the pet model, so it goes away with it. The trail is
-- tagged "PetSparkle", so the Low Effects setting turns it off and on with the other pet sparkles (PetSparkle).

local CollectionService = game:GetService("CollectionService")

local PetTrail = {}

local GOLD = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 190)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 206, 70)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 150, 30)),
})
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 0.6, 1)),
	ColorSequenceKeypoint.new(0.2, Color3.fromHSV(0.12, 0.6, 1)),
	ColorSequenceKeypoint.new(0.4, Color3.fromHSV(0.3, 0.6, 1)),
	ColorSequenceKeypoint.new(0.6, Color3.fromHSV(0.5, 0.6, 1)),
	ColorSequenceKeypoint.new(0.8, Color3.fromHSV(0.7, 0.6, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromHSV(0.85, 0.6, 1)),
})

function PetTrail.attach(model: Model, modifier: any)
	local colors = if modifier == "Golden" then GOLD elseif modifier == "Rainbow" then RAINBOW else nil
	if not colors then
		return
	end
	local body = model:FindFirstChild("Body", true)
	local part: BasePart? = if body and body:IsA("BasePart") then body else (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
	if not part then
		return
	end
	local h = tonumber(model:GetAttribute("Height")) or 1.5
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, h * 0.18, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -h * 0.18, 0)
	a1.Parent = part
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = colors
	tr.Transparency = NumberSequence.new(0.6, 1) -- a soft hint of shine, never a streak over the view
	tr.WidthScale = NumberSequence.new(1, 0.1)
	tr.Lifetime = 0.25
	tr.MinLength = 0.15
	tr.LightEmission = 0.4
	tr.FaceCamera = true
	CollectionService:AddTag(tr, "PetSparkle") -- Low Effects turns it off (PetSparkle)
	tr.Parent = part
end

return PetTrail
