local ADDON, S = ...
local L = S.L
_G.Sundry = S

-- Sundry: many small tweaks in one addon. Every feature lives in a module (one file per settings page),
-- has its own switch and only touches Blizzard's UI through post-hooks (hooksecurefunc / HookScript),
-- so nothing of Blizzard's own code is replaced.

S.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "1.0.0"
S.modules = {}
S.order = {}
S.ICON = "Interface\\AddOns\\Sundry\\Textures\\Icon"

-- Every module has a switch in S.db.modules and its own settings table S.db[name].
-- Comfort features are on by default, everything that acts on its own (automation) is off.
local defaults = {
	modules = { loot = true, windows = true, bags = true, bars = true, tooltip = true, chat = true, auto = true, misc = true },
	minimap = { hide = false, angle = 195 },
	loot = {
		fastLoot = true, bindConfirm = false,
		sellJunk = true, junkSummary = true, junkKeep = {},
		repair = true, repairGuild = false,
		deleteText = true,
		stackBuy = true, stackConfirm = 10,
		qualityBorders = true,
	},
	windows = {
		move = true, modifier = "NONE", remember = "ACCOUNT", scale = true, clamp = true,
	},
	bags = {
		fillTop = true, reagentDock = true,
	},
	bars = {
		microFrame = true, microStyle = "NONE", microOrder = "BLIZZARD", microSpacing = 0,
		microFade = false, microAlpha = 0, microHide = {},
		bagFrame = true, bagStyle = "BLIZZARD", bagFade = false, bagAlpha = 0, bagCollapse = true,
		errors = "COMBAT",
		hotkeys = true, macroNames = true,
		barArt = true,
		rangeColor = false,
		classColors = false, hitText = true,
	},
	tooltip = {
		cursor = false, combatHide = false, combatModifier = "SHIFT",
		classColor = true, target = true, healthBar = true, ids = false,
	},
	chat = {
		arrowKeys = true, keepHistory = true, historySize = 50,
		urls = true, shortChannels = false, hideButtons = false, editTop = false,
		lines = 128, copy = true,
	},
	auto = {
		questAccept = false, questTurnIn = false, questReward = "SKIP",
		questNormal = true, questRepeat = false, questTrivial = false, questGroup = false, questDungeon = false,
		questPvP = false, questTimed = false, questEscort = false, questShared = false,
		gossip = false, declineDuels = false, declineGuild = false,
		acceptInvites = false, acceptRes = false, openMail = true, trainAll = true,
	},
	misc = {
		camera = false, cameraFactor = 2.6, reload = true, levelShot = false, mute = false, muted = {},
		flightBar = true,
	},
}
S.defaults = defaults

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			-- lists (empty tables in the defaults) are filled by the user, never merged into
			if next(v) then Merge(dst[k], v) end
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function S.Print(...)
	print("|cffffd100" .. L.TITLE .. ":|r", ...)
end

-- Values the client hides (Forever / newer clients: "secret" values) must never be compared or
-- concatenated; every feature that reads names, text or numbers checks them first.
function S.IsSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

function S.Readable(...)
	for i = 1, select("#", ...) do
		if S.IsSecret((select(i, ...))) then return false end
	end
	return true
end

------------------------------------------------------------------------
-- Events: several handlers per event; unknown events (other client build) are ignored.
------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			local ok, err = pcall(list[i], event, ...)
			if not ok then geterrorhandler()(err) end
		end
	end
end)

function S:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end

-- Code that touches Blizzard frames waits for the end of combat when the frame is protected.
local afterCombat = {}
function S.AfterCombat(key, fn)
	if not InCombatLockdown() then fn() return end
	afterCombat[key] = fn
end
S:On("PLAYER_REGEN_ENABLED", function()
	for key, fn in pairs(afterCombat) do
		afterCombat[key] = nil
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end)

-- Run fn once a Blizzard load-on-demand addon is there (at once when it already is).
local waiting = {}
function S.OnAddonLoaded(name, fn)
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)
	if loaded then fn() return end
	waiting[name] = waiting[name] or {}
	table.insert(waiting[name], fn)
end
S:On("ADDON_LOADED", function(_, name)
	local list = waiting[name]
	if not list then return end
	waiting[name] = nil
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end)

-- Hook a global function or a method once; missing functions (other client build) are skipped.
function S.Hook(tbl, name, fn)
	if type(tbl) == "string" then
		tbl, name, fn = _G, tbl, name
	end
	if type(tbl) == "table" and type(tbl[name]) == "function" then
		hooksecurefunc(tbl, name, fn)
		return true
	end
	return false
end

------------------------------------------------------------------------
-- Modules
------------------------------------------------------------------------
function S:RegisterModule(name, mod)
	mod.name = name
	self.modules[name] = mod
	table.insert(self.order, name)
end

function S:IsEnabled(name)
	return self.db and self.db.modules[name] and true or false
end

-- Setting of an enabled module (nil while the module is off)
function S:Get(module, key)
	if not self:IsEnabled(module) then return nil end
	return self.db[module][key]
end

-- Apply a module again after one of its settings changed.
function S:Apply(name)
	local m = self.modules[name]
	if m and m.Apply then
		local ok, err = pcall(m.Apply, m)
		if not ok then geterrorhandler()(err) end
	end
end

------------------------------------------------------------------------
-- Profiles: shared by all characters unless a character has its own copy (same as Fray and Mundi)
------------------------------------------------------------------------
S.SHARED = "Default"

function S.CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function S.SetOwnProfile(own)
	if (S.char.own and true or false) == own then return end
	S.char.own = own or nil
	local key = S.CharKey()
	if own and type(S.root.profiles[key]) ~= "table" then
		S.root.profiles[key] = CopyTable(S.root.profiles[S.SHARED])
	end
	StaticPopup_Show("SUNDRY_RELOAD")
