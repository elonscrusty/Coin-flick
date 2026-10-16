--!strict
-- Route hint (Master Prompt 4, sections 04 and 29). Replaces the giant "ROCK PILE" billboard and the large
-- yellow floor arrow with the smallest thing that still helps:
--   * a small ground chevron a few studs ahead of the avatar, only for a few seconds after the destination
--     changes (basket full -> your table, empty hands -> the pile while still learning), never when the avatar
--     is already close, and fading out; while the destination is far away (lost player) it stays on
--   * a compact chip on the screen edge that points at the destination while it is off screen, kept inside
--     the safe rectangle the HUD hands us (clear of the objective, the left column, the action and jump)
-- Direction always comes from the real target position and the camera, never from a compass constant.
-- Cosmetic only; nothing here sends or decides anything.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.ui.UI)

local GuideArrow = {}

local player = Players.LocalPlayer
local C = UI.Colors

local NEAR = 14 -- studs: closer than this the hint is not needed
local CHEVRON_SECONDS = 6 -- the ground chevron shows this long after the destination changes
local CHEVRON_AHEAD = 4.2
local CHEVRON_ALPHA = 0.35
local FAR = 40 -- studs: further than this the chevron stays on (bug 244: lost players need a steady pointer)
local CHIP_W = 124 -- screen-edge chip size (logical px)
local CHIP_H = 40

local target: Vector3? = nil
local label = ""
local floorY = 0
local shownAt = 0
local folder: Folder? = nil
local chevron: Model? = nil
local offsets: { [Instance]: CFrame } = {} -- bar -> its frame relative to the chevron's tip
local conn: RBXScriptConnection? = nil
local edge: Frame? = nil
local edgeIcon: Frame? = nil
local edgeText: TextLabel? = nil
local boundsFn: (() -> (number, number, number, number))? = nil -- screen px (left, top, right, bottom)

