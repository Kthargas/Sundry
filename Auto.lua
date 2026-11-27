local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("auto", M)

-- Automation: quests, gossip, declining duels and guild invites, accepting invites from friends and
-- resurrections, taking all mail and learning everything at a trainer. Everything that acts on its own
-- is off by default, and holding Shift pauses it.

local function Paused() return IsShiftKeyDown() end
local function On(key) return S:Get("auto", key) and not Paused() end

------------------------------------------------------------------------
-- Quests: accepting and turning in are two switches; which kinds of quests are accepted is chosen
-- per kind. A quest that belongs to several kinds is only accepted when all of them are allowed.
------------------------------------------------------------------------
local TAG_GROUP = { [1] = true }                                   -- Enum.QuestTag.Group
local TAG_DUNGEON = { [81] = true, [85] = true, [98] = true }      -- dungeon, heroic, scenario
local TAG_RAID = { [62] = true, [88] = true, [89] = true }         -- raid, raid (10), raid (25)
local TAG_PVP = { [41] = true }

-- Words in the quest text (English and German) for the kinds the client has no flag for.
local WORDS = {
	timed = { "time limit", "within %d+ minutes", "minutes to", "zeitlimit", "innerhalb von %d+ minuten", "minuten zeit" },
	escort = { "escort", "protect .- as", "safely to", "eskort", "begleit", "geleit", "beschütz", "sicher zu" },
}

local function TextHas(kind)
	local text = ((GetObjectiveText and GetObjectiveText() or "") .. " " .. (GetQuestText and GetQuestText() or ""))
	if S.IsSecret(text) then return false end
	text = text:lower()
	for _, word in ipairs(WORDS[kind]) do
		if text:find(word) then return true end
	end
	return false
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return result end
end

-- The kinds of the quest shown in the quest window (QUEST_DETAIL).
local function DetailKinds()
	local kinds = {}
	local questID = Call(GetQuestID)
	local Q = C_QuestLog or {}
	if Call(QuestIsDaily) or Call(QuestIsWeekly) or (questID and Call(Q.IsRepeatableQuest, questID)) then
		kinds.questRepeat = true
	end
	if questID and Call(Q.IsQuestTrivial, questID) then kinds.questTrivial = true end
	if (Call(GetSuggestedGroupSize) or 0) > 1 then kinds.questGroup = true end
	local tag = questID and Call(Q.GetQuestTagInfo, questID)
	local tagID = type(tag) == "table" and tag.tagID
	if tagID then
		if TAG_GROUP[tagID] then kinds.questGroup = true end
		if TAG_DUNGEON[tagID] or TAG_RAID[tagID] then kinds.questDungeon = true end
		if TAG_PVP[tagID] then kinds.questPvP = true end
	end
	if (questID and (Call(Q.GetTimeAllowed, questID) or 0) > 0) or TextHas("timed") then kinds.questTimed = true end
	if TextHas("escort") then kinds.questEscort = true end
	return kinds
end

local function KindsAllowed(kinds)
	local any = false
	for key in pairs(kinds) do
		any = true
		if not S.db.auto[key] then return false end
	end
	return any or S.db.auto.questNormal
end

-- Pre-check in gossip and greeting lists (the full check runs when the quest window opens).
local function ListAllowed(isTrivial, frequency, isRepeatable)
	local kinds = {}
	if isTrivial then kinds.questTrivial = true end
	if (frequency and frequency > 0) or isRepeatable then kinds.questRepeat = true end
	return KindsAllowed(kinds)
end

local function OnQuestDetail()
	if not On("questAccept") then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
		return
	end
	if KindsAllowed(DetailKinds()) then AcceptQuest() end
end

-- A quest a group member shares (escorts and group events start like this too)
local function OnQuestAcceptConfirm()
	if not On("questAccept") or not S.db.auto.questShared then return end
	if ConfirmAcceptQuest then
		ConfirmAcceptQuest()
		StaticPopup_Hide("QUEST_ACCEPT")
	end
end

local function OnQuestProgress()
	if On("questTurnIn") and IsQuestCompletable() then CompleteQuest() end
end

-- Sell value of a reward the player can choose (nil while the item is not known to the client yet)
local function ChoiceValue(i)
	local link = GetQuestItemLink and GetQuestItemLink("choice", i)
	if not link then return nil end
	local _, _, count = GetQuestItemInfo("choice", i)
	local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local price = select(11, GetInfo(link))
	if not price then return nil end
	return price * math.max(count or 1, 1)
