-- The leveling guides follow the 3.3.5a quest data of Magisters' Terrace and Sporeggar.
-- Usage: lua tools/guides/test_quel_danas_335.lua <addon directory>
local root = arg[1] or "ZygorGuidesViewerRM"

local function read(path)
	local f = assert(io.open(path, "rb"), "missing " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

local function guide(source, title)
	local first = assert(source:find('RegisterGuide("' .. title .. '"', 1, true), "missing guide " .. title)
	local last = source:find("\n]])", first, true)
	return source:sub(first, last)
end

-- Starters and enders from the pinned world database: Tyrith (24822) takes
-- Magisters' Terrace (11488) and gives The Scryer's Scryer (11490); Kalecgos
-- (24848) gives Hard to Kill (11492); Exarch Larethor (24813) at Sun's Reach takes it.
local function problems(text)
	local found = {}
	local function need(pattern, label)
		if not text:find(pattern) then found[#found + 1] = label end
	end
	need("talk Tyrith##24822\n[^\n]*\n[^\n]*\nturnin Magisters' Terrace##11488\naccept The Scryer's Scryer##11490\n",
		"Tyrith takes Magisters' Terrace and gives The Scryer's Scryer")
	need("talk Kalecgos##24848\n.-turnin The Scryer's Scryer##11490\naccept Hard to Kill##11492\n", "Kalecgos gives quest 11492")
	need("collect Head of Kael'thas##34157 |q 11492/1\n", "Kael'thas' head counts for quest 11492")
	need("talk Exarch Larethor##24813\n[^\n]*\nturnin Hard to Kill##11492 |goto Isle of Quel'Danas/0 47.37,30.67\n",
		"Larethor at Sun's Reach takes quest 11492")
	if text:find("29685", 1, true) or text:find("55007", 1, true) then
		found[#found + 1] = "a Wrath Classic quest or NPC remains"
	end
	return found
end

for _, faction in ipairs({ "Alliance", "Horde" }) do
	local source = read(root .. "/Guides/Retail/Leveling/ZygorLeveling" .. faction .. "CLASSIC.lua")
	local text = guide(source, "Leveling Guides\\\\The Burning Crusade (58-70)\\\\Isle of Quel'danas")
	local broken = problems(text)
	assert(#broken == 0, faction .. ": " .. table.concat(broken, "; "))
	local mutant = text:gsub("accept Hard to Kill##11492", "accept Hard to Kill##29685", 1)
	assert(#problems(mutant) > 0, faction .. ": the Wrath Classic quest was accepted")
	if faction == "Alliance" then
		local zangarmarsh = guide(source, "Leveling Guides\\\\The Burning Crusade (58-70)\\\\Zangarmarsh (62-63)")
		-- Quest 50131 does not exist on 3.3.5a; the reputation itself completes the step.
		assert(zangarmarsh:find("Reach Neutral Reputation with the Sporeggar |complete (rep('Sporeggar') >= Neutral)", 1, true),
			"the Sporeggar step does not check the reputation")
		assert(not zangarmarsh:find("50131", 1, true), "the Sporeggar step waits on a missing quest")
	end
end
print("PASS: Magisters' Terrace and Sporeggar follow the 3.3.5a quest data for both factions")
