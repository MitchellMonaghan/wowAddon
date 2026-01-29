local _, ns = ...

local lowHealthTracker = CreateFrame("Frame", "MyHealingHijacker", UIParent)
lowHealthTracker:SetSize(80, 80)
lowHealthTracker:SetPoint("CENTER", 0, 0)
lowHealthTracker.tex = lowHealthTracker:CreateTexture(nil, "OVERLAY")
lowHealthTracker.tex:SetAllPoints()
lowHealthTracker:Hide()

local HS_ID    = 5512
local POT_NAME = "Algari Healing Potion"
local POT_SPELL_ID = 431416

local function GetPotionData()
    -- We scan the bags for any item that matches our Spell ID
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local spellName, spellID = C_Item.GetItemSpell(itemID)
                if spellID == POT_SPELL_ID then
                    local count = C_Item.GetItemCount(itemID)
                    local start, duration = C_Item.GetItemCooldown(itemID)
                    -- print("|cff00ff00[MyScripts]|r PotionDuration:", duration)
                    -- Return the first match found (highest rank usually first in bags)
                    return count, (duration or 0) == 0, C_Item.GetItemIconByID(itemID)
                end
            end
        end
    end
    return 0, false, nil
end

-- === THE STABILIZED CHECK ===
local function RefreshSmartIcon(self)
    local hsCount = C_Item.GetItemCount(HS_ID, false, true)
    local isHSUsable = C_Item.IsUsableItem(HS_ID)
    
    -- 2. Check Potion (Scanner finds any rank)
    local potCount, isPotReady, potIcon = GetPotionData()

    -- === DIAGNOSTIC LOGS ===
    -- print("|cff00ff00[MyScripts]|r Healthstone:", hsCount, "Usable:", tostring(isHSUsable))
    -- print("|cff00ff00[MyScripts]|r Potion Count:", potCount, "Ready:", tostring(isPotReady))

    -- 1. Determine priority and set texture
    if hsCount > 0 and isHSUsable then
        self.tex:SetTexture(C_Item.GetItemIconByID(HS_ID))
        self:SetAlpha(1)
        -- print("|cff00ff00[MyScripts]|r Visuals: Showing Healthstone")
        return true
    elseif isPotReady then
        self.tex:SetTexture(potIcon)
        self:SetAlpha(1)
        -- print("|cff00ff00[MyScripts]|r Visuals: Showing Potion")
        return true
    else
        -- If neither is ready, we stay "Active" but invisible
        self:SetAlpha(0)
        -- print("|cff00ff00[MyScripts]|r Visuals: Hiding (Nothing ready)")
        return false
    end
end

if LowHealthFrame then
    LowHealthFrame:HookScript("OnShow", function()
        -- print("|cff00ff00[MyScripts]|r LowHealthFrame Triggered!")
        local hasHeal = RefreshSmartIcon(lowHealthTracker)
        lowHealthTracker:Show()
        ns.PlaySmartSound(ns.Sounds.LowHP)
    end)

    LowHealthFrame:HookScript("OnHide", function()
        -- print("|cff00ff00[MyScripts]|r LowHealthFrame Hidden")
        lowHealthTracker:Hide()
    end)
end

-- Watchers to update the icon while the alert is already on-screen
lowHealthTracker:RegisterEvent("BAG_UPDATE")
lowHealthTracker:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
lowHealthTracker:SetScript("OnEvent", function(self)
    if self:IsShown() then
        RefreshSmartIcon(self)
    end
end)