-- Hemet Nesingwary: The Collected Quests takes its Stranglethorn steps from
-- The Green Hills of Stranglethorn; the production parser must resolve both.
-- Usage: lua tools/guides/test_hemet_leech.lua <addon directory>
local root = arg[1] or "ZygorGuidesViewerRM"

tinsert = table.insert
function TableKeys(tbl)
	local keys = {}
	for key in pairs(tbl or {}) do keys[#keys + 1] = key end
	return keys
end
function ZygorGuidesViewer_L()
	return setmetatable({ coords = "%s,%s" }, { __index = function(_, key) return key end })
end
ZygorGuidesViewer = { BZL = {}, BSZL = {}, BFL = {}, StandingNamesEngRev = {}, dailyQuests = {}, registeredguides = {}, StepProto_mt = {}, GoalProto_mt = {} }
local ZGV = ZygorGuidesViewer
function ZGV:GetQuestName() return nil end
function ZGV:RaceClassMatch() return true end
function ZGV:GetGuideByTitle(title)
	for _, guide in ipairs(self.registeredguides) do
		if guide.title == title then return guide end
	end
end
function ZGV:EnsureGuideParsed(guide)
	if guide.parsed then return guide, true end
	if guide._parsing then return guide, false end
	guide._parsing = true
	local parsed = self:ParseEntry(guide.rawdata)
	guide._parsing = nil
	if not parsed then return guide, false end
	for key, value in pairs(parsed) do guide[key] = value end
	guide.parsed = true
	return guide, true
end
GetRealZoneText = function() return "Test Zone" end
assert(loadfile(root .. "/Parser.lua"))()

local function read(path)
	local f = assert(io.open(path, "rb"), "missing " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

local function body(source, title)
	local head = 'RegisterGuide("' .. title .. '",[['
	local first = assert(source:find(head, 1, true), "missing guide " .. title)
	local last = assert(source:find("\n]])", first, true))
	return source:sub(first + #head, last)
end

-- Steps of the 941 guide, or the parser's error.
local function collected(source, faction, hills, mutate)
	ZGV.registeredguides = {}
	local prefix = "Zygor's " .. faction .. " Achievements Guides\\\\Quest Achievements\\\\"
	local raw941 = body(source, prefix .. "Hemet Nesingwary: The Collected Quests")
	ZGV.registeredguides[1] = { title = (prefix .. hills):gsub("\\\\", "\\"), rawdata = body(source, prefix .. hills) }
	return ZGV:ParseEntry(mutate and mutate(raw941) or raw941)
end

for _, case in ipairs({ { "Alliance", "The Green Hills of Stranglethorn" }, { "Horde", "The Green Hills Of Stranglethorn" } }) do
	local faction, hills = case[1], case[2]
	local source = read(root .. "/Guides/Achievements/ZygorAchievements" .. faction .. ".lua")
	local guide, err = collected(source, faction, hills)
	assert(guide, faction .. ": " .. tostring(err))
	for _, label in ipairs({ "TheGreenHills", "WhiteElekks", "Snows", "end" }) do
		assert(guide.labels and guide.labels[label], faction .. ": label " .. label .. " is missing")
	end
	-- The leeched steps follow the label step: Barnil's first quest, then the
	-- earned 940 achievement before the Nagrand redirect.
	local function accepts(step, quest)
		for _, goal in ipairs(step and step.goals or {}) do
			if goal.action == "accept" and goal.questid == quest then return true end
		end
	end
	assert(accepts(guide.steps[guide.labels.TheGreenHills + 1], 583), faction .. ": the leeched steps do not start with Welcome to the Jungle")
	local earned = guide.steps[guide.labels.WhiteElekks - 2]
	assert(earned and earned.goals[1].achieveid == 940, faction .. ": the leeched steps do not end with the 940 achievement")
	assert(guide.quests[208] and guide.quests[338], faction .. ": quests 208 and 338 are not indexed")
	local broken = collected(source, faction, hills, function(raw)
		return (raw:gsub("Quest Achievements\\\\The Green Hills", "Quest Achievements\\\\Green Hills", 1))
	end)
	assert(not broken, faction .. ": a missing leech source was not reported")
end
print("PASS: Hemet Nesingwary: The Collected Quests leeches The Green Hills of Stranglethorn for both factions")
