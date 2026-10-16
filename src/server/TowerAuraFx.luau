--!strict
-- Pet Tower aura: glowing flame curtains that hug the temple (ParkBuilder buildTower). The temple's outline is found by
-- raycasting it from outside in a ring; each outline segment gets one vertical Beam whose height follows the temple's
-- roof line there. The flame texture scrolls upward (Beam.TextureSpeed), so the glow flows by itself on every client:
-- no script runs, nothing replicates per frame. Additive light (LightEmission 1), so see-through layers never flicker.

local TowerAuraFx = {}

local FLAME = "rbxassetid://127854632157422" -- tileable soft flame streaks (white, alpha), made for this aura
local COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 255, 140)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 200)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 140, 255)),
})

-- Builds the aura around `gate` (anchored Model with query-able parts) standing on ground height `groundY`.
function TowerAuraFx.build(gate: Model, groundY: number, steps: number?): Folder
	local n = steps or 30
	local box, ext = gate:GetBoundingBox()
	local centre = Vector3.new(box.Position.X, groundY, box.Position.Z)
	local far = math.max(ext.X, ext.Z) + 20
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gate }

	local folder = Instance.new("Folder")
	folder.Name = "TowerAuraFx"
	local anchor = Instance.new("Part")
	anchor.Name = "AuraAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new()
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor:SetAttribute("CameraIgnore", true)
	anchor.Parent = folder

	-- outline: hit points at knee height, pushed out a little; roof height just inside each point
	local pts: { Vector3 } = {}
	local tops: { number } = {}
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = centre + dir * far + Vector3.new(0, 2.5, 0)
		local hit = workspace:Raycast(from, -dir * far, params)
		local p = if hit then hit.Position + dir * 1.4 else centre + dir * (math.max(ext.X, ext.Z) / 2 + 1.4) + Vector3.new(0, 2.5, 0)
		-- roof line: the highest point of the temple within a few studs inside this spot
		local top = groundY + 4
		for _, depth in { 2, 5, 9 } do
			local inner = p - dir * depth
			local down = workspace:Raycast(Vector3.new(inner.X, box.Position.Y + ext.Y, inner.Z), Vector3.new(0, -ext.Y * 2 - 10, 0), params)
			if down then
				top = math.max(top, down.Position.Y - depth * 0.6)
			end
		end
		table.insert(pts, Vector3.new(p.X, groundY + 0.2, p.Z))
		table.insert(tops, math.max(top + 5, groundY + 9))
	end

	for i = 1, n do
		local p0, p1 = pts[i], pts[i % n + 1]
		local mid = (p0 + p1) / 2
		local along = p1 - p0
		if along.Magnitude < 0.05 then
			continue
		end
		local h = (tops[i] + tops[i % n + 1]) / 2 - groundY
		local out = (mid - centre) * Vector3.new(1, 0, 1)
		local up = Vector3.yAxis
		-- attachment frame: a Beam spreads its width along the attachments' Y axis, so Y runs along the outline
		local frame = CFrame.fromMatrix(Vector3.zero, up, along.Unit)
		local a0 = Instance.new("Attachment")
		a0.Name = "AuraLow" .. i
		a0.CFrame = CFrame.new(mid) * frame
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Name = "AuraHigh" .. i
		a1.CFrame = CFrame.new(mid + Vector3.new(0, h, 0)) * frame
		a1.Parent = anchor
		local b = Instance.new("Beam")
		b.Name = "AuraFlame" .. i
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = false
		b.Segments = 1
		b.Width0 = along.Magnitude * 1.25
		b.Width1 = along.Magnitude * 1.1
		b.Texture = FLAME
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 9
		b.TextureSpeed = 0.35 + (i % 3) * 0.06
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 2.2
		b.Color = COLOR
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.4, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		b.ZOffset = 0
		b.Parent = anchor
		local _ = out
	end
	return folder
end

return TowerAuraFx
