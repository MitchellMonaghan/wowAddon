if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local RESTO_SPEC_ID = 264
local EARTH_SHIELD_ID = 974
local EARTH_SHIELD_NAME = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(EARTH_SHIELD_ID)) or "Earth Shield"

local reminder = CreateFrame("Frame", "MyScriptsEarthShieldTankReminder", UIParent)
reminder:SetSize(48, 48)
reminder:SetPoint("TOP", UIParent, "TOP", 0, -300)
reminder:SetFrameStrata("HIGH")
reminder:Hide()

local icon = reminder:CreateTexture(nil, "OVERLAY")
icon:SetAllPoints()
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(EARTH_SHIELD_ID)) or 136089)

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

local function IsResto()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
    return specID == RESTO_SPEC_ID
end

local function UnitHasEarthShield(unit)
    if not unit then return false end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        if AuraUtil.FindAuraBySpellID(EARTH_SHIELD_ID, unit, "HELPFUL") then
            return true
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellID then
        if C_UnitAuras.GetAuraDataBySpellID(unit, EARTH_SHIELD_ID) then
            return true
        end
    end

    if C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID and C_UnitAuras.GetAuraDataBySpellID then
        local ok, mappedAuraID = pcall(C_UnitAuras.GetCooldownAuraBySpellID, EARTH_SHIELD_ID)
        if ok and mappedAuraID and C_UnitAuras.GetAuraDataBySpellID(unit, mappedAuraID) then
            return true
        end
    end

    if AuraUtil and AuraUtil.FindAuraByName and EARTH_SHIELD_NAME then
        if AuraUtil.FindAuraByName(EARTH_SHIELD_NAME, unit, "HELPFUL") then
            return true
        end
    end

    return false
end

local function AnyTankHasEarthShield()
    local foundTank = false

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "TANK" then
                foundTank = true
                if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitHasEarthShield(unit) then
                    return true, true
                end
            end
        end
        return false, foundTank
    end

    if IsInGroup and IsInGroup() then
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "TANK" then
                foundTank = true
                if UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and UnitHasEarthShield(unit) then
                    return true, true
                end
            end
        end
        return false, foundTank
    end

    return false, false
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
    if not IsResto() then
        Hide()
        return
    end

    if not (IsInGroup and IsInGroup()) then
        Hide()
        return
    end

    local hasShield, foundTank = AnyTankHasEarthShield()
    if not foundTank then
        Hide()
        return
    end

    if hasShield then
        Hide()
    else
        Show()
    end
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("GROUP_ROSTER_UPDATE")
tracker:RegisterEvent("PLAYER_ROLES_ASSIGNED")
tracker:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("SPELLS_CHANGED")

tracker:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if unit ~= "player" and unit ~= "target" and unit ~= "focus" and not string.find(unit or "", "party", 1, true) and not string.find(unit or "", "raid", 1, true) then
            return
        end
    end
    UpdateReminder()
end)

UpdateReminder()
