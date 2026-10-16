-- machine-fx: the machine sounds and the recovery glint are wired (client Audio / Effects called from
-- MachineView). A solo Gravel hunt where only the installed machine cracks; the scene collects every
-- Sound the client creates and checks the expected ones, the 3-loop cap, the wind-down after the
-- round and the glint when a machine finds the geode. Prints PASS/FAIL lines. Mock only: nothing
-- here is heard.
--   --set machine=AutoCracker|HydraulicPress|IndustrialCrusher   (default IndustrialCrusher)
--   --set reduced=on   Reduced motion on: the glint must not appear
local C = lib("ctr")
local Workspace = game:GetService("Workspace")
local machine = preview.args.machine or "IndustrialCrusher"
local reduced = preview.args.reduced == "on"
local fails = {}
local function check(name: string, ok: boolean, detail: string?)
	print(string.format("[%s] %s%s", if ok then "PASS" else "FAIL", name, if detail then (": " .. detail) else ""))
	if not ok then
		table.insert(fails, name)
	end
end

local s = C.boot({
	profile = function(data)
		data.TutorialStep = 1
		data.EquipmentOwned[machine] = true
		data.InstalledMachine = machine
		data.CapacityTier = 3 -- the whole pile fits: the machine never stops on a full bag
		data.Settings.ReducedMotion = reduced
	end,
})
local SoundIds = C.shared("SoundIds")
local nameOf = {}
for name, id in pairs(SoundIds) do
	nameOf["rbxassetid://" .. id] = name
end
local seen: { [string]: number } = {}
local maxLoops = 0
local function onAdded(d)
	if d:IsA("Sound") then
		task.defer(function()
			local n = nameOf[d.SoundId]
			if n then
				seen[n] = (seen[n] or 0) + 1
			end
		end)
	end
end
Workspace.DescendantAdded:Connect(onAdded)
local w = C.watchMatch()
C.startSolo(w)
C.waitPhase(w, "Searching", 8)
local glintSeen = false
local steps = 0
-- the player only collects and deposits (V3 loop); the installed machine crushes the table queue
C.crackUntilFound(w, nil, 400, {
	onStep = function()
		steps += 1
		if steps % 3 == 0 then
			C.followCamera() -- MachineView animates and Audio plays only near the camera
			local loops = 0
			for _, d in Workspace:GetDescendants() do
				if d:IsA("Sound") and d.Looped and (nameOf[d.SoundId] == "ConveyorHum" or nameOf[d.SoundId] == "CrusherLoop") then
					loops += 1
				end
			end
			maxLoops = math.max(maxLoops, loops)
		end
	end,
})
check("machine found the geode (no hand strikes)", w.last.Found ~= nil)
-- the glint is an Emit on a pooled attachment: look for the attachment
local function glintAttachments(): number
	local n = 0
	for _, d in Workspace.Terrain:GetChildren() do
		if d.Name == "CTR_Glint" then
			n += 1
		end
	end
	return n
end
preview.advance(0.2)
glintSeen = glintAttachments() > 0
if reduced then
	check("reduced motion: no glint", not glintSeen)
else
	check("glint on geode recovery", glintSeen, glintAttachments() .. " pooled emitter(s)")
end
if machine == "AutoCracker" then
	check("conveyor hum played", (seen.ConveyorHum or 0) >= 1)
elseif machine == "IndustrialCrusher" then
	check("crusher loop played", (seen.CrusherLoop or 0) >= 1)
else
	check("press descend played", (seen.PressDescend or 0) >= 1)
	check("press impact played", (seen.PressImpact or 0) >= 1)
	check("press retract played", (seen.PressRetract or 0) >= 1)
end
check("machine loops capped at 3", maxLoops <= 3, "max " .. maxLoops)
preview.advance(4)
local still = 0
for _, d in Workspace:GetDescendants() do
	if d:IsA("Sound") and d.Looped and (nameOf[d.SoundId] == "ConveyorHum" or nameOf[d.SoundId] == "CrusherLoop") then
		still += 1
	end
end
check("machine loops wind down after the round", still == 0, still .. " left")
print(if #fails == 0 then ("MACHINE-FX PASS (" .. machine .. ")") else ("MACHINE-FX FAIL (" .. machine .. "): " .. table.concat(fails, ", ")))
