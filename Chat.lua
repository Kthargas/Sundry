local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("chat", M)

-- Chat: arrow keys walk through what you sent (without Alt), the sent lines survive a reload or
-- logout, clickable links, short channel names, hidden chat buttons, the input box above the chat,
-- more lines per window and a window to copy the chat.
--
-- In instances the client may hide chat text (secret values); links, short channel names and the copy
-- window then leave those lines untouched.

local function ChatFrames()
	local list = {}
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local f = _G["ChatFrame" .. i]
		if f then list[#list + 1] = f end
	end
	return list
end

local function EditBox(frame)
	return frame.editBox or _G[frame:GetName() .. "EditBox"]
end

------------------------------------------------------------------------
-- Arrow keys and kept history
------------------------------------------------------------------------
local restoring
local function Remember(editBox, text)
	if restoring or not S:Get("chat", "keepHistory") then return end
	if type(text) ~= "string" or S.IsSecret(text) or text == "" then return end
	local list = S.char.chatHistory
	for i = #list, 1, -1 do
		if list[i] == text then table.remove(list, i) end
	end
	list[#list + 1] = text
	local max = S.db.chat.historySize or 50
	while #list > max do table.remove(list, 1) end
end

local function SetupEditBox(editBox)
	if editBox.sundry then return end
	editBox.sundry = true
	if editBox.AddHistoryLine then
		hooksecurefunc(editBox, "AddHistoryLine", Remember)
	end
end

local function ApplyEditBoxes()
	local db = S.db.chat
	local on = S:IsEnabled("chat")
	for _, frame in ipairs(ChatFrames()) do
		local box = EditBox(frame)
		if box then
			SetupEditBox(box)
			if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(not (on and db.arrowKeys)) end
			if on and db.editTop then
				box.sundryMoved = true
				box:ClearAllPoints()
				box:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -5, 22)
				box:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 5, 22)
			elseif box.sundryMoved then
				box.sundryMoved = nil
				box:ClearAllPoints()
				box:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
				box:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 5, -2)
			end
		end
	end
end

-- Put the kept lines back into the input history (all chat windows share ChatFrame1's box by default)
local function RestoreHistory()
	if not S:Get("chat", "keepHistory") then return end
	restoring = true
	for _, frame in ipairs(ChatFrames()) do
		local box = EditBox(frame)
		if box and box.AddHistoryLine then
			for _, text in ipairs(S.char.chatHistory) do box:AddHistoryLine(text) end
		end
	end
	restoring = nil
end

------------------------------------------------------------------------
-- Links: web addresses become clickable and open a box to copy them
------------------------------------------------------------------------
local LINK = "|cff7fbfff|Haddon:Sundry:url:%s|h[%s]|h|r"
local PATTERNS = {
	"(https?://[%w%-%.:]+[%w/%%%?%-%._~:#&=+]*)",
	"(www%.[%w%-]+%.[%w%-%.]+[%w/%%%?%-%._~:#&=+]*)",
}

local function Linkify(text)
	for _, pattern in ipairs(PATTERNS) do
		text = text:gsub(pattern, function(url)
			return LINK:format(url, url)
		end)
	end
	return text
end

local function UrlFilter(_, _, message, ...)
	if not S:Get("chat", "urls") or type(message) ~= "string" or S.IsSecret(message) then return false end
	if not (message:find("://", 1, true) or message:find("www.", 1, true)) then return false end
	-- leave messages with links (items, spells ...) alone, their text must stay as it is
	if message:find("|H", 1, true) then return false end
	return false, Linkify(message), ...
end

local URL_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_EMOTE",
}

local function AddFilter(event, fn)
	if ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter(event, fn)
	elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
		ChatFrameUtil.AddMessageEventFilter(event, fn)
	end
end

