local root=assert(arg[1],"addon root required")

local function fail(message) error(message,2) end
local captured={}
ZygorGuidesViewer={}
function ZygorGuidesViewer:RegisterGuide(title,options,rawdata)
	local guide={title=title,options=options or {},rawdata=rawdata or ""}
	captured[title]=guide
	return guide
end

local questTitle="Events Guides\\Brewfest\\Brewfest Quests"
local dailyTitle="Events Guides\\Brewfest\\Brewfest Dailies"
local harvestTitle="Events Guides\\Harvest Festival\\Harvest Festival Quest"
local factionGuides={}
local function captureFaction(faction,file)
	captured={}
	UnitFactionGroup=function() return faction end
	assert(loadfile(root..file))()
	factionGuides[faction]={quest=captured[questTitle],daily=captured[dailyTitle],harvest=captured[harvestTitle]}
end
captureFaction("Horde","/Guides/Retail/Events/ZygorEventsHordeCLASSIC.lua")
captureFaction("Alliance","/Guides/Retail/Events/ZygorEventsAllianceCLASSIC.lua")

for faction,guides in pairs(factionGuides) do
	if not guides.quest or not guides.daily then fail(faction.." Brewfest guides were not captured") end
	if guides.quest.rawdata:find("goaltype",1,true) then fail(faction.." quest guide still uses undefined goaltype()") end
	if guides.quest.rawdata:find("Blackrock Depths/0 0,0",1,true) then fail(faction.." quest guide still uses the 0,0 dungeon entry") end
	if guides.daily.rawdata:find("Blackrock Depths/0 0,0",1,true) then fail(faction.." daily guide still uses the 0,0 dungeon entry") end
	if not guides.quest.rawdata:find('complete zone("Blackrock Depths")',1,true) then fail(faction.." quest guide lacks zone completion") end
	if not guides.daily.rawdata:find('complete zone("Blackrock Depths")',1,true) then fail(faction.." daily guide lacks zone completion") end
end
if not factionGuides.Horde.harvest then fail("Horde Harvest Festival guide was not captured") end
if not factionGuides.Horde.quest.rawdata:find("Another Year, Another Souvenir.##13931",1,true) then fail("Horde current souvenir quest missing") end
if not factionGuides.Alliance.quest.rawdata:find("Another Year, Another Souvenir.##13932",1,true) then fail("Alliance current souvenir quest missing") end
if factionGuides.Horde.quest.rawdata:find("Goldark Snipehunter##23486",1,true) then fail("Horde guide still uses the Alliance Brewfest NPC") end
if not factionGuides.Horde.quest.rawdata:find("Glodrak Huntsniper##24657",1,true) then fail("Horde Brewfest NPC is missing") end
for faction,guides in pairs(factionGuides) do
	if not guides.quest.rawdata:find("Alcohol-Free Brewfest Sampler##33096 |n",1,true) then fail(faction.." sampler acquisition check is missing") end
	if not guides.quest.rawdata:find("Self-Turning and Oscillating Utility Target##24108",1,true) then fail(faction.." S.T.O.U.T. target is missing") end
