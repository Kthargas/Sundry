local ADDON, S = ...
local L = S.L
local M = {}
S:RegisterModule("loot", M)

-- Loot and merchants: fast loot, selling junk, repairing, the DELETE word, buying full stacks and
-- quality borders on the character slots.

local C = C_Container
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local function NumSlots(bag) return C and C.GetContainerNumSlots(bag) or GetContainerNumSlots(bag) end
local function SlotInfo(bag, slot)
	if C and C.GetContainerItemInfo then return C.GetContainerItemInfo(bag, slot) end
	local icon, count, locked, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
	if not icon then return nil end
	return { stackCount = count, isLocked = locked, quality = quality, hyperlink = link, hasNoValue = noValue, itemID = itemID }
end
local function UseItem(bag, slot)
	if C and C.UseContainerItem then C.UseContainerItem(bag, slot) else UseContainerItem(bag, slot) end
end
local BACKPACK, LAST_BAG = 0, NUM_BAG_SLOTS or 4

local function Money(copper)
	if GetMoneyString then return GetMoneyString(copper, true) end
	return tostring(copper)
end

------------------------------------------------------------------------
-- Fast loot: take everything the moment the loot window would open (only with auto loot, the
-- modifier key that toggles auto loot still works). Throttled, the event fires twice.
------------------------------------------------------------------------
local lastLoot = 0
local function FastLoot()
	if not S:Get("loot", "fastLoot") then return end
	local auto = GetCVarBool("autoLootDefault")
	if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
	if not auto then return end
	if GetTime() - lastLoot < 0.25 then return end
	lastLoot = GetTime()
	for i = GetNumLootItems(), 1, -1 do
		LootSlot(i)
	end
end

-- Bind on pickup while looting alone: confirm without the popup
local function BindConfirm(_, slot)
	if not S:Get("loot", "bindConfirm") or IsInGroup() then return end
	ConfirmLootSlot(slot)
	StaticPopup_Hide("LOOT_BIND")
end

------------------------------------------------------------------------
-- Sell junk: grey items with a vendor price, up to 12 per visit (the buyback list holds 12).
------------------------------------------------------------------------
local selling

local function ItemID(info)
	if info.itemID then return info.itemID end
	return info.hyperlink and tonumber(info.hyperlink:match("item:(%d+)"))
end

