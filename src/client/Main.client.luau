--!strict
-- Client boot: UI, pile view, onboarding hints and markers, server event wiring.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MapNames = require(Shared.MapNames)
local ParkConfig = require(Shared.ParkConfig)
local HintRules = require(Shared.HintRules)
local State = require(script.Parent.State)
local PileView = require(script.Parent.PileView)
local StationView = require(script.Parent.StationView)
local SurprisePop = require(script.Parent.SurprisePop)
local MachineView = require(script.Parent.MachineView)
local RevealView = require(script.Parent.RevealView)
local HatchFocus = require(script.Parent.HatchFocus)
local PromptArbiter = require(script.Parent.PromptArbiter)
local CameraGuard = require(script.Parent.CameraGuard)
local CameraMode = require(script.Parent.CameraMode)
local Reticle = require(script.Parent.Reticle)
local CarryGlimpse = require(script.Parent.CarryGlimpse)
local UI = require(script.Parent.ui.UI)
local Hud = require(script.Parent.ui.Hud)
local PartyPanel = require(script.Parent.ui.PartyPanel)
local ShopPanel = require(script.Parent.ui.ShopPanel)
local CollectionPanel = require(script.Parent.ui.CollectionPanel)
local MyPetsPanel = require(script.Parent.ui.MyPetsPanel)
local SettingsPanel = require(script.Parent.ui.SettingsPanel)
local Results = require(script.Parent.ui.ResultsPanel)
local Audio = require(script.Parent.Audio)
local Effects = require(script.Parent.Effects)
local LaunchPanel = require(script.Parent.ui.LaunchPanel)
local InspectPanel = require(script.Parent.ui.InspectPanel)
local RobuxShopPanel = require(script.Parent.ui.RobuxShopPanel)
local PetShop = require(script.Parent.ui.PetShop)
local Juice = require(script.Parent.ui.Juice)

local player = Players.LocalPlayer

Audio.init()
require(script.Parent.SoundCueView).start() -- moment sounds heard from server messages (shared/SoundCues)

local function confirmReturn()
	local m = State.Match
	if not m then
		return
	end
	if m.Phase == "Results" or m.Phase == "Reveal" then
		Net.event("MatchAction"):FireServer("Return")
		return
	end
	UI.confirm({
		Name = "ConfirmReturn",
		Title = "Leave this hunt?",
		Message = "You go back to the lobby and can't win this hunt. Candy you earned is kept.",
		Icon = "exit",
		Confirm = "LEAVE",
		Cancel = "STAY",
		Style = "red",
		OnConfirm = function()
			Net.event("MatchAction"):FireServer("Return")
		end,
	})
end

local panels = {
	Party = PartyPanel.open,
	Shop = ShopPanel.open,
	RobuxShop = function()
		PetShop.open() -- EGG SHOP hut prompt (Panel attribute): the new Pet Shop look (trial 2026-10-15)
	end,
	EggShrine = function() -- hatch stand "Buy Eggs" prompt: the Pet Shop's Eggs tab priced in coins
		PetShop.setPayCoins(true)
		PetShop.open("Eggs")
	end,
	Collection = CollectionPanel.open,
	PetIndex = function() -- PET INDEX shop in the lobby's shop square
		CollectionPanel.open("Index")
	end,
	MyPets = function() -- MY PETS (lobby HUD button and the MY PETS shop in the shop square): the team and collection
		MyPetsPanel.open()
	end,
	Settings = SettingsPanel.open,
	ConfirmReturn = confirmReturn,
	Results = Results.open,
}

local function openPanel(name: string)
	if name == "ConfirmReturn" then
		confirmReturn()
		return
	end
	if UI.modalOpen() == name then
		UI.closeModal()
		return
	end
	local fn = panels[name]
	if fn then
		fn()
	end
end

-- Onboarding ------------------------------------------------------------------------------
-- One concise hint at a time (Hud), plus a small marker over the station it points at.
-- Steps are tracked on the server (profile.Onboard) and never repeat once done or skipped.

local function onboarding()
	local prof = State.Profile
	if not prof or prof.OnboardDone or not prof.Onboard then
		return nil
	end
	return prof.Onboard
end

local GOAL_TEXT_PREFIX = "Nice! You have "

-- A hunt in progress (countdown, searching, securing): arena hints only. Lobby-only hints (gallery,
-- selling) wait until the player is back in the lobby or on the results screen, and arena hints
-- never show in the lobby.
local function inHunt(m: any): boolean
	return m ~= nil and (m.Phase == "Countdown" or m.Phase == "Searching" or m.Phase == "RewardPending")
end

