------------------------------------------------------------------------
-- HELPER: TTS FUNCTION
------------------------------------------------------------------------
local function Speak(text)
    local voice = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
    if not voice then return end
    TextToSpeech_Speak(text, voice)
end

-- Healing Stream Tracking --
local hstTracker = CreateFrame("Frame")
hstTracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Variables to track our "Imaginary" Cooldown
local hstTimerHandle = nil
local timeToCap = 0 

hstTracker:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    -- Check for HST (5394) or Surging Totem (430191) from the Player
    if unit == "player" and (spellID == 5394 or spellID == 430191) then
        
        local now = GetTime()
        local cdDuration = 20 -- FIXED 20s Cooldown (Change this if your haste changes massively)
        
        -- LOGIC:
        -- If 'timeToCap' is in the past, it means we were already fully capped.
        -- So we start the clock from NOW.
        if timeToCap < now then
            timeToCap = now
        end
        
        -- We just used a charge, so we are now one 'duration' further away from being full.
        timeToCap = timeToCap + cdDuration
        
        -- We want the alarm 3 seconds BEFORE we hit the cap.
        local alarmTime = timeToCap - 3
        local delay = alarmTime - now
        
        -- Cancel the old timer (because we just pushed the deadline back)
        if hstTimerHandle then hstTimerHandle:Cancel() end
        
        -- Schedule the new sound
        if delay > 0 then
            hstTimerHandle = C_Timer.NewTimer(delay, function()
                -- PlaySound(12891, "Master")
                -- print("|cff00ff00Totem Capping in 3s!|r") -- Uncomment to verify visual 
                Speak("Healing Stream")
            end)
        end
    end
end)

-- Riptide Tracking --
------------------------------------------------------------------------
-- RIPTIDE TRACKER (Blind Math + Reduction Logic)
------------------------------------------------------------------------
local ripTracker = CreateFrame("Frame")
ripTracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local ripTimerHandle = nil
local ripCapTime = 0 -- The exact moment (GetTime) when you will have 2 charges

-- CONFIGURATION:
local RIP_CD_BASE = 5.0  -- CHECK YOUR SPELLBOOK! Set this to your actual CD.
local REDUCTION = 2.0    -- How many seconds Ancestors reduce the CD.

-- Helper to update the sound timer
local function UpdateRipTimer()
    local now = GetTime()
    
    -- We want the alarm 3 seconds BEFORE the cap
    local alarmTime = ripCapTime - 3
    local delay = alarmTime - now
    
    -- Cancel the old timer (because the math just changed)
    if ripTimerHandle then ripTimerHandle:Cancel() end
    
    -- Schedule the new sound if the target time is in the future
    if delay > 0 then
        ripTimerHandle = C_Timer.NewTimer(delay, function()
            -- You might want a different sound for Riptide to distinguish it from Totem
            -- 11466 = Ding. 567476 = Tick.
            -- PlaySound(7308, "Master")
            -- PlaySoundFile("Interface\\AddOns\\SharedMedia_Causese\\sound\\FILENAME.ogg", "Master") 
            Speak("Riptide")
            -- print("|cff00ffffRiptide Ready in 3s!|r") 
        end)
    end
end

ripTracker:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    
    local now = GetTime()

    ---------------------------------------------------
    -- EVENT 1: CAST RIPTIDE (Add Time)
    -- Spell ID 61295 is the base Riptide
    ---------------------------------------------------
    if spellID == 61295 then
        -- If we were already fully capped (time is in the past), reset to NOW.
        if ripCapTime < now then ripCapTime = now end
        
        -- Add the cooldown to the stack
        ripCapTime = ripCapTime + RIP_CD_BASE
        
        UpdateRipTimer()
        
    ---------------------------------------------------
    -- EVENT 2: ANCESTOR SPAWNERS (Subtract Time)
    -- 73685  = Unleash Life
    -- 443454 = Ancestral Swiftness (Farseer Ability)
    -- Add other IDs here if other spells trigger the reduction
    ---------------------------------------------------
    elseif spellID == 73685 or spellID == 443454 then
        -- Only subtract if we are currently on cooldown
        if ripCapTime > now then
            ripCapTime = ripCapTime - REDUCTION
            
            -- Don't let the time go negative (can't have charges faster than NOW)
            if ripCapTime < now then ripCapTime = now end
            
            UpdateRipTimer()
        end
    end
end)