end
local hordeQuest=factionGuides.Horde.quest.rawdata
if not hordeQuest:find("path\t46.58,20.18\t47.57,22.80\t48.96,28.09",1,true) then fail("Horde outbound keg route is missing") end
if not hordeQuest:find("path\t47.57,22.80\t46.58,20.18\t46.32,15.27",1,true) then fail("Horde return keg route is missing") end
if not hordeQuest:find("|q 11412/1 |n |until questobjective(11412,1)",1,true) then fail("Horde keg route does not repeat until delivery completion") end
if not factionGuides.Alliance.quest.rawdata:find("Click Here Once 3 Kegs Have Been Delivered |confirm |or",1,true) then fail("Alliance ram-delivery fallback is missing") end
local souvenirAccept=assert(hordeQuest:find("accept Another Year, Another Souvenir.##13931",1,true))
local souvenirTurnin=assert(hordeQuest:find("turnin Another Year, Another Souvenir.##13931",1,true))
local chugAccept=assert(hordeQuest:find("accept Chug and Chuck!##12191",1,true))
if not (souvenirAccept < souvenirTurnin and souvenirTurnin < chugAccept) then fail("Horde souvenir turn-in is not immediately after acceptance") end
if not hordeQuest:find("talk Blix Fixwidget##24495",1,true) then fail("Horde souvenir turn-in must remain with Blix Fixwidget") end
if hordeQuest:find("|only if haveq(13931) or completedq(13931)",1,true) then fail("Horde souvenir turn-in still has the fragile step condition") end
if factionGuides.Alliance.quest.rawdata:find("|only if haveq(13932) or completedq(13932)",1,true) then fail("Alliance souvenir turn-in still has the fragile step condition") end
for _,route in ipairs({
	"Arrive outside Undercity |goto Tirisfal Glades/0 61.87,64.99",
	"Go to the Orb of Translocation |goto Undercity/0 54.90,11.30",
	"Go to the Silvermoon City Exit |goto Silvermoon City/0 57.16,48.92",
	"Go to the Orb of Translocation |goto Silvermoon City/0 49.50,14.80",
	"Ride the Zeppelin to Durotar",
	"label \"Dalaran_To_Thunder_Bluff\"",
	"Go to the Thunder Bluff Portal |goto Dalaran/1 57.25,22.37",
	"Fly to Thunder Bluff",
	"label \"Mulgore_Brewfest_Camp\"",
	"Go to the Thunder Bluff Elevators |goto Thunder Bluff/0 33.09,65.37",
	"label \"Dalaran_To_Orgrimmar\"",
	"Go to the Orgrimmar Portal |goto Dalaran/1 55.55,25.66",
	"label \"Thunder_Bluff_Return\"",
	"Go to the Thunder Bluff Elevators |goto Thunder Bluff/0 31.81,66.06",
	"talk Tal##2995 |goto Thunder Bluff/0 46.78,50.02",
	"Fly to Orgrimmar",
	"use the Dungeon Finder to queue directly for Coren Direbrew",
}) do
	if not factionGuides.Horde.quest.rawdata:find(route,1,true) then fail("Horde travel route is missing: "..route) end
end
for faction,guides in pairs(factionGuides) do
	local raw=guides.quest.rawdata
	if raw:find("Remove the Synthebrew Goggles and Re%-Equip your Helm |confirm") then fail(faction.." still uses manual goggles-removal confirmation") end
	local _,autoRemovals=raw:gsub("complete not equippeditem%(46735%)","")
	if autoRemovals<4 then fail(faction.." does not auto-detect all goggles-removal steps") end
end

local harvest=factionGuides.Horde.harvest.rawdata
local tribute=assert(harvest:find("use Grom's Tribute##19851",1,true))
local outbound=harvest:sub(1,tribute)
if not outbound:find("Follow the path |goto Ashenvale 84.20,72.05 < 20 |only if walking",1,true) then fail("Harvest Festival final approach is missing") end
if outbound:find("73.51,63.53",1,true) or outbound:find("75.62,65.88",1,true) then fail("Harvest Festival still forces the western approach points") end
if outbound:find("path follow smart",1,true) then fail("Harvest Festival relies on an unsupported smart-path option") end

tinsert=table.insert
loadstring=loadstring or load
if not setfenv then
	function setfenv(func,environment)
		local index=1
		while true do
			local name=debug.getupvalue(func,index)
			if name=="_ENV" then debug.upvaluejoin(func,index,function() return environment end,1) break
			elseif not name then break end
			index=index+1
		end
		return func
	end
