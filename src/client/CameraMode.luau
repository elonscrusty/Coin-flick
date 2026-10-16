--!strict
-- The one owner of camera mode, cursor and local avatar visibility (docs/m6/FIRST_PERSON.md,
-- docs/m11/CAMERA_SPAWN_FIX.md).
--
-- Hunt = first person; lobby = third person (owner decision 2026-10-10). In a hunt (State.Match from Init until
-- Left, or the Match place of Teleport mode) the view is Roblox's own supported first person:
-- Player.CameraMode = LockFirstPerson, so PlayerModule keeps doing the looking (mouse, touch drag, right stick).
-- In the lobby it is the normal Classic camera (free mouse, right-drag to turn, zoom Config.Camera.Lobby;
-- CameraGuard keeps it inside the lodge room). The switch happens once per transition (State.Changed "Match"
-- and CameraMode.restore). This module never runs a camera-follow loop. It writes Camera.CFrame only once per arrival in a
-- hunt (the first-person view starts looking at the pile, not wherever the lobby camera pointed: owner video, the view
-- began facing the back of the nest board), never per frame.
--
-- Desktop, first-person hunt: holding a free-cursor key (Config.Camera.FreeCursorKeys, Left / Right Alt) frees
-- the mouse so HUD buttons can be clicked; releasing it locks the view again.
--
-- Modal stack: UI.block(key, on) is the stack (every panel, the reveal and the results card hold a key).
-- The cursor is freed while ANY key is held and first person returns when the LAST one is released. A menu
-- swapped for another (close then open in the same frame) never gives a frame of mouse look: the change is
-- applied on the next deferred step from the state at that moment. The free cursor uses a Modal GuiButton,
-- the supported way to unlock the mouse under LockFirstPerson: the engine only honours it while the button is
-- Visible, inside the viewport and in an enabled ScreenGui, so it sits transparent at the top-left pixel of the
-- screen (it was off-screen at -10,-10 before, which is the likely reason the mouse stayed locked in Studio).
--
-- Lifecycle: fresh join, CharacterAdded (a new humanoid; the old one is never kept), CurrentCamera
-- replaced, and deliberate cinematics (CameraMode.cinematic) all re-apply the defaults once. A Scriptable
-- camera left behind is put back to Custom on those events (and on match transitions via
-- CameraMode.restore) unless the camera carries the attribute CT_Cinematic. No head bob here; the small lobby
-- camera trail, the speed-boots FOV and the shared big-moment shake live in CameraFx (they add an offset after the
-- default camera and take it off before its next step). Local-only visibility: LocalTransparencyModifier on the head, hats, torso and the own basket,
-- so other players still see the full avatar.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local CameraModeRules = require(Shared.CameraModeRules)
local State = require(script.Parent.State)
local UI = require(script.Parent.ui.UI)

local CameraMode = {}

CameraMode.Changed = Instance.new("BindableEvent") -- (cursorFree: boolean)

local player = Players.LocalPlayer

local started = false
local cinematicKeys: { [string]: true } = {}
local decision: CameraModeRules.Decision = CameraModeRules.decide({ FirstPerson = Config.Camera.FirstPerson, Blocked = false, Cinematic = false })
local dirty = false
local unblockedAt = -math.huge
local modalButton: TextButton? = nil
local camera: Camera? = nil
local cameraConns: { RBXScriptConnection } = {}
local charConns: { RBXScriptConnection } = {}
local hideParts: { BasePart } = {}
local hiddenRoots: { [Instance]: RBXScriptConnection } = {}
local backBound = false
local peekHeld = false -- a free-cursor key is held (desktop, first-person hunt)
local appliedFirstPerson: boolean? = nil -- the view the player properties were last set for
local aimPending = false -- first person just began (or the avatar was moved across the map): face the pile once
local lastRootPos: Vector3? = nil -- avatar root last frame (a jump of TELEPORT_STUDS = a server move to a spot)
local cinematicShown = false -- the own avatar was shown for a hunt cinematic and must be hidden again afterwards
local TELEPORT_STUDS = 15
-- Back to the lobby (bug 246): the third-person camera is put behind the avatar at a normal zoom and a gentle
-- downward pitch, never left at the first-person distance or the hunt's last look direction (which tilted to
-- the sky). It is placed again if the server moves the avatar within BEHIND_SECONDS.
local BEHIND_ZOOM = 13 -- studs from the head
local BEHIND_PITCH = math.rad(18) -- looking down at the avatar
local BEHIND_SECONDS = 4
local behindPending = false
local behindUntil = 0

