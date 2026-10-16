--!strict
-- SETTINGS (board 11). Only settings that change something, saved in the profile (SettingsAction, validated on the
-- server):
--   Music        Settings.Music -> SoundGroups Music and Ambience (0.6x), set live while dragging
--   Sounds       Settings.Sfx -> SoundGroup SFX (one-shots and machine loops)
--   Camera Sensitivity   Settings.CameraSensitivity -> UserInputService.MouseDeltaSensitivity (mouse look only, so
--                the row is shown only when a mouse is present; touch look speed is Roblox's own setting)
--   Reduce Motion        Settings.ReducedMotion (UI transitions, reveal, camera-free decorative motion)
--   Low Effects, Hints   Settings.LowEffects / Settings.Hints; SKIP TUTORIAL while the first-session steps run.

local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local State = require(script.Parent.Parent.State)
local UI = require(script.Parent.UI)
local PanelSkin = require(script.Parent.PanelSkin)
local HudArt = require(script.Parent.HudArt)
local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Parent.Audio)

local T = UI.T
local SettingsPanel = {}

-- Applies a volume to the real SoundGroups right away (Audio owns them: SoundService.CTR_Audio).
local function applyLive(key: string, v: number)
	if key == "CameraSensitivity" then
		pcall(function()
			UserInputService.MouseDeltaSensitivity = math.clamp(v * 2, 0.1, 2)
		end)
		return
	end
	local master = SoundService:FindFirstChild("CTR_Audio")
	if not master then
		return
	end
	local function set(name: string, vol: number)
		local g = master:FindFirstChild(name)
		if g and g:IsA("SoundGroup") then
			g.Volume = vol
		end
	end
	if key == "Sfx" then
		set("SFX", v)
	elseif key == "Music" then
		set("Music", v)
		set("Ambience", v * 0.6)
	end
end

-- Row geometry. Rows are ROW_H tall (less on a short screen, see open()); the controls on the right share one
-- column: the ON / OFF switches and SKIP are the same width and end RIGHT px inside the row.
local ROW_H = 46
local ROW_MIN = 36
local ROW_GAP = 6
local FOOT_H = 44 -- the "Saved to your profile." line sits in the panel's footer, not in the scroller
local RIGHT = 10
-- The ON / OFF switch drawn here (not UI.toggle): at least 34 px tall with a 28 px knob, OFF in the navy tab-bar
-- colour with a white word (the shared switch read small and its OFF state washed out on the sky rows, Studio).
local TRACK_H_MIN, TRACK_H_MAX = 34, 40
local TRACK_RATIO = 84 / 34
local KNOB = 28 -- slider handle and switch knob (a 20 px handle was hard to grab with a mouse on a phone-size window)
local TC = Theme.Color
local PET = Theme.Pet

