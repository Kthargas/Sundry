local ADDON, S = ...
local M = {}
S:RegisterModule("bags", M)

-- Bag window: fill the slots from the top left (Blizzard leaves the gap of a partly filled row at the top
-- left, Sundry moves it to the bottom right) and dock the reagent bag under the combined bag as an own
-- area. Moving the bag windows is done by the Windows module.
--
-- Sundry only re-anchors Blizzard's item buttons after Blizzard has laid them out (post-hooks on
-- UpdateItemLayout, UpdateFrameSize and UpdateContainerFrameAnchors); the order of the items stays the
-- same, only the empty cells move to the end.

local GAP = 6            -- space between the combined bag and the docked reagent bag
local touched = {}       -- frames whose layout Sundry changed (to give back to Blizzard)
local arranging

local function ReagentBagID()
	return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
end

local function Items(frame)
	local list = {}
	if frame.EnumerateValidItems then
		for _, button in frame:EnumerateValidItems() do
			if button:IsShown() then list[#list + 1] = button end
		end
	elseif type(frame.Items) == "table" then
		for _, button in ipairs(frame.Items) do
			if button:IsShown() then list[#list + 1] = button end
		end
	end
	return list
end

local function Round(v) return math.floor(v + 0.5) end

-- The grid Blizzard used: columns, first cell and step, read from the buttons' positions.
local function ReadGrid(buttons)
	local lefts, tops = {}, {}
	local cells = {}
	for _, button in ipairs(buttons) do
		local left, top = button:GetLeft(), button:GetTop()
		if not left or not top then return nil end
		left, top = Round(left), Round(top)
		lefts[left] = true
		tops[top] = true
		cells[#cells + 1] = { button = button, left = left, top = top }
	end
	if #cells == 0 then return nil end
	local xs, ys = {}, {}
	for x in pairs(lefts) do xs[#xs + 1] = x end
	for y in pairs(tops) do ys[#ys + 1] = y end
	table.sort(xs)
	table.sort(ys, function(a, b) return a > b end)
	local stepX, stepY = nil, nil
	for i = 2, #xs do
		local d = xs[i] - xs[i - 1]
		if d > 0 and (not stepX or d < stepX) then stepX = d end
	end
	for i = 2, #ys do
		local d = ys[i - 1] - ys[i]
		if d > 0 and (not stepY or d < stepY) then stepY = d end
	end
	local size = buttons[1]:GetWidth() or 37
	stepX = stepX or (size + 5)
	stepY = stepY or stepX
	-- reading order: top row first, left to right
	table.sort(cells, function(a, b)
		if a.top ~= b.top then return a.top > b.top end
		return a.left < b.left
	end)
	return {
		cells = cells, columns = Round((xs[#xs] - xs[1]) / stepX) + 1,
		left = xs[1], top = ys[1], bottom = ys[#ys], stepX = stepX, stepY = stepY,
	}
end

-- Put the buttons cell by cell, starting at the top left.
local function Place(frame, cells, columns, left, top, stepX, stepY)
	local fLeft, fTop = frame:GetLeft(), frame:GetTop()
	if not fLeft or not fTop then return end
	for i, cell in ipairs(cells) do
		local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
		cell.button:ClearAllPoints()
		cell.button:SetPoint("TOPLEFT", frame, "TOPLEFT", left + col * stepX - fLeft, top - row * stepY - fTop)
	end
	touched[frame] = true
end

local function FindReagentFrame()
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame.GetBagID and frame:IsShown() and frame:GetBagID() == ReagentBagID() then return frame end
	end
end

local function Undock(frame)
	if not frame or not frame.sundryDocked then return end
	frame.sundryDocked = nil
	if frame.UpdateItemLayout then pcall(frame.UpdateItemLayout, frame) end
	if UpdateContainerFrameAnchors then pcall(UpdateContainerFrameAnchors) end
end

-- The reagent bag below the combined bag: same width, same columns, its slots lined up with the bag's.
local function Dock(combined, grid)
	local reagent = FindReagentFrame()
	if not reagent then return end
	local buttons = Items(reagent)
	local own = ReadGrid(buttons)
	if not own then return end
	reagent.sundryDocked = true
	if math.abs(reagent:GetScale() - combined:GetScale()) > 0.001 then
		reagent:SetScale(combined:GetScale())
		own = ReadGrid(buttons)
		if not own then return end
	end

	-- padding of Blizzard's own layout, read once (later reads would see Sundry's size)
	if not reagent.sundryPads then
		local top = reagent:GetTop() - own.top
		local bottom = (own.bottom - (buttons[1]:GetHeight() or 37)) - reagent:GetBottom()
		if top > 0 and top < 120 then reagent.sundryPads = { top = top, bottom = math.max(bottom, 4) } end
	end
	local pads = reagent.sundryPads or { top = 30, bottom = 8 }
	local topPad, bottomPad = pads.top, pads.bottom
	local rows = math.ceil(#buttons / grid.columns)
	local height = topPad + (rows - 1) * grid.stepY + (buttons[1]:GetHeight() or 37) + math.max(bottomPad, 4)

	reagent:ClearAllPoints()
	reagent:SetPoint("TOPLEFT", combined, "BOTTOMLEFT", 0, -GAP)
	reagent:SetSize(combined:GetWidth(), height)

	-- keep the docked area on the screen: lift the combined bag when it sits too low
	local bottom = combined:GetBottom()
	if bottom and bottom - GAP - height < 0 and not InCombatLockdown() then
		local lift = height + GAP - bottom
		local cLeft, cTop = combined:GetLeft(), combined:GetTop()
		combined:ClearAllPoints()
		combined:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cLeft, cTop + lift)
	end

	-- same columns and x position as the combined bag
	local offsetX = grid.left - combined:GetLeft()
	Place(reagent, own.cells, grid.columns, reagent:GetLeft() + offsetX, reagent:GetTop() - topPad, grid.stepX, grid.stepY)
end

local function Arrange()
	if arranging then return end
	if InCombatLockdown() then S.AfterCombat("bags", Arrange) return end
	arranging = true
	local ok, err = pcall(function()
		local combined = ContainerFrameCombinedBags
		local fill = S:Get("bags", "fillTop")
		if combined and combined:IsShown() then
			local grid = ReadGrid(Items(combined))
			if grid then
				if fill then
					Place(combined, grid.cells, grid.columns, grid.left, grid.top, grid.stepX, grid.stepY)
				end
				if S:Get("bags", "reagentDock") then
					Dock(combined, grid)
				else
					Undock(FindReagentFrame())
				end
			end
		else
			Undock(FindReagentFrame())
		end
		-- single bags (when the combined bag is off in Blizzard's options)
		if fill then
			for i = 1, 13 do
				local frame = _G["ContainerFrame" .. i]
				if frame and frame:IsShown() and not frame.sundryDocked then
					local grid = ReadGrid(Items(frame))
					if grid then Place(frame, grid.cells, grid.columns, grid.left, grid.top, grid.stepX, grid.stepY) end
				end
			end
		end
	end)
	arranging = nil
	if not ok then geterrorhandler()(err) end
end

-- Open and close the reagent bag together with the combined bag.
-- Settled a moment after the last click, so fast clicking on the bag buttons does not race Blizzard's own
-- opening and closing.
local pending
local function SyncReagent()
	pending = nil
	local combined = ContainerFrameCombinedBags
	if not combined or not S:Get("bags", "reagentDock") then return end
	local reagent = FindReagentFrame()
	if combined:IsShown() then
		local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(ReagentBagID()) or 0
		if not reagent and slots > 0 and OpenBag then pcall(OpenBag, ReagentBagID()) end
	elseif reagent and reagent.sundryDocked and CloseBag then
		pcall(CloseBag, ReagentBagID())
	end
	Arrange()
	-- items that were not laid out yet when the bag opened
	C_Timer.After(0.2, Arrange)
end

local function QueueSync()
	if pending then return end
	pending = true
	C_Timer.After(0.15, SyncReagent)
end
local OnCombinedShow, OnCombinedHide = QueueSync, QueueSync

local hooked = {}
local function HookFrame(frame)
	if not frame or hooked[frame] then return end
	hooked[frame] = true
	for _, method in ipairs({ "UpdateItemLayout", "UpdateFrameSize", "UpdateItems" }) do
		if type(frame[method]) == "function" then hooksecurefunc(frame, method, Arrange) end
	end
	frame:HookScript("OnShow", function() C_Timer.After(0, Arrange) end)
end

function M:Init()
	HookFrame(ContainerFrameCombinedBags)
	for i = 1, 13 do HookFrame(_G["ContainerFrame" .. i]) end
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:HookScript("OnShow", OnCombinedShow)
		ContainerFrameCombinedBags:HookScript("OnHide", OnCombinedHide)
	end
	S.Hook("UpdateContainerFrameAnchors", Arrange)
end

function M:Apply()
	if not S:Get("bags", "reagentDock") then Undock(FindReagentFrame()) end
	-- give the layout back to Blizzard when filling from the top is switched off
	if not S:Get("bags", "fillTop") then
		for frame in pairs(touched) do
			touched[frame] = nil
			if frame:IsShown() and frame.UpdateItemLayout then pcall(frame.UpdateItemLayout, frame) end
		end
	end
	Arrange()
end