-- In a hunt: an arena round from Init until Left (State.Match), or the Match place of Teleport mode.
function CameraMode.inHunt(): boolean
	return State.Match ~= nil or State.Teleport == true
end

local function firstPersonOn(): boolean
	return CameraModeRules.firstPerson(Config.Camera.FirstPerson == true, CameraMode.inHunt())
end

-- True while the player looks through their own eyes (the camera mode is first person and no cinematic holds it).
function CameraMode.firstPerson(): boolean
	return firstPersonOn() and next(cinematicKeys) == nil
end

-- True while the cursor is FREED: a menu, a cinematic or a held free-cursor key (first-person hunt). In the
-- third-person lobby the mouse is always usable; this stays false there unless a menu is open.
function CameraMode.cursorFree(): boolean
	return decision.CursorFree
end

-- Seconds since the last blocking panel closed (large when none did).
function CameraMode.sinceUnblocked(): number
	return os.clock() - math.max(unblockedAt, UI.unblockedAt())
end

-- May a gameplay input that arrives now act? False while a panel is open and for a moment after the last
-- one closed, so the key or tap that closed a menu cannot also pick up a rock or swing the tool.
function CameraMode.mayAct(): boolean
	return CameraModeRules.mayAct(UI.blocked() or decision.CursorFree, os.clock(), math.max(unblockedAt, UI.unblockedAt()), Config.Camera.GraceAfterModal)
end

-- Local-only hiding ---------------------------------------------------------------------------------

local function isHidden(part: BasePart, char: Model): boolean
	-- the upper arms sit beside the eye and loom over the view; forearms, hands and the held tool stay
	if part.Name == "LeftUpperArm" or part.Name == "RightUpperArm" then
		return part.Parent == char
	end
	if part.Name == "Head" or part.Name == "UpperTorso" or part.Name == "LowerTorso" or part.Name == "Torso" then
		return part.Parent == char
	end
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
end

local function bindCharacter(char: Model?)
	for _, c in charConns do
		c:Disconnect()
	end
	table.clear(charConns)
	table.clear(hideParts)
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") and isHidden(d, char) then
			table.insert(hideParts, d)
		end
	end
	-- accessories and clothing can arrive after the spawn: keep the list current without per-frame searching
	table.insert(charConns, char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and isHidden(d, char) then
			table.insert(hideParts, d)
		end
	end))
	table.insert(charConns, char.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			local i = table.find(hideParts, d)
			if i then
				table.remove(hideParts, i)
			end
		end
	end))
end

local function setLocal(inst: Instance, value: number)
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= value then
			d.LocalTransparencyModifier = value
		end
	end
end

-- A model that must not block the first-person view (the own carry basket). Its parts are hidden locally
-- while the view is first person and shown again otherwise; parts added later are covered too.
function CameraMode.hideLocally(root: Instance)
	if hiddenRoots[root] then
		return
	end
	hiddenRoots[root] = root.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and CameraMode.firstPerson() then
			d.LocalTransparencyModifier = 1
		end
	end)
	if CameraMode.firstPerson() then
		setLocal(root, 1)
	end
end

function CameraMode.showLocally(root: Instance)
	local conn = hiddenRoots[root]
	if not conn then
		return
	end
	conn:Disconnect()
	hiddenRoots[root] = nil
	if root.Parent then
		setLocal(root, 0)
	end
end

