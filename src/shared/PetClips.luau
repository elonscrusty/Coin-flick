--!nonstrict
-- (nonstrict: a data table whose keys hold different channel sets)
-- Shared pet clips (one table for every rig: Body/Head/Tail/LegL/LegR/LegBL/LegBR/WingL/WingR/Arms; no Jaw, no mouth,
-- no roar). Played by PetMotion through PetPose. Root channels rootY/rootZ are studs for a 2.4-stud pet; PetPose scales
-- them by the pet's height. Started from carter's pets\pet_clips.py (Blender-checked previews); edit here now.
local Clips: { [string]: any } = {
	idle = { loop = true, dur = 2.4, keys = {
		{ t = 0.0, rootY = 0.0, rootP = 0.0, tailY = 0.3, tailP = 0.05, headY = 0.35, headP = 0.06, wing = 0.0 },
		{ t = 0.6, rootY = 0.06, rootP = -0.03, tailY = 0.05, tailP = -0.08, headY = 0.2, headP = -0.08, wing = 0.15 },
		{ t = 1.2, rootY = 0.0, rootP = 0.0, tailY = -0.3, tailP = 0.05, headY = -0.35, headP = 0.06, headR = 0.12, wing = 0.0 },
		{ t = 1.8, rootY = 0.06, rootP = -0.03, tailY = -0.05, tailP = -0.08, headY = -0.15, headP = -0.08, wing = 0.15 },
		{ t = 2.4, rootY = 0.0, rootP = 0.0, tailY = 0.3, tailP = 0.05, headY = 0.35, headP = 0.06, wing = 0.0 },
	} },
	walk = { loop = true, dur = 0.8, keys = {
		{ t = 0.0, legFL = -0.44, legBR = -0.44, legFR = 0.44, legBL = 0.44, rootY = 0.0, rootR = 0.16, rootP = 0.1, tailY = 0.6, headP = 0.14, wing = -0.18 },
		{ t = 0.2, rootY = 0.28, rootP = 0.0, tailY = 0.0, headP = -0.16, wing = -0.08 },
		{ t = 0.4, legFL = 0.44, legBR = 0.44, legFR = -0.44, legBL = -0.44, rootY = 0.0, rootR = -0.16, rootP = 0.1, tailY = -0.6, headP = 0.14, wing = -0.18 },
		{ t = 0.6, rootY = 0.28, rootP = 0.0, tailY = 0.0, headP = -0.16, wing = -0.08 },
		{ t = 0.8, legFL = -0.44, legBR = -0.44, legFR = 0.44, legBL = 0.44, rootY = 0.0, rootR = 0.16, rootP = 0.1, tailY = 0.6, headP = 0.14, wing = -0.18 },
	} },
	run = { loop = true, dur = 0.56, keys = {
		{ t = 0.0, legFL = 0.4, legFR = 0.4, legBL = -0.4, legBR = -0.4, rootY = 0.0, rootP = 0.14, tailP = -0.15, headP = -0.06, wing = -0.25 },
		{ t = 0.1, legFL = 0.1, legFR = 0.1, legBL = -0.1, legBR = -0.1, rootY = 0.3, rootP = 0.0, tailP = -0.3, wing = -0.2 },
		{ t = 0.2, legFL = -0.45, legFR = -0.45, legBL = 0.45, legBR = 0.45, rootY = 0.55, rootP = -0.18, tailP = -0.4, tailY = 0.1, headP = 0.1, wing = -0.3 },
		{ t = 0.32, legFL = -0.45, legFR = -0.45, legBL = 0.45, legBR = 0.45, rootY = 0.4, rootP = -0.08, tailP = -0.38, headP = 0.08, wing = -0.28 },
		{ t = 0.44, legFL = 0.2, legFR = 0.2, legBL = -0.2, legBR = -0.2, rootY = 0.08, rootP = 0.12, tailP = -0.22, tailY = -0.1, headP = -0.04, wing = -0.25 },
		{ t = 0.56, legFL = 0.4, legFR = 0.4, legBL = -0.4, legBR = -0.4, rootY = 0.0, rootP = 0.14, tailP = -0.15, headP = -0.06, wing = -0.25 },
	} },
	train = { loop = true, dur = 1.6, keys = {
		{ t = 0.0 },
		{ t = 0.22, rootY = -0.32, rootP = 0.32, legFL = -0.42, legFR = -0.42, headP = -0.25, wing = -0.25, tailP = -0.25 },
		{ t = 0.42, rootY = -0.34, rootP = 0.34, legFL = -0.44, legFR = -0.44, headP = -0.28, wing = -0.28, tailP = -0.28 },
		{ t = 0.62, rootY = 0.0, rootP = 0.0, wing = 0.1 },
		{ t = 0.78, rootY = -0.2, rootP = 0.06, legFL = 0.3, legFR = 0.3, legBL = 0.3, legBR = 0.3, wing = -0.15, tailP = 0.15 },
		{ t = 0.98, rootY = 0.75, rootP = -0.1, legFL = -0.35, legFR = -0.35, legBL = -0.35, legBR = -0.35, wing = 0.55, tailP = -0.35, headP = -0.18 },
		{ t = 1.14, rootY = 0.8, rootP = -0.06, legFL = -0.3, legFR = -0.3, legBL = -0.3, legBR = -0.3, wing = 0.2, tailP = -0.3, headP = -0.15 },
		{ t = 1.32, rootY = -0.12, rootP = 0.06, legFL = 0.25, legFR = 0.25, legBL = 0.25, legBR = 0.25, wing = 0.0, tailP = 0.15 },
		{ t = 1.6 },
	} },
	attack = { loop = false, dur = 0.85, keys = {
		{ t = 0.0 },
		{ t = 0.38, rootY = -0.16, rootZ = -0.7, rootP = -0.22, legFL = 0.3, legFR = 0.3, legBL = 0.3, legBR = 0.3, headP = -0.22, tailP = -0.3, wing = 0.4 },
		{ t = 0.48, rootY = 0.1, rootZ = 2.6, rootP = 0.1, legFL = -0.44, legFR = -0.44, legBL = 0.4, legBR = 0.4, headP = -0.12, tailP = -0.1, wing = 0.65 },
		{ t = 0.6, rootY = 0.04, rootZ = 2.4, rootP = 0.06, legFL = -0.35, legFR = -0.35, legBL = 0.3, legBR = 0.3, headP = -0.08, tailP = -0.08, wing = 0.4 },
		{ t = 0.85 },
	} },
	hit = { loop = false, dur = 0.55, keys = {
		{ t = 0.0 },
		{ t = 0.07, rootY = -0.3, rootZ = -2.2, rootP = -0.4, rootYaw = 0.2, rootR = 0.1, headP = -0.35, headY = -0.22, legFL = 0.3, legFR = 0.3, tailP = 0.25, wing = 0.45 },
		{ t = 0.22, rootY = -0.24, rootZ = -2.1, rootP = -0.36, rootYaw = -0.06, rootR = -0.05, headP = -0.12, headY = 0.1, tailP = 0.1, wing = 0.12 },
		{ t = 0.4, rootY = -0.08, rootZ = -0.9, rootP = -0.1, rootYaw = 0.02, headP = -0.03 },
		{ t = 0.55 },
	} },
	win = { loop = false, dur = 1.7, keys = {
		{ t = 0.0 },
		{ t = 0.15, rootY = -0.12, rootP = 0.1, legFL = 0.25, legFR = 0.25, legBL = 0.25, legBR = 0.25, wing = -0.1 },
		{ t = 0.38, rootY = 0.85, rootP = -0.15, legFL = -0.35, legFR = -0.35, legBL = -0.35, legBR = -0.35, wing = 0.55, tailP = -0.35, headP = -0.25 },
		{ t = 0.5, rootY = 0.9, wing = 0.0, headP = -0.25 },
		{ t = 0.66, rootY = -0.08, rootP = 0.08, legFL = 0.2, legFR = 0.2, legBL = 0.2, legBR = 0.2, wing = 0.45, tailY = 0.4 },
		{ t = 0.8, rootY = -0.12, rootP = 0.1, wing = -0.1, tailY = -0.4 },
		{ t = 1.05, rootY = 0.95, rootYaw = 3.1416, rootP = -0.15, legFL = -0.35, legFR = -0.35, legBL = -0.35, legBR = -0.35, wing = 0.6, tailP = -0.35, headP = -0.3 },
		{ t = 1.3, rootY = -0.08, rootYaw = 6.2832, rootP = 0.06, wing = 0.1, tailY = 0.4 },
		{ t = 1.5, rootY = 0.0, rootYaw = 6.2832, headP = -0.15, tailY = -0.4, wing = 0.25 },
		{ t = 1.7, rootYaw = 6.2832 },
	} },
}

return Clips
