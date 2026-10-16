--!strict
-- Optional bridge to the owner's ReplicatedStorage.PetMotion (client only; animates the real skinned pet meshes from
-- ReplicatedStorage.PetModels). API used: start(model), hatch(model), celebrate(model), play(model, clip) and the model attribute Anim. Every call is pcall'd and does nothing when the
-- module is missing or fails to load (offline preview, places without the meshes), or when the model is a
-- procedural stand-in (PetModel sets attribute Mesh = true only on template pets).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetMotionBridge = {}

local motion: any = nil
local tried = false

local function get(): any
	if tried then
		return motion
	end
	tried = true
	local mod = ReplicatedStorage:FindFirstChild("PetMotion")
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			motion = res
		else
			warn("[PetMotionBridge] PetMotion did not load:", res)
		end
	end
	return motion
end

local function isMesh(model: Instance?): boolean
	return model ~= nil and model:IsA("Model") and model:GetAttribute("Mesh") == true
end
PetMotionBridge.isMesh = isMesh

-- Moves the base pose of a model PetMotion is animating (it re-pivots the model every frame from that base).
-- Returns false when PetMotion is not driving it, so the caller can PivotTo the model itself.
function PetMotionBridge.setBase(model: Model, cf: CFrame): boolean
	local m = get()
	if not m or type(m.setBase) ~= "function" or not isMesh(model) then
		return false
	end
	return (pcall(m.setBase, model, cf))
end

-- Idle / walk animation for a mesh pet shown somewhere (plots, domes, stands). Returns whether it started.
function PetMotionBridge.start(model: Model): boolean
	local m = get()
	if not m or type(m.start) ~= "function" or not isMesh(model) then
		return false
	end
	local ok, err = pcall(m.start, model)
	if not ok then
		warn("[PetMotionBridge] start failed:", err)
	end
	return ok
end

-- The hatch animation (the pet bursting out of its egg). Returns whether it played.
function PetMotionBridge.hatch(model: Model): boolean
	local m = get()
	if not m or type(m.hatch) ~= "function" or not isMesh(model) then
		return false
	end
	local ok, err = pcall(m.hatch, model)
	if not ok then
		warn("[PetMotionBridge] hatch failed:", err)
	end
	return ok
end

-- Victory dance (two spinning hops; no roar, owner rule) when the owner wins a hunt. Returns whether it played.
function PetMotionBridge.celebrate(model: Model): boolean
	local m = get()
	if not m or type(m.celebrate) ~= "function" or not isMesh(model) then
		return false
	end
	local ok, err = pcall(m.celebrate, model)
	if not ok then
		warn("[PetMotionBridge] celebrate failed:", err)
	end
	return ok
end

-- One-shot clip from the owner's PetClips ("attack", "hit", "win"), when this PetMotion has play(). Returns whether
-- it played; nothing happens without the clips.
function PetMotionBridge.play(model: Model?, clip: string): boolean
	local m = get()
	if not model or not m or type(m.play) ~= "function" or not isMesh(model) then
		return false
	end
	local ok, res = pcall(m.play, model, clip)
	return ok and res ~= false
end

-- Looping clip ("idle", "walk", "run", "train"; nil = PetMotion's built-in motion) through the model attribute Anim,
-- which PetMotion cross-fades to (0.2 s). Only mesh pets carry it.
function PetMotionBridge.setAnim(model: Model?, anim: string?)
	if model and isMesh(model) and model:GetAttribute("Anim") ~= anim then
		model:SetAttribute("Anim", anim)
	end
end

return PetMotionBridge
