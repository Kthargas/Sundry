local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("flight", M)

-- Flight time bar: while you fly with a flight master a bar shows where you are going and how long the
-- flight still takes. The client does not tell how long a flight takes, so Sundry measures each route
-- once (account wide) and counts down from the second flight on; on a new route the bar counts up.
-- Settings live on the "misc" page (S.db.misc.flightBar).

local flight        -- { from, to, start (time()), startClock (GetTime()) } while flying
local picked        -- route chosen at the flight master, until the flight starts
local bar

local function Enabled() return S:Get("misc", "flightBar") end

local function Routes()
	S.root.flights = S.root.flights or {}
	return S.root.flights
end

local function RouteKey(from, to)
	if not from or not to then return nil end
	return from .. " > " .. to
end

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

------------------------------------------------------------------------
-- The route: hooked when a flight is picked on the flight map
------------------------------------------------------------------------
local function CurrentNodeName()
	if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) then return nil end
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return TaxiNodeName(i) end
	end
end

local function OnTakeTaxiNode(index)
	local to = TaxiNodeName and TaxiNodeName(index)
	local from = CurrentNodeName()
	if S.IsSecret(to) or S.IsSecret(from) then return end
	picked = { from = from, to = to, at = GetTime() }
end

------------------------------------------------------------------------
-- Flight map: the measured time in the tooltip of a destination (its first line is the node's name)
------------------------------------------------------------------------
local function MapShown()
	return (TaxiFrame and TaxiFrame:IsShown()) or (FlightMapFrame and FlightMapFrame:IsShown())
end

local function OnTooltipShow(tooltip)
	if tooltip.sundryFlight or not Enabled() or not MapShown() then return end
	local line = _G[tooltip:GetName() .. "TextLeft1"]
	local to = line and line:GetText()
	local from = CurrentNodeName()
	if not to or not from or S.IsSecret(to) or S.IsSecret(from) or to == from then return end
	local total = Routes()[RouteKey(from, to)]
	tooltip.sundryFlight = true
	if total then
		tooltip:AddLine(L.FLIGHT_TIME:format(Clock(total)), 1, 1, 1)
	else
		tooltip:AddLine(L.FLIGHT_TIME_UNKNOWN, 0.6, 0.6, 0.6)
	end
	tooltip:Show()
	tooltip.sundryFlight = nil
end

------------------------------------------------------------------------
-- The bar (Blizzard's status bar texture and tooltip border)
------------------------------------------------------------------------
local function SavePosition()
	local x, y = bar:GetCenter()
	local ux, uy = UIParent:GetCenter()
	S.db.misc.flightPos = { x = x - ux, y = y - uy }
end

local function PlaceBar()
	local pos = S.db.misc.flightPos
	bar:ClearAllPoints()
	if pos then
		bar:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
	else
		bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
end

local function CreateBar()
	bar = CreateFrame("Frame", "SundryFlightBar", UIParent, "BackdropTemplate")
	bar:SetSize(240, 22)
	bar:SetFrameStrata("MEDIUM")
	bar:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	bar:SetBackdropColor(0, 0, 0, 0.7)
	bar:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)

	local status = CreateFrame("StatusBar", nil, bar)
	status:SetPoint("TOPLEFT", 4, -4)
	status:SetPoint("BOTTOMRIGHT", -4, 4)
	status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	status:SetStatusBarColor(0.25, 0.55, 1)
	status:SetMinMaxValues(0, 1)
	bar.status = status

	local name = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("LEFT", 4, 0)
	name:SetPoint("RIGHT", -44, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	bar.name = name
	local time = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	time:SetPoint("RIGHT", -4, 0)
	bar.time = time

	-- drag to move (the position is kept), Shift + right click puts it back
	bar:SetMovable(true)
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", bar.StartMoving)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	bar:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and IsShiftKeyDown() then
			S.db.misc.flightPos = nil
			PlaceBar()
		end
	end)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip_SetTitle(GameTooltip, L.FLIGHT_TITLE)
		if flight and flight.from then GameTooltip:AddLine(RouteKey(flight.from, flight.to), 1, 1, 1) end
		GameTooltip:AddLine(L.FLIGHT_MOVE_TT, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	bar:Hide()
	PlaceBar()
end

local elapsedSince = 0
local function OnUpdate(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.1 then return end
	elapsedSince = 0
	if not flight then bar:Hide() return end
	local spent = GetTime() - flight.startClock
	local key = RouteKey(flight.from, flight.to)
	local total = key and Routes()[key]
	if total and total > 0 then
		bar.status:SetValue(math.min(spent / total, 1))
		bar.time:SetText(Clock(total - spent))
	else
		bar.status:SetValue(1)
		bar.time:SetText(Clock(spent))
	end
end

local function ShowBar()
	if not Enabled() or not flight then return end
	if not bar then CreateBar() end
	bar.name:SetText(flight.to or L.FLIGHT_UNKNOWN)
	local key = RouteKey(flight.from, flight.to)
	bar.status:SetStatusBarColor(0.25, 0.55, 1, (key and Routes()[key]) and 1 or 0.5)
	bar:SetScript("OnUpdate", OnUpdate)
	bar:Show()
end

------------------------------------------------------------------------
-- Start and end of a flight (also across a reload in the air)
------------------------------------------------------------------------
local function StartFlight()
	if flight then return end
	local now = time()
	if picked and GetTime() - picked.at < 30 then
		flight = { from = picked.from, to = picked.to, start = now }
	else
		flight = { start = now }
	end
	picked = nil
	flight.startClock = GetTime()
	S.char.flight = { from = flight.from, to = flight.to, start = flight.start }
	ShowBar()
end

local function EndFlight()
	if not flight then return end
	local key = RouteKey(flight.from, flight.to)
	if key and not flight.early and not flight.resumed then
		local spent = time() - flight.start
		if spent > 5 then Routes()[key] = spent end
	end
	flight = nil
	S.char.flight = nil
	if bar then bar:Hide() end
end

local function Check()
	local onTaxi = UnitOnTaxi("player")
	if onTaxi and not flight then
		StartFlight()
	elseif not onTaxi and flight then
		EndFlight()
	end
end

-- After a reload in the air: continue the flight that was saved.
local function Resume(isLogin)
	local saved = S.char.flight
	if not UnitOnTaxi("player") then
		S.char.flight = nil
		return
	end
	if not saved or not saved.start or time() - saved.start > 3600 then
		StartFlight()
		return
	end
	flight = { from = saved.from, to = saved.to, start = saved.start }
	flight.startClock = GetTime() - (time() - saved.start)
	-- after a fresh login the time offline is in it: count down, but do not measure the route again
	flight.resumed = isLogin or nil
	ShowBar()
end

function M:Init()
	S.Hook("TakeTaxiNode", OnTakeTaxiNode)
	GameTooltip:HookScript("OnShow", OnTooltipShow)
	S.Hook("TaxiRequestEarlyLanding", function() if flight then flight.early = true end end)
	S:On("PLAYER_CONTROL_LOST", function() C_Timer.After(0.5, Check) end)
	S:On("PLAYER_CONTROL_GAINED", function() C_Timer.After(0.2, Check) end)
	S:On("PLAYER_ENTERING_WORLD", function(_, isLogin)
		C_Timer.After(1, function()
			if flight then Check() else Resume(isLogin) end
		end)
	end)
end

function M:Apply()
	if not bar then return end
	if Enabled() and flight then ShowBar() else bar:Hide() end
end

function M:ResetRoutes()
	wipe(Routes())
end