end

function S.ResetAll()
	if InCombatLockdown() then S.Print(L.NOT_IN_COMBAT) return end
	wipe(S.db)
	S.root.windows = {}
	S.char.windows = {}
	ReloadUI()
end

StaticPopupDialogs["SUNDRY_RELOAD"] = {
	text = L.RELOAD_PROFILE,
	button1 = L.RELOAD_NOW,
	button2 = L.RELOAD_LATER,
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["SUNDRY_RESET_ALL"] = {
	text = L.RESET_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function() S.ResetAll() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SundryDB = SundryDB or {}
		local root = SundryDB
		root.profiles = root.profiles or {}
		root.chars = root.chars or {}
		root.windows = root.windows or {}
		local shared = root.profiles[S.SHARED] or {}
		root.profiles[S.SHARED] = shared
		local key = S.CharKey()
		local char = root.chars[key] or {}
		root.chars[key] = char
		char.windows = char.windows or {}
		char.chatHistory = char.chatHistory or {}
		local name = char.own and key or S.SHARED
		if type(root.profiles[name]) ~= "table" then root.profiles[name] = CopyTable(shared) end
		local db = root.profiles[name]
		-- 1.0: one switch for accepting and turning in quests
		if type(db.auto) == "table" and db.auto.quests ~= nil then
			db.auto.questAccept = db.auto.quests or nil
			db.auto.questTurnIn = db.auto.quests or nil
			db.auto.quests = nil
		end
		Merge(db, defaults)
		S.root, S.char, S.db = root, char, db
	elseif event == "PLAYER_LOGIN" then
		for _, name in ipairs(S.order) do
			local m = S.modules[name]
			local ok, err = pcall(function()
				if m.Init then m:Init() end
				if m.Apply then m:Apply() end
			end)
			if not ok then geterrorhandler()(err) end
		end
		S.ready = true
	end
end)

function S.OpenOptions()
	local o = S.modules.options
	if o and o.Open then o:Open() end
end

------------------------------------------------------------------------
-- Inspect: lists the frame under the mouse and its textures, to find the names of Blizzard's art in
-- this client (for example the micro menu backgrounds).
------------------------------------------------------------------------
local function Describe(region)
	local name = region.GetDebugName and region:GetDebugName() or region:GetName() or "?"
	local info = name .. " (" .. region:GetObjectType() .. ")"
	if region.GetAtlas and region:GetAtlas() then
		info = info .. " atlas=" .. tostring(region:GetAtlas())
	elseif region.GetTexture and region:GetTexture() then
		info = info .. " texture=" .. tostring(region:GetTexture())
	end
	if region.IsShown then info = info .. (region:IsShown() and "" or " [hidden]") end
	if region.GetAlpha then info = info .. (" a=%.2f"):format(region:GetAlpha()) end
	return info
end

function S.Inspect()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if not focus or focus == WorldFrame then S.Print(L.INSPECT_NONE) return end
	S.Print(Describe(focus))
	for _, region in ipairs({ focus:GetRegions() }) do
		print("   " .. Describe(region))
	end
	for _, child in ipairs({ focus:GetChildren() }) do
		print("   child: " .. Describe(child))
	end
	local parent, depth = focus:GetParent(), 0
	while parent and parent ~= UIParent and depth < 6 do
		print("   parent: " .. Describe(parent))
		parent, depth = parent:GetParent(), depth + 1
	end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local COMMANDS = {
	{ "", L.CMD_OPTIONS },
	{ "windows reset", L.CMD_WINDOWS_RESET },
	{ "junk add | remove <item>", L.CMD_JUNK },
	{ "mute | unmute <sound id>", L.CMD_MUTE },
	{ "copy", L.CMD_COPY },
	{ "flights", L.CMD_FLIGHTS },
	{ "inspect", L.CMD_INSPECT },
	{ "reset", L.CMD_RESET },
}

local function Help()
	S.Print(L.HELP_TITLE)
	for _, c in ipairs(COMMANDS) do
		print(("  |cffffd100/sundry%s|r - %s"):format(c[1] ~= "" and " " .. c[1] or "", c[2]))
	end
	if S:Get("misc", "reload") then print("  |cffffd100/rl|r - " .. L.CMD_RL) end
end

SLASH_SUNDRY1 = "/sundry"
SlashCmdList.SUNDRY = function(msg)
	if not S.db then return end
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		S.OpenOptions()
	elseif cmd == "windows" and rest:lower() == "reset" then
		S.modules.windows:ResetAll()
	elseif cmd == "junk" then
		S.modules.loot:JunkCommand(rest)
	elseif cmd == "mute" or cmd == "unmute" then
		S.modules.misc:MuteCommand(cmd, rest)
	elseif cmd == "copy" then
		S.modules.chat:ShowCopy(DEFAULT_CHAT_FRAME)
	elseif cmd == "flights" then
		S.modules.flight:Export()
	elseif cmd == "inspect" then
		S.Inspect()
	elseif cmd == "reset" then
		StaticPopup_Show("SUNDRY_RESET_ALL")
	else
		Help()
	end
end

-- Addon compartment entry (## AddonCompartmentFunc in the TOC), like Fray's and Mundi's
function Sundry_OnAddonCompartmentClick()
	S.OpenOptions()
end

function Sundry_OnAddonCompartmentEnter(addonName, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L.TITLE)
	GameTooltip:AddLine(L.TT_LEFT, 1, 1, 1)
	GameTooltip:Show()
end

function Sundry_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
