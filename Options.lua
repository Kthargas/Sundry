local ADDON, S = ...
local L = S.L
local O = { settings = {} }
S:RegisterModule("options", O)

-- Options in Blizzard's own settings window (Esc > Options > AddOns > Sundry), built only from the stock
-- Settings controls, laid out like Fray and Mundi: a main page, one page per module and an "Actions"
-- page for the buttons. On every module page the first switch turns the whole module on or off and the
-- settings below it are greyed out while it is off.

local function ListOptions(list)
	return function()
		local container = Settings.CreateControlTextContainer()
		for _, item in ipairs(list) do container:Add(item[1], item[2]) end
		return container:GetData()
	end
end

-- A setting stored in S.db[section][field]; changing it applies the module again.
function O:Proxy(category, variable, varType, name, default, get, set)
	local setting = Settings.RegisterProxySetting(category, "SUNDRY_" .. variable, varType, name, default, get, set)
	self.settings[#self.settings + 1] = setting
	return setting
end

function O:Field(category, section, field, varType, name, default, onSet)
	return self:Proxy(category, section:upper() .. "_" .. field:upper(), varType, name, default,
		function()
			local value = S.db[section][field]
			if value == nil then return default end
			return value
		end,
		function(value)
			S.db[section][field] = value
			if onSet then onSet(value) end
			S:Apply(section)
		end)
end

function O:Checkbox(category, section, field, name, tooltip, onSet)
	local setting = self:Field(category, section, field, Settings.VarType.Boolean, name, S.defaults[section][field], onSet)
	return Settings.CreateCheckbox(category, setting, tooltip)
end

function O:Slider(category, section, field, name, tooltip, minValue, maxValue, step, formatter)
	local setting = self:Field(category, section, field, Settings.VarType.Number, name, S.defaults[section][field])
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter or function(value)
		return tostring(math.floor(value + 0.5))
	end)
	return Settings.CreateSlider(category, setting, options, tooltip)
end

function O:Dropdown(category, section, field, name, tooltip, list)
	local setting = self:Field(category, section, field, Settings.VarType.String, name, S.defaults[section][field])
	return Settings.CreateDropdown(category, setting, ListOptions(list), tooltip)
end

local function Header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function DependsOn(child, parent, predicate)
	if child and parent and child.SetParentInitializer then
		child:SetParentInitializer(parent, predicate)
	end
end

local function Percent(value) return L.PERCENT:format(math.floor(value * 100 + 0.5)) end
local function Gold(value) return value == 0 and L.ALWAYS_ASK_OFF or L.GOLD:format(value) end
local function Factor(value) return ("%.1f"):format(value) end

-- Module switch at the top of a page; returns a helper that makes other controls depend on it.
function O:Module(category, layout, name, title, tooltip)
	Header(layout, title)
	local setting = self:Proxy(category, "MODULE_" .. name:upper(), Settings.VarType.Boolean, L.MODULE_ON, true,
		function() return S.db.modules[name] and true or false end,
		function(value)
			S.db.modules[name] = value
			S:Apply(name)
			self:Refresh()
		end)
	local on = Settings.CreateCheckbox(category, setting, tooltip)
	return function(init, parent, predicate)
		DependsOn(init, parent or on, function()
			return S.db.modules[name] and (not predicate or predicate()) and true or false
		end)
		return init
	end
end

local MODIFIER_LIST = {
	{ "NONE", L.MOD_NONE }, { "SHIFT", L.MOD_SHIFT }, { "CTRL", L.MOD_CTRL }, { "ALT", L.MOD_ALT },
}
local STYLE_LIST = {
	{ "BLIZZARD", L.STYLE_BLIZZARD }, { "NONE", L.STYLE_NONE }, { "LINE", L.STYLE_LINE },
}

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
function O:BuildGeneral(category, layout)
	Header(layout, L.SECTION_MODULES)
	for _, entry in ipairs({
		{ "loot", L.PAGE_LOOT }, { "windows", L.PAGE_WINDOWS }, { "bags", L.PAGE_BAGS }, { "bars", L.PAGE_BARS }, { "tooltip", L.PAGE_TOOLTIP },
		{ "chat", L.PAGE_CHAT }, { "auto", L.PAGE_AUTO }, { "misc", L.PAGE_MISC },
	}) do
		local name = entry[1]
		local setting = self:Proxy(category, "OVERVIEW_" .. name:upper(), Settings.VarType.Boolean, entry[2], true,
			function() return S.db.modules[name] and true or false end,
			function(value)
				S.db.modules[name] = value
				S:Apply(name)
				self:Refresh()
			end)
		Settings.CreateCheckbox(category, setting, L["MODULE_TT_" .. name:upper()])
	end

	Header(layout, L.SECTION_GENERAL)
	local own = self:Proxy(category, "CHAR_OWN", Settings.VarType.Boolean, L.OWN_PROFILE, false,
		function() return S.char.own and true or false end,
		function(value) S.SetOwnProfile(value) end)
	Settings.CreateCheckbox(category, own, L.OWN_PROFILE_TT)
	local minimap = self:Proxy(category, "MINIMAP_SHOW", Settings.VarType.Boolean, L.MINIMAP_BUTTON, true,
		function() return not S.db.minimap.hide end,
		function(value)
			S.db.minimap.hide = not value
			S.modules.minimap:Refresh()
		end)
	Settings.CreateCheckbox(category, minimap, L.MINIMAP_BUTTON_TT)
