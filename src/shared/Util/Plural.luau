--!strict
-- Numbers agree with their word in goal texts: "Get 1 heads" -> "Get 1 head", "2 time" -> "2 times".
-- Used by the rules that build job / challenge texts and by the panels, so every path is right.

local Plural = {}

-- "1 head", "2 times": numbers in goal texts agree with their word ("Get 1 heads" -> "Get 1 head").
local SINGULAR = { heads = "head", coins = "coin", upgrades = "upgrade", times = "time", flips = "flip" }
local PLURAL = { time = "times" }
function Plural.fix(text: string): string
	local fixed = string.gsub(text, "([%d,]+) rare coins", function(num: string)
		return if tonumber((string.gsub(num, ",", ""))) == 1 then `{num} rare coin` else `{num} rare coins`
	end)
	local out, pos = "", 1
	while true do
		local first, last, num, word = string.find(fixed, "([%d,]+) (%a+)", pos)
		if not first or not last or not num or not word then
			break
		end
		local n = tonumber((string.gsub(num, ",", "")))
		local replaced = word
		if n == 1 and SINGULAR[word] then
			replaced = SINGULAR[word]
		elseif n ~= nil and n ~= 1 and PLURAL[word] then
			replaced = PLURAL[word]
		end
		out ..= string.sub(fixed, pos, first - 1) .. `{num} {replaced}`
		pos = last + 1
	end
	fixed = out .. string.sub(fixed, pos)
	return fixed
end

return Plural
