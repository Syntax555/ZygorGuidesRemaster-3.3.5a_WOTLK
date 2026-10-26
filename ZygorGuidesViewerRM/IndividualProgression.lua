-- Individual Progression: the character's own earned tier and the server's
-- quest, giver and instance gates, read from the MultiBot Bridge. Guides, the
-- Gear Finder, the Gold Guide and the Talent Advisor ask this module before
-- they treat later content as available. An unknown state never unlocks.
local ZGV = ZygorGuidesViewer
if not ZGV then return end

local IP = {
	quests = {},         -- questId -> {status, reasons, tier, generation, at}
	queued = {},         -- questIds waiting for the next request
	inflight = {},       -- questIds asked and not answered yet
	requests = {},       -- token -> pending request
	warned = {},         -- guide titles already reported as locked
	generation = 1,
	sequence = 0,
}
ZGV.IP = IP

local PREFIX = "MBOT"
local CAPABILITY = "IP_PROGRESS_V1"
local HELLO_TIMEOUT = 3
local HELLO_RETRY = 30
local HELLO_RETRIES = 3
local WATCH_RENEW = 60
local REQUEST_TIMEOUT = 10
local FLUSH_DELAY = 0.25
local ACCESS_REFRESH = 10
local REPEAT_TTL = 600
local MAX_MESSAGE = 240
local MAX_BATCH = 32
-- The bridge accepts 20 requests per character in two seconds; long skips
-- through a guide spread their quest batches over several flushes.
local MAX_FLUSH_BATCHES = 6
local FLUSH_INTERVAL = 1

-- Reasons the server reports for an unavailable quest. The blocking ones stay
-- in force under this character's current progression or permanent character
-- rules; the others resolve through ordinary play and keep the step.
IP.REASON = {
	DISABLED = 0x1, CLASS = 0x2, RACE = 0x4, LEVEL_LOW = 0x8, LEVEL_HIGH = 0x10, SKILL = 0x20,
	REPUTATION = 0x40, PREVIOUS = 0x80, TIMED = 0x100, EXCLUSIVE = 0x200, NEXT_CHAIN = 0x400,
	PREV_CHAIN = 0x800, BREADCRUMB_DONE = 0x1000, BREADCRUMB_ACTIVE = 0x2000, REPEAT = 0x4000,
	CONDITIONS = 0x8000, TIER = 0x10000, GIVER_HIDDEN = 0x20000, LOG_FULL = 0x40000,
}
local R = IP.REASON
IP.BLOCKING = R.DISABLED + R.CLASS + R.RACE + R.LEVEL_HIGH + R.EXCLUSIVE + R.NEXT_CHAIN +
	R.BREADCRUMB_DONE + R.TIER + R.GIVER_HIDDEN
local REASON_ORDER = {"TIER", "GIVER_HIDDEN", "DISABLED", "CLASS", "RACE", "LEVEL_LOW", "LEVEL_HIGH", "SKILL",
	"REPUTATION", "PREVIOUS", "TIMED", "EXCLUSIVE", "NEXT_CHAIN", "PREV_CHAIN", "BREADCRUMB_DONE",
	"BREADCRUMB_ACTIVE", "REPEAT", "CONDITIONS", "LOG_FULL"}

-- Transition quests that decide progression; the player accepts and turns them in.
IP.MANUAL_QUESTS = { [8743]=true, [108743]=true, [108744]=true, [10259]=true }

-- The strict default milestone chain, for display; the server decides each step.
IP.MILESTONES = {
	[1]  = {npc=11502, name="Ragnaros", zone="Molten Core"},
	[2]  = {npc=10184, name="Onyxia", zone="Onyxia's Lair"},
	[3]  = {npc=11583, name="Nefarian", zone="Blackwing Lair"},
	[4]  = {quest=8743, name="Bang a Gong!"},
	[5]  = {quest=108744, name="Chaos and Destruction"},
	[6]  = {npc=15727, name="C'Thun", zone="Ahn'Qiraj"},
	[7]  = {npc=15990, name="Kel'Thuzad", zone="Naxxramas"},
	[8]  = {quest=10259, name="Into the Breach"},
	[9]  = {npc=15690, name="Prince Malchezaar", zone="Karazhan"},
	[10] = {npc=19622, name="Kael'thas Sunstrider", zone="Tempest Keep"},
	[12] = {npc=22917, name="Illidan Stormrage", zone="Black Temple"},
	[13] = {npc=25315, name="Kil'jaeden", zone="Sunwell Plateau"},
	[14] = {npc=15990, name="Kel'Thuzad", zone="Naxxramas"},
	[15] = {npc=33288, name="Yogg-Saron", zone="Ulduar"},
	[16] = {npc=34564, name="Anub'arak", zone="Trial of the Crusader"},
	[17] = {npc=36597, name="The Lich King", zone="Icecrown Citadel"},
	[18] = {npc=39863, name="Halion", zone="The Ruby Sanctum"},
}

-- Tiers of Individual Progression's continent and zone gates.
IP.REGIONS = {
	["Hellfire Peninsula"]=8, ["Zangarmarsh"]=8, ["Terokkar Forest"]=8, ["Nagrand"]=8,
	["Blade's Edge Mountains"]=8, ["Netherstorm"]=8, ["Shadowmoon Valley"]=8, ["Shattrath City"]=8,
	["Stattrath City"]=8, ["Isle of Quel'Danas"]=12,
	["Northrend"]=13, ["Borean Tundra"]=13, ["Howling Fjord"]=13, ["Dragonblight"]=13, ["Grizzly Hills"]=13,
	["Zul'Drak"]=13, ["Sholazar Basin"]=13, ["Crystalsong Forest"]=13, ["The Storm Peaks"]=13,
	["Storm Peaks"]=13, ["Icecrown"]=13, ["Wintergrasp"]=13, ["Dalaran"]=13, ["Hrothgar's Landing"]=13,
}
-- The TBC race starting zones open before tier 8 for Draenei and Blood Elves.
-- Other races also need an account unlock there, which this client cannot see.
IP.TBC_RACE_ZONES = {
	["Eversong Woods"]=true, ["Ghostlands"]=true, ["Silvermoon City"]=true, ["Azuremyst Isle"]=true,
	["Bloodmyst Isle"]=true, ["The Exodar"]=true, ["Exodar"]=true, ["Ammen Vale"]=true, ["The Veiled Sea"]=true,
}
IP.TBC_RACES = { Draenei=true, BloodElf=true }

