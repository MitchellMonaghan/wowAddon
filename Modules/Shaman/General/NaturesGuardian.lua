local _, ns = ...
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local NG_TALENT_ID = 30884      -- Nature's Guardian Talent
local NG_PROC_ID = 22708        -- The actual heal/proc ID
local CDR_TALENT_ID = 443442    -- Natural Harmony (-15s CD)
local BASE_COOLDOWN = 45
local ICON_SIZE = 40

-- ASSETS
local MASK_PATH   = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_mask.tga]]
local BORDER_PATH = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_border.tga]]
local FONT_PATH   = [[Interface\AddOns\EllesmereUI\media\fonts\Expressway.TTF]]

local nextAvailableAt = 0

-- UI Frame Setup
local frame = CreateFrame("Frame", "EABR_NaturesGuardian", UIParent)
frame:SetSize(ICON_SIZE, ICON_SIZE)
frame:SetFrameStrata("HIGH")

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture(MASK_PATH)
bg:SetVertexColor(0, 0, 0, 1)

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2) 
icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetTexture(C_Spell.GetSpellTexture(NG_TALENT_ID) or 132277)

local mask = frame:CreateMaskTexture()
mask:SetTexture(MASK_PATH, "CLAMPTOBORDER", "CLAMPTOBORDER")
mask:SetAllPoints(icon)
icon:AddMaskTexture(mask)

local border = frame:CreateTexture(nil, "OVERLAY")
border:SetAllPoints(frame)
border:SetTexture(BORDER_PATH)
border:SetVertexColor(0, 0, 0, 1)

local timerText = frame:CreateFontString(nil, "OVERLAY")
timerText:SetFont(FONT_PATH, 20, "OUTLINE") 
timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timerText:SetTextColor(1, 1, 1, 1)
timerText:Hide()

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(icon)
cooldown:SetDrawEdge(false)
cooldown:SetSwipeColor(0, 0, 0, 0.8)
cooldown:SetHideCountdownNumbers(true) 
if cooldown.AddMaskTexture then cooldown:AddMaskTexture(mask) end

local function UpdatePosition()
    local anchor = _G.EABR_ThunderousPaws
    if anchor then
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", anchor, "RIGHT", -5, 0)
    end
end

-- Robust Talent Check
local function CheckTalent()
    if IsPlayerSpell(NG_TALENT_ID) then
        frame:Show()
        UpdatePosition()
    else
        frame:Hide()
        -- Wipe state so a previous CD doesn't "ghost" if you relearn the talent
        nextAvailableAt = 0
        timerText:Hide()
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
        frame:SetScript("OnUpdate", nil)
    end
end

local function StartNGCooldown(triggerSource)
    local now = GetTime()
    if now < nextAvailableAt then return end 

    local cdDuration = IsPlayerSpell(CDR_TALENT_ID) and (BASE_COOLDOWN - 15) or BASE_COOLDOWN

    print(string.format("|cffff9900[NG Tracker]|r Triggered: |cff00ccff%s|r (CD: %ds)", triggerSource, cdDuration))

    nextAvailableAt = now + cdDuration
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    timerText:Show()
    cooldown:SetCooldown(now, cdDuration)
    
    frame:SetScript("OnUpdate", function()
        local timeRemaining = nextAvailableAt - GetTime()
        if timeRemaining > 0 then
            timerText:SetText(math.ceil(timeRemaining))
        else
            frame:SetScript("OnUpdate", nil)
            icon:SetDesaturated(false)
            icon:SetAlpha(1)
            timerText:Hide()
        end
    end)
end

-- TRIGGER 1: Red Border
if LowHealthFrame then
    LowHealthFrame:HookScript("OnShow", function()
        if IsPlayerSpell(NG_TALENT_ID) then 
            StartNGCooldown("LowHealth UI") 
        end
    end)
end

-- Main Driver
local driver = CreateFrame("Frame")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("TRAIT_CONFIG_UPDATED") -- Modern talent change event
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

driver:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = select(2, ...)
        if spellID == NG_PROC_ID and IsPlayerSpell(NG_TALENT_ID) then
            StartNGCooldown("UNIT_SPELLCAST_SUCCEEDED")
        end
    else
        -- Handle spec/talent swap events
        CheckTalent()
        -- Staggered retries for late-loading anchors
        C_Timer.After(0.5, CheckTalent)
        C_Timer.After(2, CheckTalent)
    end
end)