-- Run the native Finder coroutine and scorer with a captured inspected bot.
-- Usage: lua5.1 tools/gearfinder/test_target_sources.lua <addon directory>
local addon = assert(arg[1], "pass the addon directory")
local function read(path)
  local file = assert(io.open(addon .. "/" .. path, "rb"))
  local text = file:read("*a"); file:close()
  return (text:gsub("^\239\187\191", ""))
end
local function copy(values)
  local out = {}; for key, value in pairs(values) do out[key] = value end; return out
end
local function exercise(finderSource)
  local env = setmetatable({}, {__index = _G}); env._G = env
  local function run(source, name)
    local chunk = assert(loadstring(source, name)); setfenv(chunk, env); return chunk()
  end
  local function load(path) return run(read(path), path) end
  local function noop() end
  local elapsed, clock, work, visible = 1000, 0, 0, true
  local function frame()
    return {Show=noop, Hide=noop, SetText=noop, SetTexture=noop, SetPercent=noop,
      IsVisible=function() return true end}
  end
  env.table = copy(table)
  env.wipe = function(values) for key in pairs(values) do values[key] = nil end end
  env.table.wipe, env.tinsert, env.tremove = env.wipe, table.insert, table.remove
  for index, slot in ipairs({"HEAD", "NECK", "SHOULDER", "BODY", "CHEST", "WAIST", "LEGS", "FEET", "WRIST", "HAND", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2", "BACK", "MAINHAND", "OFFHAND", "RANGED", "TABARD"}) do
    env["INVSLOT_" .. slot] = index
  end
  env.LE_ITEM_CLASS_ARMOR, env.LE_ITEM_CLASS_WEAPON = 4, 2
  env.GetLocale = function() return "enUS" end
  env.GetTime, env.debugprofilestop = function() return elapsed end, function() return clock end
  env.GetMaxPlayerLevel = function() return 80 end
  env.LibStub = function(name) if name == "AceHook-3.0" then return {Embed=noop} end end
  env.SlashCmdList = {}
  env.UnitName = function(unit) return unit == "party1" and "Bot" or "Owner" end
  env.UnitGUID = function(unit) return unit == "party1" and "0xBot" or "0xOwner" end
  env.UnitClass = function(unit) if unit == "party1" then return "Warrior", "WARRIOR" end return "Mage", "MAGE" end
  env.UnitRace = function() return "Human", "Human" end
  env.UnitFactionGroup = function(unit) return unit == "party1" and "Alliance" or "Horde" end
  env.UnitLevel = function(unit) return unit == "party1" and 20 or 80 end
  env.GetInventoryItemLink = function(_, slot) if slot == 9 then return "item:100" end end
  env.UnitExists, env.CanInspect = function() return true end, function() return true end
  env.UnitIsUnit = function(a, b) return a == b end
  env.GetQuestsCompleted = function(values) values[1] = true end
  local timers, messages = {}, {}
  local zgv = {DIR="Interface\\AddOns\\ZygorGuidesViewerRM", L=setmetatable({}, {__index=function(_, key) return key end}), startups={},
    db={profile={gear_1=true, gear_2=true, gear_3=true, gear_4=true}, char={gear_active_build=1}},
    IsClassicWOTLK=true, ItemLink={GetItemID=function(link) return tonumber(tostring(link):match("item:(%d+)")) end}}
  env.ZygorGuidesViewer, env.ZGV = zgv, zgv
  zgv.Debug, zgv.RegisterGuide, zgv.GetQuestName = noop, noop, noop
  function zgv:ScheduleTimer(callback, delay) timers[#timers+1] = {callback=callback, at=elapsed+delay} end
  function zgv:ScheduleRepeatingTimer(callback) return {callback=callback} end
  function zgv:CancelTimer(timer) timer.closed = true end
  env.SendAddonMessage = function(_, message) messages[#messages+1] = message end
  env.CreateFrame = function()
    local object = {scripts={}}
    function object:SetScript(event, callback) self.scripts[event] = callback end
    function object:Show() self.shown = true end
    function object:Hide() self.shown = false end
    return object
  end
  load("Code-WOTLK/Item-DataTables.lua")
  load("Data-WOTLK/Item-Statweights.lua")
  load("Item-ItemScore.lua")
  zgv.ClassToNumber = {}
  local classIndex = 0
  for class in pairs(zgv.ItemScore.rules) do classIndex=classIndex+1; zgv.ClassToNumber[class]=classIndex end
  load("Code-WOTLK/Item-ItemScore.lua")
  load("IndividualProgression.lua")
  run(finderSource, "Item-GearFinder.lua")
  local score, ip = zgv.ItemScore, zgv.IP
  local finder = score.GearFinder
  finder.FUTURE_DUNGEONS_LIMIT, finder.PAST_DUNGEONS_LIMIT = 5, 10
  finder.MainFrame = {Buttons={}, IsVisible=function() return visible end, Hide=function() visible=false end}
  for _, field in ipairs({"overlay", "Progress", "NoSourcesFrame", "DungeonImage", "DungeonMessage", "DungeonName", "DungeonDesc", "DungeonReason", "AddButton"}) do finder.MainFrame[field] = frame() end
  local displayed = 0
  finder.DisplayResults = function() displayed = displayed + 1 end
  local records = {}
  local function item(id, slot, strength, level, family)
    records[id] = {itemid=id, itemlink="item:"..id, name="Item "..id, cached_name="Item "..id,
      class=4, type=slot, equiploc=slot, slot=score.TypeToSlot[slot], family=family or "MAIL",
      minlevel=level or 1, itemlvl=20, stats={STRENGTH=strength}, score=123456}
    return records[id]
  end
  item(100, "INVTYPE_WRIST", 50)
  item(101, "INVTYPE_HEAD", 10)
  item(102, "INVTYPE_WRIST", 5) -- Worse than the bot's immutable baseline.
  item(103, "INVTYPE_CHEST", 10)
  item(104, "INVTYPE_FEET", 10)
  item(105, "INVTYPE_HAND", 10, 1, "CLOTH")
  item(106, "INVTYPE_LEGS", 10)
  local function details(_, link)
    work, clock = work + 1, clock + 0.2
    return records[zgv.ItemLink.GetItemID(link)]
  end
  score.GetResolvedItemDetails, score.GetItemDetails, score.GetItemDetailsQueued, score.GetItemDetailsFromDB = details, details, details, details
  score.playerclass, score.playerclassName, score.playerlevel = "MAGE", "Mage", 80
  score.playerraceName, score.playerraceToken = "Human", "Human"
  score.GetEquippedStatValue = function() error("target cap read owner stats") end
  score.Upgrades = {GetEquippedItemData=function() error("target comparison read owner equipment") end,
    GetUpgradeComparison=function() error("target comparison read owner build") end,
    IsUpgrade=function() error("target evaluation read owner upgrade cache") end,
    CanUseUniqueItem=function() return true end}
  local ownerState = {ip=true, strict=true, effective=18, era=2, account="N", gm=false, maxLevel=80}
  ip.state, ip.bridge, ip.caps = ownerState, "ready", {IP_PROGRESS_V1=true, IP_TARGET_V1=true}
  local target = setmetatable({targetName="Bot", bridge="ready", generation=1,
    state={ip=true, strict=true, effective=0, era=0, account="B", gm=false, next=1, maxLevel=80},
    access={[36]="A---", [43]="G---"}, quests={}, queued={}, inflight={}, requests={},
    profile="prot", dualWield=false}, {__index=ip})
  local subject = {unit="party1", guid="0xBot", playerclass="WARRIOR", playerclassName="Warrior",
    playerlevel=20, faction="Alliance", playerraceName="Human", playerraceToken="Human",
    equipped={[9]="item:100"}, ip=target}
  finder.Context = subject
  subject.equipmentReady=false
  assert(type(finder.ResolveTargetRules)=="function", "the target rule adapter must exist")
  finder:ResolveTargetRules()
  assert(not subject.ruleReady, "unready inspected equipment must not build an empty baseline")
  subject.equipmentReady=true
  zgv.Dungeons = {
    [36]={name="The Deadmines", expansionLevel=0, minLevel=17, maxScaleLevel=25, difficulty=1},
    [43]={name="Wailing Caverns", expansionLevel=0, minLevel=17, maxScaleLevel=25, difficulty=1},
  }
  score.Items["Test\\Available"] = {dungeon=36, [1]={WARRIOR={101,102}, MAGE={105}}}
  score.Items["Test\\Locked"] = {dungeon=43, [1]={WARRIOR={106}}}
  score.GearFinderVendorSources = {
    native={key="native", expansionLevel=0, minLevel=1, vendors={Alliance={name="Bot vendor"}, Horde={name="Owner vendor"}}, items={[103]={cost=7}}},
    future={key="future", expansionLevel=1, minLevel=1, items={[104]={cost=8}}},
  }
  score.GearFinderCraftedSources = {test={expansionLevel=0, items={[105]={}}}}
  load("ZygorQuestLootDB.lua")
  zgv.startups[#zgv.startups][2]()
  -- The production wrapper builds the real numeric quest block before scoring.
  local nativeScore = finder.ScoreDungeonItems
  nativeScore(finder)
  local questBlock
  for _, source in ipairs(score.Items) do if source.dungeon == "quests" then questBlock=source end end
  assert(questBlock and #questBlock > 3, "real quest producer must create a numeric source block")
  assert(questBlock[1].quest[1] and questBlock[1].quest[1] ~= 1,
    "target quest source level band must not borrow owner's level-80 source")
  local expectedQuest, lockedQuest, unknownQuest = questBlock[1], questBlock[2], questBlock[3]
  for _, source in ipairs(questBlock) do
    local quest = source.quest[1]
    target.quests[quest] = {status="R", reasons=0, tier=0, generation=1, at=elapsed}
  end
  for index, source in ipairs({expectedQuest, lockedQuest, unknownQuest}) do
    local id = source.ALL[1]
    item(id, ({"INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_WAIST"})[index], 10)
    target.quests[source.quest[1]] = index == 1 and {status="A", reasons=0, tier=0, generation=1, at=elapsed}
      or index == 2 and {status="L", reasons=ip.REASON.TIER, tier=8, generation=1, at=elapsed} or nil
  end
  finder:ClearResults()
  visible = false
  finder:ScoreDungeonItems()
  assert(not finder.IsScanning, "a hidden target must not start scanning")
  visible = true
  finder:ScoreDungeonItems()
  assert(subject.buildNum == 3 and subject.playerclass == "WARRIOR" and subject.playerlevel == 20,
    "target effective profile/class/level must select its own native rules")
  assert(work > 0 and finder.IsScanning, "baseline resolves before bounded source work starts")
  local ticks = 0
  while finder.IsScanning do
    ticks = ticks + 1; assert(ticks < 1000, "target scan must terminate")
    local before = work
    finder.ScoreFrame.scripts.OnUpdate(finder.ScoreFrame)
    assert(work-before <= 40, "target scan must yield its bounded source work")
  end
  assert(not finder.LastError, tostring(finder.LastError))
  local results = {}
  for _, queue in pairs(finder.UpgradeQueue) do for _, result in ipairs(queue) do results[result.itemid]=result end end
  assert(results[101] and results[101].ident == 36, "target dungeon suggestion was lost")
  assert(not results[102] and not results[105], "target must compare its own baseline/class")
  assert(results[103] and results[103].vendorName == "Bot vendor" and results[103].cost == 7,
    "target vendor suggestion must preserve its own faction/source")
  assert(not results[104], "target must not borrow owner's earned expansion for vendors")
  assert(results[106] and results[106].future, "target locked dungeon must remain labeled future")
  assert(results[expectedQuest.ALL[1]] and results[expectedQuest.ALL[1]].quest == expectedQuest.quest[1],
    "target must suggest available real numeric quest rewards")
  assert(not results[lockedQuest.ALL[1]] and not results[unknownQuest.ALL[1]],
    "target must hold locked/unknown quest rewards")
  assert(target.queued[unknownQuest.quest[1]], "unknown quest rewards must request the target's answer")
  assert(ip.state == ownerState and score.playerclass == "MAGE" and zgv.db.char.gear_active_build == 1,
    "target source scan must preserve owner's state")
  assert(records[101].score == 123456 and displayed > 0 and finder.ResultsReady,
    "native pipeline must display without overwriting shared owner scores")

  -- The real level-61 Hellfire reward is in a level-60 bot's source band.
  -- Target IP_QUESTS verifies the source map as well as native CanTakeQuest.
  subject.playerlevel, subject.ruleReady = 60, nil
  finder:ClearResults(); finder:ScoreDungeonItems()
  local hellfire
  for _, source in ipairs(score.Items) do
    if source.dungeon == "quests" then
      for _, quest in ipairs(source) do
        if quest.quest[1] then target.quests[quest.quest[1]] = {status="U", reasons=0, generation=1, at=elapsed} end
        if quest.quest[1] == 10055 then hellfire = quest end
      end
    end
  end
  assert(hellfire and hellfire.ALL[1] == 29931, "the native Hellfire source contract changed")
  item(29931, "INVTYPE_NECK", 10)
  for _, status in ipairs({"L", "U", "R", "A", "I", "C"}) do
    target.quests[10055] = {status=status, reasons=status=="L" and ip.REASON.GIVER_HIDDEN or 0,
      tier=0, generation=1, at=elapsed}
    finder:ClearResults(); finder:ScoreDungeonItems()
    while finder.IsScanning do finder.ScoreFrame.scripts.OnUpdate(finder.ScoreFrame) end
    assert(not finder.LastError, tostring(finder.LastError))
    local suggested = false
    for _, queue in pairs(finder.UpgradeQueue) do
      for _, result in ipairs(queue) do if result.itemid == 29931 then suggested=true end end
    end
    assert(suggested == (status=="A" or status=="I" or status=="C"),
      "real Hellfire rewards must hold unavailable/unknown target source maps: "..status)
  end
  finder:ClearResults(); finder:ScoreDungeonItems()
  local driver = finder.ScoreFrame
  local refreshTimer = {}
  finder.InspectRefreshTimer, finder.InspectRefreshForced = refreshTimer, true
  env.UnitGUID = function() return "0xReused" end
  driver.scripts.OnUpdate(driver)
  assert(target.closed and not finder.Context and not driver.scripts.OnUpdate and not driver.shown,
    "reused inspect unit tokens must cancel the target coroutine")
  assert(refreshTimer.closed and not finder.InspectRefreshTimer and not finder.InspectRefreshForced,
    "releasing a target must cancel pending inspect refresh work")
end
local original = read("Item-GearFinder.lua")
exercise(original)
local mutations = {
  {"target class", "return GearFinder.Context or ItemScore", "return ItemScore", "target dungeon suggestion"},
  {"target progression", "return GearFinder.Context and GearFinder.Context.ip or ZGV.IP", "return ZGV.IP", "target dungeon suggestion"},
  {"target comparison", "return ItemScore:GetUpgradeComparisonForContext(slot, item, GearFinder.Context)", "return ItemScore.Upgrades:GetUpgradeComparison(slot, item)", "target comparison read owner build"},
  {"numeric quest source", 'or GearFinder.Context ~= nil and type(data) == "table" and data.dungeon == "quests"', "", "available real numeric quest rewards"},
  {"unknown quest hold", 'return answer and (answer.status == "A" or answer.status == "I" or answer.status == "C") or false', "return true", "hold locked/unknown quest rewards"},
  {"hidden target", "if self.Context and not self.MainFrame:IsVisible() then return end", "", "hidden target must not start"},
  {"reused target", "UnitGUID(context.unit) ~= context.guid", "false", "reused inspect unit tokens"},
  {"equipment readiness", "if context.equipmentReady == false then return end", "", "unready inspected equipment"},
  {"refresh cancellation", "ZGV:CancelTimer(self.InspectRefreshTimer, true)", "", "cancel pending inspect refresh"},
}
for _, mutation in ipairs(mutations) do
  local first, last = assert(original:find(mutation[2], 1, true))
  local changed = original:sub(1, first-1) .. mutation[3] .. original:sub(last+1)
  local ok, failure = pcall(exercise, changed)
  assert(not ok and tostring(failure):find(mutation[4], 1, true),
    "target source fixture did not reject "..mutation[1]..": "..tostring(failure))
end
print("PASS: native inspected-bot coroutine preserves dungeon, quest and vendor policies")
