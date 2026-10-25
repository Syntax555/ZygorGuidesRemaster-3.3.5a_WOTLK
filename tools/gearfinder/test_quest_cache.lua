-- Regression for level-filtered quest sources avoiding repeated full DB scans.
-- Usage: lua tools/gearfinder/test_quest_cache.lua <addon directory>
local addon = assert(arg[1], "pass the addon directory")
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return (s:gsub("^\239\187\191", ""))
end
local function compile(source, name, env)
  if setfenv then local fn = assert(loadstring(source, name)); setfenv(fn, env); return fn end
  return assert(load(source, name, "t", env))
end

local env = setmetatable({}, {__index=_G})
local playerLevel, scans, rowsRead, scoreCalls = 20, 0, 0, 0
local rawData
local expectedSelf, expectedForce = nil, false
local marker = {}
local finder = {}
expectedSelf = finder
function finder:ScoreDungeonItems(force, extra)
  assert(self == expectedSelf and force == expectedForce and extra == marker,
    "wrapper must forward its receiver and all arguments")
  scoreCalls = scoreCalls + 1
  return marker, nil, force, scoreCalls
end
local baseSource = {dungeon="original", {ALL={1}}}
local itemScore = {GearFinder=finder, Items={baseSource}}
env.ZygorGuidesViewer = {ItemScore=itemScore, startups={}}
env.tinsert = table.insert
env.UnitLevel = function() return playerLevel end
-- Count reads of the actual local QuestRawData, without replacing its contents.
env.ipairs = function(values)
  rawData = values
  scans = scans + 1
  local iterator, state, initial = ipairs(values)
  return function(sequence, index)
    local key, value = iterator(sequence, index)
    if key then rowsRead = rowsRead + 1 end
    return key, value
  end, state, initial
end
compile(read(addon.."/ZygorQuestLootDB.lua"), "QuestLootDB", env)()
assert(#env.ZygorGuidesViewer.startups == 1)
env.ZygorGuidesViewer.startups[1][2]()

local function score(force)
  expectedForce = force
  local a, b, c, d = finder:ScoreDungeonItems(force, marker)
  assert(a == marker and b == nil and c == force and d == scoreCalls,
    "wrapper must preserve all results, including nil values")
end
local function questBlock()
  local result
  for _, source in ipairs(itemScore.Items) do
    if source.dungeon == "quests" then
      assert(not result, "there must be only one dynamic quest source")
      result = source
    end
  end
  return result
end
local function assertLevelBand(block)
  local count = 0
  for _, row in ipairs(rawData) do
    if row[1] >= math.max(1, playerLevel - 5) and row[1] <= playerLevel + 2 then
      count = count + 1
      local quest = assert(block[count], "every quest in the level band must be preserved")
      assert(quest.name == row[4] and quest.quest == row[2] and quest.ALL == row[3],
        "cached source must preserve the original quest and reward data")
    end
  end
  assert(count == #block, "source must contain only quests in the current level band")
end

score(false)
assert(scans == 1 and rowsRead > 2000, "first scan must filter the real quest database")
local firstRowsRead = rowsRead
local firstBlock = assert(questBlock())
assertLevelBand(firstBlock)
assert(#firstBlock > 0 and itemScore.Items[1] == baseSource,
  "quest source must be appended without changing existing loot")
assert(firstBlock.dungeonmap == "quests" and firstBlock.instanceId == "quests")
local firstQuest = firstBlock[1]
assert(firstQuest.name and firstQuest.quest and firstQuest.ALL and firstQuest.boss == 0)
score(true)
assert(scans == 1 and rowsRead == firstRowsRead and questBlock() == firstBlock,
  "same-level rescans must reuse the existing quest source")

finder.ResultsReady = true
playerLevel = 80
score(false)
assert(scans == 1 and questBlock() == firstBlock,
  "cached results must return without rebuilding quest sources")
finder.ResultsReady = nil
finder.IsScanning = true
score(true)
assert(scans == 1 and questBlock() == firstBlock,
  "an in-flight scan must keep its source tables unchanged")
finder.IsScanning = nil
score(false)
local highBlock = assert(questBlock())
assertLevelBand(highBlock)
assert(scans == 2 and rowsRead == firstRowsRead * 2 and highBlock ~= firstBlock,
  "level changes must rebuild the quest source")
assert(highBlock[1].quest[1] == 1, "level-80 source must include its level-80 quest rewards")
score(false)
assert(scans == 2 and questBlock() == highBlock, "unchanged level must remain cached")

-- Existing sources from a replaced table must be removed before adding one.
itemScore.Items = {baseSource, firstBlock, highBlock}
score(false)
assert(scans == 3 and questBlock() ~= highBlock and #itemScore.Items == 2,
  "replaced source tables must be rebuilt without duplicate quest blocks")
local replacedBlock = questBlock()
score(false)
assert(scans == 3 and questBlock() == replacedBlock)

-- Empty level bands must also be cached, without leaving obsolete quests.
playerLevel = 200
score(false)
assert(scans == 4 and not questBlock() and #itemScore.Items == 1)
score(false)
assert(scans == 4, "empty level bands must not trigger repeated database scans")
assert(scoreCalls == 10, "every wrapper call must still reach the original scorer")
print("PASS: quest sources reuse unchanged data and refresh on level/source changes")
