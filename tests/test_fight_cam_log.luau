-- Pet Battle camera checked against recorded fights (tests/fixtures/fightcam/*.log). Each file holds the "FCLOG {json}"
-- lines FightCam prints when Workspace has attribute FightCamLog = true (in Studio: the Output window of a test client;
-- offline: tools/preview battle --set log=1). The lines are the real camera and the real drawn pets, so this is where
-- the offline camera maths meets what the game actually did.
return function(t)
	local test, shared = t.test, t.shared
	local Vector3, CFrame = t.Vector3, t.CFrame
	local R = shared("FightCamRules")

	local function vec(a): Vector3
		return Vector3.new(a[1], a[2], a[3])
	end

	-- Parses one log: the fight's start line and its frames.
	local function parse(text: string)
		local start, frames = nil, {}
		for line in string.gmatch(text, "[^\n]+") do
			local body = string.match(line, "FCLOG (%b{})")
			if body then
				local d = t.json(body)
				if d.Shot == "start" then
					start, frames = d, {}
				else
					table.insert(frames, d)
				end
			end
		end
		return start, frames
	end

	-- Screen units (-1..1, y up) of a logged viewport point.
	local function screen(px: number, py: number, vp): (number, number)
		return px / vp[1] * 2 - 1, 1 - py / vp[2] * 2
	end

	local logs = t.fixtures("fightcam")
	for name, text in logs do
		local start, frames = parse(text)
		if start and #frames > 0 then
			test("fight cam log " .. name .. ": the offline projection matches the game's own screen points", function()
				for _, f in frames do
					local pos, look = vec(f.Cam), vec(f.Look)
					local tanV = math.tan(math.rad(f.Fov) / 2)
					local aspect = f.Vp[1] / f.Vp[2]
					for _, p in f.Pets do
						local d = vec(p.C) - pos
						local fwd = look.Unit
						local right = fwd:Cross(if f.Up then vec(f.Up) else Vector3.new(0, 1, 0)).Unit
						local up = right:Cross(fwd)
						local depth = d:Dot(fwd)
						if depth > 3 and p.On then
							local x, y = d:Dot(right) / depth / (tanV * aspect), d:Dot(up) / depth / tanV
							local gx, gy = screen(p.X, p.Y, f.Vp)
							assert(math.abs(x - gx) < 0.03 and math.abs(y - gy) < 0.03,
								string.format("%s at t=%.2f: ours (%.3f, %.3f) game (%.3f, %.3f)", p.N, f.T, x, y, gx, gy))
						end
					end
				end
			end)

			test("fight cam log " .. name .. ": the pets stand where the stage expects them", function()
				local o = vec(start.Origin)
				local origin = CFrame.lookAt(o, o + vec(start.OriginLook))
				-- once they have walked in, the drawn pets stand on the lines the stage was fitted to
				local last = frames[#frames]
				for _, p in last.Pets do
					local local_ = origin:PointToObjectSpace(vec(p.C))
					local onLine = math.abs(local_.Z - start.Layout.PetZ) < 2.5 or math.abs(local_.Z - start.Layout.FoeZ) < 2.5
					assert(onLine, string.format("%s stands off both lines (local z %.1f)", p.N, local_.Z))
				end
			end)

			test("fight cam log " .. name .. ": the wide shot keeps every pet clear of the HUD", function()
				local safe = R.SAFE
				local base, clear = 0, 0
				local worst = ""
				for _, f in frames do
					if f.Shot == "base" then
						base += 1
						local ok = true
						for _, p in f.Pets do
							for _, py in { p.Top, p.Foot } do
								local x, y = screen(p.X, py, f.Vp)
								if not p.On or x < safe.X0 or x > safe.X1 or y < safe.Y0 or y > safe.Y1 then
									ok = false
									worst = string.format("%s t=%.2f (%.2f, %.2f)", p.N, f.T, x, y)
								end
							end
						end
						if ok then
							clear += 1
						end
					end
				end
				assert(base > 0, "the log has wide-shot frames")
				assert(clear / base >= 0.9, string.format("%d of %d wide-shot frames clear; e.g. %s", clear, base, worst))
			end)

			test("fight cam log " .. name .. ": close-ups, K.O. and hero shots keep the pet they frame on screen", function()
				local framedRows, onRows, worst = 0, 0, ""
				for _, f in frames do
					if f.Of then
						for _, p in f.Pets do
							if p.N == f.Of then
								framedRows += 1
								local x, y = screen(p.X, p.Y, f.Vp)
								if p.On and math.abs(x) < 1 and math.abs(y) < 1 then
									onRows += 1
								else
									worst = string.format("%s %s t=%.2f (%.2f, %.2f)", f.Shot, p.N, f.T, x, y)
								end
							end
						end
					end
				end
				-- the first frame or two of a shot are still easing in from the last one
				assert(framedRows == 0 or onRows / framedRows >= 0.8, string.format("%d of %d framed rows on screen; e.g. %s", onRows, framedRows, worst))
			end)
		end
	end
end