end

function O:BuildLoot(category, layout)
	local Dep = self:Module(category, layout, "loot", L.PAGE_LOOT)
	Header(layout, L.SECTION_LOOT)
	Dep(self:Checkbox(category, "loot", "fastLoot", L.FAST_LOOT, L.FAST_LOOT_TT))
	Dep(self:Checkbox(category, "loot", "bindConfirm", L.BIND_CONFIRM, L.BIND_CONFIRM_TT))
	Dep(self:Checkbox(category, "loot", "qualityBorders", L.QUALITY_BORDERS, L.QUALITY_BORDERS_TT))

	Header(layout, L.SECTION_MERCHANT)
	local junk = Dep(self:Checkbox(category, "loot", "sellJunk", L.SELL_JUNK, L.SELL_JUNK_TT))
	Dep(self:Checkbox(category, "loot", "junkSummary", L.JUNK_SUMMARY), junk, function() return S.db.loot.sellJunk end)
	local repair = Dep(self:Checkbox(category, "loot", "repair", L.REPAIR, L.REPAIR_TT))
	Dep(self:Checkbox(category, "loot", "repairGuild", L.REPAIR_GUILD, L.REPAIR_GUILD_TT), repair,
		function() return S.db.loot.repair end)
	local stack = Dep(self:Checkbox(category, "loot", "stackBuy", L.STACK_BUY, L.STACK_BUY_TT))
	Dep(self:Slider(category, "loot", "stackConfirm", L.STACK_CONFIRM, L.STACK_CONFIRM_TT, 0, 100, 5, Gold), stack,
		function() return S.db.loot.stackBuy end)
	Dep(self:Checkbox(category, "loot", "deleteText", L.DELETE_TEXT, L.DELETE_TEXT_TT))
end

function O:BuildWindows(category, layout)
	local Dep = self:Module(category, layout, "windows", L.PAGE_WINDOWS, L.WINDOWS_TT)
	Header(layout, L.SECTION_MOVE)
	local move = Dep(self:Checkbox(category, "windows", "move", L.MOVE, L.MOVE_TT))
	Dep(self:Dropdown(category, "windows", "modifier", L.MODIFIER, L.MODIFIER_TT, MODIFIER_LIST), move,
		function() return S.db.windows.move end)
	Dep(self:Dropdown(category, "windows", "remember", L.REMEMBER, L.REMEMBER_TT, {
		{ "ACCOUNT", L.REMEMBER_ACCOUNT }, { "CHAR", L.REMEMBER_CHAR }, { "SESSION", L.REMEMBER_SESSION },
	}))
	Dep(self:Checkbox(category, "windows", "scale", L.WINDOW_SCALE, L.WINDOW_SCALE_TT))
	Dep(self:Checkbox(category, "windows", "clamp", L.CLAMP, L.CLAMP_TT))
end

function O:BuildBags(category, layout)
	local Dep = self:Module(category, layout, "bags", L.PAGE_BAGS, L.BAGS_TT)
	Header(layout, L.SECTION_BAGWINDOW)
	Dep(self:Checkbox(category, "bags", "fillTop", L.BAG_FILL_TOP, L.BAG_FILL_TOP_TT))
	Dep(self:Checkbox(category, "bags", "reagentDock", L.REAGENT_DOCK, L.REAGENT_DOCK_TT))
end

