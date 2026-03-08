if select(2, UnitClass("player")) ~= "PALADIN" then return end

local DEVOTION_AURA_ID = 465
local PALADIN_AURA_IDS = {
    465,    -- Devotion Aura
    32223,  -- Crusader Aura
    183435, -- Retribution Aura
    317920, -- Concentration Aura
}
local AURA_ID_KEYS = {
    ["465"] = true,
    ["32223"] = true,
    ["183435"] = true,
    ["317920"] = true,
}
local hasAuraFromCastState = false
local lastAuraCastAt = 0
local CAST_GRACE_SECONDS = 1.5

local reminder = CreateFrame("Frame", nil, UIParent)
reminder:SetSize(84, 84)
reminder:SetPoint("TOP", UIParent, "TOP", 0, -340)
reminder:SetFrameStrata("HIGH")
reminder:Hide()

local bg = reminder:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

local icon = reminder:CreateTexture(nil, "OVERLAY")
icon:SetSize(60, 60)
icon:SetPoint("CENTER", 0, 0)

local function GetSpellIcon(spellID, fallbackName)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then return tex end
    end
    local _, _, tex = GetSpellInfo(spellID)
    if tex then return tex end
    if fallbackName then
        local _, _, nameTex = GetSpellInfo(fallbackName)
        if nameTex then return nameTex end
    end
    return 134400
end

icon:SetTexture(GetSpellIcon(DEVOTION_AURA_ID, "Devotion Aura"))

local pulse = reminder:CreateAnimationGroup()
pulse:SetLooping("REPEAT")
local fadeOut = pulse:CreateAnimation("Alpha")
fadeOut:SetOrder(1)
fadeOut:SetDuration(0.2)
fadeOut:SetFromAlpha(1.0)
fadeOut:SetToAlpha(0.55)
local fadeIn = pulse:CreateAnimation("Alpha")
fadeIn:SetOrder(2)
fadeIn:SetDuration(0.2)
fadeIn:SetFromAlpha(0.55)
fadeIn:SetToAlpha(1.0)

local function HasLivePaladinAura()
    for _, spellID in ipairs(PALADIN_AURA_IDS) do
        if IsCurrentSpell and IsCurrentSpell(spellID) then
            return true
        end

        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if aura then
                return true
            end
        elseif AuraUtil and AuraUtil.FindAuraBySpellID then
            local aura = AuraUtil.FindAuraBySpellID(spellID, "player", "HELPFUL")
            if aura then
                return true
            end
        end
    end
    return false
end

local function HasAnyPaladinAura()
    if HasLivePaladinAura() then
        return true
    end

    if hasAuraFromCastState then
        if (GetTime() - lastAuraCastAt) <= CAST_GRACE_SECONDS then
            return true
        end
        hasAuraFromCastState = false
    end

    return false
end

local function Show()
    reminder:Show()
    if not pulse:IsPlaying() then pulse:Play() end
end

local function Hide()
    reminder:Hide()
    pulse:Stop()
    reminder:SetAlpha(1.0)
end

local function UpdateReminder()
    if UnitAffectingCombat("player") then
        Hide()
        return
    end

    if HasAnyPaladinAura() then
        Hide()
    else
        Show()
    end
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("PLAYER_ALIVE")
tracker:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")

tracker:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local key = tostring(spellID)
        if AURA_ID_KEYS[key] then
            hasAuraFromCastState = true
            lastAuraCastAt = GetTime()

            C_Timer.After(0.2, function()
                if not HasLivePaladinAura() then
                    hasAuraFromCastState = false
                end
                UpdateReminder()
            end)
        end
        UpdateReminder()
        return
    end

    if event == "PLAYER_DEAD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        hasAuraFromCastState = false
        lastAuraCastAt = 0
    end

    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end
    UpdateReminder()
end)
