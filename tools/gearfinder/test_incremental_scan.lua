-- Regression for the real source-preparation/scoring coroutine on Lua 5.1.
-- Usage: lua tools/gearfinder/test_incremental_scan.lua <addon directory>
local addon = assert(arg[1], "pass the addon directory")
local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a"); file:close()
  return (source:gsub("^\239\187\191", ""))
end
local function compile(source, name, env)
  if setfenv then
    local fn = assert(loadstring(source, name)); setfenv(fn, env); return fn
  end
  return assert(load(source, name, "t", env))
end
local source = read(addon.."/Item-GearFinder.lua")
local function section(first, last)
  local a = assert(source:find(first, 1, true), first)
  local b = assert(source:find(last, a + #first, true), last)
  return source:sub(a, b - 1)
end
local implementation =
  section("GearFinder.SCAN_TIME_BUDGET_MS =", "local cancel_gearfinder_timer")..
  section("local function yield_scan_if_needed()", "local function get_time()")..
  section("local function get_time()", "local function GF_FormatFinderSummary")..
  section("local function GF_IsKnownClientItem", "local function GF_EvaluateUpgrade")..
  section("local function GF_ShouldIncludeCandidate", "local function GF_IsPhaseActive")..
  section("local function loot_score_dungeon_thread()", "-- show crawling dots")..
  section("cancel_gearfinder_timer = function(field)", "-- prepares item lists")..
  section("local function prepare_dungeon_items", "local function make_button(object)")..
  section("function GearFinder:ClearResults()", "function GearFinder:RefreshForInventoryChange()")

local function noop() end
local function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end end
local function frame()
  return {Show=noop, Hide=noop, SetText=noop, SetTexture=noop, SetPercent=noop,
    IsVisible=function() return true end}
end
local function copy(tbl)
  local out = {}; for key, value in pairs(tbl) do out[key] = value end; return out
end
local function itemID(link) return tonumber(tostring(link):match("item:(%d+)")) end

local function scenario(workMilliseconds, unresolved)
  local env = setmetatable({}, {__index=_G})
  env.table = copy(table); env.table.wipe = wipe
  local timers, clock, scheduled, elapsed = {}, 0, 0, 0
  local prepared, scored, displayed, noSources = 0, 0, 0, 0
  local pending = unresolved and {[1001]={}, [2002]={}, [3001]={}, [4001]={}} or {}
  local prematureFallbacks = 0
  local frameDelta = unresolved and 1/144 or 0.016
  local enabled, throwOnCheck = true, false
  local finder = {
    FUTURE_DUNGEONS_LIMIT=5,
    ITEM_RESOLVE_RETRY_LIMIT=60, playerfaction="Alliance",
    UpgradeQueue={[1]={}, [2]={}}, FallbackQueue={[1]={}, [2]={}},
    ItemsToScore={}, ItemsToMaybeScore={}, VendorItemsToScore={},
    FutureDungeons={}, DebugSummary={}, MainFrame={Buttons={}},
  }
  for _, field in ipairs({"overlay", "Progress", "NoSourcesFrame", "DungeonImage",
    "DungeonMessage", "DungeonName", "DungeonDesc", "DungeonReason", "AddButton"}) do
    finder.MainFrame[field] = frame()
  end
  finder.MainFrame.IsVisible = function() return true end
  finder.GetStartupItemInfoGraceRemaining = function() return 0 end
  finder.DeferFinalResultsForItemInfo = function() return false end
  finder.DisplayResults = function() displayed = displayed + 1 end
  finder.ShowNoSourcesMessage = function(self)
    noSources = noSources + 1; self.ResultsReady = true; self.MainFrame.Progress:Hide()
  end
  finder.IsValidDungeon = function(_, _, _, key)
    return key ~= "Test\\Future", key == "Test\\Future", key, 80
  end
  local score = {playerclass="MAGE", playerlevel=80, GearFinder=finder,
    Upgrades={EquippedItems={}}, Items={}, GearFinderVendorSources={}, GearFinderCraftedSources={}}
  local zgv = {ItemScore=score, db={profile={}}, ItemLink={GetItemID=itemID}, Debug=noop}
  function zgv:ScheduleRepeatingTimer(callback)
    scheduled = scheduled + 1
    local timer = {callback=callback, active=true}; timers[#timers + 1] = timer; return timer
  end
  function zgv:CancelTimer(timer) timer.active = false end
  local function work() clock = clock + workMilliseconds end
  function score:GetItemValidity(link, future)
    local id = itemID(link)
    if not finder.ScoringStarted then prepared = prepared + 1; work() end
    if throwOnCheck then error("synthetic tooltip failure") end
    return {valid=id % 3 ~= 0, slot=(math.floor(id / 1000) == 2 and 2 or 1),
      item={minlevel=(future and id % 5 == 0) and 87 or 80}}
  end
  score.GetItemDetails = function() return nil end
  local function drops(base)
    local out = {}; for i=1,120 do out[#out + 1] = base + i end
    out[#out + 1] = 55001 -- Must still respect the WotLK client-item cutoff.
    return out
  end
  score.Items["Test\\Current"] = {dungeon="current", [1]={boss=7, name="Current", ALL=drops(1000)}}
  score.Items["Test\\Future"] = {dungeon="future", [1]={boss=8, name="Future", ALL=drops(2000)}}
  score.Items["Test\\Current"][2] = {phase="disabled", ALL={999}}
  local vendorItems, craftedItems = {}, {}
  for _, id in ipairs(drops(3000)) do vendorItems[id] = {cost=id} end
  for _, id in ipairs(drops(4000)) do craftedItems[id] = {recipeSpellID=id} end
  score.GearFinderVendorSources.test = {key="test", name="Vendor", items=vendorItems}
  score.GearFinderCraftedSources.test = {key="test", name="Crafts", sourceType="crafted",
    profession="Tailoring", items=craftedItems}
  score.GearFinderVendorSources.disabled = {disabled=true, items={[998]={}}}

  env.ZGV, env.ItemScore, env.GearFinder = zgv, score, finder
  env.debugprofilestop = function() return clock end
  env.GetTime = function() return elapsed end
  env.CreateFrame = function()
    local driver = {scripts={}, shown=false}
    function driver:SetScript(event, callback) self.scripts[event] = callback end
    function driver:Show() self.shown = true end
    function driver:Hide() self.shown = false end
    return driver
  end
  env.GetInventoryItemLink = function() return nil end
  env.INVSLOT_MAINHAND = 16
  env.GF_GetItemID = itemID
  env.GF_IsPhaseActive = function(phase) return phase ~= "disabled" end
  env.GF_HasAnySourceEnabled = function() return enabled end
  env.GF_IsValidVendorSource = function(s) return not s.disabled end
  env.GF_GetFactionVendor = function() return {name="Local vendor"} end
  env.GF_IsValidCraftedSource = function() return true end
  env.GF_IsValidCraftedItem = function(_, item) return item.recipeSpellID % 5 ~= 0, "profession" end
  env.GF_GetDungeonData = function() return {minLevel=81, min_ilevel=1} end
  env.GF_GetBossNameFromID = function(_, name) return name end
  env.GF_CompactMapKeys = function() return "" end
  env.reset_debug_slot_stats, env.add_slot_debug = noop, noop
  env.set_slot_compare_reject, env.set_slot_reject = noop, noop
  env.safe_get_item_details = function(link)
    finder.ScoringStarted = true; scored = scored + 1; work()
    local id = itemID(link)
    local attempts = pending[id]
    if attempts then
      attempts[#attempts + 1] = elapsed
      if #attempts <= 3 then return nil end
    end
    return {itemid=id, itemlink=link, score=id, name="Item "..id}
  end
  env.GF_EvaluateUpgrade = function(link)
    local id = itemID(link)
    return true, (math.floor(id / 1000) == 2 and 2 or 1), id, id
  end
  env.is_replacement = function() return true end
  env.clone_item_entry = copy
  env.queue_upgrade_candidate = function(slot, item)
    local queue = finder.UpgradeQueue[slot]; queue[#queue + 1] = item
  end
  env.GF_AddVendorFields = function(item, data)
    for key, value in pairs(data) do if item[key] == nil then item[key] = value end end
  end
  env.queue_fallback_candidate = function() return false end
  env.queue_local_meta_candidate = function() prematureFallbacks = prematureFallbacks + 1 end
  env.queue_bare_fallback_candidate = env.queue_local_meta_candidate
  env.IsQuestFlaggedCompleted = function() return false end
  env.compare_current_upgrade = function(_, a, b) return a.score > b.score end
  env.compare_practical_upgrade = env.compare_current_upgrade
  env.slot_pairs, env.distinct_slot_pairs = {}, {}
  env.enforce_distinct_pair_results, env.prune_all_to_progression_band = noop, noop
  env.promote_fallback_results, env.prune_to_best_content_tier = noop, noop
  env.are_all_slots_filled = function() return false end
  env.progress_dots = noop
  env.L = {gearfinder_no_upgrade="No upgrade"}
  compile(implementation, "incremental finder", env)()

  local function tick()
    local driver = assert(finder.ScoreFrame, "expected a scan update frame")
    assert(driver.shown and driver.scripts.OnUpdate, "scan must not resume a cancelled frame")
    local beforePrepared, beforeScored = prepared, scored
    elapsed = elapsed + frameDelta
    driver.scripts.OnUpdate(driver, frameDelta)
    local completed = prepared + scored - beforePrepared - beforeScored
    assert(completed <= finder.SCAN_ITEMS_PER_SLICE, "item-count budget exceeded: "..completed)
    if workMilliseconds > 0 then
      assert(completed <= math.ceil(finder.SCAN_TIME_BUDGET_MS / workMilliseconds),
        "elapsed-time budget exceeded: "..completed)
    end
    return prepared-beforePrepared, scored-beforeScored
  end
  local function finish()
    local ticks = 0
    while finder.IsScanning do tick(); ticks=ticks+1; assert(ticks < 3000, "scan did not complete") end
    assert(not finder.IsScanning and finder.ScoreThread == nil, "finished scan must release its state")
    assert(not finder.ScoreFrame.shown and not finder.ScoreFrame.scripts.OnUpdate,
      "finished scan must remove its update callback")
    assert(not finder.AntsTimer, "finished scan must stop its progress timer")
    return ticks
  end
  local function checkResults()
    local expected, actual = {}, {}
    for base=1000,4000,1000 do
      for i=1,120 do
        local id = base+i
        if id % 3 ~= 0 and (base ~= 2000 and base ~= 4000 or id % 5 ~= 0) then expected[id] = true end
      end
    end
    for slot, queue in pairs(finder.UpgradeQueue) do
      for _, item in ipairs(queue) do
        assert(expected[item.itemid], "unexpected candidate "..item.itemid)
        assert(not actual[item.itemid], "duplicated candidate "..item.itemid)
        actual[item.itemid] = true
        if slot == 2 then assert(item.future and item.ident == "Test\\Future") end
        if item.itemid > 4000 then assert(item.sourceType == "crafted" and item.recipeSpellID == item.itemid) end
        if item.itemid > 3000 and item.itemid < 4000 then assert(item.vendorSource == "test" and item.cost == item.itemid) end
      end
    end
    for id in pairs(expected) do assert(actual[id], "lost eligible candidate "..id) end
    assert(finder.ResultsReady and displayed >= 1, "completed results must be displayed")
    assert(prepared > 0 and scored > 0, "must exercise real preparation and scoring")
  end

  finder:ScoreDungeonItems()
  assert(prepared == 0 and scored == 0, "opening must not read candidate tooltips")
  local thread, driver, callback, timerCount = finder.ScoreThread, finder.ScoreFrame,
    finder.ScoreFrame.scripts.OnUpdate, scheduled
  finder:ScoreDungeonItems(); finder:ScoreDungeonItems(true)
  assert(finder.ScoreThread == thread and finder.ScoreFrame == driver
    and driver.scripts.OnUpdate == callback and scheduled == timerCount,
    "reopening during a scan must preserve its progress")
  local p, s = tick()
  assert(p > 0 and p < 120 and s == 0, "large preparation sources must yield")
  assert(finish() > 3, "large single sources must use multiple update callbacks")
  checkResults()
  for id, attempts in pairs(pending) do
    assert(#attempts == 4, "pending item must be retried until live data resolves: "..id)
    for i=2,#attempts do
      assert(attempts[i] - attempts[i-1] >= 0.1 - 1e-9,
        "high-FPS updates must not accelerate unresolved retries: "..id)
    end
  end
  assert(prematureFallbacks == 0 and not finder.HadUnresolvedItems,
    "temporary item-cache misses must not exhaust the fallback retry limit")
  timerCount = scheduled
  finder:ScoreDungeonItems()
  assert(scheduled == timerCount and not finder.ScoreFrame.scripts.OnUpdate,
    "cached results must not restart scanning")

  -- Invalidation must cancel an unfinished scan and let a fresh scan complete.
  finder:ClearResults(); finder.ScoringStarted = nil
  finder:ScoreDungeonItems(); tick()
  local oldFrame, oldAnts, oldThread = finder.ScoreFrame, finder.AntsTimer, finder.ScoreThread
  finder:ClearResults()
  assert(not oldFrame.shown and not oldFrame.scripts.OnUpdate and not oldAnts.active
    and not finder.IsScanning and not finder.ScoreThread)
  finder.ScoringStarted = nil
  finder:ScoreDungeonItems()
  assert(finder.ScoreThread ~= oldThread, "refresh must create a fresh coroutine")
  finish(); checkResults()

  finder:ClearResults(); enabled=false; finder:ScoreDungeonItems(); finish()
  assert(noSources == 1 and finder.DebugSummary.noSources, "disabled sources must finish cleanly")

  finder:ClearResults(); finder.ScoringStarted=nil; enabled=true; throwOnCheck=true
  finder:ScoreDungeonItems(); finish()
  assert(finder.LastError and finder.LastError:find("synthetic tooltip failure", 1, true),
    "coroutine errors must be reported and release both timers")
  assert(finder.ResultsReady, "error state must terminate scanning")

  -- Display callbacks may invalidate results and replace the active coroutine.
  -- Cleanup of the finished worker must not detach the replacement's driver.
  finder:ClearResults(); finder.ScoringStarted=nil; throwOnCheck=false
  local restarted = false
  finder.DisplayResults = function(self)
    displayed = displayed + 1
    if self.ResultsReady and not restarted then
      restarted = true
      self:ClearResults(); self.ScoringStarted=nil; self:ScoreDungeonItems()
    end
  end
  finder:ScoreDungeonItems(); finish(); checkResults()
  assert(restarted, "must exercise a refresh from final result display")
end

scenario(2) -- Fake expensive tooltip API: the elapsed-time budget limits each callback.
scenario(0) -- Frozen/coarse profiler: the item-count fallback still yields.
scenario(0, true) -- Delayed live item data must retain its retry interval at 144 FPS.
print("PASS: Gear Finder preparation and scoring yield, retain filters, cache and cancel safely")
