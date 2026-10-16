--!strict
-- Short number text for small phone screens: 950, 1.2K, 34.5M, 1.20B ...

local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local index = 0
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	-- Keep at most 3 significant digits so it always fits.
	local text: string
	if n >= 100 then
		text = string.format("%d", math.floor(n))
	elseif n >= 10 then
		text = string.format("%.1f", math.floor(n * 10) / 10)
	else
		text = string.format("%.2f", math.floor(n * 100) / 100)
	end
	return sign .. text .. SUFFIXES[index]
end

function Format.percent(chance: number): string
	return string.format("%d%%", math.floor(chance * 100 + 0.5))
end

return Format
