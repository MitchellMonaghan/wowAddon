if select(2, UnitClass("player")) ~= "PALADIN" then return end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("UPDATE_BINDINGS")
driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")

local function CreateHiddenSecureMacroButton(name, macroText)
    local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
    b:Show()
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macroText)
    return b
end

local function BuildRezMacro(partyUnit)
    local lines = {}
    if partyUnit then
        lines[#lines + 1] = "/use [combat,@" .. partyUnit .. ",help,dead] Intercession"
        lines[#lines + 1] = "/use [nocombat,@" .. partyUnit .. ",help,dead] Redemption"
    end
    lines[#lines + 1] = "/use [combat,raid,@mouseover,help,dead] Intercession"
    lines[#lines + 1] = "/use [combat,@mouseover,help,dead] Intercession"
    lines[#lines + 1] = "/use [combat,@target,help,dead] Intercession"
    lines[#lines + 1] = "/use [nocombat,@mouseover,help,dead] Redemption"
    lines[#lines + 1] = "/use [nocombat,@target,help,dead] Redemption"
    return table.concat(lines, "\n")
end

local secureBaseBtn = CreateHiddenSecureMacroButton("MyScriptsPaladinRezBaseButton", BuildRezMacro(nil))
local secureShiftBtn = CreateHiddenSecureMacroButton("MyScriptsPaladinRezShiftButton", BuildRezMacro("party1"))
local secureCtrlBtn = CreateHiddenSecureMacroButton("MyScriptsPaladinRezCtrlButton", BuildRezMacro("party2"))
local secureShiftCtrlBtn = CreateHiddenSecureMacroButton("MyScriptsPaladinRezShiftCtrlButton", BuildRezMacro("party3"))
local secureShiftAltBtn = CreateHiddenSecureMacroButton("MyScriptsPaladinRezShiftAltButton", BuildRezMacro("party4"))
local secureMassBtn = CreateFrame("Button", "MyScriptsPaladinMassRezButton", UIParent, "SecureActionButtonTemplate")
secureMassBtn:RegisterForClicks("AnyDown", "AnyUp")
secureMassBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
secureMassBtn:Show()
secureMassBtn:SetAttribute("type", "spell")
secureMassBtn:SetAttribute("spell", "Absolution")

local TRACKED_SPELL_NAMES = { "Redemption", "Intercession", "Absolution" }
local TRACKED_MACRO_KEYWORDS = { "redemption", "intercession", "absolution", "rez", "res", "battle rez", "combat rez", "mass rez" }
local trackedSpellIDs = {}
local trackedSpellNamesLower = {}
local trackedSpellIDStrings = {}
local pendingRebind = false

MyScriptsDB = MyScriptsDB or {}

local function RebuildTrackedSpellIDs()
    trackedSpellIDs = {}
    trackedSpellNamesLower = {}
    trackedSpellIDStrings = {}
    if not C_Spell or not C_Spell.GetSpellInfo then return end
    for _, name in ipairs(TRACKED_SPELL_NAMES) do
        local info = C_Spell.GetSpellInfo(name)
        if info and info.spellID then
            trackedSpellIDs[info.spellID] = true
            trackedSpellIDStrings[#trackedSpellIDStrings + 1] = tostring(info.spellID)
        end
        trackedSpellNamesLower[#trackedSpellNamesLower + 1] = string.lower(name)
    end
end

local function GetMacroBodySafe(macroID)
    if C_Macro and C_Macro.GetMacroBody then
        local ok, body = pcall(C_Macro.GetMacroBody, macroID)
        if ok and type(body) == "string" and body ~= "" then
            return body
        end
    end

    if GetMacroBody then
        local ok, body = pcall(GetMacroBody, macroID)
        if ok and type(body) == "string" and body ~= "" then
            return body
        end
    end

    if GetMacroInfo then
        local ok, _, _, body = pcall(GetMacroInfo, macroID)
        if ok and type(body) == "string" and body ~= "" then
            return body
        end
    end

    return nil
end

local function ActionSlotToBindingCommand(slot)
    if slot >= 1 and slot <= 12 then
        return "ACTIONBUTTON" .. slot
    elseif slot >= 13 and slot <= 180 then
        local bar = math.floor((slot - 13) / 12) + 1
        local button = ((slot - 13) % 12) + 1
        return "MULTIACTIONBAR" .. bar .. "BUTTON" .. button
    end
    return nil
end

local function BaseKeyFromBinding(key)
    if type(key) ~= "string" then return nil end
    local base = key
    base = base:gsub("^ALT%-", "")
    base = base:gsub("^CTRL%-", "")
    base = base:gsub("^SHIFT%-", "")
    base = base:gsub("^ALT%-", "")
    base = base:gsub("^CTRL%-", "")
    base = base:gsub("^SHIFT%-", "")
    if base == "" then return nil end
    return base
end

local function BindKeyWithModifierVariants(key, variantButtons)
    local base = BaseKeyFromBinding(key)
    if not base then return end

    local variants = {
        { key = base, label = "BASE" },
        { key = "ALT-" .. base, label = "ALT" },
        { key = "SHIFT-" .. base, label = "SHIFT" },
        { key = "CTRL-" .. base, label = "CTRL" },
        { key = "ALT-SHIFT-" .. base, label = "ALT+SHIFT" },
        { key = "ALT-CTRL-" .. base, label = "ALT+CTRL" },
        { key = "CTRL-SHIFT-" .. base, label = "CTRL+SHIFT" },
        { key = "ALT-CTRL-SHIFT-" .. base, label = "ALT+CTRL+SHIFT" },
    }

    for _, v in ipairs(variants) do
        local bindButtonName = variantButtons[v.label] or variantButtons.BASE
        if bindButtonName then
            SetOverrideBindingClick(driver, true, v.key, bindButtonName, "LeftButton")
        end
    end
end

local function SlotContainsTrackedRez(slot)
    local actionType, actionID = GetActionInfo(slot)
    if not actionType then return false end

    if actionType == "spell" then
        return trackedSpellIDs[actionID] == true
    end

    if actionType == "macro" and actionID then
        if trackedSpellIDs[actionID] == true then
            return true
        end

        local macroSpellID = GetMacroSpell(actionID)
        if macroSpellID and trackedSpellIDs[macroSpellID] == true then
            return true
        end

        local body = GetMacroBodySafe(actionID)
        local actionText = GetActionText and GetActionText(slot) or nil
        if GetMacroInfo then
            local ok, macroName, _, macroBody = pcall(GetMacroInfo, actionID)
            if ok then
                if (not body or body == "") and type(macroBody) == "string" and macroBody ~= "" then
                    body = macroBody
                end
            end
        end

        if type(body) == "string" then
            local lowerBody = string.lower(body)
            for _, spellName in ipairs(trackedSpellNamesLower) do
                if string.find(lowerBody, spellName, 1, true) then
                    return true
                end
            end
            for _, idStr in ipairs(trackedSpellIDStrings) do
                if string.find(lowerBody, idStr, 1, true) then
                    return true
                end
            end
            for _, keyword in ipairs(TRACKED_MACRO_KEYWORDS) do
                if string.find(lowerBody, keyword, 1, true) then
                    return true
                end
            end
        end

        if type(actionText) == "string" and actionText ~= "" then
            local lowerActionText = string.lower(actionText)
            for _, keyword in ipairs(TRACKED_MACRO_KEYWORDS) do
                if string.find(lowerActionText, keyword, 1, true) then
                    return true
                end
            end
        end
        return false
    end

    return false
end

local function Rebind()
    if InCombatLockdown and InCombatLockdown() then
        pendingRebind = true
        return
    end
    pendingRebind = false

    ClearOverrideBindings(driver)
    RebuildTrackedSpellIDs()

    local variantButtons = {
        BASE = "MyScriptsPaladinRezBaseButton",
        ALT = "MyScriptsPaladinMassRezButton",
        SHIFT = "MyScriptsPaladinRezShiftButton",
        CTRL = "MyScriptsPaladinRezCtrlButton",
        ["ALT+SHIFT"] = "MyScriptsPaladinRezShiftAltButton",
        ["ALT+CTRL"] = "MyScriptsPaladinRezBaseButton",
        ["CTRL+SHIFT"] = "MyScriptsPaladinRezShiftCtrlButton",
        ["ALT+CTRL+SHIFT"] = "MyScriptsPaladinRezBaseButton",
    }

    local commands = {}
    for slot = 1, 180 do
        if SlotContainsTrackedRez(slot) then
            local command = ActionSlotToBindingCommand(slot)
            if command then
                commands[command] = true
            end
        end
    end

    if next(commands) == nil then
        return
    end

    for command in pairs(commands) do
        local keys = { GetBindingKey(command) }
        for _, key in ipairs(keys) do
            if key then
                BindKeyWithModifierVariants(key, variantButtons)
            end
        end
    end
end

driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and not pendingRebind then
        return
    end
    Rebind()
end)
