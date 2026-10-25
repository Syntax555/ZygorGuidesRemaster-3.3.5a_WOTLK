-- Regression for progression changes invalidating an in-flight Gear Finder scan.
-- Usage: lua tools/gearfinder/test_progression_refresh.lua <addon directory>
local addon = assert(arg[1], "pass the addon directory")
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return (s:gsub("^\239\187\191", ""))
end
local function compile(source, name, env)
  if setfenv then local fn = assert(loadstring(source, name)); setfenv(fn, env); return fn end
  return assert(load(source, name, "t", env))
end
local function section(source, first, last)
  local startAt = assert(source:find(first, 1, true), first)
  return source:sub(startAt, assert(source:find(last, startAt + #first, true), last) - 1)
end

local env = setmetatable({}, {__index=_G})
local visible, cleared, started = true, 0, 0
local talentNotifications, frameNotifications, optionNotifications = 0, 0, 0
local finder = {MainFrame={IsVisible=function() return visible end}}
function finder:ClearResults()
  cleared = cleared + 1
  self.ResultsReady = false
  self.ScoreThread = nil
  self.IsScanning = false
end
function finder:ScoreDungeonItems()
  assert(not self.ScoreThread and not self.IsScanning,
    "old scan must be cancelled before replacement scoring starts")
  started = started + 1
  self.ScoreThread = coroutine.create(function() end)
  self.IsScanning = true
end
local ip = {guideChecks={}}
local score = {GearFinder=finder}
env.ZGV = {
  ItemScore=score,
  Frame={},
  TalentAdvisorProgressionChanged=function() talentNotifications = talentNotifications + 1 end,
  UpdateFrame=function(_, force)
    assert(force == true)
    frameNotifications = frameNotifications + 1
  end,
}
env.LibStub = function(library, silent)
  assert(library == "AceConfigRegistry-3.0" and silent == true)
  return {NotifyChange=function(_, app)
    assert(app == "ZygorGuidesViewer-Progress")
    optionNotifications = optionNotifications + 1
  end}
end
env.IP, env.GearFinder = ip, finder
compile(section(read(addon.."/IndividualProgression.lua"),
  "function IP:Changed()", "function IP:ApplyState(state)"), "IP:Changed", env)()
compile(section(read(addon.."/Item-GearFinder.lua"),
  "function GearFinder:RefreshAfterSourceSettingChange()", "local function GF_TraceBool"),
  "RefreshAfterSourceSettingChange", env)()

finder.ScoreThread = coroutine.create(function() end)
finder.IsScanning = true
local previousThread = finder.ScoreThread
ip:Changed()
assert(ip.guideChecks == nil, "progression change must still invalidate guide checks")
assert(cleared == 1 and started == 1 and finder.IsScanning and finder.ScoreThread ~= previousThread,
  "visible progression changes must replace the in-flight scan")

visible = false
ip:Changed()
assert(cleared == 2 and started == 1 and not finder.IsScanning and finder.ScoreThread == nil,
  "hidden progression changes must cancel stale scans without starting work")
finder.ResultsReady = true
ip:Changed()
assert(cleared == 3 and started == 1 and not finder.ResultsReady,
  "completed hidden results must be invalidated for the next open")

-- Progression bridge messages may arrive before Gear Finder has an initialized UI.
finder.MainFrame = nil
ip:Changed()
assert(cleared == 4 and started == 1, "an uninitialized window must not start scoring")
score.GearFinder = {ResultsReady=true}
ip:Changed()
assert(score.GearFinder.ResultsReady == nil,
  "early startup must retain the result invalidation fallback")
env.ZGV.ItemScore = nil
ip:Changed()
assert(talentNotifications == 6 and frameNotifications == 6 and optionNotifications == 6,
  "gear invalidation must preserve talent, frame, and option notifications")
print("PASS: progression changes replace active scans and invalidate hidden results")
