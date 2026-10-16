--!strict
-- How the MEGA coin looks: a real coin, not a flat disc. Pure numbers and colors
-- (no Instances) so the Lune tests can check them; Systems/Mega.build() paints it.
--   raised rim ring + inner ring, gold gradient face, a ring of stars, a big
--   $ / star emblem on the two faces, a white shine bar, and a darker ridge around the edge.

local MegaLook = {}

MegaLook.BASE = Color3.fromRGB(240, 175, 30) -- the metal showing at the edge
MegaLook.FACE_TOP = Color3.fromRGB(255, 238, 140) -- gold gradient: light at the top...
MegaLook.FACE_BOTTOM = Color3.fromRGB(235, 150, 20) -- ...deeper gold at the bottom
MegaLook.RIM = Color3.fromRGB(150, 80, 0) -- thick outer ring
MegaLook.RING = Color3.fromRGB(255, 246, 180) -- thin bright inner ring
MegaLook.EMBLEM = Color3.fromRGB(110, 50, 0) -- the $ and star (dark, so it reads on bright gold)
MegaLook.EMBLEM_STROKE = Color3.fromRGB(255, 246, 180)
MegaLook.STAR = Color3.fromRGB(255, 250, 215)
MegaLook.STAR_STROKE = Color3.fromRGB(120, 60, 0)
MegaLook.RIDGE = Color3.fromRGB(190, 105, 5)
MegaLook.SHINE_ALPHA = 0.78 -- see-through amount of the white shine bar (0 = solid)
MegaLook.REFLECTANCE = 0.3
MegaLook.STARS = 16 -- stars in the ring on each face
MegaLook.STAR_RADIUS = 0.37 -- share of the face
MegaLook.SPARKLE_RATE = 10
MegaLook.SPARKLE_SIZE = 1.8

-- Ridge ring around the edge: a bit thinner than the coin and wider, so seen edge-on it has a bump.
function MegaLook.ridge(thickness: number, diameter: number): (number, number)
	return thickness * 0.75, diameter * 1.07
end

-- Where each star of the ring sits on a face (x, y as 0..1 of the face).
function MegaLook.starSpots(): { { x: number, y: number } }
	local out = {}
	for i = 0, MegaLook.STARS - 1 do
		local a = i / MegaLook.STARS * math.pi * 2
		table.insert(out, {
			x = 0.5 + math.cos(a) * MegaLook.STAR_RADIUS,
			y = 0.5 + math.sin(a) * MegaLook.STAR_RADIUS,
		})
	end
	return out
end

-- Share of the face (0..1) each ring/emblem takes: outer rim, inner ring, emblem.
MegaLook.RIM_SCALE = 0.95
MegaLook.RING_SCALE = 0.78
MegaLook.EMBLEM_SCALE = 0.46

return MegaLook
