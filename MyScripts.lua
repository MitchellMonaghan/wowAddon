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
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")

-- === CONFIGURATION ===
local btnName  = "MultiBar6Button4" 
local hsItem   = 5512 
local potItem  = 211879 -- Algari Healing Potion
local oocSpell = "Recuperate"     

-- === VISUAL UPDATER ===
local function UpdateIcon(btn)
    if not btn.VisualOverlay then return end
    local inCombat = UnitAffectingCombat("player")
    local step = tonumber(btn:GetAttribute("step")) or 1
    
    local currentID
    if not inCombat then
        btn.VisualOverlay.tex:SetTexture(btn.iconOOC)
        currentID = nil -- We don't usually track stacks for a spell
    elseif step == 2 then
        btn.VisualOverlay.tex:SetTexture(btn.iconPot)
        currentID = potItem
    else
        btn.VisualOverlay.tex:SetTexture(btn.iconHS)
        currentID = hsItem
    end

    -- 1. UPDATE STACKS
    if currentID then
        local count = C_Item.GetItemCount(currentID)
        btn.VisualOverlay.count:SetText(count > 1 and count or "")
    else
        btn.VisualOverlay.count:SetText("")
    end

    -- 2. UPDATE COOLDOWN
    local start, duration
    if not inCombat then
        local spellInfo = C_Spell.GetSpellCooldown(oocSpell)
        if spellInfo then start, duration = spellInfo.startTime, spellInfo.duration end
    else
        -- For items, use the ID directly
        local itemID = (step == 2) and potItem or hsItem
        start, duration = C_Item.GetItemCooldown(itemID)
    end
    
    if start and duration and duration > 0 then
        btn.VisualOverlay.cooldown:SetCooldown(start, duration)
        btn.VisualOverlay.cooldown:Show()
    else
        btn.VisualOverlay.cooldown:Hide()
    end
end

-- === SETUP VISUALS ===
local function SetupOverlay(btn)
    if btn.VisualOverlay then return end
    
    -- The Container (We set this to HIGH so it beats the default button layers)
    local f = CreateFrame("Frame", nil, btn) 
    f:SetFrameStrata("HIGH") 
    f:SetFrameLevel(btn:GetFrameLevel() + 10)
    f:SetAllPoints(btn)
    
    -- The Icon Texture
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(f)
    
    -- The Cooldown Swipe (Template-based)
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetFrameLevel(f:GetFrameLevel() + 1)
    
    -- The Stack Count Text
    local count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    count:SetJustifyH("RIGHT")

    -- Cache textures
    btn.iconHS  = C_Item.GetItemIconByID(hsItem) or 134414
    btn.iconPot = C_Item.GetItemIconByID(potItem) or 537027
    btn.iconOOC = C_Spell.GetSpellTexture(oocSpell) or 132274
    
    btn.VisualOverlay = f
    btn.VisualOverlay.tex = t
    btn.VisualOverlay.cooldown = cd
    btn.VisualOverlay.count = count
end

loader:SetScript("OnEvent", function(self, event)
    local btn = _G[btnName]
    if not btn or event ~= "PLAYER_LOGIN" then return end
    
    SetupOverlay(btn)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    -- Binding Logic
    ClearOverrideBindings(btn)
    local key = GetBindingKey("MULTIACTIONBAR6BUTTON4") 
    if key then SetOverrideBindingClick(btn, true, key, btnName, "LeftButton") end

    -- Secure Puppeteer
    local puppeteer = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
    puppeteer:SetFrameRef("MyButton", btn)
    puppeteer:SetAttribute("_onstate-combatcheck", [[
        self:GetFrameRef("MyButton"):SetAttribute("step", 1)
    ]])
    RegisterStateDriver(puppeteer, "combatcheck", "[combat] 1; 0")

    -- Secure Click Logic
    btn:SetAttribute("type", "macro")
    local snippet = string.format([[
        if not down then return end 
        local inCombat = PlayerInCombat()
        local step = tonumber(self:GetAttribute("step")) or 1
        if inCombat then
            if step == 1 then
                self:SetAttribute("macrotext", "/use item:%s")
                self:SetAttribute("step", 2)
            else
                self:SetAttribute("macrotext", "/use item:%s")
                self:SetAttribute("step", 1)
            end
        else
            self:SetAttribute("macrotext", "/cast %s")
        end
    ]], hsItem, potItem, oocSpell)
    
    SecureHandlerWrapScript(btn, "OnClick", btn, snippet)

    -- Visual Bridge
    btn:HookScript("OnAttributeChanged", function(self, name)
        if name == "step" or name == "macrotext" then UpdateIcon(self) end
    end)

    -- Watch for cooldown and bag changes
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    watcher:RegisterEvent("BAG_UPDATE")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function() UpdateIcon(btn) end)

    btn:SetAttribute("step", 1)
    UpdateIcon(btn)
end)