function O:BuildBars(category, layout)
	local Dep = self:Module(category, layout, "bars", L.PAGE_BARS)
	local B = S.modules.bars

	Header(layout, L.SECTION_MICRO)
	Dep(self:Checkbox(category, "bars", "microFrame", L.BAR_FRAME, L.BAR_FRAME_TT))
	Dep(self:Dropdown(category, "bars", "microStyle", L.MICRO_STYLE, L.MICRO_STYLE_TT, STYLE_LIST))
	local order = Dep(self:Dropdown(category, "bars", "microOrder", L.MICRO_ORDER, L.MICRO_ORDER_TT, {
		{ "BLIZZARD", L.ORDER_BLIZZARD }, { "RIGHT", L.ORDER_RIGHT }, { "LEFT", L.ORDER_LEFT },
		{ "DOWN", L.ORDER_DOWN }, { "UP", L.ORDER_UP },
	}))
	Dep(self:Slider(category, "bars", "microSpacing", L.MICRO_SPACING, nil, -6, 12, 1), order,
		function() return S.db.bars.microOrder ~= "BLIZZARD" end)
	local fade = Dep(self:Checkbox(category, "bars", "microFade", L.FADE, L.FADE_TT))
	Dep(self:Slider(category, "bars", "microAlpha", L.FADE_ALPHA, nil, 0, 1, 0.05, Percent), fade,
		function() return S.db.bars.microFade end)
	for _, button in ipairs(B.MicroButtons()) do
		local key = B.MicroButtonName(button)
		local label = button.tooltipText or key
		if type(label) == "string" then
			label = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%(.-%)", "")
		else
			label = key
		end
		local setting = self:Proxy(category, "MICRO_" .. key:upper(), Settings.VarType.Boolean, L.SHOW_BUTTON:format(label), true,
			function() return not S.db.bars.microHide[key] end,
			function(value)
				S.db.bars.microHide[key] = (not value) or nil
				S:Apply("bars")
			end)
		Dep(Settings.CreateCheckbox(category, setting, L.SHOW_BUTTON_TT))
	end

	Header(layout, L.SECTION_BAGS)
	Dep(self:Checkbox(category, "bars", "bagFrame", L.BAR_FRAME, L.BAR_FRAME_TT))
	Dep(self:Dropdown(category, "bars", "bagStyle", L.BAG_STYLE, nil, STYLE_LIST))
	Dep(self:Checkbox(category, "bars", "bagCollapse", L.BAG_COLLAPSE, L.BAG_COLLAPSE_TT))
	local bagFade = Dep(self:Checkbox(category, "bars", "bagFade", L.FADE, L.FADE_TT))
	Dep(self:Slider(category, "bars", "bagAlpha", L.FADE_ALPHA, nil, 0, 1, 0.05, Percent), bagFade,
		function() return S.db.bars.bagFade end)

	Header(layout, L.SECTION_ACTIONBARS)
	Dep(self:Checkbox(category, "bars", "hotkeys", L.HOTKEYS, L.HOTKEYS_TT))
	Dep(self:Checkbox(category, "bars", "macroNames", L.MACRO_NAMES, L.MACRO_NAMES_TT))
	Dep(self:Checkbox(category, "bars", "barArt", L.BAR_ART, L.BAR_ART_TT))
	Dep(self:Checkbox(category, "bars", "rangeColor", L.RANGE_COLOR, L.RANGE_COLOR_TT))

	Header(layout, L.SECTION_ERRORS)
	Dep(self:Dropdown(category, "bars", "errors", L.ERRORS, L.ERRORS_TT, {
		{ "OFF", L.ERRORS_OFF }, { "COMBAT", L.ERRORS_COMBAT }, { "ALWAYS", L.ERRORS_ALWAYS }, { "ALL", L.ERRORS_ALL },
	}))

	Header(layout, L.SECTION_UNITFRAMES)
	Dep(self:Checkbox(category, "bars", "classColors", L.CLASS_COLORS, L.CLASS_COLORS_TT))
	Dep(self:Checkbox(category, "bars", "hitText", L.HIT_TEXT, L.HIT_TEXT_TT))
end

function O:BuildTooltip(category, layout)
	local Dep = self:Module(category, layout, "tooltip", L.PAGE_TOOLTIP, L.TOOLTIP_TT)
	Header(layout, L.SECTION_POSITION)
	Dep(self:Checkbox(category, "tooltip", "cursor", L.TT_CURSOR, L.TT_CURSOR_TT))
	local hide = Dep(self:Checkbox(category, "tooltip", "combatHide", L.TT_COMBAT, L.TT_COMBAT_TT))
	Dep(self:Dropdown(category, "tooltip", "combatModifier", L.TT_COMBAT_MOD, nil, MODIFIER_LIST), hide,
		function() return S.db.tooltip.combatHide end)
	Header(layout, L.SECTION_CONTENT)
	Dep(self:Checkbox(category, "tooltip", "classColor", L.TT_CLASS, nil))
	Dep(self:Checkbox(category, "tooltip", "target", L.TT_TARGET, L.TT_TARGET_TT))
	Dep(self:Checkbox(category, "tooltip", "healthBar", L.TT_HEALTH, nil))
	Dep(self:Checkbox(category, "tooltip", "ids", L.TT_IDS, L.TT_IDS_TT))
