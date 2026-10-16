-- Top-player statues stand upright on any pedestal (shared/StandRules, audit 2 #41).
return function(t)
	local test, shared = t.test, t.shared
	local Vector3, CFrame = t.Vector3, t.CFrame
	local R = shared("StandRules")

	local function near(a: number, b: number, msg: string)
		if math.abs(a - b) > 1e-4 then
			error(msg .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
		end
	end

	-- an avatar 6 studs tall whose pivot (root) is 3 studs above its feet
	local pivot = CFrame.new(0, 3, 0)
	local boxCF, boxSize = CFrame.new(0, 3, 0), Vector3.new(4, 6, 2)

	test("statue: upright on a cylinder pedestal turned to stand (it used to lie tipped across it)", function()
		-- a Roblox cylinder lies along X: 2 tall, 10 wide, rolled 90 degrees on Z to stand up
		local padCF = CFrame.new(50, 1, 20) * CFrame.Angles(0, math.rad(30), math.rad(90))
		local padSize = Vector3.new(2, 10, 10)
		local cf = R.onTop(padCF, padSize, pivot, boxCF, boxSize)
		near(cf.UpVector.Y, 1, "stands upright")
		near(R.topY(padCF, padSize), 2, "the pedestal top is its real highest point")
		near(cf.Position.Y - 3, 2, "feet on the pedestal top")
		near(cf.Position.X, 50, "centred X")
		near(cf.Position.Z, 20, "centred Z")
	end)

	test("statue: a plain block pedestal keeps its facing; a tilted one never tilts the statue", function()
		local padCF = CFrame.new(0, 2, 0) * CFrame.Angles(0, math.rad(90), 0)
		local cf = R.onTop(padCF, Vector3.new(6, 4, 6), pivot, boxCF, boxSize)
		near(cf.UpVector.Y, 1, "upright")
		near(cf.Position.Y, 4 + 3, "feet on top")
		near(cf.LookVector:Dot(padCF.LookVector), 1, "faces where the pedestal faces")
		local tilted = CFrame.new(0, 2, 0) * CFrame.Angles(math.rad(25), 0, math.rad(-15))
		near(R.onTop(tilted, Vector3.new(6, 4, 6), pivot, boxCF, boxSize).UpVector.Y, 1, "upright on a tilted block")
		local up = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(90), 0, 0) -- look vector straight up
		near(R.facing(up).Y, 0, "a flat facing even when the look vector is vertical")
	end)
end
