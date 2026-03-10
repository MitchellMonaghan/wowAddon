local _, ns = ...
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local GHOST_WOLF_SPELL_ID = 2645
local THUNDEROUS_PAWS_TALENT_ID = 378075
local COOLDOWN_SECONDS = 20
local ICON_SIZE = 40 

-- ASSETS
local MASK_PATH   = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_mask.tga]]
local BORDER_PATH = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_border.tga]]
local FONT_PATH   = [[Interface\AddOns\EllesmereUI\media\fonts\Expressway.TTF]]

local cooldownEndsAt = 0

-- UI Frame Setup
local frame = CreateFrame("Frame", "EABR_ThunderousPaws", UIParent)
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

-- Midnight-safe texture fetch
local pawsTex = C_Spell.GetSpellTexture(THUNDEROUS_PAWS_TALENT_ID)
icon:SetTexture(pawsTex or 134400)

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
    local anchor = _G.ECME_CDMBar_buffs
    if anchor then
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", anchor, "RIGHT", -5, 0) 
        frame:SetSize(ICON_SIZE, ICON_SIZE)
    end
end

-- FIXED TALENT CHECK: Using IsPlayerSpell for 12.0/Midnight compatibility
local function CheckTalent()
    -- Global IsPlayerSpell is the standard for checking learned talents
    local isKnown = IsPlayerSpell(THUNDEROUS_PAWS_TALENT_ID)
    
    if isKnown then
        frame:Show()
        UpdatePosition()
    else
        frame:Hide()
        cooldownEndsAt = 0
        timerText:Hide()
        icon:SetDesaturated(false)
        icon:SetAlpha(1)
    end
end

local function StartInternalCD()
    local startTime = GetTime()
    cooldownEndsAt = startTime + COOLDOWN_SECONDS
    
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    timerText:Show()
    cooldown:SetCooldown(startTime, COOLDOWN_SECONDS)
    
    frame:SetScript("OnUpdate", function()
        local now = GetTime()
        local remaining = cooldownEndsAt - now
        
        if remaining > 0 then
            timerText:SetText(math.ceil(remaining))
        else
            cooldownEndsAt = 0
            frame:SetScript("OnUpdate", nil)
            icon:SetDesaturated(false)
            icon:SetAlpha(1)
            timerText:Hide()
        end
    end)
end

-- Main Driver
local driver = CreateFrame("Frame")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("TRAIT_CONFIG_UPDATED")

driver:SetScript("OnEvent", function(self, event, unit, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = select(2, ...)
        if spellID == GHOST_WOLF_SPELL_ID then
            if GetTime() >= cooldownEndsAt and IsPlayerSpell(THUNDEROUS_PAWS_TALENT_ID) then
                StartInternalCD()
            end
        end
    else
        CheckTalent()
        -- Staggered retries for the CDM anchor
        C_Timer.After(0.5, CheckTalent)
        C_Timer.After(2, CheckTalent)
    end
end)