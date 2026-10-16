-- signs: numeric audit of every world sign in the lobby (the renderer draws SurfaceGui text since 2026-10-10 and
-- tools/preview/check_signs.py checks the drawn pixels; this measures the layout numbers). Boots the real server and client, then for each SurfaceGui TextLabel on a part that
-- carries the sign attributes (SignPreset / SignW / SignH, set by KitPlace.signBoard / signText) it reads
-- the mock's measured TextBounds (real Fredoka One advance widths) and prints
--   text, board studs, canvas px, TextSize, cap height in studs, width fill %.
-- PASS when the fill is inside the preset range (Landmark 55-75 %, Plaque 45-88 %, Nameplate 40-92 %,
-- Placard 40-92 %, with 4 points of tolerance for the metrics difference) and the text height fits the board.
-- Also: every landmark title of the pet park exists once (PET PARK, UPGRADES, PET BOOK, SELL CANDY, EGG SHOP, the two
-- board headings, PET TOWER, HATCH STAND, WHAT'S NEW), a long owner name stays
-- inside its nameplate, and any SurfaceGui text WITHOUT the sign attributes is listed as UNAUDITED.
-- Prints "SIGNS PASS" or "SIGNS FAIL: ...".  --set name=<text> sets the player's display name.
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local SignLayout = C.shared("SignLayout")

local longName = preview.args.name or "Maximilian_The_Magnificent_Rockhound"
local s = C.boot({})
Players.LocalPlayer.DisplayName = longName
C.settle(2)
local gallery = C.server("GalleryService")
if gallery then
	gallery.render(s.me)
end
C.settle(1)

local fails = {}
local function check(name, ok, detail)
	print(string.format("[%s] %s%s", if ok then "PASS" else "FAIL", name, if detail then (": " .. detail) else ""))
	if not ok then
		table.insert(fails, name)
	end
end

local TOL = 0.04
local titles = {}
local unaudited = {}
local rows = 0
for _, d in Workspace:GetDescendants() do
	if d:IsA("TextLabel") and d.Parent and d.Parent:IsA("SurfaceGui") then
		local gui = d.Parent
		local p = gui.Parent
		local preset = p and p:GetAttribute("SignPreset")
		local W, H = p and p:GetAttribute("SignW"), p and p:GetAttribute("SignH")
		if type(preset) == "string" and type(W) == "number" and type(H) == "number" then
			rows += 1
			local ppsStud = gui.PixelsPerStud
			local cw, ch = W * ppsStud, H * ppsStud
			local tb = d.TextBounds
			local fill = tb.X / cw
			local cap = d.TextSize * 0.733 / ppsStud
			local pr = SignLayout.Presets[preset]
			local ok = pr ~= nil and fill >= pr.Min - TOL and fill <= pr.Max + TOL and tb.Y <= ch * 1.01 and d.TextSize <= 100 and not d.TextScaled
			local text = string.gsub(d.Text, "\n", " / ")
			check(string.format("%-9s %-34s", preset, text), ok, string.format("board %.1fx%.1f studs, canvas %dx%d px, TextSize %d, cap %.2f studs, fill %d%%", W, H, cw, ch, d.TextSize, cap, math.floor(fill * 100 + 0.5)))
			if preset == "Landmark" or preset == "Heading" then
				titles[d.Text] = (titles[d.Text] or 0) + 1
				-- one line, no wrapping
				check("landmark one line: " .. d.Text, not string.find(d.Text, "\n") and tb.Y <= ch, "")
			end
			if preset == "Nameplate" and string.find(d.Text, "gallery", 1, true) then
				check("owner nameplate stays inside its board", tb.X <= cw * 0.95, d.Text)
			end
		else
			table.insert(unaudited, d.Text)
		end
	end
end
for _, t in { "PET PARK", "UPGRADES", "PET BOOK", "SELL CANDY", "EGG SHOP", "RAREST PET", "HIGHEST FLOOR", "PET TOWER", "HATCH STAND", "WHAT'S NEW" } do
	check("landmark title " .. t .. " present once", titles[t] == 1, tostring(titles[t]))
end
check("signs audited", rows >= 20, tostring(rows))

-- Lodge visual pass (2026-10-10): every lodge landmark / heading is white with a black outline, its SurfaceGui is
-- enabled, unlit and on the face that looks at the people reading it (into the hall; the plaque out to the yard).
local lobbyRoot = Workspace:FindFirstChild("CT_Rocks_Lobby")
local landmarks = 0
for _, d in (if lobbyRoot then lobbyRoot:GetDescendants() else {}) do
	local preset = d:GetAttribute("SignPreset")
	if d:IsA("BasePart") and (preset == "Landmark" or preset == "Heading") then
		landmarks += 1
		local gui = d:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		local stroke = label and label:FindFirstChildOfClass("UIStroke")
		local text = (label and label.Text) or "?"
		local white = label ~= nil and label.TextColor3.R > 0.97 and label.TextColor3.G > 0.97 and label.TextColor3.B > 0.97
		local outlined = stroke ~= nil and stroke.Thickness >= 2 and stroke.Color.R < 0.15 and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
		check("lodge lettering white + black outline: " .. text, white and outlined and (d:GetAttribute("SignOutline") or 0) >= 2, if stroke then ("outline " .. stroke.Thickness .. " px") else "no UIStroke")
		check("lodge sign SurfaceGui enabled, unlit, on the Back face: " .. text, gui ~= nil and gui.Enabled and gui.Face == Enum.NormalId.Back and gui.LightInfluence <= 0.2, "")
		-- Back face normal = +Z of the part = -LookVector
		local n = -d.CFrame.LookVector
		local outward = text == "PET PARK" or text == "WHAT'S NEW" -- the plaza signs face the spawn, away from the park centre
		local toward = if outward then Vector3.zAxis else (Vector3.new(0, d.Position.Y, 0) - d.Position).Unit
		check("lodge sign faces its readers: " .. text, n:Dot(toward) > 0.3, string.format("normal (%.2f, %.2f, %.2f)", n.X, n.Y, n.Z))
	end
end
check("lodge landmarks + headings audited", landmarks >= 7, tostring(landmarks))

-- the two lodge boards: five permanent rank slots and a status line that is never empty, for every state
local LobbyBoards = C.server("LobbyBoards")
local mounts = lobbyRoot and lobbyRoot:FindFirstChild("BoardMounts")
for _, id in { "Biggest", "Tower" } do
	local mount = mounts and mounts:FindFirstChild("Mount_" .. id)
	local gui = mount and mount:FindFirstChild("BoardGui")
	local face = gui and gui:FindFirstChild("Board_" .. id)
	local slots = 0
	if face then
		for i = 1, 5 do
			local r = face:FindFirstChild("Row" .. i)
			if r and r:IsA("GuiObject") and r.Visible then
				slots += 1
			end
		end
	end
	check("board " .. id .. ": SurfaceGui on the mount, enabled, unlit", gui ~= nil and gui:IsA("SurfaceGui") and gui.Enabled and gui.LightInfluence == 0, "")
	check("board " .. id .. ": five rank slots shown", slots == 5, tostring(slots))
	local status = face and face:FindFirstChild("Status")
	check("board " .. id .. ": status line says something", status ~= nil and (status :: TextLabel).Text ~= "", if status then (status :: TextLabel).Text else "none")
	if LobbyBoards and LobbyBoards.lodgeStatus then
		for _, st in { "loading", "ok", "unavailable", "error" } do
			local line = LobbyBoards.lodgeStatus(id, { Status = st, Rows = {}, Updated = 0 })
			check(("board %s status (%s, no rows)"):format(id, st), type(line) == "string" and #line > 4, line)
		end
	end
end
if #unaudited > 0 then
	print("UNAUDITED SurfaceGui text (no sign attributes): " .. table.concat(unaudited, " | "))
end
print(if #fails == 0 then "SIGNS PASS" else ("SIGNS FAIL: " .. table.concat(fails, ", ")))