-- Instance names as guides and the Gear Finder use them, with their server map.
IP.INSTANCES = {
	["Ragefire Chasm"]=389, ["Wailing Caverns"]=43, ["The Deadmines"]=36, ["Deadmines"]=36,
	["Shadowfang Keep"]=33, ["Blackfathom Deeps"]=48, ["The Stockade"]=34, ["Stormwind Stockade"]=34,
	["Gnomeregan"]=90, ["Razorfen Kraul"]=47, ["Scarlet Monastery"]=189, ["Razorfen Downs"]=129,
	["Uldaman"]=70, ["Zul'Farrak"]=209, ["Maraudon"]=349, ["The Temple of Atal'Hakkar"]=109,
	["Sunken Temple"]=109, ["Blackrock Depths"]=230, ["Blackrock Spire"]=229, ["Lower Blackrock Spire"]=229,
	["Upper Blackrock Spire"]=229, ["Dire Maul"]=429, ["Stratholme"]=329, ["Scholomance"]=289,
	["Molten Core"]=409, ["Onyxia's Lair"]=249, ["Onyxia"]=249, ["Blackwing Lair"]=469, ["Zul'Gurub"]=309,
	["The Ruins of Ahn'Qiraj"]=509, ["Ruins of Ahn'Qiraj"]=509, ["The Temple of Ahn'Qiraj"]=531,
	["Temple of Ahn'Qiraj"]=531, ["Ahn'Qiraj"]=531, ["Naxxramas"]=533,
	["Hellfire Ramparts"]=543, ["The Blood Furnace"]=542, ["Blood Furnace"]=542, ["The Shattered Halls"]=540,
	["Shattered Halls"]=540, ["Magtheridon's Lair"]=544, ["The Slave Pens"]=547, ["Slave Pens"]=547,
	["The Underbog"]=546, ["Underbog"]=546, ["The Steamvault"]=545, ["Serpentshrine Cavern"]=548,
	["Mana-Tombs"]=557, ["Auchenai Crypts"]=558, ["Sethekk Halls"]=556, ["Shadow Labyrinth"]=555,
	["Old Hillsbrad Foothills"]=560, ["The Escape From Durnholde"]=560, ["The Black Morass"]=269,
	["Opening of the Dark Portal"]=269, ["The Mechanar"]=554, ["The Botanica"]=553, ["The Arcatraz"]=552,
	["Tempest Keep"]=550, ["The Eye"]=550, ["Karazhan"]=532, ["Gruul's Lair"]=565, ["Hyjal Summit"]=534,
	["The Battle for Mount Hyjal"]=534, ["Black Temple"]=564, ["Zul'Aman"]=568, ["Magisters' Terrace"]=585,
	["Sunwell Plateau"]=580, ["The Sunwell"]=580,
	["Utgarde Keep"]=574, ["Utgarde Pinnacle"]=575, ["The Nexus"]=576, ["The Oculus"]=578,
	["The Culling of Stratholme"]=595, ["Halls of Stone"]=599, ["Drak'Tharon Keep"]=600,
	["Azjol-Nerub"]=601, ["Halls of Lightning"]=602, ["Ulduar"]=603, ["Gundrak"]=604,
	["The Violet Hold"]=608, ["Violet Hold"]=608, ["The Obsidian Sanctum"]=615, ["The Eye of Eternity"]=616,
	["Ahn'kahet: The Old Kingdom"]=619, ["Vault of Archavon"]=624, ["Icecrown Citadel"]=631,
	["The Forge of Souls"]=632, ["Trial of the Crusader"]=649, ["Trial of the Champion"]=650,
	["Pit of Saron"]=658, ["Halls of Reflection"]=668, ["The Ruby Sanctum"]=724,
}
-- Individual Progression runs the 40-player Onyxia and Naxxramas in the
-- 10-player heroic difficulty slot.
IP.VANILLA_RAID_DIFFICULTY = { [249]=2, [533]=2 }

-- Gear Finder content phases and the tiers that open them.
IP.PHASES = { wotlk1=13, wotlk2=14, wotlk3=15, wotlk4=16, wotlk5=17 }

