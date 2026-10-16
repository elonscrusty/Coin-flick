--!strict
-- Hatch close-up (client only, cosmetic). When the pet egg is found, the finder's camera glides from first person to
-- a close look at their own nest (CameraModeRules.nestShot) so the egg opening on the plate is the thing on screen,
-- then hands over to the full-screen reveal card (RevealView). A CameraMode cinematic: released by HatchFocus.stop
-- (Main, right before the reveal opens), by the results, or after MAX seconds whatever happens.
-- Reduce Motion: a cut instead of the glide.
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraModeRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CameraModeRules"))
local CameraMode = require(script.Parent.CameraMode)
local UI = require(script.Parent.ui.UI)

local HatchFocus = {}

local CINE = "HatchFocus"
local GLIDE = 0.7 -- seconds
local MAX = 10 -- seconds: never holds the camera longer than this
local token = 0
local tween: Tween? = nil

function HatchFocus.stop()
	token += 1
	if tween then
		tween:Cancel()
		tween = nil
	end
	CameraMode.cinematic(CINE, false)
end

-- Starts the close-up on nest plate position `plate` (nil: nothing to look at, nothing happens).
function HatchFocus.start(plate: Vector3?)
	local cam = Workspace.CurrentCamera
	if not plate or not cam then
		return
	end
	HatchFocus.stop()
	token += 1
	local mine = token
	CameraMode.cinematic(CINE, true)
	cam.CameraType = Enum.CameraType.Scriptable
	local shot = CameraModeRules.nestShot(plate, cam.CFrame.Position)
	if UI.Reduced then
		cam.CFrame = shot
	else
		local t = TweenService:Create(cam, TweenInfo.new(GLIDE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = shot })
		tween = t
		t:Play()
	end
	task.delay(MAX, function()
		if token == mine then
			HatchFocus.stop()
		end
	end)
end

return HatchFocus
