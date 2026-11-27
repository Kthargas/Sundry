local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("windows", M)

-- Move Blizzard's windows (like BlizzMove) and remember where they were put.
--
-- How it stays clear of taint: Sundry never calls ShowUIPanel/HideUIPanel and never touches
-- UIPanelWindows. It only makes the window draggable and puts it back where it was saved, as a
-- post-hook after Blizzard has placed it (UpdateUIPanelPositions and OnShow). Protected windows are
-- not moved in combat; a pending restore runs when combat ends.

-- Windows that are always there, and windows of Blizzard's load-on-demand addons. Names that do not
-- exist in this client are skipped.
local ALWAYS = {
	"CharacterFrame", "SpellBookFrame", "QuestLogFrame", "FriendsFrame", "MerchantFrame", "BankFrame",
	"MailFrame", "OpenMailFrame", "GossipFrame", "QuestFrame", "TradeFrame", "PVEFrame", "DressUpFrame",
	"TabardFrame", "PetStableFrame", "TaxiFrame", "ItemTextFrame", "HelpFrame", "AddonList", "LootFrame",
	"GuildRegistrarFrame", "PetitionFrame", "LFGParentFrame", "WorldStateScoreFrame",
}
local ON_DEMAND = {
	Blizzard_TalentUI = { "PlayerTalentFrame" },
	Blizzard_ClassTalentUI = { "ClassTalentFrame" },
	Blizzard_PlayerSpells = { "PlayerSpellsFrame" },
	Blizzard_AuctionUI = { "AuctionFrame" },
	Blizzard_AuctionHouseUI = { "AuctionHouseFrame" },
	Blizzard_TradeSkillUI = { "TradeSkillFrame" },
	Blizzard_CraftUI = { "CraftFrame" },
	Blizzard_Professions = { "ProfessionsFrame" },
	Blizzard_ProfessionsBook = { "ProfessionsBookFrame" },
	Blizzard_TrainerUI = { "ClassTrainerFrame" },
	Blizzard_MacroUI = { "MacroFrame" },
	Blizzard_BindingUI = { "KeyBindingFrame" },
	Blizzard_InspectUI = { "InspectFrame" },
	Blizzard_Communities = { "CommunitiesFrame" },
	Blizzard_GuildUI = { "GuildFrame" },
	Blizzard_GuildBankUI = { "GuildBankFrame" },
	Blizzard_Collections = { "CollectionsJournal" },
	Blizzard_EncounterJournal = { "EncounterJournal" },
	Blizzard_AchievementUI = { "AchievementFrame" },
	Blizzard_Calendar = { "CalendarFrame" },
	Blizzard_TimeManager = { "TimeManagerFrame" },
	Blizzard_ItemSocketingUI = { "ItemSocketingFrame" },
	Blizzard_ItemUpgradeUI = { "ItemUpgradeFrame" },
	Blizzard_BarbershopUI = { "BarberShopFrame" },
}

local managed = {}       -- name -> frame
local session = {}       -- positions while "remember" is set to this session only
local dragging

local function Store()
	local mode = S.db.windows.remember
	if mode == "CHAR" then return S.char.windows end
	if mode == "SESSION" then return session end
	return S.root.windows
end

local MODIFIERS = {
	SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown,
}

local function Blocked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

