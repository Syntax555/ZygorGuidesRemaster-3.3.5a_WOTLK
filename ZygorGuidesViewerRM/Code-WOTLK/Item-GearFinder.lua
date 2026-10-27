local ZGV = ZygorGuidesViewer
if not (ZGV and ZGV.ItemScore and ZGV.ItemScore.GearFinder) then return end
local GearFinder = ZGV.ItemScore.GearFinder

local function SetCharacterHeaderShown(shown)
	local method = shown and "Show" or "Hide"
	local frames = {
		_G.CharacterNameText,
		_G.CharacterFramePortrait,
		_G.CharacterFrameCloseButton,
	}
	for _,frame in ipairs(frames) do
		if frame and frame[method] then
			frame[method](frame)
		end
	end
end

GearFinder.PAST_DUNGEONS_LIMIT = 10 -- match retail-style finder focus; ignore far-obsolete dungeons sooner
GearFinder.FUTURE_DUNGEONS_LIMIT = 5 -- how many levels to look ahead for future upgrades

function GearFinder:Initialise()
	GearFinder:CreateMainFrame()
	GearFinder:UpdateSystemTab()

	GearFinder.MainFrame:SetScript("OnHide",function()
		if GearFinder.InspectUnit then
			GearFinder.InspectUnit, GearFinder.InspectGuid = nil, nil
			GearFinder:ReleaseTarget()
			return
		end
		SetCharacterHeaderShown(true)
		-- Restore the character tab that was active before
		if not GearFinder.ClosingCharacterFrame and PaperDollFrame then PaperDollFrame:Show() end
		GearFinder.ClosingCharacterFrame = nil
	end)

	GearFinder:AttachInspectFrame()
	GearFinder:AttachCombatProfileHook()
	GearFinder:AttachInspectDataHook()
	if ZGV.AddEvent and not GearFinder.InspectEventsHooked then
		ZGV:AddEvent("ADDON_LOADED", function(_, _, name)
			if name == "Blizzard_InspectUI" then GearFinder:AttachInspectFrame() end
			if name == "MultiBot" then GearFinder:AttachCombatProfileHook() end
			if name == "DragonUI" then GearFinder:AttachInspectDataHook() end
		end)
		for _, event in ipairs({"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"}) do
			ZGV:AddEvent(event, function()
				if GearFinder.RefreshInspectButton then GearFinder.RefreshInspectButton() end
			end)
		end
		ZGV:AddEvent("UNIT_INVENTORY_CHANGED", function(_, _, unit)
			if GearFinder.InspectUnit and GearFinder.MainFrame:IsVisible()
				and UnitGUID(unit) == GearFinder.InspectGuid then
				GearFinder:QueueInspectRefresh()
			end
		end)
		GearFinder.InspectEventsHooked = true
	end

	if not GearFinder.ToggleCharacterHooked and ToggleCharacter and hooksecurefunc then
		hooksecurefunc("ToggleCharacter", function()
			if not GearFinder.InspectUnit and GearFinder.MainFrame and GearFinder.MainFrame:IsShown() then
				GearFinder.ClosingCharacterFrame = true
				GearFinder.MainFrame:Hide()
				if CharacterFrame and CharacterFrame:IsShown() and HideUIPanel then
					HideUIPanel(CharacterFrame)
				end
			end
		end)
		GearFinder.ToggleCharacterHooked = true
	end
end

local L = ZGV.L
local G = _G
local FONT=ZGV.Font
local FONTBOLD=ZGV.FontBold
local CHAIN = ZGV.ChainCall
local ui = ZGV.UI
local SkinData = ui and ui.SkinData

local tinsert,tremove,print,ipairs,pairs,wipe,debugprofilestop=tinsert,tremove,print,ipairs,pairs,wipe,debugprofilestop
local completedQuestsCache = {}
local function IsQuestFlaggedCompleted(questID)
	if _G.IsQuestFlaggedCompleted then
		return _G.IsQuestFlaggedCompleted(questID)
	end
	if GetQuestsCompleted then
		wipe(completedQuestsCache)
		GetQuestsCompleted(completedQuestsCache)
		return completedQuestsCache[questID] and true or false
	end
	return false
end

local ItemScore = ZGV.ItemScore

local PAST_DUNGEONS_LIMIT = 30 -- how many levels can user be above min level before we start ignoring its dungeon
local FUTURE_DUNGEONS_LIMIT = 5 -- how many levels to look ahead for future upgrades

-- support function for character frame system tab creation
local function OnNonZygorClick()
	if GearFinder.MainFrame:IsVisible() then
		SetCharacterHeaderShown(true)
		GearFinder.MainFrame:Hide()
	end
end

