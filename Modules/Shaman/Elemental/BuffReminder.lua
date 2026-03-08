if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local ELEMENTAL_SPEC_ID = 262
local LIGHTNING_SHIELD_ID = 192106
local SKYFURY_ID = 462854
local SKYFURY_NAME = "Skyfury"
local LIGHTNING_SHIELD_NAME = C_Spell.GetSpellName and C_Spell.GetSpellName(LIGHTNING_SHIELD_ID) or "Lightning Shield"

local reminder = CreateFrame("Frame", nil, UIParent)
reminder:SetSize(160, 64)
reminder:SetPoint("TOP", UIParent, "TOP", 0, -340)
reminder:SetFrameStrata("HIGH")
reminder:Hide()

local bg = reminder:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

local iconLightning = reminder:CreateTexture(nil, "OVERLAY")
iconLightning:SetSize(52, 52)
iconLightning:SetPoint("CENTER", 0, 0)

local iconSkyfury = reminder:CreateTexture(nil, "OVERLAY")
iconSkyfury:SetSize(52, 52)
iconSkyfury:SetPoint("CENTER", 0, 0)

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

iconLightning:SetTexture(GetSpellIcon(LIGHTNING_SHIELD_ID, "Lightning Shield"))
iconSkyfury:SetTexture(GetSpellIcon(SKYFURY_ID, SKYFURY_NAME))

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

local function IsElemental()
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == ELEMENTAL_SPEC_ID
end

local function KnowsSkyfury()
    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        local slot = C_SpellBook.FindSpellBookSlotForSpell(SKYFURY_NAME)
        if slot then return true end
    end
    return false
end

local function HasBuffByName(spellName)
    if not spellName then return false end
    for i = 1, 80 do
        local data = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not data then break end

        if data.name == spellName then
            return true
        end
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
    if not IsElemental() then
        Hide()
        return
    end

    if UnitAffectingCombat("player") then
        Hide()
        return
    end

    local missingLightning = not HasBuffByName(LIGHTNING_SHIELD_NAME)
    local missingSkyfury = KnowsSkyfury() and not HasBuffByName(SKYFURY_NAME)

    iconLightning:Hide()
    iconSkyfury:Hide()

    if missingLightning and missingSkyfury then
        iconLightning:ClearAllPoints()
        iconLightning:SetPoint("CENTER", -30, 0)
        iconSkyfury:ClearAllPoints()
        iconSkyfury:SetPoint("CENTER", 30, 0)
        iconLightning:Show()
        iconSkyfury:Show()
    elseif missingLightning then
        iconLightning:ClearAllPoints()
        iconLightning:SetPoint("CENTER", 0, 0)
        iconLightning:Show()
    elseif missingSkyfury then
        iconSkyfury:ClearAllPoints()
        iconSkyfury:SetPoint("CENTER", 0, 0)
        iconSkyfury:Show()
    end

    if not missingLightning and not missingSkyfury then
        Hide()
        return
    end

    Show()
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("PLAYER_REGEN_ENABLED")
tracker:RegisterEvent("PLAYER_REGEN_DISABLED")
tracker:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterEvent("SPELLS_CHANGED")

tracker:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end
    UpdateReminder()
end)
