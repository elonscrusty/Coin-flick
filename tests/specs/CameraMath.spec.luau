local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CameraMath = require(ReplicatedStorage.Shared.Util.CameraMath)

-- Screen shapes: phone portrait, tablet, PC, phone landscape, the 1914x645 runner window.
local ASPECTS = { 0.46, 0.75, 1.33, 1.78, 2.17, 2.97 }

describe("ZOOM camera fits every coin", function()
	for _, aspect in ASPECTS do
		it(`all 10 coins (and their flips) are on screen at {aspect}`, function()
			local view = CameraMath.tableView(aspect, 55)
			expect(CameraMath.fits(view, aspect, 55)).toBeTruthy()
			for _, p in CameraMath.points() do
				local sx, sy = CameraMath.project(view, p, aspect, 55)
				expect(sx).toBeAtLeast(CameraMath.SAFE.left)
				expect(sx).toBeAtMost(CameraMath.SAFE.right)
				expect(sy).toBeAtLeast(CameraMath.SAFE.bottom)
				expect(sy).toBeAtMost(if p[4] == 1 then CameraMath.SAFE.air else CameraMath.SAFE.top)
			end
		end)
	end

	it("stays close on normal screens (coins are big, not tiny)", function()
		expect(CameraMath.tableView(1.78, 55).up).toBeAtMost(30)
		expect(CameraMath.tableView(2.97, 55).up).toBeAtMost(30)
	end)

	it("a bad screen size never breaks it", function()
		local view = CameraMath.tableView(0 / 0, 55)
		expect(view.up).toBeAtLeast(8)
	end)

	it("the old camera spot really did cut coins off on the wide runner screen", function()
		-- Old: 7 back, 16 up, aim 2.5 past the middle (picture d05/d06).
		local old = { back = 7, up = 16, aim = 2.5 }
		expect(CameraMath.fits(old, 2.97, 55)).toBeFalsy()
	end)
end)
