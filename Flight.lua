local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("flight", M)

-- Flight time bar: while you fly with a flight master a bar shows where you are going and how long the
-- flight still takes. The client does not tell how long a flight takes, so Sundry measures each route
-- once (account wide) and counts down from the second flight on; on a new route the bar counts up.
-- Settings live on the "misc" page (S.db.misc.flightBar).

local flight        -- route of the current flight plus start (time()), startClock (GetTime())
local picked        -- route chosen at the flight master, until the flight starts
local nodes         -- slot -> { id, x, y } of the open flight map
local bar

local function Enabled() return S:Get("misc", "flightBar") end

local function Store(name)
	S.root[name] = S.root[name] or {}
	return S.root[name]
end
local function Routes() return Store("flights") end            -- measured, by node names
local function Times() return Store("flightTimes") end         -- measured, by route ID (same in every language)
local function Names() return Store("flightNames") end         -- route ID -> "from > to", for the export
local function Calibration() return Store("flightCal") end     -- flight map -> seconds flown and map length flown

local function RouteKey(from, to)
	if not from or not to then return nil end
	return from .. " > " .. to
end

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end

------------------------------------------------------------------------
-- The flight map: nodes, route IDs and the length of a route on the map
------------------------------------------------------------------------
local function MapKey()
	local id = Call(GetTaxiMapID)
	return id and ("m" .. id) or "map"
end

local function ReadNodes()
	nodes = {}
	local mapID = Call(GetTaxiMapID)
	local list = mapID and C_TaxiMap and Call(C_TaxiMap.GetAllTaxiNodes, mapID)
	for _, node in ipairs(type(list) == "table" and list or {}) do
		if node.slotIndex then
			local x, y
			local pos = node.position
			if type(pos) == "table" then
				if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
			end
			nodes[node.slotIndex] = { id = node.nodeID, x = x, y = y }
		end
	end
end

local function NodePos(slot)
	local node = nodes and nodes[slot]
	if node and node.x then return node.x, node.y end
	return Call(TaxiNodePosition, slot)
end

local function NodeKey(slot)
	local node = nodes and nodes[slot]
	if node and node.id then return "n" .. node.id end
	local x, y = NodePos(slot)
	if x and y then return ("%s:%.3f,%.3f"):format(MapKey(), x, y) end
end

local function CurrentSlot()
	if not (NumTaxiNodes and TaxiNodeGetType) then return nil end
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then return i end
	end
end

-- Size of the flight map in yards (newer clients), to turn map lengths into yards
local function MapYards()
	local mapID = Call(GetTaxiMapID)
	if not (mapID and C_Map and C_Map.GetMapWorldSize) then return nil end
	local w, h = Call(C_Map.GetMapWorldSize, mapID)
	if w and h and w > 0 and h > 0 then return w, h end
end

-- Length of all hops of the route to a slot (straight lines between the stops): in yards when the client
-- knows the size of the map, otherwise in map units. Second return: true for yards.
local function RouteLength(slot)
	local hops = Call(GetNumRoutes, slot)
	if not hops or hops < 1 then return nil end
	local w, h = MapYards()
	local yards = w ~= nil
	w, h = w or 1, h or 1
	local length = 0
	for hop = 1, hops do
		local sx, sy, dx, dy
		if TaxiGetSrcX then
			sx, sy = TaxiGetSrcX(slot, hop), TaxiGetSrcY(slot, hop)
			dx, dy = TaxiGetDestX(slot, hop), TaxiGetDestY(slot, hop)
		elseif TaxiGetNodeSlot then
			sx, sy = NodePos(TaxiGetNodeSlot(slot, hop, true))
			dx, dy = NodePos(TaxiGetNodeSlot(slot, hop, false))
		end
		if not (sx and sy and dx and dy) then return nil end
		length = length + math.sqrt(((dx - sx) * w) ^ 2 + ((dy - sy) * h) ^ 2)
	end
	return length, yards
end

local function RouteFor(slot)
	local from = CurrentSlot()
	if not from or not slot or slot == from or not TaxiNodeName then return nil end
	local fromName, toName = TaxiNodeName(from), TaxiNodeName(slot)
	if S.IsSecret(fromName) or S.IsSecret(toName) then return nil end
	if not nodes then ReadNodes() end
	local a, b = NodeKey(from), NodeKey(slot)
	local ok, length, yards = pcall(RouteLength, slot)
	return {
		from = fromName, to = toName, id = a and b and (a .. ">" .. b),
		map = MapKey(), length = ok and length or nil, yards = ok and yards or nil,
	}
end

-- Duration of a route: measured by you, known (shipped with Sundry) or estimated from the map length and
-- the flights measured on the same map. Second return: "measured", "known" or "estimate".
local DEFAULT_SPEED = 28   -- yards per second along the straight line (taxis fly about 32 yd/s on curves)

local function Duration(route)
	if not route then return nil end
	local t = route.id and Times()[route.id]
	if t then return t, "measured" end
	t = route.from and Routes()[RouteKey(route.from, route.to)]
	if t then return t, "measured" end
	t = route.id and S.FLIGHT_DATA and S.FLIGHT_DATA[route.id]
	if t then return t, "known" end
	if not route.length or route.length <= 0 then return nil end
	local cal = Calibration()[(route.map or "map") .. (route.yards and ":yd" or "")]
	if cal and (cal.length or 0) > 0 and (cal.flights or 0) > 0 then
		return route.length * cal.seconds / cal.length, "estimate"
	end
	-- nothing measured on this map yet: straight line at the usual flight speed (routes curve a little)
	if route.yards then return route.length / DEFAULT_SPEED, "estimate" end
