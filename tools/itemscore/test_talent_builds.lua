-- Gear Advisor Druid profiles use native talent identity/ranks and historical data.
-- Usage: lua tools/itemscore/test_talent_builds.lua <addon directory>
local addon = assert(arg[1], "addon directory required")
local function read(path)
  local file = assert(io.open(addon .. "/" .. path, "rb"))
  local text = file:read("*a")
  file:close()
  return (text:gsub("^\239\187\191", ""))
end
local function section(text, first, last)
  local start = assert(text:find(first, 1, true))
  return text:sub(start, assert(text:find(last, start + 1, true)) - 1)
end
local env = setmetatable({}, {__index = _G})
env._G = env
local function run(text)
  local chunk = assert(loadstring(text))
  setfenv(chunk, env)
  return chunk()
end
local score = {}
local ip = {}
env.ItemScore, env.ZGV, env.IP = score, {ItemScore = score, IP = ip}, ip
run(read("Data-WOTLK/Item-Statweights.lua"))
function score:IsKnownWeightClass(class) return self.rules[class] ~= nil end
local pointTab, pointCount, thickHideRank = 2, 7, 0
env.GetNumTalentTabs = function() return 3 end
env.GetTalentTabInfo = function(tab) return "Tree", "icon", tab == pointTab and pointCount or 0 end
env.GetActiveTalentGroup = function() return 1 end
env.UnitCharacterPoints = function() return 0 end
env.GetNumTalents = function() return 30 end
env.GetTalentLink = function(_, index)
  return "|Htalent:" .. (index == 7 and 794 or index == 11 and 801 or (1000 + index)) .. ":0|h"
end
env.GetTalentInfo = function(_, index, inspect, pet, group)
  assert(not inspect and not pet and group == 1)
  return "Localized talent", "icon", 2, 3, index == 7 and thickHideRank or (index == 11 and 2 or 0), 3
end
run(section(read("Item-ItemScore.lua"), "ItemScore.LevelingBuildFallback = {", "function ItemScore:GetGearRoleBuild"))
local registration = section(read("ZygorTalentAdvisor/Registering.lua"), '["DRUID"]={', '["MAGE"] = {')
assert(registration:find('["Thick Hide"]=794,', 1, true), "native talent identity changed")
ip.EraTalentPoints = function() end
ip.NativeTalentsHistorical = function() return false end
local function detected() return score:DetectActiveBuild("DRUID", 60) end
assert(detected() == 2, "native talent tier or Primal Fury rank selected tank weights")
thickHideRank = 2
assert(detected() == 3, "native Thick Hide rank did not select tank weights")
pointTab = 3
assert(detected() == 4, "Restoration selected the Feral tank profile")
pointCount = 0
env.GetPrimaryTalentTree = function() return 3 end
assert(detected() == 4, "primary-tree fallback lost Restoration")
env.GetPrimaryTalentTree = nil

-- Historical metadata names stay canonical; localization is a separate table.
local tree = {className = "DRUID", talents = {
  {id = 901, tab = 2, name = "Thick Hide", localized = {deDE = {name = "Dickes Fell"}}},
  {id = 902, tab = 2, name = "Ferocity"},
  {id = 903, tab = 3, name = "Improved Mark of the Wild"},
}}
env.EraTalentsData = {[0] = {[11] = tree}}
env.EraTalents = {state = {isEraChar = true, era = 0, ranks = {[901] = 2, [902] = 5}, availPts = 3}}
env.EraTalents.SpecPoints = function(data, ranks)
  local points = {0, 0, 0}
  for _, node in ipairs(data.talents) do points[node.tab] = points[node.tab] + (ranks[node.id] or 0) end
  return points
end
run(section(read("IndividualProgression.lua"), "function IP:EraTalentPoints", "-- Before its earned Wrath era"))
assert(detected() == 3, "historical Thick Hide did not select tank weights")
env.EraTalents.state.ranks = {[902] = 7}
assert(detected() == 2, "historical Feral without Thick Hide selected tank weights")
env.EraTalents.state.ranks = {[903] = 3}
assert(detected() == 4, "historical Restoration selected tank weights")

local refreshes, callback = 0
score.Initialised, score.playerclass = true, "DRUID"
score.DelayedRefreshUserData = function() refreshes = refreshes + 1 end
env.EraTalents.Refresh = function() end
env.hooksecurefunc = function(_, name, fn) assert(name == "Refresh"); callback = fn end
run(section(read("IndividualProgression.lua"), "function IP:WatchEraTalents", "------------------------------------------------------------------------\n-- Display"))
ip:WatchEraTalents()
env.EraTalents.state.ranks = {[901] = 2, [902] = 5}
callback()
env.EraTalents.state.ranks = {[902] = 7}
callback()
assert(refreshes == 2, "same tab totals hid a historical Feral role change")
callback()
assert(refreshes == 2, "unchanged talent data restarted the gear scan")
print("PASS: native/historical Druid gear profiles and event-driven role refresh")
