--!nocheck
--[[
	meshes.luau - InsertService:LoadAsset for the Blender mesh models.

	LoadAsset(id) returns what the Roblox importer gives MeshService: a Model holding a
	Model named after the catalog entry, holding one upright MeshPart per piece (named
	like the piece, sized like the piece). Each MeshPart carries the attribute
	PreviewMeshRef = "<Category>/<Model>.fbx#<Piece>", which the renderer resolves to the
	piece geometry inside meshes/<Category>/<Model>.fbx.

	Asset ids come from the live MeshCatalog module (so a scene can patch AssetId = 0
	entries to fake ids and preview models that are not uploaded yet).
]]

local roblox = require("@lune/roblox")
local R = require("./R")

local states = R.states
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local M = {}

R.meshTris = {} -- PreviewMeshRef → triangle estimate (catalog tris / pieces)

-- catalog.json (decoded list) → by name
function M.setCatalog(list)
	local byName = {}
	for _, entry in ipairs(list or {}) do
		byName[entry.name] = entry
	end
	R.catalogJson = byName
end

local function liveCatalog()
	local shared = R.services.ReplicatedStorage and R.findChild(states[R.services.ReplicatedStorage], "Shared")
	local mod = shared and R.findChild(states[shared], "MeshCatalog")
	if not mod then
		return nil
	end
	local ok, value = pcall(R.requireModule, mod)
	if ok and type(value) == "table" then
		return value
	end
	return nil
end
M.liveCatalog = liveCatalog

-- Gives every catalog model with AssetId 0 a fake id so MeshService loads it.
function M.forceUploaded(): { string }
	local mc = liveCatalog()
	local forced = {}
	if not mc then
		R.warn("MeshCatalog module not found; cannot force models as uploaded")
		return forced
	end
	local n = 0
	local names = {}
	for name in pairs(mc.Models or {}) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local entry = mc.Models[name]
		n += 1
		if not entry.AssetId or entry.AssetId == 0 then
			entry.AssetId = 990000000 + n
			table.insert(forced, name)
		end
	end
	return forced
end

-- live Shared/<name> module value (MeshIds: asset id by model name)
local function sharedModule(name)
	local shared = R.services.ReplicatedStorage and R.findChild(states[R.services.ReplicatedStorage], "Shared")
	local mod = shared and R.findChild(states[shared], name)
	if not mod then
		return nil
	end
	local ok, value = pcall(R.requireModule, mod)
	if ok and type(value) == "table" then
		return value
	end
	return nil
end

-- InsertService:LoadAsset(id): the id is looked up in MeshIds, the model in MeshCatalog. Legacy single
-- meshes (CT_Rocks_*, glb only) are not catalog models and fail like an unavailable asset, so the
-- game uses its Part stand-ins for them. Pieces are drawn from art/meshes/<Model>.fbx.
R.loadAsset = function(id)
	local mc = liveCatalog()
	local ids = sharedModule("MeshIds")
	local name, entry
	if mc and ids then
		for n, v in pairs(ids) do
			if v == id then
				name = n
				entry = mc[n]
				break
			end
		end
	end
	if not name or not entry then
		error(string.format("InsertService:LoadAsset(%s): no kit model has this asset id (preview mock)", tostring(id)), 2)
	end
	local container = R.create("Model")
	states[container].name = "Model"
	local model = R.create("Model")
	states[model].name = name
	R.setParent(model, states[model], container)
	local tris = 0
	for _, p in ipairs(entry.Pieces or {}) do
		local mp = R.create("MeshPart")
		local st = states[mp]
		st.name = p.Name
		st.props.Size = Vector3.new(p.Size[1], p.Size[2], p.Size[3])
		st.props.CFrame = CFrame.new(p.Offset[1], p.Offset[2], p.Offset[3])
		st.props.MeshId = "rbxassetid://" .. tostring(id)
		st.props.Anchored = true
		local ref = string.format("%s.fbx#%s", name, p.Name)
		st.attrs = { PreviewMeshRef = ref }
		R.meshTris[ref] = 100
		tris += 100
		R.setParent(mp, st, model)
	end
	return container
end

R.meshes = M
return M