local function ownStation(m: any): any?
	for _, st in (m and m.Stations) or {} do
		if st.UserId == player.UserId then
			return st
		end
	end
	return nil
end

-- The input the hint wording is for (shared/HintRules: touch players are never told to press a key, bug #221).
local function inputKind(): HintRules.Input
	return HintRules.inputKind(UserInputService:GetLastInputType().Name, UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
end

-- Arena guidance follows what the player is doing: pick up -> walk to the table -> deposit -> crush
-- -> keep going until the geode. Each part ends for good once the server has seen the step.
local function huntHint(ob: any, m: any): string?
	if m.Phase ~= "Searching" then
		return nil
	end
	local st = ownStation(m)
	if not st then
		return nil
	end
	local basket = #st.Basket
	local carryCap = st.CarryCap or Config.Carry.Capacity -- basket upgrades raise it (a 4/5 basket is not full)
	local queued = #st.Queue + (if st.Current then 1 else 0)
	local ctx = PileView.context()
	if not ob.Cracked then
		-- the hint follows the action button: DEPOSIT up at the nest always means "deposit" (eggs already waiting or not)
		if ctx.Id == "deposit" and basket > 0 then
			return "Tap DEPOSIT EGGS!"
		elseif queued > 0 then
			if ctx.Id == "crush" then
				return "Hold HATCH! to hatch your egg!"
			end
			return "Stand at your nest, hold HATCH!"
		elseif basket >= carryCap then
			return "Basket full! Follow the arrow to your nest."
		elseif basket > 0 then
			if ctx.Id == "deposit" then
				return "Tap DEPOSIT EGGS!"
			elseif ctx.Id == "pickup" then
				return "Nice! Grab more eggs (up to " .. carryCap .. ") or carry them to YOUR nest."
			end
			return "Follow the arrow to your nest!"
		end
		if ob.PickedUp then
			return nil -- the player has picked eggs up already: the controls tip has done its job (bug #221)
		end
		return HintRules.pickupTip(inputKind()) -- goal + action in one line (walkthrough 10-14 #9)
	end
	if not ob.Geode then
		return HintRules.candyTip(inputKind())
	end
	return nil
end

local function rawHintText(): string?
	local ob = onboarding()
	local prof = State.Profile
	local m = State.Match
	if not ob or not prof or prof.Settings.Hints == false then
		return nil
	end
	if inHunt(m) then
		return huntHint(ob, m)
	end
	-- results: the specimen is in the collection now
	if m and m.Phase == "Results" and State.Results and State.Results.Winner == player.UserId and State.Results.Kind ~= "Tutorial" and not ob.Displayed then
		return "Your new pet is in your Pet Book!"
	end
	if m and m.Phase ~= "Results" then
		return nil -- reveal: the picture is the hint
	end
	if prof.StarterEgg == true and not m then
		return nil -- the starter egg (its glow, tag and arrow) is the only lobby cue until it hatches (Studio 2026-10-15)
	end
	if ob.Geode and not ob.Displayed and #prof.Inventory > 0 then
		if m then
			return "Tap LOBBY, then put your pet in your pen!"
		end
		return "Tap PET BOOK! Then tap PLACE ON DISPLAY!"
	end
	-- selling candy comes after the pet steps: the pet loop first, coins second
	if not ob.Sold and prof.Rubble > 0 and not m then
		return "Sell candy at the candy stand for coins!"
	end
	if ob.Geode and ob.Displayed and not ob.Goal and not m then
		local h = Config.Handhelds.SteelHammer
		return GOAL_TEXT_PREFIX .. UI.money(prof.Cash) .. "! Buy upgrades! The " .. h.Name .. " costs " .. UI.money(h.Price) .. ": tap UPGRADES!"
	end
	return nil
end
-- Hint lifetime (shared/HintRules, bugs #216 / #221): a hint hides for good once its step is done, and retires for
-- the session after its timeout on screen (a menu over it pauses the clock).
local hintState = HintRules.new()
local hintClock = os.clock()
local function hintText(): string?
	local ob = onboarding()
	if ob and ob.PickedUp then
		HintRules.done(hintState, HintRules.PickupKey)
	end
	local text = rawHintText()
	local now = os.clock()
	local dt = now - hintClock
	hintClock = now
	if not text then
		return nil
	end
	local timeout: number? = nil
	if State.Match == nil then
		timeout = HintRules.Timeout.Lobby
	elseif HintRules.key(text) == HintRules.PickupKey then
		timeout = HintRules.Timeout.Pickup
	end
	local onScreen = not UI.blocked() and UI.modalOpen() == nil
	if not HintRules.visible(hintState, HintRules.key(text), timeout, onScreen, dt) then
		return nil
	end
	return text
end
Hud.hintText = hintText

-- small "here" marker over a world part
local marker: BillboardGui? = nil

-- The marker steps aside while a menu covers the screen and while the avatar is in the pet tower (the target is far
-- away there); it comes back as soon as the screen is clear. It also waits while the top objective card shows (START
-- YOUR FIRST HUNT): one guidance cue at a time, and the gold chip (AlwaysOnTop, fixed 176 px) over a far-off sell
-- stand or plot sign sat right behind that card, so only its lower half peeked out under it as a stray gold tab.
local function syncMarkerVisible()
	if marker then
		local want = not UI.blocked() and UI.modalOpen() == nil and player:GetAttribute("InTower") ~= true
			and player:GetAttribute("InBattle") ~= true and player:GetAttribute("MatchKey") == nil and not Hud.objectiveShown()
		if marker.Enabled ~= want then
			marker.Enabled = want
		end
	end
end
UI.ModalChanged.Event:Connect(syncMarkerVisible)
UI.BlockChanged.Event:Connect(syncMarkerVisible)
player:GetAttributeChangedSignal("InTower"):Connect(syncMarkerVisible)
player:GetAttributeChangedSignal("InBattle"):Connect(syncMarkerVisible)
player:GetAttributeChangedSignal("MatchKey"):Connect(syncMarkerVisible)

local function setMarker(target: BasePart?, text: string?)
	if not target then
		if marker then
			marker:Destroy()
			marker = nil
		end
		return
	end
	if marker and marker.Adornee == target then
		return
	end
	if marker then
		marker:Destroy()
	end
	local g = Instance.new("BillboardGui")
	g.Name = "CT_Rocks_Marker"
	g.Size = UDim2.fromOffset(176, 46) -- read from the path on a phone (bug #217: the 110 x 32 chip was unreadable)
	-- world up, not camera up: the chip stays over its target as the camera turns; just above a sign, higher over a floor
	g.StudsOffsetWorldSpace = Vector3.new(0, if target.Name == MapNames.PlotFloor then 14 else target.Size.Y / 2 + 2.5, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 600 -- never drawn from the far-off tower or hunt arenas (AlwaysOnTop showed it through their walls)
	g.Adornee = target
	g.Parent = player:WaitForChild("PlayerGui")
	local f = UI.frame(g, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Colors.Gold })
	UI.corner(f, 12)
	UI.stroke(f, UI.Colors.PanelEdge, 3)
	local mt = UI.text(f, text or "HERE", { Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), Font = UI.Head, TextSize = UI.T.Head + 4, TextColor3 = UI.Colors.DarkText, TextXAlignment = Enum.TextXAlignment.Center })
	mt.TextWrapped = false
	UI.fit(mt, UI.T.Head + 4, UI.T.Body)
	if not UI.Reduced then
		-- pulse once, then stay still
		local s = Instance.new("UIScale")
		s.Parent = f
		s.Scale = 1.25
		TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	marker = g
	syncMarkerVisible()
end

local HOPPER_RESCAN = 5 -- seconds
local hopperModels: { Model } = {}
local hopperScanAt = -math.huge
local function nearestHopper(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	-- the hopper list is rescanned at most every 5 s (this runs every 0.5 s during the sell tutorial step)
	if os.clock() - hopperScanAt >= HOPPER_RESCAN then
		hopperScanAt = os.clock()
		table.clear(hopperModels)
		for _, d in Workspace:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Hopper") then
				table.insert(hopperModels, d)
			end
		end
	end
	local best, bestD = nil, math.huge
	for _, d in hopperModels do
		if not d:IsDescendantOf(Workspace) then
			continue
		end
		local body = d:FindFirstChild("Body") :: BasePart?
		if body then
			local dist = (body.Position - root.Position).Magnitude
			if dist < bestD and dist < 200 then
				best, bestD = body, dist
			end
		end
	end
	return best
end

local alcoveAnchor: Part? = nil
local function myAlcove(): BasePart?
	-- the plot model (shared/MapNames: Plot<i>, hand-built or the procedural fallback) and its yard floor
	local idx = player:GetAttribute("Alcove")
	if type(idx) ~= "number" then
		return nil
	end
	local a = Workspace:FindFirstChild(MapNames.plot(idx), true)
	-- the plot's gate sign, so the chip sits on a post instead of floating over the empty yard
	if a then
		for _, n in MapNames.PlotSign do
			local sign = a:FindFirstChild(n, true)
			local sp = if sign and sign:IsA("BasePart") then sign elseif sign and sign:IsA("Model") then sign.PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true) else nil
			if sp then
				return sp
			end
		end
	end
	local f = a and a:FindFirstChild(MapNames.PlotFloor, true)
	if f and f:IsA("BasePart") then
		return f
	end
	-- StreamingEnabled: the plot model can be here before its floor streams in (far plot). Mark its pivot with a
	-- local anchor until then; this runs every 0.5 s, so the real floor takes over once it arrives.
	if a and a:IsA("Model") then
		local anchor = alcoveAnchor
		if not anchor or not anchor.Parent then
			local p = Instance.new("Part")
			p.Name = "CT_Rocks_PlotMarker"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.new(1, 1, 1)
			p.Parent = Workspace
			alcoveAnchor = p
			anchor = p
		end
		local pa = anchor :: Part
		local pos = a:GetPivot().Position
		if (pa.Position - pos).Magnitude > 0.5 then
			pa.Position = pos
		end
		return pa
	end
	return nil
end

-- Yellow outline on the own crushing table while the tutorial asks the player to go there.
local tableLight: Highlight? = nil
local function setTableHighlight(model: Model?)
	if not model then
		if tableLight then
			tableLight.Enabled = false
			tableLight.Adornee = nil
		end
		return
	end
	if not tableLight then
		local f = Instance.new("Folder")
		f.Name = "CT_Rocks_TableHighlight"
		f.Parent = Workspace
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = Config.Palette.Yellow
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = f
		tableLight = h
	end
	local h = tableLight :: Highlight
	h.Adornee = model
	h.Enabled = true
end

local function updateMarker()
	local ob = onboarding()
	local prof = State.Profile
	local m = State.Match
	if player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true then
		setMarker(nil)
		setTableHighlight(nil)
		return
	end
	if not ob or not prof then
		setMarker(nil)
		setTableHighlight(nil)
		return
	end
	if inHunt(m) then
		-- arena: the table the tutorial points at (no lobby markers while hunting)
		local st = ownStation(m)
		local want = st ~= nil and m.Phase == "Searching" and not ob.Deposited and #st.Basket > 0 and prof.Settings.Hints ~= false
		setMarker(nil)
		setTableHighlight(if want then StationView.ownModel() else nil)
		return
	end
	setTableHighlight(nil)
	if not ob.Sold and prof.Rubble > 0 then
		setMarker(nearestHopper(), "SELL HERE")
	elseif ob.Geode and not ob.Displayed and not m then
		setMarker(myAlcove(), ParkConfig.YourPlot)
	else
		setMarker(nil)
	end
end

-- Boot --------------------------------------------------------------------------------------

Hud.setPanelOpener(openPanel)
Hud.build()
PileView.start()
PromptArbiter.start()
CameraGuard.start() -- third-person camera guard (the lobby; steps aside in first person)
CameraMode.start() -- third-person lobby / first-person hunt, cursor, modal stack, local visibility (docs/m11/CAMERA_SPAWN_FIX.md)
Reticle.start()
CarryGlimpse.start()
MachineView.start()
require(script.Parent.EggFx).start() -- egg wobble hint + speed boots badge / sparkles (cosmetic)
PileView.Claimed.Event:Connect(function(uid, ids, seconds)
	MachineView.batch(uid, #ids, seconds or 1)
end)
-- A machine-cracked rock: if the round then reports it as the find, the machine glints (below).
local machineCracks: { [number]: number } = {}
PileView.Cracked.Event:Connect(function(id, _mine, viaMachine, uid)
	if viaMachine and type(uid) == "number" then
		machineCracks[id] = uid
	end
end)
PileView.Notice.Event:Connect(function(text, kind)
	Hud.toast(text, kind)
end)
PartyPanel.start()
require(script.Parent.ui.PlayButton).start() -- lobby PLAY button and hunt-queue card (PartyAction Queue / Unqueue)
require(script.Parent.SelfHide).start() -- own avatar hidden in every fight view (Pet Battle, tower climb)
require(script.Parent.StarterEggView).start() -- the free starter egg next to the spawn (RetentionAction "Starter")
require(script.Parent.RetentionView).start() -- FREE GIFT timer, away nest card, friend gifts, level-up pops
require(script.Parent.SpinView).start() -- SPIN card: free spin wheel every 4 hours (server rolls and pays)
require(script.Parent.VoidStatueFx).start() -- the Void Dragon statue breathes, sparkles orbit, "1 in 1000" pulses
require(script.Parent.ui.NewsPopup).start() -- WHAT'S NEW pop-up, once per new version (shared/WhatsNew)
ShopPanel.start()
RobuxShopPanel.start()
PetShop.start()
require(script.Parent.HatchStandView).start() -- bought eggs hatch at the public hatch stand (cosmetic)
CollectionPanel.start()
MyPetsPanel.start()
MyPetsPanel.onDisplayFull = CollectionPanel.openPlacing
CollectionPanel.onTeamFull = MyPetsPanel.openSwap
Results.start()
InspectPanel.start()
require(script.Parent.UpgradePreview).start() -- client-local preview pedestal at the Upgrades counter
require(script.Parent.LobbyAmbience).start() -- lobby life: tree sway, waterfall, butterflies, birds (client only)
require(script.Parent.LodgeLight).start() -- warm interior fill while the camera is inside the lodge (client only)
require(script.Parent.PetFollow).start() -- equipped pets follow their owners (client only, cosmetic)
require(script.Parent.PetLevelFx).start() -- level-up ring + "LEVEL UP" over a following pet (client only)
require(script.Parent.PetDisplay).start() -- PetMotion on server-built mesh pets (bones do not replicate)
require(script.Parent.PetSparkle).start() -- rare pet sparkles follow the Low Effects setting (client only)
require(script.Parent.NameTag).start() -- lobby name tags: title + best tower floor (server attributes)
require(script.Parent.RainbowPath).start() -- rainbow trail + sparkles while walking on a lobby path
require(script.Parent.ui.RareBanner).start() -- rare hatch fireworks + gold banner (RareHatch remote)
require(script.Parent.CameraFx).start() -- lobby camera trail, boots FOV, the one shared shake helper (cosmetic)
require(script.Parent.RoundIntro).start() -- hunt whoosh, big 3-2-1-GO and camera swoop over the pile (cosmetic)
require(script.Parent.LobbyFlyover).start() -- one park fly-over for a brand-new player (cosmetic)
require(script.Parent.PhotoMode).start() -- lobby photo mode: hide UI, free orbit camera (cosmetic)
require(script.Parent.WorldFx).start() -- pedestal glow, water ripples, secret egg sparkle, zone weather (cosmetic)
require(script.Parent.HangoutView).start() -- lobby hangout: sky beam, status card, emotes (cosmetic)
require(script.Parent.HangoutAnim).start() -- lobby hangout animation: auras, sparkles, bobbing, flicker (cosmetic)
require(script.Parent.HiddenEggLocal).start() -- hidden eggs this player found disappear for them (audit F25)
require(script.Parent.YourPlotTag).start() -- "YOUR PLOT" over the player's own plot, their screen only (audit 2 #3)
-- lobby HUD v2 (carter's painted buttons, live 2026-10-15): each button opens what its old HUD button did
do
	local PlayButton = require(script.Parent.ui.PlayButton)
	local TowerPanel = require(script.Parent.ui.TowerPanel)
	local PvpPanel = require(script.Parent.ui.PvpPanel)
	local QuestPanel = require(script.Parent.ui.QuestPanel)
	local SpinView = require(script.Parent.SpinView)
	require(script.Parent.ui.LobbyHudV2).start({
		open = {
			Play = PlayButton.tap,
			Train = TowerPanel.openPicker,
			Fight = PvpPanel.openBattle,
			MyPets = function()
				openPanel("MyPets")
			end,
			PetBook = function()
				openPanel("PetIndex")
			end,
			Daily = QuestPanel.open,
			Spin = SpinView.openPanel,
			Shop = function()
				openPanel("RobuxShop")
			end,
		},
		status = PlayButton.status,
		hideOld = Hud.setLobbyHidden,
		claimable = function(): boolean
			return Hud.dailyReady(State.Profile) > 0
		end,
	})
end

local pendingDisplay = false
local foundAt: number? = nil
local revealPending = false -- the Reveal event arrived but the hero sequence has not started yet
Results.OnOpenPet = function(id: string)
	CollectionPanel.openOn(id)
end
local pendingTrain = false
Results.OnTutorialAction = function(kind: string)
	if kind == "Display" then
		pendingDisplay = true
	elseif kind == "Train" then
		pendingTrain = true
	end
	Hud.hintDismissed = nil
	State.update("Profile")
end

-- the goal step is recorded when the shop opens or the goal hint's OK is tapped
UI.ModalChanged.Event:Connect(function(name)
	Audio.setMenuOpen(name ~= nil) -- sounds a bit quieter while a menu is open
	if name == "Shop" then
		local ob = onboarding()
		if ob and ob.Displayed and not ob.Goal then
			Net.event("TutorialAction"):FireServer("Goal")
		end
	end
end)
task.spawn(function()
	while true do
		task.wait(0.5)
		local d = Hud.hintDismissed
		if d and string.sub(d, 1, #GOAL_TEXT_PREFIX) == GOAL_TEXT_PREFIX then
			local ob = onboarding()
			if ob and not ob.Goal then
				Net.event("TutorialAction"):FireServer("Goal")
			end
		end
		updateMarker()
		syncMarkerVisible() -- the objective card comes and goes with the HUD refresh (cue timeout, party)
	end
end)

-- Slow device: after the profile loads, average the frame rate for 10 s; if it stays low, suggest LOW EFFECTS once with
-- a toast. The setting is saved on the server, so this never changes it for the player.
task.spawn(function()
	local RunService = game:GetService("RunService")
	while not State.Profile do
		task.wait(0.5)
	end
	task.wait(12) -- let the load and lobby streaming hitch pass
	local frames, t0 = 0, os.clock()
	local conn = RunService.Heartbeat:Connect(function()
		frames += 1
	end)
	task.wait(10)
	conn:Disconnect()
	local fps = frames / math.max(os.clock() - t0, 1)
	local prof = State.Profile
	if fps < 22 and prof and not prof.Settings.LowEffects then
		Hud.toast("Game feels slow? Turn on LOW EFFECTS in Settings!", "info")
	end
end)

-- World prompts with a Panel attribute open that panel locally.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local panel = prompt:GetAttribute("Panel")
	if type(panel) == "string" and panel ~= "" then
		openPanel(panel)
	end
end)

local secretEggHidden = false
Net.event("ProfileState").OnClientEvent:Connect(function(view)
	if view.Inventory == nil then
		-- light update: inventory unchanged since the last full sync
		view.Inventory = if State.Profile then State.Profile.Inventory else {}
	end
	State.Profile = view
	UI.Reduced = view.Settings and view.Settings.ReducedMotion == true
	-- Camera sensitivity (mouse look): scales the mouse delta the camera reads; 0.5 = Roblox default speed
	local sens = view.Settings and tonumber(view.Settings.CameraSensitivity)
	if sens then
		pcall(function()
			UserInputService.MouseDeltaSensitivity = math.clamp(sens * 2, 0.1, 2)
		end)
	end
	State.update("Profile")
	-- the secret egg is found: its prompt no longer invites a "Take" for this player (the server refuses a second one)
	if view.SecretEggFound and not secretEggHidden then
		local name = require(Shared.MapNames).SecretEggPrompt
		for _, d in Workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == name then
				d.Enabled = false
			end
		end
		secretEggHidden = true -- one scan (StreamingEnabled is off, so the egg is already here)
	end
end)

Net.event("PartyState").OnClientEvent:Connect(function(party, invites)
	local had = State.Party ~= nil
	State.Party = party
	State.Invites = invites or {}
	State.update("Party")
	if party and not had and not State.Match and UI.modalOpen() == nil then
		openPanel("Party")
	end
end)

Net.event("Toast").OnClientEvent:Connect(function(text, kind)
	Hud.toast(text, kind) -- one coalesced notification, drawn above any open menu
	-- ok = purchase / unlock, cash = daily gift / quest reward, rare = Lucky Meter etc., warn = refused (shared/SoundCues)
	local key = require(Shared.SoundCues).toast(text, kind)
	if key then
		Audio.play(key)
	end
end)

-- Cosmetic feedback from the server (sales).
Net.event("Fx").OnClientEvent:Connect(function(kind, data)
	if kind == "SecretEgg" then
		-- the hidden lobby egg: a big banner and confetti (a small toast undersold it)
		Juice.banner("YOU FOUND THE SECRET EGG!", nil, 3.2)
		Effects.confetti()
		Audio.play("ShopKaChing")
		return
	end
	if kind == "Sell" and typeof(data.Pos) == "Vector3" then
		Audio.play("ShellPop")
		-- the flying coins reach the cash counter after about 0.75 s (Effects.cashFly); PetSoundIds.CoinPickup, 0 = silent
		task.delay(0.75, Audio.play, "CoinPickup", { Volume = 0.8 })
		Audio.play("GravelSpill", { Pos = data.Pos, Volume = 0.7 })
		Effects.cashFly(data.Pos, tonumber(data.Total) or 1)
	end
	if kind == "Sell" and typeof(data.Pos) == "Vector3" and not (State.Profile and State.Profile.Settings.LowEffects) then
		-- a few gravel bits drop into the hopper grate
		for i = 1, 6 do
			local p = Instance.new("Part")
			p.Size = Vector3.one * 0.5
			p.Color = Config.Palette.Rock
			p.Material = Enum.Material.Slate
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CFrame = CFrame.new(data.Pos + Vector3.new((i - 3.5) * 0.6, 5, 0))
			p.Parent = Workspace
			TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(data.Pos + Vector3.new((i - 3.5) * 0.3, 1.5, 0)), Transparency = 1 }):Play()
			task.delay(0.5, function()
				p:Destroy()
			end)
		end
	end
end)

Net.event("MatchEvent").OnClientEvent:Connect(function(kind, data)
	if kind == "Init" then
		CameraMode.restore()
		CarryGlimpse.setSeed(data.Seed or 1)
		UI.closeModal()
		Results.hide()
		State.Results = nil
		State.Match = {
			Key = data.Key,
			Round = data.Round,
			Tier = data.Tier,
			Tutorial = data.Tutorial,
			Rocks = data.Rocks,
			Remaining = data.Rocks - #(data.Removed or {}),
			Phase = data.Phase,
			EndsAt = data.EndsAt,
			Members = data.Members,
			MyCracked = 0,
			SearchStart = data.SearchStart,
			SearchEnd = data.SearchEnd,
			Machines = data.Machines or {},
			Stations = data.Stations,
			Counts = data.Counts,
			Tables = data.Tables,
			Center = data.Center, -- pile centre (RoundIntro camera swoop)
		}
		foundAt = nil
		PileView.init(data)
		require(script.Parent.HatchFx).setPile(data.Center) -- Rare+ fireworks go up above the pile
		MachineView.setStates(data.Machines or {})
		State.update("Match")
	elseif kind == "Phase" then
		local m = State.Match
		if not m or data.Round ~= m.Round then
			return
		end
		m.Phase = data.Phase
		m.EndsAt = data.EndsAt
		m.Members = data.Members
		-- the hunt clock is the server's: it starts at Searching and stops when the geode is found
		if data.SearchStart then
			m.SearchStart = data.SearchStart
		elseif data.Phase == "Searching" and not m.SearchStart then
			m.SearchStart = Workspace:GetServerTimeNow()
		end
		m.SearchEnd = data.SearchEnd
		State.update("Match")
	elseif kind == "Members" then
		if State.Match then
			State.Match.Members = data.Members
			State.update("Match")
		end
	elseif kind == "Machines" then
		local m = State.Match
		if m and data.Round == m.Round then
			m.Machines = data.List
			MachineView.setStates(data.List)
			State.update("Match")
		end
	elseif kind == "Surprise" then
		-- surprise eggs (shared/HuntFun): the prize is already paid; this only shows it over the own nest
		local m = State.Match
		if m and data.Round == m.Round then
			SurprisePop.show(data)
		end
	elseif kind == "MaterialFound" then
		-- a first-time material for this player, told after their own crush completed (Hud merges bursts)
		local m = State.Match
		if m and data.Round == m.Round and type(data.New) == "table" then
			Hud.materialNotice(data.New)
			Audio.materialFound()
		end
	elseif kind == "Rocks" then
		PileView.onRocks(data)
	elseif kind == "RockReply" then
		local m = State.Match
		if not m or data.Round ~= m.Round then
			return
		end
		PileView.onReply(data)
		if data.Action == "Deposit" and data.Ok then
			if (data.Moved or 0) > 0 then
				Audio.deposit()
			end
			if (data.Left or 0) > 0 then
				Hud.toast("Deposited " .. (data.Moved or 0) .. "! " .. data.Left .. " still in your basket!", "info")
			end
		elseif not data.Ok then
			local text = ({
				BasketFull = "Basket full! Take your eggs to your nest.",
				QueueFull = "Nest is full! Hatch some eggs first.",
				TooFar = "Walk closer!",
				Unreachable = "Too high! Find a lower egg.",
				NoSight = "Blocked! Move to see the egg.",
				Gone = "Too slow! Try another egg.",
				Automatic = "Your Auto Nest hatches for you! Bring it eggs.",
			})[data.Reason]
			if text then
				Hud.toast(text, "info")
			end
		end
	elseif kind == "Found" then
		local m = State.Match
		if m and data.Round == m.Round then
			m.Phase = "RewardPending"
			m.WinnerName = data.WinnerName
			foundAt = os.clock()
			Audio.play("PetFound") -- everyone hears the find; the winner's reveal adds its own stings later
			require(script.Parent.CameraFx).shake(if data.Winner == Players.LocalPlayer.UserId then 1 else 0.45, 0.45) -- big moment
			if data.Winner == Players.LocalPlayer.UserId then
				require(script.Parent.PetFollow).celebrate(Players.LocalPlayer) -- your pets dance for the win
				-- the camera leaves first person for a close look at your nest while the pet egg opens on it
				HatchFocus.start(StationView.platePosition(Players.LocalPlayer.UserId))
			end
			local winner = if type(data.Winner) == "number" then Players:GetPlayerByUserId(data.Winner) else nil
			if winner and winner.Character then
				require(script.Parent.PlayerCheer).play(winner.Character) -- the winner's avatar cheers
			end
			PileView.clearReserved()
			local viaMachine = machineCracks[data.RockId]
			if viaMachine then
				MachineView.recovered(viaMachine)
			end
			table.clear(machineCracks)
			MachineView.stop()
			PileView.stopAll()
			PileView.clearSelection()
			Hud.clearMessages() -- nothing from the search stays over the find and the reveal
			State.update("Match")
		end
	elseif kind == "Reveal" then
		State.Results = data
		if type(data.Winner) == "number" and type(data.Specimen) == "table" then
			StationView.showSpecimen(data.Winner, data.Specimen)
		end
		PileView.clearPile()
		require(script.Parent.HatchFx).onReveal(data) -- Rare+: rainbow ring from the nest, fireworks above the pile
		-- let the geode finish opening on the plate before the reveal screen takes over
		local wait = if foundAt and not UI.Reduced and os.clock() - foundAt < 6 then StationView.fxRemaining() + 1.8 else 0
		revealPending = wait > 0
		task.delay(wait, function()
			if State.Results == data then
				revealPending = false
				HatchFocus.stop() -- the nest close-up hands over to the full-screen reveal card
				Results.reveal(data)
			end
		end)
		State.update("Results")
	elseif kind == "Results" then
		HatchFocus.stop()
		CameraMode.restore() -- the reveal never leaves a presentation camera behind
		State.Results = data
		if State.Match then
			State.Match.Phase = "Results"
		end
		State.update("Match")
		-- The server's reveal timer (Config.Match.RevealSeconds) starts at the Reveal event, but the client
		-- first lets the geode finish opening on the plate, so the hero sequence can still be running here.
		-- Open the results card only once it reached its final frame (or was skipped), never over its
		-- middle. Bounded: after 12 s it opens regardless (a Rare+ hatch plays about 6 s, Config.Hatch).
		task.spawn(function()
			local waited = 0
			while (revealPending or RevealView.isPlaying()) and waited < 12 and State.Results == data do
				task.wait(0.1)
				waited += 0.1
			end
			-- the finished specimen stays on screen for a moment (a tap closes it sooner)
			local held = 0
			while RevealView.isOpen() and held < 1.5 and State.Results == data do
				task.wait(0.1)
				held += 0.1
			end
			if State.Results == data then
				Results.open()
			end
		end)
	elseif kind == "ResultsBag" then
		-- a hopper sale after the snapshot: only the bag figures change (hunt counters stay as the server froze them)
		local res = State.Results
		if res and type(data) == "table" and data.Round == res.Round and type(data.Bag) == "table" then
			for _, mem in res.Members do
				if mem.UserId == player.UserId then
					mem.BagCount, mem.BagCapacity, mem.BagValue = data.Bag.Count, data.Bag.Capacity, data.Bag.Value
				end
			end
			State.update("Results")
		end
	elseif kind == "Left" then
		HatchFocus.stop()
		CameraMode.restore() -- back in the lobby: the camera on the current humanoid, never an arena camera (third person once State.Match clears)
		CarryGlimpse.clear()
		revealPending = false
		Effects.clear()
		Results.hide()
		UI.closeModal()
		PileView.leave()
		MachineView.clear()
		foundAt = nil
		table.clear(machineCracks)
		State.Match = nil
		State.Results = nil
		State.update("Match")
		if pendingTrain then
			-- TRAIN PET on the practice results: the loop's next step opens as soon as the lobby is back
			pendingTrain = false
			task.delay(0.8, function()
				require(script.Parent.ui.PvpPanel).openTrain()
			end)
		end
		if pendingDisplay then
			pendingDisplay = false
			task.delay(0.6, function()
				-- open on the newest specimen with SHOW IN GALLERY ready
				local newest, t = nil, -1
				for _, g in (State.Profile and State.Profile.Inventory or {}) do
					if g.Found > t then
						newest, t = g.Id, g.Found
					end
				end
				CollectionPanel.openOn(newest)
			end)
		end
	end
end)

LaunchPanel.start() -- Teleport mode cards; idle in the default single-place mode

Net.event("ClientReady"):FireServer()
if player:GetAttribute("MatchKey") then
	Net.event("MatchAction"):FireServer("Sync")
end
