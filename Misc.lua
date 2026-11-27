local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("misc", M)

-- Camera, sound and comfort: maximum camera distance, /rl, a screenshot on level up and a list of muted
-- sounds.

------------------------------------------------------------------------
-- Camera: maximum zoom distance (the client caps the value itself)
------------------------------------------------------------------------
local function ApplyCamera()
	if S:Get("misc", "camera") then
		if not S.char.cameraDefault then S.char.cameraDefault = GetCVar("cameraDistanceMaxZoomFactor") end
		pcall(SetCVar, "cameraDistanceMaxZoomFactor", S.db.misc.cameraFactor)
	elseif S.char.cameraDefault then
		pcall(SetCVar, "cameraDistanceMaxZoomFactor", S.char.cameraDefault)
		S.char.cameraDefault = nil
	end
end

------------------------------------------------------------------------
-- Muted sounds (sound file IDs, for example from wowhead's sound pages)
------------------------------------------------------------------------
local muted = {}
local function ApplyMute()
	if not MuteSoundFile then return end
	local want = S:Get("misc", "mute") and S.db.misc.muted or {}
	for id in pairs(muted) do
		if not want[id] then UnmuteSoundFile(id); muted[id] = nil end
	end
	for id in pairs(want) do
		if not muted[id] then MuteSoundFile(id); muted[id] = true end
	end
end

function M:MuteCommand(cmd, rest)
	if not MuteSoundFile then S.Print(L.MUTE_UNSUPPORTED) return end
	local id = tonumber(rest)
	local list = S.db.misc.muted
	if not id then
		S.Print(L.MUTE_HELP)
		for muteID in pairs(list) do print("   " .. muteID) end
		return
	end
	if cmd == "mute" then
		list[id] = true
		S.Print(L.MUTED:format(id))
	else
		list[id] = nil
		S.Print(L.UNMUTED:format(id))
	end
	ApplyMute()
end

------------------------------------------------------------------------
function M:Init()
	SLASH_SUNDRYRL1 = "/rl"
	SlashCmdList.SUNDRYRL = function()
		if S:Get("misc", "reload") then ReloadUI() else S.Print(L.RL_OFF) end
	end
	S:On("PLAYER_LEVEL_UP", function()
		if S:Get("misc", "levelShot") then C_Timer.After(1, Screenshot) end
	end)
end

function M:Apply()
	ApplyCamera()
	ApplyMute()
	if S.modules.flight then S:Apply("flight") end
end
