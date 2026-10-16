--!strict
-- Tiny shared animation scheduler for the cosmetic rock, basket and station motion (V3 loop).
-- One Heartbeat connection serves every running animation and disconnects itself when none are
-- left, so idle rounds cost nothing. With reduced motion every animation jumps to its end state at
-- once (callers always end in the correct state; animation never decides anything).

local RunService = game:GetService("RunService")

local State = require(script.Parent.State)

local Anim = {}

type Item = { T0: number, Dur: number, Fn: (number) -> (), Done: (() -> ())?, Dead: boolean }

local items: { Item } = {}
local conn: RBXScriptConnection? = nil

local function reduced(): boolean
	local s = State.Profile and State.Profile.Settings
	return s ~= nil and s.ReducedMotion == true
end

local function step()
	local now = os.clock()
	local i = 1
	while i <= #items do
		local it = items[i]
		if it.Dead then
			table.remove(items, i)
		else
			local k = if it.Dur <= 0 then 1 else math.min(1, (now - it.T0) / it.Dur)
			local ok: boolean, err: any = pcall(it.Fn, k)
			if not ok then
				warn("[Anim] " .. tostring(err))
				it.Dead = true
			end
			if k >= 1 or it.Dead then
				it.Dead = true
				table.remove(items, i)
				if it.Done then
					local ok2: boolean, err2: any = pcall(it.Done :: () -> ())
					if not ok2 then
						warn("[Anim] done: " .. tostring(err2))
					end
				end
			else
				i += 1
			end
		end
	end
	if #items == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- Runs fn(k) every frame for `duration` seconds (k 0..1, ends with exactly 1), then done().
-- Returns a handle: handle.Dead = true stops it (done is not called).
function Anim.run(duration: number, fn: (number) -> (), done: (() -> ())?): Item
	local it: Item = { T0 = os.clock(), Dur = duration, Fn = fn, Done = done, Dead = false }
	if reduced() or duration <= 0 then
		pcall(fn, 1)
		if done then
			pcall(done)
		end
		it.Dead = true
		return it
	end
	pcall(fn, 0)
	table.insert(items, it)
	if not conn then
		conn = RunService.Heartbeat:Connect(step)
	end
	return it
end

-- Scales a model to `factor` times the size it had when this was first called (repeat calls are
-- absolute, not cumulative). Cosmetic: errors are swallowed.
function Anim.scale(model: Model, factor: number)
	pcall(function()
		local cur = (model:GetAttribute("CTScale") or 1) :: number
		local f = math.max(0.02, factor)
		model:ScaleTo(model:GetScale() * (f / cur))
		model:SetAttribute("CTScale", f)
	end)
end

function Anim.cancelAll()
	for _, it in items do
		it.Dead = true
	end
	table.clear(items)
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

function Anim.count(): number
	return #items
end

function Anim.easeOut(k: number): number
	return 1 - (1 - k) * (1 - k)
end

function Anim.easeInOut(k: number): number
	return if k < 0.5 then 2 * k * k else 1 - 2 * (1 - k) * (1 - k)
end

-- Point on a parabola from a to b with `lift` studs of extra height at the middle.
function Anim.arc(a: Vector3, b: Vector3, lift: number, k: number): Vector3
	return a:Lerp(b, k) + Vector3.new(0, lift * 4 * k * (1 - k), 0)
end

return Anim
