-- settings: the SETTINGS panel from the HUD button.
local C = lib("ctr")
C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.Cash = 1250
	end,
})
C.settle(1)
C.tap("^SETTINGS$")
C.settle(1)
C.followCamera()
