-- Studio Edit-mode check (command bar, read-only, changes nothing): the pet model + animation inventory.
-- Prints one [PetInv] line per ReplicatedStorage.PetModels model (mesh parts, bones found, size, pivot to floor,
-- facing, textures) with flags, then which Config species have no model, then what the live PetMotion / PetClips
-- support. Copy the whole Output back to the coordinator.
local RS = game:GetService("ReplicatedStorage")
local folder = RS:FindFirstChild("PetModels")
if not folder then
	print("[PetInv] NO ReplicatedStorage.PetModels")
	return
end
local WANT = { "Body", "Head", "Tail", "LegL", "LegR", "LegBL", "LegBR", "WingL", "WingR", "Arms", "Jaw" }
local names = {}
for _, m in folder:GetChildren() do
	if m:IsA("Model") then
		table.insert(names, m.Name)
		local bones, meshes, tex, parts, unanch, coll = {}, 0, 0, 0, 0, 0
		local head, body, tail = nil, nil, nil
		for _, d in m:GetDescendants() do
			if d:IsA("Bone") or d:IsA("Motor6D") then
				local key = d.Name:match("_(%a+)$") or d.Name
				bones[key] = true
				if key == "Head" and d:IsA("Bone") then head = d.WorldPosition end
				if key == "Body" and d:IsA("Bone") then body = d.WorldPosition end
				if key == "Tail" and d:IsA("Bone") then tail = d.WorldPosition end
			elseif d:IsA("BasePart") then
				parts += 1
				if d:IsA("MeshPart") then
					meshes += 1
					if d.TextureID ~= "" then tex += 1 end
				end
				if not d.Anchored then unanch += 1 end
				if d.CanCollide then coll += 1 end
			end
		end
		local cf, size = m:GetBoundingBox()
		local pivot = m:GetPivot()
		local floorGap = (cf.Position.Y - size.Y / 2) - pivot.Position.Y
		local have, miss = {}, {}
		for _, b in WANT do
			table.insert(if bones[b] then have else miss, b)
		end
		local facing = "?"
		local back = tail or body
		if head and back then
			local lp = pivot:PointToObjectSpace(head) - pivot:PointToObjectSpace(back)
			facing = if lp.Z < -0.05 then "-Z ok" elseif lp.Z > 0.05 then "+Z (back to front?)" else "flat"
		end
		local flags = {}
		if not m.PrimaryPart then table.insert(flags, "NO_PRIMARY") end
		if math.abs(floorGap) > 0.15 then table.insert(flags, ("PIVOT_OFF_FLOOR %.2f"):format(floorGap)) end
		if size.Y < 1 or size.Y > 12 then table.insert(flags, "ODD_SIZE") end
		if not bones.Head then table.insert(flags, "NO_HEAD_BONE") end
		if not bones.LegL then table.insert(flags, "NO_LEG_BONES") end
		if meshes > 0 and tex == 0 then table.insert(flags, "NO_TEXTURE") end
		if coll > 0 then table.insert(flags, "COLLIDES") end
		print(("[PetInv] %s parts=%d mesh=%d tex=%d size=%.2fx%.2fx%.2f floorGap=%.2f facing=%s attrs Mesh=%s SizeBoost=%s Gait=%s | bones %s | missing %s | %s"):format(
			m.Name, parts, meshes, tex, size.X, size.Y, size.Z, floorGap, facing, tostring(m:GetAttribute("Mesh")),
			tostring(m:GetAttribute("SizeBoost")), tostring(m:GetAttribute("Gait")), table.concat(have, ","),
			table.concat(miss, ","), table.concat(flags, " ")))
	end
end
table.sort(names)
print("[PetInv] models: " .. #names .. " = " .. table.concat(names, " "))
local ok, Config = pcall(function()
	return require(RS:WaitForChild("Shared"):WaitForChild("Config"))
end)
if ok and Config and Config.Minerals then
	local missing = {}
	for id in Config.Minerals do
		if not folder:FindFirstChild("Pet_" .. id) then table.insert(missing, id) end
	end
	table.sort(missing)
	print("[PetInv] species with NO mesh (procedural stand-in): " .. #missing .. " = " .. table.concat(missing, " "))
end
for _, n in { "PetMotion", "PetClips" } do
	local mod = RS:FindFirstChild(n)
	if not mod then
		print("[PetInv] " .. n .. " MISSING")
	else
		local src = mod.Source
		local feats = {}
		for _, k in { "PetPose", "play", "LookAt", "WalkRate", "Sleepy", "PetMotion.spin", "PetMotion.hop", "Gait", "sampleClip", "roar" } do
			if src:find(k, 1, true) then table.insert(feats, k) end
		end
		print(("[PetInv] %s %d chars, has: %s"):format(n, #src, table.concat(feats, ",")))
	end
end
