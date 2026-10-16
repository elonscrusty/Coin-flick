--!strict
-- Access to the Blender kit models that the server MeshService builds into
-- ReplicatedStorage.Assets.Kit.<Name> (docs/MODELING.md). Every caller keeps its Part stand-in as the
-- fallback: when a template is missing (not uploaded, not loaded yet, Studio without asset access, the
-- offline preview without FBX files) `template` and `clone` return nil and the stand-in is built.
--
-- A template is a Model with an invisible anchored `Root` part at the origin (PrimaryPart, floor centre
-- unless the catalog says otherwise), Attachments on Root for the named points, and one coloured MeshPart
-- per piece, all laid out around the origin. Clones are in "model space" (the origin at CFrame.new()):
-- parent them after PivotTo, or use `place`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitModels = {}

-- The ready template Model for a kit name, or nil.
function KitModels.template(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local kit = assets and assets:FindFirstChild("Kit")
	local m = kit and kit:FindFirstChild(name)
	if m and m:IsA("Model") and m:GetAttribute("Ready") then
		return m
	end
	return nil
end

-- A scaled clone in model space (nil when the template is absent). Sizes, offsets and attachment
-- points are multiplied by `scale`; rotations are kept. Parts stay anchored and non-colliding.
function KitModels.clone(name: string, scale: number?): Model?
	local t = KitModels.template(name)
	if not t then
		return nil
	end
	local m = t:Clone()
	local s = scale or 1
	if math.abs(s - 1) > 1e-4 then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Size = d.Size * s
				d.CFrame = CFrame.new(d.Position * s) * d.CFrame.Rotation
			elseif d:IsA("Attachment") then
				d.Position = d.Position * s
			end
		end
	end
	return m
end

-- Position of a named attachment (on Root, model space) in a clone, or nil.
function KitModels.attach(m: Model, point: string): Vector3?
	local root = m:FindFirstChild("Root")
	local a = root and root:FindFirstChild(point)
	if a and a:IsA("Attachment") then
		return a.Position
	end
	return nil
end

-- Min / max corners of every visible piece of a model (model space), ignoring `Root`.
function KitModels.extents(m: Instance): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local h = d.Size / 2
			local c = d.Position
			lo = Vector3.new(math.min(lo.X, c.X - h.X), math.min(lo.Y, c.Y - h.Y), math.min(lo.Z, c.Z - h.Z))
			hi = Vector3.new(math.max(hi.X, c.X + h.X), math.max(hi.Y, c.Y + h.Y), math.max(hi.Z, c.Z + h.Z))
		end
	end
	return lo, hi
end

-- Moves the parts of a model-space clone to `cf` (a floor-centre frame) without needing a PrimaryPart.
function KitModels.place(m: Model, cf: CFrame)
	m:PivotTo(cf)
end

-- Stable small number from a string (seeded tint / scale per rock name).
function KitModels.hash(s: string): number
	local h = 17
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

return KitModels