local FADE_ARMS: { [string]: boolean } = { LeftLowerArm = true, RightLowerArm = true, LeftHand = true, RightHand = true }
-- The own held tool and forearms are hidden locally in first person.
local function fadeTool(char: Model, camPos: Vector3)
	-- the own held tool is never drawn from the avatar's hand in first person: it ghosts large at the lower right.
	-- A small copy rests at the edge (CarryGlimpse) and the work stroke has its own copy (StationView).
	local tool = char:FindFirstChild("CT_Rocks_HeldTool")
	if tool then
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") and d.LocalTransparencyModifier ~= 1 then
				d.LocalTransparencyModifier = 1
			end
		end
	end
	for name in FADE_ARMS do
		local a = char:FindFirstChild(name)
		if a and a:IsA("BasePart") and a.LocalTransparencyModifier ~= 1 then
			-- the own forearms and hands are never drawn in first person (a skin-coloured block over the work view);
			-- the held tool stays visible and is carried by the stroke animation
			a.LocalTransparencyModifier = 1
		end
	end
end

-- A hunt cinematic (the countdown swoop, the reveal) looks at the avatar from outside, but first person had hidden the
-- whole body locally while its held tool came back with every re-attach: owner video, a pink hammer floating alone over
-- the nest. While a hunt cinematic holds the camera the own avatar is shown whole (tool in its hand), fading out only
-- as the camera reaches the eyes (the swoop ends there).
local function cinematicBody(char: Model, camPos: Vector3)
	local head = char:FindFirstChild("Head")
	local d = if head and head:IsA("BasePart") then (camPos - head.Position).Magnitude else math.huge
	local v = math.clamp((5 - d) / 2.5, 0, 1)
	setLocal(char, v)
	cinematicShown = true
end

-- First person starts facing the pile (the spawn spots face it; RoundIntro's swoop ends the same way): the arena
-- centre when the round names it, else the avatar's own facing. Slightly down, like the swoop's last frame.
local function aimAtPile(cam: Camera, char: Model)
	local head = char:FindFirstChild("Head")
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not (head and head:IsA("BasePart") and rootPart and rootPart:IsA("BasePart")) then
		return
	end
	local eye = cam.CFrame.Position
	local m = State.Match
	local centre: Vector3? = if m and typeof(m.Center) == "Vector3" then m.Center else nil
	local flatDir = if centre then Vector3.new(centre.X - eye.X, 0, centre.Z - eye.Z) else Vector3.zero
	if flatDir.Magnitude < 1 then
		local look = rootPart.CFrame.LookVector
		flatDir = Vector3.new(look.X, 0, look.Z)
	end
	if flatDir.Magnitude < 1e-3 then
		return
	end
	cam.CFrame = CFrame.lookAt(eye, eye + flatDir.Unit * 10 - Vector3.new(0, 2.5, 0))
end

-- Third person behind the avatar at BEHIND_ZOOM. The zoom is pinned for a moment (min = max) so PlayerModule takes
-- it instead of keeping the first-person distance, then the lobby range comes back.
local zoomToken = 0
local function placeBehind(cam: Camera, rootPart: BasePart)
	if cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, -1)
	local focus = rootPart.Position + Vector3.new(0, 2, 0)
	local eye = focus - flatLook * (BEHIND_ZOOM * math.cos(BEHIND_PITCH)) + Vector3.new(0, BEHIND_ZOOM * math.sin(BEHIND_PITCH), 0)
	cam.CFrame = CFrame.lookAt(eye, focus)
	local L = Config.Camera.Lobby
	local zoom = math.clamp(BEHIND_ZOOM, L.MinZoom, L.MaxZoom)
	zoomToken += 1
	local token = zoomToken
	player.CameraMaxZoomDistance = math.max(zoom, player.CameraMinZoomDistance)
	player.CameraMinZoomDistance = zoom
	player.CameraMaxZoomDistance = zoom
	task.delay(0.3, function()
		if token == zoomToken and not firstPersonOn() then
			player.CameraMaxZoomDistance = L.MaxZoom -- raise the maximum first so it never sits below the minimum
			player.CameraMinZoomDistance = L.MinZoom
		end
	end)
end