end

function O:BuildChat(category, layout)
	local Dep = self:Module(category, layout, "chat", L.PAGE_CHAT)
	Header(layout, L.SECTION_INPUT)
	Dep(self:Checkbox(category, "chat", "arrowKeys", L.ARROW_KEYS, L.ARROW_KEYS_TT))
	local keep = Dep(self:Checkbox(category, "chat", "keepHistory", L.KEEP_HISTORY, L.KEEP_HISTORY_TT))
	Dep(self:Slider(category, "chat", "historySize", L.HISTORY_SIZE, nil, 10, 200, 10), keep,
		function() return S.db.chat.keepHistory end)
	Dep(self:Checkbox(category, "chat", "editTop", L.EDIT_TOP, nil))
	Header(layout, L.SECTION_CHATWINDOW)
	Dep(self:Checkbox(category, "chat", "urls", L.URLS, L.URLS_TT))
	Dep(self:Checkbox(category, "chat", "shortChannels", L.SHORT_CHANNELS, L.SHORT_CHANNELS_TT))
	Dep(self:Checkbox(category, "chat", "hideButtons", L.HIDE_BUTTONS, L.HIDE_BUTTONS_TT))
	Dep(self:Checkbox(category, "chat", "copy", L.COPY_BUTTON, L.COPY_BUTTON_TT))
	Dep(self:Slider(category, "chat", "lines", L.LINES, L.LINES_TT, 128, 1024, 128))
end

function O:BuildAuto(category, layout)
	local Dep = self:Module(category, layout, "auto", L.PAGE_AUTO, L.AUTO_TT)
	Header(layout, L.SECTION_QUESTS)
	local accept = Dep(self:Checkbox(category, "auto", "questAccept", L.QUEST_ACCEPT, L.QUEST_ACCEPT_TT))
	local function Accepting() return S.db.auto.questAccept end
	for _, kind in ipairs({ "Normal", "Repeat", "Trivial", "Group", "Dungeon", "PvP", "Timed", "Escort", "Shared" }) do
		local key = "QUEST_" .. kind:upper()
		Dep(self:Checkbox(category, "auto", "quest" .. kind, L[key], L[key .. "_TT"]), accept, Accepting)
	end
	local turnIn = Dep(self:Checkbox(category, "auto", "questTurnIn", L.QUEST_TURNIN, L.QUEST_TURNIN_TT))
	Dep(self:Dropdown(category, "auto", "questReward", L.QUEST_REWARD, L.QUEST_REWARD_TT, {
		{ "SKIP", L.QUEST_REWARD_SKIP }, { "VALUE", L.QUEST_REWARD_VALUE },
	}), turnIn, function() return S.db.auto.questTurnIn end)
	Header(layout, L.SECTION_NPC)
	Dep(self:Checkbox(category, "auto", "gossip", L.AUTO_GOSSIP, L.AUTO_GOSSIP_TT))
	Dep(self:Checkbox(category, "auto", "openMail", L.AUTO_MAIL, L.AUTO_MAIL_TT))
	Dep(self:Checkbox(category, "auto", "trainAll", L.AUTO_TRAINER, L.AUTO_TRAINER_TT))
	Header(layout, L.SECTION_PLAYERS)
	Dep(self:Checkbox(category, "auto", "declineDuels", L.AUTO_DUELS, nil))
	Dep(self:Checkbox(category, "auto", "declineGuild", L.AUTO_GUILD, L.AUTO_GUILD_TT))
	Dep(self:Checkbox(category, "auto", "acceptInvites", L.AUTO_INVITES, L.AUTO_INVITES_TT))
	Dep(self:Checkbox(category, "auto", "acceptRes", L.AUTO_RES, L.AUTO_RES_TT))
end

