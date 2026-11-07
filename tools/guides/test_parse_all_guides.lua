-- Every guide the TOC loads parses with the production parser for both factions, with its
-- includes and leeched guides resolved and no Cataclysm-only zone or quest in its steps.
-- Usage: lua tools/guides/test_parse_all_guides.lua <addon directory>
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

tinsert = table.insert
function TableKeys(tbl)
	local keys = {}
	for key in pairs(tbl or {}) do keys[#keys + 1] = key end
	return keys
end
function ZygorGuidesViewer_L()
	return setmetatable({ coords = "%s,%s" }, { __index = function(_, key) return key end })
end
GetRealZoneText = function() return "Test Zone" end

-- The tables ZygorGuidesViewer.lua creates before guides load.
local function newViewer()
	ZygorGuidesViewer = { BZL = {}, BSZL = {}, BFL = {}, StandingNamesEngRev = {}, dailyQuests = {}, instantQuests = {},
		registeredguides = {}, registered_includes = {}, StepProto_mt = {}, GoalProto_mt = {} }
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
	assert(loadfile(root .. "/Parser.lua"))()
	return ZGV
end

-- Loads the guide files as one faction's client does and registers their guides and includes.
local function register(ZGV, faction, files)
	local any
	any = setmetatable({}, { __index = function() return any end, __call = function() return any end,
		__newindex = function() end, __concat = function() return "" end })
	local viewer = setmetatable({ IMAGESDIR = "", DIR = "" }, { __index = function() return any end })
	function viewer:RegisterGuide(title, data, extra)
		ZGV.registeredguides[#ZGV.registeredguides + 1] = {
			title = title:gsub("\\\\", "\\"), rawdata = type(data) == "table" and (extra or "") or data }
	end
	function viewer:RegisterInclude(name, data) ZGV.registered_includes[name] = data end
	local mutexes = {}
	function viewer:DoMutex(name)
		if mutexes[name] then return true end
		mutexes[name] = true
		return false
	end
	local env = setmetatable({ ZygorGuidesViewer = viewer, ZGV = viewer,
		UnitFactionGroup = function() return faction end, UnitRace = function() return "Human", "Human" end,
		UnitClass = function() return "Warrior", "WARRIOR" end, UnitLevel = function() return 1 end,
		GetLocale = function() return "enUS" end }, { __index = _G })
	for _, path in ipairs(files) do
		local chunk = assert(loadstring(read(path), path))
		setfenv(chunk, env)
		pcall(chunk)
	end
end

-- Zones that only Cataclysm maps have, and the quest IDs that start after the last 3.3.5a quest
-- (26034) and below the server's custom quests (60000 and above).
local CATACLYSM_ZONES = { ["Northern Stranglethorn"] = true, ["The Cape of Stranglethorn"] = true, ["Northern Barrens"] = true,
	["Southern Barrens"] = true, ["Mount Hyjal"] = true, Deepholm = true, Uldum = true, ["Twilight Highlands"] = true,
	["Vashj'ir"] = true, ["Kelp'thar Forest"] = true, ["Shimmering Expanse"] = true, ["Abyssal Depths"] = true,
	["Darkmoon Island"] = true, ["Molten Front"] = true, ["Tol Barad"] = true, ["Tol Barad Peninsula"] = true,
	["Ruins of Gilneas"] = true, Gilneas = true, Kezan = true, ["The Lost Isles"] = true }

local function laterContent(title, parsed, found)
	for _, step in ipairs(parsed.steps or {}) do
		for _, goal in ipairs(step.goals or {}) do
			local map = type(goal.map) == "string" and goal.map:gsub("/%d+$", "") or nil
			if map and CATACLYSM_ZONES[map] then found[#found + 1] = title .. ": Cataclysm zone " .. map end
			if goal.questid and goal.questid > 26034 and goal.questid < 60000 then
				found[#found + 1] = title .. ": quest " .. goal.questid .. " is not on 3.3.5a"
			end
		end
	end
end

local function failures(ZGV)
	local found = {}
	for _, guide in ipairs(ZGV.registeredguides) do
		local ok, parsed, err = pcall(ZGV.ParseEntry, ZGV, guide.rawdata)
		if not ok or not parsed then found[#found + 1] = guide.title .. ": " .. tostring(ok and err or parsed)
		else laterContent(guide.title, parsed, found) end
		-- The parser reads an include name only in quotes; anything else stays a text line.
		local bare = ("\n" .. guide.rawdata):match("\n%s*(#include%s+[^\"'%s][^\n]*)")
		if bare then found[#found + 1] = guide.title .. ": unquoted " .. bare end
	end
	return found
end

local files = loadedFiles()
assert(#files > 50, "only " .. #files .. " guide files are loaded")
for _, faction in ipairs({ "Alliance", "Horde" }) do
	local ZGV = newViewer()
	register(ZGV, faction, files)
	local count = #ZGV.registeredguides
	assert(count > 1000, faction .. ": only " .. count .. " guides registered")
	local broken = failures(ZGV)
	assert(#broken == 0, faction .. ": " .. #broken .. " problems:\n" .. table.concat(broken, "\n"))
	-- A missing include and a goal before the first step must be reported.
	local include = ZGV.registeredguides[1]
	for _, guide in ipairs(ZGV.registeredguides) do
		if guide.rawdata:find('#include "', 1, true) then include = guide break end
	end
	local saved = include.rawdata
	include.rawdata = saved:gsub('#include "([^"]+)"', '#include "%1 missing"', 1)
	assert(not ZGV:ParseEntry(include.rawdata), faction .. ": a missing include was not reported")
	include.rawdata = saved:gsub('#include "([^"]+)"', "#include %1", 1)
	assert(#failures(ZGV) == 1, faction .. ": an unquoted include was not reported")
	include.rawdata = saved .. "\nstep\ngoto Northern Barrens,49.9,54.4\n.talk Flame Warden##51573\n..accept Honor the Flame##28926\n"
	assert(#failures(ZGV) == 2, faction .. ": a Cataclysm zone and quest were not reported")
	include.rawdata = saved
	assert(not pcall(ZGV.ParseEntry, ZGV, "Run into the portal |goto Netherstorm/0 70.66,69.84\nstep\nClick Here to Continue |confirm\n"),
		faction .. ": a goal before the first step was accepted")
	print(("PASS: %d %s guides parse without Cataclysm zones or quests"):format(count, faction))
end
