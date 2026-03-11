local _, ns = ...
if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local GHOST_WOLF_SPELL_ID = 2645
local THUNDEROUS_PAWS_TALENT_ID = 378075
local COOLDOWN_SECONDS = 20
local ICON_SIZE = 50

local FONT_PATH   = [[Interface\AddOns\EllesmereUI\media\fonts\Expressway.TTF]]
local MASK_PATH   = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_mask.tga]]
local BORDER_PATH = [[Interface\AddOns\EllesmereUI\media\portraits\csquare_border.tga]]

local cooldownEndsAt = 0

local frame = CreateFrame("Frame", "EABR_ThunderousPaws", UIParent)
frame:SetSize(ICON_SIZE, ICON_SIZE)
frame:SetFrameStrata("HIGH")
frame:Hide()

local icon = frame:CreateTexture(nil, "ARTWORK")

icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetTexture(C_Spell.GetSpellTexture(THUNDEROUS_PAWS_TALENT_ID) or 134400)

local mask = frame:CreateMaskTexture()
mask:SetTexture(MASK_PATH, "CLAMPTOBORDER", "CLAMPTOBORDER")
mask:SetAllPoints(icon)
icon:AddMaskTexture(mask)

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(icon)
cooldown:SetSwipeColor(0, 0, 0, 0.7)
cooldown:SetDrawEdge(false)
cooldown:SetHideCountdownNumbers(true)

if cooldown.SetSwipeTexture then
    cooldown:SetSwipeTexture(MASK_PATH) 
end
if cooldown.SetUseCircularEdge then
    cooldown:SetUseCircularEdge(true)   
end

local border = frame:CreateTexture(nil, "OVERLAY", nil, 7)
border:SetAllPoints(frame)
border:SetTexture(BORDER_PATH)
border:SetVertexColor(0, 0, 0, 1)

local timerText = frame:CreateFontString(nil, "OVERLAY", nil, 7)

timerText:SetFont(FONT_PATH, 14, "OUTLINE") 
timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timerText:SetTextColor(1, 1, 1, 1)


local function StartCD()
    local start = GetTime()
    cooldownEndsAt = start + COOLDOWN_SECONDS
    frame:Show()
    cooldown:SetCooldown(start, COOLDOWN_SECONDS)
    
    frame:SetScript("OnUpdate", function()
        local rem = cooldownEndsAt - GetTime()
        if rem > 0 then
            timerText:SetText(math.ceil(rem))
        else
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
        end
    end)
end

local function UpdatePos()
    local anchor = _G.ECME_CDMBar_buffs
    if anchor then
        frame:ClearAllPoints()
        frame:SetPoint("LEFT", anchor, "RIGHT", -5, 0)
    end
end

local driver = CreateFrame("Frame")
driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")

driver:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellID == GHOST_WOLF_SPELL_ID and IsPlayerSpell(THUNDEROUS_PAWS_TALENT_ID) and GetTime() >= cooldownEndsAt then
            StartCD()
        end
    else
        UpdatePos()
    end
end)