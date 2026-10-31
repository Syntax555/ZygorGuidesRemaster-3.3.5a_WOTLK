-- Regression for the class quests that teach a lesson trainers withhold before Wrath:
-- the warrior's Intercept from The Affray and the paladin's Sense Undead from The Tome of
-- Valor or, for blood elves, Return to Silvermoon. The active leveling guides must lead
-- each class through its chain in order, and only that class.
-- Usage: lua tools/guides/test_class_lessons.lua <addon directory>
local root = arg[1] or "ZygorGuidesViewerRM"

local function fail(message)
	error(message,2)
end

local byTitle={}
ZygorGuidesViewer={IMAGESDIR=""}
function ZygorGuidesViewer:RegisterGuide(title,options,rawdata)
	if type(options)=="string" and rawdata==nil then
		rawdata=options
		options={}
	end
	local guide={title=title,options=options or {},rawdata=rawdata or ""}
	byTitle[title]=guide
	return guide
end

local faction="Alliance"
UnitFactionGroup=function() return faction end
level=20
raceclass=function() return true end

-- Guides/Autoload.xml loads these leveling files; each registers only for its faction.
assert(loadfile(root.."/Guides/Leveling/ZygorGuidesAlliance.lua"))()
faction="Horde"
assert(loadfile(root.."/Guides/Leveling/ZygorGuidesHorde.lua"))()

tinsert=table.insert
loadstring=loadstring or load
if not setfenv then
	function setfenv(func,environment)
		local index=1
		while true do
			local name=debug.getupvalue(func,index)
			if name=="_ENV" then
				debug.upvaluejoin(func,index,function() return environment end,1)
				break
			elseif not name then
				break
			end
			index=index+1
		end
		return func
	end
end
function TableKeys(tbl)
	local keys={}
	for key in pairs(tbl or {}) do keys[#keys+1]=key end
	return keys
end
function ZygorGuidesViewer_L()
	return setmetatable({coords="%s,%s"},{__index=function(_,key) return key end})
end

local ZGV=ZygorGuidesViewer
ZGV.BZL={}
ZGV.BSZL={}
ZGV.BFL={}
ZGV.StandingNamesEngRev={}
ZGV.dailyQuests={}
ZGV.instantQuests={}
ZGV.StepProto_mt={}
ZGV.GoalProto_mt={}
function ZGV:GetQuestName() return nil end
function ZGV:RaceClassMatch() return true end
GetRealZoneText=function() return "Test Zone" end

assert(loadfile(root.."/Parser.lua"))()

local chains={
	{
		guide="Zygor's Alliance Leveling Guides\\Levels (20-25)",
		class="Paladin",
		actions={{"accept",1650},{"turnin",1650},{"accept",1651},{"turnin",1651},{"accept",1652},{"turnin",1652}},
	},
	{
		guide="Zygor's Horde Leveling Guides\\Levels (20-25)",
		class="BloodElf Paladin",
		actions={{"accept",9690},{"turnin",9690},{"accept",9686},{"turnin",9686},{"accept",9691},{"turnin",9691}},
	},
	{
		guide="Zygor's Alliance Leveling Guides\\Levels (30-35)",
		class="Warrior",
		actions={{"accept",1718},{"turnin",1718},{"accept",1719},{"turnin",1719}},
	},
	{
		guide="Zygor's Horde Leveling Guides\\Levels (30-35)",
		class="Warrior",
		actions={{"accept",1718},{"turnin",1718},{"accept",1719},{"turnin",1719}},
	},
}

local function restricted(step,class)
	if not step.requirement then return false end
	local requirements=type(step.requirement)=="table" and step.requirement or {step.requirement}
	for _,requirement in ipairs(requirements) do
		if not tostring(requirement):find(class.."$") then return false end
	end
	return #requirements>0
end

for _,chain in ipairs(chains) do
	local guide=byTitle[chain.guide]
	if not guide then fail("missing guide "..chain.guide) end
	local parsed,err,line,linedata=ZGV:ParseEntry(guide.rawdata)
	if not parsed then
		fail(("could not parse %s: %s (line %s: %s)"):format(chain.guide,tostring(err),tostring(line),tostring(linedata)))
	end
	local next=1
	for _,step in ipairs(parsed.steps) do
		for _,goal in ipairs(step.goals or {}) do
			local want=chain.actions[next]
			if want and goal.action==want[1] and goal.questid==want[2] then
				if not restricted(step,chain.class) then
					fail(("%s: %s %d is not limited to %s"):format(chain.guide,want[1],want[2],chain.class))
				end
				next=next+1
			end
		end
	end
	if next<=#chain.actions then
		local want=chain.actions[next]
		fail(("%s: %s quest %d is missing or out of order"):format(chain.guide,want[1],want[2]))
	end
end

print("Class lesson chain regression passed")
