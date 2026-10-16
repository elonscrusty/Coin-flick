--!strict
-- Hides the hidden eggs this player already found (audit F25: a taken egg stayed visible with its "Hidden Egg · Take"
-- prompt). The server keeps the eggs for everyone and publishes the found ones on the player attribute
-- Hangout.Secrets.FoundAttr; this client hides those eggs, their lights, sparkles and Take prompts for this player
-- only. A tap hides the egg at once; if the server did not take it (out of range, too fast) it comes back.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Hangout = require(Shared.Hangout)

local HiddenEggLocal = {}

local player = Players.LocalPlayer
local prompts: { [ProximityPrompt]: string } = {} -- every hidden egg Take prompt -> its egg name
local hidden: { [string]: boolean } = {}
local watchers: { [Instance]: RBXScriptConnection } = {}

-- the egg's own piece: its Model when it has one, else the part the prompt sits on
local function eggRoot(pp: ProximityPrompt): Instance?
	local part = pp.Parent
	if not part then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and Hangout.secretIndex(model.Name) then
		return model
	end
	return part
end

local function quiet(d: Instance, off: boolean)
	if d:IsA("BasePart") then
		d.LocalTransparencyModifier = if off then 1 else 0
	elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("BillboardGui") then
		(d :: any).Enabled = not off
	end
end

local function apply(pp: ProximityPrompt, off: boolean)
	pp.Enabled = not off
	local root = eggRoot(pp)
	if not root then
		return
	end
	quiet(root, off)
	for _, d in root:GetDescendants() do
		if d ~= pp then
			quiet(d, off)
		end
	end
	local w = watchers[root]
	if off and not w then
		-- sparkles and lights added later (HangoutAnim, WorldFx) stay off too
		watchers[root] = root.DescendantAdded:Connect(function(d)
			task.defer(quiet, d, true)
		end)
	elseif not off and w then
		w:Disconnect()
		watchers[root] = nil
	end
end

local function refresh()
	hidden = Hangout.parseFound(player:GetAttribute(Hangout.Secrets.FoundAttr))
	for pp, name in prompts do
		if pp.Parent then
			apply(pp, hidden[name] == true)
		else
			prompts[pp] = nil
		end
	end
end

local function track(d: Instance)
	if not d:IsA("ProximityPrompt") or d:GetAttribute("Hangout") ~= "Secret" then
		return
	end
	local name = d:GetAttribute("Secret")
	if type(name) ~= "string" then
		return
	end
	prompts[d] = name
	if hidden[name] then
		apply(d, true)
	end
end

function HiddenEggLocal.start()
	player:GetAttributeChangedSignal(Hangout.Secrets.FoundAttr):Connect(refresh)
	for _, d in Workspace:GetDescendants() do
		track(d)
	end
	Workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(track, d) -- the server sets the Hangout / Secret attributes right after making it
		end
	end)
	refresh()
	ProximityPromptService.PromptTriggered:Connect(function(pp: ProximityPrompt)
		local name = prompts[pp]
		if not name then
			return
		end
		apply(pp, true) -- gone at once: no second tap on a taken egg
		task.delay(2, function()
			if not hidden[name] and pp.Parent then
				apply(pp, false) -- the server did not take it: it comes back
			end
		end)
	end)
end

return HiddenEggLocal
