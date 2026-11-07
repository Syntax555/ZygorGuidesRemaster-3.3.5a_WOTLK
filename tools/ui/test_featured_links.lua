-- Every guide a Featured page links must be registered for the faction that sees it.
-- Usage: lua tools/ui/test_featured_links.lua <addon directory>
local root = arg[1] or "ZygorGuidesViewerRM"

local function read(path)
	local f = assert(io.open(path, "rb"), "missing " .. path)
	local s = f:read("*a")
	f:close()
	return (s:gsub("^\239\187\191", ""))
end

local function unescape(text)
	return (text:gsub("\\\\", "\\"))
end

-- Lua files in the order the client loads them: the TOC, then each XML include.
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
				local f = io.open(child, "rb")
				if f then
					f:close()
					visit(child)
				end
			end
		end
	end
	for line in read(root .. "/" .. root:match("[^/]+$") .. ".toc"):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") then
			local path = root .. "/" .. line:gsub("\\", "/")
			local f = io.open(path, "rb")
			if f then
				f:close()
				visit(path)
			end
		end
	end
	return files
end

-- title -> {A=true, H=true}: the factions whose clients register the guide.
local registered = {}
for _, path in ipairs(loadedFiles()) do
	local source = read(path)
	local head = source:sub(1, 600)
	local factions = { A = true, H = true }
	if head:find('UnitFactionGroup%("player"%)%s*~=%s*"Alliance"') then factions = { A = true } end
	if head:find('UnitFactionGroup%("player"%)%s*~=%s*"Horde"') then factions = { H = true } end
	for line in source:gmatch("[^\n]+") do
		local title = line:match('^%s*ZygorGuidesViewer:RegisterGuide%(%s*"(.-[^\\])"')
			or line:match('^%s*ZGV:RegisterGuide%(%s*"(.-[^\\])"')
		if title then
			title = unescape(title)
			registered[title] = registered[title] or {}
			for faction in pairs(factions) do registered[title][faction] = true end
		end
	end
end

local browser = read(root .. "/GuideBrowser.lua")
local first = assert(browser:find("local WhatsNewData = {}", 1, true))
local last = assert(browser:find("local function wn_colourise", first, true))
local featured = browser:sub(first, last - 1)

local function problems(text)
	local found = {}
	for item in text:gmatch('{"item",[^\n]-}') do
		local title = item:match('guide="([^"]+)"')
		if title then
			title = unescape(title)
			local faction = item:match('faction="([AH])"')
			local factions = registered[title]
			for _, side in ipairs(faction and { faction } or { "A", "H" }) do
				if not (factions and factions[side]) then
					found[#found + 1] = side .. " " .. title
				end
			end
		end
	end
	return found
end

local links = 0
for _ in featured:gmatch('guide="') do links = links + 1 end
assert(links > 100, "featured pages were not found")
local broken = problems(featured)
if #broken > 0 then
	error("featured links without a registered guide:\n  " .. table.concat(broken, "\n  "))
end

-- The check rejects the folder names of the retail menus these pages came from.
local stale = featured:gsub('guide="Leveling Guides\\\\Starter', 'guide="LEVELING\\\\Starter', 1)
assert(stale ~= featured and #problems(stale) > 0, "a link to an unregistered title was accepted")

print(("PASS: %d featured guide links resolve for their factions"):format(links))