local function step()
	local cam = camera
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local moved = false
	if rootPart and rootPart:IsA("BasePart") then
		local pos = rootPart.Position
		if lastRootPos and (pos - lastRootPos).Magnitude > TELEPORT_STUDS then
			aimPending = true -- placed on a hunt spot (or back on it after a fall)
			moved = true
		end
		lastRootPos = pos
	end
	if not CameraMode.firstPerson() and cam and rootPart and rootPart:IsA("BasePart") and next(cinematicKeys) == nil then
		if moved and os.clock() < behindUntil then
			behindPending = true -- the server moved the avatar to the lobby after the hunt ended
		end
		if behindPending and cam:GetAttribute("CT_Cinematic") ~= true then
			behindPending = false
			placeBehind(cam, rootPart)
		end
	end
	if CameraMode.inHunt() and next(cinematicKeys) ~= nil then
		if cam and char then
			cinematicBody(char, cam.CFrame.Position)
		end
		aimPending = false -- the cinematic hands over looking at the pile itself
		return
	end
	if not CameraMode.firstPerson() then
		return
	end
	if cinematicShown and char then
		-- back to first person: PlayerModule only writes its transparency on change, so hide the body here once
		cinematicShown = false
		setLocal(char, 1)
	end
	if aimPending and cam and char and CameraMode.inHunt() then
		aimPending = false
		aimAtPile(cam, char)
	end
	-- runs after PlayerModule's own transparency pass (it also touches these parts)
	for _, p in hideParts do
		if p.LocalTransparencyModifier ~= 1 then
			p.LocalTransparencyModifier = 1
		end
	end
	if cam and char then
		fadeTool(char, cam.CFrame.Position)
	end
end

-- Applying the decision -----------------------------------------------------------------------------

local function ensureModalButton()
	if modalButton and modalButton.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CT_CameraMode"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Name = "FreeCursor"
	b.Text = ""
	b.Modal = true
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	-- inside the viewport (top-left pixel, under the Roblox menu button), fully transparent: an off-screen Modal
	-- button is not honoured by the engine, so the mouse stayed locked
	b.Size = UDim2.fromOffset(1, 1)
	b.Position = UDim2.fromOffset(0, 0)
	b.AutoButtonColor = false
	b.Selectable = false
	b.Active = false
	b.Visible = false
	b.Parent = gui
	modalButton = b
end

local function bindBack(on: boolean)
	if on == backBound then
		return
	end
	backBound = on
	if on then
		-- gamepad B (and Escape on a keyboard) closes the open panel; the press is sunk so nothing else reacts to it
		ContextActionService:BindActionAtPriority("CTR_ModalBack", function(_, state)
			if state == Enum.UserInputState.Begin and UI.topOpen() ~= nil then
				UI.closeTop() -- a confirmation dialog first, then the menu under it
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	else
		ContextActionService:UnbindAction("CTR_ModalBack")
	end
end

-- Suspending look and move while a blocking panel owns the screen ---------------------------------------
-- Cause of the world turning behind a menu (owner recording 2026-10-09, NOT reproduced offline: the mock has no
-- PlayerModule): freeing the cursor only unlocks the mouse. PlayerModule keeps reading look input (mouse delta
-- while the engine reports LockCenter, right-drag, right stick, touch drag) and move input (WASD, left stick), so
-- the view could still turn and the avatar still walk behind the panel. One place now switches all of it off and
-- back on, from the same decision that frees the cursor: the supported Controls:Disable() / Enable() for move and
-- jump, CameraInput.setInputEnabled(false) for look when that module exposes it, and a sunk action for the move
-- keys and both sticks as a belt (look input that bypasses CameraInput is still eaten). No per-frame camera writes.
local controlsObj: any = nil
local cameraInputObj: any = nil
local inputResolved = false
local inputSuspended = false
local moveSuspended = false
local SINK_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2,
}

