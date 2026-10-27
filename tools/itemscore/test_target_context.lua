-- The existing scorer and uniqueness rules evaluate a captured inspected character.
-- Usage: lua tools/itemscore/test_target_context.lua <addon directory>
local addon = assert(arg[1], "addon directory required")
local function read(path)
  local file = assert(io.open(addon .. "/" .. path, "rb"))
  local text = file:read("*a")
  file:close()
  return (text:gsub("^\239\187\191", "")):gsub("\r\n", "\n")
end
local function section(text, first, last)
  local start = assert(text:find(first, 1, true), first)
  return text:sub(start, assert(text:find(last, start + 1, true), last) - 1)
end
local originals = {
  score = read("Item-ItemScore.lua"),
  slots = read("Code-WOTLK/Item-ItemScore.lua"),
  upgrades = read("Item-Upgrades.lua"),
}
local function exercise(sources)
  local env = setmetatable({}, {__index = _G})
  env._G = env
  local function run(text)
    local chunk = assert(loadstring(text))
    setfenv(chunk, env)
    return chunk()
  end
  for index, slot in ipairs({"HEAD", "NECK", "SHOULDER", "BODY", "CHEST", "WAIST", "LEGS", "FEET", "WRIST", "HAND", "FINGER1", "FINGER2", "TRINKET1", "TRINKET2", "BACK", "MAINHAND", "OFFHAND", "RANGED", "TABARD"}) do
    env["INVSLOT_" .. slot] = index
  end
  env.GetLocale = function() return "enUS" end
  env.GetMaxPlayerLevel = function() return 80 end
  env.LE_ITEM_CLASS_ARMOR, env.LE_ITEM_CLASS_WEAPON = 4, 2
  env.ZygorGuidesViewer = {db = {profile = {}, char = {gear_active_build = 1}}, L = setmetatable({}, {__index = function(_, key) return key end})}
  env.ZGV = env.ZygorGuidesViewer
  run(read("Code-WOTLK/Item-DataTables.lua"))
  local score = env.ZGV.ItemScore
  env.ItemScore = score
  run(read("Data-WOTLK/Item-Statweights.lua"))
  score.playerclass, score.playerclassName, score.playerlevel = "MAGE", "Mage", 80
  score.playerraceName, score.playerraceToken, score.playerDualWield = "Human", "Human", false
  score.IsKnownWeightClass = function(self, class) return self.rules[class] ~= nil end
  score.GetBuildName = function(_, class, build) return score.rules[class][build].name end
  score.GetEquippedStatValue = function() return 0 end
  score.NormaliseStatName = function(_, name) return name == "ITEM_MOD_HIT_RATING_SHORT" and "HIT" or name end
  local items = {
    [101] = {itemid = 101, itemlink = "item:101", stats = {ITEM_MOD_HIT_RATING_SHORT = 100}, class = 4, type = "INVTYPE_WRIST", family = "PLATE"},
    [102] = {itemid = 102, itemlink = "item:102", stats = {HIT = 1}, class = 4, type = "INVTYPE_WRIST", family = "CLOTH"},
    [103] = {itemid = 103, itemlink = "item:103", stats = {HIT = 10, EMPTY_SOCKET_YELLOW = 1}, class = 4, type = "INVTYPE_WRIST", family = "PLATE", minlevel = 40, playerclass = "Warrior", allowableRaceMask = 32, unusable_by_tooltip = true, score = 987},
    [104] = {itemid = 104, itemlink = "item:104", stats = {DAMAGE_PER_SECOND = 10}, class = 2, type = "INVTYPE_WEAPON", family = "SWORD"},
    [105] = {itemid = 105, itemlink = "item:105", stats = {AGILITY = 10}, class = 2, type = "INVTYPE_RANGED", equiploc = "INVTYPE_RANGED", subclass = 2},
    [106] = {itemid = 106, itemlink = "item:106", stats = {STRENGTH = 10}, class = 4, type = "INVTYPE_FINGER", family = "JEWELERY", slot = 11, slot_2 = 12},
    [107] = {itemid = 107, itemlink = "item:107", stats = {STRENGTH = 10}, class = 4, type = "INVTYPE_FINGER", family = "JEWELERY", slot = 11, slot_2 = 12},
    [108] = {itemid = 108, itemlink = "item:108", stats = {DAMAGE_PER_SECOND = 8}, class = 2, type = "INVTYPE_WEAPON", family = "SWORD", slot = 16},
    [109] = {itemid = 109, itemlink = "item:109", stats = {DAMAGE_PER_SECOND = 12}, class = 2, type = "INVTYPE_2HWEAPON", family = "TH_SWORD", slot = 16, twohander = true},
  }
  env.ZGV.ItemLink = {GetItemID = function(link) return tonumber(link:match("item:(%d+)")) end}
  local resolved = 0
  score.GetResolvedItemDetails = function(_, link)
    resolved = resolved + 1
    return link and items[env.ZGV.ItemLink.GetItemID(link)]
  end
  local queued = {}
  score.GetItemDetailsQueued = function(self, link) queued[link] = true; return self:GetResolvedItemDetails(link) end
  env.ZGV.ExplodeString = function(_, text)
    local values = {}
    for name in text:gmatch("[^,]+") do values[#values + 1] = name:match("^%s*(.-)%s*$") end
    return values
  end
  local equipment = {player = {[9] = "item:102"}, party1 = {[9] = "item:101"}}
  env.GetInventoryItemLink = function(unit, slot) return equipment[unit] and equipment[unit][slot] end
  env.UnitClass = function(unit) assert(unit == "party1"); return "Warrior", "WARRIOR" end
  env.UnitRace = function(unit) assert(unit == "party1"); return "Tauren", "Tauren" end
  env.bit = {band = function(a, b)
    local result, bit = 0, 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then result = result + bit end
      a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return result
  end}
  local source = sources.score
  local definitions = "local ItemScore, ZGV = ItemScore, ZGV\nlocal item_armor_types, item_weapon_types = ItemScore.Item_Armor_Types, ItemScore.Item_Weapon_Types\n"
    .. section(source, "local function get_positive_weight_total", "local function get_active_score_weight_total")
    .. section(source, "local function add_stat", "local DB_SLOT_TO_INVTYPE")
    .. section(source, "local DB_CLASS_BITS", "local ARMOR_FAMILY_ORDER")
    .. "local ARMOR_FAMILY_ORDER\nlocal bit_band = bit.band\n"
    .. section(source, "local function normalize_race_token", "local function flush_missing_itemdb_warnings")
    .. section(source, "local function item_needs_live_resolution", "local TWO_HANDED_WEAPON_FAMILIES")
    .. section(source, "local TWO_HANDED_WEAPON_FAMILIES", "local function item_is_gear")
    .. section(source, "ItemScore.LevelingBuildFallback = {", "function ItemScore:GetActiveTalentGroup")
    .. section(source, "function ItemScore:GetResolvedBuild", "function ItemScore:DetectActiveBuild")
    .. section(source, "local function copy_simple_table", "function ItemScore:EnsureSelectedWeightTarget")
  run(definitions)
  run("local ItemScore = ItemScore\n" .. section(sources.slots, "local function get_slots_by_type", "function ItemScore:SetData"))
  local earlyTank = score:BuildRuleContext("WARRIOR", 3, 5, {equipped = {}, className = "Warrior"})
  assert(earlyTank.buildNum == 3 and not earlyTank.usesFallback, "the target's selected profile was replaced by a leveling fallback")
  assert(score:BuildRuleContext("WARRIOR", 3, 5).buildNum == 1, "the player's native leveling fallback changed")
  local unknown = score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {[9] = "item:999"}, className = "Warrior"})
  assert(not unknown and queued["item:999"], "missing target baseline was treated as an empty slot")
  items[101].needs_live_scan = true
  assert(not score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {[9] = "item:101"}, className = "Warrior"}), "incomplete target baseline was treated as ready")
  items[101].needs_live_scan = nil
  local subject = {unit = "party1", ip = {state = {effective = 0}}, playerDualWield = true}
  local context = score:BuildRuleContext("WARRIOR", 1, 80, subject)
  assert(context.playerclass == "WARRIOR" and context.playerclassName == "Warrior", "context kept owner's class")
  assert(context.playerraceName == "Tauren" and context.playerraceToken == "Tauren" and context.ip == subject.ip, "context kept owner's race/progression")
  local verdict = score:GetItemValidityForContext("item:103", false, context)
  assert(verdict.valid, "owner's red tooltip or restrictions rejected the bot's gear: " .. verdict.code)
  assert(score:GetContextEquippedStatValue(context, "HIT") == 100, "cap read owner's equipped stats")
  local before = resolved
  assert(score:GetContextEquippedStatValue(context, "HIT") == 100 and resolved == before, "equipped totals were recomputed for every candidate")
  local owner = score:BuildRuleContext("WARRIOR", 1, 80)
  assert(score:GetItemValidityForContext("item:103", false, owner).code == "tooltip_subtype", "player tooltip restriction changed")
  assert(score:GetItemScoreForContext("item:103", context) < score:GetItemScoreForContext("item:103", owner), "target item/socket caps used owner totals")
  equipment.party1[9] = "item:102"
  local comparison = score:GetUpgradeComparisonForContext(9, items[103], context)
  assert(comparison.baselineScore == score:GetItemScoreForContext("item:101", context), "comparison read reused unit token or owner's equipment")
  assert(not comparison.isNewItem and score:GetContextItemLink(context, 17) == nil, "empty target slot fell back to owner")
  local saved = items[101]
  items[101] = nil
  assert(not score:GetUpgradeComparisonForContext(9, items[103], context), "missing baseline produced an upgrade comparison")
  items[101] = saved
  items[103].needs_exact_stats = true
  assert(not score:GetItemValidityForContext("item:103", false, context).final, "incomplete target candidate was accepted as final")
  local _, ready = score:GetItemScoreForContext("item:103", context)
  assert(not ready and not score:GetUpgradeComparisonForContext(9, items[103], context), "incomplete target candidate produced a score")
  items[103].needs_exact_stats = nil
  local _, offhand = score:GetValidSlots(items[104], context)
  assert(offhand == 17, "target dual wield used owner's capability")
  score.playerDualWield = true
  local noDual = score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {}, className = "Warrior", raceToken = "Tauren"})
  local _, forbiddenOffhand = score:GetValidSlots(items[104], noDual)
  assert(not forbiddenOffhand, "unknown target dual wield borrowed owner's capability")
  local hunter = score:BuildRuleContext("HUNTER", 1, 80, {equipped = {}, className = "Hunter", raceToken = "Tauren"})
  assert(score:GetItemValidityForContext("item:105", false, hunter).valid, "ranged family fallback used owner's caster class")
  items[103].ignore_for_gear = true
  assert(score:GetItemValidityForContext("item:103", false, context).code == "test_item", "generic item blocker was removed")
  items[103].ignore_for_gear = nil
  items[103].playerclass = "Mage"
  assert(score:GetItemValidityForContext("item:103", false, context).code == "class", "target class restriction was removed")
  items[103].playerclass, items[103].allowableRaceMask = "Warrior", 1
  assert(score:GetItemValidityForContext("item:103", false, context).code == "race", "target race restriction was removed")
  items[103].allowableRaceMask = 32
  assert(items[103].score == 987 and score.playerclass == "MAGE" and env.ZGV.db.char.gear_active_build == 1, "scoring changed owner/cached score")

  local upgrades = {EquippedItems = {[11] = {itemid = 106}, [12] = {}}, UniqueEquipped = {[7] = 1}}
  score.Upgrades, env.Upgrades = upgrades, upgrades
  function upgrades:GetItemUniqueness(id) if id == 106 or id == 107 then return 7, 1 end end
  run("local ItemScore, ZGV, Upgrades = ItemScore, ZGV, Upgrades\n"
    .. section(sources.upgrades, "local function get_ready_item_details", "local function is_bank_bagnum")
    .. section(sources.upgrades, "function Upgrades:CanUseUniqueItem", "local function is_protected_item"))
  local empty = score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {}, className = "Warrior", raceToken = "Tauren"})
  assert(not upgrades:CanUseUniqueItem("item:107", 12), "owner unique contract changed")
  assert(upgrades:CanUseUniqueItem("item:107", 12, empty), "owner unique family rejected empty target slots")
  local paired = score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {[11] = "item:106"}, className = "Warrior", raceToken = "Tauren"})
  assert(not upgrades:CanUseUniqueItem("item:107", 12, paired), "target unique family limit was ignored")
  assert(upgrades:CanUseUniqueItem("item:107", 11, paired), "target unique family replacement was rejected")
  function upgrades:GetItemUniqueness(id)
    if id == 106 or id == 107 then return 7, 1 end
    if id == 108 then return -108, 1 end
  end
  local weapons = score:BuildRuleContext("WARRIOR", 1, 80, {equipped = {[16] = "item:104", [17] = "item:108"}, playerDualWield = true, className = "Warrior", raceToken = "Tauren"})
  assert(not upgrades:CanUseUniqueItem("item:108", 16, weapons), "owner-cached slots hid the target's unique offhand")
  assert(upgrades:CanUseUniqueItem("item:108", 17, weapons), "target unique offhand could not replace itself")
  local pairScore = score:GetItemScoreForContext("item:104", weapons) + score:GetItemScoreForContext("item:108", weapons)
  assert(score:GetUpgradeComparisonForContext(16, items[109], weapons).baselineScore == pairScore, "two-hander ignored the target's equipped offhand")
  assert(score:GetUpgradeComparisonForContext(16, items[104], weapons, items[108]).baselineScore == pairScore, "weapon pair comparison ignored the target's equipment")