--------------------------------- PALADIN ------------------------------------------------
------------------------------------------------------------------------
-- THE ULTIMATE REZ BUTTON (Class-Aware Version)
------------------------------------------------------------------------
local oneButtonRezFrame = CreateFrame("Frame")
oneButtonRezFrame:RegisterEvent("PLAYER_LOGIN")
oneButtonRezFrame:SetScript("OnEvent", function()
    
    -- 1. DETECT CLASS & CONFIGURE SPELLS
    local _, class = UnitClass("player")
    local spellNormal, spellCombat, spellMass

    if class == "PALADIN" then
        spellNormal = "Redemption"
        spellCombat = "Intercession"
        spellMass   = "Absolution"
        print("|cff00ff00[MyScripts] Rez Logic: Paladin Mode Loaded|r")
        
    elseif class == "SHAMAN" then
        spellNormal = "Ancestral Spirit"
        spellCombat = "Ancestral Spirit" -- Shamans have no targetable B-Rez
        spellMass   = "Ancestral Vision"
        print("|cff00ff00[MyScripts] Rez Logic: Shaman Mode Loaded|r")
        
    else
        -- If not Paladin or Shaman, stop here so we don't break the button.
        return 
    end

    -- 2. TARGET BUTTON: Action Bar 2, Button 6 (Tilde)
    local btnName = "MultiBarBottomLeftButton6" 
    local btn = _G[btnName]
    
    if not btn then 
        print("|cffff0000[MyScripts] Error: Could not find " .. btnName .. "|r")
        return 
    end

    -- 3. KEYBIND BRIDGE (Fixes the "Press vs Click" issue)
    ClearOverrideBindings(btn)
    local bindCommand = "MULTIACTIONBAR1BUTTON6" -- System name for BottomLeft Btn 6
    local key = GetBindingKey(bindCommand)
    
    if key then
        SetOverrideBindingClick(btn, true, key, btnName)
    end

    -- 4. THE LOGIC SNIPPET (Dynamically built with your class spells)
    -- We insert the spell names we defined above into the secure string.
    local preClick = string.format([[
        -- Define Logic
        local target = ""
        local spell = "%s" -- Normal Spell (Redemption / Ancestral Spirit)
        
        -- Modifiers
        if IsShiftKeyDown() and IsAltKeyDown() then target = "@party4"
        elseif IsShiftKeyDown() and IsControlKeyDown() then target = "@party3"
        elseif IsControlKeyDown() then target = "@party2"
        elseif IsShiftKeyDown() then target = "@party1"
        end

        -- Mass Rez (Alt)
        -- If we aren't targeting a specific party member, Alt triggers Mass Rez.
        if target == "" and IsAltKeyDown() then 
            spell = "%s" -- Mass Spell (Absolution / Ancestral Vision)
        end

        -- Combat Check
        if PlayerInCombat() then
            -- If we were going to cast Normal Rez, switch to Combat Rez
            if spell == "%s" then 
                spell = "%s" -- Combat Spell (Intercession / Ancestral Spirit)
            end
        end

        -- Build Macro
        local macro = ""
        if target ~= "" then
            macro = "/use [" .. target .. ",dead] " .. spell
        else
            if PlayerInCombat() then
                 -- In Combat Logic
                 macro = "/use [@mouseover,raid,help,dead][] " .. spell
            else
                 -- Out of Combat Logic
                 macro = "/use [@mouseover,raid,help,dead][] " .. spell
            end
        end

        -- HIJACK
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", macro)
    ]], spellNormal, spellMass, spellNormal, spellCombat)

    -- 5. THE CLEANUP
    local postClick = [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    ]]

    -- 6. ATTACH
    SecureHandlerWrapScript(btn, "OnClick", btn, preClick, postClick)
end)

--------------------------------- AutoPotion -----------------------------------------------
--------------------------------------------------------------------------------------------
-- local loader = CreateFrame("Frame")
-- loader:RegisterEvent("PLAYER_LOGIN")

-- -- === CONFIGURATION ===
-- local btnName  = "MultiBar6Button4" 
-- local hsName   = "Healthstone"      
-- local potName  = "Algari Healing Potion"
-- local potId
-- local hsItemID = 5512

-- -- === VISUAL UPDATER ===
-- local function UpdateIcon(btn)
--     if not btn or not btn.VisualOverlay then return end
    
--     local step = tonumber(btn:GetAttribute("step")) or 1
    
