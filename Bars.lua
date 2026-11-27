local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("bars", M)

-- Bars and screen: micro menu and bag bar (frames, fading, hiding single buttons, collapsing the bag
-- bar), red error messages, key binding and macro texts, action bar art, out of range colour, class
-- colours in the unit frames and the combat text on the portraits.
--
-- Blizzard's art is never hidden with Hide(): Blizzard shows it again on every state change. Sundry
-- sets the alpha to 0 instead, which Blizzard leaves alone.

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function SetAlphaOf(region, alpha)
	if region and region.SetAlpha then region:SetAlpha(alpha) end
end

local collapseButton   -- Sundry's arrow next to the backpack (created with the bag bar)

-- Thin line frame from plain colour, like Mundi's "line" style
local function LineBorder(frame)
	if frame.sundryLine then return frame.sundryLine end
	local edges = {}
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(0, 0, 0, 0.9)
		edges[i] = t
	end
	edges[1]:SetPoint("TOPLEFT", 1, -1); edges[1]:SetPoint("TOPRIGHT", -1, -1); edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT", 1, 1); edges[2]:SetPoint("BOTTOMRIGHT", -1, 1); edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT", 1, -1); edges[3]:SetPoint("BOTTOMLEFT", 1, 1); edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT", -1, -1); edges[4]:SetPoint("BOTTOMRIGHT", -1, 1); edges[4]:SetWidth(1)
	frame.sundryLine = edges
	return edges
end

local function ShowLine(frame, shown)
	local edges = shown and LineBorder(frame) or frame.sundryLine
	if not edges then return end
	for i = 1, 4 do edges[i]:SetShown(shown) end
end

------------------------------------------------------------------------
-- Micro menu
------------------------------------------------------------------------
-- The dark rounded background behind each micro button: textures named Background / PushedBackground
-- (Dragonflight style), found by key or by their atlas.
local BG_KEYS = { "Background", "PushedBackground" }