end
exercise(originals)
local mutations = {
  {"target class", "score", "context.playerclassName = subject.className or (subject.unit and UnitClass(subject.unit))", "context.playerclassName = self.playerclassName"},
  {"target race", "score", "context.playerraceToken = subject.raceToken or (subject.unit and select(2, UnitRace(subject.unit)))", "context.playerraceToken = self.playerraceToken"},
  {"target cap", "score", "context and context.subject and ItemScore:GetContextEquippedStatValue(context, statname) or ItemScore:GetEquippedStatValue(statname)", "ItemScore:GetEquippedStatValue(statname)"},
  {"target tooltip", "score", "if item.unusable_by_tooltip and not context.subject then", "if item.unusable_by_tooltip then"},
  {"snapshot baseline", "score", "if context and context.equipped then return context.equipped[slot] end", "if false then return context.equipped[slot] end"},
  {"target dual wield", "slots", "if context and context.subject then dualWield = context.playerDualWield end", "if false then dualWield = context.playerDualWield end"},
  {"target uniqueness", "upgrades", "if context and context.subject then", "if false then"},
  {"target unique slots", "upgrades", "if context and context.subject then slot_1, slot_2 = ItemScore:GetValidSlots(item, context) end", ""},
  {"two-handed baseline", "score", "if context and context.subject and newitem and newitem.twohander and slot == INVSLOT_MAINHAND and not secondnewitem then", "if false then"},
  {"pending target baseline", "score", "if not complete then return nil end", ""},
  {"pending target comparison", "score", "if not self:GetResolvedItemDetailsReady(link) then return nil end", ""},
  {"pending target validity", "score", "if not item or (context.subject and self:IsItemPendingResolution(item)) then", "if not item then"},
  {"pending target score", "score", 'if not item or (context and context.subject and self:IsItemPendingResolution(item)) then return -1, false, "no info yet" end', 'if not item then return -1, false, "no info yet" end'},
  {"selected target profile", "score", "if subject and classRules and classRules[buildNum] then resolvedBuild, usesFallback = buildNum, false end", ""},
}
for _, mutation in ipairs(mutations) do
  local sources = {score = originals.score, slots = originals.slots, upgrades = originals.upgrades}
  local text = sources[mutation[2]]
  local start = assert(text:find(mutation[3], 1, true), mutation[1])
  sources[mutation[2]] = text:sub(1, start - 1) .. mutation[4] .. text:sub(start + #mutation[3])
  assert(not pcall(exercise, sources), "fixture accepted " .. mutation[1] .. " mutation")
end
print("PASS: inspected target rules, immutable equipment, stat/socket caps, eligibility, dual wield and uniqueness")