------------------------------------------------------------------------
-- Position: top left corner relative to UIParent's bottom left, in screen units (independent of
-- the window's own scale), plus the scale.
------------------------------------------------------------------------
local function Save(name, frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return end
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local entry = Store()[name] or {}
	entry.x, entry.y = left * s, top * s
	Store()[name] = entry
end

local function Restore(name)
	local frame = managed[name]
	local entry = Store()[name]
	if not frame or not entry or not S:IsEnabled("windows") then return end
	if Blocked(frame) then
		S.AfterCombat("window:" .. name, function() Restore(name) end)
		return
	end
	if S.db.windows.scale and entry.scale then frame:SetScale(entry.scale) end
	if entry.x and entry.y then
		local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", entry.x / s, entry.y / s)
	end
end

local function RestoreShown()
	if dragging then return end
	for name, frame in pairs(managed) do
		if frame:IsShown() then Restore(name) end
	end
end

------------------------------------------------------------------------
-- Dragging and scaling
------------------------------------------------------------------------
local function OnDragStart(frame)
	if not S:Get("windows", "move") or dragging then return end
	local mod = MODIFIERS[S.db.windows.modifier]
	if mod and not mod() then return end
	if Blocked(frame) then S.Print(L.NOT_IN_COMBAT) return end
	dragging = frame
	frame:StartMoving()
end

local function OnDragStop(frame)
	if dragging ~= frame then return end
	dragging = nil
	frame:StopMovingOrSizing()
	-- StartMoving marks the window as user placed; Blizzard's layout cache must not keep it.
	if frame.SetUserPlaced and not Blocked(frame) then frame:SetUserPlaced(false) end
	Save(frame.sundryName, frame)
end

local function OnMouseWheel(frame, delta)
	if not S:Get("windows", "scale") or not IsControlKeyDown() or Blocked(frame) then return end
	local name = frame.sundryName
	local left, top = frame:GetLeft(), frame:GetTop()
	local old = frame:GetScale()
	local new = math.max(0.5, math.min(1.6, old + delta * 0.05))
	if math.abs(new - old) < 0.001 then return end
	frame:SetScale(new)
	-- keep the top left corner where it was
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / new, top * old / new)
	end
	local entry = Store()[name] or {}
	entry.scale = new
	Store()[name] = entry
	Save(name, frame)
end

-- Shift + Ctrl + right click: forget this window's position and size (Blizzard places it again the
-- next time it opens)
local function OnMouseUp(frame, button)
	if button ~= "RightButton" or not (IsShiftKeyDown() and IsControlKeyDown()) then return end
	if not S:IsEnabled("windows") or Blocked(frame) then return end
	Store()[frame.sundryName] = nil
	frame:SetScale(frame.sundryScale or 1)
	S.Print(L.WINDOW_RESET:format(frame.sundryName))
end

local function Manage(name)
	local frame = _G[name]
	if managed[name] or type(frame) ~= "table" or not frame.GetObjectType then return end
	if frame:IsForbidden() or (frame:IsProtected() and InCombatLockdown()) then
		S.AfterCombat("manage:" .. name, function() Manage(name) end)
		return
	end
	managed[name] = frame
	frame.sundryName = name
	frame.sundryScale = frame:GetScale()
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", OnDragStart)
	frame:HookScript("OnDragStop", OnDragStop)
	frame:HookScript("OnMouseUp", OnMouseUp)
	frame:HookScript("OnHide", function(self) if dragging == self then OnDragStop(self) end end)
	if S.db.windows.scale then
		frame:EnableMouseWheel(true)
		frame:HookScript("OnMouseWheel", OnMouseWheel)
	end
	frame:HookScript("OnShow", function() Restore(name) end)
	if S.db.windows.clamp then frame:SetClampedToScreen(true) end
	if frame:IsShown() then Restore(name) end
end

function M:ResetAll()
	if InCombatLockdown() then S.Print(L.NOT_IN_COMBAT) return end
	wipe(S.root.windows)
	wipe(S.char.windows)
	wipe(session)
	for _, frame in pairs(managed) do frame:SetScale(frame.sundryScale or 1) end
	S.Print(L.WINDOWS_RESET)
end

function M:Init()
	self.initialized = false
end

-- Hooks are only set once the module is on; switching it off later stops dragging and restoring
-- (the hooks check the switch).
function M:Apply()
	if not S:IsEnabled("windows") or self.initialized then return end
	self.initialized = true
	for _, name in ipairs(ALWAYS) do Manage(name) end
	for addon, names in pairs(ON_DEMAND) do
		S.OnAddonLoaded(addon, function()
			for _, name in ipairs(names) do Manage(name) end
		end)
	end
	S.Hook("UpdateUIPanelPositions", RestoreShown)
end