local function MicroButtons()
	local list = {}
	if MicroMenu and MicroMenu.GetLayoutChildren then
		for _, b in ipairs(MicroMenu:GetLayoutChildren()) do list[#list + 1] = b end
	end
	if #list == 0 and MICRO_BUTTONS then
		for _, name in ipairs(MICRO_BUTTONS) do
			if _G[name] then list[#list + 1] = _G[name] end
		end
	end
	return list
end
M.MicroButtons = MicroButtons

local function IsButtonBackground(region)
	local atlas = region.GetAtlas and region:GetAtlas()
	return type(atlas) == "string" and atlas:find("MicroMenu%-ButtonBG") ~= nil
end

local function StyleMicroButton(button, style)
	local alpha = (style == "BLIZZARD") and 1 or 0
	for _, key in ipairs(BG_KEYS) do SetAlphaOf(button[key], alpha) end
	for _, region in ipairs({ button:GetRegions() }) do
		if IsButtonBackground(region) then region:SetAlpha(alpha) end
	end
	ShowLine(button, style == "LINE")
end

local function MicroButtonName(button)
	return button:GetName() or button:GetDebugName()
end
M.MicroButtonName = MicroButtonName

-- Outer frame of a bar: the textures of the bar frame itself and its decorative child frames (border,
-- background, nine-slice). Children that hold buttons, and buttons themselves, stay untouched.
local stripped = {}   -- region -> true, so only what Sundry faded comes back

local function HoldsButton(frame, buttons)
	for _, b in ipairs(buttons) do
		local p = b
		while p do
			if p == frame then return true end
			p = p:GetParent()
		end
	end
	return false
end

local function StripFrame(frame, buttons, hide)
	if not frame then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and (hide or stripped[region]) then
			region:SetAlpha(hide and 0 or 1)
			stripped[region] = hide or nil
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local kind = child:GetObjectType()
		if kind == "Frame" and not child:IsMouseEnabled() and not HoldsButton(child, buttons)
			and child ~= collapseButton and (hide or stripped[child]) then
			child:SetAlpha(hide and 0 or 1)
			stripped[child] = hide or nil
		end
	end
end
M.StripFrame = StripFrame

-- Order of the visible micro buttons when some are hidden. "BLIZZARD" keeps Blizzard's layout (a hidden
-- button leaves a gap); the other directions line the visible buttons up from the bar's corner.
local CHAIN = {
	RIGHT = { "TOPLEFT", "LEFT", "RIGHT", 1, 0 },
	LEFT = { "TOPRIGHT", "RIGHT", "LEFT", -1, 0 },
	DOWN = { "TOPLEFT", "TOP", "BOTTOM", 0, -1 },
	UP = { "BOTTOMLEFT", "BOTTOM", "TOP", 0, 1 },
}

local function LayoutMicro(buttons, hiddenOf)
	local db = S.db.bars
	local chain = S:IsEnabled("bars") and CHAIN[db.microOrder]
	local menu = buttons[1] and buttons[1]:GetParent()
	if not chain or not menu then return end
	local corner, point, relPoint, dx, dy = chain[1], chain[2], chain[3], chain[4], chain[5]
	local gap = db.microSpacing or 0
	local prev
	for _, b in ipairs(buttons) do
		b:ClearAllPoints()
		if hiddenOf(b) then
			b:SetPoint("CENTER", menu, "CENTER")
		elseif not prev then
			b:SetPoint(corner, menu, corner, 0, 0)
			prev = b
		else
			b:SetPoint(point, prev, relPoint, dx * gap, dy * gap)
			prev = b
		end
	end
end

local laying
local function ApplyMicro()
	if laying then return end
	laying = true
	local db = S.db.bars
	local on = S:IsEnabled("bars")
	local style = on and db.microStyle or "BLIZZARD"
	local buttons = MicroButtons()
	local function Hidden(button) return on and db.microHide[MicroButtonName(button)] and true or false end
	for _, button in ipairs(buttons) do
		StyleMicroButton(button, style)
		local hidden = Hidden(button)
		button:SetAlpha(hidden and 0 or 1)
		if not InCombatLockdown() then button:EnableMouse(not hidden) end
	end
	LayoutMicro(buttons, Hidden)
	local hideFrame = on and db.microFrame or false
	StripFrame(MicroMenuContainer, buttons, hideFrame)
	StripFrame(MicroMenu, buttons, hideFrame)
	laying = nil
end

------------------------------------------------------------------------
-- Bag bar: frame style, collapse arrow
------------------------------------------------------------------------
local function BagSlots()
	local list = {}
	for i = 0, 3 do
		local slot = _G["CharacterBag" .. i .. "Slot"]
		if slot then list[#list + 1] = slot end
	end
	if CharacterReagentBag0Slot then list[#list + 1] = CharacterReagentBag0Slot end
	return list
end

local function Backpack()
	return MainMenuBarBackpackButton
end

local function ApplyBagCollapse()
	local on = S:Get("bars", "bagCollapse")
	local collapsed = on and S.char.bagsCollapsed
	for _, slot in ipairs(BagSlots()) do
		slot:SetAlpha(collapsed and 0 or 1)
		if not InCombatLockdown() then slot:EnableMouse(not collapsed) end
	end
	if collapseButton then
		collapseButton:SetShown(on and true or false)
		-- arrow points to where the bags will go
		collapseButton.arrow:SetRotation(collapsed and math.pi or 0)
	end
	-- Blizzard's own toggle (newer clients) would fight with Sundry's: fade it out while Sundry's is on.
	if BagBarExpandToggle then
		BagBarExpandToggle:SetAlpha(on and 0 or 1)
		if not InCombatLockdown() then BagBarExpandToggle:EnableMouse(not on) end
	end
end

local function CreateCollapseButton()
	local pack = Backpack()
	if collapseButton or not pack then return end
	local b = CreateFrame("Button", "SundryBagCollapseButton", pack:GetParent() or UIParent)
	b:SetSize(12, 22)
	b:SetPoint("RIGHT", pack, "LEFT", -2, 0)
	local arrow = b:CreateTexture(nil, "ARTWORK")
	arrow:SetAllPoints()
	if not arrow:SetAtlas("bag-arrow") then
		arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	end
	b.arrow = arrow
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:SetScript("OnClick", function()
		S.char.bagsCollapsed = not S.char.bagsCollapsed
		ApplyBagCollapse()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(S.char.bagsCollapsed and L.BAGS_EXPAND or L.BAGS_COLLAPSE)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	collapseButton = b
end

local function ApplyBags()
	local db = S.db.bars
	local style = S:IsEnabled("bars") and db.bagStyle or "BLIZZARD"
	local buttons = BagSlots()
	if Backpack() then table.insert(buttons, Backpack()) end
	for _, b in ipairs(buttons) do
		-- the round slot art behind the bag icon (newer clients: SlotHighlightTexture / NormalTexture)
		local normal = b.GetNormalTexture and b:GetNormalTexture()
		SetAlphaOf(normal, style == "BLIZZARD" and 1 or 0)
		ShowLine(b, style == "LINE")
	end
	CreateCollapseButton()
	ApplyBagCollapse()
	local hideFrame = S:IsEnabled("bars") and db.bagFrame or false
	StripFrame(BagsBar, buttons, hideFrame)
	-- older layout: micro menu and bags share one bar
	if MicroButtonAndBagsBar then
		local both = {}
		for _, b in ipairs(buttons) do both[#both + 1] = b end
		for _, b in ipairs(MicroButtons()) do both[#both + 1] = b end
		StripFrame(MicroButtonAndBagsBar, both, hideFrame or (S:IsEnabled("bars") and db.microFrame) or false)
	end
end

------------------------------------------------------------------------
-- Fade micro menu and bag bar until the mouse is over them
------------------------------------------------------------------------
local fader
local function Containers()
	return MicroMenuContainer or MicroMenu or MicroButtonAndBagsBar, BagsBar or MicroButtonAndBagsBar
end

local function UpdateFade()
	local micro, bags = Containers()
	local db = S.db.bars
	local on = S:IsEnabled("bars")
	local function Fade(frame, enabled, alpha, extra)
		if not frame then return end
		if not (on and enabled) then frame:SetAlpha(1) return end
		local over = frame:IsMouseOver() or (extra and extra:IsShown() and extra:IsMouseOver())
		frame:SetAlpha(over and 1 or alpha)
	end
	Fade(micro, db.microFade, db.microAlpha)
	if bags ~= micro then Fade(bags, db.bagFade, db.bagAlpha, collapseButton) end
end

local function ApplyFade()
	local db = S.db.bars
	local want = S:IsEnabled("bars") and (db.microFade or db.bagFade)
	if want and not fader then
		fader = CreateFrame("Frame")
		local elapsed = 0
		fader:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + dt
			if elapsed < 0.1 then return end
			elapsed = 0
			UpdateFade()
		end)
	end
	if fader then fader:SetShown(want and true or false) end
	UpdateFade()
end

------------------------------------------------------------------------
-- Error messages: the red text in the middle of the screen
------------------------------------------------------------------------
local ERROR_KEYS = {
	"ERR_OUT_OF_ENERGY", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_MANA", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_RUNIC_POWER",
	"ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN", "ERR_GENERIC_NO_TARGET",
	"ERR_NO_ATTACK_TARGET", "ERR_INVALID_ATTACK_TARGET", "ERR_BADATTACKFACING", "ERR_BADATTACKPOS",
	"ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE", "ERR_NOT_WHILE_MOVING", "ERR_USE_TOO_FAR",
	"SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_NOT_READY",
	"SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_BAD_TARGETS", "SPELL_FAILED_UNIT_NOT_INFRONT",
	"SPELL_FAILED_MOVING", "SPELL_FAILED_TARGETS_DEAD", "SPELL_FAILED_NO_COMBO_POINTS",
	"SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_TOO_CLOSE", "SPELL_FAILED_NOT_BEHIND",
	"SPELL_FAILED_NOT_INFRONT", "SPELL_FAILED_NO_ENDURANCE", "OUT_OF_ENERGY", "OUT_OF_RAGE", "OUT_OF_MANA",
}
local filtered
local function FilteredMessages()
	if not filtered then
		filtered = {}
		for _, key in ipairs(ERROR_KEYS) do
			local text = _G[key]
			if type(text) == "string" then filtered[text] = true end
		end
	end
	return filtered
end

local function ShouldFilter(message)
	local mode = S:Get("bars", "errors")
	if not mode or mode == "OFF" then return false end
	if mode == "COMBAT" and not InCombatLockdown() then return false end
	if mode == "ALL" then return true end
	if S.IsSecret(message) then return false end
	return FilteredMessages()[message] or false
end

-- UIErrorsFrame keeps its own event, but Sundry takes UI_ERROR_MESSAGE over and passes on what is not
-- filtered. (Hooking AddMessage would be too late: the text is already on screen.)
local errorsTaken
local function TakeErrors()
	if errorsTaken or not UIErrorsFrame then return end
	local handler = UIErrorsFrame:GetScript("OnEvent")
	if not handler then return end
	errorsTaken = true
	UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	S:On("UI_ERROR_MESSAGE", function(event, kind, message)
		if ShouldFilter(message) then return end
		handler(UIErrorsFrame, event, kind, message)
	end)
end

------------------------------------------------------------------------
-- Action buttons: key binding and macro texts, out of range colour
------------------------------------------------------------------------
local BAR_PREFIXES = {
	"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "PetActionButton",
	"StanceButton",
}

local function ActionButtons()
	local list = {}
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b then list[#list + 1] = b end
		end
	end
	return list
end

local function ApplyButtonTexts()
	local db = S.db.bars
	local on = S:IsEnabled("bars")
	for _, b in ipairs(ActionButtons()) do
		local hotkey = b.HotKey or _G[(b:GetName() or "") .. "HotKey"]
		local name = b.Name or _G[(b:GetName() or "") .. "Name"]
		SetAlphaOf(hotkey, (on and not db.hotkeys) and 0 or 1)
		SetAlphaOf(name, (on and not db.macroNames) and 0 or 1)
	end
end

local RED = { 1, 0.25, 0.25 }
local function RangeColor(button, checksRange, inRange)
	if not S:Get("bars", "rangeColor") then return end
	local icon = button.icon or button.Icon
	if not icon or S.IsSecret(checksRange) or S.IsSecret(inRange) then return end
	if checksRange and inRange == false then
		icon:SetVertexColor(RED[1], RED[2], RED[3])
	elseif button.sundryRed then
		icon:SetVertexColor(1, 1, 1)
	end
	button.sundryRed = checksRange and inRange == false
end

------------------------------------------------------------------------
-- Action bar art (gryphons, bar background); Edit Mode may offer this too
------------------------------------------------------------------------
local function ArtRegions()
	local list = {}
	local bar = MainMenuBar or MainActionBar
	if bar then
		if bar.EndCaps then list[#list + 1] = bar.EndCaps end
		if bar.BorderArt then list[#list + 1] = bar.BorderArt end
		if bar.Background then list[#list + 1] = bar.Background end
	end
	for _, name in ipairs({ "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarTexture0",
		"MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3", "MainMenuBarArtFrameBackground" }) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	local art = MainMenuBarArtFrame
	if art then
		if art.LeftEndCap then list[#list + 1] = art.LeftEndCap end
		if art.RightEndCap then list[#list + 1] = art.RightEndCap end
	end
	return list
end

local function ApplyBarArt()
	local show = not S:IsEnabled("bars") or S.db.bars.barArt
	for _, region in ipairs(ArtRegions()) do SetAlphaOf(region, show and 1 or 0) end
end

------------------------------------------------------------------------
-- Unit frames: class coloured health bars, combat text on the portraits
------------------------------------------------------------------------
local function ClassColorBar(bar, unit)
	if not bar or not unit or S.IsSecret(unit) then return end
	if not S:Get("bars", "classColors") then
		if bar.sundryColored then
			bar.sundryColored = nil
			if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(false) end
			bar:SetStatusBarColor(bar.sundryR or 1, bar.sundryG or 1, bar.sundryB or 1)
		end
		return
	end
	if not UnitIsPlayer(unit) then return end
	local _, class = UnitClass(unit)
	local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
	if not c then return end
	if not bar.sundryColored then
		bar.sundryR, bar.sundryG, bar.sundryB = bar:GetStatusBarColor()
		bar.sundryColored = true
	end
	-- newer health bars are coloured art: desaturate it first so the class colour shows
	if bar.SetStatusBarDesaturated then bar:SetStatusBarDesaturated(true) end
	bar:SetStatusBarColor(c.r, c.g, c.b)
end

local function HitIndicators()
	local list = {}
	for _, name in ipairs({ "PlayerHitIndicator", "PetHitIndicator" }) do
		if _G[name] then list[#list + 1] = _G[name] end
	end
	local main = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
	if main and main.HitIndicator then list[#list + 1] = main.HitIndicator end
	local pet = PetFrame and PetFrame.feedbackText
	if pet then list[#list + 1] = pet end
	return list
end

local function ApplyHitText()
	local show = not S:IsEnabled("bars") or S.db.bars.hitText
	for _, region in ipairs(HitIndicators()) do SetAlphaOf(region, show and 1 or 0) end
end

------------------------------------------------------------------------
function M:Init()
	TakeErrors()
	S.Hook("ActionButton_UpdateRangeIndicator", RangeColor)
	S.Hook("UnitFrameHealthBar_Update", ClassColorBar)
	-- micro buttons and bag slots get their art back from Blizzard on some updates
	S.Hook("UpdateMicroButtons", function() if S:IsEnabled("bars") then ApplyMicro() end end)
	if MicroMenu and MicroMenu.Layout then
		hooksecurefunc(MicroMenu, "Layout", function() if S:IsEnabled("bars") then ApplyMicro() end end)
	end
	S:On("UPDATE_BINDINGS", function() S.AfterCombat("buttonTexts", ApplyButtonTexts) end)
	S:On("ACTIONBAR_SLOT_CHANGED", function() S.AfterCombat("buttonTexts", ApplyButtonTexts) end)
	S:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() M:Apply() end) end)
	S:On("PLAYER_TARGET_CHANGED", function()
		if S:Get("bars", "classColors") then
			local bar = TargetFrame and (TargetFrame.healthbar or TargetFrame.HealthBar)
			if bar then ClassColorBar(bar, "target") end
		end
	end)
end

function M:Apply()
	ApplyMicro()
	ApplyBags()
	ApplyFade()
	S.AfterCombat("buttonTexts", ApplyButtonTexts)
	ApplyBarArt()
	ApplyHitText()
end
