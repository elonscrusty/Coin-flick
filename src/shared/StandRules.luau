--!strict
-- Standing a model upright on top of a part (lobby top-player statues, audit 2 #41: the #1 avatar lay tipped across
-- the yellow podium). The old code copied the pedestal's whole rotation, so a cylinder pedestal (Roblox cylinders
-- lie along X and are turned 90 degrees to stand) tipped the avatar over with it, and used Size.Y as the height.
-- Here only the pedestal's facing (yaw) is kept, the model's feet sit on the pedestal's real highest point, and the
-- model's own pivot offset is respected.

local StandRules = {}

-- World Y of the highest point of a box part (any rotation).
function StandRules.topY(cf: CFrame, size: Vector3): number
	local h = size / 2
	return cf.Position.Y + math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z
end

-- A flat facing direction from the pedestal: its look vector without tilt (or its up vector for a part turned on
-- its side), default -Z.
function StandRules.facing(cf: CFrame): Vector3
	for _, v in { cf.LookVector, cf.UpVector, cf.RightVector } do
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 0.1 then
			return flat.Unit
		end
	end
	return Vector3.new(0, 0, -1)
end

-- The pivot CFrame for a model standing upright on the pedestal (`padCF`, `padSize`). `pivot` is the model's current
-- pivot and `boxCF`, `boxSize` its bounding box (Model:GetBoundingBox), measured while the model stands upright.
function StandRules.onTop(padCF: CFrame, padSize: Vector3, pivot: CFrame, boxCF: CFrame, boxSize: Vector3): CFrame
	local feet = boxCF.Position.Y - boxSize.Y / 2 -- the model's lowest point
	local lift = pivot.Position.Y - feet -- pivot height above the feet
	local at = Vector3.new(padCF.Position.X, StandRules.topY(padCF, padSize) + lift, padCF.Position.Z)
	return CFrame.lookAt(at, at + StandRules.facing(padCF))
end

return StandRules
