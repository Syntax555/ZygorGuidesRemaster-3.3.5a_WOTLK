-- Run the native Finder UI against recorded inspect/window events.
-- Usage: lua tools/gearfinder/test_inspect_context.lua <addon directory> [UI source override]
local addon = assert(arg[1], "pass the addon directory")
local source = arg[2] or addon .. "/Code-WOTLK/Item-GearFinder.lua"
local mainFile = assert(io.open(addon .. "/Item-GearFinder.lua", "rb"))
local mainSource = mainFile:read("*a"); mainFile:close()
local snapshotStart = assert(mainSource:find("function GearFinder:TargetEquipmentReady(unit)", 1, true))
local snapshotEnd = assert(mainSource:find("function GearFinder:BindTarget(unit, force)", snapshotStart, true))
local snapshotHelper = mainSource:sub(snapshotStart, snapshotEnd - 1)
local function object()
  local result = { scripts = {}, hooks = {}, shown = true, level = 5 }
  function result:SetScript(event, callback) self.scripts[event] = callback end
  function result:HookScript(event, callback)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], callback)
  end
  function result:Fire(event, ...)
    if self.scripts[event] then self.scripts[event](self, ...) end
    for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
  end
  function result:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
  function result:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
  function result:IsShown() return self.shown end
  result.IsVisible = result.IsShown
  function result:SetParent(parent) self.parent = parent end
  function result:ClearAllPoints() self.points = {} end
  function result:SetPoint(...) self.points = { ... } end
  function result:GetFrameLevel() return self.level end
  function result:SetFrameLevel(level) self.level = level end
  function result:SetText(text) self.text = text end
  function result:GetNormalTexture() return self end
  function result:SetTexCoord() end
  return setmetatable(result, { __index = function() return function() end end })
end
local function chain(value)
  local wrapped = {}
  return setmetatable(wrapped, { __index = function(_, key)
    if key == "__END" then return value end
    return function(_, ...) value[key](value, ...); return wrapped end
  end })
end
local function fixture(sourceText, lateInspect, lateMultiBot, withDragon)
local events, hooks, eventCounts, timers = {}, {}, {}, {}
local equipment = {party1="item:100", party2="item:200"}
local dragonReady, inspectCallback, registrations = false, nil, 0
DragonUI = withDragon and {
  IsInspectDataFor=function(_, unit) return dragonReady and unit=="party1" end,
  RegisterInspectDataCallback=function(_, callback) inspectCallback=callback; registrations=registrations+1 end,
} or nil
local binds, releases, scans, ownerScores, ownerToggles = 0, 0, 0, 0, 0
local native = object()
native.Title, native.shown = object(), false
CharacterFrame, PaperDollFrame = object(), object()
CharacterFrame.numTabs = 0
CharacterNameText, CharacterFramePortrait, CharacterFrameCloseButton = object(), object(), object()
local inspect = object()
inspect.unit = "party1"
InspectFrame = not lateInspect and inspect or nil
ZygorGearFinder = native
local finder = { MainFrame = native }
function finder:CreateMainFrame() end
function finder:BindTarget(unit)
  binds = binds + 1
  if self.refuse then return false end
  self.Context = { unit = unit, guid = UnitGUID(unit), name=UnitName(unit), playerlevel=UnitLevel(unit),
    equipped={[9]=GetInventoryItemLink(unit, 9)}, ip={profile="arms"}, equipmentReady=self:TargetEquipmentReady(unit) }
  return true
end
function finder:ReleaseTarget()
  if self.InspectRefreshTimer then
    ZygorGuidesViewer:CancelTimer(self.InspectRefreshTimer)
    self.InspectRefreshTimer, self.InspectRefreshForced = nil, nil
  end
  if self.Context then self.Context = nil; releases = releases + 1 end