end
function TableKeys(tbl) local keys={} for key in pairs(tbl or {}) do keys[#keys+1]=key end return keys end
function ZygorGuidesViewer_L() return setmetatable({coords="%s,%s"},{__index=function(_,key) return key end}) end

local ZGV=ZygorGuidesViewer
ZGV.BZL={}
ZGV.BSZL={}
ZGV.BFL={}
ZGV.StandingNamesEngRev={}
ZGV.dailyQuests={}
ZGV.instantQuests={}
ZGV.completedQuests={}
ZGV.StepProto_mt={}
ZGV.GoalProto_mt={}
ZGV.db={char={fakelevel=0}}
function ZGV:GetQuestName() return nil end
function ZGV:RaceClassMatch() return true end
GetRealZoneText=function() return "Durotar" end
GetZoneText=function() return "Durotar" end
GetSubZoneText=function() return "" end
GetMinimapZoneText=function() return "" end
UnitLevel=function() return 80 end
GetNumQuestLogEntries=function() return 0 end
GetItemCount=function() return 0 end
local equipped={}
GetInventoryItemLink=function(_,slot) return equipped[slot] end

assert(loadfile(root.."/Parser.lua"))()
local hordeKegStep
local unequipConditions={}
local hordeDailyResetCondition
for faction,guides in pairs(factionGuides) do
	for kind,guide in pairs(guides) do
		local parsed,err,line,linedata=ZGV:ParseEntry(guide.rawdata)
		if not parsed then fail(("%s %s guide parse failed: %s (line %s: %s)"):format(faction,kind,tostring(err),tostring(line),tostring(linedata))) end
		if faction=="Horde" and kind=="quest" then
			for _,step in ipairs(parsed.steps) do
				if step.condition_until_raw=="questobjective(11412,1)" then hordeKegStep=step break end
			end
		end
		if faction=="Horde" and kind=="daily" then
			for _,step in ipairs(parsed.steps) do
				for _,goal in ipairs(step.goals) do
					if goal.condition_complete_raw=="not completedq(11408,11407,12020)" then
						hordeDailyResetCondition=goal.condition_complete
						break
					end
				end
				if hordeDailyResetCondition then break end
			end
		end
		if kind=="quest" then
			local equipped
			for _,step in ipairs(parsed.steps) do
				for _,goal in ipairs(step.goals) do
					if goal.action=="equipped" and goal.itemid==46735 then equipped=goal break end
				end
				if equipped then break end
			end
			if not equipped then fail(faction.." Synthebrew equipped goal was not parsed") end
			if equipped.slot then fail(faction.." Synthebrew equipped goal should scan all inventory slots") end
			if equipped.item~="Synthebrew Goggles" then fail(faction.." Synthebrew equipped goal retained an invalid item name") end
			for _,step in ipairs(parsed.steps) do
				for _,goal in ipairs(step.goals) do
					if goal.condition_complete_raw=="not equippeditem(46735)" then
						unequipConditions[#unequipConditions+1]=goal.condition_complete
					end
				end
			end
		end
	end
end

if not hordeKegStep or not hordeKegStep.condition_until then fail("Horde keg exit condition was not parsed") end
ZGV.questsbyid={[11412]={complete=false,goals={{num=2,needed=3,complete=false}}}}
local ok,result=pcall(hordeKegStep.condition_until)
if not ok then fail("Horde keg exit condition failed at runtime: "..tostring(result)) end
if result then fail("Horde keg route exited before 3/3") end
ZGV.questsbyid[11412].goals[1].num=3
ok,result=pcall(hordeKegStep.condition_until)
if not ok then fail("Horde keg completed exit condition failed at runtime: "..tostring(result)) end
if not result then fail("Horde keg route did not exit at 3/3") end

if not hordeDailyResetCondition then fail("Horde daily reset condition was not parsed") end
ZGV.completedQuests={}
ok,result=pcall(hordeDailyResetCondition)
if not ok or not result then fail("Horde daily reset condition did not activate before any alternative quest was completed") end
ZGV.completedQuests={[12020]=true}
ok,result=pcall(hordeDailyResetCondition)
if not ok or result then fail("Horde daily reset condition ignored completion of its third alternative quest") end

if #unequipConditions<8 then fail("Parsed guides are missing automatic goggles-removal conditions") end
equipped[1]="|cff0070dd|Hitem:46735:0:0:0:0:0:0:0:80|h[Synthebrew Goggles]|h|r"
ok,result=pcall(unequipConditions[1])
if not ok then fail("Goggles-removal condition failed while equipped: "..tostring(result)) end
if result then fail("Goggles-removal condition completed while the goggles were equipped") end
equipped[1]=nil
ok,result=pcall(unequipConditions[1])
if not ok then fail("Goggles-removal condition failed after unequipping: "..tostring(result)) end
if not result then fail("Goggles-removal condition did not complete after unequipping") end

print("Brewfest guide regression passed")
