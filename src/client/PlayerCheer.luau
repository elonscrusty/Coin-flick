--!strict
-- Winner cheer (#48): a short procedural celebration on a player's avatar, no animation upload needed.
-- Client ModuleScript (StarterPlayerScripts.Client.PlayerCheer). PlayerCheer.play(character, seconds?)
-- Both arms swing up and wave, three little hops with a happy body wiggle and one spin. Face/mouth untouched.
-- Works on R15 (Right/LeftShoulder, Waist, Root) and R6 (Right/Left Shoulder, RootJoint) by driving
-- Motor6D.Transform each frame and clearing it at the end.
local RunService = game:GetService("RunService")

local PlayerCheer = {}

local function find(char: Model, names: { string }): Motor6D?
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") then
			for _, n in names do
				if d.Name == n then
					return d
				end
			end
		end
	end
	return nil
end

function PlayerCheer.play(char: Model, seconds: number?)
	local dur = seconds or 2.4
	local hum = char:FindFirstChildOfClass("Humanoid")
	local r6 = hum ~= nil and hum.RigType == Enum.HumanoidRigType.R6
	local rs = find(char, { "RightShoulder", "Right Shoulder" })
	local ls = find(char, { "LeftShoulder", "Left Shoulder" })
	local root = find(char, { "Root", "RootJoint" })
	local waist = find(char, { "Waist" })
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in animator:GetPlayingAnimationTracks() do
			tr:AdjustWeight(0.05, 0.15) -- let the cheer show over idle
		end
	end
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local k = math.clamp(t / dur, 0, 1)
		local fade = math.min(1, t / 0.15, (dur - t) / 0.25)
		if t >= dur then
			conn:Disconnect()
			for _, m in { rs, ls, root, waist } do
				if m then
					m.Transform = CFrame.new()
				end
			end
			if animator then
				for _, tr in animator:GetPlayingAnimationTracks() do
					tr:AdjustWeight(1, 0.2)
				end
			end
			return
		end
		fade = math.max(fade, 0)
		local wave = math.sin(t * 14) * 0.35
		local up = math.rad(160) * fade
		-- arms: raised overhead (R15 shoulders rotate about X, R6 about Z), waving
		if rs then
			rs.Transform = if r6 then CFrame.Angles(0, 0, up + wave) else CFrame.Angles(up + wave, 0, 0)
		end
		if ls then
			ls.Transform = if r6 then CFrame.Angles(0, 0, -(up - wave)) else CFrame.Angles(up - wave, 0, 0)
		end
		-- body: three hops in the first 70 %, one spin on the middle hop, small wiggle
		local hopK = math.clamp(k / 0.7, 0, 1)
		local hop = math.abs(math.sin(hopK * math.pi * 3)) * 0.9 * fade * (if k < 0.7 then 1 else 0)
		local spin = if hopK > 0.34 and hopK < 0.66 then (hopK - 0.34) / 0.32 * math.pi * 2 else 0
		local wig = math.sin(t * 9) * 0.08 * fade
		if root then
			local cf = CFrame.new(0, hop, 0) * CFrame.Angles(0, spin, wig)
			root.Transform = if r6 then CFrame.new(0, 0, hop) * CFrame.Angles(0, 0, spin) else cf
		end
		if waist then
			waist.Transform = CFrame.Angles(0, wig * 2, 0)
		end
	end)
end

return PlayerCheer
