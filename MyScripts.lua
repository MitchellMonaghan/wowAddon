------------------------------------------------------------------------
-- HELPER: TTS FUNCTION
------------------------------------------------------------------------
local function Speak(text)
    local voice = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
    if not voice then return end
    TextToSpeech_Speak(text, voice)
end

local function PlaySmartSound(soundData)
    if not soundData then return end

    local t = type(soundData)
    
    if t == "number" then
        -- It's a Blizzard Sound ID
        PlaySound(soundData, "Master")
        
    elseif t == "string" then
        -- It's a File Path
        PlaySoundFile(soundData, "Master")
    end
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
        PlaySmartSound("Interface\\AddOns\\MyScripts\\PowerAurasMedia\\Sounds\\Gasp.ogg")
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

------------------------------------------------------------------------------------
------------------------------------------------------------------------------------
-- 1. CONFIGURATION
local PALADIN_LIGHT_ID = 53563   -- Beacon of Light
local PALADIN_FAITH_ID = 156910  -- Beacon of Faith
local PALADIN_VIRTUE_ID = 200025 -- Beacon of Virtue (The "Disable" Switch)

local SHAMAN_WATER_SHIELD_ID = 52127 -- Water Shield
local SHAMAN_EARTH_SHIELD_ID = 974   -- Earth Shield (Ally)

local _, class = UnitClass("player")
if class ~= "PALADIN" and class ~= "SHAMAN" then return end

print("|cff00ff00Buff Tracker Loaded:|r " .. class)

-- 2. CREATE THE FRAME
local classBuffReminderTracker = CreateFrame("Frame", "MyMultiBeaconContainer", UIParent)
classBuffReminderTracker:SetSize(90, 40)
classBuffReminderTracker:SetPoint("CENTER", 100, 0)
classBuffReminderTracker:Hide()

local icon1 = classBuffReminderTracker:CreateTexture(nil, "OVERLAY")
icon1:SetSize(40, 40)
icon1:SetPoint("LEFT", 0, 0)

local icon2 = classBuffReminderTracker:CreateTexture(nil, "OVERLAY")
icon2:SetSize(40, 40)
icon2:SetPoint("LEFT", 45, 0) 

-- 3. HELPER: DYNAMIC TEXTURE LOADER
local function UpdateTextures()
    if class == "PALADIN" then
        -- If Virtue is selected, we don't really care about textures because we hide everything.
        -- But for safety, we default to Light/Faith textures.
        icon1:SetTexture(C_Spell.GetSpellTexture(PALADIN_LIGHT_ID))
        icon2:SetTexture(C_Spell.GetSpellTexture(PALADIN_FAITH_ID))
        
    elseif class == "SHAMAN" then
        icon1:SetTexture(C_Spell.GetSpellTexture(SHAMAN_WATER_SHIELD_ID))
        icon2:SetTexture(C_Spell.GetSpellTexture(SHAMAN_EARTH_SHIELD_ID))
    end
end

-- 4. THE SCANNER
local function UpdateState()
    -- Safety: Combat Lock
    if InCombatLockdown() then 
        classBuffReminderTracker:Hide()
        return 
    end

    -- === SHAMAN LOGIC ===
    if class == "SHAMAN" then
        local hasWaterShield = false
        local hasAllyShield = false
        local isSolo = not IsInGroup()

        -- A: CHECK SELF (Water Shield)
        for i = 1, 40 do
            local data = C_UnitAuras.GetBuffDataByIndex("player", i)
            if not data then break end
            
            if data.spellId == SHAMAN_WATER_SHIELD_ID and data.sourceUnit == "player" then
                hasWaterShield = true
                break
            end
        end

        -- B: CHECK OTHERS (Earth Shield)
        if isSolo then
            hasAllyShield = true 
            icon2:Hide() 
        else
            local units = {}
            local prefix = IsInRaid() and "raid" or "party"
            local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
            for i = 1, count do table.insert(units, prefix..i) end

            for _, unit in ipairs(units) do
                if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                    for i = 1, 40 do
                        local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
                        if not data then break end
                        if data.spellId == SHAMAN_EARTH_SHIELD_ID and data.sourceUnit == "player" then
                            hasAllyShield = true
                            break
                        end
                    end
                end
                if hasAllyShield then break end
            end
            if hasAllyShield then icon2:Hide() else icon2:Show() end
        end

        if hasWaterShield then icon1:Hide() else icon1:Show() end
        if hasWaterShield and hasAllyShield then classBuffReminderTracker:Hide() else classBuffReminderTracker:Show() end


    -- === PALADIN LOGIC ===
    elseif class == "PALADIN" then
        
        -- TALENT CHECK: VIRTUE
        -- If we have Beacon of Virtue, we STOP here. 
        -- Virtue is not a maintenance buff, so we hide the tracker entirely.
        if IsPlayerSpell(PALADIN_VIRTUE_ID) then
            classBuffReminderTracker:Hide()
            return
        end

        -- Standard Logic for Light / Faith
        local hasLight = false  
        local hasFaith = false  
        local knowsFaith = IsPlayerSpell(PALADIN_FAITH_ID)
        
        local units = {"player"}
        if IsInGroup() then
            local prefix = IsInRaid() and "raid" or "party"
            local count = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
            for i = 1, count do table.insert(units, prefix..i) end
        end

        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                for i = 1, 40 do
                    local data = C_UnitAuras.GetBuffDataByIndex(unit, i)
                    if not data then break end
                    
                    if data.sourceUnit == "player" then
                        -- We only check for standard Light here, since Virtue is handled above
                        if data.spellId == PALADIN_LIGHT_ID then
                            hasLight = true
                        end
                        if data.spellId == PALADIN_FAITH_ID then
                            hasFaith = true
                        end
                    end
                end
            end
            if hasLight and (hasFaith or not knowsFaith) then break end 
        end

        if hasLight then icon1:Hide() else icon1:Show() end
        
        if knowsFaith then
            icon2:Show()
            if hasFaith then icon2:Hide() end
        else
            icon2:Hide() 
        end

        local lightDone = hasLight
        local faithDone = (not knowsFaith) or hasFaith
        if lightDone and faithDone then classBuffReminderTracker:Hide() else classBuffReminderTracker:Show() end
    end