end

local function OnQuestComplete()
	if not On("questTurnIn") then return end
	if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end
	local choices = GetNumQuestChoices()
	if choices <= 1 then
		GetQuestReward(choices)
		return
	end
	if S.db.auto.questReward ~= "VALUE" then return end
	local best, bestValue = nil, -1
	for i = 1, choices do
		local value = ChoiceValue(i)
		if not value then return end   -- not all rewards known yet: leave it to the player
		if value > bestValue then best, bestValue = i, value end
	end
	if best then GetQuestReward(best) end
end

local function OnQuestGreeting()
	if On("questTurnIn") then
		for i = 1, GetNumActiveQuests() do
			local _, complete = GetActiveTitle(i)
			if complete then SelectActiveQuest(i) return end
		end
	end
	if On("questAccept") then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial, frequency, isRepeatable = nil, nil, nil
			if GetAvailableQuestInfo then isTrivial, frequency, isRepeatable = GetAvailableQuestInfo(i) end
			if ListAllowed(isTrivial, frequency, isRepeatable) then SelectAvailableQuest(i) return end
		end
	end
end

------------------------------------------------------------------------
-- Gossip: quests first (when quest automation is on), then the only option of a vendor, flight
-- master, innkeeper, trainer or banker
------------------------------------------------------------------------
-- Gossip icons of service NPCs (file IDs of Blizzard's gossip icons)
local SERVICE_ICONS = {
	[132050] = true, -- banker
	[132052] = true, -- innkeeper
	[132057] = true, -- flight master
	[132058] = true, -- trainer
	[132060] = true, -- vendor
}

local function OnGossipShow()
	local G = C_GossipInfo
	if not G or Paused() then return end
	if S:Get("auto", "questTurnIn") then
		for _, quest in ipairs(G.GetActiveQuests() or {}) do
			if quest.isComplete then G.SelectActiveQuest(quest.questID) return end
		end
	end
	if S:Get("auto", "questAccept") then
		for _, quest in ipairs(G.GetAvailableQuests() or {}) do
			if ListAllowed(quest.isTrivial, quest.frequency, quest.repeatable) then
				G.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
	if not S:Get("auto", "gossip") then return end
	if #(G.GetActiveQuests() or {}) > 0 or #(G.GetAvailableQuests() or {}) > 0 then return end
	local options = G.GetOptions() or {}
	local only = options[1]
	if #options == 1 and only.gossipOptionID and SERVICE_ICONS[only.icon] then
		G.SelectOption(only.gossipOptionID)
	end
end

------------------------------------------------------------------------
-- Decline duels, guild invites and guild charters
------------------------------------------------------------------------
local function OnDuel()
	if not S:Get("auto", "declineDuels") then return end
	CancelDuel()
	StaticPopup_Hide("DUEL_REQUESTED")
end

local function OnGuildInvite()
	if not S:Get("auto", "declineGuild") then return end
	DeclineGuild()
	StaticPopup_Hide("GUILD_INVITE")
end

local function OnPetition()
	if not S:Get("auto", "declineGuild") then return end
	-- only charters offered by someone else, never your own
	local _, _, _, _, originator, isOriginator = GetPetitionInfo()
	if originator and not isOriginator then ClosePetition() end
end

------------------------------------------------------------------------
-- Accept group invites from friends and guild members
------------------------------------------------------------------------
local function IsFriendGUID(guid)
	if not guid or S.IsSecret(guid) then return false end
	if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
	if IsGuildMember and IsGuildMember(guid) then return true end
	if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then return true end
	return false
end

local function OnPartyInvite(_, name, _, _, _, _, _, guid)
	if not On("acceptInvites") then return end
	if IsFriendGUID(guid) then
		AcceptGroup()
		StaticPopup_Hide("PARTY_INVITE")
		S.Print(L.INVITE_ACCEPTED:format(S.IsSecret(name) and "?" or tostring(name)))
	end
end

------------------------------------------------------------------------
-- Accept resurrections (not while the player who casts it is still fighting)
------------------------------------------------------------------------
local function CasterInCombat(name)
	if not name or S.IsSecret(name) then return false end
	local prefix, count = IsInRaid() and "raid" or "party", GetNumGroupMembers()
	for i = 1, count do
		local unit = prefix .. i
		if UnitExists(unit) and UnitName(unit) == name then return UnitAffectingCombat(unit) end
	end
	return false
end

local function OnResurrect(_, name)
	if not On("acceptRes") or CasterInCombat(name) then return end
	C_Timer.After(0.5, function()
		AcceptResurrect()
		for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do
			StaticPopup_Hide(which)
		end
	end)
end

------------------------------------------------------------------------
-- Mail: "Take all" button (only when the client has no own button for it)
------------------------------------------------------------------------
local taking
local function TakeStep()
	if not taking or not (InboxFrame and InboxFrame:IsVisible()) then taking = nil return end
	for i = GetInboxNumItems(), 1, -1 do
		local _, _, _, _, money, cod, _, hasItem, _, _, _, _, isGM = GetInboxHeaderInfo(i)
		if not isGM and (cod or 0) == 0 then
			if money and money > 0 then
				TakeInboxMoney(i)
				C_Timer.After(0.3, TakeStep)
				return
			elseif hasItem then
				for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
					if GetInboxItem(i, a) then
						TakeInboxItem(i, a)
						C_Timer.After(0.3, TakeStep)
						return
					end
				end
			end
		end
	end
	taking = nil
	S.Print(L.MAIL_DONE)
end

local function CreateMailButton()
	if M.mailButton or not InboxFrame or OpenAllMail then return end
	local b = CreateFrame("Button", "SundryTakeAllButton", InboxFrame, "UIPanelButtonTemplate")
	b:SetSize(120, 24)
	b:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 100)
	b:SetText(L.MAIL_TAKE_ALL)
	b:SetScript("OnClick", function()
		if taking then return end
		taking = true
		TakeStep()
	end)
	M.mailButton = b
