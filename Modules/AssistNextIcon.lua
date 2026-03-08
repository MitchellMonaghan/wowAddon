-- Single-icon Assisted Combat display.
-- No background, no extra proc icon.
-- Best-effort: attaches to Blizzard assist frame/button when present.

local frame = CreateFrame("Frame", "MyScriptsAssistNextIcon", UIParent)
frame:SetSize(64, 64)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
frame:SetFrameStrata("DIALOG")
frame:SetFrameLevel(500)
frame:Show()

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
icon:SetTexture(134400)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local anchorCandidateNames = {
    -- Requested primary anchor.
    "EssentialCooldownViewer",
    -- Common alternate viewer name seen in some layouts.
    "UtilityCooldownViewer",
    -- Fallback guesses for assisted combat frames.
    "AssistedCombatActionButton",
    "AssistedCombatSingleButton",
    "AssistedCombatFrame",
    "BlizzardAssistedCombatFrame",
}

local attachedAnchor = nil
local inheritedIconSize = 44
local inheritedIconInset = 0
local EXTRA_ICON_INSET = 2

local function IsHealerSpec()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return false end
    local role = GetSpecializationRole and GetSpecializationRole(specIndex)
    return role == "HEALER"
end

local function GetSpellTextureSafe(spellID)
    if not spellID or spellID <= 0 then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

local function GetNextAssistSpellID()
    if C_AssistedCombat and C_AssistedCombat.GetNextCastSpell then
        local spellID = C_AssistedCombat.GetNextCastSpell(false)
        if spellID and spellID > 0 then
            return spellID
        end
    end
    return nil
end

local function FindAssistAnchor()
    for _, name in ipairs(anchorCandidateNames) do
        local obj = _G[name]
        if obj and obj.GetObjectType then
            local objectType = obj:GetObjectType()
            if (objectType == "Button" or objectType == "Frame") and obj.IsShown and obj:IsShown() then
                return obj
            end
        end
    end
    return nil
end

local function GetAnchorIconMetrics(anchor)
    -- Try to inherit icon size from child buttons (shown or hidden).
    -- Outside Edit Mode many children are hidden, but still carry configured size.
    local children = { anchor:GetChildren() }
    for _, child in ipairs(children) do
        if child then
            local w = child.GetWidth and child:GetWidth() or 0
            local h = child.GetHeight and child:GetHeight() or 0
            if w > 0 and h > 0 then
                local s = math.floor(math.min(w, h) + 0.5)
                if s >= 20 and s <= 128 then
                    local inset = 0
                    local childIcon = child.Icon
                    if childIcon and childIcon.GetWidth and childIcon.GetHeight then
                        local iw = childIcon:GetWidth() or 0
                        local ih = childIcon:GetHeight() or 0
                        if iw > 0 and ih > 0 then
                            local iconSize = math.min(iw, ih)
                            inset = math.floor(((s - iconSize) * 0.5) + 0.5)
                            if inset < 0 then inset = 0 end
                            if inset > 8 then inset = 8 end
                        end
                    end
                    return s, inset
                end
            end
        end
    end

    -- Fallback to anchor size if child probing fails.
    local aw = anchor.GetWidth and anchor:GetWidth() or 0
    local ah = anchor.GetHeight and anchor:GetHeight() or 0
    local fallback = math.floor(math.min(aw, ah) + 0.5)
    if fallback >= 20 and fallback <= 128 then
        return fallback, 2
    end
    return nil, nil
end

local function TryAttachToAssistFrame()
    local anchor = FindAssistAnchor()
    if not anchor then return end

    if attachedAnchor ~= anchor then
        attachedAnchor = anchor
        frame:SetParent(anchor)
        frame:SetFrameStrata(anchor:GetFrameStrata() or "DIALOG")
        frame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 2)
        frame:ClearAllPoints()
        -- Attach to the left/front side of the viewer.
        frame:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    end

    -- Continuously sync size so CDM setting changes are reflected.
    local size, inset = GetAnchorIconMetrics(anchor)
    if size then
        inheritedIconSize = size
        inheritedIconInset = inset or 0
    end
    frame:SetSize(inheritedIconSize, inheritedIconSize)
    icon:ClearAllPoints()
    local effectiveInset = inheritedIconInset + EXTRA_ICON_INSET
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", effectiveInset, -effectiveInset)
    icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -effectiveInset, effectiveInset)
end

local function Refresh()
    TryAttachToAssistFrame()

    if IsHealerSpec() then
        frame:Hide()
        return
    end

    if not frame:IsShown() then
        frame:Show()
    end

    local spellID = GetNextAssistSpellID()
    local tex = GetSpellTextureSafe(spellID)
    icon:SetTexture(tex or 134400)
end

local ticker = CreateFrame("Frame")
ticker:RegisterEvent("PLAYER_ENTERING_WORLD")
ticker:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ticker:RegisterEvent("SPELL_UPDATE_USABLE")
ticker:RegisterEvent("SPELLS_CHANGED")
ticker:RegisterEvent("UNIT_AURA")
ticker:RegisterEvent("PLAYER_TARGET_CHANGED")
ticker:RegisterEvent("PLAYER_REGEN_ENABLED")
ticker:RegisterEvent("PLAYER_REGEN_DISABLED")
ticker:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ticker:RegisterEvent("UPDATE_BINDINGS")
ticker:SetScript("OnEvent", function(_, event, ...)
    local unit = ...
    if event == "UNIT_AURA" and unit ~= "player" and unit ~= "target" then
        return
    end
    Refresh()
end)

ticker:SetScript("OnUpdate", function(self, elapsed)
    self._accum = (self._accum or 0) + elapsed
    if self._accum < 0.08 then return end
    self._accum = 0
    Refresh()
end)