end

local function DurationText(seconds, kind)
	if kind == "estimate" then return "~" .. Clock(seconds) end
	return Clock(seconds)
end

local function OnTakeTaxiNode(slot)
	local route = RouteFor(slot)
	if not route then return end
	route.at = GetTime()
	picked = route
end

------------------------------------------------------------------------
-- Flight map: the flight time in the tooltip of a destination (its first line is the node's name)
------------------------------------------------------------------------
local function MapShown()
	return (TaxiFrame and TaxiFrame:IsShown()) or (FlightMapFrame and FlightMapFrame:IsShown())
end

local function SlotOf(tooltip, name)
	local owner = tooltip:GetOwner()
	if owner and owner.GetID and TaxiNodeName and owner:GetID() > 0 and TaxiNodeName(owner:GetID()) == name then
		return owner:GetID()
	end
	for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
		if TaxiNodeName(i) == name then return i end
	end
end

local function OnTooltipShow(tooltip)
	if tooltip.sundryFlight or not Enabled() or not MapShown() then return end
	local line = _G[tooltip:GetName() .. "TextLeft1"]
	local to = line and line:GetText()
	if not to or S.IsSecret(to) then return end
	local route = RouteFor(SlotOf(tooltip, to))
	if not route then return end
	local seconds, kind = Duration(route)
	tooltip.sundryFlight = true
	if seconds then
		local text = L.FLIGHT_TIME:format(DurationText(seconds, kind))
		if kind == "estimate" then text = text .. " " .. L.FLIGHT_ESTIMATED end
		tooltip:AddLine(text, 1, 1, 1)
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
	local total = flight.total
	if total and total > 0 then
		bar.status:SetValue(math.max(1 - spent / total, 0))
		if spent <= total then
			bar.time:SetText((flight.kind == "estimate" and "~" or "") .. Clock(total - spent))
		else
			bar.time:SetText("+" .. Clock(spent - total))
		end
	else
		bar.status:SetValue(1)
		bar.time:SetText(Clock(spent))
	end
end

local function ShowBar()
	if not Enabled() or not flight then return end
	if not bar then CreateBar() end
	bar.name:SetText(flight.to or L.FLIGHT_UNKNOWN)
	flight.total, flight.kind = Duration(flight)
	bar.status:SetStatusBarColor(0.25, 0.55, 1, (flight.total and flight.kind ~= "estimate") and 1 or 0.5)
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
		flight = picked
		flight.at = nil
	else
		flight = {}
	end
	picked = nil
	flight.start = now
	flight.startClock = GetTime()
	S.char.flight = {
		from = flight.from, to = flight.to, id = flight.id, map = flight.map, length = flight.length, yards = flight.yards,
		start = flight.start,
	}
	ShowBar()
end

local function EndFlight()
	if not flight then return end
	local key = RouteKey(flight.from, flight.to)
	local spent = time() - flight.start
	if key and not flight.early and not flight.resumed and spent > 5 then
		Routes()[key] = spent
		if flight.id then
			Times()[flight.id] = spent
			Names()[flight.id] = key
		end
		-- calibration of the estimate: seconds per map length on this flight map
		if flight.length and flight.length > 0 then
			local calKey = (flight.map or "map") .. (flight.yards and ":yd" or "")
			local cal = Calibration()[calKey] or { seconds = 0, length = 0, flights = 0 }
			cal.seconds, cal.length, cal.flights = cal.seconds + spent, cal.length + flight.length, cal.flights + 1
			Calibration()[calKey] = cal
		end
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
	flight = {
		from = saved.from, to = saved.to, id = saved.id, map = saved.map, length = saved.length, yards = saved.yards,
		start = saved.start,
	}
	flight.startClock = GetTime() - (time() - saved.start)
	-- after a fresh login the time offline is in it: count down, but do not measure the route again
	flight.resumed = isLogin or nil
	ShowBar()
end

function M:Init()
	S.Hook("TakeTaxiNode", OnTakeTaxiNode)
	S:On("TAXIMAP_OPENED", function() nodes = nil end)
	S:On("TAXIMAP_CLOSED", function() nodes = nil end)
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
	wipe(Times())
	wipe(Names())
	wipe(Calibration())
end

-- All measured routes as Lua lines, to be copied into FlightData.lua (shipped flight times)
function M:Export()
	local ids = {}
	for id in pairs(Times()) do ids[#ids + 1] = id end
	table.sort(ids)
	if #ids == 0 then S.Print(L.FLIGHT_EXPORT_NONE) return end
	local lines = {}
	for _, id in ipairs(ids) do
		lines[#lines + 1] = ('["%s"] = %d, -- %s'):format(id, Times()[id], Names()[id] or "?")
	end
	local chat = S.modules.chat
	if chat and chat.ShowText then
		chat:ShowText(L.FLIGHT_EXPORT_TITLE, table.concat(lines, "\n"))
	else
		for _, l in ipairs(lines) do print(l) end
	end
end