local function JunkList()
	local list = {}
	local keep = S.db.loot.junkKeep
	for bag = BACKPACK, LAST_BAG do
		for slot = 1, NumSlots(bag) do
			local info = SlotInfo(bag, slot)
			if info and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				local id = ItemID(info)
				if id and not keep[id] then
					local price = select(11, GetItemInfo(id)) or 0
					if price > 0 then
						list[#list + 1] = { bag = bag, slot = slot, value = price * (info.stackCount or 1) }
					end
				end
			end
		end
	end
	return list
end

local function SellJunk()
	if not S:Get("loot", "sellJunk") or selling then return end
	local list = JunkList()
	if #list == 0 then return end
	selling = { total = 0, count = 0 }
	local i = 0
	local function Step()
		if not selling or not (MerchantFrame and MerchantFrame:IsShown()) then selling = nil return end
		i = i + 1
		local item = list[i]
		if not item or i > 12 then
			if S.db.loot.junkSummary and selling.count > 0 then
				S.Print(L.JUNK_SOLD:format(selling.count, Money(selling.total)))
			end
			selling = nil
			return
		end
		UseItem(item.bag, item.slot)
		selling.total = selling.total + item.value
		selling.count = selling.count + 1
		C_Timer.After(0.15, Step)
	end
	Step()
end

function M:JunkCommand(rest)
	local action, item = rest:match("^(%S*)%s*(.-)$")
	action = (action or ""):lower()
	local id = tonumber(item) or (item and tonumber(item:match("item:(%d+)")))
	local keep = S.db.loot.junkKeep
	if action == "add" and id then
		keep[id] = true
		S.Print(L.JUNK_KEEP_ADDED:format(item))
	elseif action == "remove" and id then
		keep[id] = nil
		S.Print(L.JUNK_KEEP_REMOVED:format(item))
	else
		S.Print(L.JUNK_HELP)
		for kept in pairs(keep) do
			local _, link = GetItemInfo(kept)
			print("   " .. (link or kept))
		end
	end
end

------------------------------------------------------------------------
-- Repair: guild bank first when chosen and allowed, otherwise own gold.
------------------------------------------------------------------------
local function Repair()
	if not S:Get("loot", "repair") or not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end
	if S.db.loot.repairGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
		if limit == -1 or limit >= cost then
			RepairAllItems(true)
			S.Print(L.REPAIRED_GUILD:format(Money(cost)))
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems()
		S.Print(L.REPAIRED:format(Money(cost)))
	else
		S.Print(L.REPAIR_NO_MONEY:format(Money(cost)))
	end
end

------------------------------------------------------------------------
-- DELETE: fill in the confirmation word when destroying a good item
------------------------------------------------------------------------
local function FillDelete(popup)
	if not S:Get("loot", "deleteText") then return end
	local box = popup.editBox or (popup.GetEditBox and popup:GetEditBox())
	if box and DELETE_ITEM_CONFIRM_STRING then box:SetText(DELETE_ITEM_CONFIRM_STRING) end
end

local function HookDelete()
	for _, which in ipairs({ "DELETE_GOOD_ITEM", "DELETE_GOOD_QUEST_ITEM" }) do
		local dialog = StaticPopupDialogs[which]
		if dialog and dialog.OnShow then
			hooksecurefunc(dialog, "OnShow", FillDelete)
		end
	end
end

------------------------------------------------------------------------
-- Alt + click on a merchant item buys a full stack (asks above a price)
------------------------------------------------------------------------
local function MerchantInfo(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then return info.name, info.price, info.stackCount end
	end
	local name, _, price, quantity = GetMerchantItemInfo(index)
	return name, price, quantity
end

StaticPopupDialogs["SUNDRY_BUY_STACK"] = {
	text = L.BUY_STACK_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data) BuyMerchantItem(data.index, data.count) end,
	timeout = 0,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function BuyStack(button, mouse)
	if not S:Get("loot", "stackBuy") or mouse ~= "LeftButton" or not IsAltKeyDown() then return end
	if not (MerchantFrame and MerchantFrame.selectedTab == 1) then return end
	local index = button:GetID()
	local name, price, perBuy = MerchantInfo(index)
	local stack = GetMerchantItemMaxStack(index) or 1
	if not name or stack <= 1 then return end
	perBuy = math.max(perBuy or 1, 1)
	local total = math.floor(stack / perBuy) * (price or 0)
	local limit = (S.db.loot.stackConfirm or 0) * 10000
	if limit > 0 and total >= limit then
		StaticPopup_Show("SUNDRY_BUY_STACK", stack, name, { index = index, count = stack })
	else
		BuyMerchantItem(index, stack)
	end
end

------------------------------------------------------------------------
-- Quality borders on the character slots (Blizzard's own border, coloured by rarity)
------------------------------------------------------------------------
local function SlotQuality(button)
	if not S:Get("loot", "qualityBorders") or not button.IconBorder then return end
	local link = GetInventoryItemLink("player", button:GetID())
	local quality = link and select(3, GetItemInfo(link))
	if quality and quality >= 2 and BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[quality] then
		local c = BAG_ITEM_QUALITY_COLORS[quality]
		button.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
		button.IconBorder:SetVertexColor(c.r, c.g, c.b)
		button.IconBorder:Show()
	end
end

------------------------------------------------------------------------
function M:Init()
	S:On("LOOT_READY", FastLoot)
	S:On("LOOT_OPENED", FastLoot)
	S:On("LOOT_BIND_CONFIRM", BindConfirm)
	S:On("MERCHANT_SHOW", function()
		Repair()
		SellJunk()
	end)
	S:On("MERCHANT_CLOSED", function() selling = nil end)
	HookDelete()
	S.Hook("MerchantItemButton_OnModifiedClick", BuyStack)
	S.Hook("PaperDollItemSlotButton_Update", SlotQuality)
end