function O:BuildMisc(category, layout)
	local Dep = self:Module(category, layout, "misc", L.PAGE_MISC)
	Header(layout, L.SECTION_CAMERA)
	local cam = Dep(self:Checkbox(category, "misc", "camera", L.CAMERA, L.CAMERA_TT))
	Dep(self:Slider(category, "misc", "cameraFactor", L.CAMERA_FACTOR, L.CAMERA_FACTOR_TT, 1, 4, 0.1, Factor), cam,
		function() return S.db.misc.camera end)
	Dep(self:Checkbox(category, "misc", "levelShot", L.LEVEL_SHOT, nil))
	Header(layout, L.SECTION_TRAVEL)
	Dep(self:Checkbox(category, "misc", "flightBar", L.FLIGHT_BAR, L.FLIGHT_BAR_TT))
	Header(layout, L.SECTION_SOUND)
	Dep(self:Checkbox(category, "misc", "mute", L.MUTE, L.MUTE_TT))
	Header(layout, L.SECTION_COMMANDS)
	Dep(self:Checkbox(category, "misc", "reload", L.RL, L.RL_TT))
end

------------------------------------------------------------------------
-- Actions page (own frames, so Blizzard's reused setting controls never get tainted)
------------------------------------------------------------------------
function O:CreateActionsPanel()
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 7, -22)
	title:SetText(L.SECTION_ACTIONS)
	local divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("Options_HorizontalDivider", true)
	divider:SetPoint("TOP", 0, -50)

	local y = -70
	local function Section(text)
		local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
		fs:SetPoint("TOPLEFT", 7, y - 6)
		fs:SetText(text)
		y = y - 36
	end
	local function Row(label, buttonText, desc, onClick)
		local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		fs:SetPoint("TOPLEFT", 37, y)
		fs:SetText(label)
		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		button:SetSize(200, 26)
		button:SetPoint("TOPLEFT", panel, "TOPLEFT", 300, y + 6)
		button:SetText(buttonText)
		button:SetScript("OnClick", onClick)
		if desc then
			local d = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			d:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
			d:SetPoint("RIGHT", button, "LEFT", -12, 0)
			d:SetJustifyH("LEFT")
			d:SetText(desc)
			y = y - 52
		else
			y = y - 36
		end
		return button
	end

	Section(L.PAGE_WINDOWS)
	Row(L.WINDOW_POSITIONS, L.RESET_BTN, L.WINDOW_POSITIONS_TT, function() S.modules.windows:ResetAll() end)
	Section(L.SECTION_TRAVEL)
	Row(L.FLIGHT_TIMES, L.RESET_BTN, L.FLIGHT_TIMES_TT, function()
		S.modules.flight:ResetRoutes()
		S.Print(L.FLIGHT_TIMES_CLEARED)
	end)
	Section(L.PAGE_CHAT)
	Row(L.COPY_TITLE, L.OPEN_BTN, L.COPY_ACTION_TT, function() S.modules.chat:ShowCopy(DEFAULT_CHAT_FRAME) end)
	Row(L.CLEAR_HISTORY, L.CLEAR_BTN, L.CLEAR_HISTORY_TT, function()
		wipe(S.char.chatHistory)
		S.Print(L.HISTORY_CLEARED)
	end)
	Section(L.SECTION_DATA)
	Row(L.RESET_ALL, L.RESET_BTN, L.RESET_ALL_TT, function() StaticPopup_Show("SUNDRY_RESET_ALL") end)
	return panel
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------
function O:Init()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
	self.category = category
	self:BuildGeneral(category, layout)

	local function Sub(name, build)
		local sub, subLayout = Settings.RegisterVerticalLayoutSubcategory(category, name)
		local ok, err = pcall(build, self, sub, subLayout)
		if not ok then geterrorhandler()(err) end
	end
	Sub(L.PAGE_LOOT, O.BuildLoot)
	Sub(L.PAGE_WINDOWS, O.BuildWindows)
	Sub(L.PAGE_BAGS, O.BuildBags)
	Sub(L.PAGE_BARS, O.BuildBars)
	Sub(L.PAGE_TOOLTIP, O.BuildTooltip)
	Sub(L.PAGE_CHAT, O.BuildChat)
	Sub(L.PAGE_AUTO, O.BuildAuto)
	Sub(L.PAGE_MISC, O.BuildMisc)

	Settings.RegisterAddOnCategory(category)
	if Settings.RegisterCanvasLayoutSubcategory then
		self.actionsCategory = Settings.RegisterCanvasLayoutSubcategory(category, self:CreateActionsPanel(), L.SECTION_ACTIONS)
	end
end

function O:Refresh()
	for _, setting in ipairs(self.settings) do
		if setting.NotifyUpdate then setting:NotifyUpdate() end
	end
end

function O:Open()
	if self.category and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	end
end
