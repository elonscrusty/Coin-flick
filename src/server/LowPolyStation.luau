--!strict
-- The owner's low-poly station kit (IMPORT_NOW2/StationKit_LowPoly.fbx, imported into ServerStorage.StationKit_LowPoly):
-- the carried basket and the three tappers become kit templates in ReplicatedStorage.Assets.Kit (the same names
-- MeshService builds from the uploaded meshes, so CarryView and the tool code pick them up unchanged), and
-- StationModels asks `nestPieces` for the straw nest. Untextured meshes: colours and materials are set here.
-- Without the imported kit everything stays as it was.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LowPolyStation = {}

local WOOD = Color3.fromRGB(196, 140, 86)
local WOOD_DARK = Color3.fromRGB(150, 98, 56)
local STRAW = Color3.fromRGB(240, 204, 120)

local function kit(): Instance?
	return ServerStorage:FindFirstChild("StationKit_LowPoly")
end

-- Kit pieces as unparented copies in studs. An import that came in centimetre-sized (a 190-stud tapper handle)
-- is scaled down 100x, positions included, so the pieces keep their layout.
local function pieces(names: { string }): { [string]: MeshPart }
	local out: { [string]: MeshPart } = {}
	local k = kit()
	if k then
		for _, d in k:GetDescendants() do
			if d:IsA("MeshPart") then
				local base = string.gsub(d.Name, "%.%d+$", "")
				if table.find(names, base) and not out[base] then
					out[base] = d
				end
			end
		end
	end
	local big = 0
	for _, p in out do
		big = math.max(big, p.Size.X, p.Size.Y, p.Size.Z)
	end
	local u = if big > 40 then 0.01 else 1
	for name, src in out do
		local p = src:Clone()
		p.Size = src.Size * u
		p.CFrame = CFrame.new(src.Position * u) * src.CFrame.Rotation
		out[name] = p
	end
	return out
end

-- Rescales a group of pieces about the import origin so its size along `axis` is `want` studs (the size of the
-- uploaded mesh it stands in for, so the tool fit and the carry spots keep working).
local function fit(parts: { [string]: MeshPart }, axis: string, want: number)
	local lo, hi = math.huge, -math.huge
	for _, p in parts do
		local c, h = (p.Position :: any)[axis], (p.Size :: any)[axis] / 2
		lo = math.min(lo, c - h)
		hi = math.max(hi, c + h)
	end
	local k = want / math.max(hi - lo, 0.01)
	for _, p in parts do
		p.Size *= k
		p.CFrame = CFrame.new(p.Position * k) * p.CFrame.Rotation
	end
end

-- bottom centre of a group of parts (world space of the import)
local function baseOf(parts: { [string]: MeshPart }): Vector3
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local h = p.Size / 2
		lo = lo:Min(p.Position - h)
		hi = hi:Max(p.Position + h)
	end
	return Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
end

local function template(name: string, parts: { [string]: MeshPart }, look: { [string]: { Color3 | Enum.Material } }, attach: { [string]: Vector3 }): Model
	local origin = baseOf(parts)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	for point, at in attach do
		local a = Instance.new("Attachment")
		a.Name = point
		a.Position = at
		a.Parent = root
	end
	for pieceName, src in parts do
		local p = src:Clone()
		for _, c in p:GetChildren() do
			c:Destroy()
		end
		p.Name = pieceName
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(src.Position - origin) * src.CFrame.Rotation
		local l = look[pieceName]
		if l then
			p.Color = l[1] :: Color3
			p.Material = l[2] :: Enum.Material
		end
		p.Parent = model
	end
	model.PrimaryPart = root
	model.WorldPivot = CFrame.new()
	model:SetAttribute("Ready", true)
	model:SetAttribute("LowPoly", true)
	return model
end

-- Builds the basket and tapper templates over MeshService's. Call after MeshService.start().
function LowPolyStation.apply()
	if not kit() then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
	local kitFolder = assets:FindFirstChild("Kit") or Instance.new("Folder")
	kitFolder.Name = "Kit"
	kitFolder.Parent = assets
	local function put(m: Model)
		local old = kitFolder:FindFirstChild(m.Name)
		if old then
			old:Destroy()
		end
		m.Parent = kitFolder
	end

	local basket = pieces({ "Basket_Body", "Basket_Rim", "Basket_Handle" })
	if basket.Basket_Body then
		fit(basket, "X", 2.37)
		local h = 0
		for _, p in basket do
			h = math.max(h, p.Position.Y + p.Size.Y / 2 - baseOf(basket).Y)
		end
		put(template("Basket_Empty", basket, {
			Basket_Body = { WOOD, Enum.Material.Wood },
			Basket_Rim = { WOOD_DARK, Enum.Material.Wood },
			Basket_Handle = { WOOD_DARK, Enum.Material.Wood },
		}, { Grip = Vector3.new(0, h * 0.95, 0) }))
	end

	local tapper = pieces({ "Tapper_Handle", "Tapper_Head", "Tapper_Band" })
	local head = tapper.Tapper_Head
	if head and tapper.Tapper_Handle then
		fit(tapper, "Y", 4.39)
		local origin = baseOf(tapper)
		local hc = head.Position - origin
		local strike = Vector3.new(hc.X - head.Size.X / 2, hc.Y, hc.Z)
		-- Wooden Mallet, Golden Mallet, Rainbow Tapper (the kit names the tool code maps them to)
		local looks: { [string]: { any } } = {
			Tool_StarterHammer = { WOOD_DARK, Enum.Material.Wood },
			Tool_SteelHammer = { Color3.fromRGB(255, 200, 60), Enum.Material.Metal },
			Tool_Jackhammer = { Color3.fromRGB(255, 120, 200), Enum.Material.Neon },
		}
		for name, headLook in looks do
			put(template(name, tapper, {
				Tapper_Handle = { WOOD, Enum.Material.Wood },
				Tapper_Head = headLook,
				Tapper_Band = { Color3.fromRGB(244, 190, 67), Enum.Material.SmoothPlastic },
			}, { Grip = Vector3.zero, Strike = strike }))
		end
	end
end

-- The low-poly nest for a station plate: { base, straw } MeshParts (clones, unparented) or nil without the kit.
function LowPolyStation.nestPieces(): (MeshPart?, MeshPart?)
	local n = pieces({ "Station_NestBase", "Station_NestStraw" })
	local base = n.Station_NestBase
	local straw = n.Station_NestStraw
	if not (base and straw) then
		return nil, nil
	end
	local b, s = base:Clone(), straw:Clone()
	for _, p in { b, s } do
		for _, c in p:GetChildren() do
			c:Destroy()
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	b.Color = Color3.fromRGB(240, 208, 124)
	b.Material = Enum.Material.SmoothPlastic
	s.Color = STRAW
	s.Material = Enum.Material.SmoothPlastic
	return b, s
end

return LowPolyStation