end

-- 5. EVENTS
local updateQueued = false
local function RequestUpdate()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.1, function()
        UpdateState()
        updateQueued = false
    end)
end

classBuffReminderTracker:RegisterEvent("UNIT_AURA")
classBuffReminderTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
classBuffReminderTracker:RegisterEvent("GROUP_ROSTER_UPDATE")
classBuffReminderTracker:RegisterEvent("PLAYER_REGEN_ENABLED")
classBuffReminderTracker:RegisterEvent("PLAYER_REGEN_DISABLED")
classBuffReminderTracker:RegisterEvent("PLAYER_TALENT_UPDATE") 

classBuffReminderTracker:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        self:Hide()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        UpdateTextures()
        RequestUpdate()
    elseif event == "UNIT_AURA" then
        if unit and (unit == "player" or unit:find("party") or unit:find("raid")) then
            RequestUpdate()
        end
    else
        RequestUpdate()
    end
end)

-- 6. INITIALIZATION
UpdateTextures()
RequestUpdate()

----------------------------------------------------------- LUST TRACKER ----------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------
-- 1. CONFIGURATION
-- Thresholds (% Haste Jump)
local THRESHOLD_LUST = 28.0 
local THRESHOLD_PI   = 14.0 

-- AUDIO CONFIGURATION
-- You can put a Number (ID) OR a String (File Path) here.
-- Examples:
-- Number: 12867 (Raid Warning)
-- String: "Interface\\AddOns\\MyScripts\\sounds\\lust.ogg"

local SOUND_LUST = 12867  -- Currently set to Raid Warning (Alarm)
local SOUND_PI   = 12865  -- Currently set to Quest Complete (Ding)

-- 3. CREATE THE WATCHER
local lustAndPowerInfusionTracker = CreateFrame("Frame", "MyHasteAnalyzer", UIParent)
lustAndPowerInfusionTracker:Hide()

-- 4. THE ANALYZER
local lastHaste = 0
local timer = 0

lustAndPowerInfusionTracker:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer < 0.1 then return end -- Check 10x per second
    timer = 0

    -- Get current Haste %
    local currentHaste = UnitSpellHaste("player")
    
    -- Calculate the Spike
    -- We only care if haste went UP (positive delta)
    local delta = currentHaste - lastHaste

    -- Filter out tiny fluctuations (trinket ramp-ups, etc)
    if lastHaste > 0 and delta > 2.0 then
        
        -- PRIORITY 1: LUST (+30%)
        if delta >= THRESHOLD_LUST then
            print("|cffFF0000[MyScripts] LUST DETECTED! (+"..string.format("%.1f", delta).."%)|r")
            PlaySmartSound(SOUND_LUST)
            
        -- PRIORITY 2: POWER INFUSION (+20-25%)
        elseif delta >= THRESHOLD_PI then
            print("|cffFFFF00[MyScripts] PI DETECTED! (+"..string.format("%.1f", delta).."%)|r")
            PlaySmartSound(SOUND_PI)
        end
    end

    -- Update history
    lastHaste = currentHaste
end)

-- 5. COMBAT STATE MANAGEMENT
lustAndPowerInfusionTracker:RegisterEvent("PLAYER_REGEN_DISABLED")
lustAndPowerInfusionTracker:RegisterEvent("PLAYER_REGEN_ENABLED")
lustAndPowerInfusionTracker:RegisterEvent("PLAYER_ENTERING_WORLD")

lustAndPowerInfusionTracker:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Snapshot current haste so we don't trigger on the moment combat starts
        lastHaste = UnitSpellHaste("player") 
        self:Show()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:Hide()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:Hide()
    end
end)

print("|cff00ff00Haste Pulse Monitor Loaded|r")