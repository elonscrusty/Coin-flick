--!strict
-- Placement helpers for the Blender kit models (ReplicatedStorage.Assets.Kit, see shared/KitModels and
-- docs/MODELING.md) used by LobbyBuilder, ArenaBuilder and GalleryService. Every function returns nil
-- (or does nothing) when the kit model is missing, so the caller keeps building its Part stand-in.
--
-- Kit frame: +Y up, the FRONT of a model faces -Z. To make a model face world direction d (a unit
-- vector on the ground plane) use `KitPlace.facing(pos, d)`.
-- Kit meshes are non-colliding (MeshService strips collision); structures that players can bump into get
-- invisible blockers from `blocker`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KitModels"))
local SignLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SignLayout"))

local KitPlace = {}

-- Owner-made mesh props (Studio: ServerStorage.MeshyAssets). meshy(name, cf, size) clones one, scales it uniformly so it
-- fits inside `size` (studs), centres it on `cf` and returns it unparented; nil when the asset is missing.
function KitPlace.meshy(name: string, cf: CFrame, size: Vector3): Model?
	local folder = game:GetService("ServerStorage"):FindFirstChild("MeshyAssets")
	local src = folder and folder:FindFirstChild(name)
	if not (src and src:IsA("Model")) then
		return nil
	end
	local m = src:Clone()
	local ext = m:GetExtentsSize()
	local k = math.min(size.X / math.max(ext.X, 0.01), size.Y / math.max(ext.Y, 0.01), size.Z / math.max(ext.Z, 0.01))
	if k > 0 and k ~= 1 then
		m:ScaleTo(m:GetScale() * k)
	end
	local box = m:GetBoundingBox()
	m:PivotTo(cf * box:ToObjectSpace(m:GetPivot()))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return m
end

-- True when every named kit model is present.
function KitPlace.has(...: string): boolean
	for _, n in { ... } do
		if not KitModels.template(n) then
			return false
		end
	end
	return true
end

-- CFrame at `pos` whose kit front (-Z) points along `dir` (ground plane).
function KitPlace.facing(pos: Vector3, dir: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0) -- yaw only; front (-Z) along dir
end

-- Clone a kit model, place it at `cf` (floor-centre frame, front -Z) and parent it. nil when absent.
function KitPlace.place(parent: Instance, name: string, cf: CFrame, scale: number?, modelName: string?): Model?
	local m = KitModels.clone(name, scale)
	if not m then
		return nil
	end
	m.Name = modelName or ("CT_Rocks_" .. name)
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- World position of a named attachment of a placed model, or nil.
function KitPlace.attach(m: Model, point: string): Vector3?
	local root = m:FindFirstChild("Root")
	local a = root and root:FindFirstChild(point)
	if a and a:IsA("Attachment") then
		return (a :: Attachment).WorldPosition
	end
	return nil
end

