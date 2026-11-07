-- The guide browser's era tabs, run on every guide file the TOC loads.
-- Usage: lua tools/guides/test_guide_eras.lua <addon directory>
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

-- Production IndividualProgression.lua against a minimal viewer.
local function newIP(source)
	tinsert, SlashCmdList = table.insert, {}
	ZygorGuidesViewer = { L = {}, startups = {}, RegisterGuide = function() end }
	local chunk = assert(loadstring(source, "IndividualProgression.lua"))
	chunk()
	return ZygorGuidesViewer.IP
end

-- Registers the guides of every loaded guide file for one faction, as RegisterGuide stores them.
local function registerGuides(faction, files, guides)
	-- Anything else a guide file touches while loading is an inert stand-in.
	local any
	any = setmetatable({}, { __index = function() return any end, __call = function() return any end,
		__newindex = function() end, __concat = function() return "" end })
	local viewer = setmetatable({ IMAGESDIR = "", DIR = "" }, { __index = function() return any end })
	function viewer:RegisterGuide(title, data, extra)
		local guide = { title = title, faction = faction }
		if type(data) == "table" then
			guide.headerdata, guide.rawdata = data, extra or ""
		else
			guide.rawdata = data
		end
		guides[#guides + 1] = guide
	end
	local env = setmetatable({
		ZygorGuidesViewer = viewer,
		ZGV = viewer,
		UnitFactionGroup = function() return faction end,
		UnitRace = function() return "Human", "Human" end,
		UnitClass = function() return "Warrior", "WARRIOR" end,
		UnitLevel = function() return 1 end,
		GetLocale = function() return "enUS" end,
	}, { __index = _G })
	for _, path in ipairs(files) do
		local chunk = loadstring(read(path), path)
		if chunk then
			setfenv(chunk, env)
			pcall(chunk)
		end
	end
end

local guides = {}
local files = loadedFiles()
assert(#files > 40, "guide files were not found")
registerGuides("Alliance", files, guides)
registerGuides("Horde", files, guides)
assert(#guides > 2000, "guides were not registered: " .. #guides)

local source = read(root .. "/IndividualProgression.lua")

-- Groups of guides and the era each must belong to; nil belongs to every era.
local EXPECTED = {
	{ "^Leveling Guides\\Classic %(12%-58%)\\", 0 },
	{ "^Leveling Guides\\The Burning Crusade %(58%-70%)\\", 1 },
	{ "^Leveling Guides\\Northrend %(69%-80%)\\", 2 },
	{ "^Dungeon Guides\\Classic\\", 0 },
	{ "^Dungeon Guides\\The Burning Crusade\\", 1 },
	{ "^Dungeon Guides\\Wrath of the Lich King\\", 2 },
	{ "^Leveling Guides\\Starter Guides %(1%-11%)\\Human Starter", 0 },
	{ "^Leveling Guides\\Starter Guides %(1%-11%)\\Draenei Starter", 1 },
	{ "^Leveling Guides\\Starter Guides %(1%-12%)\\Eversong Woods", 1 },
	{ "Death Knight Starter", 2 },
	{ "^Leveling Guides\\Darkshore %(11%-14%)$", 0 },
	{ "^Leveling Guides\\Ahn'Qiraj Gear\\", 0 },
	{ "^Ding80's Alliance Leveling Guides\\Borean Tundra$", 2 },
	{ "^Profession Guides\\Cooking\\Cooking %(1%-375%)$", 0 },
}

local function problems(ip)
	local found, matched = {}, {}
	for _, guide in ipairs(guides) do
		guide._ipEra = nil
		local era = ip:GuideEra(guide)
		for i, rule in ipairs(EXPECTED) do
			if guide.title:find(rule[1]) then
				matched[i] = (matched[i] or 0) + 1
				if era ~= rule[2] then
					found[#found + 1] = ("%s is era %s, expected %s"):format(guide.title, tostring(era), tostring(rule[2]))
				end
			end
		end
		if not ip:GuideInEra(guide, era) or (era ~= nil and ip:GuideInEra(guide, (era + 1) % 3)) then
			found[#found + 1] = guide.title .. " is not listed in exactly its own tab"
		end
	end
	for i, rule in ipairs(EXPECTED) do
		if not matched[i] then found[#found + 1] = "no guide matches " .. rule[1] end
	end
	-- Instances decide the era of a guide whose title names none.
	for text, era in pairs({ ["goto Karazhan,50,50"] = 1, ["goto Utgarde Keep,50,50"] = 2, ["goto Molten Core,50,50"] = 0 }) do
		if ip:GuideEra({ title = "Raid notes", rawdata = text }) ~= era then
			found[#found + 1] = text .. " is not era " .. era
		end
	end
	return found
end

local ip = newIP(source)
local broken = problems(ip)
if #broken > 0 then error(table.concat(broken, "\n"), 0) end

assert(ip:GuideEra({ title = "Notes", rawdata = "step\nRead the tips" }) == nil, "a guide without places is not in every era")

-- Zones written before space-separated coordinates also decide the tier gates.
local spaced = { title = "x", rawdata = "step\ngoto Shadowmoon Valley 50.2,40.1\n" }
assert(ip:GuideRequirement(spaced).tier == 8, "a zone before space-separated coordinates is ignored")

local counts = { [0] = 0, 0, 0 }
local shared = 0
for _, guide in ipairs(guides) do
	local era = ip:GuideEra(guide)
	if era then counts[era] = counts[era] + 1 else shared = shared + 1 end
end

local mutations = {
	{ "coordinates kept in zone names", 'text = string.gsub(text, "%s+[%d%.]+$", "")\n', "" },
	{ "TBC race zones follow the player's race", "self.TBC_RACE_ZONES[name] and 8", "nil" },
	{ "title words ignored", "if string.find(title, word, 1, true) then", "if false then" },
	{ "the latest place visited wins", "visits[candidate] >= visits[era]", "true" },
	{ "instances ignored", "if map then zoneEra", "if false then zoneEra" },
	{ "every guide in every tab", "return era == nil or guideEra == nil or guideEra == era", "return true" },
}
for _, mutation in ipairs(mutations) do
	local label, old, new = mutation[1], mutation[2], mutation[3]
	local first = source:find(old, 1, true)
	assert(first, label .. " mutation was not applied")
	local mutant = source:sub(1, first - 1) .. new .. source:sub(first + #old)
	local mutantIP = newIP(mutant)
	local rejected = #problems(mutantIP) > 0
	if not rejected and label:find("coordinates", 1, true) then
		rejected = mutantIP:GuideRequirement({ title = "x", rawdata = spaced.rawdata }).tier ~= 8
	end
	assert(rejected, "the era check accepted: " .. label)
	print("PASS: rejected " .. label)
end

print(("PASS: %d guides: %d Vanilla, %d TBC, %d Wrath, %d in every era"):format(#guides, counts[0], counts[1], counts[2], shared))