end
function finder:ScoreDungeonItems() if not self.Context or self.Context.equipmentReady then scans = scans + 1 end end
function finder:ClearResults() end
function finder:ShowItemInfoLoadingMessage() self.loading=true end
local scores = { GearFinder = finder, Upgrades = { ScoredEquippedItems = true } }
function scores:EnsureActiveRuleSet() return true end
function scores.Upgrades:ScoreEquippedItems() ownerScores = ownerScores + 1 end
ZygorGuidesViewer = {
  DIR = "Interface\\AddOns\\ZygorGuidesViewerRM",
  L = { gearfinder_title = "Equipement" },
  ItemScore = scores,
  db = { profile = { autogear = true } },
  ChainCall = chain,
  CreateFrameWithBG = function(_, _, parent) local frame = object(); frame.parent = parent; return frame end,
  AddEvent = function(_, event, callback)
    eventCounts[event] = (eventCounts[event] or 0) + 1
    events[event] = callback
  end,
  ScheduleTimer = function(_, callback)
    local timer={callback=callback}; timers[#timers+1]=timer; return timer
  end,
  CancelTimer = function(_, timer) timer.closed=true end,
}
function UnitExists(unit) return unit == "party1" or unit == "party2" or unit == "player" end
function UnitName(unit) return ({ party1 = "Bot", party2 = "Other", player = "Owner" })[unit] end
function UnitGUID(unit) return ({ party1 = "0xBot", party2 = "0xOther", player = "0xOwner" })[unit] end
function UnitLevel() return 60 end
function GetInventoryItemLink(unit, slot) return slot==9 and equipment[unit] or nil end
function UnitIsUnit(a, b) return UnitGUID(a) == UnitGUID(b) end
function UnitIsPlayer() return true end
function CanInspect() return true end
local inGroup = true
function UnitInParty() return inGroup end
function UnitInRaid() return nil end
function ToggleCharacter() ownerToggles = ownerToggles + 1 end
function InspectFrame_UnitChanged() end
function hooksecurefunc(owner, name, callback)
  if type(owner)=="string" then hooks[owner]=name else hooks[name]=callback end
end
local multiBot = { isActive = function(name) return name == "Bot" or name == "Other" end,
  Comm={FinishCombatProfileRequest=function() end} }
MultiBot = not lateMultiBot and multiBot or nil
GearFinder = finder
assert(loadstring(snapshotHelper, "TargetSnapshot"))()
local function flush()
  local pending=timers; timers={}
  for _, timer in ipairs(pending) do if not timer.closed then timer.callback() end end
end
GameTooltip = object()
assert(loadstring(sourceText, "GearFinderInspectUI"))()
finder:Initialise()
if lateMultiBot then
  assert(not hooks.FinishCombatProfileRequest, "profile hooks wait for MultiBot")
  MultiBot=multiBot
  events.ADDON_LOADED(nil, nil, "MultiBot")
end
if lateInspect then
  assert(not finder.InspectButton, "inspect hooks wait for its native load-on-demand addon")
  InspectFrame = inspect
  events.ADDON_LOADED(nil, nil, "OtherAddon")
  assert(not finder.InspectButton, "unrelated addon loads do not attach inspect")
  events.ADDON_LOADED(nil, nil, "Blizzard_InspectUI")
end
assert(finder.InspectButton and finder.InspectButton.parent == InspectFrame, "inspect launch uses the native frame")
assert(events.ADDON_LOADED and events.UNIT_INVENTORY_CHANGED, "hooks are event driven")
assert(eventCounts.PARTY_MEMBERS_CHANGED == 1 and eventCounts.RAID_ROSTER_UPDATE == 1,
  "roster events must register once")
finder.InspectButton:Fire("OnEnter")
assert(GameTooltip.text == "Zygor Equipement", "inspect launcher uses the localized Gear Finder label")
local attachCount = #(InspectFrame.hooks.OnShow or {})
finder:AttachInspectFrame()
assert(#InspectFrame.hooks.OnShow == attachCount, "inspect hooks must be installed once")
finder:ShowInspectFinder("party2")
assert(binds == 0, "only the unit currently shown in inspect may be bound")
finder.refuse = true
finder:ShowInspectFinder("party1")
assert(not native:IsShown() and finder.InspectUnit == nil, "a refused subject must not open recommendations")
finder.refuse = nil
finder:ShowInspectFinder("party1")
if withDragon then
  assert(scans==0 and finder.Context.equipmentReady==false, "unready DragonUI data must hold target scoring")
  local pendingBinds=binds
  inspectCallback("0xOther"); flush()
  events.UNIT_INVENTORY_CHANGED(nil,nil,"party1"); flush()
  assert(binds==pendingBinds and scans==0, "foreign or unready inspect data must not refresh the target")
  dragonReady=true
  inspectCallback("0xBot"); flush()
  assert(binds==pendingBinds+1 and scans==1, "matching DragonUI data must release target loading")
  finder:AttachInspectDataHook()
  assert(registrations==1, "inspect data callbacks must register once")
end
assert(native:IsShown() and native.parent == InspectFrame and finder.InspectGuid == "0xBot", "inspect reuses the Finder window")
assert(finder.Context.guid == "0xBot" and scans == 1 and ownerScores == 0 and ownerToggles == 0,
  "target opening must not rescore or open the owner's character")
assert(native.Title.text == "Zygor Equipement - Bot", "the localized window identifies its target")
local before = binds
local beforeTimers=#timers
events.UNIT_INVENTORY_CHANGED(nil, nil, "party2")
assert(binds == before and #timers==beforeTimers, "other units must not restart target scans")
events.UNIT_INVENTORY_CHANGED(nil, nil, "party1")
flush()
assert(binds == before and scans == 1, "unchanged target equipment events must preserve requests and scan")
equipment.party1="item:101"
beforeTimers=#timers
for _=1,20 do events.UNIT_INVENTORY_CHANGED(nil, nil, "party1") end
assert(binds == before and #timers==beforeTimers+1, "one equipment batch must refresh the target once")
flush()
assert(binds == before + 1 and scans == 2, "one equipment batch must refresh the target once")
local profileBefore=binds
hooks.FinishCombatProfileRequest("token", {status="ok",botName="Other",effective="prot"})
hooks.FinishCombatProfileRequest("token", {status="error",botName="Bot",effective="prot"})
hooks.FinishCombatProfileRequest("token", {status="ok",botName="Bot",effective="arms"})
flush()
assert(binds == profileBefore, "unrelated, refused and unchanged profiles must not refresh")
hooks.FinishCombatProfileRequest("token", {status="ok",botName="Bot",effective="prot"})
flush()
assert(binds == profileBefore+1 and scans == 3, "profile changes must refresh without equipment changes")
finder.refuse = true
equipment.party1="item:102"
events.UNIT_INVENTORY_CHANGED(nil, nil, "party1")
flush()
assert(not native:IsShown() and finder.Context == nil and scans == 3,
  "a refused refresh must close the target instead of scanning the owner")
finder.refuse = nil
finder:ShowInspectFinder("party1")
equipment.party1="item:103"
events.UNIT_INVENTORY_CHANGED(nil, nil, "party1")
local closedCallback=timers[#timers].callback
InspectFrame:Hide()
closedCallback()
assert(not native:IsShown() and finder.Context == nil and finder.InspectUnit == nil and releases == 2,
  "closing inspect cancels and releases target work")
local closedBinds = binds
events.UNIT_INVENTORY_CHANGED(nil, nil, "party1")
assert(binds == closedBinds, "hidden target equipment updates do not run work")
InspectFrame:Show()
finder:ShowInspectFinder("party1")
equipment.party1="item:104"
events.UNIT_INVENTORY_CHANGED(nil, nil, "party1")
local oldCallback=timers[#timers].callback
InspectFrame.unit = "party2"
hooks.InspectFrame_UnitChanged()
assert(not native:IsShown() and finder.Context == nil, "changing inspected GUID must discard the old target")
finder:ShowInspectFinder("party2")
local newContext, switchedBinds=finder.Context,binds
oldCallback()
assert(native:IsShown() and finder.Context==newContext and binds==switchedBinds,
  "late target callbacks must not refresh or hide a switched subject")
native:Hide()
InspectFrame.unit = "party1"
finder:ShowInspectFinder("party1")
inGroup = false
events.PARTY_MEMBERS_CHANGED()
assert(not native:IsShown() and finder.Context == nil, "leaving the group releases inspected bot work")
inGroup = true
events.RAID_ROSTER_UPDATE()
finder:ShowInspectFinder("party1")
if withDragon then
  dragonReady=false
  inspectCallback(nil)
  assert(finder.Context.equipmentReady==false and finder.loading,
    "invalidated DragonUI inspect data must hold target results")
  local unreadyBinds=binds
  events.UNIT_INVENTORY_CHANGED(nil,nil,"party1"); flush()
  assert(binds==unreadyBinds, "unready inspect invalidation must not send requests")
  dragonReady=true
  inspectCallback("0xBot"); flush()
  assert(binds==unreadyBinds+1, "fresh matching data must refresh an invalidated snapshot")
end
finder:ShowFinder()
assert(native:IsShown() and native.parent == CharacterFrame and finder.Context == nil and finder.InspectUnit == nil,
  "the owner's launch restores the same native Finder to its player context")
assert(ownerScores == 0, "valid owner equipped cache must be preserved")
local ownerBefore = ownerToggles
native:Hide()
assert(PaperDollFrame:IsShown(), "closing player Finder restores the native tab")
ZygorGuidesViewer.db.profile.autogear = false
finder:UpdateSystemTab()
assert(not finder.InspectButton:IsShown(), "disabled Gear Advisor hides both launch controls")
assert(ownerToggles == ownerBefore, "inspect lifecycle must not toggle the player's character frame")
end
local handle = assert(io.open(source, "rb"))
local original = handle:read("*a"); handle:close()
fixture(original)
fixture(original, true)
fixture(original, false, true)
fixture(original, false, false, true)
local mutations = {
  {"localized inspect title", '(L["gearfinder_title"] or "Gear Finder") .. " - "', '"Gear Finder - "',
    "localized window identifies"},
  {"roster event registration", '\t\tfor _, event in ipairs({"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"}) do',
    '\t\tfor _, event in ipairs({"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED"}) do',
    "roster events must register once"},
  {"visible subject", "if not unit or unit ~= inspectedUnit() then return end", "if not unit then return end",
    "only the unit currently shown in inspect"},
  {"inspect teardown", "GearFinder:ReleaseTarget()\n\t\t\treturn", "return",
    "a refused refresh must close"},
  {"equipment isolation", "and UnitGUID(unit) == GearFinder.InspectGuid", "and true",
    "other units must not restart"},
  {"refused refresh", "if not self:BindTarget(unit, true) then", 'if self:BindTarget(unit, true) == "ignored" then',
    "a refused refresh must close"},
  {"snapshot dedupe", "if not forced and self:IsTargetSnapshotCurrent(unit) then return end", "",
    "unchanged target equipment events"},
  {"equipment batch", "if self.InspectRefreshTimer then return end", "",
    "one equipment batch must refresh"},
  {"profile refresh", "GearFinder:QueueInspectRefresh(true)", "GearFinder:QueueInspectRefresh()",
    "profile changes must refresh without equipment"},
  {"profile identity", "string.lower(result.botName) == string.lower(context.name)", "true",
    "unrelated, refused and unchanged profiles"},
  {"inspect readiness", "if not self:TargetEquipmentReady(unit) then return end", "",
    "foreign or unready inspect data", true},
  {"inspect invalidation", "context.equipmentReady, context.ruleReady = false, nil", "context.ruleReady = nil",
    "invalidated DragonUI inspect data", true},
  {"single inspect callback", "self.InspectDataHooked or not", "not",
    "inspect data callbacks must register once", true},
  {"native parent", 'GearFinder.MainFrame:SetParent(CharacterFrame)', 'GearFinder.MainFrame:SetParent(InspectFrame)',
    "owner's launch restores"},
}
for _, mutation in ipairs(mutations) do
  local first, last = original:find(mutation[2], 1, true)
  assert(first, mutation[1])
  local changed = original:sub(1, first - 1) .. mutation[3] .. original:sub(last + 1)
  local ok, failure = pcall(fixture, changed, false, false, mutation[5])
  assert(not ok and tostring(failure):find(mutation[4], 1, true),
    "inspect fixture did not reject " .. mutation[1] .. ": " .. tostring(failure))
end
print("PASS: native Gear Finder follows the visible inspected subject without owner state changes")
