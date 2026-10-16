--!strict
-- World-sign typography (Master Prompt 5 section 3). Pure maths, no Instances, so tests and the preview
-- audit can run it.
--
-- Cause of the tiny-text signs: every sign factory used TextScaled inside a SurfaceGui with a fixed
-- PixelsPerStud and a text plate sized separately from the visible board. TextScaled never goes above
-- 100 px and the board and the text plate were never tied together, so a big board (or a plate smaller
-- than the black face it sat on) left small words in a sea of board. Here ONE call decides everything
-- from the board size in studs and the text: TextSize is explicit (<= 100), PixelsPerStud is derived from
-- it, and the resulting width fill is checked against the preset range.
--
-- Presets (fraction of the board width the line should fill):
--   Landmark  START HUNT / UPGRADES / COLLECTION / RECORDS: 60-88 percent, big cap height
--   Heading   board headings (SOLO FINDS / COMPETITIVE WINS): up to 94 percent of the board's top band
--   Plaque    small item and counter plaques: up to 88 percent
--   Nameplate owner names: fills to 78 percent, shrinks, then truncates with "..." (MaxChars)
--   Placard   short hints and warnings: up to 92 percent
--   Row       one line of a list board: up to 98 percent of its row box
-- The advance widths are the Fredoka One metrics the preview renderer measured (em units); the real
-- Roblox rendering can differ by a few percent, which the preset ranges leave room for.

local SignLayout = {}

local ADV: { [string]: number } = { [" "]=0.253, ["!"]=0.267, ["\""]=0.429, ["#"]=0.749, ["$"]=0.475, ["%"]=0.838, ["&"]=0.748, ["'"]=0.208, ["("]=0.384, [")"]=0.384, ["*"]=0.503, ["+"]=0.527, [","]=0.238, ["-"]=0.433, ["."]=0.237, ["/"]=0.526, ["0"]=0.608, ["1"]=0.407, ["2"]=0.609, ["3"]=0.608, ["4"]=0.592, ["5"]=0.53, ["6"]=0.56, ["7"]=0.561, ["8"]=0.582, ["9"]=0.56, [":"]=0.238, [";"]=0.237, ["<"]=0.627, ["="]=0.478, [">"]=0.627, ["?"]=0.512, ["@"]=0.908, ["A"]=0.765, ["B"]=0.646, ["C"]=0.679, ["D"]=0.704, ["E"]=0.638, ["F"]=0.637, ["G"]=0.714, ["H"]=0.699, ["I"]=0.257, ["J"]=0.549, ["K"]=0.639, ["L"]=0.587, ["M"]=0.87, ["N"]=0.72, ["O"]=0.775, ["P"]=0.632, ["Q"]=0.83, ["R"]=0.631, ["S"]=0.583, ["T"]=0.731, ["U"]=0.726, ["V"]=0.783, ["W"]=0.999, ["X"]=0.741, ["Y"]=0.686, ["Z"]=0.643, ["["]=0.348, ["\\"]=0.528, ["]"]=0.348, ["^"]=0.526, ["_"]=0.826, ["`"]=0.482, ["a"]=0.596, ["b"]=0.592, ["c"]=0.517, ["d"]=0.598, ["e"]=0.573, ["f"]=0.45, ["g"]=0.585, ["h"]=0.605, ["i"]=0.255, ["j"]=0.252, ["k"]=0.536, ["l"]=0.327, ["m"]=0.851, ["n"]=0.606, ["o"]=0.6, ["p"]=0.582, ["q"]=0.582, ["r"]=0.457, ["s"]=0.489, ["t"]=0.449, ["u"]=0.606, ["v"]=0.638, ["w"]=0.793, ["x"]=0.567, ["y"]=0.604, ["z"]=0.586, ["{"]=0.381, ["|"]=0.217, ["}"]=0.381, ["~"]=0.651 }
local FALLBACK = 0.606
local ASCENT, DESCENT = 0.974, 0.236

export type Preset = { Target: number, Min: number, Max: number, HeightFill: number, TextPx: number, MaxChars: number?, MinEm: number? }
export type Fit = {
	Text: string,
	Preset: string,
	Lines: number,
	Em: number, -- studs per em (font size in studs)
	TextSize: number, -- px, what the TextLabel uses
	PPS: number, -- PixelsPerStud for the SurfaceGui
	Fill: number, -- widest line / board width
	CapStuds: number, -- cap height in studs
	InRange: boolean,
}

