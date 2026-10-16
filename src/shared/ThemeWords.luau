--!strict
-- THEME WORDS: the one list of words that must never appear in text a player reads. FIND THE PET! is a pet game
-- (find, train, fight): rock and mining wording is banned in names, descriptions, toasts, prompts, quests, news.
-- Code identifiers, attribute names and save keys keep their old names on purpose (CLAUDE.md), so this list is
-- only checked against player-visible strings (tests/test_theme_words.luau). Whole words, case-insensitive.

local ThemeWords = {}

ThemeWords.Banned = {
	"rock", "rocks", "rocky", "boulder", "boulders",
	"crack", "cracks", "cracked", "cracking", "cracker",
	"mallet", "mallets", "hammer", "hammers", "jackhammer", "tapper",
	"mine", "mines", "mining", "miner", "miners",
	"geode", "geodes", "rubble", "quarry", "ore", "ores", "pickaxe", "pickaxes",
	"crush", "crushes", "crushed", "crushing", "crusher", "crushers",
	"shell", "shells",
} :: { string }

local set: { [string]: boolean } = {}
for _, w in ThemeWords.Banned do
	set[w] = true
end

-- The first banned whole word inside `text`, or nil.
function ThemeWords.find(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	for word in string.gmatch(string.lower(text), "%a+") do
		if set[word] then
			return word
		end
	end
	return nil
end

return ThemeWords