end

------------------------------------------------------------------------
-- Trainer: "Learn all"
------------------------------------------------------------------------
local function LearnAll()
	local learned, cost = 0, 0
	local function Step()
		for i = 1, GetNumTrainerServices() do
			local _, kind = GetTrainerServiceInfo(i)
			if kind == "available" then
				local price = GetTrainerServiceCost(i) or 0
				if price > GetMoney() then break end
				BuyTrainerService(i)
				learned, cost = learned + 1, cost + price
				C_Timer.After(0.3, Step)
				return
			end
		end
		if learned > 0 then S.Print(L.TRAINER_DONE:format(learned, GetMoneyString and GetMoneyString(cost, true) or cost)) end
	end
	Step()
end

local function CreateTrainerButton()
	if M.trainerButton or not ClassTrainerFrame then return end
	local b = CreateFrame("Button", "SundryLearnAllButton", ClassTrainerFrame, "UIPanelButtonTemplate")
	b:SetSize(100, 22)
	local anchor = ClassTrainerTrainButton or ClassTrainerFrame.TrainButton
	if anchor then
		b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
	else
		b:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -100, 6)
	end
	b:SetText(L.TRAINER_ALL)
	b:SetScript("OnClick", LearnAll)
	M.trainerButton = b
end

------------------------------------------------------------------------
function M:Init()
	S:On("QUEST_DETAIL", OnQuestDetail)
	S:On("QUEST_PROGRESS", OnQuestProgress)
	S:On("QUEST_COMPLETE", OnQuestComplete)
	S:On("QUEST_GREETING", OnQuestGreeting)
	S:On("QUEST_ACCEPT_CONFIRM", OnQuestAcceptConfirm)
	S:On("GOSSIP_SHOW", OnGossipShow)
	S:On("DUEL_REQUESTED", OnDuel)
	S:On("GUILD_INVITE_REQUEST", OnGuildInvite)
	S:On("PETITION_SHOW", OnPetition)
	S:On("PARTY_INVITE_REQUEST", OnPartyInvite)
	S:On("RESURRECT_REQUEST", OnResurrect)
	S:On("MAIL_SHOW", function() CreateMailButton(); M:Apply() end)
	S:On("MAIL_CLOSED", function() taking = nil end)
	S.OnAddonLoaded("Blizzard_TrainerUI", function() CreateTrainerButton(); M:Apply() end)
end

function M:Apply()
	if self.mailButton then self.mailButton:SetShown(S:Get("auto", "openMail") and true or false) end
	if self.trainerButton then self.trainerButton:SetShown(S:Get("auto", "trainAll") and true or false) end
end
