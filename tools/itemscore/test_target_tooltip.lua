-- Inspect rows use the same scorer with their captured subject; owner tooltips stay native.
-- Usage: lua tools/itemscore/test_target_tooltip.lua <addon directory>
local addon = assert(arg[1], "addon directory required")
local file = assert(io.open(addon .. "/Item-ItemScore.lua", "rb"))
local original = file:read("*a"):gsub("\r\n", "\n"); file:close()
local function section(text, first, last)
  local a = assert(text:find(first, 1, true), first)
  return text:sub(a, assert(text:find(last, a + 1, true), last) - 1)
end
local function exercise(source)
  local env = setmetatable({}, {__index = _G})
  local context = {name = "Altbot", playerclass = "WARRIOR", playerclassName = "Warrior", buildNum = 3,
    playerlevel = 60, ip = {closed = false}, ActiveRuleSet = {stats = {STRENGTH = 5}}}
  local owner = {zygorGearContext = context}
  local item = {itemlink = "item:101", type = "INVTYPE_WEAPON", class = 2, targetOnly = true}
  local score = {playerclass = "MAGE", playerlevel = 80, Upgrades = {}}
  local nativeCalls, targetCalls, compared = 0, 0, {}
  local verdict = {valid = true, final = true, slot = 16, slot_2 = 17}
  local ready, pending = true, false
  function score:GetResolvedItemDetails() return item end
  function score:GetItemDetails() return item end
  function score:IsItemPendingResolution() return pending end
  function score:GetValidSlots(candidate, subject)
    if candidate.targetOnly and subject ~= context then return nil end
    return 16, 17
  end
  function score:GetItemValidityForContext(link, future, subject)
    assert(link == item.itemlink and subject == context, "tooltip lost the inspected subject validity")
    targetCalls = targetCalls + 1
    return verdict
  end
  function score:GetItemScoreForContext(link, subject)
    assert(link == item.itemlink and subject == context, "tooltip lost the inspected subject score")
    targetCalls = targetCalls + 1
    return 200, ready
  end
  function score:GetUpgradeComparisonForContext(slot, candidate, subject)
    assert(candidate == item and subject == context, "tooltip compared against owner equipment")
    compared[#compared + 1] = slot
    return {candidateScore = 200, deltaScore = slot == 16 and 25 or 50, percent = slot == 16 and 14.2 or 33.3}
  end
  function score:GetContextScoreWeightTotal(subject)
    assert(subject == context, "tooltip normalized against owner weights")
    return 5
  end
  function score:GetBuildName(class, build, level)
    if class == "WARRIOR" then
      assert(build == 3 and level == 60, "tooltip label used the owner build")
      return "Protection"
    end
    assert(class == "MAGE"); return "Arcane"
  end
  function score:GetItemScore() nativeCalls = nativeCalls + 1; return 1, true end
  function score:IsValidItem() nativeCalls = nativeCalls + 1; return false, true end
  function score:GetHeirloomInfo() nativeCalls = nativeCalls + 1 end
  function score:GetActiveBuildSourceLabel() return "Detected build" end
  function score.Upgrades:GetEquippedItemData() nativeCalls = nativeCalls + 1; return {} end
  function score.Upgrades:ResetWeaponQueue() error("target tooltip mutated the owner weapon queue") end
  env.ItemScore, env.LE_ITEM_CLASS_WEAPON = score, 2
  env.L = {gearfinder_upgrade_percent_short = "%+.1f%%"}
  env.ZGV = {db = {profile = {autogear = true, itemscore_tooltips = true,
    itemscore_tooltip_value_mode = "both", itemscore_tooltip_normalize_score = true}, char = {gear_active_build = 1}}}
  local tip = {lines = {}}
  function tip:GetItem() return "Candidate", item.itemlink end
  function tip:GetOwner() return owner end
  function tip:AddLine(line) self.lines[#self.lines + 1] = line end
  function tip:IsVisible() return true end
  env.GameTooltip, env.ItemRefTooltip = tip, {}
  local definitions = "local ItemScore, ZGV, L = ItemScore, ZGV, L\n"
    .. section(source, "local function branded_tooltip_header", "local function branded_chat_prefix")
    .. section(source, "local function round_score", "if not ItemScore then return end")
    .. section(source, "local EQUIPPABLE_INV_TYPES", "local DB_STRUCTURAL_STATS")
    .. section(source, "local function get_item_slot_info", "local function debug_bool")
    .. section(source, "local function ItemScore_SetTooltipData", "-- functions that support itemscore/gearfinder options panel")
    .. "\nreturn ItemScore_SetTooltipData, ItemScore_ClearTooltipData"
  local chunk = assert(loadstring(definitions, "NativeTooltip")); setfenv(chunk, env)
  local render, clear = chunk()
  render(tip)
  local text = table.concat(tip.lines, "\n")
  assert(text:find("Altbot:|r Protection", 1, true), "target tooltip must identify its own profile")
  assert(text:find("40.0", 1, true) and text:find("+50.0", 1, true), "target tooltip must use subject score, caps and best slot")
  assert(#compared == 2 and compared[1] == 16 and compared[2] == 17, "target tooltip must compare both subject slots")
  assert(nativeCalls == 0 and targetCalls == 2, "target tooltip must not invoke owner scoring")
  local count = #tip.lines
  render(tip)
  assert(#tip.lines == count, "target tooltip is appended once")
  clear(tip); tip.lines = {}; verdict.valid = false
  render(tip)
  assert(table.concat(tip.lines, "\n"):find("Unusable", 1, true), "target restrictions must stay visible")
  clear(tip); tip.lines = {}; verdict.final = false
  render(tip)
  assert(#tip.lines == 0, "an unfinished target verdict must not show scoring")
  clear(tip); tip.lines = {}; verdict.final, ready = true, false
  render(tip)
  assert(#tip.lines == 0, "an unfinished target score must not show scoring")
  clear(tip); tip.lines = {}; ready, context.ip.closed = true, true
  render(tip)
  assert(#tip.lines == 0, "a closed inspect session must not show scoring")
  clear(tip); tip.lines = {}; context.ip.closed = false; pending = true
  render(tip)
  assert(#tip.lines == 0, "unresolved item data must not show scoring")
  clear(tip); tip.lines = {}; pending = false; owner.zygorGearContext = nil; item.targetOnly = false
  render(tip)
  text = table.concat(tip.lines, "\n")
  assert(nativeCalls > 0 and text:find("Detected build:|r Arcane", 1, true), "the owner tooltip must retain native scoring")
end
exercise(original)
local mutations = {
  {"subject gear slots", "item_is_gear(item, context)", "item_is_gear(item)", "target tooltip must identify"},
  {"subject scoring", "if context then\n\t\t\tItemScore.TooltipPatched", "if false then\n\t\t\tItemScore.TooltipPatched", "target tooltip must identify"},
  {"closed subject", "if context.ip and context.ip.closed then return end", "if false then return end", "closed inspect session"},
  {"final target verdict", "if not verdict.final or not success then return end", "if not success then return end", "unfinished target verdict"},
  {"ready target score", "if not verdict.final or not success then return end", "if not verdict.final then return end", "unfinished target score"},
}
for _, mutation in ipairs(mutations) do
  local a, b = original:find(mutation[2], 1, true); assert(a, mutation[1])
  local source = original:sub(1, a - 1) .. mutation[3] .. original:sub(b + 1)
  local ok, failure = pcall(exercise, source)
  assert(not ok and tostring(failure):find(mutation[4], 1, true),
    "tooltip fixture did not reject " .. mutation[1] .. ": " .. tostring(failure))
end
print("PASS: inspected Gear Finder tooltips use the target context and preserve owner scoring")