SignLayout.Presets = {
	-- (visual pass 2026-10-10: the lodge landmarks fill more of their boards, like the approved painting; was 0.65 / 0.55-0.75 / 0.7)
	Landmark = { Target = 0.78, Min = 0.6, Max = 0.88, HeightFill = 0.78, TextPx = 80 },
	Plaque = { Target = 0.72, Min = 0.45, Max = 0.88, HeightFill = 0.7, TextPx = 60 },
	Nameplate = { Target = 0.78, Min = 0.4, Max = 0.92, HeightFill = 0.7, TextPx = 56, MaxChars = 22, MinEm = 0.36 },
	Placard = { Target = 0.8, Min = 0.4, Max = 0.92, HeightFill = 0.72, TextPx = 48 },
	-- board headings (SOLO FINDS / COMPETITIVE WINS on the lodge boards): fill the top band of the board face
	Heading = { Target = 0.9, Min = 0.55, Max = 0.94, HeightFill = 0.74, TextPx = 80 },
	-- one line of a list board (LAST WINNERS rows): fills its row box nearly edge to edge; long lines just get smaller
	Row = { Target = 0.96, Min = 0.2, Max = 0.98, HeightFill = 0.9, TextPx = 60 },
} :: { [string]: Preset }

-- Lodge landmark lettering (owner brief 2026-10-10, docs/lodge/VISUAL_PASS_BRIEF.md): bold white letters with a
-- controlled black outline, like the approved lobby painting. The outline is a UIStroke on the label (Contextual),
-- its thickness in canvas pixels scaled with the text size so every sign has the same proportion of outline.
SignLayout.Outline = {
	Ink = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(16, 12, 10),
	Transparency = 0.05,
	Ratio = 0.075, -- outline thickness / TextSize
	MinPx = 2,
	MaxPx = 7,
}

-- Outline thickness (px) for a label of `textSize` px.
function SignLayout.outlinePx(textSize: number): number
	local o = SignLayout.Outline
	return math.clamp(math.floor(textSize * o.Ratio + 0.5), o.MinPx, o.MaxPx)
end

-- Width of one line in em.
function SignLayout.lineEm(line: string): number
	local w = 0
	for i = 1, #line do
		w += ADV[string.sub(line, i, i)] or FALLBACK
	end
	return w
end

local function lines(text: string): { string }
	local out = {}
	for l in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, l)
	end
	return out
end

function SignLayout.widestEm(text: string): number
	local m = 0
	for _, l in lines(text) do
		m = math.max(m, SignLayout.lineEm(l))
	end
	return m
end

-- Layout for `text` on a board `boardW` x `boardH` studs.
function SignLayout.fit(text: string, boardW: number, boardH: number, presetName: string): Fit
	local p = SignLayout.Presets[presetName] or SignLayout.Presets.Plaque
	local t = text
	if p.MaxChars and #t > p.MaxChars then
		t = string.sub(t, 1, p.MaxChars - 3) .. "..."
	end
	local ls = lines(t)
	local ew = SignLayout.widestEm(t)
	if ew <= 0 then
		ew = 1
	end
	local function emFor(str: string): number
		local w = SignLayout.widestEm(str)
		local byW = p.Target * boardW / math.max(w, 0.01)
		local byH = p.HeightFill * boardH / ((ASCENT + DESCENT) * #lines(str))
		return math.min(byW, byH)
	end
	local em = emFor(t)
	-- too small to read: drop characters (names only) until it is readable
	if p.MinEm and #ls == 1 then
		while em < p.MinEm and #t > 4 do
			t = string.sub(t, 1, #t - 4) .. "..."
			em = emFor(t)
		end
		ls = lines(t)
		ew = SignLayout.widestEm(t)
	end
	local textSize = p.TextPx
	local pps = math.max(8, textSize / em)
	local fill = em * ew / boardW
	return {
		Text = t,
		Preset = presetName,
		Lines = #ls,
		Em = em,
		TextSize = textSize,
		PPS = pps,
		Fill = fill,
		CapStuds = em * 0.733,
		InRange = fill >= p.Min - 0.001 and fill <= p.Max + 0.001,
	}
end

return SignLayout