local function resolveInput()
	if inputResolved then
		return
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	local pm = scripts and scripts:FindFirstChild("PlayerModule")
	if not (pm and pm:IsA("ModuleScript")) then
		return -- not there yet (or the offline preview): try again on the next change
	end
	inputResolved = true
	local ok, mod = pcall(require, pm)
	if ok and type(mod) == "table" then
		local okc, c = pcall(function()
			return mod:GetControls()
		end)
		if okc then
			controlsObj = c
		end
	end
	local cm = pm:FindFirstChild("CameraModule")
	local ci = cm and cm:FindFirstChild("CameraInput")
	if ci and ci:IsA("ModuleScript") then
		local ok2, m = pcall(require, ci)
		if ok2 and type(m) == "table" and type(m.setInputEnabled) == "function" then
			cameraInputObj = m
		end
	end
end

-- `move`: walking/jumping is suspended too (a menu or cinematic holds the screen). The desktop free-cursor peek
-- (Alt held in a hunt) only suspends the look input: the player keeps walking while the mouse is free (audit 15).
local function suspendInput(on: boolean, move: boolean)
	local moveOn = on and move
	if on == inputSuspended and moveOn == moveSuspended then
		return
	end
	local lookChanged = on ~= inputSuspended
	local moveChanged = moveOn ~= moveSuspended
	inputSuspended = on
	moveSuspended = moveOn
	resolveInput()
	if controlsObj and moveChanged then
		pcall(function()
			if moveOn then
				controlsObj:Disable()
			else
				controlsObj:Enable()
			end
		end)
	end
	if cameraInputObj and lookChanged then
		pcall(function()
			cameraInputObj.setInputEnabled(not on)
		end)
	end
	if moveChanged then
		if moveOn then
			ContextActionService:BindActionAtPriority("CTR_ModalSink", function()
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, table.unpack(SINK_KEYS))
		else
			ContextActionService:UnbindAction("CTR_ModalSink")
		end
	end
end
CameraMode.suspendedInput = function(): boolean
	return inputSuspended
end

-- The own body comes back once when first person ends (PlayerModule's transparency pass only writes on change,
-- so a 1 left by the first-person hiding would otherwise stay).
local function showOwnBody()
	local char = player.Character
	cinematicShown = false
	if char then
		setLocal(char, 0)
	end
end

local function applyDefaults()
	local fp = firstPersonOn()
	if fp then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5 -- lower the minimum first so it never exceeds the maximum
		player.CameraMaxZoomDistance = 0.5
	else
		local L = Config.Camera.Lobby
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = L.MaxZoom -- raise the maximum first so it never sits below the minimum
		player.CameraMinZoomDistance = L.MinZoom
	end
	if appliedFirstPerson ~= fp then
		local was = appliedFirstPerson
		appliedFirstPerson = fp
		aimPending = fp -- a hunt began: its first-person view starts facing the pile
		if not fp then
			if was == true then
				showOwnBody()
				behindPending = true -- back from a hunt: camera behind the avatar at a normal zoom (bug 246)
				behindUntil = os.clock() + BEHIND_SECONDS
			end
			-- third person: the ordinary free mouse (right-drag turns the view)
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end

local function apply()
	dirty = false
	local was = decision
	if appliedFirstPerson ~= firstPersonOn() then
		applyDefaults() -- a hunt began or ended since the last apply
	end
	decision = CameraModeRules.decide({ FirstPerson = firstPersonOn(), Blocked = UI.blocked(), Cinematic = next(cinematicKeys) ~= nil, Peek = peekHeld })
	if was.CursorFree and not decision.CursorFree then
		unblockedAt = os.clock()
	end
	ensureModalButton()
	if modalButton then
		modalButton.Visible = decision.CursorFree
	end
	suspendInput(decision.CursorFree, UI.blocked() or next(cinematicKeys) ~= nil)
	if firstPersonOn() then
		if decision.CursorFree then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif was.CursorFree then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		-- the reticle is the pointer while the view is locked; the arrow shows whenever the mouse is free
		UserInputService.MouseIconEnabled = decision.CursorFree
	else
		UserInputService.MouseIconEnabled = true -- third person: always the normal cursor
	end
	bindBack(UI.topOpen() ~= nil)
	if was.CursorFree ~= decision.CursorFree then
		CameraMode.Changed:Fire(decision.CursorFree)
	end
	local hide = if CameraMode.firstPerson() then 1 else 0
	for root in hiddenRoots do
		setLocal(root, hide)
	end
