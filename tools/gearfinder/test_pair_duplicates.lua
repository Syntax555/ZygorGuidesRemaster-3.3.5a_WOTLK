-- Regression for one upgrade topping both slots of a ring, trinket or weapon pair.
-- Usage: lua tools/gearfinder/test_pair_duplicates.lua <addon directory>
local addon = assert(arg[1], "pass the addon directory")
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return (s:gsub("^\239\187\191", ""))
end
local function compile(source, name, env)
  if setfenv then local fn = assert(loadstring(source, name)); setfenv(fn, env); return fn end
  return assert(load(source, name, "t", env))
end
local source = read(addon.."/Item-GearFinder.lua")
local function section(first, last)
  local a = assert(source:find(first, 1, true), first)
  local b = assert(source:find(last, a + #first, true), last)
  return source:sub(a, b - 1)
end
local implementation =
  section("local slot_pairs = {", "local distinct_slot_pairs = {")..
  "return function()\n"..
  section("-- remove duplicates from primary/secondary slots", "enforce_distinct_pair_results(distinct_slot_pairs)")..
  "end\n"

local FINGER1, FINGER2 = 11, 12
local function dedupe(equipped, first_queue, second_queue)
  local env = setmetatable({
    INVSLOT_MAINHAND=16, INVSLOT_OFFHAND=17, INVSLOT_FINGER1=FINGER1, INVSLOT_FINGER2=FINGER2,
    INVSLOT_TRINKET1=13, INVSLOT_TRINKET2=14,
    ZGV={Debug=function() end},
    GearFinder={UpgradeQueue={[FINGER1]=first_queue, [FINGER2]=second_queue, [16]={}, [17]={}, [13]={}, [14]={}}},
    GF_Equipped=function(slot) return {itemlink=equipped[slot]} end,
    ItemScore={GetItemDetails=function(_, link) return link and {itemlink=link} or nil end},
  }, {__index=_G})
  compile(implementation, "pair duplicates", env)()()
  return first_queue[1], second_queue[1]
end

local shared, firstAlt, secondAlt = {name="shared"}, {name="first alternative"}, {name="second alternative"}

local first, second = dedupe({[FINGER1]="item:1"}, {shared, firstAlt}, {shared, secondAlt})
assert(first == firstAlt and second == shared, "an empty second slot must receive the shared upgrade")

first, second = dedupe({[FINGER2]="item:2"}, {shared, firstAlt}, {shared, secondAlt})
assert(first == shared and second == secondAlt, "an empty first slot must receive the shared upgrade")

first, second = dedupe({[FINGER1]="item:1", [FINGER2]="item:2"}, {shared, firstAlt}, {shared, secondAlt})
assert(first == shared and second == secondAlt, "filled slots keep the second slot's alternative")

first, second = dedupe({[FINGER1]="item:1", [FINGER2]="item:2"}, {shared}, {shared})
assert(first == shared and second == nil, "a single shared upgrade is suggested once")
print("PASS: shared pair upgrades fill an empty slot and are suggested once")