local function bar(parent: Instance, name: string, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.4, 0.08, 1.7)
	p.CFrame = cf
	p.Color = C.Amber
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build()
	if folder and folder.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "CT_Rocks_Guide"
	f.Parent = Workspace
	folder = f
	-- a chevron "V" pointing along -Z: two short bars angled 40 degrees back from the tip
	local m = Instance.new("Model")
	m.Name = "Chevron"
	local right = bar(m, "BarR", CFrame.new(0.55, 0, 0.65) * CFrame.Angles(0, math.rad(40), 0))
	local left = bar(m, "BarL", CFrame.new(-0.55, 0, 0.65) * CFrame.Angles(0, math.rad(-40), 0))
	offsets[right], offsets[left] = right.CFrame, left.CFrame
	m.Parent = f
	chevron = m
	-- edge chip: small and dark with an amber arrow, never the brightest thing on screen
	-- (bug #222: big enough to read on a phone; CHIP_W x CHIP_H)
	local e = UI.frame(UI.screen(), { Name = "GuideEdge", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(CHIP_W, CHIP_H), BackgroundColor3 = C.Slate, BackgroundTransparency = 0.12, Visible = false, ZIndex = 4 })
	UI.corner(e, CHIP_H // 2)
	UI.stroke(e, C.SlateLine, 1.5)
	edgeIcon = UI.icon(e, "arrow", 26, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(22, CHIP_H // 2), Color = C.Amber, Bg = C.Slate })
	local et = UI.text(e, "", { Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -46, 1, 0), Font = UI.Head, TextSize = UI.T.Head, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center })
	et.TextWrapped = false
	UI.fit(et, UI.T.Head, UI.T.Body)
	edgeText = et
	edge = e
end

local curAlpha = 1 -- eased chevron transparency (fades out when the nest is reached)
local lastTick = os.clock()

local function tick()
	local nowT = os.clock()
	local dtT = math.min(nowT - lastTick, 0.1)
	lastTick = nowT
	local t = target
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not t or not root or not chevron then
		return
	end
	local blocked = UI.blocked() or UI.modalOpen() ~= nil or (player:GetAttribute("InTower") == true or player:GetAttribute("InBattle") == true) -- no route hint over a menu or in the tower
	local flat = Vector3.new(t.X - root.Position.X, 0, t.Z - root.Position.Z)
	local near = flat.Magnitude < NEAR
	local cam = Workspace.CurrentCamera
	if edge and cam then
		local gui = UI.screen()
		local vp = cam:WorldToViewportPoint(t + Vector3.new(0, 3, 0))
		local origin, size = gui.AbsolutePosition, gui.AbsoluteSize
		local px, py = vp.X - origin.X, vp.Y - origin.Y
		local l, tp, r, b = 60, 60, size.X - 60, size.Y - 60
		if boundsFn then
			l, tp, r, b = boundsFn()
			l, r, tp, b = l + CHIP_W / 2, r - CHIP_W / 2, tp + CHIP_H / 2, b - CHIP_H / 2 -- the chip's own half size stays inside the rectangle
		end
		-- the chip is for a destination that is OFF screen: one the player can already see (even in a strip the HUD
		-- covers) needs no chip, which used to float mid-screen at the edge of the free rectangle (bug #222)
		local on = vp.Z > 0 and px > 0 and px < size.X and py > 0 and py < size.Y
		edge.Visible = not on and not blocked and not near
		if edge.Visible then
			local cx, cy = (l + r) / 2, (tp + b) / 2
			local dx, dy = px - cx, py - cy
			if vp.Z < 0 then
				dx, dy = -dx, -dy
			end
			if math.abs(dx) < 1 and math.abs(dy) < 1 then
				dy = 1
			end
			local k = math.min(((r - l) / 2) / math.max(math.abs(dx), 1), ((b - tp) / 2) / math.max(math.abs(dy), 1))
			edge.Position = UDim2.fromScale((cx + dx * k) / math.max(size.X, 1), (cy + dy * k) / math.max(size.Y, 1)) -- scale, not offset: the HUD gui has its own UIScale
			if edgeIcon then
				edgeIcon.Rotation = math.deg(math.atan2(dx, -dy))
			end
			if edgeText and edgeText.Text ~= label then
				edgeText.Text = label
			end
		end
	end
	-- ground chevron: a few seconds after the destination changes, never when close or while a panel is open
	local age = os.clock() - shownAt
	local alpha = 1
	local far = flat.Magnitude > FAR
	if not blocked and not near and (far or age < CHEVRON_SECONDS) and flat.Magnitude > 0.1 then
		local fade = if far then 1 else math.clamp((CHEVRON_SECONDS - age) / 1.2, 0, 1) -- last 1.2 s fade out
		alpha = 1 - (1 - CHEVRON_ALPHA) * fade
		local dir = flat.Unit
		local at = Vector3.new(root.Position.X, floorY + 0.12, root.Position.Z) + dir * (CHEVRON_AHEAD + math.sin(os.clock() * 4) * 0.25)
		-- each bar is placed from the same frame (no Model:PivotTo), so the V can never come apart
		local base = CFrame.lookAt(at, at + dir)
		for _, d in (chevron :: Model):GetChildren() do
			local off = offsets[d]
			if off and d:IsA("BasePart") then -- (only the two bars have offsets)
				d.CFrame = base * off
			end
		end
	end
	curAlpha += (alpha - curAlpha) * math.min(1, dtT * 7) -- soft fade, not a snap
	if math.abs(alpha - curAlpha) < 0.01 then
		curAlpha = alpha
	end
	for _, d in (chevron :: Model):GetChildren() do
		if d:IsA("BasePart") then
			d.Transparency = curAlpha
		end
	end
end

-- The HUD tells us the rectangle (screen px inside the HUD gui) the edge chip may use.
function GuideArrow.setBounds(fn: (() -> (number, number, number, number))?)
	boundsFn = fn
end

-- Points at `pos` (world) with `name` as the short chip text; nil clears it. Calling it again with the same
-- destination keeps the current chevron timer; a new destination restarts it.
function GuideArrow.set(pos: Vector3?, name: string?, floor: number?)
	if not pos then
		GuideArrow.clear()
		return
	end
	build()
	if label ~= (name or "") or not target then
		shownAt = os.clock()
	end
	target = pos
	label = name or ""
	floorY = floor or pos.Y
	if not conn then
		conn = RunService.Heartbeat:Connect(tick)
	end
end

function GuideArrow.clear()
	target = nil
	label = ""
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if edge then
		edge:Destroy()
		edge, edgeIcon, edgeText = nil, nil, nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	chevron = nil
	table.clear(offsets)
	curAlpha = 1
end

function GuideArrow.label(): string
	return label
end

return GuideArrow