-- ON / OFF switch: a 44 px tall hit box around a track `h` px tall. Returns the hit button.
local function bigToggle(parent: Instance, on: boolean, h: number, onChange: (boolean) -> (), props: { [string]: any }): TextButton
	local w = math.floor(h * TRACK_RATIO + 0.5)
	local hit = Instance.new("TextButton")
	hit.Name = "Switch"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromOffset(w, math.max(T.Touch, UI.minTouch()))
	UI.apply(hit, props)
	hit.Parent = parent
	local track = UI.frame(hit, { Name = "Track", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h) })
	UI.corner(track, math.floor(h / 2))
	UI.stroke(track, TC.Outline, 2)
	local knob = UI.frame(track, { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(KNOB, KNOB), BackgroundColor3 = Color3.fromRGB(245, 245, 245) })
	UI.corner(knob, math.floor(KNOB / 2))
	UI.stroke(knob, TC.Outline, 1.5)
	local wordW = w - KNOB - 8
	local word = UI.text(track, "", { Name = "Word", Font = UI.Head, TextSize = T.Body, TextColor3 = Color3.new(1, 1, 1), Outline = "Normal", Size = UDim2.new(0, wordW, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	word.TextWrapped = false
	UI.fit(word, T.Body, T.MinText)
	local state = on
	local function show()
		track.BackgroundColor3 = if state then TC.Green else PET.TabBar
		knob.Position = if state then UDim2.new(1, -(KNOB + 3), 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		word.Text = if state then "ON" else "OFF"
		word.Position = if state then UDim2.fromOffset(4, 0) else UDim2.new(1, -(wordW + 4), 0, 0)
	end
	hit.Activated:Connect(function()
		Audio.button()
		state = not state
		show()
		onChange(state)
	end)
	show()
	return hit
end

function SettingsPanel.open()
	local prof = State.Profile
	local mouse = UserInputService.MouseEnabled
	local rows = 5 + (if mouse then 1 else 0) + (if prof and not prof.OnboardDone then 1 else 0)
	local h = math.min(54 + rows * (ROW_H + ROW_GAP) + 12 + FOOT_H, if UI.isPortrait() then 640 else 470)
	local panel, b, _, footer = UI.modal("Settings", "SETTINGS", Vector2.new(500, h), { Footer = FOOT_H })
	PanelSkin.dress(panel, "Gear", "SETTINGS", { Center = true }) -- owner mockup: reference/ui/settings/mockup.png
	UI.list(b, Enum.FillDirection.Vertical, ROW_GAP, Enum.HorizontalAlignment.Center)
	-- Rows shrink (down to ROW_MIN) so the whole list fits the panel on a short screen (Studio 1434 x 658 with the
	-- mouse-only camera row overflowed: a scrollbar showed and the last line sat on the bottom border). The panel is
	-- min(h, screen + its negative size offset) tall; the body is that minus the header, the footer and its padding.
	local panelH = math.min(h, UI.Logical.Y + panel.Size.Y.Offset)
	local bodyH = panelH - (b :: GuiObject).Position.Y.Offset - FOOT_H - 12
	local rowH = math.clamp(math.floor((bodyH - (rows - 1) * ROW_GAP) / rows), ROW_MIN, ROW_H)
	-- the switches (and SKIP) share one column: 34 to 40 px tall, as the row allows
	local colH = math.clamp(rowH - 4, TRACK_H_MIN, TRACK_H_MAX)
	local colW = math.floor(colH * TRACK_RATIO + 0.5)
	if typeof(b) == "Instance" and b:IsA("ScrollingFrame") then
		local sc = b :: ScrollingFrame
		-- no scrollbar, bar image or reserved strip unless the rows really overflow
		local function fitBar()
			local over = sc.AbsoluteCanvasSize.Y > sc.AbsoluteWindowSize.Y + 1
			sc.ScrollBarThickness = if over then UI.ScrollBar else 0
			sc.ScrollBarImageTransparency = if over then 0.25 else 1
			sc.VerticalScrollBarInset = if over then Enum.ScrollBarInset.Always else Enum.ScrollBarInset.None
			sc.ScrollingEnabled = over
		end
		sc:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(fitBar)
		sc:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(fitBar)
		fitBar()
		UI.endOnRow(sc, 0) -- the window ends on a whole row above the footer; the last row scrolls fully into view
	end
	if not prof then
		UI.loadingState(b, "Loading settings")
		return
	end
	local s: { [string]: any } = table.clone(prof.Settings)
	if type(s.CameraSensitivity) ~= "number" then
		s.CameraSensitivity = 0.5
	end
	local lastSave = 0
	local function save(force: boolean?)
		local now = os.clock()
		if force or now - lastSave > 0.25 then
			lastSave = now
			Net.event("SettingsAction"):FireServer(s)
		end
	end
	local order = 0
	local narrow = UI.Logical.X < 440
	local function row(icon: string, label: string): Frame
		order += 1
		-- sky row with a darker edge (mockup); icon and name centred on the row's height
		local r = PanelSkin.box(b, "Row_" .. label, PanelSkin.SKY, PanelSkin.SKY_EDGE, 3, { Size = UDim2.new(1, -6, 0, rowH), LayoutOrder = order })
		HudArt.skin(r, "settings_row", rowH)
		-- `icon` is a HudArt slot: the owner's picture once uploaded, else the drawn icon
		HudArt.image(r, icon, 28, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
		-- the strong dark outline: white words under the normal one did not read on the light sky rows (Studio)
		local l = UI.text(r, label, { Name = "Label", Font = UI.Bold, TextSize = T.Head - 2, Outline = "Strong", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 48, 0.5, 0), Size = UDim2.new(if narrow then 0.42 else 0.46, -48, 0, 24) })
		l.TextWrapped = false
		UI.fit(l, T.Head - 2, T.MinText)
		HudArt.word(l) -- owner's word picture (reference/ui/settings/) once uploaded
		return r
	end
	local function slider(key: string, icon: string, label: string)
		local r = row(icon, label)
		-- the percentage sits in a navy pill (mockup)
		-- wide enough for "100%" at the 14 px floor (a 46 px pill squeezed it under 12 px, Studio)
		local pill = UI.frame(r, { Name = "ValuePill", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -RIGHT, 0.5, 0), Size = UDim2.fromOffset(58, 30), BackgroundColor3 = PanelSkin.NAVY, BackgroundTransparency = 0.25 })
		UI.corner(pill, 10)
		local val = UI.text(pill, "", { Name = "Value", Font = UI.Head, TextSize = T.Body, Outline = "Normal", Size = UDim2.new(1, -4, 1, 0), Position = UDim2.fromOffset(2, 0), TextXAlignment = Enum.TextXAlignment.Center })
		val.TextWrapped = false
		UI.fit(val, T.Body, T.MinText)
		local function show(v: number)
			val.Text = math.floor(v * 100 + 0.5) .. "%"
		end
		local sl = UI.slider(r, s[key], function(v, final)
			s[key] = v
			show(v)
			applyLive(key, v)
			save(final)
		end, { Name = "Slider_" .. key, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(RIGHT + 62), 0.5, 0), Size = UDim2.new(if narrow then 0.58 else 0.54, -72, 0, T.Touch) })
		-- a 28 px handle on the slim track (the drag box stays 44 px tall: UI.slider holds it at the touch minimum)
		local knob = sl:FindFirstChild("Knob", true)
		if knob and knob:IsA("Frame") then
			knob.Size = UDim2.fromOffset(KNOB, KNOB)
			local kc = knob:FindFirstChildOfClass("UICorner")
			if kc then
				kc.CornerRadius = UDim.new(0, math.floor(KNOB / 2))
			end
		end
		show(s[key])
	end
	local function toggle(key: string, icon: string, label: string)
		local r = row(icon, label)
		-- the hit box is exactly the track's width, so the drawn track ends RIGHT px inside the row, like SKIP
		bigToggle(r, s[key] == true, colH, function(on)
			s[key] = on
			if key == "ReducedMotion" then
				UI.Reduced = on -- UI transitions follow at once; the server saves it
			end
			save(true)
		end, { Name = "Switch_" .. key, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -RIGHT, 0.5, 0) })
	end
	slider("Music", "Music", "Music")
	slider("Sfx", "Sound", "Sounds")
	if mouse then
		slider("CameraSensitivity", "Camera", "Camera Sensitivity")
	end
	toggle("ReducedMotion", "Motion", "Reduce Motion")
	toggle("LowEffects", "Sparkle", "Low Effects")
	toggle("Hints", "Bulb", "Hints")
	if not prof.OnboardDone then
		local r = row("Info", "First-hunt guide")
		local skip = UI.button(r, "SKIP", "blue", function()
			Net.event("TutorialAction"):FireServer("Skip")
			UI.closeModal()
		end, { Name = "SkipTutorial", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -RIGHT, 0.5, 0), Size = UDim2.fromOffset(colW, colH), TextSize = T.Body })
		HudArt.skin(skip, "btn_blue", colH)
		local sl = skip:FindFirstChild("Label") :: TextLabel?
		if sl then
			HudArt.word(sl, 0.75)
		end
	end
	-- the footer line stays under the list (never scrolled with it) and clear of the panel's bottom border and rim
	if footer then
		local fp = footer:FindFirstChildOfClass("UIPadding")
		if fp then
			fp.PaddingTop = UDim.new(0, 2)
			fp.PaddingBottom = UDim.new(0, 14)
		end
		local note = UI.text(footer, if prof.SavesOff then "Saves are off here: changes last until you leave." else "Saved to your profile.", {
			Name = "SaveNote", Font = UI.Bold, TextSize = T.Body + 1, TextColor3 = PanelSkin.NAVY, Outline = false, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		})
		note.TextWrapped = false
		UI.fit(note, T.Body + 1, T.MinText)
	end
end

return SettingsPanel