-- Invisible solid box (collision for a kit structure). `cf` is the box centre.
function KitPlace.blocker(parent: Instance, cf: CFrame, size: Vector3, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Blocker"
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Writes a fitted label into `gui`'s TextLabel: explicit TextSize and PixelsPerStud from SignLayout.fit
-- (never TextScaled), so the text size is known and checkable. Returns the fit.
function KitPlace.applyFit(gui: SurfaceGui, label: TextLabel, text: string, boardW: number, boardH: number, preset: string): SignLayout.Fit
	local f = SignLayout.fit(text, boardW, boardH, preset)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = f.PPS
	label.Text = f.Text
	label.TextScaled = false
	label.TextWrapped = false
	label.TextSize = f.TextSize
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	if label.Parent then
		label.Parent:SetAttribute("SignFill", f.Fill)
	end
	return f
end

-- Size in studs (W, H) of `part`'s `face`.
function KitPlace.faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local s = part.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	end
	return s.X, s.Y
end

-- Text on a sign or board the owner built in Studio (a TextLabel in a SurfaceGui on the board part). The owner's
-- labels used TextScaled or a small fixed TextSize, so long or multi-line text came out tiny on a phone. The code
-- owns the words' size and colour; the frame, face colour and layout stay the owner's:
--   * a label that is the only thing in its SurfaceGui gets the full sign fit (KitPlace.applyFit: explicit TextSize,
--     PixelsPerStud from it);
--   * a label inside the owner's own frames keeps the gui's pixel density (switching it would move offset-sized
--     frames) and only gets an explicit TextSize from the same fit, capped at 100 px.
-- Ink is white with the lodge black outline (KitPlace.outline): high contrast on any face colour. The SurfaceGui
-- ignores the hall lighting (LightInfluence 0), so a board in shade never reads as a black slab.
function KitPlace.fitMapLabel(label: TextLabel, text: string, preset: string): SignLayout.Fit?
	local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
	if not gui then
		label.Text = text
		return nil
	end
	local part = gui.Adornee or gui.Parent
	if not (part and part:IsA("BasePart")) then
		label.Text = text
		return nil
	end
	local W, H = KitPlace.faceSize(part, gui.Face)
	gui.LightInfluence = 0
	label.RichText = false
	local others = 0
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") and d ~= label then
			others += 1
		end
	end
	local f: SignLayout.Fit
	if others == 0 and label.Parent == gui then
		f = KitPlace.applyFit(gui, label, text, W, H, preset)
	else
		-- the label's share of the face: its scale size times the scale sizes of the frames it sits in
		local sx, sy = 1, 1
		local node: Instance? = label
		while node and node ~= gui do
			if node:IsA("GuiObject") then
				sx *= if node.Size.X.Scale > 0.05 then node.Size.X.Scale else 1
				sy *= if node.Size.Y.Scale > 0.05 then node.Size.Y.Scale else 1
			end
			node = node.Parent
		end
		f = SignLayout.fit(text, W * sx, H * sy, preset)
		local pps = if gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud
			then gui.PixelsPerStud
			else math.min(gui.CanvasSize.X / math.max(W, 0.01), gui.CanvasSize.Y / math.max(H, 0.01))
		label.Text = f.Text
		label.TextScaled = false
		label.TextWrapped = false
		label.TextSize = math.clamp(math.floor(f.Em * pps), 8, 100)
	end
	KitPlace.outline(label)
	return f
end

export type SignOpts ={ Face: Color3?, Ink: Color3?, Trim: Color3?, Depth: number?, Frame: Color3?, Outline: boolean? }

-- Framed timber sign. `cf` = centre of the sign front, +Z pointing at the viewer (the Kit.* frame).
-- W x H studs is the readable FACE; the frame, bolts and trim are built around it so the board and the
-- text are one object (no separate plate that can drift from the board). opts: Face colour, Ink colour,
-- Trim colour, Depth. Returns the face part, its label and the fit. Attributes on the face (SignText,
-- SignPreset, SignW, SignH) let tools/preview/scenes/signs.luau audit every sign numerically.
function KitPlace.signBoard(parent: Instance, name: string, cf: CFrame, W: number, H: number, text: string, preset: string, opts: SignOpts?): (Part, TextLabel, SignLayout.Fit)
	local o: SignOpts = opts or ({} :: SignOpts)
	local depth = o.Depth or 0.35
	local faceCol = o.Face or Color3.fromRGB(104, 72, 46)
	local frameCol = o.Frame or Color3.fromRGB(70, 50, 34)
	local trim = o.Trim or Color3.fromRGB(196, 152, 80)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	local function box(n: string, size: Vector3, off: CFrame, col: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = n
		p.Size = size
		p.CFrame = cf * off
		p.Anchored = true
		p.Color = col
		p.Material = mat
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p:SetAttribute("CameraIgnore", true)
		p.Parent = m
		return p
	end
	local bw = math.min(0.32, H * 0.2)
	-- the owner's MeshySign as the frame behind the face when it exists; otherwise the timber frame below
	local meshFrame = KitPlace.meshy("MeshySign", cf * CFrame.new(0, 0, -depth * 0.3), Vector3.new(W + bw * 2, H + bw * 2, depth))
	if meshFrame then
		meshFrame.Name = "Frame"
		for _, d in meshFrame:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d:SetAttribute("CameraIgnore", true)
			end
		end
		meshFrame.Parent = m
	end
	-- frame: four timber rails around the face, a backing board behind
	if not meshFrame then
	box("Back", Vector3.new(W + bw * 2, H + bw * 2, depth * 0.6), CFrame.new(0, 0, -depth * 0.3), frameCol, Enum.Material.WoodPlanks)
	box("RailTop", Vector3.new(W + bw * 2, bw, depth), CFrame.new(0, H / 2 + bw / 2, 0), frameCol, Enum.Material.Wood)
	box("RailBottom", Vector3.new(W + bw * 2, bw, depth), CFrame.new(0, -H / 2 - bw / 2, 0), frameCol, Enum.Material.Wood)
	box("RailL", Vector3.new(bw, H, depth), CFrame.new(-W / 2 - bw / 2, 0, 0), frameCol, Enum.Material.Wood)
	box("RailR", Vector3.new(bw, H, depth), CFrame.new(W / 2 + bw / 2, 0, 0), frameCol, Enum.Material.Wood)
	end
	local face = box("Face", Vector3.new(W, H, 0.1), CFrame.new(0, 0, depth / 2 - 0.12), faceCol, Enum.Material.WoodPlanks)
	-- thin muted-gold inset line just inside the frame, four corner bolts
	local inset = math.min(0.1, H * 0.06)
	box("TrimTop", Vector3.new(W - inset * 2, inset * 0.6, 0.04), CFrame.new(0, H / 2 - inset * 1.2, depth / 2 - 0.06), trim, Enum.Material.SmoothPlastic)
	box("TrimBottom", Vector3.new(W - inset * 2, inset * 0.6, 0.04), CFrame.new(0, -H / 2 + inset * 1.2, depth / 2 - 0.06), trim, Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local b = box("Bolt", Vector3.new(0.2, 0.2, 0.1), CFrame.new(sx * (W / 2 + bw / 2), sy * (H / 2 + bw / 2), depth / 2 + 0.02), Color3.fromRGB(44, 46, 52), Enum.Material.Metal)
			b.Shape = Enum.PartType.Ball
		end
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = Enum.NormalId.Back
	g.LightInfluence = 0.15
	g.Parent = face
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.TextColor3 = o.Ink or Color3.fromRGB(246, 238, 220)
	t.Font = Enum.Font.FredokaOne
	t.TextStrokeTransparency = 1
	t.Parent = g
	local f = KitPlace.applyFit(g, t, text, W, H, preset)
	face:SetAttribute("SignText", f.Text)
	face:SetAttribute("SignPreset", preset)
	face:SetAttribute("SignW", W)
	face:SetAttribute("SignH", H)
	face:SetAttribute("SignFill", f.Fill)
	if o.Outline then
		KitPlace.outline(t) -- landmark lettering: white ink, black outline
	end
	return face, t, f
end

-- Lodge landmark lettering: white ink and a controlled black outline (SignLayout.Outline) on a fitted label. A
-- UIStroke in Contextual mode outlines the glyphs only; its thickness follows the label's TextSize. Marks the sign
-- part (attribute SignOutline = px) so the `signs` audit can check every lodge landmark has it.
function KitPlace.outline(label: TextLabel)
	local o = SignLayout.Outline
	local st = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = o.Stroke
	st.Transparency = o.Transparency
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Thickness = SignLayout.outlinePx(label.TextSize)
	st.Parent = label
	label.TextColor3 = o.Ink
	label.TextStrokeTransparency = 1 -- the UIStroke is the outline (the legacy 1 px stroke would only blur it)
	local gui = label.Parent
	local part = gui and gui.Parent
	if part and part:IsA("BasePart") then
		part:SetAttribute("SignOutline", st.Thickness)
	end
end

-- Unframed fitted text laid on an existing surface (a counter front, a screen). `cf` = centre of the
-- surface, +Z toward the viewer. Same attributes as signBoard so the audit sees it. `outline` = the lodge
-- landmark look (white, black outline: KitPlace.outline).
function KitPlace.signText(parent: Instance, name: string, cf: CFrame, W: number, H: number, text: string, preset: string, ink: Color3?, backing: Color3?, outline: boolean?): (Part, TextLabel, SignLayout.Fit)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(W, H, 0.06)
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	if backing then
		p.Color = backing
	else
		p.Transparency = 1
	end
	p:SetAttribute("CameraIgnore", true)
	p.Parent = parent
	local g = Instance.new("SurfaceGui")
	g.Name = "Label"
	g.Face = Enum.NormalId.Back
	g.LightInfluence = 0
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.TextColor3 = ink or Color3.fromRGB(246, 238, 220)
	t.Font = Enum.Font.FredokaOne
	t.Parent = g
	local f = KitPlace.applyFit(g, t, text, W, H, preset)
	p:SetAttribute("SignText", f.Text)
	p:SetAttribute("SignPreset", preset)
	p:SetAttribute("SignW", W)
	p:SetAttribute("SignH", H)
	if outline then
		KitPlace.outline(t)
	end
	return p, t, f
end

-- Marks every part under `inst` as purely decorative for the client camera (attribute CameraIgnore):
-- roofs, canopies, foliage, lamps and other pieces a camera can end up inside near a walk route.
-- Floors, walls and boundaries are NOT passed here (they stay collidable and occluding).
function KitPlace.cameraIgnore(inst: Instance?)
	if not inst then
		return
	end
	if inst:IsA("BasePart") then
		inst:SetAttribute("CameraIgnore", true)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("CameraIgnore", true)
		end
	end
end

-- Repaints pieces of a placed kit model by piece name (the kit catalog colours are the Blender palette;
-- the lobby tones the lime foliage and the near-black pads down). `map` = { PieceName = Color3 }.
function KitPlace.tone(m: Model?, map: { [string]: Color3 })
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		local c = map[d.Name]
		if c and d:IsA("BasePart") then
			d.Color = c
		end
	end
end

-- Simple collision for a placed kit prop (kit meshes never collide): one invisible box over the model's
-- footprint in its own frame, shrunk 0.15 studs on each side and at most `maxH` tall (default 4: what an avatar
-- bumps into). Returns the blocker, or nil for a missing model. Audited by the `placement` scene (NOCOLLIDE).
function KitPlace.solidify(m: Model?, maxH: number?): Part?
	if not m then
		return nil
	end
	local cf, size = m:GetBoundingBox()
	local h = math.min(size.Y, maxH or 4)
	local bottom = cf.Position.Y - size.Y / 2
	local at = CFrame.new(cf.Position.X, bottom + h / 2, cf.Position.Z) * cf.Rotation
	return KitPlace.blocker(m, at, Vector3.new(math.max(0.4, size.X - 0.3), h, math.max(0.4, size.Z - 0.3)), "Solid")
end

-- Decor policy (Master 8 sections 5 and 23): every visible, non-colliding part under `root` that is not a
-- functional target (no ProximityPrompt / SurfaceGui on it, not a named contract part) is camera-ignored and
-- does not answer raycasts or touches, so trims, labels, shrubs and display pieces never push the camera in,
-- block the line-of-sight check or catch the interaction ray. Applied now and to parts added later (owner
-- cabinets rebuilt by SetCapacity, the record boards, specimens placed by the gallery). Audited by the
-- preview scene `placement` (tools/run_regressions.sh).
local FUNCTIONAL = {
	Body = true, Counter = true, Cabinet = true, Floor = true, Surface = true, Plate = true, Pad = true,
	PreviewAnchor = true, Nameplate = true, Sign = true, Light = true, Stand = true,
}
local function applyDecor(d: Instance)
	if d:IsA("BasePart") and not d.CanCollide and d.Transparency < 1 and not FUNCTIONAL[d.Name]
		and d:GetAttribute("HuntPortal") == nil and d:GetAttribute("TowerPortal") == nil -- portals keep CanTouch
		and not d:FindFirstChildWhichIsA("ProximityPrompt") and not d:FindFirstChildWhichIsA("SurfaceGui") then
		d.CanQuery = false
		d.CanTouch = false
		d:SetAttribute("CameraIgnore", true)
	end
end

function KitPlace.decorPolicy(root: Instance)
	for _, d in root:GetDescendants() do
		applyDecor(d)
	end
	root.DescendantAdded:Connect(function(d)
		-- builders set CanCollide / Transparency right after parenting: look once the frame settles
		task.defer(applyDecor, d)
	end)
end

-- Marks a decorative tree for the client's gentle sway (src/client/LobbyAmbience.luau). The canopy parts are the
-- ones named Leaf / LeafDark / Leaves; `pivot` is the world point they rock about (low on the trunk). Visual only:
-- the server never moves them and nothing else reads the attributes.
function KitPlace.sway(m: Instance?, pivot: Vector3)
	if m then
		m:SetAttribute("Sway", true)
		m:SetAttribute("SwayPivot", pivot)
	end
end

-- Shared rubble hopper from the prop kit (Prop_RubbleHopper): keeps the contract EconomyService and the
-- client rely on: Model attribute Hopper, a `Body` part carrying the ProximityPrompt `SellPrompt` with
-- attribute Sell. `cf` is the floor centre; the hopper's front (receipt, ramp) faces -Z of `cf`.
function KitPlace.hopper(parent: Instance, cf: CFrame, scale: number, panelAttr: boolean): Model?
	local m = KitPlace.place(parent, "Prop_RubbleHopper", cf, scale, "CT_Rocks_SellHopper")
	if not m then
		return nil
	end
	local s = scale
	local body = KitPlace.blocker(m, cf * CFrame.new(-0.5 * s, 2.4 * s, -0.4 * s), Vector3.new(7.2, 4.8, 5.6) * s, "Body")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "SellPrompt"
	pp.ActionText = "Sell Candy"
	pp.ObjectText = "Hopper"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.R -- E is the crack key on keyboards
	pp.UIOffset = Vector2.new(0, 30)
	if panelAttr then
		pp:SetAttribute("Panel", "")
	end
	pp:SetAttribute("Sell", true)
	pp.Parent = body
	m:SetAttribute("Hopper", true)
	-- one fitted SELL label on the slate plate of the front (kit frame: front is -Z, so face the plate toward it)
	KitPlace.signText(m, "SellLabel", cf * CFrame.new(-0.975 * s, 2.525 * s, -2.02 * s) * CFrame.Angles(0, math.pi, 0), 6.0 * s, 1.3 * s, "SELL CANDY", "Plaque", Color3.fromRGB(244, 190, 67))
	return m
end

return KitPlace
