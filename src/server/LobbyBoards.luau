--!strict
-- World leaderboards in the lobby (SurfaceGui), fed by LeaderboardService, with loading / empty / error / Studio
-- unavailable states. The pet park places the two lobby boards (owner pick: RAREST PET = Biggest, crowned, and
-- HIGHEST FLOOR = Tower; LodgeBuilder.buildBoards) beside the nests and marks their mounts `Bare`: the rows go straight
-- onto the mount (createLodgeContent, five rows).
-- A mount without `Bare` gets the classic framed pale board (createContent, top 10). Boards without a mount are
-- not drawn (LeaderboardService still keeps every board). The content builders are separate from the 3D stands
-- so the offline preview can draw them on a ScreenGui.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Boards = require(Shared.Boards)
local Leaderboards = require(script.Parent.LeaderboardService)
local KitPlace = require(script.Parent.KitPlace)

local LobbyBoards = {}

local ROWS = Config.Leaderboards.Top
-- Pale board faces with charcoal text (Master 7: readable boards, not dark walls). The board's accent colour is
-- only a thin bar under the title, never text on the pale face.
local FACE = Color3.fromRGB(234, 228, 214)
local ROW_A = Color3.fromRGB(222, 215, 200)
local ROW_B = Color3.fromRGB(242, 237, 226)
local INK = Color3.fromRGB(44, 46, 52)
local INK_SOFT = Color3.fromRGB(96, 98, 104)
local MEDAL = { Color3.fromRGB(150, 108, 30), Color3.fromRGB(96, 104, 112), Color3.fromRGB(140, 86, 48) }

export type Handle = { Set: (Leaderboards.State) -> (), Root: Frame }

local function label(parent: Instance, name: string, pos: UDim2, size: UDim2, font: Enum.Font, color: Color3, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = font
	t.TextColor3 = color
	t.TextXAlignment = align
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	return t
end

-- Builds the board face inside `parent` (any GuiObject / SurfaceGui) and returns a handle whose
-- Set(state) redraws it. Rows are created once and only their text changes.
function LobbyBoards.createContent(parent: Instance, boardId: string): Handle
	local info = Boards.Info[boardId]
	local root = Instance.new("Frame")
	root.Name = "Board_" .. boardId
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = FACE
	root.BorderSizePixel = 0
	root.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.Size = UDim2.new(1, 0, 0.012, 0)
	bar.Position = UDim2.fromScale(0, 0.1)
	bar.BackgroundColor3 = info.Accent
	bar.BorderSizePixel = 0
	bar.Parent = root

	local title = label(root, "Title", UDim2.fromScale(0.04, 0.012), UDim2.fromScale(0.92, 0.07), Enum.Font.FredokaOne, INK, Enum.TextXAlignment.Center)
	title.Text = info.Title
	local sub = label(root, "Sub", UDim2.fromScale(0.04, 0.118), UDim2.fromScale(0.92, 0.04), Enum.Font.GothamBold, INK_SOFT, Enum.TextXAlignment.Center)
	sub.Text = info.Sub

	local rowFrames: { { Frame: Frame, Rank: TextLabel, Name: TextLabel, Value: TextLabel } } = {}
	local top, rowH = 0.175, 0.073
	for i = 1, ROWS do
		local f = Instance.new("Frame")
		f.Name = "Row" .. i
		f.Position = UDim2.fromScale(0.03, top + (i - 1) * rowH)
		f.Size = UDim2.fromScale(0.94, rowH - 0.008)
		f.BackgroundColor3 = if i % 2 == 0 then ROW_B else ROW_A
		f.BorderSizePixel = 0
		f.Visible = false
		f.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = f
		local rank = label(f, "Rank", UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.12, 0.8), Enum.Font.FredokaOne, MEDAL[i] or INK, Enum.TextXAlignment.Center)
		local name = label(f, "Name", UDim2.fromScale(0.16, 0.1), UDim2.fromScale(0.5, 0.8), Enum.Font.GothamBold, INK, Enum.TextXAlignment.Left)
		local value = label(f, "Value", UDim2.fromScale(0.66, 0.1), UDim2.fromScale(0.32, 0.8), Enum.Font.FredokaOne, INK, Enum.TextXAlignment.Right)
		for _, t in { rank, name, value } do
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = 40
			c.MinTextSize = 8
			c.Parent = t
		end
		table.insert(rowFrames, { Frame = f, Rank = rank, Name = name, Value = value })
	end

	local note = label(root, "Note", UDim2.fromScale(0.06, 0.28), UDim2.fromScale(0.88, 0.4), Enum.Font.GothamBold, INK, Enum.TextXAlignment.Center)
	note.TextWrapped = true
	local foot = label(root, "Foot", UDim2.fromScale(0.04, 0.93), UDim2.fromScale(0.92, 0.05), Enum.Font.GothamBold, INK_SOFT, Enum.TextXAlignment.Center)
	for _, t in { title, sub, note, foot } do
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = if t == title then 56 else 34
		c.MinTextSize = 8
		c.Parent = t
	end

	local function set(state: Leaderboards.State)
		local rows = state.Rows
		for i, r in rowFrames do
			local row = rows[i]
			r.Frame.Visible = row ~= nil
			if row then
				r.Rank.Text = tostring(row.Rank)
				r.Name.Text = row.Name
				r.Value.Text = row.Text .. (if info.Unit ~= "" then " " .. info.Unit else "")
			end
		end
		if #rows > 0 then
			note.Text = ""
		elseif state.Status == "loading" then
			note.Text = "Loading..."
		elseif state.Status == "unavailable" then
			note.Text = "Records unavailable in this Studio test"
		elseif state.Status == "error" then
			note.Text = "Could not load this board.\nTrying again soon."
		else
			note.Text = "No records yet \u{2014} start a hunt!"
		end
		if state.Status == "error" and #rows > 0 then
			foot.Text = "Showing the last saved list"
		elseif state.Status == "ok" then
			foot.Text = "Top " .. ROWS .. " · ranks never reset"
		else
			foot.Text = ""
		end
	end
	set({ Status = "loading", Rows = {}, Updated = 0 })
	return { Set = set, Root = root }