--     -- 1. Texture and Count Logic
--     if step == 2 then
--         btn.VisualOverlay.tex:SetTexture(btn.iconPot)
--         local potCount = C_Item.GetItemCount(potName)
--         btn.VisualOverlay.count:SetText((potCount and potCount > 0) and potCount or "")
--     else
--         btn.VisualOverlay.tex:SetTexture(btn.iconHS)
--         local hsCount = C_Item.GetItemCount(hsName, false, true)
--         btn.VisualOverlay.count:SetText((hsCount and hsCount > 0) and hsCount or "")
--     end

--     -- 2. Cooldown Logic
--     -- Note: Potion CD check by name can be finicky, so we use a generic health potion ID for the CD swipe
--     local cdID = (step == 2) and 211878 or hsItemID
--     local start, duration = C_Item.GetItemCooldown(cdID)
    
--     if start and duration and duration > 0 then
--         btn.VisualOverlay.cooldown:SetCooldown(start, duration)
--         btn.VisualOverlay.cooldown:Show()
--     else
--         btn.VisualOverlay.cooldown:Hide()
--     end
-- end

-- -- === SETUP VISUALS ===
-- local function SetupOverlay(btn)
--     if btn.VisualOverlay then return end
    
--     local f = CreateFrame("Frame", nil, btn) 
--     f:SetFrameStrata("HIGH") 
--     f:SetFrameLevel(btn:GetFrameLevel() + 20)
--     f:SetAllPoints(btn)
    
--     local t = f:CreateTexture(nil, "OVERLAY")
--     t:SetAllPoints(f)
    
--     local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
--     cd:SetAllPoints(f)
--     cd:SetFrameLevel(f:GetFrameLevel() + 1)
    
--     local count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
--     count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)

--     -- Assign references safely
--     btn.VisualOverlay = f
--     f.tex = t
--     f.cooldown = cd
--     f.count = count

--     -- Cache icons (Using IDs for icons is still best for performance)
--     btn.iconHS  = C_Item.GetItemIconByID(hsItemID) or 134414
--     btn.iconPot = C_Item.GetItemIconByID(211878) or 5931169
-- end

-- loader:SetScript("OnEvent", function(self, event)
--     local btn = _G[btnName]
--     if not btn then return end

--     if event == "PLAYER_LOGIN" then
--         SetupOverlay(btn)
--         btn:RegisterForClicks("AnyDown", "AnyUp")
        
--         ClearOverrideBindings(btn)
--         local key = GetBindingKey("MULTIACTIONBAR6BUTTON4") 
--         if key then SetOverrideBindingClick(btn, true, key, btnName, "LeftButton") end

--         -- 1. THE SECURE PUPPETEER (Reset on Combat Transition)
--         local puppeteer = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
--         puppeteer:SetFrameRef("MyButton", btn)
--         puppeteer:SetAttribute("_onstate-combatcheck", [[
--             local btn = self:GetFrameRef("MyButton")
--             btn:SetAttribute("step", 1)
--         ]])
--         RegisterStateDriver(puppeteer, "combatcheck", "[combat] 1; 0")

--         -- 2. THE CLICK LOGIC (Infinite Cycle by Name)
--         btn:SetAttribute("type", "macro")
--         SecureHandlerWrapScript(btn, "OnClick", btn, string.format([[
--             if not down then return end
            
--             local step = tonumber(self:GetAttribute("step")) or 1
            
--             if step == 1 then
--                 self:SetAttribute("macrotext", "/use %s")
--                 self:SetAttribute("step", 2)
--             else
--                 self:SetAttribute("macrotext", "/use %s")
--                 self:SetAttribute("step", 1)
--             end
--         ]], hsName, potName))

--         btn:HookScript("OnAttributeChanged", function(self, name)
--             if name == "step" then UpdateIcon(self) end
--         end)

--         UpdateIcon(btn)
--     else
--         UpdateIcon(btn)
--     end
-- end)

-- loader:RegisterEvent("BAG_UPDATE")
-- loader:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
-- loader:RegisterEvent("PLAYER_REGEN_ENABLED")
-- loader:RegisterEvent("PLAYER_REGEN_DISABLED")

------------------------------------------ Low Health Aura ---------------------------------
--------------------------------------------------------------------------------------------
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
        PlaySoundFile("Interface\\AddOns\\MyScripts\\PowerAurasMedia\\Sounds\\Gasp.ogg", "Master")
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