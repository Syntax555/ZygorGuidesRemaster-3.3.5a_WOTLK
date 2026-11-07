-- Achievement guides and corrected quest steps follow the 3.3.5a quest data,
-- achievement criteria and quest givers.
-- Usage: lua tools/guides/test_achievements_335.lua <addon directory>
local root = arg[1] or "ZygorGuidesViewerRM"

local function read(path)
	local f = assert(io.open(path, "rb"), "missing " .. path)
	local s = f:read("*a")
	f:close()
	return (s:gsub("^\239\187\191", ""))
end

local function exists(path)
	local f = io.open(path, "rb")
	if f then f:close() end
	return f ~= nil
end

local function loadedFiles()
	local files = {}
	local function visit(path)
		if path:lower():match("%.lua$") then
			files[#files + 1] = path
			return
		end
		local xml = read(path):gsub("<!%-%-.-%-%->", "")
		local dir = path:match("^(.*)/") or "."
		for _, tag in ipairs({ "Script", "Include" }) do
			for name in xml:gmatch("<" .. tag .. '%s+file="([^"]+)"') do
				local child = dir .. "/" .. name:gsub("\\", "/")
				if exists(child) then visit(child) end
			end
		end
	end
	for line in read(root .. "/" .. root:match("[^/]+$") .. ".toc"):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		local path = root .. "/" .. line:gsub("\\", "/")
		if line ~= "" and not line:match("^#") and path:match("/Guides/") and exists(path) then visit(path) end
	end
	return files
end

local function guide(source, title)
	local first = assert(source:find('RegisterGuide("' .. title .. '"', 1, true), "missing guide " .. title)
	local last = source:find("\n]])", first, true)
	return source:sub(first, last)
end

local function check(label, problems, text, mutate)
	local found = problems(text)
	assert(#found == 0, label .. ": " .. table.concat(found, "; "))
	local mutant = mutate(text)
	assert(mutant ~= text, label .. ": the mutation changed nothing")
	assert(#problems(mutant) > 0, label .. ": the mutation was not detected")
end

local ACH = root .. "/Guides/Achievements/"

-- The Green Hills of Stranglethorn (940) needs quests 338 and 208. Nesingwary's
-- expedition at Nesingwary's Camp gives the Mastery chains, Big Game Hunter and
-- the four chapters; none of them is a Cataclysm quest.
local GREEN_HILLS = {}
for _, id in ipairs({ 583, 185, 186, 187, 188, 190, 191, 192, 193, 194, 195, 196, 197, 208, 338, 339, 340, 341, 342 }) do
	GREEN_HILLS[id] = true
end

local function greenHillsProblems(text)
	local found = {}
	for id in pairs(GREEN_HILLS) do
		if not text:find("accept [^\n#]+##" .. id .. "\n") then found[#found + 1] = "quest " .. id .. " is not accepted" end
		if not text:find("turnin [^\n#]+##" .. id .. "\n") then found[#found + 1] = "quest " .. id .. " is not turned in" end
	end
	for id in text:gmatch("%.%.%a+ [^\n#]+##(%d+)") do
		if not GREEN_HILLS[tonumber(id)] then found[#found + 1] = "quest " .. id .. " is not a Green Hills quest" end
	end
	if text:find("Northern Stranglethorn", 1, true) then found[#found + 1] = "a Cataclysm zone remains" end
	if not text:find("|achieve 940\n", 1, true) then found[#found + 1] = "the achievement step is missing" end
	return found
end

for _, case in ipairs({ { "Alliance", "The Green Hills of Stranglethorn" }, { "Horde", "The Green Hills Of Stranglethorn" } }) do
	local faction, title = case[1], case[2]
	local source = read(ACH .. "ZygorAchievements" .. faction .. ".lua")
	local hills = "Zygor's " .. faction .. " Achievements Guides\\\\Quest Achievements\\\\" .. title
	check(faction .. " 940", greenHillsProblems, guide(source, hills), function(text)
		return (text:gsub("Big Game Hunter##208", "Big Game Hunter##26269", 1))
	end)
	-- Hemet Nesingwary: The Collected Quests (941) reuses those steps.
	local collected = guide(source, "Zygor's " .. faction .. " Achievements Guides\\\\Quest Achievements\\\\Hemet Nesingwary: The Collected Quests")
	local function collectedProblems(text)
		local found = {}
		if not text:find('step\nlabel "TheGreenHills"\n', 1, true) then found[#found + 1] = "no TheGreenHills label" end
		if not text:find('\nleechsteps "' .. hills .. '" 2%-%d+\n') then found[#found + 1] = "the 940 steps are not leeched" end
		if not text:find('step\nlabel "end"\n', 1, true) then found[#found + 1] = "no end label" end
		if not text:find('|next "TheGreenHills" |only if not (completedq(208) and completedq(338))', 1, true) then
			found[#found + 1] = "the redirect does not wait for both 940 quests"
		end
		if text:find("Northern Stranglethorn", 1, true) or text:find("##2626%d") then found[#found + 1] = "Cataclysm steps remain" end
		return found
	end
	check(faction .. " 941", collectedProblems, collected, function(text)
		return (text:gsub('label "end"', 'label "finish"', 1))
	end)
end

-- Exploration criteria in 3.3.5a order. Cataclysm reshaped these zones; the
-- index after |achieve must name the subzone the step unlocks.
local EXPLORE = {
	{ "Eastern Kingdoms", "Badlands", 765, { "Lethlor Ravine", "Camp Boff", "Agmond's End", "Mirage Flats", "Camp Cagg", "Apocryphan's Rest", "Kargath", "The Dustbowl", "Valley of Fangs", "Angor Fortress", "Dustwind Gulch", "Hammertoe's Digsite", "The Maker's Terrace", "Camp Kosh" } },
	{ "Eastern Kingdoms", "Blasted Lands", 766, { "Dreadmaul Hold", "Garrison Armory", "Nethergarde Keep", "Serpent's Coil", "The Dark Portal", "Altar of Storms", "Dreadmaul Post", "The Tainted Scar", "Rise of the Defiler" } },
	{ "Eastern Kingdoms", "Swamp of Sorrows", 782, { "Itharius's Cave", "Misty Valley", "The Harborage", "Splinterspear Junction", "The Shifting Mire", "Stonard", "Pool of Tears", "Stagalbog", "Sorrowmurk", "Fallow Sanctuary", "Misty Reed Strand" } },
	{ "Eastern Kingdoms", "Wetlands", 841, { "Menethil Harbor", "Black Channel Marsh", "Bluegill Marsh", "Whelgar's Excavation Site", "Sundown Marsh", "Saltspray Glen", "Ironbeard's Tomb", "Dun Modr", "Angerfang Encampment", "Dun Algaz", "The Green Belt", "Mosshide Fen", "Direforge Hill", "Raptor Ridge", "Grim Batol" } },
	{ "Eastern Kingdoms", "Western Plaguelands", 770, { "Darrowmere Lake", "Caer Darrow", "Sorrow Hill", "Ruins of Andorhal", "The Bulwark", "Felstone Field", "Dalson's Tears", "The Writhing Haunt", "Northridge Lumber Camp", "Hearthglen", "Gahrron's Withering", "The Weeping Cave", "Thondroril River" } },
	{ "Eastern Kingdoms", "Arathi Highlands", 761, { "Circle of West Binding", "Northfold Manor", "Boulder'gor", "Thoradin's Wall", "Stromgarde Keep", "Faldir's Cove", "Circle of Inner Binding", "Thandol Span", "Boulderfist Hall", "Refuge Pointe", "Circle of Outer Binding", "Witherbark Village", "Go'Shek Farm", "Dabyrie's Farmstead", "Circle of East Binding", "Hammerfall" } },
	{ "Northrend", "Dragonblight", 1265, { "Galakrond's Rest", "Lake Indu'le", "Ruby Dragonshrine", "Obsidian Dragonshrine", "New Hearthglen", "Naxxramas", "Light's Trust", "Icemist Village", "Emerald Dragonshrine", "Coldwind Heights", "Angrathar the Wrath Gate", "Agmar's Hammer", "Wyrmrest Temple", "Westwind Refugee Camp", "Venomspite", "The Forgotten Shore", "The Crystal Vice", "Scarlet Point" } },
}
local exploration = read(ACH .. "AresAchievementExploration.lua")
for _, case in ipairs(EXPLORE) do
	local continent, zone, id, names = case[1], case[2], case[3], case[4]
	local function problems(text)
		local found, seen = {}, {}
		for line in text:gmatch("[^\n]+") do
			local index = line:match("achieve " .. id .. "/(%d+)")
			if index then
				index = tonumber(index)
				seen[index] = true
				if not names[index] then
					found[#found + 1] = "criterion " .. index .. " does not exist"
				elseif not line:find("Unlock " .. names[index] .. " |achieve", 1, true) then
					found[#found + 1] = "criterion " .. index .. " is not " .. names[index]
				end
			end
		end
		for index, name in ipairs(names) do
			if not seen[index] then found[#found + 1] = "no step unlocks " .. name end
		end
		return found
	end
	check("Explore " .. zone, problems, guide(exploration, "Ares' Achievement Guides\\\\Explore " .. continent .. "\\\\Explore " .. zone), function(text)
		return (text:gsub("achieve " .. id .. "/2|", "achieve " .. id .. "/" .. (#names + 1) .. "|", 1))
	end)
end

-- Brew of the Year (1183) lists the monthly brews in this order on 3.3.5a.
local BREWS = { "Wild Winter Pilsner", "Stranglethorn Brew", "Springtime Stout", "Metok's Bubble Bock", "Lord of Frost's Private Label",
	"Izzard's Ever Flavor", "Draenic Pale Ale", "Blackrock Lager", "Binary Brew", "Bartlett's Bitter Brew", "Autumnal Acorn Ale", "Aromatic Honey Brew" }
local function brewProblems(text)
	local found = {}
	for index, brew in ipairs(BREWS) do
		local plain = brew:gsub("%p", "%%%0")
		local criterion = text:match("use [^\n]-" .. plain .. "##%d+\nDrink [^\n]-|achieve 1183/(%d+)")
		if tonumber(criterion) ~= index then found[#found + 1] = brew .. " counts as criterion " .. tostring(criterion) end
		for waited in text:gmatch("collect " .. plain .. "##%d+ |or\n[^\n]*\n'|complete achieved%(1183,(%d+)%)") do
			if tonumber(waited) ~= index then found[#found + 1] = brew .. " waits on criterion " .. waited end
		end
	end
	return found
end
for _, faction in ipairs({ "Alliance", "Horde" }) do
	check(faction .. " Brew of the Year", brewProblems, read(root .. "/Guides/Retail/Events/ZygorEvents" .. faction .. "CLASSIC.lua"), function(text)
		return (text:gsub("achieve 1183/9\n", "achieve 1183/5\n", 1))
	end)
end

-- Corrected quest givers and takers from the 3.3.5a quest relations.
local STEPS = {
	{ "Retail/Dungeons/ZygorDungeonAllianceCLASSIC.lua", "Kurzel", 26664, "accept Head Games##13129" },
	{ "Retail/Dungeons/ZygorDungeonHordeCLASSIC.lua", "Kurzel", 26664, "accept Head Games##13129" },
	{ "Retail/Dungeons/ZygorDungeonAllianceCLASSIC.lua", "Ordinn Thunderfist", 19370, "turnin Illidari-Bane Shard##10621" },
	{ "Retail/Leveling/ZygorLevelingAllianceCLASSIC.lua", "Ordinn Thunderfist", 19370, "turnin Illidari-Bane Shard##10621" },
	{ "Retail/Events/ZygorEventsAllianceCLASSIC.lua", "Boxey Boltspinner", 27215, "turnin This One Time, When I Was Drunk...##12020" },
	{ "Retail/Events/ZygorEventsAllianceCLASSIC.lua", "Costumed Orphan Matron", 24519, "accept Stop the Fires!##11131" },
	{ "Retail/Reputations/ZygorReputationsHordeCLASSIC.lua", "Greatmother Geyah", 18141, "turnin There Is No Hope##10172" },
}
for _, case in ipairs(STEPS) do
	local file, npc, id, action = case[1], case[2], case[3], case[4]
	-- Every step that does it talks to that NPC.
	local function problems(text)
		local found, steps = {}, 0
		for step in (text:gsub("\nstep\n", "\nstep\nstep\n") .. "\nstep"):gmatch("\nstep\n(.-)\nstep") do
			if step:find("\n" .. action, 1, true) then
				steps = steps + 1
				if not step:find("talk " .. npc .. "##" .. id .. "\n", 1, true) then
					found[#found + 1] = action .. " at another NPC: " .. (step:match("talk ([^\n]+)") or "none")
				end
			end
		end
		if steps == 0 then found[#found + 1] = "no step does " .. action end
		return found
	end
	check(file .. " " .. npc, problems, read(root .. "/Guides/" .. file), function(text)
		return (text:gsub("talk " .. npc .. "##" .. id .. "\n", "talk " .. npc .. "##1" .. id .. "\n"))
	end)
end

-- Achievements that 3.3.5a does not have, and Cataclysm races in criteria steps.
local MISSING = { 4827, 4888, 4956, 4957, 4958, 4975 }
local function removedProblems(text)
	local found = {}
	for _, id in ipairs(MISSING) do
		if text:find("achieve " .. id .. "%f[^%d]") or text:find("achieved%(" .. id .. "%)") then found[#found + 1] = "achievement " .. id end
	end
	-- Darna Honeybock and the Brewfest Spy have no spawns, so neither Save Brewfest! nor the Insult
	-- Coren Direbrew quest that needs it can be taken; Coren's own gossip starts the fight.
	for _, id in ipairs({ 12318, 12062 }) do
		if text:find("##" .. id .. "%f[^%d]") then found[#found + 1] = "unobtainable quest " .. id end
	end
	if text:find("Worgen |achieve", 1, true) or text:find("Goblin |achieve", 1, true)
		or text:find("Worgen Rogue |achieve", 1, true) or text:find("Goblin Rogue |achieve", 1, true) then
		found[#found + 1] = "a Cataclysm race criterion"
	end
	return found
end
local files = loadedFiles()
assert(#files > 50, "only " .. #files .. " guide files are loaded")
local all = {}
for _, path in ipairs(files) do all[#all + 1] = read(path) end
check("loaded guides", removedProblems, table.concat(all, "\n"), function(text)
	return text .. "\n.' Visit the Sundering |achieve 4827/2\n"
end)
check("loaded guides", removedProblems, table.concat(all, "\n"), function(text)
	return text .. "\naccept Save Brewfest!##12318\n"
end)

print("PASS: achievement guides, exploration criteria, Brew of the Year, Brewfest and corrected quest steps follow 3.3.5a in " .. #files .. " guide files")