local TEXT = {
	enUS = {
		title = "Individual Progression",
		mode = "Individual Progression mode",
		mode_desc = "Automatic follows the server when it reports Individual Progression. On keeps later content locked until the server answers. Off shows every guide as on an ordinary realm.",
		mode_auto = "Automatic", mode_on = "On", mode_off = "Off",
		refresh = "Refresh",
		status_off = "Off: guides are not limited by Individual Progression.",
		status_absent = "No server support found; guides behave as on an ordinary realm.",
		status_absent_on = "No server support found; later content stays locked while the mode is On.",
		status_pending = "Waiting for the server's progression data.",
		status_inactive = "This realm does not use Individual Progression.",
		status_active = "tier %d (%s)",
		status_stored = "Saved progression: tier %d; usable on this realm: tier %d.",
		status_limit = "Realm ceiling: tier %d, level %d.",
		status_nolimit = "Realm ceiling: none, level %d.",
		status_custom = "Custom progression chain: the default milestones do not apply.",
		status_account = "Individual Progression does not apply to this account.",
		status_gm = "Game master mode bypasses progression gates.",
		status_level = "Experience stops at level %d until the next expansion's tier.",
		next = "Next milestone: tier %d - %s.",
		next_quest = "turn in %s",
		next_boss = "defeat %s in %s",
		next_met = "%s is already turned in and counts once the earlier milestones are complete.",
		next_ceiling = "The next milestone is above the realm ceiling.",
		next_done = "The default milestone chain is complete.",
		era0 = "Vanilla", era1 = "The Burning Crusade", era2 = "Wrath of the Lich King",
		locked_tier = "requires Individual Progression tier %d (%s)",
		locked_level = "level %d is the cap until tier %d (%s)",
		locked_instance = "%s: %s",
		unknown = "the server's progression data is not known yet",
		guide_stop = "The next guide, %s, is not available yet: %s.",
		guide_warning = "%s is not available to this character yet: %s.",
		quest_tier_need = "needs tier %d",
		quest_tier_retired = "retired at tier %d",
		quest_status = "Individual Progression: %s",
		quest_available = "available",
		quest_unknown = "availability not known yet",
		access_G = "locked by progression, its key or attunement",
		access_R = "an access requirement is missing", access_D = "disabled", access_U = "access not known",
		gear_next = "next tier",
		gear_later = "later tier",
		gear_unknown = "source not verified under Individual Progression",
		gear_recipe = "recipe source not verified under Individual Progression",
		talent_blocked = "the Talent Advisor knows only the Wrath talent trees",
		manual = "%s decides your progression; accept and turn it in yourself.",
		milestone_guide = "Individual Progression\\Milestone Chain",
		milestone_step = "Tier %d: %s.",
		milestone_ceiling = "The realm ceiling is reached; later milestones open when it is raised.",
		milestone_none = "This realm has not reported Individual Progression yet.",
		reason = {
			TIER = "progression marker condition", GIVER_HIDDEN = "quest giver hidden at this tier",
			DISABLED = "disabled", CLASS = "class", RACE = "race", LEVEL_LOW = "level too low",
			LEVEL_HIGH = "level too high", SKILL = "skill", REPUTATION = "reputation",
			PREVIOUS = "previous quest", TIMED = "another timed quest", EXCLUSIVE = "alternative already taken",
			NEXT_CHAIN = "later chain quest taken", PREV_CHAIN = "previous chain quest active",
			BREADCRUMB_DONE = "follow-up already taken", BREADCRUMB_ACTIVE = "breadcrumb active",
			REPEAT = "already done this reset", CONDITIONS = "quest conditions", LOG_FULL = "quest log full",
		},
	},
	deDE = {
		mode = "Individual-Progression-Modus",
		mode_desc = "Automatisch folgt dem Server, wenn er Individual Progression meldet. An hält spätere Inhalte gesperrt, bis der Server antwortet. Aus zeigt alle Guides wie auf einem gewöhnlichen Realm.",
		mode_auto = "Automatisch", mode_on = "An", mode_off = "Aus",
		refresh = "Aktualisieren",
		status_off = "Aus: Guides werden nicht durch Individual Progression begrenzt.",
		status_absent = "Keine Serverunterstützung gefunden; Guides verhalten sich wie auf einem gewöhnlichen Realm.",
		status_absent_on = "Keine Serverunterstützung gefunden; spätere Inhalte bleiben gesperrt, solange der Modus An ist.",
		status_pending = "Warte auf die Progressionsdaten des Servers.",
		status_inactive = "Dieser Realm verwendet Individual Progression nicht.",
		status_active = "Stufe %d (%s)",
		status_stored = "Gespeicherter Fortschritt: Stufe %d; auf diesem Realm nutzbar: Stufe %d.",
		status_limit = "Realm-Obergrenze: Stufe %d, Level %d.",
		status_nolimit = "Realm-Obergrenze: keine, Level %d.",
		status_custom = "Eigene Progressionskette: die Standard-Meilensteine gelten nicht.",
		status_account = "Individual Progression gilt für dieses Konto nicht.",
		status_gm = "Der Spielleitermodus umgeht die Progressionssperren.",
		status_level = "Erfahrung endet bei Level %d bis zur Stufe der nächsten Erweiterung.",
		next = "Nächster Meilenstein: Stufe %d - %s.",
		next_quest = "%s abgeben",
		next_boss = "%s in %s besiegen",
		next_met = "%s ist bereits abgegeben und zählt, sobald die früheren Meilensteine erreicht sind.",
		next_ceiling = "Der nächste Meilenstein liegt über der Realm-Obergrenze.",
		next_done = "Die Standard-Meilensteinkette ist abgeschlossen.",
		locked_tier = "erfordert Individual-Progression-Stufe %d (%s)",
		locked_level = "Level %d ist die Obergrenze bis Stufe %d (%s)",
		unknown = "die Progressionsdaten des Servers sind noch unbekannt",
		guide_stop = "Der nächste Guide, %s, ist noch nicht verfügbar: %s.",
		guide_warning = "%s ist für diesen Charakter noch nicht verfügbar: %s.",
		quest_tier_need = "benötigt Stufe %d",
		quest_tier_retired = "seit Stufe %d nicht mehr verfügbar",
		quest_available = "verfügbar",
		quest_unknown = "Verfügbarkeit noch unbekannt",
		access_G = "durch Progression, Schlüssel oder Einstimmung gesperrt",
		access_R = "eine Zugangsvoraussetzung fehlt", access_D = "deaktiviert", access_U = "Zugang unbekannt",
		gear_next = "nächste Stufe",
		gear_later = "spätere Stufe",
		gear_unknown = "Quelle unter Individual Progression nicht geprüft",
		gear_recipe = "Rezeptquelle unter Individual Progression nicht geprüft",
		talent_blocked = "der Talentberater kennt nur die Wrath-Talentbäume",
		manual = "%s entscheidet über deinen Fortschritt; nimm sie selbst an und gib sie selbst ab.",
		milestone_guide = "Individual Progression\\Meilensteinkette",
		milestone_step = "Stufe %d: %s.",
		milestone_ceiling = "Die Realm-Obergrenze ist erreicht; spätere Meilensteine öffnen sich, wenn sie angehoben wird.",
		milestone_none = "Dieser Realm hat Individual Progression noch nicht gemeldet.",
		reason = {
			TIER = "Progressionsbedingung", GIVER_HIDDEN = "Questgeber auf dieser Stufe verborgen",
			DISABLED = "deaktiviert", CLASS = "Klasse", RACE = "Volk", LEVEL_LOW = "Level zu niedrig",
			LEVEL_HIGH = "Level zu hoch", SKILL = "Fertigkeit", REPUTATION = "Ruf",
			PREVIOUS = "vorherige Quest", TIMED = "andere zeitgesteuerte Quest", EXCLUSIVE = "Alternative bereits gewählt",
			NEXT_CHAIN = "spätere Kettenquest angenommen", PREV_CHAIN = "vorherige Kettenquest aktiv",
			BREADCRUMB_DONE = "Folgequest bereits angenommen", BREADCRUMB_ACTIVE = "Hinweisquest aktiv",
			REPEAT = "in diesem Zeitraum erledigt", CONDITIONS = "Questbedingungen", LOG_FULL = "Questlog voll",
		},
	},
}
IP.TEXT = TEXT
local L = TEXT[GetLocale and GetLocale() or "enUS"] or TEXT.enUS
if L ~= TEXT.enUS then
	setmetatable(L, {__index = TEXT.enUS})
	setmetatable(L.reason, {__index = TEXT.enUS.reason})
end
IP.L = L

local function hasbit(mask, bit)
	return mask % (bit * 2) >= bit
end
IP.hasbit = hasbit

local function Babble(name)
	local lib = LibStub and LibStub("LibBabble-Zone-3.0", true)
	local lookup = lib and lib:GetUnstrictLookupTable()
	return lookup and lookup[name] or name
end

local function EraOfTier(tier)
	return tier >= 13 and 2 or tier >= 8 and 1 or 0
end
IP.EraOfTier = EraOfTier

local function TierOfEra(era)
	return era == 2 and 13 or era == 1 and 8 or 0
end
IP.TierOfEra = TierOfEra

function IP:TierName(tier)
	return L["era" .. EraOfTier(tier)]
end

------------------------------------------------------------------------
-- Progression state
------------------------------------------------------------------------

function IP:Mode()
	local mode = ZGV.db and ZGV.db.profile and ZGV.db.profile.ip_mode
	return (mode == "on" or mode == "off") and mode or "auto"
end

-- off: disabled; inactive: the realm has no Individual Progression;
-- active: server state known; absent: no bridge; pending: still asking.
function IP:Status()
	if self:Mode() == "off" then return "off" end
	if self.state then return self.state.ip and "active" or "inactive" end
	if self.bridge == "absent" or self.bridge == "unsupported" then return "absent" end
	return "pending"
end