StaticPopupDialogs["SUNDRY_COPY_URL"] = {
	text = L.COPY_URL,
	button1 = CLOSE or OKAY,
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(self, data)
		local box = self.editBox or (self.GetEditBox and self:GetEditBox())
		if box then
			box:SetText(data or "")
			box:HighlightText()
			box:SetFocus()
		end
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function OnLink(link)
	if type(link) ~= "string" then return end
	local url = link:match("^addon:Sundry:url:(.+)$")
	if url then StaticPopup_Show("SUNDRY_COPY_URL", nil, nil, url) end
end

------------------------------------------------------------------------
-- Short channel names: "[1. General - Elwynn Forest]" becomes "[1]". The chat windows' AddMessage is
-- wrapped only once this option is switched on.
------------------------------------------------------------------------
local function Shorten(text)
	return (text:gsub("|Hchannel:(.-)|h%[(%d+)%. .-%]|h", "|Hchannel:%1|h[%2]|h"))
end

local function HookAddMessage(frame)
	if frame.sundryAddMessage or frame == ChatFrame2 then return end
	frame.sundryAddMessage = true
	local original = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		if type(text) == "string" and S:Get("chat", "shortChannels") and not S.IsSecret(text) then
			text = Shorten(text)
		end
		return original(self, text, ...)
	end
end

------------------------------------------------------------------------
-- Chat buttons, lines per window
------------------------------------------------------------------------
local function ChatButtons()
	local list = {}
	for _, name in ipairs({ "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
		"ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	for _, frame in ipairs(ChatFrames()) do
		local bf = _G[frame:GetName() .. "ButtonFrame"]
		if bf then list[#list + 1] = bf end
	end
	return list
end

local function ApplyButtons()
	local hide = S:Get("chat", "hideButtons")
	for _, b in ipairs(ChatButtons()) do
		b:SetAlpha(hide and 0 or 1)
		if not InCombatLockdown() and b.EnableMouse and b:IsMouseEnabled() ~= not hide then
			b:EnableMouse(not hide)
		end
	end
end

local function ApplyLines()
	local lines = S:Get("chat", "lines")
	if not lines then return end
	for _, frame in ipairs(ChatFrames()) do
		-- SetMaxLines empties the window, so only when the number really changes
		if frame.GetMaxLines and frame:GetMaxLines() ~= lines then frame:SetMaxLines(lines) end
	end
end

------------------------------------------------------------------------
-- Copy window: the chat window's lines in a box to select and copy
------------------------------------------------------------------------
local copyFrame
local function CopyFrame()
	if copyFrame then return copyFrame end
	local f = CreateFrame("Frame", "SundryCopyFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(560, 400)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.TitleText then f.TitleText:SetText(L.COPY_TITLE) end
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -30)
	scroll:SetPoint("BOTTOMRIGHT", -32, 10)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetWidth(510)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(box)
	f.box = box
	tinsert(UISpecialFrames, "SundryCopyFrame")
	copyFrame = f
	return f
end

function M:ShowCopy(frame)
	frame = frame or DEFAULT_CHAT_FRAME
	if not frame or not frame.GetNumMessages then return end
	local lines = {}
	for i = 1, frame:GetNumMessages() do
		local text = frame:GetMessageInfo(i)
		if type(text) == "string" and not S.IsSecret(text) then
			-- remove colours, links and textures so the text can be pasted anywhere
			text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
			lines[#lines + 1] = text
		end
	end
	local f = CopyFrame()
	f.box:SetText(table.concat(lines, "\n"))
	f:Show()
	f.box:SetFocus()
	f.box:HighlightText()
end

local function CopyButton(frame)
	if frame.sundryCopy then return frame.sundryCopy end
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(18, 18)
	b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	b:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetAlpha(0)
	b:SetScript("OnClick", function() M:ShowCopy(frame) end)
	b:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L.COPY_TITLE)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self:SetAlpha(0)
		GameTooltip:Hide()
	end)
	frame.sundryCopy = b
	return b
end

local function ApplyCopy()
	local on = S:Get("chat", "copy")
	for _, frame in ipairs(ChatFrames()) do
		if on then CopyButton(frame):Show() elseif frame.sundryCopy then frame.sundryCopy:Hide() end
	end
end

------------------------------------------------------------------------
function M:Init()
	for _, event in ipairs(URL_EVENTS) do AddFilter(event, UrlFilter) end
	S.Hook("SetItemRef", OnLink)
	S.Hook("FCF_OpenTemporaryWindow", function() M:Apply() end)
	RestoreHistory()
end

function M:Apply()
	if S:Get("chat", "shortChannels") then
		for _, frame in ipairs(ChatFrames()) do HookAddMessage(frame) end
	end
	ApplyEditBoxes()
	ApplyButtons()
	ApplyLines()
	ApplyCopy()
end
