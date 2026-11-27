local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("tooltip", M)

-- Tooltip: at the mouse, hidden in combat, class coloured names, the unit's target, no health bar,
-- item and spell IDs. In combat the client may hide unit data (secret values); then these extras
-- simply stay out.

local MODIFIERS = { SHIFT = IsShiftKeyDown, CTRL = IsControlKeyDown, ALT = IsAltKeyDown }

local function TooltipUnit(tt)
	if not tt.GetUnit then return nil end
	local ok, _, unit = pcall(tt.GetUnit, tt)
	if not ok or not unit or S.IsSecret(unit) then return nil end
	return unit
end

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	if not class or S.IsSecret(class) then return nil end
	return C_ClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

------------------------------------------------------------------------
local function OnUnit(tt)
	if tt ~= GameTooltip or not S:IsEnabled("tooltip") then return end
	local db = S.db.tooltip
	if db.combatHide and InCombatLockdown() then
		local mod = MODIFIERS[db.combatModifier]
		if not (mod and mod()) then tt:Hide() return end
	end
	local unit = TooltipUnit(tt)
	if not unit then return end
	if db.classColor and UnitIsPlayer(unit) then
		local c = ClassColor(unit)
		local line = GameTooltipTextLeft1
		if c and line then line:SetTextColor(c.r, c.g, c.b) end
	end
	if db.target then
		local target = unit .. "target"
		if UnitExists(target) then
			local name = UnitName(target)
			if name and not S.IsSecret(name) then
				local text = name
				if UnitIsUnit(target, "player") then
					text = "|cffff4040" .. L.TARGET_YOU .. "|r"
				elseif UnitIsPlayer(target) then
					local c = ClassColor(target)
					if c then text = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
				end
				tt:AddLine(L.TARGET_LINE:format(text), 1, 0.82, 0)
				tt:Show()
			end
		end
	end
end

local function AddID(tt, label, id)
	if not id or S.IsSecret(id) or not S:Get("tooltip", "ids") then return end
	tt:AddLine(("%s |cffffffff%s|r"):format(label, tostring(id)), 0.6, 0.6, 0.6)
	tt:Show()
end

------------------------------------------------------------------------
local function DefaultAnchor(tt, parent)
	if not S:Get("tooltip", "cursor") or tt ~= GameTooltip then return end
	-- only for tooltips Blizzard would put in the corner (units in the world, frames without an anchor)
	tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 24, 4)
end

local function ApplyHealthBar()
	local bar = GameTooltipStatusBar
	if not bar then return end
	local show = not S:IsEnabled("tooltip") or S.db.tooltip.healthBar
	bar:SetAlpha(show and 1 or 0)
end

function M:Init()
	S.Hook("GameTooltip_SetDefaultAnchor", DefaultAnchor)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		local T = Enum.TooltipDataType
		TooltipDataProcessor.AddTooltipPostCall(T.Unit, OnUnit)
		TooltipDataProcessor.AddTooltipPostCall(T.Item, function(tt, data)
			AddID(tt, L.ITEM_ID, data and data.id)
		end)
		TooltipDataProcessor.AddTooltipPostCall(T.Spell, function(tt, data)
			AddID(tt, L.SPELL_ID, data and data.id)
		end)
	else
		GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
		GameTooltip:HookScript("OnTooltipSetItem", function(tt)
			local _, link = tt:GetItem()
			AddID(tt, L.ITEM_ID, link and tonumber(link:match("item:(%d+)")))
		end)
		GameTooltip:HookScript("OnTooltipSetSpell", function(tt)
			AddID(tt, L.SPELL_ID, select(2, tt:GetSpell()))
		end)
	end
	if GameTooltipStatusBar then
		GameTooltipStatusBar:HookScript("OnShow", ApplyHealthBar)
	end
	S:On("PLAYER_REGEN_DISABLED", function()
		if S:Get("tooltip", "combatHide") and GameTooltip:IsShown() and TooltipUnit(GameTooltip) then
			local mod = MODIFIERS[S.db.tooltip.combatModifier]
			if not (mod and mod()) then GameTooltip:Hide() end
		end
	end)
end

function M:Apply()
	ApplyHealthBar()
end