local function CreateLaunchButton(parent, onClick)
	local frame = CHAIN(ZGV.CreateFrameWithBG("FRAME",nil,parent))
		:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -40, -12)
		:SetSize(50,50)
		:SetBackdrop({bgFile="Interface\\Minimap\\MiniMap-TrackingBorder"})--,tile=true, tileSize=50})
		:SetFrameLevel(610)
		:Show()
	.__END

	local button = CHAIN(ZGV.CreateFrameWithBG("Button", nil , frame))
		:SetSize(20,20)
		:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
		:SetBackdrop({bgFile=ZGV.DIR.."\\Skins\\zglogo-back"})
		:SetNormalTexture(ZGV.DIR.."\\Skins\\zglogo")
		:SetFrameLevel(611)
		:SetScript("OnClick", onClick)
		:SetScript("OnEnter",function(self) 
			CHAIN(GameTooltip):SetOwner(self, "ANCHOR_TOP") 
			:SetText("Zygor " .. (L["gearfinder_title"] or "Gear Finder"))
			:Show() 
			end)
		:SetScript("OnLeave",function(self) GameTooltip:Hide() end)
		:Show()
	.__END
	button:GetNormalTexture():SetTexCoord(0,0,0,1/4 , 1,0,1,1/4)
	return frame, button
end

function GearFinder:AttachFrame()
	self.PaperDollButtonFrame, self.PaperDollButton = CreateLaunchButton(PaperDollFrame,
		function() GearFinder:ShowFinder() end)
end

function GearFinder:UpdateSystemTab()
	local enabled = ZGV.db and ZGV.db.profile and ZGV.db.profile.autogear
	if GearFinder.RefreshInspectButton then GearFinder.RefreshInspectButton() end
	if enabled then
		if GearFinder.PaperDollButtonFrame then GearFinder.PaperDollButtonFrame:Show() end
	else
		if GearFinder.PaperDollButtonFrame then GearFinder.PaperDollButtonFrame:Hide() end
		if GearFinder.MainFrame then GearFinder.MainFrame:Hide() end
	end
end

local function inspectedUnit()
	local unit = InspectFrame and InspectFrame.unit
	if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") or not UnitIsPlayer(unit)
		or not CanInspect(unit) then return nil end
	if UnitInParty and UnitInRaid and not (UnitInParty(unit) or UnitInRaid(unit)) then return nil end
	local name = UnitName(unit)
	if MultiBot and type(MultiBot.isActive) == "function" and not MultiBot.isActive(name) then return nil end
	return unit
end

function GearFinder:QueueInspectRefresh(force)
	local context, unit, guid = self.Context, self.InspectUnit, self.InspectGuid
	if not context or not unit or not self.MainFrame:IsVisible() then return end
	self.InspectRefreshForced = self.InspectRefreshForced or force
	if self.InspectRefreshTimer then return end
	local timer
	timer = ZGV:ScheduleTimer(function()
		if self.InspectRefreshTimer ~= timer then return end
		local forced = self.InspectRefreshForced
		self.InspectRefreshTimer, self.InspectRefreshForced = nil, nil
		if self.Context ~= context or self.InspectGuid ~= guid or not self.MainFrame:IsVisible() then return end
		if unit ~= inspectedUnit() or UnitGUID(unit) ~= guid then self.MainFrame:Hide() return end
		if not self:TargetEquipmentReady(unit) then return end
		if not forced and self:IsTargetSnapshotCurrent(unit) then return end
		if not self:BindTarget(unit, true) then self.MainFrame:Hide() return end
		self:ScoreDungeonItems()
	end, 0.1)
	self.InspectRefreshTimer = timer
end

function GearFinder:AttachCombatProfileHook()
	local comm = MultiBot and MultiBot.Comm
	if self.CombatProfileHooked or not (comm and comm.FinishCombatProfileRequest and hooksecurefunc) then return end
	hooksecurefunc(comm, "FinishCombatProfileRequest", function(_, result)
		local context = GearFinder.Context
		if context and type(result) == "table" and result.status == "ok" and type(result.botName) == "string"
			and string.lower(result.botName) == string.lower(context.name)
			and type(result.effective) == "string" and result.effective ~= ""
			and result.effective ~= context.ip.profile then GearFinder:QueueInspectRefresh(true) end
	end)
	self.CombatProfileHooked = true
end

function GearFinder:AttachInspectDataHook()
	if self.InspectDataHooked or not (DragonUI and DragonUI.RegisterInspectDataCallback and DragonUI.IsInspectDataFor) then return end
	DragonUI:RegisterInspectDataCallback(function(ownerGUID)
		local context = GearFinder.Context
		if not context or not GearFinder.MainFrame:IsVisible() then return end
		if ownerGUID == GearFinder.InspectGuid then
			GearFinder:QueueInspectRefresh(true)
		elseif not ownerGUID then
			context.equipmentReady, context.ruleReady = false, nil
			GearFinder:ClearResults()
			GearFinder:ShowItemInfoLoadingMessage()
		end
	end)
	self.InspectDataHooked = true
end