end

local function markDirty()
	if dirty then
		return
	end
	dirty = true
	task.defer(function()
		if dirty then
			apply()
		end
	end)
end

-- Put the camera back to normal play: Custom type on the current humanoid, the default field of view.
-- Called on spawn, camera replacement, lobby return, rematch and result transitions. A deliberate
-- cinematic (key held or CT_Cinematic attribute) is left alone.
function CameraMode.restore()
	applyDefaults()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	if next(cinematicKeys) == nil and cam:GetAttribute("CT_Cinematic") ~= true then
		if cam.CameraType == Enum.CameraType.Scriptable or cam.CameraType == Enum.CameraType.Fixed then
			cam.CameraType = Enum.CameraType.Custom
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and cam.CameraSubject ~= hum then
			cam.CameraSubject = hum
		end
		if firstPersonOn() and cam.CameraType == Enum.CameraType.Custom and math.abs(cam.FieldOfView - Config.Camera.Fov) > 0.01 then
			cam.FieldOfView = Config.Camera.Fov
		end
	end
	markDirty()
end

-- A deliberate presentation camera: while any key is held the cursor is free and first person is suspended.
-- Releasing the last key restores first person (the default camera script takes over again, so a stale
-- arena position can never come back).
function CameraMode.cinematic(key: string, on: boolean)
	local had = next(cinematicKeys) ~= nil
	if on then
		cinematicKeys[key] = true
	else
		cinematicKeys[key] = nil
	end
	if had and next(cinematicKeys) == nil then
		CameraMode.restore()
	end
	markDirty()
end

local function bindCamera(cam: Camera?)
	for _, c in cameraConns do
		c:Disconnect()
	end
	table.clear(cameraConns)
	camera = cam
	if not cam then
		return
	end
	CameraMode.restore()
	-- something left it Scriptable without a cinematic: take it back once, on the change
	table.insert(cameraConns, cam:GetPropertyChangedSignal("CameraType"):Connect(function()
		if cam.CameraType == Enum.CameraType.Scriptable and next(cinematicKeys) == nil and cam:GetAttribute("CT_Cinematic") ~= true then
			task.defer(CameraMode.restore)
		end
	end))
end

function CameraMode.start()
	if started then
		return
	end
	started = true
	applyDefaults()
	bindCharacter(player.Character)
	player.CharacterAdded:Connect(function(char)
		bindCharacter(char)
		CameraMode.restore() -- a new humanoid: the camera subject and defaults come back
		if not firstPersonOn() then
			behindPending = true -- a lobby (re)spawn starts with the camera behind the new avatar
		end
	end)
	player.CharacterRemoving:Connect(function()
		bindCharacter(nil)
	end)
	bindCamera(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
	end)
	UI.BlockChanged.Event:Connect(markDirty)
	-- lobby <-> hunt: switch the view once per transition (Init sets State.Match, Left clears it)
	State.Changed.Event:Connect(function(what)
		if what == "Match" and appliedFirstPerson ~= firstPersonOn() then
			CameraMode.restore()
		end
	end)
	-- desktop free-cursor keys (first-person hunt only): held = mouse free for the HUD, released = view locked again
	local function isPeekKey(code: Enum.KeyCode): boolean
		return table.find(Config.Camera.FreeCursorKeys, code.Name) ~= nil
	end
	UserInputService.InputBegan:Connect(function(input)
		if isPeekKey(input.KeyCode) and not peekHeld then
			peekHeld = true
			markDirty()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isPeekKey(input.KeyCode) and peekHeld then
			peekHeld = false
			markDirty()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		if peekHeld then
			peekHeld = false -- switching windows: the key-up never arrives
			markDirty()
		end
	end)
	RunService:BindToRenderStep("CTR_CameraMode", Enum.RenderPriority.Camera.Value + 2, step)
	apply()
end

return CameraMode
