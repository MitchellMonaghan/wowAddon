local _, ns = ...

if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local ELEMENTAL_SPEC_ID = 262
local EARTH_SHOCK_ID = 8042
local EARTHQUAKE_ID = 61882
local REMINDER_INTERVAL = 2.5
local SPEAK_GAP = 1.2

local isSpendWindow = false
local lastSpeakAt = 0
local reminderTicker = nil

local warning = CreateFrame("Frame", nil, UIParent)
warning:SetSize(320, 72)
warning:SetPoint("CENTER", 0, 210)
warning:Hide()
warning:SetFrameStrata("HIGH")

local bg = warning:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

local text = warning:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
text:SetPoint("CENTER", 0, 0)
text:SetTextColor(1, 0.82, 0.1, 1)
text:SetText("SPEND MAELSTROM")

local pulse = warning:CreateAnimationGroup()
pulse:SetLooping("REPEAT")
local fadeOut = pulse:CreateAnimation("Alpha")
fadeOut:SetOrder(1)
fadeOut:SetDuration(0.18)
fadeOut:SetFromAlpha(1.0)
fadeOut:SetToAlpha(0.5)
local fadeIn = pulse:CreateAnimation("Alpha")
fadeIn:SetOrder(2)
fadeIn:SetDuration(0.18)
fadeIn:SetFromAlpha(0.5)
fadeIn:SetToAlpha(1.0)

local function IsElemental()
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == ELEMENTAL_SPEC_ID
end

local function SpeakThrottled(line)
    local now = GetTime()
    if now - lastSpeakAt < SPEAK_GAP then return end
    lastSpeakAt = now
    ns.Speak(line)
end

local function IsSpellUsableCompat(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local usable = C_Spell.IsSpellUsable(spellID)
        if type(usable) == "table" then
            return usable.usable or usable.isUsable or false
        end
        return usable and true or false
    end

    if IsUsableSpell then
        local usable = IsUsableSpell(spellID)
        return usable and true or false
    end

    return false
end

local function IsSpenderUsable()
    local canShock = IsSpellUsableCompat(EARTH_SHOCK_ID)
    local canQuake = IsSpellUsableCompat(EARTHQUAKE_ID)
    return canShock or canQuake
end

local function ShowWarning()
    warning:Show()
    if not pulse:IsPlaying() then pulse:Play() end
end

local function HideWarning()
    warning:Hide()
    pulse:Stop()
    warning:SetAlpha(1.0)
end

local function StopReminderTicker()
    if reminderTicker then
        reminderTicker:Cancel()
        reminderTicker = nil
    end
end

local function StartReminderTicker()
    if reminderTicker then return end
    reminderTicker = C_Timer.NewTicker(REMINDER_INTERVAL, function()
        if isSpendWindow then
            SpeakThrottled("Spend maelstrom")
        end
    end)
end

local function UpdateMaelstromReminder()
    local active = IsElemental() and UnitAffectingCombat("player") and IsSpenderUsable()

    if active and not isSpendWindow then
        isSpendWindow = true
        ShowWarning()
        SpeakThrottled("Spend maelstrom")
        StartReminderTicker()
    elseif (not active) and isSpendWindow then
        isSpendWindow = false
        HideWarning()
        StopReminderTicker()
    elseif active then
        ShowWarning()
    end
end

local maelstromTracker = CreateFrame("Frame")
maelstromTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
maelstromTracker:RegisterEvent("PLAYER_REGEN_ENABLED")
maelstromTracker:RegisterEvent("PLAYER_REGEN_DISABLED")
maelstromTracker:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
maelstromTracker:RegisterEvent("SPELL_UPDATE_USABLE")
maelstromTracker:RegisterEvent("ACTIONBAR_UPDATE_USABLE")

maelstromTracker:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end
    UpdateMaelstromReminder()
end)