-- Whether this module limits anything: off, inactive realms and an automatic
-- mode without server support keep the addon's own behaviour.
function IP:Applies()
	local status = self:Status()
	if status == "off" or status == "inactive" then return false end
	if status == "absent" then return self:Mode() == "on" end
	return true
end

-- Gates apply to this character: Individual Progression is active, applies to
-- the account and no game master mode bypasses it.
function IP:Gated()
	local s = self.state
	return s ~= nil and s.ip and s.account == "N" and not s.gm
end

-- "ok", "locked" or "unknown" for content that opens at tier.
function IP:TierCheck(tier)
	if not self:Applies() then return "ok" end
	if not (self.state and self.state.ip) then return "unknown" end
	if not self:Gated() or self.state.effective >= tier then return "ok" end
	return "locked"
end

-- True only when the server reports that this character has the tier.
function IP:HasTier(tier)
	return self.state ~= nil and self.state.ip and self:TierCheck(tier) == "ok"
end

-- The reason text for a tier check that is not "ok".
function IP:TierReason(check, tier)
	if check == "locked" then return L.locked_tier:format(tier, self:TierName(tier)) end
	return L.unknown
end

-- Normal accounts stop gaining experience at the cap of their earned era.
function IP:LevelCap()
	local s = self.state
	local maxLevel = s and s.maxLevel or 80
	if not self:Gated() then return maxLevel end
	local cap = s.effective >= 13 and 80 or s.effective >= 8 and 70 or 60
	return math.min(cap, maxLevel)
end

function IP:ParseState(fields)
	-- IP_STATE~token~1~ip~strict~stored~effective~limit~era~next~nextMet~account~gm~maxLevel
	if #fields ~= 14 or fields[3] ~= "1" then return nil end
	local n = {}
	for i = 4, 14 do
		if i ~= 12 then
			n[i] = tonumber(fields[i])
			if not n[i] or n[i] < 0 or n[i] % 1 ~= 0 then return nil end
		end
	end
	local account = fields[12]
	if account ~= "N" and account ~= "B" and account ~= "X" then return nil end
	if n[4] > 1 or n[5] > 1 or n[11] > 1 or n[13] > 1 then return nil end
	if n[6] > 18 or n[7] > n[6] or n[8] > 18 or (n[8] > 0 and n[7] > n[8]) or n[10] > 18 then return nil end
	if n[9] > 2 and n[9] ~= 255 then return nil end
	return {
		ip = n[4] == 1, strict = n[5] == 1, stored = n[6], effective = n[7], limit = n[8], era = n[9],
		next = n[10], nextMet = n[11] == 1, account = account, gm = n[13] == 1, maxLevel = n[14],
	}
end

local function SameState(a, b)
	if not a or not b then return false end
	for k, v in pairs(a) do
		if b[k] ~= v then return false end
	end
	return true
end

function IP:Changed()
	self.guideChecks = nil
	local finder = ZGV.ItemScore and ZGV.ItemScore.GearFinder
	if finder then
		if finder.RefreshAfterSourceSettingChange then
			finder:RefreshAfterSourceSettingChange()
		else
			finder.ResultsReady = nil
		end
	end
	if ZGV.TalentAdvisorProgressionChanged then ZGV:TalentAdvisorProgressionChanged() end
	if ZGV.UpdateFrame and ZGV.Frame then ZGV:UpdateFrame(true) end
	local registry = LibStub and LibStub("AceConfigRegistry-3.0", true)
	if registry then registry:NotifyChange("ZygorGuidesViewer-Progress") end
end

function IP:ApplyState(state)
	if SameState(state, self.state) then return end
	local first = self.state == nil
	self.state = state
	self:InvalidateQuests()
	self.access = nil
	self.accessAt = nil
	if state.ip then self:RequestAccess(true) end
	self:Changed()
	if first and state.ip and ZGV.Print then
		ZGV:Print(L.title .. ": " .. L.status_active:format(state.effective, self:TierName(state.effective)))
	end
end

------------------------------------------------------------------------
-- Bridge messages
------------------------------------------------------------------------

