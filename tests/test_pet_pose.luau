-- Pet pose (PetPose + PetClips): clips loop cleanly and end at rest, legs never pass the hip-stretch limit, steps
-- keep pace with the ground (no foot sliding), clip moves scale with the pet, every species gets a body type,
-- no jaw channel (owner rule: mouths stay shut), switching clips never pops.
return function(t)
	local test, shared = t.test, t.shared
	local Config = shared("Config")
	local PetPose = shared("PetPose")
	local Clips = shared("PetClips")

	local LEGS = { "legFL", "legFR", "legBL", "legBR" }
	local function input(over: { [string]: any }?)
		local i = { moving = false, speed = 0, height = 2.4, gait = "quad", rigged = true, anim = nil, walkRate = nil,
			sleepy = false, aimYaw = nil, aimPitch = nil, yaw = 0 }
		for k, v in over or {} do
			i[k] = v
		end
		return i
	end
	local function finite(x: number): boolean
		return x == x and x > -1e6 and x < 1e6
	end

	test("pet clips: keys ordered, loops seamless, one-shots end at rest, no jaw channel", function()
		local known = {}
		for _, ch in PetPose.CH do
			known[ch] = true
		end
		for name, c in Clips do
			local prev = -1
			for _, k in c.keys do
				assert(k.t > prev, name .. " key times must rise")
				prev = k.t
				for ch, v in k do
					assert(ch == "t" or known[ch], name .. " unknown channel " .. tostring(ch))
					assert(not string.find(string.lower(ch), "jaw"), name .. " has a jaw channel")
					assert(type(v) == "number" and finite(v), name .. " bad value")
				end
			end
			assert(c.keys[1].t == 0 and math.abs(prev - c.dur) < 1e-6, name .. " keys span 0..dur")
			local a, b = c.keys[1], c.keys[#c.keys]
			for _, ch in PetPose.CH do
				local va, vb = a[ch] or 0, b[ch] or 0
				if c.loop then
					assert(math.abs(va - vb) < 1e-6, name .. " loop seam on " .. ch)
				elseif ch == "rootYaw" then
					assert(math.abs(vb - math.floor(vb / (2 * math.pi) + 0.5) * 2 * math.pi) < 0.01, name .. " ends facing forward")
				else
					assert(math.abs(vb) < 1e-6, name .. " ends off rest on " .. ch)
				end
			end
		end
		for _, need in { "idle", "walk", "run", "train", "attack", "hit", "win" } do
			assert(Clips[need], "missing clip " .. need)
		end
	end)

	test("pet pose: every gait and clip keeps legs inside the hip limit, no NaN, never sinks far", function()
		local anims = { false, "idle", "walk", "run", "train" }
		for gname in PetPose.GAITS do
			for _, h in { 1.2, 2.4, 4.6, 9 } do
				for _, anim in anims do
					local s = PetPose.new(3)
					for f = 1, 600 do
						local moving = (f // 120) % 2 == 0
						local V = PetPose.step(s, input({ moving = moving, speed = if moving then 16 else 0, height = h,
							gait = gname, anim = if anim then anim else nil, yaw = f * 0.01 }), 1 / 60)
						if f == 200 then
							PetPose.play(s, "attack")
						elseif f == 400 then
							PetPose.pop(s, "celebrate")
						end
						for _, ch in PetPose.CH do
							assert(finite(V[ch]), gname .. " NaN in " .. ch)
						end
						for _, leg in LEGS do
							assert(math.abs(V[leg]) <= PetPose.LEG_MAX + 1e-9, gname .. " " .. leg .. " " .. V[leg])
						end
						assert(V.rootY > -0.2 * h - 0.05, gname .. " sinks " .. V.rootY .. " at h " .. h)
					end
				end
			end
		end
	end)

	test("pet pose: steps keep pace with the ground (no foot slide) up to the cap", function()
		for gname, g in PetPose.GAITS do
			for _, h in { 2.4, 4.6 } do
				for _, speed in { 3, 6, 10, 16 } do
					local r = PetPose.stepRate(g, speed, h, nil)
					local covered = r / (2 * math.pi) * g.cycle * h -- studs per second the feet travel
					if r < g.maxRate - 1e-6 and r > g.minRate * 0.6 + 1e-6 then
						assert(math.abs(covered - speed) / speed < 0.01, gname .. " slides at " .. speed)
					end
					assert(r <= g.maxRate + 1e-6, gname .. " buzzes")
				end
			end
			-- on the spot (viewport, no measured speed): the gait's own rate, faster with WalkRate
			assert(PetPose.stepRate(g, 0, 2.4, nil) == g.minRate, gname .. " on the spot")
			assert(PetPose.stepRate(g, 0, 2.4, 1.5) > g.minRate, gname .. " walk rate")
		end
		-- bigger pets take slower steps at the same speed
		local q = PetPose.GAITS.quad
		assert(PetPose.stepRate(q, 8, 4.6, nil) < PetPose.stepRate(q, 8, 2.4, nil), "big pets step slower")
	end)

	test("pet pose: clip and hop moves scale with the pet's height", function()
		local function peak(h: number, what: string): number
			local s = PetPose.new(1)
			if what == "attack" then
				PetPose.play(s, "attack")
			else
				PetPose.pop(s, "hatch")
			end
			local m = 0
			for _ = 1, 60 do
				local V = PetPose.step(s, input({ height = h }), 1 / 60)
				m = math.max(m, if what == "attack" then V.rootZ else V.rootY)
			end
			return m
		end
		for _, what in { "attack", "hatch" } do
			local small, big = peak(2.4, what), peak(4.8, what)
			assert(small > 0.1, what .. " moves")
			assert(math.abs(big / small - 2) < 0.15, what .. " scales: " .. small .. " vs " .. big)
		end
	end)

	test("pet pose: sits only after standing still, never drops more than the cap; any move stands it up", function()
		local s = PetPose.new(2)
		local V
		for _ = 1, math.floor(PetPose.SIT_AFTER * 60) - 30 do
			V = PetPose.step(s, input({ height = 9 }), 1 / 60)
		end
		assert(s.sit < 0.01, "not sitting yet")
		local low = 0
		for _ = 1, 300 do
			V = PetPose.step(s, input({ height = 9 }), 1 / 60)
			low = math.min(low, V.rootY)
		end
		assert(s.sit > 0.9, "sits")
		assert(low >= -PetPose.SIT_DROP_MAX - 0.011 * 9, "sit drop " .. low) -- plus breathing
		for _ = 1, 30 do
			PetPose.step(s, input({ moving = true, speed = 10, height = 9 }), 1 / 60)
		end
		assert(s.sit < 0.1, "stands up when moving")
	end)

	test("pet pose: hoppers hop with legs together, the rest walk with legs in turn", function()
		local s = PetPose.new(4)
		local maxY, sameFront, apart = 0, true, false
		for _ = 1, 240 do
			local V = PetPose.step(s, input({ moving = true, speed = 8, gait = "hopper" }), 1 / 60)
			maxY = math.max(maxY, V.rootY)
			sameFront = sameFront and math.abs(V.legFL - V.legFR) < 1e-9
		end
		assert(sameFront and maxY > 0.15, "hopper hops " .. maxY)
		local q = PetPose.new(4)
		for _ = 1, 240 do
			local V = PetPose.step(q, input({ moving = true, speed = 8, gait = "quad" }), 1 / 60)
			apart = apart or math.abs(V.legFL - V.legFR) > 0.3
		end
		assert(apart, "quad steps in turn")
	end)

	test("pet pose: switching clips fades (no pops), look-at is limited, sleepy ignores it", function()
		local s = PetPose.new(5)
		local last = {}
		local worst = 0
		for f = 1, 600 do
			local anim = ({ nil, "walk", "run", "train", "idle" } :: { any })[(f // 90) % 5 + 1]
			local V = PetPose.step(s, input({ moving = anim ~= nil, speed = 12, anim = anim, height = 2.4 }), 1 / 60)
			if f > 1 then
				for _, ch in PetPose.CH do
					if ch ~= "rootYaw" then
						worst = math.max(worst, math.abs(V[ch] - last[ch]))
					end
				end
			end
			for _, ch in PetPose.CH do
				last[ch] = V[ch]
			end
		end
		-- the fast run clip moves a leg up to ~0.2 rad a frame by itself; an unfaded switch jumps 0.5-0.9 rad
		assert(worst < 0.3, "biggest frame jump " .. worst)
		local a = PetPose.new(6)
		local V
		for _ = 1, 120 do
			V = PetPose.step(a, input({ aimYaw = 2.5, aimPitch = -1 }), 1 / 60)
		end
		assert(math.abs(V.headY) <= 0.62 and a.lookYaw > 0.55, "look-at turns the head, limited " .. V.headY)
		local z = PetPose.new(6)
		for _ = 1, 240 do
			V = PetPose.step(z, input({ aimYaw = 2.5, sleepy = true }), 1 / 60)
		end
		assert(z.lookW < 0.05 and V.headP > 0.2, "sleepy: head droops, no look-at")
	end)

	test("pet pose: every species gets a body type; known bodies are right", function()
		for id, sp in Config.Minerals do
			local g = PetPose.gaitFor(id, sp.Name, sp.Kind, nil)
			assert(PetPose.GAITS[g], id .. " gait " .. tostring(g))
		end
		assert(PetPose.gaitFor("Bunny") == "hopper", "bunny")
		assert(PetPose.gaitFor("Frog") == "hopper", "frog")
		assert(PetPose.gaitFor("Waddlefrost") == "waddle", "penguin")
		assert(PetPose.gaitFor("Mammoth") == "heavy", "mammoth")
		assert(PetPose.gaitFor("Panda") == "heavy", "panda")
		assert(PetPose.gaitFor("Raptor") == "biped", "raptor")
		assert(PetPose.gaitFor("DireWolf") == "quad", "wolf")
		assert(PetPose.gaitFor("Somebody", "Grizzly Bear") == "heavy", "name words")
		assert(PetPose.gaitFor("Unknown", nil, nil, false) == "biped", "two-leg rig")
		assert(PetPose.gaitFor("Unknown", nil, "raptor", true) == "quad", "a four-leg rig beats the old Kind")
	end)

	test("pet pose: one-shots return to the loop; a small hop never cuts a hatch short", function()
		local s = PetPose.new(7)
		assert(PetPose.play(s, "win"), "win plays")
		assert(not PetPose.play(s, "roar"), "no roar clip")
		for _ = 1, math.ceil(Clips.win.dur * 60) + 2 do
			PetPose.step(s, input(), 1 / 60)
		end
		assert(s.shot == nil, "win ends")
		PetPose.pop(s, "hatch")
		PetPose.step(s, input(), 0.2)
		PetPose.pop(s, "hop")
		assert(s.popKind == "hatch", "hop waits for the hatch")
	end)
	test("pet pose: wings swing slowly and stay in range (idle, happy burst, walk, clips, one-shots)", function()
		local s = PetPose.new(2)
		local dt = 1 / 60
		local last: number? = nil
		local lo, hi = math.huge, -math.huge
		local function run(over: { [string]: any }?, secs: number)
			for _ = 1, math.floor(secs / dt) do
				local w = PetPose.step(s, input(over), dt).wing
				if last then
					assert(math.abs(w - last) <= PetPose.WING_SPEED * dt + 1e-9, "wing swings too fast")
				end
				lo, hi = math.min(lo, w), math.max(hi, w)
				last = w
			end
		end
		run({ gait = "biped" }, 20) -- idle long enough for happy bursts
		run({ gait = "biped", moving = true, speed = 16 }, 3)
		PetPose.pop(s, "celebrate")
		run({ gait = "biped" }, 2)
		for _, name in { "win", "attack", "celebrate" } do
			if Clips[name] then
				PetPose.play(s, name)
				run({ gait = "biped" }, 2)
			end
		end
		run({ gait = "biped", anim = "dance" }, 3)
		assert(lo >= PetPose.WING_MIN - 1e-9 and hi <= PetPose.WING_MAX + 1e-9, "wing out of range")
		assert(hi - lo > 0.4, "wings still beat with a real arc")
	end)
end
