--!strict
-- What the camera and cursor should be, as one pure decision (docs/m6/FIRST_PERSON.md section 1).
-- The client coordinator (src/client/CameraMode.luau) feeds it the facts and applies the answer; nothing
-- else in the game decides camera mode, cursor or reticle.
--   Blocked   at least one blocking panel / reveal / results holds the screen (UI.block keys)
--   Cinematic a deliberate presentation camera owns the view (none by default)
--   Peek      desktop: the free-cursor key is held in a first-person hunt (Config.Camera.FreeCursorKeys), so HUD
--             buttons can be clicked without opening a menu
-- First person is a HUNT-only view (owner decision 2026-10-10): the lobby uses the normal Roblox Classic third-person
-- camera with a free mouse. `CameraModeRules.firstPerson` is that rule; FirstPerson below is its answer.
local CameraModeRules = {}

export type Inputs = { FirstPerson: boolean, Blocked: boolean, Cinematic: boolean, Peek: boolean? }

-- Is the view first person? Only when the switch is on AND the player is in a hunt (an arena round from Init until
-- Left, or the Match place of Teleport mode). The lobby is always third person.
function CameraModeRules.firstPerson(enabled: boolean, inHunt: boolean): boolean
	return enabled and inHunt
end
export type Decision = {
	Mode: string, -- "LockFirstPerson" | "Classic"
	CursorFree: boolean, -- the mouse is FREED by a menu / cinematic / peek (in third person it is free anyway)
	Reticle: boolean, -- draw the centre reticle
	Actions: boolean, -- gameplay input may act
}

function CameraModeRules.decide(i: Inputs): Decision
	local free = i.Blocked or i.Cinematic or (i.FirstPerson and i.Peek == true)
	return {
		Mode = if i.FirstPerson then "LockFirstPerson" else "Classic",
		CursorFree = free,
		Reticle = i.FirstPerson and not free,
		Actions = not free,
	}
end

-- A keyed holder set: the camera returns to play only when the LAST holder lets go. Used for the tests of the
-- modal-stack rule (UI.block is the live implementation; it has the same semantics).
export type Stack = { Keys: { [string]: boolean } }

function CameraModeRules.newStack(): Stack
	return { Keys = {} }
end

function CameraModeRules.hold(s: Stack, key: string, on: boolean): boolean -- returns blocked after the change
	if on then
		s.Keys[key] = true
	else
		s.Keys[key] = nil
	end
	return next(s.Keys) ~= nil
end

-- May an input that arrives now act? An input that was already down when the last menu closed, or arrives within
-- `grace` seconds of it, must not (closing a menu with a key cannot fire the tool).
function CameraModeRules.mayAct(blocked: boolean, now: number, unblockedAt: number, grace: number): boolean
	return not blocked and now - unblockedAt >= grace
end

-- The hatch close-up (client HatchFocus): when the pet egg is found, the finder's camera leaves first person and
-- looks down at their own nest from the side they stood on, so the in-world hatch is seen before the big reveal
-- card (walkthrough 10-14: "Pet hatched!" showed while the camera faced bare ground). `plate` = the nest plate,
-- `viewer` = where the camera was. Back NEST_BACK studs toward the viewer, NEST_UP up, looking just above the plate.
CameraModeRules.NestBack, CameraModeRules.NestUp, CameraModeRules.NestLookUp = 9, 6, 1.5
function CameraModeRules.nestShot(plate: Vector3, viewer: Vector3): CFrame
	local d = Vector3.new(viewer.X - plate.X, 0, viewer.Z - plate.Z)
	local dir = if d.Magnitude > 0.1 then d.Unit else Vector3.new(0, 0, 1)
	local eye = plate + dir * CameraModeRules.NestBack + Vector3.new(0, CameraModeRules.NestUp, 0)
	local look = (plate + Vector3.new(0, CameraModeRules.NestLookUp, 0) - eye).Unit
	local right = look:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(eye, right, right:Cross(look)) -- = CFrame.lookAt(eye, target)
end

return CameraModeRules