local function SplitFields(value)
	local fields, start = {}, 1
	while true do
		local stop = string.find(value, "~", start, true)
		if not stop then
			fields[#fields + 1] = string.sub(value, start)
			return fields
		end
		fields[#fields + 1] = string.sub(value, start, stop - 1)
		start = stop + 1
	end
end
IP.SplitFields = SplitFields

local function Channel()
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
	return "WHISPER"
end

function IP:Send(message)
	local player = UnitName and UnitName("player")
	if not player or #message > MAX_MESSAGE then return false end
	local channel = Channel()
	if channel == "WHISPER" then
		SendAddonMessage(PREFIX, message, channel, player)
	else
		SendAddonMessage(PREFIX, message, channel)
	end
	return true
end

function IP:Token()
	self.sequence = self.sequence + 1
	return "zip" .. self.sequence
end

function IP:Now()
	return GetTime and GetTime() or 0
end

function IP:Probe()
	if self:Mode() == "off" or self.bridge == "ready" or self.helloPending then return end
	self.helloPending = true
	self.helloAt = self:Now()
	self.helloRetries = (self.helloRetries or 0) + 1
	self.caps = {}
	self:Send("HELLO~1")
end

function IP:RequestState()
	if self.bridge ~= "ready" then return end
	self.watchToken = self.watchToken or self:Token()
	self.watchAt = self:Now()
	self:Send("GET~IP_STATE~" .. self.watchToken .. "~WATCH")
end

function IP:RequestAccess(force)
	if self.bridge ~= "ready" or not (self.state and self.state.ip) then return end
	local now = self:Now()
	if not force and self.accessAt and now - self.accessAt < ACCESS_REFRESH then return end
	for _, request in pairs(self.requests) do
		if request.kind == "IP_ACCESS" then return end
	end
	self.accessAt = now
	local token = self:Token()
	self.requests[token] = {kind="IP_ACCESS", at=now, items={}}
	self:Send("GET~IP_ACCESS~" .. token)
end

function IP:QueueQuest(id)
	if self.bridge ~= "ready" or not (self.state and self.state.ip) then return end
	if self.queued[id] or self.inflight[id] then return end
	self.queued[id] = true
	if not self.flushPending then
		self.flushPending = true
		if ZGV.ScheduleTimer then
			ZGV:ScheduleTimer(function() IP:Flush() end, FLUSH_DELAY)
		end
	end
end

-- Sends queued quest IDs in batches that fit one addon message.
function IP:Flush()
	self.flushPending = nil
	local ids = {}
	for id in pairs(self.queued) do ids[#ids + 1] = id end
	table.sort(ids)
	local batch, size, sent = {}, 0, 0
	local function send()
		if #batch == 0 then return end
		local token = self:Token()
		self.requests[token] = {kind="IP_QUESTS", at=self:Now(), items={}, ids=batch, generation=self.generation}
		self:Send("GET~IP_QUESTS~" .. token .. "~" .. table.concat(batch, ","))
		batch, size, sent = {}, 0, sent + 1
	end
	local base = #"GET~IP_QUESTS~" + #"zip" + 10
	for _, id in ipairs(ids) do
		local text = tostring(id)
		if #batch >= MAX_BATCH or base + size + #text > MAX_MESSAGE then send() end
		if sent >= MAX_FLUSH_BATCHES then break end
		batch[#batch + 1] = text
		size = size + #text + 1
		self.queued[id] = nil
		self.inflight[id] = true
	end
	send()
	if next(self.queued) and ZGV.ScheduleTimer then
		self.flushPending = true
		ZGV:ScheduleTimer(function() IP:Flush() end, FLUSH_INTERVAL)
	end
end

function IP:Settle(request)
	for _, id in ipairs(request.ids or {}) do self.inflight[tonumber(id)] = nil end
end

function IP:Requeue(request)
	self:Settle(request)
	for _, id in ipairs(request.ids or {}) do self:QueueQuest(tonumber(id)) end
end

function IP:Tick()
	local now = self:Now()
	if self.helloPending and now - self.helloAt >= HELLO_TIMEOUT then
		self.helloPending = false
		if self.helloRetries >= HELLO_RETRIES then
			self.bridge = "absent"
			self:Changed()
		end
	end
	if not self.bridge and not self.helloPending and now - (self.helloAt or -HELLO_RETRY) >= HELLO_RETRY then
		self:Probe()
	end
	if self.bridge == "ready" and self.watchAt and now - self.watchAt >= WATCH_RENEW then
		self:RequestState()
	end
	for token, request in pairs(self.requests) do
		if now - request.at >= REQUEST_TIMEOUT then
			self.requests[token] = nil
			self:Settle(request)
			if request.kind == "IP_ACCESS" then self.accessAt = nil end
		end
	end
end

function IP:StoreQuests(request)
	-- An answer to quests asked before an invalidation would restore stale state.
	if request.generation ~= self.generation then
		self:Requeue(request)
		return
	end
	self:Settle(request)
	local now = self:Now()
	for _, entry in ipairs(request.items) do
		local id, status, rest = string.match(entry, "^(%d+):(%u)(.*)$")
		id = tonumber(id)
		if id then
			local reasons, tier = 0, nil
			if status == "L" then
				local hex, sign, value = string.match(rest, "^(%x+):?([+-]?)(%d*)$")
				reasons = tonumber(hex or "", 16) or 0
				if value ~= "" then tier = (sign == "-" and -1 or 1) * tonumber(value) end
			end
			self.quests[id] = {status=status, reasons=reasons, tier=tier, generation=self.generation, at=now}
		end
	end
	if ZGV.UpdateFrame and ZGV.Frame then ZGV:UpdateFrame() end
end

function IP:StoreAccess(request)
	local access = {}
	for _, entry in ipairs(request.items) do
		local map, codes = string.match(entry, "^(%d+):([AGRD%-][AGRD%-][AGRD%-][AGRD%-])$")
		if map then access[tonumber(map)] = codes end
	end
	self.access = access
	self:Changed()
end

function IP:OnMessage(prefix, message, sender)
	if prefix ~= PREFIX or type(message) ~= "string" or #message > 255 then return end
	local player = UnitName and UnitName("player")
	sender = sender and string.gsub(sender, "%-.*$", "")
	-- The bridge answers as the player's own addon message sender.
	if not player or not sender or string.lower(sender) ~= string.lower(player) then return end
	local fields = SplitFields(message)
	local opcode = fields[1]
	if opcode == "CAPS_BEGIN" and self.helloPending then
		self.caps = {}
	elseif opcode == "CAPS" and self.helloPending then
		for cap in string.gmatch(fields[2] or "", "[^,]+") do self.caps[cap] = true end
	elseif opcode == "CAPS_END" and self.helloPending then
		self.helloPending = false
		self.bridge = self.caps[CAPABILITY] and "ready" or "unsupported"
		if self.bridge == "ready" then self:RequestState() else self:Changed() end
	elseif opcode == "IP_STATE" then
		if fields[2] ~= self.watchToken then return end
		local state = self:ParseState(fields)
		if state then self:ApplyState(state) end
	elseif opcode == "IP_QUESTS_BEGIN" or opcode == "IP_ACCESS_BEGIN" then
		local request = self.requests[fields[2] or ""]
		if request and request.kind .. "_BEGIN" == opcode then request.items = {} end
	elseif opcode == "IP_QUESTS" or opcode == "IP_ACCESS" then
		local request = self.requests[fields[2] or ""]
		if request and request.kind == opcode then
			for entry in string.gmatch(fields[3] or "", "[^,]+") do request.items[#request.items + 1] = entry end
		end
	elseif opcode == "IP_QUESTS_END" or opcode == "IP_ACCESS_END" then
		local token = fields[2] or ""
		local request = self.requests[token]
		if not request or request.kind .. "_END" ~= opcode then return end
		self.requests[token] = nil
		-- A reply that lost a packet is incomplete; ask again instead of guessing.
		if tonumber(fields[3]) ~= #request.items then
			if request.kind == "IP_QUESTS" then self:Requeue(request) else self.accessAt = nil end
			return
		end
		if request.kind == "IP_QUESTS" then self:StoreQuests(request) else self:StoreAccess(request) end
	elseif opcode == "ERR" and fields[2] == "GET" then
		-- ERR~GET~request~token~reason
		local request = self.requests[fields[4] or ""]
		if request then
			self.requests[fields[4]] = nil
			self:Settle(request)
			if request.kind == "IP_ACCESS" then self.accessAt = nil end
			if request.kind == "IP_QUESTS" and fields[5] == "RATE_LIMIT" then self:Requeue(request) end
		end
	end
end

------------------------------------------------------------------------
-- Quests
------------------------------------------------------------------------

local function sharesbit(a, b)
	for _, key in ipairs(REASON_ORDER) do
		if hasbit(a, R[key]) and hasbit(b, R[key]) then return true end
	end
	return false
end

-- Quest log changes and levels alter chains, exclusive groups, breadcrumbs and
-- level ranges; skills and reputation alter only answers that named them.
function IP:InvalidateQuests(bits)
	if not bits then
		self.generation = self.generation + 1
		return
	end
	for id, entry in pairs(self.quests) do
		if entry.status == "L" and sharesbit(entry.reasons, bits) then self.quests[id] = nil end
	end
end

-- The server's answer for a quest, or nil while unknown; asks for it when
-- needed. An outdated answer stays in use until its replacement arrives.
function IP:Quest(id)
	if not id or not (self.state and self.state.ip) then return nil end
	local entry = self.quests[id]
	if not entry or entry.generation ~= self.generation or
		(hasbit(entry.reasons, R.REPEAT) and self:Now() - entry.at >= REPEAT_TTL) then
		self:QueueQuest(id)
	end
	return entry
end

function IP:IsBlockingMask(mask)
	return sharesbit(mask, self.BLOCKING)
end

-- True when the server reports the quest unavailable under this character's
-- current progression or permanent character rules. Quests in the log,
-- completed quests and unknown answers are never blocked.
function IP:IsQuestBlocked(id)
	if not id or not self:Applies() or not self:Gated() then return false end
	if ZGV.questsbyid and ZGV.questsbyid[id] then return false end
	if ZGV.completedQuests and ZGV.completedQuests[id] then return false end
	local entry = self:Quest(id)
	return entry ~= nil and entry.status == "L" and self:IsBlockingMask(entry.reasons)
end

function IP:DescribeQuest(id)
	local entry = self:Quest(id)
	if not entry then return L.quest_unknown end
	if entry.status ~= "L" then return L.quest_available end
	local parts = {}
	for _, key in ipairs(REASON_ORDER) do
		if hasbit(entry.reasons, R[key]) then
			local text = L.reason[key]
			if key == "TIER" and entry.tier then
				text = entry.tier > 0 and L.quest_tier_need:format(entry.tier) or L.quest_tier_retired:format(-entry.tier)
			end
			parts[#parts + 1] = text
		end
	end
	return table.concat(parts, ", ")
end

function IP:IsGoalBlocked(goal)
	return goal.questid ~= nil and self:IsQuestBlocked(goal.questid)
end

-- A step whose every quest goal is blocked does not apply to this character.
function IP:IsStepBlocked(step)
	local quests = 0
	for _, goal in ipairs(step.goals or {}) do
		if goal.questid then
			if not self:IsGoalBlocked(goal) then return false end
			quests = quests + 1
		end
	end
	return quests > 0
end

function IP:IsManualQuest(id)
	return id ~= nil and self.MANUAL_QUESTS[id] == true and self:Applies()
end

-- Reports once per quest that the player decides a progression quest.
function IP:ManualQuestNotice(goal)
	if not self:IsManualQuest(goal.questid) then return false end
	self.manualNoticed = self.manualNoticed or {}
	if not self.manualNoticed[goal.questid] and ZGV.Print then
		self.manualNoticed[goal.questid] = true
		ZGV:Print(L.manual:format(goal.quest or tostring(goal.questid)))
	end
	return true
end

function IP:AddGoalTooltip(tooltip, goal)
	if not goal or not goal.questid or not self:Gated() then return end
	if ZGV.questsbyid and ZGV.questsbyid[goal.questid] then return end
	if ZGV.completedQuests and ZGV.completedQuests[goal.questid] then return end
	tooltip:AddLine(L.quest_status:format(self:DescribeQuest(goal.questid)), 0.6, 0.8, 1, true)
end

------------------------------------------------------------------------
-- Guides, regions and instances
------------------------------------------------------------------------

function IP:RegionTier(zone)
	local tier = self.REGIONS[zone]
	if tier then return tier end
	if self.TBC_RACE_ZONES[zone] then
		local race = UnitRace and select(2, UnitRace("player"))
		return self.TBC_RACES[race] and 0 or 8
	end
	return 0
end

-- Codes for one map's difficulties 0-3, or nil while unknown.
function IP:AccessCodes(map)
	if not self.access then
		self:RequestAccess()
		return nil
	end
	return self.access[map]
end

-- "ok", "locked" or "unknown" with a reason for an instance map. Without a
-- difficulty the check passes when any existing difficulty is accessible.
function IP:InstanceCheck(map, difficulty)
	if not self:Applies() then return "ok" end
	if not self:Gated() then
		if self.state and self.state.ip then return "ok" end
		return "unknown", L.unknown
	end
	if not map then return "unknown", L.access_U end
	local codes = self:AccessCodes(map)
	if not codes then return "unknown", L.access_U end
	local code
	if difficulty then
		code = string.sub(codes, difficulty + 1, difficulty + 1)
	else
		code = string.find(codes, "A", 1, true) and "A" or string.match(codes, "[GRD]") or "-"
	end
	if code == "A" then return "ok" end
	if code == "-" or code == "" then return "unknown", L.access_U end
	return "locked", L["access_" .. code], code
end

local function ZoneName(text)
	text = string.gsub(string.gsub(text, "/.*$", ""), "^%s+", "")
	return (string.gsub(text, "%s+$", ""))
end

-- The tier a guide's zones need and the instances it enters.
function IP:GuideRequirement(guide)
	if guide._ipRequirement then return guide._ipRequirement end
	local requirement = {tier = 0, instances = {}}
	local seen = {}
	local function zone(name)
		name = ZoneName(name)
		if name == "" or seen[name] then return end
		seen[name] = true
		local tier = self:RegionTier(name)
		if tier > requirement.tier then requirement.tier, requirement.zone = tier, name end
		local map = self.INSTANCES[name]
		if map then requirement.instances[map] = name end
	end
	local text = type(guide.rawdata) == "string" and guide.rawdata or ""
	for name in string.gmatch(text, "goto%s+([^,|\n\r]+)") do zone(name) end
	local header = type(guide.headerdata) == "table" and guide.headerdata or nil
	if header and type(header.maps) == "table" then
		for _, name in ipairs(header.maps) do
			if type(name) == "string" then zone(name) end
		end
	end
	requirement.startlevel = tonumber(guide.startlevel)
	guide._ipRequirement = requirement
	return requirement
end

-- "ok", "locked" or "unknown" and a reason for following a guide now.
function IP:GuideCheck(guide)
	if not guide or not self:Applies() then return "ok" end
	local requirement = self:GuideRequirement(guide)
	local check = self:TierCheck(requirement.tier)
	if check ~= "ok" then return check, self:TierReason(check, requirement.tier) end
	if not self:Gated() then return "ok" end
	local level = requirement.startlevel
	local leveling = guide.type == "leveling" or string.find(string.lower(guide.title or ""), "leveling", 1, true)
	if level and leveling then
		local cap = self:LevelCap()
		if level >= cap and cap < self.state.maxLevel then
			local tier = cap < 70 and 8 or 13
			return "locked", L.locked_level:format(cap, tier, self:TierName(tier))
		end
	end
	-- Only the progression gate closes a guide; keys and levels belong to its steps.
	for map, name in pairs(requirement.instances) do
		local result, reason, code = self:InstanceCheck(map)
		if result == "locked" and code == "G" then
			return "locked", L.locked_instance:format(Babble(name), reason)
		elseif result == "unknown" then
			return "unknown", reason
		end
	end
	return "ok"
end

function IP:IsGuideBlocked(guide)
	return self:GuideCheck(guide) ~= "ok"
end

local function GuideName(guide)
	return guide and (guide.title_short or guide.title) or "?"
end

-- The finish text that holds a guide chain before a locked next guide.
function IP:GuideStopText(guide, reason)
	return L.guide_stop:format(GuideName(guide), reason or L.unknown)
end

-- A detail line for the guide browser, or nil when the guide is available.
function IP:GuideLine(guide)
	local check, reason = self:GuideCheck(guide)
	if check == "ok" then return nil end
	return "|cffff8040" .. L.title .. ": " .. (reason or L.unknown) .. "|r"
end

-- Warns once when the player loads a guide this character cannot follow yet.
function IP:WarnGuide(guide)
	local check, reason = self:GuideCheck(guide)
	if check ~= "locked" or self.warned[guide.title] or not ZGV.Print then return end
	self.warned[guide.title] = true
	ZGV:Print(L.guide_warning:format(GuideName(guide), reason))
end

------------------------------------------------------------------------
-- Gear sources
------------------------------------------------------------------------

-- Whether a Gear Finder phase is open, or nil when this module does not apply.
function IP:PhaseActive(phase)
	local tier = self.PHASES[phase]
	if not tier or not self:Applies() then return nil end
	return self:TierCheck(tier) == "ok"
end

-- "next" when the next milestone opens the tier, "later" otherwise.
function IP:Horizon(tier)
	local s = self.state
	if s and s.ip and s.strict and s.next > 0 and tier <= s.next then return L.gear_next end
	return L.gear_later
end

-- The server map and difficulty slot of a Gear Finder dungeon entry.
function IP:DungeonMap(ident, dungeon)
	-- Dungeons.lua builds its objects without the hardcoded instance name of a dungeon's wings.
	local hardcoded = ZGV.Dungeons and rawget(ZGV.Dungeons, "hardcoded_dungeons")
	local wing = hardcoded and hardcoded[ident]
	local map = self.INSTANCES[dungeon.instancename or ""] or self.INSTANCES[wing and wing.instancename or ""]
		or self.INSTANCES[dungeon.name or ""]
	if not map then
		local text = tostring(ident)
		map = tonumber(string.match(text, "^(%d+)_")) or tonumber(string.match(text, "^(%d+)H?$"))
		local known = false
		for _, value in pairs(self.INSTANCES) do
			if value == map then known = true break end
		end
		if not known then return nil end
	end
	local text = tostring(ident)
	local difficulty
	if self.VANILLA_RAID_DIFFICULTY[map] and (dungeon.expansionLevel or 0) == 0 then
		difficulty = self.VANILLA_RAID_DIFFICULTY[map]
	elseif string.find(text, "_25H$") then difficulty = 3
	elseif string.find(text, "_10H$") then difficulty = 2
	elseif string.find(text, "_25$") then difficulty = 1
	elseif string.find(text, "_10$") then difficulty = 0
	elseif string.find(text, "H$") then difficulty = 1
	else difficulty = 0 end
	return map, difficulty
end

-- Whether a dungeon's loot is farmable now: "ok", "locked" or "unknown",
-- with a reason that says when it opens.
function IP:DungeonCheck(ident, dungeon)
	if not self:Applies() then return "ok" end
	local tier = TierOfEra(dungeon.expansionLevel or 0)
	if dungeon.phase and self.PHASES[dungeon.phase] then tier = math.max(tier, self.PHASES[dungeon.phase]) end
	local check = self:TierCheck(tier)
	if check == "locked" then
		return "locked", self:Horizon(tier) .. ": " .. self:TierReason(check, tier)
	elseif check ~= "ok" then
		return check, L.unknown
	end
	local map, difficulty = self:DungeonMap(ident, dungeon)
	if not map then return "unknown", L.gear_unknown end
	local result, reason, code = self:InstanceCheck(map, difficulty)
	-- A disabled map never opens; a missing key or attunement opens through play.
	if code == "D" then return "unknown", reason end
	if code == "G" then return "locked", self:Horizon(self.state.effective + 1) .. ": " .. reason end
	return result, reason
end

-- Currency vendors of a later era are not reachable before its tier.
function IP:VendorCheck(source)
	if not self:Applies() then return "ok" end
	local tier = TierOfEra(source.expansionLevel or 0)
	local check = self:TierCheck(tier)
	if check == "ok" then return "ok" end
	return check, self:TierReason(check, tier)
end

-- Crafted gear is reachable through a recipe the character knows or a trainer
-- recipe of an earned era; other recipe sources are not verified.
function IP:CraftCheck(source, itemSource)
	if not self:Applies() then return "ok" end
	local era = itemSource.expansionLevel
	if era == nil then era = source.expansionLevel end
	local tier = TierOfEra(era or 0)
	local check = self:TierCheck(tier)
	if check ~= "ok" then return check, self:TierReason(check, tier) end
	if not self:Gated() then return "ok" end
	local spell = tonumber(itemSource.recipeSpellID)
	if spell and IsSpellKnown and IsSpellKnown(spell) then return "ok" end
	local recipeSource = itemSource.recipeSource or ""
	if string.find(recipeSource, "^Trainer") then return "ok" end
	return "unknown", L.gear_recipe
end

-- The highest Wrath raid tier whose best-in-slot lists apply now, -1 before
-- Wrath, or nil when this module does not apply.
function IP:BISPhaseRank()
	if not self:Applies() then return nil end
	if not (self.state and self.state.ip) then return -1 end
	local tier = self:Gated() and self.state.effective or 18
	if tier < 13 then return -1 end
	return math.min(tier - 12, 5)
end

------------------------------------------------------------------------
-- Talents
------------------------------------------------------------------------

-- The bundled advisor knows the native Wrath trees only. It stays inactive
-- while EraTalents manages historical trees, before the earned Wrath era and
-- while the era is not known.
function IP:TalentAdvisorBlocked()
	local era = _G.EraTalents and _G.EraTalents.state
	if era and era.isEraChar then return true, L.talent_blocked end
	if not self:Applies() then return false end
	if not (self.state and self.state.ip) then return true, L.unknown end
	if not self:Gated() then return false end
	return self.state.era ~= 2, L.talent_blocked
end

-- EraTalents keeps a Vanilla/TBC character's points outside the native talent API, which then
-- reports none spent and none free. Points per tab of the synchronised historical tree, the spent
-- total, unspent points and optional Druid Thick Hide rank; nil while EraTalents does not manage this character.
function IP:EraTalentPoints(classToken)
	local era = _G.EraTalents
	local state = era and era.state
	if not (state and state.isEraChar and type(era.SpecPoints) == "function") then return nil end
	local trees = _G.EraTalentsData and _G.EraTalentsData[state.era]
	for _, tree in pairs(trees or {}) do
		if tree.className == classToken then
			local points = era.SpecPoints(tree, state.ranks)
			local feralRank
			if classToken == "DRUID" then
				feralRank = 0
				for _, node in ipairs(tree.talents) do
					if node.name == "Thick Hide" then feralRank = (state.ranks and state.ranks[node.id]) or 0; break end
				end
			end
			return points, points[1] + points[2] + points[3], tonumber(state.availPts) or 0, feralRank
		end
	end
end

-- Before its earned Wrath era a gated character's points live in historical trees, so empty native
-- trees do not mean that talent data is still loading.
function IP:NativeTalentsHistorical()
	return self:Gated() and self.state.era < 2
end

-- EraTalents synchronises historical points without native talent events; rescore gear when they change.
function IP:WatchEraTalents()
	local era = _G.EraTalents
	if self.eraWatched or not (era and type(era.Refresh) == "function") then return end
	self.eraWatched = true
	local last
	hooksecurefunc(era, "Refresh", function()
		local score = ZGV.ItemScore
		if not (score and score.Initialised) then return end
		local points, _, free, feralRank = IP:EraTalentPoints(score.playerclass)
		local signature = points and table.concat(points, ",") .. "/" .. free .. "/" .. (feralRank or "") or ""
		if signature == last then return end
		last = signature
		score:DelayedRefreshUserData()
	end)
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------

function IP:MilestoneText(tier)
	local milestone = self.MILESTONES[tier]
	if not milestone then return "?" end
	if milestone.quest then
		local name = ZGV.GetQuestName and ZGV:GetQuestName(milestone.quest)
		return L.next_quest:format(name or milestone.name)
	end
	local npc = ZGV.GetTranslatedNPC and ZGV:GetTranslatedNPC(milestone.npc)
	return L.next_boss:format(npc or milestone.name, Babble(milestone.zone))
end

function IP:StatusLines()
	local status = self:Status()
	if status == "off" then return {L.status_off} end
	if status == "absent" then return {self:Mode() == "on" and L.status_absent_on or L.status_absent} end
	if status == "pending" then return {L.status_pending} end
	if status == "inactive" then return {L.status_inactive} end
	local s = self.state
	local lines = {L.title .. ": " .. L.status_active:format(s.effective, self:TierName(s.effective))}
	lines[#lines + 1] = L.status_stored:format(s.stored, s.effective)
	lines[#lines + 1] = s.limit > 0 and L.status_limit:format(s.limit, s.maxLevel) or L.status_nolimit:format(s.maxLevel)
	if s.account ~= "N" then lines[#lines + 1] = L.status_account end
	if s.gm then lines[#lines + 1] = L.status_gm end
	if self:Gated() and self:LevelCap() < s.maxLevel then lines[#lines + 1] = L.status_level:format(self:LevelCap()) end
	if not s.strict then
		lines[#lines + 1] = L.status_custom
	elseif s.next == 0 then
		lines[#lines + 1] = L.next_done
	elseif s.limit > 0 and s.next > s.limit then
		lines[#lines + 1] = L.next_ceiling
	else
		lines[#lines + 1] = L.next:format(s.next, self:MilestoneText(s.next))
		local milestone = self.MILESTONES[s.next]
		if s.nextMet and milestone and milestone.quest then
			local name = ZGV.GetQuestName and ZGV:GetQuestName(milestone.quest)
			lines[#lines + 1] = L.next_met:format(name or milestone.name)
		end
	end
	return lines
end

function IP:StatusText()
	return table.concat(self:StatusLines(), "\n")
end

function IP:PrintStatus()
	for _, line in ipairs(self:StatusLines()) do ZGV:Print(line) end
end

-- The milestone chain as a guide; each step completes from the server's tier.
function IP:MilestoneGuide()
	local lines = {"author Individual Progression", "type misc", "startlevel 1"}
	local first = true
	for tier = 1, 18 do
		if self.MILESTONES[tier] then
			-- Guide lines use | and // as syntax; localized names must not.
			local text = L.milestone_step:format(tier, self:MilestoneText(tier)):gsub("|", "/"):gsub("//", "/")
			lines[#lines + 1] = "step"
			lines[#lines + 1] = ("\t.'%s|condition ZGV.IP:HasTier(%d)"):format(text, tier)
			-- The viewer shows a guide's first step even when it is skipped, so
			-- the note for a realm that has not reported a tier is a line here.
			if first then
				lines[#lines + 1] = "\t.'" .. L.milestone_none .. "|only if not (ZGV.IP.state and ZGV.IP.state.ip)"
				first = false
			end
			lines[#lines + 1] = ("\tonly if not (ZGV.IP.state and ZGV.IP.state.limit > 0 and ZGV.IP.state.limit < %d)"):format(tier)
		end
	end
	lines[#lines + 1] = "step"
	lines[#lines + 1] = "\t.'" .. L.milestone_ceiling .. "|confirm"
	lines[#lines + 1] = "\tonly if ZGV.IP.state and ZGV.IP.state.limit > 0 and ZGV.IP.state.limit < 18"
	return table.concat(lines, "\n")
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------

function IP:Refresh()
	self.access = nil
	self.accessAt = nil
	self:InvalidateQuests()
	if self.bridge == "ready" then
		self:RequestState()
		self:RequestAccess(true)
	else
		self.bridge, self.helloRetries, self.helloPending = nil, 0, false
		self:Probe()
	end
	self:Changed()
end

function IP:ModeChanged()
	if self:Mode() == "off" then
		self.helloPending = false
	elseif not self.bridge then
		self.helloRetries = 0
		self:Probe()
	end
	self:Changed()
end

function IP:Startup()
	if self.started then return end
	self.started = true
	ZGV:AddEvent("CHAT_MSG_ADDON", function(_, _, prefix, message, _, sender) IP:OnMessage(prefix, message, sender) end)
	ZGV:AddEvent("PLAYER_LEVEL_UP", function()
		IP:InvalidateQuests()
		IP:RequestAccess(true)
		IP:Changed()
	end)
	for _, event in ipairs({"NewQuestEvent", "LostQuestEvent", "CompletedQuestEvent"}) do
		if ZGV[event] then hooksecurefunc(ZGV, event, function() IP:InvalidateQuests() end) end
	end
	ZGV:AddEvent("SKILL_LINES_CHANGED", function() IP:InvalidateQuests(R.SKILL) end)
	ZGV:AddEvent("UPDATE_FACTION", function() IP:InvalidateQuests(R.REPUTATION) end)
	ZGV:ScheduleRepeatingTimer(function() IP:Tick() end, 1)
	self:WatchEraTalents()
	self:Probe()
end

if ZGV.ConditionEnv then
	ZGV.ConditionEnv.iptier = function(tier) return IP:HasTier(tier) end
end

tinsert(ZGV.startups, {"Individual Progression", function() IP:Startup() end})

ZGV:RegisterGuide(L.milestone_guide, IP:MilestoneGuide())

SLASH_ZYGORIP1 = "/zygorip"
SlashCmdList["ZYGORIP"] = function(msg)
	if msg and string.lower(msg) == "refresh" then IP:Refresh() end
	IP:PrintStatus()
end
