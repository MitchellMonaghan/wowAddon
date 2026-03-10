local _, ns = ...

if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local THUNDEROUS_PAWS_ID = 378075
local THUNDEROUS_PAWS_NAME = "Thunderous Paws"
local COOLDOWN_SECONDS = 20

local thunderousPawsID = nil
local buffWasActive = false
local cooldownEndsAt = 0

local frame = CreateFrame("Frame", nil, UIParent)
frame:SetSize(40, 40)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
frame:SetFrameStrata("HIGH")

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.65)

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 2, -2)
icon:SetPoint("BOTTOMRIGHT", -2, 2)

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(icon)
cooldown:SetDrawEdge(false)
cooldown:SetSwipeColor(0, 0, 0, 0.8)
cooldown:SetHideCountdownNumbers(false)

local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
border:SetPoint("TOPLEFT", -1, 1)
border:SetPoint("BOTTOMRIGHT", 1, -1)
border:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})
border:SetBackdropBorderColor(0.08, 0.08, 0.08, 1)

local function ResolveThunderousPawsID()
    thunderousPawsID = THUNDEROUS_PAWS_ID
end

local function GetSpellTextureSafe(spellID, fallbackName)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then
            return tex
        end
    end

    if GetSpellInfo then
        local _, _, tex = GetSpellInfo(spellID or fallbackName)
        if tex then
            return tex
        end
    end

    return 134400
end

local function IsKnown()
    ResolveThunderousPawsID()

    if thunderousPawsID and IsPlayerSpell and IsPlayerSpell(thunderousPawsID) then
        return true
    end

    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        local slot = C_SpellBook.FindSpellBookSlotForSpell(thunderousPawsID or THUNDEROUS_PAWS_NAME)
        if slot then
            return true
        end
    end

    return false
end

local function GetBuffData()
    ResolveThunderousPawsID()

    if thunderousPawsID and AuraUtil and AuraUtil.FindAuraBySpellID then
        local aura = AuraUtil.FindAuraBySpellID(thunderousPawsID, "player", "HELPFUL")
        if aura then
            return aura
        end
    end

    if thunderousPawsID and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        local aura = C_UnitAuras.GetAuraDataBySpellID("player", thunderousPawsID)
        if aura then
            return aura
        end
    end

    if thunderousPawsID and C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID and C_UnitAuras.GetAuraDataBySpellID then
        local ok, mappedAuraID = pcall(C_UnitAuras.GetCooldownAuraBySpellID, thunderousPawsID)
        if ok and mappedAuraID then
            local aura = C_UnitAuras.GetAuraDataBySpellID("player", mappedAuraID)
            if aura then
                return aura
            end
        end
    end

    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for i = 1, 80 do
            local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
            if not aura then
                break
            end

            if aura.name == THUNDEROUS_PAWS_NAME then
                return aura
            end
        end
    end

    return nil
end

local function StartCooldown(startTime)
    cooldownEndsAt = startTime + COOLDOWN_SECONDS
    icon:SetDesaturated(true)
    icon:SetAlpha(0.45)
    bg:SetAlpha(0.9)
    cooldown:SetCooldown(startTime, COOLDOWN_SECONDS)
    frame:SetScript("OnUpdate", function()
        if GetTime() >= cooldownEndsAt then
            cooldownEndsAt = 0
            frame:SetScript("OnUpdate", nil)
            cooldown:Clear()
            icon:SetDesaturated(false)
            icon:SetAlpha(1)
            bg:SetAlpha(0.65)
        end
    end)
end

local function UpdateTracker()
    frame:Show()

    if not IsKnown() then
        cooldown:Clear()
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
        bg:SetAlpha(0.65)
        return
    end

    local aura = GetBuffData()
    local buffIsActive = aura ~= nil

    if buffIsActive and not buffWasActive then
        local startTime = GetTime()
        if aura.expirationTime and aura.duration and aura.duration > 0 then
            startTime = aura.expirationTime - aura.duration
        end
        StartCooldown(startTime)
    end

    buffWasActive = buffIsActive

    if cooldownEndsAt > 0 and GetTime() < cooldownEndsAt then
        frame:Show()
        return
    end

    frame:Show()
    cooldown:Clear()
    icon:SetDesaturated(false)
    icon:SetAlpha(1)
    bg:SetAlpha(0.65)
end

ResolveThunderousPawsID()
icon:SetTexture(GetSpellTextureSafe(thunderousPawsID, THUNDEROUS_PAWS_NAME))
frame:Show()

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("UNIT_AURA")

driver:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end

    ResolveThunderousPawsID()
    icon:SetTexture(GetSpellTextureSafe(thunderousPawsID, THUNDEROUS_PAWS_NAME))
    UpdateTracker()
end)