function GearFinder:AttachInspectFrame()
	if not InspectFrame or not InspectPaperDollFrame or self.InspectButton then return end
	local frame, button = CreateLaunchButton(InspectPaperDollFrame,
		function() GearFinder:ShowInspectFinder(inspectedUnit()) end)
	self.InspectButtonFrame, self.InspectButton = frame, button
	local function refresh()
		local unit = inspectedUnit()
		local enabled = ZGV.db and ZGV.db.profile and ZGV.db.profile.autogear
		if enabled and unit then frame:Show() else frame:Hide() end
		if GearFinder.InspectUnit and (not unit or UnitGUID(unit) ~= GearFinder.InspectGuid) then
			GearFinder.MainFrame:Hide()
		end
	end
	self.RefreshInspectButton = refresh
	InspectFrame:HookScript("OnShow", refresh)
	InspectPaperDollFrame:HookScript("OnShow", refresh)
	InspectPaperDollFrame:HookScript("OnHide", function()
		if GearFinder.InspectUnit then GearFinder.MainFrame:Hide() end
	end)
	if InspectFrame_UnitChanged and hooksecurefunc then hooksecurefunc("InspectFrame_UnitChanged", refresh) end
	refresh()
end

function GearFinder:ShowInspectFinder(unit)
	if not unit or unit ~= inspectedUnit() then return end
	if not InspectPaperDollFrame:IsVisible() then return end
	if not (ZGV.db and ZGV.db.profile and ZGV.db.profile.autogear) then return end
	if self.InspectGuid == UnitGUID(unit) and self.MainFrame:IsVisible() then self.MainFrame:Hide() return end
	self.MainFrame:Hide()
	if not self:BindTarget(unit) then
		ZGV:Print("Gear Finder for inspected bots is unavailable. Check the server connection and use the matching server update.")
		return
	end
	self.InspectUnit, self.InspectGuid = unit, UnitGUID(unit)
	self.MainFrame:SetParent(InspectFrame)
	self.MainFrame:ClearAllPoints()
	self.MainFrame:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT")
	self.MainFrame:SetFrameLevel(InspectFrame:GetFrameLevel() + 10)
	self.MainFrame.Title:SetText("Zygor " .. (L["gearfinder_title"] or "Gear Finder") .. " - " .. UnitName(unit))
	self.MainFrame:Show()
	self:ScoreDungeonItems()
end

function GearFinder:ShowFinder()
	if not (ZGV.db and ZGV.db.profile and ZGV.db.profile.autogear) then
		GearFinder:UpdateSystemTab()
		return
	end
	local wasInspect = GearFinder.InspectUnit ~= nil
	if wasInspect then GearFinder.MainFrame:Hide() end
	GearFinder:ReleaseTarget()
	if not wasInspect and ZygorGearFinder and ZygorGearFinder:IsVisible() then GearFinder.MainFrame:Hide() return end
	GearFinder.MainFrame:SetParent(CharacterFrame)
	GearFinder.MainFrame:ClearAllPoints()
	GearFinder.MainFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT")
	GearFinder.MainFrame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 10)
	GearFinder.MainFrame.Title:SetText("|cffffff88Z|cffffee66y|cffffdd44g|cffffcc22o|cffffbb00r|r Guides Gear Finder")

	if CharacterFrame and not CharacterFrame:IsShown() and ToggleCharacter then
		ToggleCharacter("PaperDollFrame")
	end

	-- DragonUI's custom tabs also use the native subframe switch.
	if not GearFinder.HookedChar then
		if hooksecurefunc and _G.CharacterFrame_ShowSubFrame then
			hooksecurefunc("CharacterFrame_ShowSubFrame", function()
				if not GearFinder.InspectUnit and GearFinder.MainFrame and GearFinder.MainFrame:IsVisible() then
					GearFinder.ClosingCharacterFrame = true
					SetCharacterHeaderShown(true)
					GearFinder.MainFrame:Hide()
				end
			end)
		end
		GearFinder.HookedChar = true
	end

	-- Hide ALL character frame sub-panels
	SetCharacterHeaderShown(false)
	if PaperDollFrame then PaperDollFrame:Hide() end
	if SkillFrame then SkillFrame:Hide() end
	if ReputationFrame then ReputationFrame:Hide() end
	if PetPaperDollFrame then PetPaperDollFrame:Hide() end
	if TokenFrame then TokenFrame:Hide() end
	if PVPFrame then PVPFrame:Hide() end

	for i=1,(CharacterFrame.numTabs or 5) do
		local tab = _G["CharacterFrameTab"..i]
		if tab then PanelTemplates_DeselectTab(tab) end
	end

	if ItemScore and ItemScore.Upgrades and ItemScore.Upgrades.ScoreEquippedItems then
		if ItemScore.EnsureActiveRuleSet then
			ItemScore:EnsureActiveRuleSet()
		elseif not ItemScore.ActiveRuleSet and ItemScore.SetStatWeights then
			ItemScore:SetStatWeights()
		end
		if not ItemScore.Upgrades.ScoredEquippedItems then
			ItemScore.Upgrades:ScoreEquippedItems()
		end
	end

	ZygorGearFinder:Show()
	GearFinder:ScoreDungeonItems()
end