end

-- The Prospector Lodge boards (docs/lodge/): the kit frame carries the heading (a fitted world sign, LodgeBuilder), so
-- this face is the ranking: FIVE permanent row slots (owner brief 2026-10-10: "each leaderboard permanently displays
-- five prominent ranking rows"), each with a rank chip (gold / silver / bronze for the top three), the player's avatar
-- head shot, name and real score, and one status line under them. A slot without a ranked player stays visible but
-- empty (rank chip, blank avatar, a dash): nothing is invented. The status line always says what the board is doing
-- (loading, empty, unavailable in a Studio test, a failed read and its retry), so the face is never an unexplained
-- black rectangle. Never an example name or score: rows come from LeaderboardService only.
local LODGE_ROWS = 5
-- (phone video 2026-10-13: the near-black face read as a dark slab; a lifted slate face with lighter rows keeps the
-- white names and gold scores high contrast without the black-wall look)
-- (Studio check 2026-10-13: the slate was still too dark; now a bright sky blue face with lighter rows, the same
-- white names and gold scores)
local LODGE_FACE = Color3.fromRGB(46, 118, 206)
local LODGE_ROW = Color3.fromRGB(86, 152, 230)
local LODGE_ROW_EMPTY = Color3.fromRGB(70, 136, 218)
local LODGE_INK = Color3.fromRGB(255, 255, 255)
local LODGE_SOFT = Color3.fromRGB(214, 220, 228)
local LODGE_MEDAL = { Color3.fromRGB(240, 192, 64), Color3.fromRGB(196, 202, 210), Color3.fromRGB(214, 140, 78) }
local LODGE_CHIP = Color3.fromRGB(36, 84, 156)
local LODGE_SCORE = Color3.fromRGB(250, 214, 92)
local LODGE_EMPTY: { [string]: string } = {
	Solo = "No solo finds yet \u{2014} be the first!",
	Wins = "No competitive wins yet \u{2014} be the first!",
	Biggest = "No pets hatched yet \u{2014} be the first!",
	Collection = "No pets hatched yet \u{2014} be the first!",
	Tower = "Nobody has climbed the tower yet \u{2014} be the first!",
}

-- Status line for a board state (also used by the preview check): never empty.
function LobbyBoards.lodgeStatus(boardId: string, state: Leaderboards.State): string
	local n = #state.Rows
	if state.Status == "loading" then
		return "Loading records\u{2026}"
	elseif state.Status == "unavailable" then
		return "Records unavailable in this Studio test"
	elseif state.Status == "error" then
		return if n > 0 then "Showing the last saved list \u{00B7} retrying" else "Records unavailable right now \u{00B7} retrying"
	elseif n == 0 then
		return LODGE_EMPTY[boardId] or "No records yet \u{2014} start a hunt!"
	end
	local info = Boards.Info[boardId]
	return if info then info.Sub else ""
end

function LobbyBoards.createLodgeContent(parent: Instance, boardId: string): Handle
	local root = Instance.new("Frame")
	root.Name = "Board_" .. boardId
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = LODGE_FACE
	root.BorderSizePixel = 0
	root.Parent = parent
	local rowFrames: { { Frame: Frame, Chip: Frame, Rank: TextLabel, Name: TextLabel, Value: TextLabel, Head: ImageLabel } } = {}
	local top, rowH = 0.02, 0.168
	for i = 1, LODGE_ROWS do
		local f = Instance.new("Frame")
		f.Name = "Row" .. i
		f.Position = UDim2.fromScale(0.025, top + (i - 1) * rowH)
		f.Size = UDim2.fromScale(0.95, rowH - 0.022)
		f.BackgroundColor3 = LODGE_ROW_EMPTY
		f.BorderSizePixel = 0
		f.Visible = true
		f.Parent = root
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = f
		local chip = Instance.new("Frame")
		chip.Name = "RankChip"
		chip.Position = UDim2.fromScale(0.015, 0.1)
		chip.Size = UDim2.fromScale(0.12, 0.8)
		chip.BackgroundColor3 = LODGE_MEDAL[i] or LODGE_CHIP
		chip.BorderSizePixel = 0
		chip.Parent = f
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = chip
		local rank = label(chip, "Rank", UDim2.fromScale(0, 0.06), UDim2.fromScale(1, 0.88), Enum.Font.FredokaOne, if i <= 3 then Color3.fromRGB(36, 28, 16) else LODGE_INK, Enum.TextXAlignment.Center)
		rank.Text = tostring(i)
		local head = Instance.new("ImageLabel")
		head.Name = "Avatar"
		head.BackgroundColor3 = Color3.fromRGB(40, 96, 176)
		head.BorderSizePixel = 0
		head.Position = UDim2.fromScale(0.15, 0.08)
		head.Size = UDim2.fromScale(0.115, 0.84)
		head.Image = ""
		head.Parent = f
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = head
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0.5, 0)
		hc.Parent = head
		local name = label(f, "Name", UDim2.fromScale(0.29, 0.14), UDim2.fromScale(0.45, 0.72), Enum.Font.GothamBold, LODGE_INK, Enum.TextXAlignment.Left)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local value = label(f, "Value", UDim2.fromScale(0.75, 0.12), UDim2.fromScale(0.225, 0.76), Enum.Font.FredokaOne, LODGE_SCORE, Enum.TextXAlignment.Right)
		for _, t in { rank, name, value } do
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = 72
			c.MinTextSize = 20 -- big rows: readable on a phone from across the hall
			c.Parent = t
		end
		table.insert(rowFrames, { Frame = f, Chip = chip, Rank = rank, Name = name, Value = value, Head = head })
	end
	-- the status line under the five slots (never empty)
	local status = label(root, "Status", UDim2.fromScale(0.04, 0.865), UDim2.fromScale(0.92, 0.11), Enum.Font.GothamBold, LODGE_SOFT, Enum.TextXAlignment.Center)
	status.TextWrapped = true
	local sc = Instance.new("UITextSizeConstraint")
	sc.MaxTextSize = 34
	sc.MinTextSize = 12
	sc.Parent = status
	local function set(state: Leaderboards.State)
		local rows = state.Rows
		for i, r in rowFrames do
			local row = rows[i]
			if row then
				r.Frame.BackgroundColor3 = LODGE_ROW
				r.Chip.BackgroundTransparency = 0
				r.Rank.Text = tostring(row.Rank)
				r.Name.Text = row.Name
				r.Name.TextColor3 = LODGE_INK
				r.Value.Text = row.Text
				r.Value.TextColor3 = if i <= 3 then LODGE_SCORE else LODGE_INK
				-- avatar head shot from the Roblox thumbnail service (content URL, no web call from this server)
				local img = if row.UserId > 0 then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(row.UserId) else ""
				if r.Head.Image ~= img then -- same picture: leave it alone, so a refresh never reloads (flickers) the avatar
					r.Head.Image = img
				end
			else
				-- an open slot: the rank and a dash, no name, no score, no picture (never an example row)
				r.Frame.BackgroundColor3 = LODGE_ROW_EMPTY
				r.Chip.BackgroundTransparency = 0.55
				r.Rank.Text = tostring(i)
				r.Name.Text = "\u{2014}"
				r.Name.TextColor3 = LODGE_SOFT
				r.Value.Text = ""
				if r.Head.Image ~= "" then
					r.Head.Image = ""
				end
			end
		end
		status.Text = LobbyBoards.lodgeStatus(boardId, state)
		status.TextColor3 = if #rows == 0 then LODGE_INK else LODGE_SOFT
	end
	set({ Status = "loading", Rows = {}, Updated = 0 })
	return { Set = set, Root = root }
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Builds the four boards at the BoardMounts the lobby builder placed on the north records wall (an
-- invisible Mount_<id> part per board whose +Z side faces the viewer, plus Mount_Header). The
-- boards are compact and framed; one fitted text title serves the wall.
-- Plain-text board (the owner's hand-built boards: one TextLabel, attribute BoardId set by MapHooks): the title, then
-- one line per row ("1. Name   12,345"), or the honest status line when there are no rows.
function LobbyBoards.textFor(boardId: string, state: Leaderboards.State, maxRows: number?): string
	local info = Boards.Info[boardId]
	local lines = { if info then info.Title else boardId }
	if #state.Rows == 0 then
		table.insert(lines, LobbyBoards.lodgeStatus(boardId, state))
	else
		for i, row in state.Rows do
			if i > (maxRows or 5) then
				break
			end
			table.insert(lines, ("%d. %s   %s"):format(row.Rank, row.Name, row.Text))
		end
	end
	return table.concat(lines, "\n")
end

-- Every TextLabel in the world marked with attribute BoardId (MapHooks: the hand-built lobby's leaderboards) gets
-- the board as text, now and on every refresh.
local function bindTextBoards()
	local labels: { [string]: { TextLabel } } = {}
	for _, d in game:GetService("Workspace"):GetDescendants() do
		local id = d:GetAttribute("BoardId")
		if d:IsA("TextLabel") and type(id) == "string" and Boards.Info[id] then
			labels[id] = labels[id] or {}
			table.insert(labels[id], d)
		end
	end
	local function set(board: string)
		local list = labels[board]
		if list then
			-- fitted to the owner's board face, white with a black outline, unlit (KitPlace.fitMapLabel): the owner's
			-- labels were TextScaled dark text on a dark face, unreadable on a phone. The label paints a bright sky
			-- blue backing over the dark face, and the board shows its top three so each row can be big.
			local text = LobbyBoards.textFor(board, Leaderboards.get(board), 3)
			for _, l in list do
				l.BackgroundColor3 = LODGE_FACE
				l.BackgroundTransparency = 0
				local ok: boolean, err: any = pcall(KitPlace.fitMapLabel, l, text, "Landmark")
				if not ok then
					l.Text = text
					warn("[LobbyBoards] text board", board, "not fitted:", err)
				end
			end
		end
	end
	Leaderboards.onUpdated(set)
	for id in labels do
		set(id)
	end
end

function LobbyBoards.build(lobbyRoot: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CT_Rocks_Leaderboards"
	folder.Parent = lobbyRoot
	local handles: { [string]: Handle } = {}
	local okText: boolean, errText: any = pcall(bindTextBoards)
	if not okText then
		warn("[LobbyBoards] text boards not bound:", errText)
	end
	local mounts = lobbyRoot:FindFirstChild("BoardMounts")
	if not mounts then
		warn("[LobbyBoards] no BoardMounts folder in the lobby; boards not built")
		return handles
	end
	for _, id in Boards.Order do
		local info = Boards.Info[id]
		local mount = mounts:FindFirstChild("Mount_" .. id) :: BasePart?
		if mount and mount:GetAttribute("Bare") then
			-- lodge board: the kit frame and heading exist; draw the rows straight onto the mount (+Z = viewer side)
			-- (LightInfluence 0: a display face reads at its own colours whatever the hall lighting does)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "BoardGui"
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 60
			gui.LightInfluence = 0
			gui.Parent = mount
			local ok, h = pcall(LobbyBoards.createLodgeContent, gui, id)
			if ok then
				handles[id] = h
			else
				warn("[LobbyBoards] board", id, "could not be drawn:", h)
			end
		elseif mount then
			local W, H = mount.Size.X, mount.Size.Y
			local cf = mount.CFrame
			local m = Instance.new("Model")
			m.Name = "Board_" .. id
			m.Parent = folder
			block(m, "Frame", Vector3.new(W + 0.5, H + 0.5, 0.4), cf * CFrame.new(0, 0, -0.3), Color3.fromRGB(110, 78, 52), Enum.Material.Wood)
			local face = block(m, "Face", Vector3.new(W, H, 0.2), cf * CFrame.new(0, 0, -0.1), FACE, Enum.Material.SmoothPlastic)
			local accent = block(m, "AccentBar", Vector3.new(W * 0.6, 0.1, 0.45), cf * CFrame.new(0, H / 2 + 0.3, -0.25), info.Accent, Enum.Material.SmoothPlastic)
			accent.CanCollide = false
			local gui = Instance.new("SurfaceGui")
			gui.Name = "BoardGui"
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
			gui.CanvasSize = Vector2.new(580, 710)
			gui.LightInfluence = 0
			gui.Parent = face
			handles[id] = LobbyBoards.createContent(gui, id)
		end
	end
	-- ONE title for the whole records wall: a wood plate with a single fitted SurfaceGui line. (The first kit
	-- pass spelled RECORDS in 5x7 pixel-font blocks with 0.25-stud gaps, so rounded letters read as broken
	-- segments, and two wall lamps hung over the R, E and O. Text is now font text, lamps sit beside it.)
	local header = mounts:FindFirstChild("Mount_Header") :: BasePart?
	if header then
		local hm = Instance.new("Model")
		hm.Name = "Header"
		hm.Parent = folder
		-- one framed Landmark sign (KitPlace.signBoard fits the text to the board: explicit TextSize, PixelsPerStud
		-- derived from it, width fill checked by tools/preview/scenes/signs.luau)
		KitPlace.signBoard(hm, "Plate", header.CFrame * CFrame.new(0, 0, -0.1), header.Size.X, header.Size.Y, "RECORDS", "Landmark", { Face = Color3.fromRGB(58, 61, 67), Ink = Color3.fromRGB(232, 226, 212), Frame = Color3.fromRGB(58, 61, 67), Trim = Color3.fromRGB(217, 164, 65) })
	end

	local lastSig: { [string]: string } = {}
	local function refresh(board: string)
		local h = handles[board]
		if h then
			-- redraw only when the rows changed (a refresh with the same data repaints nothing)
			local st = Leaderboards.get(board)
			local parts = { st.Status }
			for _, row in st.Rows do
				table.insert(parts, row.Rank .. "|" .. row.Name .. "|" .. row.Text .. "|" .. row.UserId)
			end
			local sig = table.concat(parts, ";")
			if lastSig[board] == sig then
				return
			end
			local ok: boolean, err: any = pcall(h.Set, Leaderboards.get(board))
			if ok then
				lastSig[board] = sig -- only a board that painted skips the same rows next time
			else
				warn("[LobbyBoards] board", board, "could not be updated:", err)
			end
		end
	end
	Leaderboards.onUpdated(refresh)
	for id in handles do
		refresh(id)
	end
	return handles
end

return LobbyBoards
